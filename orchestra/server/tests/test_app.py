"""Guards and the static page (spec 2026-10-03 §4.1)."""

import http.client
import json
import os
import socket
import unittest
from unittest import mock

from orchestra_server import validate as v
from orchestra_server.errors import BadRequest
from tests.support import ServerCase


def _fetch(port, method, path, *, headers=None):
    """A plain http.client round trip that hands back status and response headers."""
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=20)
    sent = {"Host": f"127.0.0.1:{port}"}
    sent.update(headers or {})
    conn.request(method, path, headers=sent)
    response = conn.getresponse()
    response.read()
    result = (response.status, dict(response.getheaders()))
    conn.close()
    return result


def _raw_exchange(port, head: bytes, body: bytes = b"", timeout: float = 5) -> bytes:
    """A request sent over a bare socket, for cases http.client itself refuses to send."""
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.sendall(head + body)
        sock.settimeout(timeout)
        chunks = []
        try:
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        except OSError:
            pass
    return b"".join(chunks)


def _status_of(raw: bytes) -> int:
    return int(raw.split(b" ", 2)[1])


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


class SecurityHeaders(ServerCase):
    def test_clickjacking_headers_on_json_static_and_error_responses(self):
        (self.base / "dist" / "index.html").write_text("<html><head></head></html>")
        index_status, index_headers = _fetch(self.port, "GET", "/")
        state_status, state_headers = _fetch(self.port, "GET", "/api/state")
        forbidden_status, forbidden_headers = _fetch(self.port, "GET", "/api/state", headers={"Host": "evil.example"})
        self.assertEqual((index_status, state_status, forbidden_status), (200, 200, 403))
        for headers in (index_headers, state_headers, forbidden_headers):
            self.assertEqual(headers.get("X-Frame-Options"), "DENY")
            self.assertEqual(headers.get("Content-Security-Policy"), "frame-ancestors 'none'")


class TokenEncoding(ServerCase):
    def test_a_non_ascii_token_is_refused_not_a_crash(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        sent = {
            "Host": f"127.0.0.1:{self.port}",
            "X-Orchestra-Token": "café",
            "Content-Type": "application/json",
        }
        conn.request("POST", "/api/phases/B2/status", body=json.dumps({"status": "paused"}), headers=sent)
        response = conn.getresponse()
        data = json.loads(response.read())
        conn.close()
        self.assertEqual((response.status, data), (403, {"error": "bad token"}))


class BadContentLength(ServerCase):
    def _post_with_length(self, length_header):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        sent = {
            "Host": f"127.0.0.1:{self.port}",
            "X-Orchestra-Token": self.token,
            "Content-Type": "application/json",
            "Content-Length": length_header,
        }
        conn.request("POST", "/api/phases/B2/status", body=b'{"status": "paused"}', headers=sent)
        response = conn.getresponse()
        data = json.loads(response.read())
        conn.close()
        return response.status, data

    def test_non_numeric_content_length_is_400(self):
        self.assertEqual(self._post_with_length("abc"), (400, {"error": "bad Content-Length"}))

    def test_negative_content_length_is_400(self):
        self.assertEqual(self._post_with_length("-5"), (400, {"error": "bad Content-Length"}))


class ValidationTypeSafety(ServerCase):
    def test_unhashable_or_wrong_type_json_values_are_400_not_500(self):
        decision = {"phase": ["B3"], "text": "x", "affects": [], "source": "s"}
        self.assertEqual(self.request("POST", "/api/decisions", decision)[0], 400)
        self.assertEqual(self.request("POST", "/api/phases/B2/status", {"status": {}})[0], 400)
        self.assertEqual(self.request("POST", "/api/queue/reorder", {"slice": "B3a", "direction": ["up"]})[0], 400)


class ValidateFunctionsRejectNonStrings(unittest.TestCase):
    """Every lookup that tests membership against a collection checks the type first —
    some of these (L.PHASES is a dict) raise TypeError on an unhashable value otherwise."""

    def test_non_string_inputs_raise_bad_request_not_type_error(self):
        for fn, bad in ((v.phase, ["B3"]), (v.status, {}), (v.mode, ["auto"]), (v.effort, {}), (v.direction, ["up"])):
            with self.assertRaises(BadRequest):
                fn(bad)

    def test_a_non_string_item_in_a_phases_list_raises_bad_request(self):
        with self.assertRaises(BadRequest):
            v.phases([["B3"]])


class StaticPathEdgeCases(ServerCase):
    def test_a_null_byte_in_the_path_falls_back_to_index_not_500(self):
        (self.base / "dist" / "index.html").write_text("<html><head></head></html>")
        request = f"GET /\x00 HTTP/1.1\r\nHost: 127.0.0.1:{self.port}\r\nConnection: close\r\n\r\n".encode("latin-1")
        raw = _raw_exchange(self.port, request)
        self.assertEqual(_status_of(raw), 200)
        self.assertIn(b"orchestra-token", raw)

    def test_a_symlink_pointing_outside_dist_serves_index_not_the_target(self):
        (self.base / "dist" / "index.html").write_text("<html><head></head></html>")
        outside = self.base / "secret.txt"
        outside.write_text("do not serve me")
        (self.base / "dist" / "escape").symlink_to(outside)
        status, body = self.request("GET", "/escape")
        self.assertEqual(status, 200)
        self.assertIn("orchestra-token", body)
        self.assertNotIn("do not serve me", body)

    def test_post_to_a_static_path_is_404(self):
        self.assertEqual(self.request("POST", "/")[0], 404)


class RawProtocolEdgeCases(ServerCase):
    def test_a_missing_host_header_is_refused(self):
        request = b"GET /api/state HTTP/1.1\r\nConnection: close\r\n\r\n"
        raw = _raw_exchange(self.port, request)
        self.assertEqual(_status_of(raw), 403)

    def test_an_origin_of_null_is_refused(self):
        status, data = self.request("GET", "/api/state", headers={"Origin": "null"})
        self.assertEqual((status, data), (403, {"error": "bad origin"}))


class MethodNotAllowed(ServerCase):
    def test_a_known_path_with_the_wrong_method_is_405(self):
        self.assertEqual(self.request("GET", "/api/queue/next"), (405, {"error": "method not allowed"}))
        self.assertEqual(self.request("POST", "/api/state"), (405, {"error": "method not allowed"}))
