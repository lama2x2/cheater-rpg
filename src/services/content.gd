extends Node
## Загрузка игровых данных из data/. Файлы читаются лениво при первом обращении.

const STATS_PATH := "res://data/stats.json"
const RULES_PATH := "res://data/rules.json"
const PLAYER_PATH := "res://data/player.json"
const TEXTS_PATH := "res://data/text/ru.json"
const VITALS_PATH := "res://data/vitals.json"
const DEATH_PATH := "res://data/death.json"
const INVENTORY_PATH := "res://data/inventory.json"
const ITEMS_DIR := "res://data/items"
const RECIPES_PATH := "res://data/recipes.json"

var _cache: Dictionary = {}


func stats_config() -> Dictionary:
	return _cached(STATS_PATH, StatBlock.REQUIRED_KEYS)


func rules() -> Dictionary:
	return _cached(RULES_PATH, ["lives_start", "deaths_per_region_shift", "real_seconds_per_game_day", "start_hour"])


func player_tuning() -> Dictionary:
	return _cached(PLAYER_PATH, ["walk_speed", "sprint_speed", "speed_bonus_per_level", "sprint_progress_per_meter", "gravity", "interact_radius"])


func vitals_config() -> Dictionary:
	return _cached(VITALS_PATH, Vitals.REQUIRED_KEYS)


func death_config() -> Dictionary:
	return _cached(DEATH_PATH, DeathRules.REQUIRED_KEYS)


func inventory_config() -> Dictionary:
	return _cached(INVENTORY_PATH, Inventory.REQUIRED_KEYS)


## Справочник предметов из всех data/items/*.json.
func item_db() -> ItemDB:
	if not _cache.has(ITEMS_DIR):
		var files: Array = []
		for file in DirAccess.get_files_at(ITEMS_DIR):
			if file.ends_with(".json"):
				files.append(JsonData.load_dict(ITEMS_DIR.path_join(file)))
		var db := ItemDB.new(files)
		for error in db.errors():
			push_error("data/items: " + error)
		_cache[ITEMS_DIR] = db
	return _cache[ITEMS_DIR]


func recipes() -> Array:
	return _cached(RECIPES_PATH, Crafting.REQUIRED_KEYS)["recipes"]


func item_name(id: String) -> String:
	return String(texts()["item_names"].get(id, id))


func texts() -> Dictionary:
	return _cached(TEXTS_PATH, ["stat_names", "item_names", "log", "ui", "death_causes", "death_advice", "epitaphs"])


## Строка интерфейса по ключу (texts.ui), с подстановкой параметров.
func ui(key: String, params: Dictionary = {}) -> String:
	return String(texts()["ui"].get(key, key)).format(params)


func death_cause(cause: String) -> String:
	return String(texts()["death_causes"].get(cause, cause))


func stat_name(stat: String) -> String:
	return texts()["stat_names"].get(stat, stat)


func _cached(path: String, required: PackedStringArray) -> Dictionary:
	if not _cache.has(path):
		_cache[path] = JsonData.load_dict(path, required)
	return _cache[path]
