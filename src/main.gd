extends Node3D
## Прототип M0: земля, препятствия, герой, изометрическая камера, отладочный HUD.
## Всё собирается кодом, чтобы сцена была читаемой в diff.

const PlayerScript := preload("res://src/actors/player.gd")
const IsoCameraScript := preload("res://src/world/iso_camera.gd")
const DebugHudScript := preload("res://src/ui/debug_hud.gd")

const GROUND_SIZE := 200.0
const OBSTACLE_COUNT := 40
const OBSTACLE_SEED := 74920891


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_environment()
	_build_ground()
	_build_obstacles()

	var player: CharacterBody3D = PlayerScript.new()
	player.name = "Player"
	player.position = Vector3(0, 0.1, 0)
	add_child(player)

	var camera: Camera3D = IsoCameraScript.new()
	camera.target = player
	add_child(camera)
	player.camera = camera

	add_child(DebugHudScript.new())
	SystemLog.post("welcome")
	_handle_debug_args()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_die"):
		PlayerState.die("debug")


## Отладочные аргументы после «--»:
##   --demo        герой сам бежит вперёд (проверка прокачки Скорости)
##   --shot=PATH   через 4 секунды сохранить скриншот в PATH и выйти
func _handle_debug_args() -> void:
	var shot_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			Input.action_press("move_forward")
			Input.action_press("sprint")
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
	if shot_path.is_empty():
		return
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1, GROUND_SIZE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	add_child(_static_body(box, Vector3(0, -0.5, 0), plane, Vector3.ZERO, Color(0.36, 0.42, 0.3)))


## Случайные «дома» и «ящики» — детерминированно по сиду, чтобы сцена не менялась между запусками.
func _build_obstacles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = OBSTACLE_SEED
	var placed := 0
	while placed < OBSTACLE_COUNT:
		var at := Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
		if at.length() < 6.0:
			continue
		var size := Vector3(rng.randf_range(1, 6), rng.randf_range(1, 4), rng.randf_range(1, 6))
		var box := BoxShape3D.new()
		box.size = size
		var mesh := BoxMesh.new()
		mesh.size = size
		var shade := rng.randf_range(0.45, 0.7)
		var center := at + Vector3(0, size.y / 2.0, 0)
		add_child(_static_body(box, center, mesh, center, Color(shade, shade * 0.95, shade * 0.9)))
		placed += 1


func _static_body(shape: Shape3D, shape_at: Vector3, mesh: Mesh, mesh_at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = shape_at
	body.add_child(collision)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = mesh_at
	body.add_child(instance)
	return body
