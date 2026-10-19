extends SceneTree
## Сценарий умений (задачи 13, 13b), без окна: godot --headless --path . -s res://tests/scenarios/skills.gd
## Печатает: дар у знахарки (варианты и выбор), Улыбку Фортуны (мана, откат, Удача, иммунитет),
## боевую Удачу (промахи тварей за 400 атак без и под Улыбкой), смерть обнуляет откаты,
## сохранение и загрузку умений; пачка 1 (13b) — на кластере с тварями: Вспышка, Чревовещатель,
## Пугач, Второе дыхание, Гаситель, Мягкий шаг, Из тени; пачка 2 — Тепловое зрение, Мимо!,
## Ловкие руки, Нюх на мешок, Споровый форсаж, Кредит баланса, Пуля. Сверять глазами.


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var ws: Node = root.get_node("WorldSim")
	var ps: Node = root.get_node("PlayerState")
	var clock: Node = root.get_node("GameClock")
	ws.new_world(11)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(0.5).timeout

	ps.skill_gifts_opened.append(10)
	ps.pending_skill_choices += 1
	var offers: PackedStringArray = ps.gift_offers()
	print("gift 10 offers: ", offers, " (again: ", ps.gift_offers(), ")")
	ps.choose_gift("fortune_smile" if offers.has("fortune_smile") else offers[0])
	print("learned: ", ps.skills.learned.keys(), " list: ", ps.skills.active_list, " pending: ", ps.pending_skill_choices)
	for id: String in ps.skills.all_ids():
		ps.learn_skill(id)
	_only(ps, "fortune_smile")

	var luck_before: float = ps.effective("luck")
	ps.vitals.restore("mana", 999.0)
	var mana_before: float = ps.vitals.value("mana")
	print("use key 1: ", ps.use_hotkey(0), "; again: ", ps.use_hotkey(0))
	print("luck %.1f -> %.1f, mana %.0f -> %.0f, cooldown %s" % [luck_before, ps.effective("luck"), mana_before,
		ps.vitals.value("mana"), ps.cooldown_text(ps.skills.cooldown_left("fortune_smile", clock.minutes))])
	var model: LuckModel = root.get_node("Content").luck_model()
	for kind: String in ["enemy_miss", "enemy_stumble", "hero_crit", "quiet_noise", "unnoticed"]:
		print("  %s: %.1f%% -> %.1f%%" % [kind, model.chance(kind, luck_before) * 100.0, model.chance(kind, ps.effective("luck")) * 100.0])
	var misses := 0
	for i in 400:
		if ps.lucky("enemy_miss"):
			misses += 1
	print("enemy misses under smile: %d / 400" % misses)

	ps.skills.learned["fortune_smile"]["properties"] = ["fortune_immunity"]
	ps.skills.reset_cooldowns()
	ps.stats.add_levels("mental", 29)
	ps.vitals.restore("mana", 999.0)
	ps.use_skill("fortune_smile")
	var hp: float = ps.vitals.value("health")
	ps.hurt(30.0, "runner")
	print("immunity: hp %.0f -> %.0f (status %.2f min)" % [hp, ps.vitals.value("health"), ps.skills.status_left("immunity", clock.minutes)])

	await create_timer(4.5).timeout
	print("after 4.5 s: luck %.1f, smile active=%s" % [ps.effective("luck"), ps.buffs.is_active("skill:fortune_smile", clock.minutes)])

	ps.die("debug")
	print("after death: cooldown left %.1f min" % ps.skills.cooldown_left("fortune_smile", clock.minutes))
	ps.respawn()
	ps.vitals.restore("mana", 999.0)
	ps.use_skill("fortune_smile")
	var save: Node = root.get_node("SaveService")
	save.save_game("debug")
	var cd: float = ps.skills.cooldown_left("fortune_smile", clock.minutes)
	ps.setup()
	save.load_game("debug")
	await create_timer(1.0).timeout
	print("after load: learned %s, key 1 %s, cooldown %.0f ≈ %.0f min" % [ps.skills.learned.keys(), ps.skills.hotkey_skill(0), ps.skills.cooldown_left("fortune_smile", clock.minutes), cd])
	await _batch_1(ps, clock)
	await _batch_2(ps, clock)
	_pearl(ps)
	var log_tail: Array = root.get_node("SystemLog").history.filter(func(e: Dictionary) -> bool: return not String(e["text"]).contains("зафиксировано")) \
		.slice(-20).map(func(e: Dictionary) -> String: return e["text"])
	for line in log_tail:
		print("  › ", line)
	quit()


