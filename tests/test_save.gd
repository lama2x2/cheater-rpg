extends "res://tests/test_case.gd"
## Сохранения: docs/spec/13_tech.md, 13.5.

const SaveFormatScript := preload("res://src/core/save_format.gd")
const PlayerStateScript := preload("res://src/services/player_state.gd")
const GameClockScript := preload("res://src/services/game_clock.gd")

const TEST_DIR := "user://test_saves"


func _player() -> Node:
	var player: Node = PlayerStateScript.new()
	player.setup()
	return player


func test_wrap_has_current_version() -> void:
	var data := SaveFormatScript.wrap({"a": {}}, 123.0)
	assert_eq(int(data["save_version"]), SaveFormatScript.VERSION, "версия")
	assert_true(data["sections"].has("a"), "секции внутри")


func test_migration_chain_applies_in_order() -> void:
	var migrations := {
		1: func(d: Dictionary) -> Dictionary: d["sections"]["log"] = ["v2"]; return d,
		2: func(d: Dictionary) -> Dictionary: d["sections"]["log"].append("v3"); return d,
	}
	var old := {"save_version": 1, "sections": {}}
	var result := SaveFormatScript.migrate(old, migrations, 3)
	assert_eq(int(result["save_version"]), 3, "доведено до 3")
	assert_eq(result["sections"]["log"], ["v2", "v3"], "миграции по порядку")
	assert_eq(old["sections"], {}, "исходные данные не тронуты")


func test_migration_refuses_gaps_and_future() -> void:
	assert_eq(SaveFormatScript.migrate({"save_version": 1, "sections": {}}, {}, 2), {}, "нет миграции 1→2")
	assert_eq(SaveFormatScript.migrate({"save_version": 9, "sections": {}}, {}, 2), {}, "версия из будущего")
	assert_eq(SaveFormatScript.migrate({"sections": {}}), {}, "без save_version")


func test_meta_in_envelope_and_v7_migration() -> void:
	var data := SaveFormatScript.wrap({}, 5.0, {"day": 3, "lives": 97})
	assert_eq(data["meta"]["day"], 3, "сводка для списка ячеек")
	var v7 := {"save_version": 7, "saved_at": 1.0, "sections": {"player": {"lives": 50}}}
	var migrated := SaveFormatScript.migrate(v7)
	assert_eq(migrated["meta"], {}, "старый сейв — пустая сводка")
	assert_eq(int(migrated["sections"]["player"]["ng_plus"]), 0, "цикл NG+ = 0")


func test_ng_plus_carries_primary_and_coefficients() -> void:
	var player := _player()
	player.inventory.add("sporan", 30)
	player.inventory.add("vodka", 1)
	var carry: Dictionary = player.ng_plus_carry()
	var fresh := _player()
	fresh.apply_carry(carry)
	assert_eq(fresh.ng_plus, 1, "первый цикл")
	assert_eq(fresh.inventory.count_of("sporan"), 30, "ячейки Системы перенесены")
	assert_eq(fresh.inventory.count_of("vodka"), 0, "рюкзак — нет")
	assert_almost(fresh.stats.get_coefficient("strength"), 1.05, "коэффициенты +5%")
	assert_eq(fresh.lives, 100, "жизни полные")
	player.free()
	fresh.free()


func test_v1_save_gets_default_vitals() -> void:
	var v1 := {"save_version": 1, "sections": {"player": {"stats": {}, "lives": 9, "deaths": 0}}}
	var result := SaveFormatScript.migrate(v1)
	assert_eq(int(result["save_version"]), SaveFormatScript.VERSION, "доведено до текущей")
	assert_eq(result["sections"]["player"]["vitals"], {}, "пустые шкалы → значения по умолчанию")


func test_file_roundtrip_and_missing_file() -> void:
	var path := TEST_DIR.path_join("roundtrip.json")
	var data := SaveFormatScript.wrap({"clock": {"minutes": 487.123456789}}, 1.0)
	assert_eq(SaveFormatScript.write_file(path, data), OK, "запись")
	assert_true(not FileAccess.file_exists(path + ".tmp"), "временный файл убран")
	var back := SaveFormatScript.read_file(path)
	assert_almost(float(back["sections"]["clock"]["minutes"]), 487.123456789, "дробь без потерь", 1e-9)
	assert_eq(SaveFormatScript.read_file(TEST_DIR.path_join("nope.json")), {}, "нет файла — пусто")
	DirAccess.remove_absolute(path)


