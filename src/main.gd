extends Node3D
## Вертикальный срез M1: текущий кластер региона (WorldSim), герой, заражённые, интерфейс.
## Всё собирается кодом, чтобы сцена была читаемой в diff. Переход в другой кластер и загрузка
## сохранения пересобирают сцену целиком (WorldSim.travel, SaveService.load_game).

const PlayerScript := preload("res://src/actors/player.gd")
const IsoCameraScript := preload("res://src/world/iso_camera.gd")
const DebugHudScript := preload("res://src/ui/debug_hud.gd")
const VitalsBarsScript := preload("res://src/ui/vitals_bars.gd")
const DeathFlowScript := preload("res://src/world/death_flow.gd")
const WorldItemsScript := preload("res://src/world/world_items.gd")
const InventoryPanelScript := preload("res://src/ui/inventory_panel.gd")
const InteractPromptScript := preload("res://src/ui/interact_prompt.gd")
const ClusterAreaScript := preload("res://src/world/cluster_area.gd")
const ClusterDirectorScript := preload("res://src/world/cluster_director.gd")
const InfectedPopulationScript := preload("res://src/world/infected_population.gd")
const NoiseSystemScript := preload("res://src/world/noise_system.gd")
const ProgressWatcherScript := preload("res://src/world/progress_watcher.gd")
const GameMenuScript := preload("res://src/ui/game_menu.gd")
const SkillsBarScript := preload("res://src/ui/skills_bar.gd")
const SkillsPanelScript := preload("res://src/ui/skills_panel.gd")
const GazeCardScript := preload("res://src/ui/gaze_card.gd")
const HeroVisionScript := preload("res://src/world/hero_vision.gd")
const SenseIndicatorScript := preload("res://src/ui/sense_indicator.gd")
const MapWatcherScript := preload("res://src/world/map_watcher.gd")
const MinimapScript := preload("res://src/ui/minimap.gd")
const MapWindowScript := preload("res://src/ui/map_window.gd")

var _death_flow: Node
var _environment: Environment
## Отладочные аргументы срабатывают один раз за запуск: переход и загрузка пересобирают сцену.
static var _debug_args_done := false
## Титульный экран — один раз за запуск: без аргументов (обычный запуск игры) или с --title.
static var _title_done := false


