class_name ItemTable
extends RefCounted
## Правила таблицы предметов (12.8, как SkyUI): строки из инвентаря, вкладки-фильтры, поиск,
## сортировка по столбцам, редкость, сравнение оружия с надетым, «Взять всё» по ценности и хлам.
## Чистые правила без Node; окно — src/ui/inventory_panel.gd. Данные — data/ui.json.

const REQUIRED_KEYS: PackedStringArray = ["tabs", "junk_categories", "columns", "rarity", "rarity_colors",
	"icons", "quick_slots", "tooltip_delay_s", "compare"]
const PRIMARY := "primary"
const BACKPACK := "backpack"

var _config: Dictionary
var _db: ItemDB


func _init(config: Dictionary, db: ItemDB) -> void:
	_config = config
	_db = db


func config() -> Dictionary:
	return _config


## Строка таблицы: {"id", "count", "where" (primary/backpack/container), "slot" (номер ячейки или −1),
## "unit_g", "weight_g", "price" (базовая цена штуки), "value", "price_kg", "category", "junk"}.
func row(id: String, count: int, where: String, slot: int = -1, junk_marks: Dictionary = {}) -> Dictionary:
	var unit := _db.weight_g(id)
	var price := float(_db.item(id).get("base_price", 0))
	var category := _db.category(id)
	return {
		"id": id, "count": count, "where": where, "slot": slot, "unit_g": unit, "weight_g": unit * count,
		"price": price, "value": price * count, "price_kg": price / maxf(unit / 1000.0, 0.001),
		"category": category, "junk": is_junk(id, junk_marks),
	}


## Все строки инвентаря: ячейки Системы, затем рюкзак.
func rows(inventory: Inventory, junk_marks: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in inventory.primary.size():
		var slot: Dictionary = inventory.primary[i]
		if not slot.is_empty():
			result.append(row(String(slot["id"]), int(slot["count"]), PRIMARY, i, junk_marks))
	for stack in inventory.backpack:
		result.append(row(String(stack["id"]), int(stack["count"]), BACKPACK, -1, junk_marks))
	return result


## Строки чужого контейнера (труп, тайник): [{"id", "count"}] или [[id, count]].
func container_rows(stacks: Array, junk_marks: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stack: Variant in stacks:
		var id := String(stack["id"] if stack is Dictionary else stack[0])
		var count := int(stack["count"] if stack is Dictionary else stack[1])
		if _db.has_item(id):
			result.append(row(id, count, "container", -1, junk_marks))
	return result


func is_junk(id: String, junk_marks: Dictionary = {}) -> bool:
	return junk_marks.has(id) or (_config["junk_categories"] as Array).has(_db.category(id))


func tab_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for tab: Dictionary in _config["tabs"]:
		ids.append(String(tab["id"]))
	return ids


## Вкладка и строка поиска (без учёта регистра, по названию). names — {id: название}.
func filter(list: Array[Dictionary], tab_id: String, search: String, names: Dictionary) -> Array[Dictionary]:
	var tab: Dictionary = {}
	for t: Dictionary in _config["tabs"]:
		if String(t["id"]) == tab_id:
			tab = t
	var categories: Array = tab.get("categories", [])
	var marked := bool(tab.get("marked_junk", false))
	var needle := search.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for r in list:
		if not categories.is_empty() and not categories.has(r["category"]) and not (marked and bool(r["junk"])):
			continue
		if not needle.is_empty() and not String(names.get(r["id"], r["id"])).to_lower().contains(needle):
			continue
		result.append(r)
	return result


## Сортировка по столбцу: name, count, weight, price, price_kg. При равенстве — по названию.
func sorted(list: Array[Dictionary], column: String, descending: bool, names: Dictionary) -> Array[Dictionary]:
	var key: String = {"weight": "weight_g", "price": "price", "price_kg": "price_kg", "count": "count"}.get(column, "")
	var result := list.duplicate()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_a := String(names.get(a["id"], a["id"]))
		var name_b := String(names.get(b["id"], b["id"]))
		if key.is_empty():
			return name_a.naturalnocasecmp_to(name_b) > 0 if descending else name_a.naturalnocasecmp_to(name_b) < 0
		var va := float(a[key])
		var vb := float(b[key])
		if is_equal_approx(va, vb):
			return name_a.naturalnocasecmp_to(name_b) < 0
		return va > vb if descending else va < vb)
	return result


## Редкость по базовой цене штуки: common, good, rare, epic.
func rarity(id: String) -> String:
	var price := float(_db.item(id).get("base_price", 0))
	for entry: Array in _config["rarity"]:
		if price >= float(entry[0]):
			return String(entry[1])
	return "common"


func rarity_color(id: String) -> Color:
	var c: Array = _config["rarity_colors"][rarity(id)]
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Силуэт иконки: поле icon предмета или по категории.
func icon(id: String) -> String:
	var item := _db.item(id)
	return String(item.get("icon", _config["icons"].get(_db.category(id), "box")))


## Сравнение оружия с надетым: [[ключ, значение у предмета, у надетого, знак]]; знак +1 — лучше,
## −1 — хуже, 0 — так же. Разные виды (ближнее / дальнее) — сравниваются по своему списку
## предмета, отсутствующее у надетого — пропускается. noise_radii — {ключ шума: радиус}.
func compare(item: Dictionary, equipped: Dictionary, noise_radii: Dictionary) -> Array:
	var result: Array = []
	if item.is_empty() or equipped.is_empty():
		return result
	var kind := String(item.get("kind", "melee"))
	for spec: Array in _config["compare"].get(kind, []):
		var a: Variant = _value(item, String(spec[1]), noise_radii)
		var b: Variant = _value(equipped, String(spec[1]), noise_radii)
		if a == null or b == null:
			continue
		var fa := float(a)
		var fb := float(b)
		var sign := 0
		if not is_equal_approx(fa, fb):
			sign = 1 if (fa > fb) == (String(spec[2]) == "high") else -1
		result.append([String(spec[0]), fa, fb, sign])
	return result


static func _value(weapon: Dictionary, path: String, noise_radii: Dictionary) -> Variant:
	var value: Variant = weapon
	for part in path.split("."):
		if not value is Dictionary or not (value as Dictionary).has(part):
			return null
		value = value[part]
	if path == "noise":
		return noise_radii.get(String(value), null)
	return value


## «Взять всё»: что ценнее за килограмм — вперёд; что не влезло — остаётся. stacks — [{"id",
## "count"}]. add — Callable(id, count) → сколько не влезло (Inventory.add(...)["left"]).
## Возвращает {"taken": [{"id", "count"}], "left": [{"id", "count"}]}.
func take_all(stacks: Array, add: Callable) -> Dictionary:
	var order := container_rows(stacks)
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["price_kg"]) > float(b["price_kg"]))
	var taken: Array = []
	var left: Array = []
	for r in order:
		var rest := int(add.call(String(r["id"]), int(r["count"])))
		if int(r["count"]) - rest > 0:
			taken.append({"id": r["id"], "count": int(r["count"]) - rest})
		if rest > 0:
			left.append({"id": r["id"], "count": rest})
	return {"taken": taken, "left": left}


## Хлам на продажу: строки рюкзака с пометкой хлама (ячейки Системы не трогаем — там ценное).
func junk_to_sell(list: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for r in list:
		if bool(r["junk"]) and r["where"] == BACKPACK:
			result.append(r)
	return result
