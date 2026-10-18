extends SceneTree
## Сценарий настроек и режима сохранений (задача 12a), без окна:
## godot --headless --path . -s res://tests/scenarios/settings.gd
## Печатает: хардкор вне стаба и в стабе, смену режима посреди игры, режим после сохранения и
## загрузки, настройки из файла с мусором. Файл настроек пользователя восстанавливается в конце.


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var settings: Node = root.get_node("Settings")
	var path: String = settings.PATH
	var backup := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var ws: Node = root.get_node("WorldSim")
	var ps: Node = root.get_node("PlayerState")
	var save: Node = root.get_node("SaveService")
	ws.new_world(11)
	ps.setup()
	ps.save_mode = "stab_only"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(1.0).timeout
	print("stab_only on %s: can save=%s" % [ws.current, save.can_manual_save()])
	ws.travel("c_stab", {"from": "c_village"})
	await create_timer(1.5).timeout
	print("stab_only on %s: can save=%s" % [ws.current, save.can_manual_save()])
	ps.change_save_mode("anywhere")
	ps.change_save_mode("anywhere")
	print("mode changes: %d, mode=%s" % [ps.run.count("save_mode_changes"), ps.save_mode])
	save.save_game("debug")
	ps.save_mode = "stab_only"
	save.load_game("debug")
	await create_timer(1.0).timeout
	print("after load: mode=%s, changes=%d, meta mode=%s" % [ps.save_mode, ps.run.count("save_mode_changes"), save.slot_info("debug").get("save_mode")])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"save_mode": "stab_only", "volume": 7, "window_size": "big", "noise_ring": false}')
	file.close()
	settings.model = null
	print("settings from file: mode=%s volume=%s window=%s ring=%s" % [settings.value("save_mode"), settings.value("volume"), settings.value("window_size"), settings.value("noise_ring")])
	if backup.is_empty():
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(backup)
		restore.close()
	quit()
