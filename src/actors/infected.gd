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
## Удача героя (D-76): тварь оступилась — стоит; «отвернулась» — не видит героя; повтор броска.
var _stumble_left := 0.0
var _unnoticed_left := 0.0
var _unnoticed_retry := 0.0
## Мешок, брошенный заранее (Нюх на мешок): выпадет при вскрытии трупа. sniffed — герой уже
## «принюхивался» (бросок показа — один раз на тварь).
var sack_loot: Dictionary = {}
var sack_rolled := false
var sniffed := false
var _glow: Label3D
## Капкан (задача 18): стоит на месте, пока не вырвется. Яд: урон мимо брони и слабые пластины.
var _trapped_left := 0.0
var _poison_left := 0.0
var _poison_dps := 0.0
var _weak_armor_left := 0.0


func _ready() -> void:
	add_to_group("infected")
	_data = Content.enemy_db().enemy(enemy_id)
	if hp <= 0.0:
		hp = Content.enemy_db().max_hp(enemy_id, level)
	if brain == null:
		var hunger := float(_data["ai"].get("start_hunger", _rng.randf_range(0.0, 0.4)))
		brain = InfectedBrain.new(_data["ai"], float(_data["attack"]["range"]), hunger)
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
	_stumble_left = maxf(0.0, _stumble_left - delta)
	_unnoticed_left = maxf(0.0, _unnoticed_left - delta)
	_unnoticed_retry = maxf(0.0, _unnoticed_retry - delta)
	_trapped_left = maxf(0.0, _trapped_left - delta)
	_weak_armor_left = maxf(0.0, _weak_armor_left - delta)
	if _poison_left > 0.0:
		_poison_left -= delta
		if take_damage(_poison_dps * delta):
			return
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
	if is_queued_for_deletion():
		return true
	hp -= amount
	if from != Vector3.INF and not brain.is_alert():
		_pending_noise = {"position": from, "loudness": 1.0}
	if hp <= 0.0:
		if sack_rolled:
			EventBus.sack_prerolled.emit(global_position, sack_loot)
		EventBus.infected_killed.emit(enemy_id, level, global_position)
		queue_free()
		return true
	return false


## Пугач: бежать прочь от точки from на seconds секунд (на 25 м в сторону от неё).
func scare(from: Vector3, seconds: float) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var point := global_position + away.normalized() * 25.0
	brain.flee(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point), seconds)
	_lunge_left = 0.0
	_on_state_changed()


## Бросить содержимое мешка заранее (Нюх на мешок) — с Удачей героя на этот момент.
func preroll_sack() -> Dictionary:
	if not sack_rolled:
		sack_rolled = true
		if bool(_data.get("spore_sack", false)):
			var frac := LootTable.level_fraction(level, _data["level"])
			sack_loot = Content.loot().roll(String(_data["loot"]), frac, PlayerState.effective("luck"), _rng)
	return sack_loot


## Слабое свечение «ценный мешок» (Нюх на мешок); bright — жемчуг ярче.
func set_trophy_glow(on: bool, bright: bool = false) -> void:
	if _glow == null:
		if not on:
			return
		_glow = Label3D.new()
		_glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_glow.no_depth_test = true
		_glow.pixel_size = 0.012
		_glow.outline_size = 6
		_glow.text = "✧"
		_glow.add_to_group("skill_marks")  # подсвеченное умением видно и вне взгляда героя
		_glow.position = Vector3.UP * (float(_data["body"]["height"]) + 0.3)
		add_child(_glow)
	_glow.visible = on
	_glow.modulate = Color(1.0, 1.0, 1.0, 0.95) if bright else Color(1.0, 0.85, 0.35, 0.7)


## Пристальный взгляд (12.3): описание цели для GazeRules.card.
func gaze_info() -> Dictionary:
	var traits: PackedStringArray = []
	if (_data["move"] as Dictionary).has("lunge"):
		traits.append("trait_lunge")
	if bool(_data["can_open_doors"]):
		traits.append("trait_doors")
	if bool(_data.get("spore_sack", false)):
		traits.append("trait_sack")
	var armor := {}
	for zone: String in _data["armor"]:
		if float(_data["armor"][zone]) > 0.0:
			armor[zone] = float(_data["armor"][zone])
	return {
		"kind": "infected", "category": "object", "name": Content.enemy_name(enemy_id),
		"stealth": float(_data["senses"].get("stealth", 0.0)), "level": level,
		"level_range": [int(_data["level"][0]), int(_data["level"][1])], "threat": String(_data["threat"]),
		"health": hp / maxf(Content.enemy_db().max_hp(enemy_id, level), 1.0), "state": brain.state,
		"armor": armor, "traits": Array(traits), "hunger": brain.hunger,
	}


