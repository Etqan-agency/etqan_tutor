---
name: call-fixes
phase: C
modules: [scheduling, signaling, dashboard]
status: in-progress
created: 2026-09-12
closed: null
---

## Goal

Seven defects found by using C4's call on a real phone, plus the control-bar
redesign they motivate. Six of the seven are the same shape as the failure
`journal/2026-W36.md` names as this phase's recurring one — **something stops
working and nobody is told**: a share ends and the viewer keeps the frozen last
frame; a camera is switched off and the device stays open with the indicator
lit; a menu runs off the edge of a phone and its items simply cannot be read.
The seventh is the control bar itself, which at seven targets was already at
the edge of a 360px viewport and is measurably worse in portrait.

The unifying mechanism is a new signalling message, `media-state`. Two of the
ghosts exist because a peer's media state is only ever inferred from pixels,
and pixels latch. Telling the other side what changed replaces the inference.

## User flow

**Joining.** A returning user opens a lesson. The browser already holds a camera
and microphone grant for this origin, so the preview starts by itself and the
"Check camera and microphone" button does not appear. A first-time user, a user
who refused, and any browser that will not answer the permissions question (iOS
Safari) all still see the tap — C3e-b's gesture gate is untouched for the case
it exists for.

**Camera off.** The student taps the camera button. The track stops, the device
is released, the OS indicator goes out, and the sender's camera track is
replaced with null. A `media-state` frame tells the teacher, whose stage swaps
the frozen frame for the student's initials avatar immediately. Tapping again
re-acquires the camera — a few hundred milliseconds, and the existing
per-kind merge in `useLocalMedia.acquireOnce` means the microphone is not
disturbed. If the re-acquisition fails (the device was taken by another app in
the meantime), the in-room `MediaFailureAlert` already covers it.

**Microphone off is unchanged** — `track.enabled = false`, device held. Muting
happens mid-sentence and a re-acquire there costs latency and can fail outright.
Meet does the same.

**Screen share.** The teacher taps Share. The calling tab is not offered in the
picker (`selfBrowserSurface: "exclude"`), so the hall-of-mirrors cannot be
started. While sharing, the teacher sees a persistent "You're presenting to
everyone" banner with a **Stop presenting** button, and a small preview of what
the student is actually seeing. On stop — from our button, or from the browser's
own share bar — a `media-state` frame tells the student, whose screen tile
leaves the layout at once instead of holding the last frame for the rest of the
lesson.

**Layout and settings.** The bar is mic / camera / share / ⋮ / leave. The ⋮
opens a menu on a wide viewport and a bottom sheet on a phone, holding
Microphone, Camera, Layout, and "Show shared screen". No control opens anything
that extends past the viewport at any width.

**Error cases.** A peer running an older bundle never sends `media-state`; the
receiver falls back to today's behaviour (frames-based inference plus the manual
"Show shared screen" toggle), so a mixed-version call degrades rather than
breaks. A `media-state` frame arriving before the peer connection exists is
applied to state and survives, because it is state, not an event.

## Data model delta

None. Nothing here is persisted server-side. `useCallLayout`'s existing
`localStorage` key is unchanged.

## API delta

**Signaling service** (`backend/signaling/app.py`), one new relayable message
type:

```jsonc
{ "type": "media-state", "camera": boolean, "screen": boolean }
```

`RELAYABLE` becomes `frozenset({"offer", "answer", "ice", "media-state"})`. The
relay stays a dumb passthrough — it does not parse or validate the two booleans,
exactly as it does not parse SDP. It is relayed to the other peer only, dropped
when nobody is there, same as every other frame.

⚠ **Deploy ordering is load-bearing.** `app.py:228` closes the socket with
`CLOSE_BAD_MESSAGE` on any type outside the allowlist. A new dashboard bundle
talking to an old signaling container would therefore have its socket closed the
first time anyone toggles a camera — mid-lesson, for a child. The backend change
must merge, deploy, and be confirmed live **before** the dashboard change that
sends the frame. This is the same mismatched-bundle deploy window ADR-0039 names
for `line-mismatch`, and it is the second thing to fall into it.

No Django/product API changes. No new routes, so ADR-0029 is not engaged.

## Frontend

Routes are unchanged: `/_call/sessions/$sessionId/room`.

**A — Lobby auto-start when already granted.** `Lobby.tsx:93` derives
`showEnable` from component state alone, so it is true on every mount. On mount,
`navigator.permissions.query({ name: "camera" })` and `"microphone"`; when both
resolve `granted`, call `start()` from the effect. No prompt can appear in that
state, so no user activation is required and the gate is not being bypassed —
it is being skipped where it has nothing to gate. Every other outcome
(`prompt`, `denied`, the query rejecting, `navigator.permissions` absent) keeps
the tap. The query is injected through `UseLocalMediaDeps`' existing convention
so it is testable.

**B — Camera off releases the device.** `useLocalMedia` gains
`stopKind("video" | "audio")`, stopping only that kind's tracks and publishing a
new stream identity. `useCallRoom.toggleCamera` calls it on the way off and
`start({ video: true, audio: false })` on the way back. `usePeerConnection`'s
track-attach effect must learn that a stream with no video track means
`replaceTrack(null)` on the camera sender, rather than leaving the last track in
place — today "no track for this kind" and "do not touch this kind" are the same
state to it, and they stop being the same state here.

**C — `media-state`.** `SignalMessage` gains the variant and
`parseSignalMessage` validates both booleans. `useCallRoom` sends on every
camera and share change, and once on `peer-joined` so a late joiner is not
looking at a stale default. `CallRoom` derives `screenActive` as
`(peerScreen ?? screenHasFrames) && !screenHidden` and passes the peer's camera
state to `ParticipantTile`, which shows the avatar on `camera === false` without
waiting for a frames signal that will never fall.

