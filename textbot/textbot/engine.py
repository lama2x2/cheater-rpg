"""Движок книги-игры: чистые функции над состоянием прохождения, без Telegram."""
from __future__ import annotations

import random
import re
from dataclasses import dataclass, field
from typing import Any

from pydantic import BaseModel, model_validator

from . import expr
from .model import Campaign, Choice, Goto, compile_effects, parse_expr

MAX_CHAIN = 20  # защита от бесконечных переходов внутри одного шага
REWIND = "\0rewind"  # цель «откат к контрольной точке»


class Meta(BaseModel):
    """Между прохождениями: открытые концовки, «Мементо»."""
    runs: int = 0
    endings: dict[str, int] = {}
    deaths: list[dict] = []  # {run, cause, scene}


class RunState(BaseModel):
    campaign: str
    mode: str
    scene: str
    run: int = 1
    seed: int = 0
    name: str | None = None
    awaiting_name: bool = False
    flags: list[str] = []
    vars: dict[str, int] = {}
    items: dict[str, int] = {}
    time: int = 0
    steps: int = 0
    lives: int = 1
    deaths: int = 0
    pending: list[dict] = []
    checkpoint: dict | None = None       # снимок последней контрольной точки (откат в режиме real)
    last_checkpoint: str | None = None   # id последней пройденной сцены с checkpoint: true
    chapters: list[dict] = []            # главы: {scene, title, state} — снимок при первом входе в каждую контрольную точку
    campaign_version: int = 1
    ended: str | None = None
    shown: list[list[str]] = []   # итог прошлого хода по порядку: [вид, строка]; вид — text | system | entry
    screen_mode: str = "full"     # как показать сцену: full — целиком; stay — выбор оставил в ней (только
                                  # итог и новые extra); again — повторный вход (короткий again + новые extra)
    seen: dict[str, list[int]] = {}   # сцены, чей текст уже показан, → номера показанных extra
    seen_extra: list[int] = []        # extra текущей сцены, показанные до этого экрана
    shown_status: str | None = None   # шапка на прошлом экране: повторяем, только когда изменилась
    came_from: str | None = None      # сцена, из которой пришли в текущую (from в условиях)

    @model_validator(mode="before")
    @classmethod
    def _legacy_shown(cls, data: Any) -> Any:
        """Сейвы старого формата: итог хода хранился двумя списками (Система — над текстом)."""
        if isinstance(data, dict) and ("shown_text" in data or "shown_system" in data):
            data = dict(data)
            old = [["system", x] for x in data.pop("shown_system", None) or []]
            old += [["text", x] for x in data.pop("shown_text", None) or []]
            data.setdefault("shown", old)
        return data

    @property
    def shown_text(self) -> list[str]:
        return [t for k, t in self.shown if k == "text"]

    @property
    def shown_system(self) -> list[str]:
        return [t for k, t in self.shown if k != "text"]


@dataclass
class ChoiceView:
    index: int
    label: str
    enabled: bool
    reason: str | None = None


@dataclass
class Screen:
    parts: list[tuple[str, str]]   # по порядку: ("text", абзац) | ("system", строка Системы) | ("title", концовка)
    status: str | None
    choices: list[ChoiceView]
    ending: str | None = None
    ending_title: str | None = None

    @property
    def text(self) -> list[str]:
        return [t for k, t in self.parts if k == "text"]

    @property
    def system(self) -> list[str]:
        return [t for k, t in self.parts if k == "system"]


@dataclass
class Result:
    events: list[tuple] = field(default_factory=list)  # ("ending", id) | ("death", cause, scene)


class GameError(Exception):
    pass


# ---------- начало и чтение ----------

def new_run(c: Campaign, seed: int | None = None, run: int = 1, mode: str | None = None,
            meta: Meta | None = None) -> RunState:
    mode = mode or c.mode
    st = RunState(
        campaign=c.id, mode=mode, scene=c.start, run=run,
        seed=seed if seed is not None else random.randrange(1 << 30),
        vars={k: v.start for k, v in c.vars.items()},
        lives=c.death.lives if mode == "system" else 1,
        awaiting_name=bool(c.ask_name),
        campaign_version=c.version,
    )
    if not st.awaiting_name:
        _enter(c, st, c.start, Result(), meta or Meta())
        _settle(c, st, meta or Meta(), "enter")
    return st


