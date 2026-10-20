extends CanvasLayer
## Лог Системы (12.2): в HUD слева внизу — последние строки (цвет по виду, шрифт — настройка);
## L — окно истории: вкладки по видам (прогресс, события, предупреждения, прочее), поиск по тексту,
## время каждого сообщения. Игра на паузу не встаёт. Правила — LogFilter, данные — data/log.json.

const MAX_SHOWN := 300

static var tab := "all"
static var search := ""

var _hud: VBoxContainer
var _panel: PanelContainer
var _tabs: HFlowContainer
var _search: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _count: Label
var _dirty := true


func _ready() -> void:
	layer = 4
	add_to_group("log_panel")
	_hud = VBoxContainer.new()
	_hud.anchor_top = 1.0
	_hud.anchor_bottom = 1.0
	_hud.offset_left = 16
	_hud.offset_bottom = -16
	_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_constant_override("separation", 1)
	add_child(_hud)

	_panel = UiKit.panel()
	_panel.visible = false
	_panel.anchor_top = 0.35
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16
	_panel.offset_bottom = -16
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)
	root.add_child(UiKit.header(Content.ui("log_title"), Content.ui("log_keys", {"key": InputSetup.key_label("log")}), close))
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	root.add_child(_tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = Content.ui("log_search")
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text = search
	_search.text_changed.connect(func(text: String) -> void:
		search = text
		_dirty = true)
	_search.focus_entered.connect(func() -> void: UiKit.typing = true)
	_search.focus_exited.connect(func() -> void: UiKit.typing = false)
	row.add_child(_search)
	_count = UiKit.label(13, UiKit.TEXT_DIM)
	row.add_child(_count)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)

	SystemLog.entry_posted.connect(func(_e: Dictionary) -> void: _dirty = true)
	SystemLog.history_replaced.connect(func() -> void: _dirty = true)
	Settings.changed.connect(func(_k: String) -> void: _dirty = true)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	_panel.offset_right = 16 + minf(980.0, view.x - 32.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("log"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _panel.visible:
		close()
	else:
		open()


func open() -> void:
	_panel.visible = true
	_hud.visible = false
	UiKit.window_opened(self)
	_dirty = true


func close() -> void:
	_panel.visible = false
	_hud.visible = true
	UiKit.typing = false
	_search.release_focus()
	UiKit.window_closed(self)


## Для стека окон: «открыто» — это окно истории, а не строки HUD.
func is_open() -> bool:
	return _panel.visible


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	_refresh_hud()
	if _panel.visible:
		_refresh_window()


func _refresh_hud() -> void:
	for child in _hud.get_children():
		_hud.remove_child(child)
		child.queue_free()
	var filter := Content.log_filter()
	var n := int(filter.config()["hud_lines"])
	var size := int(Settings.value("log_font"))
	var history := SystemLog.history
	for i in range(maxi(0, history.size() - n), history.size()):
		var entry: Dictionary = history[i]
		var label := UiKit.label(size, filter.color(String(entry["kind"])))
		label.text = "› " + String(entry["text"])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(label)


func _refresh_window() -> void:
	var filter := Content.log_filter()
	for box: Container in [_tabs, _list]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for id in filter.tab_ids():
		var b := UiKit.button(Content.ui("log_tab_" + id), func() -> void:
			tab = id
			_dirty = true, 12)
		b.disabled = id == tab
		_tabs.add_child(b)
	var shown := filter.filter(SystemLog.history, tab, search)
	_count.text = Content.ui("log_count", {"n": shown.size(), "total": SystemLog.history.size()})
	var size := int(Settings.value("log_font"))
	for i in range(maxi(0, shown.size() - MAX_SHOWN), shown.size()):
		var entry: Dictionary = shown[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var stamp := UiKit.label(size - 2, UiKit.TEXT_DIM)
		stamp.text = LogFilter.stamp(float(entry["minutes"]))
		stamp.custom_minimum_size.x = 96
		row.add_child(stamp)
		var text := UiKit.label(size, filter.color(String(entry["kind"])))
		text.text = String(entry["text"])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_list.add_child(row)
	if shown.is_empty():
		var empty := UiKit.label(size, UiKit.TEXT_DIM)
		empty.text = Content.ui("log_empty")
		_list.add_child(empty)
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
