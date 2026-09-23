# Phase C3e-b — Safari/iOS Browser Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the seven defects that make the video call fail silently on Safari and iOS.

**Architecture:** Dashboard-only. Four files carry almost all of it — `useLocalMedia.ts`, `usePeerConnection.ts`, `VideoTile.tsx`/`CallRoom.tsx`, and the room route. Media acquisition moves behind a user gesture, viewport units move to `dvh`, `restartIce` gets a feature guard, backgrounding reuses the recovery path that already exists, and device changes hot-swap through `sender.replaceTrack()` — which needs no renegotiation and so never touches the single-offerer rule.

**Tech Stack:** React 19, TypeScript, Tailwind v4 (4.2.2), Vitest, Playwright, WebRTC.

**Spec:** `docs/superpowers/specs/2026-09-07-phase-c3e-b-browser-hardening-design.md`

## Global Constraints

- **Dashboard only.** No backend change, no signaling-service change, and **no new signaling message type** — the protocol stays closed at `peer-joined`, `peer-left`, `offer`, `answer`, `ice` (C3b). If a task seems to need a sixth, stop and report rather than adding one.
- **The single-offerer rule is untouchable.** The teacher offers on every `peer-joined`; the student only answers. `replaceTrack` is chosen precisely because it needs no renegotiation. Nothing in this phase may add an `onnegotiationneeded` handler or make the student offer.
- **Diagnostic codes are a closed vocabulary**, already defined in `src/features/call/diagnosticsApi.ts`: `gum-denied`, `gum-not-found`, `gum-in-use`, `autoplay-blocked`, `gum-no-gesture`, `ice-restart-unsupported`, `backgrounded`, `device-lost`. **Do not add one** — the backend enum would have to change, and the e2e contract test would fail.
- **`unknown` stays absent from `FAILURE_CODES`.** Reporting an unclassifiable failure under a specific code writes a wrong answer into the one table this phase reads. A test pins this; do not "fix" it.
- **Coverage floors are ratchets** (ADR-0026), in `dashboard/vitest.config.ts`: currently 95.2 lines / 91.5 branches / 87 functions / 95.2 statements. They may only rise. Set new floors with **tenths of headroom below the measured figure** — the file's own comment explains that a floor equal to the achieved number is a tripwire.
- **Styles come from design tokens** — semantic utilities only, never a hardcoded hex or `color-mix`.
- **a11y/i18n/RTL are a repo-wide baseline.** Every user-visible string goes through `react-i18next` (add keys to the locale files, do not hardcode English). Use logical direction utilities, never physical ones.
- **Tabs, not spaces. Biome, not ESLint/Prettier.** Comments explain *why* and what breaks otherwise, never *what*.
- **Trunk-based git** (ADR-0028): work on `feat/browser-hardening` off `main`; PR into `main`. Never commit to a trunk, never `--no-verify`. Commit with `PIP_CONFIG_FILE=/dev/null` — a dead pip proxy otherwise breaks the pre-commit hook.
- **`min-h-dvh` is verified real**: it compiles to `min-height: 100dvh` under this project's Tailwind 4.2.2. Do not substitute an invented alternative.

---

## File Structure

| File | Change |
| --- | --- |
| `src/features/call/useLocalMedia.ts` | `start()` replaces the mount effect; device-change detection; persisted device ids |
| `src/features/call/deviceStorage.ts` (create) | Pure read/write of persisted device ids. Separate so it is testable without React and without a live `localStorage` in every test |
| `src/features/call/usePeerConnection.ts` | Keep senders; add `replaceTrack`; guard `restartIce` |
| `src/features/call/VideoTile.tsx` | The tap-to-enable-sound control |
| `src/features/call/Lobby.tsx` | The "Turn on camera and microphone" step; `min-h-dvh` |
| `src/features/call/CallRoom.tsx` | Teacher copy; wire `replaceTrack`; `min-h-dvh` |
| `src/routes/_call/sessions.$sessionId.room.tsx` | `visibilitychange` trigger; `min-h-dvh` |
| `src/locales/*` | New i18n keys |
| `e2e/call-hardening.spec.ts` (create) | Gesture gate + autoplay control, Chromium |

---

### Task 1: `100vh` → `100dvh`

**Files:**
- Modify: `dashboard/src/features/call/Lobby.tsx`, `dashboard/src/features/call/CallRoom.tsx`, `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`
- Test: `dashboard/src/features/call/viewport-units.test.ts` (create)

**Interfaces:**
- Produces: nothing consumed by later tasks.

On iOS Safari the dynamic address bar makes `100vh` taller than the visible viewport, so in a full-bleed layout `CallControls` can sit below the fold with no way to reach it. A child who cannot find the leave button stays in a lesson.

- [ ] **Step 1: Write the failing test**

The valuable assertion is against the **built CSS**, not the source. Asserting a source file contains a string proves only that someone typed it; this project has already shipped a spec prescribing `inset-b-*`, which is not a real Tailwind utility and compiled to nothing, silently.

