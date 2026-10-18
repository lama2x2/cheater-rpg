extends Node3D
## Труп героя на месте смерти. На нём остаётся рюкзак (и позже оружие, одежда) — пока кластер
## не перезагрузится. Содержимое заполняет инвентарь (задача 4), забирают на E.
## Спецификация: docs/spec/04_death_lives.md, 4.2.

var life: int = 0
## Что осталось на трупе: {"backpack": [...]} — формат задаёт инвентарь.
var contents: Dictionary = {}


func _ready() -> void:
	add_to_group("corpses")
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


func to_dict() -> Dictionary:
	return {"life": life, "position": [position.x, position.y, position.z], "yaw": rotation.y, "contents": contents}


func load_dict(data: Dictionary) -> void:
	life = int(data["life"])
	var at: Array = data["position"]
	position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	rotation.y = float(data["yaw"])
	contents = data["contents"]


func _mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance
