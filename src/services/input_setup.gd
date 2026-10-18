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
	"debug_die": [KEY_K],
	"debug_save": [KEY_F5],
	"debug_load": [KEY_F9],
	"debug_skip_respawn": [KEY_F8],
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
