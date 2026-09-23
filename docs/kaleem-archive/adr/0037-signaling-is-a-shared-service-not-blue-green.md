# ADR-0037: Signaling is a shared service, not blue-green

**Status:** Proposed
**Date:** 2026-09-07
**Supersedes:** the per-colour signaling clause of ADR-0035 (which stands otherwise)
**Related:** ADR-0028 (trunk-based, a merge to master is a deploy), `ISSUES.md` "An ACTIVE room
outlives the colour it was pinned to"

## Context

C3b gave signaling its own service (ADR-0035) and deployed it blue-green alongside Django, one
container and one hostname per colour. C3c then found that per-colour hostnames alone were not
enough: `django-blue` and `django-green` both claim `Host(${API_DOMAIN})`, so two participants
in one lesson can be served their join grants by different Djangos and handed different
signaling hosts, each landing alone in a one-peer room with no `peer-joined`, no error and no
close code. The fix was `Room.signaling_url` — the room itself is pinned to one host at
creation, and every later joiner reads the row.

That pin is correct and it works. What it does not survive is the colour going away.

`ship.sh` step 8 stops and removes the old colour's signaling container after a switch, and
Traefik's router lives on that container. A room created before a deploy then points at a
hostname that no longer routes. `_ensure_room` reuses an `ACTIVE` row indefinitely, so the
session is not merely interrupted — it is **permanently unjoinable**, and the client's only
symptom is a WebSocket that never opens.

This was hit on staging on 2026-09-07, twice: once by hand during the C3d call setup, and again
when the session UI redesign merge flipped green → blue and stranded sessions 3 and 5.

The obvious repair — re-pin at join time when the pin does not match the current setting — is
wrong. During a deploy each Django believes its own colour is live, so the two participants
re-pin in opposite directions and the C3c bug returns. A correct liveness check needs a shared
source of truth about the active colour: a second mechanism, to keep correct forever, guarding
a condition we can instead delete.

## Decision

**Signaling is deployed as a shared service on one hostname, not per colour.**

One `signaling` container sits in the shared block beside `traefik`, `postgres`, `redis`,
`flower` and `coturn`. Both Djangos are configured with the same `DJANGO_SIGNALING_URL`.
`ship.sh` starts it with the other shared services and never stops it as part of a colour flip.

`Room.signaling_url` is kept. Every row now holds the same value, so it can no longer be wrong,
but it still records where a room lives and remains the tripwire if per-host signaling is ever
reintroduced.

## Consequences

**The failure class stops existing rather than being handled.** A signaling room is created
implicitly by the first peer to connect — `create_room` does no I/O and membership is a
process-local dict — so with one host a stale `ACTIVE` row self-heals: its URL is still correct
and the first joiner recreates the in-process room. No deploy-time room ending, no liveness
check, no shared active-colour lookup. The split-room bug becomes unreachable as well, since two
participants cannot be given different hosts when only one exists.

**Signaling loses independent rollback.** A bad signaling release is a roll-forward, or a manual
`up -d signaling` pinned to an older image. This is honest to what exists rather than a real
loss: every deploy already drops every live call, and `coturn`, which carries the media itself,
is already shared on exactly these terms.

**A deploy still drops calls in progress.** That is a separate, still-open problem needing a
join-routing switch that does not exist. `docs/runbook/signaling.md`'s "deploy between lessons"
rule stands. This ADR must not be read as fixing it.

**CI cannot verify this decision.** The `e2e` job runs its own signaling on `:9000` and never
exercises Traefik routing or blue-green. The defect lived in the gap between a compose file and
the process that consumes it — the same gap that produced all five C3c Criticals, none of which
any test found. Verification is a live staging check: flip the colour and confirm a session
whose room predates the flip is still joinable.

## Alternatives considered

**Re-pin at join time against a shared active-colour source** (the `.active-color` file, or
Redis). Keeps blue-green signaling, but adds a second correctness-critical mechanism and keeps
alive the exact condition that produced two Criticals in two days. Rejected: the state is the
bug, not the handling of it.

**End all `ACTIVE` rooms as part of every deploy.** Small and it works, but it treats the symptom
on a schedule — a room orphaned by anything other than a deploy stays orphaned, and it leaves
the split-room condition standing.

**Keep the old colour's signaling alive until its rooms empty.** This is the real drain, and it
is the right long-term answer to dropped calls — but it needs the join-routing switch that does
not exist, and it does not remove the pin-versus-colour coupling. Out of scope here; still open.
