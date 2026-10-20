"""Экран → текст: HTML для Telegram и простой текст для терминала."""
from __future__ import annotations

from html import escape

from .engine import Meta, RunState, Screen, getter
from .model import Campaign


def html(screen: Screen) -> str:
    parts = []
    if screen.system:
        parts.append("<blockquote>" + "\n".join("▌ " + escape(s) for s in screen.system) + "</blockquote>")
    if screen.ending_title:
        parts.append(f"<b>{escape(screen.ending_title.upper())}</b>")
    parts += [escape(t) for t in screen.text]
    if screen.status:
        parts.append(f"<i>{escape(screen.status)}</i>")
    return "\n\n".join(parts)[:4000]


def plain(screen: Screen) -> str:
    parts = ["\n".join("▌ " + s for s in screen.system)] if screen.system else []
    if screen.ending_title:
        parts.append(f"=== {screen.ending_title.upper()} ===")
    parts += screen.text
    if screen.status:
        parts.append(f"[{screen.status}]")
    for ch in screen.choices:
        parts.append(f"  {ch.index + 1}. {ch.label}" if ch.enabled else f"  🔒 {ch.label} — {ch.reason}")
    return "\n\n".join(parts)


def status(c: Campaign, st: RunState, meta: Meta) -> str:
    """/status: в режиме system — интерфейс Системы, в real — только что при себе."""
    get = getter(st, meta)
    items = [f"{c.items[k].name}{' ×' + str(n) if n > 1 else ''}" for k, n in st.items.items() if n > 0 and k in c.items]
    if st.mode == "system":
        lines = [f"▌ ИНТЕРФЕЙС · {st.name or 'Объект'}", f"▌ Жизней: {st.lives} · смертей: {st.deaths}"]
        lines += [f"▌ {v.label}: {get('var.' + k)}" for k, v in c.vars.items() if v.show and v.label]
    else:
        lines = [st.name or ""]
    if c.time:
        lines.append(c.time.label.replace("{time}", str(st.time)).replace("{limit}", str(c.time.limit or "∞")))
    lines.append("При себе: " + (", ".join(items) if items else "ничего"))
    return "\n".join(lines)


def memento(c: Campaign, meta: Meta) -> str:
    endings = {s.ending.id: s.ending.title for s in c.scenes.values() if s.ending}
    lines = [f"Прохождений: {meta.runs}", f"Концовки: {len([e for e in endings if e in meta.endings])} из {len(endings)}"]
    lines += [f"  ✓ {title}" if eid in meta.endings else "  · ???" for eid, title in endings.items()]
    if meta.deaths:
        lines.append("Мементо:")
        lines += [f"  † прохождение {d['run']}: {d['cause']}" for d in meta.deaths[-10:]]
    return "\n".join(lines)
