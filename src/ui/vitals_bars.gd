extends CanvasLayer
## Полоски шкал героя внизу по центру: здоровье, бодрость, споровый баланс, мана.
## Споровый баланс мигает, когда ниже порога штрафов.

const BAR_SIZE := Vector2(260, 14)
const BARS := [
	["health", "Здоровье", Color(0.78, 0.2, 0.18)],
	["stamina", "Бодрость", Color(0.85, 0.7, 0.25)],
	["spore_balance", "Споровый баланс", Color(0.45, 0.72, 0.35)],
	["mana", "Мана", Color(0.3, 0.5, 0.9)],
]

var _weapon: Label
var _bleeding: Label
var _bars: Dictionary = {}
var _labels: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New"])
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_right = -16
	box.offset_bottom = -16
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_bleeding = UiKit.label(14, Color(0.95, 0.3, 0.25))
	box.add_child(_bleeding)
	_weapon = UiKit.label(15, Color(0.95, 0.9, 0.75))
	box.add_child(_weapon)
	for spec: Array in BARS:
		var label := Label.new()
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		box.add_child(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = BAR_SIZE
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _style(Color(0, 0, 0, 0.55)))
		bar.add_theme_stylebox_override("fill", _style(spec[2]))
		box.add_child(bar)
		_bars[spec[0]] = bar
		_labels[spec[0]] = label


func _process(delta: float) -> void:
	_time += delta
	var vitals := PlayerState.vitals
	for spec: Array in BARS:
		var vital: String = spec[0]
		var bar: ProgressBar = _bars[vital]
		bar.max_value = vitals.max_value(vital)
		bar.value = vitals.value(vital)
		_labels[vital].text = "%s  %d / %d" % [spec[1], roundi(vitals.value(vital)), roundi(vitals.max_value(vital))]
	_update_weapon_line()
	var stacks := PlayerState.wounds.bleeding.size()
	_bleeding.text = Content.ui("bleeding_line", {"n": stacks}) if stacks > 0 else ""
	var spore_bar: ProgressBar = _bars["spore_balance"]
	var state := vitals.spore_state()
	var blink := state == "critical" or (state == "low" and fmod(_time, 1.0) < 0.5)
	spore_bar.modulate = Color(1.6, 0.6, 0.6) if blink else Color.WHITE
	_bars["stamina"].modulate = Color(1, 1, 1, 0.5) if not vitals.can_sprint() else Color.WHITE


func _update_weapon_line() -> void:
	var hero := get_tree().get_first_node_in_group("hero")
	if hero == null or hero.combat == null:
		return
	var s: Dictionary = hero.combat.status()
	var ammo := ""
	if s.has("magazine"):
		ammo = Content.ui("weapon_ammo", {"loaded": s["loaded"], "magazine": s["magazine"], "reserve": s["reserve"]})
	if s["reloading"]:
		ammo = Content.ui("weapon_reloading")
	elif float(s["charge"]) > 0.0:
		var filled := roundi(float(s["charge"]) * 10.0)
		ammo = Content.ui("weapon_charge", {"bar": "█".repeat(filled) + "░".repeat(10 - filled)})
	_weapon.text = Content.ui("weapon_line", {"weapon": Content.item_name(s["id"]), "ammo": ammo})


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style
