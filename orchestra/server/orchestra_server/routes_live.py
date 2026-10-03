"""The event stream and CI (spec 2026-10-03 §4.2)."""

import queue

from . import ci
from .events import HUB
from .ledger_api import read
from .routing import STREAMED, route

PING_SECONDS = 15


@route("GET", "/api/events")
def events(req):
    handler = req.handler
    handler.send_response(200)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-store")
    for name, value in handler.security_headers().items():
        handler.send_header(name, value)
    handler.end_headers()
    q = HUB.subscribe()
    try:
        handler.wfile.write(b": connected\n\n")
        handler.wfile.flush()
        while True:
            try:
                handler.wfile.write(f"event: {q.get(timeout=PING_SECONDS)}\ndata: {{}}\n\n".encode())
            except queue.Empty:
                handler.wfile.write(b": ping\n\n")
            handler.wfile.flush()
    except OSError:
        pass  # the page went away
    finally:
        HUB.unsubscribe(q)
    return STREAMED


@route("GET", "/api/ci")
def ci_status(req):
    return ci.cached(read())
