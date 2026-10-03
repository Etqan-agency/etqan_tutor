"""Every input is checked before anything runs (spec 2026-10-03 §4.1)."""

import re

from .errors import BadRequest
from .ledger_api import L

MODES = ("auto", "acceptEdits", "manual", "plan", "dontAsk")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
_SLICE = re.compile(r"^B\d+[a-z]+$")
_SUFFIX = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_MODEL = re.compile(r"^[a-z0-9][a-z0-9.-]*$")
_SHA = re.compile(r"^[0-9a-f]{7,40}$")
_REPO = re.compile(r"^[a-z0-9_-]+$")
MAX_TEXT = 4000


def phase(code) -> str:
    if not isinstance(code, str) or code not in L.PHASES:
        raise BadRequest(f"unknown phase {code}")
    return code


def who(value) -> str:
    return "conductor" if value == "conductor" else phase(value)


def slot(value, *, allow_zero: bool = False) -> int:
    low = 0 if allow_zero else 1
    if not isinstance(value, int) or isinstance(value, bool) or not low <= value <= L.SLOTS:
        raise BadRequest(f"slot must be {low}-{L.SLOTS}")
    return value


def slice_id(value) -> str:
    if not isinstance(value, str) or not _SLICE.match(value):
        raise BadRequest(f"not a slice id: {value}")
    return value


def suffix(value) -> str:
    if not isinstance(value, str) or not _SUFFIX.match(value) or len(value) > 60:
        raise BadRequest(f"not a branch suffix: {value}")
    return value


def mode(value) -> str:
    value = value or "auto"
    if not isinstance(value, str) or value not in MODES:
        raise BadRequest(f"mode must be one of {', '.join(MODES)}")
    return value


def model(value) -> str | None:
    if value in (None, ""):
        return None
    if not isinstance(value, str) or not _MODEL.match(value):
        raise BadRequest(f"not a model id: {value}")
    return value


def effort(value) -> str | None:
    if value in (None, ""):
        return None
    if not isinstance(value, str) or value not in EFFORTS:
        raise BadRequest(f"effort must be one of {', '.join(EFFORTS)}")
    return value


def status(value) -> str:
    if not isinstance(value, str) or value not in L.STATUSES:
        raise BadRequest(f"status must be one of {', '.join(L.STATUSES)}")
    return value


def text(value, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise BadRequest(f"{name} is required")
    if len(value) > MAX_TEXT:
        raise BadRequest(f"{name} is longer than {MAX_TEXT} characters")
    return value.strip()


def direction(value) -> str:
    if not isinstance(value, str) or value not in ("up", "down"):
        raise BadRequest("direction must be up or down")
    return value


def heads(value) -> dict[str, str]:
    if not isinstance(value, dict) or not value:
        raise BadRequest("heads must map repo to commit")
    for repo, sha in value.items():
        if not isinstance(repo, str) or not _REPO.match(repo) or not isinstance(sha, str) or not _SHA.match(sha):
            raise BadRequest(f"bad head {repo}={sha}")
    return value


def phases(value) -> list[str]:
    if not isinstance(value, list):
        raise BadRequest("affects must be a list of phases")
    return [phase(code) for code in value]
