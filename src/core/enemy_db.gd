class_name EnemyDB
extends RefCounted
## Справочник тварей из data/enemies/*.json. Чистый класс без Node. Схема — 14.2.

const REQUIRED_KEYS: PackedStringArray = [
	"id", "stage", "level", "body", "hp", "hp_per_level", "move", "attack", "senses", "can_open_doors", "ai",
]

var _enemies: Dictionary = {}


func _init(files: Array = []) -> void:
	for file: Dictionary in files:
		for enemy: Dictionary in file.get("enemies", []):
			_enemies[String(enemy.get("id", ""))] = enemy


func errors() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in _enemies:
		for key in REQUIRED_KEYS:
			if not _enemies[id].has(key):
				result.append("%s: нет ключа «%s»" % [id, key])
	return result


func ids() -> PackedStringArray:
	return PackedStringArray(_enemies.keys())


func has_enemy(id: String) -> bool:
	return _enemies.has(id)


func enemy(id: String) -> Dictionary:
	assert(_enemies.has(id), "Неизвестная тварь: %s" % id)
	return _enemies[id]


## Уровень конкретной особи — случайно в диапазоне стадии.
func roll_level(id: String, rng: RandomNumberGenerator) -> int:
	var range_: Array = enemy(id)["level"]
	return rng.randi_range(int(range_[0]), int(range_[1]))


## Здоровье растёт с уровнем внутри стадии.
func max_hp(id: String, level: int) -> float:
	var e := enemy(id)
	return float(e["hp"]) + float(e["hp_per_level"]) * (level - int(e["level"][0]))
