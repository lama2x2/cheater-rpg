extends CanvasLayer
## Быстрые слоты F1–F4 в HUD (12.1, 12.8): иконки расходников и оружия с количеством, внизу по
## центру. Назначаются в инвентаре (перетащить, ПКМ → «В быстрый слот»), применяются клавишей.

var _box: HBoxContainer


func _ready() -> void:
	layer = 3
	add_to_group("hud_layers")
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_bottom = -16
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	PlayerState.inventory_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var any := false
	for i in PlayerState.quick_slots.size():
		any = any or not PlayerState.quick_slots[i].is_empty()
	if not any:
		return  # пустые слоты не занимают экран
	for i in PlayerState.quick_slots.size():
		var id := PlayerState.quick_slots[i]
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := ItemIcon.make(id, 38.0, PlayerState.inventory.count_of(id) if not id.is_empty() else 0)
		if not id.is_empty() and PlayerState.inventory.count_of(id) <= 0:
			icon.modulate.a = 0.35
		cell.add_child(icon)
		var key := UiKit.label(11, UiKit.TEXT_DIM)
		key.text = "F%d" % (i + 1)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(key)
		_box.add_child(cell)
