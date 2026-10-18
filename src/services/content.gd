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
const REGION_PATH := "res://data/world/region.json"
const CLUSTER_TYPES_PATH := "res://data/world/cluster_types.json"
const POPULATION_PATH := "res://data/world/population.json"
const TEMPLATES_DIR := "res://data/world/templates"
const NOISE_PATH := "res://data/noise.json"
const WEAPONS_PATH := "res://data/weapons.json"
const COMBAT_PATH := "res://data/combat.json"
const LOOT_DIR := "res://data/loot"
const PROGRESS_PATH := "res://data/progress.json"
const STAB_PATH := "res://data/stab.json"
const SETTINGS_PATH := "res://data/settings.json"
const SKILL_RULES_PATH := "res://data/skill_rules.json"
const SKILLS_DIR := "res://data/skills"
const LUCK_PATH := "res://data/luck.json"
const TEXTS_DIR := "res://data/text"

var _cache: Dictionary = {}


func stats_config() -> Dictionary:
	return _cached(STATS_PATH, StatBlock.REQUIRED_KEYS)


func rules() -> Dictionary:
	return _cached(RULES_PATH, ["lives_start", "deaths_per_region_shift", "real_seconds_per_game_day", "start_hour", "ng_plus", "save_slots"])


func player_tuning() -> Dictionary:
	return _cached(PLAYER_PATH, ["walk_speed", "sprint_speed", "speed_bonus_per_level", "gravity", "interact_radius", "sneak_speed", "sneak_visibility"])


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


func loot() -> LootTable:
	if not _cache.has(LOOT_DIR):
		var files: Array = []
		for file in DirAccess.get_files_at(LOOT_DIR):
			if file.ends_with(".json"):
				files.append(JsonData.load_dict(LOOT_DIR.path_join(file), LootTable.REQUIRED_KEYS))
		_cache[LOOT_DIR] = LootTable.new(files)
	return _cache[LOOT_DIR]


func skill_rules_config() -> Dictionary:
	return _cached(SKILL_RULES_PATH, SkillRules.REQUIRED_KEYS)


## Описания умений из всех data/skills/*.json (схема 14.5).
func skill_defs() -> Array:
	if not _cache.has(SKILLS_DIR):
		var defs: Array = []
		for file in DirAccess.get_files_at(SKILLS_DIR):
			if file.ends_with(".json"):
				defs.append(JsonData.load_dict(SKILLS_DIR.path_join(file), ["id", "slot", "effects"]))
		_cache[SKILLS_DIR] = defs
	return _cache[SKILLS_DIR]


func luck_model() -> LuckModel:
	if not _cache.has(LUCK_PATH):
		_cache[LUCK_PATH] = LuckModel.new(JsonData.load_dict(LUCK_PATH, LuckModel.REQUIRED_KEYS))
	return _cache[LUCK_PATH]


func skill_name(id: String) -> String:
	return String(texts()["skill_names"].get(id, id))


func settings_config() -> Dictionary:
	return _cached(SETTINGS_PATH, SettingsModel.REQUIRED_KEYS)


func stab_config() -> Dictionary:
	return _cached(STAB_PATH, ["cluster", "npcs", "trade", "healer", "bar", "board"])


func progress_config() -> Dictionary:
	return _cached(PROGRESS_PATH, ProgressRules.REQUIRED_KEYS)


func combat_config() -> Dictionary:
	return _cached(COMBAT_PATH, DamageModel.REQUIRED_KEYS)


func noise_config() -> Dictionary:
	return _cached(NOISE_PATH, NoiseModel.REQUIRED_KEYS)


## Регион (граф кластеров). Ошибки графа — в лог движка при первой загрузке.
func region() -> RegionMap:
	if not _cache.has(REGION_PATH):
		var map := RegionMap.new(JsonData.load_dict(REGION_PATH, RegionMap.REQUIRED_KEYS))
		for error in map.errors(PackedStringArray(templates().keys()), PackedStringArray(cluster_types()["types"].keys())):
			push_error("data/world/region.json: " + error)
		_cache[REGION_PATH] = map
	return _cache[REGION_PATH]


func cluster_types() -> Dictionary:
	return _cached(CLUSTER_TYPES_PATH, ["types", "fog", "travel_fade_s", "stash_reveal"])


func cluster_type(type_id: String) -> Dictionary:
	return cluster_types()["types"][type_id]


func population_model() -> PopulationModel:
	if not _cache.has(POPULATION_PATH):
		_cache[POPULATION_PATH] = PopulationModel.new(JsonData.load_dict(POPULATION_PATH, PopulationModel.REQUIRED_KEYS))
	return _cache[POPULATION_PATH]


## Шаблоны кластеров из data/world/templates/*.json по id.
func templates() -> Dictionary:
	if not _cache.has(TEMPLATES_DIR):
		var result := {}
		for file in DirAccess.get_files_at(TEMPLATES_DIR):
			if file.ends_with(".json"):
				var template := JsonData.load_dict(TEMPLATES_DIR.path_join(file), ClusterLayout.REQUIRED_KEYS)
				result[String(template["id"])] = template
		_cache[TEMPLATES_DIR] = result
	return _cache[TEMPLATES_DIR]


func template(id: String) -> Dictionary:
	return templates()[id]


func recipes() -> Array:
	return _cached(RECIPES_PATH, Crafting.REQUIRED_KEYS)["recipes"]


func item_name(id: String) -> String:
	return String(texts()["item_names"].get(id, id))


## Тексты: data/text/ru.json + дополнения data/text/ru_*.json (разделы сливаются по ключам —
## так тексты умений живут отдельно от общего файла).
func texts() -> Dictionary:
	if not _cache.has(TEXTS_PATH):
		var texts := JsonData.load_dict(TEXTS_PATH, ["stat_names", "item_names", "enemy_names", "log", "ui", "death_causes", "death_advice", "epitaphs"])
		for file in DirAccess.get_files_at(TEXTS_DIR):
			if file.begins_with("ru_") and file.ends_with(".json"):
				var extra := JsonData.load_dict(TEXTS_DIR.path_join(file))
				for section: String in extra:
					if extra[section] is Dictionary:
						if not texts.has(section):
							texts[section] = {}
						texts[section].merge(extra[section], true)
		_cache[TEXTS_PATH] = texts
	return _cache[TEXTS_PATH]


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
