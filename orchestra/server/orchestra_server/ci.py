"""CI as `gh` reports it, cached for a minute (spec 2026-10-03 §4.2)."""

import json
import re
import threading
import time

from . import commands, config

CACHE_SECONDS = 60
PR = re.compile(r"https://github\.com/([\w.-]+/[\w.-]+)/pull/(\d+)")
_cache: dict = {"at": 0.0, "value": None}
_lock = threading.Lock()


def clear_cache() -> None:
    with _lock:
        _cache.update(at=0.0, value=None)


def _gh(argv: list[str], *, ok_codes=(0,)):
    try:
        return json.loads(commands.run(argv, timeout=60, ok_codes=ok_codes))
    except commands.CommandFailed as error:
        return {"error": error.payload["output_tail"] or f"exit {error.payload['exit_code']}"}
    except ValueError:
        return {"error": "gh printed something that is not JSON"}


def collect(data: dict) -> dict:
    runs = _gh(
        [
            "gh",
            "run",
            "list",
            "-R",
            config.repo(),
            "--branch",
            "master",
            "--workflow",
            "CI",
            "--limit",
            "1",
            "--json",
            "databaseId,status,conclusion,headSha,url,createdAt",
        ]
    )
    master = runs[0] if isinstance(runs, list) and runs else (runs if isinstance(runs, dict) else None)
    prs = []
    for sid, entry in data["slices"].items():
        if entry["status"] == "merged":
            continue
        for repo, number in PR.findall(entry.get("prs") or ""):
            # `gh pr checks` exits 8 while checks are pending; its JSON is still complete.
            checks = _gh(
                ["gh", "pr", "checks", number, "-R", repo, "--json", "name,state,bucket,link"], ok_codes=(0, 8)
            )
            prs.append(
                {
                    "slice": sid,
                    "repo": repo,
                    "number": int(number),
                    "url": f"https://github.com/{repo}/pull/{number}",
                    "checks": checks,
                }
            )
    return {"master": master, "prs": prs}


def cached(data: dict) -> dict:
    with _lock:
        if _cache["value"] is not None and time.monotonic() - _cache["at"] < CACHE_SECONDS:
            return _cache["value"]
    value = collect(data)
    with _lock:
        _cache.update(at=time.monotonic(), value=value)
    return value
