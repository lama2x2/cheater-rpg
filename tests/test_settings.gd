extends "res://tests/test_case.gd"
## Настройки игрока и режим сохранений: docs/spec/12_ui_ux.md, 12.6a; D-30.

const SettingsModelScript := preload("res://src/core/settings_model.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _model() -> SettingsModel:
	return SettingsModelScript.new(JsonDataScript.load_dict("res://data/settings.json"))


func test_defaults() -> void:
	var m := _model()
	assert_eq(m.get_value("save_mode"), "anywhere", "по умолчанию — где угодно")
	assert_eq(m.get_value("noise_ring"), true, "кольцо шума включено")
	assert_almost(float(m.get_value("volume")), 0.8, "громкость")


func test_saved_values_validated() -> void:
	var m := _model()
	m.load_saved({
		"save_mode": "stab_only", "volume": 3.0, "fullscreen": "да", "window_size": [800, 600],
		"noise_ring": false, "unknown": 1,
	})
	assert_eq(m.get_value("save_mode"), "stab_only", "допустимое — принято")
	assert_almost(float(m.get_value("volume")), 1.0, "громкость обрезана до 1")
	assert_eq(m.get_value("fullscreen"), false, "не bool — умолчание")
	assert_eq(m.get_value("window_size"), [1600, 900], "размера нет в списке — умолчание")
	assert_eq(m.get_value("noise_ring"), false, "кольцо выключено")
	assert_true(not m.to_dict().has("unknown"), "неизвестное выброшено")
	assert_true(not m.set_value("save_mode", "never"), "неизвестный режим не ставится")


func test_json_roundtrip_window_size() -> void:
	var m := _model()
	m.set_value("window_size", [1920, 1080])
	var back := _model()
	back.load_saved(JSON.parse_string(JSON.stringify(m.to_dict())))
	assert_eq(back.get_value("window_size"), [1920, 1080], "размер окна после JSON (числа float)")


func test_next_option_cycles() -> void:
	var m := _model()
	assert_eq(m.next_option("save_mode"), "stab_only", "следующий режим")
	m.set_value("save_mode", "stab_only")
	assert_eq(m.next_option("save_mode"), "anywhere", "по кругу")
	m.set_value("window_size", [1920, 1080])
	assert_eq(m.next_option("window_size"), [1280, 720], "размеры по кругу")


func test_manual_save_by_mode() -> void:
	assert_true(SettingsModelScript.can_manual_save("anywhere", false), "где угодно — и вне стаба")
	assert_true(not SettingsModelScript.can_manual_save("stab_only", false), "хардкор вне стаба — нельзя")
	assert_true(SettingsModelScript.can_manual_save("stab_only", true), "хардкор в стабе — можно")


func test_volume_db() -> void:
	assert_almost(SettingsModelScript.volume_db(1.0), 0.0, "полная — 0 дБ")
	assert_almost(SettingsModelScript.volume_db(0.0), -80.0, "ноль — тишина")
	assert_true(SettingsModelScript.volume_db(0.5) < -5.0, "половина — тише")


func test_ui_scale_options() -> void:
	var m := _model()
	assert_almost(float(m.get_value("ui_scale")), 1.0, "по умолчанию 100% (интерфейс и так тянется под окно)")
	assert_true(m.set_value("ui_scale", 1.5), "150% — есть в списке")
	assert_true(not m.set_value("ui_scale", 1.3), "130% — нет в списке")
	assert_almost(float(m.next_option("ui_scale")), 1.75, "следующий шаг")
	m.set_value("ui_scale", 2.0)
	assert_almost(float(m.next_option("ui_scale")), 1.0, "по кругу")