func _ready() -> void:
	InputSetup.ensure_actions()
	get_tree().root.theme = UiKit.theme()
	_build_environment()
	var area: NavigationRegion3D = ClusterAreaScript.new()
	area.name = "Area"
	add_child(area)
	add_child(NoiseSystemScript.new())
	add_child(ProgressWatcherScript.new())

	var player: CharacterBody3D = PlayerScript.new()
	player.name = "Player"
	var on_respawn_cluster := WorldSim.current == String(WorldSim.region.region["respawn"])
	player.position = PlayerState.respawn_position if on_respawn_cluster else Vector3(0, 0.1, 0)
	add_child(player)

	var camera: Camera3D = IsoCameraScript.new()
	camera.target = player
	add_child(camera)
	player.camera = camera
	var vision: Node3D = HeroVisionScript.new()
	vision.hero = player
	add_child(vision)

	add_child(DebugHudScript.new())
	add_child(VitalsBarsScript.new())
	var prompt: CanvasLayer = InteractPromptScript.new()
	prompt.hero = player
	add_child(prompt)
	add_child(InventoryPanelScript.new())
	add_child(SkillsBarScript.new())
	add_child(SkillsPanelScript.new())
	add_child(GazeCardScript.new())
	add_child(SenseIndicatorScript.new())
	add_child(MinimapScript.new())
	add_child(MapWindowScript.new())
	var map_watcher: Node = MapWatcherScript.new()
	map_watcher.area = area
	map_watcher.hero = player
	add_child(map_watcher)
	var menu: CanvasLayer = GameMenuScript.new()
	add_child(menu)

	var world_items: Node3D = WorldItemsScript.new()
	add_child(world_items)

	var population: Node3D = null
	if not "--no-enemies" in OS.get_cmdline_user_args():
		population = InfectedPopulationScript.new()
		population.name = "Infected"
		population.area = area
		add_child(population)

	_death_flow = DeathFlowScript.new()
	_death_flow.hero = player
	add_child(_death_flow)

	var director: Node = ClusterDirectorScript.new()
	director.name = "ClusterDirector"
	director.area = area
	director.items = world_items
	director.population = population
	director.death_flow = _death_flow
	director.hero = player
	director.environment = _environment
	add_child(director)

	if SystemLog.history.is_empty():
		SystemLog.post("welcome" if PlayerState.ng_plus == 0 else "welcome_ng_plus", {"cycle": PlayerState.ng_plus})
	SaveService.finish_scene_load()
	var args := OS.get_cmdline_user_args()
	if not _title_done and (args.is_empty() or "--title" in args):
		_title_done = true
		menu.open_title()
	_title_done = true
	_handle_debug_args()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_die"):
		PlayerState.die("debug")
	elif event.is_action_pressed("debug_save"):
		if SaveService.can_manual_save():
			SaveService.save_game(SaveService.DEBUG_SLOT)
		else:
			SystemLog.post("save_blocked", {}, "warning")
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
##   --menu        сохранить в ячейку 1 и открыть меню загрузки (проверка ячеек)
##   --cluster=ID  начать в кластере ID (c_village, c_town, c_industrial, c_black, c_stab)
##   --kislyak     на текущем кластере сейчас встанет кисляк (сброс через kislyak_min минут)
##   --reload=S    через S секунд перезагрузить текущий кластер (проверка сброса при герое)
##   --hours=N     прокрутить мир на N игровых часов (проверка симуляции)
##   --world-seed=N  сид мира (читает WorldSim), для одинаковых снимков
##   --title       показать титульный экран (без аргументов он и так показывается)
##   --page=NAME   открыть страницу меню Esc: main, save, load, settings, new_game
##   --talk=ID     в стабе: встать у непися ID (trader, healer, barman, board) и открыть его окно
##   --skills=A,B  выучить умения A, B (в список активных по порядку); --skills=all — все из data/skills
##   --cast=N      через 1 с применить умение с клавиши N (1–8), мана — полная
##   --skills-panel  открыть окно умений
##   --gaze        через 1,5 с показать карточку Пристального взгляда ближайшей твари (нет тварей —
##                 ближайшей другой цели)
##   --zoom=N      размер ортокамеры N м (обычно 10–40; больше — снять кластер целиком)
##   --map=TAB     открыть карту: cluster или region (и --reveal — карты всех кластеров)
##   --inside      поставить героя в ближайшее к центру здание (прозрачные стены, позже крыши)
##   --gift        вскрыть дар 10 уровня даром (pending_skill_choices) — для окна знахарки
##   --pearl       висящее умение чёрной жемчужины (pending_pearl_skills) — окно умений и знахарки
func _handle_debug_args() -> void:
	if _debug_args_done:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cluster="):
			var target := arg.trim_prefix("--cluster=")
			if WorldSim.current != target and WorldSim.region.has_cluster(target):
				WorldSim.travel(target, {"from": WorldSim.region.neighbors(target)[0]})
				return
	_debug_args_done = true
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
		elif arg == "--menu":
			SaveService.save_game("slot_1")
			var open_menu := InputEventAction.new()
			open_menu.action = "menu"
			open_menu.pressed = true
			Input.parse_input_event(open_menu)
			_open_load_page.call_deferred()
		elif arg.begins_with("--corpse="):
			PlayerState.pick_up("knife", 1)
			var enemy := arg.trim_prefix("--corpse=")
			EventBus.infected_killed.emit(enemy, int(Content.enemy_db().enemy(enemy)["level"][1]), Vector3(0.8, 0, -0.8))
		elif arg == "--kislyak":
			var timer: Dictionary = WorldSim.state()["timer"]
			if ClusterLifecycle.reloads(timer):
				timer["next"] = GameClock.minutes + float(timer["kislyak_min"]) * 0.5
		elif arg.begins_with("--reload="):
			_debug_reload(float(arg.trim_prefix("--reload=")))
		elif arg.begins_with("--page="):
			_debug_page.call_deferred(arg.trim_prefix("--page="))
		elif arg.begins_with("--talk="):
			_debug_talk.call_deferred(arg.trim_prefix("--talk="))
		elif arg.begins_with("--skills="):
			_debug_skills(arg.trim_prefix("--skills="))
		elif arg.begins_with("--cast="):
			_debug_cast.call_deferred(int(arg.trim_prefix("--cast=")))
		elif arg == "--skills-panel":
			_debug_skills_panel.call_deferred()
		elif arg == "--pearl":
			PlayerState.pending_pearl_skills += 1
		elif arg.begins_with("--zoom="):
			get_viewport().get_camera_3d().size = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--map="):
			_debug_map.call_deferred(arg.trim_prefix("--map="))
		elif arg == "--reveal":
			for id in WorldSim.region.ids():
				WorldSim.reveal_map(id)
		elif arg == "--inside":
			_debug_inside()
		elif arg == "--gaze":
			_debug_gaze.call_deferred()
		elif arg == "--gift":
			PlayerState.skill_gifts_opened.append(10)
			PlayerState.pending_skill_choices += 1
		elif arg.begins_with("--hours="):
			GameClock.advance(float(arg.trim_prefix("--hours=")) * 60.0)
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


