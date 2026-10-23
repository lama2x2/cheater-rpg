"""Рассылка об обновлении: только пущенным и админам, сбой у одного не мешает остальным."""
import asyncio

from textbot import broadcast
from textbot.storage import Storage

ADMIN, OK, PENDING, DENIED, BLOCKED_BOT = 1000, 2000, 2001, 2002, 2003


def test_recipients_are_approved_and_admins(tmp_path):
    db = Storage(tmp_path / "t.db")
    for tg_id in (OK, PENDING, DENIED, BLOCKED_BOT):
        db.add_request(tg_id, "x", None, now=1)
    for tg_id in (OK, BLOCKED_BOT):
        db.decide(tg_id, "approved", ADMIN, now=2)
    db.decide(DENIED, "denied", ADMIN, now=2)
    assert broadcast.recipients(db, {ADMIN}) == [ADMIN, OK, BLOCKED_BOT]


def test_send_all_skips_failures(monkeypatch):
    monkeypatch.setattr(broadcast, "PAUSE_S", 0)
    got = []

    async def send(tg_id, text):
        if tg_id == BLOCKED_BOT:
            raise RuntimeError("bot was blocked by the user")
        got.append((tg_id, text))

    sent, failed = asyncio.run(broadcast.send_all(send, [ADMIN, BLOCKED_BOT, OK], "Новое"))
    assert (sent, failed) == (2, [BLOCKED_BOT])
    assert got == [(ADMIN, "Новое"), (OK, "Новое")]
