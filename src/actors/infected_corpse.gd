extends Node3D
## Труп заражённого: лежит, пока кластер не перезагрузится; его едят другие твари (группа edible).
## E — вскрыть споровый мешок (06, 6.1): нужен клинок, время по стадии, шумно.

var enemy_id: String = "slowpoke"
var level: int = 0
var food: float = 60.0
var sack_opened := false


func _ready() -> void:
	add_to_group("infected_corpses")
	if _has_sack() and not sack_opened:
		add_to_group("interactable")
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


func interact_text() -> String:
	var hero := get_tree().get_first_node_in_group("hero")
	if hero and hero.channel.is_active():
		var filled := roundi(hero.channel.progress() * 10.0)
		return "%s  %s" % [hero.channel.label(), "█".repeat(filled) + "░".repeat(10 - filled)]
	if _blade_mult() <= 0.0:
		return Content.ui("interact_sack_no_blade")
	return Content.ui("interact_sack", {"enemy": Content.enemy_name(enemy_id)})


func interact(hero: Node3D) -> void:
	if hero.channel.is_active():
		return
	var mult := _blade_mult()
	if mult <= 0.0:
		SystemLog.post("sack_no_blade", {}, "warning")
		return
	var seconds := float(Content.enemy_db().enemy(enemy_id)["sack_open_s"]) / mult
	hero.channel.start(Content.ui("sack_opening"), seconds, _open_sack, "spore_sack_open")


## Чем быстрее режет лучший клинок в инвентаре (нож ×2, топор ×1,5); 0 — нечем.
func _blade_mult() -> float:
	var best := 0.0
	var weapons := Content.weapon_db()
	for id in weapons.ids():
		if PlayerState.inventory.count_of(id) > 0:
			best = maxf(best, float(weapons.weapon(id).get("sack_open_mult", 0.0)))
	return best


func _open_sack() -> void:
	sack_opened = true
	remove_from_group("interactable")
	var data := Content.enemy_db().enemy(enemy_id)
	var frac := LootTable.level_fraction(level, data["level"])
	var drop := Content.loot().roll(String(data["loot"]), frac, PlayerState.effective("luck"), _rng())
	PlayerState.run.add("sacks_opened")
	if drop.is_empty():
		SystemLog.post("sack_empty", {"enemy": Content.enemy_name(enemy_id)})
		return
	var parts: PackedStringArray = []
	var rare := false
	for id: String in drop:
		parts.append("%s ×%d" % [Content.item_name(id), drop[id]])
		rare = rare or int(Content.item_db().item(id)["base_price"]) >= 40
	SystemLog.post("sack_loot", {"items": ", ".join(parts)}, "special" if rare else "progress")
	for id: String in drop:
		var left: int = PlayerState.inventory.add(id, int(drop[id]))["left"]
		if left > 0:
			EventBus.items_dropped.emit(id, int(left))
	PlayerState.notify_inventory_changed()


func _has_sack() -> bool:
	return bool(Content.enemy_db().enemy(enemy_id).get("spore_sack", false))


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


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
