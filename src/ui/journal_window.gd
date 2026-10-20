extends CanvasLayer
## Журнал заданий (J, задача 17b): текущие миссии кампании с описанием и целями, выполненные,
## сделанные выборы и провалы. Игра на паузу не встаёт.

var _panel: PanelContainer
var _content: VBoxContainer


func _ready() -> void:
	layer = 5
	visible = false
	add_to_group("journal_window")
	_panel = UiKit.panel()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -360
	_panel.offset_right = 360
	_panel.offset_top = 80
	_panel.anchor_bottom = 1.0
	_panel.offset_bottom = -16
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	root.add_child(UiKit.header(Content.ui("journal_title"), Content.ui("journal_keys", {"key": InputSetup.key_label("journal")}), close))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	PlayerState.quests_changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	UiKit.window_opened(self)
	_refresh()


func close() -> void:
	visible = false
	UiKit.window_closed(self)


func _refresh() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var rules := PlayerState.quest_rules()
	if rules == null:
		_text(Content.ui("journal_sandbox"), 15, UiKit.TEXT_DIM)
		return
	var q := PlayerState.quests
	_text(Content.ui("campaign_" + PlayerState.story_version), 18, UiKit.ACCENT)
	_text(Content.ui("journal_active"), 16, Color(0.85, 0.75, 0.55))
	if (q["active"] as Dictionary).is_empty():
		_text(Content.ui("journal_none"), 14, UiKit.TEXT_DIM)
	for id: String in q["active"]:
		_mission(rules, id, false)
	if not (q["done"] as Array).is_empty():
		_text(Content.ui("journal_done"), 16, Color(0.85, 0.75, 0.55))
		for id in q["done"]:
			_mission(rules, String(id), true)


func _mission(rules: QuestRules, id: String, done: bool) -> void:
	var m := rules.mission(id)
	var fails := int(PlayerState.quests["fails"].get(id, 0))
	_text(("✓ " if done else "◆ ") + Content.ui(String(m.get("title", id))) + ("  · " + Content.ui("journal_fails", {"n": fails}) if fails > 0 else ""),
		16, UiKit.TEXT_DIM if done else UiKit.TEXT)
	if done:
		for c: Dictionary in m.get("choices", []):
			var chosen := rules.chosen(PlayerState.quests, id, String(c["id"]))
			for option: Dictionary in c["options"]:
				if String(option["id"]) == chosen:
					_text("   " + Content.ui("journal_choice", {"text": Content.ui(String(option["text"]))}), 13, UiKit.TEXT_DIM)
		return
	_text("   " + Content.ui(String(m.get("desc", ""))), 14, Color(0.8, 0.82, 0.8))
	for o in rules.objectives(PlayerState.quests, id):
		_text(("   ☑ " if o["done"] else "   ☐ ") + Content.ui(String(o["text"])), 14, UiKit.TEXT_DIM if o["done"] else UiKit.TEXT)


func _text(text: String, size: int, color: Color) -> void:
	var label := UiKit.label(size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
