# Local development

One command brings the whole stack up in Docker behind a Traefik reverse proxy.
Containers run as your host UID/GID, so nothing they write is owned by root.

## Prerequisites
- Docker + Docker Compose, `just`, and either the `gh` CLI authenticated
  (recommended) or a `GH_TOKEN` env var set.
- `gh` provides read access to the private `@kaleem/tokens` package the frontends
  install; the `justfile` derives the token automatically via `gh auth token`.
  If you don't use `gh`, export `GH_TOKEN=<a PAT with read access to kaleem-lms/tokens>`.

## First run
```bash
just setup     # submodules + build images + migrate + seed (all in Docker)
just dev       # brings the whole stack up (Ctrl-C to stop)
```

## URLs (no /etc/hosts edits — *.kaleem.localhost resolves to loopback)
| Service | URL |
| --- | --- |
| Dashboard | http://app.kaleem.localhost |
| Marketing | http://kaleem.localhost |
| API / admin | http://api.kaleem.localhost |
| Mailpit | http://mail.kaleem.localhost |
| Flower | http://flower.kaleem.localhost |
| Traefik dashboard | http://localhost:8080 |

## Why subdomains?
They reproduce ADR-0019's same-site cookie auth locally: the dashboard (`app-`)
and API (`api-`) share `kaleem.localhost`, so the session/CSRF cookies (scoped
`Domain=.kaleem.localhost`) flow across both. Login/CSRF/CORS bugs surface in
dev instead of on staging.

## Common commands
| Command | What it does |
| --- | --- |
| `just dev` | Whole stack up, foreground logs |
| `just dev-backend` | Whole stack up, detached |
| `just stop` | Stop the stack |
| `just rebuild` | Rebuild images after dependency/Dockerfile changes |
| `just logs <service>` | Tail one service (e.g. `just logs dashboard`) |
| `just migrate` / `just seed` / `just shell` | Django tasks, in the container |
| `just test` / `just lint` | Run in-container (CI parity) |
| `just test-backend-host` | Escape hatch: backend tests on the host `.venv` |

## Ownership
Dev containers run as your host UID/GID (the justfile injects them from
`id -u`/`id -g`). Files written into bind mounts — coverage data, caches, Vite/
Astro build artifacts — are owned by you, never root.

## Fallback: if *.kaleem.localhost does not resolve on your machine
Add one line to /etc/hosts:
`127.0.0.1 app.kaleem.localhost api.kaleem.localhost kaleem.localhost mail.kaleem.localhost flower.kaleem.localhost`
