class_name GazeRules
extends RefCounted
## Пристальный взгляд (12.3): сколько герой видит о цели — по Наблюдательности против Скрытности.
## Чистые правила: на вход — описание цели (subject) и Наблюдательность героя, на выход — карточка
## с полями, которые видно на этой глубине. Тексты подставляет интерфейс (src/ui/gaze_card.gd).
##
## subject: {"kind": "infected"|"npc"|"item"|"corpse", "category": "object"|"immune"|"red"|"thing",
##   "stealth": float, поля карточки ("name", "level", "level_range", "threat", "health" (0..1),
##   "state", "armor", "traits", "humanity", "equipment"…), "morok": {поля, которые морок подменяет}}.
## Данные — data/gaze.json.

const REQUIRED_KEYS: PackedStringArray = ["unavailable_at", "depth_at", "min_perception", "fields",
	"morok_pierce_depth", "health_words", "humanity", "range_m", "range_per_perception", "pick_px", "colors"]
const UNAVAILABLE := 0
const FULL_DEPTH := 3

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func config() -> Dictionary:
	return _config


## Глубина взгляда: 0 — «Информация недоступна», 1–3 — всё больше полей.
## bonus — прибавка глубины от умений (Глубокий взгляд), не поднимает выше 3 и не пробивает 0.
func depth(perception: float, stealth: float, bonus: int = 0) -> int:
	var ratio := maxf(stealth, 0.0) / maxf(perception, float(_config["min_perception"]))
	if ratio >= float(_config["unavailable_at"]):
		return UNAVAILABLE
	var result := 1
	for threshold: float in _config["depth_at"]:
		if ratio < float(threshold):
			result += 1
	return mini(result + bonus, FULL_DEPTH)


## Дальность взгляда в метрах.
func range_m(perception_level: int) -> float:
	return float(_config["range_m"]) + float(_config["range_per_perception"]) * maxi(perception_level - 1, 0)


## Карточка: {"depth", "category", "unavailable", "morok" (морок раскрыт), "fields": [[ключ, значение], …]}.
## Поля идут в порядке data/gaze.json → fields; точный уровень заменяет диапазон.
func card(subject: Dictionary, perception: float, bonus: int = 0) -> Dictionary:
	var stealth := float(subject.get("stealth", 0.0))
	var d := FULL_DEPTH if String(subject.get("kind", "")) == "item" else depth(perception, stealth, bonus)
	var shown := subject.duplicate(true)
	var morok: Dictionary = subject.get("morok", {})
	var pierced := false
	if not morok.is_empty():
		if d >= int(_config["morok_pierce_depth"]):
			pierced = true
		else:
			shown.merge(morok, true)
	var result := {"depth": d, "category": String(shown.get("category", "object")),
		"unavailable": d == UNAVAILABLE, "morok": pierced, "fields": []}
	if d == UNAVAILABLE:
		return result
	var fields: Dictionary = _config["fields"]
	for key: String in fields:
		if not shown.has(key) or d < int(fields[key]):
			continue
		if key == "level_range" and d >= int(fields["level"]) and shown.has("level"):
			continue
		var value: Variant = shown[key]
		if key == "health":
			value = health_word(float(value))
		elif key == "humanity":
			value = humanity_word(int(value))
		if value is Array and (value as Array).is_empty():
			continue
		if value is Dictionary and (value as Dictionary).is_empty():
			continue
		result["fields"].append([key, value])
	return result


## Слово о здоровье по доле (ключ текста): «невредим», «ранен», «тяжело ранен», «при смерти».
func health_word(fraction: float) -> String:
	for entry: Array in _config["health_words"]:
		if fraction >= float(entry[0]):
			return String(entry[1])
	return String((_config["health_words"] as Array).back()[1])


## Гуманность словом (3.4): высокая («зелёный»), обычная, «красный».
func humanity_word(value: int) -> String:
	var h: Dictionary = _config["humanity"]
	if value >= int(h["green_at"]):
		return "humanity_green"
	if value <= int(h["red_at"]):
		return "humanity_red"
	return "humanity_normal"


func color(category: String) -> Color:
	var colors: Dictionary = _config["colors"]
	var c: Array = colors.get(category, colors["object"])
	return Color(float(c[0]), float(c[1]), float(c[2]))
