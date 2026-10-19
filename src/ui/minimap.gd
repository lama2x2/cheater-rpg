extends CanvasLayer
## Миникарта (12.6, D-72): полупрозрачный квадрат в правом верхнем углу — текущий кластер вокруг
## героя (известные постройки, выходы, отметки, респ, труп), герой и его взгляд, название и таймер.
## Тварей не показывает. Повёрнута как камера. N — спрятать/показать (и настройка «Миникарта»).

var _canvas: Control
var _caption: Label
var _style: StyleBoxFlat


func _ready() -> void:
	layer = 2
	add_to_group("minimap")
	var config: Dictionary = Content.map_config()["minimap"]
	var side := float(config["size_px"])
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -side - 16.0
	box.offset_right = -16.0
	box.offset_top = 16.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(side, side)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	box.add_child(_canvas)
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.03, 0.04, 0.05, float(config["alpha"]))
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(1)
	_style.border_color = Color(0.7, 0.75, 0.7, 0.35)
	_caption = UiKit.label(13, Color(0.85, 0.88, 0.85))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.custom_minimum_size.x = side
	box.add_child(_caption)
	EventBus.map_changed.connect(_canvas.queue_redraw)
	Settings.changed.connect(_on_settings)
	_on_settings()


func _on_settings(_key: String = "") -> void:
	visible = bool(Settings.value("minimap"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("minimap"):
		Settings.change("minimap", not bool(Settings.value("minimap")))
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	_canvas.queue_redraw()
	_caption.text = "%s · ⏱ %s" % [WorldSim.cluster_name(), WorldSim.timer_text()]


func _draw_map() -> void:
	var size := _canvas.size
	_canvas.draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	var area := get_tree().get_first_node_in_group("cluster_area") as Node3D
	if hero == null or area == null:
		return
	var radius := float(Content.map_config()["minimap"]["radius_m"])
	var scale := size.x / 2.0 / radius
	var angle := MapDraw.rotation_for(get_viewport().get_camera_3d())
	var focus := Vector2(hero.global_position.x, hero.global_position.z)
	var xf := MapDraw.transform(size / 2.0, focus, scale, angle)
	MapDraw.draw_cluster(_canvas, xf, area, {"font": 11})
	var vision := get_tree().get_first_node_in_group("hero_vision")
	MapDraw.draw_hero(_canvas, xf, hero, float(vision.get("_reach")) if vision else 0.0)
	MapDraw.draw_north(_canvas, Vector2(size.x - 26.0, 40.0), angle, 11)
