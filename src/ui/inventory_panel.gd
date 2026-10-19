extends CanvasLayer
## Инвентарь (Tab / I; 12.5, 12.8 — как SkyUI, D-25 — список): слева ячейки Системы (сохраняются
## при смерти), быстрые слоты F1–F4 и крафт; справа рюкзак таблицей — вкладки-фильтры, поиск,
## столбцы с сортировкой (вес, цена, цена за кг), полоса веса с порогом перегруза. Двойной клик —
## главное действие, ПКМ — меню, перетаскивание между ячейками, рюкзаком и быстрыми слотами
## (Shift — половину кучи). Игра на паузу не встаёт (D-05). Правила — ItemTable.

const COLUMNS := ["name", "count", "weight", "price", "price_kg"]

## Окно помнит вкладку, сортировку и поиск между открытиями (и пересборками сцены).
static var tab := "all"
static var sort_column := "name"
static var sort_desc := false
static var search := ""

var _panel: PanelContainer
var _slots_box: VBoxContainer
var _quick_box: HBoxContainer
var _craft_box: VBoxContainer
var _free_points: Label
var _tabs_box: HFlowContainer
var _search: LineEdit
var _columns_box: HBoxContainer
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _weight_bar: Control
var _weight_text: Label
var _menu: PopupMenu
var _menu_row: Dictionary = {}
var _confirm: ConfirmationDialog
var _confirm_item := ""
var _dirty := false
var _left: VBoxContainer
var _compact := false


func _ready() -> void:
	layer = 5
	visible = false
	add_to_group("inventory_panel")
	_panel = UiKit.panel()
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16
	_panel.offset_top = 70
	_panel.offset_bottom = -16
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	root.add_child(UiKit.header(Content.ui("inv_window_title"), Content.ui("inv_window_keys", {"key": InputSetup.key_label("inventory")}), close))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	_left = left
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_title(Content.ui("inv_primary"), Color(0.6, 0.85, 0.6)))
	var slots_zone := DropZone.new()
	slots_zone.accepts = func(d: Dictionary) -> bool: return String(d["where"]) != "primary" and Content.item_db().allowed_in_primary(String(d["id"]))
	slots_zone.dropped.connect(_drop_to_primary.bind(-1))
	left.add_child(slots_zone)
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 1)
	slots_zone.add_child(_slots_box)
	left.add_child(_title(Content.ui("inv_quick_title"), Color(0.75, 0.8, 0.95)))
	var quick_hint := _title(Content.ui("inv_quick_help"), UiKit.TEXT_DIM)
	quick_hint.add_theme_font_size_override("font_size", 12)
	left.add_child(quick_hint)
	_quick_box = HBoxContainer.new()
	_quick_box.add_theme_constant_override("separation", 6)
	left.add_child(_quick_box)
	_free_points = UiKit.label(14, UiKit.ACCENT)
	_free_points.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_free_points)
	left.add_child(_title(Content.ui("inv_craft"), Color(0.7, 0.75, 0.9)))
	_craft_box = VBoxContainer.new()
	left.add_child(_craft_box)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_title(Content.ui("inv_backpack_title"), Color(0.85, 0.75, 0.55)))
	_weight_text = UiKit.label(13, UiKit.TEXT)
	_weight_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_weight_text)
	_weight_bar = Control.new()
	_weight_bar.custom_minimum_size = Vector2(200, 12)
	_weight_bar.draw.connect(_draw_weight)
	right.add_child(_weight_bar)
	_tabs_box = HFlowContainer.new()  # вкладки переносятся, если окно узкое
	_tabs_box.add_theme_constant_override("h_separation", 4)
	_tabs_box.add_theme_constant_override("v_separation", 4)
	right.add_child(_tabs_box)
	_search = LineEdit.new()
	_search.placeholder_text = Content.ui("inv_search")
	_search.clear_button_enabled = true
	_search.text = search
	_search.text_changed.connect(func(text: String) -> void:
		search = text
		_refresh())
	_search.focus_entered.connect(func() -> void: UiKit.typing = true)
	_search.focus_exited.connect(func() -> void: UiKit.typing = false)
	right.add_child(_search)
	_columns_box = HBoxContainer.new()
	_columns_box.add_theme_constant_override("separation", 8)
	right.add_child(_columns_box)
	var backpack_zone := DropZone.new()
	backpack_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	backpack_zone.accepts = func(d: Dictionary) -> bool: return String(d["where"]) == "primary"
	backpack_zone.dropped.connect(_drop_to_backpack)
	right.add_child(backpack_zone)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(520, 160)
	backpack_zone.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 1)
	_scroll.add_child(_rows_box)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_confirm = ConfirmationDialog.new()
	_confirm.title = Content.ui("confirm_title")
	_confirm.ok_button_text = Content.ui("confirm_ok")
	_confirm.cancel_button_text = Content.ui("confirm_cancel")
	_confirm.confirmed.connect(func() -> void: PlayerState.consume(_confirm_item, true))
	add_child(_confirm)
	get_viewport().size_changed.connect(_fit)
	PlayerState.inventory_changed.connect(func() -> void: _dirty = true)


