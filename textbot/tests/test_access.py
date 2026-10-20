"""Доступ по заявкам: незнакомец → заявка → админ пускает или отказывает."""
from textbot.model import load_campaign
from textbot.service import REPEAT_NOTIFY_S, Game
from textbot.storage import Storage

from .conftest import CAMPAIGNS

ADMIN, ADMIN2, GUEST = 1000, 1001, 2000


def game(tmp_path):
    return Game(Storage(tmp_path / "t.db"), {"demo": load_campaign(CAMPAIGNS / "demo")}, {ADMIN, ADMIN2})


def test_admin_always_allowed(tmp_path):
    g = game(tmp_path)
    assert g.allowed(ADMIN) and not g.allowed(GUEST)
    assert g.revoke(ADMIN2, ADMIN).outs[0].html.startswith("Админа закрыть нельзя")
    assert g.allowed(ADMIN)


def test_request_notifies_admins_once_a_day(tmp_path):
    g = game(tmp_path)
    rep = g.request(GUEST, "Мама", "mama", now=100)
    assert "Заявка отправлена" in rep.outs[0].html
    assert sorted(to for to, _ in rep.notify) == [ADMIN, ADMIN2]
    card = rep.notify[0][1]
    assert "Мама" in card.html and "@mama" in card.html and str(GUEST) in card.html
    assert card.keyboard == [[("✅ Пустить", f"a:ok:{GUEST}"), ("⛔ Отказать", f"a:no:{GUEST}")]]
    assert g.db.user(GUEST)["status"] == "pending"

    assert g.request(GUEST, "Мама", "mama", now=100 + 3600).notify == []          # не спамим
    assert len(g.request(GUEST, "Мама", "mama", now=100 + REPEAT_NOTIFY_S).notify) == 2  # через сутки — снова


def test_approve_by_button_gives_welcome_and_game(tmp_path):
    g = game(tmp_path)
    g.request(GUEST, "Папа", None, now=1)
    assert g.press(GUEST, f"a:ok:{GUEST}").alert == "Это может только хозяин бота"  # сам себя не пустит
    rep = g.press(ADMIN, f"a:ok:{GUEST}")
    assert rep.mark == "✅ Пущен"
    assert all(to == GUEST for to, _ in rep.notify)
    assert "Добро пожаловать" in rep.notify[0][1].html and "зовут" in rep.notify[1][1].html  # меню игры
    u = g.db.user(GUEST)
    assert u["status"] == "approved" and u["decided_by"] == ADMIN and u["decided_at"]
    assert g.allowed(GUEST)
    assert g.press(ADMIN2, f"a:ok:{GUEST}").mark == "✅ уже пущен"  # второй админ нажал позже


def test_deny_is_polite_and_silent_afterwards(tmp_path):
    g = game(tmp_path)
    g.request(GUEST, "Сосед", None, now=1)
    rep = g.press(ADMIN, f"a:no:{GUEST}")
    assert rep.mark == "⛔ Отказано" and "не открыт" in rep.notify[0][1].html
    assert g.db.user(GUEST)["status"] == "denied" and not g.allowed(GUEST)
    again = g.request(GUEST, "Сосед", None, now=1 + 10 * REPEAT_NOTIFY_S)
    assert again.notify == [] and "не открыт" in again.outs[0].html


def test_admin_commands(tmp_path):
    g = game(tmp_path)
    g.request(GUEST, "Мама", "mama", now=1)
    assert "Мама" in g.users_list(ADMIN).outs[0].html and "ждёт" in g.users_list(ADMIN).outs[0].html
    assert g.users_list(GUEST).outs[0].html == "Это может только хозяин бота"
    rep = g.approve_cmd(ADMIN, GUEST)
    assert g.allowed(GUEST) and rep.notify
    g.revoke(ADMIN, GUEST)
    assert g.db.user(GUEST)["status"] == "blocked" and not g.allowed(GUEST)
    assert g.request(GUEST, "Мама", "mama").notify == []  # закрытый не спамит
    assert g.revoke(GUEST, ADMIN).outs[0].html == "Это может только хозяин бота"
    g.approve_cmd(ADMIN, GUEST)  # можно вернуть
    assert g.allowed(GUEST)
