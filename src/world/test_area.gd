extends NavigationRegion3D
## Тестовая площадка M1 (до кластеров, задача 11): земля, случайные коробки-препятствия, дом с
## дверью, плита респа. Навигация запекается в рантайме из коллизий детей.
## Раскладка — data/world/test_area.json.

signal navigation_ready

const DoorScript := preload("res://src/world/door.gd")

const GROUND_SIZE := 200.0
const OBSTACLE_COUNT := 40
const OBSTACLE_SEED := 74920891
const BAKE_HALF_SIZE := 70.0

var is_navigation_ready := false

var _config: Dictionary
var _door: StaticBody3D


func _ready() -> void:
	_config = Content.test_area()
	_build_ground()
	_build_house(_config["house"])
	_build_obstacles()
	_build_respawn_marker(PlayerState.respawn_position)
	SaveService.register("area", self)

	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_radius = 0.5
	nav.agent_height = 1.75
	nav.filter_baking_aabb = AABB(Vector3(-BAKE_HALF_SIZE, -2, -BAKE_HALF_SIZE), Vector3(BAKE_HALF_SIZE * 2, 10, BAKE_HALF_SIZE * 2))
	navigation_mesh = nav
	bake_finished.connect(_on_baked)
	bake_navigation_mesh(true)


func _exit_tree() -> void:
	SaveService.unregister("area")


## Ближайшая точка навигации (для спавна тварей).
func snap(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


func to_dict() -> Dictionary:
	return {"door_open": _door.is_open}


func load_dict(data: Dictionary) -> void:
	if bool(data.get("door_open", false)):
		_door.open_door()
	else:
		_door.close_door()


func _on_baked() -> void:
	# Карта навигации обновляется на следующем кадре синхронизации.
	await get_tree().physics_frame
	await get_tree().physics_frame
	is_navigation_ready = true
	navigation_ready.emit()


func _build_ground() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1, GROUND_SIZE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	add_child(_static_body(box, Vector3(0, -0.5, 0), plane, Vector3.ZERO, Color(0.36, 0.42, 0.3)))


## Дом: четыре стены, в южной — проём с дверью (дверь смотрит на респ).
func _build_house(house: Dictionary) -> void:
	var center := Vector3(float(house["center"][0]), 0, float(house["center"][1]))
	var size_x := float(house["size"][0])
	var size_z := float(house["size"][1])
	var h := float(house["wall_height"])
	var door_w := float(house["door_width"])
	var t := 0.3
	var color := Color(0.62, 0.55, 0.48)
	_wall(center + Vector3(0, 0, size_z / 2.0), Vector3(size_x, h, t), color)        # северная (+Z)
	_wall(center + Vector3(-size_x / 2.0, 0, 0), Vector3(t, h, size_z), color)       # западная
	_wall(center + Vector3(size_x / 2.0, 0, 0), Vector3(t, h, size_z), color)        # восточная
	var side := (size_x - door_w) / 2.0                                              # южная с проёмом
	_wall(center + Vector3(-(door_w + side) / 2.0, 0, -size_z / 2.0), Vector3(side, h, t), color)
	_wall(center + Vector3((door_w + side) / 2.0, 0, -size_z / 2.0), Vector3(side, h, t), color)
	_wall(center + Vector3(0, 2.3, -size_z / 2.0), Vector3(door_w, h - 2.3, t), color)  # над дверью

	_door = DoorScript.new()
	_door.width = door_w
	_door.position = center + Vector3(0, 0, -size_z / 2.0)
	add_child(_door)


func _wall(base: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	var at := base + Vector3(0, size.y / 2.0, 0)
	add_child(_static_body(box, at, mesh, at, color))


## Случайные «дома» и «ящики» — детерминированно по сиду. Вокруг респа и дома — пусто.
func _build_obstacles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = OBSTACLE_SEED
	var house: Dictionary = _config["house"]
	var house_center := Vector3(float(house["center"][0]), 0, float(house["center"][1]))
	var placed := 0
	while placed < OBSTACLE_COUNT:
		var at := Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
		var size := Vector3(rng.randf_range(1, 6), rng.randf_range(1, 4), rng.randf_range(1, 6))
		if at.length() < 6.0 or at.distance_to(house_center) < 9.0:
			continue
		var box := BoxShape3D.new()
		box.size = size
		var mesh := BoxMesh.new()
		mesh.size = size
		var shade := rng.randf_range(0.45, 0.7)
		var center := at + Vector3(0, size.y / 2.0, 0)
		add_child(_static_body(box, center, mesh, center, Color(shade, shade * 0.95, shade * 0.9)))
		placed += 1


## Респ героя — тёмная плита с бледным свечением (позже — шаблоны «общежитие» / «стройка»).
func _build_respawn_marker(at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.2
	mesh.bottom_radius = 1.2
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.22, 0.25)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.6, 0.5)
	material.emission_energy_multiplier = 0.4
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = material
	marker.position = Vector3(at.x, 0.03, at.z)
	add_child(marker)


func _static_body(shape: Shape3D, shape_at: Vector3, mesh: Mesh, mesh_at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = shape_at
	body.add_child(collision)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = mesh_at
	body.add_child(instance)
	return body
