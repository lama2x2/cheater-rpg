class_name StabRules
extends RefCounted
## Услуги стаба без торговли: цена лечения у знахаря, дары уровней (умение на 10/30/60 — 05),
## сон в баре (что станет со шкалами), слухи о таймерах кластеров.
## Чистые правила без Node. Числа — data/stab.json (healer, bar). Спецификация: 10.1, 05.


## Цена лечения: недостающее здоровье по heal_per_spore за споран (вверх) + кровотечение.
static func heal_cost(missing_health: float, bleeding: bool, healer: Dictionary) -> int:
	var cost := ceili(maxf(0.0, missing_health) / float(healer["heal_per_spore"]))
	if bleeding:
		cost += int(healer["bleed_price"])
	return cost


## Следующий дар уровня, который можно открыть сейчас (-1 — нет): уровень достигнут, дар не открыт.
static func next_gift(general_level: int, opened: Array, healer: Dictionary) -> int:
	for level in healer["gift_levels"]:
		if general_level >= int(level) and not opened.has(int(level)):
			return int(level)
	return -1


static func gift_price(healer: Dictionary, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(int(healer["gift_price"][0]), int(healer["gift_price"][1]))


## Сколько спорового баланса останется после сна (тот же расход, что и наяву: decay_per_game_hour).
static func spore_after_sleep(spore_now: float, decay_per_hour: float, bar: Dictionary) -> float:
	return spore_now - decay_per_hour * float(bar["sleep_hours"])


static func can_sleep(spore_now: float, decay_per_hour: float, bar: Dictionary) -> bool:
	return spore_after_sleep(spore_now, decay_per_hour, bar) >= float(bar["sleep_min_spore"])


## Слух: случайный кластер, чей таймер герою ещё не известен (и который вообще перезагружается).
## candidates — id таких кластеров. "" — слухов нет.
static func rumor_target(candidates: PackedStringArray, rng: RandomNumberGenerator) -> String:
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]
