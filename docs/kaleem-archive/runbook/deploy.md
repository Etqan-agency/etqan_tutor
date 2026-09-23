# Deploy Runbook

## How deployment works

Deploys are triggered automatically when code is merged to `master`:

1. CI runs (lint, test, build)
2. If all pass, `deploy-staging` job builds a Docker image, pushes to GHCR, and SSHs into the staging VPS
3. On the VPS, `scripts/ship.sh` runs a blue-green swap

## Manual deploy (if CI is down or you need to deploy a specific SHA)

```bash
ssh deploy@<staging-ip>
cd /opt/kaleem
echo "<ghcr-pat>" | docker login ghcr.io -u <username> --password-stdin
export DEPLOY_SHA=<git-sha-short>
bash scripts/ship.sh $DEPLOY_SHA
```

## Rollback

Re-deploy the previous image SHA:

```bash
ssh deploy@<staging-ip>
cd /opt/kaleem
bash scripts/ship.sh <previous-sha>
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

### `.env.production` is hand-managed, and a missing variable rolls the deploy back

There is no `.env.production` in git. It is created by hand on this VPS and
edited by hand thereafter, so **a variable added to
`infra/.env.production.example` does not reach the server until someone copies
it across**. `ship.sh` health-gates the new colour and rolls back *all* of it
— including a perfectly healthy Django — if any one service fails to come up,
so a forgotten variable presents as "the whole deploy failed" rather than as
"one feature is off".

Before deploying a change that adds an environment variable, diff the two:

```bash
# On the VPS. Lists variable names present in the template but not in the
# live file — the ones that will take the next deploy down.
comm -23 \
  <(grep -oP '^[A-Z_]+(?==)' /opt/kaleem/.env.production.example | sort) \
  <(grep -oP '^[A-Z_]+(?==)' /opt/kaleem/.env.production | sort)
```

Variables added in Phase C3b (signaling / WebRTC) — all four are required, see
`docs/runbook/signaling.md`:

| Variable | Read by | Missing means |
| --- | --- | --- |
| `WS_DOMAIN` | `docker-compose.production.yml` | `${WS_DOMAIN:?WS_DOMAIN is required}` fails interpolation before anything starts; **deploy aborts immediately**, not a routing failure caught later by a health check |
| `DJANGO_SIGNALING_SECRET` | both `django-*` and `signaling-*` | signaling's health check 503s; **deploy rolls back** |
| `DJANGO_SIGNALING_URL` | `django-*` | `SignalingProvider` refuses to construct (`ImproperlyConfigured`) |
| `DJANGO_VIDEO_PROVIDER` | `django-*` | falls back to `FakeVideoProvider` — deploy succeeds, signaling is healthy, and **no lesson can reach it** |

## Checking deploy status

```bash
ssh deploy@<staging-ip>
cat /opt/kaleem/.active-color
docker ps --format 'table {{.Names}}\t{{.Status}}'
curl http://localhost:8000/health/ready/
```

## Secrets (stored in GitHub repo settings)

| Secret | Purpose |
| --- | --- |
| `GHCR_PAT` | Push/pull Docker images |
| `STAGING_HOST` | VPS IP address |
| `STAGING_SSH_KEY` | SSH private key |
| `STAGING_USER` | SSH username |
