#!/usr/bin/env python3
"""The orchestration ledger (docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md §4).

One JSON file every session edits under an exclusive file lock; after each
change LEDGER.md is re-rendered and both are committed on the
`orchestration` branch. Standard library only."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PHASES = {
    "B2": ("Scheduling depth", []),
    "B3": ("Money depth", []),
    "B4": ("Payroll depth", ["B2", "B3"]),
    "B5": ("Communication", ["B2"]),
    "B6": ("Learning", ["B2"]),
    "B7": ("Add-on sales", ["B3"]),
    "B8": ("Marketing extras", []),
    "B9": ("Platform extras", []),
    "B10": ("AI", ["B6"]),
    "B11": ("Apps", ["B2", "B3", "B4", "B5"]),
}
PRIORITY = ("B2", "B3", "B8", "B9", "B6", "B5", "B4", "B7", "B10", "B11")
SLOTS = 4
STATUSES = ("waiting-deps", "spec", "plan", "build", "review", "queued", "merged", "paused")
INACTIVE = ("waiting-deps", "merged")
SLICE_STATUSES = ("spec", "plan", "build", "review", "queued", "in-flight", "merged")
OWNERSHIP = {
    "scheduling": "B2",
    "billing": "B3",
    "catalogue.pricing": "B3",
    "payroll": "B4",
    "notifications": "B5",
    "site": "B8",
    "identity.auth": "B9",
}
ESCALATION_KINDS = (
    "money",
    "irreversible-data",
    "shared-decision",
    "queue-failures",
    "production",
    "stalled",
)
FIRST_PLAN = 15
MAX_BOUNCES = 3

# Passed for a field (CLI: the word `none`) to clear it; plain None means "leave as is".
CLEAR = object()


class LedgerError(Exception):
    """A refused change; the CLI prints it and exits 1 without writing."""


def empty() -> dict:
    return {
        "phases": {
            code: {
                "title": title,
                "status": "waiting-deps",
                "requires": list(requires),
                "slot": None,
                "worktree": None,
                "branch": None,
                "spec": None,
                "current_slice": None,
                "current_task": None,
                "session": None,
            }
            for code, (title, requires) in PHASES.items()
        },
        "slices": {},
        "next_plan_number": FIRST_PLAN,
        "ownership": dict(OWNERSHIP),
        "claims": [],
        "shared_decisions": [],
        "requests": [],
        "queue": [],
        "in_flight": None,
        "main_heads": {},
        "escalations": [],
        "conductor_session": None,
    }


def _phase(data: dict, code: str) -> dict:
    try:
        return data["phases"][code]
    except KeyError:
        raise LedgerError(f"unknown phase {code}") from None


def _slice(data: dict, sid: str) -> dict:
    try:
        return data["slices"][sid]
    except KeyError:
        raise LedgerError(f"unknown slice {sid}") from None


def _holds_slot(phase: dict) -> bool:
    """A phase keeps its slot until it merges or the conductor releases it
    (`phase <code> --slot 0`), waiting-deps included: lending is explicit."""
    return phase["slot"] is not None and phase["status"] != "merged"


def set_phase(data: dict, code: str, **fields) -> None:
    phase = _phase(data, code)
    status = fields.get("status")
    if status is not None and status not in STATUSES:
        raise LedgerError(f"unknown status {status}; one of {', '.join(STATUSES)}")
    slot = fields.pop("slot", None)
    if slot is not None:
        if not 0 <= slot <= SLOTS:
            raise LedgerError(f"slot must be 1-{SLOTS} (0 releases it)")
        for other_code, other in data["phases"].items():
            if slot and other_code != code and other["slot"] == slot and _holds_slot(other):
                raise LedgerError(f"slot {slot} is held by {other_code}")
    updated = {
        **phase,
        **{key: (None if value is CLEAR else value) for key, value in fields.items() if value is not None},
    }
    if slot is not None:
        updated["slot"] = slot or None
    if updated["status"] == "merged":
        updated["slot"] = None
    # A launched phase that gave its slot away (see CONDUCTOR.md) works again
    # only once the conductor hands it a slot: its ports may be in use.
    if (updated["worktree"] is not None and updated["slot"] is None
            and updated["status"] not in (*INACTIVE, "paused")):
        raise LedgerError(f"{code} holds no slot; the conductor assigns one (`phase {code} --slot <n>`)")
    phase.update(updated)


def add_slice(data: dict, sid: str, *, phase: str, requires: list[str]) -> None:
    _phase(data, phase)
    if not (sid.startswith(phase) and sid[len(phase):].isalpha()):
        raise LedgerError(f"slice {sid} must start with {phase} and end in letters")
    entry = data["slices"].setdefault(
        sid,
        {"phase": phase, "status": "spec", "requires": [], "plan_number": None,
         "spec": None, "plan": None, "prs": None, "bounces": 0},
    )
    if requires:
        entry["requires"] = list(requires)


def set_slice(data: dict, sid: str, **fields) -> None:
    entry = _slice(data, sid)
    status = fields.get("status")
    if status is not None and status not in SLICE_STATUSES:
        raise LedgerError(f"unknown slice status {status}")
    entry.update({key: value for key, value in fields.items() if value is not None})


def alloc_plan(data: dict, sid: str) -> int:
    entry = _slice(data, sid)
    if entry["plan_number"] is None:
        entry["plan_number"] = data["next_plan_number"]
        data["next_plan_number"] += 1
    return entry["plan_number"]


def unmet(data: dict, sid: str) -> list[str]:
    return [
        need for need in _slice(data, sid)["requires"]
        if data["slices"].get(need, {}).get("status") != "merged"
    ]


def enqueue(data: dict, sid: str) -> None:
    entry = _slice(data, sid)
    if entry["status"] == "merged":
        raise LedgerError(f"{sid} is already merged")
    if sid in data["queue"] or data["in_flight"] == sid:
        raise LedgerError(f"{sid} is already queued")
    entry["status"] = "queued"
    data["queue"].append(sid)


def take_next(data: dict) -> str | None:
    if data["in_flight"]:
        raise LedgerError(f"{data['in_flight']} is in flight")
    if not data["queue"]:
        return None
    sid = data["queue"].pop(0)
    data["in_flight"] = sid
    data["slices"][sid]["status"] = "in-flight"
    return sid


def _in_flight(data: dict, sid: str) -> dict:
    if data["in_flight"] != sid:
        raise LedgerError(f"{sid} is not in flight")
    data["in_flight"] = None
    return data["slices"][sid]


def mark_merged(data: dict, sid: str, heads: dict[str, str]) -> None:
    _in_flight(data, sid)["status"] = "merged"
    data["main_heads"].update(heads)


def bounce(data: dict, sid: str, reason: str) -> None:
    entry = _in_flight(data, sid)
    entry["status"] = "build"
    entry["bounces"] += 1
    entry["last_bounce"] = reason
    if entry["bounces"] == MAX_BOUNCES:
        escalate(data, entry["phase"], "queue-failures", f"{sid} bounced {MAX_BOUNCES} times: {reason}")


def _next_id(items: list, prefix: str) -> str:
    return f"{prefix}{len(items) + 1}"


def decide(data: dict, phase: str, text: str, affects: list[str], source: str) -> str:
    _phase(data, phase)
    did = _next_id(data["shared_decisions"], "D")
    data["shared_decisions"].append(
        {"id": did, "phase": phase, "decision": text, "affects": affects, "source": source}
    )
    return did


def claim(data: dict, phase: str, target: str, reason: str) -> None:
    _phase(data, phase)
    for held in data["claims"]:
        if held["target"] == target:
            if held["phase"] == phase:
                return
            raise LedgerError(f"{target} is claimed by {held['phase']}")
    data["claims"].append({
        "target": target,
        "phase": phase,
        "reason": reason,
        "since": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    })


def release(data: dict, phase: str, target: str) -> None:
    for held in data["claims"]:
        if held["target"] == target and held["phase"] == phase:
            data["claims"].remove(held)
            return
    raise LedgerError(f"{phase} holds no claim on {target}")


def request(data: dict, phase: str, app: str, what: str) -> str:
    _phase(data, phase)
    rid = _next_id(data["requests"], "R")
    owner = data["ownership"].get(app, "conductor")
    data["requests"].append(
        {"id": rid, "from": phase, "app": app, "to_owner": owner, "what": what, "status": "open"}
    )
    return rid


def escalate(data: dict, phase: str, kind: str, question: str) -> str:
    _phase(data, phase)
    if kind not in ESCALATION_KINDS:
        raise LedgerError(f"unknown escalation kind {kind}; one of {', '.join(ESCALATION_KINDS)}")
    eid = _next_id(data["escalations"], "E")
    data["escalations"].append(
        {"id": eid, "phase": phase, "kind": kind, "question": question,
         "status": "open", "answer": None}
    )
    return eid


def resolve(data: dict, eid: str, answer: str) -> None:
    for item in data["escalations"]:
        if item["id"] == eid:
            item.update(status="resolved", answer=answer)
            return
    raise LedgerError(f"unknown escalation {eid}")


def set_conductor_session(data: dict, session) -> None:
    data["conductor_session"] = None if session is CLEAR else session


def reorder(data: dict, sid: str, direction: str) -> None:
    """Move a queued slice one place; the in-flight slice is not in the queue."""
    if direction not in ("up", "down"):
        raise LedgerError("direction must be up or down")
    queue = data["queue"]
    if sid not in queue:
        raise LedgerError(f"{sid} is not queued")
    index = queue.index(sid)
    other = index - 1 if direction == "up" else index + 1
    if other < 0:
        raise LedgerError(f"{sid} is already first")
    if other >= len(queue):
        raise LedgerError(f"{sid} is already last")
    queue[index], queue[other] = queue[other], queue[index]


def request_done(data: dict, rid: str) -> None:
    for item in data["requests"]:
        if item["id"] == rid:
            if item["status"] == "done":
                raise LedgerError(f"{rid} is already done")
            item["status"] = "done"
            return
    raise LedgerError(f"unknown request {rid}")


def force_release(data: dict, target: str) -> None:
    """The conductor's (or the owner's) release, whoever holds the claim."""
    for held in data["claims"]:
        if held["target"] == target:
            data["claims"].remove(held)
            return
    raise LedgerError(f"no claim on {target}")


def eligible(data: dict) -> tuple[int, list[str]]:
    """Free slots, and the phases never launched (no worktree) whose
    dependencies have specs, best first. A launched phase that is waiting
    is not offered again: it is resumed in its own worktree."""
    phases = data["phases"]
    # A working phase with no slot recorded yet still occupies one; a paused
    # phase whose slot was released does not.
    held = sum(
        1 for p in phases.values()
        if _holds_slot(p) or (p["slot"] is None and p["status"] not in (*INACTIVE, "paused"))
    )
    free = max(SLOTS - held, 0)
    ready = [
        code for code in PRIORITY
        if phases[code]["status"] == "waiting-deps"
        and phases[code]["worktree"] is None
        and all(phases[need]["spec"] for need in phases[code]["requires"])
    ]
    return free, ready[:free]


def _cell(value) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value).replace("|", "\\|")


def _table(headers: list[str], rows: list[list]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    lines += ["| " + " | ".join(_cell(c) for c in row) + " |" for row in rows]
    return lines + [""]


def render(data: dict) -> str:
    out = ["# Orchestration ledger", "",
           "Generated by `scripts/orchestration/ledger.py` from `ledger.json`; never edit by hand.", "",
           f"In flight: **{data['in_flight'] or '—'}** · Queue: {', '.join(data['queue']) or '—'} · "
           f"Next plan number: {data['next_plan_number']} · "
           f"Conductor: {data.get('conductor_session') or '—'}", "", "## Phases", ""]
    out += _table(
        ["Phase", "Title", "Status", "Slot", "Slice", "Task", "Requires", "Spec", "Session"],
        [[c, p["title"], p["status"], p["slot"], p["current_slice"], p["current_task"],
          p["requires"], p["spec"], p.get("session")] for c, p in data["phases"].items()],
    )
    out += ["## Slices", ""]
    out += _table(
        ["Slice", "Phase", "Status", "Plan", "Requires", "PRs", "Bounces"],
        [[s, e["phase"], e["status"], e["plan_number"], e["requires"], e["prs"], e["bounces"]]
         for s, e in data["slices"].items()],
    )
    out += ["## Open escalations", ""]
    out += _table(["Id", "Phase", "Kind", "Question"],
                  [[e["id"], e["phase"], e["kind"], e["question"]]
                   for e in data["escalations"] if e["status"] == "open"])
    out += ["## Shared decisions", ""]
    out += _table(["Id", "Phase", "Decision", "Affects", "Source"],
                  [[d["id"], d["phase"], d["decision"], d["affects"], d["source"]]
                   for d in data["shared_decisions"]])
    out += ["## Claims and requests", ""]
    out += _table(["Target", "Phase", "Reason", "Since"],
                  [[c["target"], c["phase"], c["reason"], c["since"]] for c in data["claims"]])
    out += _table(["Id", "From", "App", "To owner", "What", "Status"],
                  [[r["id"], r["from"], r["app"], r["to_owner"], r["what"], r["status"]]
                   for r in data["requests"]])
    out += ["## Trunk heads", ""]
    out += _table(["Repo", "Commit"], [[r, h] for r, h in sorted(data["main_heads"].items())])
    return "\n".join(out)


def default_dir() -> Path:
    # Honour the same overrides the shell scripts do (bootstrap-ledger.sh,
    # launch-phase.sh), so a plain `ledger.py show` run from inside a phase
    # worktree finds the ledger that was bootstrapped for it.
    ledger_dir = os.environ.get("ETQAN_LEDGER_DIR")
    if ledger_dir:
        return Path(ledger_dir)
    wt_root = os.environ.get("ETQAN_WT_ROOT")
    if wt_root:
        return Path(wt_root) / "_ledger"
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return Path(common).parent.parent / "etqan_tutor-wt" / "_ledger"


@contextlib.contextmanager
def locked(directory: Path, *, write: bool):
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
        yield


def load(directory: Path) -> dict:
    path = directory / "orchestration" / "ledger.json"
    if not path.exists():
        raise LedgerError(f"no ledger at {path}; run `ledger.py init`")
    data = json.loads(path.read_text(encoding="utf-8"))
    # Ledgers written before the dashboard (Plan 15) lack the session fields.
    data.setdefault("conductor_session", None)
    for phase in data["phases"].values():
        phase.setdefault("session", None)
    return data


def _rollback(directory: Path, previous: dict[Path, bytes | None]) -> list[str]:
    """Best-effort restore of the working tree and index to `previous`.

    Returns a list of problems encountered (empty if the rollback was clean);
    it never raises, so a caller can always report the original failure too."""
    problems: list[str] = []
    for path, content in previous.items():
        try:
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
        except OSError as error:
            problems.append(f"restoring {path.name}: {error}")
    git = ["git", "-C", str(directory)]
    relative = [str(path.relative_to(directory)) for path in previous]
    has_head = subprocess.run(
        [*git, "rev-parse", "--verify", "-q", "HEAD"], capture_output=True
    ).returncode == 0
    if has_head:
        unstage = subprocess.run([*git, "reset", "-q", "HEAD", "--", *relative], capture_output=True, text=True)
    else:
        # Unborn branch (e.g. during `init`): nothing to reset to, just unstage.
        unstage = subprocess.run(
            [*git, "rm", "--cached", "-q", "-r", "--ignore-unmatch", *relative], capture_output=True, text=True
        )
    if unstage.returncode != 0:
        problems.append(f"unstaging: {(unstage.stderr or unstage.stdout).strip()}")
    return problems


def _fail(directory: Path, previous: dict[Path, bytes | None], original: str) -> None:
    problems = _rollback(directory, previous)
    message = f"commit failed: {original}"
    if problems:
        message += f"; rollback incomplete: {'; '.join(problems)} — inspect {directory} by hand"
    raise LedgerError(message)


def save(directory: Path, data: dict, message: str, *, source: str | None = None) -> None:
    folder = directory / "orchestration"
    folder.mkdir(exist_ok=True)
    targets = {
        folder / "ledger.json": json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        folder / "LEDGER.md": render(data) + "\n",
        directory / ".gitignore": ".lock\n",
    }
    previous = {path: (path.read_bytes() if path.exists() else None) for path in targets}
    for path, content in targets.items():
        path.write_text(content, encoding="utf-8")
    if (directory / ".git").exists():
        git = ["git", "-C", str(directory)]
        # Only the files written here: phase notes and MERGES.md are committed by
        # their authors (under the same lock), never swept into a ledger commit.
        paths = [str(path.relative_to(directory)) for path in targets]  # git -C directory
        add = subprocess.run([*git, "add", "--", *paths], capture_output=True, text=True)
        if add.returncode != 0:
            _fail(directory, previous, add.stderr.strip())
        unchanged = subprocess.run([*git, "diff", "--cached", "--quiet", "--", *paths]).returncode == 0
        if not unchanged:
            subject = f"ledger ({source}): {message}" if source else f"ledger: {message}"
            commit = subprocess.run(
                [*git, "commit", "-q", "-m", subject, "--", *paths],
                capture_output=True, text=True,
            )
            if commit.returncode != 0:
                _fail(directory, previous, (commit.stderr or commit.stdout).strip())


def _csv(value: str | None) -> list[str]:
    return [item for item in (value or "").split(",") if item]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--dir", type=Path, default=None)
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    show = sub.add_parser("show")
    show.add_argument("--json", action="store_true")
    sub.add_parser("eligible")
    ph = sub.add_parser("phase")
    ph.add_argument("code")
    for flag in ("status", "worktree", "branch", "spec", "slice", "task", "session"):
        ph.add_argument(f"--{flag}")
    ph.add_argument("--slot", type=int, help="1-4; 0 releases the slot (lending it)")
    sl = sub.add_parser("slice")
    sl.add_argument("id")
    for flag in ("phase", "requires", "status", "spec", "plan", "prs"):
        sl.add_argument(f"--{flag}")
    for name in ("alloc-plan", "ready", "queue"):
        sub.add_parser(name).add_argument("id")
    sub.add_parser("next")
    mg = sub.add_parser("merged")
    mg.add_argument("id")
    mg.add_argument("--head", action="append", default=[], help="repo=sha")
    bo = sub.add_parser("bounce")
    bo.add_argument("id")
    bo.add_argument("--reason", required=True)
    de = sub.add_parser("decide")
    de.add_argument("phase")
    de.add_argument("text")
    de.add_argument("--affects", default="")
    de.add_argument("--source", required=True)
    for name in ("claim", "release"):
        c = sub.add_parser(name)
        c.add_argument("phase")
        c.add_argument("target")
        if name == "claim":
            c.add_argument("--reason", required=True)
    rq = sub.add_parser("request")
    rq.add_argument("phase")
    rq.add_argument("app")
    rq.add_argument("text")
    es = sub.add_parser("escalate")
    es.add_argument("phase")
    es.add_argument("kind", choices=ESCALATION_KINDS)
    es.add_argument("text")
    rs = sub.add_parser("resolve")
    rs.add_argument("id")
    rs.add_argument("text")
    co = sub.add_parser("conductor")
    co.add_argument("--session", required=True)
    ro = sub.add_parser("reorder")
    ro.add_argument("id")
    ro.add_argument("direction", choices=("up", "down"))
    sub.add_parser("request-done").add_argument("id")
    sub.add_parser("release-claim").add_argument("target")
    return p


READ_ONLY = ("show", "eligible", "ready")


def _field(value):
    return CLEAR if value == "none" else value


def run(args: argparse.Namespace) -> tuple[int, str]:
    directory = args.dir or default_dir()
    write = args.command not in READ_ONLY
    with locked(directory, write=write):
        if args.command == "init":
            if (directory / "orchestration" / "ledger.json").exists():
                raise LedgerError("ledger already initialised")
            save(directory, empty(), "init")
            return 0, str(directory)
        data = load(directory)
        c = args.command
        out, message = "", c
        if c == "show":
            return 0, json.dumps(data, indent=2, ensure_ascii=False) if args.json else render(data)
        if c == "eligible":
            free, codes = eligible(data)
            return 0, "\n".join([f"free={free}", *codes])
        if c == "ready":
            missing = unmet(data, args.id)
            return (1 if missing else 0), "\n".join(missing)
        if c == "phase":
            set_phase(data, args.code, status=args.status, slot=args.slot, worktree=_field(args.worktree),
                      branch=_field(args.branch), spec=args.spec, current_slice=args.slice,
                      current_task=args.task, session=_field(args.session))
            message = f"phase {args.code}"
        elif c == "slice":
            if args.id not in data["slices"]:
                if not args.phase:
                    raise LedgerError(f"new slice {args.id} needs --phase")
                add_slice(data, args.id, phase=args.phase, requires=_csv(args.requires))
            elif args.requires:
                data["slices"][args.id]["requires"] = _csv(args.requires)
            set_slice(data, args.id, status=args.status, spec=args.spec, plan=args.plan, prs=args.prs)
            message = f"slice {args.id}"
        elif c == "alloc-plan":
            out = str(alloc_plan(data, args.id))
            message = f"plan {out} for {args.id}"
        elif c == "queue":
            enqueue(data, args.id)
            message = f"queue {args.id}"
        elif c == "next":
            out = take_next(data) or ""
            if not out:
                return 0, ""
            message = f"in flight {out}"
        elif c == "merged":
            heads = dict(item.split("=", 1) for item in args.head)
            mark_merged(data, args.id, heads)
            message = f"merged {args.id}"
        elif c == "bounce":
            bounce(data, args.id, args.reason)
            message = f"bounce {args.id}"
        elif c == "decide":
            out = decide(data, args.phase, args.text, _csv(args.affects), args.source)
            message = f"decision {out}"
        elif c == "claim":
            claim(data, args.phase, args.target, args.reason)
            message = f"claim {args.target} for {args.phase}"
        elif c == "release":
            release(data, args.phase, args.target)
            message = f"release {args.target}"
        elif c == "request":
            out = request(data, args.phase, args.app, args.text)
            message = f"request {out}"
        elif c == "escalate":
            out = escalate(data, args.phase, args.kind, args.text)
            message = f"escalation {out}"
        elif c == "resolve":
            resolve(data, args.id, args.text)
            message = f"resolve {args.id}"
        elif c == "conductor":
            set_conductor_session(data, _field(args.session))
            message = "conductor session"
        elif c == "reorder":
            reorder(data, args.id, args.direction)
            message = f"reorder {args.id} {args.direction}"
        elif c == "request-done":
            request_done(data, args.id)
            message = f"request {args.id} done"
        elif c == "release-claim":
            force_release(data, args.target)
            message = f"release {args.target} (forced)"
        save(directory, data, message)
        return 0, out


def main(argv: list[str] | None = None) -> int:
    try:
        code, out = run(parser().parse_args(argv))
    except LedgerError as error:
        print(f"ledger: {error}", file=sys.stderr)
        return 1
    if out:
        print(out)
    return code


if __name__ == "__main__":
    sys.exit(main())
