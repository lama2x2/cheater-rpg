class_name LuckModel
extends RefCounted
## Удача во всём (D-76): шанс случайности в пользу героя с насыщением p = cap × L / (L + k).
## Чистый класс без Node. Данные — data/luck.json. Спецификация: docs/spec/03_character.md «Удача».

const REQUIRED_KEYS: PackedStringArray = ["events", "quiet_mult", "quiet_sources", "stumble_s", "unnoticed_s", "unnoticed_retry_s", "log_throttle_s"]

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func has_event(kind: String) -> bool:
	return _config["events"].has(kind)


## Шанс события kind при итоговой Удаче luck. double_roll — бросок дважды, берётся лучший.
func chance(kind: String, luck: float, double_roll: bool = false) -> float:
	var e: Dictionary = _config["events"][kind]
	var l := maxf(0.0, luck)
	var p := float(e["cap"]) * l / (l + float(e["k"])) if l > 0.0 else 0.0
	return 1.0 - (1.0 - p) * (1.0 - p) if double_roll else p


func roll(kind: String, luck: float, rng: RandomNumberGenerator, double_roll: bool = false) -> bool:
	return rng.randf() < chance(kind, luck, double_roll)


func config() -> Dictionary:
	return _config


## Множитель шанса лута с тем же насыщением: 1 + (cap − 1) × L / (L + k). scaling — luck_scaling
## таблицы лута ({"cap", "k"}).
static func saturating_mult(scaling: Dictionary, luck: float) -> float:
	var l := maxf(0.0, luck)
	if l <= 0.0:
		return 1.0
	return 1.0 + (float(scaling["cap"]) - 1.0) * l / (l + float(scaling["k"]))
