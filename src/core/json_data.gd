class_name JsonData
extends RefCounted
## Чтение JSON-файлов из data/ с понятными ошибками.


static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Файл данных не найден: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Загружает словарь и проверяет, что в нём есть обязательные ключи.
static func load_dict(path: String, required_keys: PackedStringArray = []) -> Dictionary:
	var data: Variant = load_file(path)
	if not data is Dictionary:
		push_error("Ожидался объект JSON: %s" % path)
		return {}
	for key in required_keys:
		if not data.has(key):
			push_error("%s: нет обязательного ключа «%s»" % [path, key])
	return data
