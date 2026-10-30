---
title: "Operations"
---

Keeping a deployed stack healthy: health checks, logs and errors, background jobs, academy
administration, and the known gaps. For deploys and rollback see [Deploy](deploy.md).

## Health

| Check | Meaning |
|---|---|
| `GET /health/live/` | The process is up. Always `{"status": "ok"}`. Used by Docker's healthcheck |
| `GET /health/ready/` | The database answers (`SELECT 1`), or 503. Caddy routes only to a colour that passes it, and `ship.sh` and `smoke.sh` gate on it |
| `infra/scripts/smoke.sh <academy-url>` | The post-deploy check: API ready, staff admin, dashboard shell, public site |

Both are served on every academy host and on the base domain.

## Errors and logs

- **Sentry.** Errors and traces when `SENTRY_DSN` is set (`config/settings/base.py`).
  The sample rate defaults to 0.1, with no local variables and no PII sent.
- **Logs.** `docker logs etqan-django-$(cat /opt/etqan/.active-color)-1`, and the same for
  `celery-worker-<c>` and `celery-beat-<c>`. Each request carries a request ID
  (`etqan.platform.middleware.RequestIDMiddleware`), so search by it.
- **Monitoring stack.** `infra/monitoring/` (Prometheus, Grafana, Loki, promtail, Uptime
  Kuma) **does not work as committed**. Prometheus scrapes `django:8000/metrics`, but no
  `django` service exists in production (it is `django-blue`/`django-green`) and the backend
  exposes no metrics endpoint. promtail has no config file. Treat it as a starting point.
  Uptime Kuma polling `/health/ready/` is the quickest useful piece.

## Background jobs

Celery worker and beat run per colour, and swap with the deploy. The broker is Redis, and
the schedule is stored in the database (django-celery-beat), seeded from
`CELERY_BEAT_SCHEDULE`. Every job loops over active academies with `for_each_academy`. One
academy failing is logged and the rest continue. Limits are a 60-second soft and 300-second
hard limit per task.

| Task | When | What |
|---|---|---|
| `notifications.scan` | every minute | finds due notices and sends them |
| `devices.push` | every minute | sends web push |
| `scheduling.provision_meetings` | every 5 min | fills blank meeting links for the next day's sessions |
| `consultations.cancel_unpaid` | every 15 min | releases unpaid consultation holds |
| `scheduling.run_daily` | hourly at :05 | daily scheduling work, per academy local time |
| `etqan_billing.issue_due` | hourly at :10 | issues Etqan's drafted invoices to academies after 24 hours |
| `registration.expire_unconfirmed` | 03:15 | drops registrations nobody confirmed |
| `gateways.expire_checkouts` | 03:20 | expires abandoned online checkouts |
| `etqan_billing.build_month` | 1st, 03:00 UTC | drafts Etqan's monthly invoices to academies |

Watch queues with Flower (an SSH tunnel in production, `flower.etqan.localhost` locally).

## Academy administration (Etqan staff)

On the base domain's `/admin/`, or with `manage.sh`:

- create an academy: `create_academy --name … --subdomain … --admin-email …`;
- switch features: `set_features` or the academy's page in the admin. Only `etqan.tenants`
  writes switches;
- suspend an academy: set its status. Suspended academies are refused at the middleware and
  skipped by every job;
- Etqan's default provider accounts, prices, Connect fee, usage and invoices to academies:
  the integrations and Etqan billing sections of the admin. See
  [Integrations](../../features/integrations.md) and [Etqan billing](../../features/etqan-billing.md).

## Docs site users

`docs.<base domain>` (this site) is behind Caddy's basic_auth; every path needs a user. The
users live in `/opt/etqan/caddy/docs-users/users.caddy` on the server, one
`name <bcrypt hash>` line per person, never in git. Caddy gets the whole `docs-users/`
directory (read-only), so it sees the file however it is edited. `ship.sh` and
`deploy-staging.sh` refuse to deploy unless it is a regular file with at least one user
line, because Caddy cannot load its configuration without it.

In `/opt/etqan` (on staging add `-f docker-compose.staging.yml` after the production file):

```sh
dc() { docker compose -f docker-compose.production.yml --env-file .env.production "$@"; }
```

Add a person:

```sh
dc exec caddy caddy hash-password          # type the password twice; prints $2a$14$…
echo 'alice $2a$14$…' >> caddy/docs-users/users.caddy
dc exec caddy caddy reload --config /etc/caddy/Caddyfile
```

`>>` appends one line without touching the others, so a typo cannot wipe the file the way a
`>` would. Put the hash in single quotes: it contains `$`.

The very first user, before a deploy that carries the docs site (Caddy is not running with
the file yet):

```sh
install -d -m 755 caddy/docs-users
docker run --rm -it caddy:2.11.4-alpine caddy hash-password
echo 'alice $2a$14$…' > caddy/docs-users/users.caddy
```

Remove a person, then check they are gone:

```sh
sed -i '/^alice /d' caddy/docs-users/users.caddy
dc exec caddy caddy reload --config /etc/caddy/Caddyfile
dc exec caddy grep -c '^alice ' /etc/caddy/docs-users/users.caddy   # prints 0
curl -s -o /dev/null -w '%{http_code}\n' -u 'alice:<their password>' https://docs.<base domain>/   # 401
```

Keep at least one user: a file with none stops the next deploy.

## Backups: not in place yet

There is no backup or restore tooling in the repo. PostgreSQL is a single container on the
`postgres_data` volume, and uploaded media is in S3. Until there is a backup job, a manual
dump from the server works:

```sh
docker exec etqan-postgres-1 pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" > etqan-$(date +%F).dump
```

`pg_dump` of the whole database includes every academy's schema. Restoring one academy means
restoring its schema (`pg_restore -n <schema>`) into a scratch database first. Setting up
scheduled, off-server backups with tested restores is an open task.

## Incidents: first steps

1. `smoke.sh` against the affected academy, and `/health/ready/` on the base domain.
2. Is it one academy or all? One academy: check its `Domain` row, status and feature
   switches. All of them: check the active colour's logs, then Postgres and Redis.
3. A bad deploy: roll back (see [Deploy](deploy.md#rollback)). Schema changes stay, which is
   why migrations are backward-compatible.
4. A stuck job: Flower, then the worker logs. Jobs are safe to re-run per academy.
5. Custom domain without TLS: check DNS (CNAME to `sites.<base>`, grey cloud) and that the
   `Domain` row is active, because `/internal/tls-allowed` refuses anything else.
