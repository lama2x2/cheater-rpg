extends Node
## Знание карты на сцене кластера (12.6): отмечает посещение и постройки, которые герой увидел
## (в конусе взгляда и не за стеной — те же правила, что у зрения, 17). Знание — WorldSim.knowledge.

const LAYER_WORLD := 1
const EYE := Vector3(0, 1.5, 0)

var area: Node3D
var hero: Node3D
var _left := 0.0
var _interval := 0.4


func _ready() -> void:
	add_to_group("map_watcher")
	_interval = float(Content.map_config()["seen_check_s"])
	if WorldSim.knowledge.visit(WorldSim.current):
		EventBus.map_changed.emit()
		if WorldSim.current != String(WorldSim.region.region["start"]):
			SystemLog.post("map_cluster_added", {"name": WorldSim.cluster_name()}, "info")


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or area == null or hero == null or not hero.visible:
		return
	_left = _interval
	var vision := get_tree().get_first_node_in_group("hero_vision")
	if vision == null:
		return
	var buildings: Array = area.layout["buildings"]
	var space := hero.get_world_3d().direct_space_state
	var changed := false
	var me := Vector2(hero.global_position.x, hero.global_position.z)
	for i in buildings.size():
		if WorldSim.knowledge.knows_building(WorldSim.current, i):
			continue
		var b: Dictionary = buildings[i]
		var rect := Rect2(b["center"] - b["size"] / 2.0, b["size"])
		var near := Vector2(clampf(me.x, rect.position.x, rect.end.x), clampf(me.y, rect.position.y, rect.end.y))
		if near.distance_to(me) > 0.01:
			near = near.move_toward(me, 0.4)  # стена — сама препятствие: смотрим на её наружную сторону
		var point := Vector3(near.x, 1.0, near.y)
		if not vision.sees_point(point):
			continue
		var query := PhysicsRayQueryParameters3D.create(hero.global_position + EYE, point, LAYER_WORLD)
		if space.intersect_ray(query).is_empty():
			changed = WorldSim.knowledge.see_building(WorldSim.current, i) or changed
	if changed:
		EventBus.map_changed.emit()