def set_name(c: Campaign, st: RunState, name: str, meta: Meta) -> Result:
    st.name = name.strip()[:40] or c.default_name
    st.awaiting_name = False
    res = Result()
    _enter(c, st, st.scene, res, meta)
    _settle(c, st, meta, "enter")
    return res


def getter(st: RunState, meta: Meta):
    flags = set(st.flags)

    def get(name: str) -> Any:
        root, _, rest = name.partition(".")
        if root == "flag":
            return rest in flags
        if root == "var":
            return st.vars.get(rest, 0)
        if root == "item":
            return st.items.get(rest, 0)
        if root == "meta":
            if rest == "runs":
                return meta.runs
            if rest.startswith("ending."):
                return meta.endings.get(rest[7:], 0) > 0
            raise GameError(f"неизвестное имя {name}")
        if root == "mode":
            return st.mode
        if root == "from":
            return st.came_from or ""
        return getattr(st, root)
    return get


def check(src: str | int | None, st: RunState, meta: Meta) -> bool:
    return True if src is None else bool(expr.evaluate(parse_expr(src), getter(st, meta)))


def fill(text: str, st: RunState, meta: Meta, extra: dict | None = None) -> str:
    """Подстановки {name}, {var.x}… и склейка строк: одиночный перенос — пробел, пустая строка — абзац."""
    text = re.sub(r"[ \t]*(?<!\n)\n(?!\n)[ \t]*", " ", text.strip())
    get = getter(st, meta)

    def sub(m: re.Match) -> str:
        key = m.group(1)
        if extra and key in extra:
            return str(extra[key])
        if key == "name":
            return st.name or ""
        try:
            expr.check_name(key)
            return str(get(key))
        except (expr.ExprError, GameError, AttributeError):
            return m.group(0)
    return re.sub(r"\{([a-z_][a-z0-9_.]*)\}", sub, text)


def view(c: Campaign, st: RunState, meta: Meta, full: bool = False) -> Screen:
    """Экран после хода. full — показать сцену целиком (повторный показ после паузы, /start)."""
    scene = c.scenes[st.scene]
    extras = [(i, v.text) for i, v in enumerate(scene.extra) if check(v.if_, st, meta)]

    intro = next(([v.text] for v in scene.intro if check(v.if_, st, meta)), [])

    def body(mode: str) -> list[str]:
        if mode == "full":
            return intro + [scene.text] + [t for _, t in extras]
        fresh = [t for i, t in extras if i not in st.seen_extra]
        return (intro + [scene.again] if mode == "again" and scene.again else []) + fresh

    system = st.mode == "system"
    before = [(k, t) for k, t in st.shown if k == "text" or (system and k == "system")]
    after = [("system", t) for k, t in st.shown if system and k == "entry"]
    mode = "full" if full else st.screen_mode
    text = body(mode)
    if not before and not text and not after:  # выбор без итога — хоть что-то показать
        text = body("again" if scene.again else "full")
    title = [("title", scene.ending.title)] if scene.ending else []
    body_parts = [("text", fill(t.strip(), st, meta)) for t in text]
    if mode == "stay":
        # остались в сцене: открывшиеся абзацы — часть события, строки Системы о нём — после
        cut = len(before)
        while cut and before[cut - 1][0] == "system":
            cut -= 1
        parts = before[:cut] + body_parts + before[cut:] + after
    else:
        parts = before + title + body_parts + after
    choices = []
    if not st.ended:
        for i, ch in enumerate(scene.choices):
            ok = check(ch.if_, st, meta)
            if ok or ch.locked:
                choices.append(ChoiceView(i, fill(ch.label, st, meta), ok, None if ok else ch.locked))
    status = status_line(c, st, meta)
    if not full and status == st.shown_status:
        status = None  # не изменилась — не повторяем на каждом экране
    return Screen(parts=parts, status=status, choices=choices,
                  ending=st.ended, ending_title=scene.ending.title if scene.ending else None)


def status_line(c: Campaign, st: RunState, meta: Meta) -> str | None:
    parts = []
    if st.mode == "system" and c.death.lives:
        parts.append(f"☥ жизней: {st.lives}")
    if c.time:
        parts.append(fill(c.time.label, st, meta, {"limit": c.time.limit or "∞"}))
    return " · ".join(parts) or None


# ---------- ход ----------

