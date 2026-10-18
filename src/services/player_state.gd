extends Node
## Состояние героя: характеристики, шкалы, жизни и смерти. Связывает правила (src/core) со сценой
## и логом. Показ смерти и возрождения — src/world/death_flow.gd.

signal inventory_changed

var stats: StatBlock
var vitals: Vitals
var inventory: Inventory
var run := RunStats.new()
var trophies: TrophyRules
var buffs := Buffs.new()
var weapons: WeaponState
var wounds: Wounds
var combat: DamageModel
## Свободные очки характеристик (золотая звезда). Распределение — в окне героя (позже).
var free_points: int = 0
## Сколько раз Система дала умение (жемчуг). Сами умения — задача 13.
var skills_awakened: int = 0
var lives: int = 0
var deaths: int = 0
## Что осталось на трупе последней смерти: {"backpack": [...]}. Забирает DeathFlow.
var dropped_on_death: Dictionary = {}
## Смертей с прошлой смены региона (D-03). Сама смена — в M3, пока только лог.
var deaths_since_region_shift: int = 0
## Герой мёртв и ждёт возрождения (экран «Жизнь N закончилась» или итоги).
var awaiting_respawn: bool = false
var respawn_position := Vector3(0, 0.1, 0)
## Игровое время начала игры — для «самой долгой жизни» в итогах.
var start_minutes: float = 0.0
var _rng := RandomNumberGenerator.new()
var _was_overloaded := false
## Кто последним ранил героя — причина смерти, если здоровье кончится.
var _last_damage_source := "health"


func _ready() -> void:
	setup()


## Новый герой из данных Content. Отдельно от _ready — чтобы тесты собирали состояние так же.
func setup() -> void:
	stats = StatBlock.new(Content.stats_config())
	lives = int(Content.rules()["lives_start"])
	stats.stat_level_changed.connect(_on_stat_level_changed)
	vitals = Vitals.new(Content.vitals_config(), stats.get_level("endurance"), stats.get_level("mental"))
	vitals.depleted.connect(_on_vital_depleted)
	vitals.spore_state_changed.connect(_on_spore_state_changed)
	inventory = Inventory.new(Content.item_db(), Content.inventory_config(), stats.get_level("strength"))
	trophies = TrophyRules.new(Content.item_db())
	weapons = WeaponState.new(Content.weapon_db())
	combat = DamageModel.new(Content.combat_config())
	wounds = Wounds.new(Content.combat_config()["bleeding"])
	start_minutes = GameClock.minutes


func add_progress(stat: String, points: float) -> void:
	stats.add_progress(stat, points)


## Смерть: −1 жизнь, штраф прогресса, запись в статистику, счётчик смены региона.
## Дальше герой ждёт возрождения (respawn) — экран и таймер ведёт DeathFlow.
func die(cause: String) -> void:
	if awaiting_respawn or lives <= 0:
		return
	var life_number := deaths + 1
	deaths += 1
	lives -= 1
	deaths_since_region_shift += 1
	stats.apply_death_penalty(_rng)
	dropped_on_death = {"backpack": inventory.take_backpack()}
	wounds.stop_bleeding()
	_after_inventory_change()
	run.record_death(life_number, cause, GameClock.minutes, stats.general_level())
	SystemLog.post("death", {"life": life_number, "lives": lives, "cause": Content.death_cause(cause)}, "death")
	var per_shift := int(Content.rules()["deaths_per_region_shift"])
	if lives > 0 and DeathRules.region_shift_due(deaths_since_region_shift, per_shift):
		deaths_since_region_shift = 0
		SystemLog.post("region_shift", {"deaths": per_shift}, "special")
	if lives == 0:
		SystemLog.post("death_final", {}, "death")
	awaiting_respawn = true
	EventBus.player_died.emit(cause, lives)


func _process(delta: float) -> void:
	for buff in buffs.expire(GameClock.minutes):
		SystemLog.post("buff_ended", {"stat": Content.stat_name(buff["stat"])})
	if wounds and wounds.is_bleeding() and not awaiting_respawn:
		var loss := wounds.tick(delta)
		_last_damage_source = "bleeding"
		vitals.damage(loss)
		if not wounds.is_bleeding():
			SystemLog.post("bleeding_stopped")


## Итоговое значение характеристики с учётом баффов.
func effective(stat: String) -> float:
	return stats.effective_value(stat) * buffs.multiplier(stat, GameClock.minutes)


