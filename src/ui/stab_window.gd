extends CanvasLayer
## Окно услуг стаба: торговец (купить / продать), знахарка (лечение, дар уровня), бар (сон, слух),
## доска (взять / сдать контракт). Открывается E у непися (src/actors/stab_npc.gd), закрывается
## кнопкой «Уйти» или если герой отошёл. Игра на паузу не встаёт (D-05). Действия — StabState.

const CLOSE_DISTANCE := 3.5

var _npc: Node3D
var _panel: PanelContainer
var _title: Label
var _line: Label
var _money: Label
var _content: VBoxContainer
var _gift_price := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 6
	visible = false
	add_to_group("stab_window")
	_rng.randomize()
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.92)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -760
	_panel.offset_right = -16
	_panel.offset_top = 160
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	_title = UiKit.label(18, Color(0.95, 0.78, 0.3))
	root.add_child(_title)
	_line = UiKit.label(14, Color(0.8, 0.85, 0.8))
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 700
	root.add_child(_line)
	_money = UiKit.label(15, Color(0.6, 0.85, 0.6))
	root.add_child(_money)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	root.add_child(_content)
	var close := _button(Content.ui("stab_close"), close_window)
	root.add_child(close)

	StabState.changed.connect(_refresh)
	PlayerState.inventory_changed.connect(_refresh)
	PlayerState.skills_changed.connect(_refresh)


func open(npc: Node3D) -> void:
	_npc = npc
	StabState.refresh()
	var info: Dictionary = npc.info()
	_title.text = info["name"] if npc.kind == "board" else "%s — %s" % [info["name"], info["role"]]
	var lines: Array = info["lines"]
	_line.text = "«%s»" % lines[_rng.randi_range(0, lines.size() - 1)] if npc.kind != "board" else String(lines[_rng.randi_range(0, lines.size() - 1)])
	_gift_price = StabState.gift_price()
	visible = true
	_refresh()


func close_window() -> void:
	visible = false
	_npc = null


func _process(_delta: float) -> void:
	if not visible:
		return
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if _npc == null or not is_instance_valid(_npc) or hero == null or not hero.visible \
			or hero.global_position.distance_to(_npc.global_position) > CLOSE_DISTANCE:
		close_window()


func _refresh() -> void:
	if not visible or _npc == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_money.text = Content.ui("stab_money", {"n": StabState.money()})
	match String(_npc.kind):
		"trader":
			_trader()
		"healer":
			_healer()
		"bar":
			_bar()
		"board":
			_board()


func _trader() -> void:
	var trade := StabState.trade
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	_content.add_child(columns)

	var buy_box := _column(columns, Content.ui("trade_buy_title"))
	var any := false
	for id: String in trade.stock:
		var stock := int(trade.stock[id])
		if stock <= 0:
			continue
		any = true
		var buttons: Array = [[Content.ui("trade_buy"), StabState.buy.bind(id, 1)]]
		if stock >= 5:
			buttons.append([Content.ui("trade_buy_5"), StabState.buy.bind(id, 5)])
		buy_box.add_child(_row(Content.ui("trade_buy_row", {"item": Content.item_name(id), "stock": stock, "price": trade.buy_price(id)}), buttons))
	if not any:
		buy_box.add_child(_row(Content.ui("trade_nothing"), []))

	var sell_box := _column(columns, Content.ui("trade_sell_title"))
	var inv := PlayerState.inventory
	any = false
	for id in _owned_ids():
		if trade.sell_price(id) <= 0:
			continue
		any = true
		var count := inv.count_of(id)
		var buttons: Array = [[Content.ui("trade_sell"), StabState.sell.bind(id, 1)]]
		if count > 1:
			buttons.append([Content.ui("trade_sell_all"), StabState.sell.bind(id, count)])
		sell_box.add_child(_row(Content.ui("trade_sell_row", {"item": Content.item_name(id), "count": count, "price": trade.sell_price(id)}), buttons))
	if not any:
		sell_box.add_child(_row(Content.ui("trade_nothing"), []))


