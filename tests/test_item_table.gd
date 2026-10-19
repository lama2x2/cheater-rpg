extends "res://tests/test_case.gd"
## Таблица предметов (12.8): строки, вкладки, поиск, сортировка, редкость, сравнение с надетым,
## «Взять всё» по ценности, хлам; деление кучи и перестановка ячеек в Inventory.

const ItemTableScript := preload("res://src/core/item_table.gd")
const ItemDBScript := preload("res://src/core/item_db.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const WeaponDBScript := preload("res://src/core/weapon_db.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _db() -> ItemDB:
	var files: Array = []
	for f in ["supplies", "trophies", "weapons"]:
		files.append(JsonDataScript.load_dict("res://data/items/%s.json" % f))
	return ItemDBScript.new(files)


func _table() -> ItemTable:
	return ItemTableScript.new(JsonDataScript.load_dict("res://data/ui.json"), _db())


func _inventory() -> Inventory:
	var inv := InventoryScript.new(_db(), JsonDataScript.load_dict("res://data/inventory.json"))
	inv.add("sporan", 20)
	inv.add("canned_food", 2)
	inv.add("brick", 1)
	inv.add("knife", 1)
	inv.add("bandage", 3)
	inv.add("vodka", 1)
	return inv


func _names() -> Dictionary:
	return {"sporan": "Споран", "canned_food": "Тушёнка", "brick": "Кирпич", "knife": "Нож", "bandage": "Бинт", "vodka": "Водка"}


func _ids(list: Array[Dictionary]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for r in list:
		ids.append(String(r["id"]))
	return ids


func test_rows_and_numbers() -> void:
	var rows := _table().rows(_inventory())
	var food: Dictionary = {}
	for r in rows:
		if r["id"] == "canned_food":
			food = r
	assert_eq(food["where"], ItemTable.BACKPACK, "тушёнка — в рюкзаке")
	assert_almost(float(food["weight_g"]), 800.0, "вес строки — за все штуки")
	assert_almost(float(food["price_kg"]), 2.5, "цена за кг — по штуке: 1 / 0,4 кг")
	assert_eq(rows[0]["where"], ItemTable.PRIMARY, "сначала ячейки Системы")


func test_tabs_and_search() -> void:
	var table := _table()
	var rows := table.rows(_inventory(), {"vodka": true})
	assert_eq(_ids(table.filter(rows, "weapons", "", _names())), PackedStringArray(["knife"]), "оружие")
	assert_eq(_ids(table.filter(rows, "medical", "", _names())), PackedStringArray(["bandage"]), "медицина")
	var junk := _ids(table.filter(rows, "junk", "", _names()))
	assert_true(junk.has("brick") and junk.has("vodka") and junk.size() == 2, "хлам — кирпич и помеченная водка: %s" % [junk])
	assert_eq(_ids(table.filter(rows, "all", "туш", _names())), PackedStringArray(["canned_food"]), "поиск без регистра")
	assert_eq(table.filter(rows, "all", "", _names()).size(), rows.size(), "всё")


func test_sorting() -> void:
	var table := _table()
	var rows := table.rows(_inventory())
	var by_weight := _ids(table.sorted(rows, "weight", true, _names()))
	assert_eq(by_weight[0], "brick", "тяжелее всех — кирпич")
	var by_price_kg := _ids(table.sorted(rows, "price_kg", true, _names()))
	assert_eq(by_price_kg[0], "sporan", "дороже за кг — споран (1 за грамм)")
	var by_name := _ids(table.sorted(rows, "name", false, _names()))
	assert_eq(by_name[0], "bandage", "по алфавиту: Бинт первый")
	assert_eq(_ids(table.sorted(rows, "name", true, _names()))[0], "canned_food", "обратно: Тушёнка первая")


func test_rarity_and_icons() -> void:
	var table := _table()
	assert_eq(table.rarity("brick"), "common", "кирпич — обычное")
	assert_eq(table.rarity("pea_white"), "rare", "белая горошина — редкое")
	assert_eq(table.rarity("pearl_black"), "epic", "жемчуг — эпическое")
	assert_eq(table.icon("knife"), "blade", "поле icon")
	assert_eq(table.icon("pea_yellow"), "orb", "по категории")


func test_compare_with_equipped() -> void:
	var table := _table()
	var weapons := WeaponDBScript.new(JsonDataScript.load_dict("res://data/weapons.json"))
	var noise := {"melee_hit": 3.0, "pistol": 60.0, "shotgun": 80.0}
	var axe_vs_knife := table.compare(weapons.weapon("axe"), weapons.weapon("knife"), noise)
	var signs := {}
	for c: Array in axe_vs_knife:
		signs[c[0]] = c[3]
	assert_eq(signs.get("damage"), 1, "топор бьёт сильнее ножа")
	assert_eq(signs.get("cooldown"), -1, "но медленнее")
	assert_eq(signs.get("noise"), 0, "шум тот же")
	var shotgun_vs_pistol := table.compare(weapons.weapon("shotgun"), weapons.weapon("pistol"), noise)
	for c: Array in shotgun_vs_pistol:
		if c[0] == "noise":
			assert_eq(c[3], -1, "дробовик громче пистолета — хуже")
		if c[0] == "pellets":
			assert_eq(c[3], 1, "дробин больше")
	assert_eq(table.compare(weapons.weapon("bow"), {}, noise), [], "нечего сравнивать — пусто")


func test_take_all_by_value() -> void:
	var table := _table()
	var inv := InventoryScript.new(_db(), JsonDataScript.load_dict("res://data/inventory.json"))
	inv.add("brick", 4)  # 14 кг из 15 — места почти нет
	var corpse := [{"id": "brick", "count": 5}, {"id": "gold_ring", "count": 1}, {"id": "canned_food", "count": 3}]
	var result := table.take_all(corpse, func(id: String, count: int) -> int: return int(inv.add(id, count)["left"]))
	assert_eq(String(result["taken"][0]["id"]), "gold_ring", "ценное за кг — первым")
	var left_ids := []
	for s: Dictionary in result["left"]:
		left_ids.append(s["id"])
	assert_true(left_ids.has("brick"), "кирпичи не влезли — остались: %s" % [result])
	assert_eq(inv.count_of("gold_ring"), 1, "кольцо у героя")


func test_junk_to_sell_only_backpack() -> void:
	var table := _table()
	var rows := table.rows(_inventory(), {"sporan": true})
	var sell := _ids(table.junk_to_sell(rows))
	assert_eq(sell, PackedStringArray(["brick"]), "споран в ячейках Системы не продаётся как хлам, кирпич — да")


func test_split_and_swap() -> void:
	var inv := InventoryScript.new(_db(), JsonDataScript.load_dict("res://data/inventory.json"))
	inv.add("sporan", 20)
	assert_true(inv.move_slot_to_backpack(0, 5), "переложить 5 из 20")
	assert_eq(int(inv.primary[0]["count"]), 15, "в ячейке 15")
	assert_eq(inv.backpack.size(), 1, "в рюкзаке куча")
	assert_eq(inv.move_backpack_to_primary("sporan", 2), 2, "вернуть 2")
	assert_eq(int(inv.primary[0]["count"]), 17, "в ячейке 17")
	inv.add_primary("gold_ring", 1)
	var ring_slot := 1
	inv.swap_slots(0, ring_slot)
	assert_eq(String(inv.primary[0]["id"]), "gold_ring", "кольцо в первой ячейке")
	assert_eq(String(inv.primary[1]["id"]), "sporan", "споран во второй")
