class_name LootTable
extends RefCounted
## Бросок содержимого спорового мешка по таблице (data/loot/*.json, схема 14.3).
## Шанс диапазоном — интерполяция по уровню твари внутри стадии; Удача умножает шансы.
## Чистый класс без Node. Спецификация: docs/spec/06_trophies_items.md, 6.1.

const REQUIRED_KEYS: PackedStringArray = ["luck_scaling", "tables"]

var _tables: Dictionary = {}
var _luck: Dictionary


func _init(files: Array) -> void:
	for file: Dictionary in files:
		_luck = file.get("luck_scaling", _luck)
		for table: Dictionary in file.get("tables", []):
			_tables[String(table["id"])] = table


func has_table(id: String) -> bool:
	return _tables.has(id)


## Доля уровня внутри стадии: 0 — младший, 1 — старший.
static func level_fraction(level: int, level_range: Array) -> float:
	var low := int(level_range[0])
	var high := int(level_range[1])
	return 0.0 if high <= low else clampf(float(level - low) / float(high - low), 0.0, 1.0)


## Множитель шансов от Удачи (итоговое значение).
func luck_multiplier(luck: float) -> float:
	return minf(float(_luck["cap"]), 1.0 + maxf(0.0, luck) / 100.0 * float(_luck["chance_mult_per_100_luck"]))


## Шанс строки таблицы с учётом уровня и Удачи.
func chance(roll: Dictionary, level_frac: float, luck: float) -> float:
	var c: Variant = roll["chance"]
	var base := lerpf(float(c[0]), float(c[1]), level_frac) if c is Array else float(c)
	return minf(1.0, base * luck_multiplier(luck))


## Бросок: {"sporan": 3, "grain": 1}. Пустой словарь — мешок пуст.
func roll(table_id: String, level_frac: float, luck: float, rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for row: Dictionary in _tables[table_id]["rolls"]:
		if rng.randf() >= chance(row, level_frac, luck):
			continue
		var item := String(row["item"]) if row.has("item") else _pick(row["one_of"], rng)
		var count := rng.randi_range(int(row["count"][0]), int(row["count"][1]))
		if count > 0:
			result[item] = int(result.get(item, 0)) + count
	return result


func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for option: Dictionary in options:
		total += float(option["weight"])
	var r := rng.randf() * total
	for option: Dictionary in options:
		r -= float(option["weight"])
		if r <= 0.0:
			return String(option["item"])
	return String(options[-1]["item"])
