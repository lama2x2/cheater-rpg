extends CanvasLayer
## Меню по Esc: пауза (единственная пауза в игре, D-05), сохранение в ячейки, загрузка (ячейки и
## автосейв), настройки, новая игра (экран с режимом сохранений, D-30), выход. Ячейки —
## SaveService.manual_slots(). Тот же узел — титульный экран при запуске (open_title).

var _shade: ColorRect
var _box: VBoxContainer
var _confirm: ConfirmationDialog
var _on_confirm: Callable
## Титульный экран: вместо «Продолжить игру» — «Продолжить» (последнее сохранение), Esc не закрывает.
var _title_mode := false
## Выбор на экране новой игры.
var _new_save_mode := ""
## Страница «Клавиши»: ждём нажатия для этого действия ("" — не ждём).
var _waiting_action := ""
var _bindings: KeyBindings


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.7)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	center.add_child(_box)
	_confirm = ConfirmationDialog.new()
	_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm.confirmed.connect(func() -> void: _on_confirm.call())
	add_child(_confirm)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		# Esc сначала закрывает верхнее открытое окно (12.8), меню — только если окон нет.
		if not visible and UiKit.close_top():
			get_viewport().set_input_as_handled()
			return
		if _title_mode:
			_main_page()
		elif visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


## Титульный экран поверх свежего мира (при запуске игры).
func open_title() -> void:
	_title_mode = true
	visible = true
	_shade.color = Color(0.02, 0.03, 0.03, 0.92)
	get_tree().paused = true
	_main_page()


func _open() -> void:
	_title_mode = false
	_shade.color = Color(0, 0, 0, 0.7)
	visible = true
	get_tree().paused = true
	_main_page()


func _close() -> void:
	_title_mode = false
	visible = false
	get_tree().paused = false


func _main_page() -> void:
	if _title_mode:
		_title_page()
		return
	_clear(Content.ui("menu_title"))
	_button(Content.ui("menu_resume"), _close)
	var can_save := SaveService.can_manual_save()
	var save := _button(Content.ui("menu_save") if can_save else Content.ui("menu_save_stab_only"), _save_page)
	save.disabled = not can_save
	_button(Content.ui("menu_load"), _load_page)
	_button(Content.ui("menu_settings"), _settings_page)
	_button(Content.ui("menu_keys"), _keys_page)
	_button(Content.ui("menu_new"), func() -> void: _ask(Content.ui("menu_confirm_new"), _open_new_game))
	_button(Content.ui("menu_quit"), func() -> void: get_tree().quit())


func _title_page() -> void:
	_clear(Content.ui("title_name"))
	_text(Content.ui("title_subtitle"), 16, Color(0.7, 0.75, 0.7))
	var latest := SaveService.latest_slot()
	var resume := _button(Content.ui("title_continue"), _load.bind(latest))
	resume.disabled = latest.is_empty()
	_button(Content.ui("menu_new"), _open_new_game)
	_button(Content.ui("menu_load"), _load_page)
	_button(Content.ui("menu_settings"), _settings_page)
	_button(Content.ui("menu_keys"), _keys_page)
	_button(Content.ui("menu_quit"), func() -> void: get_tree().quit())


## Экран новой игры: режим сохранений (D-30), дальше — предыстория (D-10).
func _open_new_game() -> void:
	_new_save_mode = String(Settings.value("save_mode"))
	_new_game_page()


func _new_game_page() -> void:
	_clear(Content.ui("new_game_title"))
	_text(Content.ui("new_game_save_mode"), 18, Color(0.85, 0.75, 0.55))
	for mode in [SettingsModel.ANYWHERE, SettingsModel.STAB_ONLY]:
		var mark := "●" if mode == _new_save_mode else "○"
		_button("%s %s" % [mark, Content.ui("save_mode_" + mode)], func() -> void:
			_new_save_mode = mode
			_new_game_page())
	_text(Content.ui("save_mode_hint_" + _new_save_mode), 14, Color(0.75, 0.75, 0.75))
	_button(Content.ui("new_game_start"), func() -> void:
		Settings.change("save_mode", _new_save_mode)
		SaveService.start_new_game({}, {"save_mode": _new_save_mode}))
	_button(Content.ui("menu_back"), _main_page)


