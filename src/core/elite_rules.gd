class_name EliteRules
extends RefCounted
## Элита-событие и средства против брони (задача 18): капкан, яд, бронебой. Чистые правила;
## сцена — src/world/elite_event.gd, капкан и приманка — src/world/placed_trap.gd. Данные —
## data/elite.json, патроны — data/weapons.json (ap_ammo, ap_penetration).

const REQUIRED_KEYS: PackedStringArray = ["cluster", "level", "ambush", "trap", "bait", "victim_reward"]

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func config() -> Dictionary:
	return _config


## Сколько держит капкан тварь (элита вырывается быстрее).
func trap_hold(elite: bool) -> float:
	var trap: Dictionary = _config["trap"]
	return float(trap["elite_hold_s"]) if elite else float(trap["hold_s"])


## Броня под ядом: каждая зона × armor_mult.
func poisoned_armor(armor: Dictionary, poisoned: bool) -> Dictionary:
	if not poisoned:
		return armor
	var mult := float(_config["bait"]["armor_mult"])
	var result := {}
	for zone: String in armor:
		result[zone] = float(armor[zone]) * mult
	return result


## Жива ли элита на кластере: убита в этом цикле перезагрузки — нет до следующего сброса.
static func alive(killed_at_reload: int, reloads_now: int) -> bool:
	return killed_at_reload != reloads_now


## Где ждать засаде и где лежать приманке: у дома building (Rect2), приманка — на distance к центру
## кластера, элита — за домом с другой стороны. Возвращает {"bait": Vector2, "lurk": Vector2}.
func ambush_points(building: Rect2) -> Dictionary:
	var center := building.get_center()
	var toward := (-center).normalized() if center.length() > 0.1 else Vector2(1, 0)
	var half := maxf(building.size.x, building.size.y) / 2.0
	return {"bait": center + toward * (half + float(_config["ambush"]["distance_m"])), "lurk": center - toward * (half + 1.5)}
