extends "res://tests/test_case.gd"
## Трофеи и крафт: docs/spec/06_trophies_items.md, 6.2.

const ItemDBScript := preload("res://src/core/item_db.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const TrophyRulesScript := preload("res://src/core/trophy_rules.gd")
const BuffsScript := preload("res://src/core/buffs.gd")
const CraftingScript := preload("res://src/core/crafting.gd")
const VitalsScript := preload("res://src/core/vitals.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")

const CONTEXT := {
	"skill_count": 0,
	"main_stats": ["strength", "agility", "speed", "endurance", "mental"],
	"additional_stats": ["accuracy", "reaction", "luck", "stealth", "perception"],
	"vitals": ["health", "stamina", "spore_balance", "mana"],
}


func _db() -> ItemDB:
	var files: Array = []
	for file in DirAccess.get_files_at("res://data/items"):
		if file.ends_with(".json"):
			files.append(JsonDataScript.load_dict("res://data/items".path_join(file)))
	return ItemDBScript.new(files)


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_pea_cooldown_12_hours_shared_by_group() -> void:
	var rules := TrophyRulesScript.new(_db())
	assert_true(not rules.is_violation("pea_yellow", 0.0), "первая горошина — без нарушения")
	rules.resolve("pea_yellow", 100.0, _rng(), CONTEXT)
	assert_almost(rules.cooldown_left("pea_white", 100.0 + 60.0), 11.0 * 60.0, "белая — та же группа, ещё 11 ч")
	assert_true(rules.is_violation("pea_gold", 100.0 + 11.9 * 60.0), "11.9 ч — рано")
	assert_true(not rules.is_violation("pea_gold", 100.0 + 12.0 * 60.0), "12 ч — можно")
	assert_true(not rules.is_violation("pearl_black", 200.0), "жемчуг — своя группа")


func test_pea_effect_ranges_and_violation_halves() -> void:
	var rng := _rng(11)
	for i in 200:
		var rules := TrophyRulesScript.new(_db())
		var normal: Dictionary = rules.resolve("pea_white", 0.0, rng, CONTEXT)
		var value: int = normal["effects"][0]["value"]
		assert_true(value >= 4 and value <= 9, "белая: +4–9, получено %d" % value)
		var violated: Dictionary = rules.resolve("pea_white", 60.0, rng, CONTEXT)
		assert_true(violated["violation"], "второй приём через час — нарушение")
		var half: int = violated["effects"][0]["value"]
		assert_true(half >= 2 and half <= 5, "при нарушении — вдвое меньше, получено %d" % half)


func test_pearl_risk_grows_when_interval_violated() -> void:
	var rng := _rng(5)
	var quasi_normal := 0
	var quasi_violated := 0
	for i in 2000:
		var rules := TrophyRulesScript.new(_db())
		if rules.resolve("pearl_black", 0.0, rng, CONTEXT)["risks"].has("become_quasi"):
			quasi_normal += 1
		if rules.resolve("pearl_black", 60.0, rng, CONTEXT)["risks"].has("become_quasi"):
			quasi_violated += 1
	assert_true(quasi_normal > 10 and quasi_normal < 80, "2%% из 2000 ≈ 40, получено %d" % quasi_normal)
	assert_true(quasi_violated > 600 and quasi_violated < 800, "35%% из 2000 ≈ 700, получено %d" % quasi_violated)


func test_pearl_skill_chance_depends_on_skill_count() -> void:
	var rules := TrophyRulesScript.new(_db())
	var ctx := CONTEXT.duplicate()
	var chances: Array = []
	for skills in 4:
		ctx["skill_count"] = skills
		rules.last_taken.clear()
		var effects: Array = rules.resolve("pearl_black", 0.0, _rng(), ctx)["effects"]
		chances.append(effects[2]["chance"])
	assert_eq(chances, [0.2, 0.1, 0.05, 0.0], "20% / 10% / 5% / дальше нет")


func test_grain_buffs_main_stat_and_stars_pick_vitals() -> void:
	var rules := TrophyRulesScript.new(_db())
	var rng := _rng(3)
	var grain: Dictionary = rules.resolve("grain", 0.0, rng, CONTEXT)["effects"][0]
	assert_true(CONTEXT["main_stats"].has(grain["stat"]), "зерно — основная характеристика")
	assert_true(grain["mult"] >= 0.1 and grain["mult"] <= 0.5 and grain["hours"] >= 1.0 and grain["hours"] <= 15.0, "+10–50% на 1–15 ч")
	var white: Array = rules.resolve("star_white", 0.0, rng, CONTEXT)["effects"]
	assert_eq(white.size(), 2, "белая звезда — две шкалы")
	assert_true(white[0]["vital"] != white[1]["vital"], "разные шкалы")
	var gold: Array = rules.resolve("star_gold", 0.0, rng, CONTEXT)["effects"]
	assert_eq(gold.size(), 5, "золотая — все 4 шкалы + свободные очки")


func test_requirements_vinegar_for_peas() -> void:
	var db := _db()
	var rules := TrophyRulesScript.new(db)
	var inv := InventoryScript.new(db, JsonDataScript.load_dict("res://data/inventory.json"))
	assert_eq(rules.missing_requirements("pea_yellow", inv), {"vinegar": 1}, "нужен уксус")
	inv.add("vinegar", 1)
	assert_eq(rules.missing_requirements("pea_yellow", inv), {}, "уксус есть")
	assert_eq(rules.missing_requirements("pearl_black", inv), {}, "жемчуг — без требований")
	assert_true(not rules.can_consume("sporan"), "споран не едят")


func test_buffs_stack_and_expire() -> void:
	var buffs := BuffsScript.new()
	buffs.add("strength", 0.3, 600.0)
	buffs.add("strength", 0.2, 120.0)
	assert_almost(buffs.multiplier("strength", 100.0), 1.5, "два бафа складываются")
	assert_almost(buffs.multiplier("strength", 200.0), 1.3, "короткий закончился")
	assert_eq(buffs.expire(200.0).size(), 1, "убран один")
	var back := BuffsScript.new()
	back.load_dict(JSON.parse_string(JSON.stringify(buffs.to_dict())))
	assert_almost(back.multiplier("strength", 300.0), 1.3, "после сохранения")


func test_craft_zhivchik() -> void:
	var db := _db()
	var inv := InventoryScript.new(db, JsonDataScript.load_dict("res://data/inventory.json"))
	var recipe: Dictionary = JsonDataScript.load_dict("res://data/recipes.json")["recipes"][0]
	inv.add("sporan", 7)
	assert_eq(CraftingScript.times_possible(recipe, inv), 0, "без водки — нельзя")
	inv.add("vodka", 2)
	assert_eq(CraftingScript.times_possible(recipe, inv), 2, "7 споранов и 2 водки — два раза")
	assert_true(CraftingScript.craft(recipe, inv)["ok"], "сделано")
	assert_eq(inv.count_of("zhivchik"), 3, "3 живчика")
	assert_eq(inv.count_of("sporan"), 4, "списано 3 спорана")
	assert_eq(inv.count_of("vodka"), 1, "списана 1 водка")


func test_star_raises_vital_max_and_survives_save() -> void:
	var vitals := VitalsScript.new(JsonDataScript.load_dict("res://data/vitals.json"))
	vitals.add_max_bonus("health", 5.0)
	assert_almost(vitals.max_value("health"), 105.0, "максимум здоровья +5")
	assert_almost(vitals.value("health"), 105.0, "текущее тоже +5")
	vitals.set_stat_levels(3, 1)
	assert_almost(vitals.max_value("health"), 125.0, "прибавка сохраняется при росте Выносливости")
	var back := VitalsScript.new(JsonDataScript.load_dict("res://data/vitals.json"), 3, 1)
	back.load_dict(JSON.parse_string(JSON.stringify(vitals.to_dict())))
	assert_almost(back.max_value("health"), 125.0, "после сохранения")
