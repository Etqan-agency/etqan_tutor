---
name: phase-c3c-turn
phase: C
modules: [scheduling, signaling, infra]
status: draft
created: 2026-09-06
---

## Goal

Make a call able to connect at all, and stop handing credentials to things that write logs.

C3a gave a session a room. C3b built the relay the room's grant points at. Neither produces a
call: roughly one connection in six cannot go peer-to-peer — symmetric NAT, corporate egress
filtering, carrier-grade NAT — and fails outright with no relay to fall back on. C3c stands up
that relay, mints per-user ephemeral credentials for it, and delivers them to the client
alongside the join grant.

**C3c still produces no call.** There is no browser code here — `RTCPeerConnection`, the video
grid and the controls are C3d. What C3c delivers is a working relay, proven by a throwaway
harness, plus the ICE payload C3d will consume.

Three hardening items ride along because they touch the same grant and the same deployable, and
splitting them would mean two branches editing `SignalingProvider` and `docker-compose.production.yml`
in the same week: the capability token leaves the URL query string, a room is pinned to one
deploy colour, and the grant's expiry stops being a flat constant.

## Decisions taken

Recorded so the plan does not relitigate them.

1. **coturn, self-hosted, on the existing staging VPS with `network_mode: host`.** Not a managed
   TURN vendor: E2 (self-hosted → managed) is an escape hatch, not the default, and putting a
   paid third party in the media path of a children's lesson is a decision that deserves its own
   ADR rather than a drive-by.
2. **coturn is a shared service, not a blue/green pair.** It holds no deploy-versioned code.
   Restarting it on every ship would drop live relay allocations for nothing.
3. **`turn:` only — no `turns:` TLS in C3c.** Traefik owns 443 on this box, and 5349 would need a
   certificate delivered to a container Traefik does not front. Media is DTLS-SRTP end to end
   regardless; what a path observer gains is one ephemeral, single-user credential. The cost is
   real and named: **users behind a TLS-443-only egress filter still cannot call.** Logged to
   `ISSUES.md` under *Blocks launch*, not silently accepted.
4. **Credentials are coturn's `use-auth-secret` (TURN REST) scheme.** No user table in coturn, so
   nothing to provision, nothing to revoke, and no state to keep in sync with kaleem's.
5. **One expiry in the system.** The TURN credential expires when the join grant expires, which
   is when the room stops being enterable. Not three constants that can drift apart.
6. **A clean break on the token's transport.** No query-string fallback. C3d does not exist yet,
   so there is no client to keep compatible — the alternative is a dual path forever.

## The relay

### Placement and ports

`coturn` container, `network_mode: host`, added to `docker-compose.production.yml` beside
`traefik`/`postgres`/`redis` rather than under a colour profile.

| Listener | Purpose |
| --- | --- |
| `3478/udp` | the normal path |
| `3478/tcp` | for egress filters that drop UDP |
| `49152–49999/udp` | relay allocations |

The relay range is bounded on purpose. Stock coturn suggests ~10k ports; a 1-on-1 platform needs
hundreds, and a tight range is a firewall rule a human can read and verify.

**DNS: `turn-staging.kaleem.academy`, DNS-only (grey cloud).** Cloudflare cannot proxy UDP, and a
proxied record breaks every allocation with no error a client can interpret. This also publishes
the origin IP that the proxied records currently hide — a real consequence, stated so nobody
discovers it later.

### Hardening — part of the spec, not the plan

An unfenced TURN server is two things at once: an SSRF pivot that will happily relay a packet
into the private Docker network, and a DDoS amplifier with somebody else's return address.

- `denied-peer-ip` covering every RFC1918 range, loopback, and link-local.
- `no-multicast-peers`.
- `user-quota` and `total-quota`, so one credential cannot exhaust the relay range.
- No CLI listener.
- `realm` set explicitly; no `lt-cred-mech` user database of any kind.

### Credentials

```text
username  = "<unix-expiry>:<user-id>"
password  = base64(HMAC-SHA1(TURN_SECRET, username))
```

HMAC-SHA1 is **mandated by the scheme**, not chosen — everything else in this repo signs with
SHA-256, so the code says so at the call site. It is an HMAC, so SHA-1's collision weakness does
not apply to it.

coturn holds only `static-auth-secret`. There is no account to disable; the expiry in the
username is the whole revocation story, which is why it is short and why it is tied to the room's
own lifetime.

New settings, both read by Django only:

- `DJANGO_TURN_SECRET` — the shared HMAC key.
- `DJANGO_TURN_URLS` — comma-separated ICE URLs (`stun:…:3478`, `turn:…:3478?transport=udp`,
  `turn:…:3478?transport=tcp`).

Minting lives in `backend/kaleem/scheduling/providers/turn.py` as one pure function: secret,
urls, user id and expiry in; ICE servers out. No ORM, no settings read inside it.

