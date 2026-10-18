extends Node3D
## Труп героя на месте смерти. На нём остаётся рюкзак (и позже оружие, одежда) — пока кластер
## не перезагрузится. Содержимое заполняет инвентарь (задача 4), забирают на E.
## Спецификация: docs/spec/04_death_lives.md, 4.2.

var life: int = 0
## Что осталось на трупе: {"backpack": [...]} — формат задаёт инвентарь.
var contents: Dictionary = {}
## Сколько «еды» осталось для тварей (07, «Голод»). Съеденный труп остаётся с рюкзаком.
var food: float = 100.0


func _ready() -> void:
	add_to_group("corpses")
	add_to_group("interactable")
	add_to_group("edible")
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.8
	var body_mesh := _mesh(body, Color(0.45, 0.4, 0.35))
	body_mesh.rotation_degrees = Vector3(0, 0, 90)
	body_mesh.position = Vector3(0, 0.35, 0)
	add_child(body_mesh)

	var pack := BoxMesh.new()
	pack.size = Vector3(0.5, 0.35, 0.6)
	var pack_mesh := _mesh(pack, Color(0.35, 0.28, 0.15))
	pack_mesh.position = Vector3(0.2, 0.18, 0.55)
	pack_mesh.rotation_degrees = Vector3(0, 25, 0)
	add_child(pack_mesh)

	var label := Label3D.new()
	label.text = "† %d" % life
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 1.2, 0)
	label.pixel_size = 0.01
	label.outline_size = 8
	add_child(label)


func interact_text() -> String:
	if _backpack().is_empty():
		return Content.ui("interact_corpse_empty", {"life": life})
	return Content.ui("interact_corpse", {"life": life})


## Забрать своё: всё из рюкзака трупа — в рюкзак героя, что не влезло — остаётся на трупе.
func interact(_hero: Node3D) -> void:
	var stacks := _backpack()
	if stacks.is_empty():
		SystemLog.post("corpse_empty")
		return
	var inv := PlayerState.inventory
	var remaining: Array = []
	var moved := 0
	for stack: Dictionary in stacks:
		var left := inv.add_backpack(String(stack["id"]), int(stack["count"]))
		moved += int(stack["count"]) - left
		if left > 0:
			remaining.append({"id": stack["id"], "count": left})
	contents["backpack"] = remaining
	SystemLog.post("corpse_looted", {"count": moved})
	if not remaining.is_empty():
		SystemLog.post("too_heavy", {"item": Content.item_name(remaining[0]["id"]), "strength": PlayerState.stats.get_level("strength")}, "warning")
	PlayerState.notify_inventory_changed()


func eat(amount: float) -> void:
	food = maxf(0.0, food - amount)
	if food <= 0.0:
		remove_from_group("edible")


func _backpack() -> Array:
	return contents.get("backpack", [])


func to_dict() -> Dictionary:
	return {"life": life, "position": [position.x, position.y, position.z], "yaw": rotation.y, "contents": contents, "food": food}


func load_dict(data: Dictionary) -> void:
	life = int(data["life"])
	var at: Array = data["position"]
	position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	rotation.y = float(data["yaw"])
	contents = data["contents"]
	food = float(data.get("food", 100.0))


func _mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance
