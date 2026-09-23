---
number: 0021
title: 100% test coverage and end-to-end tests are a shipping gate in every repo
status: accepted
date: 2026-06-17
---

## Context

The old MVP shipped untested code: orphaned ViewSets, business logic on models with no
tests, serializers with `print()` left in. Bugs that a single test would have caught reached
production. The rebuild's process (D3 Test-driven development) sets a target of **≥ 80%
coverage on services/models**, and D9 (Definition of Done) requires "tests passing" plus a
manual browser check — but neither pins a hard, machine-enforced number, and neither requires
automated end-to-end coverage of user-facing flows. "Target ≥ 80%" is a goal CI does not fail
on; "manual test in browser" is a human step that does not run on every change.

The user has stated, explicitly, that **no task — in `backend`, `dashboard`, or `marketing` —
should ship until it has full test coverage and is exercised by end-to-end tests.** This is a
strengthening of D3/D5/D9, and because it changes the coverage target baked into D3 it needs
to be recorded as a decision (per CLAUDE.md, changes to the process and to `CLAUDE.md` are
decisions requiring an ADR).

The known failure mode of a "100% coverage" rule is that it pushes teams to write hollow tests
for trivial or genuinely untestable lines (migrations, `__repr__`, generated code, defensive
branches that cannot occur). The way to make 100% real rather than gamed is a hard CI gate at
100% combined with a **narrow, explicit, reviewed per-line exclusion** mechanism — never
blanket file/directory exclusions for business logic.

## Decision

**Full test coverage and end-to-end tests are a non-negotiable shipping gate, binding on every
repo and submodule (`backend`, `dashboard`, `marketing`, and all future submodules).** A change
does not merge and does not deploy unless both are green in CI.

Concretely:

1. **100% coverage, enforced in CI, line *and* branch.**
   - Backend: `pytest --cov --cov-branch` with `fail_under = 100` in the coverage config. CI
     fails below 100%.
   - Frontend (`dashboard`, `marketing`): the test runner's coverage thresholds
     (`lines`, `branches`, `functions`, `statements`) are all set to `100`. CI fails below.
   - Coverage runs on every PR. A red coverage gate blocks merge exactly like a failing test
     (D5: no `--no-verify`, no exceptions).

2. **Exclusions are per-line, explicit, and justified — never blanket.**
   - The only way to drop a line from the denominator is an inline pragma with a one-line
     reason on the same or preceding line: `# pragma: no cover  # <why>` (Python),
     `/* c8 ignore next -- <why> */` or `/* v8 ignore next -- <why> */` (TS/JS).
   - Permitted reasons: framework boilerplate that cannot execute under test, defensive
     `assert`/`raise` for truly unreachable states, third-party glue with no logic.
   - **Forbidden:** excluding whole files or directories of business logic, excluding a module
     to "get CI green", or excluding `services.py` / `models.py` logic. Reviewers reject these.
   - Migrations, settings, and generated files may be excluded at the config level (they carry
     no hand-written logic); this exclusion list lives in the coverage config and is reviewed
     like code.

3. **End-to-end tests for every user-facing feature.**
   - Every feature that a student, parent, teacher, or admin can see or trigger ships with
     end-to-end tests (Playwright) covering the **primary happy path and the key failure
     paths** (validation error, auth/permission denied, empty/loading state).
   - E2E runs in CI against a **real built app** (built frontend + running backend), not mocks.
   - A feature with no e2e coverage of its primary flow is not done, regardless of unit
     coverage.

4. **Process changes.** This ADR:
   - **Supersedes the "≥ 80% on services/models" target in D3** — the number is now 100%,
     line and branch, machine-enforced, across all three repos (not just services/models).
   - **Extends D5** — the coverage gate and the e2e suite are part of "green CI before merge".
   - **Extends D9** — "tests passing" means 100% coverage green *and* e2e green; the manual
     browser check remains but no longer substitutes for automated e2e.

   `CLAUDE.md` (D3, D9) and `/ship` must be updated to reflect this.

## Alternatives considered

- **Keep the 80% target.** Cheapest, and 80% catches most regressions. Rejected: a *target*
  CI does not fail on is advisory, and "the 20% we skipped" is exactly where the MVP's untested
  ViewSets and serializer bugs lived. The user wants a hard gate, not a goal.
- **100% line coverage only, no branch coverage.** Easier to hit. Rejected: line-only coverage
  reports a function with an untested `else` as fully covered; branch coverage is where real
  conditional bugs hide. If we are gating, gate on the meaningful metric.
- **Coverage gate but e2e optional / manual only.** Keeps CI fast. Rejected: unit tests with
  100% coverage still pass while the wired-up feature is broken end to end (the orphaned-router
  class of bug). The user asked specifically for e2e, and integration is exactly what unit
  coverage cannot prove.
- **Blanket per-directory exclusions to ease the gate.** Rejected outright: it makes "100%" a
  lie. Exclusions are per-line and justified, or they do not happen.

## Consequences

**Good**
- The gate is machine-enforced and uniform across `backend`, `dashboard`, and `marketing` —
  no feature merges with an untested branch, and no feature merges that has never been run end
  to end.
- The MVP's failure classes (orphaned wiring, untested services, dead defensive code) become
  CI failures instead of production bugs.
- "Done" is objective and testable, consistent with the a11y/i18n baseline (ADR-0020) and D9.

**Bad / costs**
- Real discipline tax: every change carries its tests, and edge/error branches must be
  exercised, not just the happy path. Slower per-PR throughput, especially early.
- E2E suites are slower and more fragile than unit tests; they need stable selectors, seed
  data, and CI infra (a built app + backend). This is setup cost in Phase 0 tooling.
- The 100% gate can tempt hollow tests; the per-line-exclusion rule and code review are the
  guardrails, and reviewers must hold the line on test *quality*, not just the number.
- Genuinely hard-to-test code must be either restructured to be testable or explicitly,
  justifiably excluded — both are deliberate work. That friction is the point.
