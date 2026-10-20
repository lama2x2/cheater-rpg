class_name TerrainRules
extends RefCounted
## Ландшафт кластера (02 «Соты и ландшафт», 17.4, D-71, задача 19a): рельеф шумом — ровно под
## постройками, у выходов, точек лута и респа; ручей вдоль стороны соты без соседа (с бродом);
## деревья, кусты, трава, камни. Запросы для сцены: высота, вода, куст, трава; множители скорости,
## шума и видимости; прибавка дальности зрения с высоты. Чистые правила: детерминированно по сиду
## раскладки — после перезагрузки это тот же кусок Земли. Данные — data/terrain.json (общие числа)
## и terrain в шаблоне кластера.

const REQUIRED_KEYS: PackedStringArray = ["speed", "noise", "visibility", "bush_radius_m", "bush_reveal_m",
	"height_view_per_m", "slope_penalty", "slope_min_mult", "water_level", "kinds"]

var config: Dictionary
var terrain: Dictionary
var apothem := 50.0
var stream: Dictionary = {}
## Растительность: [{"kind": tree|bush|grass|rock, "model", "at": Vector2, "scale", "rot"}].
var plants: Array[Dictionary] = []

var _noise := FastNoiseLite.new()
var _features: Array = []
var _bushes: Array[Vector2] = []
var _grass: Array[Vector2] = []


## template_terrain — раздел terrain шаблона ({} — ровно и голо); free_sides — стороны соты без
## соседа (0..5, HexGrid), туда может лечь ручей.
func _init(common: Dictionary, template_terrain: Dictionary, size: float, seed_value: int, free_sides: Array) -> void:
	config = common
	terrain = template_terrain
	apothem = size / 2.0
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = float(terrain.get("frequency", 0.03))
	var s: Dictionary = terrain.get("stream", {})
	if not s.is_empty() and not free_sides.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + 17
		var side := int(free_sides[rng.randi_range(0, free_sides.size() - 1)])
		stream = {"side": side, "normal": HexGrid.side_normal(side), "offset": apothem - float(s.get("inset_m", 10.0)),
			"half": float(s.get("width_m", 6.0)) / 2.0, "depth": float(s.get("depth_m", 1.5)),
			"ford_half": float(s.get("ford_m", 6.0)) / 2.0}


## Зоны «тут ничего не ставить» для раскладки (ClusterLayout.clear): кружки вдоль ручья.
func stream_clear_zones() -> Array:
	var zones: Array = []
	if stream.is_empty():
		return zones
	var n: Vector2 = stream["normal"]
	var t := Vector2(-n.y, n.x)
	var reach := apothem * 2.0 / HexGrid.SQRT3
	var step := 6.0
	var k := -reach
	while k <= reach:
		zones.append({"at": n * float(stream["offset"]) + t * k, "r": float(stream["half"]) + 2.5})
		k += step
	return zones


## Где рельеф должен быть ровным: прямоугольники (Rect2) и точки (Vector2) с запасом flat_margin.
func set_features(features: Array) -> void:
	_features = features


func _flat_factor(p: Vector2) -> float:
	var margin := float(terrain.get("flat_margin_m", 4.0))
	var best := INF
	for f: Variant in _features:
		var d: float
		if f is Rect2:
			var r: Rect2 = f
			var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
			d = c.distance_to(p)
		else:
			d = (f as Vector2).distance_to(p) - 2.0
		best = minf(best, d)
		if best <= 0.0:
			return 0.0
	return clampf(best / margin, 0.0, 1.0) if margin > 0.0 else 1.0


## Расстояние до русла (от оси) и вдоль него; нет ручья — INF.
func _stream_coords(p: Vector2) -> Vector2:
	if stream.is_empty():
		return Vector2(INF, INF)
	var n: Vector2 = stream["normal"]
	return Vector2(absf(p.dot(n) - float(stream["offset"])), p.dot(Vector2(-n.y, n.x)))


## Высота земли в точке (x, z).
func height_at(p: Vector2) -> float:
	var amp := float(terrain.get("amplitude_m", 0.0))
	var h := 0.0
	if amp > 0.0:
		h = amp * (_noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5) * _flat_factor(p)
	var s := _stream_coords(p)
	if s.x < float(stream.get("half", 0.0)):
		var u := s.x / float(stream["half"])
		var depth := float(stream["depth"])
		if absf(s.y) < float(stream["ford_half"]):
			depth = float(config["water_level"]) * -1.0 + 0.15  # брод — по колено
		h = minf(h, -depth * (1.0 - u * u))
	return h


