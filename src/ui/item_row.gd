class_name ItemRow
extends PanelContainer
## Строка таблицы предметов (12.8): иконка, название, кол-во, вес, цена, цена за кг. Двойной клик
## (или Enter) — главное действие, ПКМ — меню действий, Ctrl+клик — переложить строку целиком,
## перетаскивание (Shift — половину кучи). Подсказка со сравнением — через _make_custom_tooltip.
## Строка без предмета — пустая ячейка Системы (только цель перетаскивания).

signal activated(row: ItemRow)
signal context_requested(row: ItemRow, at: Vector2)
signal ctrl_clicked(row: ItemRow)
## На строку бросили перетаскиваемое: data — словарь из _get_drag_data другой строки.
signal dropped(row: ItemRow, data: Dictionary)

const WIDTHS := {"count": 52, "weight": 80, "price": 62, "price_kg": 78}

var data: Dictionary = {}
## Где лежит строка: primary (ячейка slot), backpack, container, quick (быстрый слот slot).
var where := ""
var slot := -1
var _hover := false
var _style: StyleBoxFlat


static func make(row_data: Dictionary, columns: bool, extra: String = "") -> ItemRow:
	var row := ItemRow.new()
	row.data = row_data
	row.where = String(row_data.get("where", ""))
	row.slot = int(row_data.get("slot", -1))
	row._build(columns, extra)
	return row


func _build(columns: bool, extra: String) -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(1, 1, 1, 0.0)
	_style.set_content_margin_all(2)
	_style.content_margin_left = 4
	_style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", _style)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var id := String(data.get("id", ""))
	box.add_child(ItemIcon.make(id, 24.0))
	var name := UiKit.label(14, UiKit.TEXT_DIM if bool(data.get("junk", false)) else UiKit.TEXT)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text = (Content.item_name(id) if not id.is_empty() else Content.ui("inv_slot_empty")) + extra
	box.add_child(name)
	if id.is_empty():
		tooltip_text = ""
		return
	tooltip_text = " "  # подсказку строит _make_custom_tooltip
	if columns:
		_cell(box, "count", "×%d" % int(data["count"]))
		_cell(box, "weight", ItemTooltip._grams(float(data["weight_g"])))
		_cell(box, "price", str(int(data["price"])))
		_cell(box, "price_kg", str(roundi(float(data["price_kg"]))))
	else:
		_cell(box, "count", "×%d" % int(data["count"]))


func _cell(box: HBoxContainer, key: String, text: String) -> void:
	var label := UiKit.label(13, UiKit.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size.x = WIDTHS[key]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.text = text
	box.add_child(label)


func item_id() -> String:
	return String(data.get("id", ""))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			_paint()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_paint()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			_paint()


func _paint() -> void:
	_style.bg_color = Color(0.95, 0.85, 0.5, 0.16) if _hover or has_focus() else Color(1, 1, 1, 0.0)


func _gui_input(event: InputEvent) -> void:
	if item_id().is_empty():
		return
	var click := event as InputEventMouseButton
	if click and click.pressed:
		if click.button_index == MOUSE_BUTTON_LEFT and click.double_click:
			activated.emit(self)
			accept_event()
		elif click.button_index == MOUSE_BUTTON_LEFT and click.ctrl_pressed:
			ctrl_clicked.emit(self)
			accept_event()
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(self, click.global_position)
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		activated.emit(self)
		accept_event()


func _make_custom_tooltip(_for_text: String) -> Object:
	if item_id().is_empty():
		return null
	return ItemTooltip.build(item_id(), int(data.get("count", 1)))


func _get_drag_data(_at: Vector2) -> Variant:
	if item_id().is_empty():
		return null
	var count := int(data["count"])
	var split := Input.is_key_pressed(KEY_SHIFT) and count > 1
	var moving := ceili(count / 2.0) if split else count
	var preview := HBoxContainer.new()
	preview.add_child(ItemIcon.make(item_id(), 30.0, moving))
	set_drag_preview(preview)
	return {"type": "item", "id": item_id(), "count": moving, "whole": not split, "where": where, "slot": slot}


func _can_drop_data(_at: Vector2, value: Variant) -> bool:
	return value is Dictionary and String(value.get("type", "")) == "item"


func _drop_data(_at: Vector2, value: Variant) -> void:
	dropped.emit(self, value)