func _debug_page(page: String) -> void:
	await get_tree().process_frame
	for child in get_children():
		if child.has_method("open_title"):
			child._open()
			if page == "new_game":
				child._open_new_game()
			else:
				child.call("_" + page + "_page")


func _debug_talk(npc_id: String) -> void:
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group("interactable"):
		if node.get("npc_id") == npc_id:
			var hero := get_tree().get_first_node_in_group("hero") as Node3D
			hero.global_position = node.global_position - node.global_transform.basis.z * 1.4 + Vector3.UP * 0.1
			node.interact(hero)
			return


func _debug_skills(list: String) -> void:
	var ids := PlayerState.skills.all_ids() if list == "all" else PackedStringArray(list.split(","))
	for id in ids:
		PlayerState.learn_skill(id)


func _debug_cast(slot: int) -> void:
	await get_tree().create_timer(1.0).timeout
	PlayerState.vitals.restore(Vitals.MANA, PlayerState.vitals.max_value(Vitals.MANA))
	PlayerState.use_hotkey(slot - 1)


func _debug_map(tab: String) -> void:
	await get_tree().create_timer(1.5).timeout
	get_tree().get_first_node_in_group("map_window").open(tab)


func _debug_inside() -> void:
	var area := get_node("Area")
	var best: Dictionary = {}
	for building: Dictionary in area.layout["buildings"]:
		if best.is_empty() or (building["center"] as Vector2).length() < (best["center"] as Vector2).length():
			best = building
	if not best.is_empty():
		get_tree().get_first_node_in_group("hero").position = Vector3(best["center"].x, 0.1, best["center"].y)


func _debug_gaze() -> void:
	await get_tree().create_timer(1.5).timeout
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	var best: Node3D = null
	for group in ["infected", "interactable", "infected_corpses"]:
		if best:
			break  # твари — в первую очередь
		for node: Node3D in get_tree().get_nodes_in_group(group):
			if node.has_method("gaze_info") and (best == null or
					node.global_position.distance_to(hero.global_position) < best.global_position.distance_to(hero.global_position)):
				best = node
	if best:
		get_tree().get_first_node_in_group("gaze_card").show_target(best)


func _debug_skills_panel() -> void:
	await get_tree().process_frame
	get_tree().get_first_node_in_group("skills_panel").toggle()


func _debug_reload(after: float) -> void:
	await get_tree().create_timer(after).timeout
	var timer: Dictionary = WorldSim.state()["timer"]
	if ClusterLifecycle.reloads(timer):
		timer["next"] = GameClock.minutes


func _open_load_page() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for child in get_children():
		if child.has_method("_load_page"):
			child._load_page()


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
	_environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
