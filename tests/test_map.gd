extends "res://tests/test_case.gd"
## Знание карты (12.6, D-72): посещение, увиденные постройки, купленная карта, отметки, сейв.

const MapKnowledgeScript := preload("res://src/core/map_knowledge.gd")
const RegionMapScript := preload("res://src/core/region_map.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")
const TrophyRulesScript := preload("res://src/core/trophy_rules.gd")
const ItemDBScript := preload("res://src/core/item_db.gd")


func _region() -> RegionMap:
	return RegionMapScript.new(JsonDataScript.load_dict("res://data/world/region.json"))


func test_region_states() -> void:
	var k := MapKnowledgeScript.new()
	var region := _region()
	assert_eq(k.region_state(region, "c_town"), MapKnowledge.UNKNOWN, "ничего не знаем")
	assert_true(k.visit("c_start"), "первое посещение")
	assert_true(not k.visit("c_start"), "второе — не новость")
	assert_eq(k.region_state(region, "c_start"), MapKnowledge.VISITED, "был")
	assert_eq(k.region_state(region, "c_village"), MapKnowledge.HEARD, "сосед — по табличке выхода")
	assert_eq(k.region_state(region, "c_town"), MapKnowledge.UNKNOWN, "дальше — туман")
	k.reveal("c_town")
	assert_eq(k.region_state(region, "c_town"), MapKnowledge.MAPPED, "куплена карта")


func test_buildings_seen_or_mapped() -> void:
	var k := MapKnowledgeScript.new()
	assert_true(not k.knows_building("c_village", 2), "не видел")
	assert_true(k.see_building("c_village", 2), "увидел впервые")
	assert_true(not k.see_building("c_village", 2), "второй раз — не новость")
	assert_true(k.knows_building("c_village", 2) and not k.knows_building("c_village", 3), "знаю только увиденное")
	assert_eq(k.seen_count("c_village"), 1, "счётчик")
	assert_true(k.reveal("c_village"), "карта — новое")
	assert_true(k.knows_building("c_village", 3), "с картой — все постройки")
	assert_true(not k.see_building("c_village", 5), "с картой увидеть — уже не новость")


func test_marks_toggle() -> void:
	var k := MapKnowledgeScript.new()
	assert_true(k.toggle_mark("c_start", Vector2(10, 5), 4.0), "поставил")
	assert_true(k.toggle_mark("c_start", Vector2(30, 5), 4.0), "вторая")
	assert_true(not k.toggle_mark("c_start", Vector2(11, 6), 4.0), "клик рядом — убрал")
	assert_eq(k.marks("c_start").size(), 1, "осталась одна")
	assert_true(k.toggle_region_mark("c_black") and not k.toggle_region_mark("c_black"), "отметка соты туда-обратно")


func test_save_round_trip() -> void:
	var k := MapKnowledgeScript.new()
	k.visit("c_start")
	k.see_building("c_start", 4)
	k.reveal("c_town")
	k.toggle_mark("c_start", Vector2(1, 2), 4.0)
	k.toggle_region_mark("c_black")
	var data: Dictionary = JSON.parse_string(JSON.stringify(k.to_dict()))
	var back := MapKnowledgeScript.new()
	back.load_dict(data)
	assert_true(back.is_visited("c_start") and back.knows_building("c_start", 4), "посещение и постройка")
	assert_true(back.is_mapped("c_town"), "карта")
	assert_eq(back.marks("c_start"), [Vector2(1, 2)] as Array[Vector2], "отметка")
	assert_true(back.region_marks.has("c_black"), "отметка соты")
	var empty := MapKnowledgeScript.new()
	empty.load_dict({})
	assert_true(not empty.is_visited("c_start"), "старый сейв без знания — пусто")


func test_unmapped_and_map_item() -> void:
	var k := MapKnowledgeScript.new()
	k.reveal("c_start")
	var left := k.unmapped(_region().ids())
	assert_eq(left.size(), 5, "без карты — пять")
	assert_true(not left.has("c_start"), "кроме купленной")
	var db := ItemDBScript.new([JsonDataScript.load_dict("res://data/items/supplies.json")])
	var trophies := TrophyRulesScript.new(db)
	assert_true(trophies.can_consume("cluster_map"), "карту можно прочитать")
	var result := trophies.resolve("cluster_map", 0.0, RandomNumberGenerator.new(), {})
	assert_eq(String(result["effects"][0]["type"]), "map_reveal", "эффект — открыть карту")
