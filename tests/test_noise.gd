extends "res://tests/test_case.gd"
## Шум: docs/spec/08_combat.md, 8.2.

const NoiseModelScript := preload("res://src/core/noise_model.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _noise() -> NoiseModel:
	return NoiseModelScript.new(JsonDataScript.load_dict("res://data/noise.json"))


func test_table_matches_spec_order() -> void:
	var n := _noise()
	assert_true(n.base_radius("sneak_step") < n.base_radius("walk_step"), "крадётся тише, чем идёт")
	assert_true(n.base_radius("walk_step") < n.base_radius("sprint_step"), "бег громче шага")
	assert_true(n.base_radius("pistol_silenced") < n.base_radius("pistol"), "глушитель")
	assert_almost(n.base_radius("pistol"), 60.0, "пистолет 60 м")
	assert_almost(n.base_radius("rifle"), 120.0, "автомат 120 м")


func test_linear_falloff_and_threshold() -> void:
	var n := _noise()
	assert_almost(n.loudness_at(60.0, 0.0), 1.0, "в упор — 1")
	assert_almost(n.loudness_at(60.0, 30.0), 0.5, "на половине — 0.5")
	assert_almost(n.loudness_at(60.0, 59.0), 0.0, "у края ниже порога 0.05 — не слышно")
	assert_almost(n.loudness_at(60.0, 61.0), 0.0, "за радиусом — тишина")


func test_walls_and_hearing() -> void:
	var n := _noise()
	assert_almost(n.loudness_at(60.0, 15.0, 1), 0.5, "стена режет радиус вдвое: 1 − 15/30")
	assert_almost(n.loudness_at(60.0, 10.0, 5), n.loudness_at(60.0, 10.0, 2), "больше двух стен не считаем")
	assert_almost(n.loudness_at(60.0, 30.0, 0, 1.2), 0.6, "острый слух — громче")


func test_weather_indoors_stealth_overload() -> void:
	var n := _noise()
	assert_almost(n.radius("pistol", {"weather": "rain"}), 42.0, "дождь −30%")
	assert_almost(n.radius("pistol", {"indoors": true}), 42.0, "в помещении −30%")
	assert_almost(n.radius("walk_step", {"stealth_level": 11}), 6.0 * 0.8, "Скрытность 11 — шаги −20%")
	assert_almost(n.radius("walk_step", {"stealth_level": 100}), 3.0, "не тише половины")
	assert_almost(n.radius("walk_step", {"load_ratio": 1.5}), 6.0 * 1.3, "перегруз ×1.5 — шаги ×1.3")
	assert_almost(n.radius("walk_step", {"load_ratio": 0.5}), 6.0, "без перегруза — как есть")


func test_loud_series_accumulates_and_cools() -> void:
	var n := _noise()
	n.register(n.radius("walk_step"))
	assert_almost(n.heat_bonus, 0.0, "тихое не копится")
	for i in 3:
		n.register(n.radius("pistol"))
	assert_true(n.heat_bonus > 0.3, "три выстрела — радиус растёт (%f)" % n.heat_bonus)
	assert_true(n.radius("pistol") > 60.0 * 1.3, "следующий выстрел слышно дальше")
	assert_almost(n.radius("walk_step"), 6.0, "на шаги накопление не влияет")
	n.cool_down(100.0)
	assert_almost(n.heat_bonus, 0.0, "остыло")
