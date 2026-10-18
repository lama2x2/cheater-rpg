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
