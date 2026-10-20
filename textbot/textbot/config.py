"""Настройки из переменных окружения (.env)."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Config:
    token: str
    allowed_ids: set[int]
    campaigns: list[str]
    campaigns_dir: Path
    data_dir: Path

    @classmethod
    def from_env(cls) -> "Config":
        token = os.environ.get("BOT_TOKEN", "").strip()
        if not token:
            raise SystemExit("Нет BOT_TOKEN: впишите токен от @BotFather в .env")
        ids = {int(x) for x in os.environ.get("ALLOWED_IDS", "").replace(" ", "").split(",") if x}
        root = Path(__file__).resolve().parent.parent
        return cls(
            token=token,
            allowed_ids=ids,
            campaigns=[x.strip() for x in os.environ.get("CAMPAIGNS", "demo").split(",") if x.strip()],
            campaigns_dir=Path(os.environ.get("CAMPAIGNS_DIR", root / "campaigns")),
            data_dir=Path(os.environ.get("DATA_DIR", root / "data")),
        )
