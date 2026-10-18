class_name DamageModel
extends RefCounted
## Попадания и урон: зоны (голова, торс, конечности, споровый мешок на затылке — крит), броня по
## зонам, пробой, Сила в ближнем бою, разброс от Меткости и движения.
## Чистый класс без Node. Спецификация: docs/spec/08_combat.md, 8.3–8.4.

const REQUIRED_KEYS: PackedStringArray = [
	"zones", "behind_arc_deg", "ranged_zones", "melee_zones", "strength_bonus_per_level",
	"winded_melee_mult", "spread", "bleeding",
]
const SPORE_SACK := "spore_sack"

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


## Удар пришёл сзади: угол между взглядом цели и направлением на атакующего больше половины
## «заднего» сектора от лица. target_forward и to_attacker — на плоскости.
func is_from_behind(target_forward: Vector3, to_attacker: Vector3) -> bool:
	var a := Vector2(target_forward.x, target_forward.z)
	var b := Vector2(to_attacker.x, to_attacker.z)
	if a.length() < 0.001 or b.length() < 0.001:
		return false
	var angle := rad_to_deg(absf(a.angle_to(b)))
	return angle > 180.0 - float(_config["behind_arc_deg"]) / 2.0


## Зона удара в ближнем бою — случайно по весам вида удара (сзади мешок открыт).
func melee_zone(kind: String, from_behind: bool, rng: RandomNumberGenerator, has_sack: bool = true) -> String:
	var weights: Dictionary = _config["melee_zones"][kind + ("_behind" if from_behind else "")]
	var total := 0.0
	for zone: String in weights:
		if zone != SPORE_SACK or has_sack:
			total += float(weights[zone])
	var roll := rng.randf() * total
	for zone: String in weights:
		if zone == SPORE_SACK and not has_sack:
			continue
		roll -= float(weights[zone])
		if roll <= 0.0:
			return zone
	return "torso"


## Зона попадания пули или стрелы: голова — с шансом от Меткости, сзади — споровый мешок,
## конечности — постоянная доля, остальное — торс.
func ranged_zone(from_behind: bool, accuracy_value: float, rng: RandomNumberGenerator, has_sack: bool = true) -> String:
	var z: Dictionary = _config["ranged_zones"]
	var extra := maxf(0.0, accuracy_value - 1.0)
	var head := minf(float(z["max_head"]), float(z["head"]) + float(z["head_per_accuracy"]) * extra)
	var sack := 0.0
	if from_behind and has_sack:
		sack = minf(float(z["max_sack"]), float(z["spore_sack_behind"]) + float(z["sack_per_accuracy"]) * extra)
	var roll := rng.randf()
	if roll < sack:
		return SPORE_SACK
	if roll < sack + head:
		return "head"
	if roll < sack + head + float(z["limbs"]):
		return "limbs"
	return "torso"


## Урон по зоне: base × множитель зоны × mult − броня зоны × (1 − пробой), не меньше 0.
## Результат: {"damage", "zone", "armor_stopped": bool — броня погасила всё, "crit": bool}.
func hit(base_damage: float, zone: String, armor: Dictionary, penetration: float, mult: float = 1.0) -> Dictionary:
	var raw := base_damage * float(_config["zones"][zone]) * mult
	var effective_armor := float(armor.get(zone, 0.0)) * (1.0 - clampf(penetration, 0.0, 1.0))
	var damage := maxf(0.0, raw - effective_armor)
	return {"damage": damage, "zone": zone, "armor_stopped": damage <= 0.0, "crit": zone == SPORE_SACK}


## Множитель урона ближнего боя от Силы (итоговое значение) и бодрости.
func melee_multiplier(strength_value: float, winded: bool) -> float:
	var m := 1.0 + float(_config["strength_bonus_per_level"]) * maxf(0.0, strength_value - 1.0)
	return m * (float(_config["winded_melee_mult"]) if winded else 1.0)


## Разброс выстрела в градусах: Меткость сужает (до min_mult), движение расширяет, присед сужает.
## stance: "still" / "moving" / "sprinting" / "sneaking".
func spread_deg(weapon_spread: float, accuracy_value: float, stance: String) -> float:
	var s: Dictionary = _config["spread"]
	var acc := maxf(float(s["min_mult"]), 1.0 - float(s["accuracy_reduction_per_level"]) * maxf(0.0, accuracy_value - 1.0))
	var stance_mult := 1.0
	match stance:
		"moving": stance_mult = float(s["moving_mult"])
		"sprinting": stance_mult = float(s["sprinting_mult"])
		"sneaking": stance_mult = float(s["sneaking_mult"])
	return weapon_spread * acc * stance_mult


## Случайное отклонение направления в пределах конуса spread (равномерно по углу).
static func deviate(direction: Vector3, spread: float, rng: RandomNumberGenerator) -> Vector3:
	var yaw := deg_to_rad(rng.randf_range(-spread, spread))
	var pitch := deg_to_rad(rng.randf_range(-spread, spread) * 0.3)
	var right := direction.cross(Vector3.UP).normalized()
	return direction.rotated(Vector3.UP, yaw).rotated(right, pitch).normalized()
