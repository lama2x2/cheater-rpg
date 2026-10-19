extends SceneTree
## Сценарий зрения героя (задача 14a), без окна: godot --headless --path . -s res://tests/scenarios/vision.gd
## Ставит тварей впереди, за спиной, рядом и за стеной; печатает, кого герой видит, отметки
## последнего места и чуйку. Ожидается: front=true back=false near=true wall=false.

var _main: Node


func _initialize() -> void:
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _spawn(at: Vector3) -> Node3D:
	var infected: CharacterBody3D = load("res://src/actors/infected.gd").new()
	infected.enemy_id = "crawler"
	infected.level = 0
	_main.add_child(infected)
	infected.global_position = at
	infected.home = at
	return infected


func _run() -> void:
	await process_frame
	await process_frame
	root.get_node("WorldSim").new_world(5)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await _wait(2.0)
	paused = false  # без аргументов игра стартует с титульного экрана на паузе
	for node in get_nodes_in_group("infected"):
		node.queue_free()
	var hero: Node3D = get_first_node_in_group("hero")
	var vision: Node = get_first_node_in_group("hero_vision")
	hero.global_position = Vector3(0, 0.1, 0)
	await _wait(0.5)
	var look: Vector3 = vision.view_dir
	var side := look.cross(Vector3.UP).normalized()
	var front := _spawn(hero.global_position + look * 9.0 + Vector3.UP * 0.1)
	var back := _spawn(hero.global_position - look * 9.0 + Vector3.UP * 0.1)
	var near := _spawn(hero.global_position - look * 1.8 + Vector3.UP * 0.1)
	var walled := _spawn(hero.global_position + (look + side * 0.35).normalized() * 12.0 + Vector3.UP * 0.1)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 3.0, 1.5)
	shape.shape = box
	wall.add_child(shape)
	_main.add_child(wall)
	wall.global_position = hero.global_position + (look + side * 0.35).normalized() * 6.0 + Vector3.UP * 1.5
	await _wait(0.6)
	print("vision: front=%s back=%s near=%s wall=%s" % [vision.is_seen(front), vision.is_seen(back), vision.is_seen(near), vision.is_seen(walled)])
	var ps: Node = root.get_node("PlayerState")
	var rules = root.get_node("Content").vision_rules()
	print("rules: cone=%.0f range=%.1f" % [rules.cone_deg(false, ps.stats.get_level("perception")), rules.view_range(12, false, 1)])
	front.global_position = hero.global_position - look * 7.0 + Vector3.UP * 0.1
	await _wait(0.5)
	print("moved front behind: seen=%s ghosts=%d" % [vision.is_seen(front), get_nodes_in_group("vision_ghosts").size()])
	await _wait(5.0)
	print("after 5 s: ghosts=%d alarms=%d" % [get_nodes_in_group("vision_ghosts").size(), vision.alarms.size()])
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	var screen := StaticBody3D.new()
	var screen_shape := CollisionShape3D.new()
	var screen_box := BoxShape3D.new()
	screen_box.size = Vector3(3, 4, 0.3)
	screen_shape.shape = screen_box
	screen.add_child(screen_shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = screen_box.size
	mesh.mesh = box_mesh
	screen.add_child(mesh)
	_main.add_child(screen)
	var toward_camera := camera.global_transform.basis.z
	toward_camera.y = 0.0
	screen.global_position = hero.global_position + toward_camera.normalized() * 2.0 + Vector3.UP * 2.0
	screen.look_at(hero.global_position + Vector3.UP * 2.0, Vector3.UP)
	await _wait(0.4)
	print("wall between camera and hero: transparency=%.2f (ожидается 0.70)" % mesh.transparency)
	quit()
