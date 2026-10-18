extends SceneTree
## Сценарий умений (задачи 13, 13b), без окна: godot --headless --path . -s res://tests/scenarios/skills.gd
## Печатает: дар у знахарки (варианты и выбор), Улыбку Фортуны (мана, откат, Удача, иммунитет),
## боевую Удачу (промахи тварей за 400 атак без и под Улыбкой), смерть обнуляет откаты,
## сохранение и загрузку умений; пачка 1 (13b) — на кластере с тварями: Вспышка, Чревовещатель,
## Пугач, Второе дыхание, Гаситель, Мягкий шаг, Из тени. Сверять глазами.


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
	print("learned: ", ps.skills.learned.keys(), " slots: ", ps.skills.slots, " pending: ", ps.pending_skill_choices)
	for id: String in ps.skills.all_ids():
		ps.learn_skill(id)
	ps.skills.slots[0] = "fortune_smile"

	var luck_before: float = ps.effective("luck")
	ps.vitals.restore("mana", 999.0)
	var mana_before: float = ps.vitals.value("mana")
	print("use slot 1: ", ps.use_skill_slot(0), "; again: ", ps.use_skill_slot(0))
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
	print("after load: learned %s, slot1 %s, cooldown %.0f ≈ %.0f min" % [ps.skills.learned.keys(), ps.skills.slots[0], ps.skills.cooldown_left("fortune_smile", clock.minutes), cd])
	await _batch_1(ps, clock)
	var log_tail: Array = root.get_node("SystemLog").history.slice(-24).map(func(e: Dictionary) -> String: return e["text"])
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
		ps.skills.slots[0] = id
		ps.vitals.restore("mana", 999.0)
		if id == "second_wind":
			ps.vitals.spend_stamina(999.0)
		if id == "voice_throw" and is_instance_valid(target):
			hero.skills.aim_override = target.global_position + Vector3(3, 0, 3)
			hero.visible = false  # твари не видят героя — проверяем только слух
			target.brain.state = "wander"
			await create_timer(0.3).timeout
		var result: String = ps.use_skill_slot(0)
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
	ps.skills.slots[0] = "soft_step"
	ps.call("_update_mana_reserve")
	var levels: Dictionary = ps.skill_levels()
	print("soft_step: walk noise ×%.2f, mana max %.1f (reserve %.0f%%)" % [ps.skills.noise_adjust("walk_step", clock.minutes, levels)["mult"],
		ps.vitals.max_value("mana"), ps.vitals.mana_reserve() * 100.0])
	ps.skills.slots[0] = "ambusher"
	print("ambusher: unaware ×%.2f, alert ×%.2f, target unaware=%s" % [ps.skills.damage_mult(true, false, levels),
		ps.skills.damage_mult(false, false, levels), target.is_unaware() if is_instance_valid(target) else "?"])
