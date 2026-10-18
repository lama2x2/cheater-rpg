extends Node3D
## Раздаёт шумовые импульсы тварям: радиус по NoiseModel (src/core), стены между источником и
## слушателем — лучами, громкость — в infected.hear(). Источник шлёт EventBus.noise_made.
## Вокруг героя рисует кольцо шума (обучающее, 12.1; выключается в data/noise.json).

const RAY_LIFT := Vector3(0, 1.0, 0)
const LAYER_WORLD := 1

var model: NoiseModel
var weather := "clear"


func _ready() -> void:
	add_to_group("noise_system")
	model = NoiseModel.new(Content.noise_config())
	EventBus.noise_made.connect(_on_noise)


func _process(delta: float) -> void:
	model.cool_down(delta)


func _on_noise(source: String, at: Vector3, options: Dictionary) -> void:
	var opts := options.duplicate()
	opts["weather"] = weather
	var r := model.radius(source, opts)
	model.register(r)
	for infected: Node3D in get_tree().get_nodes_in_group("infected"):
		var distance := Vector2(infected.global_position.x - at.x, infected.global_position.z - at.z).length()
		if distance >= r:
			continue
		var loudness := model.loudness_at(r, distance, _walls_between(at, infected.global_position))
		if loudness > 0.0:
			infected.hear(at, loudness)
	if bool(options.get("from_hero", false)) and bool(Content.noise_config()["debug_ring"]):
		_ring(at, r)


## Сколько стен между точками (до max_walls): луч, потом луч дальше за препятствием.
func _walls_between(from: Vector3, to: Vector3) -> int:
	var space := get_world_3d().direct_space_state
	var walls := 0
	var exclude: Array[RID] = []
	var max_walls := int(Content.noise_config()["max_walls"])
	while walls < max_walls:
		var query := PhysicsRayQueryParameters3D.create(from + RAY_LIFT, to + RAY_LIFT, LAYER_WORLD, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		walls += 1
		exclude.append(hit["rid"])
	return walls


func _ring(at: Vector3, r: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.0, r - 0.08)
	torus.outer_radius = r
	torus.rings = 48
	torus.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.9, 0.5, 0.55) if r < 20.0 else Color(1.0, 0.4, 0.3, 0.7)
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(at.x, 0.05, at.z)
	ring.scale = Vector3(1, 0.05, 1)
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.7)
	tween.tween_callback(ring.queue_free)
