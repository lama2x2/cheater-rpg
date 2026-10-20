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
## «Трещина» за краем соты и юбка края рельефа уходят на эту глубину.
const RIM_DEPTH := -2.4

var cluster_id: String
var template: Dictionary
var layout: Dictionary
var is_navigation_ready := false

var _doors: Array[StaticBody3D] = []
## Стены зданий для среза (D-102): [{"rect": Rect2, "walls": [{"side", "body", "height"}]}].
var building_walls: Array = []
var _stashes: Array[Node3D] = []
## Ландшафт (задача 19a): рельеф, ручей, растительность и запросы (кусты, вода, скорость, шум).
var terrain: TerrainRules
static var _plant_scenes: Dictionary = {}


func _ready() -> void:
	add_to_group("cluster_area")
	cluster_id = WorldSim.current
	template = WorldSim.template()
	var size := float(template["size"])
	var clear: Array = []
	for key in ["respawn", "plaza"]:
		if template.has(key):
			clear.append({"at": _v2(template[key]), "r": float(template["clear_radius"])})
	for neighbor in WorldSim.region.neighbors(cluster_id):
		clear.append({"at": WorldSim.region.exit_point(cluster_id, neighbor, size, EXIT_INSET), "r": EXIT_CLEAR_RADIUS})
	# Ручей ложится на сторону без соседа; раскладка обходит русло.
	var free_sides: Array = []
	for side in 6:
		var free := true
		for neighbor in WorldSim.region.neighbors(cluster_id):
			if WorldSim.region.side(cluster_id, neighbor) == side:
				free = false
		if free:
			free_sides.append(side)
	terrain = TerrainRules.new(Content.terrain_config(), template.get("terrain", {}), size, int(template["layout_seed"]), free_sides)
	clear.append_array(terrain.stream_clear_zones())
	layout = ClusterLayout.generate(template, clear)
	terrain.set_features(_flat_features(size))
	terrain.scatter()

	_build_ground(size)
	_build_terrain(size)
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
	rim_instance.position.y = RIM_DEPTH  # ниже самого глубокого русла (задача 19a)
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
	var record := {"rect": Rect2(b["center"] - b["size"] / 2.0, b["size"]), "walls": [], "height": h}
	building_walls.append(record)
	# Крыша (задача 19, 17.3): двускатная, без коллизий; у руин крыши нет.
	if String(b["kind"]) != "ruin":
		record["roof"] = _roof(record["rect"], h, String(b["kind"]))
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
			record["walls"].append({"side": side, "body": _wall(at, Vector3(length, h, t) if along_x else Vector3(t, h, length), color)})
			continue
		var piece := (length - DOOR_WIDTH) / 2.0
		var shift := (DOOR_WIDTH + piece) / 2.0
		var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var piece_size := Vector3(piece, h, t) if along_x else Vector3(t, h, piece)
		record["walls"].append({"side": side, "body": _wall(at - axis * shift, piece_size, color)})
		record["walls"].append({"side": side, "body": _wall(at + axis * shift, piece_size, color)})
		if h > DOOR_HEIGHT:
			var lintel := Vector3(DOOR_WIDTH, h - DOOR_HEIGHT, t) if along_x else Vector3(t, h - DOOR_HEIGHT, DOOR_WIDTH)
			record["walls"].append({"side": side, "body": _wall(at + Vector3(0, DOOR_HEIGHT, 0), lintel, color)})
		if bool(b["leaf"]):
			var door: StaticBody3D = DoorScript.new()
			door.width = DOOR_WIDTH
			door.position = at
			door.rotation.y = 0.0 if along_x else PI / 2.0
			add_child(door)
			_doors.append(door)
			record["walls"].append({"side": side, "body": door})


