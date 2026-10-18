extends Node
## Состояние героя: характеристики, шкалы, жизни и смерти. Связывает правила (src/core) со сценой
## и логом. Показ смерти и возрождения — src/world/death_flow.gd.

signal inventory_changed
## Умения изменились: выучено, слот, свойство, применено (окно умений и HUD перерисовываются).
signal skills_changed

var stats: StatBlock
var vitals: Vitals
var inventory: Inventory
var run := RunStats.new()
var trophies: TrophyRules
var buffs := Buffs.new()
var weapons: WeaponState
var wounds: Wounds
var combat: DamageModel
var progress: ProgressRules
## Умения (задача 13): изученные, слоты, откаты. Правила — src/core/skill_rules.gd.
var skills: SkillRules
## Варианты дара, который сейчас ждёт выбора (бросаются один раз, переживают сейв).
var skill_offers: PackedStringArray = []
## Свободные очки характеристик (золотая звезда). Распределение — в окне героя (позже).
var free_points: int = 0
## Сколько раз Система дала умение (жемчуг).
var skills_awakened: int = 0
## Дары уровней, «вскрытые» у знахарки (10, 30, 60), и сколько из них ждут выбора умения
## (последние pending_skill_choices в skill_gifts_opened).
var skill_gifts_opened: Array[int] = []
var pending_skill_choices: int = 0
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
## Номер цикла «Новой игры+» (0 — первая игра).
var ng_plus: int = 0
## Режим сохранений партии (D-30): "anywhere" / "stab_only". Умолчание для новой игры — в настройках.
var save_mode: String = SettingsModel.ANYWHERE
var _rng := RandomNumberGenerator.new()
var _was_overloaded := false
## Кто последним ранил героя — причина смерти, если здоровье кончится.
var _last_damage_source := "health"
## Игровой час, в котором уже предупредили об однообразии: {"melee_hit": 12}.
var _farm_warned: Dictionary = {}
## Когда последний раз писали в лог о каждом виде удачи (реальные мс) — не спамить.
var _luck_logged: Dictionary = {}
## Умения с долгим откатом, о готовности которых сообщить: {id: true}.
var _waiting_ready: Dictionary = {}


func _ready() -> void:
	setup()


## Новый герой из данных Content: всё состояние с нуля. Отдельно от _ready — чтобы тесты
## собирали состояние так же и чтобы «Новая игра» сбрасывала героя (SaveService.start_new_game).
func setup() -> void:
	run = RunStats.new()
	buffs = Buffs.new()
	free_points = 0
	skills_awakened = 0
	skill_gifts_opened = []
	pending_skill_choices = 0
	deaths = 0
	dropped_on_death = {}
	deaths_since_region_shift = 0
	awaiting_respawn = false
	respawn_position = Vector3(0, 0.1, 0)
	ng_plus = 0
	save_mode = String(Settings.value("save_mode"))
	_was_overloaded = false
	_last_damage_source = "health"
	_farm_warned = {}
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
	progress = ProgressRules.new(Content.progress_config())
	skills = SkillRules.new(Content.skill_rules_config(), Content.skill_defs(),
		GameClock.MINUTES_PER_DAY / float(Content.rules()["real_seconds_per_game_day"]))
	skill_offers = []
	_luck_logged = {}
	_waiting_ready = {}
	start_minutes = GameClock.minutes


func add_progress(stat: String, points: float) -> void:
	stats.add_progress(stat, points)


## Прокачка действием (3.2): очки по data/progress.json с убывающей отдачей и уровнем цели.
## context: {"target_level": int} — уровень твари, если действие против неё.
func award(action: String, amount: float = 1.0, context: Dictionary = {}) -> void:
	if awaiting_respawn:
		return
	var ctx := context.duplicate()
	if ctx.has("target_level"):
		ctx["hero_level"] = stats.general_level()
	var result := progress.award(action, amount, GameClock.minutes, ctx)
	stats.add_progress(result["stat"], result["points"])
	var below := float(Content.progress_config()["farm_warning_below"])
	if progress.farm_multiplier(action) < below and _farm_warned.get(action, -1) != progress.hour:
		_farm_warned[action] = progress.hour
		SystemLog.post("farm_warning", {"stat": Content.stat_name(result["stat"])}, "warning")


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
	if not skills.cooldowns.is_empty():
		SystemLog.post("skill_cooldowns_reset")
	skills.reset_cooldowns()
	_waiting_ready.clear()
	skills_changed.emit()
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
		if not String(buff["source"]).begins_with("skill:"):
			SystemLog.post("buff_ended", {"stat": Content.stat_name(buff["stat"])})
	_skills_tick()
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
					_pearl_skill()
	for risk in result["risks"]:
		run.add("risk_" + risk)
		SystemLog.post("risk_" + risk, {}, "special")


