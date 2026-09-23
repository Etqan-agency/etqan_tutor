---
spec: docs/superpowers/specs/2026-09-03-playwright-e2e-harness-design.md
created: 2026-09-03
status: in-progress
---

# Plan — Playwright e2e harness

Six slices. Each is independently reviewable; 1–3 are the harness, 4 proves it, 5 wires CI,
6 tells the truth in the docs.

## 1. `seed_e2e` (backend, in `identity`)

New `kaleem/identity/management/commands/seed_e2e.py`. **Not** an `e2e` branch on
`platform`'s existing `seed` stub: `import-linter`'s `platform imports no business modules`
is an independence contract, so nothing in `platform` may call `identity.services`. The old
stub cannot be implemented where it sits — that goes to `ISSUES.md`, not into this slice.

- Accounts, all idempotent (`get_or_create` + explicit `set_password` every run so a
  re-seed repairs a drifted password rather than crashing):
  - `e2e.parent@kaleem.test` — verified, `ParentProfile`
  - `e2e.student@kaleem.test` — verified, `StudentProfile`
  - `e2e.teacher@kaleem.test` — verified, `TeacherProfile`
  - `e2e.unverified@kaleem.test` — **not** verified; the login gate needs it
- One shared password constant, exported so the specs import it rather than repeating it.
- Guard: refuse to run when `DEBUG` is false **and** the host is not localhost. A seed
  command that creates known-password accounts must never be runnable against production
  by accident.
- Tests (D3): idempotency, the unverified account really is unverified, the guard fires.

## 2. Playwright install + config (dashboard)

- `@playwright/test`, `playwright.config.ts`, `e2e/` directory.
- `testDir: "e2e"`, chromium only, `retries: process.env.CI ? 1 : 0`, trace on first retry.
- `baseURL` from `E2E_APP_URL`, defaulting to the local dev stack
  (`http://app.kaleem.localhost`) so `pnpm e2e` works against `just dev` with no arguments.
- `vitest.config.ts` must **exclude** `e2e/**`, or vitest will try to run the specs and
  fail on the missing Playwright globals. Verify by running `pnpm test` after.
- `pnpm e2e` + `pnpm e2e:ui` scripts.

## 3. Fixtures

- `e2e/fixtures.ts`: the seeded accounts (imported names, not literals scattered per spec)
  and a `login(page, who)` helper going through the real form — no cookie injection. A
  helper that fakes the session would skip the exact boundary this harness exists to prove.

## 4. The six specs

`e2e/identity.spec.ts`, one per flow in the spec table. Each written to fail first: invert
the assertion, watch it go red, restore. Role/name selectors only.

## 5. CI job (meta)

New `e2e` job in `.github/workflows/ci.yml`:

1. postgres + redis services (copy `backend-test`)
2. `/etc/hosts` ← `127.0.0.1 app.kaleem.localhost api.kaleem.localhost`
3. install backend deps, `migrate`, `seed e2e`
4. `runserver` on `api.kaleem.localhost:8000`, backgrounded, wait for `/health/ready/`
5. `pnpm build` with `VITE_API_URL=http://api.kaleem.localhost:8000/api/v1/`, then
   `vite preview --host app.kaleem.localhost --port 4173`, backgrounded, wait for 200
6. `pnpm exec playwright install --with-deps chromium`
7. `pnpm e2e`
8. upload the HTML report + traces on failure — a red e2e job with no artefact is a
   guessing game
9. add `e2e` to `deploy-staging`'s `needs:`

Backend settings for this env need `SESSION_COOKIE_DOMAIN=.kaleem.localhost`,
`ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS` and `CORS` to include the two hosts. Check whether
`config.settings.local` already covers it (the dev stack uses the same hostnames) before
adding a settings module — reuse beats a new file.

## 6. Tell the truth in the docs

- `CLAUDE.md` D3: e2e moves from **NOT YET IN FORCE** to in force *for identity*, named
  precisely. D9's suspended clause updated.
- ADR-0026's D3 table gains an e2e column.
- A short ADR amending ADR-0021's clause 3 to match what now runs.
- `ISSUES.md`: drop "no Playwright harness exists"; keep the billing-e2e-gap entry, which
  this does not fix, and add a "flows not yet covered" entry so the gap stays visible.

## Risks

- **`vite preview` on a custom host.** If `--host app.kaleem.localhost` misbehaves in CI,
  fall back to binding `0.0.0.0` and letting `/etc/hosts` resolve the name; the cookie
  domain is what matters, not the bind address.
- **Backgrounded servers racing the tests.** Poll the health endpoints, never `sleep`.
- **First-run flake.** If a spec is flaky on day one it does not get a retry bump — it gets
  fixed or deleted. A flaky blocking gate trains everyone to re-run CI, which is how a gate
  dies.
