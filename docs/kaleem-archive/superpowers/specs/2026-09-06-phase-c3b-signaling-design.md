---
name: phase-c3b-signaling
phase: C
modules: [scheduling, signaling]
status: shipped
created: 2026-09-06
closed: 2026-09-06
---

## Goal

Let the two people in a lesson find each other, and let nobody else into the conversation.

C3a gives a `Session` a room and mints a join grant for its two participants. The grant points
at nothing, and nothing validates it. C3b builds the service the grant points at: a signaling
endpoint over which exactly two authenticated peers exchange the offers, answers and ICE
candidates WebRTC needs to open a direct connection.

**C3b still produces no call.** Signaling is necessary and not sufficient: roughly one
connection in six cannot go peer-to-peer and needs a TURN relay, which is C3c. There is also no
browser code here — `RTCPeerConnection`, the video grid and the controls are C3d. What C3b
delivers is a correct, authenticated, tested relay with no client.

**Why this is its own spec.** Signaling is the first stateful thing kaleem has built. Every
other phase is request/response against a database; this holds connections open, and its
interesting failures are reconnection, cleanup and races rather than authorization. Bundling it
with the client would make one branch that owns both a new deployable and a new browser API.

## Decisions taken

Recorded so the plan does not relitigate them. The process-model decision and its alternatives
are **ADR-0035**; these are the ones below it.

1. **Signaling is a separate deployable, in Python, sharing the backend image** (ADR-0035, E5).
   Its own container, command, health check and blue/green pair.
2. **It is not a Django app.** No Django import, no ORM, no database connection. An
   `import-linter` contract fails CI if a signaling module imports `kaleem.*`.
3. **Authentication is a signed capability token, not a session.** Django mints; signaling
   verifies with a shared secret. The codec is pure stdlib, Django-free, and imported by both,
   so the two cannot disagree about the format.
4. **A room holds at most two peers.** 1-on-1 is the product (ADR-0034); the cap is enforced,
   not assumed, and a third connection is refused rather than silently dropped.
5. **Signaling relays; it does not interpret.** It does not parse SDP, does not know what an ICE
   candidate contains, and does not implement WebRTC. It moves opaque payloads between two
   authenticated peers, which is what keeps it small enough to be correct.
6. **No message is persisted.** Nothing about a lesson's negotiation is written anywhere. There
   is no database, so this is by construction rather than by policy.
7. **Single replica per colour.** No cross-process fan-out, no Redis channel layer. Two peers in
   a room must land on the same process, and with one replica they always do. Scaling past one
   replica is a later phase and needs sticky routing or a fan-out layer — stated here so the
   constraint is visible rather than discovered.

## The token

Replaces `FakeVideoProvider`'s unsigned hash, closing the `ISSUES.md` *Blocks launch* entry that
C3a opened.

```text
payload   room id, participant user id, is_teacher, expiry (unix seconds)
encoding  base64url(json)  .  base64url(hmac_sha256(secret, payload))
```

- **HMAC-SHA256 with `hmac.compare_digest`.** Constant-time comparison, stdlib only, no new
  dependency and no JWT library.
