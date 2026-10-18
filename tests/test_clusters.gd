extends "res://tests/test_case.gd"
## Кластеры: таймеры и кисляк, граф региона, раскладка шаблонов. docs/spec/02_world.md.

const ClusterLifecycleScript := preload("res://src/core/cluster_lifecycle.gd")
const RegionMapScript := preload("res://src/core/region_map.gd")
const ClusterLayoutScript := preload("res://src/core/cluster_layout.gd")
const LootTableScript := preload("res://src/core/loot_table.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")

const TEMPLATES_DIR := "res://data/world/templates"


func _types() -> Dictionary:
	return JsonDataScript.load_dict("res://data/world/cluster_types.json")["types"]


func _region() -> RegionMap:
	return RegionMapScript.new(JsonDataScript.load_dict("res://data/world/region.json"))


func _templates() -> Dictionary:
	var result := {}
	for file in DirAccess.get_files_at(TEMPLATES_DIR):
		if file.ends_with(".json"):
			var t := JsonDataScript.load_dict(TEMPLATES_DIR.path_join(file))
			result[String(t["id"])] = t
	return result


func _rng(s: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func test_timer_period_in_type_range() -> void:
	var types := _types()
	var rng := _rng()
	for type_id in ["fast", "normal", "black"]:
		var range_: Array = types[type_id]["period_h"]
		for i in 100:
			var timer := ClusterLifecycleScript.new_timer(types[type_id], 1000.0, rng)
			assert_true(float(timer["period_h"]) >= float(range_[0]) and float(timer["period_h"]) <= float(range_[1]), "%s: период в диапазоне" % type_id)
			var first := float(timer["next"]) - 1000.0
			var p := float(timer["period_h"]) * 60.0
			assert_true(first >= p * 0.9 - 0.01 and first <= p * 1.1 + 0.01, "%s: интервал = период ± 10%%" % type_id)


func test_elapsed_fraction_shortens_first_interval() -> void:
	var t := ClusterLifecycleScript.new_timer(_types()["normal"], 0.0, _rng(3), 0.75)
	assert_true(float(t["next"]) <= float(t["period_h"]) * 60.0 * 1.1 * 0.25 + 0.01, "три четверти уже прошло")


func test_stab_never_reloads() -> void:
	var t := ClusterLifecycleScript.new_timer(_types()["stab"], 0.0, _rng())
	assert_eq(ClusterLifecycleScript.phase(t, 1.0e7), ClusterLifecycleScript.NEVER, "стаб — никогда")
	assert_eq(ClusterLifecycleScript.take_due(t, 1.0e7, _types()["stab"], _rng()).size(), 0, "сбросов нет")
	assert_eq(ClusterLifecycleScript.timer_text(t, 0.0, true), "—", "в интерфейсе — прочерк")


func test_kislyak_window_before_reload() -> void:
	var t := {"period_h": 10.0, "jitter": 0.0, "next": 600.0, "kislyak_min": 60.0}
	assert_eq(ClusterLifecycleScript.phase(t, 500.0), ClusterLifecycleScript.CALM, "за 100 мин — спокойно")
	assert_eq(ClusterLifecycleScript.phase(t, 545.0), ClusterLifecycleScript.KISLYAK, "за 55 мин — кисляк")
	var types := _types()
	for type_id in ["fast", "normal"]:
		var k := ClusterLifecycleScript.roll_kislyak(types[type_id], _rng())
		assert_true(k >= float(types[type_id]["kislyak_min"][0]) and k <= float(types[type_id]["kislyak_min"][1]), "%s: кисляк в диапазоне" % type_id)
	# Быстрый кластер: кисляк заметно короче интервала, иначе туман стоял бы всегда.
	assert_true(float(types["fast"]["kislyak_min"][1]) < float(types["fast"]["period_h"][0]) * 60.0 * 0.5, "кисляк быстрого < половины интервала")


func test_take_due_catches_up_after_time_skip() -> void:
	var fast: Dictionary = _types()["fast"]
	var t := {"period_h": 2.0, "jitter": 0.0, "next": 120.0, "kislyak_min": 20.0}
	assert_eq(ClusterLifecycleScript.take_due(t, 100.0, fast, _rng()).size(), 0, "ещё рано")
	var due := ClusterLifecycleScript.take_due(t, 400.0, fast, _rng())
	assert_eq(due, [120.0, 240.0, 360.0] as Array[float], "три сброса за прокрутку")
	assert_almost(float(t["next"]), 480.0, "следующий — после now")


func test_timer_text_known_and_unknown() -> void:
	var t := {"period_h": 10.0, "jitter": 0.0, "next": 600.0, "kislyak_min": 60.0}
	assert_eq(ClusterLifecycleScript.timer_text(t, 475.0, false), "??:??", "неизвестен")
	assert_eq(ClusterLifecycleScript.timer_text(t, 475.0, true), "02:05", "известен — часы:минуты")


func test_reload_seed_differs_per_reload() -> void:
	var a := ClusterLifecycleScript.reload_seed(5, "c_town", 1)
	assert_eq(a, ClusterLifecycleScript.reload_seed(5, "c_town", 1), "воспроизводимо")
	assert_true(a != ClusterLifecycleScript.reload_seed(5, "c_town", 2), "новая перезагрузка — новый сид")
	assert_true(a != ClusterLifecycleScript.reload_seed(5, "c_village", 1), "другой кластер — другой сид")


func test_region_graph_valid() -> void:
	var region := _region()
	var templates := PackedStringArray(_templates().keys())
	var errors := region.errors(templates, PackedStringArray(_types().keys()))
	assert_eq(errors, PackedStringArray(), "ошибки графа")
	assert_eq(region.ids().size(), 6, "6 кластеров среза")
	var types: Array = []
	for id in region.ids():
		types.append(region.cluster(id)["type"])
	for needed in ["fast", "normal", "black", "stab"]:
		assert_true(types.has(needed), "есть тип %s" % needed)


func test_region_errors_detect_bad_edges() -> void:
	var data := {"id": "r", "name": "r", "start": "a", "respawn": "a", "clusters": [
		{"id": "a", "code": "1", "name": "A", "type": "fast", "template": "t", "map_pos": [0, 0], "neighbors": ["b", "zzz"]},
		{"id": "b", "code": "2", "name": "B", "type": "fast", "template": "t", "map_pos": [1, 0], "neighbors": []},
	]}
	var errors := RegionMapScript.new(data).errors(PackedStringArray(["t"]), PackedStringArray(["fast"]))
	assert_eq(errors.size(), 2, "несимметричное ребро и неизвестный сосед: %s" % str(errors))


func test_exit_points_on_edge_towards_neighbor() -> void:
	var region := _region()
	var p := region.exit_point("c_start", "c_village", 110.0, 3.0)
	assert_almost(p.x, 52.0, "сосед на востоке — выход на восточном краю")
	assert_almost(p.y, 0.0, "по центру края")
	var q := region.exit_point("c_village", "c_stab", 140.0, 3.0)
	assert_almost(q.y, -67.0, "стаб севернее (−y) — выход на северном краю карты")
	assert_true(q.x > 0.0, "и чуть восточнее")


func test_layouts_valid_and_deterministic() -> void:
	var loot := LootTableScript.new([JsonDataScript.load_dict("res://data/loot/places.json")])
	for id: String in _templates():
		var template: Dictionary = _templates()[id]
		for key in ClusterLayoutScript.REQUIRED_KEYS:
			assert_true(template.has(key), "%s: ключ %s" % [id, key])
		var clear := [{"at": Vector2.ZERO, "r": 8.0}]
		var layout := ClusterLayoutScript.generate(template, clear)
		assert_eq(layout, ClusterLayoutScript.generate(template, clear), "%s: детерминированно" % id)
		var expected := 0
		for group: Dictionary in template["buildings"]:
			expected += int(group["count"])
		assert_eq(layout["buildings"].size(), expected, "%s: все здания поместились" % id)
		var rects: Array[Rect2] = []
		for b: Dictionary in layout["buildings"]:
			var rect := Rect2(b["center"] - b["size"] / 2.0, b["size"])
			assert_true(Rect2(-layout["half"], -layout["half"], layout["half"] * 2, layout["half"] * 2).encloses(rect), "%s: здание внутри" % id)
			assert_true(Vector2.ZERO.distance_to(b["center"]) > 8.0, "%s: чистая зона пуста" % id)
			for other in rects:
				assert_true(not rect.intersects(other), "%s: здания не пересекаются" % id)
			rects.append(rect)
		for point: Dictionary in layout["loot"] + layout["stashes"]:
			assert_true(loot.has_table(point["table"]), "%s: таблица %s" % [id, point["table"]])


func test_roll_loot_respects_index() -> void:
	var loot := LootTableScript.new([JsonDataScript.load_dict("res://data/loot/places.json")])
	var points: Array = []
	for i in 200:
		points.append({"at": Vector2(i, 0), "table": "spot_shop"})
	var full := ClusterLayoutScript.roll_loot(points, loot, 1.0, 0.0, _rng(9)).size()
	var looted := ClusterLayoutScript.roll_loot(points, loot, 0.25, 0.0, _rng(9)).size()
	assert_true(looted < full * 0.4 and looted > full * 0.1, "разграблено ~3/4: %d из %d" % [looted, full])
	assert_eq(ClusterLayoutScript.roll_loot(points, loot, 0.0, 0.0, _rng(9)).size(), 0, "всё вынесли")
	var stashes := ClusterLayoutScript.roll_stashes(points.slice(0, 3), loot, 0.0, _rng(9))
	assert_eq(stashes.size(), 3, "по списку на тайник")
