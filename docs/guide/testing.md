---
title: "Testing"
---

What runs where, how to write tests for a multi-academy app, and the bars CI holds you to.

## Commands

| Command | Runs |
|---|---|
| `just test` | backend + dashboard type check + marketing + boundaries |
| `just test-backend` | `pytest -v --cov=etqan --cov-report=term-missing` in the django container |
| `just test-backend-host` | the same on the host, using `backend/.venv` |
| `just test-frontend` | `tsc --noEmit` for the dashboard (unit tests: `pnpm test` / `pnpm test:coverage` in `dashboard/`) |
| `just test-marketing` | marketing `pnpm test:coverage` |
| `just check-boundaries` | `lint-imports` (module boundaries) |
| `just lint` | ruff, biome, boundaries, `just secrets` (gitleaks over tracked files including submodules) |
| `just e2e [spec]` | Playwright against your running stack (`just dev-backend` first) |
| `bash infra/scripts/tests/<name>_test.sh` | deploy script tests (`ship`, `smoke`, `compose`, `edge_ca`) |

## Coverage floors (CI fails below them)

| Suite | Lines | Statements | Branches | Functions |
|---|---|---|---|---|
| Backend (`--cov=etqan`, branch coverage on) | 80 total | | | |
| Dashboard (vitest, v8, `all: true`) | 80 | 80 | 70 | 70 |
| Marketing | 80 | 80 | 70 | 70 |

Keep `--cov=etqan` identical in the justfile and `.github/workflows/ci.yml`. If they differ,
the two measure different files.

## Backend tests

pytest with `--ds=config.settings.test --reuse-db`. Tests sit in each app's `tests/`.

**Every test already runs inside an academy.** `backend/conftest.py` creates three tenants
once per session: `public`, `pytest_main` (host `testserver`, so the default test client
reaches it) and `pytest_other`. An autouse fixture puts the connection on `pytest_main`
before each test. Fixtures:

| Fixture | Use |
|---|---|
| `tenants` | `tenants.main`, `tenants.other`: the academies, for isolation tests |
| `api_for("teacher")` | an `APIClient` signed in as a new user of that role (`client.user`) |
| `staff_for("invoice.view_any", …)` | a staff client holding exactly these permission codes |
| `set_features(things=False)` | switch features for the test's academy |

Conventions:

- Test services directly for rules, and test views for permissions and wiring. Every route
  should have a test that the wrong role gets 403, and that a disabled feature gets 404.
- For anything that could leak across academies, write a row in `tenants.other` and assert
  the main academy can't see it.
- Use `force_login` (not `force_authenticate`) when a user's grants change between two
  requests. `codes_of` caches codes on the user object.
- Celery runs eager in tests. Jobs that loop with `for_each_academy` will visit the test
  academies.
- Outside services are never called for real: `ETQAN_AI_FAKE`, `GATEWAYS_SIMULATE`, Mailpit
  locally, and mocks at the integration boundary in tests.
- `etqan.access.tests.test_routes` checks the permission registry against the routes, and
  `tests/test_api_versioning_is_enforced.py` checks that everything is under `/api/v1/`.

## Dashboard tests

Vitest with Testing Library. A test sits next to its component (`Foo.tsx` → `Foo.test.tsx`).
Mock the API at the feature's `api.ts`, or with the helpers in `src/test/`. `locales.test.ts`
fails when the `en`, `ar` and `es` catalogues disagree.

## End-to-end

Playwright specs in `dashboard/e2e/`. The base URL is `E2E_APP_URL` (default
`http://demo.etqan.localhost`). Specs that need server state call management commands
through `E2E_MANAGE`; `just e2e` points that at your stack's django container. In CI the
`e2e` job builds the stack from scratch (`migrate_schemas --shared`, `seed_dev`, the built
dashboard and marketing, Caddy with `caddy/Caddyfile.e2e`), so a test that passes only on a
stale local stack will fail there. Rebuild before you trust a local result.

## CI

`.github/workflows/ci.yml` in the meta repo, on every PR and every push to `master`:

| Job | Checks |
|---|---|
| backend | ruff check + format, `lint-imports`, pytest with coverage (PostgreSQL 18 service) |
| dashboard | token pin check, `tsc`, biome, vitest coverage, build |
| marketing | astro check, lint, vitest coverage, build |
| caddy, infra-scripts | Caddyfile validation; shellcheck and tests for the deploy scripts |
| e2e | Playwright against a full stack |
| orchestra | the orchestration tooling's own tests |
| security | gitleaks: history plus tracked tree (allowlist `.gitleaksignore`) |

On `master` it then builds images, runs a simulated staging deploy when infra changed, and
deploys to staging. See [Deploy](runbooks/deploy.md).
