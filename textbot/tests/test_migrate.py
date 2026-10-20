"""Сейв старой версии кампании → новая версия: переименование, удаление, новые переменные."""
from textbot import engine
from textbot.engine import Meta
from textbot.lint import lint

V1 = [
    {"id": "intro", "chapter": "Пролог", "text": "Начало", "checkpoint": True,
     "choices": [{"label": "Дальше", "effects": ["set flag.met", "var.trust += 2"], "goto": "ch2"}]},
    {"id": "ch2", "chapter": "Глава 2", "text": "Глава 2", "checkpoint": True,
     "choices": [{"label": "В подвал", "effects": [{"after": {"steps": 3}, "goto": "basement"}], "goto": "hall"}]},
    {"id": "hall", "text": "Зал", "choices": [{"label": "В подвал", "goto": "basement"}]},
    {"id": "basement", "text": "Подвал", "choices": [{"label": "Наверх", "goto": "end"}]},
    {"id": "end", "text": "Конец", "ending": {"id": "end", "title": "Конец"}},
]


def v2_scenes():
    """Версия 2: hall переименован в lobby, basement удалён, появилась переменная fear."""
    return [
        V1[0],
        {**V1[1], "choices": [{"label": "В вестибюль", "goto": "lobby"}]},
        {"id": "lobby", "text": "Вестибюль (новый текст)", "choices": [
            {"label": "Наверх", "goto": "end"}, {"label": "Испугаться", "effects": ["var.fear += 1"]}]},
        V1[4],
    ]


CFG1 = {"version": 1, "vars": {"trust": {"start": 0}}}
CFG2 = {"version": 2, "vars": {"trust": {"start": 0}, "fear": {"start": 5}},
        "renamed": {"hall": "lobby"}, "removed": ["basement"]}


def play_v1(make_campaign, to: str):
    c1 = make_campaign(CFG1, V1, name="v1")
    st = engine.new_run(c1, seed=1)
    engine.choose(c1, st, 0, Meta())          # intro → ch2
    engine.choose(c1, st, 0, Meta())          # ch2 → hall (+ отложенный goto в basement)
    if to == "basement":
        engine.choose(c1, st, 0, Meta())      # hall → basement
    return st


def test_renamed_scene_keeps_progress(make_campaign):
    st = play_v1(make_campaign, "hall")
    c2 = make_campaign(CFG2, v2_scenes(), name="v2")
    meta = Meta(endings={"end": 1})
    assert engine.migrate(c2, st)
    assert st.scene == "lobby" and st.campaign_version == 2
    assert "met" in st.flags and st.vars["trust"] == 2 and st.vars["fear"] == 5  # новое — по умолчанию
    assert st.pending == [] or all(p["goto"] in (None, "lobby", "end") for p in st.pending)
    scr = engine.view(c2, st, meta)
    assert scr.text[-1] == "Вестибюль (новый текст)" and [c.label for c in scr.choices] == ["Наверх", "Испугаться"]
    assert meta.endings == {"end": 1}  # мета не тронута
    assert not engine.migrate(c2, st)  # повторно — без изменений


def test_removed_scene_goes_to_last_checkpoint(make_campaign):
    st = play_v1(make_campaign, "basement")
    assert st.last_checkpoint == "ch2"
    c2 = make_campaign(CFG2, v2_scenes(), name="v2")
    engine.migrate(c2, st)
    assert st.scene == "ch2"
    assert st.shown_text == ["Кампания обновлена — вы на начале главы «Глава 2»."]
    engine.choose(c2, st, 0, Meta())          # игра продолжается по новой версии
    assert st.scene == "lobby"


def test_lint_warns_about_lost_scene(make_campaign, tmp_path):
    c1 = make_campaign(CFG1, V1, name="v1")
    c2 = make_campaign({**CFG2, "removed": []}, v2_scenes(), name="v2")
    (tmp_path / "v2" / "scene_ids.lock").write_text("\n".join(c1.scenes), encoding="utf-8")
    warnings = lint(c2).warnings
    assert any("basement" in w and "пропала" in w for w in warnings)
    assert not any("«hall»" in w and "пропала" in w for w in warnings)  # hall есть в renamed
