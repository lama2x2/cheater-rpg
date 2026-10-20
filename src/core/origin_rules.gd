class_name OriginRules
extends RefCounted
## Происхождение героя (16, D-66): Читер — с вариантом форс-мажора (куш и долг) и скрытым
## свойством «Читер», или Обычный. Окно новичка (D-67) — правило мира для всех. «Читер позже»
## (D-68) — после нескольких «невозможных» событий. Чистые правила; состояние — PlayerState.
## Данные — data/origins.json.

const REQUIRED_KEYS: PackedStringArray = ["newbie_window_h", "secret_chance", "cheater", "later_events", "later_kinds", "variants"]
const CHEATER := "cheater"
const ORDINARY := "ordinary"
const RANDOM := "random"

var _config: Dictionary
var _by_id: Dictionary = {}


func _init(config: Dictionary) -> void:
	_config = config
	for v: Dictionary in config["variants"]:
		_by_id[String(v["id"])] = v


func config() -> Dictionary:
	return _config


func has_variant(id: String) -> bool:
	return _by_id.has(id)


func variant(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Карточки экрана новой игры: доступные в этой версии и не секретные.
func cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for v: Dictionary in _config["variants"]:
		if bool(v.get("available", true)) and not bool(v.get("secret", false)):
			result.append(v)
	return result


## «Случайно»: равновероятно из карточек, секретный — с шансом secret_chance.
func roll(rng: RandomNumberGenerator) -> String:
	for v: Dictionary in _config["variants"]:
		if bool(v.get("secret", false)) and bool(v.get("available", true)) and rng.randf() < float(_config["secret_chance"]):
			return String(v["id"])
	var list := cards()
	return String(list[rng.randi_range(0, list.size() - 1)]["id"])


## Какой вариант выдать: выбранный (если он есть и доступен) или случайный.
func resolve_choice(choice: String, rng: RandomNumberGenerator) -> String:
	if choice != RANDOM and _by_id.has(choice) and bool(_by_id[choice].get("available", true)):
		return choice
	return roll(rng)


func grants(id: String) -> Array:
	return variant(id).get("grants", [])


func debts(id: String) -> PackedStringArray:
	return PackedStringArray(variant(id).get("debt", []))


## Конец окна новичка в игровых минутах от начала игры.
func newbie_until(start_minutes: float) -> float:
	return start_minutes + float(_config["newbie_window_h"]) * 60.0


## Окно новичка открыто: время не вышло и крестин ещё не было.
static func newbie_active(now: float, until: float, christened: bool = false) -> bool:
	return now < until and not christened


## «Читер позже»: событие засчитано? kind — из later_kinds. Возвращает true, если свойство
## «Читер» теперь включается (событий набралось later_events).
func counts_for_later(kind: String) -> bool:
	return (_config["later_kinds"] as Array).has(kind)


func later_reached(events: int) -> bool:
	return events >= int(_config["later_events"])
