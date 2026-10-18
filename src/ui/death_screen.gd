extends CanvasLayer
## Экран «Жизнь N закончилась»: затемнение, причина, «рекомендация» Системы, отсчёт до возрождения.
## Спецификация: docs/spec/04_death_lives.md, 4.2.

var _shade: ColorRect
var _title: Label
var _cause: Label
var _advice: Label
var _timer: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 10
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.0)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_title = UiKit.label(40, Color(0.85, 0.2, 0.15))
	_cause = UiKit.label(20, Color(0.85, 0.85, 0.85))
	_advice = UiKit.label(16, Color(0.6, 0.75, 0.6))
	_timer = UiKit.label(18, Color(0.9, 0.9, 0.9))
	for label: Label in [_title, _cause, _advice, _timer]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)


func open(life: int, cause: String) -> void:
	_title.text = Content.ui("death_title", {"life": life})
	_cause.text = Content.ui("death_cause", {"cause": Content.death_cause(cause)})
	var advice: Array = Content.texts()["death_advice"]
	_advice.text = Content.ui("death_advice", {"advice": advice[_rng.randi_range(0, advice.size() - 1)]})
	_timer.text = ""
	visible = true
	_shade.color.a = 0.0
	create_tween().tween_property(_shade, "color:a", 0.88, 1.5)


func set_remaining(seconds: float) -> void:
	var s := ceili(seconds)
	var text := Content.ui("respawn_in", {"time": "%d:%02d" % [s / 60, s % 60]})
	if OS.is_debug_build():
		text += "\n" + Content.ui("respawn_skip_hint")
	_timer.text = text


func close() -> void:
	visible = false
