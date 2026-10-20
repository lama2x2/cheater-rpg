extends CanvasLayer
## Разговор с наставником (задача 17): знакомство и подарки (споран, живчик, бинт, нож — если нечем
## вскрыть мешок), «загляни ему в затылок», крестины — имя (поле ввода) или «как сам назовёшь»;
## крестный может отказать и дать кличку по поступку (OnboardingRules.christen).

const CLOSE_DISTANCE := 3.5

var _npc: Node3D
var _panel: PanelContainer
var _content: VBoxContainer
var _name_edit: LineEdit


func _ready() -> void:
	layer = 6
	visible = false
	add_to_group("mentor_window")
	_panel = UiKit.panel()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -560
	_panel.offset_right = -16
	_panel.offset_top = 120
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	root.add_child(UiKit.header(Content.ui("mentor_name") + " — " + Content.ui("mentor_role"), "[Esc]", close))
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	root.add_child(_content)
	PlayerState.onboarding_changed.connect(func(_s: String) -> void: _refresh())


func open(npc: Node3D) -> void:
	_npc = npc
	visible = true
	UiKit.window_opened(self)
	_refresh()


func close() -> void:
	visible = false
	_npc = null
	UiKit.typing = false
	UiKit.window_closed(self)


func _process(_delta: float) -> void:
	if not visible:
		return
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if _npc == null or not is_instance_valid(_npc) or hero == null or hero.global_position.distance_to(_npc.global_position) > CLOSE_DISTANCE:
		close()


func _refresh() -> void:
	if not visible:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match PlayerState.onboarding_step:
		"mentor":
			_say("mentor_intro")
			_content.add_child(UiKit.button(Content.ui("mentor_take"), _first_talk, 15))
		"sack":
			_say("mentor_sack_reminder")
		"return":
			var rules := PlayerState.quest_rules()
			if rules and rules.is_active(PlayerState.quests, "bs_skull") and rules.chosen(PlayerState.quests, "bs_skull", "share").is_empty():
				_choice(rules, "bs_skull", "share")
				return
			_say("mentor_christening")
			_name_edit = LineEdit.new()
			_name_edit.placeholder_text = Content.ui("mentor_name_placeholder")
			_name_edit.max_length = 16
			_name_edit.focus_entered.connect(func() -> void: UiKit.typing = true)
			_name_edit.focus_exited.connect(func() -> void: UiKit.typing = false)
			_name_edit.text_submitted.connect(func(t: String) -> void: _christen(t))
			_content.add_child(_name_edit)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(UiKit.button(Content.ui("mentor_name_ask"), func() -> void: _christen(_name_edit.text), 15))
			row.add_child(UiKit.button(Content.ui("mentor_name_any"), func() -> void: _christen(""), 15))
			_content.add_child(row)
		_:
			_say("mentor_after" if PlayerState.christened else "mentor_busy", {"name": PlayerState.hero_name})


## Выбор миссии (задача 17b): реплика и варианты-кнопки; выбор — PlayerState.quest_choose.
func _choice(rules: QuestRules, mission_id: String, choice_id: String) -> void:
	for c: Dictionary in rules.mission(mission_id).get("choices", []):
		if String(c["id"]) != choice_id:
			continue
		_say(String(c["text"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for option: Dictionary in c["options"]:
			var oid := String(option["id"])
			row.add_child(UiKit.button(Content.ui(String(option["text"])), func() -> void:
				if PlayerState.quest_choose(mission_id, choice_id, oid):
					_refresh(), 15))
		_content.add_child(row)


func _say(key: String, params: Dictionary = {}) -> void:
	var label := UiKit.label(15, UiKit.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 500
	label.text = Content.ui(key, params)
	_content.add_child(label)


## Подарки и задание: споран, живчик, бинт; нож — если в инвентаре нечем вскрыть мешок.
func _first_talk() -> void:
	var mentor: Dictionary = Content.onboarding_rules().config()["mentor"]
	for gift: Array in mentor["gifts"]:
		PlayerState.pick_up(String(gift[0]), int(gift[1]))
	if bool(mentor.get("knife_if_none", true)) and not _has_blade():
		PlayerState.pick_up("knife", 1)
	SystemLog.post("mentor_gifts", {"name": Content.ui("mentor_name")})
	PlayerState.onboarding_event("mentor_talked")


func _has_blade() -> bool:
	var weapons := Content.weapon_db()
	for id in weapons.ids():
		if PlayerState.inventory.count_of(id) > 0 and float(weapons.weapon(id).get("sack_open_mult", 0.0)) > 0.0:
			return true
	return false


func _christen(requested: String) -> void:
	UiKit.typing = false
	var result := PlayerState.christen(requested)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_say("mentor_named_nick" if result["nickname"] else "mentor_named", {"name": result["name"]})
	_content.add_child(UiKit.button(Content.ui("mentor_bye"), close, 15))
