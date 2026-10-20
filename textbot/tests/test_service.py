"""Бот без Telegram: сохранение после каждого выбора и продолжение после «рестарта»."""
from textbot.model import load_campaign
from textbot.service import Game
from textbot.storage import Storage

from .conftest import CAMPAIGNS

UID = 42


def game(db_path):
    campaigns = {c.id: c for c in (load_campaign(CAMPAIGNS / "demo"),)}
    return Game(Storage(db_path), campaigns)


def first_choice(rep):
    return next(d for row in rep.outs[-1].keyboard for _, d in row if d.startswith("c:"))


def test_restart_continues_same_screen(tmp_path):
    db = tmp_path / "t.db"
    g = game(db)
    rep = g.start(UID)
    assert "зовут" in rep.outs[0].html
    rep = g.text(UID, "Вася")
    rep = g.press(UID, first_choice(rep))
    rep = g.press(UID, first_choice(rep))
    before = rep.outs[-1]
    st_before = g.db.load(UID, 1)
    g.db.close()

    g2 = game(db)  # «рестарт контейнера»
    after = g2.start(UID).outs[-1]
    assert after.html == before.html and after.keyboard == before.keyboard
    assert g2.db.load(UID, 1) == st_before


def test_stale_button_redraws(tmp_path):
    g = game(tmp_path / "t.db")
    g.start(UID)
    rep = g.text(UID, "Вася")
    old = first_choice(rep)
    g.press(UID, old)
    steps = g.db.load(UID, 1).steps
    rep = g.press(UID, old)  # та же старая кнопка ещё раз
    assert rep.toast == "Экран обновлён" and g.db.load(UID, 1).steps == steps
    rep = g.press(UID, "мусор:1:2")
    assert rep.toast == "Экран обновлён" and rep.outs


def test_slots_reset_and_meta(tmp_path):
    g = game(tmp_path / "t.db")
    g.start(UID)
    g.text(UID, "Вася")
    g.press(UID, "m:open:2")             # пустой слот 2 — новая игра
    assert g.db.player(UID) == 2 and g.db.load(UID, 2) is not None
    assert g.db.meta(UID, "demo").runs == 2
    rep = g.press(UID, "m:reset:2")
    assert "Да, заново" in str(rep.outs[0].keyboard)
    g.press(UID, "m:reset!:2")
    assert g.db.load(UID, 2).steps == 0 and g.db.meta(UID, "demo").runs == 3
    assert g.db.load(UID, 1) is not None  # слот 1 не тронут
    assert "Сохранения" in g.menu(UID).outs[0].html


def test_locked_choice_alert(tmp_path):
    g = game(tmp_path / "t.db")
    g.start(UID)
    g.text(UID, "Вася")
    st = g.db.load(UID, 1)
    st.scene = "road"
    g.db.save(UID, 1, st)
    rep = g.start(UID)
    locked = next(d for row in rep.outs[0].keyboard for _, d in row if d.startswith("l:"))
    assert g.press(UID, locked).alert == "🔒 Нужно оружие"
