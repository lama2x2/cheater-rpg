class_name KeyBindings
extends RefCounted
## Привязки клавиш (12.7, 12.8): умолчания — InputSetup.ACTIONS, поверх — переназначения игрока
## {действие: физическая клавиша} (хранятся в user://settings.json, ключ keys). Конфликты — одна
## клавиша у двух действий; сброс. Чистые правила без Node; применение к InputMap — InputSetup.

## Что не переназначается: Esc — меню и «закрыть окно», отладочные клавиши.
const FIXED: PackedStringArray = ["menu", "debug_die", "debug_save", "debug_load", "debug_skip_respawn"]

var defaults: Dictionary = {}
var overrides: Dictionary = {}


func _init(default_actions: Dictionary, saved: Dictionary = {}) -> void:
	defaults = default_actions
	load_dict(saved)


## Действия, которые можно переназначить, в порядке InputSetup.ACTIONS.
func actions() -> PackedStringArray:
	var result: PackedStringArray = []
	for action: String in defaults:
		if not FIXED.has(action):
			result.append(action)
	return result


## Клавиши действия: переназначенная (одна) или умолчания.
func keys(action: String) -> Array[int]:
	var result: Array[int] = []
	if overrides.has(action):
		result.append(int(overrides[action]))
		return result
	for key in defaults.get(action, []):
		result.append(int(key))
	return result


## Назначить клавишу. Возвращает действия, у которых теперь та же клавиша (конфликт).
func bind(action: String, keycode: int) -> PackedStringArray:
	if FIXED.has(action) or not defaults.has(action):
		return PackedStringArray()
	if (defaults[action] as Array).size() == 1 and int(defaults[action][0]) == keycode:
		overrides.erase(action)
	else:
		overrides[action] = keycode
	return users(keycode, action)


## Кто ещё сидит на клавише (кроме except).
func users(keycode: int, except: String = "") -> PackedStringArray:
	var result: PackedStringArray = []
	for other: String in defaults:
		if other != except and keys(other).has(keycode):
			result.append(other)
	return result


## Все конфликты: {клавиша: [действия]} — где на одной клавише больше одного действия.
func conflicts() -> Dictionary:
	var by_key := {}
	for action: String in defaults:
		for key in keys(action):
			if not by_key.has(key):
				by_key[key] = []
			by_key[key].append(action)
	var result := {}
	for key: int in by_key:
		if (by_key[key] as Array).size() > 1:
			result[key] = by_key[key]
	return result


func reset() -> void:
	overrides.clear()


func to_dict() -> Dictionary:
	return overrides.duplicate()


## Испорченное и неизвестное пропускается.
func load_dict(saved: Dictionary) -> void:
	overrides = {}
	for action: String in saved:
		var value: Variant = saved[action]
		if defaults.has(action) and not FIXED.has(action) and (value is int or value is float) and int(value) > 0:
			overrides[action] = int(value)
