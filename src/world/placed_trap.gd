extends Node3D
## Поставленный героем капкан или отравленная приманка (задача 18). Капкан срабатывает на первую
## тварь рядом: держит и ранит мимо брони. Приманка — еда (группа edible): съевшая тварь отравлена
## (EliteRules: урон ядом и слабые пластины). Числа — data/elite.json.

const CHECK_S := 0.1

var what := "trap"
var food := 0.0
var _left := 0.0
var _used := false


func _ready() -> void:
	add_to_group("placed_traps")
	var cfg := Content.elite_rules().config()
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	if what == "bait":
		food = float(cfg["bait"]["food"])
		add_to_group("edible")
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.3
		mesh.mesh = sphere
		material.albedo_color = Color(0.5, 0.25, 0.3)
	else:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.25
		ring.outer_radius = 0.4
		mesh.mesh = ring
		material.albedo_color = Color(0.45, 0.45, 0.48)
		material.metallic = 0.8
	mesh.material_override = material
	mesh.position.y = 0.08
	add_child(mesh)


func _process(delta: float) -> void:
	if what != "trap" or _used:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = CHECK_S
	var cfg: Dictionary = Content.elite_rules().config()["trap"]
	for node: Node in get_tree().get_nodes_in_group("infected"):
		var target := node as Node3D
		if Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length() <= float(cfg["radius_m"]):
			_used = true
			var elite := bool(Content.enemy_db().enemy(String(target.get("enemy_id"))).get("elite", false))
			SystemLog.post("trap_sprung", {"enemy": Content.enemy_name(String(target.get("enemy_id")))}, "progress")
			EventBus.noise_made.emit("door", global_position, {})
			target.trap(Content.elite_rules().trap_hold(elite), float(cfg["damage"]))
			queue_free()
			return


## Еда для тварей (как труп): кончилась — приманки нет.
func eat(amount: float) -> void:
	food = maxf(0.0, food - amount)
	if food <= 0.0:
		remove_from_group("edible")
		queue_free()


## Тварь начала есть — отравлена (один раз на тварь, см. infected.gd).
func poison_for(target: Node3D) -> void:
	var cfg: Dictionary = Content.elite_rules().config()["bait"]
	target.poison(float(cfg["poison_s"]), float(cfg["dps"]), float(cfg["armor_s"]))
	SystemLog.post("bait_poisoned", {"enemy": Content.enemy_name(String(target.get("enemy_id")))}, "progress")
