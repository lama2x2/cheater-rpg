class_name Buffs
extends RefCounted
## Временные усиления характеристик (зерно, орех, умения): +mult к значению с игровой минуты from
## до until. Чистый класс без Node.
##
## group — «джекпот»-группа умений (D-18): усиления одной группы не складываются, действует
## наибольшее (Улыбка Фортуны и Кредит баланса).

var active: Array[Dictionary] = []


func add(stat: String, mult: float, until: float, source: String = "", from: float = -INF, group: String = "") -> void:
	var buff := {"stat": stat, "mult": mult, "until": until, "source": source}
	if from > -INF:
		buff["from"] = from
	if not group.is_empty():
		buff["group"] = group
	active.append(buff)


## Множитель характеристики сейчас: 1 + сумма активных усилений; в группе — только наибольшее.
func multiplier(stat: String, now: float) -> float:
	var total := 1.0
	var groups := {}
	for buff in active:
		if buff["stat"] != stat or float(buff["until"]) <= now or float(buff.get("from", -INF)) > now:
			continue
		if buff.has("group"):
			groups[buff["group"]] = maxf(float(groups.get(buff["group"], -INF)), float(buff["mult"]))
		else:
			total += float(buff["mult"])
	for group: String in groups:
		total += float(groups[group])
	return total


## Усиление от источника source действует сейчас.
func is_active(source: String, now: float) -> bool:
	for buff in active:
		if buff["source"] == source and float(buff["until"]) > now and float(buff.get("from", -INF)) <= now:
			return true
	return false


## Сколько игровых минут осталось у самого долгого действующего усиления от source.
func left(source: String, now: float) -> float:
	var best := 0.0
	for buff in active:
		if buff["source"] == source and float(buff.get("from", -INF)) <= now:
			best = maxf(best, float(buff["until"]) - now)
	return best


## Убирает закончившиеся. Возвращает их — чтобы сообщить в лог.
func expire(now: float) -> Array[Dictionary]:
	var ended: Array[Dictionary] = []
	for buff in active:
		if float(buff["until"]) <= now:
			ended.append(buff)
	for buff in ended:
		active.erase(buff)
	return ended


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true)}


func load_dict(data: Dictionary) -> void:
	active.clear()
	for buff: Dictionary in data.get("active", []):
		add(String(buff["stat"]), float(buff["mult"]), float(buff["until"]), String(buff.get("source", "")),
			float(buff.get("from", -INF)), String(buff.get("group", "")))
