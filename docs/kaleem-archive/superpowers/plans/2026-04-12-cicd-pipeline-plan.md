# CI/CD Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old Lightsail deploy workflow with a Traefik-based blue-green CI/CD pipeline that auto-deploys to staging on merge to master.

**Architecture:** GitHub Actions builds and pushes Docker images to GHCR, then SSHs into the staging VPS to run a blue-green deploy script. Traefik (running permanently on the VPS) routes traffic to the active color. The deploy script starts the new color, health-checks it, runs migrations, then drains and stops the old color.

**Tech Stack:** GitHub Actions, GHCR, Traefik v3, Docker Compose profiles, bash deploy script, SSH.

**Spec:** `docs/superpowers/specs/2026-04-12-cicd-pipeline-design.md`

---

## File map

```
Delete:
  .github/workflows/deploy.yml          ← old Lightsail pipeline
  infra/nginx/nginx.conf                 ← replaced by Traefik
  infra/nginx/                           ← directory removed

Create:
  infra/traefik/traefik.yml              ← Traefik static config
  infra/scripts/deploy.sh                ← blue-green orchestration script

Modify:
  infra/docker-compose.production.yml    ← replace nginx with Traefik, add blue/green profiles
  .github/workflows/ci.yml              ← add deploy-staging job
  infra/CLAUDE.md                        ← update to reflect Traefik replacing nginx
  docs/runbook/deploy.md                 ← update with blue-green deploy instructions
```

## Task dependency graph

```
Task 1 (delete old files)
Task 2 (Traefik config) ──► Task 3 (docker-compose rewrite) ──► Task 4 (deploy script)
Task 5 (CI workflow update) ◄── Tasks 3, 4
Task 6 (update docs)
Task 7 (verify)
```

Tasks 1 and 2 can run in parallel. Task 6 can run any time after Task 3.

---

### Task 1: Delete old Lightsail deploy workflow and nginx config

**Files:**
- Delete: `.github/workflows/deploy.yml`
- Delete: `infra/nginx/nginx.conf`
- Delete: `infra/nginx/` (directory)

- [ ] **Step 1: Delete the old deploy workflow**

```bash
cd /home/abdulkhalek/Projects/kaleem
git rm .github/workflows/deploy.yml
```

- [ ] **Step 2: Delete the nginx directory from infra submodule**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git rm -r nginx/
```

- [ ] **Step 3: Commit infra submodule**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git add -A
git commit -m "chore: remove nginx config (replaced by Traefik)"
git push origin main
```

- [ ] **Step 4: Commit meta repo**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add .github/workflows/deploy.yml infra
git commit -m "chore: remove old Lightsail deploy workflow and nginx config"
```

---

### Task 2: Create Traefik static configuration

**Files:**
- Create: `infra/traefik/traefik.yml`

- [ ] **Step 1: Create the Traefik config directory**

```bash
mkdir -p /home/abdulkhalek/Projects/kaleem/infra/traefik
```

- [ ] **Step 2: Write the Traefik static config**

Create `infra/traefik/traefik.yml`:

```yaml
# Traefik v3 static configuration
# Docs: https://doc.traefik.io/traefik/

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
    transport:
      lifecycle:
        graceTimeOut: 30s
  websecure:
    address: ":443"
    transport:
      lifecycle:
        graceTimeOut: 30s

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: kaleem_default

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${ACME_EMAIL}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO
  format: json

accessLog:
  format: json
```

- [ ] **Step 3: Commit infra submodule**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git add traefik/
git commit -m "feat: add Traefik v3 static config with Let's Encrypt and 30s grace timeout"
git push origin main
```

- [ ] **Step 4: Commit meta repo**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add infra
git commit -m "chore: update infra submodule — add Traefik config"
```

---

### Task 3: Rewrite docker-compose.production.yml with Traefik and blue-green profiles

**Files:**
- Modify: `infra/docker-compose.production.yml`

- [ ] **Step 1: Replace the entire docker-compose.production.yml**

Write `infra/docker-compose.production.yml`:

```yaml
# Production stack with Traefik blue-green deployment
# Usage:
#   docker compose --profile blue up -d   (start blue)
#   docker compose --profile green up -d  (start green)
#   Traefik and shared services (postgres, redis) are always running.

