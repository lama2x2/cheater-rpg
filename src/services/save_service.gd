extends Node
## Сохранение и загрузка игры. Секции — объекты с to_dict()/load_dict(data).
## Сервисы-синглтоны подключены здесь; объекты сцены (герой) регистрируются сами через register().
## Спецификация: docs/spec/13_tech.md, 13.5. Ячейки slot_1…slot_N (меню Esc), auto — автосейв
## при смерти, debug — F5/F9. Новая игра и «Новая игра+» — start_new_game().

signal saved(slot: String)
signal loaded(slot: String)

const SAVES_DIR := "user://saves"
const DEBUG_SLOT := "debug"
const AUTO_SLOT := "auto"

var _sections: Dictionary = {}


func _ready() -> void:
	register("clock", GameClock)
	register("player", PlayerState)
	register("log", SystemLog)
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
func start_new_game(carry: Dictionary = {}) -> void:
	get_tree().paused = false
	GameClock.reset()
	SystemLog.clear()
	PlayerState.setup()
	if not carry.is_empty():
		PlayerState.apply_carry(carry)
	get_tree().reload_current_scene()


func save_game(slot: String) -> bool:
	var sections := {}
	for section: String in _sections:
		sections[section] = _sections[section].to_dict()
	var meta := {
		"day": GameClock.day(), "clock": GameClock.clock_text(), "lives": PlayerState.lives,
		"level": PlayerState.stats.general_level(), "ng_plus": PlayerState.ng_plus,
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
	for section: String in _sections:
		if sections.has(section):
			_sections[section].load_dict(sections[section])
		else:
			push_warning("В сохранении «%s» нет секции «%s»" % [slot, section])
	SystemLog.post("game_loaded", {"slot": slot_label(slot)})
	loaded.emit(slot)
	return true
