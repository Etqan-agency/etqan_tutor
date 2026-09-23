---
name: shared-signaling-service
phase: C
modules: [scheduling]
status: shipped
created: 2026-09-07
closed: 2026-09-07
---

## Goal

A session can become permanently unjoinable, silently, and it happened on staging today.
`Room.signaling_url` pins a room to the deploy colour that created it; `ship.sh` removes the
old colour's signaling container on every colour flip, taking its Traefik router with it. Any
room created before a deploy then points at a hostname that no longer routes, and because
`_ensure_room` reuses an `ACTIVE` row indefinitely, every future join re-reads the dead pin.

This spec removes the condition that makes that possible: signaling stops being deployed
blue-green and becomes a shared service on one hostname, like `coturn` already is.

## What actually broke, on 2026-09-07

Merging the session UI redesign flipped staging green → blue. Afterwards:

| Check | Result |
| --- | --- |
| DNS + TLS, both colours | fine — both resolve, certificates verify |
| `ws-blue-staging` | `server: uvicorn` — the app answers |
| `ws-green-staging` | Traefik's own `404 page not found`, no `server` header — no router exists |
| `/opt/kaleem/.active-color` | `blue` |
| `docker ps -a --filter name=signaling` | only `kaleem-signaling-blue-1` — green was removed |
| `Room` row, session 5 | `active`, pinned `wss://ws-green-staging.kaleem.academy` |

Sessions 3 and 5 were both stranded. Session 4's active room happened to be pinned to blue and
kept working. The client's only symptom is a WebSocket that never opens — no close code, no
error naming the cause.

This is `ISSUES.md`'s *"An ACTIVE room outlives the colour it was pinned to (C3a/C3c)"*, logged
earlier the same day and re-triggered by the next deploy, exactly as that entry predicted.

## Why the obvious fix is wrong

"At join time, if the pin does not match my own `SIGNALING_URL`, re-pin it" reintroduces the
bug C3c exists to prevent. `django-blue` and `django-green` **both** claim `Host(${API_DOMAIN})`,
so during a deploy two participants of one lesson can be served by different Djangos. Each would
re-pin toward its own colour, and the two would land in separate one-peer rooms — "no
`peer-joined`, no error and no close code".

Any liveness check therefore needs a shared source of truth about the active colour, not each
process's own environment. That is a second mechanism to keep correct. This spec removes the
need for one instead.

## The change

`signaling-blue` and `signaling-green` are byte-identical apart from name, profile and host.
They collapse into a single `signaling` service in the shared block beside `traefik`, `postgres`,
`redis`, `flower` and `coturn`, with one Traefik router on a new `${WS_DOMAIN}`.

- Both `django-blue` and `django-green` get the same `DJANGO_SIGNALING_URL=wss://${WS_DOMAIN}`.
- `ship.sh`: `signaling` joins the shared `up -d` line (step 4) and leaves the colour start and
  stop lists (steps 5 and 8). Its health check retargets the shared container.
- The `${WS_DOMAIN:?...}` guard form stays. It is what turns an unset variable into a failed
  deploy rather than a router matching the truthy string `wss://` — a real Critical from C3c.
- `WS_BLUE_DOMAIN` / `WS_GREEN_DOMAIN` are deleted once nothing references them.

## Why this fixes it rather than defending against it

A signaling room is **created implicitly by the first peer to connect**: `create_room` does no
I/O, and room membership is a process-local dict in the relay.

So with exactly one signaling host, a stale `ACTIVE` row stops being a problem. The URL it
carries is still correct, and the first joiner recreates the in-process room on connect. The row
self-heals.

That is the whole argument for this shape:

- No deploy-time room ending.
- No liveness check, and no shared active-colour lookup to keep correct.
- The split-room bug becomes unreachable too — two participants cannot be handed different
  signaling hosts when only one exists.

The failure class stops existing rather than being handled.

## `Room.signaling_url` stays

Every row will now hold the same value, which makes the column look like dead weight. It stays:
it costs nothing, it records where a room actually lives, and it is the tripwire if per-host
signaling is ever reintroduced. Removing it would mean reading settings at join time again,
which is what C3c moved away from. The reason for the guard is gone; the guard is cheap.

## Existing rows

A one-off data migration ends **all** `ACTIVE` rooms.

Ending, not rewriting: after any deploy the in-process membership is gone, so `active` is
already a false statement about those rows. The next join mints a fresh, correct one. This is
the same operation as the by-hand workaround, done once and properly.

This does not contradict the self-healing property above, and the difference is worth stating.
Rows written *after* this change carry the shared host, so a stale one heals on its own. The
rows that exist *today* carry a per-colour host that will stop routing entirely once the
per-colour services are deleted, and nothing can heal those — hence the one-off migration.
It runs once and is not a recurring deploy step.

## Sequencing

Order is load-bearing; reversed, joins break mid-transition.

1. Stand up the shared `signaling` on `${WS_DOMAIN}`; confirm it serves and holds a certificate.
2. Repoint both Djangos at it.
3. Run the migration.
4. Only then delete `signaling-blue` / `signaling-green` and their variables.

## What this gives up

Independent rollback for signaling. A bad signaling release becomes a roll-forward, or a manual
`up -d signaling` pinned to an older image.

This is honest to what exists rather than a real loss: every deploy already drops every live
call, and `coturn` — which carries the media itself — is already shared on exactly these terms.

## Out of scope

- **A deploy still drops calls in progress.** That is the separate drain issue; it needs a
  join-routing switch that does not exist, and `docs/runbook/signaling.md`'s "deploy between
  lessons" rule still stands. This spec must not be read as fixing it.
- Making this failure class announce itself. The socket that never opens is still silent; that
  was considered and deliberately left out of scope.
- `Room.provider` being stored but never read (`ISSUES.md`), and the join endpoint's missing
  throttle. Both are adjacent and both stay open.

## Test plan

- Backend unit tests for `SignalingProvider` and the room pin, unchanged in shape.
- The import-linter contract from ADR-0035 (`kaleem` may import `signaling.tokens`, never the
  reverse) must stay green, and be verified by breaking it in both directions.
- The migration gets a test: an `ACTIVE` room pinned to any host ends, and a subsequent
  `_ensure_room` mints a fresh row at the configured host.
- Backend coverage floor holds at 97.7 (ADR-0026 ratchet; measure with
  `pytest --cov=kaleem --cov=signaling`, never a bare `pytest --cov`).

## What this spec cannot prove

**CI cannot catch the bug this fixes.** The `e2e` job runs its own signaling on `:9000` and
never exercises Traefik routing, per-colour hostnames, or blue-green at all. The defect lived in
the gap between a compose file and the process that consumes it — the same gap that produced
all five C3c Criticals, none of which any test found.

Verification is therefore a live staging check, and it is as much the deliverable as the code:
deploy, flip the colour, and confirm a session whose room was created **before** the flip is
still joinable **after** it. Mutation-check it by confirming the same session is unjoinable on
the current code.

## Open questions

None. The two decisions this rests on — that signaling need not stay blue-green deployable, and
that the drain stays out of scope — were both settled before this spec was written.
