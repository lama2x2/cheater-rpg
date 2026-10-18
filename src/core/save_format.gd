class_name SaveFormat
extends RefCounted
## Формат файла сохранения: конверт с версией, цепочка миграций, чтение и запись JSON.
## Чистые правила без Node — тестируются headless. Спецификация: docs/spec/13_tech.md, 13.5.
##
## Файл: {"save_version": N, "saved_at": unix, "sections": {"clock": {...}, "player": {...}, ...}}
## Миграция — функция (data: Dictionary) -> Dictionary, переводит версию K в K+1.
##
## История версий:
##   1 — clock, player (stats, lives, deaths), log, hero.
##   2 — player.vitals (шкалы). Старые сейвы получают шкалы по умолчанию.
##   3 — player: run, deaths_since_region_shift, awaiting_respawn, start_minutes, respawn_position;
##       log.highlights; секция corpses.
##   4 — player.inventory; секция world_items.
##   5 — player: trophies, buffs, free_points, skills_awakened.
##   6 — player: weapons (в руках, магазины), wounds (кровотечение).
##   7 — player.progress (счётчики анти-фарма за игровой час); area.stashes.
##   8 — player.ng_plus; meta (сводка для списка ячеек: день, жизни, уровень).
##   9 — кластеры: секция world (таймеры, популяции, снимки сцен кластеров). Секции площадки
##       (area, world_items, infected, corpses) и позиция героя выбрасываются — мир создаётся заново.
##   10 — стаб: секция stab (торговец, доска контрактов); player.skill_gifts_opened, pending_skill_choices.
##   11 — player.save_mode (режим сохранений партии, D-30); meta.save_mode.
##   12 — player.skills (умения: изученные, слоты, откаты, статусы), player.skill_offers.

const VERSION := 12


## Миграции по исходной версии: {K: Callable}.
static func migrations() -> Dictionary:
	return {1: _v1_to_v2, 2: _v2_to_v3, 3: _v3_to_v4, 4: _v4_to_v5, 5: _v5_to_v6, 6: _v6_to_v7, 7: _v7_to_v8, 8: _v8_to_v9, 9: _v9_to_v10, 10: _v10_to_v11, 11: _v11_to_v12}


static func _v11_to_v12(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"skills": {}, "skill_offers": []})
	return data


static func _v10_to_v11(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"save_mode": "anywhere"})
	return data


static func _v9_to_v10(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"skill_gifts_opened": [], "pending_skill_choices": 0})
	data["sections"].merge({"stab": {}})
	return data


static func _v8_to_v9(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data["sections"]
	for old in ["area", "world_items", "infected", "corpses", "hero"]:
		sections.erase(old)
	sections["world"] = {}
	return data


static func _v7_to_v8(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"ng_plus": 0})
	data.merge({"meta": {}})
	return data


static func _v6_to_v7(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"progress": {}})
	if data["sections"].has("area"):
		data["sections"]["area"].merge({"stashes": []})
	return data


static func _v5_to_v6(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"weapons": {}, "wounds": {}})
	return data


static func _v4_to_v5(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"trophies": {}, "buffs": {}, "free_points": 0, "skills_awakened": 0})
	return data


static func _v3_to_v4(data: Dictionary) -> Dictionary:
	if data["sections"].has("player"):
		data["sections"]["player"].merge({"inventory": {}})
	return data


static func _v2_to_v3(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data["sections"]
	if sections.has("player"):
		var player: Dictionary = sections["player"]
		var defaults := {
			"run": {}, "deaths_since_region_shift": 0, "awaiting_respawn": false,
			"start_minutes": 0.0, "respawn_position": [0.0, 0.1, 0.0],
		}
		player.merge(defaults)
	if sections.has("log"):
		sections["log"].merge({"highlights": []})
	return data


static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var player: Dictionary = data["sections"].get("player", {})
	if not player.is_empty() and not player.has("vitals"):
		player["vitals"] = {}
	return data


## meta — короткая сводка для списка ячеек (день, жизни, уровень), чтобы не грузить всё.
static func wrap(sections: Dictionary, saved_at: float, meta: Dictionary = {}) -> Dictionary:
	return {"save_version": VERSION, "saved_at": saved_at, "meta": meta, "sections": sections}


## Доводит данные до текущей версии. Возвращает {} и пишет ошибку, если это невозможно.
## migration_table: null — встроенные migrations(); тесты передают свою таблицу.
static func migrate(data: Dictionary, migration_table: Variant = null, target: int = VERSION) -> Dictionary:
	var table: Dictionary = migrations() if migration_table == null else migration_table
	if not data.has("save_version"):
		push_error("Сохранение без save_version")
		return {}
	var version := int(data["save_version"])
	if version > target:
		push_error("Сохранение из более новой версии игры (%d > %d)" % [version, target])
		return {}
	var result := data.duplicate(true)
	while version < target:
		if not table.has(version):
			push_error("Нет миграции сохранения с версии %d" % version)
			return {}
		var migration: Callable = table[version]
		result = migration.call(result)
		version += 1
		result["save_version"] = version
	return result


## Пишет атомарно: сначала во временный файл, потом переименовывает.
static func write_file(path: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp_path, path)


## Читает и мигрирует. Пустой словарь — файла нет или он испорчен.
static func read_file(path: String, migration_table: Variant = null, target: int = VERSION) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("Сохранение не является объектом JSON: %s" % path)
		return {}
	return migrate(json.data, migration_table, target)
