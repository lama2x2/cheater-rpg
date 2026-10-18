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
const ENEMIES_DIR := "res://data/enemies"
const TEST_AREA_PATH := "res://data/world/test_area.json"
const NOISE_PATH := "res://data/noise.json"
const WEAPONS_PATH := "res://data/weapons.json"
const COMBAT_PATH := "res://data/combat.json"

var _cache: Dictionary = {}


func stats_config() -> Dictionary:
	return _cached(STATS_PATH, StatBlock.REQUIRED_KEYS)


func rules() -> Dictionary:
	return _cached(RULES_PATH, ["lives_start", "deaths_per_region_shift", "real_seconds_per_game_day", "start_hour"])


func player_tuning() -> Dictionary:
	return _cached(PLAYER_PATH, ["walk_speed", "sprint_speed", "speed_bonus_per_level", "sprint_progress_per_meter", "gravity", "interact_radius", "sneak_speed", "sneak_visibility"])


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


func enemy_db() -> EnemyDB:
	if not _cache.has(ENEMIES_DIR):
		var files: Array = []
		for file in DirAccess.get_files_at(ENEMIES_DIR):
			if file.ends_with(".json"):
				files.append(JsonData.load_dict(ENEMIES_DIR.path_join(file)))
		var db := EnemyDB.new(files)
		for error in db.errors():
			push_error("data/enemies: " + error)
		_cache[ENEMIES_DIR] = db
	return _cache[ENEMIES_DIR]


func enemy_name(id: String) -> String:
	return String(texts()["enemy_names"].get(id, id))


func weapon_db() -> WeaponDB:
	if not _cache.has(WEAPONS_PATH):
		_cache[WEAPONS_PATH] = WeaponDB.new(JsonData.load_dict(WEAPONS_PATH, WeaponDB.REQUIRED_KEYS))
	return _cache[WEAPONS_PATH]


func combat_config() -> Dictionary:
	return _cached(COMBAT_PATH, DamageModel.REQUIRED_KEYS)


func noise_config() -> Dictionary:
	return _cached(NOISE_PATH, NoiseModel.REQUIRED_KEYS)


func test_area() -> Dictionary:
	return _cached(TEST_AREA_PATH, ["items", "house", "infected_seed", "infected"])


func recipes() -> Array:
	return _cached(RECIPES_PATH, Crafting.REQUIRED_KEYS)["recipes"]


func item_name(id: String) -> String:
	return String(texts()["item_names"].get(id, id))


func texts() -> Dictionary:
	return _cached(TEXTS_PATH, ["stat_names", "item_names", "enemy_names", "log", "ui", "death_causes", "death_advice", "epitaphs"])


## Строка интерфейса по ключу (texts.ui), с подстановкой параметров.
func ui(key: String, params: Dictionary = {}) -> String:
	return String(texts()["ui"].get(key, key)).format(params)


## Причина смерти для экрана и лога: особые причины — из death_causes, твари — «растерзан: медляк».
func death_cause(cause: String) -> String:
	var causes: Dictionary = texts()["death_causes"]
	if causes.has(cause):
		return String(causes[cause])
	if texts()["enemy_names"].has(cause):
		return ui("killed_by", {"enemy": enemy_name(cause)})
	return cause


func stat_name(stat: String) -> String:
	return texts()["stat_names"].get(stat, stat)


func _cached(path: String, required: PackedStringArray) -> Dictionary:
	if not _cache.has(path):
		_cache[path] = JsonData.load_dict(path, required)
	return _cache[path]
