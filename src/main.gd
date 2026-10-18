extends Node3D
## Вертикальный срез M1: тестовая площадка, герой, заражённые, интерфейс.
## Всё собирается кодом, чтобы сцена была читаемой в diff.

const PlayerScript := preload("res://src/actors/player.gd")
const IsoCameraScript := preload("res://src/world/iso_camera.gd")
const DebugHudScript := preload("res://src/ui/debug_hud.gd")
const VitalsBarsScript := preload("res://src/ui/vitals_bars.gd")
const DeathFlowScript := preload("res://src/world/death_flow.gd")
const WorldItemsScript := preload("res://src/world/world_items.gd")
const InventoryPanelScript := preload("res://src/ui/inventory_panel.gd")
const InteractPromptScript := preload("res://src/ui/interact_prompt.gd")
const TestAreaScript := preload("res://src/world/test_area.gd")
const InfectedPopulationScript := preload("res://src/world/infected_population.gd")
const NoiseSystemScript := preload("res://src/world/noise_system.gd")
const ProgressWatcherScript := preload("res://src/world/progress_watcher.gd")

var _death_flow: Node


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_environment()
	var area: NavigationRegion3D = TestAreaScript.new()
	area.name = "Area"
	add_child(area)
	add_child(NoiseSystemScript.new())
	add_child(ProgressWatcherScript.new())

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
	add_child(InventoryPanelScript.new())

	var world_items: Node3D = WorldItemsScript.new()
	add_child(world_items)
	for entry: Array in Content.test_area()["items"]:
		world_items.spawn(entry[0], int(entry[1]), Vector3(float(entry[2]), 0.0, float(entry[3])))

	var population: Node3D = InfectedPopulationScript.new()
	population.name = "Infected"
	population.area = area
	if not "--no-enemies" in OS.get_cmdline_user_args():
		add_child(population)

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
##   --no-enemies  без заражённых
##   --at=X,Z      поставить героя в точку (для снимков)
##   --corpse=ID   труп твари ID в метре от героя и нож в рюкзак (проверка вскрытия мешка)
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
		elif arg.begins_with("--at="):
			var xz := arg.trim_prefix("--at=").split(",")
			get_tree().get_first_node_in_group("hero").position = Vector3(float(xz[0]), 0.1, float(xz[1]))
		elif arg.begins_with("--corpse="):
			PlayerState.pick_up("knife", 1)
			var enemy := arg.trim_prefix("--corpse=")
			EventBus.infected_killed.emit(enemy, int(Content.enemy_db().enemy(enemy)["level"][1]), Vector3(0.8, 0, -0.8))
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
	for entry: Array in [["sporan", 47], ["pearl_black", 1], ["pea_yellow", 2], ["vinegar", 1], ["vodka", 2],
			["canned_food", 3], ["knife", 1], ["pistol", 1], ["ammo_9mm", 20], ["bandage", 2]]:
		PlayerState.pick_up(entry[0], entry[1])
	PlayerState.consume("pea_yellow")
	PlayerState.weapons.equipped = "pistol"
	PlayerState.reload_weapon()
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
