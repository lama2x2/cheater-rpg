class_name RegionMap
extends RefCounted
## Регион как граф кластеров: соседи, проверка данных, где на краю кластера стоит выход к соседу.
## Чистый класс без Node. Данные — data/world/region.json (схема 14.8).
## Спецификация: docs/spec/02_world.md («Иерархия», «Регионы и границы»).

const REQUIRED_KEYS: PackedStringArray = ["id", "name", "start", "respawn", "clusters"]
const CLUSTER_KEYS: PackedStringArray = ["id", "code", "name", "type", "template", "map_pos", "neighbors"]

var region: Dictionary
var _clusters: Dictionary = {}


func _init(data: Dictionary) -> void:
	region = data
	for cluster: Dictionary in data.get("clusters", []):
		_clusters[String(cluster.get("id", ""))] = cluster


func ids() -> PackedStringArray:
	return PackedStringArray(_clusters.keys())


func has_cluster(id: String) -> bool:
	return _clusters.has(id)


func cluster(id: String) -> Dictionary:
	assert(_clusters.has(id), "Неизвестный кластер: %s" % id)
	return _clusters[id]


func neighbors(id: String) -> PackedStringArray:
	return PackedStringArray(cluster(id)["neighbors"])


## Ошибки данных: ключи, неизвестные соседи, несимметричные рёбра, шаблоны и типы без описания.
func errors(template_ids: PackedStringArray, type_ids: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for key in ["start", "respawn"]:
		if not _clusters.has(String(region.get(key, ""))):
			result.append("%s: нет кластера «%s»" % [key, region.get(key, "")])
	for id: String in _clusters:
		var c: Dictionary = _clusters[id]
		for key in CLUSTER_KEYS:
			if not c.has(key):
				result.append("%s: нет ключа «%s»" % [id, key])
		if not template_ids.has(String(c.get("template", ""))):
			result.append("%s: нет шаблона «%s»" % [id, c.get("template", "")])
		if not type_ids.has(String(c.get("type", ""))):
			result.append("%s: неизвестный тип «%s»" % [id, c.get("type", "")])
		for other: String in c.get("neighbors", []):
			if not _clusters.has(other):
				result.append("%s: неизвестный сосед «%s»" % [id, other])
			elif not _clusters[other]["neighbors"].has(id):
				result.append("%s → %s: ребро без обратного" % [id, other])
	return result


## Направление на карте от кластера к соседу (единичный вектор; x — восток, y — юг = ось z сцены).
func direction(from_id: String, to_id: String) -> Vector2:
	var a: Array = cluster(from_id)["map_pos"]
	var b: Array = cluster(to_id)["map_pos"]
	return Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])).normalized()


## Точка выхода к соседу внутри квадрата кластера со стороной size: луч от центра в сторону
## соседа до края, минус inset (координаты x, z в метрах от центра).
func exit_point(from_id: String, to_id: String, size: float, inset: float) -> Vector2:
	return edge_point(direction(from_id, to_id), size / 2.0, inset)


static func edge_point(dir: Vector2, half: float, inset: float) -> Vector2:
	var m := maxf(absf(dir.x), absf(dir.y))
	if m <= 0.0:
		return Vector2.ZERO
	return dir / m * (half - inset)
