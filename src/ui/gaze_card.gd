extends CanvasLayer
## Пристальный взгляд (12.3): пока зажат Alt, цель под курсором получает карточку — цвет панели по
## виду цели (объект, иммунный, «красный», вещь), поля — по глубине взгляда (GazeRules). Цель —
## любой узел с gaze_info() в группах тварей и интерактивных, в пределах дальности и не за стеной.
## Новая осмотренная тварь или непись даёт немного прогресса Наблюдательности (gaze_new).

const GROUPS: PackedStringArray = ["infected", "interactable", "infected_corpses", "corpses"]
const EYE := Vector3(0, 1.5, 0)
const LAYER_WORLD := 1
const OFFSET := Vector2(34, -20)
## Как часто перечитывать цель, пока на неё смотрят (здоровье, состояние).
const REFRESH_S := 0.3

var _rules: GazeRules
var _panel: PanelContainer
var _style: StyleBoxFlat
var _lines: VBoxContainer
var _marker: Control
var _target: Node3D
var _target_screen := Vector2.ZERO
## Уже осмотренные цели (id экземпляров) — прогресс только за новые.
var _seen: Dictionary = {}
var _refresh_left := 0.0
## Карточка закреплена кодом (show_target) — не прятать без Alt.
var _pinned := false


func _ready() -> void:
	layer = 4
	add_to_group("gaze_card")
	_rules = Content.gaze_rules()
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.04, 0.05, 0.06, 0.88)
	_style.set_content_margin_all(12)
	_style.set_border_width_all(0)
	_style.border_width_left = 4
	_style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	_panel.add_child(_lines)
	_panel.visible = false


func _process(delta: float) -> void:
	var holding := Input.is_action_pressed("gaze") and not PlayerState.awaiting_respawn
	if holding:
		_pinned = false
	var target := _target if _pinned and is_instance_valid(_target) else (_pick() if holding else null)
	_refresh_left -= delta
	if target != _target or (target and _refresh_left <= 0.0):
		_target = target
		_refresh_left = REFRESH_S
		if target:
			_show(target)
	if _target == null:
		_panel.visible = false
		_marker.queue_redraw()
		return
	_place()
	_marker.queue_redraw()


## Показать карточку цели сразу (отладка --gaze и сценарии).
func show_target(target: Node3D) -> void:
	_target = target
	_pinned = true
	_show(target)
	_place()


## Цель под курсором: ближайшая к нему на экране, в пределах pick_px. Текущая держится, пока курсор
## не ушёл от неё вдвое дальше (без дрожи между соседними целями).
func _pick() -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if camera == null or hero == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var pick := float(_rules.config()["pick_px"])
	var reach := _rules.range_m(PlayerState.stats.get_level("perception"))
	var best: Node3D = null
	var best_px := pick
	for group in GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			var target := node as Node3D
			if target == null or not target.has_method("gaze_info") or not target.is_visible_in_tree() \
					or target.is_queued_for_deletion():
				continue
			if target.global_position.distance_to(hero.global_position) > reach or camera.is_position_behind(target.global_position):
				continue
			var px := camera.unproject_position(target.global_position + Vector3.UP * 0.8).distance_to(mouse)
			if target == _target:
				px *= 0.5
			if px < best_px and _in_sight(hero, target) and _vision_sees(target):
				best = target
				best_px = px
	return best


## Зрение героя (14a): цель вне конуса или за стеной не осмотреть.
func _vision_sees(target: Node3D) -> bool:
	var vision := get_tree().get_first_node_in_group("hero_vision")
	return vision == null or vision.is_seen(target)