## Настройки (12.6a). Режим сохранений в игре меняет и партию (отметка в итогах), на титуле —
## только умолчание для новой игры.
func _settings_page() -> void:
	_clear(Content.ui("menu_settings"))
	var mode_key := String(PlayerState.save_mode if not _title_mode else Settings.value("save_mode"))
	_button(Content.ui("settings_save_mode", {"value": Content.ui("save_mode_" + mode_key)}), func() -> void:
		var next: String = Settings.model.next_option("save_mode") if _title_mode else \
			(SettingsModel.STAB_ONLY if PlayerState.save_mode == SettingsModel.ANYWHERE else SettingsModel.ANYWHERE)
		Settings.change("save_mode", next)
		if not _title_mode:
			PlayerState.change_save_mode(next)
		_settings_page())
	_text(Content.ui("save_mode_hint_" + mode_key), 13, Color(0.7, 0.7, 0.7))
	_button(Content.ui("settings_noise_ring", {"value": _on_off(Settings.value("noise_ring"))}), func() -> void:
		Settings.change("noise_ring", not bool(Settings.value("noise_ring")))
		_settings_page())
	_button(Content.ui("settings_minimap", {"value": _on_off(Settings.value("minimap"))}), func() -> void:
		Settings.change("minimap", not bool(Settings.value("minimap")))
		_settings_page())
	_button(Content.ui("settings_contrast", {"value": _on_off(Settings.value("contrast"))}), func() -> void:
		Settings.change("contrast", not bool(Settings.value("contrast")))
		_settings_page())
	_button(Content.ui("settings_log_font", {"value": int(Settings.value("log_font"))}), func() -> void:
		Settings.change("log_font", Settings.model.next_option("log_font"))
		_settings_page())
	_button(Content.ui("settings_hud_opacity", {"value": roundi(float(Settings.value("hud_opacity")) * 100.0)}), func() -> void:
		Settings.change("hud_opacity", Settings.model.next_option("hud_opacity"))
		_settings_page())
	_button(Content.ui("menu_keys"), _keys_page)
	var step := Settings.model.volume_step()
	var volume := float(Settings.value("volume"))
	_button(Content.ui("settings_volume", {"value": roundi(volume * 100.0)}), func() -> void:
		Settings.change("volume", 0.0 if volume >= 0.999 else minf(1.0, volume + step))
		_settings_page())
	_button(Content.ui("settings_fullscreen", {"value": _on_off(Settings.value("fullscreen"))}), func() -> void:
		Settings.change("fullscreen", not bool(Settings.value("fullscreen")))
		_settings_page())
	_button(Content.ui("settings_ui_scale", {"value": roundi(float(Settings.value("ui_scale")) * 100.0)}), func() -> void:
		Settings.change("ui_scale", Settings.model.next_option("ui_scale"))
		_settings_page())
	var size: Array = Settings.value("window_size")
	_button(Content.ui("settings_window", {"w": size[0], "h": size[1]}), func() -> void:
		Settings.change("window_size", Settings.model.next_option("window_size"))
		_settings_page())
	_button(Content.ui("menu_back"), _main_page)


