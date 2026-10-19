class_name InputSetup
extends RefCounted
## Действия ввода задаются кодом (не в project.godot), чтобы их было видно в diff.
## Физические клавиши — WASD работает и на русской раскладке.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"sneak": [KEY_C],
	"interact": [KEY_E],
	"reload": [KEY_R],
	"weapon_next": [KEY_Q],
	"inventory": [KEY_TAB, KEY_I],
	"menu": [KEY_ESCAPE],
	"skill_1": [KEY_1],
	"skill_2": [KEY_2],
	"skill_3": [KEY_3],
	"skill_4": [KEY_4],
	"skill_5": [KEY_5],
	"skill_6": [KEY_6],
	"skill_7": [KEY_7],
	"skill_8": [KEY_8],
	"skills": [KEY_U],
	"gaze": [KEY_ALT],
	"map": [KEY_M],
	"minimap": [KEY_N],
	"character": [KEY_P],
	"quick_1": [KEY_F1],
	"quick_2": [KEY_F2],
	"quick_3": [KEY_F3],
	"quick_4": [KEY_F4],
	"debug_die": [KEY_K],
	"debug_save": [KEY_F5],
	"debug_load": [KEY_F9],
	"debug_skip_respawn": [KEY_F8],
}

const MOUSE_ACTIONS := {
	"attack": MOUSE_BUTTON_LEFT,
}


static func ensure_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: String in MOUSE_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_ACTIONS[action]
		InputMap.action_add_event(action, click)


## Переназначения игрока (KeyBindings, настройка keys) — поверх умолчаний: события клавиатуры
## действия заменяются его клавишами; мышь не трогается.
static func apply_bindings(saved: Dictionary) -> KeyBindings:
	var bindings := KeyBindings.new(ACTIONS, saved)
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		for keycode in bindings.keys(action):
			var key := InputEventKey.new()
			key.physical_keycode = keycode as Key
			InputMap.action_add_event(action, key)
	return bindings


## Подпись клавиши действия для подсказок интерфейса: «Tab», «M», «F1».
static func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			# Физическая клавиша — подпись по латинской раскладке (WASD и на русской).
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	return "?"
