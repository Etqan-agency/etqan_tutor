---
name: phase-c3e-a-call-diagnostics
phase: C
modules: [scheduling, dashboard]
status: draft
created: 2026-09-07
---

## Goal

Find out when a call breaks on a browser we cannot run.

C3d shipped a working video call, built and verified against Chromium only. C3e is the browser
hardening ADR-0034 reserved for Safari and iOS and said must not be dropped as polish. But this
project has **no access to any Apple device** — no Mac, no iPhone, no iPad — and Playwright's
WebKit on Linux is not iOS Safari and has no equivalent of Chromium's fake-media flags. So the
e2e harness that gates every other shipped area (ADR-0027, the D3 table) structurally cannot
cover this one.

That constraint decides the phase's shape. If the fixes cannot be tested before release, the
substitute is not hope — it is making every failure announce itself. **C3e-a builds the channel
through which a Safari failure becomes a fact we hold**, so that the hardening work in C3e-b
lands with evidence instead of optimism.

Today a Safari user whose call fails produces exactly one signal: a parent saying "the lesson
didn't work." That sentence is compatible with at least six distinct defects, and there is no
way to tell which. After C3e-a it is a row that names the failure.

## Why diagnostics come before the fixes

This ordering is counterintuitive and deliberate. The user-facing fixes are what a reader wants
first; they are sequenced second on purpose.

Ship the seven hardening fixes first and the result is seven behaviour changes, on a browser
nobody here can run, with no channel to discover whether any of them worked. That is precisely
the failure this phase keeps repeating in C3b, C3c and C3d: **something fails, the code carries
on, and nobody is told** — and one level up, the verifier is itself unverified.

Ship the pipeline first and every subsequent fix arrives with its own evidence. C3e-a also has a
property C3e-b structurally lacks: it can close cleanly under D9, with a real manual
click-through, because the pipeline does not care which browser reported to it.

## What C3e-a is not

- **Not the Safari fixes.** `100dvh`, the `getUserMedia` gesture gate, the autoplay fallback
  control, the `restartIce` feature guard, iOS backgrounding, mid-call device changes, and
  persisted device choices are all C3e-b. They are agreed scope, not open questions — this
  document defers them, it does not drop them.
- **Not frontend error reporting.** No Sentry on the dashboard, no vendor on a child-facing
  surface, no session replay. This is one endpoint with a closed vocabulary, not a telemetry
  platform.
- **Not analytics.** Nothing here measures engagement, usage or quality. The only question it
  answers is "which failure happened, on what browser."
- **Not a dashboard.** Reading the data is `manage.py` and SQL for now. A reporting UI is
  unjustified before the table has ever held a row.

## Decisions taken

1. **A closed enum of failure codes.** An unrecognised code is a `400` and stores nothing. The
   moment free text is accepted, the field becomes an uncontrolled channel carrying whatever a
   browser puts in a localised error message — which may include device names.
2. **WebRTC stats are captured, with addresses removed client-side.** Candidate type, byte
   counts, selected-pair state, codec and packet loss answer every question worth asking. The
   address fields answer only "where does this child live."
3. **Redaction is an allow-list, not a deny-list.** See below — this is the single most
   important decision in the document.
4. **Authorization reuses `rooms.is_participant`.** Not a second predicate that agrees with it
   today.
5. **90-day retention**, enforced by a Celery beat job, not by intention.
6. **Reporting is fire-and-forget.** A diagnostics failure must never affect a lesson.
7. **Only already-detected failures emit in C3e-a.** Wiring an emitter for a condition nothing
   detects yet would be dead code.

## Redaction is an allow-list

The obvious implementation of "strip the IPs" is a deny-list: delete `address`,
`relatedAddress`, `raddr`, `ip`. **That implementation is wrong here, and wrong in the specific
way this phase is dangerous.**

`RTCStatsReport` fields differ per browser and per version. Safari is exactly the browser whose
stat shape cannot be inspected from this project. A deny-list leaks every address-bearing field
nobody here knew to name — and the browser most likely to have one is the browser this whole
phase exists for.

