extends Node
## Стаб: торговец, знахарка, бар и доска контрактов. Связывает правила (TradeRules, ContractBoard,
## StabRules) с героем, временем, миром и логом Системы. Окно — src/ui/stab_window.gd, неписи —
## src/actors/stab_npc.gd. Данные — data/stab.json. Спецификация: docs/spec/10_stabs_economy.md.

## Что-то изменилось (сделка, контракт) — окно перерисовывается.
signal changed

var trade: TradeRules
var board: ContractBoard
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_ensure()
	EventBus.infected_killed.connect(_on_infected_killed)
	EventBus.cluster_entered.connect(_on_cluster_entered)


## Новая игра: торговец с полным запасом, доска пустая.
func setup() -> void:
	var config := Content.stab_config()
	trade = TradeRules.new(config["trade"], Content.item_db())
	board = ContractBoard.new(config["board"])


## Лениво: тесты (скрипт -s) обращаются к сервису до его _ready.
func _ensure() -> void:
	if trade == null:
		setup()


## Новые сутки: запас торговца и доска.
func refresh() -> void:
	_ensure()
	var today := GameClock.day()
	trade.refresh(today)
	board.refresh(today, hash([WorldSim.world_seed, "board", today]))


func money() -> int:
	return TradeRules.money(PlayerState.inventory)


func buy(id: String, count: int) -> void:
	var result := trade.buy(id, count, PlayerState.inventory)
	if not result["ok"]:
		SystemLog.post("trade_no_stock" if result["reason"] == "stock" else "not_enough_money", {"price": trade.buy_price(id) * count}, "warning")
		return
	if int(result["left"]) > 0:
		EventBus.items_dropped.emit(id, int(result["left"]))
	SystemLog.post("trade_bought", {"item": Content.item_name(id), "count": count, "price": result["cost"]})
	_after_deal()


func sell(id: String, count: int) -> void:
	var result := trade.sell(id, count, PlayerState.inventory)
	if not result["ok"]:
		return
	if int(result["left"]) > 0:
		EventBus.items_dropped.emit(TradeRules.CURRENCY, int(result["left"]))
	SystemLog.post("trade_sold", {"item": Content.item_name(id), "count": count, "price": result["gain"]})
	_after_deal()


func heal_cost() -> int:
	var vitals := PlayerState.vitals
	return StabRules.heal_cost(vitals.max_value(Vitals.HEALTH) - vitals.value(Vitals.HEALTH),
		PlayerState.wounds.is_bleeding(), Content.stab_config()["healer"])


func heal() -> void:
	var cost := heal_cost()
	if cost <= 0 or not _pay(cost):
		return
	PlayerState.vitals.restore(Vitals.HEALTH, PlayerState.vitals.max_value(Vitals.HEALTH))
	if PlayerState.wounds.is_bleeding():
		PlayerState.wounds.stop_bleeding()
	SystemLog.post("healed", {"price": cost})
	_after_deal()


## Следующий дар уровня у знахарки (-1 — нет). Цена — 25–30, бросается при открытии окна.
func next_gift() -> int:
	return StabRules.next_gift(PlayerState.stats.general_level(), PlayerState.skill_gifts_opened, Content.stab_config()["healer"])


func gift_price() -> int:
	return StabRules.gift_price(Content.stab_config()["healer"], _rng)


## «Вскрытие» дара: умение появится в выборе (задача 13 — само умение и выбор).
func open_gift(price: int) -> void:
	var level := next_gift()
	if level < 0 or not _pay(price):
		return
	PlayerState.skill_gifts_opened.append(level)
	PlayerState.pending_skill_choices += 1
	SystemLog.post("gift_opened", {"level": level, "price": price}, "special")
	_after_deal()


func pearl_price() -> int:
	return int(Content.skill_rules_config()["pearl"]["healer_price"])


## Висящее умение жемчужины у знахарки (D-86): за плату — выбранная область, умение случайное из неё.
func open_pearl_area(area: String) -> void:
	if PlayerState.pending_pearl_skills <= 0 or PlayerState.skills.area_skills(area).is_empty():
		return
	if not _pay(pearl_price()):
		return
	PlayerState.open_pearl_area(area)
	_after_deal()


