# Session UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the schedule's session list and the call room to be genuinely responsive, and restructure the components underneath them so that redesign has somewhere to live.

**Architecture:** Two stages, in this order and no other. First a set of **pure extractions** that change no behaviour and are proven by the existing test suites passing unmodified. Only then the redesign, against a structure already proven equivalent. `CallRoom`'s WebRTC lifecycle moves wholesale into a `useCallRoom` hook; every new component below it is stateless.

**Tech Stack:** React 19, TanStack Router + Query, Tailwind v4 (`@kaleem/tokens`), vitest + @testing-library/react, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-07-session-ui-redesign-design.md`

## Global Constraints

- **All work happens in the `dashboard` submodule** on one `feat/session-ui-redesign` branch off `main`. The meta repo gets only the pointer bump plus docs. No backend, infra or marketing change.
- **Four test files are frozen. No edits, at any task, for any reason:**
  - `src/features/call/Lobby.test.tsx` — the "requests the camera synchronously inside the click, not from an effect" test
  - `src/features/call/VideoTile.test.tsx`
  - the terminal-cleanup tests in `src/features/call/CallRoom.test.tsx`
  - the visibility-recovery tests in `src/routes/_call/sessions.$sessionId.room.test.tsx`

  If a change makes one of these fail, the change is wrong. Do not adjust the test.
- **`VideoTile.tsx` logic is out of scope.** It receives new classNames from callers and nothing else. Its `useEffect(..., [stream])` dependency array stays `[stream]` alone. Its overlay condition stays `blocked && !muted`.
- **No `h-screen`, no `100vh`, anywhere.** `viewport-units.test.ts` enforces this across `src/routes` and `src/features/call`, and Task 15 extends it to `src/features/booking`.
- **Styles come from design tokens** — semantic utilities (`bg-card`, `text-muted-foreground`, `border-border`) only. No hardcoded hex, no `color-mix` in components.
- **Logical properties only** for the inline axis: `inset-s-*` / `inset-e-*` / `text-start` / `ms-*` / `me-*`, never `left`/`right`. RTL must mirror with no second rule. Note `inset-t-*` and `inset-b-*` **do not exist** in Tailwind v4 — use `top-*` / `bottom-*` for the block axis, which does not mirror.
- **Every user-visible string is an i18n key** added to **both** `src/locales/en/common.json` and `src/locales/ar/common.json`. A key in one and not the other is a defect.
- **WCAG 2.2 AA:** interactive controls keep a 44px minimum target (`Button` `size="md"`/`"icon"` = `h-11`). Decorative icons carry `aria-hidden="true"`.
- **Commands:** `pnpm test` (vitest), `pnpm lint` (biome + tsc), `pnpm test:e2e` (Playwright), all run from `dashboard/`.
- **Coverage floors** live in `dashboard/vitest.config.ts` and currently read 95.5 lines / 91.6 branches / 87.2 functions / 95.5 statements. They ratchet up in Task 17; they never go down.

---

## File Structure

**Created — `src/features/call/`**

| File | Responsibility |
| --- | --- |
| `useCallRoom.ts` | All of `CallRoom`'s current logic: signaling + peer wiring, mic/camera flags, terminal derivation, cleanup effects, `handleLeave`. Returns a view model. |
| `CallStage.tsx` | Stage layout — remote surface, self-view slot, chrome slots. Stateless. |
| `CallStatus.tsx` | Connection chip + lesson identity header. Stateless. |
| `WaitingForPeer.tsx` | The "alone in the room" state. Stateless. |
| `CallEnded.tsx` | Terminal screens. Stateless. |
| `SelfView.tsx` | Fluid picture-in-picture wrapper around `VideoTile`. Stateless. |
| `DeviceSelect.tsx` | One camera/microphone picker. Stateless. |
| `MediaFailureAlert.tsx` | Per-failure copy, shared by Lobby and the in-room banner. Stateless. |

**Created — `src/features/booking/components/`**

| File | Responsibility |
| --- | --- |
| `SessionCard.tsx` | One session, responsive grid. Stateless apart from the cancel dialog's open state, which it delegates. |
| `CancelSessionDialog.tsx` | The cancel confirmation, its mutation and its failure state. |
| `groupSessionsByDay.ts` | Pure function: sorted sessions → day-labelled groups. |

**Created — `src/ui/`**

| File | Responsibility |
| --- | --- |
| `select.tsx` | The design system's missing native `<select>`. |
| `status-chip.tsx` | Small labelled status pill. |
| `relative-time.tsx` | `Intl.RelativeTimeFormat` wrapper, **extracted from `JoinButton`**. |

**Modified:** `CallRoom.tsx` (thinned), `Lobby.tsx` (thinned + relaid out), `CallControls.tsx` (restyled), `SessionList.tsx` (thinned + grouping), `JoinButton.tsx` (uses `RelativeTime`), `src/ui/index.ts`, both `common.json` files, `vitest.config.ts`, `viewport-units.test.ts`.

---

# Stage 1 — Pure extractions (no behaviour change)

The rule for every task in this stage: **the existing test files pass unmodified.** If one needs editing, the extraction is wrong — revert and redo it. This is the entire safety net for the restructure, so it is not negotiable and not a formality.

---

### Task 1: Extract `useCallRoom` from `CallRoom`

**Files:**
- Create: `dashboard/src/features/call/useCallRoom.ts`
- Modify: `dashboard/src/features/call/CallRoom.tsx`
- Test: `dashboard/src/features/call/CallRoom.test.tsx` — **read only, do not edit**

**Interfaces:**
- Consumes: `usePeerConnection`, `useSignaling`, `setTrackEnabled` (currently a module-level helper in `CallRoom.tsx` — move it into `useCallRoom.ts`), `UseLocalMediaResult`, `JoinGrant`.
- Produces:

```ts
export interface TerminalScreen {
  titleKey: string;
  detailKey?: string;
  onRetry?: () => void;
}

export interface UseCallRoomResult {
  state: PeerConnectionState;
  remoteStream: MediaStream | null;
  isTeacher: boolean;
  micOn: boolean;
  cameraOn: boolean;
  toggleMic: () => void;
  toggleCamera: () => void;
  leave: () => void;
  terminal: TerminalScreen | null;
  mediaFailure: MediaFailure | null;
  retryMedia: () => void;
  onAutoplayBlocked: () => void;
}

export function useCallRoom(props: CallRoomProps): UseCallRoomResult;
```

- [ ] **Step 1: Verify the existing suite is green before touching anything**

```bash
cd dashboard && pnpm test -- src/features/call/CallRoom.test.tsx
```

Expected: PASS. Record the test count — the same number must pass at Step 5. A suite you did not see green before the change proves nothing after it.

- [ ] **Step 2: Create `useCallRoom.ts` by moving code verbatim**

Move, do not rewrite. Cut from `CallRoom.tsx` and paste into `useCallRoom.ts`, **carrying every comment with its code**: `TERMINAL_FAILURE_COPY`, `CONNECTION_STATE_COPY`, `reconnectingCopyKey`, `setTrackEnabled`, the `usePeerConnection`/`useSignaling` calls, the mount/unmount effect, the expiry effect, the track-enable effect, `toggleMic`, `toggleCamera`, `handleLeave`, the terminal derivation `if/else` chain, the terminal-cleanup effect, and `handleAutoplayBlocked`.

The comments are the record of five shipped bugs. A comment left behind in `CallRoom.tsx` while its code moves is a defect in this task.

Guard-rails that must survive the move unchanged:
- `expiredCalledRef` still guards `onExpired` to exactly one call per mounted instance.
- `terminalCleanupDoneRef` still guards the terminal cleanup so `peer.close()` / `localMedia.stop()` run once.
- The track-enable effect's dependency array stays `[localMedia.stream, micOn, cameraOn]` — the stream identity is the load-bearing half.
- The terminal derivation keeps its exact branch order: `room-full`/`replaced`, then `unauthorized`, then `lost`, then `peer.state === "failed"`.

- [ ] **Step 3: Reduce `CallRoom.tsx` to a caller**

```tsx
export function CallRoom(props: CallRoomProps) {
	const { t } = useTranslation();
	const room = useCallRoom(props);

	if (room.terminal) {
		// ... the existing terminal JSX, unchanged, reading from `room.terminal`
	}

	// ... the existing stage JSX, unchanged, reading from `room.*`
}
```

Only the *sources* of the values change (`micOn` → `room.micOn`). The JSX itself is not touched in this task — it is redesigned in Stage 4, and mixing the two is how an extraction stops proving anything.

- [ ] **Step 4: Run the frozen suite**

```bash
cd dashboard && pnpm test -- src/features/call/CallRoom.test.tsx
```

Expected: PASS, with **the same test count as Step 1** and **zero edits to the test file**. Confirm with `git status` that `CallRoom.test.tsx` is unmodified.

- [ ] **Step 5: Run the full suite and the linter**

```bash
cd dashboard && pnpm test && pnpm lint
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/features/call/useCallRoom.ts src/features/call/CallRoom.tsx
git commit -m "refactor: extract useCallRoom from CallRoom, no behaviour change