## Урон герою от твари и т. п. source — id твари или причины (для экрана смерти).
## bleed_chance — шанс открыть кровотечение (у тварей — attack.bleed_chance).
func hurt(amount: float, source: String, bleed_chance: float = 0.0) -> void:
	if awaiting_respawn:
		return
	if skills.has_status("immunity", GameClock.minutes):
		EventBus.luck_event.emit("immunity", Vector3.INF)
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


## «Дальше» после итогов (D-34): тот же герой в том же мире, жизни снова стартовые.
## Сменить режим сохранений посреди игры (D-30): можно в любую сторону, итоги это запомнят.
func change_save_mode(mode: String) -> void:
	if mode == save_mode:
		return
	save_mode = mode
	run.add("save_mode_changes")
	SystemLog.post("save_mode_changed", {"mode": Content.ui("save_mode_" + mode)}, "warning")


func continue_after_final() -> void:
	lives = int(Content.rules()["lives_start"])
	run.add("continues")
	SystemLog.post("continue_after_final", {"lives": lives}, "special")


## Что «Новая игра+» переносит в новый мир (D-34, D-52): ячейки Системы, номер цикла и умения
## (со свойствами и слотами, без откатов).
func ng_plus_carry() -> Dictionary:
	var known := skills.to_dict()
	return {"ng_plus": ng_plus + 1, "primary": inventory.to_dict()["primary"], "save_mode": save_mode,
		"skills": {"learned": known["learned"], "slots": known["slots"]}}


## Применить перенос к только что созданному герою: ячейки, коэффициенты × (1 + бонус × цикл).
func apply_carry(carry: Dictionary) -> void:
	ng_plus = int(carry.get("ng_plus", 0))
	save_mode = String(carry.get("save_mode", save_mode))
	if carry.has("primary"):
		inventory.load_dict({"primary": carry["primary"], "backpack": []})
	if carry.has("skills"):
		skills.load_dict(carry["skills"])
		_update_mana_reserve()
		skills_changed.emit()
	var bonus := float(Content.rules()["ng_plus"]["coefficient_bonus"]) * ng_plus
	for stat in stats.all_stats():
		stats.set_coefficient(stat, stats.get_coefficient(stat) * (1.0 + bonus))
	inventory_changed.emit()


func to_dict() -> Dictionary:
	return {
		"stats": stats.to_dict(), "vitals": vitals.to_dict(), "run": run.to_dict(),
		"inventory": inventory.to_dict(), "trophies": trophies.to_dict(), "buffs": buffs.to_dict(),
		"free_points": free_points, "skills_awakened": skills_awakened,
		"skill_gifts_opened": skill_gifts_opened.duplicate(), "pending_skill_choices": pending_skill_choices,
		"weapons": weapons.to_dict(), "wounds": wounds.to_dict(), "progress": progress.to_dict(),
		"skills": skills.to_dict(), "skill_offers": Array(skill_offers),
		"lives": lives, "deaths": deaths, "deaths_since_region_shift": deaths_since_region_shift,
		"awaiting_respawn": awaiting_respawn, "start_minutes": start_minutes, "ng_plus": ng_plus, "save_mode": save_mode,
		"respawn_position": [respawn_position.x, respawn_position.y, respawn_position.z],
	}


func load_dict(data: Dictionary) -> void:
	stats.load_dict(data["stats"])
	skills.load_dict(data["skills"])
	skill_offers = PackedStringArray(data["skill_offers"])
	_waiting_ready.clear()
	_update_mana_reserve()
	vitals.set_stat_levels(stats.get_level("endurance"), stats.get_level("mental"))
	vitals.load_dict(data["vitals"])
	run.load_dict(data["run"])
	inventory.strength_level = stats.get_level("strength")
	inventory.load_dict(data["inventory"])
	trophies.load_dict(data["trophies"])
	buffs.load_dict(data["buffs"])
	free_points = int(data["free_points"])
	skills_awakened = int(data["skills_awakened"])
	skill_gifts_opened.clear()
	for level in data["skill_gifts_opened"]:
		skill_gifts_opened.append(int(level))
	pending_skill_choices = int(data["pending_skill_choices"])
	weapons.load_dict(data["weapons"])
	wounds.load_dict(data["wounds"])
	progress.load_dict(data["progress"])
	_was_overloaded = inventory.is_overloaded()
	inventory_changed.emit()
	lives = int(data["lives"])
	deaths = int(data["deaths"])
	deaths_since_region_shift = int(data["deaths_since_region_shift"])
	awaiting_respawn = bool(data["awaiting_respawn"])
	start_minutes = float(data["start_minutes"])
	ng_plus = int(data["ng_plus"])
	save_mode = String(data["save_mode"])
	var at: Array = data["respawn_position"]
	respawn_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	skills_changed.emit()


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
	if skills:
		_on_skill_levels_changed(stat, old_level, new_level)
	var params := {"stat": Content.stat_name(stat), "level": new_level}
	if new_level < old_level:
		SystemLog.post("stat_level_lost", params, "warning")
		return
	var special_key := "stat_level_up_" + stat
	SystemLog.post(special_key if SystemLog.has_key(special_key) else "stat_level_up", params, "progress")


