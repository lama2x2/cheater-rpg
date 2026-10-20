extends Node
## Мир региона: кластеры, их таймеры перезагрузки и абстрактные популяции, текущий кластер, переходы.
## Правила — ClusterLifecycle и PopulationModel (src/core), граф — RegionMap. Сцена текущего кластера
## (src/world/cluster_director.gd) слушает сигналы и отдаёт свои секции в снимок через register().
## Спецификация: docs/spec/02_world.md, 13.3. Тик абстрактной симуляции — игровой час.

signal kislyak_started(cluster_id: String)
signal cluster_reloaded(cluster_id: String)
## Сколько единиц популяции текущего кластера обратилось за час — сцена добавляет медляков.
signal civilians_turned(cluster_id: String, units: float)

const CHECK_INTERVAL := 0.5

var region: RegionMap
var population: PopulationModel
var world_seed: int = 0
var current: String = ""
## Состояния кластеров: {id: {"timer", "reloads", "pop", "fresh", "known_timer", "visited", "kislyak", "ratio"}}.
## fresh — после перезагрузки сцена ещё не создавалась (лут и тайники бросаются заново);
## ratio — агентов на сцене на единицу популяции (с потолком), пока кластер материализован.
var clusters: Dictionary = {}
## Снимки сцен кластеров, где герой бывал после перезагрузки: {id: {секция: данные}}.
## В снимке, оставленном при переходе, нет живых тварей — их соберёт абстрактная популяция.
var snapshots: Dictionary = {}
## Куда поставить героя после перехода: {"from": id} — у выхода к нему, {"at": [x, z]} — в точку.
var arrival: Dictionary = {}
## Переход только что случился — сцена показывает короткую «загрузку».
var just_traveled := false
## Знание карты героя (12.6): посещённые соты, увиденные постройки, купленные карты, отметки.
var knowledge := MapKnowledge.new()

var _scene_sections: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _check_timer := 0.0


func _ready() -> void:
	var seed_value := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-seed="):
			seed_value = int(arg.trim_prefix("--world-seed="))
	new_world(seed_value)
	GameClock.hour_passed.connect(_on_hour_passed)
	EventBus.infected_killed.connect(_on_infected_killed)


## Новый мир: таймеры со случайной фазой, популяции «прогреты» на прошедшие с прилёта часы.
## Стартовый кластер только что перезагрузился — люди вокруг ещё не обратились.
func new_world(seed_value: int = 0) -> void:
	_load_rules()
	world_seed = seed_value if seed_value != 0 else randi()
	_rng.seed = world_seed
	clusters.clear()
	snapshots.clear()
	knowledge = MapKnowledge.new()
	arrival = {}
	just_traveled = false
	current = String(region.region["start"])
	var now := GameClock.minutes
	for id in region.ids():
		var type_config := _type(id)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed, id, "timer"])
		var elapsed := 0.0 if id == current else rng.randf()
		var timer := ClusterLifecycle.new_timer(type_config, now, rng, elapsed)
		var state := {
			"timer": timer, "reloads": 0, "pop": _arrival(id, 0), "fresh": true,
			"known_timer": false, "visited": false, "kislyak": false, "ratio": 0.0,
		}
		if ClusterLifecycle.reloads(timer):
			var hours := mini(int(elapsed * float(timer["period_h"])), population.warmup_hours())
			population.advance(state["pop"], hours)
		clusters[id] = state


## Граф и модель — лениво: тесты (скрипт -s) обращаются к сервису до его _ready.
func _load_rules() -> void:
	if region == null:
		region = Content.region()
		population = Content.population_model()


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_INTERVAL
	_check_reloads(GameClock.minutes)
	var state: Dictionary = clusters[current]
	if not state["kislyak"] and ClusterLifecycle.phase(state["timer"], GameClock.minutes) == ClusterLifecycle.KISLYAK:
		state["kislyak"] = true
		SystemLog.post("kislyak_started", {}, "warning")
		kislyak_started.emit(current)


