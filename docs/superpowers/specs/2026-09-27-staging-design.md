# Plan 9 — E2E and Staging Deploy — Design

**Date:** 2026-09-27
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B0, milestone 9 (the last) of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:**
- v1 spec §7 (the end-to-end journey) and §9, milestone 9;
- Plan 2 (the Caddy edge, per-academy routing, on-demand TLS);
- `infra/`: `docker-compose.production.yml`, `scripts/ship.sh` (the blue/green deploy), and `caddy/`;
- Plans 3–8 (every flow the journey walks).

## 1. Goal

Every change merged to `master` is built into images and, once a staging server exists, deployed to it automatically, with a check that it works. Until then, the same deploy is proven on every run against a simulated server.

One end-to-end test walks the whole v1 journey, from Etqan creating an academy to a parent reading a notification. It runs both in CI and against the deployed stack.

## 2. Decisions

| # | Decision |
|---|---|
| S9-1 | **No server or domain yet (owner).** The pipeline is built and proven now against a simulated server. Going live on a real server is configuration only (secrets, DNS, `.env.production`). |
| S9-2 | **Build, push and auto-deploy (owner).** Every green `master` builds and pushes the images, then deploys to staging when the staging secrets exist, and skips cleanly otherwise. There is no manual gate. A manual run (`workflow_dispatch` with a SHA) is kept for rollback. |
| S9-3 | **One tag for all images.** `backend`, `dashboard` and `marketing` are tagged with the meta commit's SHA (also `:master`). `ship.sh <sha>` deploys them together, as it already expects. |
| S9-4 | **The deploy is `ship.sh`, unchanged in spirit.** Blue/green: migrate and `bootstrap_platform` with the new image, start the new colour, health-check it, drain the old one. CI only copies `infra/`, logs the server in to the registry, runs `ship.sh` over SSH, then smoke-checks. |
| S9-5 | **Staging is production-shaped.** It runs the same compose file and images. A small overlay (`docker-compose.staging.yml`) swaps only what staging can't have yet: Caddy's internal CA instead of Cloudflare DNS-01, MinIO instead of S3, and Mailpit instead of SES. Production config is unchanged by default. |
| S9-6 | Out of scope: a real server or domain, the production deploy, monitoring alerts, backups and restore drills, Cloudflare automation, and load tests. |

## 3. The pipeline (meta `.github/workflows/`)

### 3.1 Images

A new job, `images`, runs after the existing test jobs pass:
- **What it builds:** `backend/Dockerfile`, `dashboard/Dockerfile` and `marketing/Dockerfile`, from the pinned submodules.
- **On pull requests:** it builds without pushing, so a broken Dockerfile fails the PR.
- **On a push to `master`:** it pushes `ghcr.io/etqan-agency/<name>:<meta-sha>` and `:master` to GHCR, which is private, using `GITHUB_TOKEN` with `packages: write`.
- **Caching:** build cache through GitHub Actions cache.

The Caddy edge image stays built on the server from `infra/caddy`, as today.

### 3.2 Deploy to staging

A new job, `deploy-staging`:
- **Runs:** after `images`, on `master` pushes and manual runs, in the GitHub `staging` environment.
- **Serialised:** `concurrency: staging`, and a queued deploy is never cancelled.
- **Skips** with a clear message when the `STAGING_SSH_HOST` secret is absent. The job then succeeds, so `master` stays green without a server.

Its steps:
1. Write the SSH key and `known_hosts` from secrets.
2. `rsync` `infra/` to `/opt/etqan/` on the server. The server's `.env.production` is never overwritten or read by CI.
3. Log the server in to GHCR with `GHCR_READ_TOKEN` (read-only).
4. Run `bash /opt/etqan/scripts/ship.sh <sha>`.
5. Run the smoke check (§4.3) against `STAGING_BASE_URL`.

A failed step fails the job. `ship.sh` only drains the old colour after the new one is healthy, so a failed deploy leaves the old colour serving. A failed smoke check after the switch is reported; recover by rolling back with a manual run of the previous SHA.

**Secrets (the `staging` environment):**
- `STAGING_SSH_HOST`, `STAGING_SSH_USER`, `STAGING_SSH_KEY`, `STAGING_KNOWN_HOSTS`;
- `GHCR_READ_TOKEN`;
- `STAGING_BASE_URL`, e.g. `https://demo.staging.<domain>`.

## 4. Staging configuration (`infra/`)

### 4.1 TLS mode

The Caddyfile gains a `TLS_MODE` env:
- `cloudflare` (the default): today's wildcard certificate through DNS-01, plus on-demand TLS for custom domains, with no change.
- `internal`: Caddy's internal CA for every host, for the simulated server and any staging without Cloudflare.

CI validates the Caddyfile in both modes.

### 4.2 Overlay (`docker-compose.staging.yml`) and env template

The overlay adds:
- **MinIO**, the S3 store. On start it creates the bucket and makes media public-read. It is configured through the existing `DJANGO_S3_*` and `AWS_*` settings.
- **Mailpit**, the SMTP server, through the existing `DJANGO_EMAIL_*` settings. Staging mail never reaches real people.