### Delivery

`JoinGrant` gains `ice_servers`; `JoinGrantSerializer` gains it as a nested read-only field. No
new endpoint: `POST /api/v1/scheduling/sessions/<id>/join/` is already authenticated, already
participant-guarded and already window-guarded, so the credentials inherit exactly the
authorization that admits someone to the room. A second endpoint would duplicate that question
and invite the two answers to diverge.

`SignalingProvider` mints them and **fails closed** on a missing `DJANGO_TURN_SECRET` or
`DJANGO_TURN_URLS`, symmetric with what it already does for the signaling secret. "TURN is not
optional" has to be enforced by the process refusing to start, not by a sentence in a runbook.

`FakeVideoProvider` returns an empty list. The fake has no relay and must not pretend it does.

## The token leaves the query string

The client opens `new WebSocket(url, ["kaleem.signaling.v1", token])`. The browser sends both
values in `Sec-WebSocket-Protocol`; the server selects and echoes **`kaleem.signaling.v1`**, never
the token — echoing the token only moves it into the response headers.

Two details decide whether this works at all:

- **The grammar fits.** Subprotocol values are RFC 7230 tokens. Ours is `base64url . base64url`,
  drawing only on `A-Za-z0-9-_.`, every character a valid `tchar`. No escaping layer is needed —
  if that were not true this approach would not be available.
- **The refusal path must still `accept(subprotocol=…)` before closing 4401.** A client that
  offered subprotocols and receives an accept selecting none must fail the connection per
  RFC 6455; the browser would then surface a generic handshake error and destroy the
  4400/4401/4409/4410 vocabulary C3b built. Every signaling test runs through Starlette's
  `TestClient`, which is exactly the layer that would not notice — the same blind spot that hid
  C3b's uvicorn token logging.

A connection arriving with no subprotocol, or with only `kaleem.signaling.v1` and no second
value, is refused with `CLOSE_UNAUTHORIZED`. No new close code: the fixed vocabulary stays fixed.

`SignalingProvider.get_join_url` stops embedding `?t=`. `JoinGrant` carries `join_url` and
`token` as separate fields, both in the POST response body.

### What this does *not* buy: Traefik's `RequestPath`

`ISSUES.md` records the plan to restore Traefik's dropped `RequestPath` field once the token
leaves the query string. **That is not safe and this spec withdraws it.** `config/urls.py`
includes `allauth.urls`, which serves `/accounts/confirm-email/<key>/` and
`/accounts/password/reset/key/<uidb36>-<key>/`. Those are single-use account-takeover credentials
in the **path**, not the query string, so removing the signaling token changes nothing about
whether `RequestPath` is safe to log. Traefik still has no per-router access-log configuration and
no partial-field redaction.

`RequestPath` therefore stays dropped, and the lost visibility is recovered where it was actually
lost: **dashboard and marketing get path-level logging from their own container access logs**, the
same compensating control Django already has through gunicorn. The `ISSUES.md` entry is rewritten
to say this rather than to keep promising a rollback that cannot be taken.

The token move is still worth making on its own terms — a query string leaks to `Referer`, to
browser history, and to every future proxy or CDN hop, and each new hop is a new leak to find.

## A room is pinned to one colour

`ISSUES.md` describes a deploy splitting a room in two: `signaling-blue` and `signaling-green`
both claim `Host(${WS_DOMAIN})`, so between the new colour starting and the old one stopping,
Traefik spreads one hostname across two processes and two participants can each sit alone in a
one-peer room — no `peer-joined`, no error, no close code, every health check green.

**The issue's fix (a) — a colour-pinned WS hostname — is necessary and not sufficient.**
`django-blue` and `django-green` both claim `Host(${API_DOMAIN})` as well, so during the same
window two participants can be served their join grants by *different Django colours* and
straddle anyway. Hostname pinning narrows the window; it does not close it.

C3c does both halves:

1. **Per-colour hostnames.** `WS_BLUE_DOMAIN` / `WS_GREEN_DOMAIN`; each `signaling-*` router
   claims only its own. `DJANGO_SIGNALING_URL` is overridden per Django colour in the service's
   own `environment:` block, above the shared `env_file`. `WS_DOMAIN` is retired — an alias would
   reintroduce exactly the straddle being removed.
2. **The colour is a property of the room.** `Room` gains `signaling_url`, written by the first
   joiner inside `_ensure_room` and read by every later joiner. That code already runs under the
   session row lock C3a added, so the pin is race-free without new machinery. Two people in one
   lesson then receive the same host regardless of which Django colour served them.

**Trade-off, stated rather than hidden:** a room pinned to a colour that is later stopped fails
loudly on a rejoin, where today it would silently succeed into a split room. Loud beats
undetectable, and the runbook's interim rule — deploy between lessons — already bounds it.

