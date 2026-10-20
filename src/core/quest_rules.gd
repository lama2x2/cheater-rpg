class_name QuestRules
extends RefCounted
## Движок сюжетных миссий (11.4a, D-97, задача 17b): миссии кампании — данными
## (data/campaigns/<id>/missions.json). Миссия стартует по событию (у непися, на месте) или сразу,
## у неё цели-счётчики по событиям, события провала (с повтором или без), выборы с флагами и
## отложенные последствия: через N игровых часов, если флаги совпали. Чистые правила; состояние —
## словарь (в сейве), события подаёт PlayerState.quest_event.
##
## Миссия: {"id", "title", "desc", "start": {"event"} | {"auto": true}, "objectives": [{"id",
##   "event", "count", "text"}], "fail": {"events": [...], "retry": bool}, "choices": [{"id",
##   "text", "options": [{"id", "text", "flags": {}, "cost": {id: n}}]}], "consequences": [{"id",
##   "delay_h", "if": {флаг: значение}, "log", "grants": [...]}], "next": [id…], "final": bool}.
## Состояние: {"active": {id: {"progress": {цель: n}, "started": мин}}, "done": [id…],
##   "fails": {id: n}, "flags": {}, "choices": {"миссия:выбор": вариант}, "pending": [{"at", "mission",
##   "id"}], "fired": [id…]}.

var missions: Dictionary = {}
var order: PackedStringArray = []


func _init(defs: Array) -> void:
	for m: Dictionary in defs:
		missions[String(m["id"])] = m
		order.append(String(m["id"]))


static func new_state() -> Dictionary:
	return {"active": {}, "done": [], "fails": {}, "flags": {}, "choices": {}, "pending": [], "fired": []}


func mission(id: String) -> Dictionary:
	return missions.get(id, {})


## Ошибки данных: неизвестные миссии в next, цели без события.
func errors() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in missions:
		var m: Dictionary = missions[id]
		for other in m.get("next", []):
			if not missions.has(String(other)):
				result.append("%s: неизвестная миссия в next «%s»" % [id, other])
		for o: Dictionary in m.get("objectives", []):
			if String(o.get("event", "")).is_empty():
				result.append("%s: цель %s без события" % [id, o.get("id", "?")])
		if (m.get("objectives", []) as Array).is_empty():
			result.append("%s: нет целей" % id)
	return result


## Миссии, которые стартуют сразу (start.auto) — в начале кампании.
func start_auto(state: Dictionary, now: float) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	for id in order:
		if bool(missions[id].get("start", {}).get("auto", false)):
			notes.append_array(_start(state, id, now))
	return notes


func is_active(state: Dictionary, id: String) -> bool:
	return (state["active"] as Dictionary).has(id)


func is_done(state: Dictionary, id: String) -> bool:
	return (state["done"] as Array).has(id)


## Событие мира. Возвращает заметки для лога и интерфейса: {"type": started | progress | done |
## failed | retry, "mission", "objective"?}.
func on_event(state: Dictionary, event: String, now: float) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	# Провал раньше прогресса: смерть на последнем шаге — это провал, а не победа.
	for id: String in (state["active"] as Dictionary).keys():
		var fail: Dictionary = missions[id].get("fail", {})
		if (fail.get("events", []) as Array).has(event):
			state["fails"][id] = int(state["fails"].get(id, 0)) + 1
			if bool(fail.get("retry", true)):
				state["active"][id] = {"progress": {}, "started": now}
				notes.append({"type": "retry", "mission": id})
			else:
				state["active"].erase(id)
				notes.append({"type": "failed", "mission": id})
	for id: String in (state["active"] as Dictionary).keys():
		var entry: Dictionary = state["active"][id]
		var changed := false
		for o: Dictionary in missions[id].get("objectives", []):
			var oid := String(o["id"])
			var have := int(entry["progress"].get(oid, 0))
			if String(o["event"]) == event and have < int(o.get("count", 1)):
				entry["progress"][oid] = have + 1
				changed = true
				notes.append({"type": "progress", "mission": id, "objective": oid})
		if changed and _complete(entry, missions[id]):
			notes.append_array(_finish(state, id, now))
	for id in order:
		var start: Dictionary = missions[id].get("start", {})
		if String(start.get("event", "")) == event:
			notes.append_array(_start(state, id, now))
	return notes


## Выбор в миссии: вариант option выбора choice. Возвращает вариант ({"flags", "cost"…}) или {},
## если выбор уже сделан или такого нет. Флаги ставятся сразу.
func choose(state: Dictionary, mission_id: String, choice_id: String, option_id: String) -> Dictionary:
	var key := "%s:%s" % [mission_id, choice_id]
	if (state["choices"] as Dictionary).has(key):
		return {}
	for c: Dictionary in mission(mission_id).get("choices", []):
		if String(c["id"]) != choice_id:
			continue
		for option: Dictionary in c["options"]:
			if String(option["id"]) == option_id:
				state["choices"][key] = option_id
				var flags: Dictionary = option.get("flags", {})
				for flag: String in flags:
					state["flags"][flag] = flags[flag]
				return option
	return {}


func chosen(state: Dictionary, mission_id: String, choice_id: String) -> String:
	return String(state["choices"].get("%s:%s" % [mission_id, choice_id], ""))


## Отложенные последствия, время которых пришло и флаги совпали. Не совпали — отменяются.
func due(state: Dictionary, now: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keep: Array = []
	for p: Dictionary in state["pending"]:
		if float(p["at"]) > now:
			keep.append(p)
			continue
		for c: Dictionary in mission(String(p["mission"])).get("consequences", []):
			if String(c["id"]) == String(p["id"]) and _flags_match(state, c.get("if", {})):
				result.append(c)
				state["fired"].append(String(c["id"]))
	state["pending"] = keep
	return result


## Цели миссии для интерфейса: [{"id", "text", "have", "need", "done"}].
func objectives(state: Dictionary, id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var progress: Dictionary = state["active"].get(id, {}).get("progress", {})
	var finished := is_done(state, id)
	for o: Dictionary in mission(id).get("objectives", []):
		var need := int(o.get("count", 1))
		var have := need if finished else int(progress.get(String(o["id"]), 0))
		result.append({"id": String(o["id"]), "text": String(o.get("text", "")), "have": have, "need": need, "done": have >= need})
	return result


func _start(state: Dictionary, id: String, now: float) -> Array[Dictionary]:
	if is_active(state, id) or is_done(state, id):
		return []
	state["active"][id] = {"progress": {}, "started": now}
	return [{"type": "started", "mission": id}]


func _complete(entry: Dictionary, def: Dictionary) -> bool:
	for o: Dictionary in def.get("objectives", []):
		if int(entry["progress"].get(String(o["id"]), 0)) < int(o.get("count", 1)):
			return false
	return true


func _finish(state: Dictionary, id: String, now: float) -> Array[Dictionary]:
	state["active"].erase(id)
	state["done"].append(id)
	var notes: Array[Dictionary] = [{"type": "done", "mission": id}]
	for c: Dictionary in missions[id].get("consequences", []):
		state["pending"].append({"at": now + float(c.get("delay_h", 0.0)) * 60.0, "mission": id, "id": String(c["id"])})
	for next in missions[id].get("next", []):
		notes.append_array(_start(state, String(next), now))
	return notes


func _flags_match(state: Dictionary, need: Dictionary) -> bool:
	for flag: String in need:
		if state["flags"].get(flag) != need[flag]:
			return false
	return true
