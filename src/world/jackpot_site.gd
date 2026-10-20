extends Node3D
## Место куша варианта происхождения (16.3, задача 17): броневик, курьер, придавленная элита…
## Заглушка-коробка с подписью до ассетов (19). E — забрать куш; не трогать — куша не будет.

var variant := ""
var scene: Dictionary = {}


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("jackpot_sites")
	var s: Array = scene.get("size", [1.0, 1.0, 1.0])
	var c: Array = scene.get("color", [0.5, 0.5, 0.5])
	var box := BoxMesh.new()
	box.size = Vector3(float(s[0]), float(s[1]), float(s[2]))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.position.y = float(s[1]) / 2.0
	add_child(mesh)
	var label := Label3D.new()
	label.text = Content.ui(String(scene.get("label", "site_generic")))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.018
	label.outline_size = 10
	label.modulate = Color(1.0, 0.85, 0.45)
	label.position = Vector3(0, float(s[1]) + 1.0, 0)
	add_child(label)


func interact_text() -> String:
	return Content.ui("interact_site", {"what": Content.ui(String(scene.get("label", "site_generic")))})


func interact(_hero: Node3D) -> void:
	SystemLog.post("jackpot_" + variant, {}, "special")
	PlayerState.grant_jackpot()
	queue_free()


func gaze_info() -> Dictionary:
	return {"kind": "item", "category": "thing", "name": Content.ui(String(scene.get("label", "site_generic")))}
