extends StaticBody3D
## Дверь. Закрытая — физическая преграда. Проход для навигации — NavigationLink3D сквозь проём:
## у закрытой двери ссылка есть только на слое «двери» (им пользуются твари, умеющие открывать),
## у открытой — и на обычном слое. Так медляки не находят путь через закрытую дверь (07, «ИИ»).

const LAYER_WALK := 1
const LAYER_DOORS := 2

var width: float = 1.4
var height: float = 2.2
var is_open := false

var _shape: CollisionShape3D
var _leaf: Node3D
var _link: NavigationLink3D


func _ready() -> void:
	add_to_group("doors")
	add_to_group("interactable")
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.12)
	_shape = CollisionShape3D.new()
	_shape.shape = box
	_shape.position = Vector3(0, height / 2.0, 0)
	add_child(_shape)

	# Створка вращается вокруг петли на левом краю.
	_leaf = Node3D.new()
	_leaf.position = Vector3(-width / 2.0, 0, 0)
	add_child(_leaf)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, 0.1)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.27, 0.16)
	material.roughness = 0.9
	var leaf_mesh := MeshInstance3D.new()
	leaf_mesh.mesh = mesh
	leaf_mesh.material_override = material
	leaf_mesh.position = Vector3(width / 2.0, height / 2.0, 0)
	_leaf.add_child(leaf_mesh)

	_link = NavigationLink3D.new()
	_link.bidirectional = true
	_link.start_position = Vector3(0, 0, -1.2)
	_link.end_position = Vector3(0, 0, 1.2)
	add_child(_link)
	_apply()


func open_door() -> void:
	if not is_open:
		is_open = true
		_apply()


func close_door() -> void:
	if is_open:
		is_open = false
		_apply()


## С какой стороны точка: знак по нормали двери (локальная ось Z).
func side_of(point: Vector3) -> float:
	return signf(to_local(point).z)


func interact_text() -> String:
	return Content.ui("interact_door_close" if is_open else "interact_door_open")


func interact(_hero: Node3D) -> void:
	if is_open:
		close_door()
	else:
		open_door()


func _apply() -> void:
	_shape.disabled = is_open
	_leaf.rotation_degrees.y = 95.0 if is_open else 0.0
	_link.navigation_layers = (LAYER_WALK | LAYER_DOORS) if is_open else LAYER_DOORS
