class_name DeathRules
extends RefCounted
## Правила смерти и возрождения: длительность «Жизнь N закончилась», сколько часов проходит в мире,
## когда пора менять регион, какие строки лога попадут в итоги.
## Чистые правила без Node. Спецификация: docs/spec/04_death_lives.md.

const REQUIRED_KEYS: PackedStringArray = [
	"respawn_seconds_min", "respawn_seconds_max", "debug_respawn_seconds",
	"respawn_game_hours_min", "respawn_game_hours_max", "highlight_kinds", "summary_highlights",
]


## Реальные секунды экрана возрождения: 100–180 с, в отладке — коротко.
static func respawn_seconds(config: Dictionary, rng: RandomNumberGenerator, fast: bool = false) -> float:
	if fast:
		return float(config["debug_respawn_seconds"])
	return rng.randf_range(float(config["respawn_seconds_min"]), float(config["respawn_seconds_max"]))


## Сколько игровых минут проходит в мире, пока герой возрождается.
static func game_minutes_away(config: Dictionary, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(float(config["respawn_game_hours_min"]), float(config["respawn_game_hours_max"])) * 60.0


## Смена региона после каждых N смертей (D-03). deaths_since_shift — уже с учётом этой смерти.
static func region_shift_due(deaths_since_shift: int, deaths_per_shift: int) -> bool:
	return deaths_per_shift > 0 and deaths_since_shift >= deaths_per_shift


## Лучшие строки для итогов: по приоритету вида (раньше в highlight_kinds — важнее),
## внутри вида — свежие первыми, без повторов текста. Порог count — из summary_highlights.
static func pick_highlights(entries: Array, config: Dictionary) -> PackedStringArray:
	var kinds: Array = config["highlight_kinds"]
	var count := int(config["summary_highlights"])
	var result: PackedStringArray = []
	for kind in kinds:
		for i in range(entries.size() - 1, -1, -1):
			var entry: Dictionary = entries[i]
			if entry["kind"] != kind or result.has(entry["text"]):
				continue
			result.append(entry["text"])
			if result.size() >= count:
				return result
	return result
