class_name Inventory
extends RefCounted
## Инвентарь героя: первичный (ячейки Системы, граммы, сохраняется при смерти) и рюкзак
## (список по весу, перегруз замедляет, остаётся на трупе). Чистый класс без Node.
## Спецификация: docs/spec/06_trophies_items.md, 6.3; интерфейс — D-25 (список, не грид).
##
## Ячейка первичного инвентаря: {"id", "count"} или пустой словарь. Один вид предмета на ячейку,
## общий вес ячейки ≤ slot_capacity_g. Рюкзак: [{"id", "count"}], одинаковые предметы — одной строкой.

const REQUIRED_KEYS: PackedStringArray = ["primary", "backpack"]

var primary: Array[Dictionary] = []
var backpack: Array[Dictionary] = []
var strength_level: int = 1

var _db: ItemDB
var _config: Dictionary


func _init(db: ItemDB, config: Dictionary, strength: int = 1) -> void:
	_db = db
	_config = config
	strength_level = strength
	set_slot_count(int(config["primary"]["slots_start"]))


## Число ячеек растёт за элит и уровни Силы (позже). Уменьшать не даём, если ячейка занята.
func set_slot_count(count: int) -> void:
	while primary.size() < count:
		primary.append({})
	while primary.size() > count and primary[-1].is_empty():
		primary.pop_back()


func slot_capacity_g() -> float:
	return float(_config["primary"]["slot_capacity_g"])


## Сколько штук предмета поместится в ячейки (в существующие стопки и свободные ячейки).
func primary_room(id: String) -> int:
	if not _db.allowed_in_primary(id):
		return 0
	var per_slot := floori(slot_capacity_g() / _db.weight_g(id))
	var room := 0
	for slot in primary:
		if slot.is_empty():
			room += per_slot
		elif slot["id"] == id:
			room += per_slot - int(slot["count"])
	return room


## Кладёт в ячейки сколько влезет. Возвращает, сколько не поместилось.
func add_primary(id: String, count: int) -> int:
	if not _db.allowed_in_primary(id):
		return count
	var per_slot := floori(slot_capacity_g() / _db.weight_g(id))
	var left := count
	for slot in primary:
		if left > 0 and not slot.is_empty() and slot["id"] == id:
			var put := mini(left, per_slot - int(slot["count"]))
			slot["count"] = int(slot["count"]) + put
			left -= put
	for slot in primary:
		if left > 0 and slot.is_empty() and per_slot > 0:
			var put := mini(left, per_slot)
			slot["id"] = id
			slot["count"] = put
			left -= put
	return left


## Вместимость рюкзака по Силе, кг.
func backpack_capacity_kg() -> float:
	var b: Dictionary = _config["backpack"]
	return float(b["capacity_base_kg"]) + float(b["capacity_per_strength_level_kg"]) * (strength_level - 1)


func backpack_weight_kg() -> float:
	var grams := 0.0
	for stack in backpack:
		grams += _db.weight_g(stack["id"]) * int(stack["count"])
	return grams / 1000.0


func primary_weight_g() -> float:
	var grams := 0.0
	for slot in primary:
		if not slot.is_empty():
			grams += _db.weight_g(slot["id"]) * int(slot["count"])
	return grams


## Вес относительно вместимости: 1.0 — полный, > 1 — перегруз.
func load_ratio() -> float:
	return backpack_weight_kg() / backpack_capacity_kg()


func is_overloaded() -> bool:
	return load_ratio() > 1.0


## Множитель скорости: 1 до полного рюкзака, линейно до overload_speed_at_double на двойном весе.
func speed_multiplier() -> float:
	var at_double := float(_config["backpack"]["overload_speed_at_double"])
	return lerpf(1.0, at_double, clampf(load_ratio() - 1.0, 0.0, 1.0))


## Множитель расхода бодрости: так же растёт до overload_stamina_cost_at_double.
func stamina_cost_multiplier() -> float:
	var at_double := float(_config["backpack"]["overload_stamina_cost_at_double"])
	return lerpf(1.0, at_double, clampf(load_ratio() - 1.0, 0.0, 1.0))


## Сколько штук ещё можно положить в рюкзак до жёсткого предела (hard_limit_ratio × вместимость).
func backpack_room(id: String) -> int:
	var limit_kg := backpack_capacity_kg() * float(_config["backpack"]["hard_limit_ratio"])
	var free_g := (limit_kg - backpack_weight_kg()) * 1000.0
	return maxi(0, floori(free_g / _db.weight_g(id) + 0.0001))


