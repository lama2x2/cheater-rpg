class_name NoiseModel
extends RefCounted
## Шум: радиусы источников и модификаторы, громкость у слушателя, накопление серии громких звуков.
## Чистый класс без Node. Спецификация: docs/spec/08_combat.md, 8.2.
## Громкость 0..1 линейно падает от источника до края радиуса.

const REQUIRED_KEYS: PackedStringArray = [
	"sources", "step_length_m", "hear_threshold", "wall_mult", "max_walls", "indoors_mult",
	"weather", "stealth", "overload_step_mult_at_double", "accumulation",
]

## Накопленный «жар» от недавних громких звуков (множитель радиуса = 1 + бонус).
var heat_bonus: float = 0.0

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func base_radius(source: String) -> float:
	assert(_config["sources"].has(source), "Неизвестный источник шума: %s" % source)
	return float(_config["sources"][source])


## Радиус импульса с модификаторами источника.
## options: weather ("clear"/"rain"/…), indoors (bool), stealth_level (для шагов), load_ratio (для шагов).
func radius(source: String, options: Dictionary = {}) -> float:
	var r := base_radius(source)
	r *= float(_config["weather"].get(options.get("weather", "clear"), 1.0))
	if bool(options.get("indoors", false)):
		r *= float(_config["indoors_mult"])
	if source.ends_with("_step"):
		r *= stealth_multiplier(int(options.get("stealth_level", 1)))
		r *= overload_multiplier(float(options.get("load_ratio", 0.0)))
	else:
		r *= 1.0 + heat_bonus
	return r


## Скрытность гасит шаги: −2% за уровень сверх первого, но не тише половины.
func stealth_multiplier(stealth_level: int) -> float:
	var s: Dictionary = _config["stealth"]
	return maxf(float(s["min_mult"]), 1.0 - float(s["step_reduction_per_level"]) * (stealth_level - 1))


## Перегруз делает шаги громче: от ×1 на полном рюкзаке до значения из данных на двойном весе.
func overload_multiplier(load_ratio: float) -> float:
	return lerpf(1.0, float(_config["overload_step_mult_at_double"]), clampf(load_ratio - 1.0, 0.0, 1.0))


## Громкость у слушателя: стены между ними (до max_walls) режут радиус, слух твари — множитель.
## Ниже порога — 0 (не услышал).
func loudness_at(impulse_radius: float, distance: float, walls: int = 0, hearing: float = 1.0) -> float:
	var r := impulse_radius * pow(float(_config["wall_mult"]), mini(walls, int(_config["max_walls"])))
	if r <= 0.0 or distance >= r:
		return 0.0
	var loudness := clampf((1.0 - distance / r) * hearing, 0.0, 1.0)
	return loudness if loudness >= float(_config["hear_threshold"]) else 0.0


## Длина шага для режима движения: "sneak" / "walk" / "sprint".
func step_length(mode: String) -> float:
	return float(_config["step_length_m"][mode])


## Учесть громкий импульс в накоплении (вызывать после radius()).
func register(impulse_radius: float) -> void:
	var a: Dictionary = _config["accumulation"]
	if impulse_radius >= float(a["loud_from"]):
		heat_bonus = minf(float(a["max_bonus"]), heat_bonus + impulse_radius * float(a["per_meter"]))


## Остывание накопления, реальные секунды.
func cool_down(seconds: float) -> void:
	heat_bonus = maxf(0.0, heat_bonus - float(_config["accumulation"]["decay_per_second"]) * seconds)
