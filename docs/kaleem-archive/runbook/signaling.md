# Signaling Runbook

## What it is

The signaling service is a standalone WebSocket relay that lets the two
participants of a 1-on-1 lesson exchange WebRTC negotiation messages (SDP
offers/answers, ICE candidates) so their browsers can open a direct peer
connection. It ships in the same backend image as Django but runs as its own
process (`uvicorn signaling.app:app`), imports no Django, and has no database
and no ORM (ADR-0035).

**What it is not:** it does not carry any lesson media. Audio and video flow
peer-to-peer between the two browsers once negotiation completes; the
signaling service never sees a media byte. It only relays small JSON control
messages (`offer`, `answer`, `ice`, `media-state`) between exactly two sockets in a room, and
drops a message rather than queuing it if the other peer is not there.

## Environment variables

| Variable | Set on | Purpose |
| --- | --- | --- |
| `DJANGO_SIGNALING_SECRET` | both the API (Django) container and the signaling container | HMAC key used to mint (API) and verify (signaling) the short-lived, room-scoped join token. **Must be byte-for-byte identical in both containers.** |
| `DJANGO_SIGNALING_URL` | the API container only, **set in `docker-compose.production.yml`, not in `.env.production`** | The public base URL of the signaling service, used to build the `join_url` handed to each participant. As of ADR-0037 both Django colours are given the **same** value, `wss://${WS_DOMAIN}`, via each colour's `environment:` block (which takes precedence over `env_file:`). That used to be exactly the bug — a shared value straddling two independent signaling hosts — but signaling is no longer two independent hosts: there is one shared replica, so both colours pointing at the same URL is now correct. |
| `DJANGO_TURN_SECRET` | the API (Django) container **and** coturn | HMAC key for the ephemeral TURN credentials. One entry in `.env.production` feeds both; coturn receives it as a `--static-auth-secret` command-line argument (see `docs/runbook/turn.md` for why it cannot live in `turnserver.conf`). |
| `DJANGO_TURN_URLS` | the API container only | Comma-separated ICE URLs handed to the browser. Absent, `SignalingProvider` refuses to start. |
| `DJANGO_VIDEO_PROVIDER` | the API container only | Must be `kaleem.scheduling.providers.signaling_provider.SignalingProvider`. It **defaults to `FakeVideoProvider`**, whose join URLs point at nothing — so leaving it unset deploys a healthy, routable signaling service that no lesson can reach. This failure is silent: every gate stays green. |

All of these live in the hand-managed
`.env.production` on the VPS and are listed in
`infra/.env.production.example`. **`.env.production.example` is a template on
disk, not a deployment mechanism** — adding a variable there does not put it on
the server. `docs/runbook/deploy.md` has the diff command to run before
deploying.

`WS_DOMAIN` is a single variable used only by `docker-compose.production.yml`
— to build the Traefik `Host()` rule for the shared `signaling` service, and
to build both Django colours' `DJANGO_SIGNALING_URL` (the same value for
each). It is not read by the application itself. It lives in the
hand-managed `.env.production` on the VPS, the same file that holds
`API_DOMAIN`, `DASHBOARD_DOMAIN`, etc. There is no `.env.production` in git;
it is created by hand on first VPS setup (see `docs/runbook/deploy.md`) and
edited by hand thereafter.

⚠ **`WS_DOMAIN` was retired between C3c and 2026-09-07, then reinstated as a
single shared host under ADR-0037 — the name is the same, the meaning is
not.** C3c replaced it with `WS_BLUE_DOMAIN`/`WS_GREEN_DOMAIN` (one hostname
per deploy colour) specifically to stop two participants landing on
different signaling processes. That per-colour scheme created a worse bug:
`Room.signaling_url` pins a room to the colour that created it, `ship.sh`
removed the *old* colour's signaling container on every flip, and
`_ensure_room` reuses an `ACTIVE` row forever — so a session created before a
deploy became permanently unjoinable, silently, with no close code and
nothing naming the cause. Hit live on staging 2026-09-07. ADR-0037's fix is
not a revert to the pre-C3c bug: signaling is now **one shared, never-stopped
replica** (see "Deployment" below), so a single hostname no longer risks
splitting a room the way it did before C3c — there is only one process to
land on.

