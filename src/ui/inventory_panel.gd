extends CanvasLayer
## Инвентарь списком (D-25): слева ячейки Системы, справа рюкзак. Tab / I — открыть и закрыть.
## Игра на паузу не встаёт (D-05). Спецификация: docs/spec/12_ui_ux.md, 12.5.

var hero: Node3D

var _panel: PanelContainer
var _primary_box: VBoxContainer
var _backpack_box: VBoxContainer
var _backpack_title: Label
var _overload: Label


func _ready() -> void:
	layer = 5
	visible = false
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.9)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(16, 120)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)
	var title := UiKit.label(18, Color(0.95, 0.78, 0.3))
	title.text = Content.ui("inv_title")
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	root.add_child(columns)

	var left := VBoxContainer.new()
	var primary_title := UiKit.label(15, Color(0.6, 0.85, 0.6))
	primary_title.text = Content.ui("inv_primary")
	left.add_child(primary_title)
	_primary_box = VBoxContainer.new()
	left.add_child(_primary_box)
	columns.add_child(left)

	var right := VBoxContainer.new()
	_backpack_title = UiKit.label(15, Color(0.85, 0.75, 0.55))
	right.add_child(_backpack_title)
	_overload = UiKit.label(14, Color(0.95, 0.35, 0.3))
	right.add_child(_overload)
	_backpack_box = VBoxContainer.new()
	right.add_child(_backpack_box)
	columns.add_child(right)

	PlayerState.inventory_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		visible = not visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not visible:
		return
	var inv := PlayerState.inventory
	for box: VBoxContainer in [_primary_box, _backpack_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()

	var cap := roundi(inv.slot_capacity_g())
	for i in inv.primary.size():
		var slot: Dictionary = inv.primary[i]
		if slot.is_empty():
			_primary_box.add_child(_row(Content.ui("inv_primary_empty", {"n": i + 1, "cap": cap}), []))
			continue
		var grams := Content.item_db().weight_g(slot["id"]) * int(slot["count"])
		var text := Content.ui("inv_primary_slot", {
			"n": i + 1, "item": Content.item_name(slot["id"]), "count": slot["count"], "grams": _num(grams), "cap": cap})
		_primary_box.add_child(_row(text, [
			[Content.ui("inv_to_backpack"), _to_backpack.bind(i)],
			[Content.ui("inv_drop"), _drop_slot.bind(i)],
		]))

	_backpack_title.text = Content.ui("inv_backpack", {"kg": _num(inv.backpack_weight_kg()), "cap": _num(inv.backpack_capacity_kg())})
	_overload.text = Content.ui("inv_overload", {"speed": _num(inv.speed_multiplier())}) if inv.is_overloaded() else ""
	if inv.backpack.is_empty():
		_backpack_box.add_child(_row(Content.ui("inv_backpack_empty"), []))
	for stack in inv.backpack:
		var id: String = stack["id"]
		var kg := Content.item_db().weight_g(id) * int(stack["count"]) / 1000.0
		var buttons: Array = []
		if inv.primary_room(id) > 0:
			buttons.append([Content.ui("inv_to_primary"), _to_primary.bind(id)])
		buttons.append([Content.ui("inv_drop_one"), _drop_backpack.bind(id, 1)])
		if int(stack["count"]) > 1:
			buttons.append([Content.ui("inv_drop"), _drop_backpack.bind(id, int(stack["count"]))])
		_backpack_box.add_child(_row(Content.ui("inv_backpack_row", {"item": Content.item_name(id), "count": stack["count"], "kg": _num(kg)}), buttons))


func _row(text: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := UiKit.label(14, Color(0.9, 0.9, 0.9))
	label.text = text
	label.custom_minimum_size.x = 300
	row.add_child(label)
	for spec: Array in buttons:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", UiKit.font())
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(spec[1])
		row.add_child(button)
	return row


func _to_backpack(slot_index: int) -> void:
	if PlayerState.inventory.move_slot_to_backpack(slot_index):
		PlayerState.notify_inventory_changed()


func _to_primary(id: String) -> void:
	if PlayerState.inventory.move_backpack_to_primary(id) > 0:
		PlayerState.notify_inventory_changed()


func _drop_slot(slot_index: int) -> void:
	var slot: Dictionary = PlayerState.inventory.primary[slot_index]
	if slot.is_empty():
		return
	var id: String = slot["id"]
	var count: int = slot["count"]
	slot.clear()
	_drop(id, count)


func _drop_backpack(id: String, count: int) -> void:
	if PlayerState.inventory.remove_from_backpack(id, count):
		_drop(id, count)


func _drop(id: String, count: int) -> void:
	var world := get_tree().get_first_node_in_group("world_items")
	if world and hero:
		world.drop_near(id, count, hero.global_position)
	SystemLog.post("item_dropped", {"item": Content.item_name(id), "count": count})
	PlayerState.notify_inventory_changed()


## Число без лишних нулей: 1.5, 0.35, 12.
func _num(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")
