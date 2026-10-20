from textbot import engine
from textbot.engine import Meta

SCENES = [
    {"id": "a", "text": "Начало", "system": "вход в A", "checkpoint": True, "choices": [
        {"label": "Взять ключ", "if": "item.key == 0", "effects": ["item.key += 1", "set flag.k"]},
        {"label": "Дверь", "if": "item.key > 0", "locked": "Нужен ключ", "goto": "b"},
        {"label": "Ждать", "effects": ["time += 1"]},
        {"label": "Прыгнуть ☠", "effects": ["die 'обрыв'"]},
        {"label": "Отложить", "effects": [{"after": {"steps": 2}, "do": ["set flag.late"], "system": "сработало"}]},
        {"label": "Развилка", "goto": [{"if": "flag.k", "goto": "b"}, {"goto": "c"}]},
    ]},
    {"id": "b", "text": "Комната {name}", "extra": [{"if": "meta.ending.good", "text": "Дежавю."}],
     "choices": [{"label": "Финал", "goto": "good"}, {"label": "Назад", "goto": "a"}]},
    {"id": "c", "text": "Тупичок", "choices": [{"label": "Назад", "goto": "a"}]},
    {"id": "good", "text": "Хорошо", "ending": {"id": "good", "title": "Хорошо"}},
    {"id": "late", "text": "Поздно", "ending": {"id": "late", "title": "Поздно"}},
    {"id": "respawn", "text": "Респ", "choices": [{"label": "В начало", "goto": "a"}]},
    {"id": "final", "text": "Всё", "ending": {"id": "final", "title": "Всё"}},
    {"id": "dead", "text": "Мёртв", "ending": {"id": "dead", "title": "Мёртв"}},
]
CFG = {
    "items": {"key": {"name": "Ключ", "keep_on_death": False}},
    "time": {"limit": 3, "on_limit": "late"},
    "death": {"lives": 2, "respawn": "respawn", "final": "final", "time_cost": 0,
              "real": "ending", "real_final": "dead"},
}


def pick(c, st, label, meta=None):
    meta = meta or Meta()
    scene = c.scenes[st.scene]
    idx = next(i for i, ch in enumerate(scene.choices) if ch.label == label)
    res = engine.choose(c, st, idx, meta)
    engine.record(meta, st, res)
    return res


def labels(c, st, meta=None):
    return [(ch.label, ch.enabled) for ch in engine.view(c, st, meta or Meta()).choices]


def test_conditions_lock_and_hide(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    assert ("Дверь", False) in labels(c, st) and ("Взять ключ", True) in labels(c, st)
    pick(c, st, "Взять ключ")
    assert st.scene == "a" and st.items["key"] == 1
    assert ("Взять ключ", True) not in labels(c, st) and ("Дверь", True) in labels(c, st)
    pick(c, st, "Развилка")
    assert st.scene == "b"


def test_conditional_goto_default(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Развилка")
    assert st.scene == "c"


def test_time_limit_forces_scene(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    for _ in range(3):
        pick(c, st, "Ждать")
    assert st.ended == "late"


def test_delayed_effect(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Отложить")
    assert "late" not in st.flags
    pick(c, st, "Взять ключ")
    assert "late" in st.flags and st.shown_system == ["сработало"]


def test_system_death_lives_and_final(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Взять ключ")
    res = pick(c, st, "Прыгнуть ☠")
    assert res.events[0][:2] == ("death", "обрыв")
    assert st.scene == "respawn" and st.lives == 1 and "key" not in st.items
    assert "обрыв" in st.shown_system[0]
    pick(c, st, "В начало")
    pick(c, st, "Прыгнуть ☠")
    assert st.ended == "final" and st.lives == 0


def test_real_death_is_ending(make_campaign):
    c = make_campaign({**CFG, "mode": "real"}, SCENES)
    st = engine.new_run(c, seed=1)
    assert st.lives == 1 and engine.view(c, st, Meta()).system == []  # Системы нет
    pick(c, st, "Прыгнуть ☠")
    assert st.ended == "dead"


def test_real_death_rewinds_to_checkpoint(make_campaign):
    cfg = {**CFG, "mode": "real", "death": {**CFG["death"], "real": "rewind", "rewind_text": "Откат."}}
    c = make_campaign(cfg, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Ждать")
    pick(c, st, "Прыгнуть ☠")
    assert st.scene == "a" and st.time == 0 and st.ended is None and st.deaths == 1
    assert st.shown_text[-1] == "Откат."


def test_roll_is_deterministic_by_seed(make_campaign):
    scenes = [{"id": "s", "text": "?", "choices": [{"label": "Бросок", "roll": {
        "chance": 50, "success": {"goto": "w"}, "fail": {"goto": "l"}}}]},
        {"id": "w", "text": "w", "ending": {"id": "w", "title": "w"}},
        {"id": "l", "text": "l", "ending": {"id": "l", "title": "l"}}]
    c = make_campaign({}, scenes)
    outcomes = set()
    for seed in range(40):
        a, b = engine.new_run(c, seed=seed), engine.new_run(c, seed=seed)
        pick(c, a, "Бросок")
        pick(c, b, "Бросок")
        assert a.ended == b.ended
        outcomes.add(a.ended)
    assert outcomes == {"w", "l"}


def test_name_text_and_meta(make_campaign):
    c = make_campaign({**CFG, "ask_name": "Имя?"}, SCENES)
    meta = Meta(endings={"good": 1})
    st = engine.new_run(c, seed=1)
    assert st.awaiting_name
    engine.set_name(c, st, "Вася", meta)
    pick(c, st, "Взять ключ", meta)
    pick(c, st, "Дверь", meta)
    scr = engine.view(c, st, meta)
    assert scr.text == ["Комната Вася", "Дежавю."]


def test_stay_does_not_reenter(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    assert st.shown_system == ["вход в A"]
    pick(c, st, "Ждать")
    assert st.shown_system == []
