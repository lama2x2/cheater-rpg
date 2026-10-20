extends CanvasLayer
## Подсказка онбординга (задача 17): строка вверху по центру — что делать сейчас («Осмотрите
## тварь: зажмите Alt»…). Клавиши — из текущих привязок. Исчезает после выхода в стаб.

var _label: Label


func _ready() -> void:
	layer = 3
	add_to_group("hud_layers")
	_label = UiKit.label(17, Color(0.95, 0.9, 0.65))
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_top = 150
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 720
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	PlayerState.onboarding_changed.connect(func(_s: String) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var key := Content.onboarding_rules().hint(PlayerState.onboarding_step)
	if key.is_empty() or PlayerState.awaiting_respawn:
		_label.text = ""
		return
	var k := func(action: String) -> String: return InputSetup.key_label(action)
	_label.text = "▸ " + Content.ui(key, {
		"move": k.call("move_forward") + k.call("move_left") + k.call("move_back") + k.call("move_right"),
		"sprint": k.call("sprint"), "gaze": k.call("gaze"), "interact": k.call("interact"),
		"inventory": k.call("inventory"), "map": k.call("map"), "sneak": k.call("sneak"), "char": k.call("character"),
	})


func _process(_delta: float) -> void:
	_label.visible = not PlayerState.awaiting_respawn
