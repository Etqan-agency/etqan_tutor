---
name: playwright-e2e-harness
phase: B
modules: [platform, identity]
status: approved
created: 2026-09-03
closed: null
---

## Goal

Stand up the end-to-end test harness ADR-0021 has required since 2026-06-17 and that has
never existed. Until it does, D3's e2e clause and part of D9 are formally suspended
(ADR-0026), and the substitute is a human clicking through staging.

That substitute is not a formality. On 2026-09-03 the manual click-through found **two
real defects** — a subscription created with no renewal date, and a 403 telling users to
retry something that could never succeed — against a backend at 97% coverage with
`kaleem.billing` at 100% line+branch and 363 green dashboard tests. Neither unit suite
could have caught either, because both live in the seam between a real browser, real
cookies, and a real server.

This slice builds the harness and proves it on the identity flows. Converting the rest of
the app is follow-on work, not this spec.

## Decisions

**1. It lives in `dashboard/e2e/`, run by Playwright, separate from vitest.**
Vitest owns `src/**/*.test.tsx` with mocked modules. Playwright owns `e2e/**/*.spec.ts`
against a real built app and a real server. Different runners, no overlap, no shared
config — a test that needs a mock belongs in vitest.

**2. CI mirrors the ADR-0019 subdomain topology, not `localhost:3000`.**

```
app.kaleem.localhost:4173   the built dashboard (vite preview)
api.kaleem.localhost:8000   Django (runserver)
SESSION_COOKIE_DOMAIN=.kaleem.localhost
```

via an `/etc/hosts` line. This is the point of the whole exercise: the one thing e2e can
prove that vitest cannot is that a **real session cookie crosses a real subdomain boundary
with real CSRF**. Serving both from `localhost` on two ports would share cookies by
accident (cookies ignore ports) and prove nothing about the production topology. It also
mirrors the existing local dev stack, which already uses `*.kaleem.localhost`.

**3. No Docker Compose, no Traefik, in CI.** Postgres and Redis come from GitHub services —
the `backend-test` job already does this. Django runs via `runserver`, the dashboard via
`vite preview` on a production build. Compose would be higher fidelity and several minutes
slower; the fidelity that matters (cookie domain, CSRF, a real build) is covered above.

**4. A real seed, as `identity`'s `manage.py seed_e2e` — not `platform`'s `seed`.**

The existing `kaleem/platform/management/commands/seed.py` is a stub whose every branch
prints "requires the identity module (Phase A)". Phase A closed in July, but the command
**still cannot be implemented as written**: `import-linter`'s `platform imports no business
modules` is an *independence* contract, so a seeder living in `platform` may never call
`identity.services`. The stub is not merely unfinished, it is architecturally impossible
where it sits — logged separately in `ISSUES.md`.

So the e2e seed lives in `kaleem/identity/management/commands/seed_e2e.py`, which is where
identity fixtures belong. Deterministic and **idempotent** accounts: a verified parent, a
verified student, a verified teacher, and — deliberately — one **unverified** user, because
the login gate is one of the flows under test. Fixed emails and one shared password, defined
once in the command and imported by the specs so they cannot drift.

**5. Selectors are role + accessible name. No `data-testid`.** `getByRole("button", {name:
"Sign in"})` fails when the accessible name breaks, which is exactly what ADR-0020's WCAG
2.2 AA baseline cares about. A `data-testid` passes happily on a button no screen reader can
name. The harness doubles as an a11y regression net at no extra cost.

**6. Blocking from day one (D5), with a small suite.** The failure mode of e2e is flakiness,
and the standard cure — silent retries — turns a real intermittent bug into a green build.
`retries: 0` locally; `retries: 1` in CI, and a test that only passes on retry is logged as
a finding, not waved through. Keeping the suite small is what makes that affordable.

## Scope: flows in this slice

All identity, all reachable without an inbox:

| Flow | Asserts |
| --- | --- |
| Unverified login is refused | the D-gate that shipped broken once: the *submitted* email's verification is what counts |
| Verified login → role-aware home | the cross-subdomain session cookie, end to end |
| Sign out | session actually cleared; going back lands on `/login` |
| `_authed` guard | an anonymous visit to `/family` redirects to `/login` |
| `/verify-email?key=bad` | terminal error, **not an infinite spinner** — this regressed twice (dashboard #11, #12) |
| Language + direction | switching to Arabic sets `dir="rtl"` |

## Explicitly out of scope

- **Billing.** The hosted Stripe redirect cannot run in Playwright; card → checkout →
  webhook stays the manual staging test in `docs/runbook/stripe-billing.md` §5. Already in
  `ISSUES.md`; this spec does not change it.
- **Anything needing a real inbox** — registration, password reset, child activation. Needs
  a mail-catcher wired into CI; its own slice.
- **Converting existing features.** ADR-0021 wants e2e per user-facing feature. This slice
  builds the harness and proves it; the backlog of conversions is follow-on.
- **Cross-browser.** Chromium only. Add browsers when a rendering bug justifies the minutes.

## Module boundaries

`seed_e2e` lives in `kaleem.identity` and creates only identity data, so it needs no
cross-module call at all. This was a design correction found while writing the code: the
first draft put it in `kaleem.platform`, which `import-linter` forbids from importing any
business module (D4 caught it before implementation, which is the point of D4).

## Definition of done

- `pnpm e2e` runs locally against the dev stack.
- A CI job runs it on every PR and blocks merge (D5).
- All six flows above pass; each written to fail first against a deliberately broken
  assumption.
- `seed e2e` is idempotent — running twice is a no-op, not a crash.
- `CLAUDE.md` D3/D9 updated: the e2e clause moves from *suspended* to *in force for
  identity*, stated precisely rather than claiming coverage the harness does not have.
- ADR-0021's e2e clause partially un-suspended; ADR-0026's D3 table updated.