func _in_sight(hero: Node3D, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(hero.global_position + EYE,
		target.global_position + Vector3.UP * 0.6, LAYER_WORLD)
	return hero.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _show(target: Node3D) -> void:
	var subject: Dictionary = target.gaze_info()
	var card := _rules.card(subject, PlayerState.effective("perception"))
	_style.border_color = _rules.color(card["category"])
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	var title := UiKit.label(18, _rules.color(card["category"]))
	var name := String(subject.get("name", "?")) if not card["unavailable"] else Content.ui("gaze_unknown_" + String(subject.get("kind", "item")))
	title.text = name.left(1).to_upper() + name.substr(1)
	_lines.add_child(title)
	var kind_line := Content.ui("gaze_category_" + String(card["category"]))
	if not kind_line.is_empty() and card["category"] != "thing" and not card["unavailable"]:
		_line(kind_line, Color(0.7, 0.72, 0.75), 13)
	if card["unavailable"]:
		_line(Content.ui("gaze_unavailable"), Color(0.95, 0.5, 0.4))
		if PlayerState.run.count("gaze_unavailable") == 0:
			SystemLog.post("gaze_unavailable_hint", {})
		PlayerState.run.add("gaze_unavailable")
	for field: Array in card["fields"]:
		var key := String(field[0])
		if key in ["name", "category"]:
			continue
		_line(_format(key, field[1]), Color(0.88, 0.9, 0.86))
	if card["morok"]:
		_line(Content.ui("gaze_morok"), Color(0.75, 0.6, 1.0))
	_panel.reset_size()
	_panel.visible = true
	var id := target.get_instance_id()
	if not _seen.has(id) and not card["unavailable"] and String(subject.get("kind", "")) in ["infected", "npc"]:
		_seen[id] = true
		PlayerState.award("gaze_new")


func _format(key: String, value: Variant) -> String:
	var text := ""
	match key:
		"level_range":
			text = "%d–%d" % [int(value[0]), int(value[1])] if int(value[0]) != int(value[1]) else str(int(value[0]))
		"level", "count":
			text = str(int(value))
		"threat":
			text = Content.ui("threat_" + String(value))
		"health", "humanity", "sack":
			text = Content.ui("gaze_" + String(value))
		"state":
			text = Content.ui("gaze_state_" + String(value))
		"hunger":
			text = "%d%%" % roundi(float(value) * 100.0)
		"weight":
			text = Content.ui("gaze_grams", {"g": roundi(float(value))}) if float(value) < 1000.0 \
				else Content.ui("gaze_kg", {"kg": String.num(float(value) / 1000.0, 1)})
		"price":
			text = Content.ui("gaze_spores", {"n": int(value)})
		"equipment":
			var names: PackedStringArray = []
			for id: String in value:
				names.append(Content.item_name(id))
			text = ", ".join(names)
		"armor":
			var parts: PackedStringArray = []
			for zone: String in value:
				parts.append("%s %d" % [Content.ui("zone_" + zone), roundi(float(value[zone]))])
			text = ", ".join(parts)
		"traits":
			var parts: PackedStringArray = []
			for trait_key: String in value:
				parts.append(Content.ui("gaze_" + trait_key))
			text = ", ".join(parts)
		_:
			text = str(value)
	return Content.ui("gaze_field_" + key, {"v": text})


func _line(text: String, color: Color, size: int = 15) -> void:
	var label := UiKit.label(size, color)
	label.text = text
	_lines.add_child(label)


func _place() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(_target):
		_target = null
		return
	_target_screen = camera.unproject_position(_target.global_position + Vector3.UP * 0.8)
	var view := _panel.get_viewport_rect().size
	var size := _panel.size
	var at := _target_screen + OFFSET
	if at.x + size.x > view.x - 8.0:
		at.x = _target_screen.x - OFFSET.x - size.x
	at.y = clampf(at.y - size.y * 0.3, 8.0, view.y - size.y - 8.0)
	at.x = clampf(at.x, 8.0, view.x - size.x - 8.0)
	_panel.position = at


## Уголки вокруг цели — в цвет панели.
func _draw_marker() -> void:
	if _target == null or not _panel.visible:
		return
	var color := _style.border_color
	var r := 22.0
	var arm := 8.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := _target_screen + Vector2(sx * r, sy * r)
			_marker.draw_line(corner, corner - Vector2(sx * arm, 0), color, 2.0)
			_marker.draw_line(corner, corner - Vector2(0, sy * arm), color, 2.0)
