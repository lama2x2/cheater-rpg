extends "res://tests/test_case.gd"
## Споровые мешки: docs/spec/06_trophies_items.md, 6.1; 7.1.

const LootTableScript := preload("res://src/core/loot_table.gd")
const ItemDBScript := preload("res://src/core/item_db.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _loot() -> LootTable:
	return LootTableScript.new([JsonDataScript.load_dict("res://data/loot/infected.json")])


func _average(table: String, frac: float, luck: float, item: String, runs: int = 1000) -> float:
	var loot := _loot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var total := 0
	for i in runs:
		total += int(loot.roll(table, frac, luck, rng).get(item, 0))
	return float(total) / runs


func test_every_sack_enemy_has_table_and_items_exist() -> void:
	var loot := _loot()
	var enemies: Array = JsonDataScript.load_dict("res://data/enemies/infected.json")["enemies"]
	for e: Dictionary in enemies:
		if e["spore_sack"]:
			assert_true(loot.has_table(e["loot"]), "%s: таблица %s" % [e["id"], e["loot"]])
	var files: Array = []
	for file in DirAccess.get_files_at("res://data/items"):
		if file.ends_with(".json"):
			files.append(JsonDataScript.load_dict("res://data/items".path_join(file)))
	var db := ItemDBScript.new(files)
	for table: Dictionary in JsonDataScript.load_dict("res://data/loot/infected.json")["tables"]:
		for row: Dictionary in table["rolls"]:
			var ids: Array = [row["item"]] if row.has("item") else row["one_of"].map(func(o: Dictionary) -> String: return o["item"])
			for id: String in ids:
				assert_true(db.has_item(id), "%s: нет предмета %s" % [table["id"], id])


func test_level_fraction() -> void:
	assert_almost(LootTableScript.level_fraction(10, [10, 20]), 0.0, "младший")
	assert_almost(LootTableScript.level_fraction(15, [10, 20]), 0.5, "середина")
	assert_almost(LootTableScript.level_fraction(0, [0, 0]), 0.0, "одноуровневая стадия")


func test_slowpoke_chance_grows_with_level() -> void:
	# споран 1–2 (в среднем 1.5) с шансом 10% у младшего и 100% у старшего
	var young := _average("loot_slowpoke", 0.0, 0.0, "sporan")
	var old := _average("loot_slowpoke", 1.0, 0.0, "sporan")
	assert_true(young > 0.08 and young < 0.25, "младший медляк ≈ 0.15 спорана: %f" % young)
	assert_true(old > 1.4 and old < 1.6, "старший ≈ 1.5: %f" % old)


func test_runner_distribution_matches_table() -> void:
	var sporan := _average("loot_runner", 0.5, 0.0, "sporan")
	var grain := _average("loot_runner", 0.5, 0.0, "grain")
	var nut := _average("loot_runner", 0.5, 0.0, "nut")
	assert_true(sporan > 5.8 and sporan < 6.2, "споран 4–8 ≈ 6: %f" % sporan)
	assert_true(grain > 1.85 and grain < 2.15, "зерно 1–3 ≈ 2: %f" % grain)
	assert_true(nut > 0.3 and nut < 0.4, "орех на середине стадии ≈ 35%%: %f" % nut)


func test_luck_raises_chances_with_cap() -> void:
	var loot := _loot()
	assert_almost(loot.luck_multiplier(0.0), 1.0, "без Удачи")
	assert_almost(loot.luck_multiplier(200.0), 1.5, "Удача 200 — ×1.5")
	assert_almost(loot.luck_multiplier(2000.0), 2.0, "потолок ×2")
	var plain := _average("loot_jumper", 0.0, 0.0, "grain")
	var lucky := _average("loot_jumper", 0.0, 400.0, "grain")
	assert_true(lucky > plain * 1.7, "Улыбка Фортуны (Удача ×20) почти удваивает зерно: %f → %f" % [plain, lucky])


func test_stomper_rare_variants() -> void:
	var loot := _loot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var counts := {"pea_yellow": 0, "pea_white": 0, "pea_gold": 0}
	for i in 1000:
		var drop := loot.roll("loot_stomper", 0.5, 0.0, rng)
		for id: String in counts:
			if drop.has(id):
				counts[id] += 1
	assert_true(counts["pea_yellow"] > counts["pea_white"] and counts["pea_white"] > counts["pea_gold"], "жёлтых больше белых, белых больше золотых: %s" % counts)
	assert_true(counts["pea_gold"] > 20 and counts["pea_gold"] < 90, "золотая ≈ 5%%: %d" % counts["pea_gold"])