# --- Умения (задача 13, docs/spec/05_skills.md) ---------------------------------------------------

## Уровни характеристик, от которых зависят умения (рост, пороги свойств, слоты).
func skill_levels() -> Dictionary:
	return {
		"mental": stats.get_level("mental"), "talent_facets": stats.get_level("talent_facets"),
		"general": stats.general_level(), "luck": stats.get_level("luck"),
	}


func learn_skill(id: String, log_key: String = "skill_learned") -> bool:
	if not skills.learn(id, stats.general_level()):
		return false
	SystemLog.post(log_key, {"skill": Content.skill_name(id)}, "special")
	_update_mana_reserve()
	skills_changed.emit()
	return true


## Применить умение из слота index (клавиши 1–4). Возвращает результат SkillRules.can_use.
func use_skill_slot(index: int) -> String:
	if index < 0 or index >= skills.slot_count(stats.general_level()) or skills.slots[index].is_empty():
		return "empty"
	return use_skill(skills.slots[index])


func use_skill(id: String) -> String:
	if awaiting_respawn:
		return "dead"
	var levels := skill_levels()
	var used := skills.use(id, GameClock.minutes, vitals.value(Vitals.MANA), levels)
	var name := Content.skill_name(id)
	match String(used["result"]):
		"ok":
			vitals.spend_mana(float(used["mana"]))
			_apply_skill_effects(id, used["effects"])
			if skills.cooldown_s(id, levels) >= 3600.0:
				_waiting_ready[id] = true
			skills_changed.emit()
		"mana":
			SystemLog.post("skill_no_mana", {"skill": name, "cost": roundi(skills.mana_cost(id, levels)), "mana": floori(vitals.value(Vitals.MANA))}, "warning")
		"cooldown":
			SystemLog.post("skill_on_cooldown", {"skill": name, "left": cooldown_text(skills.cooldown_left(id, GameClock.minutes))}, "warning")
		"blocked":
			SystemLog.post("skill_blocked", {}, "warning")
	return used["result"]


## Откат для интерфейса в игровом времени, как таймеры кластеров: «45 с», «12 мин», «3 ч 20 мин».
static func cooldown_text(game_minutes: float) -> String:
	if game_minutes < 1.0:
		return "%d с" % ceili(game_minutes * 60.0)
	if game_minutes < 60.0:
		return "%d мин" % ceili(game_minutes)
	return "%d ч %02d мин" % [floori(game_minutes / 60.0), floori(fmod(game_minutes, 60.0))]


func set_skill_slot(index: int, id: String) -> void:
	if skills.set_slot(index, id, GameClock.minutes, stats.general_level()):
		if not id.is_empty():
			SystemLog.post("skill_slot_set", {"skill": Content.skill_name(id), "slot": index + 1})
		_update_mana_reserve()
		skills_changed.emit()


func choose_skill_property(id: String, property_id: String) -> void:
	if skills.choose_property(id, property_id, skill_levels()):
		SystemLog.post("skill_property", {"skill": Content.skill_name(id), "property": Content.texts()["property_names"].get(property_id, property_id)}, "progress")
		skills_changed.emit()


## Уровень дара, ждущего выбора (-1 — нет).
func pending_gift_level() -> int:
	if pending_skill_choices <= 0 or skill_gifts_opened.is_empty():
		return -1
	var index := maxi(0, skill_gifts_opened.size() - pending_skill_choices)
	return skill_gifts_opened[index]


## Варианты для дара, ждущего выбора: бросаются один раз (переоткрыть окно — те же варианты).
func gift_offers() -> PackedStringArray:
	var level := pending_gift_level()
	if level < 0:
		return []
	if skill_offers.is_empty():
		var pool := skills.gift_pool(level)
		var count := skills.offer_count(pool, stats.get_level("luck"))
		var origin_id := String(get("origin")) if "origin" in self else ""
		skill_offers = skills.gift_offer(pool, count, _rng, skills.always_for_origin(origin_id))
	return skill_offers


