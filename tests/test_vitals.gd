extends "res://tests/test_case.gd"
## Шкалы героя: docs/spec/03_character.md, 3.3.

const VitalsScript := preload("res://src/core/vitals.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _config() -> Dictionary:
	return JsonDataScript.load_dict("res://data/vitals.json").duplicate(true)


func _vitals(endurance: int = 1, mental: int = 1) -> Vitals:
	return VitalsScript.new(_config(), endurance, mental)


func test_start_values_and_max_from_stats() -> void:
	var v := _vitals()
	assert_almost(v.value("health"), 100.0, "здоровье полное")
	assert_almost(v.value("spore_balance"), 80.0, "споровый баланс со старта неполный")
	var tough := _vitals(5, 3)
	assert_almost(tough.max_value("health"), 140.0, "здоровье +10 за уровень Выносливости")
	assert_almost(tough.max_value("stamina"), 120.0, "бодрость +5 за уровень Выносливости")
	assert_almost(tough.max_value("mana"), 30.0, "мана +5 за уровень Ментальной силы")


func test_sprint_spends_stamina_and_winded_until_restart() -> void:
	var v := _vitals()
	var seconds := 0.0
	while v.can_sprint() and seconds < 60.0:
		v.tick(0.1, 0.0, true)
		seconds += 0.1
	assert_almost(seconds, 7.2, "100 бодрости / 14 в секунду ≈ 7.2 с бега", 0.05)
	assert_almost(v.value("stamina"), 0.0, "выдохся")
	assert_true(not v.can_sprint(), "бег недоступен на нуле")
	v.tick(0.5, 0.0, false)  # задержка регенерации: 0.5 с из 1
	v.tick(0.5, 0.0, false)  # задержка вышла: +9
	v.tick(0.5, 0.0, false)  # +9 → 18
	assert_true(not v.can_sprint(), "18 < 25: ещё рано")
	v.tick(0.5, 0.0, false)  # +9 → 27
	assert_true(v.can_sprint(), "≥ 25: снова можно бежать")


func test_stamina_regen_waits_for_delay() -> void:
	var v := _vitals()
	v.spend_stamina(50.0)
	v.tick(0.5, 0.0, false)
	v.tick(0.4, 0.0, false)
	assert_almost(v.value("stamina"), 50.0, "в первую секунду не восстанавливается")
	v.tick(1.0, 0.0, false)
	assert_almost(v.value("stamina"), 68.0, "после задержки +18/с")


func test_spore_balance_decays_with_time_and_load() -> void:
	var v := _vitals()
	v.tick(0.0, 120.0, false)
	assert_almost(v.value("spore_balance"), 72.0, "2 игровых часа × 4")
	var w := _vitals()
	w.tick(1.0, 0.0, true)
	assert_almost(w.value("spore_balance"), 80.0 - 14.0 * 0.01, "нагрузка: 14 бодрости × 0.01")


func test_spore_penalties_below_half() -> void:
	var v := _vitals()
	assert_almost(v.spore_penalty(), 0.0, "80% — без штрафа")
	assert_almost(v.speed_multiplier(), 1.0, "скорость без штрафа")
	v.drain("spore_balance", 55.0)  # 25% — половина порога
	assert_almost(v.spore_penalty(), 0.5, "25% → штраф наполовину")
	assert_almost(v.speed_multiplier(), 0.925, "скорость между 1.0 и 0.85")
	assert_almost(v.penalty_multiplier("health_regen"), 0.5, "регенерация здоровья вдвое")
	v.spend_stamina(50.0)
	v.tick(0.9, 0.0, false)
	v.tick(1.0, 0.0, false)
	assert_almost(v.value("stamina"), 50.0 + 18.0 * 0.7, "бодрость восстанавливается медленнее")


func test_spore_state_signals() -> void:
	var v := _vitals()
	var states: Array = []
	v.spore_state_changed.connect(func(s: String) -> void: states.append(s))
	v.drain("spore_balance", 35.0)   # 45%
	v.drain("spore_balance", 35.0)   # 10%
	v.restore("spore_balance", 60.0) # 70%
	assert_eq(states, ["low", "critical", "ok"], "переходы порогов")


func test_zero_spore_or_health_is_death_once() -> void:
	var v := _vitals()
	var events: Array = []
	v.depleted.connect(func(vital: String) -> void: events.append(vital))
	v.tick(0.0, 60.0 * 30.0, false)  # 30 игровых часов × 4 > 80
	assert_true(v.is_dead(), "споровый баланс 0 — смерть")
	v.tick(0.0, 60.0, false)
	assert_eq(events, ["spore_balance"], "сигнал один раз")
	var h := _vitals()
	assert_true(not h.damage(60.0), "60 урона не смертельно")
	assert_true(h.damage(60.0), "ещё 60 — смерть")


func test_health_and_mana_regen_in_game_time() -> void:
	var v := _vitals(1, 3)
	v.damage(30.0)
	v.spend_mana(20.0)
	v.tick(0.0, 60.0, false)
	assert_almost(v.value("health"), 76.0, "+6 за игровой час")
	assert_almost(v.value("mana"), 10.0 + 4.0 + 0.5 * 2, "мана: 4 + 0.5 за уровень сверх первого")
	assert_true(not v.spend_mana(100.0), "маны не хватает")


func test_restore_after_death() -> void:
	var v := _vitals()
	v.drain("spore_balance", 80.0)
	v.restore_after_death()
	assert_true(not v.is_dead(), "живой")
	assert_almost(v.fraction("spore_balance"), 0.6, "споровый баланс поднят до минимума")
	assert_almost(v.value("mana"), 0.0, "мана пуста")
	var full := _vitals()
	full.restore_after_death()
	assert_almost(full.value("spore_balance"), 80.0, "высокий баланс не режется")


func test_save_roundtrip() -> void:
	var v := _vitals()
	v.damage(12.5)
	v.drain("spore_balance", 50.0)
	var back := _vitals()
	back.load_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_eq(back.to_dict(), v.to_dict(), "значения шкал")
	assert_eq(back.spore_state(), "low", "состояние спорового баланса восстановлено")
