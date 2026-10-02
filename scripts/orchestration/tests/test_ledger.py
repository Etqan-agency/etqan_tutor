"""The orchestration ledger (spec 2026-10-02 §4). Run with
`python3 -m unittest discover -s scripts/orchestration/tests`."""

import json
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "ledger.py"
sys.path.insert(0, str(HERE.parent))

import ledger as L  # noqa: E402


def cli(directory, *args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--dir", str(directory), *args],
        capture_output=True,
        text=True,
    )


class PhasesAndSlots(unittest.TestCase):
    def test_empty_ledger_lists_every_phase_waiting(self):
        data = L.empty()
        self.assertEqual(list(data["phases"]), [f"B{n}" for n in range(2, 12)])
        self.assertTrue(all(p["status"] == "waiting-deps" for p in data["phases"].values()))
        self.assertEqual(data["next_plan_number"], 15)

    def test_a_slot_is_held_by_one_active_phase(self):
        data = L.empty()
        L.set_phase(data, "B2", status="spec", slot=1)
        with self.assertRaisesRegex(L.LedgerError, "slot 1 is held by B2"):
            L.set_phase(data, "B3", status="spec", slot=1)

    def test_a_merged_phase_frees_its_slot(self):
        data = L.empty()
        L.set_phase(data, "B8", status="spec", slot=3)
        L.set_phase(data, "B8", status="merged")
        self.assertIsNone(data["phases"]["B8"]["slot"])
        L.set_phase(data, "B6", status="spec", slot=3)

    def test_unknown_status_and_slot_are_refused(self):
        data = L.empty()
        with self.assertRaises(L.LedgerError):
            L.set_phase(data, "B2", status="done")
        with self.assertRaises(L.LedgerError):
            L.set_phase(data, "B2", slot=5)

    def test_eligible_needs_dependency_specs_and_free_slots(self):
        data = L.empty()
        free, codes = L.eligible(data)
        self.assertEqual((free, codes), (4, ["B2", "B3", "B8", "B9"]))
        for slot, code in enumerate(["B2", "B3", "B8", "B9"], start=1):
            L.set_phase(data, code, status="spec", slot=slot)
        self.assertEqual(L.eligible(data), (0, []))
        L.set_phase(data, "B2", spec="docs/b2.md")
        L.set_phase(data, "B8", status="merged")
        # B6 and B5 now qualify (B4 also needs B3's spec); one slot is free.
        self.assertEqual(L.eligible(data), (1, ["B6"]))


class SlicesAndQueue(unittest.TestCase):
    def setUp(self):
        self.data = L.empty()
        L.add_slice(self.data, "B3a", phase="B3", requires=[])
        L.add_slice(self.data, "B4a", phase="B4", requires=["B2b", "B3a"])

    def test_a_slice_belongs_to_its_phase(self):
        with self.assertRaisesRegex(L.LedgerError, "must start with B2"):
            L.add_slice(self.data, "B3z", phase="B2", requires=[])

    def test_plan_numbers_are_allocated_once(self):
        self.assertEqual(L.alloc_plan(self.data, "B3a"), 15)
        self.assertEqual(L.alloc_plan(self.data, "B3a"), 15)
        self.assertEqual(L.alloc_plan(self.data, "B4a"), 16)

    def test_unmet_lists_unmerged_and_unknown_requirements(self):
        self.assertEqual(L.unmet(self.data, "B4a"), ["B2b", "B3a"])
        L.enqueue(self.data, "B3a")
        L.take_next(self.data)
        L.mark_merged(self.data, "B3a", {"backend": "abc"})
        self.assertEqual(L.unmet(self.data, "B4a"), ["B2b"])
        self.assertEqual(self.data["main_heads"], {"backend": "abc"})

    def test_one_slice_in_flight_at_a_time(self):
        L.add_slice(self.data, "B3b", phase="B3", requires=[])
        L.enqueue(self.data, "B3a")
        L.enqueue(self.data, "B3b")
        self.assertEqual(L.take_next(self.data), "B3a")
        with self.assertRaisesRegex(L.LedgerError, "B3a is in flight"):
            L.take_next(self.data)
        L.bounce(self.data, "B3a", "CI red")
        self.assertEqual(self.data["slices"]["B3a"]["status"], "build")
        self.assertEqual(L.take_next(self.data), "B3b")

    def test_queueing_twice_is_refused(self):
        L.enqueue(self.data, "B3a")
        with self.assertRaises(L.LedgerError):
            L.enqueue(self.data, "B3a")

    def test_a_third_bounce_escalates(self):
        for _ in range(3):
            L.enqueue(self.data, "B3a")
            L.take_next(self.data)
            L.bounce(self.data, "B3a", "CI red")
        kinds = [e["kind"] for e in self.data["escalations"]]
        self.assertEqual(kinds, ["queue-failures"])


