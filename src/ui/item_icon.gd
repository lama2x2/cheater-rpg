class_name ItemIcon
extends Control
## Иконка предмета (12.8): простой силуэт по виду (поле icon в data/items или по категории) в
## цвете редкости. Заглушка до ассетов задачи 19 — рисуется кодом, без картинок.

var item_id := ""
var shape := "box"
var tint := Color.WHITE
var count := 0


static func make(id: String, side: float = 26.0, show_count: int = 0) -> ItemIcon:
	var icon := ItemIcon.new()
	icon.set_item(id)
	icon.count = show_count
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func set_item(id: String) -> void:
	item_id = id
	if id.is_empty():
		shape = "empty"
		tint = Color(0.4, 0.42, 0.42, 0.5)
	else:
		var table := Content.item_table()
		shape = table.icon(id)
		tint = table.rarity_color(id)
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var r := s * 0.42
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.03, 0.55))
	draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.45), false, 1.0)
	var col := tint
	var dark := tint.darkened(0.45)
	match shape:
		"empty":
			pass
		"can":
			draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.75), Vector2(r * 1.2, r * 1.5)), col)
			draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.75), Vector2(r * 1.2, r * 0.25)), dark)
		"bottle":
			draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.2), Vector2(r * 0.9, r * 1.1)), col)
			draw_rect(Rect2(c + Vector2(-r * 0.18, -r * 0.85), Vector2(r * 0.36, r * 0.7)), col)
		"cross":
			draw_rect(Rect2(c - Vector2(r * 0.25, r * 0.8), Vector2(r * 0.5, r * 1.6)), col)
			draw_rect(Rect2(c - Vector2(r * 0.8, r * 0.25), Vector2(r * 1.6, r * 0.5)), col)
		"orb":
			draw_circle(c, r * 0.55, col)
			draw_circle(c - Vector2(r * 0.18, r * 0.18), r * 0.15, Color(1, 1, 1, 0.6))
		"pearl":
			draw_circle(c, r * 0.65, Color(0.15, 0.12, 0.18))
			draw_circle(c - Vector2(r * 0.2, r * 0.2), r * 0.2, col)
		"spore":
			for i in 3:
				draw_circle(c + Vector2.from_angle(i * TAU / 3.0) * r * 0.35, r * 0.28, col)
		"star":
			var points := PackedVector2Array()
			for i in 10:
				points.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (r * 0.85 if i % 2 == 0 else r * 0.35))
			draw_colored_polygon(points, col)
		"blade":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.75, -r * 0.75),
				c + Vector2(r * 0.4, -r * 0.2), c + Vector2(-r * 0.5, r * 0.75)]), col)
			draw_line(c + Vector2(-r * 0.75, r * 0.45), c + Vector2(-r * 0.4, r * 0.85), dark, 3.0)
		"axe":
			draw_line(c + Vector2(-r * 0.6, r * 0.8), c + Vector2(r * 0.3, -r * 0.7), dark, 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.05, -r * 0.8), c + Vector2(r * 0.8, -r * 0.5),
				c + Vector2(r * 0.5, r * 0.05), c + Vector2(r * 0.15, -r * 0.3)]), col)
		"bow":
			draw_arc(c + Vector2(r * 0.3, 0), r * 0.85, PI * 0.6, PI * 1.4, 12, col, 2.5)
			draw_line(c + Vector2(r * 0.3, 0) + Vector2.from_angle(PI * 0.6) * r * 0.85,
				c + Vector2(r * 0.3, 0) + Vector2.from_angle(PI * 1.4) * r * 0.85, dark, 1.0)
		"gun":
			draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.35), Vector2(r * 1.6, r * 0.4)), col)
			draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.05), Vector2(r * 0.4, r * 0.75)), col)
		"ammo", "arrow":
			for i in 3:
				var x := c.x + (i - 1) * r * 0.45
				draw_rect(Rect2(Vector2(x - r * 0.13, c.y - r * 0.5), Vector2(r * 0.26, r * 1.1)), col)
				draw_circle(Vector2(x, c.y - r * 0.5), r * 0.13, dark)
		"ring":
			draw_arc(c, r * 0.55, 0.0, TAU, 20, col, 3.0)
			draw_circle(c + Vector2(0, -r * 0.55), r * 0.2, Color(0.6, 0.9, 1.0))
		"paper":
			draw_rect(Rect2(c - Vector2(r * 0.7, r * 0.55), Vector2(r * 1.4, r * 1.1)), col)
			draw_line(c + Vector2(-r * 0.4, -r * 0.2), c + Vector2(r * 0.4, r * 0.25), dark, 1.5)
			draw_line(c + Vector2(-r * 0.1, -r * 0.4), c + Vector2(-r * 0.2, r * 0.4), dark, 1.5)
		"brick":
			draw_rect(Rect2(c - Vector2(r * 0.8, r * 0.4), Vector2(r * 1.6, r * 0.8)), col.darkened(0.2))
		_:
			draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), col)
	if count > 1:
		var font := UiKit.font()
		var text := str(count)
		var fs := maxi(9, int(s * 0.36))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(size.x - w - 2, size.y - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.BLACK)
		draw_string(font, Vector2(size.x - w - 2, size.y - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
