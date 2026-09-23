---
name: <short-name>
phase: 0 | A | B | C | D | E
modules: [identity, billing, ...]
status: draft | approved | in-progress | shipped | abandoned
created: YYYY-MM-DD
closed: YYYY-MM-DD | null
---

## Goal

One paragraph: what and why.

## User flow

Step by step, from the user's POV. Include error cases.

## Data model delta

New tables, new fields, new relationships. Include a mini ERD.

## API delta

New endpoints, changed endpoints, removed endpoints. Request/response shape.

## Frontend

Required for every feature. The dashboard slice that exposes this:
- Routes (TanStack Router paths) and which role(s) see them.
- Components / states (loading, empty, error, success).
- API calls (which endpoints, via `src/lib/api.ts`).
- "Done" = built, deployed to staging, and verified in the browser end-to-end.

## Module boundaries

Which module owns this? What other modules does it call? Any new events?

## Out of scope

What this spec explicitly does NOT do.

## Test plan

Happy path + edge cases + failure cases that must pass.

## Open questions

Must be resolved before implementation begins.
