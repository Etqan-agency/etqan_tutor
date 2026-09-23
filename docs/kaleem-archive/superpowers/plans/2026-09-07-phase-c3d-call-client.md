# Phase C3d — The Call Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a student and a teacher see and hear each other — the first phase of this project whose output is an actual video call.

**Architecture:** A full-bleed authenticated route mints its own short-lived join grant, opens the C3b signaling socket carrying the capability token in `Sec-WebSocket-Protocol`, and drives an `RTCPeerConnection` configured with the C3c TURN servers. The teacher always sends the offer and the student always answers, which makes glare unreachable and needs no change to the four-message signaling protocol. Three hooks own all the state machines (`useLocalMedia`, `useSignaling`, `usePeerConnection`); the components own none, which is what makes the connection logic testable without a browser.

**Tech Stack:** React 19, TanStack Router (file-based routes) + TanStack Query, zod, Tailwind v4 with `@kaleem/tokens`, Vitest + Testing Library, Playwright (Chromium), Django/DRF on the backend.

**Spec:** `docs/superpowers/specs/2026-09-07-phase-c3d-call-client-design.md`

## Global Constraints

- **Three repos, three branches, three PRs.** `backend` (`feat/phase-c3d-is-teacher`), `dashboard` (`feat/phase-c3d-call-client`), then a meta PR carrying docs + submodule pointer bumps. Trunk is `main` in submodules, `master` in meta (ADR-0028). Never commit to a trunk. Never `--no-verify`; if pre-commit fails on the dead pip proxy, use `PIP_CONFIG_FILE=/dev/null git commit …`.
- **Coverage floors are ratchets (ADR-0026), and may only rise.** Backend `fail_under = 97.7` in `backend/pyproject.toml`; measure with `pytest --cov=kaleem --cov=signaling`, **never a bare `pytest --cov`**. Dashboard floors are `93.6 / 90.4 / 86.6 / 93.6` in `vitest.config.ts`. Do not remove `precision = 1`. Note a measured total *above* the floor does not always permit raising it — see the ISSUES entry on coverage.py's rounding.
- **The C3b signaling protocol does not change.** Exactly four message types: `peer-joined`, `peer-left`, `offer`, `answer`, `ice`. A design needing a fifth is wrong.
- **The token rides `Sec-WebSocket-Protocol` as `[SUBPROTOCOL, token]`, protocol name FIRST.** `SUBPROTOCOL` is the exact string `kaleem.signaling.v1`. Reversed order is treated by the server as "no offer". The token never goes in a URL, never in `localStorage`/`sessionStorage`.
- **Close codes:** 4400 bad message, 4401 unauthorized, 4409 room full, 4410 replaced. **4410 must never trigger reconnection.**
- **a11y / i18n / RTL are a repo-wide baseline**, not per-feature. Every user-visible string goes in `src/locales/{en,ar}/common.json` under a new `call` namespace. Layout uses logical properties (`inset-e-*`, `inset-b-*`, `ms-*`, `me-*`) so RTL mirrors without a second rule. Controls are real `<button>`s, keyboard reachable, toggles carry `aria-pressed`, connection state lives in an `aria-live` region.
- **Style values come from design tokens** (semantic Tailwind utilities), never hardcoded hex or `color-mix`.
- **No `print()`, no bare `except Exception`, typed exceptions only, business logic in service modules** (backend, CLAUDE.md).
- **Out of scope, reject as scope creep:** Safari/iOS handling (C3e), screen sharing, recording, group calls, in-call chat, network-quality UI, persisting device choices.

---

### Task 1: The backend tells the client which side it is

The "teacher offers" rule needs the client to know whether *this viewer* is the teacher of *this session*. Nothing says so today, and `SessionSerializer`'s own comment explains a client cannot derive it — the payload carries names, not ids.

**Files:**
- Modify: `backend/kaleem/scheduling/providers/__init__.py` (`JoinGrant`)
- Modify: `backend/kaleem/scheduling/providers/signaling_provider.py`
- Modify: `backend/kaleem/scheduling/providers/fake_provider.py`
- Modify: `backend/kaleem/scheduling/api/booking_serializers.py`
- Test: `backend/kaleem/scheduling/tests/test_signaling_provider.py`, `test_rooms_api.py`

**Interfaces:**
- Consumes: `Participant.is_teacher` (exists), `signaling.tokens.RoomToken.is_teacher` (exists).
- Produces: `JoinGrant(join_url, expires_at, ice_servers=(), token="", is_teacher=False)`; the join response body gains `is_teacher: bool`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/scheduling/tests/test_signaling_provider.py`. Read the file first — it already defines `SECRET`, a `SIGNALING` settings dict used as `@override_settings(**SIGNALING)`, and a `room_request` fixture. Reuse them; do not reintroduce per-test override kwargs.

```python
@override_settings(**SIGNALING)
def test_the_grant_says_whether_this_participant_is_the_teacher(room_request):
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)

    teacher = provider.get_join_url(
        room,
        Participant(user_id=8, display_name="Ustadh", is_teacher=True),
        expires_at=expires_at,
    )
    student = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=expires_at,
    )

    assert teacher.is_teacher is True
    assert student.is_teacher is False


