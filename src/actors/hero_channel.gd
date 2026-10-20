extends Node
## Длительное действие героя («вскрыть мешок», позже — перевязка, крафт на месте): идёт
## duration секунд, шумит раз в секунду, срывается, если герой сдвинулся или его ранили.

const MOVE_TOLERANCE := 0.6

var hero: Node3D

var _label := ""
var _duration := 0.0
var _elapsed := 0.0
var _on_done: Callable
var _noise := ""
var _noise_timer := 0.0
var _start_position := Vector3.ZERO
var _move_tolerance := MOVE_TOLERANCE


func _ready() -> void:
	EventBus.player_hurt.connect(func(_amount: float, _source: String) -> void: cancel())


func is_active() -> bool:
	return _duration > 0.0


## Доля выполнения 0..1 и подпись — для подсказки взаимодействия.
func progress() -> float:
	return _elapsed / _duration if is_active() else 0.0


func label() -> String:
	return _label


## move_tolerance — на сколько можно сдвинуться, не сорвав действие (Ловкие руки — 1,5 м).
func start(label_text: String, duration: float, on_done: Callable, noise_source: String = "", move_tolerance: float = MOVE_TOLERANCE) -> void:
	_label = label_text
	_duration = maxf(0.05, duration)
	_elapsed = 0.0
	_on_done = on_done
	_noise = noise_source
	_noise_timer = 0.0
	_start_position = hero.global_position
	_move_tolerance = move_tolerance


func cancel() -> void:
	if is_active():
		_duration = 0.0
		SystemLog.post("action_interrupted", {"action": _label}, "warning")


func _process(delta: float) -> void:
	if not is_active():
		return
	if not _on_done.is_valid():
		_duration = 0.0  # цель исчезла (кластер перезагрузился) — молча бросить
		return
	if hero.global_position.distance_to(_start_position) > _move_tolerance:
		cancel()
		return
	_elapsed += delta
	_noise_timer -= delta
	if not _noise.is_empty() and _noise_timer <= 0.0:
		_noise_timer = 1.0
		EventBus.noise_made.emit(_noise, hero.global_position, {"from_hero": true})
	if _elapsed >= _duration:
		_duration = 0.0
		_on_done.call()
