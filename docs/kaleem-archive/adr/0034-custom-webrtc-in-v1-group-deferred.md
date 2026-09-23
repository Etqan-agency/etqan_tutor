---
number: 0034
title: Build 1-on-1 WebRTC in v1; defer group sessions
status: accepted
date: 2026-09-05
supersedes: 0011
---

## Context

ADR-0011 decided **Zoom for v1, custom WebRTC for v2**, sizing the custom build at 15–25 specs
and 6–12 months. That decision is now reversed by the user, deliberately and with the cost
stated.

Two facts changed the arithmetic:

**Zoom's free tier caps every meeting at 40 minutes, including 1-on-1.** kaleem's
`SESSION_DURATION_MINUTES` is 60. So the v1 path in ADR-0011 was never free — it required a
paid Zoom account and a Server-to-Server OAuth app before a single lesson could run.

**ADR-0011's 6–12 month estimate priced the wrong system.** It covered an SFU, group calls,
recording, and bandwidth adaptation. Restricted to **1-on-1**, media goes peer-to-peer, there
is no media server in the path, and the backend's job reduces to signaling plus authorization.
That is a different engineering category, and a materially smaller one.

## Decision

**kaleem builds its own 1-on-1 WebRTC video service in v1. There is no Zoom adapter.**

**Group sessions are deferred to their own later phase.** Peer-to-peer degrades past roughly
three participants — every browser uploads a separate stream to every other participant, which
ordinary home upstream cannot carry. Group requires an SFU, and an SFU is the part ADR-0011
correctly priced in quarters.

**Recording is out of the arc entirely.** It needs server-side media ingest, which is an SFU
under another name.

ADR-0011's adapter interface survives unchanged — `create_room`, `get_join_url`, `end_room`.
It was designed to outlive a provider swap, and it does, including this one.

Video ships as five slices, in dependency order: **C3a** rooms and the provider seam, **C3b**
signaling, **C3c** STUN/TURN, **C3d** the call client, **C3e** browser hardening.

## Alternatives considered

**Zoom on a paid account, as ADR-0011 wrote it.** Proven infrastructure, recording and waiting
rooms for free, and a name parents recognise. Rejected by the user, who wants to own the video
stack.

**Zoom now, custom later — the ADR-0011 sequence, honoured.** Would ship lessons soonest.
Rejected: it means building the whole thing twice, and the second build is the one that was
always going to happen.

**Jitsi Meet as an interim.** No account, no keys, no meeting cap; a room is a URL. Rejected
for the same reason — an interim provider is work thrown away.

**LiveKit, self-hosted.** The middle ground ADR-0011 already floated: an SFU that would carry
group as well as 1-on-1. Rejected for the same ownership reason, and noted here because it is
the obvious candidate if group arrives before an in-house SFU does.

## Consequences

**Good.**

- No vendor cost, no per-seat pricing, no 40-minute cap on a 60-minute lesson.
- kaleem owns the stack it considers strategic, and owns it once rather than twice.
- C3a is unaffected by any of this. Room lifecycle, authorization, and the provider seam are
  identical whether media is P2P, an SFU, or a vendor — which is why that slice goes first and
  ships behind a fake provider.

**Bad, or at least owed.**

- **The roadmap's v1 scope lists "1-on-1 and group sessions."** Group is now out of v1. That is
  a visible product reduction, recorded here rather than discovered at launch.
- **A TURN server is mandatory, not optional.** Roughly one connection in six cannot establish
  peer-to-peer — symmetric NAT, corporate networks, some mobile carriers — and those calls fail
  outright without a relay. `coturn` becomes a new service in `infra` carrying real bandwidth
  cost, with HMAC-derived ephemeral credentials; a static TURN password is a resource anyone can
  steal. This is C3c and it is not skippable.
- **Signaling needs ASGI, which production does not serve today.** `config/asgi.py` exists but
  the backend runs `gunicorn` WSGI; nothing serves the ASGI app. WebSockets mean Django Channels
  and a process-model change in `infra`. Redis is already present for Celery, so the channel
  layer costs nothing extra. **That change gets its own ADR when C3b is specced** — not a line in
  an implementation PR.
- **No recording** means no dispute evidence and no lesson replay. If either becomes a
  requirement, it reopens the SFU decision rather than being added to the P2P path.
- Safari and iOS have their own WebRTC behaviour, and parents on iPhones are not an edge case.
  C3e exists for this and must not be dropped as "polish".
