extends SceneTree
## Сценарий умений (задачи 13, 13b), без окна: godot --headless --path . -s res://tests/scenarios/skills.gd
## Печатает: дар у знахарки (варианты и выбор), Улыбку Фортуны (мана, откат, Удача, иммунитет),
## боевую Удачу (промахи тварей за 400 атак без и под Улыбкой), смерть обнуляет откаты,
## сохранение и загрузку умений. Сверять глазами.


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var ws: Node = root.get_node("WorldSim")
	var ps: Node = root.get_node("PlayerState")
	var clock: Node = root.get_node("GameClock")
	ws.new_world(11)
	ws.current = "c_stab"
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
	var log_tail: Array = root.get_node("SystemLog").history.slice(-14).map(func(e: Dictionary) -> String: return e["text"])
	for line in log_tail:
		print("  › ", line)
	quit()
