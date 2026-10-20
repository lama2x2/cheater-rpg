extends Node
## Сохранение и загрузка игры. Секции — объекты с to_dict()/load_dict(data).
## Сервисы-синглтоны подключены здесь (clock, player, log, world); объекты сцены (герой)
## регистрируются сами через register(). Содержимое кластеров (вещи, твари, трупы, тайники) — внутри
## секции world (снимки WorldSim). Загрузка: сервисы сразу, затем пересборка сцены, затем секции сцены
## (finish_scene_load из main). Спецификация: docs/spec/13_tech.md, 13.5. Ячейки slot_1…slot_N
## (меню Esc), auto — автосейв при смерти и входе в стаб, debug — F5/F9. Новая игра — start_new_game().

signal saved(slot: String)
signal loaded(slot: String)

const SAVES_DIR := "user://saves"
const DEBUG_SLOT := "debug"
const AUTO_SLOT := "auto"

var _sections: Dictionary = {}
## Секции сервисов (переживают пересборку сцены) — грузятся сразу.
var _service_sections: PackedStringArray = []
## Секции сцены из загруженного сохранения, ждут пересборки: {"hero": {...}}.
var _pending: Dictionary = {}
var _pending_slot := ""


func _ready() -> void:
	register("clock", GameClock)
	register("player", PlayerState)
	register("log", SystemLog)
	register("world", WorldSim)
	register("stab", StabState)
	_service_sections = PackedStringArray(_sections.keys())
	# Отложенно: сначала сцена кладёт труп с рюкзаком, потом пишем сейв.
	EventBus.player_died.connect(func(_cause: String, _lives: int) -> void: save_game.call_deferred(AUTO_SLOT))


func register(section: String, owner: Object) -> void:
	_sections[section] = owner


func unregister(section: String) -> void:
	_sections.erase(section)


func slot_path(slot: String) -> String:
	return SAVES_DIR.path_join(slot + ".json")


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Подпись ячейки для лога: «ячейка 2», «авто», «отладка».
func slot_label(slot: String) -> String:
	if slot.begins_with("slot_"):
		return Content.ui("slot_label", {"n": slot.trim_prefix("slot_")})
	return Content.ui("slot_label_" + slot)


## Ячейки для ручных сохранений: slot_1 … slot_N (N — save_slots в rules.json).
func manual_slots() -> PackedStringArray:
	var slots: PackedStringArray = []
	for i in int(Content.rules()["save_slots"]):
		slots.append("slot_%d" % (i + 1))
	return slots


## Сводка ячейки для меню: {} — пусто, иначе {"saved_at", "day", "lives", "level", "ng_plus"}.
func slot_info(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var data := SaveFormat.read_file(slot_path(slot))
	if data.is_empty():
		return {"broken": true}
	var info: Dictionary = data.get("meta", {}).duplicate()
	info["saved_at"] = float(data["saved_at"])
	return info


## Новая игра: всё состояние с нуля, сцена пересобирается. carry — перенос «Новой игры+».
## options: {"save_mode": ...} — с экрана новой игры (D-30).
func start_new_game(carry: Dictionary = {}, options: Dictionary = {}) -> void:
	get_tree().paused = false
	GameClock.reset()
	SystemLog.clear()
	PlayerState.setup()
	if not carry.is_empty():
		PlayerState.apply_carry(carry)
	if options.has("save_mode"):
		PlayerState.save_mode = String(options["save_mode"])
	WorldSim.new_world()
	# Происхождение (16): с экрана новой игры, у «Новой игры+» — то же, что было.
	var origin_kind := String(options.get("origin", carry.get("origin", OriginRules.ORDINARY)))
	# Первая игра — с прологом и онбордингом (задача 17), куш — в своей сцене; «Новая игра+» — сразу.
	var onboarding := carry.is_empty() and not bool(options.get("skip_onboarding", false))
	PlayerState.start_origin(origin_kind, String(options.get("variant", OriginRules.RANDOM)), not onboarding)
	if onboarding:
		PlayerState.begin_onboarding()
	StabState.setup()
	_pending = {}
	get_tree().reload_current_scene()


## Ручное сохранение разрешено режимом партии здесь и сейчас (D-30). Автосейв и загрузка — всегда.
func can_manual_save() -> bool:
	return SettingsModel.can_manual_save(PlayerState.save_mode, bool(WorldSim.cluster_config().get("safe", false)))


## Самое свежее сохранение (ячейки и автосейв) — для «Продолжить». "" — сохранений нет.
func latest_slot() -> String:
	var best := ""
	var best_time := -1.0
	var slots := manual_slots()
	slots.append(AUTO_SLOT)
	for slot in slots:
		var info := slot_info(slot)
		if info.is_empty() or info.has("broken"):
			continue
		if float(info["saved_at"]) > best_time:
			best_time = float(info["saved_at"])
			best = slot
	return best


func save_game(slot: String) -> bool:
	var sections := {}
	for section: String in _sections:
		sections[section] = _sections[section].to_dict()
	var meta := {
		"day": GameClock.day(), "clock": GameClock.clock_text(), "lives": PlayerState.lives,
		"level": PlayerState.stats.general_level(), "ng_plus": PlayerState.ng_plus, "save_mode": PlayerState.save_mode,
	}
	var err := SaveFormat.write_file(slot_path(slot), SaveFormat.wrap(sections, Time.get_unix_time_from_system(), meta))
	if err != OK:
		push_error("Не удалось сохранить «%s»: %s" % [slot, error_string(err)])
		SystemLog.post("save_failed", {}, "warning")
		return false
	SystemLog.post("game_saved", {"slot": slot_label(slot)})
	saved.emit(slot)
	return true


func load_game(slot: String) -> bool:
	var data := SaveFormat.read_file(slot_path(slot))
	if data.is_empty():
		SystemLog.post("load_failed", {}, "warning")
		return false
	var sections: Dictionary = data["sections"]
	_pending = {}
	for section: String in sections:
		if _service_sections.has(section):
			_sections[section].load_dict(sections[section])
		else:
			_pending[section] = sections[section]
	for section in _service_sections:
		if not sections.has(section):
			push_warning("В сохранении «%s» нет секции «%s»" % [slot, section])
	_pending_slot = slot
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()
	return true


## Сцена пересобрана (вызывает main в конце _ready): отдать секции сцены, сообщить о загрузке.
func finish_scene_load() -> void:
	if _pending_slot.is_empty():
		return
	for section: String in _pending:
		if _sections.has(section):
			_sections[section].load_dict(_pending[section])
	var slot := _pending_slot
	_pending = {}
	_pending_slot = ""
	SystemLog.post("game_loaded", {"slot": slot_label(slot)})
	loaded.emit(slot)
