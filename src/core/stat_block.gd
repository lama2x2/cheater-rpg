class_name StatBlock
extends RefCounted
## Характеристики героя: уровни, прогресс к следующему уровню, коэффициенты.
## Чистые правила без Node — тестируются headless. Спецификация: docs/spec/03_character.md.

signal stat_level_changed(stat: String, old_level: int, new_level: int)

const REQUIRED_KEYS: PackedStringArray = [
	"main", "additional", "start_level", "progress_per_level",
	"general_level_divisor", "additional_level_divisor",
	"base_growth_per_general_level", "experience_bonus", "death_penalty",
]

var _config: Dictionary
var _main: PackedStringArray
var _additional: PackedStringArray
var _levels: Dictionary = {}
var _progress: Dictionary = {}
var _coefficients: Dictionary = {}


func _init(config: Dictionary) -> void:
	_config = config
	_main = PackedStringArray(config["main"])
	_additional = PackedStringArray(config["additional"])
	var start_level := int(config["start_level"])
	for stat in all_stats():
		_levels[stat] = start_level
		_progress[stat] = 0.0
		_coefficients[stat] = 1.0


func all_stats() -> PackedStringArray:
	return _main + _additional


func main_stats() -> PackedStringArray:
	return _main


func additional_stats() -> PackedStringArray:
	return _additional


func has_stat(stat: String) -> bool:
	return _levels.has(stat)


func get_level(stat: String) -> int:
	_check(stat)
	return _levels[stat]


func get_progress(stat: String) -> float:
	_check(stat)
	return _progress[stat]


func get_coefficient(stat: String) -> float:
	_check(stat)
	return _coefficients[stat]


func set_coefficient(stat: String, value: float) -> void:
	_check(stat)
	_coefficients[stat] = value


## Сколько очков прогресса нужно, чтобы поднять характеристику на следующий уровень.
func threshold(stat: String) -> float:
	return float(_config["progress_per_level"]) * maxi(get_level(stat), 1)


## Общий уровень = сумма основных / 5 (вниз).
func general_level() -> int:
	return floori(float(_sum_levels(_main)) / float(_config["general_level_divisor"]))


## Дополнительный уровень = сумма дополнительных / 7 (вниз).
func additional_level() -> int:
	return floori(float(_sum_levels(_additional)) / float(_config["additional_level_divisor"]))


## Опытность: +бонус за каждые N единиц суммы дополнительных, не выше капа.
func experience_multiplier() -> float:
	var eb: Dictionary = _config["experience_bonus"]
	var steps := floori(float(_sum_levels(_additional)) / float(eb["per_additional_sum"]))
	return 1.0 + minf(float(eb["cap"]), steps * float(eb["bonus"]))


## Итоговое значение = уровень × коэффициент × рост базы от общего уровня.
func effective_value(stat: String) -> float:
	var growth := 1.0 + float(_config["base_growth_per_general_level"]) * general_level()
	return get_level(stat) * get_coefficient(stat) * growth


## Начисляет очки прогресса (с учётом опытности). Возвращает число полученных уровней.
func add_progress(stat: String, points: float, apply_experience: bool = true) -> int:
	_check(stat)
	if points <= 0.0:
		return 0
	var gained := points * (experience_multiplier() if apply_experience else 1.0)
	_progress[stat] += gained
	var old_level: int = _levels[stat]
	while _progress[stat] >= threshold(stat):
		_progress[stat] -= threshold(stat)
		_levels[stat] += 1
	var levels_up: int = _levels[stat] - old_level
	if levels_up > 0:
		stat_level_changed.emit(stat, old_level, _levels[stat])
	return levels_up


## Свободные очки: каждое — сразу +1 уровень характеристики.
func add_levels(stat: String, amount: int) -> void:
	_check(stat)
	if amount == 0:
		return
	var old_level: int = _levels[stat]
	_levels[stat] = maxi(1, old_level + amount)
	if _levels[stat] != old_level:
		stat_level_changed.emit(stat, old_level, _levels[stat])


## Штраф смерти по основным характеристикам. Возвращает отчёт {stat: {lost, level_lost}}.
func apply_death_penalty(rng: RandomNumberGenerator) -> Dictionary:
	var dp: Dictionary = _config["death_penalty"]
	var report := {}
	for stat in _main:
		var before: float = _progress[stat]
		var t := threshold(stat)
		var can_lose_level: bool = _levels[stat] > 1 and before < t * float(dp["level_loss_progress_below"])
		if can_lose_level and rng.randf() < float(dp["level_loss_chance"]):
			var old_level: int = _levels[stat]
			_levels[stat] = old_level - 1
			_progress[stat] = 0.0
			report[stat] = {"lost": before, "level_lost": true}
			stat_level_changed.emit(stat, old_level, _levels[stat])
			continue
		var pct := rng.randf_range(float(dp["loss_min"]), float(dp["loss_max"]))
		var loss := maxf(float(dp["min_loss_points"]), roundf(before * pct))
		loss = minf(loss, before)
		_progress[stat] = before - loss
		report[stat] = {"lost": loss, "level_lost": false}
	return report


func to_dict() -> Dictionary:
	return {
		"levels": _levels.duplicate(),
		"progress": _progress.duplicate(),
		"coefficients": _coefficients.duplicate(),
	}


func load_dict(data: Dictionary) -> void:
	for stat in all_stats():
		_levels[stat] = int(data["levels"].get(stat, _levels[stat]))
		_progress[stat] = float(data["progress"].get(stat, _progress[stat]))
		_coefficients[stat] = float(data["coefficients"].get(stat, _coefficients[stat]))


func _sum_levels(stats: PackedStringArray) -> int:
	var total := 0
	for stat in stats:
		total += int(_levels[stat])
	return total


func _check(stat: String) -> void:
	assert(_levels.has(stat), "Неизвестная характеристика: %s" % stat)
