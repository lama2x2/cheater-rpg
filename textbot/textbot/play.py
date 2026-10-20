"""Игра в терминале: python -m textbot.play campaigns/demo [--mode real] [--seed N]"""
from __future__ import annotations

import argparse

from . import engine, render
from .model import load_campaign


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description="Проигрыватель кампании в терминале")
    ap.add_argument("folder")
    ap.add_argument("--mode", choices=["system", "real"])
    ap.add_argument("--seed", type=int)
    a = ap.parse_args(argv)
    c = load_campaign(a.folder)
    meta = engine.Meta(runs=1)
    st = engine.new_run(c, a.seed, mode=a.mode)
    if st.awaiting_name:
        engine.set_name(c, st, input(f"{c.ask_name}\n> "), meta)
    while True:
        print("\n" + "─" * 60 + "\n" + render.plain(engine.view(c, st, meta)))
        if st.ended:
            print("\n" + render.memento(c, meta))
            return
        cmd = input("> ").strip()
        if cmd in ("q", "quit", "выход"):
            return
        if cmd == "s":
            print(render.status(c, st, meta))
            continue
        try:
            res = engine.choose(c, st, int(cmd) - 1, meta)
            engine.record(meta, st, res)
        except (ValueError, engine.GameError) as e:
            print(f"(нельзя: {e}; номер выбора, s — статус, q — выход)")


if __name__ == "__main__":
    main()