## Приём трофея или расходника. Результат:
##   "ok" — принят; "needs_confirm" — интервал не соблюдён, нужно подтверждение (confirmed=true);
##   "missing" — нет предмета или того, что нужно для приёма (уксус); "not_consumable".
func consume(id: String, confirmed: bool = false) -> String:
	if not trophies.can_consume(id):
		return "not_consumable"
	if inventory.count_of(id) < 1:
		return "missing"
	var missing := trophies.missing_requirements(id, inventory)
	if not missing.is_empty():
		var need: String = missing.keys()[0]
		SystemLog.post("consume_missing", {"item": Content.item_name(id), "need": Content.item_name(need)}, "warning")
		return "missing"
	if trophies.is_violation(id, GameClock.minutes) and not confirmed:
		return "needs_confirm"
	inventory.remove(id, 1)
	var requires: Dictionary = trophies.spec(id).get("requires", {})
	for need: String in requires:
		inventory.remove(need, int(requires[need]))
	var result := trophies.resolve(id, GameClock.minutes, _rng, {
		"skill_count": skills_awakened, "main_stats": stats.main_stats(),
		"additional_stats": stats.additional_stats(), "vitals": Array(Vitals.ALL),
	})
	_apply_consume(result)
	_after_inventory_change()
	return "ok"


## Крафт по рецепту из data/recipes.json. Невлезшее падает под ноги (через сигнал в сцену).
func craft(recipe: Dictionary) -> bool:
	var result := Crafting.craft(recipe, inventory)
	if not result["ok"]:
		return false
	var outputs: Dictionary = recipe["outputs"]
	for id: String in outputs:
		SystemLog.post("crafted", {"item": Content.item_name(id), "count": int(outputs[id])})
	var left: Dictionary = result["left"]
	for id: String in left:
		EventBus.items_dropped.emit(id, int(left[id]))
	_after_inventory_change()
	return true


func _apply_consume(result: Dictionary) -> void:
	var item_name := Content.item_name(result["id"])
	SystemLog.post("consumed_" + String(trophies.spec(result["id"]).get("verb", "swallow")), {"item": item_name})
	if result["violation"]:
		SystemLog.post("cooldown_violated", {"item": item_name}, "warning")
	for effect: Dictionary in result["effects"]:
		match String(effect["type"]):
			"stat_add":
				stats.add_levels(effect["stat"], effect["value"])
			"stat_buff":
				buffs.add(effect["stat"], effect["mult"], GameClock.minutes + float(effect["hours"]) * 60.0, result["id"])
				SystemLog.post("buff_started", {
					"stat": Content.stat_name(effect["stat"]), "percent": roundi(float(effect["mult"]) * 100.0),
					"hours": roundi(float(effect["hours"]))}, "progress")
			"vital_max_add":
				vitals.add_max_bonus(effect["vital"], effect["value"])
				SystemLog.post("vital_max_up", {"vital": Content.ui("vital_" + String(effect["vital"])), "value": effect["value"]}, "progress")
			"vital_restore":
				vitals.restore(effect["vital"], effect["value"])
			"stop_bleeding":
				if wounds.is_bleeding():
					wounds.stop_bleeding()
					SystemLog.post("bleeding_stopped")
			"free_points":
				free_points += int(effect["value"])
				SystemLog.post("free_points", {"value": effect["value"], "total": free_points}, "progress")
			"skill_chance":
				if effect["success"]:
					skills_awakened += 1
					run.add("skills_awakened")
					SystemLog.post("skill_awakened", {}, "special")
	for risk in result["risks"]:
		run.add("risk_" + risk)
		SystemLog.post("risk_" + risk, {}, "special")


## Урон герою от твари и т. п. source — id твари или причины (для экрана смерти).
## bleed_chance — шанс открыть кровотечение (у тварей — attack.bleed_chance).
func hurt(amount: float, source: String, bleed_chance: float = 0.0) -> void:
	if awaiting_respawn:
		return
	_last_damage_source = source
	EventBus.player_hurt.emit(amount, source)
	if bleed_chance > 0.0 and _rng.randf() < bleed_chance:
		var was_bleeding := wounds.is_bleeding()
		wounds.add_bleeding()
		if not was_bleeding:
			SystemLog.post("bleeding_started", {}, "warning")
	vitals.damage(amount)


## Перезарядить оружие в руках из инвентаря. Возвращает, сколько патронов вошло.
func reload_weapon() -> int:
	var loaded := weapons.reload(weapons.equipped, inventory)
	if loaded > 0:
		_after_inventory_change()
	return loaded


func cycle_weapon() -> String:
	return equip_weapon(weapons.cycle(inventory))


func equip_weapon(id: String) -> String:
	if id != WeaponDB.FISTS and inventory.count_of(id) < 1:
		return weapons.equipped
	weapons.equipped = id
	SystemLog.post("weapon_equipped", {"weapon": Content.item_name(id)})
	# Лук и подобное без времени перезарядки — сразу наложить стрелу.
	var weapon := Content.weapon_db().weapon(id)
	if weapon["kind"] == "ranged" and float(weapon["reload"]) <= 0.0:
		reload_weapon()
	return id