Fix (b), the real drain, is **not attempted here**. *A deploy drops every live call* stays open in
`ISSUES.md`; it needs a join-routing switch that does not exist, and bolting one on as a side
change to a TURN phase is how the C3a lock bug happened.

## The grant's expiry

`GRANT_TTL` is deleted rather than clamped. `expires_at = join_window(session)[1]` — the grant
dies exactly when the room stops being enterable.

The flat 30 minutes was wrong in both directions at once: a grant minted the moment the window
opens died 40 minutes before a 60-minute lesson ended, and one minted at the window's close
outlived the window by 30. A constant that has to be reconciled against another constant is two
places for the truth to live. The window is already computed in one place (`join_window`), and
now the grant and the TURN credentials both derive from it.

## Testing

**Unit — credential minting.** The username shape, the HMAC, the expiry derivation, the URL list
parse, and the fail-closed behaviour on each missing setting. Pure function, no fixtures.

**Unit — the grant.** `expires_at` equals the window close for a session at the start of its
window, at the end of it, and for lessons of different lengths — the three cases the flat TTL got
wrong. `ice_servers` present for `SignalingProvider`, empty for `FakeVideoProvider`.

**Component — the join endpoint.** The serialized payload carries `join_url`, `token` and
`ice_servers`, and `join_url` no longer contains `?t=`.

**Signaling — the handshake.** Accepts a token in `Sec-WebSocket-Protocol`; refuses a missing
subprotocol, a subprotocol-only offer, a malformed token and an expired one, each with 4401;
**echoes `kaleem.signaling.v1` and never the token**; and — the assertion that matters — a
refused connection still receives the selected subprotocol so the close code survives.

**Room pinning.** Two joins to one session return the same `join_url` host after the setting
changes underneath them between the calls. This is the test that would fail if the pin were read
from settings rather than from the row.

**Live verification, and it is not optional.** C3b shipped a Critical that every green suite was
structurally unable to see, because the bug lived in uvicorn and every test ran through
`TestClient`. The same shape of blind spot applies here: nothing in the Python suite proves a UDP
packet traverses coturn.

- `turnutils_uclient` against staging with a minted credential — proves the relay allocates and
  that the HMAC kaleem computes is the one coturn expects.
- A **throwaway** page holding two `RTCPeerConnection`s with `iceTransportPolicy: 'relay'`,
  driven by hand against staging. Relay-only forces every candidate through coturn, so a
  connection proves the path end to end. Labelled throwaway, not committed to `dashboard/`; C3d
  owns the real client and should not inherit a scaffold written before its design.
- **Mutation-checked:** breaking the HMAC secret must make both fail.

**No new e2e flow.** CI has no coturn and no media, and there is still no user-facing behaviour to
drive — the same reasoning that made C3b `❌ by design` in the D3 table. C3c is added to that table
with that reason, and e2e stays at 33.

## Out of scope

- **`turns:` on 5349 or 443** — decision 3, logged to `ISSUES.md`.
- **The real drain** — fix (b) of the split-room issue.
- **Any browser code** — C3d.
- **TURN capacity planning, bandwidth metering, per-tenant quotas** — one VPS, staging only.
- **Production TURN** — production does not exist yet.

## Risks

- **The relay range and the firewall must agree.** A UDP range open in coturn and closed at the
  provider's firewall produces allocations that succeed and media that never arrives — a failure
  that looks like a client bug. Verified explicitly, not assumed.
- **Retiring `WS_DOMAIN` is a breaking env change.** A staging box still carrying the old variable
  and not the two new ones must have the deploy **abort**, not ship broken.
  `scripts/ship.sh`'s signaling health check (`docker exec ... curl
  http://localhost:9000/health/live/`) is container-local — it cannot see whether Traefik's
  `Host()` rule, DNS, or a certificate exist, so it passes regardless. Left unguarded, an unset
  `WS_BLUE_DOMAIN`/`WS_GREEN_DOMAIN` expands to the truthy literal `wss://`, defeats
  `SignalingProvider`'s own fail-closed check, and PERSISTS a broken `Room.signaling_url` to every
  later joiner — a **green deploy with a dead router**, not a failed health check and a colour
  rollback. `docker-compose.production.yml` guards both variables with Compose's `${VAR:?message}`
  mandatory syntax instead, so the deploy fails at `docker compose up` rather than after. The
  runbook step and the two new DNS records (`ws-blue-staging`/`ws-green-staging`, replacing the
  retired `ws-staging`) land in the same PR as the compose change.
- **`Room.signaling_url` on existing rows.** The migration adds it nullable; a room created before
  the migration reads `NULL` and must fall back to the configured URL rather than raise. Staging
  has live rooms.
