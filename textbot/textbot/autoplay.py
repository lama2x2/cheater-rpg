"""Автоигрок: python -m textbot.autoplay campaigns/demo [-n 2000] [--mode real] [--screens [--seed N]]

Случайные прохождения: ищет тупики и зацикливание, проверяет, что все достижимые концовки
(по линтеру) реально достигаются, и читает экраны глазами игрока: абзац, повторённый на одном
из недавних экранов, пустой или слишком длинный экран, заход в сцену, где делать уже нечего.
Код возврата 1 — есть проблемы.

--screens — вывести экраны одного прохождения подряд (как в чате), повторы помечены ⟳.
"""
from __future__ import annotations

import argparse
import random
import sys
from collections import Counter, deque

from . import engine, render
from .lint import REPEAT_MIN, TEXT_LIMIT, lint
from .model import Campaign, load_campaign

MAX_STEPS = 400
REPEAT_WINDOW = 6   # с последними скольких экранами сравнивать (в пределах одной жизни)


class Reader:
    """Следит за экранами одного прохождения так, как их видит игрок."""

    def __init__(self, c: Campaign):
        self.c = c
        self.recent: deque[set[str]] = deque(maxlen=REPEAT_WINDOW)
        self.visited: set[str] = set()

    def death(self) -> None:
        self.recent.clear()  # после смерти всё по новой — повтор знакомых мест задуман

    def look(self, st: engine.RunState, scr: engine.Screen, came_from: str | None) -> tuple[list[str], set[str]]:
        """Проблемы этого экрана и абзацы-повторы."""
        problems: list[str] = []
        paras = [t for k, t in scr.parts if k in ("text", "system")]
        repeats = {p for p in paras if len(p) >= REPEAT_MIN and any(p in old for old in self.recent)}
        dup = {p for p in paras if len(p) >= REPEAT_MIN and paras.count(p) > 1}
        for p in sorted(repeats | dup):
            problems.append(f"«{st.scene}»: абзац повторяется — «{p[:70]}…»")
        if not scr.text:
            problems.append(f"«{st.scene}»: на экране нет текста")
        size = len("\n\n".join(paras))
        if size > TEXT_LIMIT:
            problems.append(f"«{st.scene}»: экран {size} знаков, больше {TEXT_LIMIT}")
        if came_from and came_from != st.scene and st.scene in self.visited and not st.ended:
            scene = self.c.scenes[st.scene]
            enabled = [scene.choices[ch.index] for ch in scr.choices if ch.enabled]
            if all(ch.goto == came_from and not (ch.effects or ch.text or ch.roll or ch.system) for ch in enabled):
                problems.append(f"«{st.scene}»: повторный заход, а делать уже нечего — только назад в «{came_from}»")
        self.visited.add(st.scene)
        self.recent.append(set(paras))
        return problems, repeats | dup


def run(c: Campaign, n: int, mode: str | None = None, seed: int = 0) -> tuple[Counter, list[str], int]:
    rng = random.Random(seed)
    endings: Counter = Counter()
    problems: dict[str, int] = {}  # проблема → номер первого прохождения, где встретилась
    deaths = 0
    meta = engine.Meta()

    def note(msgs: list[str], i: int) -> None:
        for m in msgs:
            problems.setdefault(m, i)

    for i in range(n):
        meta.runs += 1
        st = engine.new_run(c, seed=rng.randrange(1 << 30), run=meta.runs, mode=mode, meta=meta)
        if st.awaiting_name:
            engine.set_name(c, st, "Тест", meta)
        reader = Reader(c)
        note(reader.look(st, engine.view(c, st, meta), None)[0], i)
        for _ in range(MAX_STEPS):
            if st.ended:
                endings[st.ended] += 1
                break
            options = [ch.index for ch in engine.view(c, st, meta).choices if ch.enabled]
            if not options:
                note([f"тупик в «{st.scene}»"], i)
                break
            came_from = st.scene
            res = engine.choose(c, st, rng.choice(options), meta)
            engine.record(meta, st, res)
            died = sum(1 for e in res.events if e[0] == "death")
            deaths += died
            if died:
                reader.death()
            note(reader.look(st, engine.view(c, st, meta), came_from)[0], i)
        else:
            note([f"больше {MAX_STEPS} шагов, последняя сцена «{st.scene}»"], i)
    return endings, [f"прохождение {i}: {m}" for m, i in problems.items()], deaths


def screens(c: Campaign, mode: str | None, seed: int) -> list[str]:
    """Одно прохождение экран за экраном — как в чате. Возвращает проблемы."""
    rng = random.Random(seed)
    meta = engine.Meta(runs=1)
    st = engine.new_run(c, seed=seed, mode=mode, meta=meta)
    if st.awaiting_name:
        engine.set_name(c, st, "Тест", meta)
    reader = Reader(c)
    found: list[str] = []
    came_from, label = None, None
    for _ in range(MAX_STEPS):
        scr = engine.view(c, st, meta)
        problems, repeats = reader.look(st, scr, came_from)
        found += problems
        out = render.plain(scr)
        for p in repeats:
            out = out.replace(p, "⟳ " + p)
        print("─" * 72 + (f"\n➤ {label}\n" if label else "\n") + f"[{st.scene} · {st.screen_mode}]\n" + out)
        for p in problems:
            print(f"!!! {p}")
        if st.ended:
            break
        options = [ch for ch in scr.choices if ch.enabled]
        if not options:
            break
        pick = rng.choice(options)
        came_from, label = st.scene, pick.label
        res = engine.choose(c, st, pick.index, meta)
        engine.record(meta, st, res)
        if any(e[0] == "death" for e in res.events):
            reader.death()
    return found


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Случайные прохождения кампании")
    ap.add_argument("folder")
    ap.add_argument("-n", type=int, default=2000)
    ap.add_argument("--mode", choices=["system", "real"])
    ap.add_argument("--screens", action="store_true", help="показать экраны одного прохождения")
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args(argv)
    c = load_campaign(a.folder)
    mode = a.mode or c.mode
    if a.screens:
        return 1 if screens(c, mode, a.seed) else 0
    endings, problems, deaths = run(c, a.n, mode, a.seed)
    expected = lint(c, mode).endings
    missing = expected - set(endings)
    for p in problems[:40]:
        print(f"ПРОБЛЕМА: {p}")
    if len(problems) > 40:
        print(f"… и ещё {len(problems) - 40}")
    print(f"{c.id} ({mode}): {a.n} прохождений, смертей {deaths}")
    for eid, k in endings.most_common():
        print(f"  {eid}: {k} ({k * 100 / a.n:.1f}%)")
    if missing:
        print(f"НЕ ДОСТИГНУТЫ концовки: {', '.join(sorted(missing))}")
    return 1 if problems or missing else 0


if __name__ == "__main__":
    sys.exit(main())
