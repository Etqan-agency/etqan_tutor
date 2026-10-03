"""The HTTP server: guards, routing, JSON and the built web page (spec 2026-10-03 §4)."""

import json
import mimetypes
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from . import config
from .errors import BadRequest, Forbidden, HttpError, NotFound
from .ledger_api import LedgerError
from .routing import ROUTES, STREAMED, Request, route

MAX_BODY = 1_000_000


@route("GET", "/api/token")
def dev_token(req):
    """Only for `just orchestra-dev`, where Vite (not the server) serves index.html."""
    if not config.dev():
        raise NotFound()
    return {"token": req.handler.server.token}


class Handler(BaseHTTPRequestHandler):
    server_version = "Orchestra"

    def log_message(self, format, *args):  # noqa: A002 — quiet; the page shows errors
        pass

    def do_GET(self):  # noqa: N802
        self._dispatch("GET")

    def do_POST(self):  # noqa: N802
        self._dispatch("POST")

    def _guard(self, method: str) -> None:
        port = self.server.server_port
        hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        if self.headers.get("Host") not in hosts:
            raise Forbidden("bad host")
        origin = self.headers.get("Origin")
        if origin is not None and origin not in {f"http://{host}" for host in hosts}:
            raise Forbidden("bad origin")
        sent = self.headers.get("X-Orchestra-Token", "")
        if method != "GET" and not secrets.compare_digest(sent, self.server.token):
            raise Forbidden("bad token")

    def _dispatch(self, method: str) -> None:
        url = urlsplit(self.path)
        try:
            self._guard(method)
            if not url.path.startswith("/api/"):
                if method != "GET":
                    raise NotFound()
                self._static(url.path)
                return
            for wanted, pattern, handler in ROUTES:
                match = pattern.match(url.path)
                if match and wanted == method:
                    body = self._body() if method == "POST" else {}
                    result = handler(Request(self, match.groupdict(), parse_qs(url.query), body))
                    if result is not STREAMED:
                        self._json(200, result)
                    return
            raise NotFound()
        except HttpError as error:
            self._json(error.status, error.payload)
        except LedgerError as error:
            self._json(409, {"error": str(error)})
        except Exception as error:  # noqa: BLE001 — shown on the page, never swallowed
            self._json(500, {"error": f"{type(error).__name__}: {error}"})

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            raise BadRequest("body too large")
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            raise BadRequest("body is not JSON") from None
        if not isinstance(body, dict):
            raise BadRequest("body must be a JSON object")
        return body

    def _send(self, status: int, content_type: str, data: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, status: int, payload) -> None:
        self._send(status, "application/json", json.dumps(payload).encode())

    def _static(self, path: str) -> None:
        root = config.web_dist().resolve()
        index = root / "index.html"
        target = (root / path.lstrip("/")).resolve()
        if not target.is_relative_to(root) or not target.is_file():
            target = index
        if not target.is_file():
            self._send(
                503, "text/plain; charset=utf-8", b"The web app is not built: start Orchestra with `just orchestra`."
            )
            return
        data = target.read_bytes()
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        if target == index:
            meta = f'<meta name="orchestra-token" content="{self.server.token}">'.encode()
            data = data.replace(b"</head>", meta + b"</head>", 1)
            content_type = "text/html; charset=utf-8"
        self._send(200, content_type, data)


class OrchestraServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False  # open SSE streams must not hold a shutdown

    def __init__(self, port: int, token: str):
        super().__init__(("127.0.0.1", port), Handler)
        self.token = token


def make_server(port: int, token: str) -> OrchestraServer:
    from . import routes_ledger  # noqa: F401 — registers its routes

    return OrchestraServer(port, token)


def main() -> None:
    server = make_server(config.port(), secrets.token_urlsafe(32))
    print(f"Orchestra: http://127.0.0.1:{server.server_port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