@override_settings(**SIGNALING)
def test_the_grant_field_and_the_token_claim_cannot_disagree(room_request):
    """One source of truth for who offers.

    The client reads `is_teacher` off the grant; the signaling service reads
    it off the token. If those two are computed independently they can drift,
    and a room ends up with two offerers or none -- a failure that looks like
    "the call just doesn't start" and is invisible in every log.
    """
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    for uid, teacher in ((8, True), (7, False)):
        grant = provider.get_join_url(
            room,
            Participant(user_id=uid, display_name="X", is_teacher=teacher),
            expires_at=timezone.now() + dt.timedelta(minutes=30),
        )
        assert grant.is_teacher is verify(grant.token, SECRET, now=0).is_teacher
```

Append to `backend/kaleem/scheduling/tests/test_video_providers.py`:

```python
def test_the_fake_provider_reports_the_participants_role_too():
    """The fake stands in for the real provider in every test and in CI, so a
    field it silently omits is a field the dashboard never sees under test."""
    provider = FakeVideoProvider()
    room = provider.create_room(
        RoomRequest(
            session_id=1,
            subject_name="Quran",
            starts_at=timezone.now(),
            duration_minutes=60,
        )
    )
    grant = provider.get_join_url(
        room,
        Participant(user_id=1, display_name="X", is_teacher=True),
        expires_at=timezone.now(),
    )
    assert grant.is_teacher is True
```

Append to `backend/kaleem/scheduling/tests/test_rooms_api.py` — read the file and reuse its real fixtures (`session`, `student`, `teacher`, `client_for`), the same ones `test_a_participant_gets_a_join_url` uses:

```python
def test_the_join_response_reports_the_viewers_role(client_for, session, student, teacher):
    student_body = client_for(student).post(
        f"/api/v1/scheduling/sessions/{session.id}/join/"
    ).json()
    teacher_body = client_for(teacher).post(
        f"/api/v1/scheduling/sessions/{session.id}/join/"
    ).json()

    assert student_body["is_teacher"] is False
    assert teacher_body["is_teacher"] is True
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_signaling_provider.py kaleem/scheduling/tests/test_video_providers.py kaleem/scheduling/tests/test_rooms_api.py -v
```
Expected: FAIL — `JoinGrant` has no attribute `is_teacher`, and `KeyError: 'is_teacher'` on the response bodies.

- [ ] **Step 3: Implement**

In `providers/__init__.py`, add to `JoinGrant`:

```python
    # Which side of the lesson this grant is for. The client needs it to know
    # whether to send the offer or wait for one (the teacher offers; see the
    # C3d spec), and it CANNOT derive it: the session payload carries names,
    # not ids, and the viewer's roles do not answer it -- someone may be both
    # a parent and the teacher on the same row. Sourced from the same
    # `Participant` that mints the token claim, so the two cannot disagree
    # about who offers.
    is_teacher: bool = False
```

In `signaling_provider.py`'s `get_join_url`, pass `is_teacher=participant.is_teacher` to the returned `JoinGrant`. Do the same in `fake_provider.py`.

In `booking_serializers.py`, add to `JoinGrantSerializer`:

```python
    is_teacher = serializers.BooleanField()
```

- [ ] **Step 4: Run the full suite and the linters**

```bash
cd backend && pytest -q && ruff check . && mypy kaleem signaling && lint-imports
```
Expected: all pass, all clean.

- [ ] **Step 5: Commit, push, open the PR**

```bash
cd backend && git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): the join grant says which side of the lesson it is for (C3d)"
git push -u origin feat/phase-c3d-is-teacher
gh pr create --base main --title "C3d: is_teacher on the join grant" --body "Implements the backend half of docs/superpowers/specs/2026-09-07-phase-c3d-call-client-design.md. The client cannot derive which side it is on; this states it, from the same Participant that mints the token claim."
```

---

### Task 2: A full-bleed authenticated layout, and the room route

`_authed` wraps every child in `AppShell`. A call needs the viewport, so it needs a sibling layout with the same guard and no shell — and the guard must not be duplicated, or the two can drift apart.

**Files:**
- Create: `dashboard/src/routes/_call.tsx`
- Create: `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`
- Create: `dashboard/src/features/identity/require-auth.ts`
- Modify: `dashboard/src/routes/_authed.tsx`
- Modify: `dashboard/src/features/booking/components/JoinButton.tsx`
- Modify: `dashboard/src/features/booking/components/JoinButton.test.tsx`
- Test: `dashboard/src/routes/_call/sessions.$sessionId.room.test.tsx`

**Interfaces:**
- Consumes: `ensureAuthed(queryClient)` from `@/features/identity/queries` (exists).
- Produces: `requireAuth(context)` — the shared `beforeLoad` body; route path `/sessions/$sessionId/room`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/routes/_call/sessions.$sessionId.room.test.tsx`. Read `src/routes/_authed/availability.test.tsx` first and follow its router-harness pattern exactly (it renders a route through a test router); mirror it rather than inventing a second harness.

