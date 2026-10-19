class_name RegionMap
extends RefCounted
## Регион — сотовая сетка кластеров (D-70): у каждого кластера осевые координаты hex: [q, r]
## (HexGrid), соседи — кластеры на соседних сотах, граница проходит по стороне. Выход к соседу —
## посередине общей стороны. Чистый класс без Node. Данные — data/world/region.json (схема 14.8).
## Спецификация: docs/spec/02_world.md («Соты и ландшафт», «Регионы и границы»).

const REQUIRED_KEYS: PackedStringArray = ["id", "name", "start", "respawn", "clusters"]
const CLUSTER_KEYS: PackedStringArray = ["id", "code", "name", "type", "template", "hex"]

var region: Dictionary
var _clusters: Dictionary = {}
## Сота → id кластера.
var _by_hex: Dictionary = {}


func _init(data: Dictionary) -> void:
	region = data
	for cluster: Dictionary in data.get("clusters", []):
		_clusters[String(cluster.get("id", ""))] = cluster
		if cluster.has("hex"):
			_by_hex[_to_hex(cluster["hex"])] = String(cluster["id"])
	# Соседи — по сетке: кто стоит на соседних сотах (порядок — по сторонам 0..5).
	for id: String in _clusters:
		var cluster: Dictionary = _clusters[id]
		var list: Array = []
		if cluster.has("hex"):
			var at := _to_hex(cluster["hex"])
			for dir in HexGrid.DIRS:
				if _by_hex.has(at + dir):
					list.append(_by_hex[at + dir])
		cluster["neighbors"] = list


func ids() -> PackedStringArray:
	return PackedStringArray(_clusters.keys())


func has_cluster(id: String) -> bool:
	return _clusters.has(id)


func cluster(id: String) -> Dictionary:
	assert(_clusters.has(id), "Неизвестный кластер: %s" % id)
	return _clusters[id]


func neighbors(id: String) -> PackedStringArray:
	return PackedStringArray(cluster(id)["neighbors"])


func hex(id: String) -> Vector2i:
	return _to_hex(cluster(id)["hex"])


## Кластер на соте или "".
func at_hex(cell: Vector2i) -> String:
	return String(_by_hex.get(cell, ""))


## Сторона соты from_id (0..5, HexGrid), за которой лежит to_id, или −1.
func side(from_id: String, to_id: String) -> int:
	return HexGrid.side_between(hex(from_id), hex(to_id))


## Ошибки данных: ключи, две соты в одной клетке, шаблоны и типы без описания, кластеры, до
## которых не дойти от старта.
func errors(template_ids: PackedStringArray, type_ids: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for key in ["start", "respawn"]:
		if not _clusters.has(String(region.get(key, ""))):
			result.append("%s: нет кластера «%s»" % [key, region.get(key, "")])
	var cells := {}
	for id: String in _clusters:
		var c: Dictionary = _clusters[id]
		for key in CLUSTER_KEYS:
			if not c.has(key):
				result.append("%s: нет ключа «%s»" % [id, key])
		if c.has("hex"):
			var cell := _to_hex(c["hex"])
			if cells.has(cell):
				result.append("%s: сота %s занята кластером %s" % [id, cell, cells[cell]])
			cells[cell] = id
		if not template_ids.has(String(c.get("template", ""))):
			result.append("%s: нет шаблона «%s»" % [id, c.get("template", "")])
		if not type_ids.has(String(c.get("type", ""))):
			result.append("%s: неизвестный тип «%s»" % [id, c.get("type", "")])
	var start := String(region.get("start", ""))
	if _clusters.has(start):
		var reached := {start: true}
		var queue: Array = [start]
		while not queue.is_empty():
			for other: String in _clusters[queue.pop_front()]["neighbors"]:
				if not reached.has(other):
					reached[other] = true
					queue.append(other)
		for id: String in _clusters:
			if not reached.has(id):
				result.append("%s: не дойти от старта" % id)
	return result


## Направление от кластера к соседу (единичный вектор; x — восток, y — юг = ось z сцены): нормаль
## общей стороны. Для несоседей — направление между центрами сот.
func direction(from_id: String, to_id: String) -> Vector2:
	var s := side(from_id, to_id)
	if s >= 0:
		return HexGrid.side_normal(s)
	return (HexGrid.to_plane(hex(to_id)) - HexGrid.to_plane(hex(from_id))).normalized()


## Точка выхода к соседу в шестиугольнике кластера (size — расстояние между противоположными
## сторонами): середина общей стороны, на inset внутрь (x, z в метрах от центра).
func exit_point(from_id: String, to_id: String, size: float, inset: float) -> Vector2:
	return direction(from_id, to_id) * (size / 2.0 - inset)


static func _to_hex(value: Variant) -> Vector2i:
	var a: Array = value
	return Vector2i(int(a[0]), int(a[1]))
