# Flower — Celery monitoring dashboard

- **Date:** 2026-06-10
- **Status:** Approved (brainstorming → ready for implementation)
- **Phase:** A (infrastructure / observability)
- **Repos touched:** `backend`, `infra`, meta (spec + local compose + pointer bumps)

## Problem

Celery (worker + beat) runs locally and in the blue/green production stack, but
there is no visibility into workers, queues, task throughput, or failures. When a
task hangs or errors we have no dashboard — only logs. We want
[Flower](https://flower.readthedocs.io/) as a read-only monitoring UI on the Redis
broker.

## Goals

- A Flower dashboard locally for development.
- A Flower dashboard on staging and production, protected by auth and TLS.
- No new image to maintain — run Flower from the existing backend image so its
  Celery/Flower versions track the app.

## Non-goals

- Persisting task history in a database (Flower's in-memory/broker view is enough
  for now). Revisit if we need long-term task analytics — that belongs in the
  `analytics` module, not Flower.
- Prometheus scraping of Flower metrics (the `infra/monitoring` stack can wire this
  later; out of scope here).

## Design

Flower is a **singleton** that watches the shared Redis broker. It does not
participate in blue/green — it sits alongside `traefik`/`postgres`/`redis`.

### Backend

Add `flower>=2.0` to `backend/requirements/base.txt` (next to `celery[redis]`), so
it ships in the GHCR image and is available locally too.

### Local — `docker-compose.local.yml` (meta repo root)

New `flower` service:

- backend `dev` target image
- command: `celery -A config.celery_app flower --port=5555`
- ports: `5555:5555`
- `depends_on: redis` (broker URL via the same `CELERY_BROKER_URL` env as the worker)
- no auth — bound to the developer's machine

### Production / staging — `infra/docker-compose.production.yml`

New `flower` service in the **"Always running"** section (no `blue`/`green`
profile, so it is untouched by colour swaps and survives every deploy):

- image: `ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}`
- command: `celery -A config.celery_app flower --port=5555`
- `restart: unless-stopped`
- `env_file: .env.production`, `depends_on: redis`
- Traefik labels:
  - router rule `Host(\`${FLOWER_DOMAIN}\`)`, entrypoint `websecure`,
    `tls.certresolver=letsencrypt`
  - service loadbalancer port `5555`
  - **basic-auth middleware** `flower-auth.basicauth.users=${FLOWER_BASIC_AUTH}`
    attached to the router. Flower exposes task arguments/payloads, so it never
    goes out unauthenticated.

### Env — `infra/.env.production.example`

```
# Flower (Celery monitoring) — own subdomain, Traefik basic-auth
FLOWER_DOMAIN=flower.staging.kaleem.academy
# htpasswd bcrypt hash, e.g. `htpasswd -nbB admin <pass>`; double every `$` to `$$`
FLOWER_BASIC_AUTH=
```

On **staging** `FLOWER_DOMAIN=flower.staging.kaleem.academy`; on **production**
`flower.kaleem.academy`.

### Deploy — `infra/scripts/ship.sh`

Staging and production share the same `docker-compose.production.yml`, differing only
by `.env.production`. So Flower deploys to both automatically. The one change:
`ship.sh` step 4 explicitly starts the profile-less singletons, so add `flower`:

```
docker compose ... up -d traefik postgres redis flower
```

Every deploy then pulls Flower's new image and ensures it is running. The blue/green
colour swap (steps 5–8) never touches it.

## Manual one-time setup (per environment)

- **DNS:** A record `flower.staging.kaleem.academy` (and later `flower.kaleem.academy`)
  → VPS IP, so Let's Encrypt can issue the cert.
- **Credentials:** generate `FLOWER_BASIC_AUTH` via `htpasswd -nbB admin <pass>`,
  double the `$` to `$$`, and set it in each `.env.production`.

## Testing / verification

- **Local:** `docker compose -f docker-compose.local.yml up flower` → open
  `http://localhost:5555`, confirm workers and the beat schedule appear; fire a task
  and watch it land.
- **Staging:** after deploy, `https://flower.staging.kaleem.academy` prompts for basic
  auth, serves over valid TLS, and shows the live worker.

## Risks / notes

- Flower reads the broker, not a DB, so it adds negligible load.
- Basic-auth secret lives only in `.env.production` (gitignored); the example file
  carries an empty placeholder.
- If we later want SSO instead of basic-auth, swap the Traefik middleware — the
  service definition is unaffected.