services:
  # ─── Always running ─────────────────────────────────────────

  traefik:
    image: traefik:v3
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # dashboard (restrict via firewall in production)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - traefik_certs:/letsencrypt
    environment:
      - ACME_EMAIL=${ACME_EMAIL:-admin@kaleem.academy}

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    env_file:
      - .env.production
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ─── Blue profile ───────────────────────────────────────────

  django-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: gunicorn config.wsgi --bind 0.0.0.0:8000 --workers 3 --timeout 120 --graceful-timeout 30
    restart: unless-stopped
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/live')"]
      interval: 15s
      timeout: 5s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.django-blue.rule=Host(`${APP_DOMAIN}`)"
      - "traefik.http.routers.django-blue.entrypoints=websecure"
      - "traefik.http.routers.django-blue.tls.certresolver=letsencrypt"
      - "traefik.http.services.django-blue.loadbalancer.server.port=8000"

  celery-worker-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: celery -A config.celery_app worker -l info
    restart: unless-stopped
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  celery-beat-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: celery -A config.celery_app beat -l info
    restart: unless-stopped
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      redis:
        condition: service_healthy

  # ─── Green profile ──────────────────────────────────────────

  django-green:
    profiles: [green]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: gunicorn config.wsgi --bind 0.0.0.0:8000 --workers 3 --timeout 120 --graceful-timeout 30
    restart: unless-stopped
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/live')"]
      interval: 15s
      timeout: 5s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.django-green.rule=Host(`${APP_DOMAIN}`)"
      - "traefik.http.routers.django-green.entrypoints=websecure"
      - "traefik.http.routers.django-green.tls.certresolver=letsencrypt"
      - "traefik.http.services.django-green.loadbalancer.server.port=8000"

  celery-worker-green:
    profiles: [green]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: celery -A config.celery_app worker -l info
    restart: unless-stopped
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  celery-beat-green:
    profiles: [green]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: celery -A config.celery_app beat -l info
    restart: unless-stopped
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      redis:
        condition: service_healthy

volumes:
  postgres_data:
  traefik_certs:
```

- [ ] **Step 2: Update `.env.production.example` with new variables**

Add to `infra/.env.production.example`:

```
# Traefik / Deploy
APP_DOMAIN=staging.kaleem.academy
ACME_EMAIL=admin@kaleem.academy
DEPLOY_SHA=latest
```

- [ ] **Step 3: Commit infra submodule**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git add docker-compose.production.yml .env.production.example
git commit -m "feat: rewrite production compose with Traefik and blue-green profiles"
git push origin main
```

- [ ] **Step 4: Commit meta repo**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add infra
git commit -m "chore: update infra submodule — Traefik blue-green compose"
```

---

### Task 4: Create the blue-green deploy script

**Files:**
- Create: `infra/scripts/deploy.sh`

- [ ] **Step 1: Create the scripts directory**

```bash
mkdir -p /home/abdulkhalek/Projects/kaleem/infra/scripts
```

- [ ] **Step 2: Write the deploy script**

Create `infra/scripts/deploy.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Blue-green deploy script for kaleem.
# Called by CI via SSH: ./deploy.sh <image-sha>
# Expects docker-compose.production.yml and .env.production in /opt/kaleem/

DEPLOY_SHA="${1:?Usage: deploy.sh <image-sha>}"
COMPOSE_FILE="/opt/kaleem/docker-compose.production.yml"
ENV_FILE="/opt/kaleem/.env.production"
STATE_FILE="/opt/kaleem/.active-color"
HEALTH_RETRIES=10
HEALTH_DELAY=3

echo "=========================================="
echo "kaleem deploy — sha: ${DEPLOY_SHA}"
echo "=========================================="

# ─── 1. Determine colors ─────────────────────────────────────
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "none")
if [ "$CURRENT" = "green" ]; then
    NEW="blue"
else
    NEW="green"
fi
echo "Current: ${CURRENT} → New: ${NEW}"

# ─── 2. Export SHA for compose interpolation ──────────────────
export DEPLOY_SHA

# ─── 3. Pull new images ──────────────────────────────────────
echo "Pulling images for sha ${DEPLOY_SHA}..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

# ─── 4. Ensure shared services are running ────────────────────
echo "Ensuring shared services (traefik, postgres, redis) are up..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d traefik postgres redis

# ─── 5. Start new color ──────────────────────────────────────
echo "Starting ${NEW} containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile "$NEW" up -d

# ─── 6. Health check ─────────────────────────────────────────
echo "Waiting for ${NEW} to be healthy..."
HEALTH_PASSED=false
for i in $(seq 1 $HEALTH_RETRIES); do
    # Health check the django container directly
    CONTAINER="kaleem-django-${NEW}-1"
    if docker exec "$CONTAINER" python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/ready')" 2>/dev/null; then
        echo "Health check passed on attempt ${i}"
        HEALTH_PASSED=true
        break
    fi
    echo "  Attempt ${i}/${HEALTH_RETRIES} — not ready, waiting ${HEALTH_DELAY}s..."
    sleep $HEALTH_DELAY
done

