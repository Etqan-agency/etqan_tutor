"""The commands behind a phase's launch, slot, stack and teardown (spec 2026-10-03 §4.2)."""

import contextlib
import threading
from pathlib import Path

from . import commands, config, sessions
from .errors import BadRequest
from .ledger_api import L, LedgerError, read, write

# Serializes a whole launch's eligibility/slot check through its ledger write, so two
# concurrent launches for the same slot cannot both pass the check before either writes.
_LAUNCH_LOCK = threading.Lock()


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
    with _LAUNCH_LOCK:
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
    recorded_worktree = data["phases"][code]["worktree"]
    # A launch the ledger never recorded (the write after launch-phase.sh never
    # happened) still left its worktree on disk: find it the same way launch does.
    worktree = recorded_worktree or str(config.wt_root() / code.lower())
    exists = Path(worktree).is_dir()
    if not recorded_worktree and not exists:
        raise BadRequest(f"{code} has no worktree")
    sid = data["phases"][code]["session"]
    if sid:
        with contextlib.suppress(commands.CommandFailed):  # already stopped or removed
            commands.run(["claude", "stop", sid], timeout=60)
    if exists:
        commands.run(commands.script("teardown-phase.sh", code), cwd=config.MAIN, timeout=900)
    # else: the worktree is already gone (a retry after a script that failed late, past
    # the point it removed the worktree) — nothing left to tear down but the ledger.
    slices = [s for s in data["slices"].values() if s["phase"] == code]
    finished = bool(slices) and all(s["status"] == "merged" for s in slices)

    def change(d):
        if finished:
            L.set_phase(d, code, status="merged", worktree=L.CLEAR, session=L.CLEAR)
        else:
            L.set_phase(d, code, status="waiting-deps", slot=0, worktree=L.CLEAR, branch=L.CLEAR, session=L.CLEAR)

    write(f"teardown {code}", change)
    return {"ok": True, "status": "merged" if finished else "waiting-deps"}
