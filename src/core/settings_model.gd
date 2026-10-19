class_name SettingsModel
extends RefCounted
## Настройки игрока: значения по умолчанию из data/settings.json, проверка сохранённых значений
## (чужое, испорченное или устаревшее заменяется умолчанием), правило ручного сохранения по режиму.
## Чистый класс без Node. Файл и применение — сервис Settings. Спецификация: 12.6a, D-30.

const REQUIRED_KEYS: PackedStringArray = ["defaults", "save_modes", "volume_step", "window_sizes", "ui_scales"]
const ANYWHERE := "anywhere"
const STAB_ONLY := "stab_only"

var values: Dictionary = {}
var _config: Dictionary


func _init(config: Dictionary) -> void:
	# JSON отдаёт числа float — размеры окна приводим к целым, чтобы сравнение работало.
	_config = config.duplicate(true)
	var sizes: Array = []
	for size: Array in config["window_sizes"]:
		sizes.append([int(size[0]), int(size[1])])
	_config["window_sizes"] = sizes
	var size_default: Array = config["defaults"]["window_size"]
	_config["defaults"]["window_size"] = [int(size_default[0]), int(size_default[1])]
	values = _config["defaults"].duplicate(true)


## Взять сохранённые значения поверх умолчаний: каждое — только если оно допустимо.
func load_saved(saved: Dictionary) -> void:
	values = _config["defaults"].duplicate(true)
	for key: String in saved:
		set_value(key, saved[key])


## Изменить настройку. false — ключ неизвестен или значение недопустимо (ничего не меняется).
func set_value(key: String, value: Variant) -> bool:
	if not values.has(key):
		return false
	var clean: Variant = _validate(key, value)
	if clean == null:
		return false
	values[key] = clean
	return true


func get_value(key: String) -> Variant:
	return values[key]


func to_dict() -> Dictionary:
	return values.duplicate(true)


## Следующий вариант по кругу (режим сохранений, размер окна) — для кнопок меню.
func next_option(key: String) -> Variant:
	var options: Array = _config[{"save_mode": "save_modes", "window_size": "window_sizes", "ui_scale": "ui_scales"}[key]]
	var index := options.find(values[key])
	return options[(index + 1) % options.size()]


func volume_step() -> float:
	return float(_config["volume_step"])


func _validate(key: String, value: Variant) -> Variant:
	match key:
		"save_mode":
			return String(value) if value is String and _config["save_modes"].has(value) else null
		"noise_ring", "fullscreen", "minimap":
			return bool(value) if value is bool else null
		"volume":
			return snappedf(clampf(float(value), 0.0, 1.0), 0.01) if value is float or value is int else null
		"ui_scale":
			if not (value is float or value is int):
				return null
			for option in _config["ui_scales"]:
				if is_equal_approx(float(option), float(value)):
					return float(option)
			return null
		"window_size":
			if not value is Array or value.size() != 2:
				return null
			var size := [int(value[0]), int(value[1])]
			return size if _config["window_sizes"].has(size) else null
	return null


## Можно ли сохраниться вручную: «где угодно» — всегда, «только в стабах» — только на безопасном
## кластере. Загрузка и автосейв от режима не зависят.
static func can_manual_save(mode: String, in_safe_cluster: bool) -> bool:
	return mode != STAB_ONLY or in_safe_cluster


## Громкость 0..1 → децибелы шины (0 — тишина).
static func volume_db(volume: float) -> float:
	return -80.0 if volume <= 0.001 else linear_to_db(volume)
