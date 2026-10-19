extends CanvasLayer
## Окно контейнера (12.8): свой труп, тайник — две колонки «там / у меня». «Взять всё» — кнопкой
## или E ещё раз: ценное за килограмм — вперёд, что не влезло — остаётся и пишется в лог.
## Двойной клик или Ctrl+клик — взять строку целиком, перетаскивание — взять или положить
## обратно (Shift — половину). Закрывается Esc, крестиком или если герой отошёл.
##
## Контейнер — узел с методами container_title(), container_stacks() → [{"id", "count"}],
## container_take(id, count) и container_put(id, count) → сколько положено.

const CLOSE_DISTANCE := 3.0

var target: Node3D
var _panel: PanelContainer
var _title: Label
var _there: VBoxContainer
var _mine: VBoxContainer
var _status: Label
var _dirty := false


func _ready() -> void:
	layer = 6
	visible = false
	add_to_group("container_window")
	_panel = UiKit.panel()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_right = -16
	_panel.offset_top = 90
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	var header := UiKit.header("", Content.ui("cont_keys"), close)
	_title = header.get_child(0) as Label
	root.add_child(header)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)
	_there = _column(columns, Content.ui("cont_there"), _drop_there, func(d: Dictionary) -> bool: return String(d["where"]) != "container")
	_mine = _column(columns, Content.ui("cont_mine"), _drop_mine, func(d: Dictionary) -> bool: return String(d["where"]) == "container")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	root.add_child(buttons)
	buttons.add_child(UiKit.button(Content.ui("cont_take_all"), take_all, 15))
	_status = UiKit.label(13, UiKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_status)
	PlayerState.inventory_changed.connect(func() -> void: _dirty = true)


func _column(parent: Container, title: String, on_drop: Callable, accepts: Callable) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := UiKit.label(15, Color(0.85, 0.75, 0.55))
	label.text = title
	column.add_child(label)
	var zone := DropZone.new()
	zone.accepts = accepts
	zone.dropped.connect(on_drop)
	column.add_child(zone)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(220, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	zone.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)
	scroll.add_child(box)
	parent.add_child(column)
	return box


## E у контейнера: открыть окно, а если оно уже открыто для него — «Взять всё».
func open_or_take(container: Node3D) -> void:
	if visible and target == container:
		take_all()
		return
	target = container
	var view := get_viewport().get_visible_rect().size
	_panel.offset_left = -16.0 - preload("res://src/ui/inventory_panel.gd").side_width(view.x)
	visible = true
	UiKit.window_opened(self)
	_status.text = ""
	_refresh()


func close() -> void:
	visible = false
	target = null
	UiKit.window_closed(self)


func _process(_delta: float) -> void:
	if not visible:
		return
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if target == null or not is_instance_valid(target) or hero == null or not hero.visible \
			or hero.global_position.distance_to(target.global_position) > CLOSE_DISTANCE:
		close()
		return
	if _dirty:
		_dirty = false
		_refresh()


func _refresh() -> void:
	if not visible or target == null:
		return
	_title.text = target.container_title()
	var table := Content.item_table()
	for box in [_there, _mine]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var stacks: Array = target.container_stacks()
	if stacks.is_empty():
		_there.add_child(_empty(Content.ui("cont_empty")))
	for r in table.container_rows(stacks, PlayerState.junk_marks):
		var row := ItemRow.make(r, false)
		row.activated.connect(func(rr: ItemRow) -> void: _take(rr.item_id(), int(rr.data["count"])))
		row.ctrl_clicked.connect(func(rr: ItemRow) -> void: _take(rr.item_id(), int(rr.data["count"])))
		_there.add_child(row)
	var mine := table.rows(PlayerState.inventory, PlayerState.junk_marks)
	if mine.is_empty():
		_mine.add_child(_empty(Content.ui("inv_backpack_empty")))
	for r in mine:
		var row := ItemRow.make(r, false)
		row.ctrl_clicked.connect(func(rr: ItemRow) -> void: _put(rr.data, int(rr.data["count"])))
		_mine.add_child(row)


func _empty(text: String) -> Label:
	var label := UiKit.label(14, UiKit.TEXT_DIM)
	label.text = text
	return label


## Всё по ценности за килограмм; что не влезло — остаётся в контейнере.
func take_all() -> void:
	if target == null:
		return
	var stacks: Array = target.container_stacks().duplicate(true)
	if stacks.is_empty():
		return
	var inv := PlayerState.inventory
	var result := Content.item_table().take_all(stacks, func(id: String, count: int) -> int:
		var left := int(inv.add(id, count)["left"])
		if count - left > 0:
			target.container_take(id, count - left)
			EventBus.item_picked.emit(id, count - left)
		return left)
	var left: Array = result["left"]
	if left.is_empty():
		SystemLog.post("cont_took_all", {"what": target.container_title()})
		_status.text = ""
	else:
		var parts: PackedStringArray = []
		for s: Dictionary in left:
			parts.append("%s ×%d" % [Content.item_name(String(s["id"])), int(s["count"])])
		SystemLog.post("cont_left", {"items": ", ".join(parts)}, "warning")
		_status.text = Content.ui("cont_left_status", {"items": ", ".join(parts)})
	PlayerState.notify_inventory_changed()


func _take(id: String, count: int) -> void:
	var left := int(PlayerState.inventory.add(id, count)["left"])
	if count - left > 0:
		target.container_take(id, count - left)
		EventBus.item_picked.emit(id, count - left)
	if left > 0:
		_status.text = Content.ui("cont_no_room", {"item": Content.item_name(id)})
	PlayerState.notify_inventory_changed()


## Положить из инвентаря обратно в контейнер.
func _put(data: Dictionary, count: int) -> void:
	var id := String(data["id"])
	var inv := PlayerState.inventory
	if String(data["where"]) == ItemTable.PRIMARY:
		var slot: Dictionary = inv.primary[int(data["slot"])]
		if slot.is_empty() or String(slot["id"]) != id:
			return
		count = mini(count, int(slot["count"]))
		slot["count"] = int(slot["count"]) - count
		if int(slot["count"]) <= 0:
			slot.clear()
	elif not inv.remove_from_backpack(id, count):
		return
	target.container_put(id, count)
	PlayerState.notify_inventory_changed()


func _drop_there(data: Dictionary) -> void:
	_put(data, int(data["count"]))


func _drop_mine(data: Dictionary) -> void:
	_take(String(data["id"]), int(data["count"]))
