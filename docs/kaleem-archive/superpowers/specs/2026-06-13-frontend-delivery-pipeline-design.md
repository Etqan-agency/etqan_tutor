---
name: frontend-delivery-pipeline
phase: B
modules: [platform]
status: draft
created: 2026-06-13
closed: null
---

## Goal

kaleem can deploy a backend but not a frontend. The CI builds the Django image,
ships it blue-green behind Traefik, and routes one host (`staging.kaleem.academy`)
to it. The React **dashboard** (the actual product — where students, parents,
teachers, and admins live) only gets linted and build-checked, then its `dist/` is
thrown away; the **marketing** Astro site has no CI job at all. Neither has a
Dockerfile, a Traefik route, or any path to staging.

This spec builds the frontend delivery pipeline so both frontends ship end-to-end,
and codifies the process rule that **every feature from now on includes its frontend
slice and is not "done" until that slice is deployed and verified in the browser.**
It is an infrastructure + process enabler for Phase B, written before any Phase B
feature ships UI.

## User flow

This spec has no end-user flow of its own; its "users" are the developer and the
deploy pipeline. The flow it *enables* end-to-end:

1. A developer merges a feature to `master` in the meta repo.
2. CI builds three images (backend, dashboard, marketing) tagged with the meta
   short-SHA, pushes them to GHCR.
3. CI syncs infra config to the VPS and runs `ship.sh`.
4. `ship.sh` does the existing backend blue-green, then recreates the two static
   frontend containers with the new SHA.
5. Traefik serves: `app-staging.kaleem.academy` → dashboard, `api-staging.kaleem.academy`
   → Django, `staging.kaleem.academy` → marketing.
6. A user opens the dashboard in a browser, registers/logs in, and the session
   cookie + CSRF + CORS work across the `app-`/`api-` subdomains.

Failure cases:
- A frontend image fails to build → CI fails, nothing deploys (D5).
- The backend blue-green health check fails → `ship.sh` rolls back the backend and
  exits before touching the static frontends (they keep serving the previous image).
- A static container fails to come up → it is a plain `compose up`; the previous
  container is already replaced, so this is a visible blip masked by Cloudflare asset
  caching. (Acceptable for static; no health-gate.)

## Architecture

### Surfaces & domains

One-label hosts only — the Cloudflare Universal SSL cert covers `*.kaleem.academy`
(one level), so `app.staging.kaleem.academy` (two levels) has no edge cert.

| Surface | Production (documented, not wired yet) | Staging (wired now) |
| --- | --- | --- |
| Dashboard (the app) | `app.kaleem.academy` | `app-staging.kaleem.academy` |
| API (Django) | `api.kaleem.academy` | `api-staging.kaleem.academy` |
| Marketing (Astro) | `kaleem.academy` + `www.kaleem.academy` | `staging.kaleem.academy` |

The backend **moves off** `staging.kaleem.academy` → `api-staging.kaleem.academy`.

### Auth: same-origin → same-site

CLAUDE.md and the roadmap say "same-origin frontend/backend." Separate `app-`/`api-`
subdomains make the frontend and API **same-site but cross-origin**. Because they
share the registrable domain `kaleem.academy`, session auth still works **without**
`SameSite=None`:

- `SESSION_COOKIE_DOMAIN=.kaleem.academy`, `CSRF_COOKIE_DOMAIN=.kaleem.academy`
- Both cookies `SameSite=Lax; Secure`
- `CSRF_TRUSTED_ORIGINS` += the `app-`/`app.` origins
- CORS allow-list those origins with `CORS_ALLOW_CREDENTIALS=True`
- Dashboard axios: `withCredentials: true`; read the CSRF cookie, send `X-CSRFToken`

This is a documented deviation from the "same-origin" decision and is recorded in an
ADR that also updates the CLAUDE.md wording (CLAUDE.md edits require an ADR).

### Build & serve (one mental model: GHCR image, like the backend)

Each frontend gets a multi-stage Dockerfile: `node:22` + `pnpm build` → copy `dist/`
into `nginx:alpine`.

- **Dashboard:** nginx `try_files $uri /index.html` SPA fallback for TanStack Router;
  `Cache-Control: public, max-age=31536000, immutable` on `/assets/*` (content-hashed),
  `no-cache` on `index.html`. `VITE_API_URL` is a Docker **build-arg** (staging image
  built with `https://api-staging.kaleem.academy`).
- **Marketing:** Astro static multi-page output, plain nginx static serving.

Images: `ghcr.io/kaleem-lms/dashboard:<sha>` / `…/marketing:<sha>`, same meta
short-SHA as the backend (all three built in one CI run). Cloudflare edge-caches the
immutable `/assets/*`, giving most of a CDN's benefit with no second deploy system.

### Compose & Traefik

- Add `dashboard` and `marketing` services to `docker-compose.production.yml` —
  **singletons, no blue-green** (static, no migrations; recreate is a sub-second blip).
  `image: ghcr.io/kaleem-lms/<name>:${DEPLOY_SHA:-latest}`, nginx on port 80.
- Traefik labels: `app(-staging)` → dashboard:80; marketing host (staging:
  `staging.kaleem.academy`; prod: apex + `www`) → marketing:80.
- Existing blue/green django routers: change `Host` rule from `APP_DOMAIN` →
  new `API_DOMAIN`.

### CI (meta `ci.yml`)

- Extend `dashboard-build` and add `marketing-build` to **build + push GHCR images**
  on `master` push (mirroring the backend image step).
- `deploy-staging`: build/push all three images → scp infra → `ship.sh`.
- `ship.sh`: after the backend blue-green completes, `docker compose up -d dashboard
  marketing` recreates the static services with the new SHA. No health-gate/migrate.

### Process change (the headline)

- **D9 Definition of Done** gains an explicit line: a feature is not done until its
  frontend slice is built, deployed to staging, and verified end-to-end in a browser.
- **`docs/templates/spec.md`** gains a required **Frontend** section (routes,
  components, states, API calls) so every future feature spec plans its UI up front.
- **ADR** records (a) the same-site auth decision (updating CLAUDE.md's "same-origin"
  wording) and (b) the frontend-delivery architecture above.

## Data model delta

None. No database changes.

## API delta

No new endpoints. Backend **settings** change only: session/CSRF cookie domain +
SameSite, `CSRF_TRUSTED_ORIGINS`, CORS allow-list + credentials. The cross-origin
`OPTIONS` preflight for `app-` → `api-` calls must return the CORS headers.

## Module boundaries

This is `platform`/infra work — no business module is touched. It crosses three
submodules (`backend` settings, `dashboard`/`marketing` Dockerfiles + nginx conf,
`infra` compose/Traefik/ship.sh) and the meta repo (`ci.yml`, docs, ADR, template,
STATE/ISSUES). No `import-linter` boundaries are affected.

## Out of scope

- **Production environment wiring.** Prod domains are documented; only staging is
  provisioned (no prod VPS yet).
- **CDN / object-storage hosting** (option B). Stays available as escape hatch E2 if
  preview-mode shows a real app-shell latency problem.
- **Mailpit local-email fix.** Tracked separately in `ISSUES.md`; a small local-dev
  change handled right after this spec, not part of it.
- **Blue-green for static frontends.** Deliberately a plain container recreate.
- Any actual Phase B feature UI. This is the pipeline, not a feature.

## Test plan

- **CI:** all three image builds succeed; a build failure fails the pipeline (D5).
- **Routing smoke (staging):** `app-staging` serves the SPA `index.html` (200);
  `api-staging/health/ready/` returns 200; `staging.kaleem.academy` serves marketing.
- **SPA fallback:** a deep dashboard route (e.g. `/app-staging…/some/route`) returns
  `index.html`, not 404.
- **Asset caching:** `/assets/<hashed>.js` returns the `immutable` cache header.
- **End-to-end auth (the DoD gate):** register → verify → login → `GET /me/` driven
  **through the dashboard in a browser** against `api-staging`, confirming the
  same-site cookie, CSRF token round-trip, and CORS preflight all work cross-subdomain.
- **Rollback safety:** a forced backend health-check failure rolls back the backend
  and leaves the static frontends on their prior image.

## Open questions

None. All four keystone decisions (routing topology, serving method, domain scheme,
no-blue-green-for-static) were resolved during brainstorming.
