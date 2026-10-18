extends "res://tests/test_case.gd"
## Все файлы data/ — валидный JSON, тексты есть для всех характеристик.

const JsonDataScript := preload("res://src/core/json_data.gd")


func test_all_json_parse() -> void:
	for path in _json_files("res://data"):
		assert_true(JsonDataScript.load_file(path) != null, path)


func test_every_stat_has_a_name() -> void:
	var stats: Dictionary = JsonDataScript.load_dict("res://data/stats.json")
	var names: Dictionary = JsonDataScript.load_dict("res://data/text/ru.json")["stat_names"]
	for stat: String in stats["main"] + stats["additional"]:
		assert_true(names.has(stat), "нет имени для «%s»" % stat)


func _json_files(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			result.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_json_files(dir.path_join(sub)))
	return result
