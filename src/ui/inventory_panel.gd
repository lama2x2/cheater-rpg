extends CanvasLayer
## Инвентарь списком (D-25): слева ячейки Системы, справа рюкзак, внизу крафт. Tab / I — открыть
## и закрыть. Трофеи принимаются отсюда; нарушение интервала — с подтверждением.
## Игра на паузу не встаёт (D-05). Спецификация: docs/spec/12_ui_ux.md, 12.5.

var _panel: PanelContainer
var _craft_box: VBoxContainer
var _free_points: Label
var _confirm: ConfirmationDialog
var _confirm_item := ""
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

	_free_points = UiKit.label(14, Color(0.95, 0.78, 0.3))
	root.add_child(_free_points)
	var craft_title := UiKit.label(15, Color(0.7, 0.75, 0.9))
	craft_title.text = Content.ui("inv_craft")
	root.add_child(craft_title)
	_craft_box = VBoxContainer.new()
	root.add_child(_craft_box)

	_confirm = ConfirmationDialog.new()
	_confirm.title = Content.ui("confirm_title")
	_confirm.ok_button_text = Content.ui("confirm_ok")
	_confirm.cancel_button_text = Content.ui("confirm_cancel")
	_confirm.confirmed.connect(func() -> void: PlayerState.consume(_confirm_item, true))
	add_child(_confirm)

	PlayerState.inventory_changed.connect(_refresh)


func _process(_delta: float) -> void:
	# Откаты тикают — раз в секунду перерисовываем открытую панель.
	if visible and Engine.get_process_frames() % 60 == 0:
		_refresh()


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
	for box: VBoxContainer in [_primary_box, _backpack_box, _craft_box]:
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
		var slot_buttons := _use_buttons(slot["id"])
		slot_buttons.append([Content.ui("inv_to_backpack"), _to_backpack.bind(i)])
		slot_buttons.append([Content.ui("inv_drop"), _drop_slot.bind(i)])
		_primary_box.add_child(_row(text, slot_buttons))

	_backpack_title.text = Content.ui("inv_backpack", {"kg": _num(inv.backpack_weight_kg()), "cap": _num(inv.backpack_capacity_kg())})
	_overload.text = Content.ui("inv_overload", {"speed": _num(inv.speed_multiplier())}) if inv.is_overloaded() else ""
	if inv.backpack.is_empty():
		_backpack_box.add_child(_row(Content.ui("inv_backpack_empty"), []))
	for stack in inv.backpack:
		var id: String = stack["id"]
		var grams := Content.item_db().weight_g(id) * int(stack["count"])
		var buttons := _use_buttons(id)
		if inv.primary_room(id) > 0:
			buttons.append([Content.ui("inv_to_primary"), _to_primary.bind(id)])
		buttons.append([Content.ui("inv_drop_one"), _drop_backpack.bind(id, 1)])
		if int(stack["count"]) > 1:
			buttons.append([Content.ui("inv_drop"), _drop_backpack.bind(id, int(stack["count"]))])
		_backpack_box.add_child(_row(Content.ui("inv_backpack_row", {"item": Content.item_name(id), "count": stack["count"], "weight": _weight(grams)}), buttons))

	_free_points.text = Content.ui("inv_free_points", {"n": PlayerState.free_points}) if PlayerState.free_points > 0 else ""
	for recipe: Dictionary in Content.recipes():
		var parts: PackedStringArray = []
		var inputs: Dictionary = recipe["inputs"]
		for id: String in inputs:
			parts.append("%s ×%d" % [Content.item_name(id), inputs[id]])
		var outputs: Dictionary = recipe["outputs"]
		var out_id: String = outputs.keys()[0]
		var text := Content.ui("inv_recipe", {"out": "%s ×%d" % [Content.item_name(out_id), outputs[out_id]], "inputs": " + ".join(parts)})
		var craft_buttons: Array = []
		if Crafting.times_possible(recipe, inv) > 0:
			craft_buttons.append([Content.ui("inv_make"), PlayerState.craft.bind(recipe)])
		_craft_box.add_child(_row(text, craft_buttons))


## Кнопка приёма (если предмет можно принять) с подписью отката.
func _use_buttons(id: String) -> Array:
	var trophies := PlayerState.trophies
	if not trophies.can_consume(id):
		return []
	var label := Content.ui("inv_use_" + String(trophies.spec(id).get("verb", "swallow")))
	var left := trophies.cooldown_left(id, GameClock.minutes)
	if left > 0.0:
		label += " (" + Content.ui("inv_cooldown", {"time": _hours(left)}) + ")"
	return [[label, _use.bind(id)]]


func _use(id: String) -> void:
	if PlayerState.consume(id) == "needs_confirm":
		_confirm_item = id
		_confirm.dialog_text = Content.ui("confirm_text", {
			"item": Content.item_name(id), "time": _hours(PlayerState.trophies.cooldown_left(id, GameClock.minutes))})
		_confirm.popup_centered()


## Игровые минуты → «11:05».
func _hours(minutes: float) -> String:
	var total := ceili(minutes)
	return "%d:%02d" % [total / 60, total % 60]


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
	EventBus.items_dropped.emit(id, count)
	SystemLog.post("item_dropped", {"item": Content.item_name(id), "count": count})
	PlayerState.notify_inventory_changed()


## Вес строки рюкзака: до 100 г — в граммах, дальше — в килограммах.
func _weight(grams: float) -> String:
	return "%s г" % _num(grams) if grams < 100.0 else "%s кг" % _num(grams / 1000.0)


## Число без лишних нулей: 1.5, 0.35, 12.
func _num(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")
