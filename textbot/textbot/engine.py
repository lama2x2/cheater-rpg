"""Движок книги-игры: чистые функции над состоянием прохождения, без Telegram."""
from __future__ import annotations

import random
import re
from dataclasses import dataclass, field
from typing import Any

from pydantic import BaseModel

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
    checkpoint: dict | None = None
    last_checkpoint: str | None = None   # id последней пройденной сцены с checkpoint: true
    campaign_version: int = 1
    ended: str | None = None
    shown_text: list[str] = []    # итог прошлого выбора — над текстом сцены
    shown_system: list[str] = []  # строки Системы к этому экрану


@dataclass
class ChoiceView:
    index: int
    label: str
    enabled: bool
    reason: str | None = None


@dataclass
class Screen:
    text: list[str]
    system: list[str]
    status: str | None
    choices: list[ChoiceView]
    ending: str | None = None
    ending_title: str | None = None


@dataclass
class Result:
    events: list[tuple] = field(default_factory=list)  # ("ending", id) | ("death", cause, scene)


class GameError(Exception):
    pass


# ---------- начало и чтение ----------

def new_run(c: Campaign, seed: int | None = None, run: int = 1, mode: str | None = None) -> RunState:
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
        _enter(c, st, c.start, Result(), Meta())
    return st


def set_name(c: Campaign, st: RunState, name: str, meta: Meta) -> Result:
    st.name = name.strip()[:40] or c.default_name
    st.awaiting_name = False
    res = Result()
    _enter(c, st, st.scene, res, meta)
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


def view(c: Campaign, st: RunState, meta: Meta) -> Screen:
    scene = c.scenes[st.scene]
    body = [fill(scene.text.strip(), st, meta)]
    body += [fill(v.text.strip(), st, meta) for v in scene.extra if check(v.if_, st, meta)]
    choices = []
    if not st.ended:
        for i, ch in enumerate(scene.choices):
            ok = check(ch.if_, st, meta)
            if ok or ch.locked:
                choices.append(ChoiceView(i, fill(ch.label, st, meta), ok, None if ok else ch.locked))
    system = st.shown_system if st.mode == "system" else []
    return Screen(
        text=st.shown_text + body, system=system, status=status_line(c, st, meta), choices=choices,
        ending=st.ended, ending_title=scene.ending.title if scene.ending else None,
    )


def status_line(c: Campaign, st: RunState, meta: Meta) -> str | None:
    parts = []
    if st.mode == "system":
        parts.append(f"☥ {st.lives}")
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
    st.shown_text, st.shown_system = [], []
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
    if c.time and c.time.limit is not None and c.time.on_limit and st.time >= c.time.limit \
            and target != REWIND:
        if not (target and target in c.scenes and c.scenes[target].ending):
            target = c.time.on_limit
    if target:  # без перехода — остаёмся в сцене, вход не повторяем
        _enter(c, st, target, res, meta, ctx)
    return res


@dataclass
class _Ctx:
    death: str | None = None


def _say(st, meta, ctx, text, system):
    if text:
        st.shown_text.append(fill(text.strip(), st, meta))
    if system:
        st.shown_system.append(fill(system.strip(), st, meta))


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
        elif root == "lives" and st.mode != "system":
            return  # в реал-режиме жизнь одна
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
            snap.steps, snap.deaths, snap.checkpoint = st.steps, st.deaths, st.checkpoint
            snap.shown_text, snap.shown_system = st.shown_text + [d.rewind_text], []
            st.__dict__.update(snap.__dict__)
            return REWIND
        return d.real_final or c.start
    st.lives -= 1 if st.lives > 0 else 0
    st.time += d.time_cost
    for item_id, item in c.items.items():
        if not item.keep_on_death:
            st.items.pop(item_id, None)
    st.shown_system.append(fill(d.message, st, Meta(), {"cause": cause}))
    if st.lives <= 0:
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
        _say(st, meta, ctx, None, scene.system)
        ctx.death = None
        _apply(c, st, meta, compile_effects(scene.on_enter, target), ctx)
        if ctx.death is not None:
            target = _die(c, st, meta, ctx.death, res)
            if target == REWIND:
                return
            continue
        if scene.checkpoint:
            st.last_checkpoint = target
            snap = st.model_dump()
            snap["checkpoint"] = None
            st.checkpoint = snap
        if scene.ending:
            st.ended = scene.ending.id
            res.events.append(("ending", scene.ending.id))
        return
    raise GameError("слишком много переходов подряд")


def migrate(c: Campaign, st: RunState) -> bool:
    """Подогнать старый сейв под новую версию кампании. True — состояние изменилось (сохранить)."""
    before = st.model_dump_json()

    def resolve(sid: str | None) -> str | None:
        seen: set[str] = set()
        while sid in c.renamed and sid not in seen:
            seen.add(sid)
            sid = c.renamed[sid]
        return sid

    st.scene = resolve(st.scene)
    st.last_checkpoint = resolve(st.last_checkpoint)
    if st.last_checkpoint not in c.scenes:
        st.last_checkpoint = None
    for p in st.pending:
        if p.get("goto"):
            p["goto"] = resolve(p["goto"])
            if p["goto"] not in c.scenes:
                p["goto"] = None
    if st.checkpoint:
        st.checkpoint["scene"] = resolve(st.checkpoint["scene"])
        if st.checkpoint["scene"] not in c.scenes:
            st.checkpoint = None
    for key, var in c.vars.items():
        st.vars.setdefault(key, var.start)
    if st.scene not in c.scenes:
        target = st.last_checkpoint or c.start
        st.scene = target
        chapter = c.scenes[target].chapter
        if not st.ended:
            st.shown_system = []
            st.shown_text = [f"Кампания обновлена — вы на начале главы «{chapter}»." if chapter
                             else "Кампания обновлена — вы на последней контрольной точке."]
    st.campaign_version = c.version
    return st.model_dump_json() != before


def record(meta: Meta, st: RunState, res: Result) -> None:
    """Перенести события хода в мету."""
    for ev in res.events:
        if ev[0] == "ending":
            meta.endings[ev[1]] = meta.endings.get(ev[1], 0) + 1
        elif ev[0] == "death":
            meta.deaths.append({"run": st.run, "cause": ev[1], "scene": ev[2]})
            meta.deaths = meta.deaths[-50:]
