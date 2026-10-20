extends Node3D
## Зрение героя (17, D-69): твари, лут и трупы вне конуса взгляда или за стеной не рисуются; где
## тварь видели последний раз — бледный силуэт, гаснет. Вне конуса мир затемнён (полноэкранный
## шейдер по глубине). Стены между камерой и героем полупрозрачны. Чуйка — «!» в сторону угрозы в
## слепой зоне (значок рисует src/ui/sense_indicator.gd по alarms). Правила — VisionRules.
##
## Прячутся только меши и подписи цели; метки умений (группа "skill_marks") видны всегда.

const LAYER_WORLD := 1
const EYE := Vector3(0, 1.5, 0)
const WALL_CHECK_S := 0.1
const SHADE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 hero_pos;
uniform vec2 facing = vec2(0.0, -1.0);
uniform float half_cone = 0.96;
uniform float reach = 30.0;
uniform float near_r = 2.5;
uniform float strength = 0.45;
uniform float soft_angle = 0.14;
uniform float soft_dist = 3.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 to = world.xz - hero_pos.xz;
	float d = length(to);
	float ang = acos(clamp(dot(to / max(d, 0.0001), facing), -1.0, 1.0));
	float shade = max(smoothstep(half_cone - soft_angle * 0.5, half_cone + soft_angle * 0.5, ang),
		smoothstep(reach - soft_dist, reach, d));
	shade *= smoothstep(near_r - 0.4, near_r + 0.4, d);
	ALBEDO = vec3(0.0);
	ALPHA = shade * strength;
}
"""

var hero: CharacterBody3D
## Направление взгляда (единичное, XZ): догоняет поворот героя со скоростью от Реакции.
var view_dir := Vector3.FORWARD
## Сработавшая чуйка: {id твари: {"node", "left" (с), "since" (мс)}}.
var alarms: Dictionary = {}

var _rules: VisionRules
var _seen: Dictionary = {}
var _ghosts: Dictionary = {}
var _check_left := 0.0
var _sense_left := 0.0
var _wall_left := 0.0
var _faded: Dictionary = {}
## Чуйка сработала — ждём, увидит ли герой угрозу (подтверждение): {id: мс}.
var _sensed_at: Dictionary = {}
var _shade: MeshInstance3D
var _shade_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _reach := 30.0
var _cone := 110.0


func _ready() -> void:
	add_to_group("hero_vision")
	_rules = Content.vision_rules()
	_rng.randomize()
	_build_shade.call_deferred()


func _exit_tree() -> void:
	for body: Node in _faded:
		if is_instance_valid(body):
			_set_fade(body, 0.0)


## Видит ли герой цель. Узлы, за которыми зрение не следит (неписи, двери), — всегда.
func is_seen(node: Node) -> bool:
	return bool(_seen.get(node.get_instance_id(), not _tracked(node)))


## Точка в конусе взгляда и в дальности (без проверки стен) — для знания карты.
func sees_point(point: Vector3) -> bool:
	if hero == null:
		return false
	return _rules.in_view(hero.global_position, view_dir, point, _cone, _reach)


func _process(delta: float) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var alive := hero.visible and not PlayerState.awaiting_respawn
	var forward := -hero.global_transform.basis.z
	view_dir = VisionRules.turn_towards(view_dir, forward, _rules.turn_speed(PlayerState.stats.get_level("reaction")) * delta)
	var perception := PlayerState.stats.get_level("perception")
	_reach = _rules.view_range(int(GameClock.minutes / 60.0) % 24, WorldSim.is_kislyak(), perception)
	_cone = _rules.cone_deg(bool(hero.get("is_sprinting")), perception)
	_update_shade(alive)
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = float(_rules.config()["check_s"])
		_check_all(alive)
	var sense: Dictionary = _rules.config()["sense"]
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = float(sense["check_s"])
		if alive:
			_sense_tick()
	for id in alarms.keys():
		alarms[id]["left"] = float(alarms[id]["left"]) - delta
		if float(alarms[id]["left"]) <= 0.0 or not is_instance_valid(alarms[id]["node"]):
			alarms.erase(id)
	_wall_left -= delta
	if _wall_left <= 0.0:
		_wall_left = WALL_CHECK_S
		_fade_walls()


func _tracked(node: Node) -> bool:
	if node.is_in_group("infected") or node.is_in_group("infected_corpses"):
		return true
	return node.is_in_group("interactable") and "item_id" in node


func _targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group in ["infected", "infected_corpses", "interactable"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is Node3D and _tracked(node) and not node.is_queued_for_deletion() and not result.has(node):
				result.append(node)
	return result


func _check_all(alive: bool) -> void:
	var space := get_world_3d().direct_space_state
	var alive_ids := {}
	for node in _targets():
		var id := node.get_instance_id()
		alive_ids[id] = true
		var seen := true
		if alive:
			seen = _rules.in_view(hero.global_position, view_dir, node.global_position, _cone, _reach) \
				and _clear_line(space, node)
		var known := _seen.has(id)
		var was := bool(_seen.get(id, true))
		if not known or was != seen:
			_seen[id] = seen
			_apply(node, seen)
			if node.is_in_group("infected"):
				if seen:
					_drop_ghost(id)
					_confirm_sense(id)
					_first_sight(node)
				elif known:
					_spawn_ghost(id, node)
	for id in _seen.keys():
		if not alive_ids.has(id):
			_seen.erase(id)


func _clear_line(space: PhysicsDirectSpaceState3D, node: Node3D) -> bool:
	var height := 1.1 if node.is_in_group("infected") else 0.25
	var query := PhysicsRayQueryParameters3D.create(hero.global_position + EYE, node.global_position + Vector3.UP * height, LAYER_WORLD)
	return space.intersect_ray(query).is_empty()


## Показать или спрятать меши и подписи цели (кроме меток умений).
static func _apply(node: Node, seen: bool) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D and not child.is_in_group("skill_marks"):
			child.visible = seen


# --- Отметка последнего места ------------------------------------------------------------------

func _spawn_ghost(id: int, node: Node3D) -> void:
	_drop_ghost(id)
	var data := Content.enemy_db().enemy(String(node.get("enemy_id")))
	var body: Dictionary = data["body"]
	var radius := float(body["radius"])
	var height := maxf(float(body["height"]), radius * 2.0)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.85, 0.9, 1.0, 0.28)
	material.render_priority = 1
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh
	ghost.material_override = material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = node.global_position + Vector3.UP * height / 2.0
	ghost.add_to_group("vision_ghosts")
	_ghosts[id] = ghost
	var tween := ghost.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, float(_rules.config()["last_seen_s"]))
	tween.tween_callback(func() -> void:
		if _ghosts.get(id) == ghost:
			_ghosts.erase(id)
		ghost.queue_free())


func _drop_ghost(id: int) -> void:
	var ghost: Node = _ghosts.get(id)
	_ghosts.erase(id)
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()


# --- Чуйка -------------------------------------------------------------------------------------

func _sense_tick() -> void:
	var sense: Dictionary = _rules.config()["sense"]
	var radius := float(sense["radius_m"])
	var perception := PlayerState.effective("perception")
	var reaction := PlayerState.effective("reaction")
	for node: Node in get_tree().get_nodes_in_group("infected"):
		var target := node as Node3D
		var id := target.get_instance_id()
		if is_seen(target) or alarms.has(id):
			continue
		var distance := target.global_position.distance_to(hero.global_position)
		if distance > radius:
			continue
		var info: Dictionary = target.sense_info() if target.has_method("sense_info") else {}
		var chance := _rules.sense_chance(perception, reaction, float(info.get("stealth", 0.0)),
			int(info.get("level", 0)), distance, bool(info.get("alert", false)), float(info.get("hush", 0.0)))
		if _rng.randf() < chance:
			alarms[id] = {"node": target, "left": float(sense["hold_s"])}
			_sensed_at[id] = Time.get_ticks_msec()
			if PlayerState.run.count("sense_triggered") == 0:
				SystemLog.post("sense_first", {}, "special")
			PlayerState.run.add("sense_triggered")


## Первая встреча с видом тварей за игру — справка Системы (лог, задача 16).
func _first_sight(node: Node3D) -> void:
	var enemy := String(node.get("enemy_id"))
	if enemy.is_empty() or PlayerState.run.count("seen_" + enemy) > 0:
		return
	PlayerState.run.add("seen_" + enemy)
	var data := Content.enemy_db().enemy(enemy)
	SystemLog.post("species_seen", {"enemy": Content.enemy_name(enemy), "threat": Content.ui("threat_" + String(data["threat"]))}, "info")


## Чуйка подтвердилась: угрозу увидели вскоре после «!» — немного Наблюдательности.
func _confirm_sense(id: int) -> void:
	if not _sensed_at.has(id):
		return
	var since := Time.get_ticks_msec() - int(_sensed_at[id])
	_sensed_at.erase(id)
	if since <= float(_rules.config()["sense"]["confirm_s"]) * 1000.0:
		PlayerState.award("sense_confirmed")


# --- Затемнение вне конуса ---------------------------------------------------------------------

func _build_shade() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var shader := Shader.new()
	shader.code = SHADE_SHADER
	_shade_material = ShaderMaterial.new()
	_shade_material.shader = shader
	_shade_material.render_priority = -100
	_shade = MeshInstance3D.new()
	_shade.mesh = quad
	_shade.material_override = _shade_material
	_shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shade.extra_cull_margin = 16384.0
	_shade.position = Vector3(0, 0, -1)
	camera.add_child(_shade)


func _update_shade(alive: bool) -> void:
	if _shade_material == null:
		return
	var c := _rules.config()
	var strength := float(c["shade"]) if alive else 0.0
	_shade.visible = strength > 0.0
	_shade_material.set_shader_parameter("hero_pos", hero.global_position)
	_shade_material.set_shader_parameter("facing", Vector2(view_dir.x, view_dir.z).normalized())
	_shade_material.set_shader_parameter("half_cone", deg_to_rad(_cone / 2.0))
	_shade_material.set_shader_parameter("reach", _reach)
	_shade_material.set_shader_parameter("near_r", float(c["near_m"]))
	_shade_material.set_shader_parameter("strength", strength)
	_shade_material.set_shader_parameter("soft_angle", deg_to_rad(float(c["shade_soft_deg"])))
	_shade_material.set_shader_parameter("soft_dist", float(c["shade_soft_m"]))


# --- Прозрачные стены --------------------------------------------------------------------------

## Стены и предметы между камерой и героем — полупрозрачные (17.3).
func _fade_walls() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var space := get_world_3d().direct_space_state
	var hit := {}
	if hero.visible:
		for height: float in [0.9, 1.7]:
			var target := hero.global_position + Vector3.UP * height
			var from := target + camera.global_transform.basis.z * 60.0
			var exclude: Array[RID] = []
			for i in 4:
				var query := PhysicsRayQueryParameters3D.create(from, target, LAYER_WORLD, exclude)
				var result := space.intersect_ray(query)
				if result.is_empty():
					break
				var body := result["collider"] as Node
				exclude.append(result["rid"])
				if body:
					hit[body] = true
	var alpha := float(_rules.config()["fade_walls_alpha"])
	for body: Node in hit:
		if not _faded.has(body):
			_set_fade(body, alpha)
	for body: Node in _faded.keys():
		if not hit.has(body):
			if is_instance_valid(body):
				_set_fade(body, 0.0)
	_faded = hit


static func _set_fade(body: Node, alpha: float) -> void:
	for child in body.get_children():
		if child is GeometryInstance3D:
			child.transparency = alpha
