class_name VisionRules
extends RefCounted
## Зрение героя и чуйка (17, D-69): конус взгляда и круг вокруг, дальность от времени суток,
## кисляка и Наблюдательности, поворот взгляда от Реакции, шанс чуйки. Чистые правила без лучей:
## стены проверяет сцена (src/world/hero_vision.gd). Данные — data/vision.json.

const REQUIRED_KEYS: PackedStringArray = ["cone_deg", "sprint_cone_deg", "near_m", "range_day_m",
	"range_night_m", "night_from", "night_to", "kislyak_mult", "range_per_perception",
	"angle_per_perception", "angle_bonus_max", "turn_deg_s", "turn_per_reaction", "check_s",
	"last_seen_s", "shade", "shade_soft_deg", "shade_soft_m", "fade_walls_alpha", "sense"]

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func config() -> Dictionary:
	return _config


func is_night(hour: int) -> bool:
	var from := int(_config["night_from"])
	var to := int(_config["night_to"])
	return hour >= from or hour < to if from > to else (hour >= from and hour < to)


## Дальность зрения в метрах.
func view_range(hour: int, kislyak: bool, perception_level: int) -> float:
	var r := float(_config["range_night_m"]) if is_night(hour) else float(_config["range_day_m"])
	r += float(_config["range_per_perception"]) * maxi(perception_level - 1, 0)
	if kislyak:
		r *= float(_config["kislyak_mult"])
	return r


## Полный угол конуса в градусах.
func cone_deg(sprinting: bool, perception_level: int) -> float:
	var base := float(_config["sprint_cone_deg"]) if sprinting else float(_config["cone_deg"])
	return base + minf(float(_config["angle_per_perception"]) * maxi(perception_level - 1, 0), float(_config["angle_bonus_max"]))


## Скорость поворота взгляда, градусов в секунду.
func turn_speed(reaction_level: int) -> float:
	return float(_config["turn_deg_s"]) + float(_config["turn_per_reaction"]) * maxi(reaction_level - 1, 0)


## В конусе или круге вокруг (по плоскости XZ). facing — направление взгляда (длина не важна).
func in_view(hero: Vector3, facing: Vector3, target: Vector3, cone: float, reach: float) -> bool:
	var to := Vector2(target.x - hero.x, target.z - hero.z)
	var distance := to.length()
	if distance <= float(_config["near_m"]):
		return true
	if distance > reach:
		return false
	var look := Vector2(facing.x, facing.z)
	if look.length() < 0.0001:
		return false
	return rad_to_deg(absf(look.angle_to(to))) <= cone / 2.0


## Шанс чуйки за одну проверку. perception, reaction — итоговые значения героя; stealth, level,
## hush (0..1, гашение у элит) — угрозы; distance — до неё; alert — гонится за героем.
func sense_chance(perception: float, reaction: float, stealth: float, level: int, distance: float,
		alert: bool, hush: float = 0.0) -> float:
	var s: Dictionary = _config["sense"]
	var radius := float(s["radius_m"])
	if distance > radius:
		return 0.0
	var closeness := 1.0 - clampf(distance / radius, 0.0, 1.0)
	var near_floor := float(s["near_floor"])
	var skill := maxf((perception + reaction) / 2.0, 0.1)
	var hide := maxf(stealth, 0.0) + float(s["level_weight"]) * maxi(level, 0)
	var chance := float(s["base"]) * (near_floor + (1.0 - near_floor) * closeness)
	if alert:
		chance *= float(s["alert_mult"])
	chance *= skill / (skill + hide * float(s["hide_weight"]))
	chance *= 1.0 - clampf(hush, 0.0, 1.0)
	return clampf(chance, 0.0, float(s["max"]))


## Повернуть взгляд from к to не больше чем на max_deg (по плоскости XZ). Возвращает единичный вектор.
static func turn_towards(from: Vector3, to: Vector3, max_deg: float) -> Vector3:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if b.length() < 0.0001:
		return Vector3(a.x, 0.0, a.y).normalized() if a.length() > 0.0001 else Vector3.FORWARD
	if a.length() < 0.0001:
		return Vector3(b.x, 0.0, b.y).normalized()
	var angle := a.angle_to(b)
	var step := clampf(angle, -deg_to_rad(max_deg), deg_to_rad(max_deg))
	var result := a.normalized().rotated(step)
	return Vector3(result.x, 0.0, result.y)