Create `dashboard/src/features/call/viewport-units.test.ts`:

```ts
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// Compiles the class through the project's OWN Tailwind rather than trusting
// that it exists. `inset-b-*` was specced for this codebase once, looked
// entirely plausible, and compiled to nothing -- leaving an element with no
// position and no error anywhere. A utility is real when the compiler emits
// a rule for it, and not before.
function compile(classNames: string): string {
	const dir = mkdtempSync(join(tmpdir(), "twprobe-"));
	writeFileSync(join(dir, "probe.css"), '@import "tailwindcss";\n');
	writeFileSync(join(dir, "probe.html"), `<div class="${classNames}"></div>`);
	execFileSync(
		"npx",
		["@tailwindcss/cli", "-i", join(dir, "probe.css"), "-o", join(dir, "out.css"),
		 "--content", join(dir, "probe.html")],
		{ cwd: process.cwd(), stdio: "pipe" },
	);
	return readFileSync(join(dir, "out.css"), "utf8");
}

describe("the call surfaces size to the VISIBLE viewport", () => {
	it("min-h-dvh is a real utility that emits 100dvh", () => {
		expect(compile("min-h-dvh")).toContain("min-height: 100dvh");
	});

	it("no call surface still uses min-h-screen", async () => {
		const files = [
			"src/features/call/Lobby.tsx",
			"src/features/call/CallRoom.tsx",
			"src/routes/_call/sessions.$sessionId.room.tsx",
		];
		const { readFile } = await import("node:fs/promises");
		for (const file of files) {
			const source = await readFile(file, "utf8");
			expect(source, `${file} still pins 100vh`).not.toContain("min-h-screen");
		}
	});
});
```

- [ ] **Step 2: Run it and watch the second test fail**

```bash
cd dashboard && pnpm vitest run src/features/call/viewport-units.test.ts
```
Expected: the first test PASSES (the utility is real), the second FAILS naming `Lobby.tsx`.

- [ ] **Step 3: Replace the three occurrences**

In each of the three files, change `min-h-screen` to `min-h-dvh`. There is exactly one occurrence per file; leave every other class untouched.

- [ ] **Step 4: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/ src/routes/_call/ && pnpm lint && pnpm tsc --noEmit
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd dashboard && PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "fix(call): size call surfaces to the visible viewport, not 100vh"
```

---

### Task 2: `getUserMedia` behind a user gesture

**Files:**
- Modify: `dashboard/src/features/call/useLocalMedia.ts`, `dashboard/src/features/call/Lobby.tsx`, `dashboard/src/features/call/CallRoom.tsx`, `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`
- Test: `dashboard/src/features/call/useLocalMedia.test.ts`, `dashboard/src/features/call/Lobby.test.tsx`

**Interfaces:**
- Consumes: `DiagnosticCode` from `./diagnosticsApi`.
- Produces: `UseLocalMediaResult.start: () => Promise<void>`. **`retry` is renamed to `start`** — one function, one name. The Lobby's first acquisition and a post-failure re-acquisition are the same operation, and two names for it would drift. Update both existing `localMedia.retry()` call sites (`CallRoom.tsx`, the room route) to `start()`.

`useLocalMedia` currently acquires in a mount effect, so the camera prompt fires on navigation with no user gesture between. iOS gates media capture on user activation, and a refusal costs the whole lesson.

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/features/call/useLocalMedia.test.ts`:

```ts
it("does not touch the camera until start() is called", () => {
	const getUserMedia = vi.fn().mockResolvedValue(new MediaStream());
	renderHook(() =>
		useLocalMedia({ getUserMedia, enumerateDevices: vi.fn().mockResolvedValue([]) }),
	);
	// The whole point: mounting the room must not prompt. On iOS the prompt
	// has to arrive inside a tap or it can be refused outright.
	expect(getUserMedia).not.toHaveBeenCalled();
});

it("acquires when start() is called", async () => {
	const stream = new MediaStream();
	const getUserMedia = vi.fn().mockResolvedValue(stream);
	const { result } = renderHook(() =>
		useLocalMedia({ getUserMedia, enumerateDevices: vi.fn().mockResolvedValue([]) }),
	);
	await act(() => result.current.start());
	expect(getUserMedia).toHaveBeenCalledOnce();
	expect(result.current.stream).toBe(stream);
});

it("reports gum-no-gesture when the browser refuses for want of activation", async () => {
	const onFailure = vi.fn();
	// Safari raises NotAllowedError for both a denied permission and a
	// missing user gesture; `InvalidStateError` is the one that means
	// specifically "not allowed here, in this context".
	const noGesture = Object.assign(new Error("no activation"), {
		name: "InvalidStateError",
	});
	const { result } = renderHook(() =>
		useLocalMedia({
			getUserMedia: vi.fn().mockRejectedValue(noGesture),
			enumerateDevices: vi.fn().mockResolvedValue([]),
			onFailure,
		}),
	);
	await act(() => result.current.start());
	expect(onFailure).toHaveBeenCalledWith("gum-no-gesture");
});
```

Append to `dashboard/src/features/call/Lobby.test.tsx`:

```tsx
it("shows an enable control before any preview, and starts media on tap", async () => {
	const start = vi.fn().mockResolvedValue(undefined);
	render(<Lobby onJoin={vi.fn()} localMedia={{ ...baseMedia, stream: null, start }} />);
	const button = screen.getByRole("button", { name: /turn on camera/i });
	await userEvent.click(button);
	expect(start).toHaveBeenCalledOnce();
});

it("does not offer Join before media exists", () => {
	render(<Lobby onJoin={vi.fn()} localMedia={{ ...baseMedia, stream: null }} />);
	expect(screen.queryByRole("button", { name: /join/i })).not.toBeInTheDocument();
});
```

Reuse whatever `baseMedia`-style fixture `Lobby.test.tsx` already builds; if it has none, construct one from `UseLocalMediaResult`'s fields rather than casting `as any`.

- [ ] **Step 2: Run and watch them fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useLocalMedia.test.ts src/features/call/Lobby.test.tsx
```
Expected: FAIL — `getUserMedia` was called on mount; `start` does not exist.

- [ ] **Step 3: Change the hook**

In `useLocalMedia.ts`, add `InvalidStateError` to the failure table and its code, delete the acquire from the mount effect (keep the cleanup), and rename `retry` to `start`:

```ts
const FAILURES: Record<string, MediaFailure> = {
	NotAllowedError: "denied",
	PermissionDeniedError: "denied",
	NotFoundError: "not-found",
	DevicesNotFoundError: "not-found",
	NotReadableError: "in-use",
	TrackStartError: "in-use",
	// Distinct from `denied`: the browser is not refusing permission, it is
	// refusing the CONTEXT -- capture was requested without user activation.
	// The instruction differs too ("tap to turn on your camera", not "allow
	// camera access in your browser settings"), which is why it earns its
	// own row rather than collapsing into `denied`.
	InvalidStateError: "no-gesture",
};
```

Widen `MediaFailure` with `"no-gesture"`, add `"no-gesture": "gum-no-gesture"` to `FAILURE_CODES`, and add a `call.noGestureHelp` message key to `FAILURE_MESSAGE_KEY` in `Lobby.tsx`.

The mount effect keeps only its cleanup:

```ts
	// No acquisition here, deliberately. `start()` is the only entry point,
	// and it exists to be called from inside a tap: iOS gates capture on user
	// activation, and a prompt fired from a navigation has no activation
	// behind it. The cleanup stays -- an unmounted room must never leave the
	// camera light on.
	// biome-ignore lint/correctness/useExhaustiveDependencies: cleanup-only by design
	useEffect(() => {
		return () => {
			stopStream(streamRef.current);
			streamRef.current = null;
		};
	}, []);

	const start = useCallback(async () => {
		await acquire(DEFAULT_CONSTRAINTS);
	}, [acquire]);
```

Return `start` instead of `retry`.

- [ ] **Step 4: Change the Lobby**

Add local state for whether the person has asked yet, and render the enable control before any preview:

```tsx
	const [requested, setRequested] = useState(false);

	// The tap is the point. `start()` must be called from inside this handler
	// so the browser sees user activation on the capture request itself --
	// moving it to an effect, however small the refactor looks, is the exact
	// bug this task exists to fix.
	const handleEnable = () => {
		setRequested(true);
		void start();
	};
```

Show the video preview and the Join button only when `stream` is non-null. Show the enable button when `!requested && !stream`. On failure, the existing per-failure `Alert` and the existing try-again control (now calling `start`) handle it — do not add a second error path.

- [ ] **Step 5: Update the two other call sites**

`CallRoom.tsx` and the room route each call `localMedia.retry()`. Change both to `localMedia.start()`. Nothing else about them changes.

- [ ] **Step 6: Run the tests**

```bash
cd dashboard && pnpm vitest run src/features/call/ src/routes/_call/ && pnpm lint && pnpm tsc --noEmit
```
Expected: PASS. Existing `useLocalMedia` tests that relied on mount-acquisition will need updating to call `start()` first — update them; do not weaken their assertions.

- [ ] **Step 7: Mutation-check the gesture rule**

Move the `void start()` out of `handleEnable` into a `useEffect` in `Lobby`, confirm `does not touch the camera until start() is called` still passes but the Lobby test for tapping fails, then restore. Record the output — this is the fix's whole substance.

- [ ] **Step 8: Commit**

```bash
cd dashboard && PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "fix(call): request camera and microphone from inside a user gesture"
```

---

### Task 3: Persisted device choices

**Files:**
- Create: `dashboard/src/features/call/deviceStorage.ts`, `dashboard/src/features/call/deviceStorage.test.ts`
- Modify: `dashboard/src/features/call/useLocalMedia.ts`
- Test: `dashboard/src/features/call/useLocalMedia.test.ts`

**Interfaces:**
- Produces: `readDeviceId(kind: "camera" | "microphone"): string | null` and `writeDeviceId(kind: "camera" | "microphone", id: string): void`.

- [ ] **Step 1: Write the failing test**

Create `dashboard/src/features/call/deviceStorage.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { readDeviceId, writeDeviceId } from "./deviceStorage";

describe("deviceStorage", () => {
	beforeEach(() => localStorage.clear());

	it("round-trips a chosen device", () => {
		writeDeviceId("camera", "cam-1");
		expect(readDeviceId("camera")).toBe("cam-1");
		expect(readDeviceId("microphone")).toBeNull();
	});

	it("survives localStorage being unavailable", () => {
		// Safari in private browsing has historically thrown on setItem, and
		// a thrown quota error here would take out the Lobby entirely --
		// remembering a camera is a convenience and must never cost a lesson.
		const spy = vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
			throw new Error("QuotaExceededError");
		});
		expect(() => writeDeviceId("camera", "cam-1")).not.toThrow();
		spy.mockRestore();
	});
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm vitest run src/features/call/deviceStorage.test.ts
```
Expected: FAIL — cannot resolve `./deviceStorage`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/call/deviceStorage.ts`:

```ts
// Remembering which camera someone used is a convenience, so every path here
// fails soft. Safari in private browsing has thrown on `setItem`, and a
// storage error must never be the reason a lesson does not start.
const KEYS = {
	camera: "kaleem.call.cameraId",
	microphone: "kaleem.call.microphoneId",
} as const;

export type DeviceKind = keyof typeof KEYS;

export function readDeviceId(kind: DeviceKind): string | null {
	try {
		return localStorage.getItem(KEYS[kind]);
	} catch {
		return null;
	}
}

export function writeDeviceId(kind: DeviceKind, id: string): void {
	try {
		localStorage.setItem(KEYS[kind], id);
	} catch {
		// Deliberately swallowed -- see the module comment.
	}
}
```

- [ ] **Step 4: Wire it into the hook**

In `useLocalMedia.ts`, `selectCamera` and `selectMicrophone` each call `writeDeviceId` alongside their existing `setSelected*Id`. After a successful enumeration inside `acquire`, adopt a stored id **only if the device is still present**:

```ts
				// A camera used last week may simply not be here today. Falling
				// back to the default silently is deliberate: a stored id that
				// no longer resolves must never block joining a lesson, and
				// must not produce an error someone has to dismiss to continue.
				const storedCamera = readDeviceId("camera");
				if (storedCamera && cameras.some((d) => d.deviceId === storedCamera)) {
					setSelectedCameraId(storedCamera);
				}
```

and the same for the microphone.

- [ ] **Step 5: Add the hook-level test**

```ts
it("ignores a stored device that is no longer present", async () => {
	writeDeviceId("camera", "cam-that-is-gone");
	const { result } = renderHook(() =>
		useLocalMedia({
			getUserMedia: vi.fn().mockResolvedValue(new MediaStream()),
			enumerateDevices: vi.fn().mockResolvedValue([
				{ deviceId: "cam-2", kind: "videoinput", label: "Other" } as MediaDeviceInfo,
			]),
		}),
	);
	await act(() => result.current.start());
	// Not the stored id, and no failure surfaced -- the lesson proceeds.
	expect(result.current.selectedCameraId).not.toBe("cam-that-is-gone");
	expect(result.current.failure).toBeNull();
});
```

- [ ] **Step 6: Run, then commit**

```bash
cd dashboard && pnpm vitest run src/features/call/ && pnpm lint && pnpm tsc --noEmit
PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): remember the chosen camera and microphone"
```

---

### Task 4: Tap to turn on sound

**Files:**
- Modify: `dashboard/src/features/call/VideoTile.tsx`
- Test: `dashboard/src/features/call/VideoTile.test.tsx`

**Interfaces:**
- Produces: no new props. `VideoTile` renders its own control when `play()` rejects.

On Safari a refused audible autoplay is the most likely failure and a perfectly silent one — a still frame and no sound, which reads as "the teacher isn't talking." C3e-a made it *reported*; this makes it *recoverable*.

- [ ] **Step 1: Write the failing test**

```tsx
it("offers a tap-to-play control when the browser refuses autoplay, and clears it on success", async () => {
	const play = vi
		.spyOn(HTMLMediaElement.prototype, "play")
		.mockRejectedValueOnce(Object.assign(new Error("blocked"), { name: "NotAllowedError" }))
		.mockResolvedValue(undefined);
	render(<VideoTile stream={fakeStream()} data-testid="remote" />);

	const button = await screen.findByRole("button", { name: /turn on sound/i });
	await userEvent.click(button);

	// The retry must happen inside the click -- that user activation is
	// exactly what the browser was waiting for.
	expect(play).toHaveBeenCalledTimes(2);
	expect(screen.queryByRole("button", { name: /turn on sound/i })).not.toBeInTheDocument();
	play.mockRestore();
});
```

Reuse the `fakeStream()` helper already in this file (jsdom has no `MediaStream` global).

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm vitest run src/features/call/VideoTile.test.tsx
```
Expected: FAIL — no such button.

- [ ] **Step 3: Implement**

Add `const [blocked, setBlocked] = useState(false);`. In the existing catch, `setBlocked(true)` alongside the existing report. Add a handler that replays and clears:

```tsx
	// Called from a real click, which is the entire mechanism: the browser
	// refused because there was no user activation, and this supplies one.
	const handleTapToPlay = async () => {
		try {
			await videoRef.current?.play();
			setBlocked(false);
		} catch {
			// Still refused. Leave the control up rather than clearing it --
			// hiding it would strand the viewer with no way to try again.
		}
	};
```

Render the control **over** the tile when `blocked`, wrapping the `<video>` in a `relative` container. Use design tokens for its colours and an i18n key (`call.tapForSound`) for its label. Add `setBlocked(false)` when the stream changes, so a new stream starts clean.

- [ ] **Step 4: Run, mutation-check, commit**

Mutation check: make `handleTapToPlay` clear `blocked` before awaiting `play()`, confirm the "still refused" case would hide the control, then restore.

```bash
cd dashboard && pnpm vitest run src/features/call/ && pnpm lint && pnpm tsc --noEmit
PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): let a viewer turn on sound the browser refused to autoplay"
```

---

### Task 5: Guard `restartIce`

**Files:**
- Modify: `dashboard/src/features/call/usePeerConnection.ts`
- Test: `dashboard/src/features/call/usePeerConnection.test.ts`

**Interfaces:**
- Consumes: `report` is not available here; the hook gains an optional `onUnsupported?: () => void` so the route can emit `ice-restart-unsupported` without this hook knowing a session id — the same shape `useLocalMedia.onFailure` already uses.

An unguarded `pc.restartIce()` on a browser lacking it **throws inside `onconnectionstatechange`**, taking out the recovery path itself. The failure mode is "reconnection silently never happens".

- [ ] **Step 1: Write the failing test**

```ts
it("degrades to failed rather than throwing when restartIce is unavailable", async () => {
	const onUnsupported = vi.fn();
	const pc = makeFakePeerConnection();
	// A browser without ICE restart. Deleting the method is the honest
	// simulation -- a `vi.fn()` that throws would test our catch, not our
	// feature check.
	pc.restartIce = undefined as unknown as () => void;
	const { result } = renderHook(() =>
		usePeerConnection({
			iceServers: [], isTeacher: true, localStream: null,
			send: vi.fn(), createPeerConnection: () => pc, onUnsupported,
		}),
	);
	act(() => {
		pc.connectionState = "failed";
		pc.onconnectionstatechange?.(new Event("connectionstatechange"));
	});
	expect(result.current.state).toBe("failed");
	expect(onUnsupported).toHaveBeenCalledOnce();
});
```

Use whatever fake-peer-connection helper the file already has rather than writing a second one.

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — a `TypeError` escapes, or `state` is `"reconnecting"`.

- [ ] **Step 3: Implement**

In `onconnectionstatechange`, before incrementing restarts:

```ts
				// A feature check, not a try/catch. Safari has had
				// `restartIce` since 15.4, so this is belt-and-braces -- but
				// an unguarded call on a browser without it throws INSIDE
				// this handler, which takes out the recovery path itself and
				// leaves the call stuck on "reconnecting" forever. Failing
				// over to `failed` at least surfaces the rejoin control.
				if (isTeacherRef.current && typeof pc.restartIce !== "function") {
					onUnsupportedRef.current?.();
					setState("failed");
					return;
				}
```

Make `restartIce` optional in the `PeerConnectionLike` `Pick` so the type permits its absence.

- [ ] **Step 4: Run, then commit**

```bash
cd dashboard && pnpm vitest run src/features/call/ && pnpm lint && pnpm tsc --noEmit
PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "fix(call): survive a browser without restartIce instead of throwing mid-recovery"
```

---

### Task 6: Backgrounding recovery, and the teacher's copy

**Files:**
- Modify: `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`, `dashboard/src/features/call/CallRoom.tsx`, locale files
- Test: `dashboard/src/routes/_call/sessions.$sessionId.room.test.tsx`, `dashboard/src/features/call/CallRoom.test.tsx`

**Interfaces:**
- Consumes: `handleRetryConnection` (already in the route), `useCallDiagnostics.report`.
- Produces: nothing new.

**The recovery machinery already exists.** `handleRetryConnection` re-acquires media and remounts `CallRoom` via a key bump — a fresh socket, a fresh peer connection. This task adds a *trigger*, not a second mechanism. Two recovery paths that must agree are two that can drift.

- [ ] **Step 1: Write the failing tests**

```tsx
it("recovers when the page returns to view with the call not connected", async () => {
	// An iPad returning from a lock screen or another app.
	renderRoom({ connectionState: "reconnecting" });
	act(() => {
		Object.defineProperty(document, "visibilityState", { value: "visible", configurable: true });
		document.dispatchEvent(new Event("visibilitychange"));
	});
	await waitFor(() => expect(startSpy).toHaveBeenCalled());
	expect(reportSpy).toHaveBeenCalledWith("backgrounded");
});

it("does NOT disturb a healthy call when the page returns to view", async () => {
	// Tabbing away and back during a working lesson must be a no-op --
	// re-acquiring media and remounting a live call would break the very
	// thing this task protects.
	renderRoom({ connectionState: "connected" });
	act(() => {
		Object.defineProperty(document, "visibilityState", { value: "visible", configurable: true });
		document.dispatchEvent(new Event("visibilitychange"));
	});
	expect(startSpy).not.toHaveBeenCalled();
});
```

Build `renderRoom` from the harness the route's existing test file already uses.

- [ ] **Step 2: Run and watch them fail**

Expected: the first FAILS (nothing listens), the second passes vacuously — which is why the first is the load-bearing one.

- [ ] **Step 3: Implement the trigger**

In `RoomPage`:

```tsx
	// iOS suspends a backgrounded page: media stops and the socket may or may
	// not survive. The recovery this needs already exists as
	// `handleRetryConnection`, so this is a trigger and not a second
	// mechanism -- two recovery paths that must agree are two that can drift.
	//
	// Guarded on the connection actually being down: tabbing away and back
	// during a healthy lesson must be a no-op, or this "fix" would tear down
	// working calls. The retry it calls is already bounded, so a page that
	// returns to view while permanently unable to connect cannot loop.
	useEffect(() => {
		const onVisibility = () => {
			if (document.visibilityState !== "visible") {
				return;
			}
			if (connectionStateRef.current === "connected") {
				return;
			}
			diagnostics.report("backgrounded");
			handleRetryConnection();
		};
		document.addEventListener("visibilitychange", onVisibility);
		return () => document.removeEventListener("visibilitychange", onVisibility);
	}, [diagnostics.report, handleRetryConnection]);
```

`CallRoom` reports its connection state up so the route can read it — add an `onConnectionStateChange?: (state: PeerConnectionState) => void` prop, called from an effect on `peer.state`, and hold the latest value in `connectionStateRef` in the route. Keep the prop optional.

- [ ] **Step 4: Fix the teacher's copy**

In `CallRoom.tsx`, `CONNECTION_STATE_COPY.reconnecting` and the peer-left path currently read as bare state labels. Change the message keys so a teacher is told what to do — "their connection dropped, waiting for them to come back" rather than "Reconnecting". Add the keys to every locale file, including the RTL one; do not leave a key untranslated in one locale.

- [ ] **Step 5: Run, mutation-check, commit**

Mutation check: remove the `connectionState === "connected"` guard, confirm the second test fails (a healthy call now gets torn down), restore.

```bash
cd dashboard && pnpm vitest run src/features/call/ src/routes/_call/ && pnpm lint && pnpm tsc --noEmit
PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): recover a suspended page, and tell the teacher what happened"
```

---

### Task 7: Hot-swap a changed device

**Files:**
- Modify: `dashboard/src/features/call/usePeerConnection.ts`, `dashboard/src/features/call/useLocalMedia.ts`, `dashboard/src/features/call/CallRoom.tsx`
- Test: `dashboard/src/features/call/usePeerConnection.test.ts`, `dashboard/src/features/call/useLocalMedia.test.ts`

**Interfaces:**
- Produces: `UsePeerConnectionResult.replaceTrack: (track: MediaStreamTrack) => Promise<void>`.

**This is the riskiest task in the phase — it is the only one that reaches into a live connection.** `replaceTrack` needs no renegotiation (same `m=` line, same codec), which is exactly why it is safe against the single-offerer rule. Nothing here may add an `onnegotiationneeded` handler.

- [ ] **Step 1: Write the failing test for the sender swap**

```ts
it("replaces the live sender's track rather than renegotiating", async () => {
	const sender = { track: oldTrack, replaceTrack: vi.fn().mockResolvedValue(undefined) };
	const pc = makeFakePeerConnection();
	pc.addTrack = vi.fn().mockReturnValue(sender);
	const { result } = renderHook(() => usePeerConnection({ /* …, localStream: streamWith(oldTrack) */ }));

	await act(() => result.current.replaceTrack(newAudioTrack));

	// The assertion that matters: the SENDER received the new track. That
	// `ondevicechange` fired, or that some handler ran, proves nothing --
	// the failure this fixes is a swap that silently does not happen.
	expect(sender.replaceTrack).toHaveBeenCalledWith(newAudioTrack);
	expect(pc.createOffer).not.toHaveBeenCalled(); // no renegotiation
});
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — `replaceTrack` is not a function.

- [ ] **Step 3: Close the double-`addTrack` hole this task opens**

**Read this before writing any code — it is a live conflict with existing behaviour, not a style note.**

The track-attach effect runs on every `localStream` **identity** change and calls `pc.addTrack` unconditionally. It sets `tracksAddedRef.current = true` but never checks it. That is safe today only by accident: the sole thing that changes the stream identity is `localMedia.start()`, and the route always pairs it with a full `CallRoom` remount, so the peer connection is brand new each time.

**This task breaks that pairing.** A device swap produces a new stream identity on a *live* connection, so the effect would re-run and add a SECOND sender per kind instead of replacing — duplicate `m=` sections the single offerer never renegotiates, and a call that degrades with nothing thrown.

So the effect must branch:

```ts
	useEffect(() => {
		const pc = pcRef.current;
		if (!pc || !localStream) {
			return;
		}
		if (tracksAddedRef.current) {
			// A stream identity change on a connection that already has
			// senders means a device swap, not a first attach. Adding here
			// would create a second sender per kind and quietly wreck the
			// negotiated media -- swap instead, which needs no renegotiation.
			for (const track of localStream.getTracks()) {
				void sendersRef.current.get(track.kind)?.replaceTrack(track);
			}
			return;
		}
		for (const track of localStream.getTracks()) {
			sendersRef.current.set(track.kind, pc.addTrack(track, localStream));
		}
		tracksAddedRef.current = true;
		/* ...existing pending-action drain, unchanged... */
	}, [localStream]);
```

Add a test pinning it:

```ts
it("swaps rather than adds when the stream changes on a live connection", async () => {
	const pc = makeFakePeerConnection();
	const sender = { track: null, replaceTrack: vi.fn().mockResolvedValue(undefined) };
	pc.addTrack = vi.fn().mockReturnValue(sender);
	const { rerender } = renderHook(
		({ stream }) => usePeerConnection({ /* ..., */ localStream: stream }),
		{ initialProps: { stream: streamWith(firstAudioTrack) } },
	);
	rerender({ stream: streamWith(secondAudioTrack) });
	// One addTrack for the whole lifetime, not two.
	expect(pc.addTrack).toHaveBeenCalledTimes(1);
	expect(sender.replaceTrack).toHaveBeenCalledWith(secondAudioTrack);
});
```

**Mutation-check it:** delete the `tracksAddedRef.current` branch, confirm the test fails with `addTrack` called twice, restore.

- [ ] **Step 4: Keep the senders and expose the swap**

`addTrack` already returns an `RTCRtpSender`; the current code discards it. Capture them by kind in the track-attach effect:

```ts
		for (const track of localStream.getTracks()) {
			// The sender is kept, not discarded: swapping a device mid-call
			// goes through `sender.replaceTrack`, which needs no
			// renegotiation and so leaves the single-offerer rule alone.
			sendersRef.current.set(track.kind, pc.addTrack(track, localStream));
		}
```

Add `"getSenders"` to the `PeerConnectionLike` `Pick` if the fake needs it, and:

```ts
	const replaceTrack = useCallback(async (track: MediaStreamTrack) => {
		const sender = sendersRef.current.get(track.kind);
		if (!sender) {
			return;
		}
		await sender.replaceTrack(track);
	}, []);
```

- [ ] **Step 5: Detect the change in `useLocalMedia`**

