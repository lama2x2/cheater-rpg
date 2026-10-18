extends "res://tests/test_case.gd"
## Абстрактная популяция кластера: docs/spec/02_world.md («Жизненный цикл»), 13.3.

const PopulationModelScript := preload("res://src/core/population_model.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _model() -> PopulationModel:
	return PopulationModelScript.new(JsonDataScript.load_dict("res://data/world/population.json"))


func _village() -> Dictionary:
	return JsonDataScript.load_dict("res://data/world/templates/village.json")["population"]


func _arrival(seed_value: int = 7) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _model().arrival(_village(), rng)


func test_stages_match_enemies() -> void:
	var enemies: Array = JsonDataScript.load_dict("res://data/enemies/infected.json")["enemies"]
	var ids: Array = enemies.map(func(e: Dictionary) -> String: return e["id"])
	for stage in _model().stages:
		assert_true(ids.has(stage), "стадия %s есть в data/enemies" % stage)


func test_arrival_within_profile() -> void:
	var model := _model()
	for s in 50:
		var state := _arrival(s)
		var people := float(state["civilians"]) + model.total_infected(state) + int(state["immune"])
		assert_true(people >= 60.0 and people <= 120.0, "люди %f в 60–120" % people)
		assert_true(int(state["immune"]) <= 120 * 0.07 * 1.5 + 1, "иммунных немного")
		assert_almost(float(state["loot"]), 1.0, "лут нетронут")
		assert_true(float(state["infected"]["slowpoke"]) > 0.0, "часть обратилась сразу")


func test_empty_profile_is_lifeless() -> void:
	var rng := RandomNumberGenerator.new()
	var state := _model().arrival({}, rng)
	assert_almost(_model().total_infected(state), 0.0, "тварей нет")
	assert_almost(float(state["civilians"]), 0.0, "людей нет")
	_model().advance(state, 48)
	assert_almost(_model().total_infected(state), 0.0, "и не появятся")


func test_people_turn_within_a_day() -> void:
	var model := _model()
	var state := _arrival()
	var people := float(state["civilians"])
	var turned := model.advance(state, 24)
	assert_true(float(state["civilians"]) < people * 0.05, "за сутки почти все обратились")
	assert_almost(turned, people - float(state["civilians"]), "advance возвращает обратившихся", 0.001)
	assert_true(float(state["infected"]["slowpoke"]) > float(state["infected"]["jumper"]) * 5.0, "свежий кластер — толпы медляков")


func test_late_cluster_has_few_but_stronger() -> void:
	var model := _model()
	var state := _arrival()
	model.advance(state, 24)
	var early_total := model.total_infected(state)
	model.advance(state, 24 * 10)
	var inf: Dictionary = state["infected"]
	assert_true(model.total_infected(state) < early_total * 0.4, "через 11 дней тварей гораздо меньше")
	var older := float(inf["jumper"]) + float(inf["runner"]) + float(inf["lottery"]) + float(inf["stomper"])
	assert_true(older > float(inf["slowpoke"]) + float(inf["crawler"]), "старших больше, чем медляков и ползунов")
	assert_true(float(inf["runner"]) > 0.5, "появились бегуны")


func test_starvation_makes_crawlers() -> void:
	var model := _model()
	var state := model.empty_state()
	state["infected"]["slowpoke"] = 100.0
	state["food"] = 0.0
	model.advance(state, 24)
	assert_true(float(state["infected"]["crawler"]) > 10.0, "голодные медляки становятся ползунами")
	assert_true(float(state["infected"]["jumper"]) < 0.01, "голодные не эволюционируют")


func test_hungry_predators_eat_lower_stages() -> void:
	var model := _model()
	var state := model.empty_state()
	state["infected"]["slowpoke"] = 50.0
	state["infected"]["runner"] = 10.0
	model.tick_hour(state)
	assert_true(float(state["infected"]["slowpoke"]) < 50.0 - 0.3, "бегуны съели медляков")


func test_fed_evolve_and_loot_decays() -> void:
	var model := _model()
	var state := model.empty_state()
	state["infected"]["slowpoke"] = 100.0
	state["food"] = 10000.0
	model.advance(state, 48)
	assert_true(float(state["infected"]["jumper"]) > 10.0, "сытые медляки становятся прыгунами")
	assert_true(float(state["loot"]) < 0.8 and float(state["loot"]) > 0.6, "лут растаскивают: %f" % state["loot"])


func test_deterministic() -> void:
	var a := _arrival(42)
	var b := _arrival(42)
	_model().advance(a, 100)
	_model().advance(b, 100)
	assert_eq(a, b, "одинаковый сид — одинаковый результат")


func test_agents_ratio_cap_and_rounding() -> void:
	var model := _model()
	var state := model.empty_state()
	state["infected"]["slowpoke"] = 200.0
	state["infected"]["jumper"] = 1.4
	state["infected"]["runner"] = 0.4
	var ratio := model.effective_ratio(state, 0.25, 30)
	assert_almost(ratio, 30.0 / 201.8, "потолок агентов")
	var agents := model.agents(state, ratio)
	var total := 0
	for id: String in agents:
		total += int(agents[id])
	assert_eq(total, 30, "сумма агентов — до потолка")
	assert_almost(model.effective_ratio(state, 0.1, 30), 0.1, "без потолка — как в шаблоне")
	var few := model.empty_state()
	few["infected"]["runner"] = 0.6
	few["infected"]["jumper"] = 1.0
	assert_eq(model.agents(few, 1.0), {"runner": 1, "jumper": 1}, "остаток переносится на младшую стадию: 1,6 → 2")


func test_remove_never_negative() -> void:
	var model := _model()
	var state := model.empty_state()
	state["infected"]["jumper"] = 2.0
	model.remove(state, "jumper", 4.0)
	assert_almost(float(state["infected"]["jumper"]), 0.0, "не меньше нуля")
