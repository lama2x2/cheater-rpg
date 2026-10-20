class_name LogFilter
extends RefCounted
## Лог Системы (12.2): вкладки по видам сообщений и поиск по тексту — для окна истории.
## Чистые правила; данные — data/log.json.

const REQUIRED_KEYS: PackedStringArray = ["hud_lines", "tabs", "kind_colors", "cards", "card_s", "low_health", "low_health_recover"]

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func config() -> Dictionary:
	return _config


func tab_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for t: Dictionary in _config["tabs"]:
		ids.append(String(t["id"]))
	return ids


## Сообщения вкладки tab, где есть search (без регистра). Порядок — как в истории.
func filter(history: Array, tab: String, search: String) -> Array:
	var kinds: Array = []
	for t: Dictionary in _config["tabs"]:
		if String(t["id"]) == tab:
			kinds = t["kinds"]
	var needle := search.strip_edges().to_lower()
	var result: Array = []
	for entry: Dictionary in history:
		if not kinds.is_empty() and not kinds.has(String(entry["kind"])):
			continue
		if not needle.is_empty() and not String(entry["text"]).to_lower().contains(needle):
			continue
		result.append(entry)
	return result


func color(kind: String) -> Color:
	var colors: Dictionary = _config["kind_colors"]
	var c: Array = colors.get(kind, colors["info"])
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Показывать ли сообщение ещё и карточкой (крупное событие).
func is_card(key: String) -> bool:
	return (_config["cards"] as Array).has(key)


## Время сообщения для истории: «Д2 14:05».
static func stamp(minutes: float) -> String:
	var total := int(minutes)
	return "Д%d %02d:%02d" % [total / 1440 + 1, (total / 60) % 24, total % 60]
