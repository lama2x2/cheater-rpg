class_name WeaponDB
extends RefCounted
## Боевые свойства оружия из data/weapons.json. Чистый класс без Node.

const REQUIRED_KEYS: PackedStringArray = ["weapons"]
const FISTS := "fists"

var _weapons: Dictionary = {}


func _init(data: Dictionary) -> void:
	for weapon: Dictionary in data.get("weapons", []):
		_weapons[String(weapon["id"])] = weapon


func has_weapon(id: String) -> bool:
	return _weapons.has(id)


func weapon(id: String) -> Dictionary:
	assert(_weapons.has(id), "Неизвестное оружие: %s" % id)
	return _weapons[id]


func ids() -> PackedStringArray:
	return PackedStringArray(_weapons.keys())


func is_ranged(id: String) -> bool:
	return weapon(id)["kind"] == "ranged"
