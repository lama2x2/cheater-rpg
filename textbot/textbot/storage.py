"""SQLite: доступ (заявки), игроки, сейвы по историям и слотам, мета. Каждое сохранение — одна транзакция."""
from __future__ import annotations

import sqlite3
import time
from pathlib import Path

from .engine import Meta, RunState

SLOTS = 3

SCHEMA = """
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
CREATE TABLE IF NOT EXISTS players (
    tg_id INTEGER PRIMARY KEY,
    name TEXT,
    active_slot INTEGER NOT NULL DEFAULT 1,
    created REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS saves (
    tg_id INTEGER NOT NULL,
    campaign TEXT NOT NULL,
    slot INTEGER NOT NULL,
    state TEXT NOT NULL,
    updated REAL NOT NULL,
    PRIMARY KEY (tg_id, campaign, slot)
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
        cols = {r[1] for r in self.db.execute("PRAGMA table_info(players)")}
        if "active_campaign" not in cols:  # база первой версии
            self.db.execute("ALTER TABLE players ADD COLUMN active_campaign TEXT")

    def close(self) -> None:
        self.db.close()

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

    # ---------- игрок и сейвы ----------

    def active(self, tg_id: int) -> tuple[str | None, int]:
        """Создаёт игрока при первом визите; возвращает (активная история, слот)."""
        self.db.execute("INSERT OR IGNORE INTO players (tg_id, created) VALUES (?, ?)", (tg_id, time.time()))
        row = self.db.execute("SELECT active_campaign, active_slot FROM players WHERE tg_id = ?", (tg_id,)).fetchone()
        return row[0], row[1]

    def set_active(self, tg_id: int, campaign: str | None, slot: int) -> None:
        self.active(tg_id)
        self.db.execute("UPDATE players SET active_campaign = ?, active_slot = ? WHERE tg_id = ?",
                        (campaign, slot, tg_id))

    def load(self, tg_id: int, campaign: str, slot: int) -> RunState | None:
        row = self.db.execute("SELECT state FROM saves WHERE tg_id = ? AND campaign = ? AND slot = ?",
                              (tg_id, campaign, slot)).fetchone()
        return RunState.model_validate_json(row[0]) if row else None

    def slots(self, tg_id: int, campaign: str) -> dict[int, RunState]:
        rows = self.db.execute("SELECT slot, state FROM saves WHERE tg_id = ? AND campaign = ?",
                               (tg_id, campaign)).fetchall()
        return {slot: RunState.model_validate_json(s) for slot, s in rows}

    def meta(self, tg_id: int, campaign: str) -> Meta:
        row = self.db.execute("SELECT data FROM meta WHERE tg_id = ? AND campaign = ?", (tg_id, campaign)).fetchone()
        return Meta.model_validate_json(row[0]) if row else Meta()

    def save(self, tg_id: int, slot: int, st: RunState, meta: Meta | None = None) -> None:
        """Сейв и мета — атомарно, одной транзакцией."""
        with self._tx():
            self.db.execute(
                "INSERT INTO saves (tg_id, campaign, slot, state, updated) VALUES (?, ?, ?, ?, ?) "
                "ON CONFLICT (tg_id, campaign, slot) DO UPDATE SET state = excluded.state, updated = excluded.updated",
                (tg_id, st.campaign, slot, st.model_dump_json(), time.time()))
            if meta is not None:
                self.db.execute(
                    "INSERT INTO meta (tg_id, campaign, data) VALUES (?, ?, ?) "
                    "ON CONFLICT (tg_id, campaign) DO UPDATE SET data = excluded.data",
                    (tg_id, st.campaign, meta.model_dump_json()))

    def delete(self, tg_id: int, campaign: str, slot: int) -> None:
        self.db.execute("DELETE FROM saves WHERE tg_id = ? AND campaign = ? AND slot = ?", (tg_id, campaign, slot))

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

    def _tx(self):
        db = self.db

        class Tx:
            def __enter__(self):
                db.execute("BEGIN IMMEDIATE")

            def __exit__(self, exc_type, *_):
                db.execute("ROLLBACK" if exc_type else "COMMIT")
        return Tx()
