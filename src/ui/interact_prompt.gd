extends CanvasLayer
## Подсказка «[E] …» над нижним краем экрана, когда рядом есть с чем взаимодействовать.

var hero: Node3D

var _label: Label


func _ready() -> void:
	_label = UiKit.label(18, Color(0.95, 0.9, 0.7))
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_top = -190
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _process(_delta: float) -> void:
	var target: Node3D = hero.current_interactable if hero and hero.visible else null
	_label.text = target.interact_text() if target else ""
