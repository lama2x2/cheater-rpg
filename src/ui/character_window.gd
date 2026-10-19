extends CanvasLayer
## Экран персонажа (12.4, клавиша P): общий и дополнительный уровень, опытность; основные и
## дополнительные характеристики — уровень, итог (по наведению — «уровень × коэффициент × рост от
## общего уровня» и баффы), полоса прогресса до следующего уровня; шкалы; скрытые — «???»;
## свободные очки — «+» у характеристики с подтверждением (PlayerState.spend_free_point).

## Свободные очки сюда не тратятся: Грани Таланта и Забота о стиксах — особые (D-92).
const NO_FREE_POINTS: PackedStringArray = ["talent_facets", "stix_care"]

var _panel: PanelContainer
var _content: VBoxContainer
var _confirm: ConfirmationDialog
var _pending_stat := ""
var _dirty := false


func _ready() -> void:
	layer = 5
	visible = false
	add_to_group("character_window")
	_panel = UiKit.panel()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -380
	_panel.offset_right = 380
	_panel.offset_top = 70
	_panel.anchor_bottom = 1.0
	_panel.offset_bottom = -16
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)
	root.add_child(UiKit.header(Content.ui("char_title"), Content.ui("char_keys", {"key": InputSetup.key_label("character")}), close))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_content)
	_confirm = ConfirmationDialog.new()
	_confirm.title = Content.ui("char_confirm_title")
	_confirm.ok_button_text = Content.ui("confirm_ok")
	_confirm.cancel_button_text = Content.ui("confirm_cancel")
	_confirm.confirmed.connect(func() -> void: PlayerState.spend_free_point(_pending_stat))
	add_child(_confirm)
	PlayerState.stats_changed.connect(func() -> void: _dirty = true)
	PlayerState.inventory_changed.connect(func() -> void: _dirty = true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("character"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	UiKit.window_opened(self)
	_refresh()


func close() -> void:
	visible = false
	UiKit.window_closed(self)


func _process(_delta: float) -> void:
	if visible and (_dirty or Engine.get_process_frames() % 60 == 0):
		_dirty = false
		_refresh()


func _refresh() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var stats := PlayerState.stats
	_text(Content.ui("char_summary", {"general": stats.general_level(), "additional": stats.additional_level(),
		"exp": roundi((stats.experience_multiplier() - 1.0) * 100.0), "lives": PlayerState.lives, "deaths": PlayerState.deaths}), 15, UiKit.TEXT)
	if PlayerState.free_points > 0:
		_text(Content.ui("char_free_points", {"n": PlayerState.free_points}), 15, UiKit.ACCENT)
	_section(Content.ui("char_main"))
	for stat in stats.main_stats():
		_stat_row(stat)
	_section(Content.ui("char_additional"))
	for stat in stats.additional_stats():
		_stat_row(stat)
	_section(Content.ui("char_vitals"))
	var vitals := PlayerState.vitals
	for vital in Vitals.ALL:
		_text("%s: %d / %d" % [Content.ui("vital_" + vital), roundi(vitals.value(vital)), roundi(vitals.max_value(vital))], 14, UiKit.TEXT)
	_section(Content.ui("char_other"))
	_text(Content.ui("char_humanity"), 14, UiKit.TEXT_DIM)
	_section(Content.ui("char_hidden"))
	for i in 3:
		_text("???", 14, UiKit.TEXT_DIM)
	_text(Content.ui("char_hidden_hint"), 12, UiKit.TEXT_DIM)


func _stat_row(stat: String) -> void:
	var stats := PlayerState.stats
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var level := stats.get_level(stat)
	var buff := PlayerState.buffs.multiplier(stat, GameClock.minutes)
	var name := UiKit.label(14, UiKit.TEXT)
	name.text = Content.stat_name(stat)
	name.custom_minimum_size.x = 230
	name.mouse_filter = Control.MOUSE_FILTER_PASS
	var growth := 1.0 + float(Content.stats_config()["base_growth_per_general_level"]) * stats.general_level()
	name.tooltip_text = Content.ui("char_stat_tip", {"level": level, "coef": _num(stats.get_coefficient(stat)), "growth": _num(growth),
		"value": _num(stats.effective_value(stat)), "buff": "" if is_equal_approx(buff, 1.0) else Content.ui("char_stat_buff", {"p": roundi((buff - 1.0) * 100.0)}),
		"progress": _num(stats.get_progress(stat)), "need": _num(stats.threshold(stat))})
	row.add_child(name)
	var value := UiKit.label(14, UiKit.GOOD if buff > 1.0 else UiKit.TEXT)
	value.text = "%d  (%s)" % [level, _num(PlayerState.effective(stat))]
	value.custom_minimum_size.x = 110
	row.add_child(value)
	var bar := UiKit.bar(stats.get_progress(stat), stats.threshold(stat), Color(0.55, 0.75, 0.5))
	bar.tooltip_text = name.tooltip_text
	row.add_child(bar)
	if PlayerState.free_points > 0 and not NO_FREE_POINTS.has(stat):
		row.add_child(UiKit.button("+", _ask_spend.bind(stat), 14))
	_content.add_child(row)


func _ask_spend(stat: String) -> void:
	_pending_stat = stat
	_confirm.dialog_text = Content.ui("char_confirm_text", {"stat": Content.stat_name(stat), "n": PlayerState.free_points})
	_confirm.popup_centered()


func _section(title: String) -> void:
	var label := UiKit.label(16, Color(0.85, 0.75, 0.55))
	label.text = title
	_content.add_child(label)


func _text(text: String, size: int, color: Color) -> void:
	var label := UiKit.label(size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)


static func _num(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")
