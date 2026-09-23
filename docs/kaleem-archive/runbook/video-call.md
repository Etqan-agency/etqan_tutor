# Runbook — a call will not connect

Shipped in Phase C3d (the call client). Spec:
`docs/superpowers/specs/2026-09-07-phase-c3d-call-client-design.md`. This
runbook is for the visible symptom **"a lesson's video call never connects, or
connects one-way"** — walk it top to bottom; each step narrows which layer of
the stack is at fault. It assumes C3a (rooms), C3b (signaling — see
`docs/runbook/signaling.md`) and C3c (TURN — see `docs/runbook/turn.md`) are
already deployed and healthy; this runbook does not repeat their content, only
cross-links it at the point each layer matters.

**What "connects" means here, and what it doesn't.** CI's e2e coverage
(`call.spec.ts`, 2 flows) proves host-candidate peer-to-peer connectivity with
fake media on a single machine — it has no coturn, so it cannot prove the
relay path, and fake media proves plumbing, not that anyone can hear or see
anything. The relay path is proven separately, by C3c's live verification on
staging. If a real call fails only for a specific user network (not in this
runbook's steps 1–3), suspect the relay path first and go straight to
`docs/runbook/turn.md`.

## Step 1 — is the join grant being minted?

Open the browser network tab (or `curl` the endpoint with a real session
cookie) for the join-grant request the Lobby makes on mount.

| Response | Meaning | Where to look next |
| --- | --- | --- |
| `200` with a body containing `join_url`, `token`, `ice_servers`, `is_teacher` | The grant is fine. Move to step 2. | — |
| `403` | The caller is not a participant of this session (wrong user, or a teacher/student mismatch on the row). | `scheduling` view/service logic, not signaling or TURN. Not a call-infrastructure bug. |
| `409` | The request is outside the join window (`join_window(session)`, C3c) — too early or the lesson has ended. | Confirm server clock; compare `expires_at` semantics in `docs/runbook/signaling.md` ("Every join logs `expired`" row). |
| `500` / no `ice_servers` in the body | `SignalingProvider` failed to construct — almost always a missing `DJANGO_TURN_SECRET` / `DJANGO_TURN_URLS`, which it fails closed on. | `docker logs kaleem-django-<colour>-1`; see `docs/runbook/turn.md` "Environment variables". |

If the grant never 200s, nothing past this point matters — the browser has no
`join_url` or `token` to open a socket with.

## Step 2 — does the signaling socket open?

The call room opens a WebSocket to `join_url` with `token` carried in
`Sec-WebSocket-Protocol` (not the query string — see
`docs/runbook/signaling.md`). Check the browser's WS frame inspector or
`docker logs kaleem-signaling-<colour>-1` for the close code.

| Close code | Meaning | Action |
| --- | --- | --- |
| Socket stays open, `peer-joined` never arrives | The other participant hasn't opened their own socket yet (still on their own grant/lobby step), or their grant pointed at a different room/colour. | Confirm both grants resolved the same `Room.signaling_url` — see the `Room.signaling_url` entry in `ISSUES.md`'s history for why colour pinning exists. |
| `4401` (`CLOSE_UNAUTHORIZED`) | **Secret mismatch, or a bad/expired/wrong-room token** — five distinct refusals share this one code. | Check `docker logs kaleem-signaling-<colour>-1`: *every* join logging "bad signature" means `DJANGO_SIGNALING_SECRET` differs between the Django and signaling containers; *every* join logging "expired" is clock skew or too-tight a join window, not a one-off. Full table in `docs/runbook/signaling.md` ("Reading the logs"). |
| `4409` (`CLOSE_ROOM_FULL`) | A third socket tried to join a 1-on-1 room. | Look for a stray extra tab/device on one side; the cap (`MAX_PEERS = 2`) is correct behaviour, not a bug. |
| `4410` (`CLOSE_REPLACED`) | **Not an error.** The affected participant opened a second tab or reconnected; their older socket lost its seat. | Tell the user they're connected elsewhere; nothing to fix server-side. |

If both sockets open and `peer-joined` fires on both sides, signaling is
healthy — the problem is in the peer connection itself. Move to step 3.

## Step 3 — is negotiation actually carrying media?

A `connectionState` of `"connected"` in the browser's WebRTC internals
(`chrome://webrtc-internals`) is **not proof of media** — C3d shipped with
exactly this failure mode twice before it reached CI (see the 2026-W36
journal entry): an offer created before local tracks were attached describes
no media at all, yet negotiation completes and reports `connected`.

- Check the SDP actually exchanged (`chrome://webrtc-internals` → the peer
  connection → `getStats`/SDP dump) for `m=audio` / `m=video` lines. Zero
  `m=` lines means one side offered or answered before its own
  `getUserMedia()` resolved.
- Check the browser console for an unhandled `InvalidStateError` on
  `setLocalDescription`/`setRemoteDescription`. This is the signature of two
  offers racing (the single-offerer invariant broken) — see the C3d mutation
  history in `docs/superpowers/journal/2026-W36.md` for exactly what this
  looks like and why the outcome is timing-dependent, not deterministic.
- If SDP looks correct on both sides but no frames render, the peers likely
  need a relay and aren't getting one — move to step 4.

## Step 4 — does either side get a relay candidate?

Roughly one connection in six cannot go host-to-host (symmetric/carrier-grade
NAT, corporate egress filtering) and needs coturn. In
`chrome://webrtc-internals`, check the candidate pair that ends up selected:
a `relay` typed local or remote candidate means TURN was used; if the
selected pair is `host`/`srflx` on both sides that's a direct connection and
this step doesn't apply.

- No relay candidate gathered at all → the `ice_servers` list handed to the
  browser is empty or malformed. Re-check step 1's grant body.
- A relay candidate is gathered but the connection still fails → coturn
  itself. Full detail in `docs/runbook/turn.md`, including the two easy-to-hit
  operational traps: a config-only change to `turnserver.conf` does not
  restart the running relay by itself, and the relay range
  (49152–49999/UDP) can be open in coturn but closed at the provider
  firewall.
- `docker logs kaleem-coturn-1` (confirm the exact container name with
  `docker ps` if it differs) — coturn logs to stdout as of C3c
  (`log-file=stdout`); an empty log despite active calls means that setting
  regressed. Every allocation logging `401` means the shared secret
  (`DJANGO_TURN_SECRET`) disagrees between Django and coturn, or was pasted
  literally into `turnserver.conf` instead of passed on the command line —
  see `docs/runbook/turn.md`'s "Why the secret is a command-line argument"
  section, since this is an easy, security-relevant mistake to reintroduce.

## Step 5 — did the browser tell us anything? (C3e-a)

Shipped in Phase C3e-a: `docs/superpowers/specs/2026-09-07-phase-c3e-a-call-diagnostics-design.md`.
Before C3e-a, a call failing on a browser this project cannot run (see below) produced exactly
one signal — a parent saying "the lesson didn't work" — compatible with at least six distinct
defects. Now it can produce a `CallDiagnostic` row naming one of eight failure codes:
`gum-denied`, `gum-not-found`, `gum-in-use`, `autoplay-blocked` (all wired to an emitter as of
C3e-a), and `gum-no-gesture`, `ice-restart-unsupported`, `backgrounded`, `device-lost` (reserved
for C3e-b's fixes, in the enum from the start so the contract test covers them before their
emitters exist).

Read it with the Django shell, there is no dashboard for this data:

```python
from kaleem.scheduling.models import CallDiagnostic
CallDiagnostic.objects.filter(session_id=<id>).order_by("-created_at").values(
    "code", "user_agent", "stats", "created_at"
)
```

`user_agent` is the field that tells you whether the report was Safari 17 on iOS or Chrome on
Android — read server-side from the request header, so it cannot be forged. `stats` is a
client-redacted allow-list of WebRTC stat fields (never an address) and is `null` on the three
`gum-*` codes, which fire in the Lobby before any `RTCPeerConnection` exists — a null there is
correct, not missing data. The guarantee is precisely "**our** client redacts before sending",
not "the server refuses addresses": `stats` is an unvalidated `JSONField` by design, so a future
non-kaleem client (or anyone POSTing by hand) could store anything in it — read the column as
address-free by convention, never as structurally address-free.

**Two things this table will not tell you.** It is throttled at 20/hour per **user**, not per
session — `ScopedRateThrottle` keys on `request.user.pk`, so back-to-back lessons share one
budget and a browser failing in a tight loop understates its own frequency — do not read the row count as an
incident count. And reporting is fire-and-forget on the client: a diagnostics outage, a throttle
refusal, or an offline browser all mean *no row*, which is not the same as *no failure*. Rows
older than 90 days are gone (a Celery beat job), so a pattern tied to a slow-rolling iOS point
release needs to be read within that window.

## What this runbook cannot diagnose

- **Whether a real call was audible or watchable.** No log or test proves
  quality; that is only ever checked by a human in a real call (C3d's Task
  10 manual check).
- **Safari/iOS**, beyond what C3e-a's diagnostics rows happen to report.
  C3e-b (ADR-0034) adds seven Safari/iOS hardening fixes — `min-h-dvh`,
  the `getUserMedia` gesture gate, a tap-to-play control for a refused
  autoplay, a feature-guarded `restartIce`, backgrounding/screen-lock
  recovery, device-change hot-swapping, and persisted device choices — but
  **none of them is verified on the browser they exist for**. This project
  has no Apple device at all — no Mac, no iPhone, no iPad — and Playwright's
  WebKit on Linux is not iOS Safari and has no fake-media equivalent, so
  nothing here can be verified against the real target browser; only real
  reports from real users can, via C3e-a's `CallDiagnostic` codes
  (`gum-no-gesture`, `autoplay-blocked`, `backgrounded`, `device-lost`,
  `ice-restart-unsupported`) once C3e-b is merged and live. It is CODE-COMPLETE
  on `feat/browser-hardening` today: not merged, not deployed.

## See also

- `docs/runbook/signaling.md` — the WebSocket relay: environment variables,
  every close code, and reading `docker logs kaleem-signaling-<colour>-1`.
- `docs/runbook/turn.md` — coturn: environment variables, the
  command-line-secret trap, and reading `docker logs kaleem-coturn-1`.
