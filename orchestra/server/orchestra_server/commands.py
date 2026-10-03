"""Every subprocess the server runs: an argv list from a fixed template, never a
shell (spec 2026-10-03 §4.1); a failure carries its last 50 lines to the page."""

import subprocess
from pathlib import Path

from . import config
from .errors import HttpError

TAIL_LINES = 50
MAX_OUTPUT = 2_000_000  # characters kept from a command's output


class CommandFailed(HttpError):
    def __init__(self, argv: list[str], exit_code: int, output_tail: str):
        super().__init__(500, {"ok": False, "exit_code": exit_code, "output_tail": output_tail})
        self.argv = argv


def _text(value) -> str:
    if value is None:
        return ""
    return value.decode(errors="replace") if isinstance(value, bytes) else value


def tail(text: str, lines: int = TAIL_LINES) -> str:
    return "\n".join(text[-MAX_OUTPUT:].splitlines()[-lines:])


def run(
    argv: list[str], *, cwd: Path | str | None = None, timeout: float = 1800, ok_codes: tuple[int, ...] = (0,)
) -> str:
    try:
        proc = subprocess.run(
            argv, cwd=cwd, capture_output=True, text=True, errors="replace", timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired as error:
        output = _text(error.stdout) + _text(error.stderr)
        raise CommandFailed(argv, -1, tail(f"{output}\n(timed out after {timeout:.0f}s)")) from None
    except FileNotFoundError:
        raise CommandFailed(argv, 127, f"{argv[0]}: not found") from None
    output = (proc.stdout or "")[-MAX_OUTPUT:] + (proc.stderr or "")[-MAX_OUTPUT:]
    if proc.returncode not in ok_codes:
        raise CommandFailed(argv, proc.returncode, tail(output))
    return output


def script(name: str, *args: str) -> list[str]:
    return ["bash", str(config.scripts() / name), *args]