So the payload is built by **copying named fields out** of each stats entry:

| Kept | Why |
| --- | --- |
| `type`, `candidateType` | Was the path host, srflx, or relay? Did TURN work? |
| `bytesSent`, `bytesReceived` | Was media flowing, or connected-but-silent? |
| `state`, `nominated` | Which leg of the connection broke |
| `codecId`, `mimeType` | Codec negotiation failures |
| `packetsLost`, `jitter` | Quality, when the call connected but was unusable |

Everything not on that list is dropped by construction. A field added by a future browser cannot
leak, because nothing is copied unless it is listed. This is a pure function — no network, no
DOM — so it is directly unit-testable, and it runs **in the browser**, before the event is sent:
a raw address never reaches our server, our logs, or our database, so there is nothing to
retain and nothing to breach.

**Its test uses a realistic Safari-shaped stats fixture** containing genuine dotted-quad and
IPv6 addresses across several entry types, and asserts that no address survives the function.
A two-field stub would remove the very constraint under test.

## The failure vocabulary

| Code | Meaning | Detected in |
| --- | --- | --- |
| `gum-denied` | Camera/microphone permission refused | C3e-a — exists today |
| `gum-not-found` | No camera or microphone present | C3e-a — exists today |
| `gum-in-use` | Device held by another application | C3e-a — exists today |
| `autoplay-blocked` | The browser refused to play remote media | C3e-a — exists today, silently |
| `gum-no-gesture` | Media requested without user activation | C3e-b |
| `ice-restart-unsupported` | `restartIce()` unavailable | C3e-b |
| `backgrounded` | The page was suspended mid-call | C3e-b |
| `device-lost` | A device disappeared mid-call | C3e-b |

The enum is defined **once**, in the backend. The client necessarily holds its own copy — a
Vitest test cannot read a Python enum, and the dashboard is a separate submodule — so drift is
caught by **an e2e test that POSTs every code the client knows through the real endpoint** and
asserts each is accepted. That is a genuine contract test against a running Django, not two
frozen literals a human is trusted to keep in step. Every code is listed here from the start,
including C3e-b's, so that phase adds emitters rather than reopening the schema, and so the
contract test covers them before their emitters exist.

`autoplay-blocked` is the highest-value emitter in the phase. Today `VideoTile` does
`void video.play().catch(() => {})` — an empty catch. On Safari a refused audible autoplay is
both the most likely failure and a perfectly silent one: a still frame and no sound, which reads
to a parent as "the teacher isn't talking." That empty catch becoming a report is, on its own,
worth the endpoint.

## The endpoint

`POST /api/v1/scheduling/sessions/<id>/diagnostics/`

Under `/api/v1/` and mounted through `kaleem.scheduling.api.urls`, per ADR-0017 and ADR-0029 —
the unversioned allowlist is closed and CI walks the URLconf to enforce it. Session cookie plus
real CSRF, like every other mutation (ADR-0019).

**Authorization calls `rooms.is_participant`.** That predicate already encodes the rule that a
parent may see the schedule but may not enter the lesson (Decision 3), and reusing it means a
future widening of who may join lands on both the room and its diagnostics at once. A test
asserts a parent of the student is refused — the mistake a reader who thinks "related to this
session" rather than "in this lesson" would make.

**Throttled** at `"call-diagnostics": "20/hour"`, a new DRF scope alongside the existing
`"email": "5/hour"`. A client failing in a loop — which is exactly what a broken browser does —
must not be able to write unbounded rows. Twenty is chosen to sit above a bad lesson's honest
count (a handful of failures, a few rejoin attempts) and well below a loop's.

Request body: the failure code, and an optional redacted stats object. **Stats are attached
only when a peer connection exists to read them from** — so `autoplay-blocked` and every C3e-b
connection failure carry them, while the three `getUserMedia` failures never do: they happen in
the Lobby, before any `RTCPeerConnection` is built. `stats` is therefore nullable by design, not
by laxity, and a null on a `gum-*` row is correct rather than missing data. The session comes from
the URL and the user from the session cookie; neither is client-supplied, so neither can be
forged to write a row against someone else's lesson.

