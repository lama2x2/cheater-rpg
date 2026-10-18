class_name PopulationModel
extends RefCounted
## Абстрактная популяция кластера: люди после прилёта, заражённые по стадиям, еда, нетронутый лут.
## Тик — игровой час: люди обращаются, твари едят, голодают, едят друг друга и эволюционируют.
## Итог по книгам: свежий кластер — толпы медляков, поздний — мало тварей, но старших стадий.
## Чистый класс без Node. Числа — data/world/population.json, профили — шаблоны кластеров.
## Спецификация: docs/spec/02_world.md («Жизненный цикл»), 13.3 («Абстрактный» уровень).
##
## Состояние — словарь (так оно и сохраняется):
##   {"civilians": float, "infected": {"slowpoke": float, ...}, "food": float, "loot": 0..1, "immune": int}

const REQUIRED_KEYS: PackedStringArray = [
	"stages", "infect_per_h", "appetite", "body_food", "starve_per_h", "predator_starve_per_h", "evolve_per_h",
	"crawler_death_per_h", "loot_decay_per_h", "warmup_max_h",
]
## С какой стадии твари едят младших (прыгун и старше).
const PREDATOR_FROM := 2

var stages: PackedStringArray
var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config
	stages = PackedStringArray(config["stages"])


## Сколько часов максимум просчитывать при создании мира (прогрев кластеров со случайной фазой).
func warmup_hours() -> int:
	return int(_config["warmup_max_h"])


## Пустой кластер: ни людей, ни тварей, лут нетронут.
func empty_state() -> Dictionary:
	var infected := {}
	for stage in stages:
		infected[stage] = 0.0
	return {"civilians": 0.0, "infected": infected, "food": 0.0, "loot": 1.0, "immune": 0}


## Прилёт (перезагрузка): свежая копия. profile — "population" из шаблона; {} — кластер без жизни.
func arrival(profile: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var state := empty_state()
	if profile.is_empty():
		return state
	var people := float(rng.randi_range(int(profile["civilians"][0]), int(profile["civilians"][1])))
	var immune := roundi(people * float(profile["immune_chance"]) * rng.randf_range(0.5, 1.5))
	people -= immune
	var turned := people * float(profile["infected_on_arrival"])
	state["civilians"] = people - turned
	state["infected"]["slowpoke"] = turned
	state["food"] = people * float(profile["food_per_civilian"])
	state["immune"] = immune
	return state


## Один игровой час. Меняет state на месте. Возвращает, сколько людей обратилось за час.
func tick_hour(state: Dictionary) -> float:
	var infected: Dictionary = state["infected"]
	var turned := float(state["civilians"]) * float(_config["infect_per_h"])
	state["civilians"] = float(state["civilians"]) - turned
	infected["slowpoke"] = float(infected["slowpoke"]) + turned

	var appetite: Dictionary = _config["appetite"]
	var demand := 0.0
	for stage in stages:
		demand += float(infected[stage]) * float(appetite[stage])
	var fed := 1.0 if demand <= 0.0 else minf(1.0, float(state["food"]) / demand)
	state["food"] = maxf(0.0, float(state["food"]) - demand * fed)
	var hunger := 1.0 - fed

	# Голодные старшие едят младших: сначала ползунов, потом медляков.
	var predator_fed := fed
	if hunger > 0.0:
		var need := 0.0
		for i in range(PREDATOR_FROM, stages.size()):
			need += float(infected[stages[i]]) * float(appetite[stages[i]]) * hunger
		if need > 0.0:
			var bodies := need / float(_config["body_food"])
			var eaten := _eat_lowest(infected, bodies)
			predator_fed = fed + hunger * (eaten / bodies)

	# Несытые старшие гибнут — и сами становятся едой.
	for i in range(PREDATOR_FROM, stages.size()):
		var died := float(infected[stages[i]]) * float(_config["predator_starve_per_h"]) * (1.0 - predator_fed)
		infected[stages[i]] = float(infected[stages[i]]) - died
		state["food"] = float(state["food"]) + died * float(_config["body_food"])

	var starving := float(infected["slowpoke"]) * float(_config["starve_per_h"]) * hunger
	infected["slowpoke"] = float(infected["slowpoke"]) - starving
	infected[stages[0]] = float(infected[stages[0]]) + starving

	# Эволюция сытых — сверху вниз, чтобы за час никто не прыгнул через стадию.
	var evolve: Dictionary = _config["evolve_per_h"]
	for i in range(stages.size() - 2, 0, -1):
		var stage := stages[i]
		var up := float(infected[stage]) * float(evolve.get(stage, 0.0)) * (predator_fed if i >= PREDATOR_FROM else fed)
		infected[stage] = float(infected[stage]) - up
		infected[stages[i + 1]] = float(infected[stages[i + 1]]) + up

	infected[stages[0]] = float(infected[stages[0]]) * (1.0 - float(_config["crawler_death_per_h"]))
	state["loot"] = float(state["loot"]) * (1.0 - float(_config["loot_decay_per_h"]))
	return turned


## Несколько часов подряд. Возвращает, сколько людей обратилось.
func advance(state: Dictionary, hours: int) -> float:
	var turned := 0.0
	for i in hours:
		turned += tick_hour(state)
	return turned


func total_infected(state: Dictionary) -> float:
	var total := 0.0
	for stage in stages:
		total += float(state["infected"][stage])
	return total


## Сколько агентов на сцене приходится на единицу популяции: ratio из шаблона, но не больше cap всего.
func effective_ratio(state: Dictionary, ratio: float, cap: int) -> float:
	var total := total_infected(state)
	if total * ratio > cap and total > 0.0:
		return float(cap) / total
	return ratio


## Агенты для сцены по стадиям: {"slowpoke": 12, ...}. Округление с переносом остатка, чтобы
## сумма совпала с округлённым итогом (мелкие стадии не пропадают целиком без причины).
func agents(state: Dictionary, ratio: float) -> Dictionary:
	var result := {}
	var carry := 0.0
	for i in range(stages.size() - 1, -1, -1):
		var exact := float(state["infected"][stages[i]]) * ratio + carry
		var count := maxi(0, roundi(exact))
		carry = exact - count
		if count > 0:
			result[stages[i]] = count
	return result


## Убрать units тварей стадии (убиты героем на сцене: 1 агент = 1 / ratio единиц).
func remove(state: Dictionary, stage: String, units: float) -> void:
	if state["infected"].has(stage):
		state["infected"][stage] = maxf(0.0, float(state["infected"][stage]) - units)


func _eat_lowest(infected: Dictionary, bodies: float) -> float:
	var eaten := 0.0
	for i in PREDATOR_FROM:
		var take := minf(float(infected[stages[i]]), bodies - eaten)
		infected[stages[i]] = float(infected[stages[i]]) - take
		eaten += take
		if eaten >= bodies:
			break
	return eaten