## Подбор предмета: в ячейки, если можно, иначе в рюкзак. Возвращает, сколько не влезло.
func pick_up(id: String, count: int) -> int:
	var result := inventory.add(id, count)
	var params := {"item": Content.item_name(id), "strength": stats.get_level("strength")}
	if result["primary"] > 0:
		SystemLog.post("item_picked_primary", params.merged({"count": result["primary"]}))
	if result["backpack"] > 0:
		SystemLog.post("item_picked", params.merged({"count": result["backpack"]}))
	if result["left"] > 0:
		SystemLog.post("too_heavy", params, "warning")
	_after_inventory_change()
	return result["left"]


## Сообщить интерфейсу и проверить перегруз (лог — при переходе в перегруз).
func _after_inventory_change() -> void:
	weapons.drop_if_missing(inventory)
	var overloaded := inventory.is_overloaded()
	if overloaded and not _was_overloaded:
		SystemLog.post("overloaded", {}, "warning")
	_was_overloaded = overloaded
	inventory_changed.emit()


func notify_inventory_changed() -> void:
	_after_inventory_change()


## Конец ожидания: герой встаёт на респе с восстановленными шкалами.
func respawn() -> void:
	if not awaiting_respawn:
		return
	awaiting_respawn = false
	vitals.restore_after_death()
	SystemLog.post("respawned", {"life": deaths + 1})
	EventBus.player_respawned.emit()


## Заглушка D-34: после итогов тот же герой получает стартовые жизни. Как продолжать — решаем в M1.
func continue_after_final() -> void:
	lives = int(Content.rules()["lives_start"])
	SystemLog.post("continue_stub", {"lives": lives}, "special")


func to_dict() -> Dictionary:
	return {
		"stats": stats.to_dict(), "vitals": vitals.to_dict(), "run": run.to_dict(),
		"inventory": inventory.to_dict(), "trophies": trophies.to_dict(), "buffs": buffs.to_dict(),
		"free_points": free_points, "skills_awakened": skills_awakened,
		"weapons": weapons.to_dict(), "wounds": wounds.to_dict(),
		"lives": lives, "deaths": deaths, "deaths_since_region_shift": deaths_since_region_shift,
		"awaiting_respawn": awaiting_respawn, "start_minutes": start_minutes,
		"respawn_position": [respawn_position.x, respawn_position.y, respawn_position.z],
	}


func load_dict(data: Dictionary) -> void:
	stats.load_dict(data["stats"])
	vitals.set_stat_levels(stats.get_level("endurance"), stats.get_level("mental"))
	vitals.load_dict(data["vitals"])
	run.load_dict(data["run"])
	inventory.strength_level = stats.get_level("strength")
	inventory.load_dict(data["inventory"])
	trophies.load_dict(data["trophies"])
	buffs.load_dict(data["buffs"])
	free_points = int(data["free_points"])
	skills_awakened = int(data["skills_awakened"])
	weapons.load_dict(data["weapons"])
	wounds.load_dict(data["wounds"])
	_was_overloaded = inventory.is_overloaded()
	inventory_changed.emit()
	lives = int(data["lives"])
	deaths = int(data["deaths"])
	deaths_since_region_shift = int(data["deaths_since_region_shift"])
	awaiting_respawn = bool(data["awaiting_respawn"])
	start_minutes = float(data["start_minutes"])
	var at: Array = data["respawn_position"]
	respawn_position = Vector3(float(at[0]), float(at[1]), float(at[2]))


func _on_vital_depleted(vital: String) -> void:
	if vital == Vitals.STAMINA:
		SystemLog.post("stamina_out", {}, "warning")
	elif vital == Vitals.SPORE:
		die("spore_balance")
	elif vital == Vitals.HEALTH:
		die(_last_damage_source)


func _on_spore_state_changed(state: String) -> void:
	SystemLog.post("spore_" + state, {}, "info" if state == "ok" else "warning")


func _on_stat_level_changed(stat: String, old_level: int, new_level: int) -> void:
	if vitals and (stat == "endurance" or stat == "mental"):
		vitals.set_stat_levels(stats.get_level("endurance"), stats.get_level("mental"))
	if inventory and stat == "strength":
		inventory.strength_level = new_level
	var params := {"stat": Content.stat_name(stat), "level": new_level}
	if new_level < old_level:
		SystemLog.post("stat_level_lost", params, "warning")
		return
	var special_key := "stat_level_up_" + stat
	SystemLog.post(special_key if SystemLog.has_key(special_key) else "stat_level_up", params, "progress")
