extends CharacterBody3D
## Герой: движение относительно камеры, спринт качает Скорость, поворот к курсору.
## Шаги шумят (EventBus.noise_made); C — красться: медленнее, тише, заметнее хуже.

const HeroCombatScript := preload("res://src/actors/hero_combat.gd")
const HeroChannelScript := preload("res://src/actors/hero_channel.gd")
const HeroSkillsScript := preload("res://src/actors/hero_skills.gd")

var camera: Camera3D
var combat: Node3D
var channel: Node
var skills: Node3D
## Ближайший объект для E (группа "interactable"), или null.
var current_interactable: Node3D
var sneaking := false

var _tuning: Dictionary
var _sprint_meters: float = 0.0
var _step_meters: float = 0.0
var _carry_meters: float = 0.0
var _body_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	_tuning = Content.player_tuning()
	_build_body()
	add_to_group("hero")
	collision_layer = 2
	collision_mask = 1 | 4
	combat = HeroCombatScript.new()
	combat.hero = self
	add_child(combat)
	channel = HeroChannelScript.new()
	channel.hero = self
	add_child(channel)
	skills = HeroSkillsScript.new()
	skills.hero = self
	add_child(skills)
	SaveService.register("hero", self)


func _exit_tree() -> void:
	SaveService.unregister("hero")


func to_dict() -> Dictionary:
	return {"position": [global_position.x, global_position.y, global_position.z], "yaw": rotation.y}


func load_dict(data: Dictionary) -> void:
	var at: Array = data["position"]
	global_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	rotation.y = float(data["yaw"])
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	if camera:
		direction = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera.global_rotation.y)
	var vitals := PlayerState.vitals
	var sprinting := Input.is_action_pressed("sprint") and direction.length() > 0.1 and vitals.can_sprint()
	if sprinting and sneaking:
		_set_sneaking(false)
	var inventory := PlayerState.inventory
	# Второе дыхание: бег без расхода бодрости.
	var free_sprint := PlayerState.skills.has_status("free_sprint", GameClock.minutes)
	vitals.tick(delta, GameClock.game_minutes_for(delta), sprinting, 0.0 if free_sprint else inventory.stamina_cost_multiplier())
	var speed: float = float(_tuning["sprint_speed"]) if sprinting else float(_tuning["walk_speed"])
	if sneaking:
		speed = float(_tuning["sneak_speed"])
	speed *= 1.0 + float(_tuning["speed_bonus_per_level"]) * (PlayerState.stats.get_level("speed") - 1)
	speed *= vitals.speed_multiplier() * inventory.speed_multiplier()
	speed *= PlayerState.buffs.multiplier("speed", GameClock.minutes)  # Споровый форсаж

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= float(_tuning["gravity"]) * delta

	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if sprinting:
		_count_sprint(moved)
	if inventory.is_overloaded():
		_count_carry(moved)
	_count_steps(moved, "sprint" if sprinting else ("sneak" if sneaking else "walk"))
	_face_cursor()
	current_interactable = _nearest_interactable()


## Во сколько раз хуже героя видно (крадётся — дальность зрения тварей меньше).
func visibility_multiplier() -> float:
	return float(_tuning["sneak_visibility"]) if sneaking else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sneak"):
		_set_sneaking(not sneaking)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and current_interactable:
		current_interactable.interact(self)
		get_viewport().set_input_as_handled()


func _nearest_interactable() -> Node3D:
	var radius := float(_tuning["interact_radius"])
	var best: Node3D = null
	var best_distance := radius
	for node: Node3D in get_tree().get_nodes_in_group("interactable"):
		if node.is_queued_for_deletion():
			continue
		var distance := Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length()
		if distance <= best_distance:
			best = node
			best_distance = distance
	return best


## Спринт качает Скорость, ходьба с перегрузом — Силу: очки за каждый целый метр (3.2).
func _count_sprint(meters: float) -> void:
	_sprint_meters += meters
	if _sprint_meters < 1.0:
		return
	var whole := floorf(_sprint_meters)
	_sprint_meters -= whole
	PlayerState.award("sprint_meter", whole)


func _count_carry(meters: float) -> void:
	_carry_meters += meters
	if _carry_meters < 1.0:
		return
	var whole := floorf(_carry_meters)
	_carry_meters -= whole
	PlayerState.award("carry_overloaded_meter", whole)


## Шаг — шумовой импульс. Длина шага зависит от режима, радиус — от Скрытности и перегруза.
func _count_steps(meters: float, mode: String) -> void:
	_step_meters += meters
	var noise: NoiseModel = _noise_model()
	if noise == null or _step_meters < noise.step_length(mode):
		return
	_step_meters = 0.0
	EventBus.noise_made.emit(mode + "_step", global_position, {
		"stealth_level": PlayerState.stats.get_level("stealth"),
		"load_ratio": PlayerState.inventory.load_ratio(), "from_hero": true,
	})


func _noise_model() -> NoiseModel:
	var system := get_tree().get_first_node_in_group("noise_system")
	return system.model if system else null


func _set_sneaking(value: bool) -> void:
	sneaking = value
	for mesh in _body_meshes:
		mesh.scale.y = 0.75 if sneaking else 1.0


func _face_cursor() -> void:
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return
	var target: Vector3 = hit
	target.y = global_position.y
	if target.distance_to(global_position) > 0.3:
		look_at(target, Vector3.UP)


func _build_body() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.8
	var body := _mesh(body_mesh, Vector3(0, 0.9, 0), Color(0.85, 0.75, 0.55))
	add_child(body)
	_body_meshes.append(body)

	# «Нос» показывает, куда смотрит герой (вперёд в Godot — это −Z).
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.15, 0.15, 0.4)
	var nose := _mesh(nose_mesh, Vector3(0, 1.5, -0.4), Color(0.2, 0.2, 0.2))
	add_child(nose)


func _mesh(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance
