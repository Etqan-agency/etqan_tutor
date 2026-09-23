# C5 Call Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix seven defects found by using C4's call on a real phone — a lobby that
re-asks for a tap on every join, a camera that never releases its device, a screen
share that leaves a frozen ghost, no view of your own share, a control bar with seven
targets, tiles that letterbox in portrait, and a menu that runs off the edge.

**Architecture:** One new signalling message, `media-state`, is the spine. Two of the
defects exist because a peer's media state is only ever inferred from pixels and pixels
latch; telling the other side what changed replaces the inference. Everything else is
local: a permissions query, a per-kind track release, one object-fit rule, and a control
bar that loses two targets to a settings menu.

**Tech Stack:** Python 3.12 / FastAPI (`backend/signaling`, pytest). React 19 +
TypeScript + Tailwind v4 + vitest + Playwright (`dashboard`).

**Spec:** `docs/superpowers/specs/2026-09-12-call-fixes-design.md` — read it before
Task 1. Every task below argues from it.

## Global Constraints

- **D3 coverage floors are ratchets and CI enforces them.** `backend` 97.7 line/branch
  (`pyproject.toml`), `dashboard` 95.2 lines / 91.5 branches / 87.0 functions
  (`vitest.config.ts`). Never lower one; raise it in the PR that lifts coverage.
  Backend coverage is measured `--cov=kaleem --cov=signaling` — **never a bare
  `pytest --cov`**, which omits unimported files and reads ~0.55 high.
- **D4 module boundaries.** No module imports another's models. Not engaged by this
  plan, but `just lint` runs `import-linter` and must stay green.
- **D5 green CI before merge. No `--no-verify`.** This machine has a dead pip proxy in
  `pip.conf`; commit with `PIP_CONFIG_FILE=/dev/null git commit …` rather than skipping
  hooks.
- **Trunk-based (ADR-0028).** `feat/<name>` → PR → `main` in submodules, `master` in
  meta. A merge to the meta trunk **is a staging deploy**.
- **a11y/i18n/RTL are a repo-wide baseline**, not per-feature. Every new string goes in
  **both** `src/locales/en/common.json` and `src/locales/ar/common.json` under `call`.
  Every new control is a real `<button>`, keyboard reachable, ≥44×44, with an accessible
  name. Use logical properties (`inset-s-*`, `inset-e-*`, `text-start`), never
  `left`/`right`.
- **Style values come from design tokens** (semantic utilities: `bg-popover`,
  `text-muted-foreground`, `border-border`). Never a hardcoded hex or `color-mix`.
- **Deploy ordering is load-bearing.** `backend/signaling/app.py:228` closes the socket
  on any `type` outside `RELAYABLE`. PR 1 must merge, deploy to staging, and be
  confirmed live **before** PR 2 merges. Do not combine them.
- **Never re-key, re-mount, or conditionally mount a `<video>` to express a state
  change.** It re-runs the media element's load algorithm, aborts a pending `play()`,
  and produces a false "Tap to turn on sound" plus a bogus `autoplay-blocked`
  diagnostic. This codebase has shipped that bug twice — see `VideoTile.tsx:50-59`.
  State changes are className changes.

---

## PR 1 — backend/signaling (merges and deploys first, alone)

### Task 1: Relay `media-state`

**Files:**
- Modify: `backend/signaling/app.py:50`
- Test: `backend/signaling/tests/test_app.py`

**Interfaces:**
- Consumes: nothing.
- Produces: the wire contract `{"type": "media-state", "camera": bool, "screen": bool}`
  is relayed to the other peer in the room. The relay does not parse or validate the
  two booleans — it is a passthrough, exactly as it is for SDP.

- [ ] **Step 1: Write the failing tests**

Add to `backend/signaling/tests/test_app.py`, following the existing relay tests'
fixtures and style (open two sockets into one room, send from one, receive on the other):

```python
def test_media_state_relays_to_the_other_peer(...):
    """The one message type C5 adds. A share that stops, or a camera that is
    switched off, is otherwise invisible to the other side: the receiving
    <video> freezes on its last frame and keeps reporting that size forever.
    """
    with _two_peers() as (first, second):
        first.send_json({"type": "media-state", "camera": False, "screen": True})
        assert second.receive_json() == {
            "type": "media-state",
            "camera": False,
            "screen": True,
        }


def test_media_state_is_not_echoed_to_the_sender(...):
    with _two_peers() as (first, second):
        first.send_json({"type": "media-state", "camera": True, "screen": False})
        assert second.receive_json()["type"] == "media-state"
        # Nothing came back to the sender: the relay is to the OTHER peer only.
        with pytest.raises(TimeoutError):
            first.receive_json(timeout=0.2)


def test_an_unknown_type_still_closes_the_socket(...):
    """The allowlist widens by exactly one. A frame we do not recognise is a
    bug or an attack, never a version to tolerate -- that property must not be
    a casualty of adding a type to the set.
    """
    with _one_peer() as peer:
        peer.send_json({"type": "chat", "body": "hi"})
        with pytest.raises(WebSocketDisconnect) as excinfo:
            peer.receive_json()
        assert excinfo.value.code == CLOSE_BAD_MESSAGE
```

Match the file's existing helper names — read `test_app.py` first and reuse whatever it
already uses to open peers rather than introducing `_two_peers`/`_one_peer` if
equivalents exist.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd backend && python -m pytest signaling/tests/test_app.py -k media_state -v
```

Expected: the two `media_state` tests FAIL — the socket is closed with
`CLOSE_BAD_MESSAGE` because `media-state` is not in the allowlist. The third
(`unknown_type`) already PASSES; it is a regression guard, not a new behaviour.

- [ ] **Step 3: Widen the allowlist by exactly one**

`backend/signaling/app.py:50`:

```python
# `media-state` is the one non-negotiation type this relay carries, and it is
# here because the browser gives the two peers no other way to learn it. A
# share that stops, or a camera that is released, leaves the receiving
# <video> frozen on its last frame -- no `resize`, no `emptied`, and
# `track.muted` stays False (all measured; see `useVideoFrames`'s comment in
# the dashboard). Inference from pixels latches; a message does not. The
# relay stays a passthrough: it does not read the two booleans, exactly as it
# does not read SDP.
RELAYABLE = frozenset({"offer", "answer", "ice", "media-state"})
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend && python -m pytest signaling/tests/test_app.py -v
```

Expected: all PASS, including the unknown-type guard.

- [ ] **Step 5: Check the coverage floor**

```bash
cd backend && python -m pytest --cov=kaleem --cov=signaling --cov-report=term-missing
```

Expected: at or above 97.7. If it rose, raise the floor in `pyproject.toml` in this
commit.

- [ ] **Step 6: Commit and open the PR**

```bash
git checkout -b feat/media-state-relay
git add signaling/app.py signaling/tests/test_app.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): relay media-state

A share that stops, or a camera that is released, is invisible to the other
peer: the receiving <video> freezes on its last frame and keeps reporting
that size. Inference from pixels latches; a message does not.

The relay stays a passthrough -- it does not read the two booleans. The
allowlist widens by exactly one, and a type outside it still closes the
socket, which this commit adds a regression test for.

⚠ Ships ALONE and deploys BEFORE the dashboard change that sends this
frame: app.py closes the socket on an unrecognised type, so a new bundle
against an old relay would drop a lesson the first time anyone toggles a
camera.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Open the PR against `main`. **After it merges, bump the meta pointer, let
`deploy-staging` run, and confirm the new relay is live before starting PR 2's merge.**
PR 2's code can be written in the meantime; it just must not merge first.

---

## PR 2 — dashboard behaviour (A, B, C, D, F)

Branch: `feat/call-fixes-behaviour`.

### Task 2: The Lobby stops re-asking when permission is already granted

**Files:**
- Modify: `dashboard/src/features/call/useLocalMedia.ts` (add `queryPermission` dep)
- Modify: `dashboard/src/features/call/Lobby.tsx:40-93`
- Test: `dashboard/src/features/call/Lobby.test.tsx`

**Interfaces:**
- Produces: `UseLocalMediaDeps.queryPermission?: (name: "camera" | "microphone") =>
  Promise<PermissionState>` and `UseLocalMediaResult.permissionsGranted: boolean | null`
  — `null` while unknown, `true` when both camera and microphone report `granted`,
  `false` otherwise. Task 3 and later consume `UseLocalMediaResult` but not this field.

- [ ] **Step 1: Write the failing tests**

In `Lobby.test.tsx`:

```tsx
it("starts the preview by itself when both permissions are already granted", async () => {
    const start = vi.fn();
    renderLobby({ start, permissionsGranted: true });
    await waitFor(() => expect(start).toHaveBeenCalledTimes(1));
    expect(
        screen.queryByRole("button", { name: /check camera and microphone/i }),
    ).not.toBeInTheDocument();
});

it("still requires the tap when permission has not been granted", async () => {
    const start = vi.fn();
    renderLobby({ start, permissionsGranted: false });
    // Flush anything an effect might have queued -- the point is that nothing did.
    await Promise.resolve();
    expect(start).not.toHaveBeenCalled();
    expect(
        screen.getByRole("button", { name: /check camera and microphone/i }),
    ).toBeInTheDocument();
});

it("requires the tap while the permission answer is still unknown", async () => {
    // `null` is what a browser that will not answer the question leaves behind
    // -- iOS Safari has no camera entry in the Permissions API at all, and the
    // query rejects. The gesture gate C3e-b exists for must survive exactly
    // that case, so `null` behaves like `false`, never like `true`.
    const start = vi.fn();
    renderLobby({ start, permissionsGranted: null });
    await Promise.resolve();
    expect(start).not.toHaveBeenCalled();
    expect(
        screen.getByRole("button", { name: /check camera and microphone/i }),
    ).toBeInTheDocument();
});
```

In `useLocalMedia.test.ts`:

```ts
it("reports permissionsGranted true only when both kinds are granted", async () => {
    const queryPermission = vi.fn().mockResolvedValue("granted");
    const { result } = renderHook(() =>
        useLocalMedia({ ...deps, queryPermission }),
    );
    await waitFor(() => expect(result.current.permissionsGranted).toBe(true));
    expect(queryPermission).toHaveBeenCalledWith("camera");
    expect(queryPermission).toHaveBeenCalledWith("microphone");
});

it("reports false when only one kind is granted", async () => {
    const queryPermission = vi
        .fn()
        .mockImplementation(async (name: string) =>
            name === "camera" ? "granted" : "prompt",
        );
    const { result } = renderHook(() =>
        useLocalMedia({ ...deps, queryPermission }),
    );
    await waitFor(() => expect(result.current.permissionsGranted).toBe(false));
});

it("reports null when the query rejects", async () => {
    // Safari has no `camera` PermissionName; the query throws a TypeError
    // rather than answering. Null, not false, so a caller can tell "we know
    // it is not granted" from "we could not ask" if it ever needs to.
    const queryPermission = vi.fn().mockRejectedValue(new TypeError("bad name"));
    const { result } = renderHook(() =>
        useLocalMedia({ ...deps, queryPermission }),
    );
    await waitFor(() => expect(result.current.permissionsGranted).toBe(null));
});
```

`renderLobby` is this file's existing helper — extend its options object with
`permissionsGranted`, defaulting to `null` so every existing test keeps its current
behaviour (the tap) unchanged.

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/Lobby.test.tsx src/features/call/useLocalMedia.test.ts
```

Expected: FAIL — `permissionsGranted` is not a property of the hook's result.

- [ ] **Step 3: Add the permission query to `useLocalMedia`**

Add to `UseLocalMediaDeps`:

```ts
	// Injected for the same reason `getUserMedia` and `subscribeDeviceChange`
	// are: this project cannot drive a real permission state, so a hook that
	// reached for `navigator.permissions` here would have a branch no test
	// could ever cover. Optional, so every existing call site keeps working.
	queryPermission?: (name: "camera" | "microphone") => Promise<PermissionState>;
```

Default implementation, alongside `defaultSubscribeDeviceChange`:

```ts
// `as PermissionName`: TypeScript's lib DOM types do not include "camera" or
// "microphone" in `PermissionName`, because the spec leaves the set
// open-ended and browsers disagree about it. That disagreement is the whole
// point here -- Chromium answers, Safari throws a TypeError for an unknown
// name, and the caller treats "could not ask" as "not granted" either way.
const defaultQueryPermission = async (name: "camera" | "microphone") => {
	const status = await navigator.permissions.query({
		name: name as PermissionName,
	});
	return status.state;
};
```

In the hook body:

```ts
	// `null` means "we have not been able to find out", which is NOT the same
	// as "not granted" and must never be collapsed into it by a caller that
	// wants to skip the gesture gate. See `Lobby`'s own use.
	const [permissionsGranted, setPermissionsGranted] = useState<boolean | null>(
		null,
	);

	// Asked once, on mount. Never re-asked: a `PermissionStatus` change while
	// someone sits in the lobby is not a state this needs to chase, and
	// subscribing to one would be a second listener for a question the
	// getUserMedia call itself answers definitively a moment later.
	useEffect(() => {
		let cancelled = false;
		void (async () => {
			try {
				const [camera, microphone] = await Promise.all([
					queryPermissionRef.current("camera"),
					queryPermissionRef.current("microphone"),
				]);
				if (!cancelled) {
					setPermissionsGranted(
						camera === "granted" && microphone === "granted",
					);
				}
			} catch {
				// The browser would not answer -- iOS Safari has no `camera`
				// PermissionName and throws. Stay `null`: the caller keeps the
				// tap, which is exactly what that platform needs anyway.
			}
		})();
		return () => {
			cancelled = true;
		};
	}, []);
```

Mirror `queryPermission` into a ref (`queryPermissionRef`) exactly as
`subscribeDeviceChange` is at `useLocalMedia.ts:684`, so the effect keeps an empty
dependency array. Return `permissionsGranted` from the hook and add it to
`UseLocalMediaResult`.

- [ ] **Step 4: Wire the Lobby**

In `Lobby.tsx`, destructure `permissionsGranted` from `localMedia`, and add below
`handleEnable`:

```tsx
	// Auto-start when the browser already holds a grant for this origin. No
	// prompt can appear in that state, so no user activation is required and
	// C3e-b's gesture gate is not being bypassed -- it is being skipped where
	// it has nothing to gate. `=== true` and not a truthiness check: `null`
	// means "we could not ask", which is every browser that will not answer
	// the permissions question, and those keep the tap.
	//
	// `requested` is set alongside, so a grant that somehow fails anyway lands
	// in the same "already asked, show the alert's own retry" state a tap
	// would have.
	useEffect(() => {
		if (permissionsGranted === true && !requested) {
			setRequested(true);
			void start();
		}
	}, [permissionsGranted, requested, start]);
```

`showEnable` at line 93 needs no change: `requested` flipping true removes the button.

- [ ] **Step 5: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/Lobby.test.tsx src/features/call/useLocalMedia.test.ts
```

Expected: PASS, including the pre-existing test "requests the camera synchronously
inside the click, not from an effect" — that test uses `permissionsGranted: null` via
the default and must stay green. **If it goes red, the auto-start is firing where the
gate applies; fix the auto-start, never that test.**

- [ ] **Step 6: Commit**

```bash
git add src/features/call/Lobby.tsx src/features/call/Lobby.test.tsx \
        src/features/call/useLocalMedia.ts src/features/call/useLocalMedia.test.ts
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): skip the lobby tap when permission is already granted

showEnable was derived from component state alone, so a returning user
whose browser already holds a grant tapped 'Check camera and microphone'
on every single join.

Asks navigator.permissions on mount and starts by itself only when BOTH
kinds report granted -- no prompt can appear in that state, so no user
activation is needed. Every other outcome keeps the tap, `null` (the
query rejecting, which is what iOS Safari does for a camera) included.
C3e-b's gate survives intact for the platform it exists for.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 3: `useLocalMedia.stopKind`

**Files:**
- Modify: `dashboard/src/features/call/useLocalMedia.ts:725-729`
- Test: `dashboard/src/features/call/useLocalMedia.test.ts`

**Interfaces:**
- Produces: `UseLocalMediaResult.stopKind: (kind: "audio" | "video") => void`. Stops
  only that kind's tracks and publishes a **new `MediaStream` identity** containing the
  survivors. Task 4 consumes it.

- [ ] **Step 1: Write the failing tests**

```ts
it("stopKind stops only its own kind and leaves the other live", async () => {
    const { result } = renderHook(() => useLocalMedia(deps));
    await act(async () => { await result.current.start(); });
    const [video] = result.current.stream!.getVideoTracks();
    const [audio] = result.current.stream!.getAudioTracks();

    act(() => { result.current.stopKind("video"); });

    expect(video.stop).toHaveBeenCalledTimes(1);
    expect(audio.stop).not.toHaveBeenCalled();
    expect(result.current.stream!.getVideoTracks()).toHaveLength(0);
    expect(result.current.stream!.getAudioTracks()).toEqual([audio]);
});