Subscribe to `navigator.mediaDevices.ondevicechange` (as an injectable dep, matching the file's existing `getUserMedia`/`enumerateDevices` pattern so it stays testable). Apply the spec's rule exactly:

```ts
			// Which device wins, stated once so it cannot drift:
			//   * an explicit choice outranks a newly-arrived device, for as
			//     long as that choice still exists;
			//   * absent a choice, follow the system default -- a newly
			//     connected headset taking over is what the OS does and what
			//     someone putting headphones on expects;
			//   * a device actually in use disappearing is ALWAYS replaced,
			//     chosen or not, because the alternative is a dead microphone
			//     that reports success.
```

When a swap is called for, re-acquire and emit `device-lost` if the previous device vanished.

- [ ] **Step 6: Wire it in `CallRoom`**

On a `localMedia.stream` identity change while the call is live, call `peer.replaceTrack` for each track of the new stream. Do **not** rebuild the peer connection.

- [ ] **Step 7: Run, mutation-check, commit**

Mutation check: make `replaceTrack` a no-op that resolves, confirm the sender test fails, restore.

```bash
cd dashboard && pnpm vitest run src/features/call/ src/routes/_call/ && pnpm lint && pnpm tsc --noEmit
PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "feat(call): hot-swap a changed camera or microphone without renegotiating"
```

---

### Task 8: e2e for what Chromium can reach

**Files:**
- Create: `dashboard/e2e/call-hardening.spec.ts`

Two flows only, because two are all Chromium can honestly prove:

1. **The gesture gate.** The Lobby opens with no preview and an enable control; after tapping it, the preview appears and Join becomes available.
2. **The autoplay control.** With autoplay blocked, the tap-to-play control appears on the remote tile and dismisses after a tap.

- [ ] **Step 1: Write the spec**

Follow `e2e/call.spec.ts` for login (`login(page, who)` from `./fixtures`) and session discovery — do not invent a second mechanism. Give the file a header comment in the suite's established voice naming what it does **not** cover: backgrounding, device changes, and everything Safari-specific.

For flow 2, block autoplay with a context-level media permission override rather than by stubbing `play()`, so the test exercises the real refusal path.

- [ ] **Step 2: Run it for real**

```bash
cd dashboard && E2E_APP_URL=http://app.kaleem.localhost:4173 pnpm exec playwright test call-hardening
```

Reproduce CI's topology as described in `docs/runbook/video-call.md`; `just dev` cannot bind port 80 on this machine. **If the environment cannot be made to work after a genuine attempt, report BLOCKED with what failed — do not report DONE on a spec you have not seen pass.**

- [ ] **Step 3: Commit**

```bash
cd dashboard && PIP_CONFIG_FILE=/dev/null git add -A && \
PIP_CONFIG_FILE=/dev/null git commit -m "test(e2e): the gesture gate and the tap-to-play control"
```

---

### Task 9: Coverage, documentation, and the honest limits

**Files:**
- Modify: `dashboard/vitest.config.ts`; then in the meta repo `CLAUDE.md`, `STATE.md`, `ISSUES.md`, `docs/runbook/video-call.md`, `docs/superpowers/journal/2026-W36.md`

- [ ] **Step 1: Ratchet the floors**

```bash
cd dashboard && pnpm test:coverage 2>&1 | tail -20
```
Raise the four thresholds toward the measured figures, keeping tenths of headroom, and update the explanatory comment with the new measured numbers. Floors may only rise; if any measured value is below its floor, stop and report.

- [ ] **Step 2: Update the D3 table**

Add a `scheduling` — browser hardening (C3e-b) row stating the two Chromium flows and, in the same words the C3e-a row uses, that **nothing here is verified on Safari or iOS and cannot be in this project**.

- [ ] **Step 3: Delete the resolved `ISSUES.md` entries**

Four entries are resolved by this phase and must be **deleted**, not struck through: "No Safari/iOS support yet", "Device changes mid-call are not handled gracefully", "Device choices are not remembered between lessons", and the room route's `100vh` note if one exists. Leave the socket-never-opens entry — this phase does not touch it.

- [ ] **Step 4: Record the D9 deviation and the verification loop**

In the journal: what shipped, and that **none of the seven fixes is verified on its target**. The loop is watching `gum-no-gesture`, `autoplay-blocked`, `backgrounded`, `device-lost` and `ice-restart-unsupported` appear or fall silent in `CallDiagnostic` once real users arrive — slower and weaker than a test, and the reason C3e-a was built first.

- [ ] **Step 5: Commit**

---

### Task 10: Ship

- [ ] **Step 1** — Open the `dashboard` PR into `main`. Green CI, then merge (merge commit, not squash).
- [ ] **Step 2** — Bump the submodule pointer in the meta docs PR.
- [ ] **Step 3** — Merge the meta PR. **This is a staging deploy.**
- [ ] **Step 4** — Live click-through on staging with the C3d fixture accounts (`c3d.student@example.com` / `c3d.teacher@example.com`, `KaleemC3d!2026`): confirm the Lobby's enable step appears and works, that the controls are reachable, and that a call still connects. **On Chromium — the target browsers remain unverified, and the click-through must be reported as such.**
- [ ] **Step 5** — Confirm no new diagnostic rows appeared from the click-through that shouldn't have (a `backgrounded` or `autoplay-blocked` row from an ordinary successful call would mean a false-positive emitter shipped).
- [ ] **Step 6** — Update `STATE.md` with the result.

---

## Self-Review

**Spec coverage.** Fix 1 → Task 1. Fix 2 → Task 2. Fix 3 → Task 4. Fix 4 → Task 5. Fix 5 (both halves) → Task 6. Fix 6 → Task 7. Fix 7 → Task 3. Testing section → Tasks 1, 7, 8. Honest-limits section → Task 9. No gaps.

**Placeholder scan.** Task 8 deliberately delegates login and session discovery to the existing `call.spec.ts` rather than transcribing it — inventing a second mechanism is the failure mode there. Task 7's step 4 gives the decision rule verbatim from the spec but leaves the enumeration comparison to the implementer, because it depends on `getSettings()` shapes best read from the live types.

**Type consistency.** `start()` replaces `retry()` in Task 2 and is used under that name in Tasks 3 and 6. `replaceTrack(track: MediaStreamTrack): Promise<void>` is defined in Task 7 and used only there. `onUnsupported?: () => void` (Task 5) matches the optional-callback shape `onFailure` already uses. `MediaFailure` gains `"no-gesture"` in Task 2 and `FAILURE_CODES` gains its mapping in the same task, so the `Partial` never has a dangling key.

**One risk restated for the executor.** Task 7 is the only task that touches a live connection. If its review is going to be strict anywhere, make it there.
