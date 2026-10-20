extends "res://tests/test_case.gd"
## Бой: docs/spec/08_combat.md, 8.3–8.4.

const DamageModelScript := preload("res://src/core/damage_model.gd")
const WeaponDBScript := preload("res://src/core/weapon_db.gd")
const WeaponStateScript := preload("res://src/core/weapon_state.gd")
const WoundsScript := preload("res://src/core/wounds.gd")
const ItemDBScript := preload("res://src/core/item_db.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _model() -> DamageModel:
	return DamageModelScript.new(JsonDataScript.load_dict("res://data/combat.json"))


func _weapons() -> WeaponDB:
	return WeaponDBScript.new(JsonDataScript.load_dict("res://data/weapons.json"))


func _inventory() -> Inventory:
	var files: Array = []
	for file in DirAccess.get_files_at("res://data/items"):
		if file.ends_with(".json"):
			files.append(JsonDataScript.load_dict("res://data/items".path_join(file)))
	return InventoryScript.new(ItemDBScript.new(files), JsonDataScript.load_dict("res://data/inventory.json"))


func test_zone_multipliers_and_crit() -> void:
	var m := _model()
	var none := {}
	assert_almost(m.hit(30, "torso", none, 0.0)["damage"], 30.0, "торс ×1")
	assert_almost(m.hit(30, "head", none, 0.0)["damage"], 60.0, "голова ×2")
	assert_almost(m.hit(30, "limbs", none, 0.0)["damage"], 18.0, "конечности ×0.6")
	var sack := m.hit(30, "spore_sack", none, 0.0)
	assert_almost(sack["damage"], 90.0, "мешок ×3")
	assert_true(sack["crit"], "мешок — крит")


func test_armor_and_penetration() -> void:
	var m := _model()
	var plates := {"head": 20.0, "torso": 18.0}
	assert_almost(m.hit(14, "torso", plates, 0.1)["damage"], 0.0, "нож в пластину топтуна — ничего")
	assert_true(m.hit(14, "torso", plates, 0.1)["armor_stopped"], "броня погасила")
	assert_almost(m.hit(50, "torso", plates, 0.3)["damage"], 50.0 - 18.0 * 0.7, "топор: пробой 30%")
	assert_almost(m.hit(14, "limbs", plates, 0.1)["damage"], 8.4, "по ногам броня не мешает")


func test_ranged_zones_grow_with_accuracy() -> void:
	var m := _model()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var counts := {"low": 0, "high": 0, "sack": 0, "sack_front": 0}
	for i in 4000:
		if m.ranged_zone(false, 1.0, rng) == "head":
			counts["low"] += 1
		if m.ranged_zone(false, 41.0, rng) == "head":
			counts["high"] += 1
		if m.ranged_zone(true, 1.0, rng) == "spore_sack":
			counts["sack"] += 1
		if m.ranged_zone(false, 41.0, rng) == "spore_sack":
			counts["sack_front"] += 1
	assert_true(counts["low"] > 380 and counts["low"] < 580, "Меткость 1: голова ≈ 12%%: %d" % counts["low"])
	assert_true(counts["high"] > 1150 and counts["high"] < 1450, "Меткость 41: ≈ 32%%: %d" % counts["high"])
	assert_true(counts["sack"] > 220 and counts["sack"] < 420, "сзади мешок ≈ 8%%: %d" % counts["sack"])
	assert_eq(counts["sack_front"], 0, "спереди мешка не видно")


func test_from_behind() -> void:
	var m := _model()
	var forward := Vector3(0, 0, -1)
	assert_true(not m.is_from_behind(forward, Vector3(0, 0, -1)), "спереди")
	assert_true(m.is_from_behind(forward, Vector3(0, 0, 1)), "строго сзади")
	assert_true(m.is_from_behind(forward, Vector3(0.5, 0, 1)), "сзади-сбоку (в секторе 120°)")
	assert_true(not m.is_from_behind(forward, Vector3(1, 0, 0)), "сбоку — не сзади")


func test_melee_zone_distribution() -> void:
	var m := _model()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var sack_front := 0
	var sack_back := 0
	for i in 2000:
		if m.melee_zone("heavy", false, rng) == "spore_sack":
			sack_front += 1
		if m.melee_zone("heavy", true, rng) == "spore_sack":
			sack_back += 1
	assert_eq(sack_front, 0, "спереди в мешок не попасть")
	assert_true(sack_back > 800 and sack_back < 1000, "тяжёлый сзади ≈ 45%%: %d из 2000" % sack_back)
	for i in 200:
		assert_true(m.melee_zone("heavy", true, rng, false) != "spore_sack", "без мешка — никогда")


func test_strength_and_winded() -> void:
	var m := _model()
	assert_almost(m.melee_multiplier(1.0, false), 1.0, "Сила 1")
	assert_almost(m.melee_multiplier(11.0, false), 1.4, "Сила 11 — +40%")
	assert_almost(m.melee_multiplier(1.0, true), 0.6, "выдохся — удар слабее")


func test_spread_from_accuracy_and_stance() -> void:
	var m := _model()
	assert_almost(m.spread_deg(3.0, 1.0, "still"), 3.0, "база")
	assert_almost(m.spread_deg(3.0, 11.0, "still"), 2.4, "Меткость 11 — −20%")
	assert_almost(m.spread_deg(3.0, 100.0, "still"), 1.2, "не уже 40%")
	assert_almost(m.spread_deg(3.0, 1.0, "sprinting"), 7.5, "на бегу ×2.5")
	assert_almost(m.spread_deg(3.0, 1.0, "sneaking"), 2.4, "присед ×0.8")


func test_magazine_reload_and_fire() -> void:
	var state := WeaponStateScript.new(_weapons())
	var inv := _inventory()
	assert_true(not state.can_fire("pistol"), "пустой магазин")
	inv.add("ammo_9mm", 11)
	assert_eq(state.reload("pistol", inv), 8, "вошло 8")
	assert_eq(inv.count_of("ammo_9mm"), 3, "в запасе 3")
	for i in 8:
		assert_true(state.fire("pistol"), "выстрел %d" % i)
	assert_true(not state.fire("pistol"), "кончились")
	assert_eq(state.reload("pistol", inv), 3, "дозарядили остаток")
	assert_true(state.can_fire("knife"), "нож патронов не просит")


func test_equip_cycle_and_loss() -> void:
	var state := WeaponStateScript.new(_weapons())
	var inv := _inventory()
	inv.add("knife", 1)
	inv.add("pistol", 1)
	var seen: Array = []
	for i in 3:
		seen.append(state.cycle(inv))
	assert_eq(seen.size(), 3, "три шага")
	assert_true(seen.has("knife") and seen.has("pistol") and seen.has("fists"), "кулаки, нож, пистолет по кругу")
	state.equipped = "pistol"
	inv.take_backpack()
	state.drop_if_missing(inv)
	assert_eq(state.equipped, "fists", "оружие ушло с трупом — в руках кулаки")


func test_bleeding_stacks_clot_and_bandage() -> void:
	var config: Dictionary = JsonDataScript.load_dict("res://data/combat.json")["bleeding"]
	var per := float(config["hp_per_second_per_stack"])
	var clot := float(config["clot_seconds"])
	var w := WoundsScript.new(config)
	w.add_bleeding()
	w.add_bleeding()
	assert_almost(w.tick(10.0), 2.0 * per * 10.0, "две стопки × 10 с")
	for i in 5:
		w.add_bleeding()
	assert_eq(w.bleeding.size(), int(config["max_stacks"]), "стопок не больше предела")
	w.stop_bleeding()
	assert_true(not w.is_bleeding(), "бинт останавливает")
	w.add_bleeding()
	assert_almost(w.tick(clot + 10.0), per * clot, "свернулась через clot_seconds")
	assert_true(not w.is_bleeding(), "сама прошла")


## Плейтест (задача 20, D-105): само кровотечение, даже в полную силу, не добивает здорового героя —
## убивает рана плюс бой, а не «победил и истёк».
func test_full_bleeding_does_not_kill_healthy_hero() -> void:
	var config: Dictionary = JsonDataScript.load_dict("res://data/combat.json")["bleeding"]
	var worst := float(config["hp_per_second_per_stack"]) * float(config["clot_seconds"]) * int(config["max_stacks"])
	var health := float(JsonDataScript.load_dict("res://data/vitals.json")["health"]["max_base"])
	assert_true(worst < health, "три стопки — %.0f из %.0f здоровья" % [worst, health])
