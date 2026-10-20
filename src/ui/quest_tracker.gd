extends CanvasLayer
## Трекер миссий (задача 17b): справа под миникартой — текущие задания кампании и их цели
## (☐ / ☑, счётчик). Подробности — журнал J. В песочнице и без заданий — пусто.

var _box: VBoxContainer


func _ready() -> void:
	layer = 2
	add_to_group("hud_layers")
	_box = VBoxContainer.new()
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.offset_left = -300
	_box.offset_right = -16
	_box.offset_top = 300
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	PlayerState.quests_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var rules := PlayerState.quest_rules()
	if rules == null:
		return
	for id: String in PlayerState.quests["active"]:
		var title := UiKit.label(15, UiKit.ACCENT)
		title.text = "◆ " + Content.ui(String(rules.mission(id).get("title", id)))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = 284
		_box.add_child(title)
		for o in rules.objectives(PlayerState.quests, id):
			var line := UiKit.label(13, UiKit.TEXT_DIM if o["done"] else UiKit.TEXT)
			var count := " (%d/%d)" % [o["have"], o["need"]] if int(o["need"]) > 1 else ""
			line.text = ("  ☑ " if o["done"] else "  ☐ ") + Content.ui(String(o["text"])) + count
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size.x = 284
			_box.add_child(line)