`ship.sh` passes `-f docker-compose.staging.yml` when `/opt/etqan/.env.production` sets `ETQAN_OVERLAY=staging`, or through an equivalent single switch. With no overlay it behaves exactly as today.

`.env.staging.example` documents a complete staging env.

### 4.3 Smoke check (`infra/scripts/smoke.sh <base-url>`)

It passes only when all of these hold:
- `GET /health/ready/` is 200;
- the base domain's admin login page is 200;
- `/app/` serves the dashboard shell;
- the academy's marketing home page is 200;
- `/internal/tls-allowed` is 404 from outside.

It has a short retry for TLS warm-up.

## 5. The simulated server (`infra/staging-sim/`)

**What it is:** a container that plays the staging server. It runs `sshd` and a Docker-in-Docker daemon, with `/opt/etqan/` laid out as a real server would have it.

**The registry:** a local `registry:2` stands in for GHCR; the images are built and pushed there.

**The run** (`just staging-sim` locally, and the `staging-sim` CI job):
1. Build the images and push them to the local registry.
2. Start the simulated server and give it a staging `.env.production`: `TLS_MODE=internal`, the staging overlay, and hosts under a test base domain resolved to it.
3. Deploy SHA A through SSH, with the same script steps as `deploy-staging`, then run the smoke check.
4. Seed the demo academy (§6.2).
5. Deploy SHA B (a re-tag) while a loop polls `/health/ready/`. Every poll must succeed, and `.active-color` must flip.
6. Run the full-journey spec (§6.1) against the deployed stack, trusting Caddy's internal CA and reading mail from Mailpit.
7. Tear everything down.

**When the CI job runs:** on pull requests that touch `infra/`, the workflows or the Dockerfiles, and on every `master` push.

## 6. End to end

### 6.1 The full journey (`dashboard/e2e/journey.spec.ts`)

One spec covers v1 §7:
1. Etqan creates an academy with the `create_academy` command, called the way `manage.ts` calls commands.
2. Its admin accepts the invite.
3. The admin creates a course, a package, a teacher and a student with a parent.
4. The admin sets up a subscription with two slots and generates sessions.
5. The teacher accepts their invite, marks the student absent on a started session and writes a report.
6. The admin records a payment on the subscription's invoice.
7. The admin sets the teacher's rate, then generates and issues **last month's** payslip. To make this possible, the subscription in step 4 starts in the previous month (on its 15th, which is never a month or midnight boundary), so a completed session exists in a month that has already ended. Plan 7's e2e uses the same arrangement.
8. The scan runs, and the parent sees the absence notification.

It runs in the existing CI `e2e` job with the other specs, and against the simulated staging server.

The other specs are not rewritten. The e2e helpers gain env switches so the same suite can target another base URL and read mail from Mailpit or from files:
- `E2E_BASE_URL`;
- the mail source;
- how commands are run (locally, or through SSH / `docker exec` on the simulated server).

### 6.2 Staging data (`seed_staging`)

Running `seed_staging` after a deploy:
- creates the `demo` academy with the dev seed data, only if it doesn't exist;
- is idempotent;
- never touches another academy.

It runs on the simulated server. On a real staging server it runs only when asked, through a workflow input.

## 7. Documentation

- **`infra/STAGING.md`**: going live on a real server. It covers:
  - server requirements (Docker, disk, the `/opt/etqan` layout);
  - DNS (`*.staging.<domain>` and the base domain);
  - the secrets to add;
  - `.env.production` for staging;
  - the first deploy;
  - rollback;
  - switching to Cloudflare TLS, real S3 and real email.
- **`STATE.md`**: updated.

## 8. Testing

- **`images`:** the builds pass on every PR.
- **`staging-sim`:**
  - two blue/green deploys, where every health poll during the switch succeeds;
  - the smoke check passes;
  - the full journey passes against the deployed stack.
- **Caddyfile:** validated in both TLS modes.
- **`ship.sh` and `smoke.sh`:** `shellcheck` clean, a check added to CI.
- **`deploy-staging`:** skips cleanly without secrets. A CI run on `master` must show it skipped and green.
- **Coverage:** the backend and dashboard gates are unchanged. `seed_staging` has tests, including an idempotency test and a test that it never touches another academy.

## 9. Risks

| Risk | Mitigation |
|---|---|
| The simulated server passes but a real server differs | The same `ship.sh`, compose and images; the differences are confined to the overlay and `TLS_MODE`; `STAGING.md` lists the real-server checks |
| An auto-deploy breaks staging | The new colour must pass health before the old one drains; the smoke check runs after; rollback is a manual run of an earlier SHA |
| Secrets leak through logs | SSH key and tokens only through GitHub secrets; `set +x` around them; `.env.production` never leaves the server |
| CI time grows | Image build cache; `staging-sim` only on infra-touching PRs and on `master` |
| Docker-in-Docker flakiness in CI | A privileged service container with a pinned image; one retry of the whole simulated run, never of individual steps |

## 10. Out of scope

- a real server or domain;
- the production deploy and its workflow;
- monitoring alerts;
- backups and restore drills;
- Cloudflare DNS automation;
- load or performance testing;
- the per-academy scanner fan-out (a STATE.md follow-up).
