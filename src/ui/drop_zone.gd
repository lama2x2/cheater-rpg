class_name DropZone
extends PanelContainer
## Область, куда можно бросить перетаскиваемый предмет (12.8): рюкзак, ячейки, быстрый слот,
## контейнер. Подсвечивается, когда над ней тащат предмет.

signal dropped(data: Dictionary)
## Правый клик по области (быстрый слот — очистить).
signal right_clicked

var accepts: Callable = func(_data: Dictionary) -> bool: return true
var _style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0, 0, 0, 0.18)
	_style.set_content_margin_all(4)
	_style.set_corner_radius_all(3)
	_style.set_border_width_all(1)
	_style.border_color = Color(0.5, 0.55, 0.5, 0.25)
	add_theme_stylebox_override("panel", _style)


func _can_drop_data(_at: Vector2, value: Variant) -> bool:
	var ok := value is Dictionary and String(value.get("type", "")) == "item" and bool(accepts.call(value))
	_style.border_color = Color(0.95, 0.85, 0.5, 0.9) if ok else Color(0.5, 0.55, 0.5, 0.25)
	return ok


func _drop_data(_at: Vector2, value: Variant) -> void:
	_style.border_color = Color(0.5, 0.55, 0.5, 0.25)
	dropped.emit(value)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_style.border_color = Color(0.5, 0.55, 0.5, 0.25)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()
		accept_event()
