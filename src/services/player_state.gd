extends Node
## Состояние героя: характеристики и жизни. Связывает правила (src/core) со сценой и логом.

var stats: StatBlock
var lives: int = 0
var deaths: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	stats = StatBlock.new(Content.stats_config())
	lives = int(Content.rules()["lives_start"])
	stats.stat_level_changed.connect(_on_stat_level_changed)


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
	EventBus.player_died.emit(cause, lives)


func _on_stat_level_changed(stat: String, old_level: int, new_level: int) -> void:
	var params := {"stat": Content.stat_name(stat), "level": new_level}
	if new_level < old_level:
		SystemLog.post("stat_level_lost", params, "warning")
		return
	var special_key := "stat_level_up_" + stat
	SystemLog.post(special_key if SystemLog.has_key(special_key) else "stat_level_up", params, "progress")