```tsx
it("renders the room without the app shell", async () => {
	renderRoomRoute({ sessionId: "1" });
	// The nav landmark is AppShell's; a call route that renders it has been
	// hung under the wrong layout and will fight the video for the viewport.
	expect(screen.queryByRole("navigation")).not.toBeInTheDocument();
	expect(await screen.findByRole("heading", { name: /lesson/i })).toBeVisible();
});
```

Modify `JoinButton.test.tsx`: replace the assertion that clicking calls `window.open` with one asserting it navigates to `/sessions/<id>/room`. Read the file first for how it currently mocks `useJoinSession` and adapt.

```tsx
it("navigates to the room instead of opening a tab", async () => {
	const user = userEvent.setup();
	renderJoinButton({ session: joinableSession });
	await user.click(screen.getByRole("button", { name: /join/i }));
	expect(navigate).toHaveBeenCalledWith({
		to: "/sessions/$sessionId/room",
		params: { sessionId: "1" },
	});
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/routes/_call src/features/booking/components/JoinButton.test.tsx
```
Expected: FAIL — the route module does not exist; `JoinButton` still calls `window.open`.

- [ ] **Step 3: Implement**

Create `src/features/identity/require-auth.ts`:

```ts
import { redirect } from "@tanstack/react-router";
import { ensureAuthed } from "./queries";

/**
 * The authenticated-route guard, in one place.
 *
 * Both `_authed` (the app shell) and `_call` (full-bleed, for a lesson) need
 * exactly this. Duplicating it would let the two drift, and the drift that
 * matters is the silent direction: a call route that forgets to redirect
 * renders a room to a logged-out visitor.
 */
export async function requireAuth(context: {
	queryClient: Parameters<typeof ensureAuthed>[0];
}): Promise<void> {
	try {
		await ensureAuthed(context.queryClient);
	} catch {
		throw redirect({ to: "/login" });
	}
}
```

Rewrite `src/routes/_authed.tsx`'s `beforeLoad` to `({ context }) => requireAuth(context)`, leaving its `component` untouched.

Create `src/routes/_call.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireAuth } from "@/features/identity/require-auth";

/**
 * Authenticated, but WITHOUT `AppShell`.
 *
 * A 1-on-1 lesson wants the whole viewport, and nav chrome around a video
 * call is wasted space on desktop and unusable on a phone in landscape. Same
 * guard as `_authed` -- deliberately the shared one, not a copy.
 */
export const Route = createFileRoute("/_call")({
	beforeLoad: ({ context }) => requireAuth(context),
	component: () => <Outlet />,
});
```

Create `src/routes/_call/sessions.$sessionId.room.tsx` rendering, for now, a heading naming the lesson. Later tasks replace its body; keep it minimal here so this task's deliverable is exactly "the route exists, is guarded, and has no shell".

In `JoinButton.tsx`: delete `handleJoin`'s call to `join.mutateAsync` and `window.open`, delete the now-unused `useJoinSession` import, and navigate instead:

```tsx
const navigate = useNavigate();
// The ROUTE mints the grant, not this button. A grant is short-lived, so one
// minted here would already be stale after a reload of the room -- and
// minting on the route keeps the token out of anything that could carry it,
// which is the whole reason C3c moved it off the URL.
function handleJoin() {
	navigate({ to: "/sessions/$sessionId/room", params: { sessionId: String(session.id) } });
}
```
Keep the countdown, the `active` computation and the disabled logic exactly as they are — they are correct and tested.

- [ ] **Step 4: Run tests, lint and typecheck**

```bash
cd dashboard && pnpm vitest run && pnpm lint && pnpm tsc --noEmit
```
Expected: all pass. The route tree is generated — if `routeTree.gen.ts` is stale, run the dev server once or `pnpm build` to regenerate, and commit it.

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add -A
git commit -m "feat(call): a full-bleed authenticated room route (C3d)"
```

---

### Task 3: `useLocalMedia` — the camera, the microphone, and every way they fail

**Files:**
- Create: `dashboard/src/features/call/useLocalMedia.ts`
- Test: `dashboard/src/features/call/useLocalMedia.test.ts`

**Interfaces:**
- Produces:
  - `type MediaFailure = "denied" | "not-found" | "in-use" | "unknown"`
  - `useLocalMedia(deps: { getUserMedia, enumerateDevices })` → `{ stream, failure, devices: {cameras, microphones}, selectedCameraId, selectedMicrophoneId, selectCamera(id), selectMicrophone(id), retry(), stop() }`

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/call/useLocalMedia.test.ts`:

