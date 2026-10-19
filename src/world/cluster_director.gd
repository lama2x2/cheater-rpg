extends Node
## Содержимое текущего кластера и его жизнь на сцене: при свежем прилёте бросает лут, тайники и
## тварей, иначе восстанавливает снимок; ставит героя у выхода, через который он пришёл; кисляк —
## туман перед сбросом; перезагрузка при герое — всё «чужое» исчезает, приходят новые жители (D-08);
## люди обращаются — новые медляки; чёрный кластер тянет здоровье; стаб — автосейв при входе.
## Состояние мира — WorldSim (src/services), правила — src/core. Спецификация: docs/spec/02_world.md.

const FOG_UPDATE := 0.5
const StabNpcScript := preload("res://src/actors/stab_npc.gd")
const StabWindowScript := preload("res://src/ui/stab_window.gd")

var area: Node            # cluster_area.gd
var items: Node3D         # world_items.gd
var population: Node3D    # infected_population.gd (может не быть в сцене: --no-enemies)
var death_flow: Node
var hero: Node3D
var environment: Environment

var _overlay: CanvasLayer
var _overlay_rect: ColorRect
var _overlay_label: Label
var _fog_timer := 0.0
var _drain_timer := 0.0
var _turned_carry := 0.0
var _turned_hour_logged := -1


func _ready() -> void:
	_build_overlay()
	WorldSim.kislyak_started.connect(func(_id: String) -> void: _update_fog())
	WorldSim.cluster_reloaded.connect(_on_cluster_reloaded)
	WorldSim.civilians_turned.connect(_on_civilians_turned)

	var snapshot := WorldSim.scene_snapshot()
	if snapshot.is_empty() or bool(WorldSim.state()["fresh"]):
		_fill_fresh()
	else:
		_restore(snapshot)
	_place_hero()
	_build_stab()
	_update_fog()
	if WorldSim.just_traveled:
		_on_entered()
	WorldSim.just_traveled = false


func _process(delta: float) -> void:
	_fog_timer -= delta
	if _fog_timer <= 0.0:
		_fog_timer = FOG_UPDATE
		_update_fog()
	_drain_black(delta)


## Свежий прилёт: лут по точкам шаблона (уцелевшее после мародёров), тайники, гарантированные вещи,
## твари из абстрактной популяции. Сиды — от сида перезагрузки: мир воспроизводим.
func _fill_fresh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSim.reload_seed(WorldSim.current) + 1
	var luck := PlayerState.effective("luck")
	var layout: Dictionary = area.layout
	var pop: Dictionary = WorldSim.state()["pop"]
	area.fill_fresh(ClusterLayout.roll_stashes(layout["stashes"], Content.loot(), luck, rng))
	for entry: Dictionary in ClusterLayout.roll_loot(layout["loot"], Content.loot(), float(pop["loot"]), luck, rng):
		items.spawn(entry["id"], entry["count"], Vector3(entry["at"].x, 0.0, entry["at"].y))
	var template := WorldSim.template()
	for entry: Array in template.get("fixed_items", []):
		items.spawn(String(entry[0]), int(entry[1]), Vector3(float(entry[2]), 0.0, float(entry[3])))
	var ratio := 0.0
	var profile: Dictionary = template.get("population", {})
	if bool(WorldSim.cluster_config()["infected"]) and not profile.is_empty():
		var model := WorldSim.population
		ratio = model.effective_ratio(pop, float(profile["agents_per_unit"]), int(profile["max_agents"]))
		if population:
			population.materialize(model.agents(pop, ratio), rng.seed + 2)
	_turned_carry = 0.0
	WorldSim.mark_materialized(ratio)


## Снимок сцены: вещи, тайники, двери, трупы. Живых тварей в снимке перехода нет — собрать заново.
func _restore(snapshot: Dictionary) -> void:
	var owners := {"area": area, "world_items": items, "corpses": death_flow, "infected": population}
	for section: String in owners:
		if owners[section] and snapshot.has(section):
			owners[section].load_dict(snapshot[section])
	var infected: Dictionary = snapshot.get("infected", {})
	if population and not infected.has("infected"):
		var pop: Dictionary = WorldSim.state()["pop"]
		var ratio := float(WorldSim.state()["ratio"])
		population.materialize(WorldSim.population.agents(pop, ratio), WorldSim.reload_seed(WorldSim.current) + randi() % 1000)