func _title(text: String, color: Color) -> Label:
	var label := UiKit.label(15, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Ширина — под окно игры (влезает при любом масштабе интерфейса). Открыт контейнер или окно
## стаба справа — инвентарь компактный: только рюкзак, чтобы окна не налезали друг на друга.
func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	_compact = _side_window_open()
	_left.visible = not _compact
	var width := minf(1120.0, view.x - 32.0)
	if _compact:
		width = clampf(view.x - side_width(view.x) - 48.0, 360.0, 700.0)
	_scroll.custom_minimum_size.x = 340.0 if _compact else 520.0
	_panel.offset_right = 16 + width
	_panel.reset_size()


## Ширина окна справа (контейнер, стаб) — его же считают окна справа.
static func side_width(view_x: float) -> float:
	return clampf(view_x * 0.5, 480.0, 784.0)


func _side_window_open() -> bool:
	for group in ["container_window", "stab_window"]:
		var w := get_tree().get_first_node_in_group(group)
		if w and bool(w.get("visible")):
			return true
	return false


func _process(_delta: float) -> void:
	if not visible:
		return
	# Откаты тикают — раз в секунду перерисовываем; изменения инвентаря — сразу (кадр спустя).
	if _side_window_open() != _compact:
		_fit()
	if _dirty or Engine.get_process_frames() % 60 == 0:
		_dirty = false
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	for i in 4:
		if event.is_action_pressed("quick_%d" % (i + 1)):
			PlayerState.use_quick_slot(i)
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	UiKit.window_opened(self)
	_fit()
	_refresh()


func close() -> void:
	visible = false
	UiKit.typing = false
	_search.release_focus()
	UiKit.window_closed(self)


func _refresh() -> void:
	if not visible:
		return
	var inv := PlayerState.inventory
	var table := Content.item_table()
	var names := _names()
	for box: Container in [_slots_box, _quick_box, _craft_box, _tabs_box, _columns_box, _rows_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	# Ячейки Системы — все, пустые тоже (цели перетаскивания).
	var cap := roundi(inv.slot_capacity_g())
	for i in inv.primary.size():
		var slot: Dictionary = inv.primary[i]
		var data := {"where": ItemTable.PRIMARY, "slot": i}
		var extra := ""
		if not slot.is_empty():
			data = table.row(String(slot["id"]), int(slot["count"]), ItemTable.PRIMARY, i, PlayerState.junk_marks)
			extra = "  " + Content.ui("inv_slot_grams", {"g": ItemTooltip._num(float(data["weight_g"])), "cap": cap})
		var row := ItemRow.make(data, false, extra + _marks(String(data.get("id", ""))))
		_wire(row)
		_slots_box.add_child(row)
	for i in PlayerState.quick_slots.size():
		_quick_box.add_child(_quick_slot(i))
	_free_points.text = Content.ui("inv_free_points_hint", {"n": PlayerState.free_points}) if PlayerState.free_points > 0 else ""
	_craft()

	var used := inv.backpack_weight_kg()
	var capacity := inv.backpack_capacity_kg()
	_weight_text.text = Content.ui("inv_weight_line", {"kg": ItemTooltip._num(snappedf(used, 0.01)), "cap": ItemTooltip._num(capacity),
		"left": ItemTooltip._num(snappedf(maxf(capacity - used, 0.0), 0.01))}) \
		+ ("   " + Content.ui("inv_overload", {"speed": ItemTooltip._num(snappedf(inv.speed_multiplier(), 0.01))}) if inv.is_overloaded() else "")
	_weight_text.add_theme_color_override("font_color", UiKit.BAD if inv.is_overloaded() else UiKit.TEXT)
	_weight_bar.queue_redraw()
	for id in table.tab_ids():
		var button := UiKit.button(Content.ui("inv_tab_" + id), _select_tab.bind(id), 12)
		button.disabled = id == tab
		_tabs_box.add_child(button)
	_columns_box.add_child(_spacer(24))
	for column: String in COLUMNS:
		var arrow := (" ▼" if sort_desc else " ▲") if column == sort_column else ""
		var button := UiKit.button(Content.ui("inv_col_" + column) + arrow, _sort_by.bind(column), 12)
		if column == "name":
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			button.custom_minimum_size.x = ItemRow.WIDTHS[column]
			button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_columns_box.add_child(button)
	var backpack_rows: Array[Dictionary] = []
	for r in table.rows(inv, PlayerState.junk_marks):
		if r["where"] == ItemTable.BACKPACK:
			backpack_rows.append(r)
	var shown := table.sorted(table.filter(backpack_rows, tab, search, names), sort_column, sort_desc, names)
	if shown.is_empty():
		var empty := UiKit.label(14, UiKit.TEXT_DIM)
		empty.text = Content.ui("inv_backpack_empty") if backpack_rows.is_empty() else Content.ui("inv_nothing_found")
		_rows_box.add_child(empty)
	for r in shown:
		var row := ItemRow.make(r, true, _marks(String(r["id"])))
		_wire(row)
		_rows_box.add_child(row)


func _marks(id: String) -> String:
	if id.is_empty():
		return ""
	var parts := ""
	if PlayerState.weapons.equipped == id:
		parts += "  ◆"
	var q := PlayerState.quick_slots.find(id)
	if q >= 0:
		parts += "  [F%d]" % (q + 1)
	return parts


func _names() -> Dictionary:
	var names := {}
	for id in Content.item_db().ids():
		names[id] = Content.item_name(id)
	return names


func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = width
	return c


func _wire(row: ItemRow) -> void:
	row.activated.connect(_activate)
	row.context_requested.connect(_context)
	row.ctrl_clicked.connect(func(r: ItemRow) -> void: _move_other_side(r.data, int(r.data["count"])))
	row.dropped.connect(_dropped_on_row)


func _select_tab(id: String) -> void:
	tab = id
	_refresh()


func _sort_by(column: String) -> void:
	if sort_column == column:
		sort_desc = not sort_desc
	else:
		sort_column = column
		sort_desc = column != "name"  # числа — сначала большие
	_refresh()


# --- Действия ----------------------------------------------------------------------------------

## Двойной клик: съесть/выпить/принять, оружие — в руки, остальное — на другую сторону.
func _activate(row: ItemRow) -> void:
	var id := row.item_id()
	if PlayerState.trophies.can_consume(id):
		_use(id)
	elif Content.weapon_db().has_weapon(id) and PlayerState.weapons.equipped != id:
		PlayerState.equip_weapon(id)
	else:
		_move_other_side(row.data, int(row.data["count"]))


func _move_other_side(data: Dictionary, count: int) -> void:
	var inv := PlayerState.inventory
	if String(data["where"]) == ItemTable.PRIMARY:
		if not inv.move_slot_to_backpack(int(data["slot"]), count):
			SystemLog.post("inv_no_room_backpack", {"item": Content.item_name(String(data["id"]))}, "warning")
	elif inv.move_backpack_to_primary(String(data["id"]), count) == 0:
		SystemLog.post("inv_no_room_primary", {"item": Content.item_name(String(data["id"]))}, "warning")
	PlayerState.notify_inventory_changed()


func _context(row: ItemRow, at: Vector2) -> void:
	_menu_row = row.data
	_menu.clear()
	var id := row.item_id()
	var count := int(row.data["count"])
	if PlayerState.trophies.can_consume(id):
		_menu.add_item(Content.ui("inv_use_" + String(PlayerState.trophies.spec(id).get("verb", "swallow"))), 1)
	if Content.weapon_db().has_weapon(id) and PlayerState.weapons.equipped != id:
		_menu.add_item(Content.ui("inv_equip"), 2)
	_menu.add_item(Content.ui("inv_to_backpack") if row.where == ItemTable.PRIMARY else Content.ui("inv_to_primary"), 3)
	if count > 1:
		_menu.add_item(Content.ui("inv_split", {"n": ceili(count / 2.0)}), 4)
	_menu.add_item(Content.ui("inv_drop_one"), 5)
	if count > 1:
		_menu.add_item(Content.ui("inv_drop_all", {"n": count}), 6)
	if PlayerState.trophies.can_consume(id) or Content.weapon_db().has_weapon(id):
		for i in PlayerState.quick_slots.size():
			_menu.add_item(Content.ui("inv_to_quick", {"n": i + 1}), 10 + i)
	_menu.add_item(Content.ui("inv_unmark_junk") if PlayerState.junk_marks.has(id) else Content.ui("inv_mark_junk"), 7)
	_menu.reset_size()
	_menu.position = Vector2i(at)
	_menu.popup()


func _on_menu(action: int) -> void:
	var data := _menu_row
	if data.is_empty():
		return
	var id := String(data["id"])
	var count := int(data["count"])
	match action:
		1:
			_use(id)
		2:
			PlayerState.equip_weapon(id)
		3:
			_move_other_side(data, count)
		4:
			_move_other_side(data, ceili(count / 2.0))
		5:
			_drop(data, 1)
		6:
			_drop(data, count)
		7:
			PlayerState.toggle_junk(id)
		_:
			if action >= 10:
				PlayerState.set_quick_slot(action - 10, id)


func _use(id: String) -> void:
	if PlayerState.consume(id) == "needs_confirm":
		_confirm_item = id
		_confirm.dialog_text = Content.ui("confirm_text", {
			"item": Content.item_name(id), "time": PlayerState.cooldown_text(PlayerState.trophies.cooldown_left(id, GameClock.minutes))})
		_confirm.popup_centered()


func _drop(data: Dictionary, count: int) -> void:
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
	EventBus.items_dropped.emit(id, count)
	SystemLog.post("item_dropped", {"item": Content.item_name(id), "count": count})
	PlayerState.notify_inventory_changed()


# --- Перетаскивание ----------------------------------------------------------------------------

func _dropped_on_row(row: ItemRow, data: Dictionary) -> void:
	if row.where == ItemTable.PRIMARY:
		_drop_to_primary(data, row.slot)
	elif row.where == ItemTable.BACKPACK:
		_drop_to_backpack(data)


## В ячейки: из рюкзака — сколько влезет; ячейка на ячейку — поменять местами.
func _drop_to_primary(data: Dictionary, target_slot: int) -> void:
	var inv := PlayerState.inventory
	if String(data["where"]) == ItemTable.PRIMARY:
		if target_slot >= 0 and target_slot != int(data["slot"]):
			inv.swap_slots(int(data["slot"]), target_slot)
			PlayerState.notify_inventory_changed()
		return
	if String(data["where"]) == ItemTable.BACKPACK:
		_move_other_side(data, int(data["count"]))


func _drop_to_backpack(data: Dictionary) -> void:
	if String(data["where"]) == ItemTable.PRIMARY:
		_move_other_side(data, int(data["count"]))


# --- Быстрые слоты и крафт ---------------------------------------------------------------------

func _quick_slot(index: int) -> Control:
	var zone := DropZone.new()
	zone.accepts = func(d: Dictionary) -> bool:
		var id := String(d["id"])
		return PlayerState.trophies.can_consume(id) or Content.weapon_db().has_weapon(id)
	zone.dropped.connect(func(d: Dictionary) -> void: PlayerState.set_quick_slot(index, String(d["id"])))
	zone.right_clicked.connect(func() -> void: PlayerState.set_quick_slot(index, ""))
	var id := PlayerState.quick_slots[index]
	zone.tooltip_text = Content.ui("inv_quick_hint", {"n": index + 1}) if id.is_empty() else "%s — %s" % [Content.item_name(id), Content.ui("inv_quick_hint", {"n": index + 1})]
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(box)
	box.add_child(ItemIcon.make(id, 40.0, PlayerState.inventory.count_of(id) if not id.is_empty() else 0))
	var key := UiKit.label(12, UiKit.TEXT_DIM)
	key.text = "F%d" % (index + 1)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key)
	return zone


func _craft() -> void:
	var inv := PlayerState.inventory
	for recipe: Dictionary in Content.recipes():
		var parts: PackedStringArray = []
		var inputs: Dictionary = recipe["inputs"]
		for id: String in inputs:
			parts.append("%s ×%d" % [Content.item_name(id), inputs[id]])
		var outputs: Dictionary = recipe["outputs"]
		var out_id: String = outputs.keys()[0]
		var row := HBoxContainer.new()
		var label := UiKit.label(13, UiKit.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = Content.ui("inv_recipe", {"out": "%s ×%d" % [Content.item_name(out_id), outputs[out_id]], "inputs": " + ".join(parts)})
		row.add_child(label)
		var make := UiKit.button(Content.ui("inv_make"), PlayerState.craft.bind(recipe), 12)
		make.disabled = Crafting.times_possible(recipe, inv) <= 0
		row.add_child(make)
		_craft_box.add_child(row)


## Полоса веса: заполнение до предела (двойная вместимость), риска — порог перегруза.
func _draw_weight() -> void:
	var inv := PlayerState.inventory
	var size := _weight_bar.size
	var limit := inv.backpack_capacity_kg() * 2.0
	var ratio := clampf(inv.backpack_weight_kg() / maxf(limit, 0.01), 0.0, 1.0)
	_weight_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.1, 0.9))
	var color := Color(0.5, 0.75, 0.45) if not inv.is_overloaded() else (Color(0.9, 0.7, 0.3) if ratio < 0.85 else UiKit.BAD)
	_weight_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), color)
	var mark := size.x * 0.5
	_weight_bar.draw_line(Vector2(mark, -2), Vector2(mark, size.y + 2), Color(1, 1, 1, 0.8), 2.0)