```ts
import { act, renderHook, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { useLocalMedia } from "./useLocalMedia";

function domError(name: string) {
	const e = new Error(name);
	e.name = name;
	return e;
}

const fakeStream = () => ({ getTracks: () => [], getVideoTracks: () => [], getAudioTracks: () => [] }) as unknown as MediaStream;

it.each([
	["NotAllowedError", "denied"],
	["NotFoundError", "not-found"],
	["NotReadableError", "in-use"],
	["SomethingElseError", "unknown"],
])("maps %s to the %s failure", async (name, expected) => {
	const { result } = renderHook(() =>
		useLocalMedia({
			getUserMedia: vi.fn().mockRejectedValue(domError(name)),
			enumerateDevices: vi.fn().mockResolvedValue([]),
		}),
	);
	await waitFor(() => expect(result.current.failure).toBe(expected));
});

it("retries an over-constrained request with default constraints instead of failing", async () => {
	// A device that cannot do the requested resolution must not cost the user
	// their lesson. Falling back is the difference between "your camera is
	// unsupported" and a working call at whatever the camera can manage.
	const getUserMedia = vi
		.fn()
		.mockRejectedValueOnce(domError("OverconstrainedError"))
		.mockResolvedValueOnce(fakeStream());
	const { result } = renderHook(() =>
		useLocalMedia({ getUserMedia, enumerateDevices: vi.fn().mockResolvedValue([]) }),
	);
	await waitFor(() => expect(result.current.stream).not.toBeNull());
	expect(result.current.failure).toBeNull();
	expect(getUserMedia).toHaveBeenCalledTimes(2);
});

it("recovers after a denial without a reload", async () => {
	const getUserMedia = vi
		.fn()
		.mockRejectedValueOnce(domError("NotAllowedError"))
		.mockResolvedValueOnce(fakeStream());
	const { result } = renderHook(() =>
		useLocalMedia({ getUserMedia, enumerateDevices: vi.fn().mockResolvedValue([]) }),
	);
	await waitFor(() => expect(result.current.failure).toBe("denied"));
	await act(async () => { await result.current.retry(); });
	await waitFor(() => expect(result.current.failure).toBeNull());
});

it("stops every track when stopped, so the camera light goes out", async () => {
	// A hook that leaves tracks live keeps the camera indicator on after the
	// lesson ends, which users read -- correctly -- as being recorded.
	const stop = vi.fn();
	const stream = { getTracks: () => [{ stop }], getVideoTracks: () => [], getAudioTracks: () => [] } as unknown as MediaStream;
	const { result } = renderHook(() =>
		useLocalMedia({
			getUserMedia: vi.fn().mockResolvedValue(stream),
			enumerateDevices: vi.fn().mockResolvedValue([]),
		}),
	);
	await waitFor(() => expect(result.current.stream).not.toBeNull());
	act(() => result.current.stop());
	expect(stop).toHaveBeenCalled();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useLocalMedia.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `useLocalMedia.ts`. Take `getUserMedia` and `enumerateDevices` as injected dependencies defaulting to the real browser APIs, so tests never touch a real device:

```ts
export type MediaFailure = "denied" | "not-found" | "in-use" | "unknown";

// DOMException names are the only machine-readable thing getUserMedia gives
// us; the message is localised by the browser and unusable. Each maps to a
// DIFFERENT instruction for the user, which is why this is a table and not a
// boolean -- "allow camera access" and "close the app using your camera" are
// not interchangeable advice.
const FAILURES: Record<string, MediaFailure> = {
	NotAllowedError: "denied",
	PermissionDeniedError: "denied",
	NotFoundError: "not-found",
	DevicesNotFoundError: "not-found",
	NotReadableError: "in-use",
	TrackStartError: "in-use",
};
```

`OverconstrainedError` is deliberately absent from that table: it is retried once with bare `{ video: true, audio: true }` before any failure is reported. Enumerate devices only *after* a successful grant — labels are empty before permission, so a picker built earlier shows blank entries.

- [ ] **Step 4: Run to verify they pass**

```bash
cd dashboard && pnpm vitest run src/features/call/useLocalMedia.test.ts && pnpm tsc --noEmit
```
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add src/features/call
git commit -m "feat(call): local media with named failure states (C3d)"
```

---

### Task 4: `useSignaling` — the socket, and the close codes

**Files:**
- Create: `dashboard/src/features/call/useSignaling.ts`
- Test: `dashboard/src/features/call/useSignaling.test.ts`

