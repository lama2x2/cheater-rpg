class_name InfectedBrain
extends RefCounted
## Мозг заражённого: состояния и переходы. Решает «что делать», а куда идти и как бить — тело
## (src/actors/infected.gd). Чистый класс без Node. Спецификация: docs/spec/07_enemies.md, «ИИ».
##
##   WANDER      бродит вокруг дома
##   INVESTIGATE идёт проверить шум или место, где потерял цель
##   CHASE       видит героя и гонится
##   ATTACK      герой в досягаемости
##   EAT         голоден и нашёл еду (трупы)
##   FLEE        напугана (умение Пугач): бежит прочь, не видит и не слышит, пока не кончится страх
##
## Чувства за тик (senses):
##   sees_player: bool, player_position: Vector3, player_distance: float,
##   noise: {"position": Vector3, "loudness": float} или {} — громкость уже с учётом слуха твари,
##   food: {"position": Vector3, "distance": float} или {} — ближайшая еда в пределах нюха,
##   at_target: bool — дошёл до target_position.

const WANDER := "wander"
const INVESTIGATE := "investigate"
const CHASE := "chase"
const ATTACK := "attack"
const EAT := "eat"
const FLEE := "flee"

## Насколько громкий шум отвлекает от еды (во время еды тварь «глохнет»).
const EAT_NOISE_THRESHOLD := 0.6
const ATTACK_EXIT_MULT := 1.25

var state := WANDER
var target_position := Vector3.ZERO
## Голод 0..1. Растёт со временем, падает, пока ест.
var hunger: float = 0.0

var _ai: Dictionary
var _attack_range: float
var _since_seen := 0.0
var _search_left := 0.0
var _flee_left := 0.0


func _init(ai: Dictionary, attack_range: float, start_hunger: float = 0.0) -> void:
	_ai = ai
	_attack_range = attack_range
	hunger = start_hunger


func update(delta: float, senses: Dictionary) -> String:
	hunger = clampf(hunger + float(_ai["hunger_per_s"]) * delta, 0.0, 1.0)
	var sees := bool(senses.get("sees_player", false))
	var noise: Dictionary = senses.get("noise", {})
	var food: Dictionary = senses.get("food", {})

	if state == FLEE:
		_flee_left -= delta
		if _flee_left <= 0.0:
			state = WANDER
		return state

	if sees:
		_since_seen = 0.0
		target_position = senses["player_position"]
		var distance := float(senses["player_distance"])
		if state == ATTACK and distance <= _attack_range * ATTACK_EXIT_MULT:
			return state
		state = ATTACK if distance <= _attack_range else CHASE
		return state

	match state:
		CHASE, ATTACK:
			_since_seen += delta
			if _since_seen >= float(_ai["lose_sight_s"]):
				_start_investigate(target_position)
			else:
				state = CHASE  # бежит к месту, где видел в последний раз
		INVESTIGATE:
			if not noise.is_empty():
				_start_investigate(noise["position"])
			elif bool(senses.get("at_target", false)):
				_search_left -= delta
				if _search_left <= 0.0:
					state = WANDER
		EAT:
			if not noise.is_empty() and float(noise["loudness"]) >= EAT_NOISE_THRESHOLD:
				_start_investigate(noise["position"])
			elif food.is_empty() or hunger <= 0.0:
				state = WANDER
			else:
				target_position = food["position"]
				if bool(senses.get("at_target", false)):
					hunger = maxf(0.0, hunger - float(_ai["eat_per_s"]) * delta)
		WANDER:
			if not noise.is_empty():
				_start_investigate(noise["position"])
			elif not food.is_empty() and hunger >= float(_ai["hungry_at"]):
				state = EAT
				target_position = food["position"]
	return state


## Страх (Пугач): бежать к точке to на seconds секунд.
func flee(to: Vector3, seconds: float) -> void:
	state = FLEE
	target_position = to
	_flee_left = seconds


## Сколько съедено за этот тик (для трупа): тело уменьшает запас еды на это.
func eating_now(senses: Dictionary) -> bool:
	return state == EAT and bool(senses.get("at_target", false))


func is_alert() -> bool:
	return state == CHASE or state == ATTACK


func to_dict() -> Dictionary:
	return {"state": state, "hunger": hunger, "target": [target_position.x, target_position.y, target_position.z]}


func load_dict(data: Dictionary) -> void:
	state = String(data.get("state", WANDER))
	hunger = float(data.get("hunger", 0.0))
	var at: Array = data.get("target", [0.0, 0.0, 0.0])
	target_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	if state == CHASE or state == ATTACK:
		_start_investigate(target_position)
	elif state == FLEE:
		state = WANDER


func _start_investigate(at: Vector3) -> void:
	state = INVESTIGATE
	target_position = at
	_search_left = float(_ai["search_s"])
