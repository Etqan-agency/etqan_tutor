# Deploy

How code gets from `master` to a server, how to roll back, and how to run commands on a
deployed stack. Setting up a staging server for the first time is covered step by step in
`infra/STAGING.md`. This page is the operational summary.

## Environments

| | Local | Staging | Production |
|---|---|---|---|
| Compose | `docker-compose.local.yml` | `infra/docker-compose.production.yml` + `infra/docker-compose.staging.yml` overlay | `infra/docker-compose.production.yml` |
| Django | `runserver` | gunicorn, blue/green | gunicorn (3 workers), blue/green |
| TLS | none (http) | `TLS_MODE=internal` (Caddy's own CA) | `TLS_MODE=cloudflare`: wildcard via DNS-01, on-demand certificates for custom domains |
| Storage | local disk | RustFS S3 from the overlay | S3 (`DJANGO_S3_*`) |
| Email | Mailpit | Mailpit (server's 127.0.0.1:8025) | SMTP/SES (`DJANGO_EMAIL_*`) |
| Env file | `backend/.env` (from `.env.example`) | `/opt/etqan/.env.production` with `ETQAN_OVERLAY=staging` (from `infra/.env.staging.example`) | `/opt/etqan/.env.production` (from `infra/.env.production.example`) |
| Deploys | — | automatic, every green `master` | by the owner, with the same `ship.sh` |

## The pipeline (staging)

1. A push to `master` runs `.github/workflows/ci.yml`, with all test jobs as in
   [Testing](../testing.md#ci).
2. `images` builds and pushes `ghcr.io/etqan-agency/{backend,dashboard,marketing}:<sha>`
   (and `:master`).
3. `staging-sim` deploys those images to a simulated server (Docker-in-Docker) when
   `scripts/staging-sim-needed.sh` says infra changed. Run it locally with `just staging-sim`.
4. `deploy-staging` calls `.github/workflows/deploy-staging.yml`. It checks that the SHA is a
   40-character hex ancestor of `origin/master`, then runs `scripts/deploy-staging.sh <sha>`:
   - rsync `infra/` → `/opt/etqan/` (never `.env.production` or `.active-color`);
   - log the server in to GHCR;
   - `ssh … bash /opt/etqan/scripts/ship.sh <sha>`;
   - optionally `manage.sh seed_staging` (manual runs with *seed* checked);
   - `infra/scripts/smoke.sh $STAGING_BASE_URL`: `/health/ready/` on the academy host,
     `/admin/login/` on the base host, `/app/` serves the SPA shell, `/` returns 200.

   Without the `STAGING_SSH_HOST` secret the job skips every step and still succeeds.
   Deploys run one at a time (`concurrency: staging`).

## What `ship.sh <sha>` does (blue/green)

1. Refuses to start with less than 5 GiB free on `/var/lib/docker`.
2. Reads `/opt/etqan/.active-color`; the new colour is the other one.
3. Pulls images and makes sure `caddy`, `postgres`, `redis` and `flower` are up.
4. Runs `manage.py migrate` (django-tenants' `migrate_schemas`: public, then every academy),
   then `bootstrap_platform`, both with the **new** image. If either fails, the new colour
   never starts and the old colour keeps serving.
5. Starts the new colour (`django-<c>`, `celery-worker-<c>`, `celery-beat-<c>`), then checks
   `/health/ready/` up to 10 times. On failure it removes the new colour.
6. Writes `.active-color`, stops the old colour with a 30-second drain, restarts
   `dashboard` and `marketing`, and prunes images older than 24 hours.

Caddy sends traffic to whichever colour is healthy (`lb_policy first` with active health
checks), so the switch has no 502 window.

**Migrations run before the new code serves, while the old code is still live.** Each one must
be backward-compatible: add first, remove in a later release. Migrations are never reversed.

## Rollback

Actions → *Deploy staging* → *Run workflow*, with `sha` set to an earlier `master` commit
whose images are still in GHCR. Only commits whose CI reached `images` have images, and
the server keeps only 24 hours of pulled images. This is the same blue/green switch, run in
the other direction. The schema stays as it is (see above). Start a rollback only when no
other deploy is waiting: GitHub keeps only the newest waiting run.

On the server directly: `bash /opt/etqan/scripts/ship.sh <previous-sha>`.

## On the server

```sh
bash /opt/etqan/scripts/manage.sh <command> [args]       # manage.py in the live colour
bash /opt/etqan/scripts/manage.sh shell -c "…"
bash /opt/etqan/scripts/manage.sh create_academy --name … --subdomain … --admin-email …
bash /opt/etqan/scripts/manage.sh set_features …         # per-academy feature switches
ssh -L 8025:127.0.0.1:8025 deploy@<server>                # staging Mailpit
bash /opt/etqan/scripts/edge-ca.sh > etqan-staging-root.crt  # staging's internal CA root
```

Flower has no public route in production. Reach it through an SSH tunnel.

## Configuration and secrets

- `/opt/etqan/.env.production` belongs to the server (chmod 600) and is never in git or CI.
  Templates: `infra/.env.production.example`, `infra/.env.staging.example`.
- Production settings fail at startup without `DJANGO_SECRET_KEY`, `DJANGO_FRONTEND_URL`,
  `DJANGO_TENANT_BASE_DOMAIN` and `DJANGO_S3_BUCKET`. Compose also requires `BASE_DOMAIN`,
  `ACME_EMAIL` and `CF_API_TOKEN`.
- **`ETQAN_SECRETS_KEY` is required in production.** It is the key that encrypts stored
  provider keys, TOTP seeds and the VAPID key (`etqan.platform.secrets`). It is
  comma-separated: the first key encrypts and all keys decrypt, which is how you rotate. It
  has no fallback in production: anything that needs a stored secret answers 503 without it.
  It is missing from both env templates, so add it by hand.
- Optional: `SENTRY_DSN`, `ETQAN_AI_FAKE`, `GATEWAYS_SIMULATE`, `JITSI_BASE_URL`,
  `WEB_PUSH_VAPID_*` (`manage.py make_vapid_keys`), `TWILIO_*`, `DJANGO_S3_PRIVATE_BUCKET` (for
  contract files). Provider accounts (Zoom, Stripe, email, WhatsApp, AI) are **not** env
  vars. Etqan's defaults are entered in the platform admin (`/admin/` on the base domain), and
  each academy enters its own under Settings → Integrations.
- CI secrets: `SUBMODULE_TOKEN`, `TOKENS_REPO_TOKEN`. The GitHub `staging` environment holds
  `STAGING_SSH_*`, `STAGING_KNOWN_HOSTS`, `GHCR_READ_TOKEN` and `STAGING_BASE_URL`.

## Custom domains

An academy registers its domain in the dashboard. The academy points a CNAME at
`DJANGO_EDGE_HOSTNAME` (`sites.<base>`), or an apex A record at `DJANGO_EDGE_PUBLIC_IP`. On
Cloudflare the record must be DNS-only. Caddy issues the certificate on the first request,
after asking Django's loopback-only `/internal/tls-allowed`, which allows only an active
`Domain` row. See [Tenancy](../../features/tenancy.md).
