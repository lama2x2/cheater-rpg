extends "res://tests/test_case.gd"
## Заражённые: данные и мозг. docs/spec/07_enemies.md, 7.1.

const BrainScript := preload("res://src/core/infected_brain.gd")
const EnemyDBScript := preload("res://src/core/enemy_db.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")

const AI := {"wander_radius": 10, "lose_sight_s": 5, "search_s": 6, "hunger_per_s": 0.01, "eat_per_s": 0.1, "hungry_at": 0.5, "smell_food": 20}


func _db() -> EnemyDB:
	return EnemyDBScript.new([JsonDataScript.load_dict("res://data/enemies/infected.json")])


func _brain(hunger: float = 0.0) -> InfectedBrain:
	return BrainScript.new(AI, 1.2, hunger)


func _seen(distance: float) -> Dictionary:
	return {"sees_player": true, "player_position": Vector3(distance, 0, 0), "player_distance": distance}


func test_data_valid_and_stages_ordered() -> void:
	var db := _db()
	assert_eq(db.errors(), PackedStringArray(), "схема")
	var stages: Array = []
	for id in ["crawler", "slowpoke", "jumper", "runner", "lottery", "stomper", "elite"]:
		assert_true(db.has_enemy(id), "есть «%s»" % id)
		stages.append(int(db.enemy(id)["stage"]))
	assert_eq(stages, [0, 1, 2, 3, 4, 5, 8], "стадии 0–5 по порядку и элита (8)")
	assert_true(not db.enemy("slowpoke")["can_open_doors"], "медляки не открывают двери")
	assert_true(db.enemy("runner")["can_open_doors"], "бегуны открывают")
	var names: Dictionary = JsonDataScript.load_dict("res://data/text/ru.json")["enemy_names"]
	for file in DirAccess.get_files_at("res://data/text"):  # дополнения ru_*.json (как Content.texts)
		if file.begins_with("ru_") and file.ends_with(".json"):
			names.merge(JsonDataScript.load_dict("res://data/text/" + file).get("enemy_names", {}), true)
	for id in db.ids():
		assert_true(names.has(id), "нет имени для «%s»" % id)


func test_level_roll_and_hp_scaling() -> void:
	var db := _db()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in 100:
		var level := db.roll_level("runner", rng)
		assert_true(level >= 10 and level <= 20, "бегун 10–20: %d" % level)
	assert_almost(db.max_hp("runner", 10), 150.0, "минимальный уровень — базовое здоровье")
	assert_almost(db.max_hp("runner", 20), 200.0, "+5 за уровень")


func test_sees_player_chase_then_attack() -> void:
	var brain := _brain()
	assert_eq(brain.update(0.1, _seen(8.0)), "chase", "увидел — гонится")
	assert_eq(brain.target_position, Vector3(8, 0, 0), "цель — герой")
	assert_eq(brain.update(0.1, _seen(1.0)), "attack", "в досягаемости — бьёт")
	assert_eq(brain.update(0.1, _seen(1.4)), "attack", "чуть дальше — ещё бьёт (гистерезис)")
	assert_eq(brain.update(0.1, _seen(2.0)), "chase", "отошёл — снова гонится")


func test_lost_sight_goes_to_last_seen_then_searches() -> void:
	var brain := _brain()
	brain.update(0.1, _seen(8.0))
	assert_eq(brain.update(4.0, {}), "chase", "4 с без героя — ещё бежит к последней точке")
	assert_eq(brain.update(1.5, {}), "investigate", "5 с — потерял, ищет")
	assert_eq(brain.target_position, Vector3(8, 0, 0), "ищет там, где видел")
	assert_eq(brain.update(3.0, {"at_target": true}), "investigate", "дошёл, осматривается")
	assert_eq(brain.update(3.5, {"at_target": true}), "wander", "через 6 с бросает")


func test_noise_draws_attention() -> void:
	var brain := _brain()
	var noise := {"position": Vector3(3, 0, 4), "loudness": 0.3}
	assert_eq(brain.update(0.1, {"noise": noise}), "investigate", "шум — проверить")
	assert_eq(brain.target_position, Vector3(3, 0, 4), "идёт на шум")


func test_hunger_leads_to_eating_and_loud_noise_interrupts() -> void:
	var brain := _brain(0.6)
	var food := {"position": Vector3(5, 0, 0), "distance": 5.0}
	assert_eq(brain.update(0.1, {"food": food}), "eat", "голоден и чует еду")
	brain.update(2.0, {"food": food, "at_target": true})
	assert_true(brain.hunger < 0.6, "ест — голод падает")
	assert_eq(brain.update(0.1, {"food": food, "at_target": true, "noise": {"position": Vector3.ZERO, "loudness": 0.3}}), "eat", "тихий шум не отвлекает от еды")
	assert_eq(brain.update(0.1, {"food": food, "noise": {"position": Vector3.ZERO, "loudness": 0.9}}), "investigate", "громкий — отвлекает")


func test_not_hungry_ignores_food() -> void:
	var brain := _brain(0.1)
	assert_eq(brain.update(0.1, {"food": {"position": Vector3.ONE, "distance": 1.0}}), "wander", "сыт — не ест")


func test_save_turns_chase_into_search() -> void:
	var brain := _brain()
	brain.update(0.1, _seen(8.0))
	var back := _brain()
	back.load_dict(JSON.parse_string(JSON.stringify(brain.to_dict())))
	assert_eq(back.state, "investigate", "после загрузки не знает, где герой, — ищет")
	assert_eq(back.target_position, Vector3(8, 0, 0), "там, где видел")