## Главный сценарий задачи: сохранить → загрузить → состояние совпадает.
func test_player_and_clock_survive_save_load() -> void:
	var player := _player()
	player.stats.add_progress("speed", 27.0)
	player.stats.set_coefficient("luck", 1.3)
	player.vitals.damage(33.0)
	player.vitals.drain("spore_balance", 41.0)
	player.inventory.add("sporan", 40)
	player.inventory.add("vodka", 1)
	player.lives = 6
	player.deaths = 3
	player.learn_skill("fortune_smile")
	player.vitals.restore("mana", 100.0)
	player.use_skill("fortune_smile")
	var clock: Node = GameClockScript.new()
	clock.minutes = 2000.5

	var path := TEST_DIR.path_join("state.json")
	SaveFormatScript.write_file(path, SaveFormatScript.wrap({"player": player.to_dict(), "clock": clock.to_dict()}, 1.0))
	var sections: Dictionary = SaveFormatScript.read_file(path)["sections"]

	var player2 := _player()
	player2.load_dict(sections["player"])
	var clock2: Node = GameClockScript.new()
	clock2.load_dict(sections["clock"])

	assert_eq(player2.to_dict(), player.to_dict(), "состояние героя")
	assert_eq(typeof(player2.lives), TYPE_INT, "жизни остаются целым числом")
	assert_eq(player2.inventory.count_of("sporan"), 40, "споранов")
	assert_eq(player2.stats.get_level("speed"), 2, "уровень Скорости (27 очков: 10 → ур.2, 17 из 20)")
	assert_almost(clock2.minutes, 2000.5, "время")
	assert_eq(player2.skills.slots[0], "fortune_smile", "умение в слоте")
	assert_true(player2.skills.cooldown_left("fortune_smile", 0.0) > 0.0, "откат пережил сейв")
	DirAccess.remove_absolute(path)
	player.free()
	player2.free()
	clock.free()
	clock2.free()


func test_v11_save_gets_empty_skills() -> void:
	var v11 := {"save_version": 11, "meta": {}, "sections": {"player": {"lives": 5}}}
	var player: Dictionary = SaveFormatScript.migrate(v11)["sections"]["player"]
	assert_eq(player["skills"], {}, "умений нет")
	assert_eq(player["skill_offers"], [], "вариантов дара нет")


func test_v8_save_drops_test_area_and_gets_new_world() -> void:
	var v8 := {"save_version": 8, "meta": {}, "sections": {
		"player": {"lives": 5}, "area": {"stashes": []}, "world_items": {"items": []},
		"infected": {"infected": [], "corpses": []}, "corpses": {"corpses": []}, "hero": {"position": [1, 0, 1], "yaw": 0},
	}}
	var result := SaveFormatScript.migrate(v8)
	var sections: Dictionary = result["sections"]
	for old in ["area", "world_items", "infected", "corpses", "hero"]:
		assert_true(not sections.has(old), "секция площадки %s убрана" % old)
	assert_eq(sections["world"], {}, "пустой world — мир создаётся заново")
	assert_eq(int(sections["player"]["lives"]), 5, "герой цел")


## Мир кластеров: сохранить → загрузить → таймеры, популяции и снимки совпадают.
func test_world_survives_save_load() -> void:
	var world := WorldSim
	world.new_world(777)
	world.clusters["c_town"]["reloads"] = 3
	world.snapshots["c_village"] = {"world_items": {"items": [{"id": "vodka", "count": 1, "position": [1.0, 0.0, 2.0]}]}}
	var before_current := world.current
	var data: Dictionary = world.to_dict()
	var path := TEST_DIR.path_join("world.json")
	SaveFormatScript.write_file(path, SaveFormatScript.wrap({"world": data}, 1.0))
	var back: Dictionary = SaveFormatScript.read_file(path)["sections"]["world"]
	world.new_world(12345)
	world.load_dict(back)
	assert_eq(world.current, before_current, "текущий кластер")
	assert_eq(_canonical(world.to_dict()), _canonical(back), "состояние мира")
	assert_eq(world.snapshots["c_village"]["world_items"]["items"][0]["id"], "vodka", "снимок кластера")
	assert_eq(typeof(world.clusters[world.current]["reloads"]), TYPE_INT, "счётчик перезагрузок — целое")
	DirAccess.remove_absolute(path)


## JSON без порядка ключей и различия int/float — для сравнения состояний после сохранения.
func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)
