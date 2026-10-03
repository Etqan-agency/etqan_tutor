"""Routes that only read or write the ledger (spec 2026-10-03 §4.2)."""

from . import validate as v
from .ledger_api import L, read, write
from .routing import route

OK = {"ok": True}


def build_state(data: dict) -> dict:
    free, codes = L.eligible(data)
    return {"ledger": data, "eligible": {"free": free, "phases": codes}}


@route("GET", "/api/state")
def state(req):
    return build_state(read())


@route("POST", r"/api/phases/(?P<code>B\d+)/status")
def phase_status(req):
    code = v.phase(req.params["code"])
    status = v.status(req.body.get("status"))
    write(f"phase {code} status {status}", lambda d: L.set_phase(d, code, status=status))
    return OK


@route("POST", "/api/queue/next")
def queue_next(req):
    return {"ok": True, "in_flight": write("queue next", L.take_next)}


@route("POST", "/api/queue/bounce")
def queue_bounce(req):
    sid = v.slice_id(req.body.get("slice"))
    reason = v.text(req.body.get("reason"), "reason")
    write(f"bounce {sid}", lambda d: L.bounce(d, sid, reason))
    return OK


@route("POST", "/api/queue/merged")
def queue_merged(req):
    sid = v.slice_id(req.body.get("slice"))
    heads = v.heads(req.body.get("heads"))
    write(f"merged {sid}", lambda d: L.mark_merged(d, sid, heads))
    return OK


@route("POST", "/api/queue/reorder")
def queue_reorder(req):
    sid = v.slice_id(req.body.get("slice"))
    direction = v.direction(req.body.get("direction"))
    write(f"reorder {sid} {direction}", lambda d: L.reorder(d, sid, direction))
    return OK


@route("POST", r"/api/escalations/(?P<id>E\d+)/resolve")
def resolve(req):
    eid = req.params["id"]
    answer = v.text(req.body.get("answer"), "answer")
    write(f"resolve {eid}", lambda d: L.resolve(d, eid, answer))
    return OK


@route("POST", "/api/decisions")
def decide(req):
    body = req.body
    phase = v.phase(body.get("phase"))
    text = v.text(body.get("text"), "text")
    affects = v.phases(body.get("affects", []))
    source = v.text(body.get("source"), "source")
    return {"ok": True, "id": write("decision", lambda d: L.decide(d, phase, text, affects, source))}


@route("POST", "/api/claims/release")
def release_claim(req):
    target = v.text(req.body.get("target"), "target")
    write(f"release {target} (forced)", lambda d: L.force_release(d, target))
    return OK


@route("POST", r"/api/requests/(?P<id>R\d+)/done")
def request_done(req):
    rid = req.params["id"]
    write(f"request {rid} done", lambda d: L.request_done(d, rid))
    return OK
