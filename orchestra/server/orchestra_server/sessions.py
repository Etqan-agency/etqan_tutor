"""Claude Code background sessions (spec 2026-10-03 §4.3): reconcile the ledger with
`claude agents --json --all`, start through start-session.sh, stop, restart, logs."""

import json
import re
from pathlib import Path

from . import commands, config
from .errors import BadRequest
from .ledger_api import L, read, write

ID = re.compile(r"backgrounded · ([0-9a-f]+) · ")
ENDED = ("done", "stopped", "exited", "failed", "killed")
LOG_CHARS = 200_000


def name_of(who: str) -> str:
    return "etqan-conductor" if who == "conductor" else f"etqan-{who}"


def recorded(data: dict, who: str) -> str | None:
    return data.get("conductor_session") if who == "conductor" else data["phases"][who].get("session")


def agents() -> list[dict]:
    try:
        output = commands.run(["claude", "agents", "--json", "--all"], timeout=30)
        items = json.loads(output)
    except (commands.CommandFailed, ValueError):
        return []
    return [a for a in items if isinstance(a, dict) and a.get("kind") == "background" and a.get("id")]


def _state(agent: dict) -> str:
    if agent.get("state") in ENDED or "pid" not in agent:
        return "exited"
    return "busy" if agent.get("status") == "busy" else "idle"


def reconcile(data: dict, items: list[dict]) -> tuple[dict, dict]:
    """Each session's view, and running `etqan-<who>` sessions the ledger has no id for."""
    by_id = {a["id"]: a for a in items}
    live_by_name = {a.get("name"): a for a in items if _state(a) != "exited"}
    view, adopt = {}, {}
    for who in [*data["phases"], "conductor"]:
        sid = recorded(data, who)
        agent = by_id.get(sid) if sid else None
        if agent is None and not sid and name_of(who) in live_by_name:
            agent = live_by_name[name_of(who)]
            adopt[who] = agent["id"]
        if agent is None:
            view[who] = {"id": sid, "state": "gone" if sid else "none"}
        else:
            view[who] = {
                "id": agent["id"],
                "session_id": agent.get("sessionId"),
                "state": _state(agent),
                "cwd": agent.get("cwd"),
            }
    return view, adopt


def record(who: str, session) -> None:
    def change(data):
        if who == "conductor":
            L.set_conductor_session(data, session)
        else:
            L.set_phase(data, who, session=session)

    shown = "cleared" if session is L.CLEAR else session
    write(f"session {who} {shown}", change)


def snapshot() -> dict:
    view, adopt = reconcile(read(), agents())
    for who, sid in adopt.items():
        record(who, sid)
    return view


def start(who: str, mode: str, model: str | None = None, effort: str | None = None) -> str:
    argv = commands.script("start-session.sh", who, "--mode", mode)
    if model:
        argv += ["--model", model]
    if effort:
        argv += ["--effort", effort]
    output = commands.run(argv, cwd=config.MAIN, timeout=120)
    return output.strip().splitlines()[-1]


def stop(who: str) -> None:
    sid = recorded(read(), who)
    if not sid:
        raise BadRequest(f"{who} has no session")
    commands.run(["claude", "stop", sid], timeout=60)


def restart(who: str, mode: str) -> str:
    sid = recorded(read(), who)
    agent = next((a for a in agents() if a["id"] == sid), None) if sid else None
    if agent and _state(agent) != "exited":
        commands.run(["claude", "respawn", sid], timeout=120)
        return sid
    if agent and agent.get("sessionId") and agent.get("cwd"):
        argv = ["claude", "--bg", "--resume", agent["sessionId"], "--name", name_of(who), "--permission-mode", mode]
        output = commands.run(argv, cwd=Path(agent["cwd"]), timeout=120)
        match = ID.search(output)
        if not match:
            raise commands.CommandFailed(argv, 0, commands.tail(output))
        record(who, match.group(1))
        return match.group(1)
    return start(who, mode)


def log(who: str) -> str:
    sid = recorded(read(), who)
    if not sid:
        return ""
    try:
        return commands.run(["claude", "logs", sid], timeout=30)[-LOG_CHARS:]
    except commands.CommandFailed as error:
        return error.payload["output_tail"]


def stacks(data: dict) -> dict[str, bool]:
    """Which launched phases have containers up (their compose project etqan-<code>)."""
    launched = [code for code, p in data["phases"].items() if p["worktree"]]
    if not launched:
        return {}
    try:
        output = commands.run(["docker", "ps", "--format", '{{.Label "com.docker.compose.project"}}'], timeout=30)
    except commands.CommandFailed:
        return {}
    projects = set(output.split())
    return {code: f"etqan-{code.lower()}" in projects for code in launched}