func choose_gift(id: String) -> bool:
	if not gift_offers().has(id) or not learn_skill(id):
		return false
	pending_skill_choices -= 1
	skill_offers = []
	skills_changed.emit()
	return true


## Удача во всём (D-76): бросок случайности в пользу героя. at — где показать (Vector3.INF — над
## героем). Успех — сигнал для сцены и строка в лог (не чаще log_throttle_s на вид).
func lucky(kind: String, at: Vector3 = Vector3.INF) -> bool:
	var model := Content.luck_model()
	if awaiting_respawn or not model.has_event(kind):
		return false
	var double := skills.has_status("luck_double_roll", GameClock.minutes)
	if not model.roll(kind, effective("luck"), _rng, double):
		return false
	EventBus.luck_event.emit(kind, at)
	var now := Time.get_ticks_msec()
	var throttle := float(model.config()["log_throttle_s"]) * 1000.0
	if now - int(_luck_logged.get(kind, -1000000)) >= throttle:
		_luck_logged[kind] = now
		var key := "luck_" + kind
		if SystemLog.has_key(key):
			SystemLog.post(key, {}, "special")
	return true


func _apply_skill_effects(id: String, list: Array[Dictionary]) -> void:
	var now := GameClock.minutes
	var group := String(skills.def(id).get("jackpot_group", ""))
	var name := Content.skill_name(id)
	var log_params := {"skill": name}
	for e in list:
		match String(e["type"]):
			"stat_mult":
				var from := now + float(e.get("delay_min", 0.0))
				buffs.add(String(e["stat"]), float(e["value"]) - 1.0, from + float(e["duration_min"]), "skill:" + id,
					from if e.has("delay_min") else -INF, group)
				if not e.has("delay_min"):
					log_params.merge({"mult": roundi(float(e["value"])), "seconds": ("%.1f" % float(e["duration_s"])).trim_suffix(".0")})
			"vital_fill":
				vitals.restore(String(e["vital"]), vitals.max_value(String(e["vital"])) * float(e["fraction"]))
			"vital_cost":
				vitals.drain(String(e["vital"]), float(e["value"]))
			"vitals_fill_random":
				for vital in Vitals.ALL:
					vitals.restore(vital, vitals.max_value(vital) * _rng.randf_range(float(e["min"]), float(e["max"])))
			"cure":
				if String(e["status"]) == "bleeding" and wounds.is_bleeding():
					wounds.stop_bleeding()
					SystemLog.post("bleeding_stopped")
	# Умения со своей строкой из сцены (Вспышка: «целей: N») общую не пишут.
	var key := "skill_used_" + id
	if not bool(skills.def(id).get("scene_log", false)):
		SystemLog.post(key if SystemLog.has_key(key) else "skill_used", log_params, "special")
	EventBus.skill_used.emit(id, list)


## Каждый кадр: глушение на отключённом кластере, сообщения о готовности долгих откатов.
func _skills_tick() -> void:
	if skills == null:
		return
	var off := false
	if WorldSim.clusters.has(WorldSim.current):
		off = bool(WorldSim.cluster_config().get("skills_off", false))
	if off != skills.blockers.has("cluster_disabled"):
		skills.set_blocker("cluster_disabled", off)
		skills_changed.emit()
	for id: String in _waiting_ready.keys():
		if skills.cooldown_left(id, GameClock.minutes) <= 0.0:
			_waiting_ready.erase(id)
			SystemLog.post("skill_ready", {"skill": Content.skill_name(id)})
			skills_changed.emit()


func _pearl_skill() -> void:
	var id := skills.pearl_skill(_rng)
	if id.is_empty():
		SystemLog.post("skill_pearl_empty", {}, "special")
	else:
		learn_skill(id, "skill_learned_pearl")


func _update_mana_reserve() -> void:
	if vitals and skills:
		vitals.set_mana_reserve(skills.mana_reserve(skill_levels()))


func _on_skill_levels_changed(stat: String, old_level: int, new_level: int) -> void:
	_update_mana_reserve()
	if new_level <= old_level or not (stat == "mental" or stat == "talent_facets"):
		skills_changed.emit()
		return
	var thresholds: Array = Content.skill_rules_config()["thresholds"].get(stat, [])
	var crossed := false
	for t in thresholds:
		if old_level < int(t) and new_level >= int(t):
			crossed = true
	if crossed:
		var levels := skill_levels()
		var names: PackedStringArray = []
		for id: String in skills.learned:
			if not skills.property_choices(id, levels).is_empty():
				names.append(Content.skill_name(id))
		if not names.is_empty():
			SystemLog.post("skill_property_available", {"skills": ", ".join(names)}, "progress")
	skills_changed.emit()
