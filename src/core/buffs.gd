class_name Buffs
extends RefCounted
## Временные усиления характеристик (зерно, орех, позже умения): +mult к значению до игровой минуты until.
## Чистый класс без Node.

var active: Array[Dictionary] = []


func add(stat: String, mult: float, until: float, source: String = "") -> void:
	active.append({"stat": stat, "mult": mult, "until": until, "source": source})


## Множитель характеристики сейчас: 1 + сумма активных усилений.
func multiplier(stat: String, now: float) -> float:
	var total := 1.0
	for buff in active:
		if buff["stat"] == stat and float(buff["until"]) > now:
			total += float(buff["mult"])
	return total


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
		add(String(buff["stat"]), float(buff["mult"]), float(buff["until"]), String(buff.get("source", "")))
