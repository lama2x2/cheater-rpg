extends SceneTree
## Сценарий происхождения (задача 16a), без окна: godot --headless --path . -s res://tests/scenarios/origin.gd
## Новая игра Читером с «Инкассатором» и Обычным: куш, лог, окно новичка, сейв/загрузка.

func _initialize() -> void:
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	await process_frame
	await process_frame
	var save: Node = root.get_node("SaveService")
	var ps: Node = root.get_node("PlayerState")
	var log: Node = root.get_node("SystemLog")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(1.0)
	save.start_new_game({}, {"origin": "cheater", "variant": "armored_van"})
	await _wait(1.5)
	paused = false
	print("cheater: origin=%s variant=%s chosen=%s pearls=%d sporan=%d property=%s debts=%s newbie=%s" % [ps.origin, ps.origin_variant,
		ps.origin_chosen, ps.inventory.count_of("pearl_black"), ps.inventory.count_of("sporan"), ps.cheater_property, ps.origin_debts, ps.in_newbie_window()])
	print("  log: %s" % log.history[log.history.size() - 1]["text"] if not log.history.is_empty() else "  log: —")
	var result: String = ps.consume("pearl_black")
	print("  pearl in newbie window: %s, risks run=%d" % [result, ps.run.count("risk_become_quasi")])
	save.save_game("debug")
	save.load_game("debug")
	await _wait(1.0)
	print("  after load: origin=%s variant=%s property=%s" % [ps.origin, ps.origin_variant, ps.cheater_property])
	save.start_new_game({}, {"origin": "ordinary"})
	await _wait(1.5)
	print("ordinary: origin=%s pearls=%d property=%s" % [ps.origin, ps.inventory.count_of("pearl_black"), ps.cheater_property])
	quit()