**Interfaces:**
- Produces:
  - `export const SUBPROTOCOL = "kaleem.signaling.v1"`
  - `type SignalMessage = {type:"peer-joined"} | {type:"peer-left"} | {type:"offer"|"answer", sdp: RTCSessionDescriptionInit} | {type:"ice", candidate: RTCIceCandidateInit}`
  - `type SocketFailure = "unauthorized" | "room-full" | "replaced" | "bad-message" | "lost"`
  - `useSignaling({url, token, onMessage, createSocket})` → `{ send(msg), failure, connected }`

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/call/useSignaling.test.ts`. Build a `FakeSocket` class exposing `onopen/onmessage/onclose`, a `sent: string[]` array, and a `close(code)` helper that invokes `onclose` with that code.

```ts
it("offers the protocol name first and the token second", () => {
	// Reversed, the server treats the offer as absent and refuses with 4401.
	// The order is the contract; this test is what stops someone "tidying"
	// the array.
	const created: Array<[string, string[]]> = [];
	renderHook(() => useSignaling({ url: "wss://x/ws/rooms/r", token: "tok",
		onMessage: vi.fn(),
		createSocket: (u, p) => { created.push([u, p]); return new FakeSocket(); } }));
	expect(created[0][1]).toEqual(["kaleem.signaling.v1", "tok"]);
});

it.each([
	[4401, "unauthorized"],
	[4409, "room-full"],
	[4410, "replaced"],
	[4400, "bad-message"],
	[1006, "lost"],
])("maps close code %i to %s", async (code, expected) => {
	const socket = new FakeSocket();
	const { result } = renderHook(() => useSignaling({ url: "u", token: "t",
		onMessage: vi.fn(), createSocket: () => socket }));
	act(() => socket.close(code));
	await waitFor(() => expect(result.current.failure).toBe(expected));
});

it("never reconnects after 4410", async () => {
	// 4410 means THIS participant opened a newer socket somewhere else. A
	// client that retries makes two tabs evict each other forever, and both
	// look healthy while doing it -- no error, no log, just a call that
	// flaps.
	let created = 0;
	const socket = new FakeSocket();
	renderHook(() => useSignaling({ url: "u", token: "t", onMessage: vi.fn(),
		createSocket: () => { created += 1; return socket; } }));
	act(() => socket.close(4410));
	await new Promise(r => setTimeout(r, 50));
	expect(created).toBe(1);
});

it("reconnects after an unexpected drop", async () => {
	let created = 0;
	const socket = new FakeSocket();
	renderHook(() => useSignaling({ url: "u", token: "t", onMessage: vi.fn(),
		createSocket: () => { created += 1; return socket; } }));
	act(() => socket.close(1006));
	await waitFor(() => expect(created).toBeGreaterThan(1));
});

