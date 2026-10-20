extends Node
## Начало игры на сцене (задача 17): пролог, первый медляк после пробуждения, наставник у респа,
## сцена куша варианта (16.3), события онбординга — смерть, убитый медляк, вскрытый мешок, стаб.
## Шаги и числа — OnboardingRules (data/onboarding.json), состояние — PlayerState.onboarding_step.

const PrologueScript := preload("res://src/ui/prologue.gd")
const MentorScript := preload("res://src/actors/mentor_npc.gd")
const JackpotSiteScript := preload("res://src/world/jackpot_site.gd")
const MENTOR_STEPS: PackedStringArray = ["mentor", "sack", "return", "to_stab"]

var hero: Node3D
var area: Node3D
var population: Node3D

var _rules: OnboardingRules
var _first_infected: Node3D
## Ждём, когда первый медляк умрёт (освобождённый узел сравнивается с null как равный — нужен флаг).
var _watch_first := false
var _escape_left := -1.0
var _awaken_left := -1.0
var _system_left := -1.0
var _sacks := 0
var _mentor: Node3D


func _ready() -> void:
	add_to_group("onboarding_director")
	_rules = Content.onboarding_rules()
	_sacks = PlayerState.run.count("sacks_opened")
	PlayerState.onboarding_changed.connect(_on_step)
	EventBus.player_died.connect(_on_died)
	EventBus.cluster_entered.connect(_on_cluster)
	_setup.call_deferred()


func _on_start_cluster() -> bool:
	return WorldSim.current == String(WorldSim.region.region["start"])


func _setup() -> void:
	var step := PlayerState.onboarding_step
	if step == OnboardingRules.START:
		get_parent().add_child(PrologueScript.new())
	if area and not area.is_navigation_ready:
		await area.navigation_ready
	if not _on_start_cluster():
		return
	if step == "awaken":
		_awaken_left = float(_rules.config()["first_infected"]["delay_s"])
	if MENTOR_STEPS.has(step):
		_spawn_mentor()
	if PlayerState.pending_jackpot:
		var scene := _rules.jackpot_scene(PlayerState.origin_variant)
		match String(scene["kind"]):
			"object":
				_spawn_site(scene)
			"system":
				_system_left = float(scene.get("delay_s", 5.0))


func _on_step(step: String) -> void:
	if step == "awaken" and _on_start_cluster():
		_awaken_left = float(_rules.config()["first_infected"]["delay_s"])
		SystemLog.post("awaken")
	if MENTOR_STEPS.has(step) and _on_start_cluster():
		_spawn_mentor()


func _process(delta: float) -> void:
	if PlayerState.onboarding_step.is_empty():
		return
	if _awaken_left > 0.0:
		_awaken_left -= delta
		if _awaken_left <= 0.0:
			_spawn_first_infected()
	if _system_left > 0.0:
		_system_left -= delta
		if _system_left <= 0.0 and PlayerState.pending_jackpot:
			SystemLog.post("jackpot_" + PlayerState.origin_variant, {}, "special")
			PlayerState.grant_jackpot()
	if _watch_first and not is_instance_valid(_first_infected):
		_watch_first = false
		PlayerState.onboarding_event("first_infected_dead")
	if _escape_left > 0.0:
		_escape_left -= delta
		if _escape_left <= 0.0:
			PlayerState.onboarding_event("first_infected_escaped")
	var sacks := PlayerState.run.count("sacks_opened")
	if sacks > _sacks:
		_sacks = sacks
		PlayerState.onboarding_event("sack_opened")


func _spawn_first_infected() -> void:
	var cfg: Dictionary = _rules.config()["first_infected"]
	if population == null or hero == null:
		PlayerState.onboarding_event("first_infected_spawned")
		return
	var angle := randf() * TAU
	var at: Vector3 = area.snap(hero.global_position + Vector3(cos(angle), 0.0, sin(angle)) * float(cfg["distance_m"]))
	_first_infected = population.spawn(String(cfg["id"]), int(cfg["level"]), at)
	if _first_infected:
		_first_infected.hear(hero.global_position, 1.0)  # идёт проверить, кто тут
		_watch_first = true
	SystemLog.post("first_infected", {}, "warning")
	_escape_left = float(cfg.get("escape_s", 90.0))
	PlayerState.onboarding_event("first_infected_spawned")


func _spawn_mentor() -> void:
	if is_instance_valid(_mentor) or not get_tree().get_nodes_in_group("mentor").is_empty():
		return
	var offset: Array = _rules.config()["mentor"]["offset"]
	var at := PlayerState.respawn_position + Vector3(float(offset[0]), 0.0, float(offset[1]))
	_mentor = MentorScript.new()
	area.add_child(_mentor)
	_mentor.global_position = area.snap(at)
	_mentor.look_at(PlayerState.respawn_position, Vector3.UP)
	_mentor.rotation.x = 0.0


func _spawn_site(scene: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.world_seed, "jackpot"])
	var angle := rng.randf() * TAU
	var site: Node3D = JackpotSiteScript.new()
	site.variant = PlayerState.origin_variant
	site.scene = scene
	area.add_child(site)
	site.global_position = area.snap(PlayerState.respawn_position + Vector3(cos(angle), 0.0, sin(angle)) * float(scene["distance_m"]))


func _on_died(_cause: String, _lives: int) -> void:
	if PlayerState.onboarding_step.is_empty():
		return
	if PlayerState.deaths == 1:
		SystemLog.post("first_death_explained", {"lives": PlayerState.lives}, "special")
	if PlayerState.pending_jackpot and String(_rules.jackpot_scene(PlayerState.origin_variant)["kind"]) == "first_death":
		SystemLog.post("jackpot_" + PlayerState.origin_variant, {}, "special")
		PlayerState.grant_jackpot()
	PlayerState.onboarding_event("hero_died")


func _on_cluster(id: String) -> void:
	if bool(WorldSim.cluster_config(id).get("safe", false)):
		PlayerState.onboarding_event("stab_entered")
