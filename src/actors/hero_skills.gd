extends Node3D
## Умения героя в сцене: клавиши 1–4 — слоты, золотое сияние под Улыбкой Фортуны, всплывающие
## надписи удачи («мимо!», «удача!») и иммунитета. Правила — SkillRules (src/core), применение
## чисел — PlayerState; сценовые эффекты (EventBus.skill_used) — здесь: highlight (Вспышка),
## noise_at (Чревовещатель), enemy_flee (Пугач), noise_zone (Гаситель).
## Спецификация: docs/spec/05_skills.md.

const SLOT_ACTIONS: PackedStringArray = ["skill_1", "skill_2", "skill_3", "skill_4"]
const FLOAT_TEXT := {
	"enemy_miss": ["luck_float_miss", Color(1.0, 0.85, 0.3)],
	"enemy_stumble": ["luck_float_stumble", Color(1.0, 0.85, 0.3)],
	"hero_crit": ["luck_float_crit", Color(1.0, 0.75, 0.15)],
	"unnoticed": ["luck_float_unnoticed", Color(1.0, 0.85, 0.3)],
	"immunity": ["immunity_float", Color(0.7, 0.9, 1.0)],
	"ambush": ["ambush_float", Color(0.75, 0.6, 1.0)],
}
## Подсветка Вспышки: знак и цвет по виду цели.
const HIGHLIGHT := {
	"living": ["◆", Color(1.0, 0.3, 0.25)],
	"sack": ["✦", Color(1.0, 0.85, 0.3)],
	"trophy": ["✦", Color(1.0, 0.75, 0.2)],
	"weapon": ["▲", Color(0.6, 0.85, 1.0)],
	"stash": ["▣", Color(0.85, 0.65, 0.4)],
}

var hero: CharacterBody3D
## Отладка и сценарии: точка прицела умений вместо курсора (Vector3.INF — курсор).
var aim_override := Vector3.INF
var _aura: MeshInstance3D
var _aura_material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_build_aura()
	EventBus.luck_event.connect(_on_luck_event)
	EventBus.skill_used.connect(_on_skill_used)


func _process(delta: float) -> void:
	_time += delta
	var lucky := PlayerState.buffs.multiplier("luck", GameClock.minutes) >= 2.0
	var immune := PlayerState.skills.has_status("immunity", GameClock.minutes)
	_aura.visible = (lucky or immune) and hero.visible
	if _aura.visible:
		var pulse := 0.35 + 0.15 * sin(_time * 6.0)
		_aura_material.albedo_color = Color(0.7, 0.9, 1.0, pulse) if immune else Color(1.0, 0.8, 0.25, pulse)
		_aura.rotation.y += delta * 1.5


func _unhandled_input(event: InputEvent) -> void:
	if not hero.visible:
		return
	for i in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			PlayerState.use_skill_slot(i)
			get_viewport().set_input_as_handled()
			return


func _on_luck_event(kind: String, at: Vector3) -> void:
	if not FLOAT_TEXT.has(kind) or not is_inside_tree():
		return
	var spec: Array = FLOAT_TEXT[kind]
	var where := at if at != Vector3.INF else hero.global_position + Vector3.UP * 2.4
	float_text(get_tree().current_scene, where, Content.ui(spec[0]), spec[1])


func _on_skill_used(_id: String, effects: Array) -> void:
	if not is_inside_tree():
		return
	for e: Dictionary in effects:
		match String(e["type"]):
			"highlight":
				_highlight(e)
			"noise_at":
				_noise_at(e)
			"enemy_flee":
				_scare(e)
			"noise_zone":
				_noise_zone(e)


# --- Вспышка -----------------------------------------------------------------------------------

func _highlight(e: Dictionary) -> void:
	var radius := float(e["radius_m"])
	var seconds := float(e["duration_s"])
	var targets: Array = e["targets"]
	_wave(radius, Color(0.6, 0.85, 1.0, 0.6))
	var count := 0
	for target in highlight_targets(get_tree(), hero.global_position, radius, targets):
		var node: Node3D = target["node"]
		var text := String(HIGHLIGHT[target["kind"]][0])
		if target["kind"] == "living" and bool(e.get("show_level", false)):
			text += " %d" % int(node.level)
		_mark(node, text, HIGHLIGHT[target["kind"]][1], seconds)
		count += 1
	SystemLog.post("skill_pulse", {"n": count, "radius": roundi(radius)})