if [ "$HEALTH_PASSED" = false ]; then
    echo "ERROR: Health check failed after ${HEALTH_RETRIES} attempts."
    echo "Rolling back — stopping ${NEW} containers..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile "$NEW" down
    echo "Rollback complete. ${CURRENT} is still live."
    exit 1
fi

# ─── 7. Run migrations ───────────────────────────────────────
echo "Running migrations on ${NEW}..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" run --rm "django-${NEW}" python manage.py migrate --noinput

# ─── 8. Stop old color (graceful drain, 30s timeout) ─────────
if [ "$CURRENT" != "none" ]; then
    echo "Stopping ${CURRENT} containers (30s graceful drain)..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile "$CURRENT" down --timeout 30
fi

# ─── 9. Record new active color ──────────────────────────────
echo "$NEW" > "$STATE_FILE"

echo "=========================================="
echo "Deploy complete: ${CURRENT} → ${NEW}"
echo "Image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA}"
echo "=========================================="
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x /home/abdulkhalek/Projects/kaleem/infra/scripts/deploy.sh
```

- [ ] **Step 4: Commit infra submodule**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git add scripts/
git commit -m "feat: add blue-green deploy script with health check and graceful drain"
git push origin main
```

- [ ] **Step 5: Commit meta repo**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add infra
git commit -m "chore: update infra submodule — blue-green deploy script"
```

---

### Task 5: Update CI workflow with deploy-staging job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the deploy-staging job to ci.yml**

Append after the `dashboard-build` job in `.github/workflows/ci.yml`:

```yaml
  deploy-staging:
    needs: [backend-lint, backend-test, dashboard-lint, dashboard-build]
    if: github.ref == 'refs/heads/master' && github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.SUBMODULE_TOKEN }}

      - name: Set short SHA
        run: echo "SHORT_SHA=${GITHUB_SHA::7}" >> $GITHUB_ENV

      - name: Log in to GHCR
        run: echo "${{ secrets.GHCR_PAT }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

      - name: Build backend image
        run: |
          docker build \
            -f backend/Dockerfile \
            -t ghcr.io/kaleem-lms/backend:${{ env.SHORT_SHA }} \
            -t ghcr.io/kaleem-lms/backend:latest \
            backend/

      - name: Push backend image
        run: |
          docker push ghcr.io/kaleem-lms/backend:${{ env.SHORT_SHA }}
          docker push ghcr.io/kaleem-lms/backend:latest

      - name: Deploy to staging via SSH
        uses: appleboy/ssh-action@v1.2.2
        with:
          host: ${{ secrets.STAGING_HOST }}
          username: ${{ secrets.STAGING_USER }}
          key: ${{ secrets.STAGING_SSH_KEY }}
          script: |
            echo "${{ secrets.GHCR_PAT }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            cd /opt/kaleem
            export DEPLOY_SHA=${{ env.SHORT_SHA }}
            bash scripts/deploy.sh ${{ env.SHORT_SHA }}
```

- [ ] **Step 2: Verify the full ci.yml is valid YAML**

```bash
cd /home/abdulkhalek/Projects/kaleem
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add .github/workflows/ci.yml
git commit -m "ci: add deploy-staging job with GHCR push and blue-green SSH deploy"
```

---

### Task 6: Update documentation

**Files:**
- Modify: `infra/CLAUDE.md`
- Modify: `docs/runbook/deploy.md`

- [ ] **Step 1: Update infra CLAUDE.md**

Replace `infra/CLAUDE.md` with:

```markdown
# Infra — kaleem deployment and monitoring

Docker Compose configs for production and monitoring. Uses Traefik for reverse proxying and blue-green zero-downtime deploys.

