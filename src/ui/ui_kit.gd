class_name UiKit
extends RefCounted
## Общие кирпичики интерфейса: шрифт и подписи в стиле лога Системы.

static var _font: Font


static func font() -> Font:
	if _font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New"])
		_font = system_font
	return _font


static func label(size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", maxi(4, size / 4))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return label
