---
number: 0030
title: Secret, dependency and performance scanning actually run — gitleaks and pip-audit block merges, Lighthouse runs nightly against staging
status: accepted
date: 2026-09-04
amends: ADR-0021 (the security/performance clauses of the Definition of Done)
---

## Context

Since 2026-06-17 the Definition of Done has asked for a security pass and a
performance budget. Neither has ever executed. `semgrep`, `pip-audit`, `trivy` and
`lhci` are absent from every workflow, so "no known CVEs" and "Core Web Vitals are
fine" have been satisfied by a human saying so at handoff time. `backend`'s
pre-commit does run a `gitleaks` hook, so committed secrets have *some* cover on a
developer machine that has pre-commit installed — and nothing covers the meta repo,
the dashboard, or a commit pushed from anywhere else.

This is the exact shape ADR-0026 and ADR-0027 found in the coverage and e2e clauses:
a documented gate that does not run. Both were closed the same way — make it execute,
scope it honestly, write down what it does not cover.

Standing the gate up immediately found things:

- **Live credentials sit in this repo's git history.** `kaleem/.envs/.production/.django`
  (commit `588a1e35`, 2026-04-12) carries an `sk_live_…` Stripe secret key, an AWS
  `AKIA…` access key + secret, a Django `SECRET_KEY`, and Flower basic-auth
  credentials. The files were deleted from the tree; history keeps them. Rotation is
  an operational task tracked in `ISSUES.md`, not something an ADR can fix.
- **A stray Playwright accessibility dump, `portal-snapshot.md`, was committed to the
  meta repo root** (`3bfb0705`, 2026-09-03), carrying a Stripe test-mode billing-portal
  session secret. Deleted here.
- The marketing site ships **no meta description**; the dashboard login page has a
  **colour-contrast failure**, **console errors**, and an **invalid `robots.txt`**.

## Decision

**Three scanners, each with a stated scope, each red for a real reason.**

1. **`gitleaks` blocks merges** — a `security` job in `ci.yml`, in `deploy-staging`'s
   `needs:`. It runs the pinned `zricethezav/gitleaks:v8.30.1` image twice: once in
   git mode over the **full meta history** (`fetch-depth: 0`), once in directory mode
   over the **checked-out tree including every submodule**, which is where a secret
   would actually reach staging from. Submodule *histories* are not scanned by this
   job; their pre-commit hooks are the only cover there, and that is a known gap.

2. **The historical leaks are allowlisted by fingerprint in `.gitleaksignore`, one
   annotated line each — not by disabling the rule and not by rewriting history.** A
   rewrite would break every submodule pointer and every SHA quoted across
   `docs/`, and would not un-leak anything: rotation is the remedy, and the
   fingerprints keep the exposure legible rather than silently suppressed. ~~Removing a
   line is how a rotated credential gets recorded as dealt with.~~ **AMENDED BY ADR-0032
   (2026-09-05): a rotated credential KEEPS its fingerprint and is re-annotated instead.
   Removing the line would make gitleaks report the still-in-history string again and turn
   CI permanently red — rotation makes a credential dead, not absent.**

3. **`pip-audit` blocks merges, and audits `requirements/production.txt` only.** It
   installs the production set into a clean environment and audits what is actually
   installed, rather than resolving a requirements file, so what is scanned is what
   ships. Dev-only dependencies are deliberately out of scope: a CVE in `pytest` does
   not reach a user, and a gate that goes red for something that cannot hurt anyone is
   a gate people learn to click past. Baseline at adoption: **no known
   vulnerabilities**.

4. **Lighthouse runs nightly against staging, not in the merge path** — its own
   workflow on `schedule` + `workflow_dispatch`, exactly like the Stripe test-clock
   harness (ADR: see the 2026-09-04 dunning spec). It cannot be a merge gate because
   it measures a *deployed* environment, and staging only exists after the merge. A
   red run is a real failure.

5. **The Lighthouse thresholds are ratchet floors set to the measured value, in the
   ADR-0026 sense** — not aspirational 100s. Measured 2026-09-04, desktop preset:

   | URL | perf | a11y | best-practices | seo |
   | --- | --- | --- | --- | --- |
   | `staging.kaleem.academy` (marketing) | 100 | 100 | 81 | 91 |
   | `app-staging.kaleem.academy` (login page) | 98 | 96 | 78 | 82 |

   Floors are set just below those, plus absolute Core Web Vitals budgets (LCP ≤ 2.5s,
   CLS ≤ 0.1, TBT ≤ 200ms). **Lowering a floor needs an ADR; raising one is a normal
   part of any PR that improves a score.** The individual audit failures behind the
   sub-100 categories are recorded in `ISSUES.md` rather than fixed here (D10).

6. **The dashboard is measured on its login page only.** Everything behind it needs a
   session, and a scanner carrying a seeded credential against a shared environment is
   a bigger decision than this one. Said plainly rather than implied.

## Alternatives considered

- **`gitleaks-action`.** Requires a paid licence key for organisation repos; this repo
  is under `kaleem-lms`. The pinned image costs one `docker run` and no licence.
- **Rewrite history to purge the leaked env files** (`git filter-repo`). Rejected:
  breaks every recorded SHA and submodule pointer, and does not rotate anything —
  which is the only step that actually revokes a leaked key.
- **`--redact` off in CI so failures are readable.** Rejected: CI logs are the least
  private place in the project. A fingerprint plus a file and line is enough to find it
  locally.
- **`semgrep` and `trivy` in the same PR.** Deferred deliberately. Both need triage
  budgets of their own — a SAST tool adopted with 200 findings gets muted within a
  week. `ISSUES.md` keeps them named.
- **Lighthouse as a blocking PR check against a preview build.** Rejected for now:
  there is no per-PR environment, and measuring `vite preview` on a CI runner would
  test the runner's CPU contention rather than the delivered site.
- **Audit dev dependencies too.** Rejected — see point 3.

## Consequences

**Good**

- The oldest un-run gate in the project runs. `CLAUDE.md`'s Definition of Done stops
  asserting a check that has never executed.
- A committed secret now fails a PR, in every repo the deploy is built from.
- The pre-existing leak is documented with fingerprints and a rotation task, instead of
  living undiscovered in history.
- Performance and accessibility of the delivered site are measured every night against
  numbers that were true when written.

**Bad / costs**

- Two more required checks per PR (~1 min combined) and a nightly workflow to keep
  green.
- **Submodule git histories are unscanned.** Only the meta history and the current
  tree are covered.
- `.gitleaksignore` is a suppression list, and suppression lists rot. It is annotated
  per line so a stale entry is visible, but nothing enforces that.
- The Lighthouse floors are tied to staging's current shape; a real regression and a
  noisy network run look the same in a single nightly sample. One retry, then read the
  artefact.
