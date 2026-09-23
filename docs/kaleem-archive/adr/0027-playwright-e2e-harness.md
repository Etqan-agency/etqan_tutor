---
number: 0027
title: The e2e harness exists, is scoped to identity, and mirrors the production subdomain topology
status: accepted
date: 2026-09-03
amends: ADR-0021 (clause 3), ADR-0026 (D3 table)
---

## Context

ADR-0021 clause 3 has required Playwright e2e for every user-facing feature since
2026-06-17. No harness existed until 2026-09-03 — nearly three months and two phases —
and ADR-0026 had to record the clause as **not in force** to stop `CLAUDE.md` asserting
something untrue.

The substitute in that period was a human clicking through staging. That is not a
formality: on 2026-09-03 a single manual click-through found **two real defects** — a
subscription created with no renewal date (a race between two concurrently delivered
webhooks) and a 403 telling users to retry something that could never succeed. The
backend was at 97% coverage with `kaleem.billing` at 100% line+branch, and 363 dashboard
tests were green. Neither defect was reachable by either suite, because both lived in the
seam between a real browser, real cookies, and a real server.

## Decision

**Build the harness, scope it honestly, and say exactly what it covers.**

1. **`dashboard/e2e/`, Playwright, blocking in CI from day one** (D5). Vitest keeps
   `src/**/*.test.tsx` with mocked modules; Playwright gets a real build and a real
   server. No overlap.

2. **CI mirrors the ADR-0019 subdomain topology** — `app.kaleem.localhost:4173` and
   `api.kaleem.localhost:8000` with `SESSION_COOKIE_DOMAIN=.kaleem.localhost` — rather
   than serving both halves from `localhost` on two ports. **Cookies ignore ports**, so
   the `localhost` arrangement would share a session by accident and prove nothing about
   the cross-subdomain cookie production depends on. Proving that cookie is the single
   thing this suite can do that vitest cannot.

3. **No Compose, no Traefik in CI.** Postgres and Redis as GitHub services, Django via
   `runserver`, the dashboard via `vite preview` on a production build. Compose would be
   higher fidelity and minutes slower; the fidelity that matters is in point 2.

4. **Selectors are role + accessible name; `data-testid` is not used.** A `data-testid`
   passes happily on a control no screen reader can name. Role/name assertions break when
   the accessible name does, so the suite is also a WCAG 2.2 AA regression net (ADR-0020)
   at no extra cost.

5. **Retries are 1 in CI, 0 locally — and a retry-pass is a finding, not a pass.** The
   standard cure for e2e flakiness turns an intermittent real bug green and teaches people
   to re-run CI, which is how a blocking gate quietly stops working.

6. **Scope is `identity` only, and `CLAUDE.md` says so in a table.** Six flows. Billing is
   excluded *by design* — the hosted Stripe redirect cannot run in Playwright, so card →
   checkout → webhook stays a manual staging test. Everything else is simply not done yet.
   ADR-0021's clause is therefore **partially** un-suspended, not restored wholesale.

## Alternatives considered

- **Cypress.** Comparable capability. Rejected on nothing stronger than Playwright's
  better multi-origin story, which this topology leans on directly.
- **Serve both from `localhost:PORT`.** Simplest CI. Rejected: see point 2 — it would make
  the suite pass while telling us nothing about the one integration that has broken before.
- **Docker Compose in CI for full fidelity.** Rejected as several minutes per PR for
  fidelity already covered more cheaply.
- **Non-blocking at first, "until it's stable".** Rejected: a non-blocking gate is a gate
  nobody fixes. Blocking with a deliberately small suite is what makes the flakiness rule
  in point 5 affordable.
- **Cover every existing feature now.** Rejected as a different, larger project. Standing
  the harness up and proving it on identity is the slice; conversions are follow-on, and
  the `CLAUDE.md` table keeps the gap visible instead of implied.

## Consequences

**Good**

- The last wholly-unmet ADR-0021 clause is partly met, and `CLAUDE.md` describes reality.
- The cross-subdomain session cookie — broken once, invisible to every unit test — now has
  automated cover on every PR.
- Role/name selectors give a11y regression cover for free.
- `manage.py seed_e2e` gives deterministic accounts, replacing a `seed` stub that had been
  printing "requires the identity module (Phase A)" since Phase A closed.

**Bad / costs**

- Every PR now pays for a browser install, a build, and two servers. Mitigated by a small
  suite and chromium only, but it is the slowest job in CI.
- **Coverage is narrow and the table will go stale unless people maintain it.** A table
  claiming less than reality is harmless; one claiming more is how we got here.
- E2E is the most brittle test class there is. The no-silent-retries rule is a discipline,
  not a mechanism, and nothing enforces it except review.
- `config.settings.local` grew CI-shaped concessions (`:4173`/`:8000` origins, an
  overridable email backend). Small, but dev settings now serve two masters.