## Пачка 1 (13b): умения пула дара 10 на живых тварях.
func _batch_1(ps: Node, clock: Node) -> void:
	var hero := get_first_node_in_group("hero") as Node3D
	var infected := get_nodes_in_group("infected")
	print("\n-- batch 1: infected on cluster: %d" % infected.size())
	if infected.is_empty():
		return
	var target := infected[0] as Node3D
	hero.global_position = target.global_position + Vector3(14, 0, 0)
	await process_frame
	for id: String in ["sense_pulse", "voice_throw", "scarecrow", "noise_eater", "second_wind"]:
		ps.skills.reset_cooldowns()
		_only(ps, id)
		ps.vitals.restore("mana", 999.0)
		if id == "second_wind":
			ps.vitals.spend_stamina(999.0)
		if id == "voice_throw" and is_instance_valid(target):
			hero.skills.aim_override = target.global_position + Vector3(3, 0, 3)
			hero.visible = false  # твари не видят героя — проверяем только слух
			target.brain.state = "wander"
			await create_timer(0.3).timeout
		var result: String = ps.use_hotkey(0)
		await process_frame
		await process_frame
		match id:
			"sense_pulse":
				print("sense_pulse: %s, marks %d" % [result, get_nodes_in_group("skill_marks").size()])
			"scarecrow":
				var fleeing := get_nodes_in_group("infected").filter(func(n: Node) -> bool: return n.brain.state == "flee").size()
				print("scarecrow: %s, fleeing %d" % [result, fleeing])
			"voice_throw":
				await create_timer(0.5).timeout
				var states: Array = get_nodes_in_group("infected").map(func(n: Node) -> String: return n.brain.state)
				print("voice_throw: %s, infected states %s (investigate = пошли на шум)" % [result, states])
				hero.visible = true
			"noise_eater":
				var system := get_first_node_in_group("noise_system")
				print("noise_eater: %s, zones %d, mult at hero %.2f" % [result, system.zones.size(), system._zone_mult(hero.global_position)])
			"second_wind":
				print("second_wind: %s, stamina %.0f, free sprint %s, spore %.0f" % [result, ps.vitals.value("stamina"),
					ps.skills.has_status("free_sprint", clock.minutes), ps.vitals.value("spore_balance")])
	_only(ps, "soft_step")
	ps.call("_update_mana_reserve")
	var levels: Dictionary = ps.skill_levels()
	print("soft_step: walk noise ×%.2f, mana max %.1f (reserve %.0f%%)" % [ps.skills.noise_adjust("walk_step", clock.minutes, levels)["mult"],
		ps.vitals.max_value("mana"), ps.vitals.mana_reserve() * 100.0])
	_only(ps, "ambusher")
	print("ambusher: unaware ×%.2f, alert ×%.2f, target unaware=%s" % [ps.skills.damage_mult(true, false, levels),
		ps.skills.damage_mult(false, false, levels), target.is_unaware() if is_instance_valid(target) else "?"])


