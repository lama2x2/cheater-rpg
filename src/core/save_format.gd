class_name SaveFormat
extends RefCounted
## Формат файла сохранения: конверт с версией, цепочка миграций, чтение и запись JSON.
## Чистые правила без Node — тестируются headless. Спецификация: docs/spec/13_tech.md, 13.5.
##
## Файл: {"save_version": N, "saved_at": unix, "sections": {"clock": {...}, "player": {...}, ...}}
## Миграция — функция (data: Dictionary) -> Dictionary, переводит версию K в K+1.

const VERSION := 1

## Миграции по исходной версии: {K: Callable}. Пока пусто — формат v1 первый.
const MIGRATIONS := {}


static func wrap(sections: Dictionary, saved_at: float) -> Dictionary:
	return {"save_version": VERSION, "saved_at": saved_at, "sections": sections}


## Доводит данные до текущей версии. Возвращает {} и пишет ошибку, если это невозможно.
static func migrate(data: Dictionary, migrations: Dictionary = MIGRATIONS, target: int = VERSION) -> Dictionary:
	if not data.has("save_version"):
		push_error("Сохранение без save_version")
		return {}
	var version := int(data["save_version"])
	if version > target:
		push_error("Сохранение из более новой версии игры (%d > %d)" % [version, target])
		return {}
	var result := data.duplicate(true)
	while version < target:
		if not migrations.has(version):
			push_error("Нет миграции сохранения с версии %d" % version)
			return {}
		var migration: Callable = migrations[version]
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
static func read_file(path: String, migrations: Dictionary = MIGRATIONS, target: int = VERSION) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("Сохранение не является объектом JSON: %s" % path)
		return {}
	return migrate(json.data, migrations, target)
