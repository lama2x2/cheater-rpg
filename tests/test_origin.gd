extends "res://tests/test_case.gd"
## Происхождение (16, D-66–D-68, D-77): карточки, «Случайно», секретный вариант, куш из
## существующих предметов, окно новичка в приёме трофеев, «читер позже», миграция сейва v14.

const OriginRulesScript := preload("res://src/core/origin_rules.gd")
const TrophyRulesScript := preload("res://src/core/trophy_rules.gd")
const ItemDBScript := preload("res://src/core/item_db.gd")
const SaveFormatScript := preload("res://src/core/save_format.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> OriginRules:
	return OriginRulesScript.new(JsonDataScript.load_dict("res://data/origins.json"))


func _db() -> ItemDB:
	var files: Array = []
	for f in ["supplies", "trophies", "weapons"]:
		files.append(JsonDataScript.load_dict("res://data/items/%s.json" % f))
	return ItemDBScript.new(files)


func test_cards_hide_secret_and_later_variants() -> void:
	var ids := []
	for card in _rules().cards():
		ids.append(card["id"])
	assert_true(ids.size() >= 11, "карточек — все доступные в M1: %d" % ids.size())
	assert_true(not ids.has("three_pearls"), "секретный — не в карточках")
	assert_true(not ids.has("horde_tail") and not ids.has("freed_prisoner"), "M2–M3 — не в карточках")


func test_random_roll_and_secret_rate() -> void:
	var rules := _rules()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var secret := 0
	var seen := {}
	for i in 3000:
		var id := rules.roll(rng)
		seen[id] = true
		if id == "three_pearls":
			secret += 1
	assert_true(secret > 40 and secret < 160, "секретный ~3%%: %d из 3000" % secret)
	assert_true(not seen.has("horde_tail"), "недоступные не выпадают")
	assert_eq(rules.resolve_choice("pinned_elite", rng), "pinned_elite", "выбранный — он и есть")
	assert_true(rules.resolve_choice("horde_tail", rng) != "horde_tail", "недоступный выбор — случайный")


func test_grants_use_known_items() -> void:
	var db := _db()
	for v: Dictionary in JsonDataScript.load_dict("res://data/origins.json")["variants"]:
		assert_true(not (v["grants"] as Array).is_empty(), "%s: есть куш" % v["id"])
		assert_true(not (v["debt"] as Array).is_empty(), "%s: есть долг" % v["id"])
		assert_true(int(v["stars"]) >= 1 and int(v["stars"]) <= 3 and int(v["skulls"]) >= 1 and int(v["skulls"]) <= 3, "%s: ★ и ☠ 1–3" % v["id"])
		for g: Dictionary in v["grants"]:
			if g["type"] == "item":
				assert_true(db.has_item(String(g["id"])), "%s: предмет %s есть" % [v["id"], g["id"]])


func test_newbie_window_in_trophy_rules() -> void:
	var trophies := TrophyRulesScript.new(_db())
	var rng := RandomNumberGenerator.new()
	var ctx := {"skill_count": 0, "main_stats": PackedStringArray(["strength"]), "additional_stats": PackedStringArray(["luck"]),
		"vitals": ["health"], "newbie": true}
	trophies.resolve("pea_yellow", 0.0, rng, ctx)
	var risky := 0
	for i in 200:
		var r := trophies.resolve("pea_yellow", 10.0, rng, ctx)
		assert_true(not r["violation"], "в окне новичка нарушения нет")
		risky += (r["risks"] as PackedStringArray).size()
	assert_eq(risky, 0, "и риска кваза нет")
	ctx["newbie"] = false
	assert_true(trophies.resolve("pea_yellow", 20.0, rng, ctx)["violation"], "после окна — нарушение")


func test_newbie_window_and_later() -> void:
	var rules := _rules()
	var until := rules.newbie_until(480.0)
	assert_almost(until, 480.0 + 24.0 * 60.0, "24 игровых часа")
	assert_true(OriginRules.newbie_active(600.0, until), "в окне")
	assert_true(not OriginRules.newbie_active(600.0, until, true), "после крестин — нет")
	assert_true(not OriginRules.newbie_active(until + 1.0, until), "время вышло")
	assert_true(rules.counts_for_later("newbie_pearl"), "жемчуг в окне — «невозможное» событие")
	assert_true(not rules.later_reached(1) and rules.later_reached(2), "читер — со второго")


func test_save_migration_v14() -> void:
	var old := {"save_version": 13, "saved_at": 0, "meta": {}, "sections": {"player": {"lives": 5}}}
	var data := SaveFormatScript.migrate(old)
	assert_eq(int(data["save_version"]), SaveFormatScript.VERSION, "доведено")
	var origin: Dictionary = data["sections"]["player"]["origin"]
	assert_eq(String(origin["kind"]), "ordinary", "старые партии — Обычный")
	assert_almost(float(origin["newbie_until"]), 0.0, "окно новичка закрыто")
