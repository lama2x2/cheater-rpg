extends Node3D
## Предметы, лежащие в мире: появляются, подбираются на E, выбрасываются из инвентаря.
## Состояние сохраняется (секция world_items). Позже их будет сбрасывать перезагрузка кластера.

const ItemPickupScript := preload("res://src/world/item_pickup.gd")


func _ready() -> void:
	add_to_group("world_items")
	SaveService.register("world_items", self)


func _exit_tree() -> void:
	SaveService.unregister("world_items")


func spawn(id: String, count: int, at: Vector3) -> Node3D:
	var pickup: Node3D = ItemPickupScript.new()
	pickup.item_id = id
	pickup.count = count
	pickup.position = at
	add_child(pickup)
	return pickup


## Выбросить рядом с героем: небольшой случайный разброс, чтобы стопки не слипались.
func drop_near(id: String, count: int, at: Vector3) -> void:
	var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	spawn(id, count, Vector3(at.x, 0.0, at.z) + offset)


func to_dict() -> Dictionary:
	var list: Array = []
	for pickup in get_children():
		if pickup.is_queued_for_deletion():
			continue
		list.append({"id": pickup.item_id, "count": pickup.count, "position": [pickup.position.x, pickup.position.y, pickup.position.z]})
	return {"items": list}


func load_dict(data: Dictionary) -> void:
	for pickup in get_children():
		remove_child(pickup)
		pickup.queue_free()
	for entry: Dictionary in data["items"]:
		var at: Array = entry["position"]
		spawn(String(entry["id"]), int(entry["count"]), Vector3(float(at[0]), float(at[1]), float(at[2])))
