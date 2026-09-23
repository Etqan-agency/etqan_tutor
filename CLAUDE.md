# etqan_tutor

Multi-academy tutoring operations SaaS (Etqan Agency). Fork of Kaleem.

## Layout
Meta repo with submodules: `backend/` (Django + DRF, package `etqan`), `dashboard/`
(React + TanStack), `infra/`, `tokens/` (`@etqan/tokens`). Trunk: `master` here, `main`
in submodules. Work on a `feat/*` branch in each touched repo, PR, merge; then bump the
submodule pointers here.

## Tenancy (read before touching models)
- django-tenants, one PostgreSQL schema per academy; `etqan.tenants.Academy` is the tenant.
- SHARED_APPS migrate into `public`; TENANT_APPS into every academy. New business apps go
  in TENANT_APPS.
- Caddy is the edge (local `caddy/Caddyfile.local`, production `infra/caddy/Caddyfile`).
  Every academy host (`<subdomain>.<TENANT_BASE_DOMAIN>` or a custom domain) is routed
  by path, all same-origin:

  | Path | Upstream |
  |---|---|
  | `/api/*`, `/accounts/*`, `/health/*`, `/media/*` | Django |
  | `/app/*` | dashboard (Vite `base: "/app/"`) |
  | everything else | marketing site (Astro, `marketing/`) |
  | `/internal/*` | 404 — never reachable from outside Caddy |

  The bare base domain serves only Django (admin for Etqan staff).
- Migrate with `migrate_schemas`, never assume a single schema.
- Background jobs must loop over academies explicitly (`tenant_context`).
- Build any user-facing URL with `etqan.platform.frontend.frontend_url()`.

## Rules
- Spec → plan → code. Specs/plans in `docs/superpowers/`.
- TDD. Backend coverage ≥ 80%; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Business logic in `<app>/services.py`; apps talk to each other only through services.
  `lint-imports` enforces the boundaries.
- All API routes under `/api/v1/`.
- Money is integer minor units + currency. Stored instants are UTC.
- Keep it simple: this is a CRUD-first product. Check the spec's non-goals before adding
  anything.

## Commands
`just setup`, `just dev`, `just test`, `just lint`, `just migrate`, `just seed`.
