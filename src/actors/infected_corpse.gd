extends Node3D
## Труп заражённого: лежит, пока кластер не перезагрузится; его едят другие твари (группа edible).
## Споровый мешок вскрывается в задаче 9.

var enemy_id: String = "slowpoke"
var level: int = 0
var food: float = 60.0
var sack_opened := false


func _ready() -> void:
	add_to_group("infected_corpses")
	if food > 0.0:
		add_to_group("edible")
	var data := Content.enemy_db().enemy(enemy_id)
	var body: Dictionary = data["body"]
	var radius := float(body["radius"])
	var height := maxf(float(body["height"]), radius * 2.0)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var c: Array = body["color"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(float(c[0]), float(c[1]), float(c[2])).darkened(0.35)
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.rotation_degrees = Vector3(90, 0, 0)
	instance.position = Vector3(0, radius, 0)
	add_child(instance)


func eat(amount: float) -> void:
	food = maxf(0.0, food - amount)
	if food <= 0.0:
		remove_from_group("edible")


func to_dict() -> Dictionary:
	return {"id": enemy_id, "level": level, "food": food, "sack_opened": sack_opened,
		"position": [position.x, position.y, position.z], "yaw": rotation.y}


func load_dict(data: Dictionary) -> void:
	enemy_id = String(data["id"])
	level = int(data["level"])
	food = float(data["food"])
	sack_opened = bool(data["sack_opened"])
	var at: Array = data["position"]
	position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	rotation.y = float(data["yaw"])
