class_name ProgressRules
extends RefCounted
## Прокачка действием: сколько очков прогресса и какой характеристике даёт действие, с убывающей
## отдачей за повторение внутри игрового часа (D-09) и поправкой на уровень цели.
## Чистый класс без Node. Спецификация: docs/spec/03_character.md, 3.2.

const REQUIRED_KEYS: PackedStringArray = [
	"actions", "target_level", "hard_shot_distance", "sneak_pass", "farm_warning_below",
]

## Номер игрового часа, к которому относятся счётчики.
var hour: int = -1
## Сколько «сырых» очков действие уже дало в этом часе: {"melee_hit": 7.2}.
var gained: Dictionary = {}

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func has_action(action: String) -> bool:
	return _config["actions"].has(action)


func stat_for(action: String) -> String:
	return String(_config["actions"][action]["stat"])


## Множитель за уровень цели: слабая — меньше, много сильнее — больше.
func target_multiplier(hero_level: int, target_level: int) -> float:
	var t: Dictionary = _config["target_level"]
	if target_level >= hero_level + int(t["strong_above"]):
		return float(t["strong_mult"])
	var below := (hero_level - int(t["grace"])) - target_level
	if below <= 0:
		return 1.0
	return maxf(float(t["min_mult"]), 1.0 - float(t["penalty_per_level"]) * below)


## Очки за amount единиц действия в игровую минуту now.
## context: {"hero_level": int, "target_level": int} — если цель есть.
## Результат: {"stat", "points", "farm_mult", "target_mult"}.
func award(action: String, amount: float, now: float, context: Dictionary = {}) -> Dictionary:
	var a: Dictionary = _config["actions"][action]
	var current_hour := floori(now / 60.0)
	if current_hour != hour:
		hour = current_hour
		gained.clear()
	var raw := float(a["points"]) * amount
	var cap := float(a["farm_cap"])
	var before := float(gained.get(action, 0.0))
	gained[action] = before + raw
	var effective := _diminished(before, before + raw, cap)
	var target_mult := 1.0
	if context.has("target_level"):
		target_mult = target_multiplier(int(context["hero_level"]), int(context["target_level"]))
	return {
		"stat": String(a["stat"]), "points": effective * target_mult,
		"farm_mult": effective / raw if raw > 0.0 else 1.0, "target_mult": target_mult,
	}


## Текущая отдача действия (для предупреждения «однообразие утомляет»).
func farm_multiplier(action: String) -> float:
	var cap := float(_config["actions"][action]["farm_cap"])
	return 1.0 / (1.0 + maxf(0.0, float(gained.get(action, 0.0)) - cap) / cap)


func to_dict() -> Dictionary:
	return {"hour": hour, "gained": gained.duplicate()}


func load_dict(data: Dictionary) -> void:
	hour = int(data.get("hour", -1))
	gained.clear()
	var saved: Dictionary = data.get("gained", {})
	for action: String in saved:
		gained[action] = float(saved[action])


## Интеграл отдачи на отрезке [from, to] сырых очков: до cap — 1, дальше 1/(1 + (x − cap)/cap).
func _diminished(from: float, to: float, cap: float) -> float:
	var full := maxf(0.0, minf(to, cap) - from)
	var over_from := maxf(from, cap) - cap
	var over_to := maxf(to, cap) - cap
	var reduced := cap * (log(1.0 + over_to / cap) - log(1.0 + over_from / cap))
	return full + reduced
