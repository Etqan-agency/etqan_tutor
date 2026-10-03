"""Server-sent events: one poller notices ledger commits and session changes and
tells every open page (spec 2026-10-03 §4.2)."""

import contextlib
import hashlib
import json
import queue
import threading
import time
from pathlib import Path

from . import commands, config, sessions
from .ledger_api import L

SESSIONS_EVERY = 2.5  # × the poll interval (2 s → 5 s)
GIT_TIMEOUT = 10  # seconds — a stuck `git` (e.g. another process's lock) must not wedge the poller


def _ledger_head(directory: Path) -> str:
    return commands.run(["git", "-C", str(directory), "rev-parse", "HEAD"], timeout=GIT_TIMEOUT).strip()


def _sessions_digest() -> str:
    return hashlib.sha256(json.dumps(sessions.agents(), sort_keys=True).encode()).hexdigest()


class Hub:
    def __init__(self):
        self._subscribers: set[queue.Queue] = set()
        self._lock = threading.Lock()
        self._poller: threading.Thread | None = None

    def subscribe(self) -> queue.Queue:
        q: queue.Queue = queue.Queue(maxsize=100)
        with self._lock:
            self._subscribers.add(q)
            if self._poller is None or not self._poller.is_alive():
                self._poller = threading.Thread(target=self._poll, daemon=True)
                self._poller.start()
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        with self._lock:
            self._subscribers.discard(q)

    def clear(self) -> None:
        """Tests only: forget every subscriber and the poller itself, so the next
        `subscribe()` always starts a fresh poller bound to the current test's ledger,
        rather than reusing one still polling a prior test's already-torn-down directory
        (a stale SSE client's handler thread can otherwise keep a queue — and so the old
        poller — alive for up to `PING_SECONDS` after the test that opened it ends)."""
        with self._lock:
            self._subscribers.clear()
            self._poller = None

    def publish(self, event: str) -> None:
        with self._lock:
            subscribers = list(self._subscribers)
        for q in subscribers:
            with contextlib.suppress(queue.Full):
                q.put_nowait(event)

    def _poll(self) -> None:
        # Resolved once per poller start (not every cycle): cheap, and keeps a transient
        # failure of `L.default_dir()` itself from being retried every poll interval.
        directory = L.default_dir()
        try:
            head = _ledger_head(directory)
        except Exception:  # noqa: BLE001 — an unreachable baseline just means the first cycle refreshes once
            head = ""
        digest, next_sessions = _sessions_digest(), 0.0
        while True:
            with self._lock:
                if not self._subscribers:
                    self._poller = None
                    return
            time.sleep(config.poll_seconds())
            try:
                now_head = _ledger_head(directory)
                if now_head != head:
                    head = now_head
                    self.publish("ledger")
                if time.monotonic() >= next_sessions:
                    next_sessions = time.monotonic() + config.poll_seconds() * SESSIONS_EVERY
                    now_digest = _sessions_digest()
                    if now_digest != digest:
                        digest = now_digest
                        self.publish("sessions")
            except Exception:  # noqa: BLE001, S112 — a transient git/claude failure must not kill the
                # poller; skip this cycle, keep the previous head/digest, and retry next interval.
                continue


HUB = Hub()
