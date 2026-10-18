extends "res://tests/test_case.gd"
## Умения: рост от Ментальной силы, свойства на порогах, слоты, откаты, мана, глушение, дары.
## docs/spec/05_skills.md, 14.5.

const SkillRulesScript := preload("res://src/core/skill_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")
const BuffsScript := preload("res://src/core/buffs.gd")
## Сутки 2880 реальных секунд (D-06): 0,5 игровой минуты в реальную секунду.
const MPS := 0.5


func _defs() -> Array:
	var defs: Array = []
	for file in DirAccess.get_files_at("res://data/skills"):
		if file.ends_with(".json"):
			defs.append(JsonDataScript.load_dict("res://data/skills".path_join(file)))
	return defs


func _rules() -> Dictionary:
	return JsonDataScript.load_dict("res://data/skill_rules.json")


func _skills() -> SkillRules:
	return SkillRulesScript.new(_rules(), _defs(), MPS)


func _levels(mental: int = 1, facets: int = 1, general: int = 1, luck: int = 1) -> Dictionary:
	return {"mental": mental, "talent_facets": facets, "general": general, "luck": luck}


func _effect(list: Array[Dictionary], type: String) -> Dictionary:
	for e in list:
		if String(e["type"]) == type:
			return e
	return {}


func test_skill_data_is_consistent() -> void:
	var rules := _rules()
	var texts := JsonDataScript.load_dict("res://data/text/ru_skills.json")
	var ids: Array = _defs().map(func(d: Dictionary) -> String: return d["id"])
	for d: Dictionary in _defs():
		assert_true(["active", "passive"].has(String(d["slot"])), "%s: slot" % d["id"])
		assert_true(d.has("mana_cost") and d.has("cooldown_s"), "%s: мана и откат" % d["id"])
		var props: Array = d.get("properties", [])
		var seen := {}
		for p: Dictionary in props:
			assert_true(not seen.has(p["id"]), "%s: свойство %s одно" % [d["id"], p["id"]])
			seen[p["id"]] = true
			for stat: String in p.get("unlock", {}):
				assert_true(rules["thresholds"].has(stat), "%s: порог %s известен" % [p["id"], stat])
		assert_true(texts["skill_names"].has(d["id"]) and texts["skill_desc"].has(d["id"]), "%s: название и описание в ru_skills.json" % d["id"])
		for p: Dictionary in props:
			assert_true(texts["property_names"].has(p["id"]), "%s: название свойства" % p["id"])
	for pool: String in rules["gifts"]:
		if pool.begins_with("_"):
			continue
		for id: String in rules["gifts"][pool]["skills"]:
			assert_true(id is String, "пул %s" % pool)
	assert_true(ids.has("fortune_smile"), "Улыбка Фортуны есть")


func test_fortune_smile_base_numbers() -> void:
	var s := _skills()
	var levels := _levels()
	assert_almost(s.mana_cost("fortune_smile", levels), 20.0, "мана 20")
	assert_almost(s.cooldown_s("fortune_smile", levels), 86400.0, "откат сутки")
	var buff := _effect(s.effects("fortune_smile", levels), "stat_mult")
	assert_almost(float(buff["value"]), 20.0, "Удача ×20")
	assert_almost(float(buff["duration_s"]), 8.0, "8 реальных секунд")
	assert_almost(float(buff["duration_min"]), 4.0, "= 4 игровые минуты")


func test_fortune_smile_grows_with_mental() -> void:
	var s := _skills()
	var at150 := _levels(150)
	var buff := _effect(s.effects("fortune_smile", at150), "stat_mult")
	assert_almost(float(buff["value"]), 35.0, "к 150 — ×35 (05)")
	assert_almost(float(buff["duration_s"]), 23.0, "к 150 — 23 с (05)")
	assert_almost(s.cooldown_s("fortune_smile", at150), 77400.0, "откат −10 мин за каждые 10")
	assert_almost(s.cooldown_s("fortune_smile", _levels(2000)), 43200.0, "откат не короче 12 ч")
	assert_almost(s.mana_cost("fortune_smile", _levels(35)), 23.0, "мана растёт: 20 + 3")


