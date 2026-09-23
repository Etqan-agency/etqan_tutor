---
number: 0026
title: Coverage is a ratchet floor that CI enforces, not an aspirational 100%
status: accepted
date: 2026-09-03
supersedes: partially supersedes ADR-0021 (clause 1)
---

## Context

ADR-0021 (2026-06-17) made "100% coverage, line and branch, machine-enforced in CI, in
every repo" a shipping gate, and `CLAUDE.md` D3 states it as fact. **Nearly three months
later, none of it runs.**

Measured 2026-09-03, on `master` as deployed to staging:

| Repo | What `CLAUDE.md` claims | What CI actually does |
| --- | --- | --- |
| `backend` | 100% line+branch, `fail_under = 100` | runs `pytest --cov --cov-branch`, **no `--cov-fail-under`**; sits at ~97% |
| `dashboard` | 100% line+branch, thresholds at 100 | **never runs `pnpm test`**, never runs biome; `@vitest/coverage-v8` was **not installed**, so coverage was not measurable at all |
| `marketing` | 100% line+branch | build only |
| all | e2e (Playwright) for every user-facing feature | **no Playwright harness exists anywhere** (built 2026-09-03 — ADR-0027) |

The gap is not an oversight anyone hid — the backend omission is commented in `ci.yml`
and both gaps are logged in `ISSUES.md`. It is the *duration* that matters: two full
phases (A and B) shipped under a rule that never once executed. During the B1 billing
review, reviewers substituted **manual branch enumeration by hand** for the dashboard
because the tool to check it was absent.

This is worse than having no rule. Three specific harms:

1. **It manufactures false confidence.** "100% coverage enforced" in `CLAUDE.md` reads as
   a fact about the codebase. It is a fact about nobody's codebase.
2. **It poisons the rest of the document for AI agents.** `CLAUDE.md` is auto-loaded as
   ground truth at the start of every session. An agent that discovers one load-bearing
   claim is aspirational has no way to tell which of the remaining rules are real. The
   value of the file is that it is trustworthy, and a single false clause is contagious.
3. **It cannot ever be adopted.** Turning on `fail_under = 100` today fails every
   unrelated PR because of pre-existing gaps in `identity`/`platform`, so the honest
   move is always "not this PR" — which is exactly how it stayed off for three months.
   A gate whose adoption cost is paid entirely by whoever happens to touch it next never
   gets adopted.

The owner decision on 2026-07-30 ("measure now, enforce once the gaps are backfilled")
was right in spirit but had no mechanism: nothing forces the backfill, and nothing stops
coverage drifting *down* in the meantime.

## Decision

**Replace the aspirational 100% target with a ratchet floor that is enforced from today,
at whatever the number currently is.**

1. **Each repo pins a coverage floor at its measured current value, rounded down**, in
   the repo's own config (not in CI), so the gate runs identically locally and in CI:
   - `backend` — `fail_under` in `[tool.coverage.report]` in `pyproject.toml`
   - `dashboard` / `marketing` — `test.coverage.thresholds` in `vitest.config.ts`

2. **The floor may only go up.** Raising it is a normal part of any PR that lifts
   coverage. **Lowering it requires an ADR** — that is the whole mechanism. A PR that
   drops coverage goes red and the author either writes the test or argues the case in
   public; it is never a silent config edit.

3. **100% line + branch remains the target**, and ADR-0021's other clauses stand
   unchanged: per-line justified exclusions only (never blanket file or directory
   exclusions of business logic), and reviewers hold the line on test *quality* rather
   than the number.

4. **`CLAUDE.md` D3 must state what is enforced today**, with the current floors, not the
   aspiration. When a floor moves, D3 moves with it.

5. **E2E (ADR-0021 clause 3) is explicitly marked NOT YET IN FORCE** in `CLAUDE.md` and
   `ISSUES.md` until a Playwright harness exists. Standing one up is its own D1 slice.
   **Superseded 2026-09-03 by ADR-0027:** the harness now exists and blocks CI, so the
   clause is in force for `identity` and still suspended for everything else.
   Until then D9's manual browser click-through is the honest substitute, and specs must
   say so rather than claiming e2e coverage they do not have.

Floors set by this ADR (measured 2026-09-03):

| Repo | Lines / statements | Branches | Functions |
| --- | --- | --- | --- |
| `dashboard` | 92 | 87 | 84 |
| `backend` | see `pyproject.toml` (set to the measured value at adoption) | same | — |
| `marketing` | deferred — no test suite exists yet | | |

## Alternatives considered

- **Keep 100% and backfill `identity`/`platform` first, then switch it on.** The stated
  plan since 2026-07-30. Rejected: it has had three months and two phases to happen. It
  also leaves coverage unprotected in the meantime — today nothing stops a PR taking the
  backend from 97% to 60%. The ratchet protects the number *while* the backfill happens,
  and does not compete with feature work for the same slot.
- **Drop the coverage gate entirely and rely on review.** Rejected: review is what
  already failed here (manual branch enumeration by hand during the billing review). The
  MVP's bug classes — orphaned wiring, untested services — are exactly what a mechanical
  gate catches and a tired reviewer does not.
- **Enforce in CI only, leaving local config bare.** Rejected: the developer then finds
  out at PR time rather than before pushing, and the gate cannot be reproduced locally to
  debug. Config in the repo, CI just invokes it.
- **Per-module floors (e.g. `billing` at 100, `identity` at 90).** More precise —
  `billing` genuinely is at 100% and this ADR lets it regress to the repo floor.
  Rejected *for now* as premature: one number per repo is understandable at a glance and
  cheap to maintain solo. Revisit if a module's coverage is deliberately sacrificed.

## Consequences

**Good**

- The gate is real on the day this merges, in the repo where it was never measurable at
  all. Coverage cannot silently drift down any more.
- `CLAUDE.md` becomes true again. Every other rule in it regains its credibility for the
  agents that read it as ground truth.
- Adoption cost is zero — the floor is set to what already passes — so the usual "not
  this PR" escape does not apply.
- The backfill toward 100% becomes incremental and voluntary rather than one blocking
  project, and every increment is locked in permanently by the ratchet.

**Bad / costs**

- The floors are well below 100%, so this ADR *reduces the stated standard*. That is the
  point — it trades a number nobody enforced for a smaller number everyone does — but it
  should be read honestly as a retreat from ADR-0021's ambition, not as progress toward
  it.
- A ratchet tolerates permanent mediocrity if nobody ever raises it. Nothing here forces
  the floor upward. The weekly D7 review is the intended pressure; if the floors have not
  moved in a quarter, that is a finding for the journal.
- Rounding down leaves a small buffer (e.g. 92.88% measured, floor 92), so a genuine
  ~0.9% regression can still slip through unnoticed.
- Marketing remains ungated because it has no tests. This ADR does not fix that; it
  records it.
