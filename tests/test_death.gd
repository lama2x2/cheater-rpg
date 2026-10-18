extends "res://tests/test_case.gd"
## Смерть и возрождение: docs/spec/04_death_lives.md.

const DeathRulesScript := preload("res://src/core/death_rules.gd")
const RunStatsScript := preload("res://src/core/run_stats.gd")
const SaveFormatScript := preload("res://src/core/save_format.gd")
const GameClockScript := preload("res://src/services/game_clock.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _config() -> Dictionary:
	return JsonDataScript.load_dict("res://data/death.json")


func test_respawn_seconds_in_range_and_fast_mode() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 300:
		var s := DeathRulesScript.respawn_seconds(_config(), rng)
		assert_true(s >= 100.0 and s <= 180.0, "%f в 100–180" % s)
	assert_almost(DeathRulesScript.respawn_seconds(_config(), rng, true), 5.0, "отладка — 5 с")


func test_game_time_away_is_hours() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 100:
		var m := DeathRulesScript.game_minutes_away(_config(), rng)
		assert_true(m >= 120.0 and m <= 300.0, "%f мин в 2–5 ч" % m)


func test_region_shift_every_n_deaths() -> void:
	assert_true(not DeathRulesScript.region_shift_due(4, 5), "4 из 5 — рано")
	assert_true(DeathRulesScript.region_shift_due(5, 5), "5 из 5 — пора")
	assert_true(not DeathRulesScript.region_shift_due(5, 0), "0 — смена выключена")


func test_highlights_priority_recency_and_no_duplicates() -> void:
	var entries := [
		{"text": "ур 2", "kind": "progress"},
		{"text": "смерть 1", "kind": "death"},
		{"text": "переброс", "kind": "special"},
		{"text": "ур 3", "kind": "progress"},
		{"text": "смерть 1", "kind": "death"},
		{"text": "мелочь", "kind": "info"},
		{"text": "смерть 2", "kind": "death"},
	]
	var config := _config().duplicate()
	config["highlight_kinds"] = ["special", "progress", "death"]
	config["summary_highlights"] = 4
	var picked := DeathRulesScript.pick_highlights(entries, config)
	assert_eq(picked, PackedStringArray(["переброс", "ур 3", "ур 2", "смерть 2"]), "порядок и лимит")
	config["summary_highlights"] = 10
	picked = DeathRulesScript.pick_highlights(entries, config)
	assert_eq(picked.size(), 5, "повтор «смерть 1» не дублируется, «мелочь» не берётся")


func test_run_stats_causes_and_longest_life() -> void:
	var run := RunStatsScript.new()
	run.record_death(1, "health", 600.0, 1)
	run.record_death(2, "spore_balance", 700.0, 1)
	run.record_death(3, "health", 1500.0, 2)
	assert_eq(run.causes_ranked(), [["health", 2], ["spore_balance", 1]], "частые причины")
	assert_almost(run.longest_life_minutes(480.0), 800.0, "самая долгая — третья жизнь")
	run.add("kills")
	run.add("kills", 2)
	assert_eq(run.count("kills"), 3, "счётчик")


func test_run_stats_roundtrip() -> void:
	var run := RunStatsScript.new()
	run.record_death(1, "health", 600.5, 1)
	run.add("kills", 4)
	var back := RunStatsScript.new()
	back.load_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
	assert_eq(back.to_dict(), run.to_dict(), "статистика после JSON")
	assert_eq(typeof(back.deaths[0]["life"]), TYPE_INT, "номер жизни — целое")


func test_v2_save_gets_death_defaults() -> void:
	var v2 := {"save_version": 2, "sections": {"player": {"lives": 7}, "log": {"history": []}}}
	var result := SaveFormatScript.migrate(v2)
	var player: Dictionary = result["sections"]["player"]
	assert_eq(player["awaiting_respawn"], false, "не ждёт возрождения")
	assert_eq(int(player["lives"]), 7, "старые поля не тронуты")
	assert_eq(result["sections"]["log"]["highlights"], [], "пустые лучшие моменты")


func test_clock_advance_emits_each_hour() -> void:
	var clock: Node = GameClockScript.new()
	clock.minutes = 23.0 * 60.0 + 30.0
	var hours: Array = []
	clock.hour_passed.connect(func(hour: int, day: int) -> void: hours.append([hour, day]))
	clock.advance(150.0)  # 23:30 → 02:00 следующего дня
	assert_eq(hours, [[0, 2], [1, 2], [2, 2]], "часы и день")
	clock.free()
