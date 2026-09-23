---
number: "0005"
title: Full 20-feature v1 scope (user choice against recommendation)
status: accepted
date: 2026-04-12
---

## Context
During brainstorming, the recommendation was to ship a minimal "happy path" v1 (auth, billing, scheduling, assessment) and phase everything else. The user chose the full ~20-feature v1 scope.

## Decision
v1 includes all features: chat, curriculum, gamification, multi-language, dashboards, trials, group sessions, reports, resources, notifications, payouts, mobile/PWA, admin, and curriculum builder.

## Alternatives considered
- **Happy-path v1**: recommended by the agent, would have been ~3 months instead of ~18-24 months. User rejected after understanding the trade-offs.

## Consequences
- Estimated 18-24 months of solo work, ~85-100 specs.
- Risks R1 (scope creep) and R2 (burnout) elevated to top risks.
- Escape hatch E4 (phased public launch) is pre-approved if two triggers fire together.
- The happy-path recommendation is preserved as Phase B's exit gate.
