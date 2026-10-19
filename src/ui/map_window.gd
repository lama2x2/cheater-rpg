extends CanvasLayer
## Карта (12.6, клавиша M): вкладка «Регион» — соты по типам, известные таймеры, отметки, граница
## региона; вкладка «Кластер» — раскладка текущего кластера: увиденные или купленные постройки,
## выходы, респ, свой труп, найденные тайники, отметки игрока. Клик — поставить/убрать отметку.
## Игра на паузу не встаёт (D-05). Знание карты — WorldSim.knowledge.

const REGION := "region"
const CLUSTER := "cluster"
const MARGIN := 24.0

var tab := CLUSTER
var _panel: PanelContainer
var _canvas: Control
var _title: Label
var _hint: Label
var _tabs: Dictionary = {}
var _centers: Dictionary = {}


func _ready() -> void:
	layer = 7
	visible = false
	add_to_group("map_window")
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.93)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	# Тянется под окно с полями — влезает при любом масштабе интерфейса (12.6a).
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_panel.set_offset(side, MARGIN if side in [SIDE_LEFT, SIDE_TOP] else -MARGIN)
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	_title = UiKit.label(19, Color(0.95, 0.78, 0.3))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	for key in [CLUSTER, REGION]:
		var button := _button(Content.ui("map_tab_" + key), _select.bind(key))
		header.add_child(button)
		_tabs[key] = button
	header.add_child(_button("×", close))
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(320, 240)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_canvas_input)
	root.add_child(_canvas)
	_hint = UiKit.label(13, Color(0.7, 0.72, 0.7))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)
	EventBus.map_changed.connect(_canvas.queue_redraw)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open(tab)


func open(which: String = CLUSTER) -> void:
	visible = true
	_select(which)


func close() -> void:
	visible = false


func _select(which: String) -> void:
	tab = which
	for key: String in _tabs:
		(_tabs[key] as Button).disabled = key == tab
	_title.text = Content.ui("map_title_" + tab, {"name": WorldSim.cluster_name(), "code": WorldSim.region.cluster(WorldSim.current)["code"]})
	_hint.text = Content.ui("map_hint_" + tab)
	_canvas.queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _draw_canvas() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.9))
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	var angle := MapDraw.rotation_for(get_viewport().get_camera_3d())
	if tab == REGION:
		_centers = MapDraw.draw_region(_canvas, size / 2.0, _cell_px(), angle, hero)
	else:
		var area := get_tree().get_first_node_in_group("cluster_area") as Node3D
		if area == null:
			return
		var xf := _cluster_xf(area, angle)
		MapDraw.draw_cluster(_canvas, xf, area, {"labels": true, "font": 14})
		if hero:
			var vision := get_tree().get_first_node_in_group("hero_vision")
			MapDraw.draw_hero(_canvas, xf, hero, float(vision.get("_reach")) if vision else 0.0)
		var known := WorldSim.knowledge.seen_count(WorldSim.current)
		var total: int = (area.layout["buildings"] as Array).size()
		var line := Content.ui("map_buildings_full") if WorldSim.knowledge.is_mapped(WorldSim.current) \
			else Content.ui("map_buildings_seen", {"n": known, "total": total})
		MapDraw._text(_canvas, UiKit.font(), Vector2(size.x / 2.0, size.y - 12.0), line, 13, Color(0.75, 0.8, 0.75))
	MapDraw.draw_north(_canvas, Vector2(size.x - 36.0, 48.0), angle, 14)


## Радиус соты на карте региона: срез (3 соты в поперечнике) занимает большую часть холста.
func _cell_px() -> float:
	return clampf(minf(_canvas.size.x, _canvas.size.y) / 6.5, 40.0, 110.0)


func _cluster_xf(area: Node3D, angle: float) -> Transform2D:
	var size := _canvas.size
	var reach := float(area.template["size"]) / HexGrid.SQRT3  # радиус до вершины
	var scale := (minf(size.x, size.y) / 2.0 - 24.0) / reach
	return MapDraw.transform(size / 2.0, Vector2.ZERO, scale, angle)


func _on_canvas_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if tab == REGION:
		for id: String in _centers:
			if (_centers[id] as Vector2).distance_to(click.position) < _cell_px() * 0.75:
				WorldSim.knowledge.toggle_region_mark(id)
				EventBus.map_changed.emit()
				return
		return
	var area := get_tree().get_first_node_in_group("cluster_area") as Node3D
	if area == null:
		return
	var xf := _cluster_xf(area, MapDraw.rotation_for(get_viewport().get_camera_3d()))
	var world := xf.affine_inverse() * click.position
	if HexGrid.inside(world, float(area.template["size"]) / 2.0):
		WorldSim.knowledge.toggle_mark(WorldSim.current, world, float(Content.map_config()["mark_radius_m"]))
		EventBus.map_changed.emit()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UiKit.font())
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button
