class_name WeaponState
extends RefCounted
## Что у героя в руках и сколько патронов в магазинах. Патроны в запасе — в инвентаре.
## Чистый класс без Node.

var equipped: String = WeaponDB.FISTS
## Заряжено в магазине: {"pistol": 5, ...}.
var loaded: Dictionary = {}

var _db: WeaponDB


func _init(db: WeaponDB) -> void:
	_db = db


func in_magazine(id: String) -> int:
	return int(loaded.get(id, 0))


func can_fire(id: String) -> bool:
	return not _db.is_ranged(id) or in_magazine(id) > 0


## Тратит патрон из магазина. false — пусто.
func fire(id: String) -> bool:
	if not can_fire(id):
		return false
	if _db.is_ranged(id):
		loaded[id] = in_magazine(id) - 1
	return true


## Перезарядка из инвентаря. Возвращает, сколько патронов вошло (0 — нечем или полный).
## У лука магазин 1: «перезарядка» — наложить стрелу.
func reload(id: String, inventory: Inventory) -> int:
	if not _db.is_ranged(id):
		return 0
	var weapon := _db.weapon(id)
	var need := int(weapon["magazine"]) - in_magazine(id)
	var have := inventory.count_of(String(weapon["ammo"]))
	var take := mini(need, have)
	if take > 0:
		inventory.remove(String(weapon["ammo"]), take)
		loaded[id] = in_magazine(id) + take
	return take


## Оружие пропало из инвентаря (смерть, выбросил): патроны из магазина остаются «в оружии»,
## в руках — кулаки.
func drop_if_missing(inventory: Inventory) -> void:
	if equipped != WeaponDB.FISTS and inventory.count_of(equipped) < 1:
		equipped = WeaponDB.FISTS


## Оружие, которое можно взять в руки: кулаки + всё оружие из инвентаря.
func available(inventory: Inventory) -> PackedStringArray:
	var result: PackedStringArray = [WeaponDB.FISTS]
	for id in _db.ids():
		if id != WeaponDB.FISTS and inventory.count_of(id) > 0:
			result.append(id)
	return result


func cycle(inventory: Inventory) -> String:
	var list := available(inventory)
	var index := list.find(equipped)
	equipped = list[(index + 1) % list.size()]
	return equipped


func to_dict() -> Dictionary:
	return {"equipped": equipped, "loaded": loaded.duplicate()}


func load_dict(data: Dictionary) -> void:
	equipped = String(data.get("equipped", WeaponDB.FISTS))
	if not _db.has_weapon(equipped):
		equipped = WeaponDB.FISTS
	loaded.clear()
	var saved: Dictionary = data.get("loaded", {})
	for id: String in saved:
		loaded[id] = int(saved[id])
