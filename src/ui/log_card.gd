extends CanvasLayer
## Карточка крупного события лога (12.2): уровень, новое умение, куш, смена региона, таймер —
## крупно по центру сверху на несколько секунд, не мешая игре (клики проходят). Очередь — по одной.

var _queue: Array[Dictionary] = []
var _panel: PanelContainer
var _title: Label
var _text: Label
var _left := 0.0


func _ready() -> void:
	layer = 18
	add_to_group("hud_layers")
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.9)
	style.set_content_margin_all(18)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = UiKit.ACCENT
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position.y = 120
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_title = UiKit.label(15, UiKit.TEXT_DIM)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_text = UiKit.label(22, UiKit.ACCENT)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 560
	box.add_child(_text)
	SystemLog.entry_posted.connect(_on_entry)


func _on_entry(entry: Dictionary) -> void:
	if Content.log_filter().is_card(String(entry.get("key", ""))):
		_queue.append(entry)


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		_panel.modulate.a = clampf(_left / 0.6, 0.0, 1.0)
		if _left <= 0.0:
			_panel.visible = false
		return
	if _queue.is_empty():
		return
	var entry: Dictionary = _queue.pop_front()
	_title.text = Content.ui("log_card_title")
	_text.text = String(entry["text"])
	_text.add_theme_color_override("font_color", Content.log_filter().color(String(entry["kind"])))
	_panel.reset_size()
	var view := _panel.get_viewport_rect().size
	_text.custom_minimum_size.x = minf(560.0, view.x - 80.0)
	_panel.reset_size()
	_panel.position.x = (view.x - _panel.size.x) / 2.0
	_panel.visible = true
	_panel.modulate.a = 1.0
	_left = float(Content.log_filter().config()["card_s"])
