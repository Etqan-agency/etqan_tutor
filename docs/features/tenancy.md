# Tenancy: academies and domains

Every customer academy is a django-tenants tenant with its own PostgreSQL schema. The academy is
picked from the request's `Host`: its Etqan subdomain or a custom domain it owns. Etqan staff create,
suspend and reactivate academies, attach custom domains and switch features in the Django admin on
the bare base domain. Academy users never see this layer. They only see "their" academy at its
hostname. Every backend developer needs it, because every query, task and URL runs inside one
academy's schema.

## Concepts

| Model (`etqan.tenants.models`, **public** schema) | What it is |
|---|---|
| `Academy` (`TenantMixin`) | One row per academy, plus one row for the public schema itself (`schema_name="public"`, name "Etqan"). Fields: `name`, `subdomain` (unique slug), `status` (`active` / `suspended`), `timezone`, `currency`, `plan_label`, `plan_notes`, `features` (JSON code → bool, see [feature-toggles.md](feature-toggles.md)), `etqan_defaults_suspended` (integrations: stops use of Etqan's default accounts), `created_at`. `auto_create_schema=True`, `auto_drop_schema=False`. |
| `Domain` (`DomainMixin`) | A hostname that serves one academy: `domain`, `tenant`, `is_primary`, `status` (`pending` / `active` / `disabled`), `is_custom`, `verified_at`. Only `active` rows resolve. |

Schema layout (`backend/config/settings/base.py`):
- `SHARED_APPS` migrate into `public`: `tenants`, `platform`, `identity` (Etqan staff accounts),
  `integrations` (Etqan's default accounts), `etqan_billing`, plus Django/allauth/celery-beat.
- `TENANT_APPS` migrate into every academy schema: `identity` (academy users), `site`, `academy`,
  and every business app. A new business app goes in `TENANT_APPS` under its phase marker.
- Schema name is `academy_<subdomain>`, with hyphens turned into underscores
  (`tenants/services.py:schema_name_for`). The primary domain is `<subdomain>.<TENANT_BASE_DOMAIN>`
  (`domain_for`).
- Migrate with `migrate_schemas`. Never assume a single schema.

## How it works

### Request routing

1. Caddy (`infra/caddy/Caddyfile`, local `caddy/Caddyfile.local`) routes every academy host by path.
   `/api/*`, `/accounts/*`, `/health/*` and `/media/*` go to Django. `/app/*` goes to the dashboard.
   Every other path goes to the marketing site (Astro). `/internal/*` answers 404 at the edge.
   The bare base domain serves only Django: the staff admin, health checks and Etqan's own webhooks
   (`config/urls_public.py`).
2. `etqan.tenants.middleware.ActiveDomainTenantMiddleware` runs first. It looks up the `Host` header
   (lowercased, port stripped). Unlike the stock django-tenants middleware, it does **not** strip
   `www.`. It then sets `connection.tenant` from an `active` `Domain` row. A pending, disabled or
   unknown host is a 404.
3. `SuspendedAcademyMiddleware` answers 403 `{"code": "tenant.suspended"}` for every request to a
   suspended academy, except `/health/*`. The marketing site maps that code to a 503 page.
4. A public-schema host (base domain, `localhost`, `127.0.0.1`) uses `PUBLIC_SCHEMA_URLCONF =
   config.urls_public`. Academy hosts use `config.urls`, which carries `/api/v1/`.

### Creating an academy

`tenants/services.py:create_academy(name, subdomain, admin_email, ...)` runs in one transaction:
1. `validate_subdomain`: 1–32 chars `[a-z0-9-]`, no leading or trailing hyphen, not in
   `RESERVED_SUBDOMAINS` (`www`, `admin`, `api`, `app`, `public`, `static`, `media`, `mail`, `flower`,
   `sites`, `etqan`). It also refuses a subdomain that is taken, or whose schema or domain still
   exists from a deleted academy.
2. Saves the `Academy`. This creates and migrates the schema. It then creates the primary `Domain`.
3. Inside `tenant_context(academy)`, it creates `AcademySettings` (`academy_services.ensure_settings`),
   the site defaults (`site_services.ensure_site_defaults`: `Branding`, `LandingContent`,
   `SiteSettings`), the first admin (`identity_services.create_academy_admin`, which sends a
   set-password email), the preset tags and the Supervisor role preset.

There are two entry points. Etqan staff use the Django admin "add academy" form (`tenants/admin.py`
`AcademyAdmin.save_model`). Scripts use `manage.py create_academy --name --subdomain --admin-email
[--admin-name --timezone --currency]`.

### Suspension (offboarding)

- `tenants/services.py:set_status(ids, "suspended" | "active")`, from the admin actions "Suspend /
  Reactivate selected academies". The public row is never touched.
- Academies cannot be deleted from the admin (`has_delete_permission` is False): a delete would
  orphan the schema.
- Background jobs skip suspended academies (`platform/tenancy.py:for_each_academy` filters
  `status="active"`).

### Custom domains

1. Staff add a domain in the admin (`DomainAdmin`). This calls `add_custom_domain`: it validates the
   hostname, refuses anything under `TENANT_BASE_DOMAIN`, and refuses duplicates. The row is created
   `pending`, `is_custom=True`, not primary. The help text tells the academy to add a CNAME to
   `EDGE_HOSTNAME`, or an A record to `EDGE_PUBLIC_IP` for an apex.
2. The admin action "Check DNS and activate" runs `check_domain_dns`. It passes only when every
   address the domain resolves to is among `EDGE_HOSTNAME`'s addresses or `EDGE_PUBLIC_IP`. On
   success, `activate_domain` sets `active` and `verified_at`. Disabled rows can be re-checked too.
3. `make_primary` (active domains only) moves `is_primary`. `frontend_url()` and canonical URLs
   follow the primary domain.
4. `disable_domain` works only on custom domains. If the custom domain was primary, it promotes the
   academy's subdomain back to primary first.
5. TLS: Caddy's `on_demand_tls` asks `GET /internal/tls-allowed?domain=…`
   (`tenants/views.py:tls_allowed` → `is_tls_allowed`). It gets 200 only for an `active` Domain
   row. The ask goes through a loopback listener (`127.0.0.1:8099`) that resolves to the public
   schema.
6. A `www.` variant is a separate `Domain` row. It must be added and activated on its own.

### Building URLs and running per-academy work

- `etqan/platform/frontend.py:frontend_url()` gives the current academy's base URL from
  `TENANT_URL_TEMPLATE` and its primary domain. In the public schema it gives `FRONTEND_URL`.
  `app_url(path)` adds `/app`. Use these for every user-facing link (emails, redirects).
- `etqan/platform/tenancy.py:for_each_academy(job, name=, atomic=True)` runs `job` in every
  active academy, one transaction each. A failure is logged and the loop continues. A Celery soft
  time limit stops the whole run.
- `etqan/platform/tenancy.py:academy_context(schema_name)` is for tasks queued from one academy.
  Pass the schema name, never the academy object.
- Business code must not import `etqan.tenants`. Read `connection.tenant` instead.
  `lint-imports` enforces this.

### Platform bootstrap

`manage.py bootstrap_platform` (`ensure_public_tenant`) creates the public tenant and `Domain` rows
for `TENANT_BASE_DOMAIN` and every `PUBLIC_EXTRA_DOMAINS` entry (default `localhost`, `127.0.0.1`).
It is idempotent. `infra/scripts/ship.sh` runs it on every deploy, before the new colour starts.

## API

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/internal/tls-allowed?domain=<host>` | Caddy only (public URLconf; `/internal/*` is 404 at the edge) | 200 if the host is an active academy domain, else 404 |
| GET | `/health/live/`, `/health/ready/` | Load balancer / Caddy | Liveness and readiness. Reachable on suspended academies too |

There is no REST API for academies or domains. Management happens in the Django admin at
`/<ADMIN_URL>` (default `admin/`) on the bare base domain.

## Dashboard

None. Tenancy is invisible to the dashboard. The SPA calls relative `/api/v1/...` on its own host,
which already selects the academy. A suspended academy's API answers 403 `tenant.suspended`.

## Background jobs

None of its own. Every periodic task in `CELERY_BEAT_SCHEDULE` loops over academies itself, through
`for_each_academy`. Suspended academies are skipped.

## Configuration

| Setting / env | Purpose |
|---|---|
| `DJANGO_TENANT_BASE_DOMAIN` (`TENANT_BASE_DOMAIN`, default `etqan.localhost`) | Base for academy subdomains. The bare domain is the public schema. |
| `DJANGO_PUBLIC_EXTRA_DOMAINS` (default `localhost,127.0.0.1`) | Extra hosts mapped to the public schema (readiness probe, TLS ask). |
| `DJANGO_TENANT_URL_TEMPLATE` (default `http://{domain}`; production `https://{domain}`) | How `frontend_url()` builds an academy URL. |
| `DJANGO_FRONTEND_URL` | Base URL used in the public schema. |
| `DJANGO_EDGE_HOSTNAME` (default `sites.<base>`), `DJANGO_EDGE_PUBLIC_IP` | What custom domains must point at (DNS check, admin help text). |
| `BASE_DOMAIN`, `TLS_MODE` (`cloudflare` / `internal`), `CF_API_TOKEN` | Caddy: wildcard certificate via Cloudflare DNS-01, on-demand certificates for custom domains. |

## Code map

- `backend/etqan/tenants/models.py`: `Academy`, `Domain`
- `backend/etqan/tenants/services.py`: `create_academy`, `validate_subdomain`, `set_status`,
  `add_custom_domain`, `check_domain_dns`, `activate_domain`, `disable_domain`, `make_primary`,
  `is_tls_allowed`, `ensure_public_tenant`, `set_features` / `copy_features` / `seed_features`
- `backend/etqan/tenants/middleware.py`: active-domain resolution, suspension block
- `backend/etqan/tenants/admin.py`: staff admin for academies (feature checkboxes, copy features,
  suspend) and domains (DNS check, primary, disable)
- `backend/etqan/tenants/views.py`: `tls_allowed`
- `backend/etqan/tenants/management/commands/`: `create_academy`, `bootstrap_platform`,
  `set_features`, `seed_dev`, `seed_staging`. Seed data is in `backend/etqan/tenants/seeds/`.
- `backend/etqan/platform/tenancy.py`: `for_each_academy`, `academy_context`
- `backend/etqan/platform/frontend.py`: `frontend_url`, `app_url`
- `backend/config/settings/base.py`: `SHARED_APPS` / `TENANT_APPS`, tenant settings, middleware order
- `backend/config/urls.py` (academy hosts), `backend/config/urls_public.py` (base domain)
- `infra/caddy/Caddyfile`, `caddy/Caddyfile.local`, `caddy/Caddyfile.e2e`

## Design history

- [v1 design](../superpowers/specs/2026-09-23-etqan-tutor-v1-design.md): schema-per-academy
  tenancy. Its routing layout was replaced by the academy-sites spec.
- [Plan 1: fork, strip, tenancy](../superpowers/plans/2026-09-23-plan-1-fork-strip-tenancy.md):
  the tenants app, `create_academy`, the public URLconf.
- [Academy sites design](../superpowers/specs/2026-09-23-academy-sites-design.md) §2.2 and §5:
  path routing on every academy host, custom domains, Caddy on-demand TLS, domain statuses.
  Its "`www.` redirects to the apex" idea was not built (see below).
- [Feature toggles design](../superpowers/specs/2026-09-30-feature-toggles-design.md): the
  `Academy.features` column and the admin checkboxes.
- [Integrations and Etqan billing design](../superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md):
  `Academy.etqan_defaults_suspended`.
