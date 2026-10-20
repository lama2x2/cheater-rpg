extends "res://tests/test_case.gd"
## Лог Системы (12.2, задача 16): у каждого сообщения из кода есть текст; вкладки, поиск, карточки.

const JsonDataScript := preload("res://src/core/json_data.gd")
const LogFilterScript := preload("res://src/core/log_filter.gd")
## Ключи, собираемые из частей в коде (consumed_ + глагол, risk_ + риск, spore_ + состояние).
const DYNAMIC_PREFIXES: PackedStringArray = ["consumed_", "risk_", "spore_"]


func _texts() -> Dictionary:
	var log: Dictionary = JsonDataScript.load_dict("res://data/text/ru.json")["log"].duplicate()
	for file in DirAccess.get_files_at("res://data/text"):
		if file.begins_with("ru_") and file.ends_with(".json"):
			log.merge(JsonDataScript.load_dict("res://data/text/" + file).get("log", {}), true)
	return log


func _sources(dir: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(FileAccess.get_file_as_string(dir.path_join(file)))
	for sub in DirAccess.get_directories_at(dir):
		_sources(dir.path_join(sub), out)


func test_every_posted_key_has_text() -> void:
	var texts := _texts()
	var sources: PackedStringArray = []
	_sources("res://src", sources)
	var regex := RegEx.new()
	regex.compile("SystemLog\\.post\\(\"([a-z0-9_]+)\"")
	var keys := {}
	for source in sources:
		for m in regex.search_all(source):
			keys[m.get_string(1)] = true
	assert_true(keys.size() > 80, "сообщений в коде много: %d" % keys.size())
	for key: String in keys:
		var dynamic := false
		for prefix in DYNAMIC_PREFIXES:
			dynamic = dynamic or key == prefix
		if dynamic:
			continue
		assert_true(texts.has(key) and (texts[key] as Array).size() > 0, "нет текста лога «%s»" % key)
	var total := 0
	for key: String in texts:
		total += (texts[key] as Array).size()
	assert_true(total >= 150, "вариантов текстов — не меньше 150: %d" % total)


func test_filter_tabs_and_search() -> void:
	var f := LogFilterScript.new(JsonDataScript.load_dict("res://data/log.json"))
	var history := [
		{"text": "Медляк готов.", "kind": "info", "minutes": 500.0, "key": "infected_killed"},
		{"text": "Сила — уровень 2.", "kind": "progress", "minutes": 510.0, "key": "stat_level_up"},
		{"text": "Кровотечение.", "kind": "warning", "minutes": 520.0, "key": "bleeding_started"},
		{"text": "Тайник обнаружен.", "kind": "special", "minutes": 530.0, "key": "stash_found"},
	]
	assert_eq(f.filter(history, "all", "").size(), 4, "всё")
	assert_eq(f.filter(history, "progress", "").size(), 1, "прогресс")
	assert_eq(f.filter(history, "warnings", "").size(), 1, "предупреждения")
	assert_eq(f.filter(history, "all", "ТАЙНИК").size(), 1, "поиск без регистра")
	assert_eq(LogFilter.stamp(1440.0 + 65.0), "Д2 01:05", "время сообщения")
	assert_true(f.is_card("general_level_up") and not f.is_card("item_picked"), "карточки — крупные события")