## Кладёт в рюкзак до жёсткого предела. Возвращает, сколько не влезло.
func add_backpack(id: String, count: int) -> int:
	var put := mini(count, backpack_room(id))
	if put > 0:
		var stack := _find_stack(id)
		if stack.is_empty():
			backpack.append({"id": id, "count": put})
		else:
			stack["count"] = int(stack["count"]) + put
	return count - put


## Подбор: то, что можно хранить в ячейках, сначала идёт туда, остальное — в рюкзак.
## Возвращает {"primary": n, "backpack": n, "left": n}.
func add(id: String, count: int) -> Dictionary:
	var after_primary := add_primary(id, count)
	var left := add_backpack(id, after_primary)
	return {"primary": count - after_primary, "backpack": after_primary - left, "left": left}


func count_of(id: String) -> int:
	var total := 0
	var stack := _find_stack(id)
	if not stack.is_empty():
		total += int(stack["count"])
	for slot in primary:
		if not slot.is_empty() and slot["id"] == id:
			total += int(slot["count"])
	return total


## Убирает предметы: сначала из рюкзака (он всё равно пропадёт при смерти), потом из ячеек.
## Если столько нет — ничего не трогает и возвращает false.
func remove(id: String, count: int) -> bool:
	if count_of(id) < count:
		return false
	var left := count
	var stack := _find_stack(id)
	if not stack.is_empty():
		var take := mini(left, int(stack["count"]))
		stack["count"] = int(stack["count"]) - take
		left -= take
		if int(stack["count"]) == 0:
			backpack.erase(stack)
	for slot in primary:
		if left > 0 and not slot.is_empty() and slot["id"] == id:
			var take := mini(left, int(slot["count"]))
			slot["count"] = int(slot["count"]) - take
			left -= take
			if int(slot["count"]) == 0:
				slot.clear()
	return true


## Переложить ячейку в рюкзак — целиком или count штук (деление кучи, 12.8), если влезает.
## false — не влезло, ничего не тронуто.
func move_slot_to_backpack(slot_index: int, count: int = -1) -> bool:
	var slot: Dictionary = primary[slot_index]
	if slot.is_empty():
		return false
	var moving := int(slot["count"]) if count < 0 else mini(count, int(slot["count"]))
	if moving <= 0 or backpack_room(slot["id"]) < moving:
		return false
	add_backpack(slot["id"], moving)
	slot["count"] = int(slot["count"]) - moving
	if int(slot["count"]) == 0:
		slot.clear()
	return true


## Поменять местами две ячейки Системы (перетаскивание).
func swap_slots(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= primary.size() or b >= primary.size():
		return
	var copy := primary[a].duplicate()
	primary[a].clear()
	primary[a].merge(primary[b])
	primary[b].clear()
	primary[b].merge(copy)


## Переложить из рюкзака в ячейки сколько влезет (или не больше count). Возвращает, сколько
## переложено.
func move_backpack_to_primary(id: String, count: int = -1) -> int:
	var stack := _find_stack(id)
	if stack.is_empty():
		return 0
	var want := int(stack["count"]) if count < 0 else mini(count, int(stack["count"]))
	var moving := mini(want, primary_room(id))
	if moving > 0:
		add_primary(id, moving)
		remove_from_backpack(id, moving)
	return moving


func remove_from_backpack(id: String, count: int) -> bool:
	var stack := _find_stack(id)
	if stack.is_empty() or int(stack["count"]) < count:
		return false
	stack["count"] = int(stack["count"]) - count
	if int(stack["count"]) == 0:
		backpack.erase(stack)
	return true


## Смерть: рюкзак уходит на труп, ячейки остаются. Возвращает содержимое рюкзака.
func take_backpack() -> Array[Dictionary]:
	var taken := backpack.duplicate(true)
	backpack.clear()
	return taken


func to_dict() -> Dictionary:
	return {"primary": primary.duplicate(true), "backpack": backpack.duplicate(true)}


func load_dict(data: Dictionary) -> void:
	var saved_primary: Array = data.get("primary", [])
	primary.clear()
	for slot: Dictionary in saved_primary:
		primary.append({} if slot.is_empty() else {"id": String(slot["id"]), "count": int(slot["count"])})
	set_slot_count(maxi(primary.size(), int(_config["primary"]["slots_start"])))
	backpack.clear()
	for stack: Dictionary in data.get("backpack", []):
		if _db.has_item(String(stack["id"])):
			backpack.append({"id": String(stack["id"]), "count": int(stack["count"])})


func _find_stack(id: String) -> Dictionary:
	for stack in backpack:
		if stack["id"] == id:
			return stack
	return {}
