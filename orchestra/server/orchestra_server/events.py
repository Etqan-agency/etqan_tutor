"""Server-sent events: one poller notices ledger commits and session changes and
tells every open page (spec 2026-10-03 §4.2)."""

import contextlib
import hashlib
import json
import queue
import subprocess
import threading
import time

from . import config, sessions
from .ledger_api import L

SESSIONS_EVERY = 2.5  # × the poll interval (2 s → 5 s)


def _ledger_head() -> str:
    proc = subprocess.run(
        ["git", "-C", str(L.default_dir()), "rev-parse", "HEAD"], capture_output=True, text=True, check=False
    )
    return proc.stdout.strip()


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

    def publish(self, event: str) -> None:
        with self._lock:
            subscribers = list(self._subscribers)
        for q in subscribers:
            with contextlib.suppress(queue.Full):
                q.put_nowait(event)

    def _poll(self) -> None:
        head, digest, next_sessions = _ledger_head(), _sessions_digest(), 0.0
        while True:
            with self._lock:
                if not self._subscribers:
                    self._poller = None
                    return
            time.sleep(config.poll_seconds())
            now_head = _ledger_head()
            if now_head != head:
                head = now_head
                self.publish("ledger")
            if time.monotonic() >= next_sessions:
                next_sessions = time.monotonic() + config.poll_seconds() * SESSIONS_EVERY
                now_digest = _sessions_digest()
                if now_digest != digest:
                    digest = now_digest
                    self.publish("sessions")


HUB = Hub()
