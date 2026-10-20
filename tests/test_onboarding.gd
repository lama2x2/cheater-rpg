extends "res://tests/test_case.gd"
## Начало игры (задача 17): цепочка шагов, имя на крестинах, кличка по поступку, сцены куша.

const OnboardingRulesScript := preload("res://src/core/onboarding_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> OnboardingRules:
	return OnboardingRulesScript.new(JsonDataScript.load_dict("res://data/onboarding.json"))


func test_steps_chain_to_done() -> void:
	var r := _rules()
	var step := OnboardingRules.START
	for event in ["prologue_done", "first_infected_spawned", "hero_died", "mentor_talked", "sack_opened", "christened", "stab_entered"]:
		step = r.next(step, event)
	assert_eq(step, OnboardingRules.DONE, "вся цепочка доходит до конца")
	assert_eq(r.next("sack", "christened"), "sack", "чужое событие шаг не двигает")
	assert_eq(r.next("first_infected", "first_infected_dead"), "mentor", "убил медляка — к наставнику")
	assert_true(not r.hint("mentor").is_empty(), "у шагов есть подсказки")


func test_every_step_reachable_and_known() -> void:
	var steps: Dictionary = JsonDataScript.load_dict("res://data/onboarding.json")["steps"]
	for id: String in steps:
		for event: String in steps[id]["next"]:
			assert_true(steps.has(String(steps[id]["next"][event])), "%s → %s: шаг есть" % [id, steps[id]["next"][event]])


func test_names() -> void:
	var r := _rules()
	assert_eq(r.clean_name("  Март "), "Март", "пробелы срезаны")
	assert_eq(r.clean_name("Я"), "", "слишком коротко")
	assert_eq(r.clean_name("<script>"), "", "не буквы")
	assert_eq(r.clean_name("Серый Волк"), "Серый Волк", "два слова — можно")


func test_christening_nicknames() -> void:
	var r := _rules()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var given := 0
	for i in 200:
		var res := r.christen("Март", {}, rng)
		if not res["nickname"]:
			given += 1
			assert_eq(res["name"], "Март", "имя принято")
	assert_true(given > 110 and given < 170, "крестный иногда отказывает (~30%%): принял %d из 200" % given)
	var bad := r.christen("<>", {"deaths": 4}, rng)
	assert_true(bad["nickname"], "негодное имя — кличка")
	assert_true(["Многоразовый", "Возвратный", "Опять"].has(bad["name"]), "кличка по смертям: %s" % bad["name"])


func test_jackpot_scenes_cover_variants() -> void:
	var r := _rules()
	for v: Dictionary in JsonDataScript.load_dict("res://data/origins.json")["variants"]:
		if bool(v.get("available", true)):
			var scene := r.jackpot_scene(String(v["id"]))
			assert_true(["object", "first_death", "system", "christening"].has(String(scene["kind"])), "%s: сцена куша" % v["id"])