## Где рельеф ровный (TerrainRules.set_features): постройки, препятствия, лут, тайники, выходы,
## места входа, респ и площадь стаба.
func _flat_features(size: float) -> Array:
	var features: Array = []
	for b: Dictionary in layout["buildings"]:
		features.append(Rect2(b["center"] - b["size"] / 2.0, b["size"]).grow(1.5))
	for prop: Dictionary in layout["props"]:
		var s: Vector3 = prop["size"]
		features.append(Rect2(prop["center"] - Vector2(s.x, s.z) / 2.0, Vector2(s.x, s.z)).grow(0.5))
	for point: Dictionary in layout["loot"] + layout["stashes"]:
		features.append(point["at"])
	for neighbor in WorldSim.region.neighbors(cluster_id):
		features.append(WorldSim.region.exit_point(cluster_id, neighbor, size, EXIT_INSET))
		features.append(WorldSim.region.exit_point(cluster_id, neighbor, size, ENTRY_INSET))
	for key in ["respawn", "plaza"]:
		if template.has(key):
			var at := _v2(template[key])
			var r := float(template["clear_radius"]) + 4.0
			features.append(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0))
	return features


## Рельеф (задача 19a): меш по сетке 2 м внутри соты, коллизия — карта высот 1 м; вода в русле;
## деревья и камни — с коллизией ствола (закрывают обзор и путь), кусты и трава — без.
func _build_terrain(size: float) -> void:
	var apothem := size / 2.0
	var reach := apothem * 2.0 / HexGrid.SQRT3 + 2.0
	var cells := int(ceil(reach)) * 2
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for z in cells + 1:
		for x in cells + 1:
			var p := Vector2(x - cells / 2.0, z - cells / 2.0)
			heights[z * (cells + 1) + x] = terrain.height_at(p) if HexGrid.inside(p, apothem + 1.0) else 0.0
	var shape := HeightMapShape3D.new()
	shape.map_width = cells + 1
	shape.map_depth = cells + 1
	shape.map_data = heights
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	# Меш: шаг 2 м, только треугольники внутри соты.
	var step := 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ground := _color(template["ground_color"])
	var n := int(ceil(reach / step))
	# Вершины за краем соты притягиваются к её границе — край ровный, без ступенек.
	var vertex := func(x: float, z: float) -> void:
		var p := Vector2(x, z)
		var k := 1.0
		for side in 3:
			var d := absf(p.dot(HexGrid.side_normal(side)))
			if d > apothem:
				k = minf(k, apothem / d)
		p *= k
		var h := terrain.height_at(p)
		st.set_color(ground.darkened(clampf(-h * 0.25, 0.0, 0.4)).lightened(clampf(h * 0.04, 0.0, 0.15)))
		st.add_vertex(Vector3(p.x, h, p.y))
	for iz in range(-n, n):
		for ix in range(-n, n):
			var x0 := ix * step
			var z0 := iz * step
			var corners_in := 0
			for c in [Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0, z0 + step), Vector2(x0 + step, z0 + step)]:
				if HexGrid.inside(c, apothem):
					corners_in += 1
			if corners_in == 0 and not HexGrid.inside(Vector2(x0 + step / 2.0, z0 + step / 2.0), apothem):
				continue
			vertex.call(x0, z0)
			vertex.call(x0 + step, z0)
			vertex.call(x0 + step, z0 + step)
			vertex.call(x0, z0)
			vertex.call(x0 + step, z0 + step)
			vertex.call(x0, z0 + step)
	# Юбка: от края рельефа вниз до «трещины» — у соты есть толщина, а не щель.
	var corners := HexGrid.corners(apothem)
	var dark := ground.darkened(0.5)
	for side in 6:
		var a: Vector2 = corners[(side + 5) % 6]
		var b: Vector2 = corners[side]
		for i in 24:
			var p0 := a.lerp(b, i / 24.0)
			var p1 := a.lerp(b, (i + 1) / 24.0)
			var t0 := Vector3(p0.x, terrain.height_at(p0), p0.y)
			var t1 := Vector3(p1.x, terrain.height_at(p1), p1.y)
			var b0 := Vector3(p0.x, RIM_DEPTH, p0.y)
			var b1 := Vector3(p1.x, RIM_DEPTH, p1.y)
			for v: Vector3 in [t0, b0, t1, t1, b0, b1]:
				st.set_color(dark)
				st.add_vertex(v)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	mesh.material_override = material
	add_child(mesh)
	if not terrain.stream.is_empty():
		_build_water(apothem)
	_build_plants()