it("stopKind publishes a NEW stream identity", async () => {
    // Load-bearing, not cosmetic: usePeerConnection's track-attach effect is
    // keyed on `[localStream]`, so a mutated-in-place stream would stop the
    // camera locally and keep sending its last frame to the other peer
    // forever. The identity change IS the replaceTrack trigger.
    const { result } = renderHook(() => useLocalMedia(deps));
    await act(async () => { await result.current.start(); });
    const before = result.current.stream;

    act(() => { result.current.stopKind("video"); });

    expect(result.current.stream).not.toBe(before);
});

it("stopKind on an empty stream is a no-op", async () => {
    const { result } = renderHook(() => useLocalMedia(deps));
    act(() => { result.current.stopKind("video"); });
    expect(result.current.stream).toBeNull();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useLocalMedia.test.ts -t stopKind
```

Expected: FAIL — `stopKind is not a function`.

- [ ] **Step 3: Implement, next to `stop`**

```ts
	// Releases ONE kind of device while the call keeps running -- the camera
	// button's "off", which used to be `track.enabled = false`. That left the
	// device open, the OS indicator lit, and the hardware unavailable to every
	// other app for the rest of the lesson: "camera off" that does not turn the
	// camera off.
	//
	// A NEW `MediaStream` rather than `removeTrack` on the existing one, and
	// that is the load-bearing half. `usePeerConnection`'s attach effect is
	// keyed on `[localStream]` IDENTITY, so a stream mutated in place would
	// release the device locally and leave the other peer receiving the last
	// frame forever -- the exact ghost this wave exists to remove, moved one
	// layer down. A fresh identity runs that effect, whose
	// `stream?.getVideoTracks()[0] ?? null` then resolves to `null` and
	// `replaceTrack(null)`s the line. No renegotiation: the line stays
	// negotiated and empty, which is precisely what ADR-0039 built it for.
	const stopKind = useCallback((kind: "audio" | "video") => {
		const current = streamRef.current;
		if (!current) {
			return;
		}
		const survivors: MediaStreamTrack[] = [];
		current.getTracks().forEach((track) => {
			if (track.kind === kind) {
				track.stop();
			} else {
				survivors.push(track);
			}
		});
		const next = new MediaStream(survivors);
		streamRef.current = next;
		setStream(next);
	}, []);
```

Add `stopKind` to `UseLocalMediaResult` (with the doc comment above it) and to the
returned object.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/useLocalMedia.test.ts
```

Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/useLocalMedia.ts src/features/call/useLocalMedia.test.ts
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): stopKind releases one device without disturbing the other

Publishes a new stream identity rather than mutating in place -- that
identity change is what runs usePeerConnection's attach effect, which
already resolves an absent track to replaceTrack(null). No new branch
needed there.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 4: Camera off releases the device

**Files:**
- Modify: `dashboard/src/features/call/useCallRoom.ts:213-224`
- Test: `dashboard/src/features/call/useCallRoom.test.tsx`

**Interfaces:**
- Consumes: `localMedia.stopKind` (Task 3), `localMedia.start` (existing).
- Produces: no signature change. `toggleCamera` now releases and re-acquires.

**Note for the implementer, verified against the code:** the spec says
`usePeerConnection` "must learn that a stream with no video track means
`replaceTrack(null)`". It already does — `usePeerConnection.ts:563` is
`attachToLine("camera", stream?.getVideoTracks()[0] ?? null)`, and `attachToLine` passes
`null` straight to `replaceTrack`. **No change is needed there.** Do not add one.

- [ ] **Step 1: Write the failing tests**

```tsx
it("turning the camera off releases the device", () => {
    const localMedia = makeLocalMedia();
    const { result } = renderCallRoom({ localMedia });
    act(() => { result.current.toggleCamera(); });

    expect(localMedia.stopKind).toHaveBeenCalledWith("video");
    expect(result.current.cameraOn).toBe(false);
});

it("turning the camera back on re-acquires video without disturbing audio", async () => {
    const localMedia = makeLocalMedia();
    const { result } = renderCallRoom({ localMedia, initialCameraOn: false });
    await act(async () => { result.current.toggleCamera(); });

    expect(localMedia.start).toHaveBeenCalledWith({ video: true, audio: false });
    expect(result.current.cameraOn).toBe(true);
});

it("muting does NOT release the microphone", () => {
    // Deliberate asymmetry, recorded in the spec: muting happens mid-sentence,
    // and a re-acquire there costs hundreds of milliseconds and can fail
    // outright with the device gone. enabled=false is instant and cannot fail.
    const localMedia = makeLocalMedia();
    const { result } = renderCallRoom({ localMedia });
    act(() => { result.current.toggleMic(); });

    expect(localMedia.stopKind).not.toHaveBeenCalled();
    expect(result.current.micOn).toBe(false);
});
```

Extend the file's existing local-media test double with `stopKind: vi.fn()`.

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useCallRoom.test.tsx
```

Expected: FAIL — `stopKind` never called.

- [ ] **Step 3: Implement**

Replace `toggleCamera` at `useCallRoom.ts:222`:

```ts
	// Off RELEASES the device rather than disabling the track: the OS
	// indicator goes out and the hardware is free for every other app. The
	// old `enabled = false` left a lit camera behind a UI saying it was off,
	// which on a platform for children is not a state to leave a machine in.
	//
	// On re-acquires ONLY video -- `audio: false` is read by `acquireOnce`'s
	// per-kind merge as "leave that kind exactly as it is" (see its comment),
	// so a muted microphone is not quietly re-acquired live, and an unmuted
	// one is not interrupted mid-sentence.
	//
	// Optimistic: the flag flips before the acquisition resolves, so the
	// button responds to the tap. A failure lands in `localMedia.failure`,
	// which the in-room `MediaFailureAlert` already surfaces with its own
	// retry -- there is nothing to add here.
	const toggleCamera = useCallback(() => {
		setCameraOn((current) => {
			const next = !current;
			if (next) {
				void localMedia.start({ video: true, audio: false });
			} else {
				localMedia.stopKind("video");
			}
			return next;
		});
	}, [localMedia.start, localMedia.stopKind]);
```

The `setTrackEnabled` effect at line 213 stays exactly as it is. It still applies
`cameraOn` to whatever video track exists, which after a re-acquire is the fresh one —
that re-application is the headset bug its own comment documents, and it must not be
removed.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/useCallRoom.test.tsx src/features/call/CallRoom.test.tsx
```

Expected: PASS both files.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/useCallRoom.ts src/features/call/useCallRoom.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): camera off releases the device

enabled=false left the device open and the OS indicator lit behind a UI
saying the camera was off. Off now stops the track; on re-acquires video
alone, so a muted microphone is not quietly re-acquired live.

The microphone deliberately keeps enabled=false -- muting happens
mid-sentence and a re-acquire there costs latency and can fail.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 5: `media-state` on the wire

**Files:**
- Modify: `dashboard/src/features/call/useSignaling.ts:18-22, 99-134`
- Test: `dashboard/src/features/call/useSignaling.test.ts`

**Interfaces:**
- Produces: `SignalMessage` gains
  `| { type: "media-state"; camera: boolean; screen: boolean }`. Tasks 6 and 7 consume it.

- [ ] **Step 1: Write the failing tests**

```ts
it("parses a media-state frame", () => {
    const received: SignalMessage[] = [];
    const socket = renderSignaling((m) => received.push(m));
    socket.onmessage!({
        data: JSON.stringify({ type: "media-state", camera: false, screen: true }),
    });
    expect(received).toEqual([{ type: "media-state", camera: false, screen: true }]);
});

it.each([
    ["a missing field", { type: "media-state", camera: false }],
    ["a non-boolean", { type: "media-state", camera: "no", screen: true }],
])("drops a malformed media-state frame: %s", (_label, frame) => {
    // Dropped, never crashed over and never half-applied: a frame with one
    // valid field would otherwise be read as "the camera is off AND no screen
    // is being shared", hiding a share nobody stopped.
    const received: SignalMessage[] = [];
    const socket = renderSignaling((m) => received.push(m));
    socket.onmessage!({ data: JSON.stringify(frame) });
    expect(received).toEqual([]);
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useSignaling.test.ts -t media-state
```

Expected: FAIL — the frame is dropped by the `default` branch, so the first test gets
`[]`.

- [ ] **Step 3: Implement**

Extend the union at line 18 and amend the comment above it — it currently says "closed
at exactly these five message types and must not be extended", which stops being true:

```ts
// The relay's protocol is closed at exactly these six message types. It is
// extended only alongside the relay's own `RELAYABLE` allowlist, and only
// ever backend-first: `app.py` closes the socket on a type it does not know,
// so a client that sends ahead of a deploy drops the lesson it is in.
// Anything else arriving over the wire is either a bug on the other end or a
// mid-upgrade mismatch, and is dropped rather than trusted.
export type SignalMessage =
	| { type: "peer-joined" }
	| { type: "peer-left" }
	| { type: "offer" | "answer"; sdp: RTCSessionDescriptionInit }
	| { type: "ice"; candidate: RTCIceCandidateInit }
	// What the OTHER peer's camera and screen are doing. Not negotiation --
	// it is the only honest answer to "did that share stop", because the
	// receiving <video> freezes on its last frame and reports it forever.
	| { type: "media-state"; camera: boolean; screen: boolean };
```

