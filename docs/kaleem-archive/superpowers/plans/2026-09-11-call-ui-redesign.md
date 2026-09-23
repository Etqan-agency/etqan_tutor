# Call UI Redesign (C4b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the capability C4a built in front of the user — device pickers where the controls are, mute and camera-off before joining, a real screen-share control, per-viewer layout, and a participant who has no camera rendered as a person rather than a black rectangle.

**Architecture:** Additive. The call surface was redesigned in ADR-0036 and its layout primitives (`CallStage`, `CallStatus`, `CallControls`, `SelfView`, `VideoTile`) are sound — this plan extends them rather than replacing them. Hooks hold behaviour, components render (ADR-0036). No changes to negotiation: C4a settled that and ADR-0039 is accepted.

**Tech Stack:** React 19, TanStack Router, Tailwind v4 + semantic tokens from `@kaleem/tokens`, shadcn-style primitives in `src/ui`, lucide icons, i18next (en + ar, full RTL), Vitest + @testing-library/react, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-11-call-experience-redesign-design.md`

**Predecessor:** `docs/superpowers/plans/2026-09-11-call-negotiation-foundation.md` (C4a — merged).

## Global Constraints

- **Tokens only.** Every colour, radius and shadow comes from the semantic token layer. No hex, no `color-mix`, no raw palette values in any component. `@kaleem/tokens` is a pinned git tag baked into `node_modules` — do not edit it; app-layout tokens belong in the dashboard's own `@theme`.
- **WCAG 2.2 AA.** Text ≥ 4.5:1 and control glyphs ≥ 3:1, light and dark **independently**. Visible focus ring on every control. No icon-only control without an accessible name. State never carried by colour alone — a muted microphone shows a slashed glyph, not only a red one.
- **Touch targets ≥ 44×44px**, ≥ 8px apart. The control bar is the most-tapped surface in the product and is used one-handed on a phone.
- **Full RTL.** Logical properties only (`inset-s-*`/`inset-e-*`, `ms-*`/`me-*`) — never `left`/`right`. `inset-s-*`/`inset-e-*` are valid Tailwind v4 aliases in this repo; do not "fix" them.
- **Motion 150–300ms, `transform`/`opacity` only**, and every transition honours `prefers-reduced-motion`. **A layout change must never reassign a `<video>`'s `srcObject`** — that re-runs the media element load algorithm and aborts a pending `play()`, which this codebase has already shipped twice as a false `autoplay-blocked` diagnostic (`VideoTile.tsx:34-43`, and again in C4a Task 2).
- **No renegotiation, ever.** Mute stays `track.enabled = false`.
- **`aria-pressed` reflects "is this action in effect"** (muted / camera off / sharing), not "did I just click this". Follow `CallControls.tsx`'s existing convention exactly.
- Never `--no-verify` (D5). Pre-commit on this machine may need `PIP_CONFIG_FILE=/dev/null`.
- **Finishing a task means all of these pass:** `pnpm vitest run src/features/call/`, `pnpm tsc --noEmit`, `pnpm lint`. Lint went unnoticed for three tasks in C4a — do not repeat it.
- **e2e locally needs `CI=1` or `--workers=1`** or the call specs race for a two-seat signaling room and produce a convincing false red.
- Branch `feat/c4b-call-ui` off `main` in `dashboard`. This plan touches no backend.

## What C4a leaves you — read before Task 1

- `useCallRoom` returns `remoteCamera` (one stable-identity stream carrying the remote peer's audio **and** camera), `remoteScreen`, `remoteHasVideo`, `micOn`, `cameraOn`, `toggleMic`, `toggleCamera`, `screenShare` (`{ sharing, supported, start, stop }`), `leave`, `terminal`, `mediaFailure`, `retryMedia`.
- `useLocalMedia` returns `stream`, `failure`, `devices` (`{ cameras, microphones }`), `selectedCameraId`, `selectedMicrophoneId`, `selectCamera`, `selectMicrophone`, `start(kinds?)`, `stop`. **`start` takes either no argument (both kinds) or an object with BOTH keys** — a partial object does not compile, by design.
- **`remoteHasVideo` is effectively constant `true` after connect** and is NOT a signal that the peer has a camera. Since ADR-0039 the camera line is negotiated whether or not they have one. Measured: `track.muted` reads `false` on an empty line, so there is no receive-side track signal to key on. Task 1 solves this a different way.

---

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `ParticipantTile.tsx` | video + initials fallback; owns the "are frames arriving" question | 1 |
| `useVideoFrames.ts` | the honest has-frames signal, from the element | 1 |
| `DevicePickerButton.tsx` | a toggle plus a chevron opening that kind's device list | 2 |
| `CallControls.tsx` | gains the pickers and the share control | 2, 3 |
| `Lobby.tsx` | preview-first, join always available, pre-join toggles | 4 |
| `useCallLayout.ts` | layout choice, persistence, the once-only auto-switch | 5 |
| `LayoutSwitcher.tsx` | the four layouts as a control | 5 |
| `CallStage.tsx` | renders a chosen layout | 5 |

---

### Task 1: `ParticipantTile` — a person, not a black rectangle

**Files:**
- Create: `dashboard/src/features/call/useVideoFrames.ts`, `dashboard/src/features/call/useVideoFrames.test.ts`
- Create: `dashboard/src/features/call/ParticipantTile.tsx`, `dashboard/src/features/call/ParticipantTile.test.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx` (the `remote` slot), `dashboard/src/features/call/CallRoom.test.tsx`

**Interfaces:**
- Consumes: `remoteCamera` from `useCallRoom`.
- Produces: `useVideoFrames(ref): boolean` and `<ParticipantTile stream name .../>`. Task 5 renders `ParticipantTile` in every layout.

**Why this is first, and why it is not the obvious implementation.** A peer who joined with no camera currently gets a black rectangle, because `remoteHasVideo` is true for every connected call. There is no receive-side track property that distinguishes an empty line — `track.muted` reads `false` on one (measured during C4a, recorded in ADR-0039's amendment). The only honest signal is the element: a `<video>` receiving no frames keeps `videoWidth === 0`. That is exactly what C4a's `call-no-permission.spec.ts` already asserts about the teacher's view of a camera-less student, so this task makes the UI agree with a fact the suite already proves.

- [ ] **Step 1: Write the failing test**

`useVideoFrames.test.ts`:

```typescript
import { act, renderHook } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { useVideoFrames } from "./useVideoFrames";

