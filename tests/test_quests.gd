extends "res://tests/test_case.gd"
## Движок миссий (11.4a, задача 17b): старт по событию, цели, провал и повтор, выбор и флаги,
## отложенные последствия, цепочка «Чистого листа» до финала.

const QuestRulesScript := preload("res://src/core/quest_rules.gd")
const JsonDataScript := preload("res://src/core/json_data.gd")


func _rules() -> QuestRules:
	return QuestRulesScript.new(JsonDataScript.load_dict("res://data/campaigns/blank_slate/missions.json")["missions"])


func _types(notes: Array) -> PackedStringArray:
	var result: PackedStringArray = []
	for n: Dictionary in notes:
		result.append("%s:%s" % [n["type"], n["mission"]])
	return result


func test_data_valid() -> void:
	assert_eq(_rules().errors(), PackedStringArray(), "миссии без ошибок")


func test_chain_to_final() -> void:
	var q := _rules()
	var s := QuestRules.new_state()
	assert_eq(q.on_event(s, "sack_opened", 0.0).size(), 0, "до старта события не считаются")
	assert_true(_types(q.on_event(s, "mentor_appeared", 10.0)).has("started:bs_mentor"), "наставник появился — миссия началась")
	var notes := _types(q.on_event(s, "mentor_talked", 20.0))
	assert_true(notes.has("done:bs_mentor") and notes.has("started:bs_skull"), "разговор — следующая миссия: %s" % [notes])
	q.on_event(s, "sack_opened", 30.0)
	assert_eq(q.objectives(s, "bs_skull")[0]["done"], true, "мешок — цель выполнена")
	assert_true(not q.is_done(s, "bs_skull"), "но крестин ещё не было")
	q.on_event(s, "christened", 40.0)
	assert_true(q.is_done(s, "bs_skull") and q.is_active(s, "bs_road"), "крестины — дорога в стаб")
	assert_true(_types(q.on_event(s, "stab_entered", 50.0)).has("done:bs_road"), "стаб — финал")


func test_fail_and_retry() -> void:
	var q := _rules()
	var s := QuestRules.new_state()
	for e in ["mentor_appeared", "mentor_talked", "sack_opened", "christened"]:
		q.on_event(s, e, 0.0)
	assert_true(_types(q.on_event(s, "hero_died", 5.0)).has("retry:bs_road"), "смерть в дороге — провал и повтор")
	assert_eq(int(s["fails"]["bs_road"]), 1, "провал засчитан")
	assert_true(q.is_active(s, "bs_road"), "миссия снова активна")
	var before := s.duplicate(true)
	q.on_event(s, "hero_died", 6.0)
	assert_true(q.is_done(s, "bs_skull"), "сделанные миссии смерть не трогает")
	assert_eq(before["done"], s["done"], "список сделанных тот же")


func test_choice_and_delayed_consequence() -> void:
	var q := _rules()
	var s := QuestRules.new_state()
	q.on_event(s, "mentor_appeared", 0.0)
	q.on_event(s, "mentor_talked", 0.0)
	var option := q.choose(s, "bs_skull", "share", "share")
	assert_eq(int(option["cost"]["sporan"]), 5, "поделиться — 5 споранов")
	assert_true(q.choose(s, "bs_skull", "share", "keep").is_empty(), "выбор окончательный")
	assert_eq(q.chosen(s, "bs_skull", "share"), "share", "запомнен")
	q.on_event(s, "sack_opened", 0.0)
	q.on_event(s, "christened", 60.0)
	assert_eq(q.due(s, 60.0 + 2 * 60.0).size(), 0, "через 2 часа — рано")
	var fired := q.due(s, 60.0 + 3 * 60.0 + 1.0)
	assert_eq(fired.size(), 1, "через 3 часа — благодарность наставника")
	assert_eq(String(fired[0]["id"]), "mentor_tip", "та, что по флагу")
	assert_eq(q.due(s, 60.0 + 10 * 60.0).size(), 0, "обида не сработала — флаг другой, и снята")
	assert_eq((s["pending"] as Array).size(), 0, "очередь пуста")


func test_campaigns_have_cards_and_versions() -> void:
	var onboarding := JsonDataScript.load_dict("res://data/onboarding.json")
	for v: Dictionary in onboarding["modes"]["story"]["versions"]:
		var path := "res://data/campaigns/%s/campaign.json" % v["id"]
		assert_true(FileAccess.file_exists(path), "у версии %s — карточка кампании" % v["id"])
		var card := JsonDataScript.load_dict(path)
		assert_eq(bool(card["available"]), bool(v["available"]), "%s: доступность совпадает" % v["id"])


func test_save_migration_v15() -> void:
	var old := {"save_version": 14, "saved_at": 0, "meta": {}, "sections": {"player": {"lives": 5}}}
	var data: Dictionary = preload("res://src/core/save_format.gd").migrate(old)
	assert_eq(int(data["save_version"]), 15, "доведено до 15")
	assert_eq(data["sections"]["player"]["quests"], {}, "старые партии — без миссий")
