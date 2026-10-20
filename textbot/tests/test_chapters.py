"""Главы: снимок каждой контрольной точки, возврат к главе, копия в другой слот, миграция,
старая схема базы, активный слот у каждой истории."""
import json
import sqlite3

from textbot import engine
from textbot.engine import Meta
from textbot.model import load_campaign
from textbot.service import Game
from textbot.storage import Storage

from .conftest import CAMPAIGNS

UID = 7
SCENES = [
    {"id": "c1", "chapter": "Пролог", "checkpoint": True, "text": "Один",
     "choices": [{"label": "Дальше", "effects": ["set flag.a", "var.x += 1"], "goto": "c2"}]},
    {"id": "c2", "chapter": "Середина", "checkpoint": True, "text": "Два",
     "choices": [{"label": "Дальше", "effects": ["set flag.b", {"after": {"steps": 3}, "do": ["set flag.late"]}],
                  "goto": "mid"}]},
    {"id": "mid", "text": "Между", "choices": [{"label": "Назад", "goto": "c2"}, {"label": "Дальше", "goto": "c3"}]},
    {"id": "c3", "chapter": "Финал", "checkpoint": True, "text": "Три",
     "choices": [{"label": "Конец", "effects": ["var.x += 10"], "goto": "end"}]},
    {"id": "end", "text": "Конец", "ending": {"id": "end", "title": "Конец"}},
]
CFG = {"vars": {"x": {"start": 0}}}


def go(c, st, label):
    idx = next(i for i, ch in enumerate(c.scenes[st.scene].choices) if ch.label == label)
    engine.choose(c, st, idx, Meta())


def play_to_end(c):
    st = engine.new_run(c, seed=1)
    for label in ("Дальше", "Дальше", "Назад", "Дальше", "Дальше", "Конец"):
        go(c, st, label)
    return st