In `parseSignalMessage`, before `default`:

```ts
		case "media-state": {
			const frame = parsed as { camera?: unknown; screen?: unknown };
			// BOTH booleans or nothing. A half-valid frame applied as a
			// partial update would read as "camera off and nothing shared",
			// which would hide a share nobody stopped -- worse than the stale
			// state it was meant to correct.
			if (
				typeof frame.camera !== "boolean" ||
				typeof frame.screen !== "boolean"
			) {
				return null;
			}
			return { type: "media-state", camera: frame.camera, screen: frame.screen };
		}
```

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/useSignaling.test.ts
```

Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/useSignaling.ts src/features/call/useSignaling.test.ts
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): parse the media-state frame

Both booleans or nothing -- a half-valid frame applied as a partial
update would read as 'camera off, nothing shared' and hide a share
nobody stopped.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 6: Send `media-state`

**Files:**
- Modify: `dashboard/src/features/call/useCallRoom.ts`
- Test: `dashboard/src/features/call/useCallRoom.test.tsx`

**Interfaces:**
- Consumes: `SignalMessage` (Task 5), `signaling.send` (existing),
  `screenShare.sharing` (existing).
- Produces: `UseCallRoomResult.peerMedia: { camera: boolean; screen: boolean }` —
  what the OTHER side last told us, defaulting to `{ camera: true, screen: false }`.
  Task 7 consumes it.

- [ ] **Step 1: Write the failing tests**

```tsx
it("announces the camera going off", () => {
    const send = vi.fn();
    const { result } = renderCallRoom({ send });
    send.mockClear();
    act(() => { result.current.toggleCamera(); });
    expect(send).toHaveBeenCalledWith({
        type: "media-state", camera: false, screen: false,
    });
});

it("announces a share starting and stopping", async () => {
    const send = vi.fn();
    const { result } = renderCallRoom({ send });
    await act(async () => { await result.current.screenShare.start(); });
    expect(send).toHaveBeenCalledWith({
        type: "media-state", camera: true, screen: true,
    });
    send.mockClear();
    act(() => { result.current.screenShare.stop(); });
    expect(send).toHaveBeenCalledWith({
        type: "media-state", camera: true, screen: false,
    });
});

it("announces the current state once when a peer joins", () => {
    // A late joiner must not be handed a stale default. Whoever was already
    // in the room with their camera off would otherwise appear live to the
    // person who just arrived, until the next time they happened to toggle.
    const send = vi.fn();
    const { result, deliver } = renderCallRoom({ send });
    act(() => { result.current.toggleCamera(); });
    send.mockClear();
    act(() => { deliver({ type: "peer-joined" }); });
    expect(send).toHaveBeenCalledWith({
        type: "media-state", camera: false, screen: false,
    });
});

it("records what the peer announces", () => {
    const { result, deliver } = renderCallRoom({});
    expect(result.current.peerMedia).toEqual({ camera: true, screen: false });
    act(() => {
        deliver({ type: "media-state", camera: false, screen: true });
    });
    expect(result.current.peerMedia).toEqual({ camera: false, screen: true });
});
```

`deliver` is a helper the test file needs: it calls the `onMessage` the hook passed to
`useSignaling`. If the file does not already have one, add it to the harness.

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useCallRoom.test.tsx
```

Expected: FAIL — `peerMedia` undefined, no `media-state` sent.

- [ ] **Step 3: Implement**

In `useCallRoom`, after `screenShare` is created:

```ts
	// What the OTHER side last told us. The default is the optimistic one on
	// purpose: a peer running a bundle from before this message existed never
	// sends it, and must not therefore appear to have their camera off for
	// the whole lesson. Absent news, assume a working camera and no share --
	// which is exactly what the frames-based inference in `CallRoom` falls
	// back to anyway.
	const [peerMedia, setPeerMedia] = useState({ camera: true, screen: false });
```

Route it in `onMessage`, before the peer connection sees the message:

```ts
	const onMessage = useCallback((message: SignalMessage) => {
		if (message.type === "media-state") {
			// Handled here and NOT forwarded: `usePeerConnection` speaks
			// offer/answer/ice and nothing else, and handing it a type it has
			// no case for is how a stray frame becomes an exception mid-lesson.
			setPeerMedia({ camera: message.camera, screen: message.screen });
			return;
		}
		if (message.type === "peer-joined") {
			// Someone arrived: tell them what is already true here. Without
			// this, a participant who muted their camera before the other
			// joined appears live to them until the next toggle.
			announceRef.current();
		}
		void handleSignalRef.current(message);
	}, []);
```

The announcement itself, memoised on nothing and read through a ref so `onMessage` can
stay stable:

```ts
	// One writer for this frame, so the two booleans can never disagree with
	// each other or be sent half-updated. Called from the toggles and from
	// `peer-joined`.
	const announce = useCallback(
		(next?: { camera?: boolean; screen?: boolean }) => {
			signaling.send({
				type: "media-state",
				camera: next?.camera ?? cameraOn,
				screen: next?.screen ?? screenShare.sharing,
			});
		},
		[signaling.send, cameraOn, screenShare.sharing],
	);
	const announceRef = useRef(announce);
	announceRef.current = announce;
```

Call `announce({ camera: next })` from inside `toggleCamera`'s updater (it already
computes `next`), and announce the share on change with an effect keyed on
`screenShare.sharing`:

```ts
	// An effect rather than a line inside `start`/`stop`, because the browser's
	// OWN "Stop sharing" bar ends a share without going through either -- see
	// `useScreenShare`'s `ended` listener. Keyed on the flag, so both routes
	// out of a share announce identically.
	//
	// Skips the mount run: a fresh room announcing `screen: false` before the
	// socket is even open is a dropped frame at best, and at worst a
	// contradiction of the `peer-joined` announcement a moment later.
	const announcedSharingRef = useRef(screenShare.sharing);
	useEffect(() => {
		if (announcedSharingRef.current === screenShare.sharing) {
			return;
		}
		announcedSharingRef.current = screenShare.sharing;
		announceRef.current({ screen: screenShare.sharing });
	}, [screenShare.sharing]);
```

Return `peerMedia` from the hook and add it to `UseCallRoomResult`.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/
```

Expected: PASS across the feature.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/useCallRoom.ts src/features/call/useCallRoom.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): announce and record media-state

Sent on every camera and share change, and once on peer-joined so a late
joiner is not handed a stale default. One writer, so the two booleans
cannot disagree.

The share announcement is an effect keyed on the flag rather than a line
in start/stop: the browser's own 'Stop sharing' bar ends a share without
going through either.

peerMedia defaults optimistic -- a peer on an older bundle never sends
this and must not appear camera-off for the whole lesson.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 7: The ghosts go away

**Files:**
- Modify: `dashboard/src/features/call/CallRoom.tsx:132-190, 251-263`
- Modify: `dashboard/src/features/call/ParticipantTile.tsx`
- Test: `dashboard/src/features/call/CallRoom.test.tsx`,
  `dashboard/src/features/call/ParticipantTile.test.tsx`

**Interfaces:**
- Consumes: `room.peerMedia` (Task 6).
- Produces: `ParticipantTileProps.cameraOff?: boolean` — when `true`, the avatar shows
  regardless of what the frames signal says.

- [ ] **Step 1: Write the failing tests**

In `CallRoom.test.tsx`:

```tsx
it("drops the screen tile out of the layout when the peer says the share stopped", async () => {
    // THE defect. `useVideoFrames` latches: when a sharer stops, the receiving
    // <video> freezes on its last frame, keeps reporting that size, fires no
    // `resize` and no `emptied`, and `track.muted` stays false. Without the
    // message the frozen screenshot holds the main tile for the rest of the
    // lesson, with the other person stuck as a thumbnail, in EVERY layout.
    const { deliver } = renderCallRoom({ screenHasFrames: true });
    expect(screen.getByTestId("call-tile-screen")).not.toHaveClass(
        ...IDLE_SCREEN_TILE.split(" "),
    );

    act(() => { deliver({ type: "media-state", camera: true, screen: false }); });

    expect(screen.getByTestId("call-tile-screen")).toHaveClass(
        ...IDLE_SCREEN_TILE.split(" "),
    );
});

