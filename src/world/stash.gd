extends Node3D
## Тайник: невидим, пока герой не подойдёт на дальность замечания (растёт с Наблюдательностью).
## Найден — прокачка Наблюдательности (3.2) и сообщение. E — забрать всё.

const CHECK_INTERVAL := 0.25

var contents: Array = []  # [["sporan", 6], ...]
var found := false

var _mesh: MeshInstance3D
var _timer := 0.0


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.3, 0.4)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.25, 0.18)
	material.emission_enabled = true
	material.emission = Color(0.5, 0.4, 0.15)
	material.emission_energy_multiplier = 0.3
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.material_override = material
	_mesh.position.y = 0.15
	add_child(_mesh)
	_apply()


func _process(delta: float) -> void:
	if found:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if hero == null or not hero.visible:
		return
	var reveal: Dictionary = Content.test_area()["stash_reveal"]
	var radius := float(reveal["base_radius"]) + float(reveal["per_perception"]) * (PlayerState.effective("perception") - 1.0)
	if Vector2(hero.global_position.x - global_position.x, hero.global_position.z - global_position.z).length() <= radius:
		found = true
		_apply()
		SystemLog.post("stash_found", {}, "special")
		PlayerState.award("stash_found")


func interact_text() -> String:
	return Content.ui("interact_stash" if not contents.is_empty() else "interact_stash_empty")


func interact(_hero: Node3D) -> void:
	if contents.is_empty():
		SystemLog.post("stash_empty")
		return
	var parts: PackedStringArray = []
	for entry: Array in contents:
		parts.append("%s ×%d" % [Content.item_name(entry[0]), int(entry[1])])
		var left: int = PlayerState.inventory.add(String(entry[0]), int(entry[1]))["left"]
		if left > 0:
			EventBus.items_dropped.emit(String(entry[0]), left)
	contents.clear()
	SystemLog.post("stash_looted", {"items": ", ".join(parts)})
	PlayerState.notify_inventory_changed()


func _apply() -> void:
	_mesh.visible = found
	if found and not is_in_group("interactable"):
		add_to_group("interactable")
	elif not found and is_in_group("interactable"):
		remove_from_group("interactable")
