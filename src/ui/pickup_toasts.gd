extends CanvasLayer
## Всплывающие строки «+ Бинт ×2» у левого края экрана при подборе (12.8) — кроме лога: видно,
## что взял, не читая лог. Гаснут за пару секунд, одинаковые подряд складываются.

const LIFE_S := 2.6
const MAX_LINES := 6

var _box: VBoxContainer


func _ready() -> void:
	layer = 3
	add_to_group("hud_layers")
	_box = VBoxContainer.new()
	_box.anchor_top = 0.5
	_box.anchor_bottom = 0.5
	_box.offset_left = 16
	_box.offset_top = -40
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	EventBus.item_picked.connect(_on_picked)


func _on_picked(id: String, count: int) -> void:
	var last := _box.get_child(_box.get_child_count() - 1) as HBoxContainer if _box.get_child_count() > 0 else null
	if last and last.get_meta("item", "") == id:
		count += int(last.get_meta("count", 0))
		last.queue_free()
		_box.remove_child(last)
	var row := HBoxContainer.new()
	row.set_meta("item", id)
	row.set_meta("count", count)
	row.add_theme_constant_override("separation", 6)
	row.add_child(ItemIcon.make(id, 22.0))
	var label := UiKit.label(15, Content.item_table().rarity_color(id).lightened(0.2))
	label.text = "+ %s ×%d" % [Content.item_name(id), count]
	row.add_child(label)
	_box.add_child(row)
	while _box.get_child_count() > MAX_LINES:
		var old := _box.get_child(0)
		_box.remove_child(old)
		old.queue_free()
	var tween := row.create_tween()
	tween.tween_interval(LIFE_S - 0.8)
	tween.tween_property(row, "modulate:a", 0.0, 0.8)
	tween.tween_callback(row.queue_free)
