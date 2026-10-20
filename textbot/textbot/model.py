"""Схема кампании (YAML) и загрузка. Формат — docs/text_rpg/campaign_format.md."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field

from . import expr


class _M(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class GotoCase(_M):
    if_: str | None = Field(None, alias="if")
    goto: str


Goto = str | list[GotoCase]


class Branch(_M):
    text: str | None = None
    system: str | None = None
    effects: list[Any] = []
    goto: Goto | None = None


class Roll(_M):
    chance: str | int
    success: Branch = Branch()
    fail: Branch = Branch()


class Choice(_M):
    label: str
    if_: str | None = Field(None, alias="if")
    locked: str | None = None  # показать замок с причиной, когда условие ложно (иначе — скрыть)
    text: str | None = None
    system: str | None = None
    effects: list[Any] = []
    roll: Roll | None = None
    goto: Goto | None = None


class TextVariant(_M):
    if_: str = Field(alias="if")
    text: str


class Ending(_M):
    id: str
    title: str


class Scene(_M):
    id: str
    text: str
    extra: list[TextVariant] = []
    system: str | None = None
    on_enter: list[Any] = []
    choices: list[Choice] = []
    ending: Ending | None = None
    checkpoint: bool = False


class VarDef(_M):
    start: int = 0
    label: str | None = None
    show: bool = False


class ItemDef(_M):
    name: str
    keep_on_death: bool = True


class TimeCfg(_M):
    limit: int | None = None
    label: str = "Время: {time}"
    on_limit: str | None = None


class DeathCfg(_M):
    lives: int = 3
    respawn: str | None = None
    final: str | None = None
    time_cost: int = 0
    message: str = "Жизнь {deaths} закончилась. Причина: {cause}. Осталось жизней: {lives}."
    real: Literal["ending", "rewind"] = "ending"
    real_final: str | None = None
    rewind_text: str = "…Нет. Не так. Вы снова там, где всё ещё можно исправить."


class Campaign(_M):
    id: str
    title: str
    mode: Literal["system", "real"] = "system"
    about: str = ""
    start: str
    ask_name: str | None = None
    default_name: str = "Нулёвка"
    scenes_dir: str = "scenes"
    vars: dict[str, VarDef] = {}
    items: dict[str, ItemDef] = {}
    time: TimeCfg | None = None
    death: DeathCfg = DeathCfg()
    scenes: dict[str, Scene] = {}
    folder: str = ""


# --- компиляция выражений и эффектов (с кэшем по строке) ---

parse_expr = lru_cache(maxsize=4096)(expr.parse_expr)
parse_stmt = lru_cache(maxsize=4096)(expr.parse_stmt)


def compile_effects(raw: list[Any], where: str) -> list[tuple]:
    out: list[tuple] = []
    for i, item in enumerate(raw):
        at = f"{where}[{i}]"
        try:
            out.append(_compile_effect(item, at))
        except expr.ExprError as e:
            raise expr.ExprError(f"{at}: {e}") from None
    return out


def _compile_effect(item: Any, at: str) -> tuple:
    if isinstance(item, str):
        return ("stmt", parse_stmt(item))
    if isinstance(item, dict) and "if" in item:
        extra = set(item) - {"if", "then", "else"}
        if extra:
            raise expr.ExprError(f"лишние ключи {sorted(extra)}")
        return ("if", parse_expr(item["if"]),
                compile_effects(item.get("then", []), at + ".then"),
                compile_effects(item.get("else", []), at + ".else"))
    if isinstance(item, dict) and "after" in item:
        extra = set(item) - {"after", "do", "goto", "note", "system"}
        when = item["after"]
        if extra or not isinstance(when, dict) or len(when) != 1 or next(iter(when)) not in ("steps", "time"):
            raise expr.ExprError("after: {steps: N} или {time: N}; ключи do, goto, note, system")
        compile_effects(item.get("do", []), at + ".do")
        return ("after", item)
    raise expr.ExprError(f"непонятный эффект {item!r}")


def iter_effect_lists(c: Campaign):
    """Все списки эффектов кампании с местом — для проверки и линтера."""
    for s in c.scenes.values():
        yield f"{s.id}.on_enter", s.on_enter
        for i, ch in enumerate(s.choices):
            yield f"{s.id}.choices[{i}].effects", ch.effects
            if ch.roll:
                yield f"{s.id}.choices[{i}].roll.success", ch.roll.success.effects
                yield f"{s.id}.choices[{i}].roll.fail", ch.roll.fail.effects


def iter_conditions(c: Campaign):
    for s in c.scenes.values():
        for v in s.extra:
            yield f"{s.id}.extra", v.if_
        for i, ch in enumerate(s.choices):
            where = f"{s.id}.choices[{i}]"
            if ch.if_:
                yield where + ".if", ch.if_
            if ch.roll:
                yield where + ".roll.chance", ch.roll.chance
            for g in _goto_cases(ch.goto) + (_goto_cases(ch.roll.success.goto) + _goto_cases(ch.roll.fail.goto) if ch.roll else []):
                if g.if_:
                    yield where + ".goto.if", g.if_


def _goto_cases(goto: Goto | None) -> list[GotoCase]:
    return goto if isinstance(goto, list) else []


def load_campaign(folder: str | Path) -> Campaign:
    folder = Path(folder)
    data = yaml.safe_load((folder / "campaign.yaml").read_text(encoding="utf-8")) or {}
    camp = Campaign.model_validate(data)
    camp.folder = str(folder)
    scenes_dir = (folder / camp.scenes_dir).resolve()
    files = sorted(scenes_dir.glob("*.yaml"))
    if not files:
        raise ValueError(f"нет сцен в {scenes_dir}")
    for f in files:
        raw = yaml.safe_load(f.read_text(encoding="utf-8")) or []
        if isinstance(raw, dict):
            raw = raw.get("scenes", [])
        for item in raw:
            scene = Scene.model_validate(item)
            if scene.id in camp.scenes:
                raise ValueError(f"{f.name}: сцена «{scene.id}» уже есть")
            camp.scenes[scene.id] = scene
    # синтаксис всех выражений и эффектов — сразу при загрузке
    for where, src in iter_conditions(camp):
        try:
            parse_expr(src)
        except expr.ExprError as e:
            raise ValueError(f"{where}: {e}") from None
    for where, lst in iter_effect_lists(camp):
        try:
            compile_effects(lst, where)
        except expr.ExprError as e:
            raise ValueError(str(e)) from None
    return camp
