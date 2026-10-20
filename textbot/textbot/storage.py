"""SQLite: игроки, слоты прохождений, мета. Каждое сохранение — одна транзакция."""
from __future__ import annotations

import sqlite3
import time
from pathlib import Path

from .engine import Meta, RunState

SLOTS = 3

SCHEMA = """
CREATE TABLE IF NOT EXISTS players (
    tg_id INTEGER PRIMARY KEY,
    name TEXT,
    active_slot INTEGER NOT NULL DEFAULT 1,
    created REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS slots (
    tg_id INTEGER NOT NULL,
    slot INTEGER NOT NULL,
    campaign TEXT NOT NULL,
    state TEXT NOT NULL,
    updated REAL NOT NULL,
    PRIMARY KEY (tg_id, slot)
);
CREATE TABLE IF NOT EXISTS users (
    tg_id INTEGER PRIMARY KEY,
    name TEXT,
    username TEXT,
    status TEXT NOT NULL,            -- pending | approved | denied | blocked
    requested_at REAL NOT NULL,
    notified_at REAL,                -- когда админу последний раз пришла заявка
    decided_by INTEGER,
    decided_at REAL
);
CREATE TABLE IF NOT EXISTS meta (
    tg_id INTEGER NOT NULL,
    campaign TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (tg_id, campaign)
);
"""


class Storage:
    def __init__(self, path: str | Path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path), isolation_level=None, check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript(SCHEMA)

    def close(self) -> None:
        self.db.close()

    def player(self, tg_id: int, name: str | None = None) -> int:
        """Создаёт игрока при первом визите; возвращает активный слот."""
        self.db.execute(
            "INSERT OR IGNORE INTO players (tg_id, name, created) VALUES (?, ?, ?)", (tg_id, name, time.time()))
        return self.db.execute("SELECT active_slot FROM players WHERE tg_id = ?", (tg_id,)).fetchone()[0]

    # ---------- доступ ----------

    def user(self, tg_id: int) -> dict | None:
        cur = self.db.execute("SELECT * FROM users WHERE tg_id = ?", (tg_id,))
        row = cur.fetchone()
        return dict(zip([d[0] for d in cur.description], row)) if row else None

    def users(self) -> list[dict]:
        cur = self.db.execute("SELECT * FROM users ORDER BY status, requested_at")
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]

    def add_request(self, tg_id: int, name: str, username: str | None, now: float) -> None:
        self.db.execute(
            "INSERT INTO users (tg_id, name, username, status, requested_at) VALUES (?, ?, ?, 'pending', ?) "
            "ON CONFLICT (tg_id) DO UPDATE SET name = excluded.name, username = excluded.username",
            (tg_id, name, username, now))

    def mark_notified(self, tg_id: int, now: float) -> None:
        self.db.execute("UPDATE users SET notified_at = ? WHERE tg_id = ?", (now, tg_id))

    def decide(self, tg_id: int, status: str, by: int, now: float) -> None:
        self.db.execute(
            "INSERT INTO users (tg_id, status, requested_at, decided_by, decided_at) VALUES (?, ?, ?, ?, ?) "
            "ON CONFLICT (tg_id) DO UPDATE SET status = excluded.status, decided_by = excluded.decided_by, "
            "decided_at = excluded.decided_at",
            (tg_id, status, now, by, now))

    def set_active(self, tg_id: int, slot: int) -> None:
        self.db.execute("UPDATE players SET active_slot = ? WHERE tg_id = ?", (slot, tg_id))

    def load(self, tg_id: int, slot: int) -> RunState | None:
        row = self.db.execute("SELECT state FROM slots WHERE tg_id = ? AND slot = ?", (tg_id, slot)).fetchone()
        return RunState.model_validate_json(row[0]) if row else None

    def slots(self, tg_id: int) -> dict[int, RunState]:
        rows = self.db.execute("SELECT slot, state FROM slots WHERE tg_id = ?", (tg_id,)).fetchall()
        return {slot: RunState.model_validate_json(s) for slot, s in rows}

    def meta(self, tg_id: int, campaign: str) -> Meta:
        row = self.db.execute("SELECT data FROM meta WHERE tg_id = ? AND campaign = ?", (tg_id, campaign)).fetchone()
        return Meta.model_validate_json(row[0]) if row else Meta()

    def save(self, tg_id: int, slot: int, st: RunState, meta: Meta | None = None) -> None:
        """Состояние и мета — атомарно, одной транзакцией."""
        with self._tx():
            self.db.execute(
                "INSERT INTO slots (tg_id, slot, campaign, state, updated) VALUES (?, ?, ?, ?, ?) "
                "ON CONFLICT (tg_id, slot) DO UPDATE SET campaign = excluded.campaign, state = excluded.state, "
                "updated = excluded.updated",
                (tg_id, slot, st.campaign, st.model_dump_json(), time.time()))
            if meta is not None:
                self.db.execute(
                    "INSERT INTO meta (tg_id, campaign, data) VALUES (?, ?, ?) "
                    "ON CONFLICT (tg_id, campaign) DO UPDATE SET data = excluded.data",
                    (tg_id, st.campaign, meta.model_dump_json()))

    def backup(self, folder: str | Path, keep: int = 7) -> Path:
        """Копия базы средствами SQLite (безопасно на ходу); хранит последние keep штук."""
        folder = Path(folder)
        folder.mkdir(parents=True, exist_ok=True)
        dest = folder / time.strftime("textbot-%Y%m%d-%H%M%S.db")
        target = sqlite3.connect(str(dest))
        with target:
            self.db.backup(target)
        target.close()
        for old in sorted(folder.glob("textbot-*.db"))[:-keep]:
            old.unlink()
        return dest

    def delete(self, tg_id: int, slot: int) -> None:
        self.db.execute("DELETE FROM slots WHERE tg_id = ? AND slot = ?", (tg_id, slot))

    def _tx(self):
        db = self.db

        class Tx:
            def __enter__(self):
                db.execute("BEGIN IMMEDIATE")

            def __exit__(self, exc_type, *_):
                db.execute("ROLLBACK" if exc_type else "COMMIT")
        return Tx()