## Data

One model, `CallDiagnostic`, in `kaleem/scheduling/models.py`:

| Field | Notes |
| --- | --- |
| `session` | FK, indexed |
| `user` | FK — who experienced it |
| `code` | The closed enum, `choices=` |
| `user_agent` | The raw `User-Agent`, read server-side from the request header, truncated to 512 characters |
| `stats` | `JSONField`, the redacted object, nullable |
| `created_at` | Indexed — the retention job filters on it |

`user_agent` is taken from the request header rather than trusting a client-supplied field.
It is the one column that answers "was this Safari 17 on iOS or Chrome on Android," which is the
question the phase exists to answer.

Per rule #4, no logic on the model. Writing a diagnostic is a function in
`kaleem/scheduling/services.py`; the view validates and delegates.

## Retention

A Celery beat task deletes rows older than **90 days**, scheduled in `CELERY_BEAT_SCHEDULE`
beside the existing jobs. 90 days is long enough to see a pattern tied to an iOS point release
— which surfaces over weeks — and short enough to state plainly in a privacy policy.

The job is tested for what it deletes **and what it leaves**: a boundary test with a row at 89
days and one at 91. A retention job that silently deletes everything is worse than none.

## The client

A `useCallDiagnostics` hook in `dashboard/src/features/call/`, exposing one `report(code, pc?)`
function, and a separate pure `redactStats` module so redaction is testable without React.

Reporting is **fire-and-forget**: no `await` on any failure path, the promise rejection
swallowed. A diagnostics outage, a throttle, or an offline client must never turn a survivable
call problem into a broken one. This is the one place in the feature where swallowing an error
is correct, and it is commented as such so a later reader does not "fix" it into an await.

Emitters wired in C3e-a: `useLocalMedia`'s three classified failures, and `VideoTile`'s autoplay
catch.

## Testing

**Backend.** Ordinary TDD. The authorization test refuses a parent. The enum test rejects an
unknown code with a 400 and asserts no row was written. The retention test checks both sides of
the 90-day boundary. Coverage ratchets up from 97.7 per ADR-0026, measured
`--cov=kaleem --cov=signaling` — never a bare `pytest --cov`, which omits unimported files and
reads low enough to set a false floor.

**Dashboard.** `redactStats` against the realistic Safari-shaped fixture. `useCallDiagnostics`
asserting a rejected POST does not propagate. Emitter tests asserting the right code for each
`getUserMedia` failure and for a rejected `play()`. Floors ratchet from 95.1/91.4/86.6.

**e2e.** One flow: a failure occurs, and the row exists. It runs on Chromium.

**What this does not prove, stated plainly for the D3 table:** that Safari emits anything. Safari
never runs in CI and cannot be run here at all. The pipeline is verified; the reporter on the
browser that matters is not. That is the honest limit of what this phase can claim, and it is
the reason the phase exists rather than an argument against it.

## Risks

- **The pipeline is built for reports that may never come.** If no Safari user ever hits a
  lesson, this is dead weight. Accepted: the alternative is shipping C3e-b blind, and one real
  report pays for the whole endpoint.
- **A row proves a failure, not its cause.** `autoplay-blocked` tells us the browser refused;
  it does not say whether the fix in C3e-b then worked. Watching the code's frequency fall after
  C3e-b ships is the actual verification loop, and it is slower than a test.
- **Throttling can hide a storm.** A browser failing in a loop is rate-limited, so the row count
  understates the incident. Deliberate — the alternative is letting a broken client write
  without bound — but a reader must not treat the count as a frequency.
- **Redaction is only as good as its allow-list.** A field that is *both* useful and
  address-bearing would tempt a future addition. The list is the security boundary; changing it
  is a decision, not a tweak.
