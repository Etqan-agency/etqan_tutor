"""Server-sent events and CI (spec 2026-10-03 §4.2)."""

import http.client
import json
import os
import threading
import time
from unittest import mock

from orchestra_server import ci, events
from orchestra_server.ledger_api import L
from tests import fakes
from tests.support import ServerCase


class LiveCase(ServerCase):
    def setUp(self):
        super().setUp()
        ci.clear_cache()
        # events.HUB is a module singleton: a previous test's SSE handler thread can take
        # up to PING_SECONDS to notice its client disconnected, which would otherwise keep
        # its queue — and so its poller, bound to that test's now-deleted ledger dir —
        # alive into this test.
        events.HUB.clear()

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


class Resilience(LiveCase):
    def test_the_poller_survives_a_transient_error_and_keeps_pushing(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/api/events", headers={"Host": f"127.0.0.1:{self.port}"})
        response = conn.getresponse()
        self.assertEqual(response.fp.readline(), b": connected\n")
        time.sleep(0.3)  # let the poller settle on a real baseline head first

        real_ledger_head = events._ledger_head
        state = {"raised": False}

        def flaky(directory):
            if not state["raised"]:
                state["raised"] = True
                raise RuntimeError("boom")
            return real_ledger_head(directory)

        try:
            with mock.patch.object(events, "_ledger_head", side_effect=flaky):
                threading.Timer(
                    0.5, lambda: self.change_ledger(lambda d: L.set_phase(d, "B2", status="paused"))
                ).start()
                deadline = time.monotonic() + 10
                seen = False
                while time.monotonic() < deadline:
                    line = response.fp.readline().decode()
                    if line == "event: ledger\n":
                        seen = True
                        break
                self.assertTrue(seen)
        finally:
            conn.close()

    def test_a_dead_poller_is_replaced_on_the_next_subscribe(self):
        hub = events.Hub()
        q1 = hub.subscribe()
        first = hub._poller
        hub.unsubscribe(q1)
        deadline = time.monotonic() + 5
        while first.is_alive() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(first.is_alive())
        q2 = hub.subscribe()
        self.assertIsNot(hub._poller, first)
        self.assertTrue(hub._poller.is_alive())
        hub.unsubscribe(q2)


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

    def test_two_concurrent_stale_requests_only_collect_once(self):
        calls = {"n": 0}
        real_collect = ci.collect

        def slow_collect(data):
            calls["n"] += 1
            time.sleep(0.3)
            return real_collect(data)

        data = self.ledger()
        results = []
        with mock.patch.object(ci, "collect", side_effect=slow_collect):
            threads = [threading.Thread(target=lambda: results.append(ci.cached(data))) for _ in range(2)]
            for thread in threads:
                thread.start()
            time.sleep(0.05)  # both should observe the stale cache before either finishes
            for thread in threads:
                thread.join(timeout=5)
        self.assertEqual(calls["n"], 1)
        self.assertEqual(results, [results[0], results[0]])