## Стаб: неписи с услугами на площади, лицом к её центру, и окно услуг (задача 12).
func _build_stab() -> void:
	var config := Content.stab_config()
	if WorldSim.current != String(config["cluster"]):
		return
	add_child(StabWindowScript.new())
	var plaza: Array = WorldSim.template().get("plaza", [0, 0])
	var center := Vector3(float(plaza[0]), 0.0, float(plaza[1]))
	for entry: Dictionary in config["npcs"]:
		var npc: Node3D = StabNpcScript.new()
		npc.npc_id = String(entry["id"])
		npc.kind = String(entry["kind"])
		npc.gaze = entry.get("gaze", {})
		if entry.has("color"):
			npc.color = Color(float(entry["color"][0]), float(entry["color"][1]), float(entry["color"][2]))
		npc.position = center + Vector3(float(entry["at"][0]), 0.0, float(entry["at"][1]))
		area.add_child(npc)
		npc.look_at(center, Vector3.UP)
		npc.rotation.x = 0.0
	StabState.refresh()


## Пришёл через выход — встать у выхода к прежнему кластеру; после смерти — на респ.
func _place_hero() -> void:
	var arrival := WorldSim.arrival
	WorldSim.arrival = {}
	if arrival.has("from"):
		hero.global_position = area.entry_point(String(arrival["from"]))
	elif arrival.has("at"):
		hero.global_position = Vector3(float(arrival["at"][0]), 0.1, float(arrival["at"][1]))


func _on_entered() -> void:
	var c := WorldSim.region.cluster(WorldSim.current)
	_fade(Color(0, 0, 0), Content.ui("travel_title", {"code": c["code"], "name": c["name"]}))
	var params := {"code": c["code"], "name": c["name"], "type": Content.ui("cluster_type_" + String(c["type"]))}
	SystemLog.post("cluster_entered", params)
	EventBus.cluster_entered.emit(WorldSim.current)
	var type_id := WorldSim.cluster_type_id()
	if type_id == "black":
		SystemLog.post("black_entered", {}, "warning")
	if bool(WorldSim.cluster_config().get("safe", false)):
		SystemLog.post("stab_entered", {"name": c["name"]})
		SaveService.save_game.call_deferred(SaveService.AUTO_SLOT)


## Перезагрузка, пока герой здесь: всё, что не прилетело с кластером, исчезает; герой и его вещи
## остаются; вокруг — новые жители (D-08). Вспышка и туман рассеивается.
func _on_cluster_reloaded(id: String) -> void:
	if id != WorldSim.current:
		return
	items.clear_all()
	death_flow.clear_corpses()
	if population:
		population.clear_all()
	_fill_fresh()
	_fade(Color(0.85, 0.9, 0.7), "")
	_update_fog()


func _on_civilians_turned(id: String, units: float) -> void:
	if id != WorldSim.current or population == null:
		return
	_turned_carry += units * float(WorldSim.state()["ratio"])
	var count := floori(_turned_carry)
	if count <= 0:
		return
	_turned_carry -= count
	population.spawn_turned(count)
	var hour := floori(GameClock.minutes / 60.0)
	if hour != _turned_hour_logged:
		_turned_hour_logged = hour
		SystemLog.post("infected_turned")


## Кисляк: плотность тумана растёт к моменту сброса.
func _update_fog() -> void:
	if environment == null:
		return
	var on := WorldSim.is_kislyak()
	environment.fog_enabled = on
	if not on:
		return
	var fog: Dictionary = Content.cluster_types()["fog"]
	var c: Array = fog["color"]
	environment.fog_light_color = Color(float(c[0]), float(c[1]), float(c[2]))
	environment.fog_density = lerpf(float(fog["density_start"]), float(fog["density_end"]), WorldSim.kislyak_progress())


## Чёрный кластер: здоровье тает раз в секунду; чем выше общий уровень, тем медленнее.
func _drain_black(delta: float) -> void:
	var drain: Dictionary = WorldSim.cluster_config().get("health_drain", {})
	if drain.is_empty() or PlayerState.awaiting_respawn or not hero.visible:
		return
	_drain_timer += delta
	if _drain_timer < 1.0:
		return
	var level := PlayerState.stats.general_level()
	PlayerState.hurt(_drain_timer * float(drain["base"]) / (1.0 + float(drain["per_level"]) * level), "black_cluster")
	_drain_timer = 0.0


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	add_child(_overlay)
	_overlay_rect = ColorRect.new()
	_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.modulate.a = 0.0
	_overlay.add_child(_overlay_rect)
	_overlay_label = UiKit.label(28, Color(0.95, 0.9, 0.7))
	_overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_rect.add_child(_overlay_label)


## Короткая «загрузка» перехода (D-07) или вспышка перезагрузки: экран цвета color гаснет.
func _fade(color: Color, text: String) -> void:
	_overlay_rect.color = color
	_overlay_label.text = text
	_overlay_rect.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(float(Content.cluster_types()["travel_fade_s"]) * 0.5)
	tween.tween_property(_overlay_rect, "modulate:a", 0.0, float(Content.cluster_types()["travel_fade_s"]))
