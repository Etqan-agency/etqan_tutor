---
name: phase-c3a-video-room
phase: C
modules: [scheduling, identity]
status: shipped
created: 2026-09-05
closed: 2026-09-05
---

## Goal

Give a `Session` a room, and let exactly the two people in that lesson — and nobody else —
into it.

C2 generates session rows and says so in its own model docstring: *"C3 hangs a join link on
it."* Today nothing does. A student and a teacher are matched, scheduled, and counted against
a quota, and when the hour arrives there is no way to meet.

C3a is the first of the video slices and it contains **no video**. It builds the room
lifecycle, the authorization that guards it, and the provider seam the real implementation
plugs into — all of it behind a fake provider, so the slice ships, is covered, and is
end-to-end tested before any external service or media code exists.

**Why this is its own spec.** Video decomposes into five slices whose dependency order is
strict (rooms → signaling → TURN → client → hardening). Specced together they produce a
branch that lives for weeks, which D6 and D11 both forbid. C3a is the slice that is
*independent of every remaining decision*: it does not change whether media ends up
peer-to-peer, on an SFU, or on a vendor.

## Decisions taken

Settled during brainstorming, recorded so the plan does not relitigate them:

1. **kaleem builds its own 1-on-1 WebRTC service; there is no Zoom.** This reverses ADR-0011
   and is recorded in **ADR-0034**, which supersedes it. C3a is unaffected by the reversal —
   that is the point of the seam — but the arc that follows it is entirely different work.
2. **1-on-1 only. Group sessions are deferred to their own later phase.** Peer-to-peer
   collapses past ~3 participants because every browser uploads a separate stream to every
   other participant; group needs an SFU, which is a media server and a second scaling axis.
   The roadmap lists group in v1 scope, so this is a real deviation and ADR-0034 records it.
3. **A parent may not join their child's lesson.** A parent is not a participant. Silent adult
   presence in a 1-on-1 between a child and a teacher is a safeguarding question rather than a
   feature toggle, and the permissive default is the one that cannot be taken back. Parents
   keep the visibility C1 and C2 already gave them: who the teacher is, when the lessons are,
   and what the quota looks like.
4. **A room is a row that happens over time, not a field on `Session`.** A provider failure, a
   reconnection, or a rescheduled lesson can each mean a second room for the same session.
   Rule #7 forbids the `OneToOneField` here for exactly this reason.
5. **Rooms are created lazily, on the first join.** Not eagerly for every session the C2
   generator writes. Eager creation provisions rooms for lessons nobody attends, and a room
   created three weeks early is a room most providers will have expired by the time it is
   used. No new beat task in this slice.
6. **A join URL is a capability, and is treated as one.** Per-user, short-lived, never stored
   on the session, never present in a list payload, never logged.

## Data model delta

```text
scheduling.Room                          (new)
    session      FK Session, CASCADE      # no independent existence
    provider     CharField                # which adapter created it
    external_id  CharField                # the provider's own id, always populated
    status       CharField                # active | ended
    created_at / ended_at

    UniqueConstraint(session, condition=Q(status="active"))   # one live room per session
```

The partial unique index is the same construction C2 used for the active slot: the invariant
"at most one live room per session" is enforced by the database rather than by a service that
remembers to check. `NULL`s are distinct in a unique index, which is why the constraint is
conditional on `status` rather than on a nullable `ended_at`.

**There is no `pending` or `failed` state, and that is deliberate.** The row is written only
**after** the provider call succeeds, inside the same transaction, so a provider outage leaves
no room at all rather than a half-created one the next join has to reason about. A failed
attempt is a log line and a 502, not a row — nothing reads a `failed` room, and a status
nothing reads is a state to maintain for free.

`on_delete=CASCADE` on `session`: a room has no meaning apart from its lesson, and `Session`
is itself reachable by cascade from `User`. **This must not be `PROTECT`.** C2 learned that at
production's expense — `PROTECT` is evaluated per cascade branch and cannot tell an orphaning
delete from a legitimate same-operation one, which is what broke account deletion for every
matched student. See `Session.slot`'s comment.

## The provider seam

`scheduling/providers/`, mirroring `billing/providers/` field for field, because that pattern
is already proven in this codebase and a second shape would be a second thing to learn:

- a `VideoProvider` `Protocol`,
- frozen request/response dataclasses (`RoomRequest`, `ProviderRoom`, `JoinGrant`),
- the concrete class resolved through `import_string(settings.VIDEO_PROVIDER)`,
- exactly one module that knows any vendor or transport name.

The interface keeps ADR-0011's three verbs, which survive the reversal unchanged:

```python
create_room(request: RoomRequest) -> ProviderRoom
get_join_url(room: ProviderRoom, participant: Participant) -> JoinGrant
end_room(room: ProviderRoom) -> None
```

**`FakeVideoProvider` is the default in dev and CI**, and it is a real implementation rather
than a mock: it mints deterministic room ids and signed, expiring join URLs. That is what lets
this slice have genuine e2e coverage with no external service in existence.

