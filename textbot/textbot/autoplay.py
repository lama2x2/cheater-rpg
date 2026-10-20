"""Автоигрок: python -m textbot.autoplay campaigns/demo [-n 2000] [--mode real]

Случайные прохождения: ищет тупики и зацикливание, проверяет, что все достижимые концовки
(по линтеру) реально достигаются. Код возврата 1 — есть проблемы.
"""
from __future__ import annotations

import argparse
import random
import sys
from collections import Counter

from . import engine
from .lint import lint
from .model import Campaign, load_campaign

MAX_STEPS = 400


def run(c: Campaign, n: int, mode: str | None = None, seed: int = 0) -> tuple[Counter, list[str], int]:
    rng = random.Random(seed)
    endings: Counter = Counter()
    problems: list[str] = []
    deaths = 0
    meta = engine.Meta()
    for i in range(n):
        meta.runs += 1
        st = engine.new_run(c, seed=rng.randrange(1 << 30), run=meta.runs, mode=mode)
        if st.awaiting_name:
            engine.set_name(c, st, "Тест", meta)
        for _ in range(MAX_STEPS):
            if st.ended:
                endings[st.ended] += 1
                break
            options = [ch.index for ch in engine.view(c, st, meta).choices if ch.enabled]
            if not options:
                problems.append(f"прохождение {i}: тупик в «{st.scene}»")
                break
            res = engine.choose(c, st, rng.choice(options), meta)
            engine.record(meta, st, res)
            deaths += sum(1 for e in res.events if e[0] == "death")
        else:
            problems.append(f"прохождение {i}: больше {MAX_STEPS} шагов, последняя сцена «{st.scene}»")
    return endings, problems, deaths


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Случайные прохождения кампании")
    ap.add_argument("folder")
    ap.add_argument("-n", type=int, default=2000)
    ap.add_argument("--mode", choices=["system", "real"])
    a = ap.parse_args(argv)
    c = load_campaign(a.folder)
    mode = a.mode or c.mode
    endings, problems, deaths = run(c, a.n, mode)
    expected = lint(c, mode).endings
    missing = expected - set(endings)
    for p in problems[:20]:
        print(f"ПРОБЛЕМА: {p}")
    print(f"{c.id} ({mode}): {a.n} прохождений, смертей {deaths}")
    for eid, k in endings.most_common():
        print(f"  {eid}: {k} ({k * 100 / a.n:.1f}%)")
    if missing:
        print(f"НЕ ДОСТИГНУТЫ концовки: {', '.join(sorted(missing))}")
    return 1 if problems or missing else 0


if __name__ == "__main__":
    sys.exit(main())