it("ignores a frame it does not recognise instead of crashing the call", () => {
	const onMessage = vi.fn();
	const socket = new FakeSocket();
	renderHook(() => useSignaling({ url: "u", token: "t", onMessage, createSocket: () => socket }));
	act(() => socket.receive('{"type":"who-knows"}'));
	act(() => socket.receive("not json at all"));
	expect(onMessage).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/useSignaling.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Reconnection: exponential backoff starting at 500ms, capped at 5 attempts, and **only** for codes that are not 4401/4409/4410. Those three are terminal — they describe a state that retrying cannot change.

- [ ] **Step 4: Run to verify they pass**

```bash
cd dashboard && pnpm vitest run src/features/call/useSignaling.test.ts && pnpm tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add src/features/call
git commit -m "feat(call): signaling socket with terminal close codes (C3d)"
```

---

### Task 5: `usePeerConnection` — who offers, and what connected means

**Files:**
- Create: `dashboard/src/features/call/usePeerConnection.ts`
- Test: `dashboard/src/features/call/usePeerConnection.test.ts`

**Interfaces:**
- Consumes: `SignalMessage` and `SUBPROTOCOL` from Task 4; `ice_servers` from the grant.
- Produces: `usePeerConnection({iceServers, isTeacher, localStream, send, createPeerConnection})` → `{ remoteStream, state: "connecting"|"connected"|"reconnecting"|"failed", handleSignal(msg), close() }`

- [ ] **Step 1: Write the failing tests**

Build a `FakePeerConnection` exposing `createOffer/createAnswer/setLocalDescription/setRemoteDescription/addTrack/addIceCandidate/restartIce/close`, plus settable `connectionState` and an `emit(event)` helper.

```ts
it("the teacher offers when the peer joins", async () => {
	const send = vi.fn();
	const { result } = renderHook(() => usePeerConnection({ ...base, isTeacher: true, send }));
	await act(async () => { await result.current.handleSignal({ type: "peer-joined" }); });
	expect(send).toHaveBeenCalledWith(expect.objectContaining({ type: "offer" }));
});

it("the student does not offer when the peer joins", async () => {
	// Both sides receive `peer-joined`. If both offered, the two offers
	// collide and the call fails to establish in a way that looks like a
	// network problem. Exactly one side offering is what makes glare
	// unreachable.
	const send = vi.fn();
	const { result } = renderHook(() => usePeerConnection({ ...base, isTeacher: false, send }));
	await act(async () => { await result.current.handleSignal({ type: "peer-joined" }); });
	expect(send).not.toHaveBeenCalled();
});

it("the student answers an offer", async () => {
	const send = vi.fn();
	const { result } = renderHook(() => usePeerConnection({ ...base, isTeacher: false, send }));
	await act(async () => {
		await result.current.handleSignal({ type: "offer", sdp: { type: "offer", sdp: "x" } });
	});
	expect(send).toHaveBeenCalledWith(expect.objectContaining({ type: "answer" }));
});

it("the teacher re-offers when the peer rejoins", async () => {
	// A student who reconnects produces a second `peer-joined` on the
	// teacher's side; that is the ONLY renegotiation trigger in normal use,
	// and it is why no extra message type is needed.
	const send = vi.fn();
	const { result } = renderHook(() => usePeerConnection({ ...base, isTeacher: true, send }));
	await act(async () => { await result.current.handleSignal({ type: "peer-joined" }); });
	await act(async () => { await result.current.handleSignal({ type: "peer-joined" }); });
	expect(send.mock.calls.filter(c => c[0].type === "offer")).toHaveLength(2);
});

it("reports failed only after ICE restarts are exhausted", async () => {
	const pc = new FakePeerConnection();
	const { result } = renderHook(() => usePeerConnection({ ...base, isTeacher: true, createPeerConnection: () => pc }));
	act(() => { pc.connectionState = "failed"; pc.emit("connectionstatechange"); });
	await waitFor(() => expect(result.current.state).toBe("reconnecting"));
	expect(pc.restartIce).toHaveBeenCalled();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/usePeerConnection.test.ts
```

- [ ] **Step 3: Implement**

Map `pc.connectionState`: `new`/`connecting` → `connecting`; `connected` → `connected`; `disconnected`/`failed` → `reconnecting` while restart attempts remain, then `failed`. Only the teacher calls `restartIce()`; the student waits for the resulting offer, which keeps the single-offerer rule intact under recovery too.

- [ ] **Step 4: Run to verify they pass**

```bash
cd dashboard && pnpm vitest run src/features/call/usePeerConnection.test.ts && pnpm tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add src/features/call
git commit -m "feat(call): peer connection with a single deterministic offerer (C3d)"
```

---

### Task 6: The lobby

**Files:**
- Create: `dashboard/src/features/call/Lobby.tsx`
- Create: `dashboard/src/features/call/Lobby.test.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

**Interfaces:**
- Consumes: `useLocalMedia` (Task 3).
- Produces: `<Lobby onJoin={() => void} />`.

- [ ] **Step 1: Write the failing tests**

```tsx
it("shows the local preview and lets you pick devices", async () => {
	renderLobby();
	expect(await screen.findByLabelText(/camera/i)).toBeInTheDocument();
	expect(screen.getByLabelText(/microphone/i)).toBeInTheDocument();
});

it("refuses to join while media has failed", async () => {
	// Entering with no media is how the other person ends up watching a black
	// rectangle. The lobby exists precisely to stop that.
	renderLobby({ failure: "denied" });
	expect(await screen.findByRole("button", { name: /join now/i })).toBeDisabled();
});

it("explains a denial and offers a retry that does not reload", async () => {
	const retry = vi.fn();
	renderLobby({ failure: "denied", retry });
	await userEvent.setup().click(screen.getByRole("button", { name: /try again/i }));
	expect(retry).toHaveBeenCalled();
});

it("offers joining without a camera when none is found", async () => {
	renderLobby({ failure: "not-found" });
	expect(await screen.findByText(/no camera or microphone/i)).toBeVisible();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call/Lobby.test.tsx
```

- [ ] **Step 3: Implement**

Add a `call` namespace to both locale files with every string used (`call.lobbyTitle`, `call.joinNow`, `call.camera`, `call.microphone`, `call.deniedTitle`, `call.deniedHelp`, `call.tryAgain`, `call.noDevice`, `call.deviceBusy`, …). Translate the Arabic properly — do not paste the English. The preview `<video>` is `muted` and `playsInline`; a self-view that is not muted feeds the microphone back into the room.

- [ ] **Step 4: Run tests, lint, typecheck**

```bash
cd dashboard && pnpm vitest run && pnpm lint && pnpm tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add -A
git commit -m "feat(call): a lobby that catches device failures before the lesson (C3d)"
```

---

### Task 7: The room — tiles, controls, and the wiring

**Files:**
- Create: `dashboard/src/features/call/VideoTile.tsx`, `CallControls.tsx`, `CallRoom.tsx`
- Create: `dashboard/src/features/call/CallRoom.test.tsx`, `CallControls.test.tsx`
- Modify: `dashboard/src/routes/_call/sessions.$sessionId.room.tsx`
- Modify: both locale files

**Interfaces:**
- Consumes: all three hooks, plus `useJoinSession` for the grant.
- Produces: the finished route.

- [ ] **Step 1: Write the failing tests**

```tsx
it("names who we are waiting for instead of showing a black rectangle", async () => {
	renderCallRoom({ remoteStream: null });
	expect(await screen.findByText(/waiting for/i)).toBeVisible();
});

it("announces connection state to assistive tech", async () => {
	renderCallRoom({ state: "reconnecting" });
	const live = await screen.findByRole("status");
	expect(live).toHaveTextContent(/reconnect/i);
});

it("mute is a toggle, not a one-way trip", async () => {
	const user = userEvent.setup();
	renderCallRoom();
	const mic = screen.getByRole("button", { name: /microphone/i });
	expect(mic).toHaveAttribute("aria-pressed", "false");
	await user.click(mic);
	expect(mic).toHaveAttribute("aria-pressed", "true");
});

it("muting disables the track rather than dropping the connection", async () => {
	// `track.enabled = false` is instant and keeps the peer connection warm.
	// Renegotiating to mute would drop and rebuild media for a button press.
	const track = { kind: "audio", enabled: true, stop: vi.fn() };
	const user = userEvent.setup();
	renderCallRoom({ localTracks: [track] });
	await user.click(screen.getByRole("button", { name: /microphone/i }));
	expect(track.enabled).toBe(false);
});

it("plays the remote track without waiting for a gesture", async () => {
	// Browsers block autoplay of UNMUTED media without a user gesture, and
	// the failure is silent -- a still frame and no sound, with nothing in
	// the console. The Join click is the gesture, so this must hold; if it
	// ever stops holding, the symptom is indistinguishable from "the other
	// person's camera is off".
	const play = vi.fn().mockResolvedValue(undefined);
	renderCallRoom({ remoteStream: fakeStream(), videoPlay: play });
	await waitFor(() => expect(play).toHaveBeenCalled());
	expect(screen.getByTestId("remote-video")).not.toHaveAttribute("muted");
});

it.each([
	["room-full", /already in this lesson/i],
	["replaced", /another tab/i],
	["unauthorized", /expired/i],
])("explains the %s failure specifically", async (failure, copy) => {
	renderCallRoom({ socketFailure: failure });
	expect(await screen.findByText(copy)).toBeVisible();
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd dashboard && pnpm vitest run src/features/call
```

- [ ] **Step 3: Implement**

`VideoTile` renders a `<video autoPlay playsInline>`, muted **only** for the local tile. The self-tile is absolutely positioned with `inset-e-4 inset-b-20` so RTL mirrors it with no second rule. `CallControls` renders three real buttons; the two toggles carry `aria-pressed`. `CallRoom` composes the hooks and owns no connection state of its own. The route mints the grant on mount via `useJoinSession`, renders `Lobby` until the user commits, then `CallRoom`.

A refused grant is handled at the route, not in `CallRoom`: reuse the existing
`isOutsideJoinWindowError` (409) and `isVideoUnavailableError` (502) helpers from
`features/booking/api.ts` and the `booking.joinNotOpen` / `booking.joinUnavailable` copy, so the
room and the schedule row say the same thing about the same refusal. A 403 means not a
participant — the same copy as `booking.joinError`. Do not invent a second vocabulary for these;
the point of reusing them is that a user who saw one message on the schedule sees the same one
here.

- [ ] **Step 4: Run everything**

```bash
cd dashboard && pnpm vitest run --coverage && pnpm lint && pnpm tsc --noEmit
```
Expected: all pass; floors green. Raise any floor the run clears.

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add -A
git commit -m "feat(call): the room, its controls and its failure states (C3d)"
```

---

### Task 8: A real two-peer call in CI

The first automated gate video has ever had.

**Files:**
- Create: `dashboard/e2e/call.spec.ts`
- Modify: `dashboard/playwright.config.ts`

**Interfaces:**
- Consumes: `login`, `ACCOUNTS` from `e2e/fixtures.ts`; the joinable session `seed_e2e_matching` positions on `now` for `e2e.booked`.

- [ ] **Step 1: Grant fake media in the config**

In `playwright.config.ts`, on the chromium project:

```ts
launchOptions: {
    // Fake devices, and permissions pre-granted: a real prompt cannot be
    // clicked from a test, and a real camera does not exist on a CI runner.
    // This proves the plumbing -- signaling, negotiation, tracks arriving --
    // never that audio is audible or video is watchable. That stays human.
    args: [
        "--use-fake-ui-for-media-stream",
        "--use-fake-device-for-media-stream",
    ],
},
```

- [ ] **Step 2: Write the failing spec**

```ts
test("a student and a teacher see each other", async ({ browser }) => {
	const studentCtx = await browser.newContext();
	const teacherCtx = await browser.newContext();
	const student = await studentCtx.newPage();
	const teacher = await teacherCtx.newPage();

	await login(student, "booked");
	await login(teacher, "teacher");

	for (const page of [student, teacher]) {
		await page.goto("/schedule");
		await page.getByRole("button", { name: /join/i }).first().click();
		await page.getByRole("button", { name: /join now/i }).click();
	}

	// The assertion that matters: a remote track actually arrived and is
	// producing frames. Asserting the element exists would pass against a
	// call that never connected.
	for (const page of [student, teacher]) {
		await expect
			.poll(() => page.evaluate(() => {
				const v = document.querySelector<HTMLVideoElement>("[data-testid=remote-video]");
				return v && v.readyState >= 2 && v.videoWidth > 0;
			}), { timeout: 30_000 })
			.toBe(true);
	}

	await studentCtx.close();
	await teacherCtx.close();
});

test("one side leaving is seen by the other", async ({ browser }) => {
	const studentCtx = await browser.newContext();
	const teacherCtx = await browser.newContext();
	const student = await studentCtx.newPage();
	const teacher = await teacherCtx.newPage();
	await login(student, "booked");
	await login(teacher, "teacher");
	for (const page of [student, teacher]) {
		await page.goto("/schedule");
		await page.getByRole("button", { name: /join/i }).first().click();
		await page.getByRole("button", { name: /join now/i }).click();
	}
	await expect(teacher.getByTestId("remote-video")).toBeVisible();

	// The student leaves by closing the context outright, not by clicking
	// Leave: an abrupt disconnect is the case that actually happens (a closed
	// laptop, a dead battery), and it is the one a clean-exit test would miss.
	await studentCtx.close();

	await expect(teacher.getByText(/waiting for/i)).toBeVisible({ timeout: 20_000 });
	await teacherCtx.close();
});
```

- [ ] **Step 3: Run against a real stack**

```bash
cd dashboard && pnpm e2e call.spec.ts
```
Reproduce CI's topology per `docs/runbook`: Django in a container on `:8000`, `pnpm preview` on `:4173`, sibling subdomains — cookies ignore ports, so `localhost:PORT` would prove nothing about ADR-0019.

- [ ] **Step 4: Mutation-check it**

Break the offerer rule — make the student offer too — and confirm the spec goes **red**. A green two-peer test that passes when negotiation is broken is not a gate. Revert.

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add -A
git commit -m "test(e2e): a real two-peer call with fake media (C3d)"
git push -u origin feat/phase-c3d-call-client
gh pr create --base main --title "C3d: the call client" --body "Implements docs/superpowers/specs/2026-09-07-phase-c3d-call-client-design.md."
```

---

### Task 9: Docs, D3 table, and the phase close

**Files:**
- Modify: `CLAUDE.md` (D3 e2e table), `ISSUES.md`, `STATE.md`, `docs/superpowers/journal/2026-W36.md`
- Create: `docs/runbook/video-call.md`

- [ ] **Step 1: Add the D3 row**

`scheduling` — call client (C3d) → `✅ 2 flows` → "a real two-peer call with fake media: both see a remote track producing frames, and one leaving is seen by the other. **Proves host-candidate P2P only — CI has no coturn**; the relay path is covered by C3c's live check, not by this."

State the limit in the table itself. A row implying video is fully gated is exactly the overclaim the D3 rule forbids.

- [ ] **Step 2: Write `docs/runbook/video-call.md`**

What to do when a call will not connect, as an ordered checklist: is the grant being minted (403/409 vs 200), does the socket open (check for 4401 — a secret mismatch — versus 4409/4410), does either side get a relay candidate, and where to look in `docker logs` for coturn and signaling. Cross-link `turn.md` and `signaling.md`.

- [ ] **Step 3: Log what shipped without being solved**

Add to `ISSUES.md`: no Safari/iOS support yet (C3e, ADR-0034); device changes mid-call are not handled gracefully; device choices are not remembered between lessons; and the e2e gate cannot see the relay path.

- [ ] **Step 4: Update `STATE.md` and the journal**

Record measured coverage and flow counts, and **do not claim the manual check until it has been done**.

- [ ] **Step 5: Commit and open the meta PR**

```bash
git add -A && PIP_CONFIG_FILE=/dev/null git commit -m "docs: C3d — the call client"
```

---

### Task 10: Live verification — a real call between two real browsers

No suite can do this. Fake media proves plumbing; it cannot tell you the lesson is usable.

- [ ] **Step 1: Deploy**

Merge backend, then dashboard, then bump pointers and merge meta. **Deploy between lessons** — a deploy still drops every call in progress (`ISSUES.md`).

- [ ] **Step 2: Make a real call on staging**

Two real browsers, two real accounts (student and teacher), on staging. Confirm both directions of video and audio, mute observed by the other side, camera off observed by the other side, and leaving observed by the one who stays.

- [ ] **Step 3: Force the relay**

Repeat with `iceTransportPolicy: "relay"` forced (DevTools override or a throwaway build), to prove the C3c path carries a *real* call and not just a synthetic data channel. This is the check CI structurally cannot do.

- [ ] **Step 4: Arabic and RTL**

Repeat as a student with the locale set to Arabic. Confirm the self-tile mirrors to the inline-start side and no control overlaps the video.

- [ ] **Step 5: Close the phase**

Run `/ship` and walk D9. Update the D3 row and `STATE.md` with what was actually verified, in the past tense only for things that were actually done.
