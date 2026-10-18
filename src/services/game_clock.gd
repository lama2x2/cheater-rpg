extends Node
## Мировое время. Идёт всегда, даже когда игрок в стабе (см. docs/spec/02_world.md, «Время»).

signal hour_passed(hour: int, day: int)

const MINUTES_PER_DAY := 1440.0

var minutes: float = 0.0
var _minutes_per_second: float = 0.0


func _ready() -> void:
	reset()


## Начало новой игры: первый день, стартовый час.
func reset() -> void:
	var rules := Content.rules()
	minutes = float(rules["start_hour"]) * 60.0
	_minutes_per_second = MINUTES_PER_DAY / float(rules["real_seconds_per_game_day"])


func _process(delta: float) -> void:
	var hour_before := floori(minutes / 60.0)
	minutes += delta * _minutes_per_second
	var hour_now := floori(minutes / 60.0)
	if hour_now != hour_before:
		hour_passed.emit(hour_now % 24, day())


func to_dict() -> Dictionary:
	return {"minutes": minutes}


func load_dict(data: Dictionary) -> void:
	minutes = float(data["minutes"])


## Прокрутка времени (возрождение, сон). Сигнал hour_passed — за каждый пройденный час.
func advance(game_minutes: float) -> void:
	var hour_before := floori(minutes / 60.0)
	minutes += game_minutes
	for hour in range(hour_before + 1, floori(minutes / 60.0) + 1):
		hour_passed.emit(hour % 24, floori(hour / 24.0) + 1)


## Сколько игровых минут проходит за real_seconds реального времени.
func game_minutes_for(real_seconds: float) -> float:
	return real_seconds * _minutes_per_second


func day() -> int:
	return floori(minutes / MINUTES_PER_DAY) + 1


func clock_text() -> String:
	var in_day := fmod(minutes, MINUTES_PER_DAY)
	return "День %d, %02d:%02d" % [day(), floori(in_day / 60.0), floori(fmod(in_day, 60.0))]