def choose(c: Campaign, st: RunState, index: int, meta: Meta) -> Result:
    if st.ended or st.awaiting_name:
        raise GameError("сейчас выбирать нечего")
    scene = c.scenes[st.scene]
    if not 0 <= index < len(scene.choices):
        raise GameError("нет такого выбора")
    ch: Choice = scene.choices[index]
    if not check(ch.if_, st, meta):
        raise GameError("выбор недоступен")

    res = Result()
    st.shown_status = status_line(c, st, meta)
    st.shown = []
    prev, time_before = st.scene, st.time
    ctx = _Ctx()
    _say(st, meta, ctx, ch.text, ch.system)
    _apply(c, st, meta, compile_effects(ch.effects, "choice"), ctx)
    target = _goto(ch.goto, st, meta)
    if ch.roll:
        chance = max(0, min(100, int(expr.evaluate(parse_expr(ch.roll.chance), getter(st, meta)))))
        rng = random.Random(f"{st.seed}:{st.run}:{st.steps}")
        branch = ch.roll.success if rng.randrange(100) < chance else ch.roll.fail
        _say(st, meta, ctx, branch.text, branch.system)
        _apply(c, st, meta, compile_effects(branch.effects, "roll"), ctx)
        target = _goto(branch.goto, st, meta) or target
    st.steps += 1

    if ctx.death is not None:
        target = _die(c, st, meta, ctx.death, res)
    else:
        target = _due(c, st, meta, ctx) or target
        if ctx.death is not None:
            target = _die(c, st, meta, ctx.death, res)
    if _time_ran_out(c, st, time_before) and target != REWIND:
        if not (target and target in c.scenes and c.scenes[target].ending):
            target = c.time.on_limit
    if target:  # без перехода — остаёмся в сцене, вход не повторяем
        if target not in (REWIND, prev):
            st.came_from = prev
        _enter(c, st, target, res, meta, ctx)
        on_limit = c.time.on_limit if c.time else None
        if target not in (REWIND, on_limit) and not st.ended and _time_ran_out(c, st, time_before):
            target = on_limit  # время кончилось уже при входе в сцену (её on_enter)
            _enter(c, st, target, res, meta, ctx)
    died = any(e[0] == "death" for e in res.events)
    if target == REWIND:
        _settle(c, st, meta, "full")
    elif target is None or (target == prev and not died):
        _settle(c, st, meta, "stay")
    else:
        _settle(c, st, meta, "enter")
    return res


def _time_ran_out(c: Campaign, st: RunState, time_before: int) -> bool:
    """Время перешло лимит именно этим ходом (уже после лимита игра идёт своим чередом)."""
    t = c.time
    return bool(t and t.limit is not None and t.on_limit and time_before < t.limit <= st.time)


def _settle(c: Campaign, st: RunState, meta: Meta, mode: str) -> None:
    """Запомнить, как показать экран после хода: целиком, только итог (stay) или кратко (again)."""
    scene = c.scenes[st.scene]
    prev = st.seen.get(st.scene)
    if mode == "enter":
        mode = "again" if prev is not None and scene.again else "full"
    st.screen_mode = mode
    st.seen_extra = list(prev or [])
    shown = {i for i, v in enumerate(scene.extra) if check(v.if_, st, meta)}
    st.seen[st.scene] = sorted(set(prev or []) | shown)


@dataclass
class _Ctx:
    death: str | None = None


def _say(st, meta, ctx, text, system, kind="system"):
    if text:
        st.shown.append(["text", fill(text.strip(), st, meta)])
    if system:
        st.shown.append([kind, fill(system.strip(), st, meta)])


def _goto(goto: Goto | None, st: RunState, meta: Meta) -> str | None:
    if goto is None or isinstance(goto, str):
        return goto
    for case in goto:
        if check(case.if_, st, meta):
            return case.goto
    return None


def _apply(c: Campaign, st: RunState, meta: Meta, effects: list[tuple], ctx: _Ctx) -> None:
    for eff in effects:
        if ctx.death is not None:
            return
        kind = eff[0]
        if kind == "if":
            _apply(c, st, meta, eff[2] if check_node(eff[1], st, meta) else eff[3], ctx)
        elif kind == "after":
            item = eff[1]
            (unit, n), = item["after"].items()
            due = (st.steps if unit == "steps" else st.time) + int(n)
            st.pending.append({"unit": unit, "due": due, **{k: v for k, v in item.items() if k != "after"}})
        else:
            _stmt(c, st, meta, eff[1], ctx)


