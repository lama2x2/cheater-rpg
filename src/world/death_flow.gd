extends Node
## Смерть героя в сцене: труп с рюкзаком на месте смерти, экран «Жизнь N закончилась» с отсчётом,
## прокрутка мирового времени, возрождение на респе. При 0 жизней — экран итогов.
## Правила — DeathRules (src/core), состояние — PlayerState. Спецификация: docs/spec/04_death_lives.md.

const CorpseScript := preload("res://src/actors/corpse.gd")
const DeathScreenScript := preload("res://src/ui/death_screen.gd")
const SummaryScreenScript := preload("res://src/ui/summary_screen.gd")

var hero: Node3D
## Короткий отсчёт для отладки (аргумент --fast-respawn).
var fast_respawn := false

var _corpses: Node3D
var _death_screen: CanvasLayer
var _summary: CanvasLayer
var _remaining := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_corpses = Node3D.new()
	_corpses.name = "Corpses"
	add_child(_corpses)
	_death_screen = DeathScreenScript.new()
	add_child(_death_screen)
	_summary = SummaryScreenScript.new()
	_summary.continue_pressed.connect(_on_continue)
	add_child(_summary)
	EventBus.player_died.connect(_on_player_died)
	SaveService.register("corpses", self)
	SaveService.loaded.connect(_on_game_loaded)


func _exit_tree() -> void:
	SaveService.unregister("corpses")


func _process(delta: float) -> void:
	if _remaining < 0.0:
		return
	_remaining -= delta
	_death_screen.set_remaining(maxf(_remaining, 0.0))
	if _remaining <= 0.0:
		finish_respawn()


func _unhandled_input(event: InputEvent) -> void:
	if _remaining > 0.0 and OS.is_debug_build() and event.is_action_pressed("debug_skip_respawn"):
		_remaining = 0.0


func _on_player_died(cause: String, lives_left: int) -> void:
	_spawn_corpse(PlayerState.deaths, hero.global_position, hero.rotation.y, PlayerState.dropped_on_death)
	PlayerState.dropped_on_death = {}
	_set_hero_active(false)
	_start_waiting(cause, lives_left)


func _start_waiting(cause: String, lives_left: int) -> void:
	if lives_left <= 0:
		_remaining = -1.0
		_death_screen.close()
		_summary.open()
		return
	_death_screen.open(PlayerState.deaths, cause)
	_remaining = DeathRules.respawn_seconds(Content.death_config(), _rng, fast_respawn)
	_death_screen.set_remaining(_remaining)


func finish_respawn() -> void:
	_remaining = -1.0
	_death_screen.close()
	GameClock.advance(DeathRules.game_minutes_away(Content.death_config(), _rng))
	PlayerState.respawn()
	hero.global_position = PlayerState.respawn_position
	_set_hero_active(true)


func _on_continue(mode: String) -> void:
	if mode == "ng_plus":
		SaveService.start_new_game(PlayerState.ng_plus_carry())
		return
	PlayerState.continue_after_final()
	finish_respawn()


## Загрузка сохранения: если герой был мёртв — продолжаем ожидание, иначе закрываем экраны.
func _on_game_loaded(_slot: String) -> void:
	_summary.close()
	if PlayerState.awaiting_respawn:
		_set_hero_active(false)
		var last: Array = PlayerState.run.deaths
		var cause: String = last[-1]["cause"] if not last.is_empty() else "unknown"
		_start_waiting(cause, PlayerState.lives)
	else:
		_remaining = -1.0
		_death_screen.close()
		_set_hero_active(true)


func _set_hero_active(active: bool) -> void:
	hero.visible = active
	hero.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _spawn_corpse(life: int, at: Vector3, yaw: float, contents: Dictionary) -> Node3D:
	var corpse: Node3D = CorpseScript.new()
	corpse.life = life
	corpse.contents = contents
	corpse.position = at
	corpse.rotation.y = yaw
	_corpses.add_child(corpse)
	return corpse


func to_dict() -> Dictionary:
	var list: Array = []
	for corpse in _corpses.get_children():
		list.append(corpse.to_dict())
	return {"corpses": list}


func load_dict(data: Dictionary) -> void:
	for corpse in _corpses.get_children():
		_corpses.remove_child(corpse)
		corpse.queue_free()
	for entry: Dictionary in data["corpses"]:
		var corpse: Node3D = CorpseScript.new()
		corpse.load_dict(entry)
		_corpses.add_child(corpse)
