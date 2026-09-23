---
number: 0035
title: Split signaling out as its own service (escape hatch E5)
status: accepted
date: 2026-09-06
---

## Context

ADR-0034 committed kaleem to building its own 1-on-1 WebRTC service. C3a shipped the room
lifecycle, the authorization guarding it, and a provider seam behind a fake. C3b is signaling:
the long-lived connection over which two browsers exchange offers, answers and ICE candidates.

Signaling does not fit how kaleem is served today. Production runs
`gunicorn config.wsgi --workers 3` in blue/green pairs. WSGI has no WebSocket; `config/asgi.py`
exists and nothing serves it. Three process models were considered, and the user chose the third.

## Decision

**Signaling runs as its own deployable service, not inside the Django API.** This is escape
hatch **E5** (modular monolith → service split), taken deliberately.

**It is Python, in the `backend` repository, sharing the backend image and differing only in its
command.** That buys E5's operational separation — its own container, its own scaling, its own
health check, its own blue/green pair — without a second language, a second dependency
ecosystem, or a second CI lane.

**It is not a Django app.** It is a standalone ASGI application that imports no Django, touches
no ORM, and holds no database connection. Its only inputs are the socket and a signed token.
An `import-linter` contract enforces that, the same way module boundaries are enforced
elsewhere: a signaling module importing `kaleem.*` fails CI.

**Authentication crosses the boundary as a signed capability token, not a session.** A separate
process cannot read Django's session cookie usefully, so `billing`-style shared state is out.
Django mints an HMAC-signed, room-scoped, expiring token; signaling verifies it with a shared
secret and nothing else. The codec is pure stdlib and Django-free, imported by both sides, so
the two cannot disagree about the format.

This is **not** ADR-0003's prohibition on JWT being reversed. ADR-0003 forbids bearer tokens as
*user authentication for the API*, and that stands: the API is still session cookies plus CSRF.
This is a capability scoped to one room, one participant, and a few minutes.

## Alternatives considered

**Serve the whole API over ASGI** (uvicorn/daphne on `config.asgi`). One process model, one
image, one Traefik route, no duplication — the smallest operational change. Rejected by the
user. Worth recording why it was tempting and why it is also risky: every existing HTTP path
would move onto async plumbing to serve WebSockets that one feature needs, sync views would run
in a threadpool, and streaming, timeouts and middleware ordering all shift. That is the whole
API's risk surface — billing, auth, booking — for one screen's benefit.

**A second Django process running Channels on `config.asgi`, split by path.** Keeps HTTP on
gunicorn untouched and adds a WS container. Less isolation than E5 (it still loads Django, the
ORM and every app), but no new boundary to authenticate across. Rejected by the user in favour
of a genuine split.

**Node or Go.** Node is the mainstream WebRTC signaling ecosystem; Go is materially better per
socket. Both add a language to the repository, a dependency-audit surface, and a second
implementation of token verification. Rejected because 1-on-1 lessons bound concurrent sockets
by concurrent lessons — hundreds, not tens of thousands — so per-socket performance is not the
constraint, and will not be for a long time.

## Consequences

**Good.**

- The API keeps the process model that already works. A signaling crash costs video, not
  billing, booking or auth.
- Signaling scales on its own axis. Long-lived connections and request/response have genuinely
  different shapes, which is the half of E5's trigger that actually fits.
- **It forces the join grant to become real.** C3a shipped a grant that nothing validates, with
  a forgeable token, logged in `ISSUES.md` under *Blocks launch*. A separate service cannot ask
  the database whether a grant is genuine, so the token must be signed and verified — closing
  that entry as a precondition of this phase rather than a later cleanup.

**Bad, or at least owed.**

- **E5 says "requires a full ADR with evidence", and the evidence here is architectural, not
  observed.** There is no production, no users, and no measured deploy-cycle pain. The honest
  statement is that this is the right shape for the workload, not that the trigger fired. That
  is a weaker case than the roadmap asks for, and it is recorded rather than dressed up.
- A second service to deploy, health-check, and run blue/green. `infra`'s compose file gains a
  pair, and `ship.sh` gains a colour to swap.
- A shared secret becomes load-bearing. If `DJANGO_SIGNALING_SECRET` differs between the two
  containers, every join fails authentication with a correct-looking token — a deployment
  failure mode that did not exist before, and one that must be caught by a health check rather
  than by a user in a lesson.
- The e2e harness gains a process. CI must start signaling alongside Django and the dashboard.
- **A dead end is now possible:** if concurrency ever does outgrow Python, the rewrite is a
  service replacement rather than a library swap. That is the cost E5 warns about, accepted
  knowingly.

**Neutral.**

- Redis is already present for Celery and the cache. If signaling later needs to span more than
  one replica, the fan-out layer costs no new infrastructure — but C3b is deliberately
  single-replica per colour, so it does not need one yet.