- **The secret is `DJANGO_SIGNALING_SECRET`**, shared by both containers and absent from the
  repository (rule #11). If the two disagree, every join fails authentication with a
  correct-looking token — a real deployment failure mode, and why the signaling health check
  must verify a self-minted token rather than only reporting that the process is up.
- **Expiry is checked on connect**, against the same `GRANT_TTL` C3a already carries.
- **The token is a URL query parameter**, because browsers cannot set headers on a WebSocket
  handshake. That means it will appear in access logs unless suppressed, which is why it is
  short-lived and single-room. Signaling must not log the query string.

`FakeVideoProvider` stays as the CI and test default. A new `SignalingProvider` mints a real
`wss://` URL and is what staging and production use.

## The protocol

JSON over WebSocket, four message types, deliberately dumb:

| Direction | Type | Meaning |
| --- | --- | --- |
| server → peer | `peer-joined` / `peer-left` | the other participant arrived or went away |
| peer → server → peer | `offer` / `answer` / `ice` | relayed verbatim to the other peer |

Rules the server enforces:

- A connection with a missing, malformed, expired or badly-signed token is closed immediately
  with a WebSocket close code, before any message is read.
- A third connection to a full room is closed with a distinct code.
- A relay with no peer present is dropped, not queued. WebRTC negotiation is not meaningful to
  replay at an absent peer, and a queue is a memory leak with extra steps.
- A payload that is not JSON, or whose type is unknown, closes the connection. Signaling has one
  client — kaleem's own — so a malformed frame is a bug or an attack, never a version skew.
- **Disconnect cleans up.** The peer is removed, the other peer is told, and an empty room is
  deleted from memory. Leaking rooms is the failure mode that ends in a restart at 3am.

## Deployment

- **`signaling-blue` / `signaling-green`** in `infra/docker-compose.production.yml`, mirroring
  the `django-*` pair, from the same image with a different command. `ship.sh` gains the colour.
- **Traefik** routes a dedicated host to it. A separate host rather than a path prefix on the
  API, because the two are different services with different lifecycles, and a path prefix would
  put a WebSocket upgrade through the API's router.
- **A health check that proves signing works**, not just that the port is open: the endpoint
  mints a token and verifies it, so a mismatched secret is red at deploy rather than silent
  until a lesson.
- **Local `docker-compose.local.yml`** gains the same service so `just dev` and the e2e harness
  have it.

## Out of scope

- **All browser code.** `RTCPeerConnection`, media capture, the video grid, controls,
  reconnection UI — C3d.
- **STUN/TURN.** Mandatory before any real call connects; C3c.
- **Group calls.** 1-on-1 only (ADR-0034).
- **Recording**, which needs server-side media ingest.
- **Scaling past one replica per colour.** Decision 7.
- **The dashboard's Join button.** It keeps opening `join_url` in a tab. Between C3b and C3d
  that URL is a WebSocket endpoint rather than a page, so clicking Join opens something that is
  not a page — exactly as it does today, when it opens a host that does not resolve. Changing
  the button now would be churn C3d undoes.

## Test plan

TDD throughout (D3). Floors are the current ratchets — backend **97.6** (measured with
`pytest --cov=kaleem`, the invocation CI runs; a bare `pytest --cov` reads higher and set a
false floor once already), dashboard 93.5 / 90 / 86.5 / 93.5.

**Token codec** — round-trips; rejects a tampered payload, a tampered signature, a wrong secret,
an expired token, a truncated token, and a token with a valid signature over the wrong room.
Comparison is constant-time.

**Signaling service** — connects with a valid token; refuses missing, malformed, expired,
wrong-secret and wrong-room tokens, each with its own close code; admits exactly two peers and
refuses a third; relays `offer`/`answer`/`ice` verbatim to the *other* peer and never back to
the sender; tells a peer when the other joins and leaves; drops a relay with no peer present;
closes on malformed JSON and on an unknown type; and **removes the room from memory when the
last peer disconnects** — asserted by inspecting the registry, not by absence of error.

**Boundary** — `lint-imports` gains a contract forbidding `signaling` from importing `kaleem.*`,
**verified by breaking it**: a probe import must turn the contract red, and the run green once
removed. A contract nobody has watched fail is not known to work.

**Django side** — `SignalingProvider` mints a URL the codec accepts; the provider seam is
unchanged otherwise, so C3a's authorization tests still pass untouched.

**Not covered, and stated rather than implied:** there is no Playwright flow, because C3b adds
no user-facing behaviour. The e2e count stays at 33. The first browser-level proof that a call
connects arrives in C3d, and only for connections that do not need a relay until C3c lands.

## Open questions

None blocking.

- **OQ-C3b-1.** Should a reconnecting peer resume its place in a room, or is a fresh connection
  with a fresh token sufficient? The grant outlives a brief drop, so a reconnect works today;
  whether it should *feel* seamless is a C3d question about the client's retry behaviour.
- **OQ-C3b-2.** Does signaling need a per-connection message rate limit? One client, two peers,
  and a short-lived token bound the blast radius, but nothing currently stops an authenticated
  participant flooding their partner. Cheap to add when C3d shows the real message volume.
