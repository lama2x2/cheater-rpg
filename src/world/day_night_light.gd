extends Node
## Солнце и окружение по игровым часам (задача 19, правила — DayNight).

var sun: DirectionalLight3D
var environment: Environment
var _rules: DayNight
var _left := 0.0


func _ready() -> void:
	_rules = DayNight.new(JsonData.load_dict("res://data/daynight.json", ["keys"]))
	_apply()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = 0.5
		_apply()


func _apply() -> void:
	var l := _rules.at(GameClock.minutes / 60.0)
	if sun:
		sun.light_energy = float(l["sun"])
		sun.light_color = l["sun_color"]
		sun.rotation_degrees.x = float(l["pitch"])
	if environment:
		environment.ambient_light_energy = float(l["ambient"])
		environment.ambient_light_color = l["ambient_color"]
		environment.background_color = l["bg"]
