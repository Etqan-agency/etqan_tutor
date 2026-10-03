"""Routes that run commands (spec 2026-10-03 §4.2)."""

from . import phases, sessions
from . import validate as v
from .errors import BadRequest
from .routing import route

PHASE = r"/api/phases/(?P<code>B\d+)"


@route("POST", PHASE + "/launch")
def launch(req):
    code = v.phase(req.params["code"])
    return phases.launch(
        code, v.suffix(req.body.get("suffix")), v.slot(req.body.get("slot")), v.mode(req.body.get("mode"))
    )


@route("POST", r"/api/(?:phases/(?P<code>B\d+)|(?P<conductor>conductor))/session/(?P<action>start|stop|restart)")
def session(req):
    who = "conductor" if req.params.get("conductor") else v.phase(req.params["code"])
    action = req.params["action"]
    if action == "stop":
        sessions.stop(who)
        return {"ok": True}
    mode = v.mode(req.body.get("mode"))
    if action == "restart":
        return {"ok": True, "id": sessions.restart(who, mode)}
    return {
        "ok": True,
        "id": sessions.start(who, mode, v.model(req.body.get("model")), v.effort(req.body.get("effort"))),
    }


@route("GET", r"/api/(?:phases/(?P<code>B\d+)|(?P<conductor>conductor))/log")
def log(req):
    who = "conductor" if req.params.get("conductor") else v.phase(req.params["code"])
    return {"text": sessions.log(who)}


@route("POST", PHASE + "/slot")
def slot(req):
    return phases.move_slot(v.phase(req.params["code"]), v.slot(req.body.get("slot"), allow_zero=True))


@route("POST", PHASE + "/stack")
def stack(req):
    up = req.body.get("up")
    if not isinstance(up, bool):
        raise BadRequest("up must be true or false")
    return phases.stack(v.phase(req.params["code"]), up)


@route("POST", PHASE + "/teardown")
def teardown(req):
    return phases.teardown(v.phase(req.params["code"]), req.body.get("confirm"))