If a VPS carries the retired `WS_BLUE_DOMAIN`/`WS_GREEN_DOMAIN` pair and not
`WS_DOMAIN`, the deploy aborts rather than shipping broken:
`docker-compose.production.yml` requires `WS_DOMAIN` via Compose's
`${VAR:?message}` syntax, so `docker compose up` for a missing value fails
outright before any container starts.

Diff `.env.production` against `infra/.env.production.example` before
deploying.

## Changing `WS_DOMAIN` after go-live

⚠ **Editing `WS_DOMAIN` on the VPS strands every currently-`ACTIVE` room, the
same failure class ADR-0037 fixed for deploys — reopened here for this one
operator action, because ADR-0037 only made both deploy colours agree with
each other, not with a value an operator changes by hand.**

`Room.signaling_url` is pinned at creation and `get_join_url` prefers it over
`settings.SIGNALING_URL` (see the comment on `signaling_provider.py`'s
`get_join_url` for why: re-reading settings at join time is the split-room bug
C3c removed, and this code intentionally does not do it). `_ensure_room`
reuses an `ACTIVE` `Room` row forever rather than minting a new one. So a
`Room` created under the old `WS_DOMAIN` keeps handing out `wss://<old
host>/...` join URLs indefinitely after the hostname changes underneath it —
permanently unjoinable, silently, with no close code and nothing naming the
cause. This is a **deliberate non-fix**: healing it automatically (e.g.
ending stale rooms on a schedule) is exactly the "treat the symptom
recurringly instead of fixing the cause" pattern ADR-0037 rejected for the
deploy case. The fix here is procedural, not code.

**Before changing `WS_DOMAIN`, end every `ACTIVE` room.** On the VPS, in a
Django shell (`docker exec -it kaleem-django-<colour>-1 python manage.py
shell_plus`, or equivalent):

```python
from django.utils import timezone
from kaleem.scheduling.models import Room

active = Room.objects.filter(status=Room.Status.ACTIVE)
count = active.count()
active.update(status=Room.Status.ENDED, ended_at=timezone.now())
print(f"Ended {count} active room(s).")
```

Run this **before** the deploy that changes `WS_DOMAIN` lands, ideally during
the same "deploy between lessons" window the rest of this runbook already
calls for. Any lesson genuinely in progress at that moment will need to
reload — same as the existing "deploys drop live calls" trade-off below, not
a new one. `_ensure_room` will mint a fresh `Room` pinned to the new
`WS_DOMAIN` the next time each session's participants join.

## Rotating the shared secret

The secret is not per-environment-variable-only — it is a **pair**, and both
halves of the pair must change together:

1. Generate a new value.
2. Update `DJANGO_SIGNALING_SECRET` in `.env.production` on the VPS (the one
   file both the `django-*` services and the shared `signaling` service read
   via `env_file`).
3. Redeploy (`bash scripts/ship.sh <sha>`), which recreates the new colour's
   Django containers and, since `signaling` is a shared service that every
   deploy re-applies (see "Deployment" above), also recreates the signaling
   container with the updated value.

Because a join token is signed with the secret at the moment a student or
teacher opens the lesson page, **every outstanding, unused token becomes
invalid the instant the secret changes** — there is no overlap window where
old and new secrets are both honoured. A participant who has an open lesson
page but has not yet joined the socket will get `CLOSE_UNAUTHORIZED` (4401) if
they try to join after a mid-lesson rotation. Rotate the secret **between
lessons** (e.g. during the nightly deploy window), never while lessons using
the current secret might still be starting.

## Close codes

