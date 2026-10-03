"""Commands behind the phase, session and stack routes (spec 2026-10-03 §4.2)."""

import json
import os
from pathlib import Path

from orchestra_server.ledger_api import L
from tests import fakes
from tests.support import ServerCase


class ActionCase(ServerCase):
    def calls(self, cmd=None):
        return [c for c in fakes.calls(self.base) if cmd is None or c["cmd"] == cmd]

    def launched(self, code="B3", slot=2):
        wt = str(self.base / "wt" / code.lower())
        Path(wt).mkdir(parents=True, exist_ok=True)
        self.change_ledger(
            lambda d: L.set_phase(d, code, status="build", slot=slot, worktree=wt, branch=f"feat/{code.lower()}a-x")
        )
        return wt


class Launch(ActionCase):
    def test_launch_runs_the_script_records_and_starts_the_session(self):
        status, data = self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-money", "slot": 2})
        self.assertEqual(status, 200, data)
        self.assertEqual(data["session"], "ab12cd34")
        launch = self.calls("launch-phase.sh")[0]
        self.assertEqual(launch["argv"][1:], ["B3", "b3a-money", "2"])
        phase = self.ledger()["phases"]["B3"]
        self.assertEqual((phase["status"], phase["slot"], phase["branch"]), ("spec", 2, "feat/b3a-money"))
        self.assertEqual(phase["worktree"], str(self.base / "wt" / "b3"))
        self.assertEqual(self.calls("start-session.sh")[0]["argv"][1:], ["B3", "--mode", "auto"])

    def test_launch_refusals(self):
        self.assertEqual(self.request("POST", "/api/phases/B6/launch", {"suffix": "b6a-x", "slot": 1})[0], 409)
        self.assertEqual(self.request("POST", "/api/phases/B3/launch", {"suffix": "B3 x", "slot": 1})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-x", "slot": 5})[0], 400)
        self.launched("B2", slot=1)
        status, data = self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-x", "slot": 1})
        self.assertEqual((status, data), (409, {"error": "slot 1 is held by B2"}))
        self.assertEqual(self.calls("launch-phase.sh"), [])

    def test_a_failing_script_reports_its_tail_and_changes_nothing(self):
        os.environ["FAKE_FAIL"] = "launch-phase.sh"
        status, data = self.request("POST", "/api/phases/B3/launch", {"suffix": "b3a-x", "slot": 2})
        self.assertEqual(status, 500)
        self.assertEqual((data["ok"], data["exit_code"]), (False, 3))
        self.assertEqual(len(data["output_tail"].splitlines()), 50)
        self.assertTrue(data["output_tail"].endswith("boom"))
        self.assertIsNone(self.ledger()["phases"]["B3"]["worktree"])


class Sessions(ActionCase):
    def test_start_validates_and_passes_options(self):
        self.launched()
        self.assertEqual(self.request("POST", "/api/phases/B3/session/start", {"mode": "bypassPermissions"})[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B3/session/start", {"model": "x y"})[0], 400)
        body = {"mode": "plan", "model": "claude-sonnet-5", "effort": "high"}
        self.assertEqual(
            self.request("POST", "/api/phases/B3/session/start", body), (200, {"ok": True, "id": "ab12cd34"})
        )
        self.assertEqual(
            self.calls("start-session.sh")[0]["argv"][1:],
            ["B3", "--mode", "plan", "--model", "claude-sonnet-5", "--effort", "high"],
        )

    def test_stop_needs_a_session(self):
        self.assertEqual(self.request("POST", "/api/phases/B3/session/stop")[0], 400)
        self.change_ledger(lambda d: L.set_phase(d, "B3", session="aa"))
        self.assertEqual(self.request("POST", "/api/phases/B3/session/stop")[0], 200)
        self.assertEqual(self.calls("claude")[-1]["argv"], ["stop", "aa"])

    def test_restart_respawns_resumes_or_starts(self):
        self.launched()
        self.change_ledger(lambda d: L.set_phase(d, "B3", session="aa"))
        self.agents_file.write_text(
            json.dumps(
                [{"id": "aa", "name": "etqan-B3", "kind": "background", "pid": 1, "state": "running", "status": "idle"}]
            )
        )
        self.assertEqual(self.request("POST", "/api/phases/B3/session/restart")[1], {"ok": True, "id": "aa"})
        self.assertEqual(self.calls("claude")[-1]["argv"], ["respawn", "aa"])

        self.agents_file.write_text(
            json.dumps(
                [
                    {
                        "id": "aa",
                        "name": "etqan-B3",
                        "kind": "background",
                        "state": "done",
                        "sessionId": "aa-uuid",
                        "cwd": str(self.base),
                    }
                ]
            )
        )
        os.environ["FAKE_ID"] = "bb"
        self.assertEqual(self.request("POST", "/api/phases/B3/session/restart")[1], {"ok": True, "id": "bb"})
        resume = self.calls("claude")[-1]
        self.assertEqual(resume["argv"][:3], ["--bg", "--resume", "aa-uuid"])
        self.assertIn("etqan-B3", resume["argv"])
        self.assertEqual(resume["cwd"], str(self.base))
        self.assertEqual(self.ledger()["phases"]["B3"]["session"], "bb")

        self.agents_file.write_text("[]")
        self.request("POST", "/api/phases/B3/session/restart")
        self.assertEqual(self.calls()[-1]["cmd"], "start-session.sh")

    def test_conductor_sessions(self):
        self.assertEqual(self.request("POST", "/api/conductor/session/start", {"mode": "auto"})[0], 200)
        self.assertEqual(self.calls("start-session.sh")[0]["argv"][1:], ["conductor", "--mode", "auto"])

    def test_logs_are_capped(self):
        logs = self.base / "logs.txt"
        logs.write_text("x" * 300_000)
        os.environ["FAKE_LOGS"] = str(logs)
        self.change_ledger(lambda d: L.set_phase(d, "B3", session="aa"))
        status, data = self.request("GET", "/api/phases/B3/log")
        self.assertEqual(status, 200)
        self.assertEqual(len(data["text"]), 200_000)
        self.assertEqual(self.request("GET", "/api/phases/B2/log"), (200, {"text": ""}))


class Slots(ActionCase):
    def test_moving_to_a_free_slot(self):
        wt = self.launched("B3", slot=2)
        self.assertEqual(self.request("POST", "/api/phases/B3/slot", {"slot": 4})[0], 200)
        sequence = [(c["cmd"], c["argv"]) for c in self.calls() if c["cmd"] != "claude"]
        self.assertEqual(
            sequence,
            [
                ("just", ["stop"]),
                ("stream-env.sh", [sequence[1][1][0], "b3", "4", wt]),
                ("just", ["dev-backend"]),
            ],
        )
        self.assertTrue(all(c["cwd"] == wt for c in self.calls("just")))
        self.assertEqual(self.ledger()["phases"]["B3"]["slot"], 4)

    def test_a_held_slot_is_refused_before_anything_runs(self):
        self.launched("B2", slot=1)
        self.launched("B3", slot=2)
        self.assertEqual(
            self.request("POST", "/api/phases/B3/slot", {"slot": 1}), (409, {"error": "slot 1 is held by B2"})
        )
        self.assertEqual(self.calls("just"), [])

    def test_releasing(self):
        self.launched("B3", slot=2)
        self.assertEqual(self.request("POST", "/api/phases/B3/slot", {"slot": 0})[0], 200)
        phase = self.ledger()["phases"]["B3"]
        self.assertEqual((phase["slot"], phase["status"]), (None, "paused"))

    def test_stack_up_and_down(self):
        wt = self.launched()
        self.request("POST", "/api/phases/B3/stack", {"up": True})
        self.request("POST", "/api/phases/B3/stack", {"up": False})
        self.assertEqual([(c["argv"], c["cwd"]) for c in self.calls("just")], [(["dev-backend"], wt), (["stop"], wt)])
        self.assertEqual(self.request("POST", "/api/phases/B2/stack", {"up": True})[0], 400)

    def test_stacks_in_state(self):
        self.launched("B3")
        os.environ["FAKE_DOCKER"] = "etqan-b3\netqan_tutor"
        self.assertEqual(self.request("GET", "/api/state")[1]["stacks"], {"B3": True})


class Teardown(ActionCase):
    def test_confirm_must_match(self):
        self.launched()
        self.assertEqual(self.request("POST", "/api/phases/B3/teardown", {"confirm": "B2"})[0], 400)
        self.assertEqual(self.calls(), [])

    def test_an_unfinished_phase_returns_to_waiting(self):
        self.launched()
        self.change_ledger(
            lambda d: (L.set_phase(d, "B3", session="aa"), L.add_slice(d, "B3a", phase="B3", requires=[]))
        )
        os.environ["FAKE_FAIL"] = "claude"  # its session is already gone: ignored
        self.assertEqual(self.request("POST", "/api/phases/B3/teardown", {"confirm": "B3"})[0], 200)
        self.assertEqual(self.calls("teardown-phase.sh")[0]["argv"][1:], ["B3"])
        phase = self.ledger()["phases"]["B3"]
        self.assertEqual(
            [phase[k] for k in ("status", "slot", "worktree", "branch", "session")],
            ["waiting-deps", None, None, None, None],
        )
        self.assertIn("B3", self.request("GET", "/api/state")[1]["eligible"]["phases"])

    def test_a_finished_phase_is_merged(self):
        self.launched()

        def finish(d):
            L.add_slice(d, "B3a", phase="B3", requires=[])
            L.enqueue(d, "B3a")
            L.take_next(d)
            L.mark_merged(d, "B3a", {})

        self.change_ledger(finish)
        self.request("POST", "/api/phases/B3/teardown", {"confirm": "B3"})
        self.assertEqual(self.ledger()["phases"]["B3"]["status"], "merged")
