class_name SkillRules
extends RefCounted
## Умения героя: изученные, список активных (D-84), откаты, свойства на порогах, мана и рост от характеристик.
## Чистый класс без Node. Данные — data/skill_rules.json и data/skills/*.json (схема 14.5).
## Спецификация: docs/spec/05_skills.md.
##
## Время — игровые минуты (как GameClock.minutes): cooldown_s в данных — игровые секунды,
## duration_s — реальные секунды, переводятся через minutes_per_second (D-06).
## levels — уровни характеристик героя: {"mental": int, "talent_facets": int, "general": int, "luck": int}.
##
## Эффект умения — словарь с type; правила только считают числа (рост, свойства), применяет их
## PlayerState (баффы, статусы, шкалы) и сцена (шум, подсветка, твари) — так новые умения
## добавляются данными. Типы: stat_mult, status, vital_fill, vital_cost, vitals_fill_random,
## reserve_mana (пассив) и сценовые (highlight, noise_zone, …).

const REQUIRED_KEYS: PackedStringArray = [
	"thresholds", "talent_facets_mults", "hotkeys", "max_mana_reserve", "status_caps_s", "gifts",
	"offer_bonus", "pearl", "areas",
]
const PASSIVE := "passive"
## Возможности движка, которых пока нет: свойства с requires из этого списка не предлагаются.
const MISSING_ENGINE: PackedStringArray = ["party", "humans", "quasi", "elites"]

var _rules: Dictionary
var _defs: Dictionary = {}
var _minutes_per_second: float
## Изученные умения: {id: {"properties": [id свойства, выбранные на порогах]}}.
var learned: Dictionary = {}
## «Список активных» (D-84): умения, которые работают, в порядке игрока; первые hotkeys — на
## клавишах 1–8. Лимита нет — ограничитель мана: пассивы держат резерв, активные стоят ману.
var active_list: Array[String] = []
## Готово к применению с игровой минуты: {id: minutes}.
var cooldowns: Dictionary = {}
## Статусы от умений до игровой минуты: {"immunity": minutes, "luck_double_roll": minutes}.
var statuses: Dictionary = {}
## Включённые умения-переключатели (Тепловое зрение): {id: true}. Держат ману в секунду.
var toggled: Dictionary = {}
## Что сейчас глушит умения: {"cluster_disabled": true, "jammer": true}. Не сохраняется — сцена
## выставляет заново.
var blockers: Dictionary = {}


func _init(rules: Dictionary, defs: Array, minutes_per_second: float) -> void:
	_rules = rules
	_minutes_per_second = minutes_per_second
	for def: Dictionary in defs:
		_defs[String(def["id"])] = def


# --- Справочник ---------------------------------------------------------------------------------

func has_def(id: String) -> bool:
	return _defs.has(id)


func def(id: String) -> Dictionary:
	return _defs[id]


func all_ids() -> PackedStringArray:
	return PackedStringArray(_defs.keys())


func is_passive(id: String) -> bool:
	return String(_defs[id].get("slot", "active")) == PASSIVE


func knows(id: String) -> bool:
	return learned.has(id)


# --- Список активных (D-84) --------------------------------------------------------------------

func in_list(id: String) -> bool:
	return active_list.has(id)


## Умение на клавише index (0 — «1»); "" — нет.
func hotkey_skill(index: int) -> String:
	return active_list[index] if index >= 0 and index < mini(active_list.size(), hotkey_count()) else ""


func hotkey_count() -> int:
	return int(_rules["hotkeys"])


## Выучить умение: сразу встаёт в конец списка активных, если хватает резерва маны.
func learn(id: String) -> bool:
	if not _defs.has(id) or learned.has(id):
		return false
	learned[id] = {"properties": []}
	add_to_list(id)
	return true


## Внести в список активных. Пассив — только если резерв маны не превысит max_mana_reserve.
## Откатов смены нет: внести и убрать можно в любой момент (D-84) — мана всё равно ограничивает.
func add_to_list(id: String) -> bool:
	if not learned.has(id) or active_list.has(id):
		return false
	if _reserve_of(id) > 0.0 and _reserve_sum(active_list) + _reserve_of(id) > float(_rules["max_mana_reserve"]) + 0.0001:
		return false
	active_list.append(id)
	return true


func remove_from_list(id: String) -> void:
	active_list.erase(id)
	toggled.erase(id)


## Сдвинуть умение в списке на delta позиций (−1 — выше, к клавише 1).
func move_in_list(id: String, delta: int) -> void:
	var i := active_list.find(id)
	if i < 0:
		return
	var j := clampi(i + delta, 0, active_list.size() - 1)
	active_list.remove_at(i)
	active_list.insert(j, id)


# --- Числа: рост от характеристик и свойства ----------------------------------------------------

## Значение параметра с ростом и свойствами. path: "mana_cost", "cooldown_s" или
## "<эффект>.<поле>" ("stat_mult.value"), где эффект — его key, если задан, иначе type: эффекты
## с одним именем меняются вместе (Форсаж — Скорость и Сила), key разводит их (Кредит баланса —
## "stat_mult" и "debt"). base — своё базовое значение (по умолчанию — из первого эффекта с этим
## именем).
func param(id: String, path: String, levels: Dictionary, base: float = NAN) -> float:
	var d: Dictionary = _defs[id]
	var value := base if not is_nan(base) else _base_param(d, path)
	for s: Dictionary in d.get("scaling", []):
		if String(s["path"]) != path:
			continue
		var steps := floori(float(levels.get(String(s["stat"]), 0)) / float(s["per"]))
		value += float(s["add"]) * steps
		if s.has("min"):
			value = maxf(value, float(s["min"]))
		if s.has("max"):
			value = minf(value, float(s["max"]))
	for p: Dictionary in active_properties(id, levels):
		var e: Dictionary = p["effect"]
		if String(e["type"]) != "modify" or String(e["path"]) != path:
			continue
		if e.has("set"):
			value = float(e["set"])
		value += float(e.get("add", 0.0))
		value *= float(e.get("mult", 1.0))
	if path == "mana_cost" or path == "cooldown_s":
		value = maxf(0.0, value * _facet_mult(path, levels))
	return value


func mana_cost(id: String, levels: Dictionary) -> float:
	return param(id, "mana_cost", levels)


## Откат в игровых секундах.
func cooldown_s(id: String, levels: Dictionary) -> float:
	return param(id, "cooldown_s", levels)


## Сколько игровых минут до готовности (0 — готово).
func cooldown_left(id: String, now: float) -> float:
	return maxf(0.0, float(cooldowns.get(id, 0.0)) - now)


## Эффекты умения с ростом и свойствами: modify меняет поле (число — с ростом, флаг или строка —
## заменой), on_use и passive добавляют эффект в конец. Длительности — в игровых минутах
## (duration_min), исходные реальные секунды — в duration_s.
func effects(id: String, levels: Dictionary) -> Array[Dictionary]:
	var d: Dictionary = _defs[id]
	var result: Array[Dictionary] = []
	for base: Dictionary in d.get("effects", []):
		var e := base.duplicate(true)
		var name := _effect_name(base)
		for key: String in base:
			if base[key] is float or base[key] is int:
				e[key] = param(id, name + "." + key, levels, float(base[key]))
		# Свойство меняет поле, которого в базе нет или которое не число (флаг, строка).
		for p: Dictionary in active_properties(id, levels):
			var pe: Dictionary = p["effect"]
			var path := String(pe.get("path", ""))
			var field := path.trim_prefix(name + ".")
			if String(pe["type"]) != "modify" or not path.begins_with(name + ".") or base.has(field) and (base[field] is float or base[field] is int):
				continue
			if pe.has("set") and not (pe["set"] is float or pe["set"] is int):
				e[field] = pe["set"]
			else:
				e[field] = param(id, path, levels, 0.0)
		result.append(e)
	for p: Dictionary in active_properties(id, levels):
		var pe: Dictionary = p["effect"]
		if String(pe["type"]) == "on_use" or String(pe["type"]) == "passive":
			result.append(Dictionary(pe["effect"]).duplicate(true))
	for e in result:
		if e.has("duration_of"):
			e["duration_s"] = _duration_of(result, String(e["duration_of"]))
		if e.has("after"):
			e["delay_s"] = _duration_of(result, String(e["after"]))
		if e.has("duration_s"):
			var cap := float(_rules["status_caps_s"].get(String(e.get("status", "")), INF))
			e["duration_s"] = minf(float(e["duration_s"]), cap)
			e["duration_min"] = float(e["duration_s"]) * _minutes_per_second
		if e.has("delay_s"):
			e["delay_min"] = float(e["delay_s"]) * _minutes_per_second
	return result


## Свойства, которые сейчас действуют: выбранные на порогах (если порог ещё держится), без выбора
## (открылись сами) и по Граням Таланта.
func active_properties(id: String, levels: Dictionary) -> Array[Dictionary]:
	var chosen: Array = learned.get(id, {}).get("properties", [])
	var result: Array[Dictionary] = []
	for p: Dictionary in _defs[id].get("properties", []):
		if not _unlocked(p, levels) or not _available(p):
			continue
		if not p.has("choice") or chosen.has(String(p["id"])):
			result.append(p)
	return result


