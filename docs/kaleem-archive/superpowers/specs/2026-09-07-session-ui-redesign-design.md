---
name: session-ui-redesign
phase: C
modules: [scheduling]
status: shipped
created: 2026-09-07
closed: 2026-09-07
---

## Goal

The two surfaces a lesson is actually lived through — the schedule's session list and
the call room — were each built to prove a mechanism, not to be used. The list renders
seven stacked paragraphs at every viewport from 360px to 1920px. The call room has no
orientation handling at all, a self-view pinned to a magic offset, and a Lobby with no
scroll container around its centered content. This spec redesigns both, and restructures
the components underneath them so the redesign has somewhere to live.

**Correction (2026-09-07, Task 18):** an earlier draft of this section framed the Lobby's
`overflow-y-auto` change as fixing a demonstrated bug — "a Lobby that clips its own content
and cannot scroll." Task 16 established that this is wrong for every browser this project can
test: Chromium does not reproduce the classic flex-centering clipping bug at all (see "What
this spec cannot prove"). The change is defensive hardening against a bug that is plausibly
Safari-only, not a fix for something we ever demonstrated broken here.

This is a **presentation and structure** change. No API changes, no data model changes,
no backend work.

## Why this is a restructure and not a reskin

`CallRoom.tsx` is 458 lines of interleaved WebRTC lifecycle, failure derivation and
JSX. Every layout change has to be threaded through connection logic, and the file is
past the size where that is safe. The redesign was offered as a presentation-only
rewrite with logic carried across verbatim; the restructure was chosen deliberately,
with the risk stated and accepted.

That risk is specific and worth naming: those files carry the C3e hardening, and each
of the following is a bug that shipped before it was fixed.

- The Lobby's `getUserMedia` must be called **synchronously inside the click handler**,
  or iOS refuses capture for want of user activation.
- `VideoTile`'s play effect depends on `[stream]` **alone**; adding the callback back
  into the dependency array blanks the remote video and writes false `autoplay-blocked`
  diagnostic rows.
- `VideoTile`'s tap-to-play control renders on `blocked && !muted`; dropping the
  `!muted` half covers the self-view with a control that fixes nothing.
- Entering any terminal state must stop the camera and microphone. A terminal screen
  with a live camera behind it is the defect class C3e existed to close.
- The room route's visibility-recovery trigger has four guards in a specific order and a
  hard rebuild ceiling. Reordering them writes false `backgrounded` rows and can strand
  a lesson on a `room-full` screen with no retry.

The safety net in **Sequencing** below exists for exactly these.

## Scope

**In:**

- `dashboard/src/features/booking/components/SessionList.tsx` and the schedule page it
  renders on.
- `dashboard/src/features/call/` — `CallRoom`, `Lobby`, `CallControls`, and the new
  components they split into.
- Three new primitives in `dashboard/src/ui/`.

**Out:**

- `VideoTile.tsx`'s logic. It receives new classNames from its callers and nothing else.
- `useLocalMedia`, `usePeerConnection`, `useSignaling`, `useCallDiagnostics`,
  `deviceStorage`, `redactStats`. Untouched.
- Any backend, infra or marketing change.
- The `assessment` and `analytics` gaps Phase C left open. A redesigned session card
  still records nothing about a delivered lesson; that is a separate phase.

## Restructure

### Call

| New file | Kind | Holds |
| --- | --- | --- |
| `useCallRoom.ts` | hook | signaling + peer connection wiring, mic/camera flags, terminal derivation, cleanup effects, `handleLeave` |
| `CallRoom.tsx` | component | calls the hook; renders `CallEnded` or `CallStage` |
| `CallStage.tsx` | presentational | the stage layout: remote surface, self-view, chrome slots |
| `CallStatus.tsx` | presentational | the connection chip and the lesson identity header |
| `WaitingForPeer.tsx` | presentational | the "alone in the room" state |
| `CallEnded.tsx` | presentational | terminal screens |
| `SelfView.tsx` | presentational | the fluid picture-in-picture wrapper around `VideoTile` |
| `DeviceSelect.tsx` | presentational | one camera/microphone picker (currently duplicated markup) |
| `MediaFailureAlert.tsx` | presentational | per-failure copy, shared by the Lobby and the in-room banner |

`useCallRoom` returns a view model — `{ state, remoteStream, micOn, cameraOn,
toggleMic, toggleCamera, leave, terminal, mediaFailure }` — and every component above
holds no state and runs no effects.

`MediaFailureAlert` closes a real duplication: the Lobby and `CallRoom` each branch on
`denied`-versus-everything-else with their own copy of the same conditional today.

### Booking

`SessionList.tsx` splits into `SessionList` (query, filtering, day grouping),
`SessionCard`, and `CancelSessionDialog`.

### Promoted to `src/ui`

- **`Select`** — the Lobby hand-rolls a `selectClassName` because the design system has
  no select. It is a genuine gap.
- **`StatusChip`** — the "Happening now" and connection-state chips.
- **`RelativeTime`** — "in 2 hours" / "Now", locale-aware via `Intl.RelativeTimeFormat`.

Nothing else is promoted. Everything else in this spec is used once.

Splitting a feature component into a hook plus stateless components is a dashboard-wide
pattern decision, not a local one, so it carries an **ADR** alongside this spec (D8).

## The schedule list

Sessions group by day — Today, Tomorrow, weekday name, then date — instead of one flat
sorted list.

`SessionCard` is a grid that reflows, not a stack:

- **Below `sm`:** time and relative time on the first line; subject as the title;
  counterpart with an initial avatar; a duration chip; actions full-width beneath.
- **`sm` and up:** `grid-cols-[auto_1fr_auto]` — a leading time block, the content, and
  the actions aligned to the inline end.

Alignment is logical throughout, so RTL mirrors with no second rule.

A session whose `may_join` is true takes an accent border and a "Happening now" chip.

**The refund consequence stays on the card.** Stating it before the cancel control is
ever clicked is deliberate and predates this spec; it is demoted to a small line beside
Cancel, not removed. The cancel dialog drops `-translate-x-1/2 … rtl:translate-x-1/2`
for grid centering, which needs no direction-specific hack.

`EmptyState` and `Spinner` stay as they are.

## The call room

The stage fills `100dvh` and all chrome overlays it. A single custom property,
`--call-chrome-height`, set on the stage drives both the control bar and the self-view
offset. This replaces `bottom-20`, a magic number tuned to one control-bar height that
silently breaks when that height changes.

**The remote video becomes `object-contain` on a dark stage, not `object-cover`.** This
is a deliberate departure from video-call convention. In a lesson the teacher holds
things up to the camera, and cropping a page is a worse failure than letterboxing.

**The self-view is fluid** — a `clamp()` width with `aspect-video`, positioned by
logical inset and offset above the chrome. It shrinks on small viewports and never
disappears: it is the only on-screen proof that your own camera is working.

**The controls float on a scrim** rather than occupying a fixed strip. At
`(orientation: landscape) and (max-height: 500px)` they move to the inline end as a
vertical stack, which is where a thumb rests on a phone held sideways. This is the
orientation the room is most used in and the one it currently does nothing about.

**A visible identity header.** The room's only `<h1>` is `sr-only` today, so nothing on
screen says which lesson you are in. `JoinGrant` carries `join_url`, `token`,
`expires_at`, `ice_servers` and `is_teacher` — no subject and no names. The names come
from the existing `useSessions()` query, matched on `sessionId`, and the header degrades
to the connection chip alone on a cold deep-link where that query has no cached row.
Extending the grant serializer instead would mean a backend PR for a cosmetic field.

**The waiting state** shows the counterpart's name, an initial avatar and a calm pulse
instead of a bare centered paragraph. **Terminal screens** become a card with an icon,
title, explanation and actions — the same copy keys and the same retry semantics.

**The Lobby's scroll hardening.** `min-h-dvh` with `justify-center` and no scroll container
means that if the preview, two device selects and the Join button were ever collectively
taller than the viewport — plausible on a landscape phone — the top would be cut off and
unreachable. It becomes `flex min-h-dvh flex-col overflow-y-auto` with an inner
`m-auto`: centered when it fits, scrollable when it does not. Two columns from `md`.
**This is defensive, not a fix for a demonstrated defect** — see "What this spec cannot
prove" below; Chromium never reproduced the clipping this guards against.

**The gesture gate is untouched.** No preview and no `getUserMedia` before a real tap.

## Sequencing

The order is the safety net, not a convenience.

1. **A pure extraction, no behaviour change.** `useCallRoom` is created and `CallRoom`
   calls it. The existing `CallRoom.test.tsx` — 557 lines — must pass **unmodified**. If
   a single test needs editing at this step, the extraction is wrong and gets redone.
   Same rule for the `Lobby` and `SessionList` splits.
2. **Mutation-check the extraction.** For each guard that moved, delete it and confirm a
   test goes red. A guard that survives its own deletion was never covered.
3. **Then the redesign**, against a structure already proven equivalent.

**Four test files are frozen** — no edits permitted at any step:

- the Lobby's "requests the camera synchronously inside the click, not from an effect"
- `VideoTile`'s stream-effect tests
- the terminal-cleanup tests
- the room route's visibility-recovery guard tests

An edit to any of these means the redesign changed behaviour it was not supposed to
touch.

## Test plan

- Unit tests for every new component and for `useCallRoom`.
- Dashboard coverage floors ratchet up from 95.5 / 91.6 / 87.2 / 95.5.
- **New Chromium e2e**, limited to what Playwright can honestly prove:
  - the session card's action layout at two viewport widths;
  - the Lobby scrolling rather than clipping at a short landscape viewport.
- `viewport-units.test.ts`'s `HEIGHT_BEARING_TREES` extends to cover
  `src/features/booking`, so the new card inherits the `100vh` guard.
- The full existing suite passes with the four frozen files unmodified.

## What this spec cannot prove

**None of this is verified on iOS Safari.** This project has no Apple device — no Mac,
no iPhone, no iPad — and Playwright's WebKit on Linux is not iOS Safari. A Chromium
window sized to 390×844 is a Chromium window, not a phone: it shares no orientation
model, no dynamic viewport behaviour on toolbar collapse, and no touch heuristics with
the device this redesign is largely aimed at.

This is the same standing limitation recorded for C3e-a and C3e-b, and it closes under
the same **D9 deviation**, recorded in `journal/2026-W36.md` rather than skipped.

**The Lobby's `overflow-y-auto` is not a proven fix, and Chromium says the bug it targets
does not reproduce here at all.** Task 16 checked this twice. First, the new Playwright flow
was mutation-checked by reverting to the literal pre-fix CSS — the flow stayed green.
Second, a minimal bare-metal reproduction (flex column, `min-height: 100vh`,
`justify-content: center`, a 2000px child, a 400×220 viewport, no `overflow` set) driven
through the same Chromium showed `scrollHeight` at the full 2000px, with the content's top
reachable at `y=0` after scrolling. **Chromium does not reproduce the classic
flex-centering clipping bug at all.** So the change described above is defensive hardening
against a bug that is plausibly Safari-only and is unverifiable in this project — not a fix
for a defect this project ever demonstrated. It is kept because it is the standard robust
pattern and costs nothing, matching the C3e Safari-hardening posture, but it must not be
reported as closing a bug we proved existed. Full account: `journal/2026-W36.md`,
2026-09-07 entry.

## Deviations

- **Preview mode has not run.** `STATE.md` records it as a non-optional gate before any
  further spec is opened, and this spec is opened anyway, at the user's direction. Named
  here and in the journal rather than skipped quietly.
- **D10 (no refactoring sprees)** would ordinarily forbid restructuring while
  redesigning. The restructure was chosen explicitly over the presentation-only
  alternative, so it is the deliverable rather than a detour — but it is a deviation and
  is recorded as one.

## Open questions

None. The `object-contain` choice and the `useSessions()` source for the header were
both raised and settled before this spec was written.
