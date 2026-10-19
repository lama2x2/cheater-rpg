extends NavigationRegion3D
## Сцена текущего кластера: земля, края, здания с дверями, препятствия, тайники, выходы к соседям,
## плита респа. Раскладка — ClusterLayout по шаблону (data/world/templates), детерминированно:
## после перезагрузки это тот же кусок Земли. Навигация запекается в рантайме из коллизий детей.
## Содержимое (лут, твари) раскладывает src/world/cluster_director.gd.

signal navigation_ready

const DoorScript := preload("res://src/world/door.gd")
const StashScript := preload("res://src/world/stash.gd")
const ExitScript := preload("res://src/world/cluster_exit.gd")

const SNAP_MAX_SHIFT := 6.0
const WALL_THICKNESS := 0.3
const DOOR_WIDTH := 1.4
const DOOR_HEIGHT := 2.3
## Выход — в метрах от края; герой после перехода встаёт глубже, чтобы не стоять на выходе.
const EXIT_INSET := 2.5
const ENTRY_INSET := 6.0
const EXIT_CLEAR_RADIUS := 7.0
const EDGE_WALL_HEIGHT := 4.0

var cluster_id: String
var template: Dictionary
var layout: Dictionary
var is_navigation_ready := false

var _doors: Array[StaticBody3D] = []
var _stashes: Array[Node3D] = []


func _ready() -> void:
	cluster_id = WorldSim.current
	template = WorldSim.template()
	var size := float(template["size"])
	var clear: Array = []
	for key in ["respawn", "plaza"]:
		if template.has(key):
			clear.append({"at": _v2(template[key]), "r": float(template["clear_radius"])})
	for neighbor in WorldSim.region.neighbors(cluster_id):
		clear.append({"at": WorldSim.region.exit_point(cluster_id, neighbor, size, EXIT_INSET), "r": EXIT_CLEAR_RADIUS})
	layout = ClusterLayout.generate(template, clear)

	_build_ground(size)
	for building: Dictionary in layout["buildings"]:
		_build_building(building)
	for prop: Dictionary in layout["props"]:
		_build_prop(prop)
	for point: Dictionary in layout["stashes"]:
		var stash: Node3D = StashScript.new()
		stash.position = Vector3(point["at"].x, 0.0, point["at"].y)
		add_child(stash)
		_stashes.append(stash)
	for neighbor in WorldSim.region.neighbors(cluster_id):
		_build_exit(neighbor, size)
	if cluster_id == String(WorldSim.region.region["respawn"]):
		_build_respawn_marker(PlayerState.respawn_position)

	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_radius = 0.5
	nav.agent_height = 1.75
	var half := size / 2.0
	var reach := half * 2.0 / HexGrid.SQRT3  # до вершины соты
	nav.filter_baking_aabb = AABB(Vector3(-half, -2, -reach), Vector3(size, 10, reach * 2.0))
	navigation_mesh = nav
	bake_finished.connect(_on_baked)
	bake_navigation_mesh(true)
	WorldSim.register("area", self)


func _exit_tree() -> void:
	WorldSim.unregister("area")


## Ближайшая точка навигации (для спавна тварей). Если навигация не нашла точку рядом
## (точка внутри коробки или карта пуста) — возвращает исходную.
func snap(point: Vector3) -> Vector3:
	var snapped_point := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)
	if Vector2(snapped_point.x - point.x, snapped_point.z - point.z).length() > SNAP_MAX_SHIFT:
		return point
	return snapped_point


## Где встать герою, пришедшему из соседнего кластера.
func entry_point(from_id: String) -> Vector3:
	if not WorldSim.region.neighbors(cluster_id).has(from_id):
		return Vector3(0, 0.1, 0)
	var p := WorldSim.region.exit_point(cluster_id, from_id, float(template["size"]), ENTRY_INSET)
	return Vector3(p.x, 0.1, p.y)


## Точки появления тварей: случайные на свободной земле соты, не ближе min_distance к герою.
func spawn_point(rng: RandomNumberGenerator, avoid: Vector3, min_distance: float) -> Vector3:
	var limit := float(template["size"]) / 2.0 - 8.0
	var point := Vector3.ZERO
	for attempt in 30:
		point = Vector3(rng.randf_range(-limit, limit), 0.0, rng.randf_range(-limit, limit))
		if HexGrid.inside(Vector2(point.x, point.z), limit) and Vector2(point.x - avoid.x, point.z - avoid.z).length() >= min_distance:
			break
	return snap(point)


## Свежий прилёт: тайники с новым содержимым и ненайденные, двери закрыты.
func fill_fresh(stash_contents: Array) -> void:
	for i in _stashes.size():
		_stashes[i].found = false
		_stashes[i].contents = stash_contents[i] if i < stash_contents.size() else []
		_stashes[i]._apply()
	for door in _doors:
		door.close_door()


func to_dict() -> Dictionary:
	var stashes: Array = []
	for stash in _stashes:
		stashes.append({"found": stash.found, "contents": stash.contents.duplicate(true)})
	var doors: Array = []
	for door in _doors:
		doors.append(door.is_open)
	return {"doors": doors, "stashes": stashes}


func load_dict(data: Dictionary) -> void:
	var saved: Array = data.get("stashes", [])
	for i in mini(saved.size(), _stashes.size()):
		_stashes[i].found = bool(saved[i]["found"])
		_stashes[i].contents = saved[i]["contents"]
		_stashes[i]._apply()
	var doors: Array = data.get("doors", [])
	for i in mini(doors.size(), _doors.size()):
		if bool(doors[i]):
			_doors[i].open_door()
		else:
			_doors[i].close_door()


