extends CanvasLayer
## Слоты умений справа над шкалами (клавиши 1–4): название, откат или остаток действия, пассив,
## «✕» — умения заглушены. Только открытые слоты (D-17). Данные — PlayerState.skills.

## Над полосками шкал (vitals_bars.gd, ~280 px высотой).
const ABOVE_VITALS := 250.0

var _box: VBoxContainer
var _cells: Array[Label] = []
var _blocked: Label


func _ready() -> void:
	layer = 3
	var root := VBoxContainer.new()
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_right = -16
	root.offset_bottom = -ABOVE_VITALS
	root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.alignment = BoxContainer.ALIGNMENT_END
	add_child(root)
	_blocked = UiKit.label(13, Color(0.95, 0.4, 0.35))
	_blocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_blocked)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	root.add_child(_box)
	for i in 4:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.06, 0.07, 0.75)
		style.set_content_margin_all(6)
		style.set_corner_radius_all(3)
		panel.add_theme_stylebox_override("panel", style)
		var label := UiKit.label(13)
		label.custom_minimum_size.x = 268
		panel.add_child(label)
		_box.add_child(panel)
		_cells.append(label)


func _process(_delta: float) -> void:
	var skills := PlayerState.skills
	var now := GameClock.minutes
	var open := skills.slot_count(PlayerState.stats.general_level())
	var any := false
	for i in _cells.size():
		var label := _cells[i]
		var panel := label.get_parent() as Control
		panel.visible = i < open
		if i >= open:
			continue
		var id := skills.slots[i]
		any = any or not id.is_empty()
		label.text = _cell_text(i, id, now)
		label.add_theme_color_override("font_color", _cell_color(id, now))
	_box.visible = any
	_blocked.text = Content.ui("skills_blocked") if skills.is_blocked() and any else ""


func _cell_text(i: int, id: String, now: float) -> String:
	var params := {"n": i + 1}
	if id.is_empty():
		return Content.ui("skill_slot_empty", params)
	var skills := PlayerState.skills
	params["name"] = Content.skill_name(id)
	if skills.is_blocked():
		return Content.ui("skill_slot_blocked", params)
	if skills.is_passive(id):
		return Content.ui("skill_slot_passive", params)
	var active := PlayerState.buffs.left("skill:" + id, now)
	if active > 0.0:
		params["left"] = "%d с" % ceili(active / _minutes_per_second())
		return Content.ui("skill_slot_active", params)
	var left := skills.cooldown_left(id, now)
	if left > 0.0:
		params["left"] = PlayerState.cooldown_text(left)
		return Content.ui("skill_slot_cd", params)
	return Content.ui("skill_slot_ready", params)


func _cell_color(id: String, now: float) -> Color:
	var skills := PlayerState.skills
	if id.is_empty():
		return Color(0.5, 0.5, 0.5)
	if skills.is_blocked():
		return Color(0.6, 0.4, 0.4)
	if skills.is_passive(id):
		return Color(0.65, 0.8, 0.95)
	if PlayerState.buffs.left("skill:" + id, now) > 0.0:
		return Color(1.0, 0.8, 0.25)
	if skills.cooldown_left(id, now) > 0.0:
		return Color(0.6, 0.6, 0.6)
	var mana_ok := PlayerState.vitals.value(Vitals.MANA) >= skills.mana_cost(id, PlayerState.skill_levels())
	return Color(0.95, 0.95, 0.9) if mana_ok else Color(0.5, 0.6, 0.9)


func _minutes_per_second() -> float:
	return GameClock.game_minutes_for(1.0)
