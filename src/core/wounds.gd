class_name Wounds
extends RefCounted
## Раны героя. В M1 — только кровотечение: стопки, каждая тянет здоровье, сама сворачивается
## через clot_seconds, бинт останавливает все. Чистый класс без Node. Спецификация: 08, «Раны».

## Оставшиеся секунды каждой стопки кровотечения.
var bleeding: Array[float] = []

var _config: Dictionary


func _init(bleeding_config: Dictionary) -> void:
	_config = bleeding_config


func add_bleeding() -> void:
	if bleeding.size() < int(_config["max_stacks"]):
		bleeding.append(float(_config["clot_seconds"]))
	else:
		bleeding[0] = float(_config["clot_seconds"])  # самая старая обновляется


func stop_bleeding() -> void:
	bleeding.clear()


func is_bleeding() -> bool:
	return not bleeding.is_empty()


## Шаг: возвращает потерю здоровья за real_seconds, свернувшиеся стопки убираются.
func tick(real_seconds: float) -> float:
	var loss := 0.0
	var per := float(_config["hp_per_second_per_stack"])
	for i in range(bleeding.size() - 1, -1, -1):
		var active := minf(real_seconds, bleeding[i])
		loss += per * active
		bleeding[i] -= real_seconds
		if bleeding[i] <= 0.0:
			bleeding.remove_at(i)
	return loss


func to_dict() -> Dictionary:
	return {"bleeding": bleeding.duplicate()}


func load_dict(data: Dictionary) -> void:
	bleeding.clear()
	for left in data.get("bleeding", []):
		bleeding.append(float(left))
