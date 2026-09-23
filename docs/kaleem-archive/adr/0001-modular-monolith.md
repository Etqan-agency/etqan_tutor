---
number: "0001"
title: Modular monolith architecture
status: accepted
date: 2026-04-12
---

## Context
kaleem needs a backend architecture that enforces boundaries between business domains while remaining simple enough for a solo developer.

## Decision
Django modular monolith with 11 modules (identity, billing, scheduling, assessment, curriculum, content, messaging, notifications, engagement, analytics, platform). Module boundaries enforced by import-linter in CI.

## Alternatives considered
- **Flat monolith**: simpler but produced the current tangle of cross-app imports.
- **Microservices**: too much plumbing overhead for a solo developer.

## Consequences
- Clear ownership: each module has defined data, public API, and dependencies.
- Enforcement is automated — violations fail CI.
- Any module can be extracted to a service later if needed (escape hatch E5).
- Slightly more discipline required upfront compared to a flat monolith.