func can_sleep() -> bool:
	return StabRules.can_sleep(PlayerState.vitals.value(Vitals.SPORE),
		float(Content.vitals_config()[Vitals.SPORE]["decay_per_game_hour"]), Content.stab_config()["bar"])


## Сон в баре: время идёт (мир меняется), шкалы — как за эти часы наяву, бодрость полная, автосейв.
func sleep() -> void:
	var bar: Dictionary = Content.stab_config()["bar"]
	if not can_sleep():
		SystemLog.post("sleep_refused", {}, "warning")
		return
	if not _pay(int(bar["sleep_price"])):
		return
	var minutes := float(bar["sleep_hours"]) * 60.0
	PlayerState.vitals.tick(0.0, minutes, false)
	PlayerState.vitals.restore(Vitals.STAMINA, PlayerState.vitals.max_value(Vitals.STAMINA))
	GameClock.advance(minutes)
	SystemLog.post("slept", {"hours": int(bar["sleep_hours"]), "clock": GameClock.clock_text()})
	refresh()
	_after_deal()
	SaveService.save_game(SaveService.AUTO_SLOT)


## Слух: таймер случайного кластера, которого герой ещё не знает.
func rumor() -> void:
	var candidates: PackedStringArray = []
	for id: String in WorldSim.clusters:
		var s: Dictionary = WorldSim.clusters[id]
		if ClusterLifecycle.reloads(s["timer"]) and not s["known_timer"]:
			candidates.append(id)
	var target := StabRules.rumor_target(candidates, _rng)
	if target.is_empty():
		SystemLog.post("rumor_none")
		return
	if not _pay(int(Content.stab_config()["bar"]["rumor_price"])):
		return
	WorldSim.clusters[target]["known_timer"] = true
	SystemLog.post("rumor", {"name": WorldSim.cluster_name(target), "timer": WorldSim.timer_text(target)}, "special")
	_after_deal()


func take_contract(index: int) -> void:
	if board.take(index):
		SystemLog.post("contract_taken", {"text": contract_text(board.active[-1])})
		changed.emit()


func complete_contract(index: int) -> void:
	var contract: Dictionary = board.active[index]
	var reward := board.complete(index, PlayerState.inventory)
	if reward <= 0:
		return
	var left: int = PlayerState.inventory.add(TradeRules.CURRENCY, reward)["left"]
	if left > 0:
		EventBus.items_dropped.emit(TradeRules.CURRENCY, left)
	PlayerState.run.add("contracts")
	SystemLog.post("contract_done", {"text": contract_text(contract), "reward": reward}, "progress")
	_after_deal()


## «Убить медляков: 3/6», «Принести: водка ×2», «Разведать: Чернота».
func contract_text(contract: Dictionary) -> String:
	var target := String(contract["target"])
	var name := ""
	match String(contract["type"]):
		ContractBoard.HUNT:
			name = Content.enemy_name(target)
		ContractBoard.DELIVER:
			name = Content.item_name(target)
		ContractBoard.SCOUT:
			name = WorldSim.cluster_name(target)
	return Content.ui("contract_" + String(contract["type"]), {
		"target": name, "count": contract["count"], "progress": contract["progress"], "reward": contract["reward"],
	})


func _pay(price: int) -> bool:
	if money() < price:
		SystemLog.post("not_enough_money", {"price": price}, "warning")
		return false
	PlayerState.inventory.remove(TradeRules.CURRENCY, price)
	return true


func _after_deal() -> void:
	PlayerState.notify_inventory_changed()
	changed.emit()


func _on_infected_killed(id: String, _level: int, _at: Vector3) -> void:
	for contract: Dictionary in board.on_kill(id):
		SystemLog.post("contract_ready", {"text": contract_text(contract)}, "progress")


func _on_cluster_entered(id: String) -> void:
	for contract: Dictionary in board.on_enter(id):
		SystemLog.post("contract_ready", {"text": contract_text(contract)}, "progress")


func to_dict() -> Dictionary:
	_ensure()
	return {"trade": trade.to_dict(), "board": board.to_dict()}


func load_dict(data: Dictionary) -> void:
	setup()
	trade.load_dict(data.get("trade", {}))
	board.load_dict(data.get("board", {}))
