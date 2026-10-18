class_name Vitals
extends RefCounted
## Шкалы героя: здоровье, бодрость, споровый баланс, мана.
## Чистые правила без Node — тестируются headless. Спецификация: docs/spec/03_character.md, 3.3.
## Бодрость живёт в реальных секундах (спринт), остальное — в игровых минутах.

## Шкала дошла до нуля: "health" или "spore_balance" — смерть, "stamina" — выдохся.
signal depleted(vital: String)
## Споровый баланс перешёл порог: "ok", "low" (< penalty_below), "critical" (< critical_below).
signal spore_state_changed(state: String)

const HEALTH := "health"
const STAMINA := "stamina"
const SPORE := "spore_balance"
const MANA := "mana"
const ALL: PackedStringArray = [HEALTH, STAMINA, SPORE, MANA]
const REQUIRED_KEYS: PackedStringArray = [HEALTH, STAMINA, SPORE, MANA, "respawn"]

var _config: Dictionary
var _value: Dictionary = {}
var _max: Dictionary = {}
## Постоянные прибавки к максимуму (звёзды): {"health": 5, ...}.
var _bonus_max: Dictionary = {}
var _endurance := 1
var _mental := 1
var _stamina_idle := 0.0
var _winded := false
var _spore_state := "ok"


func _init(config: Dictionary, endurance_level: int = 1, mental_level: int = 1) -> void:
	_config = config
	set_stat_levels(endurance_level, mental_level)
	for vital in ALL:
		_value[vital] = _max[vital]
	_value[SPORE] = float(_config[SPORE]["start"])
	_spore_state = _spore_state_for(_value[SPORE])


## Максимумы зависят от Выносливости и Ментальной силы. Текущие значения обрезаются.
func set_stat_levels(endurance_level: int, mental_level: int) -> void:
	_endurance = endurance_level
	_mental = mental_level
	var h: Dictionary = _config[HEALTH]
	var s: Dictionary = _config[STAMINA]
	var m: Dictionary = _config[MANA]
	_max[HEALTH] = float(h["max_base"]) + float(h["max_per_endurance_level"]) * (_endurance - 1)
	_max[STAMINA] = float(s["max_base"]) + float(s["max_per_endurance_level"]) * (_endurance - 1)
	_max[SPORE] = float(_config[SPORE]["max"])
	_max[MANA] = float(m["max_base"]) + float(m["max_per_mental_level"]) * (_mental - 1)
	for vital: String in _bonus_max:
		_max[vital] += float(_bonus_max[vital])
	for vital in _value:
		_value[vital] = minf(_value[vital], _max[vital])


## Постоянно увеличивает максимум шкалы; текущее значение растёт на столько же.
func add_max_bonus(vital: String, amount: float) -> void:
	_bonus_max[vital] = float(_bonus_max.get(vital, 0.0)) + amount
	set_stat_levels(_endurance, _mental)
	_value[vital] = minf(_max[vital], _value[vital] + amount)


func max_bonus(vital: String) -> float:
	return float(_bonus_max.get(vital, 0.0))


func value(vital: String) -> float:
	return _value[vital]


func max_value(vital: String) -> float:
	return _max[vital]


func fraction(vital: String) -> float:
	return _value[vital] / _max[vital] if _max[vital] > 0.0 else 0.0


func is_dead() -> bool:
	return _value[HEALTH] <= 0.0 or _value[SPORE] <= 0.0


func spore_state() -> String:
	return _spore_state


## Сила штрафа от спорового баланса: 0 — нет штрафа (баланс ≥ порога), 1 — баланс на нуле.
func spore_penalty() -> float:
	var below := float(_config[SPORE]["penalty_below"])
	return clampf(1.0 - fraction(SPORE) / below, 0.0, 1.0)


## Множитель от штрафа: 1.0 без штрафа, значение из penalty_at_zero — на нуле.
func penalty_multiplier(kind: String) -> float:
	return lerpf(1.0, float(_config[SPORE]["penalty_at_zero"][kind]), spore_penalty())


## Бежать можно, пока не выдохся; выдохшийся снова бежит, когда бодрость ≥ sprint_restart_at.
func can_sprint() -> bool:
	return not _winded and _value[STAMINA] > 0.0


## Множитель скорости движения (штраф спорового баланса).
func speed_multiplier() -> float:
	return penalty_multiplier("speed")


