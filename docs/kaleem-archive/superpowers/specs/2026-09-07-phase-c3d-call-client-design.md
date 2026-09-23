---
name: phase-c3d-call-client
phase: C
modules: [scheduling, dashboard]
status: draft
created: 2026-09-07
---

## Goal

Make a lesson happen.

C3a gave a session a room. C3b built the relay two peers find each other through. C3c stood up
the TURN relay that lets them connect when the network is against them — and proved, live, that a
packet really traverses it. **All three shipped without producing a single call**, because none of
them contains browser code.

C3d is the browser code. It is the first phase whose output a student and a teacher can see each
other through.

## What C3d is not

Named here because "the video phase" invites unbounded scope:

- **Not Safari or iOS.** ADR-0034 reserves those for C3e and says explicitly they must not be
  dropped as polish. C3d targets Chromium and Firefox.
- **No screen sharing, no recording, no group calls, no in-call chat, no network-quality UI.**
  Recording in particular reopens the SFU decision (ADR-0034) rather than being added to a P2P
  path.
- **No change to the C3b signaling protocol.** Four message types, exactly as specified. A design
  that needed a fifth would be a design worth rejecting.

## Decisions taken

Recorded so the plan does not relitigate them.

1. **A full-bleed route inside the app**, `_authed/sessions/$sessionId/room`, rendered without the
   nav shell. Not a popup: popups are blocked by default on mobile and are hard to drive in the
   e2e harness. Not inside the shell: a 1-on-1 lesson wants the viewport.
2. **The room route mints its own grant.** `JoinButton` stops calling the join endpoint and simply
   navigates. `token` and `ice_servers` live in memory only — never the URL, never storage. A
   reload re-mints rather than replaying a stale capability, which is the same reasoning that
   moved the token out of the query string in C3c.
3. **The teacher offers; the student answers**, decided from a new `is_teacher` field on the
   join grant. See below — this is the load-bearing decision, and the grant field and the token
   claim must come from one source.
4. **A mandatory lobby** before entering the room.
5. **Hooks own the state machines; components own none.** The connection logic must be testable
   without a browser.

## Who offers

> **The teacher sends an offer on every `peer-joined`. The student only ever answers.**

The token already carries `is_teacher`, and C3b's relay already announces arrival to both sides —
the newcomer receives `peer-joined` when someone is already present, and the incumbent receives it
when someone arrives. So this rule works regardless of join order, and it survives a reconnect
untouched: a student's new socket makes the teacher see `peer-joined` again, and the teacher
re-offers.

**W3C perfect negotiation was considered and rejected.** Glare requires both sides to be able to
offer; with a fixed offerer it is unreachable, so the polite/impolite machinery would guard a
state this design does not have. It would also need no new message type only by accident — the
attraction of the fixed rule is that the C3b protocol stays closed.

The cost, stated rather than discovered: a teacher whose client is wedged means no call, and the
student has no way to force renegotiation. Given the teacher runs the lesson, that is the right
asymmetry.

## The one backend change: the client must know which side it is

The "teacher offers" rule needs the client to know whether *this viewer* is the teacher **of this
session**. Nothing in the API says so today, and `SessionSerializer`'s own comment explains why a
client cannot work it out: the payload carries names, not ids, and the viewer's roles do not
answer it — someone may be both a parent and the teacher on the same row.

So `JoinGrant` gains `is_teacher`, and `JoinGrantSerializer` exposes it.

This is the right place for it rather than `SessionSerializer`, for two reasons. It is a property
of *this participant in this room*, which is exactly what a grant already describes. And
`Participant.is_teacher` is already computed in `rooms._participant` and already travels into the
token claim — so the grant field and the token claim come from one source and cannot disagree
about who is the offerer. Two places deciding that independently is precisely how a room ends up
with two offerers or none.

Decoding the token client-side was considered and rejected: the payload is readable base64url, so
it would work, but it makes the client depend on the token's internal format for something the
API can simply state.

