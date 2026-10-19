extends CanvasLayer
## Чуйка (17.2): «!» вокруг героя в сторону угрозы в слепой зоне — без вида, уровня и числа.
## Близкая угроза — значок над героем. Источник — alarms в src/world/hero_vision.gd.

const RING_PX := 120.0
const ABOVE_PX := 110.0

var _labels: Array[Label] = []


func _ready() -> void:
	layer = 3


func _process(_delta: float) -> void:
	var vision := get_tree().get_first_node_in_group("hero_vision")
	var camera := get_viewport().get_camera_3d()
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	var shown := 0
	if vision and camera and hero and hero.visible:
		var close := float(Content.vision_rules().config()["sense"]["close_m"])
		var center := camera.unproject_position(hero.global_position + Vector3.UP * 1.0)
		var above_used := false
		for id in vision.alarms:
			var alarm: Dictionary = vision.alarms[id]
			var node := alarm["node"] as Node3D
			if not is_instance_valid(node):
				continue
			var at: Vector2
			if node.global_position.distance_to(hero.global_position) <= close:
				if above_used:
					continue
				above_used = true
				at = center + Vector2(0, -ABOVE_PX)
			else:
				var dir := camera.unproject_position(node.global_position + Vector3.UP * 1.0) - center
				if dir.length() < 1.0:
					continue
				at = center + dir.normalized() * RING_PX
			var label := _label(shown)
			label.position = at - label.size / 2.0
			label.modulate.a = clampf(float(alarm["left"]) / 0.4, 0.0, 1.0)
			label.visible = true
			shown += 1
	for i in range(shown, _labels.size()):
		_labels[i].visible = false


func _label(index: int) -> Label:
	while _labels.size() <= index:
		var label := UiKit.label(34, Color(1.0, 0.62, 0.2))
		label.text = "!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(30, 40)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)
	return _labels[index]
