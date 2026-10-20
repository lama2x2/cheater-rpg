extends SceneTree
## Плейтест-бот (задача 20), без окна и быстрее реального времени:
##   godot --headless --path . --fixed-fps 30 -s res://tests/scenarios/autoplay.gd -- --minutes=90 [--world-seed=N]
## Время — минуты реальной игры (игровой час = 2 минуты, data/rules.json).
## Герой на автопилоте: дерётся с ближайшей видимой тварью (лучшим оружием, тяжёлым ударом), бежит
## при малом здоровье, лечится бинтом, пьёт живчик и ест, подбирает вещи, вскрывает мешки, бродит
## по кластеру. Раз в 5 минут игры печатает сводку: смерти, убийства, уровни, спораны, шкалы,
## трофеи — по ним правится баланс (data/). Сюжет и стаб не трогает (это делает живой плейтест).

var _ps: Node
var _hero: Node3D
var _minutes := 90.0
var _first_death := -1.0
var _frames := 0
var _idle := 0.0
var _exit: Node3D
var _travels := 0
var _loot_target: Node3D
var _loot_time := 0.0
var _skip := {}
var _log_keys := {}
var _wander := Vector3.ZERO
var _wander_left := 0.0
var _press := false
var _last_hour := -1
var _stats := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			_minutes = float(arg.trim_prefix("--minutes="))
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	await process_frame
	await process_frame
	_ps = root.get_node("PlayerState")
	var seed_value := 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-seed="):
			seed_value = int(arg.trim_prefix("--world-seed="))
	root.get_node("WorldSim").new_world(seed_value)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(1.0)
	paused = false
	for n in current_scene.get_children():
		if n.has_method("finish_respawn"):
			n.fast_respawn = true
	root.get_node("SystemLog").entry_posted.connect(func(entry: Dictionary) -> void:
		var key := String(entry.get("key", "?"))
		_log_keys[key] = int(_log_keys.get(key, 0)) + 1)
	print("autoplay: %d минут игры, сид %d" % [roundi(_minutes), seed_value])
	while true:
		await physics_frame
		_tick()
		_frames += 1
		var elapsed := _frames / float(Engine.physics_ticks_per_second) / 60.0
		if _first_death < 0.0 and _ps.deaths > 0:
			_first_death = elapsed
			print("первая смерть: %.1f мин" % elapsed)
		if int(elapsed / 5.0) != _last_hour:
			_last_hour = int(elapsed / 5.0)
			_report(elapsed)
		if elapsed >= _minutes or _ps.lives <= 0:
			_report(elapsed)
			var keys := _log_keys.keys()
			keys.sort_custom(func(a: String, b: String) -> bool: return int(_log_keys[a]) > int(_log_keys[b]))
			print("лог: ", ", ".join(keys.slice(0, 15).map(func(k: String) -> String: return "%s×%d" % [k, _log_keys[k]])))
			quit()
			return


func _tick() -> void:
	_hero = get_first_node_in_group("hero")
	if _hero == null or not _hero.is_inside_tree():
		return
	if _ps.awaiting_respawn:
		_hero.autopilot_move = Vector3.ZERO
		for n in current_scene.get_children():
			if n.has_method("finish_respawn") and n.get("_remaining") != null and float(n._remaining) < 4.0:
				n.finish_respawn()
		return
	var v: Object = _ps.vitals
	# Лечение и еда.
	if _ps.wounds.is_bleeding() and _ps.inventory.count_of("bandage") > 0:
		_ps.consume("bandage")
	if v.value("spore_balance") < 45.0 and _ps.inventory.count_of("zhivchik") > 0:
		_ps.consume("zhivchik")
	if v.value("stamina") < 25.0 and _ps.inventory.count_of("canned_food") > 0:
		_ps.consume("canned_food")
	_best_weapon()
	var enemy := _nearest_enemy()
	var hp_ratio: float = v.value("health") / v.max_value("health")
	if enemy:
		_idle = 0.0
	if _ps.inventory.count_of("sporan") >= 3 and _ps.inventory.count_of("vodka") >= 1:
		for recipe: Dictionary in root.get_node("Content").recipes():
			if recipe["id"] == "zhivchik":
				_ps.craft(recipe)
	if enemy and hp_ratio < 0.3:
		var away: Vector3 = _hero.global_position - enemy.global_position
		_hero.autopilot_move = away
		_hero.autopilot_sprint = true
		_hero.autopilot_look = Vector3.INF
		return
	_hero.autopilot_sprint = false
	if enemy:
		var d: float = _hero.global_position.distance_to(enemy.global_position)
		_hero.autopilot_look = enemy.global_position
		var ranged: bool = root.get_node("Content").weapon_db().is_ranged(_ps.weapons.equipped)
		var reach := 12.0 if ranged else 1.2
		if d > reach:
			_hero.autopilot_move = enemy.global_position - _hero.global_position
		else:
			_hero.autopilot_move = Vector3.ZERO
			_attack(ranged)
		return
	_hero.autopilot_look = Vector3.INF
	# Вещи и мешки.
	var target := _nearest_loot()
	if target != _loot_target:
		_loot_target = target
		_loot_time = 0.0
	_loot_time += 1.0 / Engine.physics_ticks_per_second
	if target and _loot_time > 20.0:
		_skip[target.get_instance_id()] = true  # не дойти — бросить
		target = null
	if target:
		var d: float = Vector2(_hero.global_position.x - target.global_position.x, _hero.global_position.z - target.global_position.z).length()
		_idle = 0.0
		if d > 1.2:
			_hero.autopilot_move = target.global_position - _hero.global_position
		else:
			_hero.autopilot_move = Vector3.ZERO
			if not _hero.channel.is_active():
				target.interact(_hero)
				var no_blade: bool = target.has_method("_blade_mult") and float(target.call("_blade_mult")) <= 0.0
				if "item_id" in target or no_blade or target.is_in_group("stashes"):
					_skip[target.get_instance_id()] = true  # не влезло или нечем резать — больше не пробовать
		return
	# Бродить.
	# Пусто дольше минуты — в соседний кластер.
	_idle += 1.0 / Engine.physics_ticks_per_second
	if _idle > 60.0:
		if _exit == null or not is_instance_valid(_exit) or not _exit.is_inside_tree():
			var exits := get_nodes_in_group("cluster_exits")
			if not exits.is_empty():
				_exit = exits[randi() % exits.size()]
		if _exit:
			_hero.autopilot_move = _exit.global_position - _hero.global_position
			if _hero.global_position.distance_to(_exit.global_position) < 2.0:
				_idle = 0.0
				_travels += 1
				_exit.interact(_hero)
				_exit = null
			return
	_wander_left -= 1.0 / Engine.physics_ticks_per_second
	if _wander_left <= 0.0:
		_wander_left = 12.0
		var a := randf() * TAU
		_wander = Vector3(cos(a), 0, sin(a)) * 35.0
	_hero.autopilot_move = _wander - _hero.global_position if _hero.global_position.distance_to(_wander) > 2.0 else Vector3.ZERO


