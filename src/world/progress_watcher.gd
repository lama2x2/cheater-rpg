extends Node
## Следит за действиями героя и начисляет прогресс (3.2): удары — Сила, попадания — Меткость
## (трудные — голова, мешок, дальше hard_shot_distance — вдвое), ранения — Выносливость,
## незамеченный проход рядом с тварью — Скрытность. Бег, перегруз и тайники начисляют сами.

const CHECK_INTERVAL := 0.25

## Твари, рядом с которыми сейчас проходит герой: {instance_id: {"time": с, "noticed": bool, "level": int}}.
var _near: Dictionary = {}
var _timer := 0.0


func _ready() -> void:
	EventBus.player_hit.connect(_on_hit)
	EventBus.player_hurt.connect(func(amount: float, _source: String) -> void: PlayerState.award("wounded", amount))


func _on_hit(_weapon_id: String, _enemy_id: String, enemy_level: int, result: Dictionary, _killed: bool) -> void:
	var context := {"target_level": enemy_level}
	match String(result.get("attack", "light")):
		"light":
			PlayerState.award("melee_hit", 1.0, context)
		"heavy":
			PlayerState.award("melee_heavy_hit", 1.0, context)
		"ranged":
			var hard: bool = result["zone"] == "head" or result["zone"] == DamageModel.SPORE_SACK \
				or float(result.get("distance", 0.0)) > float(Content.progress_config()["hard_shot_distance"])
			PlayerState.award("ranged_hard_hit" if hard else "ranged_hit", 1.0, context)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	_watch_sneak_pass(CHECK_INTERVAL)


## Скрытность: герой провёл рядом с тварью min_seconds и ушёл за leave_radius, а она так его и
## не заметила (не гналась, не атаковала).
func _watch_sneak_pass(step: float) -> void:
	var hero := get_tree().get_first_node_in_group("hero") as Node3D
	if hero == null or not hero.visible:
		_near.clear()
		return
	var s: Dictionary = Content.progress_config()["sneak_pass"]
	var seen := {}
	for infected: Node3D in get_tree().get_nodes_in_group("infected"):
		var id := infected.get_instance_id()
		var distance := Vector2(infected.global_position.x - hero.global_position.x, infected.global_position.z - hero.global_position.z).length()
		if _near.has(id):
			seen[id] = true
			var entry: Dictionary = _near[id]
			if infected.brain.is_alert():
				entry["noticed"] = true
			if distance <= float(s["near_radius"]):
				entry["time"] = float(entry["time"]) + step
			elif distance > float(s["leave_radius"]):
				if not entry["noticed"] and float(entry["time"]) >= float(s["min_seconds"]):
					PlayerState.award("sneak_pass", 1.0, {"target_level": entry["level"]})
				_near.erase(id)
		elif distance <= float(s["near_radius"]):
			seen[id] = true
			_near[id] = {"time": 0.0, "noticed": infected.brain.is_alert(), "level": infected.level}
	for id in _near.keys():
		if not seen.has(id):
			_near.erase(id)  # тварь умерла или исчезла
