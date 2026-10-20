"""Логика бота без Telegram: команды и кнопки → экраны. Состояние — только в Storage,
поэтому после рестарта игрок продолжает с того же экрана."""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from html import escape

from . import engine, render
from .model import Campaign
from .storage import SLOTS, Storage

Keyboard = list[list[tuple[str, str]]]  # ряды кнопок (текст, callback_data)


@dataclass
class Out:
    html: str
    keyboard: Keyboard = field(default_factory=list)


@dataclass
class Reply:
    outs: list[Out] = field(default_factory=list)
    alert: str | None = None   # всплывающее окно на нажатие
    toast: str | None = None   # короткая подсказка на нажатие
    mark: str | None = None    # дописать к старому сообщению и снять с него кнопки
    notify: list[tuple[int, Out]] = field(default_factory=list)  # сообщения другим людям (админам, игроку)


REPEAT_NOTIFY_S = 24 * 3600  # повтор заявки «в ожидании» — админу не чаще раза в сутки
STATUS_RU = {"pending": "⏳ ждёт", "approved": "✅ пущен", "denied": "⛔ отказ", "blocked": "🚫 закрыт"}


class Game:
    def __init__(self, storage: Storage, campaigns: dict[str, Campaign], admins: set[int] | None = None):
        self.db = storage
        self.campaigns = campaigns
        self.admins = admins or set()

    # ---------- доступ: заявки ----------

    def allowed(self, uid: int) -> bool:
        if uid in self.admins:
            return True
        u = self.db.user(uid)
        return bool(u and u["status"] == "approved")

    def request(self, uid: int, name: str, username: str | None, now: float | None = None) -> Reply:
        """Любое действие неодобренного пользователя."""
        now = time.time() if now is None else now
        u = self.db.user(uid)
        if u and u["status"] in ("denied", "blocked"):
            return Reply([Out("Извините, доступ к этой игре не открыт.")])  # админа не тревожим
        self.db.add_request(uid, name, username, now)
        rep = Reply([Out("Заявка отправлена, ждите — хозяин бота скоро ответит.")])
        if u is None or not u["notified_at"] or now - u["notified_at"] >= REPEAT_NOTIFY_S:
            self.db.mark_notified(uid, now)
            who = escape(name or "без имени") + (f" (@{escape(username)})" if username else "")
            card = Out(f"Заявка в игру: {who}\nid: <code>{uid}</code>",
                       [[("✅ Пустить", f"a:ok:{uid}"), ("⛔ Отказать", f"a:no:{uid}")]])
            rep.notify = [(admin, card) for admin in sorted(self.admins)]
        return rep

    def decide(self, admin: int, target: int, approve: bool, now: float | None = None) -> Reply:
        if admin not in self.admins:
            return Reply(alert="Это может только хозяин бота")
        now = time.time() if now is None else now
        u = self.db.user(target)
        if approve and u and u["status"] == "approved":
            return Reply(toast="Уже пущен", mark="✅ уже пущен")
        self.db.decide(target, "approved" if approve else "denied", admin, now)
        if approve:
            welcome = Out("Добро пожаловать! Вас пустили в игру. /menu — истории и сохранения, /about — об игре.")
            return Reply(mark="✅ Пущен", notify=[(target, welcome)] + [(target, o) for o in self.current(target).outs])
        return Reply(mark="⛔ Отказано", notify=[(target, Out("Извините, доступ к этой игре не открыт."))])

    def revoke(self, admin: int, target: int, now: float | None = None) -> Reply:
        if admin not in self.admins:
            return Reply([Out("Это может только хозяин бота")])
        if target in self.admins:
            return Reply([Out("Админа закрыть нельзя — он задан в .env (ADMIN_IDS).")])
        self.db.decide(target, "blocked", admin, time.time() if now is None else now)
        return Reply([Out(f"Доступ для <code>{target}</code> закрыт.")])

    def approve_cmd(self, admin: int, target: int, now: float | None = None) -> Reply:
        rep = self.decide(admin, target, True, now)
        if rep.alert:
            return Reply([Out(rep.alert)])
        return Reply([Out(f"<code>{target}</code>: {rep.mark}")], notify=rep.notify)

    def users_list(self, admin: int) -> Reply:
        if admin not in self.admins:
            return Reply([Out("Это может только хозяин бота")])
        rows = self.db.users()
        if not rows:
            return Reply([Out("Заявок пока нет.")])
        lines = ["<b>Пользователи</b>"]
        for u in rows:
            who = escape(u["name"] or "?") + (f" @{escape(u['username'])}" if u["username"] else "")
            lines.append(f"{STATUS_RU.get(u['status'], u['status'])} · {who} · <code>{u['tg_id']}</code>")
        lines.append("\n/approve &lt;id&gt; — пустить · /revoke &lt;id&gt; — закрыть")
        return Reply([Out("\n".join(lines))])

    # ---------- загрузка с миграцией ----------

    def _load(self, uid: int, cid: str, slot: int) -> engine.RunState | None:
        """Сейв, подогнанный под текущую версию истории (новые переменные, переименованные сцены)."""
        st = self.db.load(uid, cid, slot)
        c = self.campaigns.get(cid)
        if st is not None and c is not None and engine.migrate(c, st):
            self.db.save(uid, slot, st)
        return st

    def stories(self) -> list[Campaign]:
        return sorted((c for c in self.campaigns.values() if not c.hidden), key=lambda c: (c.order, c.title))

    # ---------- экраны ----------

    def screen(self, uid: int, slot: int, st: engine.RunState) -> Out:
        c = self.campaigns.get(st.campaign)
        if c is None:
            return Out("Этой истории больше нет в сборнике.", [[("📚 Истории", "m:menu")]])
        cid = c.id
        if st.awaiting_name:
            return Out(escape(c.ask_name or "Как вас зовут?"),
                       [[(f"Пусть будет «{c.default_name}»", f"n:{cid}:{slot}")]])
        meta = self.db.meta(uid, cid)
        scr = engine.view(c, st, meta)
        kb: Keyboard = []
        for ch in scr.choices:
            if ch.enabled:
                kb.append([(ch.label, f"c:{cid}:{slot}:{st.steps}:{ch.index}")])
            else:
                kb.append([(f"🔒 {ch.label}", f"l:{cid}:{slot}:{ch.index}")])
        if st.ended:
            kb = [[("🔁 Сыграть ещё раз", f"m:new:{cid}:{slot}")],
                  [("📜 Мементо", f"m:memento:{cid}"), ("📚 Истории", "m:menu")]]
        return Out(render.html(scr), kb)

    def current(self, uid: int) -> Reply:
        cid, slot = self.db.active(uid)
        st = self._load(uid, cid, slot) if cid in self.campaigns else None
        if st is None:
            return self.menu(uid)
        return Reply([self.screen(uid, slot, st)])

    def new_run(self, uid: int, cid: str, slot: int) -> Reply:
        c = self.campaigns.get(cid)
        if c is None or not 1 <= slot <= SLOTS:
            return self.menu(uid)
        meta = self.db.meta(uid, cid)
        meta.runs += 1
        st = engine.new_run(c, run=meta.runs)
        self.db.set_active(uid, cid, slot)
        self.db.save(uid, slot, st, meta)
        return Reply([self.screen(uid, slot, st)])

    # ---------- библиотека ----------

    @staticmethod
    def mode_label(c: Campaign) -> str:
        return "с Системой" if c.mode == "system" else "без Системы, одна жизнь"

    def endings_done(self, uid: int, c: Campaign) -> tuple[int, int]:
        ids = {s.ending.id for s in c.scenes.values() if s.ending}
        meta = self.db.meta(uid, c.id)
        return len(ids & set(meta.endings)), len(ids)

    def menu(self, uid: int) -> Reply:
        cid, slot = self.db.active(uid)
        lines, kb = ["<b>📚 Истории</b>"], []
        if cid in self.campaigns and self.db.load(uid, cid, slot):
            kb.append([(f"▶ Продолжить: {self.campaigns[cid].title}"[:60], f"m:open:{cid}:{slot}")])
        for n, c in enumerate(self.stories(), 1):
            done, total = self.endings_done(uid, c)
            mark = f" · ✓ пройдено ({done}/{total} концовок)" if done else ""
            info = " · ".join(x for x in (self.mode_label(c), c.length) if x)
            lines.append(f"\n<b>{n}. {escape(c.title)}</b>{mark}\n<i>{escape(info)}</i>\n{escape(c.teaser)}")
            kb.append([(f"{'✓ ' if done else ''}{n}. {c.title}"[:60], f"m:story:{c.id}")])
        if not self.stories():
            lines.append("Пока пусто.")
        return Reply([Out("\n".join(lines), kb)])

    def story(self, uid: int, cid: str) -> Reply:
        c = self.campaigns.get(cid)
        if c is None:
            return self.menu(uid)
        done, total = self.endings_done(uid, c)
        meta = self.db.meta(uid, cid)
        info = " · ".join(x for x in (self.mode_label(c), c.length) if x)
        lines = [f"<b>{escape(c.title)}</b>", f"<i>{escape(info)}</i>", "", escape(c.teaser),
                 "", f"Концовки: {done} из {total} · прохождений: {meta.runs}", "", "<b>Сохранения</b>"]
        slots = self.db.slots(uid, cid)
        kb: Keyboard = []
        for n in range(1, SLOTS + 1):
            st = slots.get(n)
            if st:
                where = "концовка" if st.ended else f"шаг {st.steps}"
                lines.append(f"{n}. {where}")
                kb.append([(f"▶ Слот {n} · {where}", f"m:open:{cid}:{n}"), (f"🗑 {n}", f"m:reset:{cid}:{n}")])
            else:
                lines.append(f"{n}. пусто")
                kb.append([(f"＋ Слот {n} · начать", f"m:new:{cid}:{n}")])
        kb.append([("📜 Мементо", f"m:memento:{cid}"), ("📚 Истории", "m:menu")])
        return Reply([Out("\n".join(lines), kb)])

    # ---------- команды ----------

    def start(self, uid: int) -> Reply:
        return self.current(uid)

    def status(self, uid: int) -> Reply:
        cid, slot = self.db.active(uid)
        st = self._load(uid, cid, slot) if cid in self.campaigns else None
        if st is None:
            return Reply([Out("История ещё не начата: /menu")])
        c = self.campaigns[cid]
        return Reply([Out(escape(render.status(c, st, self.db.meta(uid, cid))))])

    def memento(self, uid: int, cid: str | None = None) -> Reply:
        cid = cid or self.db.active(uid)[0]
        if cid not in self.campaigns:
            return self.menu(uid)
        c = self.campaigns[cid]
        text = f"<b>{escape(c.title)}</b>\n" + escape(render.memento(c, self.db.meta(uid, cid)))
        return Reply([Out(text, [[("📚 Истории", "m:menu"), ("← История", f"m:story:{cid}")]])])

    def text(self, uid: int, text: str) -> Reply:
        cid, slot = self.db.active(uid)
        st = self._load(uid, cid, slot) if cid in self.campaigns else None
        if st is not None and st.awaiting_name:
            return self._name(uid, slot, st, text)
        return self.current(uid)

    # ---------- кнопки ----------

    def press(self, uid: int, data: str) -> Reply:
        parts = data.split(":")
        kind = parts[0]
        try:
            if kind == "a":
                return self.decide(uid, int(parts[2]), parts[1] == "ok")
            if kind == "c":
                return self._choose(uid, parts[1], int(parts[2]), int(parts[3]), int(parts[4]))
            if kind == "l":
                return self._locked(uid, parts[1], int(parts[2]), int(parts[3]))
            if kind == "n":
                st = self._load(uid, parts[1], int(parts[2]))
                if st and st.awaiting_name and (parts[1], int(parts[2])) == self.db.active(uid):
                    return self._name(uid, int(parts[2]), st, "")
            if kind == "m":
                return self._menu_action(uid, parts[1:])
        except (ValueError, IndexError):
            pass
        rep = self.current(uid)
        rep.toast = "Экран обновлён"
        return rep

    def _choose(self, uid: int, cid: str, slot: int, nonce: int, index: int) -> Reply:
        st = self._load(uid, cid, slot) if cid in self.campaigns else None
        if st is None or (cid, slot) != self.db.active(uid) or st.steps != nonce or st.ended or st.awaiting_name:
            rep = self.current(uid)
            rep.toast = "Экран обновлён"
            return rep
        c = self.campaigns[cid]
        meta = self.db.meta(uid, cid)
        choices = c.scenes[st.scene].choices
        label = choices[index].label if 0 <= index < len(choices) else ""
        try:
            res = engine.choose(c, st, index, meta)
        except engine.GameError:
            rep = self.current(uid)
            rep.toast = "Этот выбор сейчас недоступен"
            return rep
        engine.record(meta, st, res)
        self.db.save(uid, slot, st, meta)  # сначала сохранить, потом показывать
        return Reply([self.screen(uid, slot, st)], mark=engine.fill(label, st, meta))

    def _locked(self, uid: int, cid: str, slot: int, index: int) -> Reply:
        st = self._load(uid, cid, slot) if cid in self.campaigns else None
        if st:
            choices = self.campaigns[cid].scenes[st.scene].choices
            if index < len(choices) and choices[index].locked:
                return Reply(alert=f"🔒 {choices[index].locked}")
        return Reply(toast="Недоступно")

    def _name(self, uid: int, slot: int, st: engine.RunState, name: str) -> Reply:
        c = self.campaigns[st.campaign]
        meta = self.db.meta(uid, c.id)
        res = engine.set_name(c, st, name, meta)
        engine.record(meta, st, res)
        self.db.save(uid, slot, st, meta)
        return Reply([self.screen(uid, slot, st)], mark=st.name or "")

    def _menu_action(self, uid: int, args: list[str]) -> Reply:
        what = args[0]
        if what == "menu":
            return self.menu(uid)
        if what == "story":
            return self.story(uid, args[1])
        if what == "memento":
            return self.memento(uid, args[1] if len(args) > 1 else None)
        cid, slot = args[1], int(args[2])
        if cid not in self.campaigns or not 1 <= slot <= SLOTS:
            return self.menu(uid)
        if what == "open":
            if self.db.load(uid, cid, slot) is None:
                return self.new_run(uid, cid, slot)
            self.db.set_active(uid, cid, slot)
            return self.current(uid)
        if what == "new":
            return self.new_run(uid, cid, slot)
        if what == "reset":
            return Reply([Out(f"Начать «{escape(self.campaigns[cid].title)}» заново в слоте {slot}? "
                              f"Это прохождение пропадёт (открытые концовки и «Мементо» останутся).",
                              [[("Да, заново", f"m:reset!:{cid}:{slot}"), ("Нет", f"m:story:{cid}")]])])
        if what == "reset!":
            self.db.delete(uid, cid, slot)
            return self.new_run(uid, cid, slot)
        return self.menu(uid)