## Вода — полоса вдоль русла на уровне воды, полупрозрачная.
func _build_water(apothem: float) -> void:
	var s := terrain.stream
	var normal: Vector2 = s["normal"]
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(s["half"]) * 2.0, apothem * 2.4)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.58, 0.75, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # вода читается и в тени, и ночью
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var center := normal * float(s["offset"])
	water.position = Vector3(center.x, float(terrain.config["water_level"]), center.y)
	water.rotation.y = -normal.angle()
	add_child(water)


func _build_plants() -> void:
	var kinds: Dictionary = terrain.config["kinds"]
	for plant: Dictionary in terrain.plants:
		var model := String(plant["model"])
		if not _plant_scenes.has(model):
			var path := "res://assets/third_party/kenney/%s.glb" % model
			_plant_scenes[model] = load(path) if ResourceLoader.exists(path) else null
		var scene: PackedScene = _plant_scenes[model]
		if scene == null:
			continue
		var kind: Dictionary = kinds[String(plant["kind"])]
		var at: Vector2 = plant["at"]
		var node: Node3D = scene.instantiate()
		var k := float(kind["model_scale"]) * float(plant["scale"])
		node.scale = Vector3(k, k, k)
		node.rotation.y = float(plant["rot"])
		var holder := StaticBody3D.new() if float(kind["collision_r"]) > 0.0 else Node3D.new()
		holder.position = Vector3(at.x, terrain.height_at(at), at.y)
		holder.add_child(node)
		if holder is StaticBody3D:
			var trunk := CylinderShape3D.new()
			trunk.radius = float(kind["collision_r"]) * float(plant["scale"])
			trunk.height = 3.0
			var cs := CollisionShape3D.new()
			cs.shape = trunk
			cs.position.y = 1.5
			holder.add_child(cs)
		if String(plant["kind"]) == "grass":
			for m in node.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_to_group("plants")
		add_child(holder)


## Двускатная крыша над прямоугольником: конёк вдоль длинной стороны, свес 0,3 м.
func _roof(rect: Rect2, wall_h: float, kind: String) -> MeshInstance3D:
	var r := rect.grow(0.3)
	var along_x := r.size.x >= r.size.y
	var rise := clampf(minf(r.size.x, r.size.y) * 0.35, 0.8, 2.2)
	var y0 := wall_h
	var y1 := wall_h + rise
	var a := Vector3(r.position.x, y0, r.position.y)
	var b := Vector3(r.end.x, y0, r.position.y)
	var c := Vector3(r.end.x, y0, r.end.y)
	var d := Vector3(r.position.x, y0, r.end.y)
	var mid := r.get_center()
	var p: Vector3
	var q: Vector3
	if along_x:
		p = Vector3(r.position.x, y1, mid.y)
		q = Vector3(r.end.x, y1, mid.y)
	else:
		p = Vector3(mid.x, y1, r.position.y)
		q = Vector3(mid.x, y1, r.end.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris: Array = [[a, p, q], [a, q, b], [c, q, p], [c, p, d], [d, p, a], [b, q, c]] if along_x \
		else [[a, b, p], [b, q, p], [b, c, q], [c, d, q], [d, p, q], [d, a, p]]
	for t: Array in tris:
		for v: Vector3 in t:
			st.add_vertex(v)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var material := StandardMaterial3D.new()
	var palette := {"house": Color(0.55, 0.28, 0.22), "shop": Color(0.35, 0.38, 0.42), "garage": Color(0.4, 0.4, 0.38),
		"police": Color(0.3, 0.33, 0.4), "hunter": Color(0.42, 0.32, 0.22), "workshop": Color(0.38, 0.36, 0.33)}
	material.albedo_color = palette.get(kind, Color(0.45, 0.35, 0.3))
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.add_to_group("roofs")
	add_child(mesh)
	return mesh


func _wall(base: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var box := BoxShape3D.new()
	box.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	var at := base + Vector3(0, size.y / 2.0, 0)
	var body := _static_body(box, at, mesh, at, color)
	add_child(body)
	return body


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
