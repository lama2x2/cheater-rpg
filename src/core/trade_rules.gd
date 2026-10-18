class_name TradeRules
extends RefCounted
## Торговля в стабе: цены покупки и продажи, насыщение спроса (торговец не скупает бесконечно
## одно и то же), запас товара с пополнением раз в сутки, сделки с инвентарём героя за спораны.
## Чистый класс без Node. Числа — data/stab.json (trade). Спецификация: docs/spec/10_stabs_economy.md.

const CURRENCY := "sporan"

## Сколько штук вида продано торговцу недавно (насыщение): {"pea_yellow": 4.5}.
var sold: Dictionary = {}
## Сколько осталось в продаже: {"vodka": 3}.
var stock: Dictionary = {}
## Игровые сутки последнего пополнения.
var day: int = 0

var _config: Dictionary
var _db: ItemDB


func _init(config: Dictionary, db: ItemDB) -> void:
	_config = config
	_db = db
	stock = config["stock"].duplicate()


## Новые сутки: запас пополнен, насыщение спадает (за каждые прошедшие сутки).
func refresh(today: int) -> void:
	if today <= day:
		return
	var keep := pow(1.0 - float(_config["recover_per_day"]), today - day)
	for id: String in sold.keys():
		sold[id] = float(sold[id]) * keep
		if float(sold[id]) < 0.05:
			sold.erase(id)
	stock = _config["stock"].duplicate()
	day = today


static func money(inventory: Inventory) -> int:
	return inventory.count_of(CURRENCY)


func buys(id: String) -> bool:
	return not _config["not_sold"].has(id) and int(_db.item(id).get("base_price", 0)) > 0


func buy_price(id: String) -> int:
	return maxi(1, ceili(float(_db.item(id)["base_price"]) * float(_config["buy_mult"])))


func saturation(id: String) -> float:
	return maxf(float(_config["saturation_min"]), 1.0 - float(_config["saturation_per_unit"]) * float(sold.get(id, 0.0)))


## Сколько торговец даст за одну штуку сейчас (0 — не берёт или уже ничего не даст), с округлением.
func sell_price(id: String) -> int:
	if not buys(id):
		return 0
	return roundi(float(_db.item(id)["base_price"]) * float(_config["sell_mult"]) * saturation(id))


## Купить count штук. Результат: {"ok", "reason" ("stock"/"money"), "cost", "left" — не влезло}.
func buy(id: String, count: int, inventory: Inventory) -> Dictionary:
	if int(stock.get(id, 0)) < count or count <= 0:
		return {"ok": false, "reason": "stock"}
	var cost := buy_price(id) * count
	if money(inventory) < cost:
		return {"ok": false, "reason": "money"}
	inventory.remove(CURRENCY, cost)
	stock[id] = int(stock[id]) - count
	return {"ok": true, "cost": cost, "left": int(inventory.add(id, count)["left"])}


## Продать count штук: цена считается поштучно (каждая следующая — дешевле из-за насыщения).
## Результат: {"ok", "reason" ("missing"/"refused"), "gain", "left" — спораны, что не влезли}.
func sell(id: String, count: int, inventory: Inventory) -> Dictionary:
	if not buys(id):
		return {"ok": false, "reason": "refused"}
	if count <= 0 or inventory.count_of(id) < count:
		return {"ok": false, "reason": "missing"}
	var gain := 0
	for i in count:
		gain += sell_price(id)
		sold[id] = float(sold.get(id, 0.0)) + 1.0
	inventory.remove(id, count)
	return {"ok": true, "gain": gain, "left": int(inventory.add(CURRENCY, gain)["left"]) if gain > 0 else 0}


func to_dict() -> Dictionary:
	return {"sold": sold.duplicate(), "stock": stock.duplicate(), "day": day}


func load_dict(data: Dictionary) -> void:
	sold = data.get("sold", {}).duplicate()
	stock = {}
	var saved: Dictionary = data.get("stock", _config["stock"])
	for id: String in saved:
		stock[id] = int(saved[id])
	day = int(data.get("day", 0))
