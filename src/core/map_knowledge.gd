class_name MapKnowledge
extends RefCounted
## Знание карты (12.6, D-72): что герой знает о регионе и кластерах. Сота открывается посещением
## (или купленной/найденной картой); постройки внутри — когда увидены своими глазами или целиком
## с карты; отметки игрока — на кластере и на соте региона. Чистый класс без Node; хранится в
## WorldSim (раздел knowledge сейва). Раскладка кластера детерминирована (ClusterLayout), поэтому
## знание постройки по её номеру переживает перезагрузку кластера.

## Как сота видна на карте региона.
const UNKNOWN := "unknown"
## Сосед посещённой: название и тип известны по табличке выхода, раскладки нет.
const HEARD := "heard"
## Своя карта (купил, нашёл), но ещё не был.
const MAPPED := "mapped"
const VISITED := "visited"

## {id: {"visited": bool, "full": bool, "seen": {номер постройки: true}, "marks": [[x, z], …]}}.
var _clusters: Dictionary = {}
## Сота, отмеченная игроком на карте региона: {id: true}.
var region_marks: Dictionary = {}


func _cell(id: String) -> Dictionary:
	if not _clusters.has(id):
		_clusters[id] = {"visited": false, "full": false, "seen": {}, "marks": []}
	return _clusters[id]


## Пришёл на кластер. true — впервые.
func visit(id: String) -> bool:
	var cell := _cell(id)
	var first := not bool(cell["visited"])
	cell["visited"] = true
	return first


func is_visited(id: String) -> bool:
	return bool(_clusters.get(id, {}).get("visited", false))


## Карта кластера целиком (картограф, находка). true — что-то новое.
func reveal(id: String) -> bool:
	var cell := _cell(id)
	var fresh := not bool(cell["full"])
	cell["full"] = true
	return fresh


func is_mapped(id: String) -> bool:
	return bool(_clusters.get(id, {}).get("full", false))


## Увидел постройку номер index. true — впервые (и карты кластера у героя ещё не было).
func see_building(id: String, index: int) -> bool:
	var cell := _cell(id)
	if cell["seen"].has(index):
		return false
	cell["seen"][index] = true
	return not bool(cell["full"])


func knows_building(id: String, index: int) -> bool:
	var cell: Dictionary = _clusters.get(id, {})
	return bool(cell.get("full", false)) or (cell.get("seen", {}) as Dictionary).has(index)


func seen_count(id: String) -> int:
	return (_clusters.get(id, {}).get("seen", {}) as Dictionary).size()


## Состояние соты на карте региона: visited, mapped, heard (сосед известной), unknown.
func region_state(region: RegionMap, id: String) -> String:
	if is_visited(id):
		return VISITED
	if is_mapped(id):
		return MAPPED
	for other in region.neighbors(id):
		if is_visited(other):
			return HEARD
	return UNKNOWN


## Отметка игрока на кластере: рядом (в radius м) с существующей — убрать её, иначе поставить.
## Возвращает true, если отметка поставлена.
func toggle_mark(id: String, at: Vector2, radius: float) -> bool:
	var marks: Array = _cell(id)["marks"]
	for i in marks.size():
		var m: Array = marks[i]
		if Vector2(float(m[0]), float(m[1])).distance_to(at) <= radius:
			marks.remove_at(i)
			return false
	marks.append([at.x, at.y])
	return true


func marks(id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for m: Array in _clusters.get(id, {}).get("marks", []):
		result.append(Vector2(float(m[0]), float(m[1])))
	return result


func toggle_region_mark(id: String) -> bool:
	if region_marks.has(id):
		region_marks.erase(id)
		return false
	region_marks[id] = true
	return true


## Кластеры без полной карты — кандидаты для найденной карты и картографа.
func unmapped(ids: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for id in ids:
		if not is_mapped(id):
			result.append(id)
	return result


func to_dict() -> Dictionary:
	var clusters := {}
	for id: String in _clusters:
		var cell: Dictionary = _clusters[id]
		clusters[id] = {"visited": cell["visited"], "full": cell["full"], "seen": (cell["seen"] as Dictionary).keys(),
			"marks": (cell["marks"] as Array).duplicate(true)}
	return {"clusters": clusters, "region_marks": region_marks.keys()}


func load_dict(data: Dictionary) -> void:
	_clusters = {}
	region_marks = {}
	var clusters: Dictionary = data.get("clusters", {})
	for id: String in clusters:
		var saved: Dictionary = clusters[id]
		var seen := {}
		for index in saved.get("seen", []):
			seen[int(index)] = true
		_clusters[id] = {"visited": bool(saved.get("visited", false)), "full": bool(saved.get("full", false)),
			"seen": seen, "marks": (saved.get("marks", []) as Array).duplicate(true)}
	for id in data.get("region_marks", []):
		region_marks[String(id)] = true
