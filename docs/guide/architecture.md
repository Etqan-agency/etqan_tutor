# Architecture

How etqan_tutor fits together: the repos, the request path, tenancy, the backend's module
rules and the dashboard's structure. Read this before [Adding a feature](adding-a-feature.md).

## The product in one paragraph

Etqan Agency runs one installation for many tutoring academies. Each academy gets its own
workspace: a PostgreSQL schema, a subdomain (`<sub>.<TENANT_BASE_DOMAIN>`, or a custom
domain), a public website and an admin dashboard. Inside it, admins and office staff manage
students, parents, teachers, subscriptions, sessions, invoices, payroll and content;
teachers run their sessions; students and parents see their own schedule, homework and
bills. Etqan's own staff use the Django admin on the bare base domain to create academies,
switch features on or off for each one, and bill academies for the services Etqan provides
(email, video, payments, AI).

## Repositories

The meta repo (`Etqan-agency/etqan_tutor`, trunk `master`) holds the submodules below plus
shared tooling. Each submodule has trunk `main`.

| Path | What | Stack |
|---|---|---|
| `backend/` | API, admin, background jobs. Python package `etqan` | Django 5+, DRF, django-tenants, allauth, Celery, PostgreSQL, Redis |
| `dashboard/` | The signed-in app at `/app/` for every role | React 19, TanStack Router + Query, Tailwind, shadcn/ui, Vite, Vitest, Playwright |
| `tokens/` | `@etqan/tokens` design tokens shared by dashboard and marketing | Private package, pinned by tag |
| `infra/` | Staging and production compose files, Caddy, monitoring | Docker Compose |
| `marketing/` (in meta repo) | Each academy's public website | Astro |
| `orchestra/`, `scripts/orchestration/` (in meta repo) | Tooling for the parallel build sessions | Not part of the product |
| `caddy/Caddyfile.local` | The local edge | Caddy |

