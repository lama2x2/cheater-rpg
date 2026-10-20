"""Демо-кампании: линтер чист, автоигрок достигает всех концовок в обоих режимах."""
import pytest

from textbot.autoplay import run
from textbot.lint import lint
from textbot.model import load_campaign

from .conftest import CAMPAIGNS


@pytest.mark.parametrize("name,mode", [("demo", "system"), ("demo", "real"), ("demo_real", "real")])
def test_demo_lint_and_autoplay(name, mode):
    c = load_campaign(CAMPAIGNS / name)
    rep = lint(c, mode)
    assert rep.errors == []
    endings, problems, _ = run(c, 1500, mode)
    assert problems == []
    assert rep.endings <= set(endings)
