extends SceneTree
## Сценарий стаба (задача 12), без окна: godot --headless --path . -s res://tests/scenarios/stab.gd
## Печатает: сделки за спораны, лечение, сон (время, шкалы, автосейв), слух, контракт на охоту,
## сохранение и загрузка стаба. Сверять глазами.


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var ws: Node = root.get_node("WorldSim")
	var ps: Node = root.get_node("PlayerState")
	var stab: Node = root.get_node("StabState")
	var clock: Node = root.get_node("GameClock")
	ws.new_world(11)
	ws.current = "c_stab"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(1.0).timeout
	print("npcs: ", get_nodes_in_group("interactable").filter(func(n: Node) -> bool: return n.get("npc_id") != null).map(func(n: Node) -> String: return n.npc_id))
	ps.inventory.add("sporan", 60)
	ps.inventory.add("pea_yellow", 3)
	stab.refresh()
	stab.buy("bandage", 2)
	stab.sell("pea_yellow", 3)
	print("money after deals: %d, bandages %d, peas %d" % [stab.money(), ps.inventory.count_of("bandage"), ps.inventory.count_of("pea_yellow")])
	ps.vitals.damage(30.0)
	print("heal cost %d" % stab.heal_cost())
	stab.heal()
	print("health %.0f, money %d" % [ps.vitals.value("health"), stab.money()])
	var t0: float = clock.minutes
	var spore0: float = ps.vitals.value("spore_balance")
	stab.sleep()
	print("sleep: +%.0f min, spore %.0f -> %.0f, autosave=%s" % [clock.minutes - t0, spore0, ps.vitals.value("spore_balance"), root.get_node("SaveService").has_save("auto")])
	var known_before: int = ws.clusters.values().filter(func(s: Dictionary) -> bool: return s["known_timer"]).size()
	stab.rumor()
	print("rumor: known timers %d -> %d" % [known_before, ws.clusters.values().filter(func(s: Dictionary) -> bool: return s["known_timer"]).size()])
	stab.board.offers = [{"type": "hunt", "target": "slowpoke", "count": 2, "reward": 4, "progress": 0}]
	stab.take_contract(0)
	root.get_node("EventBus").infected_killed.emit("slowpoke", 1, Vector3.ZERO)
	root.get_node("EventBus").infected_killed.emit("slowpoke", 1, Vector3.ZERO)
	var before: int = stab.money()
	stab.complete_contract(0)
	print("contract reward: %d" % (stab.money() - before))
	stab.board.offers = [{"type": "scout", "target": "c_black", "count": 1, "reward": 30, "progress": 0}]
	stab.take_contract(0)
	var save: Node = root.get_node("SaveService")
	save.save_game("debug")
	stab.setup()
	save.load_game("debug")
	await create_timer(1.0).timeout
	print("after load: active=%s stock bandage=%d" % [stab.board.active.map(func(c: Dictionary) -> String: return c["type"] + ":" + c["target"]), stab.trade.stock["bandage"]])
	var log_tail: Array = root.get_node("SystemLog").history.slice(-12).map(func(e: Dictionary) -> String: return e["text"])
	for line in log_tail:
		print("  › ", line)
	quit()