## ⚠ Adding a message type is a deploy-ordering constraint

`RELAYABLE` in `signaling/app.py` is an allowlist, and a frame whose `type` is
outside it does not get ignored -- the socket is **closed with `4400`**. That is
the right default (a frame we do not recognise is a bug or an attack, never a
version to tolerate), but it means the protocol can only ever be widened in one
direction:

**The relay deploys first, always.** A client bundle that sends a type the
running relay does not know drops the lesson it is in, the first time anyone
triggers it. Ship the `RELAYABLE` change, deploy it, confirm it live, and only
then ship the client that sends the new type.

The reverse is safe: a relay that knows a type no client sends yet simply never
sees one.

This has happened once deliberately -- `media-state` (C5, 2026-09-12), which
tells the other peer that a camera was released or a screen share stopped.
Neither is otherwise detectable: the receiving `<video>` freezes on its last
frame and keeps reporting it, with no `resize`, no `emptied`, and
`track.muted` still `false`.

The signaling service closes a WebSocket with one of these application close
codes (4000–4999 range, distinct per reason so a client can tell "fetch a new
token" apart from "this lesson is already full"):

| Code | Meaning |
| --- | --- |
| `4401` (`CLOSE_UNAUTHORIZED`) | The token is missing, malformed, expired, has a bad signature (secret mismatch), or is signed for a different room than the one being joined. |
| `4409` (`CLOSE_ROOM_FULL`) | A third connection tried to join a room that already has its two participants (1-on-1 only; `MAX_PEERS = 2`). |
| `4400` (`CLOSE_BAD_MESSAGE`) | A connected peer sent a frame that was not valid JSON, whose `type` was not one of `offer` / `answer` / `ice` / `media-state`, or that was a **binary** frame (this service speaks JSON text only). |
| `4410` (`CLOSE_REPLACED`) | **Not an error.** This participant opened a newer socket — a reconnect, or a second tab — and it took over their seat in the room. The *older* socket receives this code. |

A peer simply disconnecting (going away, closing the tab) is not an error —
it is the ordinary way a call ends, and it is not reported through these
codes.

### One participant, one seat

A room slot belongs to a **participant** (`user_id` from the token), not to a
socket. A second socket authenticated for a `user_id` already in the room
**replaces** the first: the older socket is closed with `4410`, the newer one
takes the seat, and the room's occupancy does not change. The other
participant sees a fresh `peer-joined` (renegotiation has to restart against
the new socket) and **no** `peer-left` — nobody left.

This is deliberate. Counting sockets instead of people meant one student
opening a second tab filled the 1-on-1 room and locked their teacher out with
`4409`, recoverable only by finding and closing a tab they had no reason to
connect with the failure. Three *distinct* participants are still refused with
`4409`; the cap is unchanged.

A client receiving `4410` should tell the user they are connected in another
tab or window, and must **not** retry — a retry loop between two tabs would
displace each other forever.

### Why five refusal reasons share one close code

The C3b spec's test plan says "each with its own close code", and the
implementation deliberately does not do that. Five distinct refusals —
missing token, malformed token, bad signature (secret mismatch), expired
token, and a token signed for a different room — all close with `4401`.

That is the better security choice, not an oversight. A distinct code per
reason is an oracle: it tells an unauthenticated caller whether a signature
was valid but stale, whether a room exists, or whether they guessed a real
room id with a wrong key — exactly the feedback needed to work a token
forgery attempt incrementally. The client has nothing to do differently in
any of the five cases: the action is always "fetch a new join grant".

**The distinction is not lost, it is moved server-side.** Every refusal is
logged at WARNING by `signaling.app` with its reason
(`signaling.tokens.TokenError` keeps four separate messages precisely for
this), so an operator can still tell a shared-secret mismatch (*every* join
logs "bad signature") from clock skew (*every* join logs "expired"). See
"Reading the logs" below.

## Deployment: one shared replica

As of ADR-0037 (2026-09-07), signaling is a **single shared service** —
`signaling`, container `kaleem-signaling-1` — started alongside the other
shared services (`traefik`, `postgres`, `redis`, `flower`, `coturn`) in
`scripts/ship.sh` step 4, and it is **never stopped by a colour flip**: it
carries no `--profile` and does not appear in either colour's service list,
including the step that used to stop the old colour. Before this it was
`signaling-blue` / `signaling-green`, one instance per deploy colour,
recreated and torn down on every flip — that per-colour split is what
produced the pinned-room bug described in "Environment variables" above.

The **single-replica constraint itself is unchanged and still matters**: room
membership (`RoomRegistry`) is an in-process, in-memory `dict` — there is no
shared store between processes. Two peers in the same lesson must land on the
same process, or neither can see the other join. What changed is *why* there
is one replica: it used to be one per colour (two processes total, kept apart
by per-colour hostnames); now it is one process, period, and there is no
second one to land on. If signaling is ever scaled beyond a single replica,
`RoomRegistry` needs a fan-out layer (e.g. Redis pub/sub) first; until that
lands, do not raise its replica count.

## Health check and its limit

The shared `signaling` service (container `kaleem-signaling-1`) exposes `GET
/health/live/` on port 9000. The check mints a token and immediately verifies
it using the container's own `DJANGO_SIGNALING_SECRET`, returning `503` if
the secret is missing or the round trip fails. This is what `scripts/ship.sh`
polls as part of "ensure shared services are running" — it is no longer tied
to promoting a colour, since signaling is not per-colour any more.

**What this proves:** the signaling container has *a* usable secret — it is
present, non-empty, and internally self-consistent.

**What this cannot prove:** that the secret is the *same* one the API
container holds. The check only ever mints and verifies against itself; it
has no way to reach into the `django-${NEW}` container and compare. A
deployment where `DJANGO_SIGNALING_SECRET` differs between the two containers
passes this health check on both sides and still fails every real join with
`CLOSE_UNAUTHORIZED`, because the API mints tokens with its own secret and
the signaling service verifies with a different one. Nothing in this
deploy process can catch that mismatch automatically — after changing the
secret, manually confirm both containers were updated from the same
`.env.production` and, ideally, do one real join test end-to-end before
calling a deploy done.

## Reading the logs

`docker logs kaleem-signaling-1`.

**The join token must never appear in a log line, and two things had to be
done to keep it out.**

uvicorn logs every WebSocket handshake at INFO with the path *and* its query
string, and that query string is the capability token — a replayable grant to
one child's lesson, valid for its full life, sitting in `docker logs` for
anyone with shell access. `--no-access-log` does **not** suppress it (that
switch only touches the `uvicorn.access` logger; the handshake line is on
`uvicorn.error`), and `--log-level warning` would only trade the leak for
blindness. The fix is `backend/signaling/logconf.py`, a `logging.Filter` that
rewrites the record before emit, installed via `--log-config
signaling/logconf.json` everywhere the service is started: `docker-compose.local.yml`
and, since ADR-0037 collapsed the per-colour pair into one shared service,
the single `signaling` service in `docker-compose.production.yml` (it used
to be both `signaling-blue` and `signaling-green`).

A correct log line looks like this — note `?REDACTED`:

```
INFO:     172.19.0.3:45532 - "WebSocket /ws/rooms/session-42?REDACTED" [accepted]
```

**If you ever see a `?t=` followed by anything in these logs, that is an
incident**: the `--log-config` flag has been dropped from a start command, and
every token logged since then should be treated as disclosed. There is no
revocation list — the only mitigation is rotating
`DJANGO_SIGNALING_SECRET` (see above), which invalidates every outstanding
token at once.

The gateway in front of the service logged the same thing separately: Traefik's
`RequestPath` access-log field is the full request URI, query string included.
`RequestPath: drop` in `infra/traefik/traefik.yml` removes it. Traefik has no
per-router access-log configuration and silently ignores `redact` for core
field names (both verified empirically against v3.6), so this is global and
**no route's path appears in the Traefik access log any more**; gunicorn's own
`--access-logfile -` carries per-request paths for the API instead.

Refusals are logged at WARNING with their reason and never with the token:

```
WARNING:  refused join to room session-42: bad signature
WARNING:  refused join to room session-42: expired
WARNING:  refused join to room session-42: token is for room session-999
WARNING:  refused join to room session-42: room is full
```

Read them in aggregate, not one at a time:

| Pattern | Almost certainly |
| --- | --- |
| *Every* join logs "bad signature" | `DJANGO_SIGNALING_SECRET` differs between the API and signaling containers. The health check cannot catch this — see above. |
| *Every* join logs "expired" | Clock skew between the API host and the signaling host, or the join window closing before a participant clicks through. `GRANT_TTL` no longer exists (C3c) — a grant's `expires_at` is now the join window's own close, `join_window(session)[1]`, so this means the window itself is too tight, not a separate constant. |
| Scattered "malformed token" | Usually crawlers and scanners hitting the endpoint. Only interesting in volume. |
| "token is for room X" | A real capability being replayed against a different room. Investigate. |

## Deploys drop live calls

This section used to be "Deploys drop live calls, and can split a room" and
covered two separate problems. **The split-room half is now structurally
impossible and this section no longer covers it. The dropped-calls half is
unchanged, still open, and is still the reason for the operational rule
below.**

**Room splitting: gone, not just fixed.** Through C3c, signaling ran as
`signaling-blue` / `signaling-green` — two independent processes — and a
colour overlap could hand a teacher and student to different ones with no
error at all. C3c's fix was per-colour hostnames plus `Room.signaling_url`
pinning a room to the colour that created it. That pin then caused a second
bug: a room created before a deploy kept pointing at a colour `ship.sh` had
since removed, and because `_ensure_room` reuses an `ACTIVE` row forever, the
session became permanently unjoinable — hit live on staging 2026-09-07. **As
of ADR-0037, signaling is one shared replica** (see "Deployment" above), not
two colour-scoped ones, so there is no second process for a participant to be
handed and no colour for a room's pin to outlive. `Room.signaling_url` still
exists and is still written and replayed the same way, but with a single
signaling host it can no longer disagree with the live deployment. This is
implemented and unit-tested; it has not yet been verified with a live
staging colour flip (the gate that would prove it — see `ISSUES.md`).

**A deploy still kills every call in progress. STILL OPEN.** This used to be
described as "step 8 stops the old colour" — that specific mechanism is gone,
since signaling is no longer part of either colour's service list and is
never stopped by a flip. But the underlying problem is unchanged: room
membership is an in-process dict with no drain, and `scripts/ship.sh` step 4
runs `docker compose up -d ... signaling` on **every** deploy. If that
command recreates the container — because a deploy actually changes the
signaling image, its compose definition, or its env — every room in it
closes at once, both participants' sockets die, and neither browser is told
why in a way it can recover from. This is now *worse* in blast radius than
before: there used to be an unaffected colour to fail over to; now there is
only one signaling process for the whole deployment, so a signaling redeploy
affects every live call, not half of them. Fixing this needs a join-routing
drain that does not exist yet (stop routing new joins, wait for rooms to
empty, then recreate). Tracked in `ISSUES.md` under *Blocks launch*.

**Operational rule, still in force: deploy between lessons.** Check the
schedule before shipping, especially before a deploy that touches the
signaling service itself. If you must ship during a lesson, expect to tell
those participants to reload.

## Related

- `docs/runbook/deploy.md` — general blue-green deploy flow (`scripts/ship.sh`)
- ADR-0035 — signaling as its own Django-free deployable
- ADR-0037 — signaling as one shared service instead of one per deploy colour
