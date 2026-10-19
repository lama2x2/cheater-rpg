class_name TrophyRules
extends RefCounted
## Приём трофеев и расходников: группы откатов (горошины 12 ч, жемчуг 36 ч), броски эффектов,
## риски (кваз), что нужно для приёма (уксус для горошин). Только решает и бросает кубики —
## применяет результат PlayerState. Чистый класс без Node.
## Спецификация: docs/spec/06_trophies_items.md, 6.2; схема — 14.4.

## Игровая минута последнего приёма по группе отката: {"pea": 1234.5, ...}.
var last_taken: Dictionary = {}

var _db: ItemDB


func _init(db: ItemDB) -> void:
	_db = db


func can_consume(id: String) -> bool:
	return _db.has_item(id) and _db.item(id).has("consume")


func spec(id: String) -> Dictionary:
	return _db.item(id).get("consume", {})


## Сколько игровых минут осталось до конца отката группы. 0 — можно без нарушения.
func cooldown_left(id: String, now: float) -> float:
	var s := spec(id)
	var group := String(s.get("cooldown_group", ""))
	if group.is_empty() or not last_taken.has(group):
		return 0.0
	return maxf(0.0, float(last_taken[group]) + float(s["cooldown_h"]) * 60.0 - now)


func is_violation(id: String, now: float) -> bool:
	return cooldown_left(id, now) > 0.0


## Чего не хватает для приёма, кроме самого предмета: {"vinegar": 1}. Пусто — всё есть.
func missing_requirements(id: String, inventory: Inventory) -> Dictionary:
	var missing := {}
	var requires: Dictionary = spec(id).get("requires", {})
	for need: String in requires:
		var short := int(requires[need]) - inventory.count_of(need)
		if short > 0:
			missing[need] = short
	return missing


## Бросает эффекты и риски приёма и отмечает время для группы отката.
## context: {"skill_count", "main_stats", "additional_stats", "vitals"}.
## Результат: {"id", "violation", "effects": [...], "risks": ["become_quasi", ...]}.
## Эффекты после броска:
##   {"type": "stat_add", "stat", "value": int}
##   {"type": "stat_buff", "stat", "mult": float, "hours": float}
##   {"type": "vital_max_add", "vital", "value": int}
##   {"type": "vital_restore", "vital", "value": float}
##   {"type": "free_points", "value": int}
##   {"type": "stop_bleeding"}
##   {"type": "skill_chance", "chance": float, "success": bool}
func resolve(id: String, now: float, rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var s := spec(id)
	var violation := is_violation(id, now)
	var mult := float(s.get("violation_effect_mult", 1.0)) if violation else 1.0
	var effects: Array[Dictionary] = []
	for effect: Dictionary in s.get("effects", []):
		effects.append_array(_roll_effect(effect, mult, rng, context))
	var risks: PackedStringArray = []
	for risk: Dictionary in s.get("risks", []):
		var chance := float(risk["chance_if_cooldown_violated"]) if violation else float(risk["chance"])
		if chance > 0.0 and rng.randf() < chance:
			risks.append(String(risk["type"]))
	var group := String(s.get("cooldown_group", ""))
	if not group.is_empty():
		last_taken[group] = now
	return {"id": id, "violation": violation, "effects": effects, "risks": risks}


func to_dict() -> Dictionary:
	return {"last_taken": last_taken.duplicate()}


func load_dict(data: Dictionary) -> void:
	last_taken.clear()
	var saved: Dictionary = data.get("last_taken", {})
	for group: String in saved:
		last_taken[group] = float(saved[group])


func _roll_effect(effect: Dictionary, mult: float, rng: RandomNumberGenerator, context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match String(effect["type"]):
		"stat_add":
			out.append({"type": "stat_add", "stat": effect["stat"], "value": _scaled_int(effect["value"], mult, rng)})
		"stat_buff":
			var pool: Array = context["main_stats"] if effect["pool"] == "main" else context["additional_stats"]
			out.append({
				"type": "stat_buff", "stat": pool[rng.randi_range(0, pool.size() - 1)],
				"mult": _roll_float(effect["mult"], rng) * mult, "hours": _roll_float(effect["hours"], rng),
			})
		"vital_max_add":
			for vital in _pick_vitals(String(effect["pool"]), context["vitals"], rng):
				out.append({"type": "vital_max_add", "vital": vital, "value": _scaled_int(effect["value"], mult, rng)})
		"vital_restore":
			out.append({"type": "vital_restore", "vital": effect["vital"], "value": float(effect["value"]) * mult})
		"stop_bleeding":
			out.append({"type": "stop_bleeding"})
		"map_reveal":
			out.append({"type": "map_reveal"})
		"free_points":
			out.append({"type": "free_points", "value": _scaled_int(effect["value"], mult, rng)})
		"skill_chance":
			var table: Array = effect["by_skill_count"]
			var skills := int(context["skill_count"])
			var chance := float(table[skills]) * mult if skills < table.size() else 0.0
			out.append({"type": "skill_chance", "chance": chance, "success": chance > 0.0 and rng.randf() < chance})
		_:
			push_error("Неизвестный эффект трофея: %s" % effect["type"])
	return out


## «one» — одна случайная шкала, «two» — две разные, «all» — все.
func _pick_vitals(pool: String, vitals: Array, rng: RandomNumberGenerator) -> Array:
	if pool == "all":
		return vitals.duplicate()
	var shuffled := vitals.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	return shuffled.slice(0, 2 if pool == "two" else 1)


## Целое из [a, b] (или числа), умноженное на штраф нарушения; не меньше 1, если штраф не нулевой.
func _scaled_int(value: Variant, mult: float, rng: RandomNumberGenerator) -> int:
	var rolled := rng.randi_range(int(value[0]), int(value[1])) if value is Array else int(value)
	if mult <= 0.0:
		return 0
	return maxi(1, roundi(rolled * mult))


func _roll_float(value: Variant, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(float(value[0]), float(value[1])) if value is Array else float(value)
