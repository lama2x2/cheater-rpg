extends Node3D
## Заражённые на площадке: стартовый спавн по сиду (data/world/test_area.json) после запекания
## навигации, сохранение и загрузка (секция infected). Позже их заменит модель популяции кластера
## (задача 11).

const InfectedScript := preload("res://src/actors/infected.gd")

var area: Node  # test_area.gd

var _loaded_from_save := false


func _ready() -> void:
	SaveService.register("infected", self)
	if area.is_navigation_ready:
		_spawn_initial()
	else:
		area.navigation_ready.connect(_spawn_initial, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	SaveService.unregister("infected")


func spawn(id: String, level: int, at: Vector3) -> Node3D:
	var infected: CharacterBody3D = InfectedScript.new()
	infected.enemy_id = id
	infected.level = level
	infected.home = at
	infected.position = at + Vector3.UP * 0.1
	infected.rotation.y = randf() * TAU
	add_child(infected)
	return infected


func _spawn_initial() -> void:
	if _loaded_from_save:
		return
	var config: Dictionary = Content.test_area()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config["infected_seed"])
	for group: Dictionary in config["infected"]:
		var ring: Array = group["ring"]
		for i in int(group["count"]):
			var angle := rng.randf() * TAU
			var distance := rng.randf_range(float(ring[0]), float(ring[1]))
			var at: Vector3 = area.snap(Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))
			spawn(String(group["id"]), Content.enemy_db().roll_level(String(group["id"]), rng), at)


func to_dict() -> Dictionary:
	var list: Array = []
	for infected in get_children():
		if not infected.is_queued_for_deletion():
			list.append(infected.to_dict())
	return {"infected": list}


func load_dict(data: Dictionary) -> void:
	_loaded_from_save = true
	for infected in get_children():
		remove_child(infected)
		infected.queue_free()
	for entry: Dictionary in data["infected"]:
		var infected: CharacterBody3D = InfectedScript.new()
		infected.load_dict(entry)
		add_child(infected)
