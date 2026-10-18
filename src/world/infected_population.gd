extends Node3D
## Заражённые текущего кластера: появляются из абстрактной популяции (WorldSim, PopulationModel)
## после запекания навигации, добавляются, когда люди обращаются, убираются при перезагрузке.
## Состояние сцены — секция infected снимка кластера (живые твари и трупы). В снимке, оставленном
## при переходе, живых нет — при возвращении твари собираются заново из абстрактных чисел.

const InfectedScript := preload("res://src/actors/infected.gd")
const InfectedCorpseScript := preload("res://src/actors/infected_corpse.gd")

## Новые твари появляются не ближе этого к герою — за пределами видимости.
const SPAWN_AWAY := 22.0

var area: Node  # cluster_area.gd

var _corpses: Node3D
## Отложенная материализация до готовности навигации: {"agents": {id: count}, "seed": int}.
var _pending: Dictionary = {}
var _rng := RandomNumberGenerator.new()


## Мешок, брошенный заранее (Нюх на мешок), для трупа, который сейчас появится: {"at", "loot"}.
var _prerolled: Dictionary = {}


func _ready() -> void:
	_corpses = Node3D.new()
	_corpses.name = "Corpses"
	add_child(_corpses)
	WorldSim.register("infected", self)
	EventBus.infected_killed.connect(_on_killed)
	EventBus.sack_prerolled.connect(func(at: Vector3, loot: Dictionary) -> void: _prerolled = {"at": at, "loot": loot})
	if not area.is_navigation_ready:
		area.navigation_ready.connect(_on_navigation_ready, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	WorldSim.unregister("infected")


## Разложить тварей по кластеру: agents — {"slowpoke": 12, ...} из PopulationModel.agents().
func materialize(agents: Dictionary, seed_value: int) -> void:
	if not area.is_navigation_ready:
		_pending = {"agents": agents, "seed": seed_value}
		return
	_rng.seed = seed_value
	var hero := _hero_position()
	for id: String in agents:
		for i in int(agents[id]):
			spawn(id, Content.enemy_db().roll_level(id, _rng), area.spawn_point(_rng, hero, SPAWN_AWAY))


## Люди обратились, пока герой на кластере: новые медляки подальше от него.
func spawn_turned(count: int) -> void:
	if count <= 0:
		return
	if not area.is_navigation_ready:
		var agents: Dictionary = _pending.get("agents", {})
		agents["slowpoke"] = int(agents.get("slowpoke", 0)) + count
		_pending = {"agents": agents, "seed": int(_pending.get("seed", randi()))}
		return
	_rng.randomize()
	for i in count:
		spawn("slowpoke", Content.enemy_db().roll_level("slowpoke", _rng), area.spawn_point(_rng, _hero_position(), SPAWN_AWAY))


func spawn(id: String, level: int, at: Vector3) -> Node3D:
	var infected: CharacterBody3D = InfectedScript.new()
	infected.enemy_id = id
	infected.level = level
	infected.home = at
	infected.position = at + Vector3.UP * 0.1
	infected.rotation.y = randf() * TAU
	add_child(infected)
	return infected


## Перезагрузка кластера: живые и трупы исчезают.
func clear_all() -> void:
	_pending = {}
	for infected in _living():
		remove_child(infected)
		infected.queue_free()
	for corpse in _corpses.get_children():
		_corpses.remove_child(corpse)
		corpse.queue_free()


func living_count() -> int:
	return _living().size()


func _on_navigation_ready() -> void:
	if not _pending.is_empty():
		var pending := _pending
		_pending = {}
		materialize(pending["agents"], int(pending["seed"]))


func _on_killed(id: String, level: int, at: Vector3) -> void:
	var corpse: Node3D = InfectedCorpseScript.new()
	corpse.enemy_id = id
	corpse.level = level
	corpse.position = Vector3(at.x, 0.0, at.z)
	corpse.rotation.y = randf() * TAU
	if not _prerolled.is_empty() and Vector3(_prerolled["at"]).distance_to(at) < 0.01:
		corpse.pre_loot = _prerolled["loot"]
		corpse.has_pre_loot = true
	_prerolled = {}
	_corpses.add_child(corpse)


func _living() -> Array:
	return get_children().filter(func(n: Node) -> bool: return n != _corpses and not n.is_queued_for_deletion())


func _hero_position() -> Vector3:
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	return hero.global_position if hero else Vector3.ZERO


func to_dict() -> Dictionary:
	var list: Array = []
	for infected in _living():
		list.append(infected.to_dict())
	var corpses: Array = []
	for corpse in _corpses.get_children():
		corpses.append(corpse.to_dict())
	return {"infected": list, "corpses": corpses}


## Есть "infected" — живые восстанавливаются как были (загрузка сохранения); нет — только трупы.
func load_dict(data: Dictionary) -> void:
	for corpse in _corpses.get_children():
		_corpses.remove_child(corpse)
		corpse.queue_free()
	for entry: Dictionary in data.get("corpses", []):
		var corpse: Node3D = InfectedCorpseScript.new()
		corpse.load_dict(entry)
		_corpses.add_child(corpse)
	if not data.has("infected"):
		return
	_pending = {}
	for infected in _living():
		remove_child(infected)
		infected.queue_free()
	for entry: Dictionary in data["infected"]:
		var infected: CharacterBody3D = InfectedScript.new()
		infected.load_dict(entry)
		add_child(infected)
