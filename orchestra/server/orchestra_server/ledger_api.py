"""Every ledger read and write goes through scripts/orchestration/ledger.py itself,
under its lock, so the dashboard and the sessions follow one set of rules."""

import sys
from collections.abc import Callable
from typing import Any

from . import config

if str(config.SCRIPTS) not in sys.path:
    sys.path.insert(0, str(config.SCRIPTS))

import ledger as L  # noqa: E402

LedgerError = L.LedgerError
SOURCE = "orchestra"


def read() -> dict:
    directory = L.default_dir()
    with L.locked(directory, write=False):
        return L.load(directory)


def write(message: str, change: Callable[[dict], Any]) -> Any:
    """Load, change and commit under one exclusive lock: no lost updates."""
    directory = L.default_dir()
    with L.locked(directory, write=True):
        data = L.load(directory)
        result = change(data)
        L.save(directory, data, message, source=SOURCE)
        return result