## Шаг симуляции. real_seconds — для бодрости, game_minutes — для остального.
## stamina_cost_mult — перегруз рюкзака и т. п. увеличивают расход на бег.
func tick(real_seconds: float, game_minutes: float, sprinting: bool, stamina_cost_mult: float = 1.0) -> void:
	if is_dead():
		return
	var s: Dictionary = _config[STAMINA]
	var spent := 0.0
	if sprinting and can_sprint():
		spent = spend_stamina(float(s["sprint_cost_per_second"]) * real_seconds * stamina_cost_mult)
	else:
		_stamina_idle += real_seconds
		if _stamina_idle >= float(s["regen_delay_seconds"]):
			var regen := float(s["regen_per_second"]) * real_seconds * penalty_multiplier("stamina_regen")
			_value[STAMINA] = minf(_max[STAMINA], _value[STAMINA] + regen)
	if _winded and _value[STAMINA] >= float(s["sprint_restart_at"]):
		_winded = false

	var hours := game_minutes / 60.0
	var h: Dictionary = _config[HEALTH]
	restore(HEALTH, float(h["regen_per_game_hour"]) * hours * penalty_multiplier("health_regen"))
	var m: Dictionary = _config[MANA]
	restore(MANA, (float(m["regen_per_game_hour"]) + float(m["regen_per_mental_level"]) * (_mental - 1)) * hours)

	var sp: Dictionary = _config[SPORE]
	drain(SPORE, float(sp["decay_per_game_hour"]) * hours + float(sp["decay_per_stamina_spent"]) * spent)


## Тратит бодрость (спринт, удар, лазание). Возвращает реально потраченное.
func spend_stamina(amount: float) -> float:
	var spent := minf(amount, _value[STAMINA])
	_value[STAMINA] -= spent
	_stamina_idle = 0.0
	if amount > 0.0 and _value[STAMINA] <= 0.0 and not _winded:
		_winded = true
		depleted.emit(STAMINA)
	return spent


## Урон здоровью. Возвращает true, если удар оказался смертельным.
func damage(amount: float) -> bool:
	return drain(HEALTH, amount)


## Тратит ману на умение. false — маны не хватает, ничего не списано.
func spend_mana(amount: float) -> bool:
	if _value[MANA] < amount:
		return false
	_value[MANA] -= amount
	return true


func restore(vital: String, amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	_value[vital] = minf(_max[vital], _value[vital] + amount)
	_update_spore_state()


## Уменьшает шкалу. Для здоровья и спорового баланса ноль — смерть (true, сигнал один раз).
func drain(vital: String, amount: float) -> bool:
	if amount <= 0.0 or is_dead():
		return false
	_value[vital] = maxf(0.0, _value[vital] - amount)
	_update_spore_state()
	if _value[vital] <= 0.0 and (vital == HEALTH or vital == SPORE):
		depleted.emit(vital)
		return true
	return false


## Возрождение: здоровье и бодрость по respawn, споровый баланс не ниже минимума, мана — доля.
func restore_after_death() -> void:
	var r: Dictionary = _config["respawn"]
	_value[HEALTH] = _max[HEALTH] * float(r["health"])
	_value[STAMINA] = _max[STAMINA] * float(r["stamina"])
	_value[SPORE] = maxf(_value[SPORE], _max[SPORE] * float(r["spore_balance_min"]))
	_value[MANA] = _max[MANA] * float(r["mana"])
	_winded = false
	_stamina_idle = 0.0
	_update_spore_state()


func to_dict() -> Dictionary:
	var data := _value.duplicate()
	data["bonus_max"] = _bonus_max.duplicate()
	return data


func load_dict(data: Dictionary) -> void:
	_bonus_max.clear()
	var bonus: Dictionary = data.get("bonus_max", {})
	for vital: String in bonus:
		_bonus_max[vital] = float(bonus[vital])
	set_stat_levels(_endurance, _mental)
	for vital in ALL:
		_value[vital] = clampf(float(data.get(vital, _value[vital])), 0.0, _max[vital])
	_winded = false
	_spore_state = _spore_state_for(_value[SPORE])


func _update_spore_state() -> void:
	var state := _spore_state_for(_value[SPORE])
	if state != _spore_state:
		_spore_state = state
		spore_state_changed.emit(state)


func _spore_state_for(amount: float) -> String:
	var sp: Dictionary = _config[SPORE]
	var f := amount / float(sp["max"])
	if f < float(sp["critical_below"]):
		return "critical"
	if f < float(sp["penalty_below"]):
		return "low"
	return "ok"
