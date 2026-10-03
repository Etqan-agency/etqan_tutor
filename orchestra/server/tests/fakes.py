"""Fake claude/just/docker and fake orchestration scripts on PATH. Each records
{"cmd", "cwd", "argv"} as one JSON line in $FAKE_LOG and answers from env:
FAKE_FAIL=<cmd> (exit 3, 'boom' + 200 lines), FAKE_WARN=<cmd> (a stderr warning line
on an otherwise-successful run), FAKE_AGENTS (a file of JSON), FAKE_ID (the id
claude --bg / start-session print), FAKE_LOGS (a file of log text), FAKE_DOCKER
(lines `docker ps` prints)."""

import json
import os
import stat
from pathlib import Path

FAKE = r"""#!/usr/bin/env python3
import json, os, sys
name, args = os.path.basename(sys.argv[0]), sys.argv[1:]
if name == "bash":  # the scripts are run as `bash <script> args…`: recorded as the script
    name, args = os.path.basename(args[0]), args[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write(json.dumps({"cmd": name, "cwd": os.getcwd(), "argv": sys.argv[1:]}) + "\n")
if os.environ.get("FAKE_FAIL") == name:
    print("\n".join(f"line {n}" for n in range(200)))
    print("boom", file=sys.stderr)
    sys.exit(3)
if os.environ.get("FAKE_WARN") == name:
    print("warning: heads up", file=sys.stderr)
if name == "claude" and args[:1] == ["agents"]:
    path = os.environ.get("FAKE_AGENTS")
    print(open(path).read() if path and os.path.exists(path) else "[]")
elif name == "claude" and args[:1] == ["logs"]:
    path = os.environ.get("FAKE_LOGS")
    print(open(path).read() if path else "")
elif name == "claude" and "--bg" in args:
    # --resume without --name/--permission-mode continues the session under its own
    # saved name, idle until prompted; with --name it is the launch/start-session path.
    label = args[args.index("--name") + 1] if "--name" in args else "resumed (idle — send a prompt to start)"
    print(f"backgrounded · {os.environ.get('FAKE_ID', 'ab12cd34')} · {label}")
elif name == "start-session.sh":
    print(os.environ.get("FAKE_ID", "ab12cd34"))
elif name == "docker":
    print(os.environ.get("FAKE_DOCKER", ""))
"""


def install(base: Path) -> dict:
    """Create the fakes under `base`; return the env to apply."""
    bin_dir = base / "bin"
    scripts = base / "scripts"
    bin_dir.mkdir()
    scripts.mkdir()
    for directory, names in (
        (bin_dir, ("claude", "just", "docker", "gh", "bash")),
        (scripts, ("launch-phase.sh", "teardown-phase.sh", "stream-env.sh", "start-session.sh")),
    ):
        for name in names:
            path = directory / name
            path.write_text(FAKE)
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "ORCHESTRA_SCRIPTS": str(scripts),
        "FAKE_LOG": str(base / "fake.log"),
    }


def calls(base: Path) -> list[dict]:
    log = base / "fake.log"
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text().splitlines()]
