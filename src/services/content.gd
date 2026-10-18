extends Node
## Загрузка игровых данных из data/. Файлы читаются лениво при первом обращении.

const STATS_PATH := "res://data/stats.json"
const RULES_PATH := "res://data/rules.json"
const PLAYER_PATH := "res://data/player.json"
const TEXTS_PATH := "res://data/text/ru.json"

var _cache: Dictionary = {}


func stats_config() -> Dictionary:
	return _cached(STATS_PATH, StatBlock.REQUIRED_KEYS)


func rules() -> Dictionary:
	return _cached(RULES_PATH, ["lives_start", "deaths_per_region_shift", "real_seconds_per_game_day", "start_hour"])


func player_tuning() -> Dictionary:
	return _cached(PLAYER_PATH, ["walk_speed", "sprint_speed", "speed_bonus_per_level", "sprint_progress_per_meter", "gravity"])


func texts() -> Dictionary:
	return _cached(TEXTS_PATH, ["stat_names", "log"])


func stat_name(stat: String) -> String:
	return texts()["stat_names"].get(stat, stat)


func _cached(path: String, required: PackedStringArray) -> Dictionary:
	if not _cache.has(path):
		_cache[path] = JsonData.load_dict(path, required)
	return _cache[path]
