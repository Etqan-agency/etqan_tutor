---
name: cicd-pipeline
description: CI/CD pipeline with Traefik blue-green deployment for staging (auto) and production (future, manual)
phase: 0
modules: []
status: draft
created: 2026-04-12
closed: null
---

## Goal

Replace the old Lightsail deploy workflow with a clean CI/CD pipeline that auto-deploys to staging on merge to master using Traefik-based blue-green deployment (zero downtime). Production deployment is scaffolded for future use with a manual trigger.

## What changes

1. **Delete** `.github/workflows/deploy.yml` (old Lightsail pipeline)
2. **Update** `.github/workflows/ci.yml` — add `deploy-staging` job after CI passes
3. **Replace** `infra/nginx/` with `infra/traefik/` (Traefik replaces nginx as reverse proxy)
4. **Update** `infra/docker-compose.production.yml` — add Traefik, Docker labels, blue/green profiles
5. **Create** `infra/scripts/deploy.sh` — blue-green orchestration script

## Architecture

### CI/CD flow

```
push/merge to master
  ├── backend-lint     ─┐
  ├── backend-test      ├── all pass ──► deploy-staging
  ├── dashboard-lint   ─┤
  └── dashboard-build  ─┘

PR only → CI jobs run, no deploy
```

### Blue-green deploy flow

```
Internet ──► Traefik ──► active color (blue or green)

Deploy steps:
1. Read current live color from /opt/kaleem/.active-color
2. New color = opposite
3. Pull new images (tagged git SHA + latest)
4. Start new color containers via docker compose --profile {new} up -d
5. Wait, health check: curl /health/ready on new containers
6. If healthy:
   - Run migrations on new containers
   - Update Traefik routing to new color (relabel)
   - Stop old color containers
   - Write new color to .active-color
7. If unhealthy:
   - Stop new containers
   - Old containers still live, untouched
   - Exit 1 (CI job fails)
```

### Traefik setup

Traefik runs as a permanent container (not part of blue/green swap). It discovers backends via Docker labels automatically. Configuration:

- **Static config** (`traefik/traefik.yml`): entrypoints (80, 443), Docker provider, Let's Encrypt ACME for TLS, **connection drain grace period** (`entrypoints.web.transport.lifecycle.graceTimeOut=30s`)
- **Docker labels** on django-blue / django-green: `traefik.http.routers.django.rule=Host(...)`, routing rules
- **Dashboard**: enabled on a separate port for debugging (optional, auth-protected)

### Connection draining during blue-green swap

When traffic switches from old to new color, in-flight connections are handled gracefully:

1. **HTTP requests**: short-lived (milliseconds), complete before the swap finishes. No impact.
2. **WebSocket connections** (Phase D, when messaging is built): long-lived. Handled by three layers:
   - **Traefik grace timeout (30s)**: `entrypoints.web.transport.lifecycle.graceTimeOut=30s` — Traefik gives existing connections 30 seconds to complete before routing them away
   - **Docker graceful shutdown (30s)**: `docker compose --profile old down --timeout 30` — sends SIGTERM, Daphne/Uvicorn drains active connections for 30s before SIGKILL
   - **Client auto-reconnect**: WebSocket clients (built in Phase D) auto-reconnect on disconnect — standard practice for any WebSocket app

**Net effect**: HTTP users see zero downtime. WebSocket users see at most a 1-second reconnection blip (connection drops, client reconnects to new color automatically).

### Docker Compose structure (single file, profiles)

```yaml
services:
  # ─── Always running ───
  traefik:
    image: traefik:v3
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - traefik_certs:/letsencrypt

  postgres:
    image: postgres:16-alpine
    # shared between blue and green

  redis:
    image: redis:7-alpine
    # shared between blue and green

  # ─── Blue profile ───
  django-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.django.rule=Host(`${APP_DOMAIN}`)"
      - "traefik.http.services.django.loadbalancer.server.port=8000"

  celery-worker-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: celery -A config.celery_app worker -l info

  celery-beat-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: celery -A config.celery_app beat -l info

  # ─── Green profile ───
  django-green:
    profiles: [green]
    # same as blue, different container name

  celery-worker-green:
    profiles: [green]

  celery-beat-green:
    profiles: [green]
```

### Image tagging

Every deploy pushes two tags:
```
ghcr.io/kaleem-lms/backend:<git-sha-short>
ghcr.io/kaleem-lms/backend:latest
```

