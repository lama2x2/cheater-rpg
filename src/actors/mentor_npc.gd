extends Node3D
## Наставник на стартовом кластере (01 «первые 2 часа», задача 17): бывалый иммунный-архетип у
## плиты респа. E — разговор (src/ui/mentor_window.gd): подарки, «загляни ему в затылок», крестины.

## Для отладки --talk=mentor (как у неписей стаба).
var npc_id := "mentor"


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("mentor")
	var model := CharacterModel.make("npc_male")  # задача 19
	model.set_tint_mult(Color(0.85, 0.82, 0.7))
	add_child(model)
	var label := Label3D.new()
	label.text = "%s\n%s" % [Content.ui("mentor_name"), Content.ui("mentor_role")]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.02
	label.outline_size = 10
	label.modulate = Color(0.9, 0.95, 0.85)
	label.position = Vector3(0, 2.6, 0)
	add_child(label)


func interact_text() -> String:
	return Content.ui("interact_mentor", {"name": Content.ui("mentor_name")})


func interact(_hero: Node3D) -> void:
	var window := get_tree().get_first_node_in_group("mentor_window")
	if window:
		window.open(self)


func gaze_info() -> Dictionary:
	return {"kind": "npc", "category": "immune", "name": Content.ui("mentor_name"), "role": Content.ui("mentor_role"),
		"stealth": 5.0, "level": 38, "humanity": 700, "equipment": ["shotgun", "axe"]}
