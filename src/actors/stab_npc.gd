extends Node3D
## Непись стаба (торговец, знахарка, бармен) или доска заданий: заглушка-капсула с именем над
## головой, E — окно услуг (src/ui/stab_window.gd). Данные — data/stab.json, имена и реплики —
## npc в data/text/ru.json. Группа "interactable".

var npc_id: String = ""
var kind: String = ""
var color := Color(0.6, 0.6, 0.6)
## Что видно Пристальным взглядом (data/stab.json → npcs[].gaze).
var gaze: Dictionary = {}


func _ready() -> void:
	add_to_group("interactable")
	if kind == "board":
		_build_board()
	else:
		_build_body()
	var label := Label3D.new()
	label.text = info()["name"] if kind == "board" else "%s\n%s" % [info()["name"], info()["role"]]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.02
	label.outline_size = 10
	label.modulate = Color(0.9, 0.95, 0.85)
	label.position = Vector3(0, 2.6, 0)
	add_child(label)


func info() -> Dictionary:
	return Content.texts()["npc"][npc_id]


## Пристальный взгляд (12.3): описание цели для GazeRules.card.
func gaze_info() -> Dictionary:
	if kind == "board":
		return {"kind": "item", "category": "thing", "name": info()["name"], "role": info()["role"]}
	var subject := {"kind": "npc", "category": "immune", "name": info()["name"], "role": info()["role"],
		"stealth": float(gaze.get("stealth", 0.0))}
	for key in ["level", "humanity", "equipment", "morok"]:
		if gaze.has(key):
			subject[key] = gaze[key]
	if subject.has("level"):
		subject["level"] = int(subject["level"])
	return subject


func interact_text() -> String:
	if kind == "board":
		return Content.ui("interact_board")
	return Content.ui("interact_npc", {"name": info()["name"], "role": info()["role"]})


func interact(_hero: Node3D) -> void:
	var window := get_tree().get_first_node_in_group("stab_window")
	if window:
		window.open(self)


func _build_body() -> void:
	# Модель непися (задача 19): знахарка — женская, остальные — мужская, оттенок — цвет из стаба.
	var model := CharacterModel.make("npc_female" if npc_id == "healer" else "npc_male")
	model.set_tint_mult(color.lightened(0.45))
	add_child(model)
	# Прилавок перед неписем.
	var counter := BoxMesh.new()
	counter.size = Vector3(2.2, 1.0, 0.5)
	add_child(_mesh(counter, Vector3(0, 0.5, -0.7), Color(0.42, 0.32, 0.22)))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.0, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 0.5, -0.7)
	body.add_child(shape)
	add_child(body)


func _build_board() -> void:
	var board := BoxMesh.new()
	board.size = Vector3(2.0, 1.3, 0.12)
	add_child(_mesh(board, Vector3(0, 1.4, 0), Color(0.5, 0.4, 0.28)))
	for x in [-0.8, 0.8]:
		var post := BoxMesh.new()
		post.size = Vector3(0.12, 2.0, 0.12)
		add_child(_mesh(post, Vector3(x, 1.0, 0), Color(0.35, 0.27, 0.18)))
	var paper := BoxMesh.new()
	paper.size = Vector3(0.35, 0.45, 0.02)
	for i in 3:
		add_child(_mesh(paper, Vector3(-0.55 + i * 0.55, 1.4, -0.08), Color(0.92, 0.9, 0.82)))


func _mesh(mesh: Mesh, at: Vector3, c: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = c
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance
