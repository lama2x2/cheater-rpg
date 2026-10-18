extends Node
## Сохранение и загрузка игры. Секции — объекты с to_dict()/load_dict(data).
## Сервисы-синглтоны подключены здесь; объекты сцены (герой) регистрируются сами через register().
## Спецификация: docs/spec/13_tech.md, 13.5. Ручное сохранение в игре — только в стабах (D-30),
## F5/F9 — отладка.

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
	EventBus.player_died.connect(func(_cause: String, _lives: int) -> void: save_game(AUTO_SLOT))


func register(section: String, owner: Object) -> void:
	_sections[section] = owner


func unregister(section: String) -> void:
	_sections.erase(section)


func slot_path(slot: String) -> String:
	return SAVES_DIR.path_join(slot + ".json")


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save_game(slot: String) -> bool:
	var sections := {}
	for section: String in _sections:
		sections[section] = _sections[section].to_dict()
	var err := SaveFormat.write_file(slot_path(slot), SaveFormat.wrap(sections, Time.get_unix_time_from_system()))
	if err != OK:
		push_error("Не удалось сохранить «%s»: %s" % [slot, error_string(err)])
		SystemLog.post("save_failed", {}, "warning")
		return false
	SystemLog.post("game_saved", {"slot": slot})
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
	SystemLog.post("game_loaded", {"slot": slot})
	loaded.emit(slot)
	return true
