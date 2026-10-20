"""Бот без Telegram: сборник историй, слоты, сохранение после каждого выбора, «рестарт»."""
from textbot.model import load_campaign
from textbot.service import Game
from textbot.storage import Storage

from .conftest import CAMPAIGNS

UID = 42


def game(db_path, extra_visible=True):
    demo = load_campaign(CAMPAIGNS / "demo")
    real = load_campaign(CAMPAIGNS / "demo_real")
    if extra_visible:  # в тестах показываем демо в библиотеке
        demo.hidden = real.hidden = False
    return Game(Storage(db_path), {demo.id: demo, real.id: real}, {UID})


def buttons(rep):
    return [d for row in rep.outs[-1].keyboard for _, d in row]


def first_choice(rep):
    return next(d for d in buttons(rep) if d.startswith("c:"))


def start_demo(g, slot=1):
    g.press(UID, f"m:new:demo:{slot}")
    return g.text(UID, "Вася")


def test_library_and_story_card(tmp_path):
    g = game(tmp_path / "t.db")
    rep = g.start(UID)
    assert "Истории" in rep.outs[0].html and "m:story:demo" in buttons(rep)
    assert "с Системой" in rep.outs[0].html and "без Системы" in rep.outs[0].html
    card = g.press(UID, "m:story:demo")
    assert "Сохранения" in card.outs[0].html and "m:new:demo:1" in buttons(card)
    hidden = game(tmp_path / "h.db", extra_visible=False)
    assert "m:story:demo" not in buttons(hidden.start(UID))  # демо скрыто из библиотеки


def test_restart_continues_same_screen(tmp_path):
    db = tmp_path / "t.db"
    g = game(db)
    rep = start_demo(g)
    rep = g.press(UID, first_choice(rep))
    rep = g.press(UID, first_choice(rep))
    before = rep.outs[-1]
    st_before = g.db.load(UID, "demo", 1)
    g.db.close()

    g2 = game(db)  # «рестарт контейнера»
    after = g2.start(UID).outs[-1]
    assert after.keyboard == before.keyboard
    # после паузы сцена показывается целиком: всё, что было на экране, — на месте
    assert all(p in after.html for p in before.html.split("\n\n") if not p.startswith("<i>"))
    assert g2.db.load(UID, "demo", 1) == st_before


def test_stale_button_redraws(tmp_path):
    g = game(tmp_path / "t.db")
    rep = start_demo(g)
    old = first_choice(rep)
    g.press(UID, old)
    steps = g.db.load(UID, "demo", 1).steps
    rep = g.press(UID, old)
    assert rep.toast == "Экран обновлён" and g.db.load(UID, "demo", 1).steps == steps
    rep = g.press(UID, "мусор:1:2")
    assert rep.toast == "Экран обновлён" and rep.outs


def test_slots_per_story_reset_and_done_mark(tmp_path):
    g = game(tmp_path / "t.db")
    start_demo(g, 1)
    g.press(UID, "m:new:demo_real:1")              # своя история — свои слоты
    assert g.db.active(UID) == ("demo_real", 1)
    assert g.db.load(UID, "demo", 1) is not None and g.db.load(UID, "demo_real", 1) is not None
    rep = g.press(UID, "m:reset:demo:1")
    assert "m:reset!:demo:1" in buttons(rep)
    g.press(UID, "m:reset!:demo:1")
    assert g.db.load(UID, "demo", 1).steps == 0 and g.db.meta(UID, "demo").runs == 2
    st = g.db.load(UID, "demo", 1)                  # дойти до концовки
    st.scene, st.awaiting_name = "late", False
    g.db.save(UID, 1, st)
    g.press(UID, "m:open:demo:1")
    meta = g.db.meta(UID, "demo")
    meta.endings["late"] = 1
    g.db.save(UID, 1, st, meta)
    assert "✓ пройдено (1/" in g.menu(UID).outs[0].html


def test_locked_choice_alert(tmp_path):
    g = game(tmp_path / "t.db")
    start_demo(g)
    st = g.db.load(UID, "demo", 1)
    st.scene = "road"
    g.db.save(UID, 1, st)
    rep = g.start(UID)
    locked = next(d for d in buttons(rep) if d.startswith("l:"))
    assert g.press(UID, locked).alert == "🔒 Нужно оружие"
