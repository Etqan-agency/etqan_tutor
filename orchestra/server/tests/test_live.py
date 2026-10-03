"""Server-sent events and CI (spec 2026-10-03 §4.2)."""

import http.client
import json
import os
import threading
import time

from orchestra_server import ci
from orchestra_server.ledger_api import L
from tests import fakes
from tests.support import ServerCase


class LiveCase(ServerCase):
    def setUp(self):
        super().setUp()
        ci.clear_cache()

    def wait_for(self, event, trigger, timeout=10):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
        conn.request("GET", "/api/events", headers={"Host": f"127.0.0.1:{self.port}"})
        response = conn.getresponse()
        self.assertEqual(response.getheader("Content-Type"), "text/event-stream")
        self.assertEqual(response.fp.readline(), b": connected\n")
        threading.Timer(0.5, trigger).start()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = response.fp.readline().decode()
            if line == f"event: {event}\n":
                conn.close()
                return True
        conn.close()
        return False


class Events(LiveCase):
    def test_security_headers_are_sent(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/api/events", headers={"Host": f"127.0.0.1:{self.port}"})
        response = conn.getresponse()
        self.assertEqual(response.getheader("X-Frame-Options"), "DENY")
        conn.close()

    def test_a_ledger_commit_is_pushed(self):
        self.assertTrue(
            self.wait_for("ledger", lambda: self.change_ledger(lambda d: L.set_phase(d, "B2", status="paused")))
        )

    def test_a_session_change_is_pushed(self):
        agent = [{"id": "aa", "name": "etqan-B2", "kind": "background", "pid": 1, "state": "running"}]
        self.assertTrue(self.wait_for("sessions", lambda: self.agents_file.write_text(json.dumps(agent))))


class Ci(LiveCase):
    def write_gh(self, run_list, checks, checks_exit=0):
        gh = self.base / "bin" / "gh"
        gh.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "entry = {'cmd': 'gh', 'cwd': os.getcwd(), 'argv': sys.argv[1:]}\n"
            "open(os.environ['FAKE_LOG'], 'a').write(json.dumps(entry) + '\\n')\n"
            f"if sys.argv[1:3] == ['run', 'list']: print({json.dumps(json.dumps(run_list))})\n"
            f"else:\n    print({json.dumps(json.dumps(checks))}); sys.exit({checks_exit})\n"
        )

    def test_master_and_pr_checks_with_pending_exit_8(self):
        run = [{"status": "completed", "conclusion": "success", "headSha": "abc", "url": "u", "createdAt": "t"}]
        checks = [{"name": "e2e", "state": "PENDING", "bucket": "pending", "link": "l"}]
        self.write_gh(run, checks, checks_exit=8)
        self.change_ledger(
            lambda d: (
                L.add_slice(d, "B3a", phase="B3", requires=[]),
                L.set_slice(d, "B3a", prs="https://github.com/Etqan-agency/etqan_tutor/pull/9"),
            )
        )
        status, data = self.request("GET", "/api/ci")
        self.assertEqual(status, 200)
        self.assertEqual(data["master"]["conclusion"], "success")
        self.assertEqual(
            data["prs"],
            [
                {
                    "slice": "B3a",
                    "repo": "Etqan-agency/etqan_tutor",
                    "number": 9,
                    "url": "https://github.com/Etqan-agency/etqan_tutor/pull/9",
                    "checks": checks,
                }
            ],
        )
        before = len(fakes.calls(self.base))
        self.request("GET", "/api/ci")
        self.assertEqual(len(fakes.calls(self.base)), before)  # cached

    def test_gh_failing_is_reported_not_a_500(self):
        os.environ["FAKE_FAIL"] = "gh"
        status, data = self.request("GET", "/api/ci")
        self.assertEqual(status, 200)
        self.assertIn("error", data["master"])
