class_name SkillsPanel
extends CanvasLayer
## Окно умений (U): изученные умения с числами (мана, откат, действие), слоты и выбор свойств на
## порогах Ментальной силы. Игра на паузу не встаёт (D-05). Действия — PlayerState.
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
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	root.add_child(_content)
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
	var general := PlayerState.stats.general_level()
	var open := skills.slot_count(general)
	_slots.text = Content.ui("skills_slots", {"used": skills.slotted(general).size(), "open": open})
	if skills.learned.is_empty():
		_content.add_child(_text(Content.ui("skills_none"), 13, Color(0.8, 0.8, 0.8)))
		return
	var levels := PlayerState.skill_levels()
	for id: String in skills.learned:
		_content.add_child(_skill_block(id, levels, open))


func _skill_block(id: String, levels: Dictionary, open: int) -> VBoxContainer:
	var skills := PlayerState.skills
	var block := VBoxContainer.new()
	var slot := skills.slot_of(id)
	var name := Content.skill_name(id) + (" [%d]" % (slot + 1) if slot >= 0 and slot < open else "")
	block.add_child(_text(name, 15, Color(1.0, 0.85, 0.45)))
	block.add_child(_text(skill_description(id, levels), 12, Color(0.85, 0.85, 0.85)))
	block.add_child(_text(_numbers(id, levels), 12, Color(0.6, 0.75, 0.95)))
	for p: Dictionary in skills.active_properties(id, levels):
		block.add_child(_text("• " + _property_name(String(p["id"])), 12, Color(0.75, 0.9, 0.7)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for i in open:
		if skills.slots[i] != id:
			buttons.add_child(_button(Content.ui("skills_to_slot", {"n": i + 1}), PlayerState.set_skill_slot.bind(i, id)))
	if slot >= 0:
		buttons.add_child(_button(Content.ui("skills_unslot"), PlayerState.set_skill_slot.bind(slot, "")))
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
				var value := float(e[key])
				params["%s.%s" % [e["type"], key]] = str(snappedf(value, 0.1)).trim_suffix(".0")
	return text.format(params)


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
