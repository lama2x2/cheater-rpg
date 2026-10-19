class_name MapDraw
extends RefCounted
## Рисование карты (12.6) для окна карты и миникарты: соты региона, раскладка кластера (только
## известные постройки), выходы, респ, свой труп, найденные тайники, отметки игрока, герой и его
## взгляд. Тварей карта не показывает. Карта повёрнута как камера: «вверх» на карте — «вверх» на
## экране (изометрия смотрит под 45°), север показывает стрелка «С».

const MARK := "★"
const HERO_COLOR := Color(1.0, 0.92, 0.55)
const MARK_COLOR := Color(1.0, 0.75, 0.25)
const EDGE_COLOR := Color(0.85, 0.9, 0.85, 0.7)
const BUILDING_COLOR := Color(0.72, 0.62, 0.5, 0.95)


## Поворот карты: направление взгляда камеры на земле — вверх.
static func rotation_for(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	var f := -camera.global_transform.basis.z
	return -PI / 2.0 - atan2(f.z, f.x)


## Мир (x, z) → пиксели: точка focus — в center, масштаб px_per_m, поворот angle.
static func transform(center: Vector2, focus: Vector2, px_per_m: float, angle: float) -> Transform2D:
	var x := Vector2(cos(angle), sin(angle)) * px_per_m
	var y := Vector2(-sin(angle), cos(angle)) * px_per_m
	return Transform2D(x, y, center - (x * focus.x + y * focus.y))


static func type_color(type_id: String) -> Color:
	var colors: Dictionary = Content.map_config()["type_colors"]
	var c: Array = colors.get(type_id, [0.6, 0.6, 0.6])
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Текущий кластер: земля-сота, известные постройки, выходы, респ, труп, тайники, отметки.
## opts: {"labels": bool — подписи выходов полностью, "font": int — размер}.
static func draw_cluster(ci: CanvasItem, xf: Transform2D, area: Node3D, opts: Dictionary = {}) -> void:
	var id := WorldSim.current
	var apothem := float(area.template["size"]) / 2.0
	var font := UiKit.font()
	var size := int(opts.get("font", 12))
	var ground := type_color(WorldSim.cluster_type_id())
	ground.a = 0.35
	var hex := xf * HexGrid.corners(apothem)
	ci.draw_colored_polygon(hex, ground)
	hex.append(hex[0])
	ci.draw_polyline(hex, EDGE_COLOR, 2.0)
	var buildings: Array = area.layout["buildings"]
	for i in buildings.size():
		if not WorldSim.knowledge.knows_building(id, i):
			continue
		var b: Dictionary = buildings[i]
		var r := Rect2(b["center"] - b["size"] / 2.0, b["size"])
		var poly := xf * PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		ci.draw_colored_polygon(poly, BUILDING_COLOR)
	for neighbor in WorldSim.region.neighbors(id):
		var p := xf * WorldSim.region.exit_point(id, neighbor, apothem * 2.0, 2.5)
		var name := WorldSim.cluster_name(neighbor)
		if not bool(opts.get("labels", false)):
			name = name.left(3)
		ci.draw_circle(p, 4.0, Color(0.95, 0.85, 0.55))
		_text(ci, font, p + Vector2(0, -8), "→ " + name, size, Color(0.95, 0.9, 0.7))
	if id == String(WorldSim.region.region["respawn"]):
		var at := PlayerState.respawn_position
		_text(ci, font, xf * Vector2(at.x, at.z) + Vector2(0, size * 0.4), "✚", size + 2, Color(0.5, 0.9, 0.75))
	for corpse: Node3D in area.get_tree().get_nodes_in_group("corpses"):
		_text(ci, font, xf * Vector2(corpse.global_position.x, corpse.global_position.z) + Vector2(0, size * 0.4), "†", size + 2, Color(0.95, 0.5, 0.45))
	for stash: Node3D in area.get_tree().get_nodes_in_group("stashes"):
		if bool(stash.get("found")):
			_text(ci, font, xf * Vector2(stash.global_position.x, stash.global_position.z) + Vector2(0, size * 0.4), "▣", size, Color(0.75, 0.85, 1.0))
	for mark in WorldSim.knowledge.marks(id):
		_text(ci, font, xf * mark + Vector2(0, size * 0.4), MARK, size + 4, MARK_COLOR)


## Герой: точка и конус взгляда (бледный сектор на дальность зрения).
static func draw_hero(ci: CanvasItem, xf: Transform2D, hero: Node3D, cone_m: float) -> void:
	var at := Vector2(hero.global_position.x, hero.global_position.z)
	var vision := hero.get_tree().get_first_node_in_group("hero_vision")
	var look := Vector2(0, -1)
	var cone := 110.0
	if vision:
		look = Vector2(vision.view_dir.x, vision.view_dir.z)
		cone = float(vision.get("_cone"))
	if cone_m > 0.0 and look.length() > 0.01:
		var points := PackedVector2Array([xf * at])
		for i in 9:
			var a := look.angle() + deg_to_rad(cone) * (float(i) / 8.0 - 0.5)
			points.append(xf * (at + Vector2.from_angle(a) * cone_m))
		ci.draw_colored_polygon(points, Color(1.0, 0.95, 0.7, 0.13))
	var p := xf * at
	var dir := (xf.basis_xform(look)).normalized()
	ci.draw_colored_polygon(PackedVector2Array([p + dir * 9.0, p + dir.rotated(2.4) * 6.0, p + dir.rotated(-2.4) * 6.0]), HERO_COLOR)


## Стрелка на север: «С» в точке at.
static func draw_north(ci: CanvasItem, at: Vector2, angle: float, size: int = 13) -> void:
	var north := Vector2(0, -1).rotated(angle)  # север в мире — −z
	ci.draw_line(at, at + north * 14.0, Color(0.9, 0.9, 0.9, 0.8), 2.0)
	_text(ci, UiKit.font(), at + north * 22.0 + Vector2(0, size * 0.4), "С", size, Color(0.9, 0.9, 0.9, 0.9))


## Регион: соты по типам (известные), соседние посещённым — бледным контуром, остальное — туман.
## cell_px — радиус соты в пикселях. Возвращает {id: центр в пикселях} — для кликов.
static func draw_region(ci: CanvasItem, center: Vector2, cell_px: float, angle: float, hero: Node3D) -> Dictionary:
	var region := WorldSim.region
	var knowledge := WorldSim.knowledge
	var font := UiKit.font()
	var centers := {}
	var known: PackedStringArray = []
	var mid := Vector2.ZERO
	for id in region.ids():
		if knowledge.region_state(region, id) != MapKnowledge.UNKNOWN:
			known.append(id)
			mid += HexGrid.to_plane(region.hex(id))
	if known.is_empty():
		return centers
	mid /= known.size()
	var xf := transform(center, mid, cell_px, angle)
	var apothem := HexGrid.SQRT3 / 2.0
	for id in known:
		var state := knowledge.region_state(region, id)
		var c := HexGrid.to_plane(region.hex(id))
		var poly := xf * HexGrid.corners(apothem * 0.97, c)
		var color := type_color(WorldSim.cluster_type_id(id))
		color.a = 0.85 if state == MapKnowledge.VISITED else (0.5 if state == MapKnowledge.MAPPED else 0.12)
		ci.draw_colored_polygon(poly, color)
		var outline := poly.duplicate()
		outline.append(outline[0])
		ci.draw_polyline(outline, Color(1, 1, 1, 0.9) if id == WorldSim.current else Color(0.8, 0.85, 0.8, 0.45), 3.0 if id == WorldSim.current else 1.5)
		# Граница региона — толстой линией по сторонам, за которыми нет кластеров.
		var corners := xf * HexGrid.corners(apothem, c)
		for side in 6:
			if region.at_hex(region.hex(id) + HexGrid.DIRS[side]).is_empty():
				ci.draw_line(corners[(side + 5) % 6], corners[side], Color(0.95, 0.4, 0.3, 0.8), 4.0)
		var p := xf * c
		centers[id] = p
		var line_name := WorldSim.cluster_name(id)
		var line_type := Content.ui("cluster_type_" + WorldSim.cluster_type_id(id))
		_text(ci, font, p + Vector2(0, -10), line_name, 15, Color(0.95, 0.95, 0.9))
		_text(ci, font, p + Vector2(0, 8), line_type, 12, Color(0.8, 0.82, 0.8))
		var timer := WorldSim.timer_text(id)
		_text(ci, font, p + Vector2(0, 26), "⏱ " + timer, 12, Color(0.85, 0.9, 1.0) if not timer.contains("?") else Color(0.6, 0.62, 0.65))
		if knowledge.region_marks.has(id):
			_text(ci, font, p + Vector2(cell_px * 0.45, -cell_px * 0.35), MARK, 20, MARK_COLOR)
		if knowledge.is_mapped(id):
			_text(ci, font, p + Vector2(-cell_px * 0.45, -cell_px * 0.35), "▤", 14, Color(0.85, 0.9, 1.0))
	if hero and centers.has(WorldSim.current):
		var area := hero.get_tree().get_first_node_in_group("cluster_area")
		var apothem_m := float(area.template["size"]) / 2.0 if area else 60.0
		var local := Vector2(hero.global_position.x, hero.global_position.z) / apothem_m * apothem
		var p: Vector2 = xf * (HexGrid.to_plane(region.hex(WorldSim.current)) + local)
		ci.draw_circle(p, 5.0, HERO_COLOR)
	return centers


static func _text(ci: CanvasItem, font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string_outline(font, at - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	ci.draw_string(font, at - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
