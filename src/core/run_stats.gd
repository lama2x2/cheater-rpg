class_name RunStats
extends RefCounted
## Статистика героя для экрана итогов: смерти с причинами, счётчики (убийства, трофеи — позже).
## Чистый класс без Node. Спецификация: docs/spec/04_death_lives.md, 4.1.

var deaths: Array[Dictionary] = []
var counters: Dictionary = {}


func record_death(life: int, cause: String, minutes: float, general_level: int) -> void:
	deaths.append({"life": life, "cause": cause, "minutes": minutes, "general_level": general_level})


func add(counter: String, amount: int = 1) -> void:
	counters[counter] = int(counters.get(counter, 0)) + amount


func count(counter: String) -> int:
	return int(counters.get(counter, 0))


## Причины смертей, от частой к редкой: [[cause, n], ...]. При равенстве — по алфавиту.
func causes_ranked() -> Array:
	var by_cause := {}
	for death in deaths:
		by_cause[death["cause"]] = int(by_cause.get(death["cause"], 0)) + 1
	var ranked: Array = []
	for cause: String in by_cause:
		ranked.append([cause, by_cause[cause]])
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	return ranked


## Самая долгая жизнь в игровых минутах (от start_minutes или от прошлой смерти).
func longest_life_minutes(start_minutes: float) -> float:
	var longest := 0.0
	var from := start_minutes
	for death in deaths:
		longest = maxf(longest, float(death["minutes"]) - from)
		from = float(death["minutes"])
	return longest


func to_dict() -> Dictionary:
	return {"deaths": deaths.duplicate(true), "counters": counters.duplicate()}


func load_dict(data: Dictionary) -> void:
	deaths.clear()
	for death: Dictionary in data.get("deaths", []):
		deaths.append({
			"life": int(death["life"]), "cause": String(death["cause"]),
			"minutes": float(death["minutes"]), "general_level": int(death["general_level"]),
		})
	counters.clear()
	var saved: Dictionary = data.get("counters", {})
	for key: String in saved:
		counters[key] = int(saved[key])
