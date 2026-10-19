extends "res://tests/test_case.gd"
## Пристальный взгляд (12.3): глубина по Наблюдательности против Скрытности, поля, морок.

const GazeRulesScript := preload("res://src/core/gaze_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> GazeRules:
	return GazeRulesScript.new(JsonDataScript.load_dict("res://data/gaze.json"))


func _keys(card: Dictionary) -> PackedStringArray:
	var keys: PackedStringArray = []
	for field: Array in card["fields"]:
		keys.append(String(field[0]))
	return keys


func _runner() -> Dictionary:
	return {"kind": "infected", "category": "object", "name": "бегун", "stealth": 2.0, "level": 14,
		"level_range": [10, 20], "threat": "medium", "health": 0.5, "state": "chase",
		"armor": {"torso": 2.0}, "traits": ["trait_lunge"], "hunger": 0.3}


func test_depth_by_ratio() -> void:
	var rules := _rules()
	assert_eq(rules.depth(1.0, 1.5), 0, "Скрытность ≥ 1,5 × Наблюдательности — ничего")
	assert_eq(rules.depth(1.0, 1.49), 1, "чуть ниже порога — самое общее")
	assert_eq(rules.depth(2.0, 1.0), 2, "вдвое выше — точнее")
	assert_eq(rules.depth(5.0, 2.0), 3, "намного выше — всё")
	assert_eq(rules.depth(1.0, 0.0), 3, "без Скрытности — всё")
	assert_eq(rules.depth(1.0, 1.2, 1), 2, "бонус умения поднимает глубину")
	assert_eq(rules.depth(1.0, 2.0, 2), 0, "но не пробивает «недоступно»")
	assert_eq(rules.depth(0.0, 0.2), 3, "нулевая Наблюдательность не делит на ноль")


func test_unavailable_card_is_empty() -> void:
	var card := _rules().card(_runner(), 1.0)
	assert_true(card["unavailable"], "бегун со Скрытностью 2 при Наблюдательности 1 — недоступно")
	assert_eq(card["fields"].size(), 0, "полей нет")


func test_fields_grow_with_depth() -> void:
	var rules := _rules()
	var shallow := _keys(rules.card(_runner(), 1.5))
	assert_true("level_range" in shallow and not "level" in shallow, "глубина 1 — диапазон уровня: %s" % [shallow])
	assert_true("threat" in shallow and not "health" in shallow and not "armor" in shallow, "без здоровья и брони")
	var middle := _keys(rules.card(_runner(), 3.0))
	assert_true("level" in middle and not "level_range" in middle, "глубина 2 — точный уровень вместо диапазона")
	assert_true("health" in middle and "state" in middle and not "armor" in middle, "здоровье и состояние, брони нет")
	var deep := _keys(rules.card(_runner(), 10.0))
	assert_true("armor" in deep and "traits" in deep and "hunger" in deep, "глубина 3 — броня и особенности")


func test_health_and_humanity_words() -> void:
	var rules := _rules()
	assert_eq(rules.health_word(1.0), "health_full", "полное")
	assert_eq(rules.health_word(0.7), "health_hurt", "ранен")
	assert_eq(rules.health_word(0.1), "health_dying", "при смерти")
	assert_eq(rules.humanity_word(900), "humanity_green", "высокая")
	assert_eq(rules.humanity_word(100), "humanity_normal", "обычная")
	assert_eq(rules.humanity_word(-5), "humanity_red", "«красный»")
	var card := rules.card({"kind": "npc", "category": "immune", "name": "Гусь", "humanity": 900, "health": 1.0}, 1.0)
	var values := {}
	for field: Array in card["fields"]:
		values[field[0]] = field[1]
	assert_eq(values.get("humanity"), "humanity_green", "в карточке — слово, не число")


func test_morok() -> void:
	var rules := _rules()
	var npc := {"kind": "npc", "category": "immune", "name": "Гусь", "stealth": 2.0, "level": 41,
		"equipment": ["pistol"], "morok": {"level": 3, "equipment": []}}
	var fooled := rules.card(npc, 3.0)
	var level := -1
	for field: Array in fooled["fields"]:
		if field[0] == "level":
			level = int(field[1])
		assert_true(field[0] != "equipment", "морок прячет снаряжение")
	assert_eq(level, 3, "морок показывает ложный уровень")
	assert_true(not fooled["morok"], "морок не раскрыт")
	var pierced := rules.card(npc, 10.0)
	assert_true(pierced["morok"], "глубина 3 пробивает морок")
	for field: Array in pierced["fields"]:
		if field[0] == "level":
			assert_eq(int(field[1]), 41, "настоящий уровень")


func test_items_always_full() -> void:
	var card := _rules().card({"kind": "item", "category": "thing", "name": "бинт", "stealth": 99.0, "weight": 50.0}, 0.0)
	assert_eq(card["depth"], 3, "предмет виден целиком")
	assert_true("weight" in _keys(card), "вес")


func test_range_grows_with_perception() -> void:
	var rules := _rules()
	assert_true(rules.range_m(5) > rules.range_m(1), "дальше с Наблюдательностью")


func test_infected_have_stealth() -> void:
	var data := JsonDataScript.load_dict("res://data/enemies/infected.json")
	for enemy: Dictionary in data["enemies"]:
		assert_true(enemy["senses"].has("stealth"), "%s: есть Скрытность" % enemy["id"])
