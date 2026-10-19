extends Node3D
## Предмет на земле. Взаимодействие (группа "interactable"): interact_text() и interact().
## Трофеи — маленькие светящиеся шарики, остальное — коробочки.

var item_id: String = ""
var count: int = 1


func _ready() -> void:
	add_to_group("interactable")
	var trophy := Content.item_db().category(item_id) == "trophy"
	var mesh: Mesh
	var material := StandardMaterial3D.new()
	material.roughness = 0.6
	if trophy:
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		mesh = sphere
		material.albedo_color = Color(0.9, 0.75, 0.3)
		material.emission_enabled = true
		material.emission = Color(0.9, 0.7, 0.2)
		material.emission_energy_multiplier = 1.2
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.25, 0.35)
		mesh = box
		material.albedo_color = Color(0.3, 0.45, 0.6)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = 0.15
	add_child(instance)


## Пристальный взгляд (12.3): предмет — название, количество, вес, цена.
func gaze_info() -> Dictionary:
	var db := Content.item_db()
	return {"kind": "item", "category": "thing", "name": Content.item_name(item_id), "count": count,
		"weight": db.weight_g(item_id) * count, "price": int(db.item(item_id).get("base_price", 0))}


func interact_text() -> String:
	return Content.ui("interact_pickup", {"item": Content.item_name(item_id), "count": count})


func interact(_hero: Node3D) -> void:
	var left := PlayerState.pick_up(item_id, count)
	if left <= 0:
		queue_free()
	else:
		count = left
