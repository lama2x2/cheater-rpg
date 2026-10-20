class_name OnboardingRules
extends RefCounted
## Начало игры (01 «первые 2 часа», 3.5, задача 17): шаги онбординга и переходы по событиям,
## подсказки, имя на крестинах (проверка, отказ крестного и кличка по поступку), сцена куша
## варианта происхождения. Чистые правила; сцена — src/world/onboarding_director.gd.
## Данные — data/onboarding.json.

const REQUIRED_KEYS: PackedStringArray = ["modes", "prologue", "steps", "first_infected", "mentor", "christening", "jackpot_scenes"]
const START := "prologue"
const AWAKEN := "awaken"
const DONE := "done"
const STORY := "story"
const SANDBOX := "sandbox"

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func config() -> Dictionary:
	return _config


## Сюжетные версии этой сборки (11.4a): [{"id", "prologue"}], доступные.
func story_versions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for v: Dictionary in _config["modes"]["story"]["versions"]:
		if bool(v.get("available", true)):
			result.append(v)
	return result


func default_version() -> String:
	return String(_config["modes"]["story"]["default"])


## Допустимая версия: известная и доступная, иначе — по умолчанию.
func clean_version(version: String) -> String:
	for v in story_versions():
		if String(v["id"]) == version:
			return version
	return default_version()


## С какого шага начинается новая игра: пролог-воспоминание — только у версий с прологом.
func start_step(mode: String, version: String) -> String:
	if mode == SANDBOX:
		return AWAKEN
	for v in story_versions():
		if String(v["id"]) == clean_version(version):
			return START if bool(v.get("prologue", false)) else AWAKEN
	return AWAKEN


## Следующий шаг после события; событие, которое шагу не важно, ничего не меняет.
func next(step: String, event: String) -> String:
	var s: Dictionary = _config["steps"].get(step, {})
	return String(s.get("next", {}).get(event, step))


func hint(step: String) -> String:
	return String(_config["steps"].get(step, {}).get("hint", ""))


## Имя, которое просит игрок: обрезать пробелы; пустое, слишком короткое/длинное или с
## не-буквами — "" (крестный не примет).
func clean_name(raw: String) -> String:
	var name := raw.strip_edges()
	var limits: Array = _config["christening"]["name_len"]
	if name.length() < int(limits[0]) or name.length() > int(limits[1]):
		return ""
	var regex := RegEx.new()
	regex.compile("^[\\p{L}\\p{N}][\\p{L}\\p{N} \\-]*$")
	return name if regex.search(name) else ""


## Крестины: {"name", "nickname": true — имя дал крестный по поступку}. counters — статистика
## героя (deaths, kills, sacks_opened…). Имя не годится или крестный «не в духе» (refuse_chance) —
## кличка по первому выполненному условию.
func christen(requested: String, counters: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var name := clean_name(requested)
	if not name.is_empty() and rng.randf() >= float(_config["christening"]["refuse_chance"]):
		return {"name": name, "nickname": false}
	for rule: Dictionary in _config["christening"]["nicknames"]:
		var counter := String(rule["counter"])
		if counter.is_empty() or int(counters.get(counter, 0)) >= int(rule["min"]):
			var names: Array = rule["names"]
			return {"name": String(names[rng.randi_range(0, names.size() - 1)]), "nickname": true}
	return {"name": "Объект", "nickname": true}


## Сцена куша варианта: {"kind": object|first_death|system|christening, …}; нет — system сразу.
func jackpot_scene(variant: String) -> Dictionary:
	return _config["jackpot_scenes"].get(variant, {"kind": "system", "delay_s": 5.0})