Rollback = redeploy with a previous SHA.

### Secrets required

| Secret | Purpose | New? |
| --- | --- | --- |
| `SUBMODULE_TOKEN` | Checkout private submodules in CI | Already exists |
| `GHCR_PAT` | Push/pull Docker images to GitHub Container Registry | Create (or reuse from old setup) |
| `STAGING_HOST` | Staging server IP or hostname | Create |
| `STAGING_SSH_KEY` | SSH private key for staging server | Create |
| `STAGING_USER` | SSH username on staging server | Create |

### CI workflow changes

The `deploy-staging` job in `ci.yml`:

```yaml
deploy-staging:
  needs: [backend-lint, backend-test, dashboard-lint, dashboard-build]
  if: github.ref == 'refs/heads/master' && github.event_name == 'push'
  runs-on: ubuntu-latest
  steps:
    - Checkout with submodules
    - Log in to GHCR
    - Build backend image
    - Tag with git SHA + latest
    - Push to GHCR
    - SSH into staging server
    - Run deploy.sh with the git SHA as argument
    - Verify health check passes
```

### Deploy script (`infra/scripts/deploy.sh`)

Runs on the VPS. Called by CI via SSH with the image tag as argument.

```bash
#!/usr/bin/env bash
set -euo pipefail

DEPLOY_SHA="${1:?Usage: deploy.sh <image-sha>}"
COMPOSE_FILE="/opt/kaleem/docker-compose.production.yml"
STATE_FILE="/opt/kaleem/.active-color"
HEALTH_URL="http://localhost:8000/health/ready"
HEALTH_RETRIES=10
HEALTH_DELAY=3

# 1. Determine colors
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "blue")
NEW=$([ "$CURRENT" = "blue" ] && echo "green" || echo "blue")

# 2. Pull new images
export DEPLOY_SHA
docker compose -f "$COMPOSE_FILE" pull

# 3. Start new color
docker compose -f "$COMPOSE_FILE" --profile "$NEW" up -d

# 4. Health check
for i in $(seq 1 $HEALTH_RETRIES); do
  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "Health check passed on attempt $i"
    break
  fi
  if [ "$i" = "$HEALTH_RETRIES" ]; then
    echo "Health check failed after $HEALTH_RETRIES attempts. Rolling back."
    docker compose -f "$COMPOSE_FILE" --profile "$NEW" down
    exit 1
  fi
  sleep $HEALTH_DELAY
done

# 5. Run migrations
docker compose -f "$COMPOSE_FILE" run --rm "django-$NEW" python manage.py migrate --noinput

# 6. Stop old color with graceful connection drain (30s timeout)
docker compose -f "$COMPOSE_FILE" --profile "$CURRENT" down --timeout 30

# 7. Record new active color
echo "$NEW" > "$STATE_FILE"
echo "Deploy complete: $CURRENT → $NEW (sha: $DEPLOY_SHA)"
```

### Production (future, not built now)

When ready, add to `ci.yml`:
```yaml
deploy-production:
  if: github.event_name == 'workflow_dispatch'
  # same steps as deploy-staging but with PRODUCTION_* secrets
```

One job, different secrets. Same deploy.sh script. Added when there are paying users, not before.

### Files to delete

- `.github/workflows/deploy.yml` (old Lightsail pipeline)
- `infra/nginx/nginx.conf` (replaced by Traefik)
- `infra/nginx/` directory

### Files to create

- `infra/traefik/traefik.yml` — Traefik static config
- `infra/scripts/deploy.sh` — blue-green deploy script

### Files to modify

- `.github/workflows/ci.yml` — add deploy-staging job
- `infra/docker-compose.production.yml` — replace nginx with Traefik, add profiles and labels

## Out of scope

- Dashboard static file deployment (Astro/React builds) — handled separately when frontend is deployed to CDN or the same VPS
- SSL certificate setup on the VPS — documented in deploy runbook, not automated in CI
- Production deploy — scaffolded as a job stub but not wired to any server
- Monitoring stack deployment — already handled separately in `monitoring/docker-compose.monitoring.yml`

## Test plan

- CI jobs still pass (lint, test, build) — no regression
- `deploy-staging` job only runs on push to master, not on PRs
- Deploy script health check correctly rolls back on failure (test by temporarily breaking the health endpoint)
- Blue-green swap works: first deploy creates blue, second deploy creates green and stops blue
- Traefik routes traffic to the active color
- Image tagged with git SHA in GHCR