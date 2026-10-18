extends CanvasLayer
## Меню по Esc: пауза (единственная пауза в игре, D-05), сохранение в ячейки, загрузка (ячейки и
## автосейв), новая игра, выход. Ячейки — SaveService.manual_slots().

var _shade: ColorRect
var _box: VBoxContainer
var _confirm: ConfirmationDialog
var _on_confirm: Callable


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
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	get_tree().paused = true
	_main_page()


func _close() -> void:
	visible = false
	get_tree().paused = false


func _main_page() -> void:
	_clear(Content.ui("menu_title"))
	_button(Content.ui("menu_resume"), _close)
	_button(Content.ui("menu_save"), _save_page)
	_button(Content.ui("menu_load"), _load_page)
	_button(Content.ui("menu_new"), func() -> void:
		_ask(Content.ui("menu_confirm_new"), func() -> void: SaveService.start_new_game()))
	_button(Content.ui("menu_quit"), func() -> void: get_tree().quit())


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
	_box.add_child(button)
	if _box.get_child_count() == 2:
		button.grab_focus.call_deferred()
	return button
