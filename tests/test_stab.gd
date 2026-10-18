extends "res://tests/test_case.gd"
## Стаб: торговля, доска контрактов, знахарь и бар. docs/spec/10_stabs_economy.md.

const ItemDBScript := preload("res://src/core/item_db.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const TradeRulesScript := preload("res://src/core/trade_rules.gd")
const ContractBoardScript := preload("res://src/core/contract_board.gd")
const StabRulesScript := preload("res://src/core/stab_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _stab() -> Dictionary:
	return JsonDataScript.load_dict("res://data/stab.json")


func _db() -> ItemDB:
	var files: Array = []
	for file in DirAccess.get_files_at("res://data/items"):
		if file.ends_with(".json"):
			files.append(JsonDataScript.load_dict("res://data/items".path_join(file)))
	return ItemDBScript.new(files)


func _inv(sporans: int = 0) -> Inventory:
	var inv := InventoryScript.new(_db(), JsonDataScript.load_dict("res://data/inventory.json"), 1)
	if sporans > 0:
		inv.add("sporan", sporans)
	return inv


func _trade() -> TradeRules:
	return TradeRulesScript.new(_stab()["trade"], _db())


func test_stab_data_refers_to_known_things() -> void:
	var db := _db()
	var stab := _stab()
	for id: String in stab["trade"]["stock"]:
		assert_true(db.has_item(id), "товар %s есть в data/items" % id)
	var enemies: Array = JsonDataScript.load_dict("res://data/enemies/infected.json")["enemies"].map(func(e: Dictionary) -> String: return e["id"])
	var clusters: Array = JsonDataScript.load_dict("res://data/world/region.json")["clusters"].map(func(c: Dictionary) -> String: return c["id"])
	assert_true(clusters.has(stab["cluster"]), "кластер стаба есть в регионе")
	for kind: Dictionary in stab["board"]["contracts"]:
		for option: Dictionary in kind["options"]:
			match String(kind["type"]):
				"hunt": assert_true(enemies.has(option["target"]), "тварь %s" % option["target"])
				"deliver": assert_true(db.has_item(option["target"]), "предмет %s" % option["target"])
				"scout": assert_true(clusters.has(option["target"]), "кластер %s" % option["target"])


func test_prices_buy_dearer_than_sell() -> void:
	var trade := _trade()
	assert_eq(trade.buy_price("pistol"), 112, "пистолет 80 × 1,4")
	assert_eq(trade.sell_price("pistol"), 48, "торговец берёт за 60%")
	assert_eq(trade.buy_price("vodka"), 2, "дешёвое — не меньше 1, вверх")
	assert_eq(trade.sell_price("sporan"), 0, "спораны не продаются — это деньги")
	assert_eq(trade.sell_price("brick"), 0, "кирпич не нужен")
	for id in _db().ids():
		if trade.sell_price(id) > 0:
			assert_true(trade.buy_price(id) > trade.sell_price(id), "%s: купить дороже, чем продать" % id)


func test_buy_spends_sporans_and_stock() -> void:
	var trade := _trade()
	var inv := _inv(30)
	var result := trade.buy("bandage", 2, inv)
	assert_true(result["ok"], "купили")
	assert_eq(TradeRulesScript.money(inv), 30 - 2 * trade.buy_price("bandage"), "заплатили")
	assert_eq(inv.count_of("bandage"), 2, "бинты у героя")
	assert_eq(int(trade.stock["bandage"]), 3, "запас уменьшился")
	assert_eq(trade.buy("pistol", 1, inv)["reason"], "money", "не хватает денег")
	assert_eq(trade.buy("pistol", 2, _inv(1000))["reason"], "stock", "столько нет")


func test_sell_saturates_and_recovers() -> void:
	var trade := _trade()
	var inv := _inv()
	inv.add("pea_yellow", 20)
	var first := trade.sell_price("pea_yellow")
	var result := trade.sell("pea_yellow", 10, inv)
	assert_true(result["ok"], "продали")
	assert_true(int(result["gain"]) < first * 10, "каждая следующая дешевле")
	assert_eq(TradeRulesScript.money(inv), int(result["gain"]), "спораны получены")
	assert_true(trade.sell_price("pea_yellow") < first, "насыщение")
	assert_true(trade.sell_price("pea_yellow") >= floori(11 * 0.6 * 0.3), "не ниже минимума")
	trade.refresh(3)
	assert_true(trade.sell_price("pea_yellow") > floori(11 * 0.6 * 0.5), "через двое суток спрос вернулся")
	assert_eq(trade.sell("pea_yellow", 50, inv)["reason"], "missing", "нельзя продать, чего нет")


func test_refresh_restocks_once_per_day() -> void:
	var trade := _trade()
	trade.buy("knife", 1, _inv(100))
	trade.refresh(0)
	assert_eq(int(trade.stock["knife"]), 0, "в тот же день — не пополняется")
	trade.refresh(1)
	assert_eq(int(trade.stock["knife"]), 1, "назавтра — пополнен")


func test_trade_save_roundtrip() -> void:
	var trade := _trade()
	var inv := _inv(200)
	trade.buy("arrow", 5, inv)
	inv.add("nut", 3)
	trade.sell("nut", 3, inv)
	var back := _trade()
	back.load_dict(JSON.parse_string(JSON.stringify(trade.to_dict())))
	assert_eq(int(back.stock["arrow"]), 25, "запас")
	assert_eq(back.sell_price("nut"), trade.sell_price("nut"), "насыщение")


func test_board_offers_one_per_type_deterministic() -> void:
	var board := ContractBoardScript.new(_stab()["board"])
	board.refresh(1, 42)
	assert_eq(board.offers.size(), 3, "три предложения")
	var types: Array = board.offers.map(func(c: Dictionary) -> String: return c["type"])
	assert_eq(types, ["hunt", "deliver", "scout"], "по одному на тип")
	var again := ContractBoardScript.new(_stab()["board"])
	again.refresh(1, 42)
	assert_eq(again.offers, board.offers, "тот же сид — те же контракты")
	board.refresh(1, 99)
	assert_eq(again.offers, board.offers, "в тот же день доска не меняется")


func test_hunt_contract_progress_and_reward() -> void:
	var board := ContractBoardScript.new(_stab()["board"])
	board.offers = [{"type": "hunt", "target": "slowpoke", "count": 2, "reward": 4, "progress": 0}]
	assert_true(board.take(0), "взяли")
	assert_eq(board.offers.size(), 0, "ушёл с доски")
	var inv := _inv()
	assert_eq(board.complete(0, inv), 0, "не готов — не сдать")
	board.on_kill("jumper")
	assert_eq(board.on_kill("slowpoke").size(), 0, "1 из 2")
	assert_eq(board.on_kill("slowpoke").size(), 1, "2 из 2 — готово")
	board.on_kill("slowpoke")
	assert_eq(int(board.active[0]["progress"]), 2, "сверх нормы не считается")
	assert_eq(board.complete(0, inv), 4, "награда")
	assert_eq(board.active.size(), 0, "закрыт")


func test_deliver_takes_items_and_scout_on_enter() -> void:
	var board := ContractBoardScript.new(_stab()["board"])
	board.active = [
		{"type": "deliver", "target": "vodka", "count": 2, "reward": 6, "progress": 0},
		{"type": "scout", "target": "c_black", "count": 1, "reward": 30, "progress": 0},
	]
	var inv := _inv()
	inv.add("vodka", 3)
	assert_true(ContractBoardScript.is_ready(board.active[0], inv), "водка есть")
	assert_eq(board.complete(0, inv), 6, "сдали водку")
	assert_eq(inv.count_of("vodka"), 1, "две забрали")
	assert_eq(board.on_enter("c_black").size(), 1, "дошёл до Черноты")
	assert_eq(board.complete(0, inv), 30, "разведка сдана")


func test_board_limit_and_save() -> void:
	var board := ContractBoardScript.new(_stab()["board"])
	board.refresh(2, 7)
	board.active = [{}, {}, {}]
	assert_true(not board.take(0), "больше трёх нельзя")
	board.active = []
	board.take(1)
	var back := ContractBoardScript.new(_stab()["board"])
	back.load_dict(JSON.parse_string(JSON.stringify(board.to_dict())))
	assert_eq(back.active, board.active, "активные")
	assert_eq(typeof(back.active[0]["count"]), TYPE_INT, "числа — целые")
	assert_eq(back.day, 2, "день")


func test_healer_cost_and_gifts() -> void:
	var healer: Dictionary = _stab()["healer"]
	assert_eq(StabRulesScript.heal_cost(0.0, false, healer), 0, "здоров — бесплатно")
	assert_eq(StabRulesScript.heal_cost(17.0, false, healer), 3, "17 здоровья — 3 спорана (вверх)")
	assert_eq(StabRulesScript.heal_cost(8.0, true, healer), 4, "+ кровотечение")
	assert_eq(StabRulesScript.next_gift(9, [], healer), -1, "до 10 уровня даров нет")
	assert_eq(StabRulesScript.next_gift(10, [], healer), 10, "дар 10 уровня")
	assert_eq(StabRulesScript.next_gift(35, [10], healer), 30, "следующий — 30")
	assert_eq(StabRulesScript.next_gift(35, [10, 30], healer), -1, "60 ещё рано")
	var p := StabRulesScript.gift_price(healer, RandomNumberGenerator.new())
	assert_true(p >= 25 and p <= 30, "25–30 споранов")


func test_sleep_and_rumor() -> void:
	var bar: Dictionary = _stab()["bar"]
	assert_almost(StabRulesScript.spore_after_sleep(80.0, 4.0, bar), 48.0, "8 часов по 4")
	assert_true(StabRulesScript.can_sleep(80.0, 4.0, bar), "с запасом — спать можно")
	assert_true(not StabRulesScript.can_sleep(30.0, 4.0, bar), "мало спорового баланса — сначала живчик")
	assert_eq(StabRulesScript.rumor_target(PackedStringArray(), RandomNumberGenerator.new()), "", "слухов нет")
	assert_eq(StabRulesScript.rumor_target(PackedStringArray(["c_town"]), RandomNumberGenerator.new()), "c_town", "единственный")
