"""Все кампании: линтер чист (и без предупреждений, кроме демо), автоигрок доходит до всех концовок."""
import pytest

from textbot.autoplay import run
from textbot.lint import lint
from textbot.model import load_campaign

from .conftest import CAMPAIGNS

CASES = [("demo", "system"), ("demo", "real"), ("demo_real", "real")] + [
    (p.parent.name, None) for p in sorted(CAMPAIGNS.glob("*/campaign.yaml")) if not p.parent.name.startswith("demo")]


@pytest.mark.parametrize("name,mode", CASES)
def test_campaign_lint_and_autoplay(name, mode):
    c = load_campaign(CAMPAIGNS / name)
    rep = lint(c, mode)
    assert rep.errors == []
    if not name.startswith("demo"):
        assert rep.warnings == []
    endings, problems, _ = run(c, 3000, mode)
    assert problems == []
    assert rep.endings <= set(endings), f"не достигнуты: {rep.endings - set(endings)}"
