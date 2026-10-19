extends Node
## Настройки игрока: user://settings.json (не в сейве), применение (громкость, окно), изменение из
## меню. Правила и проверка значений — SettingsModel (src/core). Режим сохранений здесь — умолчание
## для новой игры; у партии свой (PlayerState.save_mode, в сейве). Спецификация: 12.6a, D-30.

signal changed(key: String)

const PATH := "user://settings.json"

var model: SettingsModel


func _ready() -> void:
	_ensure()
	apply()


## Лениво: тесты и другие сервисы могут спросить настройку до _ready.
func _ensure() -> void:
	if model != null:
		return
	model = SettingsModel.new(Content.settings_config())
	if FileAccess.file_exists(PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if saved is Dictionary:
			model.load_saved(saved)


func value(key: String) -> Variant:
	_ensure()
	return model.get_value(key)


## Изменить и сразу записать в файл. false — значение недопустимо.
func change(key: String, new_value: Variant) -> bool:
	_ensure()
	if not model.set_value(key, new_value):
		return false
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(model.to_dict(), "\t"))
	apply()
	changed.emit(key)
	return true


## Громкость — на общую шину, масштаб интерфейса — на корневое окно; размер и режим окна — только
## когда окно есть (не в headless-прогонах).
func apply() -> void:
	AudioServer.set_bus_volume_db(0, SettingsModel.volume_db(float(model.get_value("volume"))))
	# Масштаб интерфейса: весь 2D (HUD, панели, меню) крупнее, 3D-мир не меняется.
	get_tree().root.content_scale_factor = float(model.get_value("ui_scale"))
	UiKit.set_contrast(bool(model.get_value("contrast")))
	if DisplayServer.get_name() == "headless":
		return
	var fullscreen := bool(model.get_value("fullscreen"))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if not fullscreen:
		var size: Array = model.get_value("window_size")
		var target := Vector2i(int(size[0]), int(size[1]))
		if DisplayServer.window_get_size() != target:
			DisplayServer.window_set_size(target)
