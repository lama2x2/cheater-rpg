extends "res://tests/test_case.gd"
## Элита (задача 18): броня везде — обычный пистолет почти бессилен, бронебой и яд пробивают;
## перезарядка берёт бронебой первым; капкан держит элиту меньше; засада у дома.

const EliteRulesScript := preload("res://src/core/elite_rules.gd")
const WeaponStateScript := preload("res://src/core/weapon_state.gd")
const WeaponDBScript := preload("res://src/core/weapon_db.gd")
const DamageModelScript := preload("res://src/core/damage_model.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const ItemDBScript := preload("res://src/core/item_db.gd")
const EnemyDBScript := preload("res://src/core/enemy_db.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> EliteRules:
	return EliteRulesScript.new(JsonDataScript.load_dict("res://data/elite.json"))


func _inventory() -> Inventory:
	var files: Array = []
	for f in ["supplies", "trophies", "weapons"]:
		files.append(JsonDataScript.load_dict("res://data/items/%s.json" % f))
	return InventoryScript.new(ItemDBScript.new(files), JsonDataScript.load_dict("res://data/inventory.json"))


func _elite_armor() -> Dictionary:
	return EnemyDBScript.new([JsonDataScript.load_dict("res://data/enemies/infected.json")]).enemy("elite")["armor"]


func test_armor_needs_ap_or_poison() -> void:
	var model := DamageModelScript.new(JsonDataScript.load_dict("res://data/combat.json"))
	var armor := _elite_armor()
	var weapons := WeaponDBScript.new(JsonDataScript.load_dict("res://data/weapons.json"))
	var pistol := weapons.weapon("pistol")
	var plain := model.hit(float(pistol["damage"]), "torso", armor, float(pistol["penetration"]))
	var ap := model.hit(float(pistol["damage"]), "torso", armor, float(pistol["ap_penetration"]))
	assert_true(plain["armor_stopped"], "обычный патрон в торс элиты — броня держит")
	assert_true(float(ap["damage"]) > 15.0, "бронебой пробивает: %f" % ap["damage"])
	var poisoned := _rules().poisoned_armor(armor, true)
	var weak := model.hit(float(pistol["damage"]), "torso", poisoned, float(pistol["penetration"]))
	assert_true(not weak["armor_stopped"], "под ядом и обычный патрон проходит: %f" % weak["damage"])
	var knife := weapons.weapon("knife")
	assert_true(float(model.hit(float(knife["heavy"]["damage"]), "torso", armor, float(knife["penetration"]))["damage"]) <= 0.0, "нож в торс элиты — без толку")


func test_reload_prefers_ap() -> void:
	var weapons := WeaponDBScript.new(JsonDataScript.load_dict("res://data/weapons.json"))
	var state := WeaponStateScript.new(weapons)
	var inv := _inventory()
	inv.add("ammo_9mm", 10)
	assert_eq(state.reload("pistol", inv), 8, "обычные — полный магазин")
	assert_almost(state.penetration("pistol"), 0.25, "обычный пробой")
	state.fire("pistol")
	inv.add("ammo_9mm_ap", 5)
	assert_eq(state.reload("pistol", inv), 5, "бронебой первым: обычные вернулись в инвентарь, вошло 5")
	assert_eq(state.loaded_type("pistol"), "ammo_9mm_ap", "в магазине бронебой")
	assert_almost(state.penetration("pistol"), 0.85, "пробой бронебоя")
	assert_eq(inv.count_of("ammo_9mm"), 9, "7 обычных вернулись к 2 оставшимся")
	assert_eq(state.reserve("pistol", inv), 9, "запас — обычные + бронебой")
	var data := state.to_dict()
	var back := WeaponStateScript.new(weapons)
	back.load_dict(data)
	assert_eq(back.loaded_type("pistol"), "ammo_9mm_ap", "тип патронов в сейве")


func test_trap_ambush_and_alive() -> void:
	var rules := _rules()
	assert_true(rules.trap_hold(true) < rules.trap_hold(false), "элита вырывается быстрее")
	var points := rules.ambush_points(Rect2(20, 0, 8, 6))
	var bait: Vector2 = points["bait"]
	var lurk: Vector2 = points["lurk"]
	assert_true(bait.length() < 20.0, "приманка — к центру кластера, на открытом месте")
	assert_true(lurk.length() > 24.0, "элита — за домом")
	assert_true(EliteRules.alive(-1, 0), "не убита — жива")
	assert_true(not EliteRules.alive(2, 2), "убита в этом цикле — нет")
	assert_true(EliteRules.alive(2, 3), "после перезагрузки — снова")