## Вода в точке: "" — сухо, "ford" — мелко (брод), "water" — глубоко (вплавь).
func water_at(p: Vector2) -> String:
	var h := height_at(p)
	var level := float(config["water_level"])
	if h >= level:
		return ""
	return "water" if h < level - 0.35 else "ford"


## Растительность: деревья не теснее tree_gap, ничего — на постройках, у точек и в воде.
func scatter() -> void:
	plants.clear()
	_bushes.clear()
	_grass.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _noise.seed + 101
	var limit := apothem - 4.0
	var sections := {"tree": "trees", "rock": "rocks", "bush": "bushes", "grass": "grass"}
	for kind: String in sections:
		var spec: Dictionary = terrain.get(sections[kind], {})
		var count := int(spec.get("count", 0))
		var models: Array = spec.get("models", [])
		if count <= 0 or models.is_empty():
			continue
		var gap := float(spec.get("gap_m", 1.0))
		var placed := 0
		var tries := 0
		while placed < count and tries < count * 20:
			tries += 1
			var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
			if not HexGrid.inside(p, limit) or _flat_factor(p) < 0.5 or not water_at(p).is_empty():
				continue
			if kind == "grass" and _noise.get_noise_2d(p.x + 500.0, p.y) < float(spec.get("patchiness", -1.0)):
				continue  # трава — пятнами
			var close := false
			for other in plants:
				if (other["at"] as Vector2).distance_to(p) < gap and (kind != "grass" or other["kind"] != "grass"):
					close = true
					break
			if close:
				continue
			var s: Array = spec.get("scale", [1.0, 1.0])
			plants.append({"kind": kind, "model": String(models[rng.randi_range(0, models.size() - 1)]), "at": p,
				"scale": rng.randf_range(float(s[0]), float(s[1])), "rot": rng.randf() * TAU})
			if kind == "bush":
				_bushes.append(p)
			elif kind == "grass":
				_grass.append(p)
			placed += 1


func in_bush(p: Vector2) -> bool:
	var r := float(config["bush_radius_m"])
	for b in _bushes:
		if b.distance_to(p) <= r:
			return true
	return false


func in_grass(p: Vector2) -> bool:
	for g in _grass:
		if g.distance_to(p) <= 1.2:
			return true
	return false


## Сколько кустов закрывают отрезок a → b (куст у самой точки a или b не считается: кто в кусте,
## того видно вблизи — bush_reveal_m).
func bushes_between(a: Vector2, b: Vector2) -> int:
	var r := float(config["bush_radius_m"])
	var count := 0
	for c in _bushes:
		if c.distance_to(a) <= r or c.distance_to(b) <= r:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(c, a, b)
		if closest.distance_to(c) <= r:
			count += 1
	return count


## Видно ли цель в точке target из точки from с учётом кустов (стены и рельеф — лучами сцены).
func bush_visible(from: Vector2, target: Vector2) -> bool:
	if bushes_between(from, target) > 0:
		return false
	return not in_bush(target) or from.distance_to(target) <= float(config["bush_reveal_m"])


## Множитель скорости: вода, брод, куст; склон в гору.
func speed_mult(p: Vector2, dir: Vector2 = Vector2.ZERO) -> float:
	var s: Dictionary = config["speed"]
	var mult := 1.0
	match water_at(p):
		"water":
			mult *= float(s["water"])
		"ford":
			mult *= float(s["ford"])
	if in_bush(p):
		mult *= float(s["bush"])
	if dir.length() > 0.01:
		var grade := (height_at(p + dir.normalized() * 0.6) - height_at(p)) / 0.6
		if grade > 0.0:
			mult *= maxf(1.0 - grade * float(config["slope_penalty"]), float(config["slope_min_mult"]))
	return mult


## Множитель громкости шагов: куст, трава (глушат), вода (плеск).
func noise_mult(p: Vector2) -> float:
	var n: Dictionary = config["noise"]
	if not water_at(p).is_empty():
		return float(n["water"])
	if in_bush(p):
		return float(n["bush"])
	if in_grass(p):
		return float(n["grass"])
	return 1.0


## Насколько хуже видно того, кто стоит здесь (куст — как «красться»).
func visibility_mult(p: Vector2) -> float:
	return float(config["visibility"]["bush"]) if in_bush(p) else 1.0


## Прибавка к дальности зрения с возвышенности (из оврага — минус).
func height_view_bonus(height: float) -> float:
	return height * float(config["height_view_per_m"])


## Ландшафт текущего кластера на сцене (или null: сценарии без кластера).
static func of(tree: SceneTree) -> TerrainRules:
	var area := tree.get_first_node_in_group("cluster_area") if tree else null
	return area.get("terrain") if area else null