Nothing else in the backend changes.

## Renegotiation is mostly avoidable

| Action | Mechanism | Renegotiates? |
| --- | --- | --- |
| Mute mic / camera off | `track.enabled = false` | No — connection stays warm, effect is instant |
| Switch device | lobby only, before any peer connection exists | N/A — see below |
| ICE failure | `restartIce()` on the teacher, bounded | Yes, and only here |
| Peer reconnects | `peer-joined` → teacher re-offers | Yes, via the existing rule |

**Device switching is a lobby-only action in C3d.** The pickers live before the peer connection
exists, so `sender.replaceTrack()` is never reached — an earlier draft of this table listed it,
which would have had the plan build a path nothing calls. In-call device switching needs an
in-call settings surface, and that is a later phase, not a line item here.

So normal use renegotiates on reconnect and nowhere else.

## The lobby

Clicking **Join** lands here, not in the call. It shows the local preview, a camera and a
microphone picker, a live mic level, and an explicit **Join now**. While the person looks at
themselves, it mints the grant and opens the signaling socket, so the token and ICE servers are
ready before they commit.

**Why mandatory.** The most common first-lesson failure on a platform for children is a permission
prompt nobody expected. A lobby means the person meets it alone and fixes it alone, instead of
discovering it while a teacher watches a black rectangle.

**The picker persists nothing.** Re-selecting each time is slightly worse in steady state and
avoids an entire class of stale-device bug for a first release. Remembering the choice is a
natural follow-up once real usage shows what people pick — it is not a first-release requirement.

## Failure states

These are the deliverable, not an afterthought. Each is a distinct message with a distinct action.
A generic "something went wrong" is a defect here, not a fallback.

| Cause | What the user is told, and can do |
| --- | --- |
| `NotAllowedError` | permission was denied; how to re-grant it, and retry **without** reloading |
| `NotFoundError` | no camera or microphone found; offer joining audio-only or camera-off |
| `NotReadableError` | another application holds the device; close it and retry |
| `OverconstrainedError` | fall back to default constraints rather than failing outright |
| Grant 403 / 409 | not a participant, or outside the join window — reuse the existing booking copy |
| Socket **4401** | the grant expired; re-mint **once**, then surface it |
| Socket **4409** | the room is full — someone else is already in this lesson |
| Socket **4410** | "you joined from another tab" — **not an error, and never retried** |
| ICE failed after retries | connection failed, with a retry control |

**4410 must not trigger reconnection.** It is the code C3b assigns when the same participant opens
a newer socket. Retrying it makes two tabs fight each other indefinitely, and the symptom — a call
that flaps forever with both tabs looking healthy — is exactly the kind of failure this project
keeps finding late.

## Connection state

One derived state, computed from `pc.connectionState` and the socket's state:

```text
lobby → connecting → connected → reconnecting → failed | ended
```

Surfaced in an `aria-live` region, so it is not conveyed by colour or motion alone. Reconnection is
bounded with backoff and **gives up visibly** rather than spinning forever.

## Layout

Remote dominant, local as a picture-in-picture tile:

```text
┌────────────────────────────────────┐
│                                    │
│           TEACHER                  │
│          (remote)                  │
│                       ┌──────────┐ │
│                       │   you    │ │
│                       └──────────┘ │
├────────────────────────────────────┤
│      ( mic )  ( cam )   [ Leave ]  │
└────────────────────────────────────┘
```

The self-tile is positioned with `inset-e-*` (a logical inline-axis property) and `bottom-*` (a
physical property), so RTL mirrors the inline axis it needs to mirror without a second rule. Only
the *inline* axis takes a logical utility here — **the block axis does not mirror in RTL, and
Tailwind v4 has no `inset-t-*`/`inset-b-*` aliases to begin with** (verified against this repo's
own Tailwind 4.2.2 build: they compile to nothing). A previous revision of this spec prescribed
`inset-b-*` for the block axis, which does not exist and shipped a self-tile with no vertical
position at all — corrected here. Controls are real buttons, keyboard reachable, with
`aria-pressed` on the two toggles.