Provider failures raise `platform.exceptions.ExternalServiceError`, which `platform.drf` maps
to **502**, not 503 — kaleem is acting as a gateway to a dependency that failed, and 503 would
claim kaleem itself is down. Never a bare `Exception` stringified into the body (rule #8).

## Authorization

This is the load-bearing part of the slice. A join URL admits its holder to a video call with
a child, so every check below is a test, not a comment.

A join is granted only when **all** hold:

| Check | Failure |
| --- | --- |
| Caller is the session's own assigned student or teacher | 403 `PermissionDeniedError` |
| Session `status` is `SCHEDULED` | 409 `ConflictError` |
| Now is within the join window | 409 `ConflictError`, message naming the bound |

**The window is 10 minutes before `starts_at` until 15 minutes after the session ends.** Both
numbers are chosen, not derived: early enough that a punctual teacher can open the room first,
late enough that a lesson running over is not cut off. They are constants in one place.

**The client does not distinguish the two 409s, and must not try.** `kaleem.platform.drf`
returns `{"detail": message}` with no machine-readable code field, so the only thing a client
can branch on is the status. That is why **`can_join_at` exists**: the countdown is driven by
that field, and the button is only enabled once it has passed, so a well-behaved client never
provokes the window 409 at all. The 409 is a server-side backstop against a stale tab or a
hand-made request, not a control-flow signal.

**A parent calling `join` gets the same 403 as any other non-participant.**
Decision 3; it is asserted by a test named for it so a future change has to delete the
assertion deliberately.

## API delta

Under `/api/v1/scheduling/` via `config.api_router` (ADR-0029).

| Method | Path | Who | Shape |
| --- | --- | --- | --- |
| `POST` | `/sessions/<id>/join/` | that session's student or teacher | `{join_url, expires_at}` |

`POST`, not `GET`: the call may create a room, and a capability-minting endpoint should not be
reachable by prefetch, link, or browser history.

`GET /sessions/` gains **`can_join_at`** — the instant the window opens — so a client counts
down locally instead of polling the join endpoint. It carries no capability and is safe in a
list payload.

Creation is wrapped in a per-session lock (`select_for_update` on the session row), so two
browsers hitting join at once produce one room rather than two. The partial unique index is
the backstop under the lock, not a substitute for it.

## Frontend

Extends C2's session list rather than adding a route.

- **Join button** on each upcoming session row: disabled with a live countdown until
  `can_join_at`, then enabled.
- Distinct copy per status — 403, 409, and 502 each say something different.
  A generic "something went wrong" on a lesson that is about to start is a support ticket.
- Teachers and students see the same control; **a parent sees none**, and no empty
  slot where one was.
- i18n keys in `en` and `ar`, RTL verified. Values from tokens, never hardcoded (repo baseline,
  ADR-0020).

## Module boundaries

`scheduling` gains nothing new outward: `Room` is its own model, and participant identity comes
from the `TeacherAssignment` it already owns. No new import-linter contract is needed and no
existing one relaxes. `lint-imports` must stay 10 kept / 0 broken.

## Test plan

TDD throughout (D3), failing test first. Floors are the current ratchets — backend 97.3,
dashboard 93 / 89.5 / 86 — and rise if this slice lifts them.

**Backend**

- A participant inside the window gets a URL; the room row is created once and reused.
- Concurrent joins produce **one** room, asserted under a real transaction, not by mocking.
- Non-participant, **parent**, cancelled session, `too_early`, `too_late` — each its own test
  and its own error code.
- A provider raising maps to 502 and leaves **no** room row behind at all.
- The partial unique index refuses a second active room at the database level.
- Deleting a user cascades their rooms, and deleting a matched student with sessions still
  succeeds — the C2 regression test extended to the new table.
- Join URLs appear in no list payload and in no log record.
- `test_api_versioning_is_enforced` still passes.

**Dashboard** — countdown renders and flips at the boundary; each error state surfaces its own
copy; the button is absent for a parent; Arabic renders RTL.

**e2e** (D3 requires it for a user-facing area) — a student sees a disabled, counting-down
button on a future session; a session seeded inside the window yields a join URL; a parent sees
no button. `seed_e2e` gains a session positioned inside the window.

## Out of scope

- **All media and signaling.** WebSocket signaling, `RTCPeerConnection`, ICE — C3b.
- **STUN/TURN infrastructure** and its ephemeral credentials — C3c. Note this is *mandatory*
  before real calls work: roughly one connection in six cannot go peer-to-peer.
- **The call UI** — device selection, mute, screen share, quality, reconnection — C3d.
- **Browser matrix hardening**, Safari/iOS especially — C3e.
- **Recording.** It needs server-side media ingest, which is an SFU by another name. Not in
  this arc at all.
- **Group sessions.** Decision 2.
- Attendance, lateness, and no-show handling. Real, and they read `Room` — a later slice.

## Open questions

None blocking.

- **OQ-C3a-1.** Should an admin be able to join for supervision or dispute resolution? Deferred
  until a dispute actually needs it; adding a participant class later is additive, and the
  permissive default is the one that cannot be withdrawn.
- **OQ-C3a-2.** Does an `ended` room need to be re-openable if both parties drop and rejoin
  after the window closes? C3b's reconnection work will answer this from real behaviour rather
  than speculation.