def check_node(node: tuple, st: RunState, meta: Meta) -> bool:
    return bool(expr.evaluate(node, getter(st, meta)))


def _stmt(c: Campaign, st: RunState, meta: Meta, stmt: tuple, ctx: _Ctx) -> None:
    kind = stmt[0]
    if kind == "set":
        if stmt[1][5:] not in st.flags:
            st.flags.append(stmt[1][5:])
    elif kind == "clear":
        st.flags = [f for f in st.flags if f != stmt[1][5:]]
    elif kind == "die":
        ctx.death = fill(stmt[1], st, meta)
    elif kind == "system":
        _say(st, meta, ctx, None, stmt[1])
    elif kind == "note":
        _say(st, meta, ctx, stmt[1], None)
    elif kind == "assign":
        _, name, op, node = stmt
        value = int(expr.evaluate(node, getter(st, meta)))
        root, _, key = name.partition(".")
        cur = {"var": st.vars, "item": st.items}.get(root)
        old = cur.get(key, 0) if cur is not None else getattr(st, root)
        new = value if op == "=" else old + value if op == "+=" else old - value
        if root == "item":
            new = max(0, new)
        if cur is not None:
            cur[key] = new
        elif root == "lives" and (st.mode != "system" or not c.death.lives):
            return  # в реал-режиме жизнь одна, при lives: 0 — бесконечны
        else:
            setattr(st, root, new)
        if root == "lives" and st.lives <= 0:
            ctx.death = ctx.death or "жизни кончились"


def _due(c: Campaign, st: RunState, meta: Meta, ctx: _Ctx) -> str | None:
    target = None
    keep = []
    for p in st.pending:
        now = st.steps if p["unit"] == "steps" else st.time
        if now < p["due"]:
            keep.append(p)
            continue
        _say(st, meta, ctx, p.get("note"), p.get("system"))
        _apply(c, st, meta, compile_effects(p.get("do", []), "after"), ctx)
        target = p.get("goto") or target
    st.pending = keep
    return target


def _die(c: Campaign, st: RunState, meta: Meta, cause: str, res: Result) -> str:
    d = c.death
    res.events.append(("death", cause, st.scene))
    st.deaths += 1
    if st.mode == "real":
        if d.real == "rewind" and st.checkpoint:
            snap = RunState.model_validate(st.checkpoint)
            _shift_pending(snap, st.steps - snap.steps)
            snap.steps, snap.deaths, snap.checkpoint = st.steps, st.deaths, st.checkpoint
            snap.chapters = st.chapters
            snap.shown = [x for x in st.shown if x[0] == "text"] + [["text", d.rewind_text]]
            snap.shown_status = None
            st.__dict__.update(snap.__dict__)
            return REWIND
        return d.real_final or c.start
    if d.lives:
        st.lives -= 1 if st.lives > 0 else 0
    st.time += d.time_cost
    for item_id, item in c.items.items():
        if not item.keep_on_death:
            st.items.pop(item_id, None)
    st.shown.append(["system", fill(d.message, st, Meta(), {"cause": cause})])
    if d.lives and st.lives <= 0:
        return d.final or c.start
    return d.respawn or c.start


def _enter(c: Campaign, st: RunState, target: str, res: Result, meta: Meta, ctx: _Ctx | None = None) -> None:
    if target == REWIND:
        return  # снимок уже на месте, вход в сцену не повторяем
    ctx = ctx or _Ctx()
    for _ in range(MAX_CHAIN):
        if target not in c.scenes:
            raise GameError(f"нет сцены «{target}»")
        st.scene = target
        scene = c.scenes[target]
        _say(st, meta, ctx, None, scene.system, "entry")  # строка Системы при входе — под текстом сцены
        ctx.death = None
        _apply(c, st, meta, compile_effects(scene.on_enter, target), ctx)
        if ctx.death is not None:
            target = _die(c, st, meta, ctx.death, res)
            if target == REWIND:
                return
            continue
        if scene.checkpoint:
            st.last_checkpoint = target
            st.checkpoint = snapshot(st)
            if not any(ch["scene"] == target for ch in st.chapters):
                st.chapters.append({"scene": target, "title": scene.chapter or "", "state": snapshot(st)})
        if scene.ending:
            st.ended = scene.ending.id
            res.events.append(("ending", scene.ending.id))
        return
    raise GameError("слишком много переходов подряд")


