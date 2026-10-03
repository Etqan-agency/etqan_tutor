"""Guards and the static page (spec 2026-10-03 §4.1)."""

import os
from unittest import mock

from tests.support import ServerCase


class Guards(ServerCase):
    def test_a_foreign_host_is_refused(self):
        status, data = self.request("GET", "/api/state", headers={"Host": f"evil.example:{self.port}"})
        self.assertEqual((status, data), (403, {"error": "bad host"}))

    def test_localhost_is_allowed(self):
        status, _ = self.request("GET", "/api/state", headers={"Host": f"localhost:{self.port}"})
        self.assertEqual(status, 200)

    def test_a_foreign_origin_is_refused_even_for_reads(self):
        status, data = self.request("GET", "/api/state", headers={"Origin": "http://evil.example"})
        self.assertEqual((status, data), (403, {"error": "bad origin"}))
        status, _ = self.request("GET", "/api/state", headers={"Origin": f"http://127.0.0.1:{self.port}"})
        self.assertEqual(status, 200)

    def test_writes_need_the_token(self):
        body = {"status": "paused"}
        self.assertEqual(self.request("POST", "/api/phases/B2/status", body, token=False)[0], 403)
        status, data = self.request(
            "POST", "/api/phases/B2/status", body, headers={"X-Orchestra-Token": "wrong"}, token=False
        )
        self.assertEqual((status, data), (403, {"error": "bad token"}))
        self.assertEqual(self.request("POST", "/api/phases/B2/status", body)[0], 200)

    def test_unknown_routes_and_bad_bodies(self):
        self.assertEqual(self.request("GET", "/api/nothing")[0], 404)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", b"not json")[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", [1, 2])[0], 400)

    def test_the_dev_token_route_exists_only_in_dev(self):
        self.assertEqual(self.request("GET", "/api/token")[0], 404)
        with mock.patch.dict(os.environ, {"ORCHESTRA_DEV": "1"}):
            self.assertEqual(self.request("GET", "/api/token"), (200, {"token": self.token}))


class StaticPage(ServerCase):
    def test_index_carries_the_token_and_serves_every_page_path(self):
        (self.base / "dist" / "index.html").write_text("<html><head><title>O</title></head><body></body></html>")
        for path in ("/", "/phase/B3", "/queue"):
            status, body = self.request("GET", path)
            self.assertEqual(status, 200)
            self.assertIn(f'<meta name="orchestra-token" content="{self.token}"></head>', body)

    def test_assets_are_served_and_traversal_falls_back_to_index(self):
        (self.base / "dist" / "index.html").write_text("<html><head></head></html>")
        (self.base / "dist" / "assets").mkdir()
        (self.base / "dist" / "assets" / "app.js").write_text("console.log(1)")
        self.assertEqual(self.request("GET", "/assets/app.js"), (200, "console.log(1)"))
        status, body = self.request("GET", "/../../../etc/passwd")
        self.assertEqual(status, 200)
        self.assertIn("orchestra-token", body)

    def test_an_unbuilt_web_app_says_so(self):
        status, body = self.request("GET", "/")
        self.assertEqual(status, 503)
        self.assertIn("just orchestra", body)
