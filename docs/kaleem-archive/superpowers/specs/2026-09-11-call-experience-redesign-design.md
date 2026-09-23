---
name: call-experience-redesign
phase: C
modules: [scheduling]
status: draft
created: 2026-09-11
closed: null
---

## Goal

The video call works — verified live through our own coturn on 2026-09-07 — and its
interface is below the standard anyone who has used Meet, Zoom or Teams expects. Four
things are missing, and they are the four things people reach for first: you cannot choose a
microphone or camera once you are in the call, you cannot join at all unless you grant
camera and microphone permission, you cannot join with your camera already off, and you
cannot share your screen.

This spec closes all four and redesigns the lobby and in-call surfaces around them. Two of
the four are not UI work: joining without permission and sharing a screen both require media
lines that do not exist at negotiation time, which ADR-0039 provides by pre-negotiating every
line up front. The UI is designed once, against the finished capability, rather than twice.

**Phase C was closed on 2026-09-07.** This spec re-opens it as C4 rather than opening a new
phase: it finishes the scheduling phase's own deliverable instead of adding a new one.

## User flow

### Lobby — before joining

1. The participant opens the room. **The lobby renders immediately**, with the preview area
   showing a placeholder and a single primary **Join now** button that is enabled from the
   first paint. Nothing is gated on a permission prompt.
2. A **Check camera and microphone** control requests media. This stays a real tap — the
   gesture gate from C3e-b is load-bearing and is not being relaxed; what changes is that
   declining it no longer blocks the door.
3. With permission granted: the preview shows the camera, and mic/camera toggle buttons sit
   on the preview itself. Each toggle carries a chevron opening a **device picker popover**
   listing that kind's devices. Choosing one re-acquires and re-previews. The two detached
   `<select>`s in the current layout go away — a picker belongs to the control it configures.
4. Either toggle may be switched off **before** joining. The choice is carried into the call,
   so a participant who joins muted is muted on arrival rather than after a scramble.
5. With permission **denied**, **dismissed**, or **no device present**: the preview shows the
   participant's initials and a plain sentence naming the actual state ("Camera and
   microphone are blocked for this site" / "No camera found"), with the existing
   `MediaFailureAlert` recovery text. **Join now stays enabled.** A secondary line states what
   joining now means: *You'll be able to see and hear, but not be seen or heard. You can turn
   them on later.*
6. Join is never disabled for a media reason. It is disabled only while the join grant is
   being minted, and shows a spinner while so (existing behaviour).

### In the call

7. On arrival the participant sees the other person, themselves in a self-tile, and a
   **control bar**: microphone, camera, share screen, layout, leave. Each is a labelled
   button, not an icon alone.
8. **Microphone and camera** toggle instantly (`track.enabled`, unchanged from today — never
   renegotiation). Each carries the same device-picker popover as the lobby, so switching to
   a headset mid-lesson is two taps and no rejoin.
9. A participant who joined without permission gets, in place of the toggle, an **enable**
   action. Tapping it requests permission for that kind alone and, on success,
   `replaceTrack`s it onto its already-negotiated line. **No rejoin, no renegotiation.** On
   refusal it returns to the blocked state with the same honest copy as the lobby.
10. **Share screen** calls `getDisplayMedia` and replaces the screen line's track. The camera
    stays live throughout — both are sent. Stopping happens from the control bar *or* from
    the browser's own stop-sharing control, and both paths must land in the same state: the
    track's `ended` event is what the UI listens to, not the button.
11. **Layout** is chosen by each viewer, for themselves, and never changes what anyone else
    sees. Four options: **Spotlight** (one large, the rest as thumbnails, with an explicit
    choice of who is spotlit), **Tiled** (equal), **Sidebar** (one large, others in a column),
    and **Picture-in-picture** (one large, the self-tile floating and draggable). The current
    choice persists per participant in `localStorage`.
12. When a screen share starts, the viewer's layout switches to Spotlight on that screen
    **once**, and a toast says so with an Undo. It never re-asserts itself: a viewer who
    chooses a different layout during a share keeps it. Auto-switching that cannot be
    overridden is the single most common complaint about this feature elsewhere.
13. Leaving is unchanged: stop tracks, close the peer connection, close the socket.

### Failure cases

