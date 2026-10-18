extends Node3D
## Прототип M0: земля, препятствия, герой, изометрическая камера, отладочный HUD.
## Всё собирается кодом, чтобы сцена была читаемой в diff.

const PlayerScript := preload("res://src/actors/player.gd")
const IsoCameraScript := preload("res://src/world/iso_camera.gd")
const DebugHudScript := preload("res://src/ui/debug_hud.gd")
const VitalsBarsScript := preload("res://src/ui/vitals_bars.gd")
const DeathFlowScript := preload("res://src/world/death_flow.gd")
const WorldItemsScript := preload("res://src/world/world_items.gd")
const InventoryPanelScript := preload("res://src/ui/inventory_panel.gd")
const InteractPromptScript := preload("res://src/ui/interact_prompt.gd")

## Стартовая россыпь предметов у респа (пока нет лута и кластеров): [id, count, x, z].
const STARTER_ITEMS := [
	["sporan", 12, 3.0, 2.0], ["pea_yellow", 1, -2.5, 3.0], ["vodka", 1, 4.0, -2.0],
	["canned_food", 2, -3.5, -2.0], ["bandage", 2, 1.5, -4.0], ["vinegar", 1, -1.0, 5.0],
	["gold_ring", 1, 5.5, 4.0], ["brick", 5, 7.0, 0.0],
]

const GROUND_SIZE := 200.0
const OBSTACLE_COUNT := 40
const OBSTACLE_SEED := 74920891

var _death_flow: Node


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
	add_child(VitalsBarsScript.new())
	var prompt: CanvasLayer = InteractPromptScript.new()
	prompt.hero = player
	add_child(prompt)
	var inventory_panel: CanvasLayer = InventoryPanelScript.new()
	inventory_panel.hero = player
	add_child(inventory_panel)

	var world_items: Node3D = WorldItemsScript.new()
	add_child(world_items)
	for entry: Array in STARTER_ITEMS:
		world_items.spawn(entry[0], entry[1], Vector3(entry[2], 0.0, entry[3]))
	_build_respawn_marker(PlayerState.respawn_position)

	_death_flow = DeathFlowScript.new()
	_death_flow.hero = player
	add_child(_death_flow)
	SystemLog.post("welcome")
	_handle_debug_args()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_die"):
		PlayerState.die("debug")
	elif event.is_action_pressed("debug_save"):
		SaveService.save_game(SaveService.DEBUG_SLOT)
	elif event.is_action_pressed("debug_load"):
		SaveService.load_game(SaveService.DEBUG_SLOT)


## Отладочные аргументы после «--»:
##   --demo        герой сам бежит вперёд (проверка прокачки Скорости)
##   --shot=PATH   через 4 секунды сохранить скриншот в PATH и выйти
##   --shot-at=S   снимать не через 4, а через S секунд
##   --fast-respawn  возрождение через 5 с вместо 100–180
##   --die=N       через секунду умереть N раз подряд (N ≥ жизней — сразу экран итогов)
##   --kit         выдать отладочный набор предметов и открыть инвентарь
func _handle_debug_args() -> void:
	var shot_path := ""
	var die_times := 0
	var shot_at := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			Input.action_press("move_forward")
			Input.action_press("sprint")
		elif arg == "--kit":
			_debug_kit()
		elif arg == "--fast-respawn":
			_death_flow.fast_respawn = true
		elif arg.begins_with("--die="):
			die_times = int(arg.trim_prefix("--die="))
		elif arg.begins_with("--shot-at="):
			shot_at = float(arg.trim_prefix("--shot-at="))
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
	if die_times > 0:
		_debug_die(die_times)
	if shot_path.is_empty():
		return
	await get_tree().create_timer(shot_at).timeout
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()


func _debug_kit() -> void:
	for entry: Array in [["sporan", 47], ["pearl_black", 1], ["zhivchik", 2], ["vodka", 2], ["brick", 4], ["canned_food", 3]]:
		PlayerState.pick_up(entry[0], entry[1])
	var open := InputEventAction.new()
	open.action = "inventory"
	open.pressed = true
	Input.parse_input_event(open)


func _debug_die(times: int) -> void:
	await get_tree().create_timer(1.0).timeout
	for i in times:
		PlayerState.die("debug")
		if i < times - 1 and PlayerState.lives > 0:
			_death_flow.finish_respawn()


## Респ героя — тёмная плита с бледным свечением (позже — шаблоны «общежитие» / «стройка»).
func _build_respawn_marker(at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.2
	mesh.bottom_radius = 1.2
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.22, 0.25)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.6, 0.5)
	material.emission_energy_multiplier = 0.4
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = material
	marker.position = Vector3(at.x, 0.03, at.z)
	add_child(marker)


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
