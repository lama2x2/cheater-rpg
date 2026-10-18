extends Node
## Лог Системы: выбирает вариант текста по ключу, хранит историю, сообщает интерфейсу.

signal message_posted(text: String, kind: String)
signal history_replaced

## Сколько последних сообщений попадает в сохранение.
const SAVED_HISTORY := 200

var history: Array[Dictionary] = []
## «Лучшие моменты» для экрана итогов: сообщения видов из death.json/highlight_kinds, без лимита (D-37).
var highlights: Array[Dictionary] = []
var _last_variant: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func post(key: String, params: Dictionary = {}, kind: String = "info") -> String:
	var text := _pick_variant(key).format(params)
	var entry := {"text": text, "kind": kind, "minutes": GameClock.minutes}
	history.append(entry)
	if Content.death_config()["highlight_kinds"].has(kind):
		highlights.append(entry)
	message_posted.emit(text, kind)
	return text


func to_dict() -> Dictionary:
	return {"history": history.slice(maxi(0, history.size() - SAVED_HISTORY)), "highlights": highlights.duplicate()}


func load_dict(data: Dictionary) -> void:
	history.clear()
	for entry: Dictionary in data["history"]:
		history.append(_entry(entry))
	highlights.clear()
	for entry: Dictionary in data["highlights"]:
		highlights.append(_entry(entry))
	history_replaced.emit()


func _entry(data: Dictionary) -> Dictionary:
	return {"text": String(data["text"]), "kind": String(data["kind"]), "minutes": float(data["minutes"])}


func has_key(key: String) -> bool:
	return Content.texts()["log"].has(key)


## Случайный вариант без повтора предыдущего для того же ключа.
func _pick_variant(key: String) -> String:
	var variants: Array = Content.texts()["log"].get(key, [])
	if variants.is_empty():
		push_warning("Нет текста лога для ключа «%s»" % key)
		return key
	var index := _rng.randi_range(0, variants.size() - 1)
	if variants.size() > 1 and index == _last_variant.get(key, -1):
		index = (index + 1) % variants.size()
	_last_variant[key] = index
	return String(variants[index])