- **Permission denied mid-call** when enabling a device — return to blocked state, keep the
  call up, report the existing `gum-denied` diagnostic.
- **Screen share cancelled** at the browser's own picker — a `NotAllowedError` that is *not*
  a failure and must not be reported as one. The button returns to rest, nothing is shown.
- **`getDisplayMedia` unsupported** (older mobile browsers) — the share control is not
  rendered at all rather than rendered and broken. Detected by capability, never by browser
  sniffing.
- **A device disappears while in use** — already handled by `useLocalMedia`'s `devicechange`
  path; the redesigned pickers must reflect the new list without losing the participant's
  explicit choice.
- **The other side never sends media on a line** (joined without permission) — the tile shows
  their initials, not a black rectangle, and not a spinner implying something is still coming.

## Data model delta

None. No new tables, no new fields.

## API delta

None to the shape of any endpoint. Two additions to the existing `DiagnosticCode` enum,
which is a closed list checked in both directions by the contract test from C3e-a:

- `screenshare-denied` — `getDisplayMedia` refused by permission policy (distinct from the
  participant cancelling the picker, which is not reported at all).
- `screenshare-failed` — it threw for any other reason.

Adding a code is a backend change (`CallDiagnostic`), a frontend change, and a line in the
contract test. The C3e-a guard is directional — it catches the client knowing a code the
backend does not — so both sides land in the same PR.

## Frontend

**Route:** `src/routes/_call/sessions.$sessionId.room.tsx`, unchanged. Both roles.

**Components.** The existing split (ADR-0036: hook holds behaviour, component renders) holds
throughout. New and changed:

| Component | State |
| --- | --- |
| `Lobby` | rewritten: single-column, preview-first, join always available |
| `DevicePickerButton` | new — a toggle plus a chevron opening that kind's device list |
| `ParticipantTile` | new — wraps `VideoTile`; renders initials when a line carries no track |
| `CallControls` | new — the control bar, labelled, keyboard-reachable |
| `LayoutSwitcher` | new — four layouts, persisted per viewer |
| `ScreenShareButton` | new — capability-gated, listens for the track's `ended` |
| `DeviceSelect` | kept, now rendered inside the popover rather than the page |
| `VideoTile` | unchanged, including the C3e-b tap-to-play control |

**Hooks.** `useLocalMedia` gains per-kind acquisition (today it acquires both or neither) and
an initial-enabled state so the lobby's pre-join toggles reach the call. `usePeerConnection`
gains the three fixed transceivers and loses `tracksAddedRef` / `pendingActionsRef` /
`runOrDefer` (ADR-0039). `useCallRoom` gains screen-share state and per-kind enable.
`useScreenShare` is new.

**States, every one of which is a real screen someone will see:** permission not yet asked ·
granted · denied · dismissed · no device · device in use by another app · joined with nothing ·
enabling mid-call · sharing · being shared to · connecting · reconnecting · terminal.

**Design constraints** — these are the repo's standing baseline, not this spec's invention:

- **Tokens only.** Every colour, radius and shadow from the semantic token layer. No hex, no
  `color-mix`, in any new component.
- **WCAG 2.2 AA.** Contrast ≥ 4.5:1 for text and ≥ 3:1 for the control-bar glyphs, in light
  and dark independently. Every control has a visible focus ring. No control is icon-only
  without an accessible name. Toggles report `aria-pressed`; state is never carried by colour
  alone — a muted microphone shows a slashed glyph, not merely a red one.
- **Touch targets ≥ 44×44px** with ≥ 8px between them. The control bar is the most-tapped
  surface in the product and is frequently used one-handed on a phone.
- **Full RTL.** Logical properties throughout; the control bar, popovers and PiP tile all
  mirror. The layout switcher's icons are direction-aware.
- **Motion 150–300ms, `transform`/`opacity` only**, and every transition honours
  `prefers-reduced-motion`. Layout changes must not reflow the video elements — a reflow
  re-runs the media element load algorithm, which is the exact mechanism that produced the
  false `autoplay-blocked` reports C3e-a had to chase down.
- **Keyboard shortcuts**: `m` microphone, `c` camera, `s` share, with a discoverable list.
  Suppressed while focus is in a text field.
- **Phone-first**, verified at 375px and in landscape, with the control bar clear of the home
  indicator.

## Module boundaries