A change that touches `backend/` is a PR in the backend repo, then a PR in the meta repo that
bumps the submodule pointer. See [Onboarding → Git workflow](onboarding.md#git-workflow).

## Request path

```
browser ──► Caddy (edge, TLS, on-demand certs for custom domains)
              │  host = <academy>.<base> or a custom domain
              ├── /api/*, /accounts/*¹, /health/*, /media/* ──► Django (gunicorn)
              ├── /app/*                                    ──► dashboard (static build, Vite base "/app/")
              ├── /internal/*                               ──► 404 (only Caddy itself calls these)
              └── everything else                           ──► marketing (Astro SSR)
            host = bare base domain ──► Django only (Etqan staff admin, Etqan webhooks)
```

¹ Caddy still routes `/accounts/*` to Django, but nothing is mounted there: sign-in,
registration and password flows are all API routes, and allauth's own pages are off.

Everything an academy serves is same-origin, so the dashboard authenticates with Django
session cookies and CSRF (`X-CSRFToken` from the `csrftoken` cookie, see
`dashboard/src/lib/api.ts`). There are no tokens or CORS between the academy's site and its API.

Inside Django the first middleware is `etqan.tenants.middleware.ActiveDomainTenantMiddleware`:
it resolves the host to an `Academy`, sets the connection's schema, and then
`SuspendedAcademyMiddleware` refuses suspended academies. From then on every ORM query in the
request runs in that academy's schema. The bare base domain resolves to the `public` schema
and uses `config/urls_public.py` (admin and Etqan's webhooks). Academy hosts use
`config/urls.py`: `/api/v1/` (all routes registered in `config/api_router.py`) and
`/health/live/`, `/health/ready/`. OpenAPI is at `/api/v1/schema/`, with Swagger UI at
`/api/v1/docs/` and ReDoc at `/api/v1/redoc/`.

The marketing site reads the academy's site settings, pages and articles from the same API
on the same host. Full detail: [Website](../features/website.md).

## Tenancy

[django-tenants](https://django-tenants.readthedocs.io/) gives every academy its own schema.

- `etqan.tenants.Academy` is the tenant model and `tenants.Domain` maps hosts to it. Both live
  in `public`, together with the academy's feature switches (`Academy.features`) and its status.
- `SHARED_APPS` migrate into `public`, and `TENANT_APPS` into every academy schema (both in
  `backend/config/settings/base.py`). `etqan.identity` is in both: Etqan staff accounts live in
  `public`, and academy accounts live in each academy's schema. `etqan.integrations` and
  `etqan.etqan_billing` are public, because they hold Etqan's accounts and Etqan's invoices to
  academies. Every business app is a tenant app.
- Migrate with `migrate_schemas` (`just migrate`), never `migrate`.
- A background job has no request to pick an academy, so it loops over academies itself.
  Use `etqan.platform.tenancy.for_each_academy(job, name=...)`: it runs the job in each active
  academy's schema, one transaction per academy, logs and skips an academy that fails, and
  skips suspended academies. `academy_context(schema_name)` is for running in one academy.
- Build any user-facing URL with `etqan.platform.frontend.frontend_url()` / `app_url(path)`.
  They give the current academy's own host.

Details on academies, domains and suspension: [Tenancy](../features/tenancy.md).

## Backend

### Module layout

Each business area is a Django app under `backend/etqan/<app>/`:

```
<app>/
  models.py          # data only, no business logic
  services.py        # or services/ package: the app's public API
  api/urls.py        # mounted in config/api_router.py
  api/views.py       # thin: parse input, call one service, return a payload
  api/serializers.py # input validation
  api/payloads.py    # output shapes (many apps build dicts rather than ModelSerializers)
  tasks.py           # Celery tasks, each looping with for_each_academy
  migrations/
  tests/
```

`etqan.platform` is the cross-cutting layer and imports no business app. It holds tenancy
helpers, DRF permissions, feature switches, secrets, currency helpers, CSV export, pagination,
throttling, uploads and health views.

### Boundaries

Apps talk to each other only through `services`. One app never imports another app's
`models` or `api`. [import-linter](https://import-linter.readthedocs.io/) enforces this with
the contracts in `backend/pyproject.toml` (`[tool.importlinter]`). Run `lint-imports` or
`just check-boundaries`. Some notable contracts:

- `platform` imports no business app. When it needs something from one, the app registers a
  hook at startup. For example, `access` hands its permission-code loader to
  `platform.permissions.register_code_loader` in `AccessConfig.ready()`.
- No core app imports `notifications`. Notifications *reads* the other apps through their
  services (its scanners/finders) and decides what to send. Apps don't call it.
- `scheduling` never imports `billing` or `payroll`. Money depends on scheduling, not the
  reverse.

When you add an app, add its contracts too. See [Adding a feature](adding-a-feature.md).

### Permissions: who may call a route

Three layers, all in `etqan/platform/permissions.py`:

1. **Role.** Each academy user has one role: `admin`, `staff`, `teacher`, `student` or
   `parent` (`role_of(user)`). Classes `IsAdmin`, `IsTeacher`, `IsStudent`, `IsParent`,
   `ReadsOwn` gate the role-specific routes.
2. **Permission codes** for office work. A route declares
   `permission_codes = {"GET": "expense.view_any", "POST": "expense.create"}` (or by viewset
   action via `viewset_codes`) and uses `HasCode`. Admins always pass. Staff pass when one of
   their active roles holds the code. Codes are `<resource>.<verb>`, and every code is
   defined once in `etqan/access/registry.py`. Roles are data: sets of codes the academy
   edits in Settings → Roles. `etqan.access.tests.test_routes` keeps the registry's "in use"
   list equal to the codes the routes declare.
3. **Feature switches.** Etqan switches parts of the product on or off per academy. Each
   switch is defined once in `etqan/platform/features.py` (`REGISTRY`), and its value is in
   `Academy.features`. A route declares `feature = "expenses"` and lists `FeatureOn` *after*
   `HasCode`. When the feature is off the route answers 404, as if it did not exist. Read a
   switch only through `features.enabled(code)`. Only `etqan.tenants` writes switches (the
   platform admin and `manage.py set_features`).

`NotImpersonating` blocks sensitive writes during a quick-login session (an admin signed in
as someone else). See [Roles & permissions](../features/roles-permissions.md).

### Cross-cutting rules

| Rule | Where |
|---|---|
| All routes under `/api/v1/` (tested by `backend/tests/test_api_versioning_is_enforced.py`) | `config/api_router.py` |
| Money is integer minor units plus an ISO currency code (`amount_minor`, `currency`). Convert only at the edges | `etqan/platform/currency.py`, `dashboard/src/lib/money.ts` |
| Stored instants are UTC. Local dates and times are converted with the academy's time zone | per app |
| Outside services (email, WhatsApp, Zoom, payments, AI) get their account only from `etqan.integrations.services.resolve(service)`. No app stores its own keys | [Integrations](../features/integrations.md) |
| Email goes out only through `integrations.services.queue_email` / `send_email_now` | same |
| Using an Etqan default is metered with `etqan_billing.services.record_usage(...)` on the provider's confirmation | [Etqan billing](../features/etqan-billing.md) |
| Secrets at rest are encrypted with `etqan.platform.secrets.encrypt/decrypt` (MultiFernet, rotatable keys) | `etqan/platform/secrets.py` |
| Video links only from `integrations.services.create_meeting(...)`. A Zoom start link is never stored, logged or listed | [Meetings](../features/meetings.md) |

### Background work

Celery workers and beat run beside Django, with Redis as the broker. The beat schedule is
`CELERY_BEAT_SCHEDULE` in `backend/config/settings/base.py`, run by django-celery-beat's
database scheduler, and the tasks themselves live in each app's `tasks.py`. Every periodic task wraps its
body in `for_each_academy`. Examples: `scheduling.provision_meetings` every 5 minutes,
notification scans, and Etqan's monthly invoices to academies. Flower shows the queues locally.

## Dashboard

- **Routing.** File-based TanStack Router under `dashboard/src/routes/`. Public pages (login,
  register, pay links, consultation booking) are at the top level. Everything signed in is
  under `_authed/`, and `_print` holds the printable layouts. `routeTree.gen.ts` is generated.
- **Features.** `dashboard/src/features/<name>/` mirrors a backend app. Each one holds
  `api.ts` (axios calls), `queries.ts` (TanStack Query hooks and keys), `schemas.ts` (zod form
  schemas) and its components with their tests. Features never import each other. Shared UI
  lives in `src/ui/` (shadcn-based) and `src/components/`, and helpers in `src/lib/` (`api.ts`,
  `money.ts`, `i18n.ts`, `direction.tsx` for RTL).
- **State.** Server state comes only from TanStack Query. Zustand holds pure client state
  only.
- **i18n.** Arabic and English, with RTL support. Strings live in one JSON file per area under
  `dashboard/src/locales/<lng>/`. An academy can override any string (Settings →
  Translations), and those overrides come from `/api/v1/translations/`.
- **Permissions in the UI.** Screens hide what the user's role, codes or feature switches
  don't allow. The API is the real check.
- **Theming.** Design tokens come from `@etqan/tokens`, and per-academy branding and
  appearance come from the API.

## Marketing site

`marketing/` is an Astro app that renders each academy's public website: home, pages built
with the page builder, articles, FAQs and sign-up entry points. It is localised under
`[lang]/`. See [Website](../features/website.md).

## Where decisions are recorded

- `docs/superpowers/specs/`: one design per slice. They are written before the code and are
  not updated afterwards. For how things work now, read [`docs/features/`](../features/README.md).
- `docs/superpowers/plans/`: the implementation plan for each spec.
- `docs/kaleem-archive/adr/`: architecture decisions inherited from Kaleem, the project
  etqan_tutor was forked from. They still apply where nothing replaced them, for example
  ADR-0001 modular monolith, 0003 session auth + CSRF, 0007 Docker Compose rather than
  Kubernetes, 0008 git submodules, 0017 URL-path versioning.
