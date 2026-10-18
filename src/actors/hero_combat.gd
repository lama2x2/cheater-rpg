extends Node3D
## Бой героя: ЛКМ — удар или выстрел (удержание — тяжёлый удар / натянуть лук), R — перезарядка,
## Q — следующее оружие. Правила урона — DamageModel (src/core), оружие — data/weapons.json.
## Дальний бой — луч с разбросом (без баллистики в M1). Спецификация: docs/spec/08_combat.md.

const CHEST := Vector3(0, 1.3, 0)
const LAYER_WORLD := 1
const LAYER_INFECTED := 4

var hero: CharacterBody3D

var _cooldown := 0.0
var _charging := false
var _charge := 0.0
var _reload_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _charging:
		_charge += delta
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


func _unhandled_input(event: InputEvent) -> void:
	if not hero.visible:
		return
	if event.is_action_pressed("weapon_next"):
		_cancel()
		PlayerState.cycle_weapon()
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("attack"):
		_on_press()
	elif event.is_action_released("attack"):
		_on_release()


## Для интерфейса: что в руках, патроны, натяжение 0..1, идёт ли перезарядка.
func status() -> Dictionary:
	var id := PlayerState.weapons.equipped
	var weapon := _weapon()
	var result := {"id": id, "reloading": _reload_left > 0.0, "charge": 0.0}
	if weapon["kind"] == "ranged":
		result["loaded"] = PlayerState.weapons.in_magazine(id)
		result["magazine"] = int(weapon["magazine"])
		result["reserve"] = PlayerState.inventory.count_of(String(weapon["ammo"]))
	var need := float(weapon.get("charge", 0.0)) if weapon["kind"] == "ranged" else float(weapon["heavy"]["charge"])
	if _charging and need > 0.0:
		result["charge"] = clampf(_charge / need, 0.0, 1.0)
	return result


func _weapon() -> Dictionary:
	return Content.weapon_db().weapon(PlayerState.weapons.equipped)


func _on_press() -> void:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return
	var weapon := _weapon()
	if weapon["kind"] == "ranged" and float(weapon["charge"]) <= 0.0:
		_shoot(weapon)
		return
	_charging = true
	_charge = 0.0


func _on_release() -> void:
	if not _charging:
		return
	_charging = false
	var weapon := _weapon()
	if weapon["kind"] == "ranged":
		if _charge >= float(weapon["charge"]):
			_shoot(weapon)
	else:
		_melee(weapon, "heavy" if _charge >= float(weapon["heavy"]["charge"]) else "light")


func _cancel() -> void:
	_charging = false
	_reload_left = 0.0


# --- Ближний бой -------------------------------------------------------------------------------

func _melee(weapon: Dictionary, kind: String) -> void:
	var strike: Dictionary = weapon[kind]
	_cooldown = float(strike["cooldown"])
	var vitals := PlayerState.vitals
	var winded := vitals.value("stamina") < float(strike["stamina"])
	vitals.spend_stamina(float(strike["stamina"]))
	var target := _melee_target(float(strike["range"]), float(strike["arc_deg"]))
	if target == null:
		return
	var model := PlayerState.combat
	var behind := model.is_from_behind(-target.global_transform.basis.z, hero.global_position - target.global_position)
	var has_sack := bool(Content.enemy_db().enemy(target.enemy_id).get("spore_sack", false))
	var zone := model.melee_zone(kind, behind, _rng, has_sack)
	var mult := model.melee_multiplier(PlayerState.effective("strength"), winded)
	var result := model.hit(float(strike["damage"]), zone, _armor(target), float(weapon["penetration"]), mult)
	_apply_hit(target, result, PlayerState.weapons.equipped)
	EventBus.noise_made.emit(String(weapon["noise"]), hero.global_position, {"from_hero": true})


## Ближайшая тварь в секторе удара перед героем.
func _melee_target(reach: float, arc_deg: float) -> Node3D:
	var forward := -hero.global_transform.basis.z
	var best: Node3D = null
	var best_distance := INF
	for infected: Node3D in get_tree().get_nodes_in_group("infected"):
		var to := infected.global_position - hero.global_position
		to.y = 0.0
		var body_radius := float(Content.enemy_db().enemy(infected.enemy_id)["body"]["radius"])
		var distance := to.length() - body_radius
		if distance > reach or distance >= best_distance:
			continue
		if to.length() > 0.3 and rad_to_deg(forward.angle_to(to.normalized())) > arc_deg / 2.0:
			continue
		best = infected
		best_distance = distance
	return best


# --- Дальний бой -------------------------------------------------------------------------------

