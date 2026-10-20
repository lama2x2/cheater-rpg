"""Telegram-обёртка над service.Game (aiogram 3)."""
from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from html import escape
from logging.handlers import RotatingFileHandler
from pathlib import Path

from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.exceptions import TelegramBadRequest, TelegramForbiddenError, TelegramUnauthorizedError
from aiogram.filters import Command
from aiogram.types import BotCommand, BotCommandScopeChat, CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message

from .config import Config
from .lint import lint
from .model import load_campaign
from .service import Game, Keyboard, Out, Reply
from .storage import Storage

log = logging.getLogger("textbot")


def keyboard(kb: Keyboard) -> InlineKeyboardMarkup | None:
    if not kb:
        return None
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=t[:64], callback_data=d) for t, d in row] for row in kb])


def setup_logging(log_dir: Path) -> None:
    log_dir.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    file = RotatingFileHandler(log_dir / "bot.log", maxBytes=2_000_000, backupCount=3, encoding="utf-8")
    file.setFormatter(fmt)
    console = logging.StreamHandler()
    console.setFormatter(fmt)
    logging.basicConfig(level=logging.INFO, handlers=[file, console])


def build(cfg: Config) -> tuple[Bot, Dispatcher, Game]:
    campaigns = {}
    for cid in cfg.campaigns:
        c = load_campaign(cfg.campaigns_dir / cid)
        rep = lint(c)
        if rep.errors:
            raise SystemExit(f"Кампания {cid} с ошибками: {rep.errors}")
        campaigns[c.id] = c
    game = Game(Storage(cfg.data_dir / "textbot.db"), campaigns, cfg.admin_ids)
    bot = Bot(cfg.token, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    dp = Dispatcher()
    locks: dict[int, asyncio.Lock] = defaultdict(asyncio.Lock)

    async def send(msg: Message, rep: Reply) -> None:
        for out in rep.outs:
            await msg.answer(out.html, reply_markup=keyboard(out.keyboard))
        for to, out in rep.notify:
            try:
                await bot.send_message(to, out.html, reply_markup=keyboard(out.keyboard))
            except (TelegramBadRequest, TelegramForbiddenError):
                log.warning("не удалось написать %s (не запускал бота или заблокировал)", to)

    async def run(uid: int, fn, *args) -> Reply:
        async with locks[uid]:
            try:
                return fn(uid, *args)
            except Exception:  # noqa: BLE001 — игроку не показываем трассировку
                log.exception("ошибка у %s", uid)
                return Reply([Out("Что-то сломалось. Попробуйте /start — прогресс сохранён.")])

    stranger = F.from_user.func(lambda u: not game.allowed(u.id))

    @dp.message(stranger)
    async def request(msg: Message) -> None:
        u = msg.from_user
        await send(msg, await run(u.id, game.request, u.full_name, u.username))

    @dp.callback_query(stranger)
    async def stranger_cb(cb: CallbackQuery) -> None:
        await cb.answer("Заявка на рассмотрении — ждите", show_alert=True)

    admin = F.from_user.id.in_(cfg.admin_ids)

    @dp.message(Command("users"), admin)
    async def users(msg: Message) -> None:
        await send(msg, await run(msg.from_user.id, game.users_list))

    @dp.message(Command("approve", "revoke"), admin)
    async def approve_revoke(msg: Message) -> None:
        cmd, _, arg = (msg.text or "").partition(" ")
        if not arg.strip().lstrip("-").isdigit():
            await msg.answer("Нужно так: /approve 123456 или /revoke 123456 (id — в /users)")
            return
        fn = game.approve_cmd if cmd.startswith("/approve") else game.revoke
        await send(msg, await run(msg.from_user.id, fn, int(arg.strip())))

    commands = {"start": Game.start, "menu": Game.menu, "status": Game.status, "memento": Game.memento}

    for name, method in commands.items():
        async def handler(msg: Message, method=method) -> None:
            await send(msg, await run(msg.from_user.id, lambda uid: method(game, uid)))
        dp.message(Command(name))(handler)

    @dp.message(Command("about"))
    async def about(msg: Message) -> None:
        lines = ["Неофициальная фанатская игра в мире цикла «Читер» Артёма Каменистого. "
                 "Не связана с автором и издательством. Сюжет и тексты — свои. Некоммерческая.", ""]
        lines += [f"<b>{escape(c.title)}</b> — {escape(c.about)}" for c in game.campaigns.values()]
        await msg.answer("\n".join(lines))

    @dp.message(F.text)
    async def text(msg: Message) -> None:
        await send(msg, await run(msg.from_user.id, game.text, msg.text))

    @dp.callback_query(F.data)
    async def press(cb: CallbackQuery) -> None:
        rep = await run(cb.from_user.id, game.press, cb.data)
        await cb.answer(rep.alert or rep.toast, show_alert=bool(rep.alert))
        if cb.message and (rep.mark is not None or rep.outs):
            try:
                if rep.mark is not None:
                    await cb.message.edit_text(f"{cb.message.html_text}\n\n➤ <b>{escape(rep.mark)}</b>")
                else:
                    await cb.message.edit_reply_markup(reply_markup=None)
            except TelegramBadRequest:
                try:  # длинное или старое сообщение — хотя бы снять кнопки
                    await cb.message.edit_reply_markup(reply_markup=None)
                except TelegramBadRequest:
                    pass
        if cb.message:
            await send(cb.message, rep)

    async def on_startup() -> None:
        base = [
            BotCommand(command="start", description="Продолжить игру"),
            BotCommand(command="menu", description="Сохранения и новая игра"),
            BotCommand(command="status", description="Состояние героя"),
            BotCommand(command="memento", description="Концовки и смерти"),
            BotCommand(command="about", description="Об игре"),
        ]
        await bot.set_my_commands(base)
        extra = [BotCommand(command="users", description="Игроки и заявки"),
                 BotCommand(command="approve", description="Пустить: /approve id"),
                 BotCommand(command="revoke", description="Закрыть доступ: /revoke id")]
        for admin_id in cfg.admin_ids:
            try:
                await bot.set_my_commands(base + extra, scope=BotCommandScopeChat(chat_id=admin_id))
            except TelegramBadRequest:
                log.warning("админ %s ещё не писал боту — меню админа появится позже", admin_id)
        asyncio.create_task(heartbeat(cfg.data_dir / "heartbeat"))
        asyncio.create_task(daily_backup(game, cfg.data_dir / "backups"))
        log.info("бот запущен: кампании %s, админов %d", list(game.campaigns), len(cfg.admin_ids))

    dp.startup.register(on_startup)
    return bot, dp, game


async def heartbeat(path: Path) -> None:
    """Файл для healthcheck Docker: обновляется, пока цикл бота жив."""
    while True:
        path.write_text(str(int(time.time())))
        await asyncio.sleep(30)


async def daily_backup(game: Game, folder: Path) -> None:
    while True:
        try:
            log.info("бэкап базы: %s", game.db.backup(folder))
        except Exception:  # noqa: BLE001
            log.exception("бэкап не удался")
        await asyncio.sleep(24 * 3600)


def main() -> None:
    cfg = Config.from_env()
    setup_logging(cfg.data_dir / "logs")
    bot, dp, _ = build(cfg)
    try:
        asyncio.run(dp.start_polling(bot))
    except TelegramUnauthorizedError:
        log.error("Telegram не принял BOT_TOKEN — проверьте токен от @BotFather в .env")
        time.sleep(60)  # не крутить перезапуски Docker впустую
        raise SystemExit(1)
