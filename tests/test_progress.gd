extends "res://tests/test_case.gd"
## Прокачка действием: docs/spec/03_character.md, 3.2; D-09.

const ProgressRulesScript := preload("res://src/core/progress_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> ProgressRules:
	return ProgressRulesScript.new(JsonDataScript.load_dict("res://data/progress.json"))


func test_actions_map_to_stats() -> void:
	var rules := _rules()
	var stats: Dictionary = JsonDataScript.load_dict("res://data/stats.json")
	var all: Array = stats["main"] + stats["additional"]
	for action: String in JsonDataScript.load_dict("res://data/progress.json")["actions"]:
		assert_true(all.has(rules.stat_for(action)), "%s → известная характеристика" % action)
	assert_eq(rules.stat_for("melee_hit"), "strength", "удары — Сила")
	assert_eq(rules.stat_for("ranged_hit"), "accuracy", "попадания — Меткость")
	assert_eq(rules.stat_for("sneak_pass"), "stealth", "незамеченный проход — Скрытность")
	assert_eq(rules.stat_for("stash_found"), "perception", "тайники — Наблюдательность")
	assert_eq(rules.stat_for("wounded"), "endurance", "ранения — Выносливость")


func test_full_rate_until_farm_cap() -> void:
	var rules := _rules()
	var total := 0.0
	for i in 20:  # 20 ударов × 0.6 = 12 = farm_cap
		total += rules.award("melee_hit", 1.0, 100.0)["points"]
	assert_almost(total, 12.0, "до потолка — полностью")


func test_diminishing_after_cap_and_reset_next_hour() -> void:
	var rules := _rules()
	for i in 20:
		rules.award("melee_hit", 1.0, 100.0)
	var after_cap: Dictionary = rules.award("melee_hit", 1.0, 100.0)
	assert_true(after_cap["farm_mult"] < 1.0 and after_cap["farm_mult"] > 0.9, "сразу за потолком чуть меньше")
	for i in 200:
		rules.award("melee_hit", 1.0, 110.0)
	assert_true(rules.farm_multiplier("melee_hit") < 0.15, "после 220 ударов за час отдача < 15%%: %f" % rules.farm_multiplier("melee_hit"))
	var next_hour: Dictionary = rules.award("melee_hit", 1.0, 125.0)
	assert_almost(next_hour["farm_mult"], 1.0, "новый игровой час — снова полностью")


func test_actions_are_independent() -> void:
	var rules := _rules()
	for i in 100:
		rules.award("melee_hit", 1.0, 0.0)
	assert_almost(rules.award("ranged_hit", 1.0, 0.0)["farm_mult"], 1.0, "стрельба не страдает от фарма ударов")


func test_weak_target_penalty_and_strong_bonus() -> void:
	var rules := _rules()
	assert_almost(rules.target_multiplier(1, 0), 1.0, "медляк для новичка — полностью")
	assert_almost(rules.target_multiplier(10, 7), 1.0, "в пределах 3 уровней — полностью")
	assert_almost(rules.target_multiplier(10, 2), 0.5, "на 8 ниже: 5 сверх допуска × 10%")
	assert_almost(rules.target_multiplier(30, 0), 0.05, "совсем слабая — 5%")
	assert_almost(rules.target_multiplier(2, 15), 1.5, "много сильнее — ×1.5")
	var hit: Dictionary = rules.award("melee_hit", 1.0, 0.0, {"hero_level": 10, "target_level": 2})
	assert_almost(hit["points"], 0.3, "0.6 × 0.5")


func test_sprint_hour_budget() -> void:
	var rules := _rules()
	var total := 0.0
	for i in 840:  # ~2 реальные минуты бега = игровой час
		total += rules.award("sprint_meter", 1.0, 480.0)["points"]
	assert_true(total > 45.0 and total < 52.0, "час непрерывного бега ≈ 49 очков вместо 84: %f" % total)


func test_save_roundtrip() -> void:
	var rules := _rules()
	rules.award("melee_hit", 30.0, 200.0)
	var back := _rules()
	back.load_dict(JSON.parse_string(JSON.stringify(rules.to_dict())))
	assert_almost(back.farm_multiplier("melee_hit"), rules.farm_multiplier("melee_hit"), "счётчики часа")