## Клавиши (12.7, 12.8): справка и переназначение. Клик по клавише — «нажмите новую», Esc — отмена;
## конфликт (одна клавиша у двух действий) — красным; «Сброс» — умолчания.
func _keys_page() -> void:
	_bindings = KeyBindings.new(InputSetup.ACTIONS, Settings.value("keys"))
	_clear(Content.ui("keys_title"))
	_text(Content.ui("keys_hint"), 14, Color(0.7, 0.72, 0.7))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, clampf(get_viewport().get_visible_rect().size.y - 330.0, 160.0, 470.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	var clashes := _bindings.conflicts()
	for action in _bindings.actions():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := UiKit.label(15, UiKit.TEXT)
		label.text = Content.ui("key_action_" + action)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var keys: PackedStringArray = []
		var clash := false
		for code in _bindings.keys(action):
			keys.append(OS.get_keycode_string(code))
			clash = clash or clashes.has(code)
		var key := Button.new()
		key.text = Content.ui("keys_press") if _waiting_action == action else " / ".join(keys)
		key.custom_minimum_size.x = 190
		key.add_theme_font_size_override("font_size", 15)
		if clash:
			key.add_theme_color_override("font_color", UiKit.BAD)
			key.tooltip_text = Content.ui("keys_conflict")
		key.pressed.connect(func() -> void:
			_waiting_action = action
			_keys_page())
		row.add_child(key)
		list.add_child(row)
	for fixed in [["key_action_attack", "ЛКМ"], ["key_action_menu", "Esc"], ["key_action_zoom", Content.ui("keys_wheel")]]:
		var row := HBoxContainer.new()
		var label := UiKit.label(15, UiKit.TEXT_DIM)
		label.text = Content.ui(fixed[0])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var key := UiKit.label(15, UiKit.TEXT_DIM)
		key.text = fixed[1]
		key.custom_minimum_size.x = 190
		row.add_child(key)
		list.add_child(row)
	if not clashes.is_empty():
		_text(Content.ui("keys_conflicts", {"n": clashes.size()}), 14, UiKit.BAD)
	_button(Content.ui("keys_reset"), func() -> void:
		_bindings.reset()
		_save_bindings()
		_keys_page())
	_button(Content.ui("menu_back"), _main_page)


func _save_bindings() -> void:
	Settings.change("keys", _bindings.to_dict())
	InputSetup.apply_bindings(_bindings.to_dict())


func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty() or not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode != KEY_ESCAPE:
		_bindings.bind(_waiting_action, key.physical_keycode)
		_save_bindings()
	_waiting_action = ""
	_keys_page()


func _on_off(value: Variant) -> String:
	return Content.ui("settings_on" if bool(value) else "settings_off")


func _text(text: String, size: int, color: Color) -> Label:
	var label := UiKit.label(size, color)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 520
	_box.add_child(label)
	return label


func _save_page() -> void:
	_clear(Content.ui("menu_save"))
	var slots := SaveService.manual_slots()
	for i in slots.size():
		var slot := slots[i]
		var info := SaveService.slot_info(slot)
		_button(_slot_text(i + 1, info), func() -> void:
			if info.is_empty():
				_save(slot, i + 1)
			else:
				_ask(Content.ui("menu_confirm_overwrite", {"n": i + 1}), _save.bind(slot, i + 1)))
	_button(Content.ui("menu_back"), _main_page)


func _load_page() -> void:
	_clear(Content.ui("menu_load"))
	var auto := SaveService.slot_info(SaveService.AUTO_SLOT)
	var auto_button := _button(_auto_text(auto), _load.bind(SaveService.AUTO_SLOT))
	auto_button.disabled = auto.is_empty()
	var slots := SaveService.manual_slots()
	for i in slots.size():
		var info := SaveService.slot_info(slots[i])
		var button := _button(_slot_text(i + 1, info), _load.bind(slots[i]))
		button.disabled = info.is_empty() or info.has("broken")
	_button(Content.ui("menu_back"), _main_page)


func _save(slot: String, _n: int) -> void:
	SaveService.save_game(slot)
	_save_page()


func _load(slot: String) -> void:
	_close()
	SaveService.load_game(slot)


func _ask(text: String, action: Callable) -> void:
	_on_confirm = action
	_confirm.dialog_text = text
	_confirm.popup_centered()


func _slot_text(n: int, info: Dictionary) -> String:
	if info.is_empty():
		return Content.ui("menu_slot_empty", {"n": n})
	if info.has("broken"):
		return Content.ui("menu_slot_broken", {"n": n})
	return Content.ui("menu_slot", _info_params(info).merged({"n": n}))


func _auto_text(info: Dictionary) -> String:
	if info.is_empty() or info.has("broken"):
		return Content.ui("menu_slot_auto_empty")
	return Content.ui("menu_slot_auto", _info_params(info))


func _info_params(info: Dictionary) -> Dictionary:
	var ng := int(info.get("ng_plus", 0))
	var date := Time.get_datetime_string_from_unix_time(int(info["saved_at"]) + _tz_offset(), true)
	return {
		"day": int(info.get("day", 0)), "lives": int(info.get("lives", 0)), "level": int(info.get("level", 0)),
		"ng": Content.ui("menu_ng", {"n": ng}) if ng > 0 else "", "date": date.substr(0, 16),
	}


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system()["bias"]) * 60


func _clear(title: String) -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var label := UiKit.label(28, Color(0.95, 0.78, 0.3))
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(label)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", UiKit.font())
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size = Vector2(520, 40)
	button.pressed.connect(action)
	var first := _box.get_children().all(func(n: Node) -> bool: return not n is Button)
	_box.add_child(button)
	if first:
		# Страницу могли тут же перерисовать (кнопка уже не в дереве) — фокус только живой.
		(func() -> void:
			if is_instance_valid(button) and button.is_inside_tree():
				button.grab_focus()).call_deferred()
	return button