func _on_hour_passed(hour: int, day: int) -> void:
	_check_reloads(((day - 1) * 24 + hour) * 60.0)
	var vision := Content.vision_rules().config()
	if hour == int(vision["night_from"]):
		SystemLog.post("night_fell", {}, "warning")
	elif hour == int(vision["night_to"]):
		SystemLog.post("dawn", {})
	for id: String in clusters:
		var turned := population.tick_hour(clusters[id]["pop"])
		if id == current and turned > 0.0:
			civilians_turned.emit(id, turned)


func _check_reloads(at_minutes: float) -> void:
	for id: String in clusters:
		var due := ClusterLifecycle.take_due(clusters[id]["timer"], at_minutes, _type(id), _rng)
		if not due.is_empty():
			_reload(id)


## Перезагрузка: новая популяция, лут и тайники бросятся заново, снимок сцены выброшен.
## Если герой на кластере — он видел сброс и теперь знает таймер (D-56).
func _reload(id: String) -> void:
	var state: Dictionary = clusters[id]
	state["reloads"] = int(state["reloads"]) + 1
	state["pop"] = _arrival(id, int(state["reloads"]))
	state["fresh"] = true
	state["kislyak"] = false
	snapshots.erase(id)
	if id == current:
		if not state["known_timer"]:
			SystemLog.post("cluster_timer_learned", {"name": cluster_name(id)}, "special")
		state["known_timer"] = true
		SystemLog.post("cluster_reloaded_here", {}, "special")
	cluster_reloaded.emit(id)


