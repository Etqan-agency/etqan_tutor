"""The orchestration ledger (spec 2026-10-02 §4). Run with
`python3 -m unittest discover -s scripts/orchestration/tests`."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

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


class WaitingPhasesKeepTheirSlot(unittest.TestCase):
    """A launched phase that sets waiting-deps still holds its slot (final review I3)."""

    def launched_then_waiting(self):
        data = L.empty()
        L.set_phase(data, "B2", status="spec", slot=1, worktree="/wt/b2", branch="feat/b2a-x")
        L.set_phase(data, "B2", status="waiting-deps")
        return data

    def test_eligible_never_offers_a_launched_phase_again(self):
        data = self.launched_then_waiting()
        free, codes = L.eligible(data)
        self.assertNotIn("B2", codes)
        self.assertEqual((free, codes), (3, ["B3", "B8", "B9"]))

    def test_a_waiting_phase_still_holds_its_slot(self):
        data = self.launched_then_waiting()
        with self.assertRaisesRegex(L.LedgerError, "slot 1 is held by B2"):
            L.set_phase(data, "B6", status="spec", slot=1)

    def test_slot_0_releases_the_slot_so_it_can_be_lent(self):
        data = self.launched_then_waiting()
        L.set_phase(data, "B2", slot=0)
        self.assertIsNone(data["phases"]["B2"]["slot"])
        self.assertEqual(L.eligible(data)[0], 4)
        L.set_phase(data, "B6", status="spec", slot=1, worktree="/wt/b6")
        self.assertEqual(data["phases"]["B6"]["slot"], 1)

    def test_a_launched_phase_without_a_slot_cannot_resume(self):
        data = self.launched_then_waiting()
        L.set_phase(data, "B2", slot=0)
        L.set_phase(data, "B6", status="spec", slot=1, worktree="/wt/b6")
        before = json.dumps(data, sort_keys=True)
        with self.assertRaisesRegex(L.LedgerError, "B2 holds no slot"):
            L.set_phase(data, "B2", status="build")
        self.assertEqual(json.dumps(data, sort_keys=True), before)
        # Given a slot again, it resumes.
        L.set_phase(data, "B2", status="build", slot=2)
        self.assertEqual((data["phases"]["B2"]["status"], data["phases"]["B2"]["slot"]), ("build", 2))

    def test_a_paused_phase_may_release_its_slot(self):
        data = self.launched_then_waiting()
        L.set_phase(data, "B2", status="paused", slot=0)
        self.assertEqual((data["phases"]["B2"]["status"], data["phases"]["B2"]["slot"]), ("paused", None))
        self.assertEqual(L.eligible(data)[0], 4)

    def test_negative_slot_is_refused(self):
        with self.assertRaises(L.LedgerError):
            L.set_phase(L.empty(), "B2", slot=-1)


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

    def test_enqueue_refuses_a_merged_slice(self):
        L.enqueue(self.data, "B3a")
        L.take_next(self.data)
        L.mark_merged(self.data, "B3a", {})
        with self.assertRaisesRegex(L.LedgerError, "B3a is already merged"):
            L.enqueue(self.data, "B3a")

    def test_a_third_bounce_escalates(self):
        for _ in range(3):
            L.enqueue(self.data, "B3a")
            L.take_next(self.data)
            L.bounce(self.data, "B3a", "CI red")
        kinds = [e["kind"] for e in self.data["escalations"]]
        self.assertEqual(kinds, ["queue-failures"])



class TwoInFlight(unittest.TestCase):
    """A second merge slot (owner decision 2026-10-10): `in_flight_extra`."""

    def setUp(self):
        self.data = L.empty()
        for sid in ("B3a", "B3b", "B3c"):
            L.add_slice(self.data, sid, phase="B3", requires=[])
            L.enqueue(self.data, sid)

    def test_a_new_ledger_has_no_extra(self):
        self.assertIsNone(L.empty()["in_flight_extra"])

    def test_parallel_takes_the_head_into_the_extra_slot(self):
        self.assertEqual(L.take_next(self.data, parallel=True), "B3a")
        self.assertEqual(self.data["in_flight"], "B3a")
        self.assertIsNone(self.data["in_flight_extra"])
        self.assertEqual(L.take_next(self.data, parallel=True), "B3b")
        self.assertEqual(self.data["in_flight_extra"], "B3b")
        self.assertEqual(self.data["slices"]["B3b"]["status"], "in-flight")
        self.assertEqual(self.data["queue"], ["B3c"])

    def test_without_parallel_a_taken_primary_refuses(self):
        L.take_next(self.data)
        with self.assertRaisesRegex(L.LedgerError, "B3a is in flight"):
            L.take_next(self.data)

    def test_a_third_is_refused(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        with self.assertRaisesRegex(L.LedgerError, "two slices are in flight"):
            L.take_next(self.data, parallel=True)
        self.assertEqual(self.data["queue"], ["B3c"])

    def test_an_empty_queue_takes_nothing(self):
        data = L.empty()
        L.add_slice(data, "B3a", phase="B3", requires=[])
        L.enqueue(data, "B3a")
        L.take_next(data)
        self.assertIsNone(L.take_next(data, parallel=True))
        self.assertIsNone(data["in_flight_extra"])

    def test_merging_the_extra_clears_only_it(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        L.mark_merged(self.data, "B3b", {"backend": "abc"})
        self.assertEqual(self.data["in_flight"], "B3a")
        self.assertIsNone(self.data["in_flight_extra"])
        self.assertEqual(self.data["slices"]["B3b"]["status"], "merged")

    def test_merging_the_primary_promotes_the_extra(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        L.mark_merged(self.data, "B3a", {})
        self.assertEqual(self.data["in_flight"], "B3b")
        self.assertIsNone(self.data["in_flight_extra"])
        self.assertEqual(L.take_next(self.data, parallel=True), "B3c")
        self.assertEqual(self.data["in_flight_extra"], "B3c")

    def test_bouncing_the_primary_promotes_the_extra(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        L.bounce(self.data, "B3a", "CI red")
        self.assertEqual(self.data["in_flight"], "B3b")
        self.assertIsNone(self.data["in_flight_extra"])
        self.assertEqual(self.data["slices"]["B3a"]["status"], "build")

    def test_bouncing_the_extra_clears_only_it(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        L.bounce(self.data, "B3b", "CI red")
        self.assertEqual(self.data["in_flight"], "B3a")
        self.assertIsNone(self.data["in_flight_extra"])
        with self.assertRaisesRegex(L.LedgerError, "B3c is not in flight"):
            L.mark_merged(self.data, "B3c", {})

    def test_enqueue_refuses_a_slice_in_either_slot(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        for sid in ("B3a", "B3b"):
            with self.assertRaisesRegex(L.LedgerError, f"{sid} is already queued"):
                L.enqueue(self.data, sid)

    def test_reorder_never_moves_an_in_flight_slice(self):
        L.take_next(self.data)
        L.take_next(self.data, parallel=True)
        for sid in ("B3a", "B3b"):
            with self.assertRaisesRegex(L.LedgerError, f"{sid} is not queued"):
                L.reorder(self.data, sid, "down")

    def test_render_shows_both(self):
        L.take_next(self.data)
        self.assertIn("In flight: **B3a** ·", L.render(self.data))
        L.take_next(self.data, parallel=True)
        self.assertIn("In flight: **B3a + B3b** · Queue: B3c", L.render(self.data))

    def test_an_older_ledger_without_the_key_still_works(self):
        del self.data["in_flight_extra"]
        L.take_next(self.data)
        self.assertIn("In flight: **B3a**", L.render(self.data))
        L.mark_merged(self.data, "B3a", {})
        self.assertEqual(L.take_next(self.data, parallel=True), "B3b")
        self.assertIsNone(self.data.get("in_flight_extra"))

    def test_load_backfills_the_extra(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            old = L.empty()
            del old["in_flight_extra"]
            (directory / "orchestration").mkdir()
            (directory / "orchestration" / "ledger.json").write_text(json.dumps(old))
            self.assertIsNone(L.load(directory)["in_flight_extra"])

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
        self.assertEqual(data["requests"][0]["to_owner"], "B2")
        L.request(data, "B4", "unowned_app", "x")
        self.assertEqual(data["requests"][1]["to_owner"], "conductor")

    def test_claims_carry_a_since_timestamp(self):
        data = L.empty()
        L.claim(data, "B3", "etqan.catalogue.models", "price field")
        since = data["claims"][0]["since"]
        self.assertIsInstance(since, str)
        # ISO-8601 UTC, e.g. "2026-10-03T12:00:00+00:00"; parseable and tz-aware.
        from datetime import datetime
        parsed = datetime.fromisoformat(since)
        self.assertIsNotNone(parsed.tzinfo)

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
        # gc.auto 0: the many commits below would start a detached `git gc
        # --auto` that still writes .git/objects/pack while tearDown deletes it.
        for key, value in (("user.name", "t"), ("user.email", "t@t"), ("gc.auto", "0")):
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

    def test_the_double_slot_case_is_refused_end_to_end(self):
        # Final review I3, reproduced through the CLI: B2 launched in slot 1
        # then waiting; B6 must not get slot 1 until the conductor lends it.
        cli(self.dir, "init")
        cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1",
            "--worktree", "/wt/b2", "--branch", "feat/b2a-x")
        cli(self.dir, "phase", "B2", "--status", "waiting-deps")
        self.assertEqual(cli(self.dir, "eligible").stdout.split(), ["free=3", "B3", "B8", "B9"])
        refused = cli(self.dir, "phase", "B6", "--status", "spec", "--slot", "1")
        self.assertEqual(refused.returncode, 1)
        self.assertIn("slot 1 is held by B2", refused.stderr)
        self.assertEqual(cli(self.dir, "phase", "B2", "--slot", "0").returncode, 0)
        self.assertEqual(cli(self.dir, "phase", "B6", "--status", "spec", "--slot", "1").returncode, 0)
        resumed = cli(self.dir, "phase", "B2", "--status", "build")
        self.assertEqual(resumed.returncode, 1)
        self.assertIn("B2 holds no slot", resumed.stderr)

    def test_a_relative_dir_works(self):
        run = subprocess.run(
            [sys.executable, str(SCRIPT), "--dir", self.dir.name, "init"],
            cwd=self.dir.parent, capture_output=True, text=True,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        log = subprocess.run(
            ["git", "-C", str(self.dir), "log", "--format=%s"], capture_output=True, text=True
        ).stdout.split("\n")[0]
        self.assertEqual(log, "ledger: init")

    def test_a_ledger_commit_never_sweeps_up_phase_notes(self):
        # Final review M3: notes are committed by their author, not by ledger.py.
        cli(self.dir, "init")
        notes = self.dir / "orchestration/phases/B2.md"
        notes.parent.mkdir(parents=True)
        notes.write_text("half-written\n")
        self.assertEqual(cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1").returncode, 0)
        committed = subprocess.run(
            ["git", "-C", str(self.dir), "show", "--name-only", "--format=", "HEAD"],
            capture_output=True, text=True,
        ).stdout.split()
        self.assertNotIn("orchestration/phases/B2.md", committed)

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

    def test_a_failed_commit_leaves_nothing_changed(self):
        cli(self.dir, "init")
        hooks = self.dir / ".git" / "hooks"
        hooks.mkdir(parents=True, exist_ok=True)
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        before = (self.dir / "orchestration/ledger.json").read_text()
        result = cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("commit failed", result.stderr)
        self.assertEqual((self.dir / "orchestration/ledger.json").read_text(), before)
        status = subprocess.run(
            ["git", "-C", str(self.dir), "status", "--porcelain"], capture_output=True, text=True
        ).stdout
        self.assertEqual(status, "")
        hook.unlink()
        result = cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1")
        self.assertEqual(result.returncode, 0)
        log = subprocess.run(
            ["git", "-C", str(self.dir), "log", "--format=%s"], capture_output=True, text=True
        ).stdout.splitlines()
        self.assertEqual(log, ["ledger: phase B2", "ledger: init"])

    def test_merged_records_both_heads(self):
        cli(self.dir, "init")
        cli(self.dir, "slice", "B3a", "--phase", "B3")
        cli(self.dir, "queue", "B3a")
        cli(self.dir, "next")
        result = cli(self.dir, "merged", "B3a", "--head", "backend=abc", "--head", "dashboard=def")
        self.assertEqual(result.returncode, 0)
        data = json.loads((self.dir / "orchestration/ledger.json").read_text())
        self.assertEqual(data["main_heads"], {"backend": "abc", "dashboard": "def"})

    def test_escalate_rejects_unknown_kind(self):
        cli(self.dir, "init")
        result = cli(self.dir, "escalate", "B3", "whim", "x")
        self.assertNotEqual(result.returncode, 0)

    def test_init_rolls_back_cleanly_when_the_branch_is_unborn(self):
        hooks = self.dir / ".git" / "hooks"
        hooks.mkdir(parents=True, exist_ok=True)
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = cli(self.dir, "init")
        self.assertEqual(result.returncode, 1)
        self.assertIn("commit failed", result.stderr)
        self.assertFalse((self.dir / "orchestration" / "ledger.json").exists())
        self.assertFalse((self.dir / "orchestration" / "LEDGER.md").exists())
        self.assertFalse((self.dir / ".gitignore").exists())
        # Nothing staged: the unborn-branch rollback (`git rm --cached`) must leave
        # an empty index, since `git reset`/`diff --cached` have no HEAD to work from.
        staged = subprocess.run(
            ["git", "-C", str(self.dir), "ls-files"], capture_output=True, text=True
        ).stdout
        self.assertEqual(staged, "")


class RollbackFailures(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.dir), "config", key, value], check=True)
        L.save(self.dir, L.empty(), "init")  # a real, successful commit; HEAD now exists

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_failing_rollback_reports_both_errors(self):
        hooks = self.dir / ".git" / "hooks"
        hooks.mkdir(parents=True, exist_ok=True)
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)

        real_run = subprocess.run

        def fake_run(cmd, *args, **kwargs):
            if "reset" in cmd:
                return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="reset exploded")
            return real_run(cmd, *args, **kwargs)

        data = L.load(self.dir)
        L.set_phase(data, "B2", status="spec", slot=1)
        with mock.patch("ledger.subprocess.run", side_effect=fake_run):
            with self.assertRaises(L.LedgerError) as ctx:
                L.save(self.dir, data, "phase B2")
        message = str(ctx.exception)
        self.assertIn("commit failed", message)
        self.assertIn("rollback incomplete", message)
        self.assertIn("reset exploded", message)


class DefaultDir(unittest.TestCase):
    """default_dir() must honour the same overrides the shell scripts do
    (bootstrap-ledger.sh / launch-phase.sh via $ETQAN_WT_ROOT) so a plain
    `ledger.py show` run from inside a phase worktree finds the bootstrapped
    ledger (fix round 1, Task 5 review)."""

    def test_etqan_ledger_dir_wins_over_everything(self):
        with mock.patch.dict(
            os.environ,
            {"ETQAN_LEDGER_DIR": "/explicit/ledger", "ETQAN_WT_ROOT": "/wt"},
            clear=False,
        ):
            with mock.patch("ledger.subprocess.run") as run:
                self.assertEqual(L.default_dir(), Path("/explicit/ledger"))
                run.assert_not_called()

    def test_etqan_wt_root_is_used_when_no_explicit_ledger_dir(self):
        env = dict(os.environ)
        env.pop("ETQAN_LEDGER_DIR", None)
        env["ETQAN_WT_ROOT"] = "/wt"
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch("ledger.subprocess.run") as run:
                self.assertEqual(L.default_dir(), Path("/wt/_ledger"))
                run.assert_not_called()

    def test_falls_back_to_git_common_dir_when_neither_is_set(self):
        env = dict(os.environ)
        env.pop("ETQAN_LEDGER_DIR", None)
        env.pop("ETQAN_WT_ROOT", None)
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch("ledger.subprocess.run") as run:
                run.return_value = subprocess.CompletedProcess(
                    [], 0, stdout="/home/x/etqan_tutor/.git\n"
                )
                self.assertEqual(
                    L.default_dir(), Path("/home/x/etqan_tutor-wt/_ledger")
                )
                run.assert_called_once()


class OrchestraAdditions(unittest.TestCase):
    def _queued(self, *sids):
        data = L.empty()
        for sid in sids:
            L.add_slice(data, sid, phase="B3", requires=[])
            L.enqueue(data, sid)
        return data

    def test_reorder_moves_a_queued_slice(self):
        data = self._queued("B3a", "B3b", "B3c")
        L.reorder(data, "B3c", "up")
        self.assertEqual(data["queue"], ["B3a", "B3c", "B3b"])
        L.reorder(data, "B3a", "down")
        self.assertEqual(data["queue"], ["B3c", "B3a", "B3b"])

    def test_reorder_refuses_edges_unqueued_and_bad_directions(self):
        data = self._queued("B3a")
        L.add_slice(data, "B3b", phase="B3", requires=[])
        with self.assertRaisesRegex(L.LedgerError, "already first"):
            L.reorder(data, "B3a", "up")
        with self.assertRaisesRegex(L.LedgerError, "already last"):
            L.reorder(data, "B3a", "down")
        with self.assertRaisesRegex(L.LedgerError, "B3b is not queued"):
            L.reorder(data, "B3b", "up")
        with self.assertRaisesRegex(L.LedgerError, "up or down"):
            L.reorder(data, "B3a", "sideways")

    def test_request_done(self):
        data = L.empty()
        rid = L.request(data, "B4", "scheduling", "a field")
        L.request_done(data, rid)
        self.assertEqual(data["requests"][0]["status"], "done")
        with self.assertRaisesRegex(L.LedgerError, "already done"):
            L.request_done(data, rid)
        with self.assertRaisesRegex(L.LedgerError, "unknown request R9"):
            L.request_done(data, "R9")

    def test_force_release_ignores_the_holder(self):
        data = L.empty()
        L.claim(data, "B3", "etqan.catalogue.models", "price")
        L.force_release(data, "etqan.catalogue.models")
        self.assertEqual(data["claims"], [])
        with self.assertRaisesRegex(L.LedgerError, "no claim on x"):
            L.force_release(data, "x")

    def test_clear_empties_a_field_and_the_phase_is_eligible_again(self):
        data = L.empty()
        L.set_phase(data, "B2", status="spec", slot=1, worktree="/w/b2", branch="feat/b2a-x", session="ab12")
        self.assertEqual(data["phases"]["B2"]["session"], "ab12")
        L.set_phase(data, "B2", status="waiting-deps", slot=0, worktree=L.CLEAR, branch=L.CLEAR, session=L.CLEAR)
        phase = data["phases"]["B2"]
        self.assertEqual([phase[k] for k in ("slot", "worktree", "branch", "session")], [None] * 4)
        self.assertIn("B2", L.eligible(data)[1])

    def test_conductor_session(self):
        data = L.empty()
        self.assertIsNone(data["conductor_session"])
        L.set_conductor_session(data, "cd34")
        self.assertEqual(data["conductor_session"], "cd34")
        L.set_conductor_session(data, L.CLEAR)
        self.assertIsNone(data["conductor_session"])

    def test_load_backfills_an_older_ledger(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            old = L.empty()
            del old["conductor_session"]
            for phase in old["phases"].values():
                del phase["session"]
            (directory / "orchestration").mkdir()
            (directory / "orchestration" / "ledger.json").write_text(json.dumps(old))
            data = L.load(directory)
            self.assertIsNone(data["conductor_session"])
            self.assertTrue(all(p["session"] is None for p in data["phases"].values()))

    def test_save_names_its_source_in_the_commit(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            subprocess.run(["git", "init", "-q", "-b", "orchestration", tmp], check=True)
            for key, value in (("user.name", "t"), ("user.email", "t@t")):
                subprocess.run(["git", "-C", tmp, "config", key, value], check=True)
            L.save(directory, L.empty(), "init", source="orchestra")
            subject = subprocess.run(
                ["git", "-C", tmp, "log", "-1", "--format=%s"], capture_output=True, text=True
            ).stdout.strip()
            self.assertEqual(subject, "ledger (orchestra): init")


class OrchestraCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.dir), "config", key, value], check=True)
        cli(self.dir, "init")

    def tearDown(self):
        self.tmp.cleanup()

    def _data(self):
        return json.loads((self.dir / "orchestration/ledger.json").read_text())

    def test_phase_session_and_none_clearing(self):
        self.assertEqual(cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1",
                             "--worktree", "/w", "--branch", "feat/b2a-x", "--session", "ab12").returncode, 0)
        result = cli(self.dir, "phase", "B2", "--status", "waiting-deps", "--slot", "0",
                     "--worktree", "none", "--branch", "none", "--session", "none")
        self.assertEqual(result.returncode, 0, result.stderr)
        phase = self._data()["phases"]["B2"]
        self.assertEqual([phase[k] for k in ("worktree", "branch", "session")], [None] * 3)

    def test_conductor_reorder_request_done_release_claim(self):
        self.assertEqual(cli(self.dir, "conductor", "--session", "cd34").returncode, 0)
        self.assertEqual(self._data()["conductor_session"], "cd34")
        for sid in ("B3a", "B3b"):
            cli(self.dir, "slice", sid, "--phase", "B3")
            cli(self.dir, "queue", sid)
        self.assertEqual(cli(self.dir, "reorder", "B3b", "up").returncode, 0)
        self.assertEqual(self._data()["queue"], ["B3b", "B3a"])
        cli(self.dir, "request", "B4", "scheduling", "a field")
        self.assertEqual(cli(self.dir, "request-done", "R1").returncode, 0)
        cli(self.dir, "claim", "B3", "t", "--reason", "r")
        self.assertEqual(cli(self.dir, "release-claim", "t").returncode, 0)
        self.assertEqual(self._data()["claims"], [])
        self.assertNotEqual(cli(self.dir, "reorder", "B3a", "left").returncode, 0)


    def test_next_parallel_and_show_json(self):
        for sid in ("B3a", "B3b", "B3c"):
            cli(self.dir, "slice", sid, "--phase", "B3")
            cli(self.dir, "queue", sid)
        self.assertEqual(cli(self.dir, "next").stdout.strip(), "B3a")
        refused = cli(self.dir, "next")
        self.assertEqual(refused.returncode, 1)
        self.assertIn("B3a is in flight", refused.stderr)
        self.assertEqual(cli(self.dir, "next", "--parallel").stdout.strip(), "B3b")
        self.assertEqual(cli(self.dir, "next", "--parallel").returncode, 1)
        shown = json.loads(cli(self.dir, "show", "--json").stdout)
        self.assertEqual((shown["in_flight"], shown["in_flight_extra"]), ("B3a", "B3b"))
        self.assertIn("In flight: **B3a + B3b**", cli(self.dir, "show").stdout)
        self.assertEqual(cli(self.dir, "merged", "B3a").returncode, 0)
        self.assertEqual((self._data()["in_flight"], self._data()["in_flight_extra"]), ("B3b", None))

if __name__ == "__main__":
    unittest.main()
