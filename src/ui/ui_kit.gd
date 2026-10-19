class_name UiKit
extends RefCounted
## Общие кирпичики интерфейса (12.8): шрифт, подписи в стиле лога Системы, общая тема окон
## («интерфейс Системы»: тёмные полупрозрачные панели, холодный текст, кнопки с наведением,
## нажатием и фокусом, полосы прокрутки, подсказки) и стек открытых окон — Esc закрывает верхнее.
## Контрастный режим (настройка) делает панели непрозрачными.

const TEXT := Color(0.88, 0.9, 0.87)
const TEXT_DIM := Color(0.62, 0.66, 0.64)
const ACCENT := Color(0.95, 0.78, 0.3)
const GOOD := Color(0.45, 0.85, 0.45)
const BAD := Color(0.95, 0.4, 0.35)
const PANEL_ALPHA := 0.92

static var _font: Font
static var _theme: Theme
static var _panel: StyleBoxFlat
## В поле ввода (поиск) печатают — герой не ходит от WASD (src/actors/player.gd).
static var typing := false
## Открытые окна, последнее — сверху.
static var _windows: Array[Node] = []


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


## Общий фон окон (один объект на все окна — контрастный режим меняет его сразу везде).
static func panel_style() -> StyleBoxFlat:
	if _panel == null:
		_panel = _box(Color(0.05, 0.06, 0.07, PANEL_ALPHA), 16, 4)
		_panel.set_border_width_all(1)
		_panel.border_color = Color(0.55, 0.62, 0.6, 0.35)
	return _panel


## Панель окна с общим фоном.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p


static func set_contrast(on: bool) -> void:
	panel_style().bg_color.a = 1.0 if on else PANEL_ALPHA
	panel_style().border_color.a = 0.9 if on else 0.35


## Тема на всё дерево: кнопки, поля ввода, меню, подсказки, прокрутка, полосы.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 15
	var normal := _box(Color(0.12, 0.14, 0.15, 0.95), 6, 3)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.4, 0.45, 0.45, 0.6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.24, 0.24, 0.98)
	hover.border_color = Color(0.75, 0.68, 0.4, 0.9)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.32, 0.28, 0.14, 1.0)
	pressed.border_color = ACCENT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.09, 0.1, 0.8)
	disabled.border_color = Color(0.3, 0.3, 0.3, 0.4)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = Color(0.95, 0.85, 0.5, 0.9)
	focus.set_corner_radius_all(3)
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 0.95, 0.8))
		t.set_color("font_pressed_color", type, Color(1, 0.92, 0.6))
		t.set_color("font_disabled_color", type, Color(0.5, 0.52, 0.5))
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var popup := _box(Color(0.06, 0.07, 0.08, 0.98), 6, 3)
	popup.set_border_width_all(1)
	popup.border_color = Color(0.6, 0.62, 0.5, 0.7)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.95, 0.8))
	t.set_stylebox("panel", "TooltipPanel", popup)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)
	var field := _box(Color(0.02, 0.03, 0.03, 0.95), 6, 3)
	field.set_border_width_all(1)
	field.border_color = Color(0.4, 0.45, 0.45, 0.7)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _box(Color(0.03, 0.04, 0.04, 0.6), 2, 3))
		t.set_stylebox("grabber", bar, _box(Color(0.4, 0.45, 0.42, 0.8), 2, 3))
		t.set_stylebox("grabber_highlight", bar, _box(Color(0.75, 0.68, 0.4, 0.9), 2, 3))
		t.set_stylebox("grabber_pressed", bar, _box(ACCENT, 2, 3))
	var bar_bg := _box(Color(0.2, 0.22, 0.22, 0.95), 0, 2)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(0.5, 0.55, 0.5, 0.6)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", _box(Color(0.55, 0.7, 0.5, 0.95), 0, 2))
	t.set_color("font_color", "Label", TEXT)
	_theme = t
	return t


static func _box(color: Color, margin: float, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(radius)
	return box


## Заголовок окна: название, подсказка клавиши закрытия и крестик.
static func header(title: String, key_hint: String, on_close: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := label(18, ACCENT)
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	if not key_hint.is_empty():
		var hint := label(13, TEXT_DIM)
		hint.text = key_hint
		row.add_child(hint)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = Content.ui("ui_close_hint")
	close.pressed.connect(on_close)
	row.add_child(close)
	return row


## Полоса «сколько из скольких» (прогресс, шкала): рисуется кодом, цвет заполнения — color.
static func bar(value: float, max_value: float, color: Color, size: Vector2 = Vector2(200, 12)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, c.size)
		c.draw_rect(r, Color(0.2, 0.22, 0.22, 0.95))
		var ratio := clampf(value / maxf(max_value, 0.0001), 0.0, 1.0)
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(c.size.x * ratio, c.size.y)), color)
		c.draw_rect(r, Color(0.5, 0.55, 0.5, 0.6), false, 1.0))
	return c


## Кнопка с подписью и действием (шрифт и стиль — из темы).
static func button(text: String, action: Callable, size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(action)
	return b


## Непрозрачность HUD (настройка): слои группы hud_layers — их верхние элементы.
static func apply_hud_opacity(tree: SceneTree, value: float) -> void:
	if tree == null:
		return
	for layer in tree.get_nodes_in_group("hud_layers"):
		for child in layer.get_children():
			if child is CanvasItem:
				(child as CanvasItem).modulate.a = value


# --- Стек окон ---------------------------------------------------------------------------------

## Окно открылось — наверх стека. У окна должен быть метод close().
static func window_opened(window: Node) -> void:
	_windows.erase(window)
	_windows.append(window)


static func window_closed(window: Node) -> void:
	_windows.erase(window)


## Esc: закрыть верхнее открытое окно. false — открытых окон нет (тогда Esc открывает меню).
static func close_top() -> bool:
	while not _windows.is_empty():
		var top: Node = _windows.pop_back()
		if is_instance_valid(top) and top.is_inside_tree() and bool(top.get("visible")):
			top.close()
			return true
	return false


static func open_windows() -> int:
	var n := 0
	for w in _windows:
		if is_instance_valid(w) and w.is_inside_tree() and bool(w.get("visible")):
			n += 1
	return n
