class_name CharacterModel
extends Node3D
## Модель персонажа (задача 19): Kenney «Animated Characters Survivors» (CC0) — скин-текстура,
## рост и ширина, оттенок (стадия, особь, уровень), бронепластины на костях, анимации idle/run
## по скорости, поза «ползёт». Данные — data/looks.json. Группа "vision_body": зрение героя прячет
## модель целиком (src/world/hero_vision.gd).

static var _scene: PackedScene
static var _library: AnimationLibrary
static var _config: Dictionary = {}

var look_id := "hero"
var _anim: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _run_speed := 4.0
var _state := ""


static func config() -> Dictionary:
	if _config.is_empty():
		_config = JsonData.load_dict("res://data/looks.json", ["model", "animations", "skin_dir", "model_height", "plate_color", "looks"])
	return _config


## look — ключ из data/looks.json; level_fraction 0..1 — уровень внутри стадии; rng — разброс особи.
static func make(look: String, level_fraction: float = 0.0, rng: RandomNumberGenerator = null) -> CharacterModel:
	var model := CharacterModel.new()
	model.look_id = look
	model._build(level_fraction, rng)
	return model


func _build(level_fraction: float, rng: RandomNumberGenerator) -> void:
	add_to_group("vision_body")
	var cfg := config()
	var look: Dictionary = cfg["looks"].get(look_id, cfg["looks"]["hero"])
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if _scene == null:
		_scene = load(String(cfg["model"]))
	var body: Node3D = _scene.instantiate()
	add_child(body)
	var k := float(look["height_m"]) / float(cfg["model_height"])
	var w := float(look.get("width", 1.0))
	body.scale = Vector3(k * w, k, k * w)
	body.rotation.y = PI  # модель смотрит на +z, вперёд в Godot — −z
	var skins: Array = look["skins"]
	var skin := load(String(cfg["skin_dir"]) + String(skins[rng.randi_range(0, skins.size() - 1)]) + ".png") as Texture2D
	var tint := _color(look["tint"])
	var spread := float(look.get("tint_spread", 0.0))
	tint = Color(tint.r * (1.0 + rng.randf_range(-spread, spread)), tint.g * (1.0 + rng.randf_range(-spread, spread)), tint.b * (1.0 + rng.randf_range(-spread, spread)))
	if look.has("level_tint"):
		tint = tint.lerp(_color(look["level_tint"]), clampf(level_fraction, 0.0, 1.0))
	for mesh: Node in body.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_texture = skin
		m.albedo_color = tint
		m.roughness = 1.0
		(mesh as MeshInstance3D).material_override = m
		_materials.append(m)
	_run_speed = float(look.get("run_speed", 4.0))
	_add_animations(body)
	_add_plates(body, look.get("plates", []), cfg)
	if String(look.get("posture", "upright")) == "crawl":
		body.rotation.x = deg_to_rad(80.0)  # лицом вниз, голова вперёд
		body.position = Vector3(0, 0.3, 0.7)


func _add_animations(body: Node3D) -> void:
	if _library == null:
		_library = AnimationLibrary.new()
		var anims: Dictionary = config()["animations"]
		for name: String in anims:
			var source: Node = (load(String(anims[name])) as PackedScene).instantiate()
			var player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
			for anim_name in player.get_animation_list():
				if anim_name.ends_with("Targeting Pose"):
					continue
				var a := player.get_animation(anim_name).duplicate() as Animation
				a.loop_mode = Animation.LOOP_LINEAR
				_library.add_animation(name, a)
				break
			source.free()
	_anim = AnimationPlayer.new()
	body.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library("", _library)
	_play("idle", 1.0)


## Скорость по земле, м/с: стоит — idle, движется — run со скоростью от run_speed.
func set_speed(speed: float) -> void:
	if speed < 0.4:
		_play("idle", 1.0)
	else:
		_play("run", clampf(speed / _run_speed, 0.35, 1.6))


func freeze() -> void:
	if _anim:
		_anim.pause()


## Лежит (труп, раненый): на спине, без анимации.
func lie_down() -> void:
	var body := get_child(0) as Node3D
	if body:
		body.rotation = Vector3(-PI / 2.0, PI, 0.0)
		body.position = Vector3(0, 0.25, -0.9)
	freeze()


func set_tint_mult(mult: Color) -> void:
	for m in _materials:
		m.albedo_color = m.albedo_color * mult


func _play(name: String, speed: float) -> void:
	if _anim == null or not _anim.has_animation(name):
		return
	_anim.speed_scale = speed
	if _state != name:
		_state = name
		_anim.play(name, 0.2)


## Пластины — тёмные коробки на костях (топтун, элита).
func _add_plates(body: Node3D, plates: Array, cfg: Dictionary) -> void:
	if plates.is_empty():
		return
	var skeleton := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = _color(cfg["plate_color"])
	material.metallic = 0.4
	material.roughness = 0.6
	# Размеры и сдвиги — в единицах модели (рост ~3,75); кости внутри узла с масштабом 100.
	var spec := {
		"head": [["Head", Vector3(0.85, 0.22, 0.85), Vector3(0, 0.72, 0)]],
		"chest": [["Chest", Vector3(0.8, 0.55, 0.16), Vector3(0, 0.25, 0.3)]],
		"back": [["Chest", Vector3(0.85, 0.6, 0.16), Vector3(0, 0.25, -0.3)]],
		"arms": [["LeftForeArm", Vector3(0.22, 0.5, 0.22), Vector3(0, 0.3, 0)], ["RightForeArm", Vector3(0.22, 0.5, 0.22), Vector3(0, 0.3, 0)]],
		"legs": [["LeftLeg", Vector3(0.26, 0.55, 0.26), Vector3(0, 0.35, 0)], ["RightLeg", Vector3(0.26, 0.55, 0.26), Vector3(0, 0.35, 0)]],
	}
	for zone in plates:
		for entry: Array in spec.get(String(zone), []):
			var bone := skeleton.find_bone(String(entry[0]))
			if bone < 0:
				continue
			var attach := BoneAttachment3D.new()
			attach.bone_name = String(entry[0])
			skeleton.add_child(attach)
			var box := BoxMesh.new()
			box.size = entry[1]
			var holder := Node3D.new()
			holder.scale = Vector3.ONE * 0.01
			attach.add_child(holder)
			var mesh := MeshInstance3D.new()
			mesh.mesh = box
			mesh.material_override = material
			mesh.position = entry[2]
			holder.add_child(mesh)


static func _color(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))
