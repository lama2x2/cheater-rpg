class_name ItemTooltip
extends RefCounted
## Подсказка предмета (12.8): название в цвете редкости, вес, цена у торговца, действие, для
## трофеев — откат и риск, для оружия — сравнение с надетым (▲ лучше зелёным, ▼ хуже красным).
## Строится в _make_custom_tooltip строк таблицы; задержка — 0,3 с (project.godot).


static func build(id: String, count: int = 1) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var table := Content.item_table()
	var db := Content.item_db()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(ItemIcon.make(id, 30.0))
	var title := UiKit.label(16, table.rarity_color(id))
	title.text = Content.item_name(id) + (" ×%d" % count if count > 1 else "")
	head.add_child(title)
	box.add_child(head)
	_line(box, Content.ui("tip_rarity_" + table.rarity(id)) + " · " + Content.ui("tip_cat_" + db.category(id)), UiKit.TEXT_DIM)
	var unit := db.weight_g(id)
	_line(box, Content.ui("tip_weight", {"unit": _grams(unit), "total": _grams(unit * count)}) if count > 1
		else Content.ui("tip_weight_one", {"unit": _grams(unit)}), UiKit.TEXT)
	if StabState.trade and StabState.trade.buys(id):
		_line(box, Content.ui("tip_price", {"n": StabState.trade.sell_price(id), "kg": roundi(table.row(id, 1, "").get("price_kg", 0.0))}), UiKit.TEXT)
	else:
		_line(box, Content.ui("tip_not_sold"), UiKit.TEXT_DIM)
	if db.allowed_in_primary(id):
		_line(box, Content.ui("tip_primary_ok"), Color(0.6, 0.85, 0.6))
	var spec: Dictionary = db.item(id).get("consume", {})
	if not spec.is_empty():
		for effect: Dictionary in spec.get("effects", []):
			_line(box, "• " + _effect_text(effect), Color(0.85, 0.9, 1.0))
		var requires: Dictionary = spec.get("requires", {})
		for need: String in requires:
			_line(box, Content.ui("tip_requires", {"item": Content.item_name(need), "n": int(requires[need])}), UiKit.TEXT_DIM)
		if spec.has("cooldown_h"):
			var left := PlayerState.trophies.cooldown_left(id, GameClock.minutes)
			_line(box, Content.ui("tip_cooldown", {"h": int(spec["cooldown_h"])}) + ("" if left <= 0.0
				else " · " + Content.ui("tip_cooldown_left", {"time": PlayerState.cooldown_text(left)})), UiKit.BAD if left > 0.0 else UiKit.TEXT_DIM)
		for risk: Dictionary in spec.get("risks", []):
			_line(box, Content.ui("tip_risk", {"what": Content.ui("tip_risk_" + String(risk["type"])),
				"p": roundi(float(risk.get("chance", 0.0)) * 100.0), "pv": roundi(float(risk.get("chance_if_cooldown_violated", 0.0)) * 100.0)}), UiKit.BAD)
	var weapons := Content.weapon_db()
	if weapons.has_weapon(id):
		var equipped := PlayerState.weapons.equipped
		var mine := weapons.weapon(id)
		if equipped == id:
			_line(box, Content.ui("tip_equipped"), UiKit.ACCENT)
		var other := weapons.weapon(equipped) if weapons.has_weapon(equipped) and equipped != id else {}
		if not other.is_empty() and String(other.get("kind", "")) != String(mine.get("kind", "")):
			_line(box, Content.ui("tip_compare_other_kind", {"item": Content.item_name(equipped)}), UiKit.TEXT_DIM)
			other = {}  # ближнее с дальним не сравниваем — разные числа
		if not other.is_empty():
			_line(box, Content.ui("tip_compare", {"item": Content.item_name(equipped)}), UiKit.TEXT_DIM)
		var rows := table.compare(mine, other if not other.is_empty() else mine, _noise_radii())
		for c: Array in rows:
			var mark := "" if other.is_empty() or int(c[3]) == 0 else (" ▲" if int(c[3]) > 0 else " ▼")
			var color := UiKit.TEXT if mark.is_empty() else (UiKit.GOOD if int(c[3]) > 0 else UiKit.BAD)
			var versus := "" if other.is_empty() else "  (%s)" % _num(float(c[2]))
			_line(box, "%s: %s%s%s" % [Content.ui("tip_cmp_" + String(c[0])), _num(float(c[1])), versus, mark], color)
	elif db.category(id) == "ammo":
		var users: PackedStringArray = []
		for wid in weapons.ids():
			if String(weapons.weapon(wid).get("ammo", "")) == id:
				users.append(Content.item_name(wid))
		if not users.is_empty():
			_line(box, Content.ui("tip_ammo_for", {"list": ", ".join(users)}), UiKit.TEXT_DIM)
	if PlayerState.junk_marks.has(id):
		_line(box, Content.ui("tip_junk_marked"), UiKit.TEXT_DIM)
	_line(box, Content.ui("tip_controls"), Color(0.55, 0.58, 0.56), 12)
	return panel


static var _tip_style: StyleBoxFlat


static func _style() -> StyleBoxFlat:
	if _tip_style == null:
		_tip_style = StyleBoxFlat.new()
		_tip_style.bg_color = Color(0.04, 0.05, 0.06, 0.97)
		_tip_style.set_content_margin_all(10)
		_tip_style.set_corner_radius_all(4)
		_tip_style.set_border_width_all(1)
		_tip_style.border_color = Color(0.65, 0.6, 0.4, 0.8)
	return _tip_style


static func _effect_text(effect: Dictionary) -> String:
	var type := String(effect["type"])
	var params := {}
	for key: String in effect:
		var v: Variant = effect[key]
		params[key] = "%s–%s" % [_num(float(v[0])), _num(float(v[1]))] if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) else str(v)
	if effect.has("vital"):
		params["vital"] = Content.ui("vital_" + String(effect["vital"]))
	if effect.has("what"):
		params["what"] = Content.ui("tip_place_" + String(effect["what"]))
	if effect.has("pool"):
		params["pool"] = Content.ui("tip_pool_" + String(effect["pool"]))
	if effect.has("stat"):
		params["stat"] = Content.stat_name(String(effect["stat"]))
	if effect.has("mult"):
		var m: Variant = effect["mult"]
		params["mult"] = "%d–%d%%" % [roundi(float(m[0]) * 100.0), roundi(float(m[1]) * 100.0)] if m is Array else "%d%%" % roundi(float(m) * 100.0)
	return Content.ui("tip_effect_" + type, params)


static func _noise_radii() -> Dictionary:
	return Content.noise_config().get("sources", {})


static func _line(box: VBoxContainer, text: String, color: Color, size: int = 14) -> void:
	var label := UiKit.label(size, color)
	label.text = text
	box.add_child(label)


static func _grams(g: float) -> String:
	return "%s г" % _num(g) if g < 1000.0 else "%s кг" % _num(g / 1000.0)


static func _num(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")
