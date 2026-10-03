"""The commands behind a phase's launch, slot, stack and teardown (spec 2026-10-03 §4.2)."""

import contextlib

from . import commands, config, sessions
from .errors import BadRequest
from .ledger_api import L, LedgerError, read, write


def _worktree(data: dict, code: str) -> str:
    worktree = data["phases"][code]["worktree"]
    if not worktree:
        raise BadRequest(f"{code} has no worktree")
    return worktree


def _slot_holder(data: dict, code: str, slot: int) -> str | None:
    for other, phase in data["phases"].items():
        if other != code and phase["slot"] == slot and phase["status"] != "merged":
            return other
    return None


def launch(code: str, suffix: str, slot: int, mode: str) -> dict:
    data = read()
    if code not in L.eligible(data)[1]:
        raise LedgerError(f"{code} is not eligible to launch")
    holder = _slot_holder(data, code, slot)
    if holder:
        raise LedgerError(f"slot {slot} is held by {holder}")
    commands.run(commands.script("launch-phase.sh", code, suffix, str(slot)), cwd=config.MAIN, timeout=900)
    worktree = str(config.wt_root() / code.lower())
    write(
        f"launch {code}",
        lambda d: L.set_phase(d, code, status="spec", slot=slot, worktree=worktree, branch=f"feat/{suffix}"),
    )
    return {"ok": True, "worktree": worktree, "session": sessions.start(code, mode)}


def move_slot(code: str, slot: int) -> dict:
    data = read()
    worktree = _worktree(data, code)
    if slot == 0:
        commands.run(["just", "stop"], cwd=worktree)
        write(f"phase {code} releases its slot", lambda d: L.set_phase(d, code, slot=0, status="paused"))
        return {"ok": True}
    holder = _slot_holder(data, code, slot)
    if holder:
        raise LedgerError(f"slot {slot} is held by {holder}")
    commands.run(["just", "stop"], cwd=worktree)
    write(f"phase {code} to slot {slot}", lambda d: L.set_phase(d, code, slot=slot))
    commands.run(commands.script("stream-env.sh", code.lower(), str(slot), worktree))
    commands.run(["just", "dev-backend"], cwd=worktree)
    return {"ok": True}


def stack(code: str, up: bool) -> dict:
    worktree = _worktree(read(), code)
    commands.run(["just", "dev-backend"] if up else ["just", "stop"], cwd=worktree)
    return {"ok": True}


def teardown(code: str, confirm) -> dict:
    if confirm != code:
        raise BadRequest(f"type {code} to confirm")
    data = read()
    _worktree(data, code)
    sid = data["phases"][code]["session"]
    if sid:
        with contextlib.suppress(commands.CommandFailed):  # already stopped or removed
            commands.run(["claude", "stop", sid], timeout=60)
    commands.run(commands.script("teardown-phase.sh", code), cwd=config.MAIN, timeout=900)
    slices = [s for s in data["slices"].values() if s["phase"] == code]
    finished = bool(slices) and all(s["status"] == "merged" for s in slices)

    def change(d):
        if finished:
            L.set_phase(d, code, status="merged", worktree=L.CLEAR, session=L.CLEAR)
        else:
            L.set_phase(d, code, status="waiting-deps", slot=0, worktree=L.CLEAR, branch=L.CLEAR, session=L.CLEAR)

    write(f"teardown {code}", change)
    return {"ok": True, "status": "merged" if finished else "waiting-deps"}
