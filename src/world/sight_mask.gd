extends Node
## Тень по линии взгляда (D-102, 17.1): раз в check_s веер лучей от глаз героя по кругу (по слою
## мира: стены, двери, препятствия) → многоугольник «что не закрыто», он рисуется сверху в маску
## (SubViewport). Шейдер затемнения (hero_vision) темнит всё вне маски — светлое значит «герой
## это видит»; конус и дальность шейдер затемняет сам, мягко.

const LAYER_WORLD := 1

var hero: Node3D
## Текстура маски и где она лежит в мире: левый-верхний угол (x, z) и сторона в метрах.
var texture: Texture2D
var origin := Vector2.ZERO
var size_m := 80.0

var _rules: VisionRules
var _viewport: SubViewport
var _polygon: Polygon2D
var _left := 0.0


func _ready() -> void:
	add_to_group("sight_mask")
	_rules = Content.vision_rules()
	var c := _rules.config()
	size_m = float(c["sight_mask_m"])
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(c["sight_mask_px"]), int(c["sight_mask_px"]))
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(_viewport.size)
	_viewport.add_child(bg)
	_polygon = Polygon2D.new()
	_polygon.color = Color.WHITE
	_polygon.antialiased = true
	_viewport.add_child(_polygon)
	texture = _viewport.get_texture()


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or hero == null or not hero.is_inside_tree():
		return
	_left = float(_rules.config()["check_s"])
	var vision := get_tree().get_first_node_in_group("hero_vision")
	var reach := float(vision.get("_reach")) if vision else 30.0
	var facing: Vector3 = vision.view_dir if vision else Vector3.FORWARD
	var eye := hero.global_position + Vector3.UP * float(_rules.config()["sight_eye_m"])
	var extend := float(_rules.config()["sight_extend_m"])
	var space := hero.get_world_3d().direct_space_state
	var center := Vector2(hero.global_position.x, hero.global_position.z)
	origin = center - Vector2(size_m, size_m) / 2.0
	var scale := float(_viewport.size.x) / size_m
	var points := PackedVector2Array()
	for angle in _rules.sight_fan(facing):
		var dir := Vector2.from_angle(angle)
		var to := eye + Vector3(dir.x, 0.0, dir.y) * reach
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, to, LAYER_WORLD))
		var length := reach
		if not hit.is_empty():
			var p: Vector3 = hit["position"]
			length = minf(Vector2(p.x - eye.x, p.z - eye.z).length() + extend, reach)
		points.append((center + dir * length - origin) * scale)
	_polygon.polygon = points
