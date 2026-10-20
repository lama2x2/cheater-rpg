extends "res://tests/test_case.gd"
## Зрение героя и чуйка (17, D-69): конус и круг, дальность, поворот взгляда, шанс чуйки.

const VisionRulesScript := preload("res://src/core/vision_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> VisionRules:
	return VisionRulesScript.new(JsonDataScript.load_dict("res://data/vision.json"))


func test_cone_and_circle() -> void:
	var rules := _rules()
	var hero := Vector3.ZERO
	var facing := Vector3(0, 0, -1)
	assert_true(rules.in_view(hero, facing, Vector3(0, 0, -10), 110.0, 30.0), "прямо впереди")
	assert_true(rules.in_view(hero, facing, Vector3(6, 0, -6), 110.0, 30.0), "45° — в конусе 110°")
	assert_true(not rules.in_view(hero, facing, Vector3(10, 0, 0), 110.0, 30.0), "90° сбоку — нет")
	assert_true(not rules.in_view(hero, facing, Vector3(0, 0, 10), 110.0, 30.0), "за спиной — нет")
	assert_true(rules.in_view(hero, facing, Vector3(0, 0, 2.0), 110.0, 30.0), "за спиной, но вплотную — круг")
	assert_true(not rules.in_view(hero, facing, Vector3(0, 0, -40), 110.0, 30.0), "дальше дальности — нет")


func test_range_by_time_fog_and_perception() -> void:
	var rules := _rules()
	assert_true(rules.is_night(23) and rules.is_night(3) and not rules.is_night(12), "ночь — с 22 до 5")
	assert_true(rules.view_range(2, false, 1) < rules.view_range(12, false, 1), "ночью дальность меньше")
	assert_true(rules.view_range(12, true, 1) < rules.view_range(12, false, 1), "в кисляке меньше")
	assert_true(rules.view_range(12, false, 10) > rules.view_range(12, false, 1), "Наблюдательность — дальше")


func test_cone_width() -> void:
	var rules := _rules()
	assert_true(rules.cone_deg(true, 1) < rules.cone_deg(false, 1), "в беге конус уже")
	assert_almost(rules.cone_deg(false, 1000) - rules.cone_deg(false, 1), 20.0, "прибавка угла с потолком")


func test_turn_towards() -> void:
	var dir := VisionRules.turn_towards(Vector3(0, 0, -1), Vector3(0, 0, 1), 90.0)
	assert_almost(dir.length(), 1.0, "единичный")
	assert_almost(absf(dir.x), 1.0, "повернулся ровно на 90°", 0.001)
	var done := VisionRules.turn_towards(Vector3(0, 0, -1), Vector3(1, 0, -1), 90.0)
	assert_almost(done.x, done.normalized().x, "доворот без перелёта")
	assert_true(done.angle_to(Vector3(1, 0, -1).normalized()) < 0.001, "45° за шаг 90° — догнал")
	var rules := _rules()
	assert_true(rules.turn_speed(10) > rules.turn_speed(1), "Реакция — быстрее")


func test_sense_chance() -> void:
	var rules := _rules()
	var near := rules.sense_chance(1.0, 1.0, 0.0, 1, 3.0, false)
	var far := rules.sense_chance(1.0, 1.0, 0.0, 1, 13.0, false)
	assert_true(near > far and far > 0.0, "ближе — вероятнее: %f > %f" % [near, far])
	assert_eq(rules.sense_chance(1.0, 1.0, 0.0, 1, 20.0, false), 0.0, "дальше радиуса — никогда")
	assert_true(rules.sense_chance(1.0, 1.0, 0.0, 1, 6.0, true) > rules.sense_chance(1.0, 1.0, 0.0, 1, 6.0, false), "гонится — злее, заметнее")
	assert_true(rules.sense_chance(1.0, 1.0, 3.0, 20, 6.0, false) < rules.sense_chance(1.0, 1.0, 0.0, 1, 6.0, false), "скрытная и сильная — хуже")
	assert_true(rules.sense_chance(8.0, 8.0, 3.0, 20, 6.0, false) > rules.sense_chance(1.0, 1.0, 3.0, 20, 6.0, false), "Наблюдательность и Реакция помогают")
	assert_eq(rules.sense_chance(9.0, 9.0, 0.0, 1, 1.0, true, 1.0), 0.0, "полное гашение элиты")
	assert_true(rules.sense_chance(1000.0, 1000.0, 0.0, 0, 0.0, true) <= 0.95, "не выше потолка")


func test_sight_fan() -> void:
	var fan := _rules().sight_fan(Vector3(0, 0, -1))
	assert_eq(fan.size(), 180, "180 лучей по кругу")
	assert_almost(fan[0], Vector2(0, -1).angle(), "первый — по взгляду")
	assert_almost(absf(wrapf(fan[90] - fan[0], -PI, PI)), PI, "90-й — за спиной", 0.001)


func test_camera_sides() -> void:
	# Изометрическая камера (рысканье 45°) смотрит на −x −z: к ней обращены стороны +z (n) и +x (e).
	var sides := VisionRules.camera_sides(Vector3(-0.707, -0.5, -0.707))
	assert_eq(sides.size(), 2, "к камере — две стороны")
	assert_true(sides.has("n") and sides.has("e"), "смотрит на −x −z — к камере стороны +z и +x: %s" % [sides])
