extends CanvasLayer
## Отладочный HUD этапа M0: жизни, уровень, время, Скорость и последние строки лога Системы.

const LOG_LINES := 6

var _status: Label
var _log: Label
var _lines: PackedStringArray = []


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New"])

	_status = _label(font)
	_status.position = Vector2(16, 16)
	add_child(_status)

	_log = _label(font)
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = 16
	_log.offset_top = -16
	_log.offset_bottom = -16
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_log)

	_reload_log()
	SystemLog.message_posted.connect(func(text: String, _kind: String) -> void: _push(text))
	SystemLog.history_replaced.connect(_reload_log)


func _process(_delta: float) -> void:
	var stats := PlayerState.stats
	_status.text = "Жизни: %d    Уровень: %d    %s\nСкорость: %d  (%.1f / %.0f)\n\n[WASD] идти  [Shift] бежать  [колесо] зум  [K] умереть  [F5/F9] сохранить/загрузить (отладка)" % [
		PlayerState.lives, stats.general_level(), GameClock.clock_text(),
		stats.get_level("speed"), stats.get_progress("speed"), stats.threshold("speed"),
	]


func _reload_log() -> void:
	_lines.clear()
	for entry in SystemLog.history:
		_push(entry["text"])


func _push(text: String) -> void:
	_lines.append("› " + text)
	if _lines.size() > LOG_LINES:
		_lines = _lines.slice(_lines.size() - LOG_LINES)
	_log.text = "\n".join(_lines)


func _label(font: Font) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return label
