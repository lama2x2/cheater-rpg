extends "res://tests/test_case.gd"
## Удача во всём (D-76): насыщение шансов, Улыбка Фортуны в бою, двойной бросок, зона удачи.
## docs/spec/03_character.md «Удача».

const LuckModelScript := preload("res://src/core/luck_model.gd")
const DamageModelScript := preload("res://src/core/damage_model.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _luck() -> LuckModel:
	return LuckModelScript.new(JsonDataScript.load_dict("res://data/luck.json"))


func test_chance_saturates() -> void:
	var luck := _luck()
	assert_almost(luck.chance("enemy_miss", 0.0), 0.0, "без Удачи — ничего")
	assert_almost(luck.chance("enemy_miss", 40.0), 0.25, "L = k — половина потолка")
	assert_true(luck.chance("enemy_miss", 100000.0) < 0.5, "не выше потолка")
	assert_true(luck.chance("enemy_miss", 1.1) < 0.02, "на старте (Удача ~1) — почти ничего")


func test_fortune_smile_is_felt_in_combat() -> void:
	var luck := _luck()
	var base := 1.1
	var smile := base * 20.0
	assert_true(luck.chance("enemy_miss", smile) > 0.15, "под Улыбкой твари промахиваются заметно: %f" % luck.chance("enemy_miss", smile))
	assert_true(luck.chance("hero_crit", smile) > 0.1, "и удары находят мешок: %f" % luck.chance("hero_crit", smile))
	assert_true(luck.chance("enemy_miss", 5.5 * 20.0) > 0.3, "Удача 5 под Улыбкой — треть промахов")


func test_double_roll() -> void:
	var luck := _luck()
	var p := luck.chance("unnoticed", 40.0)
	assert_almost(luck.chance("unnoticed", 40.0, true), 1.0 - (1.0 - p) * (1.0 - p), "второй бросок")


func test_roll_distribution() -> void:
	var luck := _luck()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hits := 0
	for i in 2000:
		if luck.roll("enemy_miss", 40.0, rng):
			hits += 1
	assert_true(hits > 440 and hits < 560, "≈25%%: %d из 2000" % hits)


func test_lucky_zone() -> void:
	assert_eq(DamageModelScript.lucky_zone("torso", true, true), "spore_sack", "сзади — в мешок")
	assert_eq(DamageModelScript.lucky_zone("limbs", false, true), "head", "спереди — в голову")
	assert_eq(DamageModelScript.lucky_zone("torso", true, false), "head", "без мешка — в голову")
	assert_eq(DamageModelScript.lucky_zone("spore_sack", true, true), "spore_sack", "мешок остаётся")


func test_saturating_loot_mult() -> void:
	assert_almost(LuckModelScript.saturating_mult({"cap": 2.0, "k": 40}, 0.0), 1.0, "ноль")
	assert_almost(LuckModelScript.saturating_mult({"cap": 2.0, "k": 40}, 40.0), 1.5, "половина")
