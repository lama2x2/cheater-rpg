class_name ContractBoard
extends RefCounted
## Доска контрактов стаба: предложения на сутки (по одному на тип — охота, доставка, разведка),
## взятые контракты с прогрессом, сдача за спораны. Чистый класс без Node.
## Числа — data/stab.json (board). Спецификация: docs/spec/10_stabs_economy.md, 11.2.
##
## Контракт: {"type": "hunt"/"deliver"/"scout", "target": id твари / предмета / кластера,
##   "count": сколько, "reward": спораны, "progress": сколько сделано (охота, разведка)}

const HUNT := "hunt"
const DELIVER := "deliver"
const SCOUT := "scout"

var offers: Array = []
var active: Array = []
var day: int = -1

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


## Новые сутки — новые предложения (взятые контракты остаются). seed_value — от сида мира и дня.
func refresh(today: int, seed_value: int) -> void:
	if today == day:
		return
	day = today
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	offers.clear()
	var kinds: Array = _config["contracts"].duplicate()
	for i in mini(int(_config["board_size"]), kinds.size()):
		var kind: Dictionary = kinds[i]
		var options: Array = kind["options"]
		var option: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		var count := rng.randi_range(int(option["count"][0]), int(option["count"][1]))
		offers.append({
			"type": String(kind["type"]), "target": String(option["target"]), "count": count,
			"reward": count * int(option["reward_per"]), "progress": 0,
		})


func can_take() -> bool:
	return active.size() < int(_config["max_active"])


## Взять предложение: уходит с доски в активные.
func take(index: int) -> bool:
	if index < 0 or index >= offers.size() or not can_take():
		return false
	active.append(offers[index])
	offers.remove_at(index)
	return true


## Убита тварь: прогресс охоты на неё.
func on_kill(enemy_id: String) -> Array:
	return _advance(HUNT, enemy_id)


## Вошёл в кластер: разведка выполнена.
func on_enter(cluster_id: String) -> Array:
	return _advance(SCOUT, cluster_id)


## Контракты, у которых только что набралось нужное (для сообщения).
func _advance(type: String, target: String) -> Array:
	var done: Array = []
	for contract: Dictionary in active:
		if contract["type"] != type or contract["target"] != target or int(contract["progress"]) >= int(contract["count"]):
			continue
		contract["progress"] = int(contract["progress"]) + 1
		if int(contract["progress"]) >= int(contract["count"]):
			done.append(contract)
	return done


static func is_ready(contract: Dictionary, inventory: Inventory) -> bool:
	if contract["type"] == DELIVER:
		return inventory.count_of(contract["target"]) >= int(contract["count"])
	return int(contract["progress"]) >= int(contract["count"])


## Сдать активный контракт: доставка забирает предметы. Возвращает награду (0 — не готов).
func complete(index: int, inventory: Inventory) -> int:
	if index < 0 or index >= active.size():
		return 0
	var contract: Dictionary = active[index]
	if not is_ready(contract, inventory):
		return 0
	if contract["type"] == DELIVER:
		inventory.remove(contract["target"], int(contract["count"]))
	active.remove_at(index)
	return int(contract["reward"])


func to_dict() -> Dictionary:
	return {"offers": offers.duplicate(true), "active": active.duplicate(true), "day": day}


func load_dict(data: Dictionary) -> void:
	offers = _ints(data.get("offers", []))
	active = _ints(data.get("active", []))
	day = int(data.get("day", -1))


## JSON возвращает числа как float — счётчики контрактов обратно в int.
static func _ints(list: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in list:
		var c := entry.duplicate()
		for key in ["count", "reward", "progress"]:
			c[key] = int(c[key])
		result.append(c)
	return result
