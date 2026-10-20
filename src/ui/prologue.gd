extends CanvasLayer
## Пролог-воспоминание (01, задача 17): несколько карточек текста на чёрном — обычная жизнь, потом
## обрыв. Пробел / Enter / клик — дальше, Esc — пропустить. Игра на это время стоит (как титул).

var _cards: Array = []
var _index := 0
var _text: Label
var _hint: Label


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cards = Content.onboarding_rules().config()["prologue"]
	get_tree().paused = true
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.01, 0.015, 1.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	_text = UiKit.label(24, Color(0.88, 0.88, 0.84))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size.x = minf(900.0, get_viewport().get_visible_rect().size.x - 80.0)
	box.add_child(_text)
	_hint = UiKit.label(14, UiKit.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = Content.ui("prologue_hint")
	box.add_child(_hint)
	_show()


func _show() -> void:
	_text.text = Content.ui(String(_cards[_index]))
	_text.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_text, "modulate:a", 1.0, 0.6)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if key and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		if key.physical_keycode == KEY_ESCAPE:
			_finish()
		elif key.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			_next()
	elif click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_next()


func _next() -> void:
	_index += 1
	if _index >= _cards.size():
		_finish()
	else:
		_show()


func _finish() -> void:
	get_tree().paused = false
	PlayerState.onboarding_event("prologue_done")
	queue_free()
