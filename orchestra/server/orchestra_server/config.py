"""Where things are (spec 2026-10-03 §3). Functions, so tests can point them elsewhere."""

import os
from pathlib import Path

MAIN = Path(__file__).resolve().parents[3]  # the meta checkout
SCRIPTS = MAIN / "scripts" / "orchestration"  # ledger.py is imported from here, always


def scripts() -> Path:
    """The scripts the server runs (tests substitute fakes)."""
    return Path(os.environ.get("ORCHESTRA_SCRIPTS", SCRIPTS))


def web_dist() -> Path:
    return Path(os.environ.get("ORCHESTRA_WEB_DIST", MAIN / "orchestra" / "web" / "dist"))


def wt_root() -> Path:
    return Path(os.environ.get("ETQAN_WT_ROOT", MAIN.parent / "etqan_tutor-wt"))


def repo() -> str:
    return os.environ.get("ORCHESTRA_REPO", "Etqan-agency/etqan_tutor")


def port() -> int:
    return int(os.environ.get("ORCHESTRA_PORT", "7700"))


def poll_seconds() -> float:
    return float(os.environ.get("ORCHESTRA_POLL", "2"))


def dev() -> bool:
    return os.environ.get("ORCHESTRA_DEV") == "1"