function fakeVideo() {
	const listeners = new Map<string, Set<() => void>>();
	return {
		videoWidth: 0,
		addEventListener(event: string, handler: () => void) {
			if (!listeners.has(event)) listeners.set(event, new Set());
			listeners.get(event)?.add(handler);
		},
		removeEventListener(event: string, handler: () => void) {
			listeners.get(event)?.delete(handler);
		},
		fire(event: string) {
			listeners.get(event)?.forEach((handler) => handler());
		},
		listenerCount: () => [...listeners.values()].reduce((n, s) => n + s.size, 0),
	};
}

describe("useVideoFrames", () => {
	it("is false while the element has no frames, true once it has", () => {
		const video = fakeVideo();
		const ref = { current: video as unknown as HTMLVideoElement };
		const { result } = renderHook(() => useVideoFrames(ref));

		expect(result.current).toBe(false);

		video.videoWidth = 640;
		act(() => {
			video.fire("resize");
		});
		expect(result.current).toBe(true);
	});

	it("goes false again when the peer's camera stops producing", () => {
		const video = fakeVideo();
		video.videoWidth = 640;
		const ref = { current: video as unknown as HTMLVideoElement };
		const { result } = renderHook(() => useVideoFrames(ref));
		act(() => {
			video.fire("loadedmetadata");
		});
		expect(result.current).toBe(true);

		video.videoWidth = 0;
		act(() => {
			video.fire("resize");
		});
		// A peer turning their camera off mid-lesson must return to their
		// initials, not freeze on their last frame.
		expect(result.current).toBe(false);
	});

	it("removes every listener on unmount", () => {
		const video = fakeVideo();
		const ref = { current: video as unknown as HTMLVideoElement };
		const { unmount } = renderHook(() => useVideoFrames(ref));
		expect(video.listenerCount()).toBeGreaterThan(0);
		unmount();
		expect(video.listenerCount()).toBe(0);
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/features/call/useVideoFrames.test.ts`
Expected: FAIL — the module does not exist.

- [ ] **Step 3: Write minimal implementation**

```typescript
import { type RefObject, useEffect, useState } from "react";

/**
 * Whether a `<video>` is actually receiving frames.
 *
 * The element is the ONLY honest source for this. Since ADR-0039 the camera
 * line is negotiated whether or not the peer has a camera, so `remoteHasVideo`
 * is true for every connected call, and the receive-side track offers nothing
 * better: `track.muted` reads `false` on a line carrying nothing (measured
 * during C4a, see ADR-0039's amendment). A `<video>` fed an empty line keeps
 * `videoWidth === 0`, which is the same fact `call-no-permission.spec.ts`
 * already asserts about a camera-less peer.
 *
 * `resize` is the load-bearing event: it fires when the intrinsic size
 * changes, which is what happens both when frames start and when they stop.
 * `loadedmetadata` covers the case where the element already had a size
 * before this hook mounted.
 */
export function useVideoFrames(ref: RefObject<HTMLVideoElement | null>) {
	const [hasFrames, setHasFrames] = useState(false);

	useEffect(() => {
		const video = ref.current;
		if (!video) {
			return;
		}
		const update = () => setHasFrames(video.videoWidth > 0);
		update();
		video.addEventListener("resize", update);
		video.addEventListener("loadedmetadata", update);
		video.addEventListener("emptied", update);
		return () => {
			video.removeEventListener("resize", update);
			video.removeEventListener("loadedmetadata", update);
			video.removeEventListener("emptied", update);
		};
	}, [ref]);

	return hasFrames;
}
```

Then `ParticipantTile.tsx`: render `VideoTile`'s `<video>` as today, and when `useVideoFrames` is false, overlay a centred avatar built from the participant's initials. The overlay must sit ON TOP of the video element, not replace it — unmounting the video would reassign `srcObject` on remount, which is the aborted-`play()` bug. Use tokens for the avatar's background and text; give the overlay `aria-hidden="true"` and put the participant's name in the tile's accessible name instead, so a screen reader says "Fatima, camera off" once rather than reading a decorative circle.

Wire it into `CallRoom.tsx`'s `remote` slot in place of the bare `VideoTile`, and **delete the `showWaiting` black-rectangle comment block** now that the thing it warns about is fixed. `WaitingForPeer` still renders while nobody has connected — that is a different state and stays.

- [ ] **Step 4: Run tests**

Run: `pnpm vitest run src/features/call/ && pnpm tsc --noEmit && pnpm lint`
Expected: PASS. `CallRoom.test.tsx` needs a case: a connected peer whose element reports `videoWidth === 0` shows initials, not a black tile.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/
git commit -m "feat(call): show a participant's initials when their camera sends nothing

remoteHasVideo cannot answer this -- since ADR-0039 the camera line is
negotiated whether or not a camera exists, and track.muted reads false on
an empty line. The element's videoWidth is the honest signal."
```

---

### Task 2: `DevicePickerButton` — pickers where the controls are

**Files:**
- Create: `dashboard/src/features/call/DevicePickerButton.tsx`, `dashboard/src/features/call/DevicePickerButton.test.tsx`
- Modify: `dashboard/src/features/call/CallControls.tsx` and its test, `dashboard/src/features/call/CallRoom.tsx`

**Interfaces:**
- Consumes: `devices`, `selectedCameraId`, `selectedMicrophoneId`, `selectCamera`, `selectMicrophone` from `useLocalMedia` (threaded through `CallRoom`), and the existing `DeviceSelect`.
- Produces: `<DevicePickerButton toggle={...} devices={...} value={...} onChange={...} />` — the existing toggle button plus a chevron that opens that kind's list. Task 4 reuses it in the Lobby.

The mid-call plumbing already works (`useLocalMedia` re-acquires, `usePeerConnection` swaps with `replaceTrack`); only the UI is missing. `DeviceSelect.tsx`'s own docstring has been waiting for this since C3: *"the in-room device picker in Stage 4 needs it a third time."*

- [ ] **Step 1: Write the failing test**

```typescript
it("opens the camera list from the chevron and switches on choice", async () => {
	const user = userEvent.setup();
	const selectCamera = vi.fn();
	render(
		<DevicePickerButton
			id="camera"
			label="Camera"
			devices={[
				{ deviceId: "a", label: "FaceTime HD" } as MediaDeviceInfo,
				{ deviceId: "b", label: "Logitech" } as MediaDeviceInfo,
			]}
			value="a"
			onChange={selectCamera}
			fallbackLabel="Camera"
			toggle={<button type="button">toggle</button>}
		/>,
	);

	// Closed by default: a list that is always open covers the call.
	expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
	await user.click(screen.getByRole("button", { name: /choose a camera/i }));
	await user.selectOptions(screen.getByRole("combobox"), "b");
	expect(selectCamera).toHaveBeenCalledWith("b");
});

it("closes on Escape and returns focus to the chevron", async () => {
	const user = userEvent.setup();
	renderPicker();
	const chevron = screen.getByRole("button", { name: /choose a camera/i });
	await user.click(chevron);
	await user.keyboard("{Escape}");
	expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
	// Focus must come back, or a keyboard user is stranded mid-call.
	expect(chevron).toHaveFocus();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/features/call/DevicePickerButton.test.tsx`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Write minimal implementation**

A `<div>` grouping the passed-in `toggle` with a chevron `<button>` carrying `aria-expanded`, `aria-haspopup="listbox"` and an explicit `aria-label` (`t("call.chooseCamera")` / `chooseMicrophone`). The panel renders `DeviceSelect` and closes on Escape, on outside click, and on choice — restoring focus to the chevron each time. Position with logical properties so it mirrors in RTL. Keep the target ≥ 44×44px including the chevron.

Wire both pickers into `CallControls`, wrapping the existing mic and camera buttons as the `toggle` slot so the toggles keep working exactly as they do now.

- [ ] **Step 4: Run tests**

Run: `pnpm vitest run src/features/call/ && pnpm tsc --noEmit && pnpm lint`
Expected: PASS, including the existing `CallControls.test.tsx` — the toggles' behaviour and `aria-pressed` must be unchanged.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/
git commit -m "feat(call): device pickers on the controls they configure"
```

---

### Task 3: The screen-share control, properly

**Files:**
- Modify: `dashboard/src/features/call/CallControls.tsx` and its test, `dashboard/src/features/call/CallRoom.tsx` and its test

**Interfaces:**
- Consumes: `screenShare` from `useCallRoom`.
- Produces: nothing new; the bare `<button data-testid="share-screen">` in `CallRoom.tsx` moves into `CallControls` as a real control.

- [ ] **Step 1: Write the failing test**

```typescript
it("reports sharing state with aria-pressed, not colour alone", async () => {
	const user = userEvent.setup();
	const start = vi.fn();
	const { rerender } = render(
		<CallControls {...base} screenShare={{ supported: true, sharing: false, start, stop: vi.fn() }} />,
	);
	const button = screen.getByRole("button", { name: /share your screen/i });
	expect(button).toHaveAttribute("aria-pressed", "false");
	await user.click(button);
	expect(start).toHaveBeenCalled();

	rerender(<CallControls {...base} screenShare={{ supported: true, sharing: true, start, stop: vi.fn() }} />);
	const sharing = screen.getByRole("button", { name: /stop sharing/i });
	expect(sharing).toHaveAttribute("aria-pressed", "true");
	// The glyph changes too -- state must not be carried by colour alone.
	expect(sharing.querySelector("[data-icon='screen-share-off']")).toBeTruthy();
});

it("renders nothing at all when the browser cannot share", () => {
	render(<CallControls {...base} screenShare={{ supported: false, sharing: false, start: vi.fn(), stop: vi.fn() }} />);
	expect(screen.queryByRole("button", { name: /share your screen/i })).not.toBeInTheDocument();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/features/call/CallControls.test.tsx`
Expected: FAIL — `CallControls` takes no `screenShare` prop.

- [ ] **Step 3: Write minimal implementation**

Add the prop and render a `Button` matching the existing convention (`variant`, `size="icon"`, `aria-label` naming the action, `aria-pressed={sharing}`), with lucide's `ScreenShare` / `ScreenShareOff` and a `data-icon` attribute so the glyph is assertable. Render nothing when `supported` is false — capability, never browser sniffing. Remove the bare button from `CallRoom.tsx`.

- [ ] **Step 4: Run tests**

Run: `pnpm vitest run src/features/call/ && pnpm tsc --noEmit && pnpm lint`
Expected: PASS. `e2e/call.spec.ts` and the C4a specs use `data-testid="share-screen"` — keep that testid on the new control or the e2e breaks.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/
git commit -m "feat(call): screen share as a real control, capability-gated"
```

---

### Task 4: The Lobby — join first, permission second

**Files:**
- Modify: `dashboard/src/features/call/Lobby.tsx`, `Lobby.test.tsx`, `Lobby.layout.test.tsx`
- Modify: `dashboard/src/routes/_call/sessions.$sessionId.room.tsx` (pass the pre-join choices through)

**Interfaces:**
- Consumes: `useLocalMedia`'s full result, `DevicePickerButton` (Task 2).
- Produces: `LobbyProps.onJoin` widens to `onJoin(initial: { micOn: boolean; cameraOn: boolean })`. `CallRoomProps` gains `initialMicOn` / `initialCameraOn`, which `useCallRoom` uses to seed its `useState` instead of hardcoding `true`.

C4a removed the join gate as a minimum change. This task makes the whole surface right: preview first, a single primary Join, mic and camera toggles **on the preview**, pickers behind their chevrons, and honest copy for each permission state.

- [ ] **Step 1: Write the failing test**

```typescript
it("carries the pre-join choices into the call", async () => {
	const user = userEvent.setup();
	const onJoin = vi.fn();
	renderLobby({ onJoin, localMedia: withStream() });

	await user.click(screen.getByRole("button", { name: /turn your microphone off/i }));
	await user.click(screen.getByRole("button", { name: /join/i }));

	// Muted on arrival, not after a scramble once the lesson has started.
	expect(onJoin).toHaveBeenCalledWith({ micOn: false, cameraOn: true });
});

it("keeps Join available, and says what joining without devices means", () => {
	renderLobby({ localMedia: withFailure("denied") });
	expect(screen.getByRole("button", { name: /join/i })).toBeEnabled();
	expect(screen.getByText(/you'll be able to see and hear/i)).toBeInTheDocument();
});

it("asks for the camera only from a real tap", async () => {
	const start = vi.fn();
	const user = userEvent.setup();
	renderLobby({ localMedia: withNoStream(start) });
	expect(start).not.toHaveBeenCalled();
	await user.click(screen.getByRole("button", { name: /check camera and microphone/i }));
	expect(start).toHaveBeenCalled();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/features/call/Lobby.test.tsx`
Expected: FAIL — `onJoin` takes no argument and the toggles do not exist.

- [ ] **Step 3: Write minimal implementation**

Rebuild the Lobby body as a single column: title, preview (or an initials placeholder in the same aspect ratio, so nothing shifts when the camera arrives), the toggle row with its pickers, the primary Join, and the failure alert. Thread the pre-join choices to `useCallRoom`'s initial state.

**The gesture gate is load-bearing and must survive**: `start()` is called synchronously inside the tap handler, never from an effect. `Lobby.test.tsx` has exactly one test guarding this ("requests the camera synchronously inside the click, not from an effect") using a raw non-act-wrapped DOM click — every other test in the file cannot tell the two implementations apart. Do not touch it, and make sure it still passes.

- [ ] **Step 4: Run tests**

Run: `pnpm vitest run src/features/call/ && pnpm tsc --noEmit && pnpm lint`
Expected: PASS, `Lobby.layout.test.tsx` included — it measures `scrollWidth` to catch overflow, so a wider control row will fail it if the layout does not actually fit.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/ src/routes/_call/
git commit -m "feat(call): lobby with pre-join mic/camera choices and honest permission copy"
```

---

### Task 5: Per-viewer layout

**Files:**
- Create: `dashboard/src/features/call/useCallLayout.ts` + test, `dashboard/src/features/call/LayoutSwitcher.tsx` + test
- Modify: `dashboard/src/features/call/CallStage.tsx` + test, `CallRoom.tsx` + test

**Interfaces:**
- Produces: `type CallLayout = "spotlight" | "tiled" | "sidebar" | "pip"` and `useCallLayout(): { layout, setLayout, spotlightOn, setSpotlightOn }`. Persisted per viewer in `localStorage` under `kaleem.call.layout`.

Each viewer chooses for themselves; nothing here is sent to the other peer.

- [ ] **Step 1: Write the failing test**

```typescript
it("remembers the choice across a reload", () => {
	const { result, unmount } = renderHook(() => useCallLayout());
	act(() => result.current.setLayout("tiled"));
	unmount();
	const second = renderHook(() => useCallLayout());
	expect(second.result.current.layout).toBe("tiled");
});

it("survives storage being unavailable", () => {
	vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
		throw new Error("denied");
	});
	// A private window must not break the call; it just forgets the choice.
	const { result } = renderHook(() => useCallLayout());
	expect(result.current.layout).toBe("spotlight");
});

it("ignores a stored value that is not a layout", () => {
	localStorage.setItem("kaleem.call.layout", "sideways");
	const { result } = renderHook(() => useCallLayout());
	expect(result.current.layout).toBe("spotlight");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/features/call/useCallLayout.test.ts`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Write minimal implementation**

`useCallLayout` reads once on init inside a `try`/`catch`, validates against the four names, defaults to `spotlight`, and writes on change inside a `try`/`catch`. `LayoutSwitcher` is a button opening a radio group of the four, each with a name and an icon, `aria-checked` on the current one. `CallStage` gains a `layout` prop and arranges `remote`, `remoteScreen` and `selfView` accordingly — **by CSS only**. The video elements must not unmount or move in the DOM between layouts; that reassigns `srcObject` and aborts `play()`. Use grid placement or classes on stable wrappers, and prove it with a test asserting the same element instance persists across a layout change.

- [ ] **Step 4: Run tests**

Run: `pnpm vitest run src/features/call/ && pnpm tsc --noEmit && pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/
git commit -m "feat(call): four layouts, chosen per viewer and remembered"
```

---

### Task 6: Auto-switch on a share — once, and undoable

**Files:**
- Modify: `dashboard/src/features/call/useCallLayout.ts` + test, `CallRoom.tsx` + test

**Interfaces:**
- Consumes: `remoteScreen` (Task 5's `CallStage` already renders it), `useCallLayout`.
- Produces: `useCallLayout` gains `onShareStarted()`.

**The requirement in one sentence, because it is the whole point:** when a share starts the viewer's layout switches to spotlight on that screen exactly once, a toast offers Undo, and a viewer who then chooses a different layout keeps it for the rest of the share. Meet's habit of repeatedly yanking the layout back is the specific complaint this feature exists to answer.

- [ ] **Step 1: Write the failing test**

```typescript
it("switches once, then never overrides a manual choice", () => {
	const { result, rerender } = renderHook(
		({ sharing }) => useCallLayoutWithShare(sharing),
		{ initialProps: { sharing: false } },
	);
	rerender({ sharing: true });
	expect(result.current.layout).toBe("spotlight");

	act(() => result.current.setLayout("tiled"));
	// A re-render while the same share continues must NOT pull it back.
	rerender({ sharing: true });
	expect(result.current.layout).toBe("tiled");
});

it("switches again for a genuinely new share", () => {
	const { result, rerender } = renderHook(/* ...as above... */);
	rerender({ sharing: true });
	act(() => result.current.setLayout("tiled"));
	rerender({ sharing: false });
	rerender({ sharing: true });
	expect(result.current.layout).toBe("spotlight");
});

it("Undo restores exactly the layout the viewer had", () => {
	const { result, rerender } = renderHook(/* ... */);
	act(() => result.current.setLayout("sidebar"));
	rerender({ sharing: true });
	act(() => result.current.undoAutoSwitch());
	expect(result.current.layout).toBe("sidebar");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/features/call/useCallLayout.test.ts -t "switches once"`
Expected: FAIL — `onShareStarted` does not exist.

- [ ] **Step 3: Write minimal implementation**

Fire on the **transition** of `sharing` from false to true, not on its value — a value-keyed effect re-asserts on every re-render, which is the exact behaviour being avoided. Remember the previous layout for Undo. Use the existing `toast` from `@/ui`, with an action, and give it `aria-live="polite"` so it does not steal focus mid-call.

- [ ] **Step 4: Run tests**

Run: `pnpm vitest run src/features/call/ && pnpm tsc --noEmit && pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/
git commit -m "feat(call): a share switches your layout once, and lets you undo it"
```

---

### Task 7: Prove it in a browser

**Files:**
- Create: `dashboard/e2e/call-ui.spec.ts`
- Modify: `dashboard/e2e/call.spec.ts` only if a testid genuinely moved

**Interfaces:** consumes everything above; produces the evidence.

- [ ] **Step 1: Write the failing tests**

Four flows, each chosen because a unit test cannot reach it:
1. **A camera-less peer shows initials, not black.** Reuse C4a's `call-no-permission.spec.ts` fixture; assert the initials element is visible on the teacher's page and that `remote-video` reports `videoWidth === 0`.
2. **In-call device switch.** Open the camera picker, choose the second fake device, assert the call stays `connected` and no new offer was sent (assert the connection never leaves `connected`, since a renegotiation would show).
3. **Layout survives a reload**, and one viewer's choice does not change the other's.
4. **Keyboard only:** tab to the controls, toggle mute with the keyboard, confirm `aria-pressed` flips, and confirm focus is visible throughout.

- [ ] **Step 2: Run to verify they fail**

Run: `CI=1 pnpm e2e call-ui`
Expected: FAIL before Tasks 1–6 land; run against `main` once to see it.

- [ ] **Step 3: No production code**

If a flow fails on the branch, fix it in the task that owns it.

- [ ] **Step 4: Run everything**

```bash
CI=1 pnpm e2e && pnpm vitest run --coverage && pnpm tsc --noEmit && pnpm lint
```
Expected: green, `call.spec.ts` and both C4a specs included. **Raise the coverage floors** to the newly measured values in `vitest.config.ts` (currently 95.77 / 91.88 / 87.57) — a ratchet only goes up.

**Then the manual pass, which no harness here can do for you** (D9): open the call on a real phone in portrait and landscape, in both light and dark, in English and Arabic. Check contrast, that nothing overflows, that the controls clear the home indicator, and that the layouts mirror in RTL. Record what you checked in the journal — and record honestly that **nothing here is verified on Safari or iOS**, because this project has no Apple device. That is a standing D9 deviation, not a gap to paper over.

- [ ] **Step 5: Commit and open the PR**

```bash
git push -u origin feat/c4b-call-ui
```

---

## Self-Review

**Spec coverage.** Lobby preview-first with Join always available and pre-join toggles: Task 4. Device pickers in popovers, both lobby and in-call: Tasks 2 and 4. Screen-share control: Task 3. `ParticipantTile` initials: Task 1. Four layouts, per-viewer, persisted: Task 5. Auto-switch once with Undo: Task 6. a11y, RTL, tokens, motion: Global Constraints, enforced per task and checked in Task 7. **Deliberately NOT here** — the spec's "enable a device mid-call for a participant who joined with nothing" needs a per-kind enable control in `CallControls`; the capability exists (C4a Task 6) and the UI belongs with the pickers, so it rides in Task 2's control row. If Task 2's implementer finds that stretches the task, split it out rather than dropping it.

**Placeholders.** Tasks 1, 5 and 6 carry complete code for the subtle parts. Tasks 2, 3 and 4 give the tests verbatim and describe the markup, because the components are conventional and the existing `CallControls.tsx` is the pattern to follow.

**Type consistency.** `CallLayout` is used identically in Tasks 5, 6 and 7. `screenShare`'s shape matches what `useCallRoom` already returns. `onJoin(initial)` in Task 4 matches `initialMicOn`/`initialCameraOn` on `CallRoomProps`.

**Carried from C4a, each landing in a task above:** the `remoteHasVideo` truth (Task 1), the screen tile's real layout (Task 5), `setRemoteScreen`'s identity churn (Task 5's no-reassign rule), and the share button's missing `aria-pressed` (Task 3).