## Группы выбора, открытые порогом и ещё не выбранные: [{"group": "m30", "options": [свойства]}].
func property_choices(id: String, levels: Dictionary) -> Array[Dictionary]:
	if not learned.has(id):
		return []
	var chosen: Array = learned[id]["properties"]
	var groups := {}
	var order: PackedStringArray = []
	for p: Dictionary in _defs[id].get("properties", []):
		if not p.has("choice") or not _unlocked(p, levels) or not _available(p):
			continue
		var group := String(p["choice"])
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append(p)
	var result: Array[Dictionary] = []
	for group in order:
		var taken := false
		for p: Dictionary in groups[group]:
			if chosen.has(String(p["id"])):
				taken = true
		if not taken:
			result.append({"group": group, "options": groups[group]})
	return result


func choose_property(id: String, property_id: String, levels: Dictionary) -> bool:
	for choice in property_choices(id, levels):
		for p: Dictionary in choice["options"]:
			if String(p["id"]) == property_id:
				learned[id]["properties"].append(property_id)
				return true
	return false


# --- Применение ---------------------------------------------------------------------------------

func is_blocked() -> bool:
	return not blockers.is_empty()


func set_blocker(reason: String, on: bool) -> void:
	if on:
		blockers[reason] = true
	else:
		blockers.erase(reason)


## Можно ли применить: "ok", "unknown", "not_listed", "passive", "blocked", "cooldown", "mana".
func can_use(id: String, now: float, mana: float, levels: Dictionary) -> String:
	if not learned.has(id):
		return "unknown"
	if toggled.has(id):
		return "ok"
	if not active_list.has(id):
		return "not_listed"
	if is_passive(id):
		return "passive"
	if is_blocked():
		return "blocked"
	if cooldown_left(id, now) > 0.0:
		return "cooldown"
	var cost := mana_cost(id, levels)
	if mana < cost or (cost > 0.0 and mana <= 0.0):
		return "mana"
	return "ok"


## Применить: ставит откат и статусы, возвращает {"result": как can_use, "mana": цена,
## "effects": [...]} — остальные эффекты применяет вызывающий.
func use(id: String, now: float, mana: float, levels: Dictionary) -> Dictionary:
	var check := can_use(id, now, mana, levels)
	if check != "ok":
		return {"result": check, "mana": 0.0, "effects": []}
	if toggled.has(id):
		toggled.erase(id)
		return {"result": "off", "mana": 0.0, "effects": []}
	if is_toggle(id):
		toggled[id] = true
	var list := effects(id, levels)
	cooldowns[id] = now + cooldown_s(id, levels) / 60.0
	for e in list:
		if String(e["type"]) == "status":
			var status := String(e["status"])
			statuses[status] = maxf(float(statuses.get(status, 0.0)), now + float(e["duration_min"]))
	return {"result": "ok", "mana": mana_cost(id, levels), "effects": list}


func is_toggle(id: String) -> bool:
	return bool(_defs[id].get("toggle", false))


## Мана в реальную секунду на включённые переключатели.
func upkeep(levels: Dictionary) -> float:
	var total := 0.0
	for id: String in toggled:
		for e in effects(id, levels):
			total += float(e.get("upkeep_mana_per_s", 0.0))
	return total


## Выключить все переключатели (кончилась мана, глушитель, смерть, умение ушло из слота).
## Возвращает выключенные.
func toggle_off_all() -> PackedStringArray:
	var off := PackedStringArray(toggled.keys())
	toggled.clear()
	return off


