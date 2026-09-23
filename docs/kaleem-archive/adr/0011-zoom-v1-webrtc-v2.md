---
number: "0011"
title: Zoom for v1 video, custom WebRTC for v2
status: superseded by ADR-0034
date: 2026-04-12
---

## Context
User wants full custom P2P/SFU video eventually. Building WebRTC from scratch is 6-12 months of specialized work (STUN/TURN, signaling, NAT traversal, SFU for groups, Safari quirks, reconnection, bandwidth adaptation).

## Decision
v1 uses Zoom via an adapter in the scheduling module. The adapter exposes a stable interface: create_room(session), get_join_url(session, user), end_room(session). v2 replaces the Zoom adapter with a custom WebRTC implementation.

## Alternatives considered
- **Custom WebRTC in v1**: rejected — would more than double the rebuild timeline.
- **LiveKit (self-hosted SFU)**: suggested as middle ground, user chose Zoom for v1 and full custom for v2.

## Consequences
- v1 ships faster with proven video infrastructure.
- The adapter pattern makes the v1->v2 swap a single-module change.
- v2 video is estimated at 15-25 additional specs, 6-12 months.
