extends CanvasLayer
## Отладочный HUD: жизни, уровень, время, кластер с таймером, Скорость и подсказка клавиш.
## Строки лога Системы — src/ui/log_panel.gd (задача 16).

var _status: Label
## Подсказка клавиш — из текущих привязок (переназначение в меню «Клавиши», 12.8).
var _help := ""


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New"])

	_status = _label(font)
	_status.position = Vector2(16, 16)
	add_child(_status)

	_on_settings()
	Settings.changed.connect(_on_settings)


func _process(_delta: float) -> void:
	var stats := PlayerState.stats
	var hero := get_tree().get_first_node_in_group("hero")
	var mode := "   КРАДЁТСЯ" if hero and hero.sneaking else ""
	_status.text = "Жизни: %d    Уровень: %d    %s%s\n%s\nСкорость: %d  (%.1f / %.0f)\n\n%s" % [
		PlayerState.lives, stats.general_level(), GameClock.clock_text(), mode, WorldSim.hud_line(),
		stats.get_level("speed"), stats.get_progress("speed"), stats.threshold("speed"), _help,
	]


func _on_settings(_key: String = "") -> void:
	var k := func(action: String) -> String: return InputSetup.key_label(action)
	_help = "[%s%s%s%s] идти  [%s] бежать  [%s] красться  [ЛКМ] удар  [%s] перезарядка  [%s] оружие  [%s] взгляд\n[%s] взять  [%s] инвентарь  [%s] персонаж  [%s] умения  [%s] карта  [%s] лог  [F1–F4] быстрые слоты  [Esc] меню · клавиши" % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("sprint"), k.call("sneak"),
		k.call("reload"), k.call("weapon_next"), k.call("gaze"), k.call("interact"), k.call("inventory"), k.call("character"),
		k.call("skills"), k.call("map"), k.call("log")]


func _label(font: Font) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return label
