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
- Outside services (email, WhatsApp, payments, video, AI) get their account only from
  `etqan.integrations.services.resolve(service)`; no app stores keys of its own. Email goes out
  only through `integrations.services.queue_email` / `send_email_now`. Secrets go through
  `etqan.platform.secrets`.
- Use of an Etqan default is metered on the provider's confirmation with
  `etqan.etqan_billing.services.record_usage(source=resolved.source, service, unit, quantity,
  source_ref)`; it records only `source == "etqan"`, once per (service, unit, `source_ref`). A
  provider event that yields several units records each unit under the provider's one id.
- Keep it simple: this is a CRUD-first product. Check the spec's non-goals before adding
  anything.

## Parallel phases
Phases B2–B11 are built by parallel sessions under
`docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md`: one conductor
(`scripts/orchestration/CONDUCTOR.md`) and one orchestrator per phase
(`scripts/orchestration/PHASE_PROMPT.md`), coordinated by `scripts/orchestration/ledger.py`.
Shared lists carry `── phase Bn ──` markers: add lines only under your phase's marker.
Translations are one file per area in `dashboard/src/locales/<lng>/`.
Orchestra (`just orchestra`, `orchestra/`) shows and controls all of it at
http://127.0.0.1:7700; sessions start only through `scripts/orchestration/start-session.sh`.

## Commands
`just setup`, `just dev`, `just test`, `just lint`, `just migrate`, `just seed`.
