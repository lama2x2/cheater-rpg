extends CharacterBody3D
## Заражённый: тело, чувства и движение. Решения принимает InfectedBrain (src/core).
## Заглушка-капсула: размер и цвет по стадии. Над головой — «?» (проверяет), «!» (гонится), «…» (ест).
## Данные — data/enemies/infected.json. Спецификация: docs/spec/07_enemies.md.

const SENSE_INTERVAL := 0.2
const EYE_HEIGHT := 1.5
const AT_TARGET_DISTANCE := 1.0
const DOOR_REACH := 1.8
const WANDER_WAIT := Vector2(2.0, 6.0)
const GRAVITY := 20.0
## Физические слои: 1 — мир, 2 — герой, 3 — заражённые.
const LAYER_WORLD := 1
const LAYER_HERO := 2
const LAYER_INFECTED := 4

var enemy_id: String = "slowpoke"
var level: int = 0
var hp: float = 0.0
var home := Vector3.ZERO

var brain: InfectedBrain
var _data: Dictionary
var _agent: NavigationAgent3D
var _mark: Label3D
var _senses: Dictionary = {}
var _sense_timer := 0.0
var _attack_timer := 0.0
var _lunge_cooldown := 0.0
var _lunge_left := 0.0
var _lunge_direction := Vector3.ZERO
var _wander_wait := 0.0
var _food: Node3D
var _rng := RandomNumberGenerator.new()
var _pending_noise: Dictionary = {}


func _ready() -> void:
	add_to_group("infected")
	_data = Content.enemy_db().enemy(enemy_id)
	if hp <= 0.0:
		hp = Content.enemy_db().max_hp(enemy_id, level)
	if brain == null:
		brain = InfectedBrain.new(_data["ai"], float(_data["attack"]["range"]), _rng.randf_range(0.0, 0.4))
	_rng.randomize()
	_attack_timer = _rng.randf_range(0.0, 0.5)
	collision_layer = LAYER_INFECTED
	collision_mask = LAYER_WORLD | LAYER_HERO | LAYER_INFECTED
	_build_body()

	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.8
	_agent.radius = float(_data["body"]["radius"])
	_agent.navigation_layers = 3 if bool(_data["can_open_doors"]) else 1
	add_child(_agent)


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_lunge_cooldown = maxf(0.0, _lunge_cooldown - delta)
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = SENSE_INTERVAL
		_senses = _sense()
		if bool(_data["can_open_doors"]):
			_open_doors_on_the_way()
	_senses["at_target"] = _reached_target()
	if not _pending_noise.is_empty():
		_senses["noise"] = _pending_noise
	var previous := brain.state
	brain.update(delta, _senses)
	_pending_noise = {}
	_senses.erase("noise")
	if brain.state != previous:
		_on_state_changed()
	_act(delta)


## Шум (задача 7): loudness 0..1 уже с учётом расстояния. Слух твари усиливает или ослабляет.
func hear(position: Vector3, loudness: float) -> void:
	var heard := loudness * float(_data["senses"]["hearing"])
	if heard > float(_pending_noise.get("loudness", 0.0)):
		_pending_noise = {"position": position, "loudness": heard}


## Урон от героя (задача 8 добавит зоны и броню). Возвращает true, если тварь умерла.
func take_damage(amount: float, from: Vector3 = Vector3.INF) -> bool:
	hp -= amount
	if from != Vector3.INF and not brain.is_alert():
		_pending_noise = {"position": from, "loudness": 1.0}
	if hp <= 0.0:
		EventBus.infected_killed.emit(enemy_id, level, global_position)
		queue_free()
		return true
	return false


func to_dict() -> Dictionary:
	return {
		"id": enemy_id, "level": level, "hp": hp, "yaw": rotation.y,
		"position": [global_position.x, global_position.y, global_position.z],
		"home": [home.x, home.y, home.z], "brain": brain.to_dict(),
	}


func load_dict(data: Dictionary) -> void:
	enemy_id = String(data["id"])
	level = int(data["level"])
	hp = float(data["hp"])
	var at: Array = data["position"]
	position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	var h: Array = data["home"]
	home = Vector3(float(h[0]), float(h[1]), float(h[2]))
	rotation.y = float(data["yaw"])
	var e := Content.enemy_db().enemy(enemy_id)
	brain = InfectedBrain.new(e["ai"], float(e["attack"]["range"]))
	brain.load_dict(data["brain"])


func _sense() -> Dictionary:
	var senses := {}
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if hero and hero.visible and not PlayerState.awaiting_respawn:
		var distance := _flat_distance(global_position, hero.global_position)
		if _can_see(hero, distance):
			senses["sees_player"] = true
			senses["player_position"] = hero.global_position
			senses["player_distance"] = distance
	var food := _nearest_food()
	_food = food
	if food:
		senses["food"] = {"position": food.global_position, "distance": _flat_distance(global_position, food.global_position)}
	return senses


func _can_see(hero: Node3D, distance: float) -> bool:
	var s: Dictionary = _data["senses"]
	if distance > float(s["sight"]) * hero.visibility_multiplier():
		return false
	if distance > float(s["notice_close"]):
		var forward := -global_transform.basis.z
		var to_hero := (hero.global_position - global_position)
		to_hero.y = 0.0
		if rad_to_deg(forward.angle_to(to_hero.normalized())) > float(s["fov_deg"]) / 2.0:
			return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * minf(EYE_HEIGHT, float(_data["body"]["height"]) * 0.8),
		hero.global_position + Vector3.UP * 1.2, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _nearest_food() -> Node3D:
	var radius := float(_data["ai"]["smell_food"])
	var best: Node3D = null
	for node: Node3D in get_tree().get_nodes_in_group("edible"):
		if node.food <= 0.0:
			continue
		var distance := _flat_distance(global_position, node.global_position)
		if distance < radius:
			best = node
			radius = distance
	return best


