extends SceneTree
## Сценарий кластеров (задача 11), без окна: godot --headless --path . -s res://tests/scenarios/clusters.gd
## Печатает: твари из популяции, обращения, сброс при герое, убитые → абстрактные числа, переход,
## сохранение/загрузка, урон черноты, возрождение на респе другого кластера. Сверять глазами.

var _main: Node


func _initialize() -> void:
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _count(group: String) -> int:
	return get_nodes_in_group(group).size()


func _items() -> int:
	return get_first_node_in_group("world_items").get_child_count()


func _run() -> void:
	await process_frame
	await process_frame
	var ws: Node = root.get_node("WorldSim")
	var clock: Node = root.get_node("GameClock")
	ws.new_world(11)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await _wait(3.0)
	print("start: cluster=%s infected=%d items=%d civ=%.1f" % [ws.current, _count("infected"), _items(), ws.state()["pop"]["civilians"]])
	clock.advance(180.0)
	await _wait(0.5)
	print("after 3h: infected=%d civ=%.1f reloads=%d known=%s" % [_count("infected"), ws.state()["pop"]["civilians"], ws.state()["reloads"], ws.state()["known_timer"]])
	ws.state()["timer"]["next"] = clock.minutes
	await _wait(1.0)
	print("reload here: reloads=%d infected=%d items=%d known=%s" % [ws.state()["reloads"], _count("infected"), _items(), ws.state()["known_timer"]])
	var killed_before: float = ws.population.total_infected(ws.state()["pop"])
	var victim = get_nodes_in_group("infected")[0] if _count("infected") > 0 else null
	if victim:
		victim.take_damage(10000.0)
	print("kill: abstract %.2f -> %.2f" % [killed_before, ws.population.total_infected(ws.state()["pop"])])
	ws.travel("c_village")
	await _wait(3.0)
	var hero: Node3D = get_first_node_in_group("hero")
	print("  village pop loot=%.2f fresh=%s ratio=%.3f groups=%d" % [ws.state()["pop"]["loot"], ws.state()["fresh"], ws.state()["ratio"], get_nodes_in_group("world_items").size()])
	print("village: cluster=%s infected=%d items=%d hero=%s snap_start=%s" % [ws.current, _count("infected"), _items(), hero.global_position, ws.snapshots.has("c_start")])
	var save: Node = root.get_node("SaveService")
	save.save_game("debug")
	var before := _count("infected")
	save.load_game("debug")
	await _wait(1.0)
	print("load: infected %d -> %d, cluster=%s" % [before, _count("infected"), ws.current])
	ws.travel("c_start")
	await _wait(3.0)
	print("back start: infected=%d items=%d hero=%s" % [_count("infected"), _items(), get_first_node_in_group("hero").global_position])
	ws.travel("c_black")
	await _wait(1.0)
	var ps: Node = root.get_node("PlayerState")
	var h0: float = ps.vitals.value("health")
	await _wait(3.0)
	print("black: infected=%d health %.2f -> %.2f" % [_count("infected"), h0, ps.vitals.value("health")])
	ps.die("debug")
	await _wait(0.5)
	_respawn()
	await _wait(2.0)
	var hero2: Node3D = get_first_node_in_group("hero")
	print("respawn: cluster=%s hero=%s visible=%s black_corpses=%d" % [ws.current, hero2.global_position, hero2.visible, ws.snapshots["c_black"]["corpses"]["corpses"].size()])
	quit()


func _respawn() -> void:
	for n in current_scene.get_children():
		if n.has_method("finish_respawn"):
			n.finish_respawn()