func _shoot(weapon: Dictionary) -> void:
	var id := PlayerState.weapons.equipped
	if not PlayerState.weapons.fire(id):
		if not _start_reload():
			SystemLog.post("weapon_empty", {}, "warning")
		return
	_cooldown = float(weapon["cooldown"])
	var model := PlayerState.combat
	var spread := model.spread_deg(float(weapon["spread_deg"]), PlayerState.effective("accuracy"), _stance())
	var origin := hero.global_position + CHEST
	var aim := -hero.global_transform.basis.z
	for i in int(weapon["pellets"]):
		var direction := DamageModel.deviate(aim, spread, _rng)
		var end := origin + direction * float(weapon["range"])
		var query := PhysicsRayQueryParameters3D.create(origin, end, LAYER_WORLD | LAYER_INFECTED, [hero.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var stop := end if hit.is_empty() else Vector3(hit["position"])
		_tracer(origin, stop)
		if not hit.is_empty() and hit["collider"].is_in_group("infected"):
			_ranged_hit(hit["collider"], stop, weapon)
		if weapon.has("recover_chance") and _rng.randf() < float(weapon["recover_chance"]):
			EventBus.arrow_landed.emit(String(weapon["ammo"]), stop)
	EventBus.noise_made.emit(String(weapon["noise"]), hero.global_position, {"from_hero": true})
	if PlayerState.weapons.in_magazine(id) == 0 and float(weapon["reload"]) <= 0.0:
		PlayerState.reload_weapon()


func _ranged_hit(target: Node3D, _at: Vector3, weapon: Dictionary) -> void:
	var model := PlayerState.combat
	var data := Content.enemy_db().enemy(target.enemy_id)
	var behind := model.is_from_behind(-target.global_transform.basis.z, hero.global_position - target.global_position)
	var zone := model.ranged_zone(behind, PlayerState.effective("accuracy"), _rng, bool(data.get("spore_sack", false)))
	var result := model.hit(float(weapon["damage"]), zone, _armor(target), float(weapon["penetration"]))
	_apply_hit(target, result, PlayerState.weapons.equipped)


func _stance() -> String:
	if hero.sneaking:
		return "sneaking"
	var speed := Vector2(hero.velocity.x, hero.velocity.z).length()
	if speed > float(Content.player_tuning()["walk_speed"]) + 0.5:
		return "sprinting"
	return "moving" if speed > 0.3 else "still"


func _start_reload() -> bool:
	var weapon := _weapon()
	if weapon["kind"] != "ranged" or _reload_left > 0.0:
		return false
	var id := PlayerState.weapons.equipped
	if PlayerState.weapons.in_magazine(id) >= int(weapon["magazine"]):
		return false
	if PlayerState.inventory.count_of(String(weapon["ammo"])) < 1:
		return false
	_charging = false
	_reload_left = maxf(0.01, float(weapon["reload"]))
	return true


func _finish_reload() -> void:
	_reload_left = 0.0
	var count := PlayerState.reload_weapon()
	if count > 0 and float(_weapon()["reload"]) > 0.0:
		SystemLog.post("reloaded", {"weapon": Content.item_name(PlayerState.weapons.equipped), "count": count})


# --- Общее -------------------------------------------------------------------------------------

func _armor(target: Node3D) -> Dictionary:
	return Content.enemy_db().enemy(target.enemy_id).get("armor", {})


func _apply_hit(target: Node3D, result: Dictionary, weapon_id: String) -> void:
	var enemy_id: String = target.enemy_id
	var level: int = target.level
	var at := target.global_position + Vector3.UP * 2.2
	_damage_number(at, result)
	var killed: bool = target.take_damage(result["damage"], hero.global_position)
	EventBus.player_hit.emit(weapon_id, enemy_id, level, result, killed)
	if killed:
		PlayerState.run.add("kills")
		PlayerState.run.add("kills_" + enemy_id)
		var key := "infected_killed_crit" if result["crit"] else "infected_killed"
		SystemLog.post(key, {"enemy": Content.enemy_name(enemy_id).capitalize(), "level": level}, "progress" if result["crit"] else "info")


func _damage_number(at: Vector3, result: Dictionary) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.012
	label.outline_size = 8
	if result["armor_stopped"]:
		label.text = Content.ui("armor_hit")
		label.modulate = Color(0.7, 0.7, 0.75)
	else:
		label.text = str(roundi(result["damage"]))
		label.modulate = Color(1.0, 0.8, 0.2) if result["crit"] else Color(1, 1, 1)
		if result["crit"]:
			label.pixel_size = 0.018
	get_tree().current_scene.add_child(label)
	label.global_position = at + Vector3(_rng.randf_range(-0.3, 0.3), 0, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", at.y + 1.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)


func _tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.95, 0.7, 0.9)
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(line.queue_free)