func _act(delta: float) -> void:
	var move: Dictionary = _data["move"]
	var speed := 0.0
	match brain.state:
		InfectedBrain.WANDER:
			_wander(delta)
			speed = float(move["walk"])
		InfectedBrain.INVESTIGATE:
			speed = lerpf(float(move["walk"]), float(move["run"]), 0.5)
		InfectedBrain.CHASE:
			speed = float(move["run"])
			_try_lunge()
		InfectedBrain.ATTACK:
			_attack()
		InfectedBrain.EAT:
			speed = float(move["walk"])
			if bool(_senses.get("at_target", false)):
				speed = 0.0
				if _food and is_instance_valid(_food):
					_food.eat(float(_data["ai"]["eat_per_s"]) * delta * 100.0)

	var direction := Vector3.ZERO
	if _lunge_left > 0.0:
		_lunge_left -= delta
		direction = _lunge_direction
		speed = float(move["lunge"]["speed"])
	elif speed > 0.0 and not bool(_senses.get("at_target", false)):
		if _agent.target_position.distance_to(brain.target_position) > 0.5:
			_agent.target_position = brain.target_position
		if not _agent.is_navigation_finished():
			direction = _agent.get_next_path_position() - global_position
			direction.y = 0.0
			direction = direction.normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	var face := direction
	if brain.state == InfectedBrain.ATTACK:
		face = brain.target_position - global_position
	face.y = 0.0
	if face.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), clampf(10.0 * delta, 0.0, 1.0))


## Дошёл до цели — или ближе подойти нельзя (цель за закрытой дверью, внутри препятствия).
func _reached_target() -> bool:
	if _flat_distance(global_position, brain.target_position) <= AT_TARGET_DISTANCE:
		return true
	return _agent.is_navigation_finished() and _agent.target_position.distance_to(brain.target_position) < 0.5 \
		and _lunge_left <= 0.0


func _wander(delta: float) -> void:
	if not bool(_senses.get("at_target", false)):
		return
	_wander_wait -= delta
	if _wander_wait > 0.0:
		return
	_wander_wait = _rng.randf_range(WANDER_WAIT.x, WANDER_WAIT.y)
	var r := float(_data["ai"]["wander_radius"])
	var angle := _rng.randf() * TAU
	var point := home + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(r * 0.3, r)
	brain.target_position = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


## Рывок прыгунов и бегунов: прямо на героя, если он на дистанции рывка и виден.
func _try_lunge() -> void:
	var move: Dictionary = _data["move"]
	if not move.has("lunge") or _lunge_cooldown > 0.0 or not bool(_senses.get("sees_player", false)):
		return
	var lunge: Dictionary = move["lunge"]
	var distance := float(_senses["player_distance"])
	if distance < float(lunge["range"][0]) or distance > float(lunge["range"][1]):
		return
	_lunge_direction = brain.target_position - global_position
	_lunge_direction.y = 0.0
	_lunge_direction = _lunge_direction.normalized()
	_lunge_left = float(lunge["duration"])
	_lunge_cooldown = float(lunge["cooldown"])


func _attack() -> void:
	if _attack_timer > 0.0 or PlayerState.awaiting_respawn:
		return
	var attack: Dictionary = _data["attack"]
	_attack_timer = float(attack["cooldown"])
	PlayerState.hurt(float(attack["damage"]), enemy_id, float(attack.get("bleed_chance", 0.0)))


## Открыть закрытую дверь, если цель — по другую сторону, а дверь рядом.
func _open_doors_on_the_way() -> void:
	if brain.state == InfectedBrain.WANDER:
		return
	for door: Node3D in get_tree().get_nodes_in_group("doors"):
		if door.is_open or _flat_distance(global_position, door.global_position) > DOOR_REACH:
			continue
		if door.side_of(global_position) != door.side_of(brain.target_position):
			door.open_door()
			EventBus.noise_made.emit("door", door.global_position, {})


func _on_state_changed() -> void:
	match brain.state:
		InfectedBrain.INVESTIGATE:
			_mark.text = "?"
			_mark.modulate = Color(1.0, 0.85, 0.3)
		InfectedBrain.CHASE, InfectedBrain.ATTACK:
			_mark.text = "!"
			_mark.modulate = Color(1.0, 0.25, 0.2)
		InfectedBrain.EAT:
			_mark.text = "…"
			_mark.modulate = Color(0.8, 0.8, 0.8)
		_:
			_mark.text = ""


func _build_body() -> void:
	var body: Dictionary = _data["body"]
	var radius := float(body["radius"])
	var height := maxf(float(body["height"]), radius * 2.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = height / 2.0
	add_child(shape)

	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var c: Array = body["color"]
	add_child(_mesh(mesh, Vector3(0, height / 2.0, 0), Color(float(c[0]), float(c[1]), float(c[2]))))
	var eyes := BoxMesh.new()
	eyes.size = Vector3(radius * 0.9, 0.08, 0.1)
	add_child(_mesh(eyes, Vector3(0, height * 0.82, -radius * 0.95), Color(0.75, 0.1, 0.08)))

	_mark = Label3D.new()
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.position = Vector3(0, height + 0.5, 0)
	_mark.pixel_size = 0.02
	_mark.outline_size = 10
	_mark.no_depth_test = true
	add_child(_mark)
	_on_state_changed()


func _mesh(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
