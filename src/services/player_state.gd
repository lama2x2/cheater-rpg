extends Node
## Состояние героя: характеристики, шкалы и жизни. Связывает правила (src/core) со сценой и логом.

var stats: StatBlock
var vitals: Vitals
var lives: int = 0
var deaths: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	stats = StatBlock.new(Content.stats_config())
	lives = int(Content.rules()["lives_start"])
	stats.stat_level_changed.connect(_on_stat_level_changed)
	vitals = Vitals.new(Content.vitals_config(), stats.get_level("endurance"), stats.get_level("mental"))
	vitals.depleted.connect(_on_vital_depleted)
	vitals.spore_state_changed.connect(_on_spore_state_changed)


func add_progress(stat: String, points: float) -> void:
	stats.add_progress(stat, points)


## Смерть: −1 жизнь, штраф прогресса. Возрождение и итоговый экран — следующие этапы.
func die(cause: String) -> void:
	if lives <= 0:
		return
	var life_number := deaths + 1
	deaths += 1
	lives -= 1
	stats.apply_death_penalty(_rng)
	SystemLog.post("death", {"life": life_number, "lives": lives}, "death")
	if lives == 0:
		SystemLog.post("death_final", {}, "death")
	# Пока нет экрана возрождения (задача 3) — герой сразу встаёт на месте.
	vitals.restore_after_death()
	EventBus.player_died.emit(cause, lives)


func to_dict() -> Dictionary:
	return {"stats": stats.to_dict(), "vitals": vitals.to_dict(), "lives": lives, "deaths": deaths}


func load_dict(data: Dictionary) -> void:
	stats.load_dict(data["stats"])
	vitals.set_stat_levels(stats.get_level("endurance"), stats.get_level("mental"))
	vitals.load_dict(data["vitals"])
	lives = int(data["lives"])
	deaths = int(data["deaths"])


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
	var params := {"stat": Content.stat_name(stat), "level": new_level}
	if new_level < old_level:
		SystemLog.post("stat_level_lost", params, "warning")
		return
	var special_key := "stat_level_up_" + stat
	SystemLog.post(special_key if SystemLog.has_key(special_key) else "stat_level_up", params, "progress")
