extends SceneTree
## Сценарий начала игры (задача 17), без окна: godot --headless --path . -s res://tests/scenarios/onboarding.gd
## Новая игра Читером («Инкассатор»): пролог → пробуждение → первый медляк → наставник → мешок →
## крестины → стаб. Печатает шаги, куш, имя, свободные очки, окно новичка.

var _ps: Node


func _initialize() -> void:
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _step(label: String) -> void:
	print("%s: step=%s" % [label, _ps.onboarding_step])


func _run() -> void:
	await process_frame
	await process_frame
	_ps = root.get_node("PlayerState")
	var save: Node = root.get_node("SaveService")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(1.0)
	save.start_new_game({}, {"origin": "cheater", "variant": "armored_van", "mode": "story", "version": "blank_slate"})
	await _wait(1.0)
	_step("start")
	for node in current_scene.get_children():
		if node.has_method("_finish"):
			node._finish()
	await _wait(0.5)
	_step("after prologue")
	print("  jackpot pending=%s sites=%d pearls=%d" % [_ps.pending_jackpot, get_nodes_in_group("jackpot_sites").size(), _ps.inventory.count_of("pearl_black")])
	var site: Node = get_first_node_in_group("jackpot_sites")
	if site:
		site.interact(get_first_node_in_group("hero"))
	print("  site taken: pearls=%d pending=%s" % [_ps.inventory.count_of("pearl_black"), _ps.pending_jackpot])
	await _wait(27.0)
	_step("after delay")
	for node in get_nodes_in_group("infected"):
		node.take_damage(100000.0)
	await _wait(0.5)
	_step("killed")
	var mentor: Node3D = get_first_node_in_group("mentor")
	print("  mentor=%s" % (mentor != null))
	var hero: Node3D = get_first_node_in_group("hero")
	if mentor:
		hero.global_position = mentor.global_position + Vector3(1.0, 0.1, 0.0)
		mentor.interact(hero)
		await process_frame
		get_first_node_in_group("mentor_window")._first_talk()
	_step("talked")
	print("  knife=%d zhivchik=%d" % [_ps.inventory.count_of("knife"), _ps.inventory.count_of("zhivchik")])
	print("  quests: active=%s done=%s" % [_ps.quests["active"].keys(), _ps.quests["done"]])
	_ps.run.add("sacks_opened")
	await _wait(0.3)
	_step("sack")
	_ps.pick_up("sporan", 10)
	print("  share: %s flags=%s" % [_ps.quest_choose("bs_skull", "share", "share"), _ps.quests["flags"]])
	var newbie_before: bool = _ps.in_newbie_window()
	var result: Dictionary = _ps.christen("Март")
	_step("christened")
	print("  name=%s nickname=%s free=%d newbie %s -> %s" % [result["name"], result["nickname"], _ps.free_points, newbie_before, _ps.in_newbie_window()])
	print("  quests: active=%s done=%s pending=%d" % [_ps.quests["active"].keys(), _ps.quests["done"], _ps.quests["pending"].size()])
	_ps.die("debug")
	print("  died on the road: fails=%s active=%s" % [_ps.quests["fails"], _ps.quests["active"].keys()])
	for node in current_scene.get_children():
		if node.has_method("finish_respawn"):
			node.finish_respawn()
	await _wait(0.5)
	root.get_node("WorldSim").travel("c_stab", {"at": [0, 0]})
	await _wait(2.0)
	_step("in stab")
	print("  quests: done=%s completed=%s" % [_ps.quests["done"], MetaProgress.completed("blank_slate")])
	root.get_node("GameClock").advance(4 * 60.0)
	await _wait(1.5)
	print("  consequence: pending=%d fired=%s" % [_ps.quests["pending"].size(), _ps.quests["fired"]])
	quit()