func test_talent_facets_cut_mana_and_cooldown() -> void:
	var s := _skills()
	assert_almost(s.mana_cost("fortune_smile", _levels(1, 60)), 18.0, "Грани 60 — мана ×0,9")
	assert_almost(s.mana_cost("fortune_smile", _levels(1, 90)), 16.2, "Грани 90 — ещё ×0,9")
	assert_almost(s.cooldown_s("fortune_smile", _levels(1, 60)), 77760.0, "откат ×0,9")


func test_properties_choice_on_thresholds() -> void:
	var s := _skills()
	s.learn("fortune_smile", 1)
	assert_eq(s.property_choices("fortune_smile", _levels(29)).size(), 0, "до 30 выбора нет")
	var choices := s.property_choices("fortune_smile", _levels(30))
	assert_eq(choices.size(), 1, "на 30 — одна группа")
	assert_eq(choices[0]["options"].size(), 2, "выбор 1 из 2")
	assert_true(not s.choose_property("fortune_smile", "fortune_echo", _levels(30)), "свойство 60 на 30 не взять")
	assert_true(s.choose_property("fortune_smile", "fortune_immunity", _levels(30)), "иммунитет взят")
	assert_true(not s.choose_property("fortune_smile", "fortune_quick", _levels(30)), "второе из группы — нельзя")
	assert_eq(s.property_choices("fortune_smile", _levels(30)).size(), 0, "группа закрыта")
	var status := _effect(s.effects("fortune_smile", _levels(30)), "status")
	assert_eq(String(status.get("status", "")), "immunity", "Улыбка даёт иммунитет")
	assert_almost(float(status["duration_s"]), 1.5, "1,5 с")
	var at90 := s.property_choices("fortune_smile", _levels(90))
	assert_eq(at90.size(), 2, "на 90 открыты группы 60 и 90")
	var m90: Array = at90[1]["options"]
	assert_eq(m90.size(), 1, "«на всех» без отряда не предлагается (M2)")


func test_modify_and_facet_properties() -> void:
	var s := _skills()
	s.learn("fortune_smile", 1)
	s.choose_property("fortune_smile", "fortune_quick", _levels(30))
	assert_almost(s.cooldown_s("fortune_smile", _levels(30)), 86400.0 - 1800.0 - 3600.0, "откат: рост и свойство")
	s.choose_property("fortune_smile", "fortune_echo", _levels(90))
	s.choose_property("fortune_smile", "fortune_big", _levels(90))
	var list := s.effects("fortune_smile", _levels(90, 30))
	var main := {}
	var echo := {}
	for e in list:
		if String(e["type"]) == "stat_mult":
			if e.has("delay_s"):
				echo = e
			else:
				main = e
	assert_almost(float(main["value"]), 34.0, "×20 + 9 + 5 (джекпот)")
	assert_almost(float(echo["delay_s"]), float(main["duration_s"]), "эхо — сразу после Улыбки")
	assert_true(not _effect(list, "vitals_fill_random").is_empty(), "Грани 30 — свойство без выбора")


func test_immunity_capped_by_d18() -> void:
	var rules := _rules()
	rules["status_caps_s"] = {"immunity": 2.0}
	var s := SkillRulesScript.new(rules, _defs(), MPS)
	s.learn("fortune_smile", 1)
	s.choose_property("fortune_smile", "fortune_immunity", _levels(150))
	s.choose_property("fortune_smile", "fortune_immunity_long", _levels(150))
	for e in s.effects("fortune_smile", _levels(150)):
		if String(e["type"]) == "status":
			assert_true(float(e["duration_s"]) <= 2.0, "иммунитет не длиннее потолка")


func test_use_cooldown_mana_and_reset_on_death() -> void:
	var s := _skills()
	var levels := _levels()
	assert_eq(s.can_use("fortune_smile", 0.0, 20.0, levels), "unknown", "не изучено")
	s.learn("fortune_smile", 1)
	assert_eq(s.slots[0], "fortune_smile", "встало в первый слот")
	assert_eq(s.can_use("fortune_smile", 0.0, 19.0, levels), "mana", "мало маны")
	var used := s.use("fortune_smile", 100.0, 20.0, levels)
	assert_eq(String(used["result"]), "ok", "применено")
	assert_almost(float(used["mana"]), 20.0, "цена")
	assert_eq(s.can_use("fortune_smile", 100.0 + 1439.0, 20.0, levels), "cooldown", "откат сутки")
	assert_eq(s.can_use("fortune_smile", 100.0 + 1440.0, 20.0, levels), "ok", "через сутки готово")
	s.reset_cooldowns()
	assert_eq(s.can_use("fortune_smile", 101.0, 20.0, levels), "ok", "смерть обнуляет откаты (D-73)")


