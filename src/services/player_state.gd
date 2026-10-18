extends Node
## Состояние героя: характеристики, шкалы, жизни и смерти. Связывает правила (src/core) со сценой
## и логом. Показ смерти и возрождения — src/world/death_flow.gd.

signal inventory_changed

var stats: StatBlock
var vitals: Vitals
var inventory: Inventory
var run := RunStats.new()
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
		"inventory": inventory.to_dict(),
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
		die("health")


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