## Для чуйки героя (17.2): Скрытность, уровень, гонится ли, гашение чуйки (элиты).
func sense_info() -> Dictionary:
	return {"stealth": float(_data["senses"].get("stealth", 0.0)), "level": level,
		"alert": brain.is_alert(), "hush": float(_data["senses"].get("sense_hush", 0.0))}


## Броня сейчас: под ядом пластины слабее (EliteRules.poisoned_armor).
func armor_now() -> Dictionary:
	return Content.elite_rules().poisoned_armor(_data.get("armor", {}), _weak_armor_left > 0.0)


## Капкан: стоять seconds секунд, урон мимо брони. Возвращает true, если тварь умерла.
func trap(seconds: float, damage: float) -> bool:
	_trapped_left = maxf(_trapped_left, seconds)
	_lunge_left = 0.0
	_mark.text = "#"
	_mark.modulate = Color(0.95, 0.6, 0.3)
	return take_damage(damage)


## Съела отравленную приманку: урон dps × seconds и пластины слабее на armor_s.
func poison(seconds: float, dps: float, armor_s: float) -> void:
	_poison_left = maxf(_poison_left, seconds)
	_poison_dps = dps
	_weak_armor_left = maxf(_weak_armor_left, armor_s)


func is_trapped() -> bool:
	return _trapped_left > 0.0


func is_poisoned() -> bool:
	return _poison_left > 0.0


## Тварь не гонится за героем и не атакует — для умения «Из тени».
func is_unaware() -> bool:
	return not brain.is_alert()


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
		if _can_see(hero, distance) and not _luck_unnoticed():
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


## Удача героя: тварь, ещё не поднявшая тревогу, заметив его, «отворачивается» на unnoticed_s.
## Бросок — не чаще unnoticed_retry_s, иначе пять проверок в секунду сложились бы в гарантию.
func _luck_unnoticed() -> bool:
	if _unnoticed_left > 0.0:
		return true
	if brain.is_alert() or _unnoticed_retry > 0.0:
		return false
	var luck: Dictionary = Content.luck_model().config()
	_unnoticed_retry = float(luck["unnoticed_retry_s"])
	if PlayerState.lucky("unnoticed", global_position + Vector3.UP * 2.4):
		_unnoticed_left = float(luck["unnoticed_s"])
		return true
	return false


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
		InfectedBrain.FLEE:
			speed = float(move["run"])
		InfectedBrain.EAT:
			speed = float(move["walk"])
			if bool(_senses.get("at_target", false)):
				speed = 0.0
				if _food and is_instance_valid(_food):
					_food.eat(float(_data["ai"]["eat_per_s"]) * delta * 100.0)
					if _food.has_method("poison_for") and not is_poisoned():
						_food.poison_for(self)

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

	if _stumble_left > 0.0 or _trapped_left > 0.0:
		direction = Vector3.ZERO
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
	if bool(_data["ai"].get("lurk", false)):
		brain.target_position = home  # засада: ждёт у своего места, не бродит
		return
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
	if not move.has("lunge") or _lunge_cooldown > 0.0 or _trapped_left > 0.0 or not bool(_senses.get("sees_player", false)):
		return
	var lunge: Dictionary = move["lunge"]
	var distance := float(_senses["player_distance"])
	if distance < float(lunge["range"][0]) or distance > float(lunge["range"][1]):
		return
	if PlayerState.lucky("enemy_stumble", global_position + Vector3.UP * 2.4):
		_lunge_cooldown = float(lunge["cooldown"])
		_stumble_left = float(Content.luck_model().config()["stumble_s"])
		return
	PlayerState.danger_warn(global_position)
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
	if PlayerState.lucky("enemy_miss"):
		return
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
		InfectedBrain.FLEE:
			_mark.text = "≈"
			_mark.modulate = Color(0.6, 0.8, 1.0)
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
