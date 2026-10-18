class_name ItemDB
extends RefCounted
## Справочник предметов из data/items/*.json. Чистый класс без Node.
## Схема — docs/spec/14_content_data.md, 14.4.

const REQUIRED_ITEM_KEYS: PackedStringArray = ["id", "category", "weight_g", "primary_inventory", "base_price"]

var _items: Dictionary = {}


## files — содержимое файлов: [{"items": [...]}, ...]. Ошибки схемы — в errors().
func _init(files: Array = []) -> void:
	for file: Dictionary in files:
		for item: Dictionary in file.get("items", []):
			_items[String(item.get("id", ""))] = item


## Проверка схемы: пустой массив — всё хорошо.
func errors() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in _items:
		var item: Dictionary = _items[id]
		for key in REQUIRED_ITEM_KEYS:
			if not item.has(key):
				result.append("%s: нет ключа «%s»" % [id, key])
		if id.is_empty():
			result.append("предмет без id")
		elif float(item.get("weight_g", 0)) <= 0.0:
			result.append("%s: вес должен быть > 0" % id)
	return result


func ids() -> PackedStringArray:
	return PackedStringArray(_items.keys())


func has_item(id: String) -> bool:
	return _items.has(id)


func item(id: String) -> Dictionary:
	assert(_items.has(id), "Неизвестный предмет: %s" % id)
	return _items[id]


func weight_g(id: String) -> float:
	return float(item(id)["weight_g"])


func allowed_in_primary(id: String) -> bool:
	return bool(item(id)["primary_inventory"])


func category(id: String) -> String:
	return String(item(id)["category"])
