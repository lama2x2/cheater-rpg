extends CanvasLayer
## Экран итогов при 0 жизней (D-02): «фанфары», эпитафия, статистика героя, лучшие строки лога.
## Дальше (D-34): «Дальше» — тот же герой и мир с новыми жизнями, «Новая игра+» — новый мир
## с переносом ячеек Системы и бонусом к коэффициентам.
## Спецификация: docs/spec/04_death_lives.md, 4.1.

## mode: "continue" или "ng_plus".
signal continue_pressed(mode: String)

const GOLD := Color(0.95, 0.78, 0.3)
const LINE_DELAY := 0.25

var _shade: ColorRect
var _box: VBoxContainer
var _confetti: CPUParticles2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 11
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(0.03, 0.03, 0.05, 0.95)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)

	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 160
	_confetti.lifetime = 4.0
	_confetti.explosiveness = 0.85
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(800, 10)
	_confetti.direction = Vector2.DOWN
	_confetti.spread = 30.0
	_confetti.gravity = Vector2(0, 160)
	_confetti.initial_velocity_min = 60.0
	_confetti.initial_velocity_max = 220.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	_confetti.scale_amount_min = 4.0
	_confetti.scale_amount_max = 8.0
	var colors := Gradient.new()
	colors.set_color(0, GOLD)
	colors.set_color(1, Color(0.8, 0.25, 0.2))
	_confetti.color_initial_ramp = colors
	add_child(_confetti)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 80
	scroll.offset_right = -80
	scroll.offset_top = 50
	scroll.offset_bottom = -40
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)


func open() -> void:
	for child in _box.get_children():
		child.queue_free()
	visible = true
	var viewport_size := get_viewport().get_visible_rect().size
	_confetti.position = Vector2(viewport_size.x / 2.0, -20)
	_confetti.emission_rect_extents = Vector2(viewport_size.x / 2.0, 10)
	_confetti.restart()

	var title := UiKit.label(44, GOLD)
	title.text = Content.ui("summary_title")
	_box.add_child(title)
	var pulse := create_tween().set_loops()
	pulse.tween_property(title, "modulate", Color(1.3, 1.3, 1.3), 0.6)
	pulse.tween_property(title, "modulate", Color.WHITE, 0.6)

	var lines: Array = []
	var epitaphs: Array = Content.texts()["epitaphs"]
	lines.append([Content.ui("summary_epitaph", {"text": epitaphs[_rng.randi_range(0, epitaphs.size() - 1)]}), 18, Color(0.8, 0.8, 0.8)])
	lines.append(["", 8, Color.WHITE])
	for row in _stat_rows():
		lines.append([row, 18, Color(0.9, 0.9, 0.9)])
	var highlights := DeathRules.pick_highlights(SystemLog.highlights, Content.death_config())
	if not highlights.is_empty():
		lines.append(["", 8, Color.WHITE])
		lines.append([Content.ui("summary_highlights"), 20, GOLD])
		for text in highlights:
			lines.append(["› " + text, 16, Color(0.6, 0.8, 0.6)])

	var delay := 0.6
	for line: Array in lines:
		var label := UiKit.label(line[1], line[2])
		label.text = line[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.modulate.a = 0.0
		_box.add_child(label)
		create_tween().tween_property(label, "modulate:a", 1.0, 0.4).set_delay(delay)
		delay += LINE_DELAY

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.modulate.a = 0.0
	_box.add_child(buttons)
	var first: Button = null
	for spec: Array in [["summary_continue", "continue"], ["summary_ng_plus", "ng_plus"]]:
		var button := Button.new()
		button.text = Content.ui(spec[0], {"cycle": PlayerState.ng_plus + 1})
		button.add_theme_font_override("font", UiKit.font())
		button.add_theme_font_size_override("font_size", 20)
		button.custom_minimum_size = Vector2(260, 44)
		button.pressed.connect(_on_choice.bind(spec[1]))
		buttons.add_child(button)
		if first == null:
			first = button
	var hint := UiKit.label(14, Color(0.6, 0.6, 0.6))
	hint.text = Content.ui("summary_ng_plus_hint")
	hint.modulate.a = 0.0
	_box.add_child(hint)
	create_tween().tween_property(buttons, "modulate:a", 1.0, 0.4).set_delay(delay)
	create_tween().tween_property(hint, "modulate:a", 1.0, 0.4).set_delay(delay)
	first.grab_focus.call_deferred()


func close() -> void:
	visible = false


func _stat_rows() -> PackedStringArray:
	var stats := PlayerState.stats
	var run := PlayerState.run
	var rows: PackedStringArray = []
	rows.append(Content.ui("summary_days", {"days": GameClock.day()}))
	rows.append(Content.ui("summary_level", {"level": stats.general_level()}))
	var parts: PackedStringArray = []
	for stat in stats.main_stats():
		parts.append("%s %d" % [Content.stat_name(stat), stats.get_level(stat)])
	rows.append(Content.ui("summary_stats", {"stats": ", ".join(parts)}))
	var causes := run.causes_ranked()
	if not causes.is_empty():
		rows.append(Content.ui("summary_deaths", {
			"deaths": run.deaths.size(), "cause": Content.death_cause(causes[0][0]), "times": causes[0][1]}))
	rows.append(Content.ui("summary_kills", {"kills": run.count("kills")}))
	rows.append(_origin_line())
	rows.append(Content.ui("summary_mode_sandbox") if PlayerState.game_mode == OnboardingRules.SANDBOX
		else Content.ui("summary_mode_story", {"version": Content.ui("story_" + PlayerState.story_version)}))
	var changes := run.count("save_mode_changes")
	rows.append(Content.ui("summary_save_mode", {
		"mode": Content.ui("save_mode_" + PlayerState.save_mode),
		"changes": Content.ui("summary_save_mode_changes", {"n": changes}) if changes > 0 else "",
	}))
	var longest := run.longest_life_minutes(PlayerState.start_minutes)
	rows.append(Content.ui("summary_longest_life", {"hours": floori(longest / 60.0), "minutes": floori(fmod(longest, 60.0))}))
	return rows


func _on_choice(mode: String) -> void:
	close()
	continue_pressed.emit(mode)


## Строка происхождения (16.1): читер с вариантом, обычный или «обычный → читер (день N)».
func _origin_line() -> String:
	if PlayerState.origin == OriginRules.CHEATER:
		return Content.ui("summary_origin_cheater", {"name": Content.ui("origin_" + PlayerState.origin_variant),
			"how": Content.ui("summary_origin_chosen" if PlayerState.origin_chosen else "summary_origin_random")})
	if PlayerState.cheater_property:
		return Content.ui("summary_origin_later", {"day": PlayerState.cheater_since_day})
	return Content.ui("summary_origin_ordinary")
