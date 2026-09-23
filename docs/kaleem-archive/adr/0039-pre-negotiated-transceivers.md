---
number: 0039
title: Pre-negotiate every media line before the first offer
status: proposed
date: 2026-09-11
---

**Related:** ADR-0034 (custom WebRTC in v1), ADR-0035/ADR-0037 (signaling as a shared
service), `docs/superpowers/specs/2026-09-11-call-experience-redesign-design.md`

## Context

C3d's peer connection negotiates **once**, and only once. The rule is stated in
`dashboard/src/features/call/usePeerConnection.ts` and enforced in exactly one place: the
teacher sends an offer on every `peer-joined`, the student never does. There is no
`onnegotiationneeded` handler. W3C perfect negotiation (polite/impolite peers) was
considered when that code was written and deliberately rejected, because glare requires
both sides to be able to offer and a fixed offerer makes that state unreachable.

That decision is sound and this ADR does not reopen it. What it did not anticipate is that
**the set of media lines is fixed at first-track-attach**, by `addTrack`:

```
for (const track of localStream.getTracks()) {
    sendersRef.current.set(track.kind, pc.addTrack(track, localStream));
}
```

Three consequences follow, and all three are load-bearing for the next phase:

1. **No local media means no media lines at all.** `tracksAddedRef` never flips, so both the
   offer and the answer sit in `pendingActionsRef` forever. A participant who declines the
   camera prompt does not join a degraded call — they join a call that can never negotiate,
   with no error, because the deferral mechanism is indistinguishable from "media is still
   arriving". The current UI hides this by refusing to show the Join button until
   `getUserMedia` resolves, which is a workaround for the defect, not an absence of it.

2. **A track that arrives later cannot be added.** The file says so directly: adding on a
   later stream change "would create a SECOND sender per kind: duplicate `m=` sections that
   this design's single fixed offerer never renegotiates, and a call that degrades with
   nothing thrown." So `replaceTrack` on an existing sender is the only safe mid-call move,
   and "a kind with no sender is silently skipped."

3. **Screen share is a second video track, so it is the same wall.** It can only replace the
   camera on the one negotiated video line, which is not what a participant expects when
   they share.

The next phase needs all three: join without granting permission, enable a device mid-call,
and share a screen while the camera stays live.

The obvious fix — allow renegotiation — costs the invariant. Renegotiation from the student
side means the student offers, which is precisely the glare the single-offerer rule exists
to make unreachable, and it would drag in the perfect-negotiation machinery that was
rejected on purpose.

## Decision

**Create every media line with `addTransceiver` at connection setup, before the first offer
is generated, whether or not any local media exists yet.** Three transceivers, in a fixed
order, both sides identical:

| Index | Kind | Direction | Carries |
| --- | --- | --- | --- |
| 0 | audio | `sendrecv` | microphone |
| 1 | video | `sendrecv` | camera |
| 2 | video | `sendrecv` | screen share |

Every later media change becomes `sender.replaceTrack(track)` on a line that is **already
negotiated** — including `replaceTrack(null)`, which is how a line with nothing to send is
expressed. Attaching the microphone twenty minutes into a lesson, turning the camera on
after joining with it off, starting and stopping a screen share: all of them reuse an
existing `m=` line and its codec.

This removes the reason to renegotiate rather than adding a mechanism to do it safely. The
single-offerer rule is untouched, `onnegotiationneeded` is still absent, and `tracksAddedRef`
and `pendingActionsRef` — the deferral machinery that exists only because SDP could go stale
waiting for media — become unnecessary, because no SDP is ever generated before the media
lines exist.

**The fixed order is part of the contract, not an implementation detail.** Transceivers are
matched to `m=` sections positionally, so both peers must create the same three in the same
order. A future fourth line is appended, never inserted. This is the kind of invariant that
is obvious while writing it and invisible six months later, so it is tested directly rather
than left to review.

## Alternatives considered

**Perfect negotiation (polite/impolite peers).** The textbook answer, and it solves more
than we need. It re-admits glare as a state that must be handled correctly instead of one
that cannot occur, on a code path — a live lesson with a child — where the failure mode is
silent and the debugging signal is a parent saying "it didn't work". Rejected for the same
reason C3d rejected it.

**A `request-offer` signal**, letting the student ask the teacher to re-offer when the
student needs a new line. Keeps one offerer, but adds a round trip to the moment a
participant unmutes, makes every media change depend on the other side being responsive, and
introduces a queue of pending requests. Strictly more moving parts than negotiating the
lines up front, for strictly less capability.

**Screen share via `replaceTrack` on the camera line.** No architecture change at all, and
genuinely tempting. Rejected on product grounds: the participant's camera goes dark for the
other side while they share, which is not what any mainstream product does, and it makes the
per-viewer layout control the spec calls for meaningless — there is only ever one video to
lay out.

**Renegotiating only for screen share**, keeping one line for camera. Splits the rule into
"we never renegotiate, except sometimes", which is the shape of invariant that survives
exactly as long as the person who wrote it.

## Consequences

**Every call now negotiates three `m=` lines, including ones carrying nothing.** An audio-only
participant negotiates two video lines that send no media. The cost is a slightly larger SDP
and two extra ICE-less `m=` sections; there is no media, no encoder, and no bandwidth for a
line whose sender has a `null` track. This is the standard trade and it is cheap.

**`recvonly` is no longer a failure mode to guard against.** The old code's second stale-SDP
hazard — an answer generated before tracks attach negotiates `recvonly` and nothing ever
renegotiates it — cannot occur, because `sendrecv` is declared at setup rather than inferred
from what happened to be attached.

**`tracksAddedRef`, `pendingActionsRef` and `runOrDefer` can go.** They exist solely to keep
SDP from being generated before media arrived. That race no longer exists. Removing them is
part of this change, not a later cleanup — leaving dead deferral machinery next to a design
that no longer defers is how the next reader concludes the race is still real.

**The mute path stays exactly as it is.** `track.enabled = false` remains the mechanism for
muting; `replaceTrack(null)` is for a line that has *no device*, which is a different state.
Conflating them would either make mute renegotiate (slow, and it drops the encoder) or make
"no camera" indistinguishable from "camera muted" to the other side.

**Both peers must ship this together.** A peer that pre-negotiates three lines and one that
adds two on first attach do not produce matching SDP. There is no version negotiation in the
signaling protocol and this ADR does not add one: the dashboard is a single deployed bundle
and both participants load it from the same origin, so a mismatch can only exist in the
window where one participant has an old bundle cached. That window is real — a lesson in
progress across a deploy — and it is the same window in which ADR-0037's deploy already drops
calls (`ISSUES.md`, "deploy between lessons"). It does not need a second mechanism, but it
does need the runbook line, and the spec's test plan covers a mismatched pair explicitly so
the failure is a known shape rather than a surprise.

**C3d's e2e call spec must keep passing unchanged.** The two-peer fake-media test asserts a
remote track producing frames; if pre-negotiation is right, that test does not know anything
changed. A change to that spec's expectations would be evidence the negotiation shape moved,
so it is the regression signal for this ADR.
