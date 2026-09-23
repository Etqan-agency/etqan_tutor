---
name: phase-c3e-b-browser-hardening
phase: C
modules: [dashboard]
status: draft
created: 2026-09-07
---

## Goal

Make the call survive the browsers it was never tested on.

C3d built a working video call against Chromium only. ADR-0034 reserved Safari and iOS for C3e and
said explicitly they must not be dropped as polish — parents on iPhones are not an edge case.
C3e-a built the diagnostics channel, because this project has **no Apple device** and the e2e
harness structurally cannot cover this phase. C3e-b is the hardening itself.

Seven defects, all present in code that ships today, all of which fail **silently** on the target
browsers. That is the point: none of them throws, none reaches a log, and each produces the same
useless signal — a parent saying the lesson did not work.

## Scope

**Dashboard only.** No backend change, no signaling change, and specifically **no new signaling
message type**: the protocol stays closed at `peer-joined`, `peer-left`, `offer`, `answer`, `ice`
(C3b). That closure is load-bearing and this phase does not spend it.

Four files carry almost all of it: `useLocalMedia.ts`, `usePeerConnection.ts`,
`VideoTile.tsx`/`CallRoom.tsx`, and `routes/_call/sessions.$sessionId.room.tsx`.

## What C3e-b is not

- **Not a Safari test suite.** There is no Apple device here and Playwright's WebKit on Linux is
  neither iOS Safari nor capable of fake media. Nothing in this phase changes that.
- **Not screen sharing, recording, group calls, in-call chat, or network-quality UI.** Reject as
  scope creep.
- **Not a wake lock.** Screen lock is covered by the backgrounding recovery below; a separate
  Wake Lock API integration is a different feature and is not justified by anything observed.

## The seven fixes

### 1. `100vh` cuts the controls off on iOS

`Lobby.tsx`, `CallRoom.tsx` (terminal screen) and the room route each use `min-h-screen`, which is
`100vh`. iOS Safari's dynamic address bar makes `100vh` **taller than the visible viewport**, so in
a full-bleed layout with no page scroll, `CallControls` — leave, mute, camera — can sit below the
fold with no way to reach them. A child who cannot find the leave button stays in a lesson.

Replace all three with `min-h-dvh`.

**This must be verified by compiling, not by assumption.** A previous spec in this project
prescribed `inset-b-*`, which is **not a real Tailwind utility**: it compiled to nothing and left
the self-view tile with no vertical position, silently. The implementation asserts `min-h-dvh`
appears in the **built** CSS, not merely in the source.

### 2. `getUserMedia` runs on mount, not on a tap

`useLocalMedia` acquires in a mount effect, so the camera prompt fires on navigation. The Lobby's
Join button comes *after*, meaning there is no user gesture between arriving and requesting the
camera. iOS gates media capture on user activation in several situations, and a refusal here costs
the whole lesson.

`useLocalMedia` stops auto-acquiring and gains an explicit `start()`. The Lobby opens with **no
preview** and a "Turn on camera and microphone" control; tapping it calls `getUserMedia` inside the
gesture, and the preview and Join appear on success.

A refused or failed `start()` uses the Lobby's existing failure copy and its existing retry
control — the per-failure vocabulary from C3d, unchanged — so this adds a trigger, not a second
error-handling path.

This is a **visible product change**, not a silent fix: the Lobby gains a step it does not have
today. It matches how Meet and Zoom behave and is better for a first-time parent, but it should not
surprise a reviewer.

Only one caller (`RoomPage`) constructs this hook, so the contract change is contained. A refusal
for want of activation emits `gum-no-gesture`.

### 3. A refused autoplay is swallowed

`VideoTile` reports `autoplay-blocked` (C3e-a) but gives the user nothing to do about it. On Safari
a refused audible autoplay is both the most likely failure and a perfectly silent one — a still
frame and no sound, which reads as "the teacher isn't talking."

When `play()` rejects on the remote tile, show a **"Tap to turn on sound"** control over it. The tap
calls `play()` inside the gesture, which is exactly what the browser is waiting for. The control
disappears on success. The diagnostic still fires, so we learn how often it happens.

### 4. `restartIce()` is called unguarded

`usePeerConnection`'s `onconnectionstatechange` calls `pc.restartIce()` with no feature check. On a
browser lacking it, that **throws inside the state-change handler**, taking out the recovery path
itself — the failure mode is "reconnection silently never happens".

Guard with `typeof pc.restartIce === "function"`. When absent, go straight to `failed`, which
already surfaces a rejoin control, and emit `ice-restart-unsupported`. Safari has supported
`restartIce` since 15.4, so this is belt-and-braces — but the cost of being wrong is the whole
recovery path, and the guard is one line.

### 5. Backgrounding and screen lock are unhandled

A child switches apps or the screen locks. iOS suspends the page: media stops, and the socket may
or may not survive. Nothing handles it.