def test_every_checkpoint_recorded_once(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = play_to_end(c)
    assert [ch["scene"] for ch in st.chapters] == ["c1", "c2", "c3"]  # c2 пройдена дважды — снимок один
    assert [engine.chapter_title(c, ch, i + 1) for i, ch in enumerate(st.chapters)] == ["Пролог", "Середина", "Финал"]
    assert all("chapters" not in ch["state"] and "checkpoint" not in ch["state"] for ch in st.chapters)


def test_restore_chapter(make_campaign):
    c = make_campaign(CFG, SCENES)
    st = play_to_end(c)
    steps = st.steps
    engine.restore_chapter(c, st, 1)                   # к началу «Середины»
    assert st.scene == "c2" and st.ended is None
    assert st.flags == ["a"] and st.vars["x"] == 1     # то, что было на входе в главу
    assert [ch["scene"] for ch in st.chapters] == ["c1", "c2"]
    assert st.steps == steps + 1                       # номер шага не откатывается (старые кнопки)
    assert st.shown_text == ["Вы вернулись к началу главы «Середина»."]
    go(c, st, "Дальше")                                # отложенный эффект от новых шагов
    assert "late" not in st.flags
    go(c, st, "Дальше")
    go(c, st, "Конец")
    assert "late" in st.flags and st.ended == "end"


def test_chapters_survive_campaign_edit(make_campaign):
    c1 = make_campaign(CFG, SCENES, name="v1")
    st = play_to_end(c1)
    scenes2 = [SCENES[0], {**SCENES[1], "id": "c2new"}, {**SCENES[2], "choices": [
        {"label": "Назад", "goto": "c2new"}, {"label": "Дальше", "goto": "end"}]}, SCENES[4]]
    scenes2[0] = {**SCENES[0], "choices": [{"label": "Дальше", "goto": "c2new"}]}
    c2 = make_campaign({**CFG, "version": 2, "renamed": {"c2": "c2new"}, "removed": ["c3"],
                        "vars": {"x": {"start": 0}, "y": {"start": 4}}}, scenes2, name="v2")
    assert engine.migrate(c2, st)
    assert [ch["scene"] for ch in st.chapters] == ["c1", "c2new"]  # c3 удалена — её глава пропала
    assert all(ch["state"]["vars"]["y"] == 4 for ch in st.chapters)
    engine.restore_chapter(c2, st, 1)
    assert st.scene == "c2new" and st.vars["y"] == 4


def game_with(tmp_path, make_campaign):
    c = make_campaign(CFG, SCENES, name="ch")
    demo = load_campaign(CAMPAIGNS / "demo")
    demo.hidden = False
    return Game(Storage(tmp_path / "g.db"), {"ch": c, "demo": demo}, {UID})


def press_label(g, rep, label):
    data = next(d for row in rep.outs[-1].keyboard for t, d in row if label in t)
    return g.press(UID, data)


def test_return_here_and_copy_to_slot(tmp_path, make_campaign):
    g = game_with(tmp_path, make_campaign)
    rep = g.press(UID, "m:new:ch:1")
    for label in ("Дальше", "Дальше", "Дальше", "Конец"):
        rep = press_label(g, rep, label)
    assert g.db.load(UID, "ch", 1).ended == "end"

    rep = g.press(UID, "m:ch:ch:1")
    assert "1. Пролог" in rep.outs[0].html and "3. Финал" in rep.outs[0].html
    # копия «Середины» в свободный слот 2 — слот 1 не меняется
    rep = g.press(UID, "m:cc:ch:1:1")
    assert "m:cc!:ch:1:1:2" in str(rep.outs[0].keyboard)
    g.press(UID, "m:cc!:ch:1:1:2")
    s1, s2 = g.db.load(UID, "ch", 1), g.db.load(UID, "ch", 2)
    assert s1.ended == "end" and len(s1.chapters) == 3
    assert s2.scene == "c2" and [ch["scene"] for ch in s2.chapters] == ["c1", "c2"]
    assert g.db.campaign_slot(UID, "ch") == 2
    # копия «Пролога» в занятый слот 2 — с подтверждением перезаписи
    rep = g.press(UID, "m:cc:ch:1:0")
    assert "m:cw:ch:1:0:2" in str(rep.outs[0].keyboard)
    rep = g.press(UID, "m:cw:ch:1:0:2")
    assert "Перезаписать" in rep.outs[0].html
    g.press(UID, "m:cc!:ch:1:0:2")
    assert g.db.load(UID, "ch", 2).scene == "c1" and g.db.load(UID, "ch", 1).ended == "end"
    # «Вернуться сюда» в слоте 1 — с подтверждением
    rep = g.press(UID, "m:cg:ch:1:2")
    assert "пропадёт" in rep.outs[0].html
    g.press(UID, "m:cg!:ch:1:2")
    s1 = g.db.load(UID, "ch", 1)
    assert s1.scene == "c3" and s1.ended is None and len(s1.chapters) == 3


def test_active_slot_per_story_and_start_continues_last(tmp_path, make_campaign):
    g = game_with(tmp_path, make_campaign)
    g.press(UID, "m:new:demo:2")
    g.press(UID, "m:new:ch:3")
    assert g.db.campaign_slot(UID, "demo") == 2 and g.db.campaign_slot(UID, "ch") == 3
    assert g.db.active(UID) == ("ch", 3)
    assert "c:ch:3:" in str(g.start(UID).outs[0].keyboard)          # /start — последняя игранная
    assert "m:open:demo:2" in str(g.story(UID, "demo").outs[0].keyboard)  # «Продолжить» у истории — её слот


def test_legacy_slots_table_migrates(tmp_path):
    path = tmp_path / "old.db"
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE players (tg_id INTEGER PRIMARY KEY, name TEXT, active_slot INTEGER NOT NULL DEFAULT 1,
                              created REAL NOT NULL);
        CREATE TABLE slots (tg_id INTEGER NOT NULL, slot INTEGER NOT NULL, campaign TEXT NOT NULL,
                            state TEXT NOT NULL, updated REAL NOT NULL, PRIMARY KEY (tg_id, slot));
        CREATE TABLE meta (tg_id INTEGER NOT NULL, campaign TEXT NOT NULL, data TEXT NOT NULL,
                           PRIMARY KEY (tg_id, campaign));
    """)
    old_state = {"campaign": "demo", "mode": "system", "scene": "square", "flags": ["clue_bar"],
                 "vars": {"humanity": -1}, "steps": 9, "lives": 2}
    db.execute("INSERT INTO players VALUES (?, ?, 2, 0)", (UID, None))
    db.execute("INSERT INTO slots VALUES (?, 1, 'demo', ?, 0)", (UID, json.dumps({**old_state, "steps": 3})))
    db.execute("INSERT INTO slots VALUES (?, 2, 'demo', ?, 0)", (UID, json.dumps(old_state)))
    db.execute("INSERT INTO meta VALUES (?, 'demo', ?)", (UID, json.dumps({"runs": 2, "endings": {"late": 1}})))
    db.commit()
    db.close()

    s = Storage(path)
    assert s.active(UID) == ("demo", 2) and s.campaign_slot(UID, "demo") == 2
    st = s.load(UID, "demo", 2)
    assert st.flags == ["clue_bar"] and st.steps == 9 and st.chapters == []
    assert s.load(UID, "demo", 1).steps == 3
    assert s.meta(UID, "demo").endings == {"late": 1}
    tables = {r[0] for r in s.db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "slots_legacy" in tables and "slots" not in tables
    s.close()
    s2 = Storage(path)  # повторное открытие — без повторной миграции и без ошибок
    assert s2.load(UID, "demo", 2).steps == 9

    demo = load_campaign(CAMPAIGNS / "demo")
    g = Game(s2, {"demo": demo}, {UID})
    assert "Площадь стаба" in g.start(UID).outs[0].html  # продолжает с того же места
