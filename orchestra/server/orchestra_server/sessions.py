"""Claude Code background sessions (spec 2026-10-03 §4.3): reconcile the ledger with
`claude agents --json --all`, start through start-session.sh, stop, restart, logs."""

import json
import re
from pathlib import Path

from . import commands, config
from .errors import BadRequest
from .ledger_api import L, LedgerError, read, write

ID = re.compile(r"backgrounded · ([0-9a-f]+) · ")
ENDED = ("done", "stopped", "exited", "failed", "killed")
LOG_CHARS = 200_000
AGENTS_ARGV = ["claude", "agents", "--json", "--all"]
RESUME_PROMPT = (
    "Continue your orchestration work from where you left off: re-read the ledger "
    "(python3 scripts/orchestration/ledger.py show) and your notes first."
)


def name_of(who: str) -> str:
    return "etqan-conductor" if who == "conductor" else f"etqan-{who}"


def recorded(data: dict, who: str) -> str | None:
    return data.get("conductor_session") if who == "conductor" else data["phases"][who].get("session")


def agents(*, strict: bool = False) -> list[dict]:
    """The running/recent background agents. Lenient (the default, for the page's GET
    snapshot): any failure or bad output is an empty list. Strict (for a mutation that
    must not risk a duplicate session): a failure raises CommandFailed instead."""
    try:
        output = commands.run(AGENTS_ARGV, timeout=30)
    except commands.CommandFailed:
        if strict:
            raise
        return []
    try:
        items = json.loads(output)
    except ValueError:
        if strict:
            raise commands.CommandFailed(AGENTS_ARGV, 0, commands.tail(output)) from None
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
        # No recorded agent, or the recorded one has exited: a live same-named session —
        # started by hand, or recorded elsewhere — replaces it rather than showing stale.
        if (agent is None or _state(agent) == "exited") and name_of(who) in live_by_name:
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
    name = name_of(who)
    live = next((a for a in agents(strict=True) if a.get("name") == name and _state(a) != "exited"), None)
    if live:
        raise LedgerError(f"{name} is already running as {live['id']}; use Restart")
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
    """Respawn the recorded session if it is live; else adopt a live same-named session
    someone started by hand (never resume or start fresh while one is already running);
    else resume an exited one that still has a sessionId, or start fresh. Uses strict
    `agents()`: a `claude agents` failure is a 500, never a silent fall-through to a
    second session."""
    sid = recorded(read(), who)
    items = agents(strict=True)
    by_id = {a["id"]: a for a in items}
    agent = by_id.get(sid) if sid else None
    if agent and _state(agent) != "exited":
        commands.run(["claude", "respawn", sid], timeout=120)  # respawn keeps the session's own mode
        return sid
    name = name_of(who)
    live = next((a for a in items if a.get("name") == name and _state(a) != "exited"), None)
    if live:
        record(who, live["id"])
        commands.run(["claude", "respawn", live["id"]], timeout=120)
        return live["id"]
    if agent and agent.get("sessionId") and agent.get("cwd"):
        # `--resume` alone continues the session under its own saved name and permission
        # mode. Passing --name/--permission-mode here does NOT resume it: the session
        # keeps its own saved options, so those flags would start an idle COPY under a
        # new id instead (confirmed against the real CLI).
        argv = ["claude", "--bg", "--resume", agent["sessionId"], RESUME_PROMPT]
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
