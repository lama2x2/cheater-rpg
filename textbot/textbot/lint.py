"""Линтер кампании: python -m textbot.lint campaigns/demo [--mode real]"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field

from . import expr
from .model import Campaign, Goto, compile_effects, load_campaign, parse_expr

TEXT_LIMIT = 3500  # запас под шапку и строки Системы до лимита Telegram 4096


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    endings: set[str] = field(default_factory=set)  # концовки, достижимые в режиме


def _targets(goto: Goto | None) -> list[str]:
    if goto is None:
        return []
    return [goto] if isinstance(goto, str) else [g.goto for g in goto]


def _walk(effects: list[tuple], reads: set, writes: set, gotos: list, flags: dict) -> bool:
    """Обходит скомпилированные эффекты; возвращает True, если внутри есть смерть."""
    dies = False
    for e in effects:
        if e[0] == "if":
            reads |= expr.names_in(e[1])
            dies |= _walk(e[2], reads, writes, gotos, flags)
            dies |= _walk(e[3], reads, writes, gotos, flags)
        elif e[0] == "after":
            gotos += _targets(e[1].get("goto"))
            dies |= _walk(compile_effects(e[1].get("do", []), "after"), reads, writes, gotos, flags)
        else:
            st = e[1]
            if st[0] in ("set", "clear"):
                flags.setdefault(st[1], [0, 0])[0] += 1
                writes.add(st[1])
            elif st[0] == "assign":
                writes.add(st[1])
                reads |= expr.names_in(st[3])
                dies |= st[1] == "lives"
            elif st[0] == "die":
                dies = True
    return dies


def lint(c: Campaign, mode: str | None = None) -> Report:
    mode = mode or c.mode
    r = Report()
    scenes = c.scenes
    reads: set[str] = set()
    writes: set[str] = set()
    flags: dict[str, list[int]] = {}
    edges: dict[str, set[str]] = {sid: set() for sid in scenes}
    dying: set[str] = set()

    def need(sid: str | None, where: str) -> None:
        if sid and sid not in scenes:
            r.errors.append(f"{where}: нет сцены «{sid}»")

    need(c.start, "start")
    if c.time:
        need(c.time.on_limit, "time.on_limit")
    d = c.death
    for key in ("respawn", "final", "real_final"):
        need(getattr(d, key), f"death.{key}")

    for sid, s in scenes.items():
        gotos: list[str] = []
        if _walk(compile_effects(s.on_enter, sid), reads, writes, gotos, flags):
            dying.add(sid)
        for v in s.extra:
            reads |= expr.names_in(parse_expr(v.if_))
        for i, ch in enumerate(s.choices):
            where = f"{sid}.choices[{i}]"
            if ch.if_:
                reads |= expr.names_in(parse_expr(ch.if_))
            branches = [(ch.effects, ch.goto)]
            if ch.roll:
                reads |= expr.names_in(parse_expr(ch.roll.chance))
                branches += [(ch.roll.success.effects, ch.roll.success.goto), (ch.roll.fail.effects, ch.roll.fail.goto)]
            for effs, goto in branches:
                if _walk(compile_effects(effs, where), reads, writes, gotos, flags):
                    dying.add(sid)
                gotos += _targets(goto)
                if isinstance(goto, list):
                    for g in goto:
                        if g.if_:
                            reads |= expr.names_in(parse_expr(g.if_))
                    if goto and goto[-1].if_:
                        r.warnings.append(f"{where}: у условного goto нет варианта по умолчанию")
        for g in gotos:
            need(g, sid)
            if g in scenes:
                edges[sid].add(g)
        if not s.ending and not s.choices:
            r.errors.append(f"{sid}: тупик — нет выборов и это не концовка")
        elif not s.ending and all(ch.if_ for ch in s.choices):
            r.warnings.append(f"{sid}: все выборы с условиями — может стать тупиком")
        if s.ending and s.choices:
            r.warnings.append(f"{sid}: у концовки есть выборы — они не покажутся")
        size = len(s.text) + sum(len(v.text) for v in s.extra)
        if size > TEXT_LIMIT:
            r.errors.append(f"{sid}: текст {size} знаков, больше {TEXT_LIMIT}")

    # имена
    for name in sorted(reads | writes):
        root, _, key = name.partition(".")
        if root == "var" and key not in c.vars:
            r.errors.append(f"неизвестная переменная «{name}» (объявите в campaign.yaml → vars)")
        if root == "item" and key not in c.items:
            r.errors.append(f"неизвестный предмет «{name}» (объявите в campaign.yaml → items)")
    for name in reads:
        if name.startswith("flag."):
            flags.setdefault(name, [0, 0])[1] += 1
    for name, (set_n, read_n) in sorted(flags.items()):
        if read_n and not set_n:
            r.errors.append(f"флаг «{name}» читается, но нигде не ставится")
        if set_n and not read_n:
            r.warnings.append(f"флаг «{name}» ставится, но нигде не читается")

    # переходы по правилам: смерть, лимит времени
    death_targets = ([d.respawn, d.final] if mode == "system"
                     else [d.real_final] if d.real == "ending" else [])
    if dying and mode == "real" and d.real == "ending" and not d.real_final:
        r.errors.append("death.real_final не задан, а смерть в кампании есть")
    for sid in dying:
        edges[sid] |= {t for t in death_targets if t and t in scenes}
    if c.time and c.time.limit is not None and c.time.on_limit in scenes:
        for sid in scenes:
            if not scenes[sid].ending:
                edges[sid].add(c.time.on_limit)

    seen, stack = set(), [c.start] if c.start in scenes else []
    while stack:
        sid = stack.pop()
        if sid in seen:
            continue
        seen.add(sid)
        stack += edges[sid]
    for sid in scenes:
        if sid not in seen:
            r.warnings.append(f"{sid}: недостижима в режиме {mode}")
    r.endings = {scenes[s].ending.id for s in seen if scenes[s].ending}
    if not r.endings:
        r.errors.append(f"в режиме {mode} нет достижимых концовок")
    return r


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Проверка кампании")
    ap.add_argument("folder")
    ap.add_argument("--mode", choices=["system", "real"])
    a = ap.parse_args(argv)
    try:
        c = load_campaign(a.folder)
    except Exception as e:  # noqa: BLE001 — показать любую ошибку загрузки
        print(f"ОШИБКА загрузки: {e}")
        return 1
    rep = lint(c, a.mode)
    for w in rep.warnings:
        print(f"предупреждение: {w}")
    for e in rep.errors:
        print(f"ОШИБКА: {e}")
    print(f"{c.id} ({a.mode or c.mode}): сцен {len(c.scenes)}, концовки: {', '.join(sorted(rep.endings)) or '—'}; "
          f"ошибок {len(rep.errors)}, предупреждений {len(rep.warnings)}")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
