extends Node3D
## Приманка элиты (задача 18): раненый на открытом месте стонет и зовёт на помощь. Подойти —
## значит попасть в засаду: элита за домом рядом. Если элита мертва — раненый благодарит
## споранами. Группа "interactable".

var _helped := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("elite_victims")
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.33
	capsule.height = 1.7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.55, 0.45)
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.material_override = material
	body.rotation_degrees = Vector3(0, 0, 90)
	body.position.y = 0.33
	add_child(body)
	var label := Label3D.new()
	label.text = Content.ui("victim_label")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.016
	label.outline_size = 8
	label.modulate = Color(0.95, 0.75, 0.6)
	label.position = Vector3(0, 1.2, 0)
	add_child(label)


func interact_text() -> String:
	return Content.ui("interact_victim")


func interact(hero: Node3D) -> void:
	if _helped:
		return
	var elites := get_tree().get_nodes_in_group("elite")
	if not elites.is_empty():
		SystemLog.post("victim_ambush", {}, "warning")
		for e in elites:
			e.hear(hero.global_position, 1.0)  # засада: элита идёт на героя
		return
	_helped = true
	var reward := int(Content.elite_rules().config()["victim_reward"])
	PlayerState.pick_up("sporan", reward)
	SystemLog.post("victim_thanks", {"n": reward}, "special")
	remove_from_group("interactable")


func gaze_info() -> Dictionary:
	return {"kind": "npc", "category": "immune", "name": Content.ui("victim_label"), "stealth": 0.0, "level": 4,
		"health": 0.15, "humanity": 300}
