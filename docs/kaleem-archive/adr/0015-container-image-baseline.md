---
number: 0015
title: Container image baseline — Postgres 18, Redis 8, Python 3.13
status: accepted
date: 2026-06-09
---

## Context

The container images were pinned early in Phase 0 and had drifted behind both
upstream and our own dev environment:

- Postgres `16-alpine` across local compose, production compose, and the CI
  `postgres` service.
- Redis `7-alpine` in the same three places.
- Python `3.12-slim` in the backend `Dockerfile` and `3.12` in CI, while the
  local dev venv already runs 3.13.7 — so Docker and CI lagged the interpreter
  developers actually use, risking "works on my machine" version skew.

We are still in Phase 0/A: there is no production data and no public launch, so
this is the cheapest window to move the baseline forward before data and uptime
constraints make a major-version Postgres bump expensive.

## Decision

Adopt a single current baseline for the data/runtime containers, applied
identically in local compose, production compose, and CI:

- **Postgres 18** (`postgres:18-alpine`)
- **Redis 8** (`redis:8-alpine`)
- **Python 3.13** (`python:3.13-slim`; `tool.mypy.python_version` and
  `tool.ruff.target-version` set to 3.13 / `py313`)

Traefik stays on `v3` and the monitoring stack stays on `:latest` for now — out
of scope here, tracked separately if we decide to pin them.

## Alternatives considered

- **Stay on Postgres 16.** 16 is supported for years, so there is no forced
  move. Rejected because doing the major bump now (zero data, zero uptime cost)
  is far cheaper than doing it post-launch, and keeping dev/CI/prod on one modern
  version avoids drift.
- **Bump Postgres but leave Redis 7 / Python 3.12.** Rejected — Redis 8 is GA
  under an OSI-approved license again, and aligning Python with the 3.13 dev venv
  removes a real skew. Doing all three at once is one coordinated change rather
  than three trickles.
- **Pin to exact patch tags (e.g. `18.1-alpine`).** Rejected for now; the
  `<major>-alpine` floating tag matches the existing convention and Renovate/
  Dependabot pinning is a separate decision.

## Consequences

- **Postgres major versions have incompatible on-disk data directories.** A
  cluster initialized by 16 will not start under 18. Local dev must recreate the
  volume (`docker compose -f docker-compose.local.yml down -v`, then `just
  setup`/`migrate`). This is safe because local data is disposable seed data.
- **The PG 18 Docker image changed the data-directory layout.** 18+ stores data
  in a major-version-specific subdirectory under `/var/lib/postgresql` (so
  `pg_upgrade --link` works without mount-boundary issues). The volume mount in
  both compose files therefore had to move from `/var/lib/postgresql/data` to
  `/var/lib/postgresql`; the image refuses to start with the old `.../data`
  mount. Verified locally: PG 18.4 comes up healthy, migrations apply, and the
  78-test backend suite passes against it on Python 3.13.
- **Production:** there is no production data yet, so the first deploy on this
  baseline starts a fresh PG 18 cluster. **If/when production carries real data,
  a future major Postgres bump will require a `pg_dump`/`pg_restore` (or
  `pg_upgrade`) migration — not just an image-tag change.** That is explicitly
  out of scope here and must get its own runbook + ADR when it arrives.
- CI now provisions PG 18 / Redis 8 and runs tests on Python 3.13; a green run is
  the gate confirming the baseline works end to end.
- Dev, CI, and prod now run the same major versions, eliminating the prior
  Docker/CI-vs-venv Python skew.