def snapshot(st: RunState) -> dict:
    """Снимок состояния без вложенных снимков (главы и откат хранятся отдельно)."""
    return st.model_dump(exclude={"chapters", "checkpoint"})


def _shift_pending(st: RunState, delta: int) -> None:
    for p in st.pending:
        if p.get("unit") == "steps":
            p["due"] += delta


def chapter_title(c: Campaign, ch: dict, number: int) -> str:
    scene = c.scenes.get(ch["scene"])
    return (scene.chapter if scene and scene.chapter else ch.get("title")) or f"Глава {number}"


def restore_chapter(c: Campaign, st: RunState, index: int) -> None:
    """Вернуть прохождение к началу главы index; главы после неё отбрасываются.
    Номер шага растёт дальше (на нём держится защита от старых кнопок)."""
    if not 0 <= index < len(st.chapters):
        raise GameError("нет такой главы")
    ch = st.chapters[index]
    new = RunState.model_validate(ch["state"])
    _shift_pending(new, st.steps + 1 - new.steps)
    new.steps = st.steps + 1
    new.chapters = [dict(x) for x in st.chapters[: index + 1]]
    new.checkpoint = dict(ch["state"])
    new.last_checkpoint = ch["scene"]
    new.ended, new.awaiting_name = None, False
    new.shown = [["text", f"Вы вернулись к началу главы «{chapter_title(c, ch, index + 1)}»."]]
    new.screen_mode, new.shown_status = "full", None
    st.__dict__.update(new.__dict__)


def migrate(c: Campaign, st: RunState) -> bool:
    """Подогнать старый сейв (и снимки его глав) под новую версию кампании.
    True — состояние изменилось (надо сохранить)."""
    before = st.model_dump_json()

    def resolve(sid: str | None) -> str | None:
        seen: set[str] = set()
        while sid in c.renamed and sid not in seen:
            seen.add(sid)
            sid = c.renamed[sid]
        return sid

    def fix(s: RunState) -> None:
        s.scene = resolve(s.scene)
        s.last_checkpoint = resolve(s.last_checkpoint)
        s.came_from = resolve(s.came_from)
        if s.last_checkpoint not in c.scenes:
            s.last_checkpoint = None
        for p in s.pending:
            if p.get("goto"):
                p["goto"] = resolve(p["goto"])
                if p["goto"] not in c.scenes:
                    p["goto"] = None
        for key, var in c.vars.items():
            s.vars.setdefault(key, var.start)
        s.seen = {k: v for k, v in ((resolve(k), v) for k, v in s.seen.items()) if k in c.scenes}
        s.campaign_version = c.version

    def fix_snap(snap: dict | None) -> dict | None:
        if not snap:
            return None
        s = RunState.model_validate(snap)
        fix(s)
        return snapshot(s) if s.scene in c.scenes else None  # сцены больше нет — снимок выбрасываем

    scene_before = st.scene
    fix(st)
    if st.scene != scene_before:
        st.screen_mode = "full"
    st.checkpoint = fix_snap(st.checkpoint)
    chapters = []
    for ch in st.chapters:
        snap = fix_snap(ch["state"])
        if snap:
            chapters.append({**ch, "scene": snap["scene"], "state": snap})
    st.chapters = chapters
    if st.scene not in c.scenes:
        target = st.last_checkpoint or c.start
        st.scene = target
        chapter = c.scenes[target].chapter
        st.screen_mode = "full"
        if not st.ended:
            st.shown = [["text", f"Кампания обновлена — вы на начале главы «{chapter}»." if chapter
                         else "Кампания обновлена — вы на последней контрольной точке."]]
    return st.model_dump_json() != before


def record(meta: Meta, st: RunState, res: Result) -> None:
    """Перенести события хода в мету."""
    for ev in res.events:
        if ev[0] == "ending":
            meta.endings[ev[1]] = meta.endings.get(ev[1], 0) + 1
        elif ev[0] == "death":
            meta.deaths.append({"run": st.run, "cause": ev[1], "scene": ev[2]})
            meta.deaths = meta.deaths[-50:]
