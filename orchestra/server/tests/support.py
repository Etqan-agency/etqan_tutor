"""A real server on a free port against a throwaway ledger repo (spec 2026-10-03 §6)."""

import http.client
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

SERVER_ROOT = Path(__file__).resolve().parents[1]
if str(SERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_ROOT))

from orchestra_server import app, ledger_api  # noqa: E402
from tests import fakes  # noqa: E402


class ServerCase(unittest.TestCase):
    token = "test-token"  # noqa: S105
    extra_env: dict = {}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.ledger_dir = self.base / "ledger"
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.ledger_dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.ledger_dir), "config", key, value], check=True)
        (self.base / "dist").mkdir()
        # Fakes always: no test ever reaches the real claude, docker, gh or scripts.
        self.agents_file = self.base / "agents.json"
        self.agents_file.write_text("[]")
        env = {
            **fakes.install(self.base),
            "FAKE_AGENTS": str(self.agents_file),
            "ETQAN_LEDGER_DIR": str(self.ledger_dir),
            "ETQAN_WT_ROOT": str(self.base / "wt"),
            "ORCHESTRA_WEB_DIST": str(self.base / "dist"),
            "ORCHESTRA_POLL": "0.1",
            **self.extra_env,
        }
        self.env_values = env
        self.env = mock.patch.dict(os.environ, env)
        self.env.start()
        ledger_api.L.save(self.ledger_dir, ledger_api.L.empty(), "init")
        self.server = app.make_server(0, self.token)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.env.stop()
        self.tmp.cleanup()

    def request(self, method, path, body=None, *, headers=None, token=True):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        sent = {"Host": f"127.0.0.1:{self.port}"}
        if token and method != "GET":
            sent["X-Orchestra-Token"] = self.token
        payload = None
        if body is not None:
            sent["Content-Type"] = "application/json"
            payload = body if isinstance(body, (bytes, str)) else json.dumps(body)
        sent.update(headers or {})
        conn.request(method, path, body=payload, headers=sent)
        response = conn.getresponse()
        raw = response.read()
        conn.close()
        try:
            data = json.loads(raw)
        except ValueError:
            data = raw.decode(errors="replace")
        return response.status, data

    def ledger(self):
        return ledger_api.read()

    def change_ledger(self, change):
        return ledger_api.write("test setup", change)

    def last_subject(self):
        return subprocess.run(
            ["git", "-C", str(self.ledger_dir), "log", "-1", "--format=%s"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