func _on_baked() -> void:
	# Карта навигации синхронизируется асинхронно (4.4+): ждём новую итерацию карты,
	# иначе map_get_closest_point вернёт ноль.
	var map := get_world_3d().navigation_map
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	while NavigationServer3D.map_get_iteration_id(map) == iteration:
		await get_tree().physics_frame
	await get_tree().physics_frame
	is_navigation_ready = true
	navigation_ready.emit()


## Земля — шестиугольник (сота, D-70; size — между противоположными сторонами) и невидимые
## стены по шести сторонам: уйти можно только через выход к соседу.
func _build_ground(size: float) -> void:
	var apothem := size / 2.0
	var box := BoxShape3D.new()
	box.size = Vector3(size * 1.2 + 20.0, 1, size * 1.2 + 20.0)
	var hex := CylinderMesh.new()  # 6 граней: вершины на севере и юге, как HexGrid
	hex.radial_segments = 6
	hex.rings = 1
	hex.top_radius = apothem * 2.0 / HexGrid.SQRT3
	hex.bottom_radius = hex.top_radius
	hex.height = 0.1
	add_child(_static_body(box, Vector3(0, -0.5, 0), hex, Vector3(0, -0.05, 0), _color(template["ground_color"])))
	var side_length := apothem * 2.0 / HexGrid.SQRT3
	for side in 6:
		var normal := HexGrid.side_normal(side)
		var edge := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var edge_box := BoxShape3D.new()
		edge_box.size = Vector3(1.0, EDGE_WALL_HEIGHT, side_length + 1.5)
		shape.shape = edge_box
		edge.add_child(shape)
		edge.position = Vector3(normal.x, 0.0, normal.y) * (apothem + 0.5) + Vector3.UP * EDGE_WALL_HEIGHT / 2.0
		edge.rotation.y = -deg_to_rad(60.0 * side)
		add_child(edge)
	# Полоса за краем — «трещина» границы кластера, другой оттенок земли.
	var rim := PlaneMesh.new()
	rim.size = Vector2(size * 1.2 + 60.0, size * 1.2 + 60.0)
	var rim_instance := MeshInstance3D.new()
	rim_instance.mesh = rim
	rim_instance.position.y = -0.02
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = _color(template["ground_color"]).darkened(0.45)
	rim_instance.material_override = rim_material
	add_child(rim_instance)


## Здание: четыре стены, в одной — проём (со створкой или без, у руин).
func _build_building(b: Dictionary) -> void:
	var center := Vector3(b["center"].x, 0, b["center"].y)
	var sx: float = b["size"].x
	var sz: float = b["size"].y
	var h := float(b["height"])
	var color := _color(template["wall_color"])
	var t := WALL_THICKNESS
	var walls := {
		"n": {"at": center + Vector3(0, 0, sz / 2.0), "length": sx, "along_x": true},
		"s": {"at": center + Vector3(0, 0, -sz / 2.0), "length": sx, "along_x": true},
		"e": {"at": center + Vector3(sx / 2.0, 0, 0), "length": sz, "along_x": false},
		"w": {"at": center + Vector3(-sx / 2.0, 0, 0), "length": sz, "along_x": false},
	}
	for side: String in walls:
		var wall: Dictionary = walls[side]
		var at: Vector3 = wall["at"]
		var length := float(wall["length"])
		var along_x := bool(wall["along_x"])
		if side != String(b["door"]):
			_wall(at, Vector3(length, h, t) if along_x else Vector3(t, h, length), color)
			continue
		var piece := (length - DOOR_WIDTH) / 2.0
		var shift := (DOOR_WIDTH + piece) / 2.0
		var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var piece_size := Vector3(piece, h, t) if along_x else Vector3(t, h, piece)
		_wall(at - axis * shift, piece_size, color)
		_wall(at + axis * shift, piece_size, color)
		if h > DOOR_HEIGHT:
			var lintel := Vector3(DOOR_WIDTH, h - DOOR_HEIGHT, t) if along_x else Vector3(t, h - DOOR_HEIGHT, DOOR_WIDTH)
			_wall(at + Vector3(0, DOOR_HEIGHT, 0), lintel, color)
		if bool(b["leaf"]):
			var door: StaticBody3D = DoorScript.new()
			door.width = DOOR_WIDTH
			door.position = at
			door.rotation.y = 0.0 if along_x else PI / 2.0
			add_child(door)
			_doors.append(door)


func _wall(base: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	var at := base + Vector3(0, size.y / 2.0, 0)
	add_child(_static_body(box, at, mesh, at, color))


func _build_prop(prop: Dictionary) -> void:
	var size: Vector3 = prop["size"]
	var box := BoxShape3D.new()
	box.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	var shade := float(prop["shade"])
	var at := Vector3(prop["center"].x, size.y / 2.0, prop["center"].y)
	add_child(_static_body(box, at, mesh, at, Color(shade, shade * 0.95, shade * 0.9)))


func _build_exit(neighbor: String, size: float) -> void:
	var exit: Node3D = ExitScript.new()
	exit.target = neighbor
	var p := WorldSim.region.exit_point(cluster_id, neighbor, size, EXIT_INSET)
	exit.position = Vector3(p.x, 0.0, p.y)
	# Трещина — вдоль стороны соты: локальная ось X поворачивается к касательной стороны.
	var dir := WorldSim.region.direction(cluster_id, neighbor)
	exit.rotation.y = -dir.angle() - PI / 2.0
	add_child(exit)


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


static func _color(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
