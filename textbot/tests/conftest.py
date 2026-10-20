import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from textbot.model import load_campaign  # noqa: E402

CAMPAIGNS = ROOT / "campaigns"


@pytest.fixture
def make_campaign(tmp_path):
    """Кампания из словаря: make_campaign({...campaign.yaml...}, [сцены])."""
    def make(cfg: dict, scenes: list[dict], name: str = "t"):
        folder = tmp_path / name
        (folder / "scenes").mkdir(parents=True)
        base = {"id": name, "title": name, "start": scenes[0]["id"]}
        (folder / "campaign.yaml").write_text(yaml.safe_dump({**base, **cfg}, allow_unicode=True), encoding="utf-8")
        (folder / "scenes" / "s.yaml").write_text(yaml.safe_dump(scenes, allow_unicode=True), encoding="utf-8")
        return load_campaign(folder)
    return make
