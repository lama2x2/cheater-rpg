"""Линтер кампании: python -m textbot.lint campaigns/demo [--mode real]"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

from . import expr
from .model import Campaign, Goto, compile_effects, load_campaign, parse_expr

LOCK = "scene_ids.lock"  # id сцен прошлой версии: python -m textbot.lint <папка> --lock
TEXT_LIMIT = 3500
AGAIN_LIMIT = 200  # again — связка при возврате, а не второй текст сцены
REPEAT_MIN = 80    # абзацы короче — связки («Вы снова у двери»): их повтор не глюк
DEATH_MARK = "☠"  # запас под шапку и строки Системы до лимита Telegram 4096


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


def _writes(effects: list) -> tuple[set[str], bool]:
    """Что меняют эффекты и может ли в них быть смерть."""
    out: set[str] = set()
    dies = _walk(compile_effects(effects, "check"), set(), out, [], {})
    return out, dies


def _stay_checks(sid: str, i: int, ch, r: Report) -> None:
    """Выбор, после которого игрок остаётся в сцене: экран не пустой и ответ не повторяется."""
    where = f"{sid}.choices[{i}] «{ch.label}»"
    outcomes = [(ch.text, ch.goto, [])]
    if ch.roll:
        outcomes = [(ch.text or b.text, b.goto or ch.goto, b.effects) for b in (ch.roll.success, ch.roll.fail)]
    cond = expr.names_in(parse_expr(ch.if_)) if ch.if_ else set()
    for text, goto, effects in outcomes:
        (w1, d1), (w2, d2) = _writes(ch.effects), _writes(effects)
        if goto or d1 or d2:  # ушли в другую сцену или погибли
            continue
        if not text:
            r.warnings.append(f"{where}: после выбора остаёмся в сцене, а текста-итога нет — экран будет пустым")
        if len(text or "") >= REPEAT_MIN and not cond & (w1 | w2):
            r.warnings.append(f"{where}: после выбора остаёмся в сцене, а выбор не исчезает — "
                              f"можно выбрать снова и получить тот же ответ (добавьте if с флагом)")
            return


def _hubs(edges: dict[str, set[str]], once: set[tuple[str, str]]) -> dict[str, str]:
    """Хабы: сцена с несколькими выходами, из которой можно сходить в соседнюю и вернуться
    назад; once — переходы, которые закрываются после первого раза (их if гасит сам выбор или вход
    в сцену). Сцена → откуда возвращаются. (Остальные повторы ловит автоигрок по факту.)"""
    out: dict[str, str] = {}
    for sid, targets in edges.items():
        back = sorted(t for t in targets if t != sid and sid in edges[t] and (t, sid) not in once)
        if back and len(targets - {sid}) >= 2:
            out[sid] = back[0]
    return out


def lint(c: Campaign, mode: str | None = None) -> Report:
    mode = mode or c.mode
    r = Report()
    scenes = c.scenes
    reads: set[str] = set()
    writes: set[str] = set()
    flags: dict[str, list[int]] = {}
    edges: dict[str, set[str]] = {sid: set() for sid in scenes}
    dying: set[str] = set()
    once: set[tuple[str, str]] = set()  # переходы «только один раз»

    def need(sid: str | None, where: str) -> None:
        if sid and sid not in scenes:
            r.errors.append(f"{where}: нет сцены «{sid}»")

    need(c.start, "start")
    for old, new in c.renamed.items():
        if old in scenes:
            r.errors.append(f"renamed: «{old}» всё ещё есть среди сцен")
        need(new, f"renamed.{old}")
    lock = Path(c.folder) / LOCK if c.folder else None
    if lock and lock.exists():
        for sid in lock.read_text(encoding="utf-8").split():
            if sid not in scenes and sid not in c.renamed and sid not in c.removed:
                r.warnings.append(f"сцена «{sid}» была в прошлой версии и пропала — добавьте её в "
                                  f"renamed (если переименована) или removed")
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
            lethal = False
            if ch.roll:
                reads |= expr.names_in(parse_expr(ch.roll.chance))
                branches += [(ch.roll.success.effects, ch.roll.success.goto), (ch.roll.fail.effects, ch.roll.fail.goto)]
            for effs, goto in branches:
                if _walk(compile_effects(effs, where), reads, writes, gotos, flags):
                    dying.add(sid)
                    lethal = True
                gotos += _targets(goto)
                if isinstance(goto, list):
                    for g in goto:
                        if g.if_:
                            reads |= expr.names_in(parse_expr(g.if_))
                    if goto and goto[-1].if_:
                        r.warnings.append(f"{where}: у условного goto нет варианта по умолчанию")
            _stay_checks(sid, i, ch, r)
            if ch.if_:
                cond = expr.names_in(parse_expr(ch.if_))
                for t in _targets(ch.goto):
                    if t in scenes and cond & (_writes(ch.effects)[0] | _writes(scenes[t].on_enter)[0]):
                        once.add((sid, t))
            if lethal and DEATH_MARK not in ch.label:
                r.warnings.append(f"{where}: выбор может убить, но в подписи нет {DEATH_MARK} — "
                                  f"смертельный риск должен быть виден заранее")
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
        if s.again and len(s.again) > AGAIN_LIMIT:
            r.warnings.append(f"{sid}: again {len(s.again)} знаков — это связка при возврате, "
                              f"держите её короче {AGAIN_LIMIT}")

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

    # хабы: без again текст сцены при возврате повторится целиком
    for sid, back in sorted(_hubs(edges, once).items()):
        if not scenes[sid].again:
            r.warnings.append(f"{sid}: в сцену возвращаются (из «{back}»), а again не задан — "
                              f"при возврате её текст повторится целиком")

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
    ap.add_argument("--lock", action="store_true", help="записать текущие id сцен как «прошлую версию»")
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
    if a.lock and not rep.errors:
        (Path(a.folder) / LOCK).write_text("\n".join(sorted(c.scenes)) + "\n", encoding="utf-8")
        print(f"записано {LOCK}")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
