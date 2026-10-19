extends "res://tests/test_case.gd"
## Переназначение клавиш (12.8): умолчания, замена, конфликты, сброс, испорченный файл.

const KeyBindingsScript := preload("res://src/core/key_bindings.gd")
const InputSetupScript := preload("res://src/services/input_setup.gd")


func _kb(saved: Dictionary = {}) -> KeyBindings:
	return KeyBindingsScript.new(InputSetupScript.ACTIONS, saved)


func test_defaults_have_no_conflicts() -> void:
	assert_eq(_kb().conflicts(), {}, "у умолчаний нет конфликтов")
	assert_true(_kb().keys("inventory").has(KEY_TAB), "инвентарь — Tab")


func test_bind_and_conflict() -> void:
	var kb := _kb()
	var clash := kb.bind("map", KEY_E)
	assert_eq(clash, PackedStringArray(["interact"]), "карта на E — конфликт с «взять»")
	assert_eq(kb.keys("map"), [KEY_E] as Array[int], "карта теперь на E")
	assert_true(kb.conflicts().has(KEY_E), "конфликт виден")
	kb.bind("map", KEY_M)
	assert_eq(kb.conflicts(), {}, "вернул — конфликта нет")
	assert_true(kb.to_dict().is_empty(), "умолчание не хранится")


func test_fixed_actions() -> void:
	var kb := _kb()
	assert_true(not kb.actions().has("menu"), "Esc не переназначается")
	kb.bind("menu", KEY_Q)
	assert_eq(kb.keys("menu"), [KEY_ESCAPE] as Array[int], "меню осталось на Esc")


func test_reset_and_bad_file() -> void:
	var kb := _kb({"map": KEY_J, "menu": KEY_Q, "nonsense": 5, "inventory": "Tab"})
	assert_eq(kb.keys("map"), [KEY_J] as Array[int], "переназначение из файла")
	assert_eq(kb.to_dict().size(), 1, "чужое и испорченное — пропущено")
	kb.reset()
	assert_eq(kb.keys("map"), [KEY_M] as Array[int], "сброс")
