"""Экраны глазами игрока: текст сцены не повторяется после реплики и при возврате, шапка — по делу."""
from textbot import engine, render
from textbot.autoplay import Reader
from textbot.engine import Meta
from textbot.lint import lint

LONG = "Такси ловится неожиданно легко: таксист рад любому живому пассажиру и гонит по проспекту."

SCENES = [
    {"id": "taxi", "text": LONG, "system": "Вход в такси", "extra": [
        {"if": "flag.radio", "text": "Радио шипит на всех частотах."}], "choices": [
        {"label": "Радио", "if": "not flag.radio", "effects": ["set flag.radio"],
         "text": "— А ничего! Одно шипение.", "system": "Связь: нет"},
        {"label": "Урчат?", "if": "not flag.urch", "effects": ["set flag.urch"], "text": "— Видел. Ночью."},
        {"label": "Молчать", "if": "not flag.quiet", "effects": ["set flag.quiet"]},
        {"label": "Ждать", "effects": ["time += 1"], "text": "Минута."},
        {"label": "В двор", "goto": "yard"},
        {"label": "В переулок", "goto": "alley"},
    ]},
    {"id": "yard", "text": "Двор-колодец.", "choices": [{"label": "Назад", "goto": "taxi"}]},
    {"id": "alley", "text": "Переулок.", "choices": [{"label": "Финал", "goto": "end"}]},
    {"id": "end", "text": "Конец.", "ending": {"id": "end", "title": "Конец"}},
    {"id": "late", "text": "Поздно.", "choices": [{"label": "Всё равно в переулок", "goto": "alley"}]},
]
CFG = {"time": {"limit": 2, "on_limit": "late", "label": "Время {time}"}, "death": {"lives": 3}}


def pick(c, st, label, meta=None):
    idx = next(i for i, ch in enumerate(c.scenes[st.scene].choices) if ch.label == label)
    engine.choose(c, st, idx, meta or Meta())


def test_reply_does_not_repeat_scene_text(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    assert engine.view(c, st, Meta()).text == [LONG]
    pick(c, st, "Радио")
    scr = engine.view(c, st, Meta())
    # только ответ, его строка Системы и то, что стало видно из-за выбора, — без текста сцены
    assert scr.parts == [("text", "— А ничего! Одно шипение."), ("system", "Связь: нет"),
                         ("text", "Радио шипит на всех частотах.")]
    pick(c, st, "Урчат?")
    assert engine.view(c, st, Meta()).text == ["— Видел. Ночью."]  # новый extra уже показан — не повторяем
    assert [ch.label for ch in engine.view(c, st, Meta()).choices] == ["Молчать", "Ждать", "В двор", "В переулок"]


def test_full_view_after_pause(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Радио")
    assert engine.view(c, st, Meta(), full=True).text == [
        "— А ничего! Одно шипение.", LONG, "Радио шипит на всех частотах."]


def test_empty_reply_falls_back_to_scene(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Молчать")  # без итога — пустой экран не отправить
    assert engine.view(c, st, Meta()).text == [LONG]


def test_return_shows_again_or_full(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "В двор")
    pick(c, st, "Назад")
    assert st.screen_mode == "full" and engine.view(c, st, Meta()).text == [LONG]  # again не задан
    scenes = [{**SCENES[0], "again": "Вы снова в такси."}] + SCENES[1:]
    c2 = make_campaign(CFG, scenes, name="t2")
    st = engine.new_run(c2, seed=1)
    pick(c2, st, "Радио")
    pick(c2, st, "В двор")
    pick(c2, st, "Назад")
    assert engine.view(c2, st, Meta()).text == ["Вы снова в такси."]  # extra про радио уже был
    assert engine.view(c2, st, Meta(), full=True).text == [LONG, "Радио шипит на всех частотах."]


def test_system_line_follows_its_text(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    scr = engine.view(c, st, Meta())
    assert scr.parts == [("text", LONG), ("system", "Вход в такси")]  # строка входа — под текстом сцены
    html = render.html(scr)
    assert html.index("Такси ловится") < html.index("▌ Вход в такси")


def test_status_only_when_changed(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    assert engine.view(c, st, Meta()).status == "☥ жизней: 3 · Время 0"  # первый экран — с шапкой
    pick(c, st, "Радио")
    assert engine.view(c, st, Meta()).status is None                     # ничего не изменилось
    pick(c, st, "Ждать")
    assert engine.view(c, st, Meta()).status == "☥ жизней: 3 · Время 1"
    assert engine.view(c, st, Meta(), full=True).status                    # после паузы — всегда


def test_time_limit_fires_once(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    pick(c, st, "Ждать")
    pick(c, st, "Ждать")
    assert st.scene == "late"
    pick(c, st, "Всё равно в переулок")  # время уже вышло — дальше игра идёт, а не снова в «late»
    assert st.scene == "alley"


def test_legacy_save_fields():
    st = engine.RunState.model_validate({"campaign": "x", "mode": "system", "scene": "a",
                                         "shown_text": ["Итог."], "shown_system": ["Система."]})
    assert st.shown == [["system", "Система."], ["text", "Итог."]]
    assert st.shown_text == ["Итог."] and st.screen_mode == "full"


def test_lint_warns_about_repeats(make_campaign):
    scenes = [
        {"id": "hub", "text": "Площадь.", "choices": [
            {"label": "Подумать", "effects": ["time += 1"], "text": LONG},
            {"label": "Позвать", "if": "not flag.x", "effects": ["set flag.x"]},
            {"label": "Бар", "goto": "bar"}, {"label": "Конец", "goto": "end"}]},
        {"id": "bar", "text": "Бар.", "choices": [{"label": "Назад", "goto": "hub"}]},
        {"id": "end", "text": "Конец.", "ending": {"id": "end", "title": "Конец"}},
    ]
    w = lint(make_campaign({}, scenes)).warnings
    assert any("«Подумать»" in x and "тот же ответ" in x for x in w)
    assert any("«Позвать»" in x and "пустым" in x for x in w)
    assert any(x.startswith("hub: в сцену возвращаются") for x in w)
    assert not any(x.startswith("bar:") for x in w)


def test_reader_flags_repeated_paragraph(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = engine.new_run(c, seed=1)
    reader = Reader(c)
    assert reader.look(st, engine.view(c, st, Meta()), None)[0] == []
    pick(c, st, "В двор")
    reader.look(st, engine.view(c, st, Meta()), "taxi")
    pick(c, st, "Назад")
    problems, repeats = reader.look(st, engine.view(c, st, Meta()), "yard")
    assert repeats == {LONG} and "абзац повторяется" in problems[0]