**D — Self-share preview and warning.** `useScreenShare` exposes the local
`MediaStream` alongside `sharing`. `CallStage` gains a `selfScreen` slot,
rendered only while sharing, in the same corner discipline as every other
thumbnail. The banner is `role="status"`, `aria-live="polite"`, and carries the
Stop control so ending a share never requires hunting for the browser's own bar.
`getDisplayMedia` gains `selfBrowserSurface: "exclude"` and
`surfaceSwitching: "include"`; both are ignored by browsers that do not know
them, so neither is a capability gate.

**E — Control bar.** `CallControls` becomes mic / camera / share / ⋮ / leave.
`DevicePickerButton` is removed from it entirely (it stays in the Lobby, which
is a setup screen with room for visible pickers — Meet does the same).
A new `CallSettingsMenu` holds Microphone and Camera as radio groups with a
checkmark on the active device, Layout (absorbing `LayoutSwitcher`, removing a
sixth target from the bar), and "Show shared screen". Dropdown menu at `≥sm`;
**bottom sheet below `sm`** — the observed failure was a popover anchored to a
trigger at the inline end with no collision handling, and a sheet anchored to
the viewport cannot reproduce it. Every surface is width-capped at
`calc(100vw - 2rem)` regardless.

**F — One place decides object-fit.** A single `fitClassFor(role)`:

| role | fit | why |
| --- | --- | --- |
| camera, any layout or size | `object-cover` | no black bars, Meet's behaviour |
| shared screen | `object-contain` | cropping slides or code is never acceptable |
| self-view | `object-cover` + `scale-x-[-1]` | mirrored, as every other product does |

Today `CallRoom.tsx:258` hardcodes `object-contain` on the remote tile in every
layout while `VideoTile.tsx:128` defaults to `object-cover`. That split is the
whole bug: thumbnails letterbox, and in portrait the main tile becomes a
16:9 band with dead stage above and below it, which is what the device capture
driving section G actually shows. The accepted cost of `cover` on a portrait main tile is that roughly half the
frame's width is cropped; someone sitting well off-centre can go partly out of
shot. That is a deliberate trade, made once, here.

**G — Phone.** Everything below was found on one real device in portrait, dark,
at roughly 430pt:

1. The layout popover is clipped at the inline edge — three of its six items
   cannot be read at all. Fixed by E's bottom sheet plus the width cap.
2. Dead space above and below a letterboxed main tile. Fixed by F.
3. The self-view is a small black chip tucked under the header. It moves to the
   bottom corner above `--call-chrome-height` in every non-tiled layout, gains a
   larger floor so "camera off" reads as a person rather than a black box, and
   is mirrored.
4. Six targets in the bar at a width that only ever fitted seven by shrinking
   its own padding. E takes it to five.
5. `env(safe-area-inset-bottom)` on the control bar. The browser's own chrome
   sits directly under it, and a collapsing address bar moves `dvh` underneath
   a call that is already running.

## Module boundaries

`scheduling` owns the call; `signaling` owns the relay. The new message type
crosses no module boundary — the relay is type-agnostic by construction and
gains one string in an allowlist. No new imports between Django modules, so
`import-linter` is not engaged.

## Out of scope

- Releasing the **microphone** on mute. Stated and rejected above.
- Stop-detection for a peer on an older bundle. The fallback is today's
  behaviour, not a second mechanism.
- Any change to ICE, TURN, or the negotiated media lines. ADR-0039's three-line
  bundle is untouched.
- A "zoom to fill / fit" per-viewer override on the main tile. Considered and
  dropped: one fit rule, decided once.
- The marketing site, and every non-call surface.

## Test plan

**Unit (vitest, dashboard).** Lobby auto-starts when both permissions report
`granted` and does **not** when either reports `prompt`, reports `denied`, or
the query rejects. `stopKind` stops only its own kind and leaves the other
live. `toggleCamera` off releases and calls `replaceTrack(null)`; on
re-acquires without disturbing audio. `media-state` is parsed, rejected when
malformed, sent on every change and once on `peer-joined`. A peer's
`screen: false` clears `screenActive` while `screenHasFrames` is still true —
the frozen-frame case, stated directly. `fitClassFor` per role.

**Unit (pytest, backend).** `media-state` relays to the other peer and is not
echoed to the sender. A type still outside the allowlist still closes the
socket — the allowlist must widen by exactly one.

**e2e (Playwright).** Extend `call-ui.spec.ts`: a portrait flow at 430×932
asserting no horizontal scroll, every control fully inside the viewport at
≥44×44, the settings sheet fully inside the viewport, and the self-view
intersecting neither the header nor the control bar. A two-peer flow asserting
that when the sharer stops, the receiver's screen tile leaves the layout —
which is the one defect here no unit test can prove, because it is about what a
real second browser does with a real track that ended.

**Not provable here, stated rather than implied.** That the OS camera indicator
actually goes out on camera-off is an operating-system behaviour no harness in
this project can observe. It is a manual check, on the device the screenshot
came from.

## Open questions

None blocking. One decision recorded rather than asked: the microphone keeps
`track.enabled = false` and is not released.

One thing for the user, not for implementation: the capture driving section G is
**from an iOS device**. `journal/2026-W36.md` carries a standing D9 deviation
that nothing in C3e or C4 is verifiable on Safari or iOS because no Apple device
exists in this project, and C3e-a's `CallDiagnostic` codes have had no real
reporter for exactly that reason. If that device is available for testing, that
deviation can be closed and this spec's manual checks have somewhere to run.
Closing it is the user's call, not this spec's.
