extends "res://tests/test_case.gd"
## Инвентарь: docs/spec/06_trophies_items.md, 6.3.

const ItemDBScript := preload("res://src/core/item_db.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _db() -> ItemDB:
	var files: Array = []
	for file in DirAccess.get_files_at("res://data/items"):
		if file.ends_with(".json"):
			files.append(JsonDataScript.load_dict("res://data/items".path_join(file)))
	return ItemDBScript.new(files)


func _inv(strength: int = 1) -> Inventory:
	return InventoryScript.new(_db(), JsonDataScript.load_dict("res://data/inventory.json"), strength)


func test_item_data_is_valid_and_named() -> void:
	var db := _db()
	assert_eq(db.errors(), PackedStringArray(), "схема предметов")
	var names: Dictionary = JsonDataScript.load_dict("res://data/text/ru.json")["item_names"]
	for id in db.ids():
		assert_true(names.has(id), "нет имени для «%s»" % id)


func test_primary_slots_hold_35_grams_each() -> void:
	var inv := _inv()
	assert_eq(inv.primary.size(), 3, "3 ячейки на старте")
	assert_eq(inv.primary_room("sporan"), 105, "3 × 35 спорана по 1 г")
	assert_eq(inv.primary_room("pearl_black"), 51, "3 × 17 жемчужин по 2 г")
	assert_eq(inv.add_primary("sporan", 40), 0, "40 споранов влезли")
	assert_eq(inv.primary[0], {"id": "sporan", "count": 35}, "первая ячейка полная")
	assert_eq(inv.primary[1], {"id": "sporan", "count": 5}, "остаток во второй")
	assert_eq(inv.primary_room("pearl_black"), 17, "под жемчуг осталась одна ячейка")


func test_primary_rejects_bulky_items() -> void:
	var inv := _inv()
	assert_eq(inv.primary_room("vodka"), 0, "водка не для ячеек")
	assert_eq(inv.add_primary("vodka", 1), 1, "не положилась")


func test_add_prefers_primary_then_backpack() -> void:
	var inv := _inv()
	var result := inv.add("sporan", 120)
	assert_eq(result, {"primary": 105, "backpack": 15, "left": 0}, "ячейки, потом рюкзак")
	assert_eq(inv.add("vodka", 2), {"primary": 0, "backpack": 2, "left": 0}, "водка — в рюкзак")
	assert_eq(inv.count_of("sporan"), 120, "всего споранов")


func test_remove_takes_backpack_first() -> void:
	var inv := _inv()
	inv.add("sporan", 110)  # 105 в ячейках, 5 в рюкзаке
	assert_true(inv.remove("sporan", 7), "списано")
	assert_eq(inv.backpack.size(), 0, "рюкзак опустел первым")
	assert_eq(inv.count_of("sporan"), 103, "из ячеек ушло 2")
	assert_true(not inv.remove("sporan", 1000), "столько нет")
	assert_eq(inv.count_of("sporan"), 103, "при неудаче ничего не тронуто")


func test_backpack_weight_and_overload() -> void:
	var inv := _inv()
	assert_almost(inv.backpack_capacity_kg(), 15.0, "15 кг при Силе 1")
	assert_almost(_inv(5).backpack_capacity_kg(), 21.0, "+1.5 кг за уровень Силы")
	inv.add("brick", 4)  # 14 кг
	assert_true(not inv.is_overloaded(), "14 из 15 — ещё нормально")
	assert_almost(inv.speed_multiplier(), 1.0, "без штрафа")
	inv.add("brick", 2)  # 21 кг → ratio 1.4
	assert_true(inv.is_overloaded(), "перегруз")
	assert_almost(inv.speed_multiplier(), 0.8, "скорость: 1 → 0.5 на двойном весе, 1.4 → 0.8")
	assert_almost(inv.stamina_cost_multiplier(), 1.4, "бодрость: 1 → 2 на двойном весе")


func test_hard_limit_double_capacity() -> void:
	var inv := _inv()
	var result := inv.add("brick", 10)  # 35 кг, предел 30
	assert_eq(result["backpack"], 8, "влезло 8 кирпичей (28 кг)")
	assert_eq(result["left"], 2, "2 не унести")


func test_moving_between_primary_and_backpack() -> void:
	var inv := _inv()
	inv.add_backpack("sporan", 50)
	assert_eq(inv.move_backpack_to_primary("sporan"), 50, "переложено в ячейки")
	assert_eq(inv.backpack.size(), 0, "рюкзак пуст")
	assert_true(inv.move_slot_to_backpack(0), "ячейка → рюкзак")
	assert_true(inv.primary[0].is_empty(), "ячейка освободилась")
	assert_eq(inv.count_of("sporan"), 50, "ничего не потерялось")


func test_death_keeps_primary_and_gives_backpack() -> void:
	var inv := _inv()
	inv.add("pearl_black", 1)
	inv.add("vodka", 1)
	var dropped := inv.take_backpack()
	assert_eq(dropped, [{"id": "vodka", "count": 1}], "рюкзак уходит на труп")
	assert_eq(inv.count_of("pearl_black"), 1, "жемчуг в ячейке остался")
	assert_almost(inv.backpack_weight_kg(), 0.0, "рюкзак пуст")


func test_save_roundtrip() -> void:
	var inv := _inv()
	inv.add("sporan", 40)
	inv.add("canned_food", 3)
	var back := _inv()
	back.load_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	assert_eq(back.to_dict(), inv.to_dict(), "содержимое после JSON")
	assert_eq(typeof(back.primary[0]["count"]), TYPE_INT, "количество — целое")