## Цели Вспышки в радиусе: [{"node", "kind"}]. kinds — living, sack, trophy, weapon, stash.
static func highlight_targets(tree: SceneTree, at: Vector3, radius: float, kinds: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var near := func(node: Node3D) -> bool:
		return Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length() <= radius
	if kinds.has("living"):
		for node: Node3D in tree.get_nodes_in_group("infected"):
			if near.call(node):
				result.append({"node": node, "kind": "living"})
	if kinds.has("sack"):
		for node: Node3D in tree.get_nodes_in_group("infected_corpses"):
			if not node.sack_opened and node.is_in_group("interactable") and near.call(node):
				result.append({"node": node, "kind": "sack"})
	for node: Node3D in tree.get_nodes_in_group("interactable"):
		if not ("item_id" in node) or not near.call(node):
			continue
		var category := Content.item_db().category(String(node.item_id))
		if category == "trophy" and kinds.has("trophy"):
			result.append({"node": node, "kind": "trophy"})
		elif category == "weapon" and kinds.has("weapon"):
			result.append({"node": node, "kind": "weapon"})
	if kinds.has("stash"):
		for node: Node3D in tree.get_nodes_in_group("stashes"):
			if not node.found and near.call(node):
				result.append({"node": node, "kind": "stash"})
	return result


## Метка над целью сквозь стены (no_depth_test): следует за целью, гаснет через seconds.
func _mark(node: Node3D, text: String, color: Color, seconds: float) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.016
	label.outline_size = 10
	label.text = text
	label.modulate = color
	label.position = Vector3.UP * 2.6
	label.add_to_group("skill_marks")
	node.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(maxf(0.0, seconds - 1.5))
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)


## Волна от героя: кольцо расходится до radius за 0,6 с.
func _wave(radius: float, color: Color) -> void:
	var ring := _ground_ring(1.0, color)
	get_tree().current_scene.add_child(ring)
	ring.global_position = hero.global_position + Vector3.UP * 0.1
	var material := ring.material_override as StandardMaterial3D
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.05, radius), 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(ring.queue_free)


# --- Чревовещатель -----------------------------------------------------------------------------

func _noise_at(e: Dictionary) -> void:
	var point := _aim_point(float(e["range_m"]))
	var source := String(e["source"])
	for i in int(e.get("count", 1)):
		if i > 0:
			await get_tree().create_timer(float(e.get("repeat_s", 2.5))).timeout
			if not is_inside_tree():
				return
		EventBus.noise_made.emit(source, point, {})
		float_text(get_tree().current_scene, point + Vector3.UP * 1.5, Content.ui("voice_float"), Color(0.9, 0.9, 1.0))


## Точка под курсором на земле, не дальше range от героя.
func _aim_point(reach: float) -> Vector3:
	var target := hero.global_position - hero.global_transform.basis.z * reach
	var camera: Camera3D = hero.camera
	if aim_override != Vector3.INF:
		target = aim_override
	elif camera:
		var mouse := get_viewport().get_mouse_position()
		var hit: Variant = Plane(Vector3.UP, hero.global_position.y).intersects_ray(
			camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if hit != null:
			target = hit
	var offset := target - hero.global_position
	offset.y = 0.0
	if offset.length() > reach:
		offset = offset.normalized() * reach
	return hero.global_position + offset


# --- Пугач -------------------------------------------------------------------------------------

func _scare(e: Dictionary) -> void:
	var radius := float(e["radius_m"])
	var max_stage := int(e["max_stage"])
	_wave(radius, Color(0.6, 0.8, 1.0, 0.5))
	var scared := 0
	for node: Node3D in get_tree().get_nodes_in_group("infected"):
		var stage := int(Content.enemy_db().enemy(node.enemy_id)["stage"])
		if stage > max_stage or hero.global_position.distance_to(node.global_position) > radius:
			continue
		node.scare(hero.global_position, float(e["duration_s"]))
		scared += 1
	SystemLog.post("skill_scare", {"n": scared})


# --- Гаситель ----------------------------------------------------------------------------------

func _noise_zone(e: Dictionary) -> void:
	var system := get_tree().get_first_node_in_group("noise_system")
	if system == null:
		return
	var follow: Node3D = hero if String(e.get("anchor", "point")) == "hero" else null
	var radius := float(e["radius_m"])
	var seconds := float(e["duration_s"])
	system.add_zone(hero.global_position, radius, float(e["mult"]), seconds, follow)
	var ring := _ground_ring(radius, Color(0.55, 0.6, 0.9, 0.35))
	if follow:
		add_child(ring)
		ring.position = Vector3.UP * 0.06
	else:
		get_tree().current_scene.add_child(ring)
		ring.global_position = hero.global_position + Vector3.UP * 0.06
	var material := ring.material_override as StandardMaterial3D
	var tween := ring.create_tween()
	tween.tween_interval(maxf(0.0, seconds - 1.0))
	tween.tween_property(material, "albedo_color:a", 0.0, 1.0)
	tween.tween_callback(ring.queue_free)


func _ground_ring(radius: float, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.0, radius - 0.12) if radius > 1.0 else 0.88
	torus.outer_radius = radius
	torus.rings = 64
	torus.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.05, 1)
	return ring


## Всплывающая надпись над точкой: поднимается и гаснет за 0,9 с.
static func float_text(parent: Node, at: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.014
	label.outline_size = 8
	label.text = text
	label.modulate = color
	parent.add_child(label)
	label.global_position = at
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", at.y + 1.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(label.queue_free)


func _build_aura() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.75
	torus.rings = 32
	torus.ring_segments = 6
	_aura_material = StandardMaterial3D.new()
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.albedo_color = Color(1.0, 0.8, 0.25, 0.4)
	_aura = MeshInstance3D.new()
	_aura.mesh = torus
	_aura.material_override = _aura_material
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.position = Vector3(0, 0.08, 0)
	_aura.scale = Vector3(1, 0.15, 1)
	_aura.visible = false
	add_child(_aura)