`scheduling` owns the room, the grant and `CallDiagnostic`; nothing new crosses a module
line. The signaling service is untouched — this changes what the two peers negotiate with
each other, not what they relay through it. No new events.

## Out of scope

- **Group calls.** Two participants, per ADR-0034. The layout switcher is built so more tiles
  would not break it, but nothing here negotiates a third peer.
- **Recording, virtual backgrounds, blur, reactions, chat, hand-raise.**
- **Bandwidth adaptation and simulcast.** The screen line sends at whatever
  `getDisplayMedia` produces.
- **Remote control of a shared screen.**
- **A second sharer's screen shown simultaneously.** Both participants *may* share; a viewer
  sees one at a time and switches. Two screens plus two cameras on a phone is not a layout
  worth designing for a 1-on-1 lesson.
- **Changing the mute mechanism.** `track.enabled` stays.

## Test plan

**Unit (Vitest), the failing test first in each case — D3.**

- A peer connection with **no local media at all** produces an offer with three `m=` sections.
  This is the ADR's core claim and the one test that must exist before any of it is written.
- The three transceivers are created in the fixed order audio, camera, screen — asserted
  positionally, because position is the contract.
- `replaceTrack` on a line whose sender holds `null` attaches media without any `createOffer`
  after the first. Mutation check: the assertion must fail if a renegotiation is introduced.
- Mute still sets `track.enabled` and still never renegotiates.
- Pre-join toggles reach the call: joining with the camera off yields a call whose video track
  is disabled on arrival, not one that flickers on and off.
- Screen share: `replaceTrack` onto line 2 leaves line 1's camera track in place.
- The browser's own stop-sharing control (`ended`) lands in the same state as the button.
- A cancelled share picker reports **no** diagnostic; a denied one reports
  `screenshare-denied`.
- Layout persists per viewer and survives a reload; the auto-switch on share fires once and
  never overrides a later manual choice.
- `ParticipantTile` renders initials, not a spinner, for a line carrying no track.

**Contract.** The C3e-a diagnostics test extends to the two new codes, both directions.

**e2e (Playwright), which is where the ADR's real risk lives.** The C3d two-peer fake-media
spec must pass **unchanged** — if it needs editing, the negotiation shape moved and the ADR
is wrong. New flows:

| Flow | Asserts |
| --- | --- |
| Join with permission denied | both peers connect; the joiner sees and hears the other; the other sees initials, not a black tile |
| Enable the microphone mid-call | audio arrives after joining with nothing — a remote audio track producing samples, not merely a button changing colour |
| Screen share with camera live | the receiver gets **two** video tracks, both producing frames |
| Stop from the browser's control | share ends, camera survives |
| Layout switch | one viewer changing layout does not change the other's |
| Keyboard only | join, mute, share and leave without a mouse |
| RTL | the control bar and popovers mirror |

**Mismatched-bundle check**, from ADR-0039's consequences: a peer built before this change
against one built after. Not automatable in CI (it needs two bundles), so it is a scripted
staging check with a written expected result, and the outcome goes in the journal.

**What cannot be verified here, stated rather than implied.** This project has no Apple
device. Screen share on iOS Safari — the one platform where `getDisplayMedia` is most
restricted — cannot be tested, and the capability gate means iOS users will simply not see
the control. That is the intended behaviour, and it is *unverified* intended behaviour. It
joins C3e's standing D9 deviation and the `CallDiagnostic` watch is the only feedback loop.

**Coverage.** Both floors are ratchets (ADR-0026): backend 97.7, dashboard 95.2 / 91.5 / 87.0.
This lands a lot of new dashboard code; the floors go up in the same PR, never down.

## Open questions

None blocking. Two settled during design and recorded here so they are not relitigated:

- **Screen replaces camera, or both?** Both — decided with the user 2026-09-11, and it is what
  makes per-viewer layout control mean anything.
- **What does "join without permission" get you?** Full watch-and-listen with the ability to
  enable either device later without rejoining. Same conversation.

One to settle before the layout work, not before the ADR:

- **Does Spotlight follow the active speaker?** Audio-level detection is available and it is
  the standard behaviour, but it is also the thing that makes Meet's layout feel out of the
  viewer's control — which is the specific complaint this spec is answering. Proposed:
  manual spotlight only in this pass, revisit with real lesson feedback.
