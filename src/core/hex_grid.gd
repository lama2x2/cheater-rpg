class_name HexGrid
extends RefCounted
## Соты (D-70): осевые координаты (q, r), шестиугольники «остриём вверх» — вершины на севере и
## юге, плоские стороны смотрят на восток, запад и по диагоналям. Плоскость — (x, z) сцены:
## +x восток, +z юг (на карте — вниз). Чистая математика без Node.
##
## Сторона i (0..5) смотрит под углом 60° × i от востока к югу: 0 — В, 1 — ЮВ, 2 — ЮЗ, 3 — З,
## 4 — СЗ, 5 — СВ. Сосед через сторону i — (q, r) + DIRS[i].

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const SQRT3 := 1.7320508075688772


## Центр соты на плоскости при радиусе описанной окружности 1 (вершина — на расстоянии 1).
static func to_plane(hex: Vector2i) -> Vector2:
	return Vector2(SQRT3 * (hex.x + hex.y / 2.0), 1.5 * hex.y)


## Сота, в которой лежит точка плоскости (радиус описанной окружности 1).
static func from_plane(point: Vector2) -> Vector2i:
	var q := (SQRT3 / 3.0 * point.x - point.y / 3.0)
	var r := (2.0 / 3.0 * point.y)
	return round_axial(q, r)


static func round_axial(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Номер стороны, через которую b соседствует с a, или −1.
static func side_between(a: Vector2i, b: Vector2i) -> int:
	return DIRS.find(b - a)


## Единичная нормаль стороны i (наружу).
static func side_normal(side: int) -> Vector2:
	return Vector2.from_angle(deg_to_rad(60.0 * side))


## Вершины шестиугольника с апофемой apothem (половина расстояния между противоположными
## сторонами) вокруг center, по часовой на карте: от вершины между сторонами 0 и 1.
static func corners(apothem: float, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var radius := apothem * 2.0 / SQRT3
	var result := PackedVector2Array()
	for i in 6:
		result.append(center + Vector2.from_angle(deg_to_rad(30.0 + 60.0 * i)) * radius)
	return result


## Точка внутри шестиугольника с апофемой apothem (центр — 0).
static func inside(point: Vector2, apothem: float) -> bool:
	for side in 3:
		if absf(point.dot(side_normal(side))) > apothem:
			return false
	return true


## Прямоугольник целиком внутри шестиугольника.
static func encloses(apothem: float, rect: Rect2) -> bool:
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		if not inside(corner, apothem):
			return false
	return true