class ClaimsDecisionsEscalations(unittest.TestCase):
    def test_a_claim_held_by_another_phase_is_refused(self):
        data = L.empty()
        L.claim(data, "B3", "etqan.catalogue.models", "price field")
        L.claim(data, "B3", "etqan.catalogue.models", "again")  # own: no-op
        self.assertEqual(len(data["claims"]), 1)
        with self.assertRaisesRegex(L.LedgerError, "claimed by B3"):
            L.claim(data, "B2", "etqan.catalogue.models", "x")
        with self.assertRaises(L.LedgerError):
            L.release(data, "B2", "etqan.catalogue.models")
        L.release(data, "B3", "etqan.catalogue.models")
        self.assertEqual(data["claims"], [])

    def test_requests_go_to_the_owner(self):
        data = L.empty()
        rid = L.request(data, "B4", "scheduling", "session class field")
        self.assertEqual(rid, "R1")
        self.assertEqual(data["requests"][0]["owner"], "B2")
        L.request(data, "B4", "unowned_app", "x")
        self.assertEqual(data["requests"][1]["owner"], "conductor")

    def test_decisions_and_escalations_are_numbered(self):
        data = L.empty()
        self.assertEqual(L.decide(data, "B3", "wallet on Student", ["B4"], "audit §2"), "D1")
        self.assertEqual(L.escalate(data, "B3", "money", "live Stripe keys?"), "E1")
        with self.assertRaises(L.LedgerError):
            L.escalate(data, "B3", "whim", "x")
        L.resolve(data, "E1", "use test keys")
        self.assertEqual(data["escalations"][0]["status"], "resolved")

    def test_render_shows_open_escalations_and_the_queue(self):
        data = L.empty()
        L.add_slice(data, "B3a", phase="B3", requires=[])
        L.enqueue(data, "B3a")
        L.escalate(data, "B3", "money", "live keys?")
        text = L.render(data)
        self.assertIn("| B3a |", text)
        self.assertIn("live keys?", text)


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.dir), "config", key, value], check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_init_then_each_write_is_a_commit(self):
        self.assertEqual(cli(self.dir, "init").returncode, 0)
        self.assertEqual(cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1").returncode, 0)
        log = subprocess.run(
            ["git", "-C", str(self.dir), "log", "--format=%s"], capture_output=True, text=True
        ).stdout.splitlines()
        self.assertEqual(log, ["ledger: phase B2", "ledger: init"])
        self.assertIn("| B2 |", (self.dir / "orchestration/LEDGER.md").read_text())
        status = subprocess.run(
            ["git", "-C", str(self.dir), "status", "--porcelain"], capture_output=True, text=True
        ).stdout
        self.assertEqual(status, "")  # .lock is ignored

    def test_errors_exit_1_without_writing(self):
        cli(self.dir, "init")
        cli(self.dir, "phase", "B2", "--slot", "1", "--status", "spec")
        before = (self.dir / "orchestration/ledger.json").read_text()
        result = cli(self.dir, "phase", "B3", "--slot", "1", "--status", "spec")
        self.assertEqual(result.returncode, 1)
        self.assertIn("slot 1 is held by B2", result.stderr)
        self.assertEqual((self.dir / "orchestration/ledger.json").read_text(), before)

    def test_ready_exit_code(self):
        cli(self.dir, "init")
        cli(self.dir, "slice", "B4a", "--phase", "B4", "--requires", "B3a")
        result = cli(self.dir, "ready", "B4a")
        self.assertEqual((result.returncode, result.stdout.strip()), (1, "B3a"))

    def test_concurrent_writers_lose_nothing(self):
        cli(self.dir, "init")
        slices = [f"B3{chr(97 + i)}" for i in range(10)]
        for sid in slices:
            cli(self.dir, "slice", sid, "--phase", "B3")
        with ThreadPoolExecutor(max_workers=10) as pool:
            numbers = list(pool.map(lambda s: cli(self.dir, "alloc-plan", s).stdout.strip(), slices))
        self.assertEqual(sorted(int(n) for n in numbers), list(range(15, 25)))
        data = json.loads((self.dir / "orchestration/ledger.json").read_text())
        self.assertEqual(data["next_plan_number"], 25)


if __name__ == "__main__":
    unittest.main()