func _arrival(id: String, reload_index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = reload_seed(id, reload_index)
	var profile: Dictionary = template(id).get("population", {}) if bool(_type(id)["infected"]) else {}
	return population.arrival(profile, rng)


func reload_seed(id: String, reload_index: int = -1) -> int:
	var index := int(clusters[id]["reloads"]) if reload_index < 0 else reload_index
	return ClusterLifecycle.reload_seed(world_seed, id, index)


func _type(id: String) -> Dictionary:
	return Content.cluster_type(String(region.cluster(id)["type"]))


func cluster_type_id(id: String = "") -> String:
	return String(region.cluster(current if id.is_empty() else id)["type"])


func cluster_config(id: String = "") -> Dictionary:
	return _type(current if id.is_empty() else id)


func template(id: String = "") -> Dictionary:
	return Content.template(String(region.cluster(current if id.is_empty() else id)["template"]))


func cluster_name(id: String = "") -> String:
	return String(region.cluster(current if id.is_empty() else id)["name"])


func state(id: String = "") -> Dictionary:
	return clusters[current if id.is_empty() else id]


func is_kislyak(id: String = "") -> bool:
	return ClusterLifecycle.phase(state(id)["timer"], GameClock.minutes) == ClusterLifecycle.KISLYAK


## Доля кисляка 0..1: 0 — туман только встал, 1 — сброс сейчас.
func kislyak_progress(id: String = "") -> float:
	var timer: Dictionary = state(id)["timer"]
	var k := float(timer["kislyak_min"])
	if k <= 0.0:
		return 0.0
	return clampf(1.0 - ClusterLifecycle.minutes_left(timer, GameClock.minutes) / k, 0.0, 1.0)


func timer_text(id: String = "") -> String:
	var s := state(id)
	return ClusterLifecycle.timer_text(s["timer"], GameClock.minutes, bool(s["known_timer"]))


## Строка для HUD: «Кластер 749-208-91 · Окраина (быстрый) · ⏱ ??:??».
func hud_line() -> String:
	var c := region.cluster(current)
	var line := Content.ui("hud_cluster", {
		"code": c["code"], "name": c["name"], "type": Content.ui("cluster_type_" + String(c["type"])), "timer": timer_text(),
	})
	if is_kislyak():
		line += "   " + Content.ui("hud_kislyak")
	return line


# --- Сцена текущего кластера ---

func register(section: String, owner: Object) -> void:
	_scene_sections[section] = owner


func unregister(section: String) -> void:
	_scene_sections.erase(section)


## Записать состояние сцены текущего кластера в снимок (переход, сохранение).
func capture() -> void:
	if _scene_sections.is_empty():
		return
	var snapshot := {}
	for section: String in _scene_sections:
		snapshot[section] = _scene_sections[section].to_dict()
	snapshots[current] = snapshot


## Снимок для сцены текущего кластера ({} — свежий прилёт, сцена бросает лут и тварей сама).
func scene_snapshot() -> Dictionary:
	return snapshots.get(current, {})


## Сцена создала содержимое свежего кластера: дальше — по снимку. ratio — агентов на единицу.
func mark_materialized(ratio: float) -> void:
	var s := state()
	s["fresh"] = false
	s["ratio"] = ratio
	if not s["visited"]:
		s["visited"] = true


## Переход в соседний кластер (или на респ после смерти) — через пересборку сцены (D-07).
## entry: {} — у выхода к кластеру, откуда пришли; {"at": [x, z]} — в точку.
func travel(to: String, entry: Dictionary = {}) -> void:
	capture()
	if snapshots.has(current) and snapshots[current].has("infected"):
		snapshots[current]["infected"].erase("infected")
	arrival = entry if not entry.is_empty() else {"from": current}
	current = to
	clusters[to]["kislyak"] = false
	just_traveled = true
	get_tree().reload_current_scene.call_deferred()


## Карта кластера целиком (картограф, находка). true — что-то новое.
func reveal_map(id: String) -> bool:
	return knowledge.reveal(id)


## Найденная карта: случайный кластер региона без полной карты (сначала — соседи известных).
## "" — всё уже на карте.
func reveal_random_map(rng: RandomNumberGenerator) -> String:
	var candidates := knowledge.unmapped(region.ids())
	if candidates.is_empty():
		return ""
	var near: PackedStringArray = []
	for id in candidates:
		if knowledge.region_state(region, id) != MapKnowledge.UNKNOWN:
			near.append(id)
	var pool := near if not near.is_empty() else candidates
	pool.sort()
	var id := pool[rng.randi_range(0, pool.size() - 1)]
	knowledge.reveal(id)
	return id


func _on_infected_killed(id: String, _level: int, _at: Vector3) -> void:
	var ratio := float(state()["ratio"])
	if ratio > 0.0:
		population.remove(state()["pop"], id, 1.0 / ratio)


func to_dict() -> Dictionary:
	capture()
	return {"seed": world_seed, "current": current, "clusters": clusters.duplicate(true), "snapshots": snapshots.duplicate(true),
		"knowledge": knowledge.to_dict()}


## Пустой словарь — сохранение до кластеров (миграция v9): мир создаётся заново.
func load_dict(data: Dictionary) -> void:
	if data.is_empty():
		new_world()
		return
	_load_rules()
	world_seed = int(data["seed"])
	_rng.seed = world_seed + int(GameClock.minutes)
	current = String(data["current"])
	clusters = data["clusters"].duplicate(true)
	snapshots = data["snapshots"].duplicate(true)
	# Знание карты появилось в задаче 15; в старых сейвах его нет — соты открываются по visited.
	knowledge = MapKnowledge.new()
	knowledge.load_dict(data.get("knowledge", {}))
	for id: String in clusters:
		if bool(clusters[id].get("visited", false)):
			knowledge.visit(id)
	arrival = {}
	just_traveled = false
	# Числа из JSON приходят float — счётчики приводим обратно.
	for id: String in clusters:
		clusters[id]["reloads"] = int(clusters[id]["reloads"])
		clusters[id]["pop"]["immune"] = int(clusters[id]["pop"]["immune"])
