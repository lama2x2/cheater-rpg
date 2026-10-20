extends "res://tests/test_case.gd"
## Ландшафт (19a, D-71, 17.4): ровно у построек, тот же рельеф по сиду, ручей с бродом,
## растительность вне построек и воды, кусты прячут, замедление и тишина.

const TerrainRulesScript := preload("res://src/core/terrain_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _terrain(template: String = "village", free_sides: Array = [0]) -> TerrainRules:
	var t := JsonDataScript.load_dict("res://data/world/templates/%s.json" % template)
	var rules := TerrainRulesScript.new(JsonDataScript.load_dict("res://data/terrain.json"), t["terrain"], float(t["size"]), int(t["layout_seed"]), free_sides)
	rules.set_features([Rect2(-5, -5, 10, 10), Vector2(-20, 0)])
	rules.scatter()
	return rules


func test_flat_at_features_and_hills_elsewhere() -> void:
	var t := _terrain()
	assert_almost(t.height_at(Vector2(0, 0)), 0.0, "под постройкой — ровно")
	assert_almost(t.height_at(Vector2(-20, 0)), 0.0, "у точки — ровно")
	var max_h := 0.0
	for i in 60:
		max_h = maxf(max_h, t.height_at(Vector2(-40 + i * 1.3, 25)))
	assert_true(max_h > 0.5, "вдали — холмы: %f" % max_h)
	assert_almost(_terrain().height_at(Vector2(13, 31)), t.height_at(Vector2(13, 31)), "тот же сид — тот же рельеф")


func test_stream_and_ford() -> void:
	var t := _terrain("village", [0])
	assert_true(not t.stream.is_empty(), "у деревни — ручей на свободной стороне")
	var axis: float = t.stream["offset"]
	assert_eq(t.water_at(Vector2(axis, 20)), "water", "на оси ручья вдали от брода — глубоко")
	assert_eq(t.water_at(Vector2(axis, 0)), "ford", "посередине — брод")
	assert_eq(t.water_at(Vector2(axis - 10, 20)), "", "в стороне — сухо")
	assert_true(_terrain("village", []).stream.is_empty(), "нет свободной стороны — нет ручья")
	assert_true(not t.stream_clear_zones().is_empty(), "раскладка обходит русло")


func test_plants_avoid_features_and_water() -> void:
	var t := _terrain()
	var counts := {}
	for p: Dictionary in t.plants:
		counts[p["kind"]] = int(counts.get(p["kind"], 0)) + 1
		var at: Vector2 = p["at"]
		assert_true(not Rect2(-5, -5, 10, 10).has_point(at), "ничего на постройке")
		assert_eq(t.water_at(at), "", "ничего в воде")
	assert_true(int(counts.get("tree", 0)) > 20 and int(counts.get("bush", 0)) > 20, "деревья и кусты есть: %s" % [counts])


func test_bushes_hide_and_slow() -> void:
	var t := _terrain()
	var bush: Vector2 = Vector2.INF
	for p: Dictionary in t.plants:
		if p["kind"] == "bush":
			bush = p["at"]
			break
	assert_true(t.in_bush(bush), "в кусте")
	assert_almost(t.visibility_mult(bush), 0.6, "в кусте видно хуже")
	assert_almost(t.noise_mult(bush), 0.7, "в кусте шаги тише")
	assert_true(t.speed_mult(bush) < 1.0, "в кусте медленнее")
	var far := bush + Vector2(12, 0)
	assert_true(not t.bush_visible(far, bush), "в кусте издалека не видно")
	assert_true(t.bush_visible(bush + Vector2(2.5, 0), bush), "вблизи — видно")
	assert_true(not t.bush_visible(bush + Vector2(-6, 0), bush + Vector2(6, 0)), "куст между — закрывает")


func test_slope_and_height_view() -> void:
	var t := _terrain()
	var config: Dictionary = JsonDataScript.load_dict("res://data/terrain.json")
	assert_almost(t.height_view_bonus(2.0), 2.0 * float(config["height_view_per_m"]), "с высоты видно дальше")
	var slowest := 1.0
	for i in 80:
		var p := Vector2(-40 + i, 30)
		slowest = minf(slowest, t.speed_mult(p, Vector2(1, 0)))
	assert_true(slowest < 1.0 and slowest >= float(config["slope_min_mult"]), "в гору медленнее, но не стоп: %f" % slowest)
