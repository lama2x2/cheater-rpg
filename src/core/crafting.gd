class_name Crafting
extends RefCounted
## Крафт из инвентаря по рецептам data/recipes.json (живчик: споран + водка). Чистый класс без Node.

const REQUIRED_KEYS: PackedStringArray = ["recipes"]


## Сколько раз можно сделать рецепт из того, что есть.
static func times_possible(recipe: Dictionary, inventory: Inventory) -> int:
	var times := 1 << 30
	var inputs: Dictionary = recipe["inputs"]
	for id: String in inputs:
		times = mini(times, floori(float(inventory.count_of(id)) / float(inputs[id])))
	return times


## Списывает входы и кладёт выходы. Результат: {"ok": bool, "left": {id: не влезло}}.
## Невлезшее вызывающий выбрасывает на землю.
static func craft(recipe: Dictionary, inventory: Inventory) -> Dictionary:
	if times_possible(recipe, inventory) < 1:
		return {"ok": false, "left": {}}
	var inputs: Dictionary = recipe["inputs"]
	for id: String in inputs:
		inventory.remove(id, int(inputs[id]))
	var left := {}
	var outputs: Dictionary = recipe["outputs"]
	for id: String in outputs:
		var not_fit: int = inventory.add(id, int(outputs[id]))["left"]
		if not_fit > 0:
			left[id] = not_fit
	return {"ok": true, "left": left}