**The recovery machinery already exists.** `RoomPage.handleRetryConnection` already performs exactly
the right sequence — re-acquire local media, then remount `CallRoom` via a key bump, giving a fresh
socket and a fresh peer connection. Backgrounding does not need new recovery logic; it needs a new
**trigger**: on `visibilitychange` back to visible, if the connection is not `connected`, invoke it.
Emit `backgrounded`.

Reusing the existing path rather than writing a second one is deliberate. Two recovery mechanisms
that must agree are two mechanisms that can drift.

**The teacher's side needs no protocol change.** When the student's page suspends, either the socket
dies — the teacher already receives `peer-left` — or the media path drops and the teacher's own
connection already moves to `reconnecting`. The signal is already there; what is missing is copy a
human can act on. The teacher sees "their connection dropped — waiting for them to come back"
rather than a bare state label or a frozen tile, so they wait instead of assuming the child left.

A sixth signaling message announcing "I am backgrounding" was **considered and rejected**: it opens
a deliberately closed protocol, requires a signaling-service change, and is best-effort anyway — a
hard suspend or a screen lock may never send it, so the generic path is needed regardless. Adding it
would mean maintaining both.

### 6. A device changing mid-call is ignored

Unplugging a camera, or connecting a Bluetooth headset, is not detected. The peer connection keeps
sending the track it already has — a dead microphone that reports success.

Subscribe to `navigator.mediaDevices.ondevicechange`, and apply one rule, stated here because
"a new device should take over" is otherwise ambiguous and interacts with fix 7:

- **If the user explicitly picked a device** (in the Lobby, or from a persisted choice), keep it for
  as long as it exists. A deliberate choice outranks a newly-arrived device.
- **If they did not**, follow the system default — which means a newly-connected headset does take
  over, matching what the operating system itself does and what a parent putting headphones on
  expects.
- **If the device in use disappears**, always swap to whatever is available, whether it was chosen
  or not. The alternative is a dead microphone that reports success.

When a swap is called for, acquire the replacement and hot-swap with **`sender.replaceTrack()`**.

`replaceTrack` needs **no renegotiation** — same `m=` line, same codec — so it does not touch the
single-offerer rule, which is why this is safe to do at all. It does require `usePeerConnection` to
retain the `RTCRtpSender`s that `addTrack` returns, which it currently discards.

A vanished device emits `device-lost`.

### 7. Device choices are forgotten between lessons

The Lobby's pickers reset to the browser default every time. Persist the chosen `deviceId` per kind
in `localStorage`.

On load, if the stored id is not present in `enumerateDevices()`, **fall back to the default
silently**. A camera used last week being absent today must never block joining a lesson, and must
not produce an error the user has to dismiss.

## Testing

Unit tests throughout, each mutation-checked — a test that passes with its fix reverted is not a
test. Two need calling out because the obvious version of each proves nothing:

- **The `min-h-dvh` check asserts the class in the BUILT CSS**, not in the source. Asserting the
  source contains a string proves only that someone typed it; the `inset-b-*` incident is exactly
  a case where the source was correct-looking and the output was empty.
- **The `replaceTrack` test asserts the sender received the new track**, not merely that
  `ondevicechange` fired. The failure this fixes is a swap that silently does not happen.

e2e can cover the gesture gate and the autoplay control on Chromium. It cannot cover backgrounding,
device changes, or anything Safari-specific.

## What this phase cannot prove

**None of the seven fixes can be verified on the browser they exist for.** Every one ships blind.

The verification loop is C3e-a's diagnostics: watching `gum-no-gesture`, `autoplay-blocked`,
`backgrounded`, `device-lost` and `ice-restart-unsupported` appear, or fall silent, in the
`CallDiagnostic` table once real users arrive. That is slower and weaker than a test, it needs real
traffic before it says anything, and it is the honest best available here. It is also the entire
reason C3e-a was built first.

Like C3e-a, this phase closes under an explicit **D9 deviation** — no manual click-through on the
target browser is possible in this project — recorded in the journal rather than skipped.

## Risks

- **The gesture gate could make things worse on browsers that were fine.** Moving acquisition
  behind a tap adds a step for every user to fix a failure only some of them have. Accepted: the
  step is one tap, it matches what every other video product does, and a refused camera on iOS
  costs a whole lesson.
- **`replaceTrack` touches a live call.** This is the only fix that reaches into a working
  connection, and a bug here breaks lessons that currently succeed. Mitigated by it requiring no
  renegotiation, and by the sender-level test — but it is the riskiest item and should be reviewed
  hardest.
- **Auto-recovery on `visibilitychange` could loop.** A page that returns to visible while
  permanently unable to connect would retry on every tab switch. The existing retry path is
  bounded; the trigger must not bypass that bound.
- **The diagnostics loop reports nothing until real users arrive.** If staging sees no Safari
  traffic, these fixes stay unverified indefinitely. That is a fact about the project's position,
  not an argument against fixing them.
