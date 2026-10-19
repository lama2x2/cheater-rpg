extends Node3D
## Выход к соседнему кластеру на краю: тёмная трещина в земле и табличка «→ Деревня».
## E — переход (WorldSim.travel, короткая загрузка — D-07). Группа "interactable".

const LENGTH := 8.0

var target: String = ""


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("cluster_exits")
	var crack := BoxMesh.new()
	crack.size = Vector3(LENGTH, 0.04, 0.5)  # вдоль локальной X — вдоль стороны соты (cluster_area)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.08)
	material.emission_enabled = true
	material.emission = Color(0.35, 0.3, 0.2)
	material.emission_energy_multiplier = 0.25
	var mesh := MeshInstance3D.new()
	mesh.mesh = crack
	mesh.material_override = material
	mesh.position.y = 0.02
	add_child(mesh)

	var label := Label3D.new()
	label.text = "→ " + WorldSim.cluster_name(target)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.03
	label.outline_size = 12
	label.modulate = Color(0.95, 0.9, 0.7)
	label.position = Vector3(0, 2.2, 0)
	add_child(label)


func interact_text() -> String:
	return Content.ui("interact_exit", {
		"name": WorldSim.cluster_name(target), "type": Content.ui("cluster_type_" + WorldSim.cluster_type_id(target)),
	})


func interact(_hero: Node3D) -> void:
	WorldSim.travel(target)
