extends Node3D
## Умения героя в сцене: клавиши 1–4 — слоты, золотое сияние под Улыбкой Фортуны, всплывающие
## надписи удачи («мимо!», «удача!») и иммунитета. Правила — SkillRules (src/core), применение
## чисел — PlayerState; сценовые эффекты умений 13b подписываются на EventBus.skill_used.
## Спецификация: docs/spec/05_skills.md.

const SLOT_ACTIONS: PackedStringArray = ["skill_1", "skill_2", "skill_3", "skill_4"]
const FLOAT_TEXT := {
	"enemy_miss": ["luck_float_miss", Color(1.0, 0.85, 0.3)],
	"enemy_stumble": ["luck_float_stumble", Color(1.0, 0.85, 0.3)],
	"hero_crit": ["luck_float_crit", Color(1.0, 0.75, 0.15)],
	"unnoticed": ["luck_float_unnoticed", Color(1.0, 0.85, 0.3)],
	"immunity": ["immunity_float", Color(0.7, 0.9, 1.0)],
}

var hero: CharacterBody3D
var _aura: MeshInstance3D
var _aura_material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_build_aura()
	EventBus.luck_event.connect(_on_luck_event)


func _process(delta: float) -> void:
	_time += delta
	var lucky := PlayerState.buffs.multiplier("luck", GameClock.minutes) >= 2.0
	var immune := PlayerState.skills.has_status("immunity", GameClock.minutes)
	_aura.visible = (lucky or immune) and hero.visible
	if _aura.visible:
		var pulse := 0.35 + 0.15 * sin(_time * 6.0)
		_aura_material.albedo_color = Color(0.7, 0.9, 1.0, pulse) if immune else Color(1.0, 0.8, 0.25, pulse)
		_aura.rotation.y += delta * 1.5


func _unhandled_input(event: InputEvent) -> void:
	if not hero.visible:
		return
	for i in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			PlayerState.use_skill_slot(i)
			get_viewport().set_input_as_handled()
			return


func _on_luck_event(kind: String, at: Vector3) -> void:
	if not FLOAT_TEXT.has(kind) or not is_inside_tree():
		return
	var spec: Array = FLOAT_TEXT[kind]
	var where := at if at != Vector3.INF else hero.global_position + Vector3.UP * 2.4
	float_text(get_tree().current_scene, where, Content.ui(spec[0]), spec[1])


## Всплывающая надпись над точкой: поднимается и гаснет за 0,9 с.
static func float_text(parent: Node, at: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.014
	label.outline_size = 8
	label.text = text
	label.modulate = color
	parent.add_child(label)
	label.global_position = at
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", at.y + 1.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(label.queue_free)


func _build_aura() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.75
	torus.rings = 32
	torus.ring_segments = 6
	_aura_material = StandardMaterial3D.new()
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.albedo_color = Color(1.0, 0.8, 0.25, 0.4)
	_aura = MeshInstance3D.new()
	_aura.mesh = torus
	_aura.material_override = _aura_material
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.position = Vector3(0, 0.08, 0)
	_aura.scale = Vector3(1, 0.15, 1)
	_aura.visible = false
	add_child(_aura)
