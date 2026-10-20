extends Node
## Элита-событие (задача 18, 7.1): в Городке после каждой перезагрузки — одна элита в засаде
## за домом, перед домом на открытом месте — приманка: раненый стонет и зовёт. Элита бесшумна,
## гасит чуйку, броня везде: нужен бронебой или хитрость — капкан, отравленная приманка.
## Ставит капканы и приманки героя (EventBus.place_requested). Данные — data/elite.json.

const PlacedTrapScript := preload("res://src/world/placed_trap.gd")
const VictimScript := preload("res://src/world/elite_victim.gd")

var area: Node3D
var population: Node3D
var hero: Node3D
var elite: Node3D


func _ready() -> void:
	add_to_group("elite_event")
	EventBus.place_requested.connect(_place)
	EventBus.infected_killed.connect(_on_killed)
	_setup.call_deferred()


func _setup() -> void:
	var rules := Content.elite_rules()
	if WorldSim.current != String(rules.config()["cluster"]) or area == null:
		return
	if not area.is_navigation_ready:
		await area.navigation_ready
	var state := WorldSim.state()
	if not EliteRules.alive(int(state.get("elite_killed_at", -1)), int(state["reloads"])):
		return
	var buildings: Array = area.layout["buildings"]
	if buildings.is_empty():
		return
	var b: Dictionary = buildings[hash([WorldSim.world_seed, "elite"]) % buildings.size()]
	var points := rules.ambush_points(Rect2(b["center"] - b["size"] / 2.0, b["size"]))
	var bait: Vector2 = points["bait"]
	var lurk: Vector2 = points["lurk"]
	var victim: Node3D = VictimScript.new()
	area.add_child(victim)
	victim.global_position = area.snap(Vector3(bait.x, 0.0, bait.y))
	if population:
		var levels: Array = rules.config()["level"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([WorldSim.world_seed, state["reloads"], "elite"])
		elite = population.spawn("elite", rng.randi_range(int(levels[0]), int(levels[1])), area.snap(Vector3(lurk.x, 0.0, lurk.y)))
		elite.add_to_group("elite")


func _on_killed(id: String, _level: int, _at: Vector3) -> void:
	if id != "elite" or WorldSim.current != String(Content.elite_rules().config()["cluster"]):
		return
	WorldSim.state()["elite_killed_at"] = int(WorldSim.state()["reloads"])
	PlayerState.run.add("elites_killed")
	SystemLog.post("elite_killed", {}, "special")


func _place(what: String) -> void:
	if hero == null:
		return
	var node: Node3D = PlacedTrapScript.new()
	node.what = what
	get_parent().add_child(node)
	node.global_position = hero.global_position - hero.global_transform.basis.z * 1.2
	node.global_position.y = hero.global_position.y
	SystemLog.post("placed_" + what)