func test_blocked_on_disabled_cluster_and_jammer() -> void:
	var s := _skills()
	s.learn("fortune_smile", 1)
	s.set_blocker("cluster_disabled", true)
	assert_eq(s.can_use("fortune_smile", 0.0, 20.0, _levels()), "blocked", "отключённый кластер")
	s.set_blocker("cluster_disabled", false)
	s.set_blocker("jammer", true)
	assert_eq(s.can_use("fortune_smile", 0.0, 20.0, _levels()), "blocked", "глушитель")
	s.set_blocker("jammer", false)
	assert_eq(s.can_use("fortune_smile", 0.0, 20.0, _levels()), "ok", "снова работает")
	assert_eq(s.can_use("fortune_smile", 0.0, 0.0, _levels()), "mana", "при нуле маны — нет")


func test_slots_by_general_level() -> void:
	var s := _skills()
	assert_eq(s.slot_count(1), 1, "на старте 1 слот (D-17)")
	assert_eq(s.slot_count(30), 2, "30 — второй")
	assert_eq(s.slot_count(60), 3, "60 — третий")
	assert_eq(s.slot_count(200, 5), 4, "не больше 4")


func test_slot_swap_and_cooldown() -> void:
	var rules := _rules()
	var defs := _defs()
	defs.append({"id": "test_passive", "slot": "passive", "mana_cost": 0, "cooldown_s": 0,
		"effects": [{"type": "reserve_mana", "pct": 0.1}, {"type": "noise_mult_self", "mult": 0.65}]})
	var s := SkillRulesScript.new(rules, defs, MPS)
	s.learn("fortune_smile", 30)
	s.learn("test_passive", 30)
	assert_eq(s.slotted(30), PackedStringArray(["fortune_smile", "test_passive"]), "два слота заняты")
	assert_eq(s.slotted(1), PackedStringArray(["fortune_smile"]), "открыт только первый")
	assert_almost(s.mana_reserve(_levels(1, 1, 30)), 0.1, "пассив держит 10% маны (D-74)")
	assert_eq(s.passive_effects("noise_mult_self", _levels(1, 1, 30)).size(), 1, "пассив действует из слота")
	s.set_blocker("jammer", true)
	assert_eq(s.passive_effects("noise_mult_self", _levels(1, 1, 30)).size(), 0, "под глушителем пассивы молчат")
	s.set_blocker("jammer", false)
	assert_true(s.set_slot(0, "test_passive", 10.0, 30), "пассив в первый слот")
	assert_eq(s.slots[0], "test_passive", "переехал")
	assert_eq(s.slots[1], "", "старый слот пуст")
	assert_true(s.set_slot(1, "fortune_smile", 10.0, 30), "Улыбка обратно")
	assert_eq(s.can_use("fortune_smile", 10.0, 20.0, _levels(1, 1, 30)), "cooldown", "после смены слота — откат смены")
	assert_eq(s.can_use("fortune_smile", 10.0 + 30.0, 20.0, _levels(1, 1, 30)), "ok", "30 игровых минут спустя готово")
	assert_eq(s.can_use("test_passive", 0.0, 20.0, _levels(1, 1, 30)), "passive", "пассив не жмётся")


