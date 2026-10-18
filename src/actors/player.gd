extends CharacterBody3D
## Герой: движение относительно камеры, спринт качает Скорость, поворот к курсору.

var camera: Camera3D

var _tuning: Dictionary
var _sprint_meters: float = 0.0


func _ready() -> void:
	_tuning = Content.player_tuning()
	_build_body()
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
	var sprinting := Input.is_action_pressed("sprint") and direction.length() > 0.1
	var speed: float = float(_tuning["sprint_speed"]) if sprinting else float(_tuning["walk_speed"])
	speed *= 1.0 + float(_tuning["speed_bonus_per_level"]) * (PlayerState.stats.get_level("speed") - 1)

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= float(_tuning["gravity"]) * delta

	var before := global_position
	move_and_slide()
	if sprinting:
		_count_sprint(Vector2(global_position.x - before.x, global_position.z - before.z).length())
	_face_cursor()


## Спринт качает Скорость: очки за каждый целый пробежанный метр.
func _count_sprint(meters: float) -> void:
	_sprint_meters += meters
	if _sprint_meters < 1.0:
		return
	var whole := floorf(_sprint_meters)
	_sprint_meters -= whole
	PlayerState.add_progress("speed", whole * float(_tuning["sprint_progress_per_meter"]))


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
	add_child(_mesh(body_mesh, Vector3(0, 0.9, 0), Color(0.85, 0.75, 0.55)))

	# «Нос» показывает, куда смотрит герой (вперёд в Godot — это −Z).
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.15, 0.15, 0.4)
	add_child(_mesh(nose_mesh, Vector3(0, 1.5, -0.4), Color(0.2, 0.2, 0.2)))


func _mesh(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance
