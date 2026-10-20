"""Ручной бэкап базы: python -m textbot.backup (в Docker: docker compose exec bot python -m textbot.backup)"""
import os
from pathlib import Path

from .storage import Storage

data = Path(os.environ.get("DATA_DIR", Path(__file__).resolve().parent.parent / "data"))
print(Storage(data / "textbot.db").backup(data / "backups"))