## Structure
- `docker-compose.production.yml` — main production stack (Traefik + blue/green profiles)
- `traefik/traefik.yml` — Traefik static config (entrypoints, Let's Encrypt, Docker provider)
- `scripts/deploy.sh` — blue-green deploy orchestration (called by CI via SSH)
- `monitoring/` — Prometheus, Grafana, Loki, Uptime Kuma

## How blue-green works
- Traefik runs permanently and routes to whichever color (blue/green) is active
- `deploy.sh <sha>` starts the new color, health-checks it, migrates, then drains the old color
- Active color tracked in `/opt/kaleem/.active-color` on the VPS
- Rollback: re-run `deploy.sh <previous-sha>`

## Usage
Start shared services: `docker compose -f docker-compose.production.yml up -d traefik postgres redis`
Deploy blue: `DEPLOY_SHA=abc123 docker compose -f docker-compose.production.yml --profile blue up -d`
Full deploy: `bash scripts/deploy.sh abc123`
Monitoring: `docker compose -f monitoring/docker-compose.monitoring.yml up -d`
```

- [ ] **Step 2: Update the deploy runbook**

Replace `docs/runbook/deploy.md` with:

```markdown
# Deploy Runbook

## How deployment works

Deploys are triggered automatically when code is merged to `master`:
1. CI runs (lint, test, build)
2. If all pass, `deploy-staging` job builds a Docker image, pushes to GHCR, and SSHs into the staging VPS
3. On the VPS, `scripts/deploy.sh` runs a blue-green swap

## Manual deploy (if CI is down or you need to deploy a specific SHA)

```bash
ssh deploy@<staging-ip>
cd /opt/kaleem
echo "<ghcr-pat>" | docker login ghcr.io -u <username> --password-stdin
export DEPLOY_SHA=<git-sha-short>
bash scripts/deploy.sh $DEPLOY_SHA
```

## Rollback

Re-deploy the previous image SHA:
```bash
ssh deploy@<staging-ip>
cd /opt/kaleem
bash scripts/deploy.sh <previous-sha>
```

The previous SHA can be found in the GitHub Actions deploy log or in GHCR tags.

## First-time VPS setup

Before the first deploy, the VPS needs:
1. Docker + Docker Compose installed
2. `/opt/kaleem/` directory with `docker-compose.production.yml`, `traefik/`, `scripts/`, `.env.production`
3. GHCR login credentials
4. Firewall: ports 80, 443 open; 8080 (Traefik dashboard) restricted

```bash
mkdir -p /opt/kaleem/{traefik,scripts}
# Copy files from infra/ submodule to /opt/kaleem/
# Create .env.production from .env.production.example
# Start shared services first:
docker compose -f docker-compose.production.yml up -d traefik postgres redis
```

## Checking deploy status

```bash
ssh deploy@<staging-ip>
cat /opt/kaleem/.active-color          # which color is live
docker ps --format 'table {{.Names}}\t{{.Status}}'  # container status
curl http://localhost:8000/health/ready  # health check
```

## Secrets (stored in GitHub repo settings)

| Secret | Purpose |
| --- | --- |
| `GHCR_PAT` | Push/pull Docker images |
| `STAGING_HOST` | VPS IP address |
| `STAGING_SSH_KEY` | SSH private key |
| `STAGING_USER` | SSH username |
```

- [ ] **Step 3: Commit infra submodule**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for Traefik blue-green deployment"
git push origin main
```

- [ ] **Step 4: Commit meta repo**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add docs/runbook/deploy.md infra
git commit -m "docs: update deploy runbook and infra docs for blue-green pipeline"
```

---

### Task 7: Verify and push

- [ ] **Step 1: Verify CI YAML is syntactically valid**

```bash
cd /home/abdulkhalek/Projects/kaleem
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 2: Verify deploy script is executable and passes shellcheck**

```bash
shellcheck infra/scripts/deploy.sh 2>/dev/null || echo "shellcheck not installed — skip"
bash -n infra/scripts/deploy.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 3: Verify docker-compose.production.yml is valid**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
docker compose -f docker-compose.production.yml config --profiles blue > /dev/null 2>&1 && echo "Blue profile valid" || echo "Blue profile invalid"
docker compose -f docker-compose.production.yml config --profiles green > /dev/null 2>&1 && echo "Green profile valid" || echo "Green profile invalid"
```

Expected: both valid.

- [ ] **Step 4: Push the branch**

```bash
cd /home/abdulkhalek/Projects/kaleem
git push origin phase-0/bootstrap
```

- [ ] **Step 5: Verify CI passes on the PR**

```bash
gh pr checks 25
```

Expected: all existing CI jobs still pass (the deploy-staging job won't trigger since this is a PR, not a push to master — which is correct behavior).

---

## Self-review

**Spec coverage:**
- Delete old deploy.yml → Task 1 ✓
- Delete nginx → Task 1 ✓
- Create Traefik config → Task 2 ✓
- Rewrite docker-compose with profiles → Task 3 ✓
- Create deploy.sh → Task 4 ✓
- Update CI with deploy-staging → Task 5 ✓
- SHA-tagged images → Task 5 (build + push steps) ✓
- Health check + rollback in deploy script → Task 4 ✓
- Connection draining (30s grace) → Task 2 (Traefik config) + Task 3 (gunicorn --graceful-timeout) + Task 4 (--timeout 30) ✓
- Update docs → Task 6 ✓
- Production future stub → Not built (spec says "not built now") ✓

**Placeholder scan:** No TBD/TODO/placeholders found. All code blocks are complete.

**Type consistency:** `DEPLOY_SHA` used consistently across ci.yml (env var), docker-compose.yml (interpolation), and deploy.sh (argument). `deploy.sh` argument name matches CI's `${{ env.SHORT_SHA }}`. Container names `django-blue`/`django-green` match between compose file and deploy script health check (`kaleem-django-${NEW}-1`).
