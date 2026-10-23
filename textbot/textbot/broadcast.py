"""Рассылка всем игрокам (новость об обновлении): текст из файла или stdin.

    python -m textbot.broadcast news.txt            # разослать
    python -m textbot.broadcast --dry-run news.txt  # только показать, кому и что
В Docker на сервере: docker compose exec -T bot python -m textbot.broadcast < news.txt
Получатели — пущенные игроки (approved) и админы. Polling не мешает: только отправка.
"""
from __future__ import annotations

import argparse
import asyncio
import sys

from .config import Config
from .storage import Storage

PAUSE_S = 0.05      # Telegram — не больше ~30 сообщений в секунду


def recipients(db: Storage, admin_ids: set[int]) -> list[int]:
    return sorted({u["tg_id"] for u in db.users() if u["status"] == "approved"} | admin_ids)


async def send_all(send, ids: list[int], text: str) -> tuple[int, list[int]]:
    """send(tg_id, text) — корутина. Ошибка у одного (заблокировал бота) не мешает остальным."""
    sent, failed = 0, []
    for tg_id in ids:
        try:
            await send(tg_id, text)
            sent += 1
        except Exception:
            failed.append(tg_id)
        await asyncio.sleep(PAUSE_S)
    return sent, failed


async def _main(text: str, dry: bool) -> None:
    cfg = Config.from_env()
    ids = recipients(Storage(cfg.data_dir / "textbot.db"), cfg.admin_ids)
    print(f"Получателей: {len(ids)}\n---\n{text}\n---")
    if dry:
        return
    from aiogram import Bot     # без parse_mode: текст уходит как есть
    bot = Bot(cfg.token)
    try:
        sent, failed = await send_all(lambda i, t: bot.send_message(i, t), ids, text)
    finally:
        await bot.session.close()
    print(f"Отправлено: {sent}" + (f", не дошло: {failed}" if failed else ""))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("file", nargs="?", help="файл с текстом (по умолчанию stdin)")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    text = (open(a.file, encoding="utf-8").read() if a.file else sys.stdin.read()).strip()
    if not text:
        raise SystemExit("Пустой текст рассылки")
    asyncio.run(_main(text, a.dry_run))


if __name__ == "__main__":
    main()