it("keeps showing the screen while the peer still says it is sharing", () => {
    const { deliver } = renderCallRoom({ screenHasFrames: true });
    act(() => { deliver({ type: "media-state", camera: true, screen: true }); });
    expect(screen.getByTestId("call-tile-screen")).not.toHaveClass(
        ...IDLE_SCREEN_TILE.split(" "),
    );
});
```

In `ParticipantTile.test.tsx`:

```tsx
it("shows the avatar the moment the peer says their camera is off", () => {
    // Same latch as the screen: a released camera leaves the last frame
    // frozen on the receiver, so the frames signal never falls and the
    // person appears to still be there, motionless.
    render(<ParticipantTile stream={stream} name="Fatima Ahmed" cameraOff />);
    expect(screen.getByText("FA")).toBeInTheDocument();
    expect(screen.getByRole("group")).toHaveAccessibleName(/camera off/i);
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/CallRoom.test.tsx src/features/call/ParticipantTile.test.tsx
```

Expected: FAIL.

- [ ] **Step 3: Implement**

In `ParticipantTile.tsx`, add the prop with its comment and fold it in:

```tsx
	// What the peer SAID, as opposed to what their pixels imply. Optional, and
	// `false` is not "their camera is on" -- it is "they have not told us
	// otherwise", so the frames signal still decides on its own. Only `true`
	// overrides, because only `true` carries information the pixels cannot:
	// `useVideoFrames` never falls back to false once frames have arrived.
	cameraOff?: boolean;
```

```tsx
	const hasFrames = useVideoFrames(videoRef) && !cameraOff;
```

That single line is the whole change — every existing use of `hasFrames` (the avatar,
the accessible name) then follows automatically, with no second code path to keep in
step.

In `CallRoom.tsx`, replace the `screenActive` derivation at line 160:

```tsx
	// Frames say a picture is arriving; the peer's own announcement says
	// whether they mean to be sending one. The announcement WINS when it says
	// no, and that is the whole fix: `screenHasFrames` latches (the receiving
	// <video> freezes on the last frame and reports it forever), so nothing in
	// the browser would otherwise ever tell this component the share ended.
	//
	// It does NOT win when it says yes -- `screenHasFrames` is still required.
	// A peer can announce a share a beat before the first frame decodes, and
	// promoting a blank tile to the main slot on the strength of an
	// announcement is the same defect ADR-0039's pre-negotiated line already
	// caused once, from the other direction.
	//
	// `screenHidden` stays. It is the escape hatch for the case this message
	// cannot cover: a peer running a bundle from before it existed, whose
	// `peerMedia.screen` sits at the optimistic default forever.
	const screenActive = screenHasFrames && room.peerMedia.screen && !screenHidden;
```

Pass `cameraOff={!room.peerMedia.camera}` to the remote `ParticipantTile`.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/
```

Expected: PASS. The pre-existing "a viewer can escape a screen that outstays its share"
behaviour is unchanged — `screenHidden` still forces `false`.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/CallRoom.tsx src/features/call/CallRoom.test.tsx \
        src/features/call/ParticipantTile.tsx src/features/call/ParticipantTile.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "fix(call): a stopped share and a released camera stop haunting the stage

useVideoFrames latches -- a receiving <video> freezes on the last frame,
reports that size forever, fires no resize and no emptied, and
track.muted stays false. So a share that ended kept the main tile for
the rest of the lesson with the other person as a thumbnail, in every
layout, and a released camera left a motionless person on screen.

The peer's own announcement decides, but only in the direction the
pixels cannot: 'no' overrides frames, 'yes' still requires them. The
manual hide toggle stays for peers on older bundles.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 8: See your own share, with the warning

**Files:**
- Modify: `dashboard/src/features/call/useScreenShare.ts`
- Modify: `dashboard/src/features/call/CallStage.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx`
- Create: `dashboard/src/features/call/PresentingBanner.tsx`
- Create: `dashboard/src/features/call/PresentingBanner.test.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/call/useScreenShare.test.ts`,
  `dashboard/src/features/call/CallStage.test.tsx`

**Interfaces:**
- Produces: `UseScreenShareResult.stream: MediaStream | null` (the local capture, for
  preview). `CallStageProps.selfScreen?: React.ReactNode`. `PresentingBanner` with
  props `{ onStop: () => void }`.

- [ ] **Step 1: Write the failing tests**

`useScreenShare.test.ts`:

```ts
it("excludes the calling tab from the picker", () => {
    // The hall-of-mirrors, prevented at the source rather than warned about
    // after the fact: sharing the tab you are calling in renders the share
    // inside the share inside the share. Ignored by browsers that do not know
    // the option, so this is not a capability gate.
    const getDisplayMedia = vi.fn().mockResolvedValue(new MediaStream());
    const { result } = renderHook(() =>
        useScreenShare({ setScreenTrack: vi.fn(), getDisplayMedia }),
    );
    await act(async () => { await result.current.start(); });
    expect(getDisplayMedia).toHaveBeenCalledWith({
        video: true,
        selfBrowserSurface: "exclude",
        surfaceSwitching: "include",
    });
});

it("exposes the captured stream for a local preview", async () => {
    const track = makeTrack("video");
    const stream = new MediaStream([track]);
    const { result } = renderHook(() =>
        useScreenShare({
            setScreenTrack: vi.fn(),
            getDisplayMedia: vi.fn().mockResolvedValue(stream),
        }),
    );
    await act(async () => { await result.current.start(); });
    expect(result.current.stream?.getVideoTracks()).toEqual([track]);
});

it("drops the preview stream when the share stops", async () => {
    const { result } = renderHook(() => /* as above */);
    await act(async () => { await result.current.start(); });
    act(() => { result.current.stop(); });
    expect(result.current.stream).toBeNull();
});
```

`PresentingBanner.test.tsx`:

```tsx
it("tells you that you are presenting, politely", () => {
    render(<PresentingBanner onStop={vi.fn()} />);
    const status = screen.getByRole("status");
    expect(status).toHaveAttribute("aria-live", "polite");
    expect(status).toHaveTextContent(/presenting to everyone/i);
});

it("stops the share from its own button", () => {
    // The browser's own share bar is not always visible -- it is not visible
    // at all on a phone -- so ending a share must be possible from inside the
    // app without hunting for it.
    const onStop = vi.fn();
    render(<PresentingBanner onStop={onStop} />);
    fireEvent.click(screen.getByRole("button", { name: /stop presenting/i }));
    expect(onStop).toHaveBeenCalledTimes(1);
});
```

`CallStage.test.tsx`:

```tsx
it("renders the self-share tile only while sharing", () => {
    const { rerender } = render(<CallStage {...props} selfScreen={null} />);
    expect(screen.queryByTestId("call-tile-self-screen")).not.toBeInTheDocument();
    rerender(<CallStage {...props} selfScreen={<div />} />);
    expect(screen.getByTestId("call-tile-self-screen")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useScreenShare.test.ts src/features/call/CallStage.test.tsx
```

Expected: FAIL, and `PresentingBanner.test.tsx` fails to resolve its import.

- [ ] **Step 3: Implement `useScreenShare`**

Add `const [stream, setStream] = useState<MediaStream | null>(null)`; set it alongside
`setSharing(true)` and clear it in `stop`. Change the capture call:

```ts
			const stream = await getDisplayMedia({
				video: true,
				// The calling tab is not offered in the picker at all, so the
				// hall-of-mirrors cannot be started rather than merely being
				// warned about. Both options are ignored by browsers that do
				// not know them, so neither is a capability gate.
				selfBrowserSurface: "exclude",
				// Lets someone switch which window they are sharing without
				// tearing the share down and renegotiating.
				surfaceSwitching: "include",
			} as DisplayMediaStreamOptions);
```

Add `stream` to `UseScreenShareResult`.

- [ ] **Step 4: Write `PresentingBanner.tsx`**

```tsx
import { MonitorUp } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/ui";

export interface PresentingBannerProps {
	onStop: () => void;
}

/**
 * Shown to the person who is sharing, for as long as they are sharing.
 *
 * `role="status"` with `aria-live="polite"` -- never `alert`/assertive. It is
 * a standing fact about the call, not an interruption, and an assertive
 * announcement mid-lesson steals focus from whatever a teacher is doing.
 *
 * Carries its own Stop control because the browser's share bar is not always
 * reachable, and on a phone is not shown at all -- without this, ending a
 * share means hunting for chrome that may not exist.
 */
export function PresentingBanner({ onStop }: PresentingBannerProps) {
	const { t } = useTranslation();
	return (
		<div
			role="status"
			aria-live="polite"
			data-testid="presenting-banner"
			className="flex items-center gap-3 rounded-full border border-border bg-popover px-4 py-2 text-sm text-popover-foreground shadow-lg"
		>
			<MonitorUp aria-hidden="true" className="size-4 shrink-0" />
			<span className="min-w-0 flex-1">{t("call.presenting")}</span>
			<Button type="button" variant="destructive" size="sm" onClick={onStop}>
				{t("call.stopPresenting")}
			</Button>
		</div>
	);
}
```

- [ ] **Step 5: Add the copy to both locales**

`en/common.json`, under `call`:

```json
"presenting": "You're presenting to everyone",
"stopPresenting": "Stop presenting",
"yourSharedScreen": "Your shared screen"
```

`ar/common.json`, under `call`:

```json
"presenting": "أنت تشارك شاشتك مع الجميع",
"stopPresenting": "إيقاف المشاركة",
"yourSharedScreen": "شاشتك المشاركة"
```

- [ ] **Step 6: Wire the stage**

Add `selfScreen?: React.ReactNode` to `CallStageProps`, and render it as a fourth tile
wrapper inside `call-stage-grid`, after `call-tile-self`:

```tsx
				{selfScreen ? (
					// Unlike the three above, this one IS conditionally mounted,
					// and the difference is real rather than an inconsistency:
					// those three carry a REMOTE <video> whose `play()` a remount
					// would abort (see the module comment). This carries a local
					// preview of a capture that, when absent, does not exist at
					// all -- there is no element to keep alive and no pending
					// play() to protect.
					<div
						data-testid="call-tile-self-screen"
						className="absolute inset-s-4 top-20 z-20 aspect-video w-[clamp(5rem,20vw,9rem)] overflow-hidden rounded-lg border border-border shadow-lg"
					>
						{selfScreen}
					</div>
				) : null}
```

In `CallRoom.tsx`, pass both:

```tsx
			selfScreen={
				room.screenShare.sharing ? (
					<VideoTile
						stream={room.screenShare.stream}
						muted
						className="h-full w-full rounded-none object-contain"
						data-testid="self-screen"
					/>
				) : null
			}
			banner={
				room.mediaFailure ? (
					<MediaFailureAlert … />
				) : room.screenShare.sharing ? (
					<PresentingBanner onStop={room.screenShare.stop} />
				) : undefined
			}
```

A media failure outranks the presenting banner: one is something broken that needs
action, the other is a standing fact.

- [ ] **Step 7: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/features/call/useScreenShare.ts src/features/call/useScreenShare.test.ts \
        src/features/call/PresentingBanner.tsx src/features/call/PresentingBanner.test.tsx \
        src/features/call/CallStage.tsx src/features/call/CallStage.test.tsx \
        src/features/call/CallRoom.tsx src/locales/en/common.json src/locales/ar/common.json
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): see your own share, and know you are sharing

A local preview tile plus a standing 'You're presenting to everyone'
banner with its own Stop control -- the browser's share bar is not
reachable on a phone, so ending a share needed a control inside the app.

selfBrowserSurface: exclude keeps the calling tab out of the picker, so
the hall-of-mirrors is prevented rather than warned about.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 9: One place decides object-fit

**Files:**
- Create: `dashboard/src/features/call/tileFit.ts`
- Create: `dashboard/src/features/call/tileFit.test.ts`
- Modify: `dashboard/src/features/call/CallRoom.tsx:258`,
  `dashboard/src/features/call/SelfView.tsx`

**Interfaces:**
- Produces: `fitClassFor(role: "camera" | "screen" | "self"): string`.

- [ ] **Step 1: Write the failing test**

```ts
import { fitClassFor } from "./tileFit";

describe("fitClassFor", () => {
    it("fills camera tiles, so nothing letterboxes", () => {
        // The defect: CallRoom hardcoded object-contain on the remote tile in
        // every layout while VideoTile defaulted to object-cover. Thumbnails
        // letterboxed, and in portrait the main tile became a 16:9 band with
        // dead stage above and below it.
        expect(fitClassFor("camera")).toContain("object-cover");
    });

    it("never crops a shared screen", () => {
        // Slides and code lose their edges, which is the one case where a
        // black bar is the correct answer.
        expect(fitClassFor("screen")).toContain("object-contain");
    });

    it("fills and mirrors the self view", () => {
        // Mirrored because every other product does: an unmirrored self view
        // makes people reach the wrong way when they point at something.
        expect(fitClassFor("self")).toContain("object-cover");
        expect(fitClassFor("self")).toContain("-scale-x-100");
    });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd dashboard && pnpm vitest run src/features/call/tileFit.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```ts
/**
 * How each kind of tile fills its box. One function so the rule is decided
 * once and cannot drift.
 *
 * It had drifted, in exactly the way a rule with two homes does: `CallRoom`
 * hardcoded `object-contain` on the remote tile for every layout, while
 * `VideoTile`'s own default was `object-cover`. So thumbnails letterboxed,
 * and on a phone in portrait the main tile became a 16:9 band floating in
 * dead stage -- measured on a real device, not inferred.
 *
 * Deliberately takes no `layout` and no viewport: the rule is per ROLE and
 * nothing else. A rule that varies by layout is a rule that has to be
 * re-derived at every call site, which is how this one broke.
 *
 * The accepted cost of `cover` on a portrait main tile is that roughly half
 * the frame's width is cropped, so someone sitting well off-centre can go
 * partly out of shot. That is the trade Meet makes too, and it is made once,
 * here, rather than argued about per tile.
 */
export function fitClassFor(role: "camera" | "screen" | "self"): string {
	if (role === "screen") {
		return "object-contain";
	}
	if (role === "self") {
		// `-scale-x-100`, not `scale-x-[-1]`: the first is the canonical
		// Tailwind v4 spelling and is what Biome's class sorter expects.
		return "object-cover -scale-x-100";
	}
	return "object-cover";
}
```

- [ ] **Step 4: Use it everywhere a fit is currently spelled out**

`CallRoom.tsx:258` — the remote `ParticipantTile`:

```tsx
						className={cn("h-full w-full rounded-none", fitClassFor("camera"))}
```

The `remoteScreen` `VideoTile` (line ~278) and the `selfScreen` tile from Task 8:
`fitClassFor("screen")`. `SelfView.tsx`'s `VideoTile`: pass
`className={fitClassFor("self")}`.

- [ ] **Step 5: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/ && pnpm lint
```

Expected: PASS and clean.

- [ ] **Step 6: Commit**

```bash
git add src/features/call/tileFit.ts src/features/call/tileFit.test.ts \
        src/features/call/CallRoom.tsx src/features/call/SelfView.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "fix(call): one rule decides object-fit, and it fills

CallRoom hardcoded object-contain on the remote tile in every layout
while VideoTile defaulted to object-cover -- so thumbnails letterboxed,
and in portrait on a real phone the main tile was a 16:9 band floating
in dead stage.

Camera tiles fill and crop, shared screens never crop, the self view
fills and mirrors. Per role, not per layout: a rule that varies by
layout is one that gets re-derived at every call site, which is how
this one broke.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 10: Open PR 2

- [ ] **Step 1: Run the full gate**

```bash
cd dashboard && pnpm lint && pnpm vitest run --coverage
```

Expected: green, and coverage at or above 95.2 / 91.5 / 87.0. **If any number rose,
raise the floor in `vitest.config.ts` in this PR.** If one dropped, find the untested
branch and test it — do not lower a floor (ADR-0026 requires an ADR for that).

- [ ] **Step 2: Push and open the PR**

Title: `feat(call): release the camera, kill the ghosts, fill the tiles`.
Body must state: depends on the signaling `media-state` relay being **live on staging**,
and must not merge before it is.

---

## PR 3 — dashboard controls and phone (E, G)

Branch: `feat/call-controls-redesign`, off PR 2's branch.

### Task 11: `CallSettingsMenu`

**Files:**
- Create: `dashboard/src/features/call/CallSettingsMenu.tsx`
- Create: `dashboard/src/features/call/CallSettingsMenu.test.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

**Interfaces:**
- Produces: `CallSettingsMenu` with props
  `{ devices, selectedCameraId, selectedMicrophoneId, selectCamera, selectMicrophone,
  layout, onLayoutChange, spotlightOn, onSpotlightChange, screenAvailable, screenShown,
  onToggleScreen }` — the union of what `DevicePickerButton` and `LayoutSwitcher` took.
  Task 12 consumes it.

- [ ] **Step 1: Write the failing tests**

```tsx
it("is one trigger, not one per setting", () => {
    render(<CallSettingsMenu {...props} />);
    expect(screen.getByRole("button", { name: /call settings/i })).toBeInTheDocument();
});

it("never renders wider than the viewport", () => {
    // THE phone defect, in the one form a unit test can hold: the old
    // LayoutSwitcher panel was `absolute inset-s-0 w-56` anchored to a
    // trigger sitting at the inline end of the control bar, so on a phone
    // three of its six items were clipped off the edge and could not be read
    // at all. A class assertion cannot prove geometry -- the e2e flow in
    // Task 14 measures that. This asserts the cap exists.
    render(<CallSettingsMenu {...props} />);
    fireEvent.click(screen.getByRole("button", { name: /call settings/i }));
    expect(screen.getByTestId("call-settings-panel").className).toContain(
        "max-w-[calc(100vw-2rem)]",
    );
});

it("picks a microphone", () => {
    const selectMicrophone = vi.fn();
    render(<CallSettingsMenu {...props} selectMicrophone={selectMicrophone} />);
    fireEvent.click(screen.getByRole("button", { name: /call settings/i }));
    fireEvent.click(screen.getByRole("radio", { name: /headset microphone/i }));
    expect(selectMicrophone).toHaveBeenCalledWith("mic-2");
});

it("marks the active device", () => {
    render(<CallSettingsMenu {...props} selectedCameraId="cam-1" />);
    fireEvent.click(screen.getByRole("button", { name: /call settings/i }));
    expect(screen.getByRole("radio", { name: /front camera/i })).toHaveAttribute(
        "aria-checked", "true",
    );
});

it("switches layout", () => {
    const onLayoutChange = vi.fn();
    render(<CallSettingsMenu {...props} onLayoutChange={onLayoutChange} />);
    fireEvent.click(screen.getByRole("button", { name: /call settings/i }));
    fireEvent.click(screen.getByRole("radio", { name: /tiled/i }));
    expect(onLayoutChange).toHaveBeenCalledWith("tiled");
});

it("closes on Escape and returns focus to the trigger", () => {
    // A keyboard user who loses focus mid-lesson is stranded with a live call
    // they cannot control.
    render(<CallSettingsMenu {...props} />);
    const trigger = screen.getByRole("button", { name: /call settings/i });
    fireEvent.click(trigger);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByTestId("call-settings-panel")).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
});

it("offers the shared-screen toggle only when there is a screen", () => {
    const { rerender } = render(<CallSettingsMenu {...props} screenAvailable={false} />);
    fireEvent.click(screen.getByRole("button", { name: /call settings/i }));
    expect(screen.queryByRole("button", { name: /shared screen/i })).not.toBeInTheDocument();
    rerender(<CallSettingsMenu {...props} screenAvailable />);
    expect(screen.getByRole("button", { name: /shared screen/i })).toBeInTheDocument();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/CallSettingsMenu.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Build it by **moving** `LayoutSwitcher.tsx`'s implementation — its `ITEM_CLASS`,
`ITEM_CHECKED_CLASS`, the layout and spotlight radio groups, the shared-screen toggle,
and the whole open/Escape/outside-click/focus-restore block, which is already correct
and tested. Do not rewrite that behaviour; carry it over with its comments.

Add on top of it:

- A `MoreVertical` trigger with `aria-label={t("call.settings")}`,
  `aria-haspopup="true"`, `aria-expanded`.
- Two device radio groups above the layout group, each built from `devices.microphones`
  / `devices.cameras`, using the same custom-radio shape (`role="radio"`,
  `aria-checked`, the `biome-ignore` comment explaining why a native `<input>` cannot
  carry an icon plus a label here). Fall back to `t("call.microphone")` /
  `t("call.camera")` for a device whose `label` is an empty string — that is what a
  browser returns before a grant, and a blank row is unusable.
- Section headings (`<p class="px-3 pt-1 text-xs text-muted-foreground">`) naming each
  group, with each `radiogroup` labelled by `aria-label`.

Panel classes — the phone fix:

```tsx
					// Anchored to the VIEWPORT below `sm`, not to the trigger. The
					// panel this replaces was `absolute inset-s-0 w-56` hanging off
					// a trigger that sits at the inline end of the control bar, so
					// on a 430pt phone three of its six items were clipped off the
					// edge -- unreadable, and unreachable. A sheet pinned to the
					// viewport cannot reproduce that, whatever the trigger's
					// position. `max-w` caps it at every width regardless, which is
					// the belt to the sheet's braces.
					className={cn(
						"z-50 flex max-h-[70dvh] flex-col gap-2 overflow-y-auto",
						"rounded-md border border-border bg-popover p-2 text-popover-foreground shadow-lg",
						"max-w-[calc(100vw-2rem)]",
						// Phone: a sheet along the bottom edge, above the control bar.
						"fixed inset-x-4 bottom-[calc(var(--call-chrome-height)+1rem)]",
						// Wider: back to a popover anchored above the trigger.
						"sm:absolute sm:inset-s-0 sm:inset-x-auto sm:bottom-full sm:mb-2 sm:w-64",
					)}
```

Add `data-testid="call-settings-panel"` to it.

- [ ] **Step 4: Add the copy to both locales**

`en`: `"settings": "Call settings"`, `"chooseMicrophoneHeading": "Microphone"`,
`"chooseCameraHeading": "Camera"`, `"layoutHeading": "Layout"`.
`ar`: `"settings": "إعدادات المكالمة"`, `"chooseMicrophoneHeading": "الميكروفون"`,
`"chooseCameraHeading": "الكاميرا"`, `"layoutHeading": "التخطيط"`.

- [ ] **Step 5: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/CallSettingsMenu.test.tsx
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/features/call/CallSettingsMenu.tsx src/features/call/CallSettingsMenu.test.tsx \
        src/locales/en/common.json src/locales/ar/common.json
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): one settings menu, a sheet on a phone

Carries over LayoutSwitcher's open/Escape/outside-click/focus-restore
behaviour unchanged and adds the two device radio groups to it.

Below sm the panel is pinned to the VIEWPORT, not to its trigger. The
panel it replaces hung off a trigger at the inline end of the control
bar, so on a real phone three of its six items were clipped off the edge
-- unreadable and unreachable.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 12: The control bar drops to five targets

**Files:**
- Modify: `dashboard/src/features/call/CallControls.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx:299-324`
- Delete: `dashboard/src/features/call/LayoutSwitcher.tsx`,
  `dashboard/src/features/call/LayoutSwitcher.test.tsx`
- Test: `dashboard/src/features/call/CallControls.test.tsx`

**Interfaces:**
- Consumes: `CallSettingsMenu` (Task 11).
- Produces: `CallControlsProps` loses nothing and gains the menu's props, which it
  forwards. `DevicePickerButton` stays in the repo — the Lobby still uses it.

- [ ] **Step 1: Write the failing test**

```tsx
it("is five controls, not seven", () => {
    // Measured, not guessed: at 360px the seven-target row came to 372px of
    // content in a 344px box -- the mute button sat at x = -6, clipped off
    // the start edge, and the document gained a 14px horizontal scroll. The
    // targets are 44x44 and must not shrink; the count is what gives.
    render(<CallControls {...props} />);
    const bar = screen.getByTestId("call-controls");
    expect(within(bar).getAllByRole("button")).toHaveLength(5);
});

it("still exposes every control it used to", () => {
    render(<CallControls {...props} />);
    for (const name of [
        /mute microphone/i, /turn camera off/i, /share your screen/i,
        /call settings/i, /leave/i,
    ]) {
        expect(screen.getByRole("button", { name })).toBeInTheDocument();
    }
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd dashboard && pnpm vitest run src/features/call/CallControls.test.tsx
```

Expected: FAIL — seven buttons.

- [ ] **Step 3: Implement**

Rewrite `CallControls`' body: keep the mic and camera `<Button>`s exactly as they are
today (`aria-pressed` reflecting "is this action in effect", the same icons, the same
labels) but **unwrapped** — no `DevicePickerButton` around either. Keep the screen-share
button and the leave button unchanged. Insert `<CallSettingsMenu {...} />` between share
and leave, and add `data-testid="call-controls"` to the row.

Leave the row's own classes alone — `flex items-center justify-center gap-1 sm:gap-3
landscape:max-md:flex-col` is already correct and its tightening is measured.

In `CallRoom.tsx`, delete the `<LayoutSwitcher>` element and its wrapper `<div
className="flex items-center gap-1 sm:gap-3">`; `controls` becomes the `<CallControls>`
element alone, now also receiving `layout`, `onLayoutChange={setLayout}`, `spotlightOn`,
`onSpotlightChange={setSpotlightOn}`, `screenAvailable={screenHasFrames}`,
`screenShown={!screenHidden}`, and `onToggleScreen`.

Delete `LayoutSwitcher.tsx` and `LayoutSwitcher.test.tsx` — its behaviour and its tests
now live in `CallSettingsMenu`.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/
```

Expected: PASS. `CallRoom.test.tsx` will need the layout assertions repointed at the
settings menu's trigger; update them rather than deleting them.

- [ ] **Step 5: Commit**

```bash
git add -A src/features/call/
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): five controls in the bar, not seven

The chevron device pickers leave the call stage entirely; the Lobby
keeps DevicePickerButton, being a setup screen with room for it.
LayoutSwitcher is absorbed into the settings menu rather than kept as a
sixth target.

At 360px the seven-target row was 372px of content in a 344px box -- the
mute button clipped off the start edge and the document scrolled
sideways. The targets stay 44x44; the count is what gives.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 13: The stage on a phone

**Files:**
- Modify: `dashboard/src/features/call/CallStage.tsx`
- Test: `dashboard/src/features/call/CallStage.test.tsx`

- [ ] **Step 1: Write the failing tests**

```tsx
it("keeps the control bar clear of the device's safe area", () => {
    // The browser's own chrome sits directly under this bar on a phone, and
    // a collapsing address bar moves dvh underneath a call already running.
    render(<CallStage {...props} />);
    expect(screen.getByTestId("call-controls-bar").className).toContain(
        "pb-[env(safe-area-inset-bottom)]",
    );
});

it("puts the self view in the bottom corner, not under the header", () => {
    // It sat at `top-20`, overlapping the header on a phone and reading as a
    // black chip rather than as a person.
    render(<CallStage {...props} layout="spotlight" />);
    const self = screen.getByTestId("call-tile-self");
    expect(self.className).toContain("bottom-[calc(var(--call-chrome-height)+1rem)]");
    expect(self.className).not.toContain("top-20");
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/CallStage.test.tsx
```

Expected: FAIL.

- [ ] **Step 3: Implement**

In `CallStage.tsx`, change the `THUMBNAIL` positioning used by `selfTileClass` and
`remoteTileClass`'s spotlight branches from `top-20` to
`bottom-[calc(var(--call-chrome-height)+1rem)]`, and raise the thumbnail's floor so an
avatar is legible:

```ts
const THUMBNAIL =
	"absolute z-20 aspect-video w-[clamp(7rem,24vw,11rem)] overflow-hidden rounded-lg border border-border shadow-lg";
```

Add the safe-area padding to the control-bar wrapper's className:

```
pb-[env(safe-area-inset-bottom)]
```

Where `remoteTileClass` and `selfTileClass` would otherwise place two thumbnails in the
same corner (spotlight with `mainIsScreen`), keep them apart by keeping the existing
`inset-s-4` / `inset-e-4` split — only the block axis moves.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/CallStage.tsx src/features/call/CallStage.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "fix(call): the stage on a phone

Self view to the bottom corner above the control bar, and large enough
that a camera-off avatar reads as a person rather than a black chip. It
sat under the header, overlapping it.

Safe-area padding on the control bar: the browser's chrome sits directly
under it, and a collapsing address bar moves dvh under a running call.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 14: Prove it in a real browser

**Files:**
- Modify: `dashboard/e2e/call-ui.spec.ts`

**Interfaces:**
- Consumes: `assertOnScreen` and `enableLobbyCamera`, both already in this suite.

- [ ] **Step 1: Write the failing flows**

Add two tests. The first, at portrait phone size:

```ts
test("every call control is reachable on a phone held upright", async ({
	browser,
}) => {
	// 430x932 is the device the C5 defects were found on. The existing 360px
	// flow is LANDSCAPE-agnostic and passed the whole time this was broken:
	// the failure was a popover clipped off the inline edge and a self view
	// overlapping the header, neither of which a width-only check sees.
	const context = await browser.newContext({
		viewport: { width: 430, height: 932 },
	});
	// … join as the student, exactly as the 44px flow does …

	// Nothing scrolls sideways.
	expect(
		await page.evaluate(
			() => document.documentElement.scrollWidth <= window.innerWidth,
		),
	).toBe(true);

	// Every control is fully on screen, and a real 44px target.
	for (const name of [
		/mute microphone/i, /turn camera off/i, /call settings/i, /leave/i,
	]) {
		const control = page.getByRole("button", { name });
		await assertOnScreen(page, control);
		const box = (await control.boundingBox())!;
		expect(box.width).toBeGreaterThanOrEqual(44);
		expect(box.height).toBeGreaterThanOrEqual(44);
	}

	// The settings sheet, opened, is fully on screen -- this is the defect
	// the screenshot showed: three of six items clipped off the edge.
	await page.getByRole("button", { name: /call settings/i }).click();
	await assertOnScreen(page, page.getByTestId("call-settings-panel"));
	for (const item of await page.getByRole("radio").all()) {
		await assertOnScreen(page, item);
	}
	await page.keyboard.press("Escape");

	// The self view overlaps neither the header nor the control bar.
	const self = (await page.getByTestId("call-tile-self").boundingBox())!;
	const bar = (await page.getByTestId("call-controls-bar").boundingBox())!;
	expect(self.y + self.height).toBeLessThanOrEqual(bar.y);
});
```

The second, two-peer:

```ts
test("a share that stops leaves the layout", async ({ browser }) => {
	// The one C5 defect no unit test can prove, because it is about what a
	// real second browser does with a real track that ended: useVideoFrames
	// latches, so before `media-state` the frozen last frame held the main
	// tile for the rest of the lesson.
	// … teacher shares (the suite's existing screen-share flow does this) …
	// … assert the student's `call-tile-screen` is laid out and on screen …
	await teacherPage.getByRole("button", { name: /stop sharing/i }).click();
	// The tile returns to its idle, one-transparent-pixel state.
	await expect
		.poll(async () =>
			studentPage.getByTestId("call-tile-screen").evaluate((el) => {
				const r = el.getBoundingClientRect();
				return r.width * r.height;
			}),
		)
		.toBeLessThan(4);
	// And the person is back in the main slot.
	await assertOnScreen(studentPage, studentPage.getByTestId("remote-video"));
});
```

Reuse this file's existing join helpers rather than writing new ones — read the
screen-share flow at line 703 and follow it exactly.

- [ ] **Step 2: Run them and watch them fail for the right reason**

```bash
cd dashboard && pnpm exec playwright test e2e/call-ui.spec.ts -g "phone held upright|share that stops"
```

Both must fail against a build **without** PR 2 and PR 3 — if either passes there, it is
not testing the defect. (Stash, build, run, unstash.) Then run against the real build:
both PASS.

- [ ] **Step 3: Commit**

```bash
git add e2e/call-ui.spec.ts
PIP_CONFIG_FILE=/dev/null git commit -m "test(e2e): the call on a phone held upright, and a share that ends

The existing 360px flow is width-only and passed the whole time this was
broken -- the failures were a popover clipped off the inline edge and a
self view overlapping the header, neither of which a width check sees.

The share-stop flow is the one C5 defect no unit test can reach: it is
about what a real second browser does with a track that ended.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

### Task 15: Open PR 3 and close the loop

- [ ] **Step 1: Full gate**

```bash
cd dashboard && pnpm lint && pnpm vitest run --coverage && pnpm exec playwright test e2e/call-ui.spec.ts
```

Coverage at or above the floors; raise them if they rose.

- [ ] **Step 2: Update the docs (D9)**

- `docs/architecture/scheduling.md` — the `media-state` message and what it is for.
- `STATE.md` — current phase and what remains.
- `docs/superpowers/journal/2026-W37.md` — an entry.
- Mark the spec `status: shipped`, `closed: 2026-09-12` (or the real date).

- [ ] **Step 3: The manual pass**

These cannot be proven by any harness in this project and must be checked by hand, on
the device the screenshot came from:

- The OS camera indicator actually goes out when the camera is switched off.
- The settings sheet is fully readable in portrait, in Arabic (RTL), in both themes.
- A shared screen is legible, and stopping it clears the other side.
- Audio is audible and video watchable — fake media proves plumbing only.

---

## Self-review notes

- **Spec coverage.** A → Task 2. B → Tasks 3, 4. C → Tasks 1, 5, 6, 7. D → Task 8.
  E → Tasks 11, 12. F → Task 9. G → Tasks 11 (G1), 9 (G2), 13 (G3, G5), 12 (G4),
  14 (G6). Test plan → the per-task tests plus Task 14. Deploy ordering → PR
  boundaries and Task 1's commit body.
- **One spec claim corrected here.** The spec says `usePeerConnection` must learn that a
  stream with no video track means `replaceTrack(null)`. It already does
  (`usePeerConnection.ts:563`). Task 4 says so explicitly and instructs the implementer
  not to add the branch.
- **Out of scope, per the spec, and not planned:** releasing the microphone on mute; a
  fit override on the main tile; any change to ICE, TURN, or the negotiated lines.
