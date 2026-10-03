"""Reconciling the ledger with `claude agents` (spec 2026-10-03 §4.3)."""

import json
import unittest

from orchestra_server import commands, sessions
from orchestra_server.ledger_api import L
from tests.support import ServerCase


def agent(id_, name, *, state="running", status="idle", pid=True):
    a = {
        "id": id_,
        "name": name,
        "kind": "background",
        "state": state,
        "status": status,
        "sessionId": f"{id_}-uuid",
        "cwd": "/w",
    }
    if pid:
        a["pid"] = 1
    return a


class Reconcile(unittest.TestCase):
    def setUp(self):
        self.data = L.empty()

    def test_states(self):
        L.set_phase(self.data, "B2", session="aa")
        L.set_phase(self.data, "B3", session="bb")
        L.set_phase(self.data, "B8", session="cc")
        L.set_phase(self.data, "B9", session="dd")  # recorded, not listed at all
        items = [
            agent("aa", "etqan-B2", status="busy"),
            agent("bb", "etqan-B3"),
            agent("cc", "etqan-B8", state="done", pid=False),
        ]
        view, adopt = sessions.reconcile(self.data, items)
        self.assertEqual(
            [view[c]["state"] for c in ("B2", "B3", "B8", "B9", "B4")], ["busy", "idle", "exited", "gone", "none"]
        )
        self.assertEqual(adopt, {})

    def test_a_running_named_session_without_an_id_is_adopted(self):
        items = [
            agent("ee", "etqan-B6"),
            agent("ff", "etqan-conductor"),
            agent("gg", "etqan-B5", state="done", pid=False),
        ]
        view, adopt = sessions.reconcile(self.data, items)
        self.assertEqual(adopt, {"B6": "ee", "conductor": "ff"})
        self.assertEqual(view["B6"]["state"], "idle")
        self.assertEqual(view["B5"]["state"], "none")

    def test_a_session_started_by_hand_under_the_same_name_replaces_an_exited_one(self):
        L.set_phase(self.data, "B3", session="aa")
        items = [agent("aa", "etqan-B3", state="done", pid=False), agent("zz", "etqan-B3")]
        view, adopt = sessions.reconcile(self.data, items)
        self.assertEqual(adopt, {"B3": "zz"})
        self.assertEqual(view["B3"]["id"], "zz")
        self.assertEqual(view["B3"]["state"], "idle")


class Agents(ServerCase):
    def test_invalid_json_is_lenient_by_default_and_raises_when_strict(self):
        self.agents_file.write_text("not json")
        self.assertEqual(sessions.agents(), [])
        with self.assertRaises(commands.CommandFailed):
            sessions.agents(strict=True)


class Snapshot(ServerCase):
    def test_state_shows_sessions_and_adopts(self):
        self.agents_file.write_text(json.dumps([agent("ee", "etqan-B6")]))
        status, data = self.request("GET", "/api/state")
        self.assertEqual(status, 200)
        self.assertEqual(data["sessions"]["B6"]["state"], "idle")
        self.assertEqual(self.ledger()["phases"]["B6"]["session"], "ee")

    def test_a_fresh_server_shows_the_same_sessions(self):
        self.change_ledger(lambda d: L.set_phase(d, "B2", session="aa"))
        self.agents_file.write_text(json.dumps([agent("aa", "etqan-B2", status="busy")]))
        first = self.request("GET", "/api/state")[1]["sessions"]
        self.server.shutdown()
        self.server.server_close()
        import threading

        from orchestra_server import app

        self.server = app.make_server(0, self.token)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.port = self.server.server_port
        self.assertEqual(self.request("GET", "/api/state")[1]["sessions"], first)