func test_gift_offer_and_pearl() -> void:
	var defs := _defs()
	defs.append({"id": "heat_vision", "slot": "active", "mana_cost": 1, "cooldown_s": 1, "effects": []})
	var s := SkillRulesScript.new(_rules(), defs, MPS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(s.gift_pool(10), "10", "дар 10")
	assert_eq(s.gift_pool(45), "30", "дар 30")
	assert_eq(s.offer_count("10", 1), 3, "3 варианта")
	assert_eq(s.offer_count("10", 60), 4, "Удача 60 — 4")
	var offer := s.gift_offer("10", 3, rng)
	assert_eq(offer.size(), 3, "три варианта")
	for id in offer:
		assert_true(_rules()["gifts"]["10"]["skills"].has(id), "%s из пула 10" % id)
	var forced := s.gift_offer("10", 3, rng, PackedStringArray(["fortune_smile"]))
	assert_true(forced.has("fortune_smile"), "читеру Улыбка всегда в списке")
	for id: String in _rules()["gifts"]["10"]["skills"]:
		if id != "ambusher":
			s.learn(id, 1)
	var rest := s.gift_offer("10", 3, rng)
	assert_eq(rest, PackedStringArray(["ambusher", "heat_vision"]), "пул исчерпан — добор из других")
	assert_eq(s.pearl_skill(rng), "ambusher", "жемчужина: пул 60 пуст → добор с младших")


func test_save_roundtrip() -> void:
	var s := _skills()
	s.learn("fortune_smile", 1)
	s.choose_property("fortune_smile", "fortune_quick", _levels(30))
	s.use("fortune_smile", 50.0, 99.0, _levels(30))
	var restored := _skills()
	restored.load_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(restored.slots[0], "fortune_smile", "слот")
	assert_eq(restored.learned["fortune_smile"]["properties"], ["fortune_quick"], "свойство")
	assert_almost(restored.cooldown_left("fortune_smile", 50.0), s.cooldown_left("fortune_smile", 50.0), "откат")
	var junk := _skills()
	junk.load_dict({"learned": {"no_such_skill": {}}, "slots": ["no_such_skill"]})
	assert_true(junk.learned.is_empty() and junk.slots[0] == "", "неизвестные умения из старого сейва выбрасываются")


func test_jackpot_group_takes_larger() -> void:
	var buffs := BuffsScript.new()
	buffs.add("luck", 19.0, 10.0, "skill:fortune_smile", -INF, "fortune")
	buffs.add("luck", 4.0, 10.0, "skill:balance_loan", -INF, "fortune")
	buffs.add("luck", 0.3, 10.0, "pea")
	assert_almost(buffs.multiplier("luck", 1.0), 20.3, "в группе — больший, остальное складывается")
	buffs.add("luck", 1.0, 30.0, "skill:fortune_smile", 10.0, "fortune")
	assert_almost(buffs.multiplier("luck", 5.0), 20.3, "эхо ещё не началось")
	assert_almost(buffs.multiplier("luck", 15.0), 2.0, "эхо после Улыбки")
	assert_true(buffs.is_active("skill:fortune_smile", 15.0), "источник активен")


# --- Пачка 1 (13b): пул дара 10 -----------------------------------------------------------------

func test_gift_10_pool_is_complete() -> void:
	var s := _skills()
	for id: String in _rules()["gifts"]["10"]["skills"]:
		assert_true(s.has_def(id), "умение пула дара 10 есть в data/skills: %s" % id)


func test_soft_step_and_quiet_sprint_noise() -> void:
	var s := _skills()
	var levels := _levels(1, 1, 30)
	s.learn("soft_step", 30)
	var walk := s.noise_adjust("walk_step", 0.0, levels)
	assert_almost(float(walk["mult"]), 0.65, "шаги ×0,65")
	assert_almost(float(s.noise_adjust("pistol", 0.0, levels)["mult"]), 1.0, "выстрел не глушится")
	assert_almost(float(s.noise_adjust("walk_step", 0.0, _levels(100, 1, 30))["mult"]), 0.45, "Ментальная 100: −0,2")
	assert_almost(float(s.noise_adjust("walk_step", 0.0, _levels(500, 1, 30))["mult"]), 0.4, "не тише ×0,4")
	s.choose_property("soft_step", "step_doors", _levels(60, 1, 30))
	var run := s.noise_adjust("sprint_step", 0.0, _levels(60, 1, 30))
	assert_eq(String(run["source"]), "walk_step", "на 60 бег шумит как шаг")
	assert_almost(float(s.noise_adjust("door", 0.0, _levels(60, 1, 30))["mult"]), 0.5, "тихие двери")
	assert_almost(s.mana_reserve(levels), 0.05, "резерв 5%")
	s.learn("second_wind", 30)
	s.choose_property("second_wind", "wind_quiet", _levels(30, 1, 30))
	s.use("second_wind", 0.0, 100.0, _levels(30, 1, 30))
	assert_true(s.has_status("free_sprint", 6.0), "бег без усталости (10 + 3 с за Ментальную 30)")
	assert_true(not s.has_status("free_sprint", 7.0), "13 с = 6,5 игровой минуты — и всё")
	assert_almost(float(s.noise_adjust("sprint_step", 1.0, _levels(1, 1, 30))["mult"]), 0.65 * 0.7, "тихий бег и мягкий шаг")


func test_second_wind_effects() -> void:
	var s := _skills()
	s.learn("second_wind", 1)
	s.choose_property("second_wind", "wind_quiet", _levels(30))
	var list := s.effects("second_wind", _levels(30))
	var statuses := list.filter(func(e: Dictionary) -> bool: return e["type"] == "status")
	assert_eq(statuses.size(), 2, "бег и тихий бег")
	assert_almost(float(statuses[0]["duration_s"]), 13.0, "10 + 3 с за Ментальную 30")
	assert_almost(float(statuses[1]["duration_s"]), 13.0, "тихий бег — столько же")
	assert_almost(float(_effect(list, "vital_cost")["value"]), 3.0, "споровый баланс −3")
	s.reset_cooldowns()
	assert_true(_effect(s.effects("second_wind", _levels(60)), "cure").has("status"), "на 60 — останавливает кровь")


func test_ambusher_damage() -> void:
	var s := _skills()
	s.learn("ambusher", 1)
	assert_almost(s.damage_mult(true, false, _levels()), 1.6, "по ничего не подозревающей ×1,6")
	assert_almost(s.damage_mult(false, false, _levels()), 1.0, "по гонящейся — без бонуса")
	assert_almost(s.damage_mult(true, true, _levels()), 1.2, "элита ×1,2")
	assert_almost(s.damage_mult(true, false, _levels(40)), 1.8, "Ментальная 40: +0,2")
	assert_almost(s.crit_chance(true, _levels(59)), 0.0, "крит — с 60")
	assert_almost(s.crit_chance(true, _levels(60)), 0.2, "на 60 +20%")
	assert_almost(s.crit_chance(false, _levels(60)), 0.0, "только по ничего не подозревающей")
	s.set_slot(0, "", 0.0, 1)
	assert_almost(s.damage_mult(true, false, _levels()), 1.0, "не в слоте — не работает")


func test_text_properties_and_flags() -> void:
	var s := _skills()
	s.learn("voice_throw", 1)
	assert_eq(String(_effect(s.effects("voice_throw", _levels(59)), "noise_at")["source"]), "voice_throw", "голос")
	assert_eq(String(_effect(s.effects("voice_throw", _levels(60)), "noise_at")["source"]), "pistol", "на 60 — как выстрел")
	s.choose_property("voice_throw", "voice_two", _levels(30))
	assert_eq(int(_effect(s.effects("voice_throw", _levels(30)), "noise_at")["count"]), 2, "два голоса")
	s.learn("sense_pulse", 1)
	s.choose_property("sense_pulse", "pulse_perception", _levels(30))
	assert_true(bool(_effect(s.effects("sense_pulse", _levels(30)), "highlight")["show_level"]), "уровни над тварями")
	assert_almost(s.cooldown_s("sense_pulse", _levels(150)), 0.0, "на 150 — без отката")
	assert_almost(s.mana_cost("sense_pulse", _levels(100)), 5.0, "мана не меньше 5")
	var m60 := s.property_choices("sense_pulse", _levels(60))
	assert_eq(m60.size(), 1, "на 60 выбор из одного — «вещи скрытых» ждут людей (M2)")
	s.learn("noise_eater", 1)
	assert_eq(String(_effect(s.effects("noise_eater", _levels(60)), "noise_zone")["anchor"]), "hero", "на 60 сфера идёт за героем")


func test_scarecrow_and_brain_flee() -> void:
	var s := _skills()
	s.learn("scarecrow", 1)
	var flee := _effect(s.effects("scarecrow", _levels(20)), "enemy_flee")
	assert_almost(float(flee["radius_m"]), 40.0, "30 + 2×5 м")
	assert_almost(float(flee["duration_s"]), 70.0, "60 + 2×5 с")
	assert_eq(int(flee["max_stage"]), 3, "до бегуна")
	var enemies: Array = JsonDataScript.load_dict("res://data/enemies/infected.json")["enemies"]
	var brain := InfectedBrain.new(enemies[1]["ai"], 1.5)
	brain.flee(Vector3(20, 0, 0), 2.0)
	assert_eq(brain.update(0.5, {"sees_player": true, "player_position": Vector3.ZERO, "player_distance": 1.0}), InfectedBrain.FLEE, "напуганная не видит героя")
	assert_true(not brain.is_alert(), "и не в тревоге (Из тени работает)")
	assert_eq(brain.update(2.0, {}), InfectedBrain.WANDER, "страх прошёл")