## Пачка 2 (13b): шортлист 9–15.
func _batch_2(ps: Node, clock: Node) -> void:
	print("\n-- batch 2")
	var hero := get_first_node_in_group("hero") as Node3D
	var infected := get_nodes_in_group("infected")
	ps.skills.reset_cooldowns()
	_only(ps, "heat_vision")
	ps.vitals.restore("mana", 999.0)
	var mana0: float = ps.vitals.value("mana")
	print("heat_vision on: ", ps.use_hotkey(0))
	await create_timer(2.0).timeout
	var heat := 0
	for node in infected:
		if is_instance_valid(node):
			heat += node.get_children().filter(func(c: Node) -> bool: return c is Label3D and String(c.text).begins_with("◉")).size()
	print("heat marks %d, mana %.2f -> %.2f (10 + ~0.2 upkeep), off: %s" % [heat, mana0, ps.vitals.value("mana"), ps.use_hotkey(0)])

	_only(ps, "trophy_nose")
	for node in infected:
		if is_instance_valid(node):
			node.sniffed = false
			hero.global_position = node.global_position + Vector3(6, 0, 0)
	await create_timer(0.6).timeout
	var target: Node3D = null
	for node in get_nodes_in_group("infected"):
		if node.sniffed:
			target = node
	if target:
		var loot: Dictionary = target.sack_loot
		print("trophy_nose: sniffed %s, sack %s, glow %s" % [target.enemy_id, loot, target.get_meta("nose_show", false)])
		_only(ps, "quick_hands")
		ps.pick_up("knife", 1)
		target.take_damage(9999.0)
		await process_frame
		var corpse: Node3D = null
		for c in get_nodes_in_group("infected_corpses"):
			if c.has_pre_loot:
				corpse = c
		if corpse:
			print("corpse pre_loot %s (= sack above)" % [corpse.pre_loot])
			hero.global_position = corpse.global_position + Vector3(0.5, 0, 0)
			corpse.interact(hero)
			print("quick_hands: opening takes %.1f s (knife ×2, hands ×1.5)" % (hero.channel._duration))
			hero.channel.cancel()

	_only(ps, "near_miss")
	ps.stats.set_coefficient("luck", 200.0)
	var saved := 0
	for i in 200:
		ps.lives = 100
		var hp: float = ps.vitals.value("health")
		ps.skills.statuses.erase("immunity")
		ps.hurt(hp + 50.0, "runner")
		if ps.awaiting_respawn:
			ps.respawn()
		else:
			saved += 1
	print("near_miss: luck %.0f, lethal hits survived %d / 200 (cap 25%%, minus deaths in region %d)" % [ps.effective("luck"), saved, ps.deaths_since_region_shift])
	ps.stats.set_coefficient("luck", 1.0)
	ps.vitals.restore("health", 999.0)

	ps.skills.reset_cooldowns()
	_only(ps, "spore_burst")
	var spore: float = ps.vitals.value("spore_balance")
	print("spore_burst: %s, spore %.0f -> %.0f, speed ×%.2f, strength ×%.2f" % [ps.use_hotkey(0), spore, ps.vitals.value("spore_balance"),
		ps.buffs.multiplier("speed", clock.minutes), ps.buffs.multiplier("strength", clock.minutes)])
	_only(ps, "balance_loan")
	ps.vitals.restore("mana", 999.0)
	var loan: String = ps.use_hotkey(0)
	var ends: float = clock.minutes + ps.buffs.left("skill:balance_loan", clock.minutes)
	print("balance_loan: %s, luck ×%.1f now (если Улыбка ещё идёт — берётся больший), ×%.1f at loan end, ×%.2f in debt" % [loan,
		ps.buffs.multiplier("luck", clock.minutes), ps.buffs.multiplier("luck", ends - 1.0), ps.buffs.multiplier("luck", ends + 1.0)])
	_only(ps, "danger_sense")
	ps.danger_warn(hero.global_position + Vector3(5, 0, 0))
	await process_frame
	var scale := Engine.time_scale
	await create_timer(0.6, true, false, true).timeout
	print("danger_sense: time scale %.2f -> %.2f (без замедления, D-85)" % [scale, Engine.time_scale])


## Оставить в списке активных одно умение — на клавише 1.
func _only(ps: Node, id: String) -> void:
	ps.skills.active_list.clear()
	ps.skills.active_list.append(id)
	ps.call("_update_mana_reserve")


## 13c: висящее умение жемчужины (D-86) и список активных (D-84).
func _pearl(ps: Node) -> void:
	print("\n-- 13c")
	ps.skills.learned.clear()
	ps.skills.active_list.clear()
	ps.pending_pearl_skills = 2
	print("pearl self: %s -> %s" % [ps.open_pearl_self(), ps.skills.learned.keys()])
	ps.inventory.add("sporan", 60)
	var stab: Node = root.get_node("StabState")
	var money: int = stab.money()
	stab.open_pearl_area("luck")
	print("pearl at healer (luck, %d sp): %s, money %d -> %d, pending %d" % [stab.pearl_price(), ps.skills.learned.keys(), money, stab.money(), ps.pending_pearl_skills])
	for id: String in ps.skills.all_ids():
		ps.learn_skill(id)
	print("active list (no limit): %d of %d learned, reserve %.0f%%, key 1..8: %s" % [ps.skills.active_list.size(), ps.skills.learned.size(),
		ps.skills.mana_reserve() * 100.0, ps.skills.active_list.slice(0, 8)])
