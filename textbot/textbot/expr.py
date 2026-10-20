"""Маленький безопасный язык условий и эффектов (без eval).

Условие:  flag.clue and (var.trust >= 2 or item.key > 0) and not meta.ending.good
Эффект:   set flag.x | clear flag.x | var.x += 1 | item.key -= 1 | time += 1
          | die 'причина' | system 'строка Системы' | note 'строка для всех режимов'

Имена: flag.<id> (bool), var.<id>, item.<id> (int), time, steps, lives, deaths,
mode ('system' | 'real'), meta.runs, meta.ending.<id> (bool).
"""
from __future__ import annotations

import re
from typing import Any, Callable

TOKEN = re.compile(
    r"\s*(?:(?P<num>\d+)|(?P<str>'[^']*'|\"[^\"]*\")|(?P<name>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)"
    r"|(?P<op>==|!=|<=|>=|\+=|-=|[<>=+\-*()]))"
)
KEYWORDS = {"and", "or", "not", "true", "false"}
ROOTS = {"flag", "var", "item", "time", "steps", "lives", "deaths", "mode", "meta"}
ASSIGNABLE = {"var", "item", "time", "lives"}


class ExprError(ValueError):
    pass


def tokenize(src: str) -> list[tuple[str, Any]]:
    pos, out = 0, []
    src = src.rstrip()
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m or m.end() == pos:
            raise ExprError(f"непонятный символ в «{src}» на позиции {pos}")
        pos = m.end()
        if m.group("num"):
            out.append(("num", int(m.group("num"))))
        elif m.group("str"):
            out.append(("str", m.group("str")[1:-1]))
        elif m.group("name"):
            name = m.group("name")
            out.append(("kw", name) if name in KEYWORDS else ("name", name))
        else:
            out.append(("op", m.group("op")))
    return out


def check_name(name: str) -> None:
    root = name.split(".")[0]
    if root not in ROOTS:
        raise ExprError(f"неизвестное имя «{name}» (можно: {', '.join(sorted(ROOTS))})")
    if root in ("flag", "var", "item") and name.count(".") != 1:
        raise ExprError(f"имя «{name}» должно быть вида {root}.<id>")


# AST: ("num", v) ("str", v) ("bool", v) ("name", n) ("not", a) ("and"/"or", a, b) (op, a, b)
class _Parser:
    def __init__(self, tokens: list, src: str):
        self.t, self.i, self.src = tokens, 0, src

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def take(self, kind=None, value=None):
        tok = self.peek()
        if tok[0] is None or (kind and tok[0] != kind) or (value and tok[1] != value):
            raise ExprError(f"ожидалось {value or kind} в «{self.src}»")
        self.i += 1
        return tok

    def done(self):
        if self.i != len(self.t):
            raise ExprError(f"лишнее в конце «{self.src}»")

    def expr(self):
        node = self.and_()
        while self.peek() == ("kw", "or"):
            self.i += 1
            node = ("or", node, self.and_())
        return node

    def and_(self):
        node = self.not_()
        while self.peek() == ("kw", "and"):
            self.i += 1
            node = ("and", node, self.not_())
        return node

    def not_(self):
        if self.peek() == ("kw", "not"):
            self.i += 1
            return ("not", self.not_())
        return self.cmp()

    def cmp(self):
        node = self.sum()
        tok = self.peek()
        if tok[0] == "op" and tok[1] in ("==", "!=", "<", "<=", ">", ">="):
            self.i += 1
            node = (tok[1], node, self.sum())
        return node

    def sum(self):
        node = self.term()
        while self.peek()[0] == "op" and self.peek()[1] in ("+", "-"):
            op = self.take()[1]
            node = (op, node, self.term())
        return node

    def term(self):
        node = self.atom()
        while self.peek() == ("op", "*"):
            self.i += 1
            node = ("*", node, self.atom())
        return node

    def atom(self):
        kind, val = self.peek()
        if kind == "num":
            self.i += 1
            return ("num", val)
        if kind == "str":
            self.i += 1
            return ("str", val)
        if kind == "kw" and val in ("true", "false"):
            self.i += 1
            return ("bool", val == "true")
        if kind == "name":
            self.i += 1
            check_name(val)
            return ("name", val)
        if (kind, val) == ("op", "-"):
            self.i += 1
            return ("-", ("num", 0), self.atom())
        if (kind, val) == ("op", "("):
            self.i += 1
            node = self.expr()
            self.take("op", ")")
            return node
        raise ExprError(f"ожидалось значение в «{self.src}»")


def parse_expr(src: str | int | bool) -> tuple:
    if isinstance(src, bool):
        return ("bool", src)
    if isinstance(src, int):
        return ("num", src)
    p = _Parser(tokenize(str(src)), str(src))
    node = p.expr()
    p.done()
    return node


def parse_stmt(src: str) -> tuple:
    """Оператор эффекта → ("set", name) | ("clear", name) | ("assign", name, op, expr) | (kw, str)."""
    toks = tokenize(src)
    if not toks:
        raise ExprError("пустой эффект")
    head = toks[0]
    if head[0] == "name" and head[1] in ("set", "clear"):
        if len(toks) != 2 or toks[1][0] != "name" or not toks[1][1].startswith("flag."):
            raise ExprError(f"«{src}»: нужно {head[1]} flag.<id>")
        check_name(toks[1][1])
        return (head[1], toks[1][1])
    if head[0] == "name" and head[1] in ("die", "system", "note"):
        if len(toks) != 2 or toks[1][0] != "str":
            raise ExprError(f"«{src}»: нужно {head[1]} 'текст'")
        return (head[1], toks[1][1])
    if head[0] == "name" and len(toks) >= 3 and toks[1] in (("op", "="), ("op", "+="), ("op", "-=")):
        name = head[1]
        check_name(name)
        if name.split(".")[0] not in ASSIGNABLE:
            raise ExprError(f"«{src}»: «{name}» нельзя менять")
        p = _Parser(toks[2:], src)
        node = p.expr()
        p.done()
        return ("assign", name, toks[1][1], node)
    raise ExprError(f"непонятный эффект «{src}»")


def evaluate(node: tuple, get: Callable[[str], Any]) -> Any:
    kind = node[0]
    if kind in ("num", "str", "bool"):
        return node[1]
    if kind == "name":
        return get(node[1])
    if kind == "not":
        return not evaluate(node[1], get)
    if kind == "and":
        return bool(evaluate(node[1], get)) and bool(evaluate(node[2], get))
    if kind == "or":
        return bool(evaluate(node[1], get)) or bool(evaluate(node[2], get))
    a, b = evaluate(node[1], get), evaluate(node[2], get)
    if kind in ("+", "-", "*"):
        a, b = int(a), int(b)
        return a + b if kind == "+" else a - b if kind == "-" else a * b
    return {"==": a == b, "!=": a != b, "<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b}[kind]


def names_in(node: tuple) -> set[str]:
    if node[0] == "name":
        return {node[1]}
    out: set[str] = set()
    for part in node[1:]:
        if isinstance(part, tuple):
            out |= names_in(part)
    return out