The existing 557-line CallRoom.test.tsx passes unmodified, which is the
point of doing this as its own commit before any redesign."
```

---

### Task 2: Mutation-check the extraction

The extracted guards are worth exactly as much as the tests that catch their removal. This task finds out which ones those are. It ends with **no production change** — every mutation is reverted.

**Files:**
- Temporarily modify then revert: `dashboard/src/features/call/useCallRoom.ts`
- Possibly create: new tests in `dashboard/src/features/call/useCallRoom.test.ts`

- [ ] **Step 1: Mutate the expiry guard**

In `useCallRoom.ts`, delete `!expiredCalledRef.current` from the expiry effect's condition. Run:

```bash
cd dashboard && pnpm test -- src/features/call/
```

Expected: **FAIL.** If it passes, the guard is uncovered — write the missing test before reverting:

```ts
it("asks for a re-mint exactly once even if the failure re-renders", async () => {
  const onExpired = vi.fn();
  const { rerender } = renderRoom({ onExpired, expiredRetryAvailable: true });
  await closeSocket(4401);
  rerender(<CallRoom {...props} onExpired={onExpired} expiredRetryAvailable />);
  expect(onExpired).toHaveBeenCalledTimes(1);
});
```

- [ ] **Step 2: Revert the mutation and confirm green**

```bash
cd dashboard && git checkout src/features/call/useCallRoom.ts && pnpm test -- src/features/call/
```

Expected: PASS.

- [ ] **Step 3: Mutate the terminal cleanup**

Delete the `peer.close()` and `localMedia.stop()` calls from the terminal-cleanup effect. Run the suite.

Expected: **FAIL** — this is the "live camera behind a dead-end screen" defect and the frozen tests must catch it. If it passes, the freeze is protecting nothing; stop and report that finding before continuing.

- [ ] **Step 4: Revert and confirm green**

```bash
cd dashboard && git checkout src/features/call/useCallRoom.ts && pnpm test -- src/features/call/
```

- [ ] **Step 5: Mutate the track-enable dependency array**

Change `[localMedia.stream, micOn, cameraOn]` to `[micOn, cameraOn]` — the "muted teacher plugs in a headset and is live again" bug. Run the suite.

Expected: **FAIL.** If it passes, add:

```ts
it("re-applies mute to a freshly acquired stream after a device swap", () => {
  const { rerender } = renderRoom({ localMedia: mediaWith(streamA) });
  act(() => screen.getByRole("button", { name: /microphone/i }).click());
  rerender(<CallRoom {...props} localMedia={mediaWith(streamB)} />);
  expect(streamB.getAudioTracks()[0].enabled).toBe(false);
});
```

- [ ] **Step 6: Revert, confirm green, commit any tests written**

```bash
cd dashboard && git checkout src/features/call/useCallRoom.ts && pnpm test
git add src/features/call/useCallRoom.test.ts
git commit -m "test: cover the useCallRoom guards that survived their own deletion"
```

If no test was needed, there is nothing to commit — say so explicitly in the task report rather than inventing a commit.

---

### Task 3: Extract `Select`, `DeviceSelect` and `MediaFailureAlert` from `Lobby`

**Files:**
- Create: `dashboard/src/ui/select.tsx`, `dashboard/src/ui/select.test.tsx`
- Create: `dashboard/src/features/call/DeviceSelect.tsx`, `DeviceSelect.test.tsx`
- Create: `dashboard/src/features/call/MediaFailureAlert.tsx`, `MediaFailureAlert.test.tsx`
- Modify: `dashboard/src/features/call/Lobby.tsx`, `dashboard/src/features/call/CallRoom.tsx`, `dashboard/src/ui/index.ts`
- Test: `dashboard/src/features/call/Lobby.test.tsx` — **frozen, do not edit**

**Interfaces:**
- Produces:

```tsx
export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>): JSX.Element;

export function DeviceSelect(props: {
  id: string;
  label: string;
  devices: MediaDeviceInfo[];
  value: string | null;
  onChange: (id: string) => void;
  fallbackLabel: string;
}): JSX.Element;

export function MediaFailureAlert(props: {
  failure: MediaFailure;
  genericTitleKey?: string;
  onRetry?: () => void;
}): JSX.Element;
```

- [ ] **Step 1: Write the failing test for `Select`**

```tsx
// src/ui/select.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Select } from "./select";

