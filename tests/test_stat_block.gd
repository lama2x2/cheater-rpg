extends "res://tests/test_case.gd"
## Правила характеристик: docs/spec/03_character.md, штраф смерти: docs/spec/04_death_lives.md.

const StatBlockScript := preload("res://src/core/stat_block.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _config(overrides: Dictionary = {}) -> Dictionary:
	var config: Dictionary = JsonDataScript.load_dict("res://data/stats.json").duplicate(true)
	config.merge(overrides, true)
	return config


func _block(overrides: Dictionary = {}) -> StatBlock:
	return StatBlockScript.new(_config(overrides))


func test_start_levels_and_general_level() -> void:
	var stats := _block()
	assert_eq(stats.get_level("speed"), 1, "стартовый уровень")
	assert_eq(stats.general_level(), 1, "общий уровень на старте (5/5)")
	stats.add_levels("strength", 4)
	assert_eq(stats.general_level(), 1, "сумма 9 → 1")
	stats.add_levels("strength", 1)
	assert_eq(stats.general_level(), 2, "сумма 10 → 2")


func test_threshold_grows_with_level() -> void:
	var stats := _block()
	assert_almost(stats.threshold("speed"), 10.0, "порог 1 уровня")
	stats.add_levels("speed", 2)
	assert_almost(stats.threshold("speed"), 30.0, "порог 3 уровня")


func test_progress_carries_over_levels() -> void:
	var stats := _block()
	assert_eq(stats.add_progress("speed", 25.0), 1, "25 очков: +1 уровень (10)")
	assert_eq(stats.get_level("speed"), 2, "уровень после 25")
	assert_almost(stats.get_progress("speed"), 15.0, "остаток прогресса")
	assert_eq(stats.add_progress("speed", 5.0), 1, "ещё 5: порог 20 достигнут")
	assert_almost(stats.get_progress("speed"), 0.0, "прогресс обнулился")


func test_level_changed_signal() -> void:
	var stats := _block()
	var events: Array = []
	stats.stat_level_changed.connect(func(stat: String, old: int, new: int) -> void: events.append([stat, old, new]))
	stats.add_progress("speed", 30.0)
	assert_eq(events, [["speed", 1, 3]], "один сигнал на несколько уровней")


func test_experience_multiplier() -> void:
	var stats := _block()
	assert_almost(stats.experience_multiplier(), 1.0, "сумма доп. 7 → без бонуса")
	stats.add_levels("luck", 13)
	assert_almost(stats.experience_multiplier(), 1.02, "сумма доп. 20 → +2%")
	stats.add_progress("speed", 5.0)
	assert_almost(stats.get_progress("speed"), 5.1, "опытность применяется к прогрессу")
	stats.add_levels("luck", 1000)
	assert_almost(stats.experience_multiplier(), 1.5, "кап +50%")


func test_effective_value_uses_coefficient_and_growth() -> void:
	var stats := _block()
	stats.set_coefficient("strength", 1.5)
	stats.add_levels("strength", 3)
	# общий уровень: (4+1+1+1+1)/5 = 1 → рост 1.1
	assert_almost(stats.effective_value("strength"), 4.0 * 1.5 * 1.1, "уровень × коэффициент × рост")


func test_death_penalty_takes_5_to_50_percent_min_one() -> void:
	var rng := RandomNumberGenerator.new()
	for i in 200:
		rng.seed = i
		var stats := _block()
		stats.add_progress("speed", 30.0)  # уровень 3, прогресс 0
		stats.add_progress("speed", 10.0)  # прогресс 10 из 30
		stats.apply_death_penalty(rng)
		var left := stats.get_progress("speed")
		assert_true(left >= 5.0 and left <= 9.0, "seed %d: осталось %f" % [i, left])
		assert_eq(stats.get_level("speed"), 3, "seed %d: уровень не теряется при прогрессе" % i)


func test_death_penalty_never_negative() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var stats := _block({"death_penalty": {
		"loss_min": 0.05, "loss_max": 0.5, "min_loss_points": 1,
		"level_loss_progress_below": 0.05, "level_loss_chance": 0.0}})
	stats.add_progress("strength", 0.5, false)
	stats.apply_death_penalty(rng)
	assert_almost(stats.get_progress("strength"), 0.0, "минимум 1, но не ниже нуля")


func test_death_penalty_level_loss_when_progress_near_zero() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stats := _block({"death_penalty": {
		"loss_min": 0.05, "loss_max": 0.5, "min_loss_points": 1,
		"level_loss_progress_below": 0.05, "level_loss_chance": 1.0}})
	stats.add_levels("speed", 2)
	var report := stats.apply_death_penalty(rng)
	assert_eq(stats.get_level("speed"), 2, "уровень снижен 3 → 2")
	assert_true(report["speed"]["level_lost"], "отчёт отмечает потерю уровня")
	assert_eq(stats.get_level("strength"), 1, "уровень 1 не теряется")


func test_save_roundtrip() -> void:
	var stats := _block()
	stats.add_progress("speed", 27.0)
	stats.set_coefficient("luck", 1.3)
	var restored := _block()
	restored.load_dict(stats.to_dict())
	assert_eq(restored.get_level("speed"), stats.get_level("speed"), "уровень")
	assert_almost(restored.get_progress("speed"), stats.get_progress("speed"), "прогресс")
	assert_almost(restored.get_coefficient("luck"), 1.3, "коэффициент")
