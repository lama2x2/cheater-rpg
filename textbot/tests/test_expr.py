import pytest

from textbot.expr import ExprError, evaluate, parse_expr, parse_stmt

ENV = {"flag.a": True, "flag.b": False, "var.x": 3, "item.key": 0, "time": 2, "mode": "system"}


def ev(src):
    return evaluate(parse_expr(src), ENV.__getitem__)


def test_logic_and_precedence():
    assert ev("flag.a and not flag.b")
    assert ev("flag.b or var.x >= 3 and time == 2")
    assert not ev("(flag.b or flag.a) and item.key > 0")
    assert ev("40 + var.x * 10") == 70
    assert ev("-1 < 0")
    assert ev("mode == 'system'")


@pytest.mark.parametrize("bad", [
    "__import__('os')", "flag.a.b", "open", "var", "flag.a and", "1 +", "x.y", "var.x ; 1", "lambda",
])
def test_rejects_bad(bad):
    with pytest.raises(ExprError):
        parse_expr(bad)


def test_statements():
    assert parse_stmt("set flag.x") == ("set", "flag.x")
    assert parse_stmt("die 'тварь'") == ("die", "тварь")
    kind, name, op, _ = parse_stmt("var.trust += 1 + time")
    assert (kind, name, op) == ("assign", "var.trust", "+=")
    for bad in ("set var.x", "steps = 3", "mode = 'real'", "var.x ++", "die тварь", "flag.x = 1"):
        with pytest.raises(ExprError):
            parse_stmt(bad)
