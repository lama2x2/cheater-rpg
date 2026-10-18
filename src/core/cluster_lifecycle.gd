class_name ClusterLifecycle
extends RefCounted
## Таймеры перезагрузки кластеров: собственный период кластера, разброс каждого интервала, окно
## кисляка перед сбросом, догон сбросов, пропущенных за прокрутку времени (сон, смерть).
## Чистые правила без Node. Числа — data/world/cluster_types.json.
## Спецификация: docs/spec/02_world.md («Типы кластеров», «Жизненный цикл»), D-56.
##
## Таймер кластера — словарь (так он и сохраняется):
##   {"period_h": float, "jitter": float, "next": минуты мира | -1 (никогда), "kislyak_min": float}

const CALM := "calm"
const KISLYAK := "kislyak"
const NEVER := "never"


## Новый таймер для типа кластера. elapsed_fraction — какая доля первого интервала уже прошла
## (0 — кластер только что перезагрузился). Не перезагружается — next = -1.
static func new_timer(type_config: Dictionary, now: float, rng: RandomNumberGenerator, elapsed_fraction: float = 0.0) -> Dictionary:
	if not bool(type_config["reloads"]):
		return {"period_h": 0.0, "jitter": 0.0, "next": -1.0, "kislyak_min": 0.0}
	var period := rng.randf_range(float(type_config["period_h"][0]), float(type_config["period_h"][1]))
	var timer := {"period_h": period, "jitter": float(type_config["jitter"]), "next": 0.0, "kislyak_min": 0.0}
	timer["next"] = now + interval_minutes(timer, rng) * (1.0 - clampf(elapsed_fraction, 0.0, 1.0))
	timer["kislyak_min"] = roll_kislyak(type_config, rng)
	return timer


## Следующий интервал: период ± jitter (игровые минуты).
static func interval_minutes(timer: Dictionary, rng: RandomNumberGenerator) -> float:
	var jitter := float(timer["jitter"])
	return float(timer["period_h"]) * 60.0 * (1.0 + rng.randf_range(-jitter, jitter))


static func roll_kislyak(type_config: Dictionary, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(float(type_config["kislyak_min"][0]), float(type_config["kislyak_min"][1]))


static func reloads(timer: Dictionary) -> bool:
	return float(timer["next"]) >= 0.0


## Фаза кластера в момент now: спокойно, кисляк (туман перед сбросом) или «никогда» (стаб).
static func phase(timer: Dictionary, now: float) -> String:
	if not reloads(timer):
		return NEVER
	return KISLYAK if now >= float(timer["next"]) - float(timer["kislyak_min"]) else CALM


## Сбросы, наступившие к моменту now: список их моментов (обычно 0 или 1; после долгой прокрутки
## у быстрого кластера — несколько). Таймер переводится на следующий сброс, кисляк бросается заново.
static func take_due(timer: Dictionary, now: float, type_config: Dictionary, rng: RandomNumberGenerator) -> Array[float]:
	var due: Array[float] = []
	if not reloads(timer):
		return due
	while float(timer["next"]) <= now:
		due.append(float(timer["next"]))
		timer["next"] = float(timer["next"]) + interval_minutes(timer, rng)
		timer["kislyak_min"] = roll_kislyak(type_config, rng)
	return due


static func minutes_left(timer: Dictionary, now: float) -> float:
	return maxf(0.0, float(timer["next"]) - now) if reloads(timer) else INF


## Таймер для интерфейса: «??:??» — неизвестен, «—» — не перезагружается, иначе ЧЧ:ММ игрового времени.
static func timer_text(timer: Dictionary, now: float, known: bool) -> String:
	if not reloads(timer):
		return "—"
	if not known:
		return "??:??"
	var left := floori(minutes_left(timer, now))
	return "%02d:%02d" % [floori(left / 60.0), left % 60]


## Сид прилёта: зависит от сида мира, кластера и номера перезагрузки — мир воспроизводим.
static func reload_seed(world_seed: int, cluster_id: String, reload_index: int) -> int:
	return hash([world_seed, cluster_id, reload_index])
