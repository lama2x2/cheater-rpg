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
	DirAccess.remove_absolute(path)
	player.free()
	player2.free()
	clock.free()
	clock2.free()
