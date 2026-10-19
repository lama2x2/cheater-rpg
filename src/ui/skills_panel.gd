class_name SkillsPanel
extends CanvasLayer
## Окно умений (U): список активных (D-84) — порядок (клавиши 1–8), внести и убрать; изученные
## умения с числами (мана, откат, действие); выбор свойств на порогах Ментальной силы; висящее
## умение жемчужины — вскрыть самому (D-86). Игра на паузу не встаёт (D-05). Действия — PlayerState.
## Спецификация: docs/spec/05_skills.md.

var _panel: PanelContainer
var _slots: Label
var _content: VBoxContainer


func _ready() -> void:
	layer = 5
	visible = false
	add_to_group("skills_panel")
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.92)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(16, 120)
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	var title := UiKit.label(18, Color(0.95, 0.78, 0.3))
	title.text = Content.ui("skills_title")
	root.add_child(title)
	_slots = UiKit.label(14, Color(0.6, 0.85, 0.6))
	root.add_child(_slots)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	PlayerState.skills_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skills"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var skills := PlayerState.skills
	_slots.text = Content.ui("skills_list", {"n": skills.active_list.size(), "reserve": roundi(skills.mana_reserve() * 100.0)})
	if PlayerState.pending_pearl_skills > 0:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_text(Content.ui("skills_pearl", {"n": PlayerState.pending_pearl_skills}), 13, Color(0.95, 0.78, 0.3)))
		row.add_child(_button(Content.ui("skills_pearl_open"), PlayerState.open_pearl_self))
		_content.add_child(row)
	if skills.learned.is_empty():
		_content.add_child(_text(Content.ui("skills_none"), 13, Color(0.8, 0.8, 0.8)))
		return
	var levels := PlayerState.skill_levels()
	for id in skills.active_list:
		_content.add_child(_skill_block(id, levels))
	for id: String in skills.learned:
		if not skills.in_list(id):
			_content.add_child(_skill_block(id, levels))


func _skill_block(id: String, levels: Dictionary) -> VBoxContainer:
	var skills := PlayerState.skills
	var block := VBoxContainer.new()
	var index := skills.active_list.find(id)
	var mark := ""
	if index >= 0:
		mark = " [%d]" % (index + 1) if index < skills.hotkey_count() else " " + Content.ui("skills_no_key")
	else:
		mark = " " + Content.ui("skills_not_listed")
	block.add_child(_text(Content.skill_name(id) + mark, 15, Color(1.0, 0.85, 0.45) if index >= 0 else Color(0.6, 0.6, 0.6)))
	block.add_child(_text(skill_description(id, levels), 12, Color(0.85, 0.85, 0.85)))
	block.add_child(_text(_numbers(id, levels), 12, Color(0.6, 0.75, 0.95)))
	for p: Dictionary in skills.active_properties(id, levels):
		block.add_child(_text("• " + _property_name(String(p["id"])), 12, Color(0.75, 0.9, 0.7)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	if index >= 0:
		if index > 0:
			buttons.add_child(_button(Content.ui("skills_up"), PlayerState.list_move.bind(id, -1)))
		if index < skills.active_list.size() - 1:
			buttons.add_child(_button(Content.ui("skills_down"), PlayerState.list_move.bind(id, 1)))
		buttons.add_child(_button(Content.ui("skills_unlist"), PlayerState.list_remove.bind(id)))
	else:
		buttons.add_child(_button(Content.ui("skills_to_list"), PlayerState.list_add.bind(id)))
	block.add_child(buttons)
	for choice in skills.property_choices(id, levels):
		block.add_child(_text(Content.ui("skills_choice", {"group": String(choice["group"]).trim_prefix("m")}), 12, Color(0.95, 0.78, 0.3)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for p: Dictionary in choice["options"]:
			row.add_child(_button(_property_name(String(p["id"])), PlayerState.choose_skill_property.bind(id, String(p["id"]))))
		block.add_child(row)
	return block


## Описание с подставленными числами: {stat_mult.value}, {stat_mult.duration_s} и т. п.
static func skill_description(id: String, levels: Dictionary) -> String:
	var text := String(Content.texts()["skill_desc"].get(id, ""))
	var params := {}
	for e in PlayerState.skills.effects(id, levels):
		for key: String in e:
			if e[key] is float or e[key] is int:
				params["%s.%s" % [e.get("key", e["type"]), key]] = _num(float(e[key]) * 100.0) + "%" if key == "pct" else _num(float(e[key]))
	return text.format(params)


## Число для текста: целое — без дроби, иначе до сотых, с запятой («0,65», «8», «12,5»).
static func _num(value: float) -> String:
	if absf(value - roundf(value)) < 0.001:
		return str(roundi(value))
	var text := ("%.2f" % value).rstrip("0").rstrip(".")
	return text.replace(".", ",")


func _numbers(id: String, levels: Dictionary) -> String:
	var skills := PlayerState.skills
	if skills.is_passive(id):
		return Content.ui("skills_row_passive", {"reserve": roundi(_reserve(id) * 100.0)})
	var left := skills.cooldown_left(id, GameClock.minutes)
	var extra := Content.ui("skills_ready_in", {"left": PlayerState.cooldown_text(left)}) if left > 0.0 else ""
	return Content.ui("skills_row_active", {
		"mana": roundi(skills.mana_cost(id, levels)),
		"cooldown": PlayerState.cooldown_text(skills.cooldown_s(id, levels) / 60.0), "extra": extra,
	})


func _reserve(id: String) -> float:
	for e: Dictionary in PlayerState.skills.def(id).get("effects", []):
		if String(e["type"]) == "reserve_mana":
			return float(e["pct"])
	return 0.0


func _property_name(id: String) -> String:
	return String(Content.texts()["property_names"].get(id, id))


func _text(text: String, size: int, color: Color) -> Label:
	var label := UiKit.label(size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 520
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UiKit.font())
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	return button