While alone in the room, the remote area carries a waiting state naming who is expected — not an
empty black rectangle.

## Module shape

`dashboard/src/features/call/`:

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `useLocalMedia` | `getUserMedia`, device enumeration, permission and device-failure states | browser media APIs |
| `useSignaling` | the socket: subprotocol handshake, typed messages, close-code mapping | `WebSocket` |
| `usePeerConnection` | `RTCPeerConnection` lifecycle, tracks, ICE, connection state | `RTCPeerConnection` |
| `Lobby` | preview, pickers, the Join control | `useLocalMedia` |
| `CallRoom` | composes the three hooks into the call | all three |
| `VideoTile`, `CallControls` | presentation only | nothing |

Each hook takes its browser API by injection so tests supply fakes. The components hold no
connection state at all — that separation is what makes the state machines testable without a
browser, and it is the difference between this phase being coverable and not.

## Testing

**Backend.** `JoinGrant.is_teacher` is asserted for both participants of one session, and
asserted to equal the `is_teacher` claim inside the token minted in the same call — the test that
fails if the two ever drift into disagreeing about who offers.

**Unit and component**, against injected fakes for `RTCPeerConnection`, `getUserMedia` and
`WebSocket`: every failure row above; the close-code mapping including 4410 **not** retrying; the
teacher-offers/student-answers rule in both join orders; mute leaving the connection up;
`replaceTrack` on device switch; and reconnection stopping at its cap. This is where the real
coverage lives.

**End-to-end — the first automated gate video has ever had.** Two Playwright contexts, student and
teacher, launched with `--use-fake-device-for-media-stream`, against a real Django and a real
signaling service exactly as the existing harness does:

1. both join, and **each asserts a remote track actually arrives and is playing** — not merely that
   an element rendered;
2. muting on one side is observed on the other;
3. one participant leaving is seen by the one who stays.

**Deviation, recorded rather than left implicit:** flow 2 (muting observed on the other side) was
not built. `e2e/call.spec.ts` ships flows 1 and 3 only, and the D3 table in `CLAUDE.md` honestly
says "2 flows" rather than claiming three — but reducing a binding spec item to a manual
click-through check is a real deviation and belongs on the record, not just in the harness's own
line count. `track.enabled = false` (the mechanism flow 2 would exercise) is unit-tested in
`CallRoom.test.tsx` against a fake track; what is missing is the end-to-end proof that the OTHER
peer's rendered video actually reflects it. Verified by hand instead, alongside the rest of the
manual verification pass below.

Two limits recorded rather than discovered later:

- **CI has no coturn**, so this proves host-candidate peer-to-peer only. The relay path stays
  covered by C3c's live verification, and the D3 table must say so rather than implying video is
  fully gated.
- **Fake media proves plumbing, not quality.** Nothing here can tell whether audio is audible or
  video is watchable; that stays a human check.

**Manual verification** remains required: a real call between two real browsers on staging, as a
student and as a teacher, in English and in Arabic with RTL.

## Risks

- **`autoplay` policy.** A remote track attached to a muted-by-default element plays; an unmuted
  one may be blocked until a gesture. The Join control is that gesture, which is another argument
  for the lobby — but the failure is silent when it happens, so it needs an explicit test.
- **Device changes mid-call** (a headset unplugged) fire `devicechange` and can end a track. Out of
  scope to handle gracefully, but the connection state must not report `connected` while a dead
  track produces nothing.
- **The e2e flow needs two authenticated users in one joinable session.** The existing seed
  commands build matched pairs; C3d needs one whose session is joinable *now*, and
  `test_seed_e2e_joinable` already exists to build on.
- **A deploy still drops every call in progress** (`ISSUES.md`). C3d makes that visible for the
  first time, because until now there were no calls to drop. The interim rule — deploy between
  lessons — becomes materially more important the day this ships.
