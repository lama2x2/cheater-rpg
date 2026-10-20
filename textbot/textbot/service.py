"""Логика бота без Telegram: команды и кнопки → экраны. Состояние — только в Storage,
поэтому после рестарта игрок продолжает с того же экрана."""
from __future__ import annotations

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


class Game:
    def __init__(self, storage: Storage, campaigns: dict[str, Campaign]):
        self.db = storage
        self.campaigns = campaigns
        self.default = next(iter(campaigns))

    # ---------- экраны ----------

    def screen(self, uid: int, slot: int, st: engine.RunState) -> Out:
        c = self.campaigns.get(st.campaign)
        if c is None or st.scene not in c.scenes:
            return Out("Кампания обновилась, и этого места в ней больше нет. Начните заново.",
                       [[("☰ Меню", "m:menu")]])
        if st.awaiting_name:
            return Out(escape(c.ask_name or "Как вас зовут?"),
                       [[(f"Пусть будет «{c.default_name}»", f"n:{slot}")]])
        meta = self.db.meta(uid, c.id)
        scr = engine.view(c, st, meta)
        kb: Keyboard = []
        for ch in scr.choices:
            if ch.enabled:
                kb.append([(ch.label, f"c:{slot}:{st.steps}:{ch.index}")])
            else:
                kb.append([(f"🔒 {ch.label}", f"l:{slot}:{ch.index}")])
        if st.ended:
            kb = [[("🔁 Сыграть ещё раз", f"m:new:{slot}:{c.id}")], [("📜 Мементо", "m:memento"), ("☰ Меню", "m:menu")]]
        return Out(render.html(scr), kb)

    def current(self, uid: int) -> Reply:
        slot = self.db.player(uid)
        st = self.db.load(uid, slot)
        if st is None:
            if len(self.campaigns) > 1:
                return Reply([self.pick_campaign(slot)])
            return self.new_run(uid, slot, self.default)
        return Reply([self.screen(uid, slot, st)])

    def pick_campaign(self, slot: int) -> Out:
        kb = [[(c.title, f"m:new:{slot}:{cid}")] for cid, c in self.campaigns.items()]
        return Out("Во что играем?", kb)

    def new_run(self, uid: int, slot: int, cid: str) -> Reply:
        c = self.campaigns.get(cid)
        if c is None:
            return Reply([self.pick_campaign(slot)])
        meta = self.db.meta(uid, cid)
        meta.runs += 1
        st = engine.new_run(c, run=meta.runs)
        self.db.player(uid)
        self.db.set_active(uid, slot)
        self.db.save(uid, slot, st, meta)
        return Reply([self.screen(uid, slot, st)])

    # ---------- команды ----------

    def start(self, uid: int) -> Reply:
        return self.current(uid)

    def menu(self, uid: int) -> Reply:
        active = self.db.player(uid)
        slots = self.db.slots(uid)
        lines, kb = ["<b>Сохранения</b>"], []
        for n in range(1, SLOTS + 1):
            st = slots.get(n)
            mark = " ◀" if n == active else ""
            if st:
                c = self.campaigns.get(st.campaign)
                title = c.title if c else st.campaign
                where = f"концовка «{st.ended}»" if st.ended else f"шаг {st.steps}"
                lines.append(f"{n}. {escape(title)} — {where}{mark}")
                kb.append([(f"▶ {n}: {title}"[:60], f"m:open:{n}")])
            else:
                lines.append(f"{n}. пусто{mark}")
                kb.append([(f"＋ {n}: новая игра", f"m:open:{n}")])
        if active in slots:
            kb.append([(f"🗑 Начать заново в слоте {active}", f"m:reset:{active}")])
        return Reply([Out("\n".join(lines), kb)])

    def status(self, uid: int) -> Reply:
        slot = self.db.player(uid)
        st = self.db.load(uid, slot)
        if st is None or st.campaign not in self.campaigns:
            return Reply([Out("Игра ещё не начата: /start")])
        c = self.campaigns[st.campaign]
        return Reply([Out(escape(render.status(c, st, self.db.meta(uid, c.id))))])

    def memento(self, uid: int) -> Reply:
        slot = self.db.player(uid)
        st = self.db.load(uid, slot)
        cid = st.campaign if st and st.campaign in self.campaigns else self.default
        return Reply([Out(escape(render.memento(self.campaigns[cid], self.db.meta(uid, cid))))])

    def text(self, uid: int, text: str) -> Reply:
        slot = self.db.player(uid)
        st = self.db.load(uid, slot)
        if st is not None and st.awaiting_name and st.campaign in self.campaigns:
            return self._name(uid, slot, st, text)
        return self.current(uid)

    # ---------- кнопки ----------

    def press(self, uid: int, data: str) -> Reply:
        parts = data.split(":")
        kind = parts[0]
        try:
            if kind == "c":
                return self._choose(uid, int(parts[1]), int(parts[2]), int(parts[3]))
            if kind == "l":
                return self._locked(uid, int(parts[1]), int(parts[2]))
            if kind == "n":
                slot = int(parts[1])
                st = self.db.load(uid, slot)
                if st and st.awaiting_name and st.campaign in self.campaigns:
                    return self._name(uid, slot, st, "")
            if kind == "m":
                return self._menu_action(uid, parts[1:])
        except (ValueError, IndexError):
            pass
        rep = self.current(uid)
        rep.toast = "Экран обновлён"
        return rep

    def _choose(self, uid: int, slot: int, nonce: int, index: int) -> Reply:
        st = self.db.load(uid, slot)
        active = self.db.player(uid)
        if st is None or slot != active or st.steps != nonce or st.ended or st.campaign not in self.campaigns:
            rep = self.current(uid)
            rep.toast = "Экран обновлён"
            return rep
        c = self.campaigns[st.campaign]
        meta = self.db.meta(uid, c.id)
        label = c.scenes[st.scene].choices[index].label if index < len(c.scenes[st.scene].choices) else ""
        try:
            res = engine.choose(c, st, index, meta)
        except engine.GameError:
            rep = self.current(uid)
            rep.toast = "Этот выбор сейчас недоступен"
            return rep
        engine.record(meta, st, res)
        self.db.save(uid, slot, st, meta)  # сначала сохранить, потом показывать
        return Reply([self.screen(uid, slot, st)], mark=engine.fill(label, st, meta))

    def _locked(self, uid: int, slot: int, index: int) -> Reply:
        st = self.db.load(uid, slot)
        if st and st.campaign in self.campaigns:
            choices = self.campaigns[st.campaign].scenes[st.scene].choices
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
        if what == "memento":
            return self.memento(uid)
        if what == "open":
            slot = int(args[1])
            if not 1 <= slot <= SLOTS:
                return self.menu(uid)
            self.db.player(uid)
            self.db.set_active(uid, slot)
            return self.current(uid)
        if what == "new":
            slot = int(args[1])
            if not 1 <= slot <= SLOTS:
                return self.menu(uid)
            return self.new_run(uid, slot, args[2])
        if what == "reset":
            slot = int(args[1])
            return Reply([Out(f"Начать заново в слоте {slot}? Текущее прохождение пропадёт "
                              f"(открытые концовки и «Мементо» останутся).",
                              [[("Да, заново", f"m:reset!:{slot}"), ("Нет", "m:menu")]])])
        if what == "reset!":
            slot = int(args[1])
            st = self.db.load(uid, slot)
            self.db.delete(uid, slot)
            self.db.set_active(uid, slot)
            if st and st.campaign in self.campaigns:
                return self.new_run(uid, slot, st.campaign)
            return self.current(uid)
        return self.menu(uid)
