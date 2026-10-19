extends "res://tests/test_case.gd"
## Соты (D-70): осевые координаты, соседи, стороны, попадание в шестиугольник.

const HexGridScript := preload("res://src/core/hex_grid.gd")


func test_neighbors_are_adjacent() -> void:
	for i in 6:
		var dir: Vector2i = HexGridScript.DIRS[i]
		assert_eq(HexGridScript.distance(Vector2i.ZERO, dir), 1, "сосед %d — на расстоянии 1" % i)
		assert_eq(HexGridScript.side_between(Vector2i.ZERO, dir), i, "сторона %d" % i)
		var center := HexGridScript.to_plane(dir)
		assert_almost(center.length(), HexGridScript.SQRT3, "центры соседей — через две апофемы", 0.0001)
		assert_true(center.normalized().distance_to(HexGridScript.side_normal(i)) < 0.0001, "сторона %d смотрит на соседа" % i)
	assert_eq(HexGridScript.side_between(Vector2i.ZERO, Vector2i(2, 0)), -1, "не сосед")
	assert_eq(HexGridScript.distance(Vector2i(0, 0), Vector2i(2, -1)), 2, "расстояние в сотах")


func test_from_plane_round_trip() -> void:
	for cell in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-1, 4), Vector2i(2, 2)]:
		assert_eq(HexGridScript.from_plane(HexGridScript.to_plane(cell)), cell, "центр %s" % cell)
		assert_eq(HexGridScript.from_plane(HexGridScript.to_plane(cell) + Vector2(0.4, -0.3)), cell, "рядом с центром %s" % cell)


func test_inside_and_corners() -> void:
	assert_true(HexGridScript.inside(Vector2(49.9, 0), 50.0), "у восточной стороны — внутри")
	assert_true(not HexGridScript.inside(Vector2(50.1, 0), 50.0), "за ней — снаружи")
	assert_true(HexGridScript.inside(Vector2(0, 57.0), 50.0), "к югу — до вершины (57,7)")
	assert_true(not HexGridScript.inside(Vector2(0, 58.0), 50.0), "дальше вершины — снаружи")
	var corners := HexGridScript.corners(50.0)
	assert_eq(corners.size(), 6, "шесть вершин")
	for corner in corners:
		assert_almost(corner.length(), 100.0 / HexGridScript.SQRT3, "на описанной окружности", 0.001)
	assert_true(HexGridScript.encloses(50.0, Rect2(-20, -20, 40, 40)), "квадрат 40 в соте 100 — внутри")
	assert_true(not HexGridScript.encloses(50.0, Rect2(30, 30, 15, 15)), "угол у диагональной стороны — снаружи")
