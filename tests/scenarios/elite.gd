extends SceneTree
## Сценарий элиты (задача 18), без окна: godot --headless --path . -s res://tests/scenarios/elite.gd
## Городок: элита в засаде и раненый-приманка; капкан держит, приманка травит, смерть элиты
## записывается до перезагрузки кластера.

func _initialize() -> void:
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	await process_frame
	await process_frame
	var ws: Node = root.get_node("WorldSim")
	ws.new_world(9)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(1.0)
	paused = false
	ws.travel("c_town", {"at": [0, 0]})
	await _wait(3.0)
	paused = false
	var elite: Node3D = get_first_node_in_group("elite")
	var victim: Node3D = get_first_node_in_group("elite_victims")
	print("town: elite=%s victim=%s hp=%s state=%s" % [elite != null, victim != null, elite.hp if elite else 0, elite.brain.state if elite else ""])
	if elite == null:
		quit()
		return
	var hero: Node3D = get_first_node_in_group("hero")
	var start: Vector3 = elite.global_position
	await _wait(3.0)
	print("  lurk: moved %.2f m (засада — стоит)" % elite.global_position.distance_to(start))
	var hp0: float = elite.hp
	elite.trap(4.0, 40.0)
	print("  trap: hp %.0f -> %.0f trapped=%s" % [hp0, elite.hp, elite.is_trapped()])
	elite.poison(25.0, 8.0, 90.0)
	var armor: Dictionary = elite.armor_now()
	print("  poison: torso armor %.1f (было 50)" % float(armor["torso"]))
	await _wait(2.0)
	print("  poison ticks: hp %.0f" % elite.hp)
	elite.take_damage(100000.0)
	await _wait(0.5)
	print("  killed: state elite_killed_at=%s reloads=%s elites=%d" % [ws.state().get("elite_killed_at", -1), ws.state()["reloads"], get_nodes_in_group("elite").size()])
	var before: int = root.get_node("PlayerState").inventory.count_of("sporan")
	victim.interact(hero)
	print("  victim thanks: sporan %d -> %d" % [before, root.get_node("PlayerState").inventory.count_of("sporan")])
	quit()
