class_name ClusterLayout
extends RefCounted
## Раскладка кластера по шаблону: здания с дверями, препятствия, точки лута и тайников.
## Детерминированно по layout_seed: после перезагрузки это тот же кусок Земли — меняются только
## лут и жители (сид прилёта). Чистый класс без Node. Шаблоны — data/world/templates/*.json (14.7).
##
## Результат generate(): {
##   "half": полстороны, "buildings": [{"kind", "center": Vector2, "size": Vector2, "height",
##     "door": сторона проёма "n"/"s"/"e"/"w", "leaf": есть ли створка (у руин — просто дыра)}],
##   "props": [{"center": Vector2, "size": Vector3, "shade"}],
##   "loot": [{"at": Vector2, "table"}], "stashes": [{"at": Vector2, "table"}] }
## Координаты — (x, z) в метрах от центра кластера; «n» — сторона +z.

const REQUIRED_KEYS: PackedStringArray = [
	"id", "size", "layout_seed", "ground_color", "wall_color", "prop_shade", "clear_radius", "buildings", "props",
]
const EDGE_MARGIN := 6.0
const BUILDING_GAP := 3.0
const PROP_GAP := 1.2
const INNER_MARGIN := 1.2
const ATTEMPTS := 80
const SIDES: PackedStringArray = ["n", "s", "e", "w"]


## clear — зоны, где ничего не ставим: [{"at": Vector2, "r": float}] (респ, выходы).
static func generate(template: Dictionary, clear: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(template["layout_seed"])
	var half := float(template["size"]) / 2.0
	var occupied: Array[Rect2] = []
	var buildings: Array = []
	var loot: Array = []
	for group: Dictionary in template["buildings"]:
		var size_range: Array = group["size"]
		for i in int(group["count"]):
			var size := Vector2(_range(size_range[0], rng), _range(size_range[1], rng))
			var rect := _place(size, half, BUILDING_GAP, occupied, clear, rng)
			if rect.size == Vector2.ZERO:
				continue
			occupied.append(rect)
			buildings.append({
				"kind": String(group["kind"]), "center": rect.get_center(), "size": rect.size,
				"height": float(group.get("wall_height", 3.0)),
				"door": SIDES[rng.randi_range(0, 3)], "leaf": bool(group.get("door", true)),
			})
			if group.has("loot"):
				var spots: Array = group["loot_spots"]
				for k in rng.randi_range(int(spots[0]), int(spots[1])):
					loot.append({"at": _inside(rect, INNER_MARGIN, rng), "table": String(group["loot"])})

	var props: Array = []
	var props_config: Dictionary = template["props"]
	var shade: Array = template["prop_shade"]
	for i in int(props_config["count"]):
		var s: Array = props_config["size"]
		var size3 := Vector3(_range(s[0], rng), _range(s[1], rng), _range(s[2], rng))
		var rect := _place(Vector2(size3.x, size3.z), half, PROP_GAP, occupied, clear, rng)
		if rect.size == Vector2.ZERO:
			continue
		occupied.append(rect)
		props.append({"center": rect.get_center(), "size": size3, "shade": rng.randf_range(float(shade[0]), float(shade[1]))})

	if template.has("outdoor_loot"):
		for i in int(template["outdoor_loot"]["count"]):
			loot.append({"at": _free_point(half, occupied, rng), "table": String(template["outdoor_loot"]["table"])})
	var stashes: Array = []
	if template.has("stashes"):
		for i in int(template["stashes"]["count"]):
			stashes.append({"at": _free_point(half, occupied, rng), "table": String(template["stashes"]["table"])})
	return {"half": half, "buildings": buildings, "props": props, "loot": loot, "stashes": stashes}


## Прямоугольник size внутри кластера, не ближе gap к занятому и вне чистых зон.
## Нулевой Rect2 — не нашлось места за ATTEMPTS попыток.
static func _place(size: Vector2, half: float, gap: float, occupied: Array[Rect2], clear: Array, rng: RandomNumberGenerator) -> Rect2:
	var limit := half - EDGE_MARGIN
	if size.x / 2.0 >= limit or size.y / 2.0 >= limit:
		return Rect2()
	for attempt in ATTEMPTS:
		var center := Vector2(rng.randf_range(-limit + size.x / 2.0, limit - size.x / 2.0),
				rng.randf_range(-limit + size.y / 2.0, limit - size.y / 2.0))
		var rect := Rect2(center - size / 2.0, size)
		if not _blocked(rect.grow(gap), occupied, clear):
			return rect
	return Rect2()


static func _blocked(rect: Rect2, occupied: Array[Rect2], clear: Array) -> bool:
	for other in occupied:
		if rect.intersects(other):
			return true
	for zone: Dictionary in clear:
		var at: Vector2 = zone["at"]
		var closest := Vector2(clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y))
		if closest.distance_to(at) < float(zone["r"]):
			return true
	return false


## Точка снаружи всех зданий и препятствий (для уличного лута и тайников).
static func _free_point(half: float, occupied: Array[Rect2], rng: RandomNumberGenerator) -> Vector2:
	var limit := half - EDGE_MARGIN
	var point := Vector2.ZERO
	for attempt in ATTEMPTS:
		point = Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		if not _blocked(Rect2(point - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), occupied, []):
			return point
	return point


static func _inside(rect: Rect2, margin: float, rng: RandomNumberGenerator) -> Vector2:
	var inner := rect.grow(-margin)
	return Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))


static func _range(pair: Array, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(float(pair[0]), float(pair[1]))


## Точки лута, уцелевшие к приходу героя: каждая — с вероятностью loot_index (мародёры).
## Возвращает [{"id", "count", "at": Vector2}] — что разложить по земле.
static func roll_loot(points: Array, loot_table: LootTable, loot_index: float, luck: float, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	for point: Dictionary in points:
		if rng.randf() >= loot_index:
			continue
		var rolled := loot_table.roll(String(point["table"]), 0.0, luck, rng)
		var k := 0
		for id: String in rolled:
			var at: Vector2 = point["at"]
			var offset := Vector2.ZERO if k == 0 else Vector2.from_angle(k * 2.4) * 0.55
			result.append({"id": id, "count": int(rolled[id]), "at": at + offset})
			k += 1
	return result


## Содержимое тайников: [[id, count], ...] на каждый тайник (тайники не грабят — loot_index не влияет).
static func roll_stashes(points: Array, loot_table: LootTable, luck: float, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	for point: Dictionary in points:
		var rolled := loot_table.roll(String(point["table"]), 0.0, luck, rng)
		var contents: Array = []
		for id: String in rolled:
			contents.append([id, int(rolled[id])])
		result.append(contents)
	return result