describe("Select", () => {
	it("renders its options and reflects the value", () => {
		render(
			<Select aria-label="Camera" value="a" onChange={() => {}}>
				<option value="a">Front</option>
				<option value="b">Back</option>
			</Select>,
		);
		expect(screen.getByRole("combobox", { name: "Camera" })).toHaveValue("a");
	});

	it("aligns text logically so RTL mirrors without a second rule", () => {
		render(<Select aria-label="Camera" />);
		expect(screen.getByRole("combobox")).toHaveClass("text-end");
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd dashboard && pnpm test -- src/ui/select.test.tsx
```

Expected: FAIL — `Cannot find module './select'`.

- [ ] **Step 3: Implement `Select` by moving `selectClassName` out of `Lobby`**

```tsx
// src/ui/select.tsx
import type * as React from "react";
import { cn } from "@/lib/cn";

/**
 * The design system's native select. Extracted from `Lobby`, which hand-rolled
 * these classes because `src/ui` had no select at all.
 *
 * `text-end` is logical, not `rtl:text-right`: the baseline here is full RTL
 * everywhere, mirrored from the document's own `dir` rather than per-feature.
 */
export function Select({
	className,
	...props
}: React.SelectHTMLAttributes<HTMLSelectElement>) {
	return (
		<select
			className={cn(
				"flex h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-base text-foreground sm:text-sm",
				"transition-colors motion-reduce:transition-none hover:border-ring/60",
				"focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
				"focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:opacity-50",
				"text-end",
				className,
			)}
			{...props}
		/>
	);
}
```

Export it from `src/ui/index.ts`, alphabetically: `export { Select } from "./select";`

- [ ] **Step 4: Run and watch it pass**

```bash
cd dashboard && pnpm test -- src/ui/select.test.tsx
```

Expected: PASS.

- [ ] **Step 5: Write the failing test for `DeviceSelect`**

```tsx
// src/features/call/DeviceSelect.test.tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { DeviceSelect } from "./DeviceSelect";

const devices = [
	{ deviceId: "a", label: "Front camera" },
	{ deviceId: "b", label: "" },
] as MediaDeviceInfo[];

describe("DeviceSelect", () => {
	it("labels an unlabelled device by its position", () => {
		render(
			<DeviceSelect
				id="cam"
				label="Camera"
				devices={devices}
				value="a"
				onChange={() => {}}
				fallbackLabel="Camera"
			/>,
		);
		expect(screen.getByRole("option", { name: "Camera 2" })).toBeInTheDocument();
	});

	it("reports the chosen device id", async () => {
		const onChange = vi.fn();
		render(
			<DeviceSelect
				id="cam"
				label="Camera"
				devices={devices}
				value="a"
				onChange={onChange}
				fallbackLabel="Camera"
			/>,
		);
		await userEvent.setup().selectOptions(screen.getByRole("combobox"), "b");
		expect(onChange).toHaveBeenCalledWith("b");
	});
});
```

- [ ] **Step 6: Run it and watch it fail, then implement**

```tsx
// src/features/call/DeviceSelect.tsx
import { Field, Select } from "@/ui";

/**
 * One camera/microphone picker. The Lobby rendered this markup twice, and the
 * in-room device picker in Stage 4 needs it a third time.
 *
 * `fallbackLabel` covers a device the browser refuses to name (Firefox before
 * permission is granted, and Safari for anything but the active device):
 * "Camera 2" beats an empty option nobody can choose between.
 */
export function DeviceSelect({
	id,
	label,
	devices,
	value,
	onChange,
	fallbackLabel,
}: {
	id: string;
	label: string;
	devices: MediaDeviceInfo[];
	value: string | null;
	onChange: (id: string) => void;
	fallbackLabel: string;
}) {
	return (
		<Field id={id} label={label}>
			<Select
				id={id}
				value={value ?? ""}
				onChange={(event) => onChange(event.target.value)}
			>
				{devices.map((device, index) => (
					<option key={device.deviceId} value={device.deviceId}>
						{device.label || `${fallbackLabel} ${index + 1}`}
					</option>
				))}
			</Select>
		</Field>
	);
}
```

Run: `pnpm test -- src/features/call/DeviceSelect.test.tsx` → PASS.

- [ ] **Step 7: Write the failing test for `MediaFailureAlert`**

```tsx
// src/features/call/MediaFailureAlert.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { MediaFailureAlert } from "./MediaFailureAlert";

describe("MediaFailureAlert", () => {
	it("gives `denied` its own title and actionable help", () => {
		render(<MediaFailureAlert failure="denied" />);
		expect(screen.getByText(/access denied/i)).toBeInTheDocument();
		expect(screen.getByText(/allow camera and microphone/i)).toBeInTheDocument();
	});

	it("uses the per-failure message for a busy device", () => {
		render(<MediaFailureAlert failure="in-use" />);
		expect(screen.getByText(/used by another app/i)).toBeInTheDocument();
	});

	it("renders a retry control only when one is offered", () => {
		const { rerender } = render(<MediaFailureAlert failure="in-use" />);
		expect(screen.queryByRole("button")).not.toBeInTheDocument();
		rerender(<MediaFailureAlert failure="in-use" onRetry={() => {}} />);
		expect(screen.getByRole("button", { name: /try again/i })).toBeInTheDocument();
	});
});
```

- [ ] **Step 8: Run it, watch it fail, then implement**

```tsx
// src/features/call/MediaFailureAlert.tsx
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, AlertTitle, Button } from "@/ui";
import type { MediaFailure } from "./useLocalMedia";

// `denied` gets its own title + explanation because "allow camera access" is
// actionable advice; the others each get one message tuned to what actually
// went wrong -- "no device" and "device busy" are different problems with
// different fixes, and collapsing them leaves the person guessing.
//
// This lives here, not in `Lobby`, because the Lobby and the in-room banner
// used to branch on `denied`-versus-everything-else with two copies of the
// same conditional. Two places that must agree about the same failure are two
// places that can drift.
export const FAILURE_MESSAGE_KEY: Record<
	Exclude<MediaFailure, "denied">,
	string
> = {
	"not-found": "call.noDevice",
	"in-use": "call.deviceBusy",
	"no-gesture": "call.noGestureHelp",
	unknown: "call.unknownFailure",
};

export function MediaFailureAlert({
	failure,
	genericTitleKey,
	onRetry,
}: {
	failure: MediaFailure;
	// Supplied by the in-room banner, which needs to say "your camera stopped
	// working" rather than repeating the Lobby's framing. Omitted in the
	// Lobby, where the message alone is the whole story.
	genericTitleKey?: string;
	onRetry?: () => void;
}) {
	const { t } = useTranslation();
	const denied = failure === "denied";
	const titleKey = denied ? "call.deniedTitle" : genericTitleKey;

	return (
		<Alert variant="destructive" className="text-start">
			{titleKey ? <AlertTitle>{t(titleKey)}</AlertTitle> : null}
			<AlertDescription>
				<p>{denied ? t("call.deniedHelp") : t(FAILURE_MESSAGE_KEY[failure])}</p>
				{onRetry ? (
					<Button size="sm" variant="outline" className="mt-2" onClick={onRetry}>
						{t("call.tryAgain")}
					</Button>
				) : null}
			</AlertDescription>
		</Alert>
	);
}
```

- [ ] **Step 9: Rewire `Lobby` and `CallRoom` to the extractions**

In `Lobby.tsx`: delete `selectClassName` and the exported `FAILURE_MESSAGE_KEY`, replace the two inline `<Field><select>` blocks with `<DeviceSelect>`, and replace the failure `<Alert>` with `<MediaFailureAlert failure={failure} onRetry={() => void start()} />`.

In `CallRoom.tsx`: change the `FAILURE_MESSAGE_KEY` import from `./Lobby` to `./MediaFailureAlert`, and replace the in-room `<Alert>` block with:

```tsx
<MediaFailureAlert
	failure={room.mediaFailure}
	genericTitleKey="call.mediaFailedInRoom"
	onRetry={room.retryMedia}
/>
```

**The `handleEnable` click handler stays exactly where it is in `Lobby.tsx`.** `start()` must remain called synchronously inside that handler. Do not move it, do not wrap it, do not let it become an effect.

- [ ] **Step 10: Run the frozen Lobby suite and the full suite**

```bash
cd dashboard && pnpm test && pnpm lint
git status --short src/features/call/Lobby.test.tsx
```

Expected: all PASS, and `Lobby.test.tsx` shows **no modification**.

- [ ] **Step 11: Commit**

```bash
git add src/ui/select.tsx src/ui/select.test.tsx src/ui/index.ts \
        src/features/call/DeviceSelect.tsx src/features/call/DeviceSelect.test.tsx \
        src/features/call/MediaFailureAlert.tsx src/features/call/MediaFailureAlert.test.tsx \
        src/features/call/Lobby.tsx src/features/call/CallRoom.tsx
git commit -m "refactor: extract Select, DeviceSelect and MediaFailureAlert

Closes a real duplication: Lobby and CallRoom each branched on
denied-vs-everything-else with their own copy of the same conditional.
Lobby.test.tsx passes unmodified."
```

---

### Task 4: Extract `RelativeTime` from `JoinButton`

**Files:**
- Create: `dashboard/src/ui/relative-time.tsx`, `dashboard/src/ui/relative-time.test.tsx`
- Modify: `dashboard/src/features/booking/components/JoinButton.tsx`, `dashboard/src/ui/index.ts`

**Interfaces:**
- Produces:

```ts
export function formatRelative(target: string, now: number, locale: string): string;
export function RelativeTime(props: { target: string; now: number }): JSX.Element;
```

`JoinButton` already contains `formatRelativeJoinTime`. This is a move, not a new implementation — the call room's identity header and the session card both need the same behaviour, and three copies of an `Intl.RelativeTimeFormat` unit ladder will drift.

- [ ] **Step 1: Write the failing test**

```tsx
// src/ui/relative-time.test.tsx
import { describe, expect, it } from "vitest";
import { formatRelative } from "./relative-time";

const NOW = Date.parse("2026-09-07T12:00:00Z");
const at = (iso: string) => formatRelative(iso, NOW, "en");

describe("formatRelative", () => {
	it("reads in minutes under an hour", () => {
		expect(at("2026-09-07T12:30:00Z")).toMatch(/30 minutes/);
	});

	it("reads in hours under a day", () => {
		expect(at("2026-09-07T17:00:00Z")).toMatch(/5 hours/);
	});

	it("reads in days beyond that", () => {
		expect(at("2026-09-10T12:00:00Z")).toMatch(/3 days/);
	});

	it("never reads as the past -- a target already reached clamps to now", () => {
		expect(at("2026-09-07T11:00:00Z")).not.toMatch(/ago/);
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd dashboard && pnpm test -- src/ui/relative-time.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Move the implementation out of `JoinButton`**

```tsx
// src/ui/relative-time.tsx
import { useTranslation } from "react-i18next";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

/**
 * Picks the largest sensible unit -- under an hour in minutes, under a day in
 * hours, otherwise days -- and hands off to the browser's own
 * Intl.RelativeTimeFormat for pluralisation. A hand-rolled minute count is
 * unreadable at the distances a weekly-generated schedule produces: sessions
 * two and three weeks out are routine, not edge cases.
 *
 * Extracted from `JoinButton`, which owned the only copy until the session
 * card and the call room's header needed the same ladder.
 */
export function formatRelative(
	target: string,
	now: number,
	locale: string,
): string {
	// Clamped at zero: a session whose moment has arrived reads "in 0 minutes",
	// never "3 minutes ago". The countdown's job is to end, not to run negative.
	const diffMs = Math.max(0, new Date(target).getTime() - now);
	const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });

	if (diffMs < HOUR_MS) return rtf.format(Math.ceil(diffMs / MINUTE_MS), "minute");
	if (diffMs < DAY_MS) return rtf.format(Math.ceil(diffMs / HOUR_MS), "hour");
	return rtf.format(Math.ceil(diffMs / DAY_MS), "day");
}

export function RelativeTime({ target, now }: { target: string; now: number }) {
	const { i18n } = useTranslation();
	return <>{formatRelative(target, now, i18n.language)}</>;
}
```

Export both from `src/ui/index.ts`.

- [ ] **Step 4: Rewire `JoinButton`**

Delete `formatRelativeJoinTime` and the three `*_MS` constants from `JoinButton.tsx`; import `formatRelative` from `@/ui` and call it in place. The `active` guard, the one-second interval and its cleanup stay exactly as they are.

- [ ] **Step 5: Run the tests**

```bash
cd dashboard && pnpm test -- src/ui/relative-time.test.tsx src/features/booking && pnpm lint
```

Expected: PASS, with `JoinButton`'s existing tests unmodified.

- [ ] **Step 6: Commit**

```bash
git add src/ui/relative-time.tsx src/ui/relative-time.test.tsx src/ui/index.ts \
        src/features/booking/components/JoinButton.tsx
git commit -m "refactor: extract RelativeTime from JoinButton into src/ui"
```

---

### Task 5: Extract `SessionCard` and `CancelSessionDialog` from `SessionList`

**Files:**
- Create: `dashboard/src/features/booking/components/SessionCard.tsx`, `SessionCard.test.tsx`
- Create: `dashboard/src/features/booking/components/CancelSessionDialog.tsx`, `CancelSessionDialog.test.tsx`
- Modify: `dashboard/src/features/booking/components/SessionList.tsx`
- Test: existing `SessionList.test.tsx` — passes unmodified

**Interfaces:**
- Produces:

```tsx
export function SessionCard(props: {
  session: Session;
  viewerRole: ViewerRole;
  onCancelled: () => void;
}): JSX.Element;

export function CancelSessionDialog(props: {
  session: Session;
  formattedDate: string;
  onCancelled: () => void;
}): JSX.Element;
```

- [ ] **Step 1: Confirm the existing suite is green and record the count**

```bash
cd dashboard && pnpm test -- src/features/booking/
```

- [ ] **Step 2: Move `SessionRow`'s dialog into `CancelSessionDialog.tsx` verbatim**

Carry the `useCancelSession` mutation, the `open` state, `cancelFailed`, `confirmCancel`, the `onOpenChange` reset and the whole `AlertDialog` tree — **with their comments**. Two comments in particular are load-bearing and must travel with the code they explain: the one about resetting `cancelFailed` on every open/close transition, and the one about keeping the error inside the dialog content because Radix marks everything outside an open dialog `aria-hidden`.

- [ ] **Step 3: Rename `SessionRow` to `SessionCard` in its own file**

Move it into `SessionCard.tsx` unchanged apart from rendering `<CancelSessionDialog>` where the inline dialog used to be. **The refund-consequence paragraph stays on the card** — it is deliberately shown before the cancel control is ever clicked. Do not fold it into the dialog.

- [ ] **Step 4: Reduce `SessionList.tsx`**

It keeps the query, the `isPending`/`isError` branches, the filter-and-sort, the `announcement` state and the `<ul>`. It imports `SessionCard`.

- [ ] **Step 5: Run the suite unmodified**

```bash
cd dashboard && pnpm test && pnpm lint
git status --short src/features/booking/
```

Expected: PASS with the same count; no test file modified.

- [ ] **Step 6: Commit**

```bash
git add src/features/booking/components/
git commit -m "refactor: split SessionList into SessionCard and CancelSessionDialog"
```

---

# Stage 2 — New primitives

### Task 6: `StatusChip`

**Files:**
- Create: `dashboard/src/ui/status-chip.tsx`, `dashboard/src/ui/status-chip.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

**Interfaces:**
- Produces: `export function StatusChip(props: { tone?: "neutral" | "live" | "warning"; pulse?: boolean; children: React.ReactNode; className?: string }): JSX.Element;`

- [ ] **Step 1: Write the failing test**

```tsx
// src/ui/status-chip.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { StatusChip } from "./status-chip";

describe("StatusChip", () => {
	it("renders its label", () => {
		render(<StatusChip>Happening now</StatusChip>);
		expect(screen.getByText("Happening now")).toBeInTheDocument();
	});

	it("carries no role of its own -- it is text, not a status region", () => {
		// The live region belongs to the caller that knows whether this chip
		// changing is worth announcing. A chip that announced itself would
		// interrupt a screen reader every time a countdown ticked.
		const { container } = render(<StatusChip>Now</StatusChip>);
		expect(container.querySelector("[role]")).toBeNull();
	});

	it("does not animate the pulse when motion is reduced", () => {
		render(<StatusChip pulse>Now</StatusChip>);
		expect(screen.getByTestId("status-chip-pulse")).toHaveClass(
			"motion-reduce:animate-none",
		);
	});
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm test -- src/ui/status-chip.test.tsx
```

- [ ] **Step 3: Implement**

```tsx
// src/ui/status-chip.tsx
import type * as React from "react";
import { cn } from "@/lib/cn";

const TONE = {
	neutral: "bg-muted text-muted-foreground",
	live: "bg-success text-success-foreground",
	warning: "bg-destructive text-destructive-foreground",
} as const;

/**
 * A small labelled status pill: "Happening now" on a session card, the
 * connection state in the call room.
 *
 * Deliberately carries no `role` and no `aria-live`. Whether a change here is
 * worth announcing depends on the caller -- the call room's connection chip
 * wants a polite live region around it, a countdown chip that ticks every
 * second very much does not.
 */
export function StatusChip({
	tone = "neutral",
	pulse = false,
	className,
	children,
}: {
	tone?: keyof typeof TONE;
	pulse?: boolean;
	className?: string;
	children: React.ReactNode;
}) {
	return (
		<span
			className={cn(
				"inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium",
				TONE[tone],
				className,
			)}
		>
			{pulse ? (
				<span
					aria-hidden="true"
					data-testid="status-chip-pulse"
					className="size-1.5 rounded-full bg-current animate-pulse motion-reduce:animate-none"
				/>
			) : null}
			{children}
		</span>
	);
}
```

- [ ] **Step 4: Run, pass, export, commit**

```bash
cd dashboard && pnpm test -- src/ui/status-chip.test.tsx && pnpm lint
git add src/ui/status-chip.tsx src/ui/status-chip.test.tsx src/ui/index.ts
git commit -m "feat: add StatusChip primitive"
```

---

# Stage 3 — The schedule redesign

### Task 7: Group sessions by day

**Files:**
- Create: `dashboard/src/features/booking/components/groupSessionsByDay.ts`, `groupSessionsByDay.test.ts`
- Modify: `dashboard/src/features/booking/components/SessionList.tsx`
- Modify: both `common.json`

**Interfaces:**
- Produces:

```ts
export interface SessionGroup { key: string; labelKey: string; date: Date; sessions: Session[] }
export function groupSessionsByDay(sessions: Session[], now: number): SessionGroup[];
```

`labelKey` is `"booking.today"`, `"booking.tomorrow"`, or `""` — an empty key means the caller formats `date` with `Intl.DateTimeFormat` instead. Keeping the decision in the pure function and the *formatting* in the component is what makes this testable without a locale.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/booking/components/groupSessionsByDay.test.ts
import { describe, expect, it } from "vitest";
import type { Session } from "../schemas";
import { groupSessionsByDay } from "./groupSessionsByDay";

const NOW = Date.parse("2026-09-07T12:00:00Z");
const session = (id: number, starts_at: string) =>
	({ id, starts_at }) as Session;

describe("groupSessionsByDay", () => {
	it("labels today and tomorrow by key, and leaves later days to the caller", () => {
		const groups = groupSessionsByDay(
			[
				session(1, "2026-09-07T18:00:00Z"),
				session(2, "2026-09-08T10:00:00Z"),
				session(3, "2026-09-14T10:00:00Z"),
			],
			NOW,
		);
		expect(groups.map((g) => g.labelKey)).toEqual([
			"booking.today",
			"booking.tomorrow",
			"",
		]);
	});

	it("puts several sessions on one day into one group, in time order", () => {
		const groups = groupSessionsByDay(
			[
				session(1, "2026-09-07T18:00:00Z"),
				session(2, "2026-09-07T09:00:00Z"),
			],
			NOW,
		);
		expect(groups).toHaveLength(1);
		expect(groups[0].sessions.map((s) => s.id)).toEqual([2, 1]);
	});

	it("groups by LOCAL calendar day, not by 24-hour distance", () => {
		// 23:00 today and 01:00 tomorrow are two hours apart and must still
		// land in different groups -- the whole point of a day heading.
		const groups = groupSessionsByDay(
			[
				session(1, "2026-09-07T23:00:00Z"),
				session(2, "2026-09-08T01:00:00Z"),
			],
			Date.parse("2026-09-07T22:00:00Z"),
		);
		expect(groups).toHaveLength(2);
	});

	it("returns nothing for no sessions", () => {
		expect(groupSessionsByDay([], NOW)).toEqual([]);
	});
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm test -- src/features/booking/components/groupSessionsByDay.test.ts
```

- [ ] **Step 3: Implement**

```ts
// src/features/booking/components/groupSessionsByDay.ts
import type { Session } from "../schemas";

export interface SessionGroup {
	key: string;
	// "booking.today" / "booking.tomorrow", or "" meaning "the caller should
	// format `date` itself". The decision lives here so it can be tested
	// without a locale; the formatting lives in the component so it can use
	// the viewer's.
	labelKey: string;
	date: Date;
	sessions: Session[];
}

// Local calendar day, not UTC and not a 24-hour bucket: 23:00 and 01:00 are
// two hours apart and belong under different headings, which is the entire
// purpose of a day heading.
function dayKey(date: Date): string {
	return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

export function groupSessionsByDay(
	sessions: Session[],
	now: number,
): SessionGroup[] {
	const today = new Date(now);
	const tomorrow = new Date(now);
	tomorrow.setDate(tomorrow.getDate() + 1);

	const groups = new Map<string, SessionGroup>();
	for (const session of [...sessions].sort(
		(a, b) =>
			new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime(),
	)) {
		const date = new Date(session.starts_at);
		const key = dayKey(date);
		let group = groups.get(key);
		if (!group) {
			group = {
				key,
				labelKey:
					key === dayKey(today)
						? "booking.today"
						: key === dayKey(tomorrow)
							? "booking.tomorrow"
							: "",
				date,
				sessions: [],
			};
			groups.set(key, group);
		}
		group.sessions.push(session);
	}
	return [...groups.values()];
}
```

- [ ] **Step 4: Run and pass**

```bash
cd dashboard && pnpm test -- src/features/booking/components/groupSessionsByDay.test.ts
```

- [ ] **Step 5: Add the copy to both locales**

`src/locales/en/common.json`, under `booking`:

```json
"today": "Today",
"tomorrow": "Tomorrow",
"happeningNow": "Happening now",
"startsIn": "Starts {{when}}"
```

`src/locales/ar/common.json`, under `booking`:

```json
"today": "اليوم",
"tomorrow": "غدًا",
"happeningNow": "جارية الآن",
"startsIn": "تبدأ {{when}}"
```

- [ ] **Step 6: Render the groups in `SessionList`**

```tsx
const groups = groupSessionsByDay(upcoming, Date.now());

return (
	<div className="flex flex-col gap-6">
		{announcement ? (
			<p role="status" aria-live="polite" className="sr-only">{announcement}</p>
		) : null}
		{groups.length === 0 ? (
			<EmptyState icon={CalendarClock} title={t("booking.empty")} />
		) : (
			groups.map((group) => (
				<section key={group.key} className="flex flex-col gap-3">
					<h2 className="text-sm font-semibold text-muted-foreground">
						{group.labelKey
							? t(group.labelKey)
							: new Intl.DateTimeFormat(i18n.language, {
									weekday: "long",
									day: "numeric",
									month: "long",
								}).format(group.date)}
					</h2>
					<ul className="flex flex-col gap-3">
						{group.sessions.map((session) => (
							<SessionCard
								key={session.id}
								session={session}
								viewerRole={viewerRole}
								onCancelled={() => setAnnouncement(t("booking.cancelled"))}
							/>
						))}
					</ul>
				</section>
			))
		)}
	</div>
);
```

Add `i18n` to the `useTranslation()` destructure.

- [ ] **Step 7: Run everything and commit**

```bash
cd dashboard && pnpm test && pnpm lint
git add src/features/booking/components/ src/locales/
git commit -m "feat: group the schedule by day"
```

---

### Task 8: Redesign `SessionCard` as a responsive grid

**Files:**
- Modify: `dashboard/src/features/booking/components/SessionCard.tsx`, `SessionCard.test.tsx`

- [ ] **Step 1: Write the failing tests**

```tsx
// added to src/features/booking/components/SessionCard.test.tsx
it("marks a joinable session as happening now", () => {
	renderCard({ session: { ...base, may_join: true, can_join_at: PAST } });
	expect(screen.getByText(/happening now/i)).toBeInTheDocument();
});

it("does not claim a future session is happening now", () => {
	renderCard({ session: { ...base, may_join: true, can_join_at: FUTURE } });
	expect(screen.queryByText(/happening now/i)).not.toBeInTheDocument();
});

it("lays actions out in a row from sm up, and stacked below it", () => {
	renderCard();
	expect(screen.getByTestId("session-card-actions")).toHaveClass(
		"flex-col",
		"sm:flex-row",
	);
});

it("uses a logical grid so RTL mirrors with no second rule", () => {
	renderCard();
	const card = screen.getByRole("listitem");
	expect(card.className).not.toMatch(/\b(left|right)-/);
	expect(card.className).not.toMatch(/\bpl-|\bpr-/);
});
```

- [ ] **Step 2: Run and watch them fail**

```bash
cd dashboard && pnpm test -- src/features/booking/components/SessionCard.test.tsx
```

- [ ] **Step 3: Implement the grid**

```tsx
const startsAt = new Date(session.starts_at);
const live = session.may_join && Date.now() >= new Date(session.can_join_at).getTime();

return (
	<li
		className={cn(
			"grid gap-4 rounded-lg border bg-card p-4 shadow-sm",
			"sm:grid-cols-[auto_1fr_auto] sm:items-center",
			live ? "border-success" : "border-border",
		)}
	>
		{/* Leading time block. `tabular-nums` keeps a column of times from
		    shifting width as the digits change. */}
		<div className="flex items-baseline gap-2 sm:flex-col sm:items-start sm:gap-0.5">
			<span className="font-display text-lg font-semibold tabular-nums">
				{new Intl.DateTimeFormat(i18n.language, { timeStyle: "short" }).format(startsAt)}
			</span>
			<span className="text-xs text-muted-foreground">
				{t("booking.durationMinutes", { count: session.duration_minutes })}
			</span>
		</div>

		<div className="flex flex-col gap-1">
			<div className="flex flex-wrap items-center gap-2">
				<p className="font-medium">{session.subject_name}</p>
				{live ? (
					<StatusChip tone="live" pulse>{t("booking.happeningNow")}</StatusChip>
				) : null}
			</div>
			{viewerRole !== "student" ? (
				<p className="text-sm text-muted-foreground">
					{t("booking.withStudent", { name: session.student_name })}
				</p>
			) : null}
			{viewerRole !== "teacher" ? (
				<p className="text-sm text-muted-foreground">
					{t("booking.withTeacher", { name: session.teacher_name })}
				</p>
			) : null}
		</div>

		<div
			data-testid="session-card-actions"
			className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-end"
		>
			<JoinButton session={session} formattedDate={formattedDate} />
			{session.may_cancel ? (
				<CancelSessionDialog
					session={session}
					formattedDate={formattedDate}
					onCancelled={onCancelled}
				/>
			) : null}
		</div>

		{/* The refund consequence stays ON THE CARD, stated before the cancel
		    control is ever clicked -- not only inside the dialog that follows
		    it. Demoted to a quiet line, never removed. */}
		{session.may_cancel ? (
			<p className="text-xs text-muted-foreground sm:col-span-3">
				{session.cancellation_refunds
					? t("booking.cancelRefunds")
					: t("booking.cancelNoRefund")}
			</p>
		) : null}
	</li>
);
```

`JoinButton`'s `className="self-start"` must be dropped now that its parent is a flex row — pass `className="w-full sm:w-auto"` instead.

- [ ] **Step 4: Run and pass**

```bash
cd dashboard && pnpm test -- src/features/booking/ && pnpm lint
```

- [ ] **Step 5: Commit**

```bash
git add src/features/booking/components/
git commit -m "feat: redesign SessionCard as a responsive grid"
```

---

### Task 9: Fix the cancel dialog's centering

**Files:**
- Modify: `dashboard/src/features/booking/components/CancelSessionDialog.tsx`, `CancelSessionDialog.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
it("centers without a direction-specific transform hack", async () => {
	await openDialog();
	const content = screen.getByRole("alertdialog");
	expect(content.className).not.toMatch(/rtl:translate/);
	expect(content.className).not.toMatch(/-translate-x-1\/2/);
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm test -- src/features/booking/components/CancelSessionDialog.test.tsx
```

- [ ] **Step 3: Replace the transform centering with a fixed grid**

On `AlertDialog.Overlay`, add the centering container:

```tsx
<AlertDialog.Overlay className="fixed inset-0 z-40 grid place-items-center bg-black/40 p-4" />
```

Radix portals `Content` as a sibling of `Overlay`, not a child, so the grid must go on a wrapper the content also lives in. Wrap both:

```tsx
<AlertDialog.Portal>
	<AlertDialog.Overlay className="fixed inset-0 z-40 bg-black/40" />
	<div className="fixed inset-0 z-50 grid place-items-center p-4 pointer-events-none">
		<AlertDialog.Content className="pointer-events-auto w-full max-w-sm rounded-lg border border-border bg-background p-6 shadow-lg">
			{/* unchanged children */}
		</AlertDialog.Content>
	</div>
</AlertDialog.Portal>
```

`pointer-events-none` on the wrapper with `pointer-events-auto` on the content keeps Radix's click-outside-to-dismiss working through the wrapper.

- [ ] **Step 4: Run, pass, commit**

```bash
cd dashboard && pnpm test -- src/features/booking/ && pnpm lint
git add src/features/booking/components/CancelSessionDialog.tsx src/features/booking/components/CancelSessionDialog.test.tsx
git commit -m "fix: center the cancel dialog without an RTL transform hack"
```

---

# Stage 4 — The call redesign

### Task 10: `SelfView` and `CallStage`

**Files:**
- Create: `dashboard/src/features/call/SelfView.tsx`, `SelfView.test.tsx`
- Create: `dashboard/src/features/call/CallStage.tsx`, `CallStage.test.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx`

**Interfaces:**
- Produces:

```tsx
export function SelfView(props: { stream: MediaStream | null }): JSX.Element;
export function CallStage(props: {
  remote: React.ReactNode;
  selfView: React.ReactNode;
  header: React.ReactNode;
  controls: React.ReactNode;
  banner?: React.ReactNode;
}): JSX.Element;
```

- [ ] **Step 1: Write the failing tests**

```tsx
// src/features/call/CallStage.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { CallStage } from "./CallStage";

const slots = {
	remote: <div>remote</div>,
	selfView: <div>self</div>,
	header: <div>header</div>,
	controls: <div>controls</div>,
};

describe("CallStage", () => {
	it("renders every slot", () => {
		render(<CallStage {...slots} />);
		for (const text of ["remote", "self", "header", "controls"]) {
			expect(screen.getByText(text)).toBeInTheDocument();
		}
	});

	it("sizes to the visible viewport, never 100vh", () => {
		render(<CallStage {...slots} />);
		const stage = screen.getByTestId("call-stage");
		expect(stage).toHaveClass("min-h-dvh");
		expect(stage.className).not.toMatch(/h-screen|100vh/);
	});

	it("drives the chrome offset from one custom property, not a magic number", () => {
		render(<CallStage {...slots} />);
		expect(screen.getByTestId("call-stage").style.getPropertyValue("--call-chrome-height")).not.toBe("");
	});

	it("omits the banner region entirely when there is nothing to say", () => {
		render(<CallStage {...slots} />);
		expect(screen.queryByTestId("call-banner")).not.toBeInTheDocument();
	});
});
```

```tsx
// src/features/call/SelfView.test.tsx
it("is fluid, not a fixed rectangle", () => {
	render(<SelfView stream={null} />);
	const el = screen.getByTestId("self-view");
	expect(el.className).toMatch(/clamp/);
	expect(el.className).toMatch(/aspect-video/);
	expect(el.className).not.toMatch(/\bh-32\b|\bw-48\b/);
});

it("positions on the inline axis logically so RTL mirrors", () => {
	render(<SelfView stream={null} />);
	expect(screen.getByTestId("self-view").className).toMatch(/inset-e-/);
});
```

- [ ] **Step 2: Run and watch them fail**

```bash
cd dashboard && pnpm test -- src/features/call/CallStage.test.tsx src/features/call/SelfView.test.tsx
```

- [ ] **Step 3: Implement `SelfView`**

```tsx
// src/features/call/SelfView.tsx
import { VideoTile } from "./VideoTile";

/**
 * The picture-in-picture self view.
 *
 * Fluid rather than a fixed rectangle: the old `h-32 w-48 sm:h-40 sm:w-56`
 * took the same share of a 1920px desktop as it did of a 360px phone held
 * sideways, where it covered a quarter of the lesson.
 *
 * It shrinks and never disappears. This is the only on-screen proof that your
 * own camera is working, so hiding it on a small viewport removes the one
 * thing that tells a parent the silence is not their end.
 *
 * `bottom` is calc'd off the stage's `--call-chrome-height`, replacing a
 * `bottom-20` tuned by hand to one control-bar height -- which is a number
 * that silently stops being true the moment the bar changes.
 */
export function SelfView({ stream }: { stream: MediaStream | null }) {
	return (
		<div
			data-testid="self-view"
			className="absolute inset-e-4 bottom-[calc(var(--call-chrome-height)+1rem)] w-[clamp(6rem,22vw,14rem)] aspect-video overflow-hidden rounded-lg border border-border shadow-lg"
		>
			<VideoTile stream={stream} muted data-testid="local-video" />
		</div>
	);
}
```

- [ ] **Step 4: Implement `CallStage`**

```tsx
// src/features/call/CallStage.tsx
import type * as React from "react";

/**
 * The call's layout, and nothing else -- no state, no effects.
 *
 * All chrome OVERLAYS the stage rather than occupying a strip of it. On a
 * phone held sideways (the way a 1-on-1 lesson is actually held) a fixed
 * control bar spent a fifth of the available height on three buttons.
 *
 * `--call-chrome-height` is declared once here and consumed by both the
 * control bar and `SelfView`, so the two cannot drift apart the way a
 * hardcoded `bottom-20` did.
 */
export function CallStage({
	remote,
	selfView,
	header,
	controls,
	banner,
}: {
	remote: React.ReactNode;
	selfView: React.ReactNode;
	header: React.ReactNode;
	controls: React.ReactNode;
	banner?: React.ReactNode;
}) {
	return (
		<div
			data-testid="call-stage"
			style={{ "--call-chrome-height": "5rem" } as React.CSSProperties}
			className="relative flex min-h-dvh flex-col bg-card text-foreground"
		>
			<div className="absolute inset-x-0 top-0 z-10 p-4">{header}</div>

			{banner ? (
				<div
					data-testid="call-banner"
					className="absolute inset-x-4 top-20 z-20 mx-auto max-w-md"
				>
					{banner}
				</div>
			) : null}

			<div className="relative flex-1">{remote}</div>

			{selfView}

			{/* Centered over the stage on a scrim. In short landscape -- a phone
			    held sideways -- it moves to the inline end as a column, which is
			    where a thumb actually rests. */}
			<div className="absolute inset-x-0 bottom-0 z-10 flex justify-center p-4 landscape:max-md:inset-x-auto landscape:max-md:inset-e-0 landscape:max-md:inset-y-0 landscape:max-md:items-center">
				<div className="rounded-full bg-background/80 p-2 backdrop-blur landscape:max-md:rounded-full">
					{controls}
				</div>
			</div>
		</div>
	);
}
```

- [ ] **Step 5: Make the controls stack in short landscape**

In `CallControls.tsx`, change the wrapper to:

```tsx
<div className="flex items-center justify-center gap-3 landscape:max-md:flex-col">
```

Nothing else in that file changes — the three buttons, their `aria-pressed` semantics and their labels stay exactly as they are.

- [ ] **Step 6: Rewire `CallRoom` to use the stage**

Replace the stage JSX with `<CallStage>`, passing `remote`, `selfView={<SelfView stream={props.localMedia.stream} />}`, `header`, `controls`, and `banner`. The remote tile gains `object-contain`:

```tsx
remote={
	room.remoteStream ? (
		<VideoTile
			stream={room.remoteStream}
			className="h-full w-full rounded-none object-contain"
			data-testid="remote-video"
			onAutoplayBlocked={room.onAutoplayBlocked}
		/>
	) : (
		<WaitingForPeer isTeacher={room.isTeacher} state={room.state} />
	)
}
```

`object-contain` is deliberate and overrides `VideoTile`'s own `object-cover` via the `className` prop — in a lesson, cropping the page the teacher is holding up is a worse failure than letterboxing.

- [ ] **Step 7: Run every call test, including the frozen ones**

```bash
cd dashboard && pnpm test && pnpm lint
git status --short src/features/call/VideoTile.test.tsx src/features/call/Lobby.test.tsx
```

Expected: PASS; both frozen files unmodified.

- [ ] **Step 8: Commit**

```bash
git add src/features/call/
git commit -m "feat: overlay call chrome on a fluid stage

Replaces a fixed control strip and a hardcoded bottom-20 self-view offset
with one --call-chrome-height property both consume, and lands the first
orientation handling this surface has ever had."
```

---

### Task 11: `CallStatus` — the visible identity header

**Files:**
- Create: `dashboard/src/features/call/CallStatus.tsx`, `CallStatus.test.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx`, `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`
- Modify: both `common.json`

**Interfaces:**
- Consumes: `useSessions()` from `@/features/booking`, `StatusChip` from `@/ui`.
- Produces: `export function CallStatus(props: { sessionId: number; state: PeerConnectionState; isTeacher: boolean }): JSX.Element;`

- [ ] **Step 1: Write the failing tests**

```tsx
// src/features/call/CallStatus.test.tsx
it("names the lesson and the other person", () => {
	renderStatus({ sessions: [{ ...base, id: 3, subject_name: "Tafsir", teacher_name: "Ustadh Bilal" }] });
	expect(screen.getByText("Tafsir")).toBeInTheDocument();
	expect(screen.getByText(/Ustadh Bilal/)).toBeInTheDocument();
});

it("falls back to the connection state alone on a cold deep-link", () => {
	// No cached session row -- someone opened the room URL directly.
	renderStatus({ sessions: [] });
	expect(screen.getByText(/connecting/i)).toBeInTheDocument();
	expect(screen.queryByTestId("call-identity")).not.toBeInTheDocument();
});

it("announces the connection state politely, not assertively", () => {
	renderStatus({ sessions: [] });
	const region = screen.getByRole("status");
	expect(region).toHaveAttribute("aria-live", "polite");
});

it("shows the teacher the student's name, not their own", () => {
	renderStatus({
		isTeacher: true,
		sessions: [{ ...base, id: 3, student_name: "Maryam", teacher_name: "Me" }],
	});
	expect(screen.getByText(/Maryam/)).toBeInTheDocument();
	expect(screen.queryByText(/Me/)).not.toBeInTheDocument();
});
```

- [ ] **Step 2: Run and watch them fail**

```bash
cd dashboard && pnpm test -- src/features/call/CallStatus.test.tsx
```

- [ ] **Step 3: Implement**

```tsx
// src/features/call/CallStatus.tsx
import { useTranslation } from "react-i18next";
import { useSessions } from "@/features/booking";
import { StatusChip } from "@/ui";
import type { PeerConnectionState } from "./usePeerConnection";

/**
 * The room's visible identity: which lesson, with whom, and how the
 * connection is doing.
 *
 * Until now the room's only `<h1>` was `sr-only`, so a sighted viewer had
 * nothing on screen telling them which of their children's lessons they were
 * looking at.
 *
 * The names come from the sessions query, NOT from the join grant: `JoinGrant`
 * carries `join_url`, `token`, `expires_at`, `ice_servers` and `is_teacher`
 * and no names at all. Extending the serializer would mean a backend change
 * for a cosmetic field. The cost is that a cold deep-link straight to this URL
 * has no cached row -- so the identity line is omitted rather than rendered
 * blank, and the connection chip stands alone.
 */
export function CallStatus({
	sessionId,
	state,
	isTeacher,
}: {
	sessionId: number;
	state: PeerConnectionState;
	isTeacher: boolean;
}) {
	const { t } = useTranslation();
	const { data } = useSessions();
	const session = data?.find((candidate) => candidate.id === sessionId);
	const counterpart = session
		? isTeacher
			? session.student_name
			: session.teacher_name
		: null;

	return (
		<div className="flex flex-wrap items-center gap-x-3 gap-y-1">
			{session ? (
				<div data-testid="call-identity" className="flex items-baseline gap-2">
					<h2 className="font-display text-base font-semibold">
						{session.subject_name}
					</h2>
					<p className="text-sm text-muted-foreground">
						{t(isTeacher ? "booking.withStudent" : "booking.withTeacher", {
							name: counterpart,
						})}
					</p>
				</div>
			) : null}
			<div role="status" aria-live="polite">
				<StatusChip tone={state === "connected" ? "live" : "neutral"}>
					{t(
						state === "reconnecting"
							? isTeacher
								? "call.stateReconnectingStudent"
								: "call.stateReconnectingTeacher"
							: state === "connected"
								? "call.stateConnected"
								: state === "failed"
									? "call.stateFailed"
									: "call.stateConnecting",
					)}
				</StatusChip>
			</div>
		</div>
	);
}
```

Note the reconnecting copy keys are chosen by *who is reading*, matching `reconnectingCopyKey` in `useCallRoom` — a teacher waiting on a student sees the "their connection dropped" wording.

- [ ] **Step 4: Pass `sessionId` from the route into `CallRoom`**

`CallRoom` needs the id for this header. Add `sessionId: number` to `CallRoomProps` and pass `Number(sessionId)` from `RoomPage`. It is the route's own param — no new fetch.

- [ ] **Step 5: Run, pass, commit**

```bash
cd dashboard && pnpm test && pnpm lint
git add src/features/call/ src/routes/_call/
git commit -m "feat: give the call room a visible identity header"
```

---

### Task 12: `WaitingForPeer`

**Files:**
- Create: `dashboard/src/features/call/WaitingForPeer.tsx`, `WaitingForPeer.test.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
it("tells a student who they are waiting for", () => {
	render(<WaitingForPeer isTeacher={false} state="connecting" />);
	expect(screen.getByText(/waiting for your teacher/i)).toBeInTheDocument();
});

it("tells a teacher who they are waiting for", () => {
	render(<WaitingForPeer isTeacher state="connecting" />);
	expect(screen.getByText(/waiting for your student/i)).toBeInTheDocument();
});

it("does not animate when motion is reduced", () => {
	render(<WaitingForPeer isTeacher={false} state="connecting" />);
	expect(screen.getByTestId("waiting-pulse")).toHaveClass("motion-reduce:animate-none");
});
```

- [ ] **Step 2: Run and watch it fail, then implement**

```tsx
// src/features/call/WaitingForPeer.tsx
import { UserRound } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { PeerConnectionState } from "./usePeerConnection";

/**
 * Shown while no remote track has arrived -- either nobody has joined yet, or
 * the connection dropped and `usePeerConnection` cleared the stale frame.
 *
 * "connecting" is the NORMAL state for this whole period, not a symptom: it is
 * where `usePeerConnection` starts and nothing moves it until the other peer
 * arrives. So this reads as waiting, not as an error.
 */
export function WaitingForPeer({
	isTeacher,
	state,
}: {
	isTeacher: boolean;
	state: PeerConnectionState;
}) {
	const { t } = useTranslation();
	return (
		<div className="flex h-full w-full flex-col items-center justify-center gap-4 p-6 text-center">
			<span
				data-testid="waiting-pulse"
				className="flex size-16 items-center justify-center rounded-full bg-secondary text-muted-foreground animate-pulse motion-reduce:animate-none"
			>
				<UserRound aria-hidden="true" className="size-8" />
			</span>
			<p className="text-base font-medium text-foreground">
				{t(isTeacher ? "call.waitingForStudent" : "call.waitingForTeacher")}
			</p>
			<p className="text-sm text-muted-foreground">
				{t(state === "failed" ? "call.stateFailed" : "call.stateConnecting")}
			</p>
		</div>
	);
}
```

- [ ] **Step 3: Run, pass, commit**

```bash
cd dashboard && pnpm test -- src/features/call/ && pnpm lint
git add src/features/call/WaitingForPeer.tsx src/features/call/WaitingForPeer.test.tsx src/features/call/CallRoom.tsx
git commit -m "feat: give the waiting state a face"
```

---

### Task 13: `CallEnded`

**Files:**
- Create: `dashboard/src/features/call/CallEnded.tsx`, `CallEnded.test.tsx`
- Modify: `dashboard/src/features/call/CallRoom.tsx`
- Test: the terminal-cleanup tests in `CallRoom.test.tsx` — **frozen**

- [ ] **Step 1: Write the failing test**

```tsx
it("offers retry only when the failure is retryable", () => {
	const { rerender } = render(
		<CallEnded terminal={{ titleKey: "call.roomFull" }} onLeave={() => {}} />,
	);
	expect(screen.queryByRole("button", { name: /try again/i })).not.toBeInTheDocument();
	rerender(
		<CallEnded
			terminal={{ titleKey: "call.connectionLostTitle", onRetry: () => {} }}
			onLeave={() => {}}
		/>,
	);
	expect(screen.getByRole("button", { name: /try again/i })).toBeInTheDocument();
});

it("always offers the way back to the schedule", () => {
	render(<CallEnded terminal={{ titleKey: "call.roomFull" }} onLeave={() => {}} />);
	expect(screen.getByRole("button", { name: /back to your schedule/i })).toBeInTheDocument();
});
```

The second test matters: a terminal screen with no way out is the dead end this component exists to prevent.

- [ ] **Step 2: Run, watch it fail, implement**

```tsx
// src/features/call/CallEnded.tsx
import { PhoneOff } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/ui";
import type { TerminalScreen } from "./useCallRoom";

/**
 * The end of a call, for every reason a call ends badly.
 *
 * The camera and microphone are ALREADY stopped by the time this renders --
 * `useCallRoom`'s terminal-cleanup effect does it on entering any terminal
 * state. A dead-end screen with a live camera behind it is the exact defect
 * class C3e existed to close; this component must never be the thing relied
 * on to prevent it.
 */
export function CallEnded({
	terminal,
	onLeave,
}: {
	terminal: TerminalScreen;
	onLeave: () => void;
}) {
	const { t } = useTranslation();
	return (
		<div className="flex min-h-dvh flex-col items-center justify-center gap-6 overflow-y-auto bg-background p-6 text-center text-foreground">
			<div className="flex w-full max-w-md flex-col items-center gap-4 rounded-lg border border-border bg-card p-8 shadow-sm">
				<span className="flex size-12 items-center justify-center rounded-full bg-secondary text-muted-foreground">
					<PhoneOff aria-hidden="true" className="size-6" />
				</span>
				<h2 className="font-display text-lg font-semibold">{t(terminal.titleKey)}</h2>
				{terminal.detailKey ? (
					<p className="text-sm text-muted-foreground">{t(terminal.detailKey)}</p>
				) : null}
				<div className="flex flex-wrap items-center justify-center gap-3">
					{terminal.onRetry ? (
						<Button variant="outline" onClick={terminal.onRetry}>
							{t("call.tryAgain")}
						</Button>
					) : null}
					<Button onClick={onLeave}>{t("call.backToSchedule")}</Button>
				</div>
			</div>
		</div>
	);
}
```

- [ ] **Step 3: Rewire `CallRoom` and verify the frozen tests**

```bash
cd dashboard && pnpm test && pnpm lint
git status --short src/features/call/CallRoom.test.tsx
```

Expected: PASS; `CallRoom.test.tsx` unmodified.

- [ ] **Step 4: Commit**

```bash
git add src/features/call/
git commit -m "feat: give terminal call states a real screen"
```

---

### Task 14: Fix the Lobby's clipping and lay it out in two columns

**Files:**
- Modify: `dashboard/src/features/call/Lobby.tsx`
- Test: `dashboard/src/features/call/Lobby.test.tsx` — **frozen**; new assertions go in a new file `Lobby.layout.test.tsx`

- [ ] **Step 1: Write the failing test in a NEW file**

The existing `Lobby.test.tsx` is frozen, so layout assertions live beside it rather than inside it.

```tsx
// src/features/call/Lobby.layout.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { Lobby } from "./Lobby";
import { fakeLocalMedia } from "./test-helpers";

describe("Lobby layout", () => {
	it("scrolls rather than clipping when it is taller than the viewport", () => {
		render(<Lobby localMedia={fakeLocalMedia()} onJoin={() => {}} />);
		const root = screen.getByTestId("lobby");
		// `min-h-dvh` + `justify-center` with no scroll container is the bug:
		// on a landscape phone the preview, both selects and Join are taller
		// than the viewport, and the top is cut off and unreachable.
		expect(root).toHaveClass("min-h-dvh", "overflow-y-auto");
		expect(root.className).not.toMatch(/\bjustify-center\b/);
		expect(screen.getByTestId("lobby-panel")).toHaveClass("m-auto");
	});

	it("uses two columns from md up", () => {
		render(<Lobby localMedia={fakeLocalMedia({ stream: new MediaStream() })} onJoin={() => {}} />);
		expect(screen.getByTestId("lobby-panel")).toHaveClass("md:grid-cols-2");
	});
});
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd dashboard && pnpm test -- src/features/call/Lobby.layout.test.tsx
```

- [ ] **Step 3: Change the layout only**

```tsx
<div
	data-testid="lobby"
	className="flex min-h-dvh flex-col overflow-y-auto bg-background p-6 text-foreground"
>
	<div
		data-testid="lobby-panel"
		className="m-auto grid w-full max-w-3xl gap-6 md:grid-cols-2 md:items-center"
	>
		{/* preview column, then the controls column */}
	</div>
</div>
```

`m-auto` on the inner panel centers it when it fits and lets it scroll when it does not — the fix for the clipping, without giving up centering.

**`handleEnable` does not move.** `start()` stays called synchronously inside the click handler. This task changes containers and classNames only; if you find yourself editing the handler, stop.

- [ ] **Step 4: Run everything, confirm the frozen file is untouched**

```bash
cd dashboard && pnpm test && pnpm lint
git status --short src/features/call/Lobby.test.tsx
```

Expected: PASS; `Lobby.test.tsx` unmodified. In particular the "requests the camera synchronously inside the click, not from an effect" test must still pass.

- [ ] **Step 5: Commit**

```bash
git add src/features/call/Lobby.tsx src/features/call/Lobby.layout.test.tsx
git commit -m "fix: the Lobby clipped its own content and could not scroll

min-h-dvh + justify-center with no scroll container means a landscape
phone cuts off the top of the panel with no way to reach it."
```

---

# Stage 5 — Gates

### Task 15: Extend the viewport guard to booking

**Files:**
- Modify: `dashboard/src/features/call/viewport-units.test.ts`

- [ ] **Step 1: Add the tree**

```ts
const HEIGHT_BEARING_TREES = [
	"src/routes",
	"src/features/call",
	// The session card and its dialog establish height on the schedule page.
	// A guard that only looks where it was pointed cannot catch the container
	// nobody thought to point it at.
	"src/features/booking",
];
```

- [ ] **Step 2: Run it**

```bash
cd dashboard && pnpm test -- src/features/call/viewport-units.test.ts
```

Expected: PASS. If it FAILS, a booking file pins `100vh` — fix the file, not the guard.

- [ ] **Step 3: Commit**

```bash
git add src/features/call/viewport-units.test.ts
git commit -m "test: extend the 100vh guard to src/features/booking"
```

---

### Task 16: e2e — the two things Playwright can honestly prove

**Files:**
- Create: `dashboard/e2e/session-ui.spec.ts`

Scope this honestly. Playwright at a phone-sized viewport proves layout rules fire at a width. It does not prove anything about iOS Safari.

- [ ] **Step 1: Write the spec**

```ts
// e2e/session-ui.spec.ts
import { expect, test } from "@playwright/test";
import { loginAs } from "./fixtures";

test.describe("session UI responsiveness", () => {
	test("the session card stacks its actions on a narrow viewport and rows them on a wide one", async ({ page }) => {
		await loginAs(page, "student");
		await page.setViewportSize({ width: 390, height: 844 });
		await page.goto("/schedule");

		const actions = page.getByTestId("session-card-actions").first();
		await expect(actions).toBeVisible();
		const narrow = await actions.boundingBox();

		await page.setViewportSize({ width: 1280, height: 900 });
		const wide = await actions.boundingBox();

		// Stacked actions are taller than they are wide relative to the row
		// layout; the row layout is wider and shorter. Comparing the SAME
		// element across two viewports is what makes this a real assertion
		// rather than a restatement of the class list.
		expect(narrow!.height).toBeGreaterThan(wide!.height);
	});

	test("the lobby scrolls instead of clipping on a short landscape viewport", async ({ page }) => {
		await loginAs(page, "student");
		await page.setViewportSize({ width: 844, height: 390 });
		await page.goto("/sessions/3/room");

		const lobby = page.getByTestId("lobby");
		await expect(lobby).toBeVisible();

		// The bug this guards: the panel's top was cut off above the viewport
		// with no way to reach it. Scrollable means reachable.
		const { scrollHeight, clientHeight } = await lobby.evaluate((el) => ({
			scrollHeight: el.scrollHeight,
			clientHeight: el.clientHeight,
		}));
		if (scrollHeight > clientHeight) {
			await lobby.evaluate((el) => el.scrollTo(0, 0));
			await expect(page.getByRole("heading", { level: 1 })).toBeInViewport();
		}
	});
});
```

- [ ] **Step 2: Run against a real stack**

```bash
cd dashboard && pnpm test:e2e -- session-ui.spec.ts
```

Expected: PASS. Session 3 is the standing joinable staging fixture; confirm the local seed provides an equivalent, and if it does not, create one in the spec's `beforeEach` rather than depending on staging data.

- [ ] **Step 3: Mutation-check both flows**

Revert the `sm:flex-row` on the actions container and confirm the first test goes red. Revert `overflow-y-auto` on the lobby and confirm the second goes red. Restore both. **A green e2e that cannot fail is not a gate** — this project has already shipped one of those.

- [ ] **Step 4: Commit**

```bash
git add e2e/session-ui.spec.ts
git commit -m "test: e2e for the session card's reflow and the lobby's scroll"
```

---

### Task 17: Ratchet the coverage floors

**Files:**
- Modify: `dashboard/vitest.config.ts`

- [ ] **Step 1: Measure**

```bash
cd dashboard && pnpm test -- --coverage
```

Record the four numbers exactly as reported.

- [ ] **Step 2: Raise the floors to just under the measurement**

Set each floor to the measured value rounded **down** to one decimal. Never round up — this repo has turned CI red twice by setting a floor above what the suite actually measures, and coverage.py's and vitest's rounding are not the same.

Current values are 95.5 lines / 91.6 branches / 87.2 functions / 95.5 statements. They may only go up.

- [ ] **Step 3: Verify the floor holds**

```bash
cd dashboard && pnpm test -- --coverage
```

Expected: PASS, not "PASS but the threshold warns".

- [ ] **Step 4: Commit**

```bash
git add vitest.config.ts
git commit -m "test: ratchet dashboard coverage floors after the session UI redesign"
```

---

### Task 18: The ADR, and the docs that close this out

**Files (meta repo, not the submodule):**
- Create: `docs/adr/NNNN-feature-components-split-hook-and-presentation.md`
- Modify: `docs/superpowers/journal/2026-W36.md`, `STATE.md`, `docs/superpowers/specs/2026-09-07-session-ui-redesign-design.md` (`status: shipped`, `closed:`)

- [ ] **Step 1: Write the ADR**

Use `/new-adr`. It records: a feature component that owns lifecycle logic splits into a `use<Feature>` hook returning a view model plus stateless components; the hook is where effects and refs live; the components take props and render. The consequence to record honestly is the one this plan is built around — **an extraction is only safe when the existing suite passes unmodified**, which is what makes the pattern adoptable rather than a licence to rewrite.

- [ ] **Step 2: Append to the journal**

Record both deviations by name: **preview mode has not run** (`STATE.md` calls it a non-optional gate before opening any further spec) and **D10** would ordinarily forbid restructuring while redesigning — chosen deliberately, with the risk stated and accepted. Record the **D9 deviation** too: no click-through on iOS Safari is possible in this project.

- [ ] **Step 3: Update `STATE.md`**

`active_spec` moves to the redesign and then to shipped. Say plainly what is and is not verified: the responsive behaviour is verified in Chromium at two viewport sizes and **nowhere else**.

- [ ] **Step 4: Bump the submodule pointer and open the meta PR**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add dashboard docs STATE.md
git commit -m "docs: close the session UI redesign, and bump dashboard"
```

Remember a merge to meta `master` **is a deploy**, and a deploy drops every call in progress. Merge between lessons.

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: the restructure table → Tasks 1, 3, 5, 10–13; the promoted primitives → Tasks 3, 4, 6; the schedule list → Tasks 7–9; the call room → Tasks 10–14; sequencing and the freeze → Tasks 1, 2 and the Global Constraints; the test plan → Tasks 15–17; the deviations → Task 18.

**One gap found and closed while reviewing:** the spec lists `DeviceSelect` as serving an in-room device picker, but no task adds one to the call room. That is deliberate — an in-room picker is new functionality, not a redesign of something that exists, and it belongs to its own spec. `DeviceSelect` is still worth extracting in Task 3 because the Lobby renders that markup twice today.

**Type consistency.** `TerminalScreen` is defined in Task 1 and consumed in Task 13 under the same name and shape. `MediaFailure` comes from `useLocalMedia` throughout. `FAILURE_MESSAGE_KEY` moves from `Lobby` to `MediaFailureAlert` in Task 3, and Task 3 Step 9 updates `CallRoom`'s import — no task references the old location afterwards. `formatRelative` is named identically in Task 4's definition and its `JoinButton` and `SessionCard` consumers.

**Ordering.** Task 11 adds `sessionId` to `CallRoomProps`; nothing before it depends on that prop. Task 10 references `WaitingForPeer`, which Task 12 creates — so Task 10 Step 6 leaves the existing inline waiting markup in place and Task 12 substitutes the component. Execute 10 before 12, not the reverse.