## Эффекты типа type от включённых переключателей.
func toggled_effects(type: String, levels: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in toggled:
		for e in effects(id, levels):
			if String(e["type"]) == type:
				result.append(e)
	return result


## «Мимо!»: шанс, что удар прошёл мимо. Срабатывает на смертельный удар (свойство — и на удар
## больше половины здоровья); каждая смерть в регионе −20% шанса, по элитам ×0,5.
func luck_save_chance(luck: float, damage: float, health: float, deaths_in_region: int, elite: bool, levels: Dictionary) -> float:
	var best := 0.0
	for e in passive_effects("luck_save", levels):
		var heavy := String(e.get("applies", "lethal")) == "heavy" and damage >= health * 0.5
		if damage < health and not heavy:
			continue
		var l := maxf(0.0, luck)
		var p := float(e["cap"]) * l / (l + float(e["k"])) if l > 0.0 else 0.0
		p *= maxf(0.0, 1.0 + float(e["per_death_in_region"]) * deaths_in_region)
		if elite:
			p *= float(e["elite_mult"])
		best = maxf(best, p)
	return best


## Длительное действие героя (вскрытие мешка): {"speed": множитель скорости, "move_m": допуск сдвига}.
func channel_mods(channel: String, levels: Dictionary, default_move: float) -> Dictionary:
	var result := {"speed": 1.0, "move_m": default_move}
	for e in passive_effects("channel_speed", levels):
		if String(e["channel"]) == channel:
			result["speed"] = maxf(float(result["speed"]), float(e["mult"]))
			result["move_m"] = maxf(float(result["move_m"]), float(e.get("interrupt_move_m", default_move)))
	return result


func has_status(status: String, now: float) -> bool:
	return float(statuses.get(status, -INF)) > now


func status_left(status: String, now: float) -> float:
	return maxf(0.0, float(statuses.get(status, 0.0)) - now)


## Эффекты типа type от пассивов в списке активных (под глушителем и на отключённом кластере — нет).
func passive_effects(type: String, levels: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if is_blocked():
		return result
	for id in active_list:
		if not is_passive(id):
			continue
		for e in effects(id, levels):
			if String(e["type"]) == type:
				result.append(e)
	return result


## Шум героя с учётом умений: пассивы (noise_mult_self, noise_source_swap) и статусы
## (quiet_sprint — бег ×0,7). Результат: {"source": источник после подмены, "mult": множитель радиуса}.
func noise_adjust(source: String, now: float, levels: Dictionary) -> Dictionary:
	var result := {"source": source, "mult": 1.0}
	for e in passive_effects("noise_source_swap", levels):
		if String(e["from"]) == source:
			result["source"] = String(e["to"])
	for e in passive_effects("noise_mult_self", levels):
		if Array(e["sources"]).has(source):
			result["mult"] = float(result["mult"]) * float(e["mult"])
	if source == "sprint_step" and has_status("quiet_sprint", now):
		result["mult"] = float(result["mult"]) * float(_rules.get("quiet_sprint_mult", 0.7))
	return result


## Множитель урона пассивов по цели: unaware — тварь не гонится и не атакует (Из тени).
func damage_mult(unaware: bool, elite: bool, levels: Dictionary) -> float:
	var mult := 1.0
	for e in passive_effects("damage_mult_vs", levels):
		if String(e["condition"]) == "target_unaware" and unaware:
			mult *= float(e["elite_mult"]) if elite and e.has("elite_mult") else float(e["mult"])
	return mult


## Прибавка шанса крита (удар в голову или мешок) от пассивов.
func crit_chance(unaware: bool, levels: Dictionary) -> float:
	var total := 0.0
	for e in passive_effects("crit_chance_add", levels):
		if String(e["condition"]) != "target_unaware" or unaware:
			total += float(e["value"])
	return total


## Доля маны, которую держат пассивы в списке активных (D-74; резерв держится и под глушителем).
func mana_reserve() -> float:
	return clampf(_reserve_sum(active_list), 0.0, float(_rules["max_mana_reserve"]))


func _reserve_of(id: String) -> float:
	var total := 0.0
	for e: Dictionary in _defs[id].get("effects", []):
		if String(e["type"]) == "reserve_mana":
			total += float(e["pct"])
	return total


func _reserve_sum(ids: Array[String]) -> float:
	var total := 0.0
	for id in ids:
		total += _reserve_of(id)
	return total


## Смерть обнуляет откаты всех умений (D-73). Статусы гаснут, переключатели выключаются.
func reset_cooldowns() -> void:
	cooldowns.clear()
	statuses.clear()
	toggled.clear()


# --- Дары ---------------------------------------------------------------------------------------

## Варианты дара: count умений из пула, которых герой не знает и которые есть в данных; недобор —
## из других пулов.
func gift_offer(pool: String, count: int, rng: RandomNumberGenerator) -> PackedStringArray:
	var result: PackedStringArray = []
	var order: PackedStringArray = [pool]
	for other: String in _rules["gifts"]:
		if other != pool and not other.begins_with("_"):
			order.append(other)
	for p in order:
		var candidates: PackedStringArray = []
		for id: String in _rules["gifts"][p]["skills"]:
			if _offerable(id) and not result.has(id):
				candidates.append(id)
		while result.size() < count and not candidates.is_empty():
			var i := rng.randi_range(0, candidates.size() - 1)
			result.append(candidates[i])
			candidates.remove_at(i)
	return result


## Сколько вариантов предлагает знахарка: нижняя граница + бонус Удачи, не больше верхней.
func offer_count(pool: String, luck_level: int, extra: int = 0) -> int:
	var offer: Array = _rules["gifts"][pool]["offer"]
	var bonus: Dictionary = _rules["offer_bonus"]
	var count := int(offer[0]) + extra + (int(bonus["value"]) if luck_level >= int(bonus["luck_level"]) else 0)
	return mini(count, int(offer[1]))


## Пул для дара уровня level ("10", "30", "60") — ближайший не выше.
func gift_pool(level: int) -> String:
	var best := ""
	for key: String in _rules["gifts"]:
		if key.begins_with("_"):
			continue
		if int(key) <= level and (best.is_empty() or int(key) > int(best)):
			best = key
	return best


## Висящее умение чёрной жемчужины, вскрытое самим (или само при смертельной опасности, D-86):
## случайное неизвестное из пула по числу известных. "" — нечего дать.
func pearl_skill(rng: RandomNumberGenerator) -> String:
	var pools: Array = _rules["pearl"]["pools_by_skill_count"]
	var pool := String(pools[mini(learned.size(), pools.size() - 1)])
	var offer := gift_offer(pool, 1, rng)
	return offer[0] if not offer.is_empty() else ""


## Области для выбора у знахарки (D-86) — areas из правил, по порядку.
func areas() -> PackedStringArray:
	return PackedStringArray(_rules["areas"])


## Неизвестные умения области (theme умения), по алфавиту id.
func area_skills(area: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in _defs:
		if _offerable(id) and String(_defs[id].get("theme", "")) == area:
			result.append(id)
	result.sort()
	return result


## Случайное неизвестное умение из области. "" — в области ничего не осталось.
func area_skill(area: String, rng: RandomNumberGenerator) -> String:
	var candidates := area_skills(area)
	return candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else ""


# --- Сохранение ---------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"learned": learned.duplicate(true), "active_list": Array(active_list), "cooldowns": cooldowns.duplicate(),
		"statuses": statuses.duplicate(), "toggled": toggled.keys()}


func load_dict(data: Dictionary) -> void:
	learned.clear()
	var known: Dictionary = data.get("learned", {})
	for id: String in known:
		if _defs.has(id):
			var props: Array = []
			for p in known[id].get("properties", []):
				props.append(String(p))
			learned[id] = {"properties": props}
	active_list.clear()
	# Старые сейвы (v12) — слоты: внесённые идут первыми, остальные изученные — следом (D-84).
	var saved: Array = data.get("active_list", data.get("slots", []))
	for id in saved:
		add_to_list(String(id))
	if not data.has("active_list"):
		for id: String in learned:
			add_to_list(id)
	cooldowns.clear()
	var cd: Dictionary = data.get("cooldowns", {})
	for id: String in cd:
		cooldowns[id] = float(cd[id])
	statuses.clear()
	var st: Dictionary = data.get("statuses", {})
	for status: String in st:
		statuses[status] = float(st[status])
	toggled.clear()
	for id in data.get("toggled", []):
		if learned.has(String(id)):
			toggled[String(id)] = true


# --- Внутреннее ---------------------------------------------------------------------------------

func _base_param(d: Dictionary, path: String) -> float:
	if not path.contains("."):
		return float(d.get(path, 0.0))
	var parts := path.split(".")
	for e: Dictionary in d.get("effects", []):
		if _effect_name(e) == parts[0]:
			return float(e.get(parts[1], 0.0))
	return 0.0


static func _effect_name(e: Dictionary) -> String:
	return String(e.get("key", e["type"]))


func _facet_mult(path: String, levels: Dictionary) -> float:
	var f: Dictionary = _rules["talent_facets_mults"]
	var mult := 1.0
	for at in f["at"]:
		if int(levels.get("talent_facets", 0)) >= int(at):
			mult *= float(f["mana_mult" if path == "mana_cost" else "cooldown_mult"])
	return mult


func _unlocked(p: Dictionary, levels: Dictionary) -> bool:
	var unlock: Dictionary = p.get("unlock", {})
	for stat: String in unlock:
		if int(levels.get(stat, 0)) < int(unlock[stat]):
			return false
	return true


func _available(p: Dictionary) -> bool:
	return not MISSING_ENGINE.has(String(p.get("requires", "")))


func _offerable(id: String) -> bool:
	return _defs.has(id) and not learned.has(id)


static func _duration_of(list: Array[Dictionary], name: String) -> float:
	for e in list:
		if _effect_name(e) == name and e.has("duration_s"):
			return float(e["duration_s"])
	return 0.0
