"""Ledger-only routes (spec 2026-10-03 §4.2)."""

import threading

from orchestra_server.ledger_api import L
from tests.support import ServerCase


class State(ServerCase):
    def test_state_has_the_ledger_and_the_eligible_phases(self):
        status, data = self.request("GET", "/api/state")
        self.assertEqual(status, 200)
        self.assertEqual(data["eligible"], {"free": 4, "phases": ["B2", "B3", "B8", "B9"]})
        self.assertIn("B11", data["ledger"]["phases"])


class PhaseStatus(ServerCase):
    def test_status_is_written_and_attributed(self):
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {"status": "paused"}), (200, {"ok": True}))
        self.assertEqual(self.ledger()["phases"]["B2"]["status"], "paused")
        self.assertEqual(self.last_subject(), "ledger (orchestra): phase B2 status paused")

    def test_bad_inputs(self):
        self.assertEqual(self.request("POST", "/api/phases/B99/status", {"status": "paused"})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {"status": "done"})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {})[0], 400)


class Queue(ServerCase):
    def setUp(self):
        super().setUp()

        def seed(d):
            for sid in ("B3a", "B3b"):
                L.add_slice(d, sid, phase="B3", requires=[])
                L.enqueue(d, sid)

        self.change_ledger(seed)

    def test_next_reorder_bounce_merged(self):
        self.assertEqual(self.request("POST", "/api/queue/reorder", {"slice": "B3b", "direction": "up"})[0], 200)
        self.assertEqual(self.ledger()["queue"], ["B3b", "B3a"])
        self.assertEqual(self.request("POST", "/api/queue/next"), (200, {"ok": True, "in_flight": "B3b"}))
        status, data = self.request("POST", "/api/queue/next")
        self.assertEqual((status, data), (409, {"error": "B3b is in flight"}))
        self.assertEqual(self.request("POST", "/api/queue/bounce", {"slice": "B3b", "reason": ""})[0], 400)
        self.assertEqual(self.request("POST", "/api/queue/bounce", {"slice": "B3b", "reason": "CI red"})[0], 200)
        self.request("POST", "/api/queue/next")
        bad = {"slice": "B3a", "heads": {"backend": "not-a-sha"}}
        self.assertEqual(self.request("POST", "/api/queue/merged", bad)[0], 400)
        good = {"slice": "B3a", "heads": {"backend": "abc1234", "meta": "def5678"}}
        self.assertEqual(self.request("POST", "/api/queue/merged", good)[0], 200)
        self.assertEqual(self.ledger()["slices"]["B3a"]["status"], "merged")
        self.assertEqual(self.ledger()["main_heads"], {"backend": "abc1234", "meta": "def5678"})


class Coordination(ServerCase):
    def test_resolve_decide_release_done(self):
        def seed(d):
            L.escalate(d, "B3", "money", "live keys?")
            L.claim(d, "B3", "etqan.catalogue.models", "price")
            L.request(d, "B4", "scheduling", "a field")

        self.change_ledger(seed)
        self.assertEqual(self.request("POST", "/api/escalations/E1/resolve", {"answer": "test keys"})[0], 200)
        self.assertEqual(self.ledger()["escalations"][0]["answer"], "test keys")
        self.assertEqual(self.request("POST", "/api/escalations/E1/resolve", {"answer": "  "})[0], 400)
        decision = {"phase": "B3", "text": "wallet on Student", "affects": ["B4"], "source": "audit §2"}
        self.assertEqual(self.request("POST", "/api/decisions", decision), (200, {"ok": True, "id": "D1"}))
        self.assertEqual(self.request("POST", "/api/decisions", {**decision, "affects": ["B99"]})[0], 400)
        self.assertEqual(self.request("POST", "/api/claims/release", {"target": "etqan.catalogue.models"})[0], 200)
        self.assertEqual(self.ledger()["claims"], [])
        self.assertEqual(self.request("POST", "/api/requests/R1/done")[0], 200)
        self.assertEqual(self.request("POST", "/api/requests/R1/done")[0], 409)

    def test_concurrent_writes_lose_nothing(self):
        decision = {"phase": "B3", "text": "x", "affects": [], "source": "s"}
        threads = [threading.Thread(target=self.request, args=("POST", "/api/decisions", decision)) for _ in range(10)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        ids = [d["id"] for d in self.ledger()["shared_decisions"]]
        self.assertEqual(sorted(ids, key=lambda i: int(i[1:])), [f"D{n}" for n in range(1, 11)])