func _healer() -> void:
	var cost := StabState.heal_cost()
	if cost > 0:
		_content.add_child(_row("", [[Content.ui("healer_heal", {"price": cost}), StabState.heal]]))
	else:
		_content.add_child(_row(Content.ui("healer_healthy"), []))
	var gift := StabState.next_gift()
	if gift > 0:
		_content.add_child(_row("", [[Content.ui("healer_gift", {"level": gift, "price": _gift_price}), StabState.open_gift.bind(_gift_price)]]))
	else:
		_content.add_child(_row(Content.ui("healer_no_gift", {"level": PlayerState.stats.general_level()}), []))
	if PlayerState.pending_skill_choices > 0:
		_content.add_child(_row(Content.ui("healer_pending", {"n": PlayerState.pending_skill_choices}), []))
		_gift_choice()
	if PlayerState.pending_pearl_skills > 0:
		_pearl_choice()


## Висящее умение жемчужины (D-86): выбрать область за плату; пустые области — без кнопки.
func _pearl_choice() -> void:
	_content.add_child(_header(Content.ui("healer_pearl", {"n": PlayerState.pending_pearl_skills, "price": StabState.pearl_price()})))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for area in PlayerState.skills.areas():
		var count := PlayerState.skills.area_skills(area).size()
		var button := _button(Content.ui("healer_pearl_area", {"area": Content.texts()["area_names"].get(area, area), "n": count}), StabState.open_pearl_area.bind(area))
		button.disabled = count == 0
		row.add_child(button)
	_content.add_child(row)


## Выбор умения из вариантов дара (задача 13): название, описание, кнопка «Взять».
func _gift_choice() -> void:
	var offers := PlayerState.gift_offers()
	if offers.is_empty():
		_content.add_child(_row(Content.ui("healer_choose_none"), []))
		return
	_content.add_child(_header(Content.ui("healer_choose_title", {"level": PlayerState.pending_gift_level()})))
	var levels := PlayerState.skill_levels()
	for id in offers:
		var text := "%s — %s" % [Content.skill_name(id), SkillsPanel.skill_description(id, levels)]
		_content.add_child(_row(text, [[Content.ui("healer_choose"), _choose_gift.bind(id)]]))


func _choose_gift(id: String) -> void:
	PlayerState.choose_gift(id)
	_refresh()


func _bar() -> void:
	var bar: Dictionary = Content.stab_config()["bar"]
	if StabState.can_sleep():
		_content.add_child(_row("", [[Content.ui("bar_sleep", {"hours": bar["sleep_hours"], "price": bar["sleep_price"]}), StabState.sleep]]))
	else:
		_content.add_child(_row(Content.ui("bar_sleep_no"), []))
	_content.add_child(_row("", [[Content.ui("bar_rumor", {"price": bar["rumor_price"]}), StabState.rumor]]))


func _board() -> void:
	var board := StabState.board
	_content.add_child(_header(Content.ui("board_offers")))
	if board.offers.is_empty():
		_content.add_child(_row(Content.ui("board_none"), []))
	for i in board.offers.size():
		var buttons: Array = [[Content.ui("board_take"), StabState.take_contract.bind(i)]] if board.can_take() else []
		_content.add_child(_row(StabState.contract_text(board.offers[i]), buttons))
	if not board.can_take():
		_content.add_child(_row(Content.ui("board_full"), []))
	_content.add_child(_header(Content.ui("board_active")))
	if board.active.is_empty():
		_content.add_child(_row(Content.ui("board_none"), []))
	for i in board.active.size():
		var contract: Dictionary = board.active[i]
		var buttons: Array = [[Content.ui("board_done"), StabState.complete_contract.bind(i)]] \
			if ContractBoard.is_ready(contract, PlayerState.inventory) else []
		_content.add_child(_row(StabState.contract_text(contract), buttons))


## Что есть у героя (ячейки и рюкзак), без повторов, в порядке инвентаря.
func _owned_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	var inv := PlayerState.inventory
	for slot in inv.primary:
		if not slot.is_empty() and not ids.has(slot["id"]):
			ids.append(slot["id"])
	for stack in inv.backpack:
		if not ids.has(stack["id"]):
			ids.append(stack["id"])
	return ids


func _column(parent: Container, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_child(_header(title))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var box := VBoxContainer.new()
	scroll.add_child(box)
	parent.add_child(column)
	return box


func _header(text: String) -> Label:
	var label := UiKit.label(15, Color(0.85, 0.75, 0.55))
	label.text = text
	return label


func _row(text: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if not text.is_empty():
		var label := UiKit.label(13, Color(0.9, 0.9, 0.9))
		label.text = text
		label.custom_minimum_size.x = 220
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	for spec: Array in buttons:
		row.add_child(_button(spec[0], spec[1]))
	return row


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UiKit.font())
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	return button