func _attack(ranged: bool) -> void:
	var combat: Node = _hero.combat
	if ranged:
		if _ps.weapons.in_magazine(_ps.weapons.equipped) == 0:
			combat._start_reload()
		else:
			combat._on_press()
		return
	# Ближний: удержать на тяжёлый удар, отпустить.
	if not _press:
		combat._on_press()
		_press = true
	elif float(combat._charge) >= float(combat._weapon()["heavy"]["charge"]):
		combat._on_release()
		_press = false


func _best_weapon() -> void:
	var order := ["pistol", "shotgun", "axe", "knife"]
	for id in order:
		if _ps.inventory.count_of(id) > 0:
			var ammo_ok: bool = not root.get_node("Content").weapon_db().is_ranged(id) or _ps.weapons.reserve(id, _ps.inventory) + _ps.weapons.in_magazine(id) > 0
			if ammo_ok:
				if _ps.weapons.equipped != id:
					_ps.equip_weapon(id)
				return


func _nearest_enemy() -> Node3D:
	var vision: Node = get_first_node_in_group("hero_vision")
	var best: Node3D = null
	for node: Node3D in get_nodes_in_group("infected"):
		if vision and not vision.is_seen(node):
			continue
		var d: float = node.global_position.distance_to(_hero.global_position)
		if d < 18.0 and (best == null or d < best.global_position.distance_to(_hero.global_position)):
			best = node
	return best


func _nearest_loot() -> Node3D:
	var best: Node3D = null
	for node: Node3D in get_nodes_in_group("interactable"):
		var ok: bool = ("item_id" in node) or node.is_in_group("infected_corpses") or node.is_in_group("corpses") \
			or node.is_in_group("stashes")
		if not ok or _skip.has(node.get_instance_id()):
			continue
		var d: float = node.global_position.distance_to(_hero.global_position)
		if d < 40.0 and (best == null or d < best.global_position.distance_to(_hero.global_position)):
			best = node
	return best


func _report(minutes: float) -> void:
	var run: Object = _ps.run
	var v: Object = _ps.vitals
	var trophies := 0
	for id in ["pea_yellow", "pea_white", "pea_gold", "pearl_black", "star_black", "star_white", "grain", "nut"]:
		trophies += _ps.inventory.count_of(id)
	print("%3d мин: оружие=%s переходов=%d смертей=%d убийств=%d мешков=%d уровень=%d (сила %d скор %d вын %d набл %d) спораны=%d трофеи=%d здор=%d бодр=%d баланс=%d ур.твари=%s" % [
		roundi(minutes), _ps.weapons.equipped, _travels, _ps.deaths, run.count("kills"), run.count("sacks_opened"), _ps.stats.general_level(),
		_ps.stats.get_level("strength"), _ps.stats.get_level("speed"), _ps.stats.get_level("endurance"), _ps.stats.get_level("perception"),
		_ps.inventory.count_of("sporan"), trophies, roundi(v.value("health")), roundi(v.value("stamina")), roundi(v.value("spore_balance")),
		_ps.run.causes_ranked().slice(0, 3)])
