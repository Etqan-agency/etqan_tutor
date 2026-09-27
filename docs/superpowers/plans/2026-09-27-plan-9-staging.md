# Plan 9 — E2E and Staging Deploy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every green `master` is built into images, pushed to GHCR and, once a staging server exists, deployed to it blue/green and smoke-checked; until then the same deploy is proven on every run against a simulated server, and one end-to-end test walks the whole v1 journey both in CI and against the deployed stack.

**Architecture:** The edge learns one switch, `TLS_MODE` (`cloudflare`, the default, is today's config byte for byte; `internal` is Caddy's own CA), and `ship.sh` learns one more, `ETQAN_OVERLAY=staging` in the server's `.env.production`, which adds `docker-compose.staging.yml` (an S3-compatible store and Mailpit). A runner-side script, `scripts/deploy-staging.sh`, does the whole deploy over SSH (copy `infra/`, registry login on stdin, `ship.sh`, optional `seed_staging`, then `infra/scripts/smoke.sh` from outside). The CI `deploy-staging` job and `scripts/staging-sim.sh` both call it; the simulation runs it against a privileged sshd + Docker-in-Docker container with a password-protected `registry:3`, deploys twice under a health poll, fails one deploy on purpose, and runs `dashboard/e2e/journey.spec.ts` against the result. The e2e helpers gain env switches (`E2E_BASE_URL`, `E2E_MANAGE`, the existing Mailpit source, resolver rules and TLS) so the same spec runs in the CI `e2e` job and on the simulated server.

**Tech Stack:** Bash (shellcheck 0.11), Docker Compose, Caddy 2.11.4 (cloudflare DNS module), `docker:29.8.1-dind`, `registry:3.1.2`, RustFS 1.0.0 + aws-cli 2.37.4, Mailpit 1.31.3; GitHub Actions (`actions/checkout@v7`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/build-push-action@v7`); Django 6 management commands; Playwright 1.62 (Chromium).

**Spec:** `docs/superpowers/specs/2026-09-27-staging-design.md` (Phase B0 milestone 9, the last, of `2026-09-24-parity-roadmap-design.md`). It builds on v1 spec §7 (the journey) and §9, Plan 2 (`2026-09-23-academy-sites-design.md`: the Caddy edge, per-academy routing, on-demand TLS), `infra/` (`docker-compose.production.yml`, `scripts/ship.sh`, `caddy/`) and Plans 3–8 (every flow the journey walks). Where this plan fills a gap in the spec, or departs from it, the Decisions below say so.

**Verified:** everything below was applied, in this plan's order and exactly as written, to scratch clones of meta `faff0c9` (branch `feat/staging`), `backend@c09f051`, `dashboard@46c8197`, `infra@46e10c9` and `marketing@b2c6aca`:
- **Edge:** `caddy adapt` of the new production Caddyfile with `TLS_MODE` unset and with `TLS_MODE=cloudflare` is byte-identical to today's Caddyfile's JSON (4959 bytes); `TLS_MODE=internal` validates and uses the `internal` issuer for the zone and on demand; `TLS_MODE=internl` is refused ("File to import not found: tls_internl"). The Task 1 CI step passes on the new image and fails on today's.
- **Compose:** `docker compose config` of the production file is unchanged but for the edge's `TLS_MODE: cloudflare`.
- **Scripts:** `shellcheck` 0.11.0 is clean on every script; `ship_test.sh` passes, and fails against today's `ship.sh` and against a `ship.sh` that ignores the overlay; `smoke_test.sh` passes, and fails when a check is removed or the body check is dropped; `compose_test.sh` passes, and fails on today's compose file (3 failures).
- **Backend:** `ruff check`, `ruff format --check`, `lint-imports` (16 contracts kept) and `pytest --cov=etqan`: 1268 passed, coverage 97.91%. Without the command the four new tests fail.
- **Dashboard:** `tsc`, `lint`, `test:coverage` and `build` pass (no `src/` change). The e2e suite, run the way the CI `e2e` job runs it (Django `config.settings.local`, file email backend, eager Celery, `vite preview`, marketing on `:4321`, `caddy:2.11.4-alpine`), passed 18 of 18 with no retry, `journey.spec.ts` included (about 12 s). Before `mail.ts` learned base64 parts, the journey failed at the first admin's invite (an Arabic-only email goes out base64).
- **Staging simulation:** `scripts/staging-sim.sh all` passed end to end three times (the last, with every check below, in 6.5 minutes on warm caches; about 10 minutes cold): deploy A with the overlay, `TLS_MODE=internal`, registry login and `seed_staging`, then the smoke check (six checks); an upload written through Django's storage and read back anonymously from the S3 store; deploy B under the health poll (161 to 177 polls per run, all 200; colour green → blue); a deploy of a SHA with no images failed with the colour and health unchanged; the journey passed against the deployed stack through `E2E_MANAGE` (SSH → `docker exec`), Mailpit over an SSH tunnel and Chromium resolver rules; no generated secret appeared in the output; `.env.production` on the server is `600 deploy`.
- **Workflows:** `actionlint` 1.7.12 (with shellcheck) is clean on `ci.yml` and `deploy-staging.yml`.
- **Not run:** the workflows themselves on GitHub (the `images` push to GHCR, the `staging-sim` job on a hosted runner, and the `deploy-staging` skip), and a real server. Task 9 checks the first three on the PR and on `master`.

## Global Constraints

**Repos and branches**
- Repos: meta (trunk `master`), `backend/`, `dashboard/`, `infra/` (trunk `main` each). `marketing/` and `tokens/` are not changed.
- The branch `feat/staging` already exists in meta and is created by the controller in each submodule a task touches (`infra`, `backend`, `dashboard`). Never create it; check with `git -C <repo> branch --show-current` before the first task in that repo.
- Nothing is merged without the user's approval. Merge order: `infra`, `backend`, `dashboard`, then bump the three pointers in meta and merge meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Workflow files (`.github/workflows/*`) are pushed over SSH (`git push git@github.com:Etqan-agency/etqan_tutor.git feat/staging`): the `gh` HTTPS token cannot push workflow changes. The meta CI checks submodules out with `secrets.SUBMODULE_TOKEN` and reads `@etqan/tokens` with `secrets.TOKENS_REPO_TOKEN`; both exist.

**Commands**
- Backend (from `backend/`, virtualenv `.venv`), once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
  Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`. Tests are not under ruff's `S` rules: no `# noqa: S105/S106` in tests (RUF100 flags them).
- Dashboard (from `dashboard/`, `npx pnpm@10`): verify `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`. `tsc` and biome cover `src/` only; `e2e/` is type-checked when Playwright loads it, and `scripts/check-colors.mjs` (in `pnpm lint`) forbids colour literals in `e2e/` too.
- Shell: `shellcheck` 0.11.0 on every script (CI uses `koalaman/shellcheck:v0.11.0`). Scripts are `#!/usr/bin/env bash` with `set -euo pipefail` (the sim entrypoint is `/bin/sh`), executable (`chmod +x`), and run as `bash <script>` from CI.
- Workflows: `actionlint` (1.7.x) on every workflow file before committing it.
- Ports on a laptop: `8000` belongs to another project here; never stop containers you did not start. The simulation uses loopback ports `18443` (https), `12222` (ssh), `15000` (registry) and `18025` (Mailpit tunnel), each overridable (`SIM_*_PORT`).

**Secrets**
- No secret is ever printed: SSH keys and known hosts reach scripts as files (`umask 077`), registry tokens through stdin (`--password-stdin`), and every script that handles one starts with `set +x`.
- `.env.production` never leaves the server: CI never reads it, `rsync` excludes it, and `ship.sh` reads only its `ETQAN_OVERLAY=` line.
- Staging mail goes to Mailpit, which listens on the server's `127.0.0.1:8025` only.

**Behaviour that must not change**
- `TLS_MODE` unset (or `cloudflare`): the production Caddyfile adapts to exactly today's JSON.
- No `ETQAN_OVERLAY` line (or an empty one): `ship.sh` runs exactly today's docker commands, in today's order (`ship.production.golden`).
- `ETQAN_REGISTRY` unset: every image is `ghcr.io/etqan-agency/<name>:${DEPLOY_SHA}` as today.

**Tests**
- Every test fails without the code it covers (each task says how that was checked).
- E2E: regex labels for required fields (`*`), exact names where one name is a prefix of another, assertions scoped to a card header, row or dialog; dates from the academy's own calendar; the journey's subscription starts on the 15th of last month (never a month's edge or midnight). Invites are read through `e2e/mail.ts`.
- Seeds are idempotent and never touch another academy; business rules are never restated (the journey drives the real flows, `seed_staging` reuses `seed_dev`'s data).

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — Image tags and build inputs.** Each image is `ghcr.io/etqan-agency/<backend|dashboard|marketing>:<meta sha>` plus `:master` (S9-3). The backend needs no build arguments: its Dockerfile's last stage, `production`, is the default target, and its `collectstatic` uses build-only values baked into the Dockerfile. The two frontends read the private `@etqan/tokens` repo through the BuildKit secret `tokens_token` (`secrets.TOKENS_REPO_TOKEN`), as their Dockerfiles already expect. Each image carries `org.opencontainers.image.source=https://github.com/Etqan-agency/etqan_tutor`, so a package the first push creates is linked to the meta repo and `GITHUB_TOKEN` (`packages: write`) may push it. The org's default workflow permission is `read`, so the job asks for `packages: write` itself.
- **D2 — One registry switch in compose.** The compose file's images read `${ETQAN_REGISTRY:-ghcr.io/etqan-agency}/<name>:…`. Unset, nothing changes (`compose_test.sh`); the simulated server sets `registry:5000/etqan-agency`. Without it the simulation could not pull the images from a local registry, since compose names `ghcr.io` literally and Docker mirrors only Docker Hub.
- **D3 — `deploy-staging` is a reusable workflow, gated per step.** `.github/workflows/deploy-staging.yml` has both `workflow_call` (the CI job, on `master` pushes, `needs: [images, staging-sim]`) and `workflow_dispatch` (`sha`, `seed`: rollback and the first seeded deploy). A job-level `if:` cannot read `secrets`, so the first step reads `STAGING_SSH_HOST` into its env and outputs `configured`; every other step has `if: steps.gate.outputs.configured == 'true'`. Without the secret the job prints a notice and succeeds. `environment: staging`, `concurrency: { group: staging, cancel-in-progress: false }`. The job checks out `inputs.sha`, so a rollback copies that commit's `infra/` along with its images. `deploy-staging` also needs `staging-sim`: only a SHA the simulation has proven is deployed.
- **D4 — `TLS_MODE` selects snippets at parse time.** Caddy replaces `{$TLS_MODE:cloudflare}` before parsing, so `import tls_{$TLS_MODE:cloudflare}` names exactly one snippet: `(tls_cloudflare)` holds today's `tls { dns cloudflare … }` and `(tls_on_demand_cloudflare)` today's `tls { on_demand }`; `(tls_internal)` and `(tls_on_demand_internal)` are their internal-CA twins. Snippets, not env-selected files, so the image still bakes one Caddyfile and `caddy adapt` proves the default is byte-identical (CI diffs unset against `cloudflare`, and checks internal mode really uses the internal issuer). An unknown value names no snippet and Caddy refuses to start. Compose passes `TLS_MODE=${TLS_MODE:-cloudflare}` to the edge.
- **D5 — How `ship.sh` picks the overlay.** It reads only the last `ETQAN_OVERLAY=` line of `.env.production` (`sed -n`, quotes and whitespace stripped; never `source`: the file holds secrets). Empty or absent: no overlay. `staging`: every compose call gets `-f docker-compose.staging.yml` after the production file. Anything else: exit 1 before any docker call. All compose calls go through one `compose()` function; `ETQAN_DIR` (default `/opt/etqan`) exists only so the tests can run it in a temp directory. `ship_test.sh` runs it twice against a fake `docker` and compares the command log with `ship.production.golden`, recorded from today's `ship.sh`.
- **D6 — The S3 store is RustFS, not MinIO (spec S9-5).** `minio/minio` and `minio/mc` are no longer pullable (Docker Hub: "repository does not exist"; `quay.io/minio/minio`: unauthorized). RustFS 1.0.0 is an S3-compatible replacement; the service is named `s3`, so a later swap renames nothing. `s3-init` (aws-cli) creates the bucket if missing and applies the same public-read policy on `tenants/*` that `.env.production.example` asks of a real bucket. Django reaches it through the existing `DJANGO_S3_*` and `AWS_*` settings. Uploaded images are linked at `http://s3:9000/…`, so browsers cannot load them on staging (`STAGING.md` §7: real S3 fixes it); writes and anonymous reads are proven by the simulation.
- **D7 — Mailpit stays private.** It publishes `127.0.0.1:8025` on the server only; the journey (and a tester) reads it over `ssh -L`. `mail.ts` already reads Mailpit's API when `E2E_MAIL_DIR` is unset.
- **D8 — Hostnames without DNS.** The test base domain is `staging.test` (`demo.staging.test`, `journey-<stamp>.staging.test`). The runner reaches the server's 443 on `127.0.0.1:$SIM_HTTPS_PORT` with `curl --connect-to ::127.0.0.1:<port>` and Chromium's `--host-resolver-rules="MAP *.staging.test 127.0.0.1:<port>, MAP staging.test 127.0.0.1:<port>"`, so the Host header, SNI and emailed links carry the real names and no `/etc/hosts` edit (which cannot hold a wildcard) or sudo is needed. `nip.io`-style hosts were rejected: they need public DNS and put the port in every link.
- **D9 — Trusting the internal CA.** The smoke check trusts the edge's root (`scripts/edge-ca.sh` prints it only when the edge runs `TLS_MODE=internal`) through `curl --cacert`, so every certificate is really verified against the right names. Playwright sets `ignoreHTTPSErrors` only when `E2E_IGNORE_HTTPS_ERRORS=1` (the simulation): Chromium ignores `NODE_EXTRA_CA_CERTS`, trusting a CA there needs an NSS database per runner, and the chain was already verified by the smoke check a minute earlier.
- **D10 — The e2e helpers' switches.** `E2E_BASE_URL` (default `http://etqan.localhost`) plus `academyUrl(sub)` in `fixtures.ts`; `DEMO_URL`/`OTHER_URL` default to it. The mail source is unchanged: files when `E2E_MAIL_DIR` is set, else Mailpit at `E2E_MAILPIT_URL`; `mail.ts` now also decodes base64 parts (an Arabic-only email). `E2E_MANAGE` is a command line (`ssh … deploy@host bash /opt/etqan/scripts/manage.sh`); `manage()` then appends each argument single-quoted for the remote shell. `acceptInvite` signs in on the invite's own origin, and `INVITE` accepts `https`. `E2E_HOST_RESOLVER_RULES` and `E2E_IGNORE_HTTPS_ERRORS` reach Chromium through `playwright.config.ts`.
- **D11 — The `staging-sim` CI job.** A `docker run --privileged` of `infra/staging-sim` (a service container cannot be built from the repo, and the image must carry sshd). It runs on every `master` push and on pull requests for which `scripts/staging-sim-needed.sh` says `true`: the meta diff touches the `infra` pointer, `.github/workflows/`, `caddy/` or the deploy/sim scripts, or a `backend`/`dashboard`/`marketing` pointer move changes that repo's `Dockerfile`, `.dockerignore`, `nginx.conf` or `requirements/` (the spec's "Dockerfiles" live inside the submodules). It needs `images` so the GHA layer cache is warm, frees runner disk first (`ship.sh` wants 5 GB free), has `timeout-minutes: 45`, and retries the whole `run` once (`down`, `up`, `run`), never a step.
- **D12 — `seed_staging`.** A tenants management command beside `seed_dev`, reusing its data through a new `seed_dev.seed_academy(academy, subdomain, name)` (the per-academy half of `seed_dev`, extracted unchanged). Staging runs production settings (no `DEBUG`), so the guard is its own setting: `STAGING_DEMO_PASSWORD` (`DJANGO_STAGING_DEMO_PASSWORD`, empty by default); without it the command refuses. It creates the `demo` academy only if missing, with that password for `admin@demo.test`, then seeds it; an existing `demo` is left exactly as it is (testers' data is never re-seeded); no other academy is read or written. It runs through `scripts/manage.sh` when `SEED=1`: on the simulated server always, on a real one only from a manual run with `seed` checked.
- **D13 — Order of a deploy.** `deploy-staging.sh`: rsync → registry login → `ship.sh` → seed (if asked) → smoke. The smoke check needs the demo academy, so a real server's first deploy is the manual run with `seed` (`STAGING.md` §5); the simulation seeds deploy A.
- **D14 — Copying `infra/`.** `rsync -rlt` without `--delete` (files only the server has are kept), excluding `.git`, `/.env.production` and `/.active-color`. The registry user is `github.repository_owner`; GHCR checks the token.
- **D15 — Spec §3.2 "a queued deploy is never cancelled".** `cancel-in-progress: false` never cancels a running deploy, but GitHub keeps only the newest pending run per concurrency group. For automatic deploys that is harmless (the newer one deploys a newer `master`); `STAGING.md` §6 says to start a rollback when no deploy is waiting.
- **D16 — `infra/STAGING.md`.** Server requirements and the `/opt/etqan` layout; DNS; the six secrets (with `STAGING_SSH_HOST` last, as the on switch, and repository secrets as the fallback if the plan has no environments for private repos); GHCR package access; `.env.production` from `.env.staging.example`; the first (seeded, manual) deploy; trusting the internal CA; rollback; moving to Cloudflare TLS, real S3 and real email; and what the simulation cannot prove.

## Review Focus

- **A deploy that fails midway.** A deploy whose images are missing, whose migrations fail or whose new colour is unhealthy must leave the old colour serving and `.active-color` unchanged; an unknown overlay must stop before touching anything. Tests:
  - Task 7: `staging-sim.sh run` deploys `0000…0000` (no images) after deploy B and asserts the failure, the unchanged colour and `/health/ready/` 200;
  - Task 2: `ship_test.sh` "an unknown overlay stops before any docker call".
- **Secret leakage.** No SSH key, registry token or server secret may appear in any log, and `.env.production` must never leave the server. Tests:
  - Task 7: `staging-sim.sh run` ends with `no_secret_in`, which fails when the registry password or any of the server's generated secrets appears in the run's output (deploy logs and Playwright included);
  - Task 7: `deploy-staging.sh` rejects anything but a 40-hex SHA before it reaches a remote command line (checked by hand in Step 5).
- **The production Caddyfile drifting.** With `TLS_MODE` unset the edge must behave exactly as today; a typo must not silently fall back. Tests:
  - Task 1: the CI step diffs `caddy adapt` unset against `cloudflare`, requires the internal issuer in internal mode, and requires `TLS_MODE=internl` to be refused (the step fails on today's image);
  - Task 4: `compose_test.sh` requires the edge's default `TLS_MODE: cloudflare` and GHCR images unless `ETQAN_REGISTRY` is set.
- **`deploy-staging` without secrets.** Before a server exists every `master` push must stay green and deploy nothing. Tests:
  - Task 8: `actionlint`, and every step after `gate` carries `if: steps.gate.outputs.configured == 'true'`;
  - Task 9: the first `master` run is checked with `gh run view`: `deploy-staging / deploy-staging` succeeded, with the notice "Staging not configured" and its other steps skipped.
- **The simulated server passing while a real one would fail.** The simulation must run the real `ship.sh`, compose files, env template and images, so only the overlay, `TLS_MODE` and the registry differ. Tests:
  - Task 7: the server's `.env.production` is generated from `.env.staging.example`, and a placeholder the script does not fill fails the run;
  - Task 7: the registry login is exercised against a password-protected registry;
  - Task 9: `STAGING.md` §8 lists what only a real server shows (DNS, ports, DNS-01, GHCR, capacity), checked on the first real deploy.

---

## File Structure

```
meta/
  .github/workflows/ci.yml             caddy: both TLS modes; infra-scripts; images; sim-needed;
                                       staging-sim; deploy-staging (calls the reusable workflow)
  .github/workflows/deploy-staging.yml NEW: workflow_call + workflow_dispatch; the gated deploy
  scripts/deploy-staging.sh            NEW: rsync, registry login, ship.sh, seed, smoke
  scripts/staging-sim.sh               NEW: up | build | run | down | all
  scripts/staging-sim-needed.sh        NEW: does a PR need the simulation?
  justfile                             staging-sim recipe; deploy points at STAGING.md
  STATE.md                             Plan 9 state; submodule pointers
infra/
  caddy/Caddyfile                      TLS_MODE snippets (cloudflare default, internal)
  docker-compose.production.yml        ETQAN_REGISTRY; TLS_MODE to the edge
  docker-compose.staging.yml           NEW: s3 (RustFS), s3-init, mailpit, depends_on
  .env.staging.example                 NEW: a complete staging env
  scripts/ship.sh                      the ETQAN_OVERLAY switch; compose(); ETQAN_DIR
  scripts/smoke.sh                     NEW: the smoke check
  scripts/manage.sh                    NEW: manage.py in the live colour
  scripts/edge-ca.sh                   NEW: the internal CA root, or nothing
  scripts/tests/ship_test.sh ship.production.golden smoke_test.sh compose_test.sh   NEW
  scripts/tests/fakebin/{docker,df,sleep,curl}                                     NEW
  staging-sim/Dockerfile entrypoint.sh NEW: the simulated server
  STAGING.md                           NEW: going live on a real server
  CLAUDE.md                            structure and staging lines
backend/
  config/settings/base.py              STAGING_DEMO_PASSWORD
  etqan/tenants/management/commands/seed_dev.py      seed_academy() extracted
  etqan/tenants/management/commands/seed_staging.py  NEW
  etqan/tenants/tests/test_seed_staging.py           NEW
dashboard/
  playwright.config.ts                 resolver rules, ignoreHTTPSErrors (env)
  e2e/fixtures.ts                      BASE_URL, academyUrl, https invites, login at the invite's origin
  e2e/manage.ts                        E2E_MANAGE (remote), shellQuote
  e2e/mail.ts                          base64 parts
  e2e/journey.spec.ts                  NEW: the whole v1 journey
```

---

### Task 1: The edge's `TLS_MODE`, and CI validating both modes

**Files:**
- Modify: `infra/caddy/Caddyfile` (header comment; four snippets before `(etqan_hsts)`; the three `tls` blocks)
- Modify: `.github/workflows/ci.yml` (meta; the `caddy` job's production step)
- Test: the `caddy` job's step, run locally

**Interfaces:**
- Consumes: nothing.
- Produces: the env `TLS_MODE` read by the edge image (`cloudflare` default, or `internal`); snippets `tls_cloudflare`, `tls_on_demand_cloudflare`, `tls_internal`, `tls_on_demand_internal`. Task 4 passes `TLS_MODE` through compose; Task 7's `edge-ca.sh` reads it from the running edge.

- [ ] **Step 1: Write the failing check (the new CI step)**

In `.github/workflows/ci.yml` (meta), replace:

```yaml
      # The production image bakes in infra/caddy/Caddyfile and the cloudflare DNS
      # module. The token only has to be well-formed (40 chars) to provision.
      - name: Validate the production Caddyfile (infra)
        run: |
          docker build -t etqan-edge infra/caddy
          docker run --rm -e BASE_DOMAIN=example.com -e ACME_EMAIL=ci@example.com \
            -e CF_API_TOKEN=0000000000000000000000000000000000000000 etqan-edge \
            caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

with:

```yaml
      # The production image bakes in infra/caddy/Caddyfile and the cloudflare DNS
      # module. The token only has to be well-formed (40 chars) to provision.
      # TLS_MODE unset is production (cloudflare); internal is staging's.
      - name: Validate the production Caddyfile (infra) in both TLS modes
        run: |
          docker build -t etqan-edge infra/caddy
          edge() {
            docker run --rm -e BASE_DOMAIN=example.com -e ACME_EMAIL=ci@example.com \
              -e CF_API_TOKEN=0000000000000000000000000000000000000000 "$@"
          }
          validate=(caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile)
          adapt=(caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile)
          edge etqan-edge "${validate[@]}"
          edge -e TLS_MODE=internal etqan-edge "${validate[@]}"
          edge -e TLS_MODE=internal etqan-edge "${adapt[@]}" | grep -q '"module":"internal"'
          # Unset means cloudflare: the same config, byte for byte.
          diff <(edge etqan-edge "${adapt[@]}") <(edge -e TLS_MODE=cloudflare etqan-edge "${adapt[@]}")
          # Any other value names no snippet, and the edge refuses to start.
          if edge -e TLS_MODE=internl etqan-edge "${validate[@]}"; then
            echo "TLS_MODE=internl was accepted"; exit 1
          fi
```

- [ ] **Step 2: Run it against today's Caddyfile to see it fail**

From the meta root:

```bash
cat > /tmp/edge-check.sh <<'EOF'
set -euo pipefail
docker build -q -t etqan-edge infra/caddy >/dev/null
edge() {
  docker run --rm -e BASE_DOMAIN=example.com -e ACME_EMAIL=ci@example.com \
    -e CF_API_TOKEN=0000000000000000000000000000000000000000 "$@"
}
validate=(caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile)
adapt=(caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile)
edge etqan-edge "${validate[@]}"
edge -e TLS_MODE=internal etqan-edge "${validate[@]}"
edge -e TLS_MODE=internal etqan-edge "${adapt[@]}" | grep -q '"module":"internal"'
diff <(edge etqan-edge "${adapt[@]}") <(edge -e TLS_MODE=cloudflare etqan-edge "${adapt[@]}")
if edge -e TLS_MODE=internl etqan-edge "${validate[@]}"; then echo "TLS_MODE=internl was accepted"; exit 1; fi
echo EDGE-OK
EOF
docker run --rm -e BASE_DOMAIN=example.com -e ACME_EMAIL=ci@example.com \
  -e CF_API_TOKEN=0000000000000000000000000000000000000000 \
  "$(docker build -q infra/caddy)" caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile > /tmp/adapt.before.json
bash /tmp/edge-check.sh
```

Expected: FAIL at the `grep -q '"module":"internal"'` line (today's file ignores `TLS_MODE`). `/tmp/adapt.before.json` keeps today's config for Step 4.

- [ ] **Step 3: Implement the snippets**

In `infra/caddy/Caddyfile`, replace:

```
# /internal/tls-allowed (200 only for an active academy domain).
#
# Caddy is the ONLY proxy hop in front of Django (REST_FRAMEWORK NUM_PROXIES=1,
```

with:

```
# /internal/tls-allowed (200 only for an active academy domain).
#
# TLS_MODE picks the issuer at parse time: {$TLS_MODE:cloudflare} is replaced
# before the file is parsed, so it names exactly one snippet pair below.
#   cloudflare (the default, production): the certificates above, unchanged;
#   internal: Caddy's own CA for every host, for a staging server without a
#   Cloudflare zone (clients must trust its root, see infra/STAGING.md).
# Any other value names no snippet, and Caddy refuses to start.
#
# Caddy is the ONLY proxy hop in front of Django (REST_FRAMEWORK NUM_PROXIES=1,
```

Replace:

```
# HSTS with includeSubDomains only on Etqan's own zone. `>` defers the header
```

with (the file indents with tabs):

```
# The certificate snippets, one pair per TLS_MODE: the Etqan zone's
# certificate, then the on-demand one for custom domains.
(tls_cloudflare) {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
}

(tls_on_demand_cloudflare) {
	tls {
		on_demand
	}
}

(tls_internal) {
	tls internal
}

(tls_on_demand_internal) {
	tls internal {
		on_demand
	}
}

# HSTS with includeSubDomains only on Etqan's own zone. `>` defers the header
```

In both the `{$BASE_DOMAIN} {` and the `*.{$BASE_DOMAIN} {` blocks, replace:

```
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
```

with:

```
	import tls_{$TLS_MODE:cloudflare}
```

In the `https:// {` block, replace:

```
	tls {
		on_demand
	}
```

with:

```
	import tls_on_demand_{$TLS_MODE:cloudflare}
```

- [ ] **Step 4: Run the check again, and compare with today's config**

```bash
bash /tmp/edge-check.sh
docker run --rm -e BASE_DOMAIN=example.com -e ACME_EMAIL=ci@example.com \
  -e CF_API_TOKEN=0000000000000000000000000000000000000000 etqan-edge \
  caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile | cmp - /tmp/adapt.before.json && echo BYTE-IDENTICAL
actionlint .github/workflows/ci.yml
```

Expected: `EDGE-OK` (the typo run prints `Error: File to import not found: tls_internl`, which is the point), `BYTE-IDENTICAL`, and no actionlint output.

- [ ] **Step 5: Commit (infra, then meta)**

```bash
git -C infra add caddy/Caddyfile
git -C infra commit -m "feat(caddy): TLS_MODE selects Cloudflare DNS-01 or the internal CA

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git add .github/workflows/ci.yml
git commit -m "ci: validate the production Caddyfile in both TLS modes

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `ship.sh` picks the staging overlay from one line of `.env.production`

**Files:**
- Create: `infra/scripts/tests/ship_test.sh`, `infra/scripts/tests/ship.production.golden`, `infra/scripts/tests/fakebin/docker`, `infra/scripts/tests/fakebin/df`, `infra/scripts/tests/fakebin/sleep`
- Modify: `infra/scripts/ship.sh` (header and paths; the overlay block and `compose()`; every compose call)

**Interfaces:**
- Consumes: nothing.
- Produces: `ship.sh <sha>` unchanged for callers; `.env.production` line `ETQAN_OVERLAY=staging` adds `/opt/etqan/docker-compose.staging.yml` (Task 4); `ETQAN_DIR` (tests only). Task 3's CI job runs `ship_test.sh`; Task 3's fake `curl` joins `fakebin/`.

- [ ] **Step 1: Write the fakes, the golden and the test**

Create `infra/scripts/tests/fakebin/docker`:

```bash
#!/usr/bin/env bash
# A stand-in for docker: records each call, one line per call, and answers
# the only questions ship.sh asks (a healthy container, a prune summary).
# The deploy directory is logged as <DIR>, so logs compare across runs.
printf '%s\n' "$*" | sed "s|${FAKE_DIR}|<DIR>|g" >> "$FAKE_LOG"
case "$1 ${2:-}" in
    "image prune") echo "Total reclaimed space: 0B" ;;
esac
exit 0
```

Create `infra/scripts/tests/fakebin/df`:

```bash
#!/usr/bin/env bash
# A stand-in for df: plenty of room on /var/lib/docker (or FAKE_FREE_KB).
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "fake 104857600 1 ${FAKE_FREE_KB:-104857599} 1% /var/lib/docker"
```

Create `infra/scripts/tests/fakebin/sleep`:

```bash
#!/usr/bin/env bash
# A stand-in for sleep: the deploy's waits cost nothing under test.
exit 0
```

Create `infra/scripts/tests/ship.production.golden` (what today's `ship.sh` runs for a first deploy and then a second; recorded from `infra@46e10c9`):

```
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production pull
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production up -d --build caddy postgres redis flower
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production run --rm django-green python manage.py migrate --noinput
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production run --rm django-green python manage.py bootstrap_platform
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production --profile green up -d
exec etqan-django-green-1 curl -sf http://localhost:8000/health/ready/
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production up -d dashboard marketing
image prune -a -f --filter until=24h
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production pull
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production up -d --build caddy postgres redis flower
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production run --rm django-blue python manage.py migrate --noinput
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production run --rm django-blue python manage.py bootstrap_platform
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production --profile blue up -d
exec etqan-django-blue-1 curl -sf http://localhost:8000/health/ready/
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production stop --timeout 30 django-green celery-worker-green celery-beat-green
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production rm -f django-green celery-worker-green celery-beat-green
compose -f <DIR>/docker-compose.production.yml --env-file <DIR>/.env.production up -d dashboard marketing
image prune -a -f --filter until=24h
```

Create `infra/scripts/tests/ship_test.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/ship.sh against a fake docker (tests/fakebin): the
# commands it would run, in order, for two deploys in a row.
#   bash scripts/tests/ship_test.sh
# ship.production.golden is what ship.sh ran before the overlay switch
# existed; with no overlay it must run exactly that.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIP="${HERE}/../ship.sh"
SHA=0123456789abcdef0123456789abcdef01234567
FAILURES=0

fail() {
    echo "FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

# deploy_twice <env-file-content> → the fake docker's log on stdout; the
# exit status of the first failing ship.sh run, or 0.
deploy_twice() {
    local dir status=0
    dir="$(mktemp -d)"
    mkdir -p "${dir}/opt"
    printf '%s\n' "$1" > "${dir}/opt/.env.production"
    : > "${dir}/log"
    for _ in 1 2; do
        if ! ETQAN_DIR="${dir}/opt" FAKE_DIR="${dir}/opt" FAKE_LOG="${dir}/log" \
            PATH="${HERE}/fakebin:${PATH}" bash "$SHIP" "$SHA" > "${dir}/out" 2>&1; then
            status=1
            break
        fi
    done
    cat "${dir}/log"
    rm -rf "$dir"
    return "$status"
}

# 1. No overlay: exactly today's commands, blue/green alternating.
for env in "POSTGRES_DB=etqan" "ETQAN_OVERLAY=" "# ETQAN_OVERLAY=staging"; do
    if ! log="$(deploy_twice "$env")"; then
        fail "no overlay ($env): ship.sh failed"
    elif [ "$log" != "$(cat "${HERE}/ship.production.golden")" ]; then
        fail "no overlay ($env): the commands differ from ship.production.golden"
        diff <(echo "$log") "${HERE}/ship.production.golden" || true
    fi
done

# 2. ETQAN_OVERLAY=staging: the same commands, each with the overlay added
# after the production file.
expected="$(sed 's|^compose -f <DIR>/docker-compose.production.yml |compose -f <DIR>/docker-compose.production.yml -f <DIR>/docker-compose.staging.yml |' \
    "${HERE}/ship.production.golden")"
for env in "ETQAN_OVERLAY=staging" 'ETQAN_OVERLAY="staging"'; do
    if ! log="$(deploy_twice "$env")"; then
        fail "overlay ($env): ship.sh failed"
    elif [ "$log" != "$expected" ]; then
        fail "overlay ($env): not every compose call carries the staging file"
        diff <(echo "$log") <(echo "$expected") || true
    fi
done

# 3. An unknown overlay stops before any docker call.
if log="$(deploy_twice "ETQAN_OVERLAY=prod")"; then
    fail "unknown overlay: ship.sh succeeded"
elif [ -n "$log" ]; then
    fail "unknown overlay: docker was called: $log"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "ship_test: ${FAILURES} failure(s)"
    exit 1
fi
echo "ship_test: all passed"
```

```bash
chmod +x infra/scripts/tests/fakebin/* infra/scripts/tests/ship_test.sh
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash infra/scripts/tests/ship_test.sh`
Expected: FAIL, six failures: today's `ship.sh` ignores `ETQAN_DIR` and writes to `/opt/etqan`, so every scenario fails.

- [ ] **Step 3: Implement the switch**

In `infra/scripts/ship.sh`, replace:

```bash
# Blue-green deploy script for etqan.
# Called by CI via SSH: ./deploy.sh <image-sha>
# Expects docker-compose.production.yml and .env.production in /opt/etqan/

DEPLOY_SHA="${1:?Usage: deploy.sh <image-sha>}"
COMPOSE_FILE="/opt/etqan/docker-compose.production.yml"
ENV_FILE="/opt/etqan/.env.production"
STATE_FILE="/opt/etqan/.active-color"
```

with:

```bash
# Blue-green deploy script for etqan.
# Called by CI via SSH: bash /opt/etqan/scripts/ship.sh <image-sha>
# Expects docker-compose.production.yml and .env.production in /opt/etqan/
# (ETQAN_DIR overrides the directory; only the tests set it).

DEPLOY_SHA="${1:?Usage: ship.sh <image-sha>}"
ETQAN_DIR="${ETQAN_DIR:-/opt/etqan}"
COMPOSE_FILE="${ETQAN_DIR}/docker-compose.production.yml"
ENV_FILE="${ETQAN_DIR}/.env.production"
STATE_FILE="${ETQAN_DIR}/.active-color"
```

Replace:

```bash
echo "=========================================="
echo "etqan deploy — sha: ${DEPLOY_SHA}"
echo "=========================================="
```

with:

```bash
echo "=========================================="
echo "etqan deploy — sha: ${DEPLOY_SHA}"
echo "=========================================="

# ─── Overlay: one switch in .env.production ──────────────────
# ETQAN_OVERLAY=staging adds docker-compose.staging.yml (an S3 store and
# Mailpit in place of S3 and SES). Unset or empty: production, the same
# commands as before the switch existed. Only that one line is read, never
# the whole file: it holds secrets. An unknown value stops here, before
# anything changes.
OVERLAY=""
if [ -f "$ENV_FILE" ]; then
    OVERLAY=$(sed -n 's/^ETQAN_OVERLAY=//p' "$ENV_FILE" | tail -n 1 | tr -d "\"' \t\r")
fi
COMPOSE_FILES=(-f "$COMPOSE_FILE")
case "$OVERLAY" in
    "") ;;
    staging) COMPOSE_FILES+=(-f "${ETQAN_DIR}/docker-compose.staging.yml") ;;
    *)
        echo "ERROR: unknown ETQAN_OVERLAY '${OVERLAY}' in ${ENV_FILE}; the only overlay is 'staging'."
        exit 1
        ;;
esac
echo "Overlay: ${OVERLAY:-none}"

# Every compose call goes through here, with the same files and env file.
compose() {
    docker compose "${COMPOSE_FILES[@]}" --env-file "$ENV_FILE" "$@"
}
```

Then route every compose call through `compose()` (ten calls; the command changes none of their arguments):

```bash
sed -i 's|docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE"|compose|' infra/scripts/ship.sh
grep -c 'docker compose -f' infra/scripts/ship.sh   # expect 0
grep -c '^\s*\(if ! \)\?compose ' infra/scripts/ship.sh   # expect 10
```

- [ ] **Step 4: Run the tests and shellcheck**

```bash
bash infra/scripts/tests/ship_test.sh
shellcheck infra/scripts/ship.sh infra/scripts/tests/ship_test.sh infra/scripts/tests/fakebin/*
```

Expected: `ship_test: all passed`; no shellcheck output. (Replacing the `staging)` branch with `staging) ;;` makes the two overlay scenarios fail: the test pins the overlay, not just the paths.)

- [ ] **Step 5: Commit**

```bash
git -C infra add scripts/ship.sh scripts/tests
git -C infra commit -m "feat(ship): ETQAN_OVERLAY=staging adds the staging compose overlay

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The smoke check, and CI running the shell tests

**Files:**
- Create: `infra/scripts/smoke.sh`, `infra/scripts/tests/smoke_test.sh`, `infra/scripts/tests/fakebin/curl`
- Modify: `.github/workflows/ci.yml` (meta; new `infra-scripts` job after `caddy`)

**Interfaces:**
- Consumes: Task 2's `ship_test.sh` and `fakebin/`.
- Produces: `bash infra/scripts/smoke.sh <academy-url>` (exit 0 only when all six checks pass; env `SMOKE_CACERT`, `SMOKE_CONNECT_TO`, `SMOKE_TRIES`, `SMOKE_DELAY`), used by Task 7's `deploy-staging.sh`. The CI job `infra-scripts`, which Task 4 extends with `compose_test.sh` and Task 8 with `images`' `needs`.

- [ ] **Step 1: Write the fake curl and the test**

Create `infra/scripts/tests/fakebin/curl`:

```bash
#!/usr/bin/env bash
# A stand-in for curl, for smoke_test.sh. FAKE_ROUTES holds one line per URL:
#   <url> <status on call 1>[,<status on call 2>,...] [<body text>]
# The last status repeats. Each call and its options are appended to
# FAKE_CALLS. Prints the status, as `-w '%{http_code}'` would, and writes the
# body to the -o file. An unknown URL answers 000 (no connection).
out="" url="" opts=()
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -w | --max-time | --max-redirs) shift 2 ;;
        --cacert | --connect-to) opts+=("$1=$2"); shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
echo "${url} ${opts[*]}" >> "$FAKE_CALLS"
calls="$(grep -c "^${url} " "$FAKE_CALLS")"
line="$(awk -v u="$url" '$1 == u' "$FAKE_ROUTES")"
if [ -z "$line" ]; then
    printf '000'
    exit 7
fi
read -r _ statuses body <<< "$line"
IFS=, read -r -a list <<< "$statuses"
index=$((calls - 1))
[ "$index" -ge "${#list[@]}" ] && index=$((${#list[@]} - 1))
printf '%s' "$body" > "$out"
printf '%s' "${list[$index]}"
```

Create `infra/scripts/tests/smoke_test.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/smoke.sh against a fake curl (tests/fakebin/curl).
#   bash scripts/tests/smoke_test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE="${HERE}/../smoke.sh"
URL=https://demo.staging.example.com
BASE=https://staging.example.com
FAILURES=0

fail() {
    echo "FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

# A healthy stack, one route per line: <url> <statuses> [<body>]
healthy() {
    cat <<ROUTES
${URL}/health/ready/ 200 {"status":"ok"}
${BASE}/admin/login/ 200 <title>Log in</title>
${URL}/app/ 200 <body><div id="root"></div></body>
${URL}/ 200 <h1>Demo Academy</h1>
${URL}/internal/tls-allowed 404
${BASE}/internal/tls-allowed 404
ROUTES
}

# smoke <routes> [VAR=value ...] → smoke.sh's exit status; its output and the
# calls it made in $OUT and $CALLS.
OUT="$(mktemp)"
CALLS="$(mktemp)"
ROUTES="$(mktemp)"
trap 'rm -f "$OUT" "$CALLS" "$ROUTES"' EXIT
smoke() {
    printf '%s\n' "$1" > "$ROUTES"
    : > "$CALLS"
    shift
    env "$@" SMOKE_TRIES=3 SMOKE_DELAY=0 FAKE_ROUTES="$ROUTES" FAKE_CALLS="$CALLS" \
        PATH="${HERE}/fakebin:${PATH}" bash "$SMOKE" "$URL" > "$OUT" 2>&1
}

# 1. A healthy stack passes, checking the base domain as the academy's parent.
if ! smoke "$(healthy)"; then
    fail "a healthy stack failed:"; cat "$OUT"
fi
grep -q "^${BASE}/admin/login/ " "$CALLS" || fail "the staff admin was not checked on ${BASE}"

# 2. Each broken check fails the run, and says which.
while IFS='|' read -r broken what; do
    routes="$(healthy | awk -v u="${broken%% *}" '$1 != u'; echo "$broken")"
    if smoke "$routes"; then
        fail "passed with ${what}"
    elif ! grep -q "^FAIL" "$OUT"; then
        fail "no FAIL line for ${what}"
    fi
done <<CASES
${URL}/health/ready/ 503|the API not ready
${BASE}/admin/login/ 404|no staff admin
${URL}/app/ 200 <h1>Not the dashboard</h1>|a page that is not the dashboard shell
${URL}/ 502|no academy site
${URL}/internal/tls-allowed 200|internal reachable on the academy host
${BASE}/internal/tls-allowed 200|internal reachable on the base domain
CASES

# 3. A slow first answer (TLS warm-up) is retried.
if ! smoke "$(healthy | sed "s|^${URL}/health/ready/ 200|${URL}/health/ready/ 000,502,200|")"; then
    fail "a check that passes on its third try failed:"; cat "$OUT"
fi

# 4. SMOKE_CACERT and SMOKE_CONNECT_TO reach every call.
smoke "$(healthy)" SMOKE_CACERT=/tmp/root.crt SMOKE_CONNECT_TO=::127.0.0.1:18443 || fail "options run failed"
if [ "$(grep -c -- "--cacert=/tmp/root.crt --connect-to=::127.0.0.1:18443" "$CALLS")" -ne 6 ]; then
    fail "not every call trusted SMOKE_CACERT and used SMOKE_CONNECT_TO"; cat "$CALLS"
fi

# 5. A URL that is not <academy>.<base> is refused.
for bad in https://staging.example.com/demo https://localhost; do
    if PATH="${HERE}/fakebin:${PATH}" bash "$SMOKE" "$bad" > "$OUT" 2>&1; then
        fail "accepted ${bad}"
    fi
done

if [ "$FAILURES" -gt 0 ]; then
    echo "smoke_test: ${FAILURES} failure(s)"
    exit 1
fi
echo "smoke_test: all passed"
```

```bash
chmod +x infra/scripts/tests/fakebin/curl infra/scripts/tests/smoke_test.sh
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash infra/scripts/tests/smoke_test.sh`
Expected: FAIL: `a healthy stack failed` (bash cannot open `smoke.sh`), among others.

- [ ] **Step 3: Implement the smoke check**

Create `infra/scripts/smoke.sh`:

```bash
#!/usr/bin/env bash
# Smoke-check a deployed stack from outside, the way a visitor reaches it
# (spec §4.3). Passes only when every check passes.
#   bash scripts/smoke.sh https://demo.staging.example.com
# The argument is an academy's URL; the base domain (the staff admin) is its
# parent: demo.staging.example.com → staging.example.com.
# Optional environment:
#   SMOKE_CACERT      a PEM file to trust instead of the system's CAs
#                     (TLS_MODE=internal: the edge's root, scripts/edge-ca.sh)
#   SMOKE_CONNECT_TO  a curl --connect-to value, e.g. ::127.0.0.1:18443, to
#                     reach a server DNS does not know (the simulated one)
#   SMOKE_TRIES, SMOKE_DELAY  tries per check and seconds between them
#                     (default 10 and 3: a first certificate takes a moment)
set -euo pipefail

ACADEMY_URL="${1:?Usage: smoke.sh <academy-url>, e.g. https://demo.staging.example.com}"
ACADEMY_URL="${ACADEMY_URL%/}"
SCHEME="${ACADEMY_URL%%://*}"
ACADEMY_HOST="${ACADEMY_URL#*://}"
case "$ACADEMY_HOST" in
    */* | "") echo "ERROR: give the academy's origin, without a path: ${ACADEMY_URL}"; exit 2 ;;
    *.*.*) ;;
    *) echo "ERROR: ${ACADEMY_HOST} is not <academy>.<base-domain>"; exit 2 ;;
esac
BASE_URL="${SCHEME}://${ACADEMY_HOST#*.}"
TRIES="${SMOKE_TRIES:-10}"
DELAY="${SMOKE_DELAY:-3}"

BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT
# -L: the site's home page answers with its language (/ → /ar/); the status
# checked is the page's own.
CURL=(curl -sS -L --max-redirs 5 --max-time 10 -o "$BODY" -w '%{http_code}')
if [ -n "${SMOKE_CACERT:-}" ]; then
    CURL+=(--cacert "$SMOKE_CACERT")
fi
if [ -n "${SMOKE_CONNECT_TO:-}" ]; then
    CURL+=(--connect-to "$SMOKE_CONNECT_TO")
fi

FAILED=0
# check <what> <url> <status> [<text the body must contain>]
check() {
    local what="$1" url="$2" want="$3" needle="${4:-}" code="" _
    for _ in $(seq 1 "$TRIES"); do
        code="$("${CURL[@]}" "$url" 2>/dev/null || true)"
        if [ "$code" = "$want" ] && { [ -z "$needle" ] || grep -qF -- "$needle" "$BODY"; }; then
            echo "ok    ${what}: ${url} → ${code}"
            return 0
        fi
        sleep "$DELAY"
    done
    echo "FAIL  ${what}: ${url} → ${code:-no answer}, expected ${want}${needle:+ with \"${needle}\"}"
    FAILED=1
}

check "API ready" "${ACADEMY_URL}/health/ready/" 200
check "staff admin" "${BASE_URL}/admin/login/" 200
check "dashboard shell" "${ACADEMY_URL}/app/" 200 '<div id="root"></div>'
check "academy site" "${ACADEMY_URL}/" 200
check "internal hidden (academy)" "${ACADEMY_URL}/internal/tls-allowed" 404
check "internal hidden (base)" "${BASE_URL}/internal/tls-allowed" 404

if [ "$FAILED" -ne 0 ]; then
    echo "Smoke check FAILED"
    exit 1
fi
echo "Smoke check passed"
```

```bash
chmod +x infra/scripts/smoke.sh
```

- [ ] **Step 4: Run the tests, shellcheck, and add the CI job**

```bash
bash infra/scripts/tests/smoke_test.sh
shellcheck infra/scripts/smoke.sh infra/scripts/tests/smoke_test.sh infra/scripts/tests/fakebin/curl
```

Expected: `smoke_test: all passed`; no shellcheck output. (Deleting the base-domain internal check, or the body check, makes it fail.)

In `.github/workflows/ci.yml` (meta), after the `caddy` job's last step (the `if edge -e TLS_MODE=internl …` block from Task 1) and before `  e2e:`, add:

```yaml

  infra-scripts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with: { submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - name: shellcheck the deploy, smoke, simulation and helper scripts
        run: |
          docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.11.0 \
            infra/scripts/*.sh infra/scripts/tests/*.sh infra/scripts/tests/fakebin/*
      - name: ship.sh and smoke.sh tests
        run: |
          bash infra/scripts/tests/ship_test.sh
          bash infra/scripts/tests/smoke_test.sh
```

Run: `actionlint .github/workflows/ci.yml` — expected: no output.

- [ ] **Step 5: Commit (infra, then meta)**

```bash
git -C infra add scripts/smoke.sh scripts/tests
git -C infra commit -m "feat(scripts): smoke-check a deployed stack from outside

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git add .github/workflows/ci.yml
git commit -m "ci: shellcheck and test the infra scripts

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The staging overlay, the registry switch, the env template and the server helpers

**Files:**
- Create: `infra/docker-compose.staging.yml`, `infra/.env.staging.example`, `infra/scripts/manage.sh`, `infra/scripts/edge-ca.sh`, `infra/scripts/tests/compose_test.sh`
- Modify: `infra/docker-compose.production.yml` (a header comment, the edge's `TLS_MODE`, nine `image:` lines), `.github/workflows/ci.yml` (meta; the `infra-scripts` test step)

**Interfaces:**
- Consumes: Task 1's `TLS_MODE`; Task 2's overlay switch.
- Produces: compose env `ETQAN_REGISTRY` (default `ghcr.io/etqan-agency`); overlay services `s3` (container `etqan-s3-1`), `s3-init`, `mailpit` (server `127.0.0.1:8025`); `bash /opt/etqan/scripts/manage.sh <command> [args…]` (runs `python manage.py` in `etqan-django-<live colour>-1`); `bash /opt/etqan/scripts/edge-ca.sh` (the internal root PEM, or nothing). Placeholders in `.env.staging.example`: `CHANGE_ME_SECRET_KEY`, `CHANGE_ME_DB_PASSWORD` (twice), `CHANGE_ME_S3_SECRET`, `CHANGE_ME_DEMO_PASSWORD`; the S3 bucket `etqan-staging-media`. Task 7 fills them and calls both helpers.

- [ ] **Step 1: Write the failing test**

Create `infra/scripts/tests/compose_test.sh`:

```bash
#!/usr/bin/env bash
# Tests for the compose files' shape (needs docker compose, no daemon work):
# production pulls from GHCR unless ETQAN_REGISTRY says otherwise, the edge
# defaults to TLS_MODE=cloudflare, and the staging overlay only adds the S3
# store, its init job and Mailpit.
#   bash scripts/tests/compose_test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="${HERE}/../.."
FAILURES=0

fail() {
    echo "FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "${INFRA}/docker-compose.production.yml" "${INFRA}/docker-compose.staging.yml" "$WORK/"
cat > "${WORK}/base.env" <<ENV
BASE_DOMAIN=example.com
ACME_EMAIL=ci@example.com
CF_API_TOKEN=token
DEPLOY_SHA=0123456789abcdef0123456789abcdef01234567
AWS_ACCESS_KEY_ID=key
AWS_SECRET_ACCESS_KEY=secret
DJANGO_S3_BUCKET=bucket
ENV
: > "${WORK}/.env.production"

# config <env-file> [compose files...] → the resolved config, one YAML
config() {
    local env="$1"
    shift
    (cd "$WORK" && docker compose --env-file "$env" "$@" --profile blue --profile green config)
}
images() {
    grep -E '^\s+image:' | sed -E 's/^\s+image: //' | sort -u
}
services() {
    (cd "$WORK" && docker compose --env-file "$1" "${@:2}" --profile blue --profile green config --services) | sort
}

# 1. Production: every app image from ghcr.io/etqan-agency at DEPLOY_SHA.
prod="$(config base.env -f docker-compose.production.yml)"
if [ "$(images <<< "$prod" | grep -c '^ghcr.io/etqan-agency/.*:0123456789abcdef0123456789abcdef01234567$')" -ne 3 ]; then
    fail "production images are not the three GHCR images at DEPLOY_SHA:"
    images <<< "$prod"
fi
grep -q 'TLS_MODE: cloudflare' <<< "$prod" || fail "the edge does not default to TLS_MODE=cloudflare"

# 2. ETQAN_REGISTRY moves all three, and nothing else.
{ cat "${WORK}/base.env"; echo "ETQAN_REGISTRY=registry:5000/etqan-agency"; } > "${WORK}/registry.env"
moved="$(config registry.env -f docker-compose.production.yml)"
if images <<< "$moved" | grep -q 'ghcr.io'; then
    fail "an image still comes from GHCR with ETQAN_REGISTRY set"
fi
if [ "$(images <<< "$moved" | grep -c '^registry:5000/etqan-agency/')" -ne 3 ]; then
    fail "ETQAN_REGISTRY did not move the three app images"
fi

# 3. The overlay adds exactly s3, s3-init and mailpit.
added="$(comm -13 <(services base.env -f docker-compose.production.yml) \
    <(services base.env -f docker-compose.production.yml -f docker-compose.staging.yml) | tr '\n' ' ')"
[ "$added" = "mailpit s3 s3-init " ] || fail "the overlay adds '${added}', expected 'mailpit s3 s3-init '"

if [ "$FAILURES" -gt 0 ]; then
    echo "compose_test: ${FAILURES} failure(s)"
    exit 1
fi
echo "compose_test: all passed"
```

Create `infra/docker-compose.staging.yml` first (the test reads it; Step 3 explains it):

```yaml
# Staging overlay (spec §4.2). scripts/ship.sh adds it after
# docker-compose.production.yml when .env.production sets
# ETQAN_OVERLAY=staging; production never reads it. Same images, same
# services; it only swaps what a staging server cannot have yet:
#   s3       an S3-compatible store (RustFS) for S3; the uploads bucket is
#            created and made public-read under tenants/ by s3-init
#   mailpit  an SMTP server that keeps every email (web UI and API on the
#            server's 127.0.0.1:8025 only) for SES: staging mail never
#            reaches anyone
# The TLS issuer is TLS_MODE (caddy/Caddyfile). Django reaches both through
# the existing DJANGO_S3_*, AWS_* and DJANGO_EMAIL_* settings
# (.env.staging.example).
services:
  s3:
    image: rustfs/rustfs:1.0.0
    restart: unless-stopped
    environment:
      - RUSTFS_ACCESS_KEY=${AWS_ACCESS_KEY_ID:?}
      - RUSTFS_SECRET_KEY=${AWS_SECRET_ACCESS_KEY:?}
    volumes:
      - s3_data:/data
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://127.0.0.1:9000/health"]
      interval: 5s
      timeout: 3s
      retries: 20

  # One-shot: the bucket, and anonymous reads of tenants/* only (the same
  # rule .env.production.example asks of a real bucket). Idempotent.
  s3-init:
    image: amazon/aws-cli:2.37.4
    depends_on:
      s3:
        condition: service_healthy
    environment:
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:?}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:?}
      - AWS_DEFAULT_REGION=${DJANGO_S3_REGION:-us-east-1}
      - BUCKET=${DJANGO_S3_BUCKET:?}
    entrypoint: ["/bin/sh", "-euc"]
    command:
      - |
        s3() { aws --endpoint-url http://s3:9000 "$$@"; }
        s3 s3api head-bucket --bucket "$$BUCKET" 2>/dev/null \
          || s3 s3api create-bucket --bucket "$$BUCKET" >/dev/null
        s3 s3api put-bucket-policy --bucket "$$BUCKET" --policy \
          "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicReadUploads\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$$BUCKET/tenants/*\"}]}"
        echo "bucket $$BUCKET ready"

  mailpit:
    image: axllent/mailpit:v1.31.3
    restart: unless-stopped
    ports: ["127.0.0.1:8025:8025"]

  # Django writes uploads and sends email; the workers send email.
  django-blue:
    depends_on:
      s3-init:
        condition: service_completed_successfully
      mailpit:
        condition: service_started
  django-green:
    depends_on:
      s3-init:
        condition: service_completed_successfully
      mailpit:
        condition: service_started
  celery-worker-blue:
    depends_on:
      mailpit:
        condition: service_started
  celery-worker-green:
    depends_on:
      mailpit:
        condition: service_started

volumes:
  s3_data:
```

```bash
chmod +x infra/scripts/tests/compose_test.sh
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash infra/scripts/tests/compose_test.sh`
Expected: FAIL, three failures: `the edge does not default to TLS_MODE=cloudflare`, `an image still comes from GHCR with ETQAN_REGISTRY set`, `ETQAN_REGISTRY did not move the three app images`.

- [ ] **Step 3: Implement the compose changes, the env template and the helpers**

In `infra/docker-compose.production.yml`, replace the first line:

```yaml
services:
```

with:

```yaml
# Images come from ETQAN_REGISTRY, ghcr.io/etqan-agency unless .env.production
# says otherwise (the simulated staging server has its own registry).
services:
```

Replace:

```yaml
      - CF_API_TOKEN=${CF_API_TOKEN:?}
```

with:

```yaml
      - CF_API_TOKEN=${CF_API_TOKEN:?}
      # cloudflare (production) or internal (staging): caddy/Caddyfile.
      - TLS_MODE=${TLS_MODE:-cloudflare}
```

Point all nine app images at the registry switch:

```bash
sed -i 's|image: ghcr.io/etqan-agency/|image: ${ETQAN_REGISTRY:-ghcr.io/etqan-agency}/|' infra/docker-compose.production.yml
grep -c 'image: ${ETQAN_REGISTRY:-ghcr.io/etqan-agency}/' infra/docker-compose.production.yml   # expect 9
```

The overlay (Step 1) swaps only what staging cannot have yet: RustFS for S3 (D6: MinIO's images are no longer pullable) with a one-shot `s3-init` that creates the bucket and allows public reads of `tenants/*`, and Mailpit for SES (D7). Django and the workers wait for them through `depends_on`, so `ship.sh`'s one-off `run --rm django-<colour>` (migrate) starts them too.

Create `infra/.env.staging.example`:

```bash
# Staging: production's compose file and images, plus the staging overlay
# (docker-compose.staging.yml), on one server. Copy this to
# /opt/etqan/.env.production on the staging server (chmod 600) and replace
# every CHANGE_ME. It never leaves the server; CI never reads it. See
# STAGING.md. Values that match production's are explained in
# .env.production.example.

# ─── Staging switches ───────────────────────────────────────
# ship.sh adds docker-compose.staging.yml (S3 store, Mailpit).
ETQAN_OVERLAY=staging
# Caddy's own CA for every host (no Cloudflare zone yet). `cloudflare` is
# production's wildcard certificate; it then needs a real CF_API_TOKEN.
TLS_MODE=internal
# Where the images come from. The simulated server uses its own registry.
ETQAN_REGISTRY=ghcr.io/etqan-agency

# ─── Edge (Caddy) ───────────────────────────────────────────
# Academies are <sub>.${BASE_DOMAIN}; the bare domain is the staff admin.
BASE_DOMAIN=staging.example.com
# Required by compose, unused while TLS_MODE=internal.
CF_API_TOKEN=unused-while-tls-mode-is-internal
ACME_EMAIL=admin@etqan.academy
DEPLOY_SHA=latest

# ─── Django ─────────────────────────────────────────────────
DJANGO_SECRET_KEY=CHANGE_ME_SECRET_KEY
DATABASE_URL=postgres://etqan:CHANGE_ME_DB_PASSWORD@postgres:5432/etqan
CELERY_BROKER_URL=redis://redis:6379/0
POSTGRES_DB=etqan
POSTGRES_USER=etqan
POSTGRES_PASSWORD=CHANGE_ME_DB_PASSWORD
SENTRY_DSN=
CSRF_TRUSTED_ORIGINS=
DJANGO_TENANT_BASE_DOMAIN=${BASE_DOMAIN}
DJANGO_TENANT_URL_TEMPLATE=https://{domain}
DJANGO_FRONTEND_URL=https://${BASE_DOMAIN}
DJANGO_EDGE_HOSTNAME=sites.${BASE_DOMAIN}
DJANGO_EDGE_PUBLIC_IP=
# The demo academy admin's password (seed_staging refuses to run without
# it; production never sets it). Choose a new one; never a dev password.
DJANGO_STAGING_DEMO_PASSWORD=CHANGE_ME_DEMO_PASSWORD

# ─── Uploads: the overlay's S3 store (service `s3`) ─────────
# s3-init creates the bucket and allows public reads of tenants/*. Uploaded
# images are linked at the store's in-network address, so browsers cannot
# load them on staging; real S3 (or a public custom domain) fixes that.
DJANGO_S3_BUCKET=etqan-staging-media
DJANGO_S3_ENDPOINT_URL=http://s3:9000
DJANGO_S3_REGION=us-east-1
DJANGO_S3_CUSTOM_DOMAIN=
# The store's root credentials, and Django's.
AWS_ACCESS_KEY_ID=etqan-staging
AWS_SECRET_ACCESS_KEY=CHANGE_ME_S3_SECRET

# ─── Email: the overlay's Mailpit (service `mailpit`) ───────
# Everything sent is kept in Mailpit, never delivered. Read it over an SSH
# tunnel: ssh -L 8025:127.0.0.1:8025 <server>, then http://localhost:8025.
DJANGO_EMAIL_HOST=mailpit
DJANGO_EMAIL_PORT=1025
DJANGO_EMAIL_USE_TLS=False
DJANGO_EMAIL_HOST_USER=
DJANGO_EMAIL_HOST_PASSWORD=
DJANGO_DEFAULT_FROM_EMAIL=etqan staging <noreply@staging.example.com>
```

Create `infra/scripts/manage.sh`:

```bash
#!/usr/bin/env bash
# Run a Django management command in the live colour's web container.
#   bash /opt/etqan/scripts/manage.sh seed_staging
# The staging deploy seeds through it, and the e2e suite runs its commands
# through it over SSH (E2E_MANAGE).
set -euo pipefail

ETQAN_DIR="${ETQAN_DIR:-/opt/etqan}"
COLOR="$(cat "${ETQAN_DIR}/.active-color" 2>/dev/null || true)"
case "$COLOR" in
    blue | green) ;;
    *)
        echo "ERROR: no live colour in ${ETQAN_DIR}/.active-color; deploy first." >&2
        exit 1
        ;;
esac
exec docker exec "etqan-django-${COLOR}-1" python manage.py "$@"
```

Create `infra/scripts/edge-ca.sh`:

```bash
#!/usr/bin/env bash
# Print the root certificate of the edge's internal CA when the edge runs
# with TLS_MODE=internal, or nothing. Clients outside the server (the smoke
# check, a tester's browser) trust it instead of a public CA.
#   bash /opt/etqan/scripts/edge-ca.sh > staging-root.crt
set -euo pipefail

EDGE=etqan-caddy-1
if [ "$(docker exec "$EDGE" printenv TLS_MODE 2>/dev/null || true)" = "internal" ]; then
    docker exec "$EDGE" cat /data/caddy/pki/authorities/local/root.crt
fi
```

```bash
chmod +x infra/scripts/manage.sh infra/scripts/edge-ca.sh
```

In `.github/workflows/ci.yml` (meta), replace:

```yaml
      - name: ship.sh and smoke.sh tests
        run: |
          bash infra/scripts/tests/ship_test.sh
          bash infra/scripts/tests/smoke_test.sh
```

with:

```yaml
      - name: ship.sh, smoke.sh and compose tests
        run: |
          bash infra/scripts/tests/ship_test.sh
          bash infra/scripts/tests/smoke_test.sh
          bash infra/scripts/tests/compose_test.sh
```

- [ ] **Step 4: Run the tests**

```bash
bash infra/scripts/tests/compose_test.sh
bash infra/scripts/tests/ship_test.sh
shellcheck infra/scripts/*.sh infra/scripts/tests/*.sh
actionlint .github/workflows/ci.yml
```

Expected: `compose_test: all passed`, `ship_test: all passed`, no other output. The whole overlay runs for real in Task 7.

- [ ] **Step 5: Commit (infra, then meta)**

```bash
git -C infra add docker-compose.production.yml docker-compose.staging.yml .env.staging.example \
  scripts/manage.sh scripts/edge-ca.sh scripts/tests/compose_test.sh
git -C infra commit -m "feat(infra): staging overlay (S3 store, Mailpit), registry switch and server helpers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git add .github/workflows/ci.yml
git commit -m "ci: test the compose files' shape

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `seed_staging`: the demo academy on a staging server, once

**Files:**
- Create: `backend/etqan/tenants/management/commands/seed_staging.py`, `backend/etqan/tenants/tests/test_seed_staging.py`
- Modify: `backend/config/settings/base.py` (after `FRONTEND_URL`), `backend/etqan/tenants/management/commands/seed_dev.py` (extract `seed_academy`)
- Existing tests: `etqan/tenants/tests/test_seed_dev.py` must pass unchanged (the extraction is behaviour-neutral).

**Interfaces:**
- Consumes: `seed_dev.ACADEMIES`, and every `seed_*` function in `seed_dev`; `services.create_academy(*, name, subdomain, admin_email, admin_full_name, admin_password)`, `services.domain_for(subdomain)`.
- Produces: `seed_dev.seed_academy(academy: Academy, subdomain: str, name: str) -> None`; setting `STAGING_DEMO_PASSWORD: str` (env `DJANGO_STAGING_DEMO_PASSWORD`, default `""`); `manage.py seed_staging` printing `created: demo.<base>` or `exists: demo`, and raising `CommandError` (naming `DJANGO_STAGING_DEMO_PASSWORD`) without the password. Task 7 runs it as `manage.sh seed_staging`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/tenants/tests/test_seed_staging.py`:

```python
"""seed_staging: the demo academy on a staging server, once (spec §6.2)."""

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.billing import services as billing
from etqan.identity.models import User
from etqan.payroll import services as payroll
from etqan.scheduling import services as scheduling
from etqan.tenants.models import Academy

PASSWORD = "staging-Demo-2026"


def subdomains() -> set[str]:
    connection.set_schema_to_public()
    return set(Academy.objects.values_list("subdomain", flat=True))


def snapshot() -> dict:
    """What the seed writes in an academy, comparable across runs."""
    return {
        "people": sorted(User.objects.values_list("full_name", "role")),
        "subscriptions": scheduling.subscriptions_queryset().count(),
        "sessions": scheduling.sessions_queryset().count(),
        "invoices": billing.invoices_queryset().count(),
        "payslips": payroll.payslips_queryset().count(),
    }


@pytest.mark.django_db
def test_seed_staging_refuses_without_the_staging_password(settings):
    settings.STAGING_DEMO_PASSWORD = ""
    before = subdomains()
    with pytest.raises(CommandError, match="DJANGO_STAGING_DEMO_PASSWORD"):
        call_command("seed_staging")
    assert subdomains() == before


@pytest.mark.django_db
def test_seed_staging_creates_the_demo_academy_with_the_dev_data(settings):
    # DEBUG stays off: staging runs production settings.
    settings.STAGING_DEMO_PASSWORD = PASSWORD
    call_command("seed_staging")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    with tenant_context(demo):
        admin = User.objects.get(email="admin@demo.test")
        assert admin.role == "admin"
        assert admin.check_password(PASSWORD)
        seeded = snapshot()
        assert [role for _, role in seeded["people"]].count("teacher") == 2
        assert seeded["subscriptions"] == 4
        assert seeded["sessions"] > 0
        assert seeded["invoices"] == 4
        assert payroll.has_payroll()


@pytest.mark.django_db
def test_seed_staging_leaves_an_existing_demo_academy_as_it_is(settings, capsys):
    settings.STAGING_DEMO_PASSWORD = PASSWORD
    call_command("seed_staging")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    with tenant_context(demo):
        first = snapshot()
    capsys.readouterr()

    settings.STAGING_DEMO_PASSWORD = "another-Password-2026"
    call_command("seed_staging")
    assert capsys.readouterr().out.strip() == "exists: demo"
    connection.set_schema_to_public()
    assert Academy.objects.filter(subdomain="demo").count() == 1
    with tenant_context(demo):
        assert snapshot() == first
        admin = User.objects.get(email="admin@demo.test")
        assert admin.check_password(PASSWORD)


@pytest.mark.django_db
def test_seed_staging_touches_no_other_academy(settings, tenants):
    settings.STAGING_DEMO_PASSWORD = PASSWORD
    with tenant_context(tenants.other):
        User.objects.create_user(
            email="kept@other.test",
            password="pw-12345678",
            full_name="Kept",
            role="admin",
        )
        other_before = snapshot()
    with tenant_context(tenants.main):
        main_before = snapshot()
    before = subdomains()

    call_command("seed_staging")

    # Only the demo academy is new: seed_dev's "other" academy is not made.
    assert subdomains() == before | {"demo"}
    with tenant_context(tenants.other):
        assert snapshot() == other_before
    with tenant_context(tenants.main):
        assert snapshot() == main_before
```

- [ ] **Step 2: Run them to see them fail**

Run: `.venv/bin/pytest -q etqan/tenants/tests/test_seed_staging.py`
Expected: 4 failed (`Unknown command: 'seed_staging'`).

- [ ] **Step 3: Implement**

In `backend/config/settings/base.py`, replace:

```python
FRONTEND_URL = env("DJANGO_FRONTEND_URL", default="http://etqan.localhost")
```

with:

```python
FRONTEND_URL = env("DJANGO_FRONTEND_URL", default="http://etqan.localhost")

# The demo academy admin's password on a staging server (`seed_staging`).
# Unset everywhere else, and seed_staging refuses to run without it, so a
# production server never gets the demo academy.
STAGING_DEMO_PASSWORD = env("DJANGO_STAGING_DEMO_PASSWORD", default="")
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."
```

with:

```python
def seed_academy(academy: Academy, subdomain: str, name: str) -> None:
    """One seeded academy's data, inside its own schema. Every step is
    idempotent, so a second run adds nothing (seed_staging reuses it)."""
    with tenant_context(academy):
        site_services.ensure_site_defaults(name)
        site_services.seed_site(**SITES[subdomain])
        seed_people(PEOPLE[subdomain])
        seed_subscriptions(SUBSCRIPTIONS[subdomain])
        seed_attendance()
        seed_billing(INVOICES[subdomain])
        seed_payroll(PAYROLL.get(subdomain))
        seed_notifications(NOTIFIED.get(subdomain))


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."
```

and replace, at the end of `Command.handle`:

```python
            with tenant_context(academy):
                site_services.ensure_site_defaults(name)
                site_services.seed_site(**SITES[subdomain])
                seed_people(PEOPLE[subdomain])
                seed_subscriptions(SUBSCRIPTIONS[subdomain])
                seed_attendance()
                seed_billing(INVOICES[subdomain])
                seed_payroll(PAYROLL.get(subdomain))
                seed_notifications(NOTIFIED.get(subdomain))
```

with:

```python
            seed_academy(academy, subdomain, name)
```

Create `backend/etqan/tenants/management/commands/seed_staging.py`:

```python
"""The demo academy on a staging server, once (spec §6.2).

Runs with production settings (no DEBUG), so it is guarded by its own
setting instead: DJANGO_STAGING_DEMO_PASSWORD, set only in a staging
server's .env.production. The demo academy gets seed_dev's data and that
password for its admin. An existing demo academy is left exactly as it is,
and no other academy is read or written.
"""

from django.conf import settings
from django.core.management.base import BaseCommand
from django.core.management.base import CommandError
from django.db import connection

from etqan.tenants import services
from etqan.tenants.management.commands import seed_dev
from etqan.tenants.models import Academy

DEMO = seed_dev.ACADEMIES[0]


class Command(BaseCommand):
    help = "Create the demo academy with the dev data, if it does not exist yet."

    def handle(self, *args, **options):
        password = settings.STAGING_DEMO_PASSWORD
        if not password:
            raise CommandError(
                "seed_staging needs DJANGO_STAGING_DEMO_PASSWORD "
                "(set only on a staging server)."
            )
        subdomain, name, email = DEMO
        connection.set_schema_to_public()
        if Academy.objects.filter(subdomain=subdomain).exists():
            self.stdout.write(f"exists: {subdomain}")
            return
        academy = services.create_academy(
            name=name,
            subdomain=subdomain,
            admin_email=email,
            admin_full_name=f"{name} Admin",
            admin_password=password,
        )
        connection.set_schema_to_public()
        seed_dev.seed_academy(academy, subdomain, name)
        connection.set_schema_to_public()
        self.stdout.write(
            self.style.SUCCESS(f"created: {services.domain_for(subdomain)}")
        )
```

`seed_staging` imports `seed_dev`, which imports `etqan.notifications.services`; the "no app imports notifications" contract already ignores that one edge (`seed_dev -> notifications.services`), so no contract changes.

- [ ] **Step 4: Run the tests and the backend gates**

```bash
.venv/bin/pytest -q etqan/tenants/tests/test_seed_staging.py etqan/tenants/tests/test_seed_dev.py
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: all pass; `Contracts: 16 kept, 0 broken.`; 1268 passed, coverage ≈ 97.9%.

- [ ] **Step 5: Commit**

```bash
git -C backend add config/settings/base.py etqan/tenants/management/commands/seed_dev.py \
  etqan/tenants/management/commands/seed_staging.py etqan/tenants/tests/test_seed_staging.py
git -C backend commit -m "feat(tenants): seed_staging creates the demo academy on a staging server once

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The full journey, and the e2e helpers' target switches

**Files:**
- Create: `dashboard/e2e/journey.spec.ts`
- Modify: `dashboard/e2e/fixtures.ts`, `dashboard/e2e/manage.ts`, `dashboard/e2e/mail.ts`, `dashboard/playwright.config.ts`
- Existing specs: all seventeen keep passing unchanged (they use `DEMO_URL`, `OTHER_URL`, `INVITE`, `acceptInvite`, `latestLink` and `manage`, whose behaviour for them is the same).

**Interfaces:**
- Consumes: Task 5 is not needed here (the journey makes its own academy). The backend commands `create_academy` (prints `Created <name> at <domain>`) and `scan_notifications` (prints `ok: <schema>`; schema `academy_<subdomain with _ for ->`).
- Produces, in `e2e/fixtures.ts`: `BASE_URL: string` (env `E2E_BASE_URL`, default `http://etqan.localhost`), `academyUrl(subdomain: string): string`, `INVITE` matching `http` or `https`, `acceptInvite` signing in on the invite's origin. In `e2e/manage.ts`: `shellQuote(arg: string): string`; `manage(...args)` runs `E2E_MANAGE <quoted args>` when that env is set. In `e2e/mail.ts`: base64 parts decoded. In `playwright.config.ts`: `E2E_HOST_RESOLVER_RULES` → `--host-resolver-rules=…`, `E2E_IGNORE_HTTPS_ERRORS=1` → `ignoreHTTPSErrors`. Task 7 sets all of these.
- CI: no change to the `e2e` job; the journey runs there with the other specs (local `manage`, file outbox).

- [ ] **Step 1: Write the failing test**

Create `dashboard/e2e/journey.spec.ts`:

```ts
import { expect, type Page, test } from "@playwright/test";
import { acceptInvite, academyUrl } from "./fixtures";
import { manage } from "./manage";

const DAY_MS = 86_400_000;
const addDays = (day: string, offset: number) =>
	new Date(Date.parse(`${day}T00:00:00Z`) + offset * DAY_MS)
		.toISOString()
		.slice(0, 10);
const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

/** Last month on the academy's calendar, from its today ("YYYY-MM-DD"): its
 * year, month and 15th, which is always over and never a month's edge. */
function lastMonth(today: string) {
	const [year, month] = today.split("-").map(Number);
	const y = month === 1 ? year - 1 : year;
	const m = month === 1 ? 12 : month - 1;
	return { year: y, month: m, mid: `${y}-${String(m).padStart(2, "0")}-15` };
}

/** A record page's card header (number heading and status chip), so a
 * status is never matched by a fact label elsewhere on the page. */
const header = (page: Page, number: string) =>
	page.locator('[data-slot="card-header"]').filter({
		has: page.getByRole("heading", { name: number, exact: true }),
	});

// v1 spec §7, the whole journey, in a new academy (spec §6.1): Etqan creates
// it with the `create_academy` command; its admin accepts the invite and sets
// up a course, a package, a teacher and a student with a parent; the
// subscription (two slots) starts on the 15th of last month, so its sessions
// are in a month that is over whatever today is, and away from midnight and
// the month's edges; the teacher marks the student absent and reports; the
// admin records the payment, sets the teacher's rate, and generates and
// issues last month's payslip; the scan runs and the parent sees the
// absence. Runs in the CI e2e job and against the simulated staging server.
// Required labels end in `*`, hence the regex queries.
test("an academy's first month, from Etqan to a parent's notification", async ({
	browser,
}) => {
	// A new academy migrates a schema of its own: allow for it.
	test.setTimeout(5 * 60_000);
	const stamp = Date.now();
	const subdomain = `journey-${stamp}`;
	const academy = academyUrl(subdomain);
	const name = `E2E Journey ${stamp}`;
	const adminName = `E2E Journey Admin ${stamp}`;
	const adminEmail = `e2e-journey-admin-${stamp}@e2e.test`;
	const teacher = `E2E Journey Teacher ${stamp}`;
	const teacherEmail = `e2e-journey-teacher-${stamp}@e2e.test`;
	const parent = `E2E Journey Parent ${stamp}`;
	const parentEmail = `e2e-journey-parent-${stamp}@e2e.test`;
	const student = `E2E Journey Student ${stamp}`;
	const course = `E2E Journey Course ${stamp}`;
	const pkg = `E2E Journey Package ${stamp}`;

	// 1. Etqan creates the academy
	expect(
		manage(
			"create_academy",
			"--name",
			name,
			"--subdomain",
			subdomain,
			"--admin-email",
			adminEmail,
			"--admin-name",
			adminName,
		),
	).toContain(`Created ${name} at ${new URL(academy).hostname}`);

	// 2. Its admin accepts the invite
	const admin = await acceptInvite(
		browser,
		adminEmail,
		"e2e-Journey-2026",
		adminName,
	);
	await expect(admin).toHaveURL(new RegExp(`^${academy}/app`));
	await admin.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// 3. A teacher (invited), their course, a package, a parent (invited)
	// and a student without a login, linked to the parent
	await admin.goto(`${academy}/app/people/teachers/new`);
	await admin.getByLabel(/^full name/i).fill(teacher);
	await admin.getByLabel(/^gender/i).selectOption("female");
	await admin.getByLabel(/^email/i).fill(teacherEmail);
	await admin.getByLabel("Preferred language").selectOption("en");
	await admin.getByRole("button", { name: "Save", exact: true }).click();
	await expect(admin).toHaveURL(/\/app\/people\/teachers\/\d+$/);

	await admin.goto(`${academy}/app/catalogue/courses/new`);
	await admin.getByLabel(/^name \(arabic\)/i).fill(`رحلة ${stamp}`);
	await admin.getByLabel(/^name \(english\)/i).fill(course);
	await admin.getByLabel(teacher, { exact: true }).click();
	await admin.getByRole("button", { name: "Save", exact: true }).click();
	await expect(admin).toHaveURL(/\/app\/catalogue\/courses$/);

	await admin.goto(`${academy}/app/catalogue/packages/new`);
	await admin.getByLabel(/^name \(arabic\)/i).fill(`باقة رحلة ${stamp}`);
	await admin.getByLabel(/^name \(english\)/i).fill(pkg);
	await admin.getByLabel("Sessions per week").fill("2");
	await admin.getByLabel("Duration", { exact: true }).fill("1");
	await admin.getByLabel("Duration unit").selectOption("month");
	await admin.getByLabel("Price").fill("400");
	await admin.getByRole("button", { name: "Save", exact: true }).click();
	await expect(admin).toHaveURL(/\/app\/catalogue\/packages$/);

	await admin.goto(`${academy}/app/people/parents/new`);
	await admin.getByLabel(/^full name/i).fill(parent);
	await admin.getByLabel(/^email/i).fill(parentEmail);
	await admin.getByLabel("Preferred language").selectOption("en");
	await admin.getByRole("button", { name: "Save", exact: true }).click();
	await expect(admin).toHaveURL(/\/app\/people\/parents\/\d+$/);

	await admin.goto(`${academy}/app/people/students/new`);
	await admin.getByLabel(/^full name/i).fill(student);
	await admin.getByRole("button", { name: "Save", exact: true }).click();
	await expect(admin).toHaveURL(/\/app\/people\/students\/\d+$/);
	await admin.getByLabel("Find a parent").fill(parent);
	await admin
		.getByRole("button", { name: `Link ${parent}`, exact: true })
		.click();
	await expect(
		admin.getByRole("button", { name: `Unlink ${parent}`, exact: true }),
	).toBeVisible();

	// 4. A subscription from the 15th of last month with two slots, then
	// that week's two sessions
	await admin.goto(`${academy}/app/scheduling/subscriptions/new`);
	const startsOn = admin.getByLabel(/^Starts/);
	await expect(startsOn).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
	const month = lastMonth(await startsOn.inputValue());
	await startsOn.fill(month.mid);
	await admin.getByLabel("Find a student").fill(student);
	await admin.getByLabel(/^Student/).selectOption({ label: student });
	await admin.getByLabel(/^Course/).selectOption({ label: course });
	await admin.getByLabel(/^Teacher/).selectOption({ label: teacher });
	await admin.getByLabel(/^Package/).selectOption({ label: pkg });
	await admin.getByLabel(weekday(month.mid), { exact: true }).click();
	await admin
		.getByLabel(weekday(addDays(month.mid, 3)), { exact: true })
		.click();
	await admin.getByLabel(/^Start time/).fill("12:00");
	await admin.getByRole("button", { name: "Create subscription" }).click();
	await expect(admin).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);
	const invoiceLink = admin.getByRole("link", { name: /^INV-\d{6}$/ });
	await expect(invoiceLink).toHaveCount(1);
	const invoice = (await invoiceLink.textContent()) ?? "";
	const invoiceUrl = `${academy}${await invoiceLink.getAttribute("href")}`;

	await admin.goto(`${academy}/app/scheduling/today`);
	await admin.getByRole("button", { name: "Generate for range" }).click();
	const generate = admin.getByRole("dialog");
	await generate.getByLabel(/^From/).fill(month.mid);
	await generate.getByLabel(/^To/).fill(addDays(month.mid, 6));
	await generate.getByRole("button", { name: "Generate", exact: true }).click();
	await expect(generate.getByText(/^Created 2\./)).toBeVisible();
	await admin.keyboard.press("Escape");

	// 5. The teacher accepts the invite, marks the student absent on a
	// session of that week and writes its report
	const tutor = await acceptInvite(
		browser,
		teacherEmail,
		"e2e-Journey-Teacher-2026",
		teacher,
	);
	await tutor.goto(`${academy}/app/teaching/sessions`);
	await tutor.getByRole("tab", { name: "History", exact: true }).click();
	const lesson = tutor.getByRole("row", { name: new RegExp(student) }).first();
	await lesson
		.getByLabel(`Student attendance for ${student}`, { exact: true })
		.selectOption("absent");
	await expect(lesson).toContainText("Completed");
	await lesson
		.getByRole("button", {
			name: `Write the report for ${student}`,
			exact: true,
		})
		.click();
	const report = tutor.getByRole("dialog");
	await report.getByLabel(/^Behaviour/).selectOption({ label: "Good" });
	await report.getByLabel(/^Participation/).selectOption({ label: "Good" });
	await report.getByLabel("Notes").fill("Absent; homework sent.");
	await report.getByRole("button", { name: "Save report" }).click();
	await expect(tutor.getByRole("dialog")).toHaveCount(0);
	await expect(
		lesson.getByRole("button", {
			name: `Edit the report for ${student}`,
			exact: true,
		}),
	).toBeVisible();
	await tutor.context().close();

	// 6. The admin records the payment on the subscription's invoice
	await admin.goto(invoiceUrl);
	await admin.getByRole("button", { name: "Record payment" }).click();
	const payment = admin.getByRole("dialog");
	await expect(payment.getByLabel(/^Amount/)).toHaveValue("400.00");
	await payment.getByRole("button", { name: "Record payment" }).click();
	await expect(admin.getByRole("dialog")).toHaveCount(0);
	await expect(
		header(admin, invoice).getByText("Paid", { exact: true }),
	).toBeVisible();

	// 7. The teacher's rate, then last month's payslip, generated and issued
	await admin.goto(`${academy}/app/payroll/rates`);
	await admin
		.getByRole("button", { name: `Add a rate for ${teacher}`, exact: true })
		.click();
	const rate = admin.getByRole("dialog");
	await rate.getByLabel(/^Per hour \(USD\)/).fill("20");
	await rate.getByRole("button", { name: "Save rate" }).click();
	await expect(admin.getByRole("dialog")).toHaveCount(0);

	await admin.goto(`${academy}/app/payroll/payslips`);
	await admin.getByLabel("Year").selectOption(String(month.year));
	await admin.getByLabel("Month").selectOption(String(month.month));
	await admin.getByRole("button", { name: "Generate", exact: true }).click();
	await expect(
		admin.getByText(/^New: \d+\. Updated: \d+\. Removed: \d+\.$/),
	).toBeVisible();
	const payslipRow = admin.getByRole("row", { name: new RegExp(teacher) });
	await expect(payslipRow.getByText("Draft", { exact: true })).toBeVisible();
	const payslipLink = payslipRow.getByRole("link", { name: /^PAY-\d{6}$/ });
	const payslip = (await payslipLink.textContent()) ?? "";
	await payslipLink.click();
	await expect(admin).toHaveURL(/\/app\/payroll\/payslips\/\d+$/);
	await admin.getByRole("button", { name: "Issue", exact: true }).click();
	await admin
		.getByRole("alertdialog")
		.getByRole("button", { name: "Issue this payslip" })
		.click();
	await expect(
		header(admin, payslip).getByText("Issued", { exact: true }),
	).toBeVisible();
	await admin.context().close();

	// 8. The scan runs (as the beat job does every minute), and the parent
	// signs in and finds the absence
	expect(manage("scan_notifications")).toContain(
		`ok: academy_${subdomain.replaceAll("-", "_")}`,
	);
	const guardian = await acceptInvite(
		browser,
		parentEmail,
		"e2e-Journey-Parent-2026",
		parent,
	);
	await expect(
		guardian.getByRole("button", { name: /^Notifications, \d+ unread$/ }),
	).toBeVisible();
	await guardian.goto(`${academy}/app/notifications`);
	await expect(
		guardian.getByRole("listitem").filter({ hasText: `Absent: ${student}` }),
	).toBeVisible();
	await guardian.context().close();
});
```

- [ ] **Step 2: Run it through Caddy, as the CI `e2e` job does, to see it fail**

From the meta root, on an empty database (`docker exec etqan-test-pg psql -U etqan -d postgres -c 'CREATE DATABASE etqan_e2e'`). Port 8000 is taken on this laptop, so Django listens on 18000 and the edge uses a copy of `Caddyfile.e2e` pointed there; CI uses the file as is.

```bash
export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan_e2e CELERY_BROKER_URL=redis://localhost:56379/5 \
  DJANGO_SETTINGS_MODULE=config.settings.local DJANGO_SECRET_KEY=ci-only DJANGO_READ_DOT_ENV_FILE=False \
  DJANGO_EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend DJANGO_EMAIL_FILE_PATH=/tmp/etqan-mail \
  CELERY_TASK_ALWAYS_EAGER=true DJANGO_TENANT_URL_TEMPLATE=http://{domain}
mkdir -p /tmp/etqan-mail
(cd backend && .venv/bin/python manage.py migrate_schemas --shared && .venv/bin/python manage.py seed_dev)
(cd backend && nohup .venv/bin/python manage.py runserver 127.0.0.1:18000 --noreload > /tmp/django.log 2>&1 &)
(cd dashboard && npx pnpm@10 build && VITE_PROXY_TARGET=http://127.0.0.1:18000 nohup npx pnpm@10 preview --port 4173 --host 127.0.0.1 > /tmp/preview.log 2>&1 &)
(cd marketing && SITE_API_ORIGIN=http://127.0.0.1:18000 SITE_SCHEME=http HOST=127.0.0.1 PORT=4321 nohup node dist/server/entry.mjs > /tmp/marketing.log 2>&1 &)
sed 's/127.0.0.1:8000/127.0.0.1:18000/g' caddy/Caddyfile.e2e > /tmp/Caddyfile.e2e
docker run -d --name e2e-edge --network host -v /tmp/Caddyfile.e2e:/etc/caddy/Caddyfile:ro caddy:2.11.4-alpine
cd dashboard
CI=1 E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost E2E_MAIL_DIR=/tmp/etqan-mail \
  E2E_PYTHON=$PWD/../backend/.venv/bin/python npx pnpm@10 exec playwright test e2e/journey.spec.ts --retries=0
```

(`marketing/dist` needs `pnpm install && pnpm build` in `marketing/` once.) Expected: FAIL: `fixtures.ts` does not export `academyUrl`. With Step 3's `fixtures.ts` and `manage.ts` but not its `mail.ts` change, it fails at step 2 instead, `No email with a matching link reached e2e-journey-admin-…`: a new academy's first admin reads Arabic, and an Arabic-only body goes out base64, which `mail.ts` does not read yet (checked while verifying this plan).

- [ ] **Step 3: Implement the helpers' switches**

Replace the whole of `dashboard/e2e/fixtures.ts` with:

```ts
import { type Browser, expect, type Page } from "@playwright/test";
import { latestLink } from "./mail";

// Must match backend/etqan/tenants/management/commands/seed_dev.py
export const DEV_PASSWORD = "e2e-EtqanTest-2026";
/** The platform's base domain, with its scheme: every academy is a
 * subdomain of it. `https://staging.test` on the simulated staging server. */
export const BASE_URL = process.env.E2E_BASE_URL ?? "http://etqan.localhost";

/** An academy's origin from its subdomain, under `BASE_URL`. */
export function academyUrl(subdomain: string): string {
	const url = new URL(BASE_URL);
	url.hostname = `${subdomain}.${url.hostname}`;
	return url.origin;
}

export const DEMO_URL = process.env.E2E_DEMO_URL ?? academyUrl("demo");
export const OTHER_URL = process.env.E2E_OTHER_URL ?? academyUrl("other");
export const DEMO_ADMIN = "admin@demo.test";
export const OTHER_ADMIN = "admin@other.test";

export async function login(page: Page, baseUrl: string, email: string) {
	await page.goto(`${baseUrl}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
	await page.getByRole("button", { name: /sign in/i }).click();
}

export async function expectLoggedIn(page: Page, name: RegExp) {
	await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();
}

export const INVITE =
	/https?:\/\/[^\s"<]+\/app\/reset-password\?uid=[^\s"<&]+&token=[^\s"<]+/;

/** Follow the emailed invite, set a password and sign in, in a new context,
 * on the academy the invite came from. */
export async function acceptInvite(
	browser: Browser,
	email: string,
	password: string,
	name: string,
): Promise<Page> {
	const link = await latestLink(email, INVITE);
	const context = await browser.newContext();
	const page = await context.newPage();
	await page.goto(link);
	await page.getByLabel(/^new password/i).fill(password);
	await page.getByRole("button", { name: "Reset password" }).click();
	await expect(page.getByText(/you can now sign in/i)).toBeVisible();
	await page.goto(`${new URL(link).origin}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(password);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, new RegExp(name));
	return page;
}
```

Replace the whole of `dashboard/e2e/manage.ts` with:

```ts
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

/** The backend checkout beside the dashboard in the meta repo (the CI `e2e`
 * job checks the submodules out), unless `E2E_BACKEND_DIR` says otherwise. */
const BACKEND_DIR =
	process.env.E2E_BACKEND_DIR ??
	fileURLToPath(new URL("../../backend", import.meta.url));
/** The Python with the backend's requirements: CI's `python`, or
 * `E2E_PYTHON` (`backend/.venv/bin/python` on a laptop). */
const PYTHON = process.env.E2E_PYTHON ?? "python";
/** A command line that runs `manage.py` on a deployed server instead, its
 * words split on spaces: the staging simulation sets
 * `ssh <options> deploy@<host> bash /opt/etqan/scripts/manage.sh`. */
const REMOTE = process.env.E2E_MANAGE?.trim().split(/\s+/);

/** One argument, quoted for the remote shell that ssh hands the words to. */
export const shellQuote = (arg: string) => `'${arg.replaceAll("'", `'\\''`)}'`;

/** Run a Django management command against the server under test: locally
 * with the same settings, database and email backend (inherited from this
 * environment), or on the deployed server through `E2E_MANAGE`. A command,
 * not an HTTP route, so nothing test-only is reachable in production. */
export function manage(...args: string[]): string {
	if (REMOTE) {
		const [command, ...words] = REMOTE;
		return execFileSync(command, [...words, ...args.map(shellQuote)], {
			encoding: "utf8",
		});
	}
	return execFileSync(PYTHON, ["manage.py", ...args], {
		cwd: BACKEND_DIR,
		encoding: "utf8",
	});
}
```

In `dashboard/e2e/mail.ts`, replace:

```ts
/** Every email to `address` in the file outbox, newest first. */
```

with:

```ts
/**
 * The base64 parts of a raw message, decoded. A body in Arabic alone (a new
 * academy's first admin reads the academy's language, Arabic by default)
 * goes out base64, not quoted-printable. Taken from the raw text before the
 * quoted-printable pass, which would join base64 lines ending in `=`.
 */
function base64Parts(raw: string): string[] {
	const parts: string[] = [];
	for (const [, body] of raw.matchAll(
		/Content-Transfer-Encoding: base64\r?\n(?:[^\r\n]+\r?\n)*\r?\n([A-Za-z0-9+/=\r\n]+)/g,
	)) {
		parts.push(
			Buffer.from(body.replace(/\s+/g, ""), "base64").toString("utf8"),
		);
	}
	return parts;
}

/** Every email to `address` in the file outbox, newest first. */
```

and replace:

```ts
	return files
		.map((file) => decodeQuotedPrintable(readFileSync(file, "latin1")))
		.filter((text) => text.includes(`To: ${address}`));
```

with:

```ts
	return files
		.map((file) => {
			const raw = readFileSync(file, "latin1");
			return [decodeQuotedPrintable(raw), ...base64Parts(raw)].join("\n");
		})
		.filter((text) => text.includes(`To: ${address}`));
```

In `dashboard/playwright.config.ts`, replace:

```ts
const APP_URL = process.env.E2E_APP_URL ?? "http://demo.etqan.localhost";
```

with:

```ts
const APP_URL = process.env.E2E_APP_URL ?? "http://demo.etqan.localhost";
// A deployed stack (the simulated staging server) is reached by name through
// Chromium's resolver rules (`MAP *.staging.test 127.0.0.1:18443`), so Host
// and SNI stay the real names, and its certificates come from the edge's
// internal CA, which the smoke check has already verified with curl.
const HOST_RULES = process.env.E2E_HOST_RESOLVER_RULES;
```

and replace:

```ts
	use: {
		baseURL: APP_URL,
		trace: "on-first-retry",
		screenshot: "only-on-failure",
	},
```

with:

```ts
	use: {
		baseURL: APP_URL,
		trace: "on-first-retry",
		screenshot: "only-on-failure",
		ignoreHTTPSErrors: process.env.E2E_IGNORE_HTTPS_ERRORS === "1",
		launchOptions: {
			args: HOST_RULES ? [`--host-resolver-rules=${HOST_RULES}`] : [],
		},
	},
```

- [ ] **Step 4: Run the whole suite through Caddy, and the dashboard gates**

With the servers of Step 2 still up:

```bash
CI=1 E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost E2E_MAIL_DIR=/tmp/etqan-mail \
  E2E_PYTHON=$PWD/../backend/.venv/bin/python npx pnpm@10 exec playwright test
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: 18 passed on the first try (`CI=1` allows one retry; a spec that passes only on the retry is a finding), `journey.spec.ts` included; the gates pass. Then stop the servers (`docker rm -f e2e-edge`, and the Django, preview and marketing processes) and drop `etqan_e2e`.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add e2e playwright.config.ts
git -C dashboard commit -m "test(e2e): the whole v1 journey; helpers can target a deployed stack

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The simulated server, the deploy script and `just staging-sim`

**Files:**
- Create: `infra/staging-sim/Dockerfile`, `infra/staging-sim/entrypoint.sh`, `scripts/deploy-staging.sh` (meta), `scripts/staging-sim.sh` (meta)
- Modify: `justfile` (meta; `deploy`, new `staging-sim`), `.github/workflows/ci.yml` (meta; the `infra-scripts` shellcheck list)

**Interfaces:**
- Consumes: Task 2 (`ship.sh`, overlay), Task 3 (`smoke.sh`), Task 4 (overlay, `.env.staging.example` placeholders, `ETQAN_REGISTRY`, `manage.sh`, `edge-ca.sh`), Task 5 (`seed_staging`), Task 6 (`journey.spec.ts`, `E2E_*`).
- Produces: `scripts/deploy-staging.sh <40-hex sha>` with env `STAGING_SSH_HOST`, `STAGING_SSH_USER`, `STAGING_SSH_PORT`, `STAGING_SSH_KEY_FILE`, `STAGING_KNOWN_HOSTS_FILE`, `STAGING_BASE_URL`, `REGISTRY_TOKEN`, `REGISTRY`, `REGISTRY_USER`, `SEED`, `SMOKE_CONNECT_TO` (Task 8's workflow calls it); `scripts/staging-sim.sh up|build|run|down|all` with `SIM_SHA`, `SIM_DIR`, `SIM_*_PORT`, `TOKENS_TOKEN_FILE`; images tagged `localhost:${SIM_REGISTRY_PORT}/etqan-agency/<name>:<sha>` (Task 8's CI builds them under those tags); containers `etqan-sim-server`, `etqan-sim-registry`, network `etqan-sim`.

- [ ] **Step 1: Write the failing test (the recipe)**

In `justfile` (meta), replace:

```
# Deploy to staging (placeholder)
deploy:
    @echo "Deploy is not wired yet — see STATE.md"
```

with:

```
# Staging deploys from CI on every green master (infra/STAGING.md)
deploy:
    @echo "Staging deploys from CI on every green master; see infra/STAGING.md."

# Prove the staging deploy on a simulated server (privileged Docker-in-Docker)
staging-sim:
    bash scripts/staging-sim.sh all
```

- [ ] **Step 2: Run it to see it fail**

Run: `just staging-sim`
Expected: FAIL: `bash: scripts/staging-sim.sh: No such file or directory`.

- [ ] **Step 3: Implement the server image and the two scripts**

Create `infra/staging-sim/Dockerfile`:

```dockerfile
# The simulated staging server (spec §5), for scripts/staging-sim.sh in the
# meta repo only: sshd and a Docker daemon in one privileged container, laid
# out as a real server is (STAGING.md): a `deploy` user in the docker group
# who owns /opt/etqan, bash, rsync and curl. Pinned, like every image here.
FROM docker:29.8.1-dind

RUN apk add --no-cache bash curl openssh-server rsync \
    && addgroup -S docker 2>/dev/null || true
RUN adduser -D -s /bin/bash deploy \
    && addgroup deploy docker \
    # A locked account (`!`) may not log in even with a key; `*` has no
    # password and may.
    && sed -i 's/^deploy:!/deploy:*/' /etc/shadow \
    && install -d -o deploy -g deploy /opt/etqan \
    && printf '%s\n' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'PermitRootLogin no' \
        'AllowUsers deploy' \
        'AllowTcpForwarding local' \
        > /etc/ssh/sshd_config.d/etqan.conf

COPY entrypoint.sh /usr/local/bin/staging-sim-entrypoint
# The daemon listens only on its socket (no TLS, no TCP): only sshd is exposed.
ENV DOCKER_TLS_CERTDIR=""
EXPOSE 22 443
ENTRYPOINT ["/usr/local/bin/staging-sim-entrypoint"]
```

Create `infra/staging-sim/entrypoint.sh`:

```sh
#!/bin/sh
# Start the simulated server: fresh host keys, the deploy user's one key,
# sshd, then the Docker daemon in the foreground. SIM_REGISTRY is the local
# registry standing in for GHCR (plain HTTP, on the sim's own network).
set -eu
: "${AUTHORIZED_KEY:?set AUTHORIZED_KEY to the deploy public key}"
ssh-keygen -A >/dev/null
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
printf '%s\n' "$AUTHORIZED_KEY" > /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
/usr/sbin/sshd -e
exec dockerd-entrypoint.sh dockerd \
    --host=unix:///var/run/docker.sock \
    --group docker \
    --insecure-registry "${SIM_REGISTRY:-registry:5000}"
```

Create `scripts/deploy-staging.sh` (meta):

```bash
#!/usr/bin/env bash
# Deploy one image tag to a staging server and check it from outside
# (spec §3.2). The deploy-staging CI job and scripts/staging-sim.sh both run
# exactly this:
#   1. copy infra/ to /opt/etqan/ (never .env.production or .active-color);
#   2. log the server in to the registry, when a token is given;
#   3. run ship.sh <sha> there (blue/green);
#   4. seed the demo academy, when SEED=1;
#   5. run infra/scripts/smoke.sh here, against STAGING_BASE_URL.
#
#   scripts/deploy-staging.sh <40-character meta commit SHA>
#
# Environment:
#   STAGING_SSH_HOST, STAGING_SSH_USER   the server and its deploy user
#   STAGING_SSH_PORT                     optional, default 22
#   STAGING_SSH_KEY_FILE                 a file holding the private key
#   STAGING_KNOWN_HOSTS_FILE             a file holding the server's host key(s)
#   STAGING_BASE_URL                     an academy's URL (https://demo.staging.example.com)
#   REGISTRY_TOKEN                       optional: a read-only registry token, sent
#                                        on stdin, never on a command line
#   REGISTRY, REGISTRY_USER              the registry (default ghcr.io) and its user
#   SEED                                 optional, 1 runs seed_staging before the smoke check
#   SMOKE_CONNECT_TO                     optional, passed on to smoke.sh
#
# Nothing here prints a secret: the key and known hosts are files, the token
# goes through a pipe, and the server's .env.production is never read.
set -euo pipefail
set +x

SHA="${1:?Usage: deploy-staging.sh <commit-sha>}"
if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: expected a full 40-character commit SHA, got '${SHA}'." >&2
    exit 2
fi
: "${STAGING_SSH_HOST:?}" "${STAGING_SSH_USER:?}" "${STAGING_SSH_KEY_FILE:?}"
: "${STAGING_KNOWN_HOSTS_FILE:?}" "${STAGING_BASE_URL:?}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SSH=(ssh -i "$STAGING_SSH_KEY_FILE" -p "${STAGING_SSH_PORT:-22}"
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$STAGING_KNOWN_HOSTS_FILE")
TARGET="${STAGING_SSH_USER}@${STAGING_SSH_HOST}"
remote() {
    "${SSH[@]}" "$TARGET" "$@"
}

echo "── 1/5 Copy infra/ to ${TARGET}:/opt/etqan/"
# No --delete: files only the server has (backups, notes) stay. The two
# server-owned files are excluded even if a stray copy sits in infra/.
rsync -rlt --itemize-changes \
    --exclude=.git --exclude=/.env.production --exclude=/.active-color \
    -e "$(printf '%q ' "${SSH[@]}")" \
    "${ROOT}/infra/" "${TARGET}:/opt/etqan/"

echo "── 2/5 Registry login"
if [ -n "${REGISTRY_TOKEN:-}" ]; then
    printf '%s' "$REGISTRY_TOKEN" |
        remote docker login "${REGISTRY:-ghcr.io}" -u "${REGISTRY_USER:?}" --password-stdin
else
    echo "No REGISTRY_TOKEN: using the server's existing registry login."
fi

echo "── 3/5 ship.sh ${SHA}"
remote bash /opt/etqan/scripts/ship.sh "$SHA"

echo "── 4/5 Seed"
if [ "${SEED:-0}" = 1 ]; then
    remote bash /opt/etqan/scripts/manage.sh seed_staging
else
    echo "Not asked to seed."
fi

echo "── 5/5 Smoke check ${STAGING_BASE_URL}"
CA="$(mktemp)"
trap 'rm -f "$CA"' EXIT
remote bash /opt/etqan/scripts/edge-ca.sh > "$CA"
if [ -s "$CA" ]; then
    echo "The edge uses its internal CA; trusting its root for the check."
    export SMOKE_CACERT="$CA"
fi
bash "${ROOT}/infra/scripts/smoke.sh" "$STAGING_BASE_URL"
```

Create `scripts/staging-sim.sh` (meta):

```bash
#!/usr/bin/env bash
# The staging deploy, proven against a simulated server (spec §5).
#   scripts/staging-sim.sh all        up, build, run, then down (`just staging-sim`)
#   scripts/staging-sim.sh up         a local registry and the simulated server
#   scripts/staging-sim.sh build      build the three images, tagged for the registry
#   scripts/staging-sim.sh run        push, deploy A (+ seed, smoke), deploy B under
#                                     a health poll, a failing deploy, then the full
#                                     journey; no secret may show in the output
#   scripts/staging-sim.sh down       remove everything `up` made
# CI runs up, builds with its layer cache (images tagged $(image <name>)), then
# run, and down always.
#
# The server is infra/staging-sim: sshd and Docker-in-Docker, privileged. Its
# registry stand-in is registry:3 with a password, so the deploy's registry
# login is exercised too. Hosts are <sub>.staging.test; the runner reaches the
# server's 443 on 127.0.0.1:$SIM_HTTPS_PORT (curl --connect-to, Chromium
# --host-resolver-rules), so Host headers and SNI are the real names.
#
# Environment (all optional):
#   SIM_SHA          tag A, default the meta repo's HEAD
#   SIM_DIR          work directory (keys, passwords, logs), default /tmp/etqan-staging-sim
#   SIM_HTTPS_PORT, SIM_SSH_PORT, SIM_REGISTRY_PORT, SIM_MAILPIT_PORT
#                    host ports, default 18443, 12222, 15000, 18025 (loopback only)
#   TOKENS_TOKEN_FILE   for `build`: a token that reads the private @etqan/tokens
#                    repo, default `gh auth token`
set -euo pipefail
set +x

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="${SIM_DIR:-/tmp/etqan-staging-sim}"
SIM_HTTPS_PORT="${SIM_HTTPS_PORT:-18443}"
SIM_SSH_PORT="${SIM_SSH_PORT:-12222}"
SIM_REGISTRY_PORT="${SIM_REGISTRY_PORT:-15000}"
SIM_MAILPIT_PORT="${SIM_MAILPIT_PORT:-18025}"
SHA_A="${SIM_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"
# B is A's images under another tag: a second deploy of the same code.
SHA_B="$(printf '%s-b' "$SHA_A" | sha1sum | cut -c1-40)"
BASE_DOMAIN=staging.test
ACADEMY_URL="https://demo.${BASE_DOMAIN}"
NET=etqan-sim
SERVER=etqan-sim-server
REGISTRY_CONTAINER=etqan-sim-registry
IMAGES=(backend dashboard marketing)

# The name a host-side tag pushes to; the server pulls the same repository
# as registry:5000/etqan-agency/<name> (ETQAN_REGISTRY in its env).
image() {
    echo "localhost:${SIM_REGISTRY_PORT}/etqan-agency/$1"
}

ssh_opts() {
    printf '%s\n' -i "${SIM_DIR}/id_ed25519" -p "$SIM_SSH_PORT" -o IdentitiesOnly=yes \
        -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="${SIM_DIR}/known_hosts"
}

on_server() {
    local opts
    mapfile -t opts < <(ssh_opts)
    # shellcheck disable=SC2029 # the arguments are the remote command line
    ssh "${opts[@]}" deploy@127.0.0.1 "$@"
}

up() {
    mkdir -p "$SIM_DIR"
    chmod 700 "$SIM_DIR"
    rm -f "${SIM_DIR}/id_ed25519" "${SIM_DIR}/id_ed25519.pub"
    ssh-keygen -q -t ed25519 -N "" -C etqan-staging-sim -f "${SIM_DIR}/id_ed25519"
    # The registry's one user, with a password nobody sees.
    (umask 077 && openssl rand -hex 24 > "${SIM_DIR}/registry-password")
    printf '%s\n' "$(cat "${SIM_DIR}/registry-password")" |
        docker run -i --rm caddy:2.11.4-alpine caddy hash-password |
        sed 's/^/sim:/' > "${SIM_DIR}/htpasswd"

    docker network create "$NET" >/dev/null
    docker run -d --name "$REGISTRY_CONTAINER" --network "$NET" --network-alias registry \
        -p "127.0.0.1:${SIM_REGISTRY_PORT}:5000" \
        -v "${SIM_DIR}/htpasswd:/auth/htpasswd:ro" \
        -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=etqan-sim \
        -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
        registry:3.1.2 >/dev/null

    docker build -q -t etqan-staging-sim "${ROOT}/infra/staging-sim" >/dev/null
    docker run -d --privileged --name "$SERVER" --network "$NET" \
        -p "127.0.0.1:${SIM_SSH_PORT}:22" -p "127.0.0.1:${SIM_HTTPS_PORT}:443" \
        -e AUTHORIZED_KEY="$(cat "${SIM_DIR}/id_ed25519.pub")" \
        etqan-staging-sim >/dev/null
    for _ in $(seq 1 60); do
        docker exec "$SERVER" docker info >/dev/null 2>&1 && break
        sleep 1
    done
    docker exec "$SERVER" docker info >/dev/null
    # known_hosts from the server's own key, as STAGING_KNOWN_HOSTS would be.
    echo "[127.0.0.1]:${SIM_SSH_PORT} $(docker exec "$SERVER" cat /etc/ssh/ssh_host_ed25519_key.pub | cut -d' ' -f1-2)" \
        > "${SIM_DIR}/known_hosts"
    echo "Simulated server up: ssh on 127.0.0.1:${SIM_SSH_PORT}, https on 127.0.0.1:${SIM_HTTPS_PORT}."
}

build() {
    local token_file="${TOKENS_TOKEN_FILE:-}" cleanup=0 name
    if [ -z "$token_file" ]; then
        token_file="$(mktemp)"
        cleanup=1
        env -u GH_TOKEN -u GITHUB_TOKEN gh auth token > "$token_file"
    fi
    docker build -q -t "$(image backend):${SHA_A}" "${ROOT}/backend" >/dev/null
    for name in dashboard marketing; do
        docker build -q --secret "id=tokens_token,src=${token_file}" \
            -t "$(image "$name"):${SHA_A}" "${ROOT}/${name}" >/dev/null
    done
    if [ "$cleanup" = 1 ]; then rm -f "$token_file"; fi
    echo "Built the three images as ${SHA_A}."
}

# The server's .env.production, from .env.staging.example: fresh secrets,
# the test base domain and the local registry. It is written once, on the
# server only, and any CHANGE_ME left over fails the run (the template must
# stay complete).
write_env() {
    local env
    env="$(sed \
        -e "s|CHANGE_ME_SECRET_KEY|$(openssl rand -hex 32)|" \
        -e "s|CHANGE_ME_DB_PASSWORD|$(openssl rand -hex 16)|g" \
        -e "s|CHANGE_ME_S3_SECRET|$(openssl rand -hex 16)|" \
        -e "s|CHANGE_ME_DEMO_PASSWORD|$(openssl rand -hex 16)|" \
        -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" \
        -e "s|^ETQAN_REGISTRY=.*|ETQAN_REGISTRY=registry:5000/etqan-agency|" \
        "${ROOT}/infra/.env.staging.example")"
    if grep -v '^#' <<< "$env" | grep -q CHANGE_ME; then
        echo "ERROR: .env.staging.example has a placeholder this script does not fill." >&2
        exit 1
    fi
    on_server 'umask 077 && mkdir -p /opt/etqan && cat > /opt/etqan/.env.production' <<< "$env"
}

deploy() { # deploy <sha> <seed 0|1>
    STAGING_SSH_HOST=127.0.0.1 STAGING_SSH_USER=deploy STAGING_SSH_PORT="$SIM_SSH_PORT" \
        STAGING_SSH_KEY_FILE="${SIM_DIR}/id_ed25519" \
        STAGING_KNOWN_HOSTS_FILE="${SIM_DIR}/known_hosts" \
        STAGING_BASE_URL="$ACADEMY_URL" \
        REGISTRY=registry:5000 REGISTRY_USER=sim \
        REGISTRY_TOKEN="$(cat "${SIM_DIR}/registry-password")" \
        SEED="$2" SMOKE_CONNECT_TO="::127.0.0.1:${SIM_HTTPS_PORT}" \
        bash "${ROOT}/scripts/deploy-staging.sh" "$1"
}

push() { # push <sha>: A's images, under the tag <sha>
    local name
    for name in "${IMAGES[@]}"; do
        if [ "$1" != "$SHA_A" ]; then
            docker tag "$(image "$name"):${SHA_A}" "$(image "$name"):$1"
        fi
        docker push -q "$(image "$name"):$1" >/dev/null
    done
}

run_steps() {
    local codes before after
    docker login "localhost:${SIM_REGISTRY_PORT}" -u sim --password-stdin \
        < "${SIM_DIR}/registry-password" >/dev/null
    push "$SHA_A"
    write_env

    echo "━━ Deploy A (${SHA_A}), seed, smoke"
    deploy "$SHA_A" 1

    echo "━━ Uploads: the S3 store takes a file and serves it publicly"
    on_server bash /opt/etqan/scripts/manage.sh shell -c \
        "'from django.core.files.base import ContentFile; from django.core.files.storage import default_storage as s; s.save(\"tenants/staging-sim/check.txt\", ContentFile(b\"ok\"))'"
    [ "$(on_server docker exec etqan-s3-1 curl -s \
        "http://127.0.0.1:9000/etqan-staging-media/tenants/staging-sim/check.txt")" = ok ]

    echo "━━ Deploy B (${SHA_B}) while /health/ready/ is polled"
    push "$SHA_B"
    on_server bash /opt/etqan/scripts/edge-ca.sh > "${SIM_DIR}/root.crt"
    before="$(on_server cat /opt/etqan/.active-color)"
    : > "${SIM_DIR}/polls"
    rm -f "${SIM_DIR}/stop-polling"
    (
        while [ ! -f "${SIM_DIR}/stop-polling" ]; do
            curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 \
                --cacert "${SIM_DIR}/root.crt" --connect-to "::127.0.0.1:${SIM_HTTPS_PORT}" \
                "${ACADEMY_URL}/health/ready/" >> "${SIM_DIR}/polls" || true
            sleep 0.2
        done
    ) &
    local poller=$!
    deploy "$SHA_B" 0
    touch "${SIM_DIR}/stop-polling"
    wait "$poller"
    after="$(on_server cat /opt/etqan/.active-color)"
    codes="$(sort "${SIM_DIR}/polls" | uniq -c | tr -s ' ')"
    echo "Colour ${before} → ${after}; polls:${codes}"
    if [ "$before" = "$after" ]; then
        echo "ERROR: the active colour did not flip." >&2
        exit 1
    fi
    if [ "$(wc -l < "${SIM_DIR}/polls")" -lt 50 ] || grep -qv '^200$' "${SIM_DIR}/polls"; then
        echo "ERROR: a health poll during the switch was not 200 (or too few ran)." >&2
        exit 1
    fi

    echo "━━ A deploy that fails (no images for its SHA) leaves ${after} serving"
    if deploy 0000000000000000000000000000000000000000 0; then
        echo "ERROR: a deploy of images that do not exist succeeded." >&2
        exit 1
    fi
    if [ "$(on_server cat /opt/etqan/.active-color)" != "$after" ]; then
        echo "ERROR: the failed deploy changed the active colour." >&2
        exit 1
    fi
    [ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "${SIM_DIR}/root.crt" \
        --connect-to "::127.0.0.1:${SIM_HTTPS_PORT}" "${ACADEMY_URL}/health/ready/")" = 200 ]
    echo "Still serving from ${after}."

    echo "━━ The full journey against the deployed stack"
    local opts tunnel
    mapfile -t opts < <(ssh_opts)
    ssh "${opts[@]}" -N -L "127.0.0.1:${SIM_MAILPIT_PORT}:127.0.0.1:8025" deploy@127.0.0.1 &
    tunnel=$!
    sleep 2
    (
        cd "${ROOT}/dashboard"
        E2E_BASE_URL="https://${BASE_DOMAIN}" \
            E2E_MAILPIT_URL="http://127.0.0.1:${SIM_MAILPIT_PORT}" \
            E2E_MANAGE="ssh ${opts[*]} deploy@127.0.0.1 bash /opt/etqan/scripts/manage.sh" \
            E2E_HOST_RESOLVER_RULES="MAP *.${BASE_DOMAIN} 127.0.0.1:${SIM_HTTPS_PORT}, MAP ${BASE_DOMAIN} 127.0.0.1:${SIM_HTTPS_PORT}" \
            E2E_IGNORE_HTTPS_ERRORS=1 \
            npx pnpm@10 exec playwright test e2e/journey.spec.ts --retries=0
    ) || { kill "$tunnel"; exit 1; }
    kill "$tunnel"
}

# Fails when any secret the run handled shows in its output: the registry
# password and the server's generated secrets (read on the server, never
# printed).
no_secret_in() {
    local secret found=0
    while IFS= read -r secret; do
        if [ -n "$secret" ] && grep -qF -- "$secret" "$1"; then
            found=1
        fi
    done < <(
        cat "${SIM_DIR}/registry-password"
        on_server "sed -n -E 's/^(DJANGO_SECRET_KEY|POSTGRES_PASSWORD|AWS_SECRET_ACCESS_KEY|DJANGO_STAGING_DEMO_PASSWORD)=//p' /opt/etqan/.env.production"
    )
    if [ "$found" = 1 ]; then
        echo "ERROR: a secret appeared in the run's output." >&2
        return 1
    fi
    echo "No secret in the run's output."
}

run() {
    local status=0
    run_steps 2>&1 | tee "${SIM_DIR}/run.log" || status=$?
    no_secret_in "${SIM_DIR}/run.log"
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    echo "Staging simulation passed."
}

# The server, the registry and the work directory. The built images stay,
# so CI's retry can run again without rebuilding.
down() {
    docker rm -fv "$SERVER" "$REGISTRY_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker logout "localhost:${SIM_REGISTRY_PORT}" >/dev/null 2>&1 || true
    rm -rf "$SIM_DIR"
    echo "Simulated server removed."
}

remove_images() {
    local name
    for name in "${IMAGES[@]}"; do
        docker image ls -q "$(image "$name")" | sort -u | xargs -r docker rmi -f >/dev/null 2>&1 || true
    done
}

case "${1:-all}" in
    up) up ;;
    build) build ;;
    run) run ;;
    down) down ;;
    all)
        trap 'down; remove_images' EXIT
        up
        build
        run
        ;;
    *)
        echo "Usage: staging-sim.sh [all|up|build|run|down]" >&2
        exit 2
        ;;
esac
```

```bash
chmod +x infra/staging-sim/entrypoint.sh scripts/deploy-staging.sh scripts/staging-sim.sh
```

In `.github/workflows/ci.yml` (meta), replace:

```yaml
            infra/scripts/*.sh infra/scripts/tests/*.sh infra/scripts/tests/fakebin/*
```

with:

```yaml
            infra/scripts/*.sh infra/scripts/tests/*.sh infra/scripts/tests/fakebin/* \
            infra/staging-sim/entrypoint.sh scripts/deploy-staging.sh scripts/staging-sim.sh
```

Why each part is shaped the way it is: D2 (the server pulls from `registry:5000` through `ETQAN_REGISTRY`), D8 (`staging.test` through `--connect-to` and resolver rules), D9 (the smoke check trusts the edge's root; Playwright skips the check only here), D12/D13 (deploy A seeds before its smoke check), D14 (rsync). The registry has a password (`caddy hash-password`, fed on stdin) so the deploy's `docker login --password-stdin` path runs; `.env.production` is generated on the server from `.env.staging.example`, so a placeholder the template gains but the script does not fill fails the run.

- [ ] **Step 4: Run the simulation, and the edge cases by hand**

```bash
shellcheck infra/staging-sim/entrypoint.sh scripts/deploy-staging.sh scripts/staging-sim.sh
actionlint .github/workflows/ci.yml
just staging-sim
```

Expected: no shellcheck or actionlint output, then (about 10 minutes the first time; the edge image is built with xcaddy inside the server) in order:
- deploy A: `Overlay: staging`, `Current: none → New: green`, `created: demo.staging.test`, six `ok` smoke lines and `Smoke check passed`;
- the upload check passes silently;
- deploy B: `Deploy complete: green → blue`, then `Colour green → blue; polls: <n> 200` with n ≥ 50 and only `200`;
- the failing deploy: `not found` from the pull, then `Still serving from blue.`;
- `1 passed` for `journey.spec.ts`, `No secret in the run's output.`, `Staging simulation passed.`, `Simulated server removed.`

Then:

```bash
bash scripts/deploy-staging.sh 'abc; rm -rf /'; echo "exit=$?"   # before any ssh: "expected a full 40-character commit SHA", exit=2
docker ps -a --filter name=etqan-sim -q; docker network ls --filter name=etqan-sim -q   # both empty
```

- [ ] **Step 5: Commit (infra, then meta)**

```bash
git -C infra add staging-sim
git -C infra commit -m "feat(staging-sim): a simulated staging server (sshd and Docker-in-Docker)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git add scripts/deploy-staging.sh scripts/staging-sim.sh justfile .github/workflows/ci.yml
git commit -m "feat: deploy-staging.sh and the staging simulation (just staging-sim)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: CI builds and pushes the images, runs the simulation and deploys staging

**Files:**
- Create: `.github/workflows/deploy-staging.yml`, `scripts/staging-sim-needed.sh` (meta)
- Modify: `.github/workflows/ci.yml` (meta; `infra-scripts` shellcheck list; new jobs `images`, `sim-needed`, `staging-sim`, `deploy-staging` at the end)

**Interfaces:**
- Consumes: Task 7's `deploy-staging.sh`, `staging-sim.sh up|run|down` and image tag names; the existing jobs `backend`, `dashboard`, `marketing`, `caddy`, `e2e`, Task 3's `infra-scripts`.
- Produces: GHCR images `ghcr.io/etqan-agency/<name>:<sha>` and `:master` on `master` pushes; `scripts/staging-sim-needed.sh <base-sha>` printing `true` or `false`; the workflow `Deploy staging` (inputs `sha`, `seed`), gated on `secrets.STAGING_SSH_HOST`, reading `STAGING_SSH_USER`, `STAGING_SSH_KEY`, `STAGING_KNOWN_HOSTS`, `STAGING_BASE_URL`, `GHCR_READ_TOKEN`.

- [ ] **Step 1: Write the failing test (the gate's four cases)**

```bash
cat > /tmp/sim-needed-check.sh <<'EOF'
set -euo pipefail
META="$PWD"; T=$(mktemp -d); git clone -q "$META" "$T/m"; cd "$T/m"
git -c protocol.file.allow=always submodule update -q --init backend infra
c() { git -c user.email=t@t -c user.name=t commit -q "$@"; }
base=$(git rev-parse HEAD)
echo x >> STATE.md; c -am docs;                                           r1=$(bash "$META/scripts/staging-sim-needed.sh" "$base")
(cd backend && echo "# x" >> manage.py && c -am x); git add backend; c -m b1; r2=$(bash "$META/scripts/staging-sim-needed.sh" "$base")
(cd backend && echo "# x" >> Dockerfile && c -am x); git add backend; c -m b2; r3=$(bash "$META/scripts/staging-sim-needed.sh" "$base")
git reset -q --hard "$base"; (cd infra && c --allow-empty -m x); git add infra; c -m i; r4=$(bash "$META/scripts/staging-sim-needed.sh" "$base")
cd /; rm -rf "$T"
echo "docs=$r1 backend-code=$r2 backend-dockerfile=$r3 infra=$r4"
[ "$r1 $r2 $r3 $r4" = "false false true true" ] && echo GATE-OK
EOF
bash /tmp/sim-needed-check.sh
```

Expected: FAIL (`bash: …/scripts/staging-sim-needed.sh: No such file or directory`).

- [ ] **Step 2: Write the gate script and see the check pass**

Create `scripts/staging-sim-needed.sh` (meta):

```bash
#!/usr/bin/env bash
# Does a pull request need the staging simulation (spec §5)? Prints true or
# false. True when the meta diff since <base> touches the infra pointer, the
# workflows, the Caddyfiles or the deploy and simulation scripts, or when a
# backend, dashboard or marketing pointer moves what shapes its image: the
# Dockerfile, .dockerignore, nginx.conf or requirements/. Master pushes
# always run the simulation; the workflow does not ask.
#   scripts/staging-sim-needed.sh <base-sha>
set -euo pipefail

BASE="${1:?Usage: staging-sim-needed.sh <base-sha>}"
changed="$(git diff --name-only "$BASE" HEAD)"
if grep -qE '^(infra$|\.github/workflows/|caddy/|scripts/(deploy-staging|staging-sim))' <<< "$changed"; then
    echo true
    exit 0
fi
for repo in backend dashboard marketing; do
    grep -qx "$repo" <<< "$changed" || continue
    old="$(git rev-parse "${BASE}:${repo}")"
    git -C "$repo" cat-file -e "${old}^{commit}" 2>/dev/null ||
        git -C "$repo" fetch -q --depth=1 origin "$old"
    if git -C "$repo" diff --name-only "$old" HEAD |
        grep -qE '^(Dockerfile|\.dockerignore|nginx\.conf|requirements/)'; then
        echo true
        exit 0
    fi
done
echo false
```

```bash
chmod +x scripts/staging-sim-needed.sh
bash /tmp/sim-needed-check.sh
shellcheck scripts/staging-sim-needed.sh
```

Expected: `docs=false backend-code=false backend-dockerfile=true infra=true` and `GATE-OK`.

- [ ] **Step 3: Implement the jobs and the deploy workflow**

In `.github/workflows/ci.yml` (meta), replace:

```yaml
            infra/staging-sim/entrypoint.sh scripts/deploy-staging.sh scripts/staging-sim.sh
```

with:

```yaml
            infra/staging-sim/entrypoint.sh scripts/deploy-staging.sh scripts/staging-sim.sh \
            scripts/staging-sim-needed.sh
```

Append to the end of `.github/workflows/ci.yml` (after the `security` job):

```yaml
  # Spec §3.1: every image, built after the tests pass. Pull requests build
  # only (a broken Dockerfile fails the PR); master pushes <meta-sha> and
  # :master to GHCR (private). The backend image needs no build arguments
  # (its default target is production); the frontends read the private
  # @etqan/tokens repo through the tokens_token build secret.
  images:
    needs: [backend, dashboard, marketing, caddy, e2e, infra-scripts]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      fail-fast: false
      matrix:
        name: [backend, dashboard, marketing]
    env:
      PUSH: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
    steps:
      - uses: actions/checkout@v7
        with: { submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - uses: docker/setup-buildx-action@v4
      - if: env.PUSH == 'true'
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v7
        with:
          context: ${{ matrix.name }}
          push: ${{ env.PUSH == 'true' }}
          tags: |
            ghcr.io/etqan-agency/${{ matrix.name }}:${{ github.sha }}
            ghcr.io/etqan-agency/${{ matrix.name }}:master
          # Links the package to this repository, so this workflow may push it.
          labels: org.opencontainers.image.source=https://github.com/${{ github.repository }}
          secrets: tokens_token=${{ secrets.TOKENS_REPO_TOKEN }}
          cache-from: type=gha,scope=${{ matrix.name }}
          cache-to: type=gha,mode=max,scope=${{ matrix.name }}

  # Spec §5: which pull requests need the staging simulation.
  sim-needed:
    runs-on: ubuntu-latest
    outputs:
      run: ${{ steps.check.outputs.run }}
    steps:
      - uses: actions/checkout@v7
        with: { fetch-depth: 0, submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - id: check
        env:
          EVENT: ${{ github.event_name }}
          BASE: ${{ github.event.pull_request.base.sha }}
        run: |
          if [ "$EVENT" = pull_request ]; then
            echo "run=$(bash scripts/staging-sim-needed.sh "$BASE")" >> "$GITHUB_OUTPUT"
          else
            echo "run=true" >> "$GITHUB_OUTPUT"
          fi

  # Spec §5: the staging deploy against a simulated server (sshd and
  # Docker-in-Docker, privileged, started with docker run: a service
  # container cannot be built from this repo). Two blue/green deploys under
  # a health poll, the smoke check, seed_staging and the full journey. One
  # retry of the whole run, never of a step.
  staging-sim:
    needs: [sim-needed, images]
    if: needs.sim-needed.outputs.run == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 45
    env:
      SIM_SHA: ${{ github.sha }}
      SIM_DIR: ${{ github.workspace }}/../staging-sim
    steps:
      # The server pulls about 3 GB, and ship.sh refuses to start with less
      # than 5 GB free: drop toolchains this job never uses.
      - name: Free disk space
        run: |
          sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL
          df -h /
      - uses: actions/checkout@v7
        with: { submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - uses: pnpm/action-setup@v6
        with: { version: 10 }
      - uses: actions/setup-node@v7
        with: { node-version: "${{ env.NODE_VERSION }}", cache: pnpm, cache-dependency-path: dashboard/pnpm-lock.yaml }
      - name: Configure git auth for private @etqan/tokens
        run: |
          git config --global url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "https://github.com/"
          git config --global --add url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "git@github.com:"
          git config --global --add url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "ssh://git@github.com/"
      - name: Playwright (the journey runs from here)
        working-directory: dashboard
        run: |
          pnpm install --frozen-lockfile
          pnpm exec playwright install --with-deps chromium
      - name: Simulated server and registry up
        run: bash scripts/staging-sim.sh up
      - uses: docker/setup-buildx-action@v4
      # The images job's layer cache makes these rebuilds cheap; they load
      # into the runner's docker, tagged for the local registry.
      - uses: docker/build-push-action@v7
        with:
          context: backend
          load: true
          tags: localhost:15000/etqan-agency/backend:${{ github.sha }}
          cache-from: type=gha,scope=backend
      - uses: docker/build-push-action@v7
        with:
          context: dashboard
          load: true
          tags: localhost:15000/etqan-agency/dashboard:${{ github.sha }}
          secrets: tokens_token=${{ secrets.TOKENS_REPO_TOKEN }}
          cache-from: type=gha,scope=dashboard
      - uses: docker/build-push-action@v7
        with:
          context: marketing
          load: true
          tags: localhost:15000/etqan-agency/marketing:${{ github.sha }}
          secrets: tokens_token=${{ secrets.TOKENS_REPO_TOKEN }}
          cache-from: type=gha,scope=marketing
      - name: Deploy twice, seed, smoke and walk the journey
        run: |
          bash scripts/staging-sim.sh run && exit 0
          echo "::warning::The staging simulation failed; retrying the whole run once."
          bash scripts/staging-sim.sh down
          bash scripts/staging-sim.sh up
          bash scripts/staging-sim.sh run
      - if: failure()
        name: Server logs
        run: |
          docker exec etqan-sim-server sh -c 'cd /opt/etqan && docker compose -f docker-compose.production.yml \
            -f docker-compose.staging.yml --env-file .env.production logs --no-color --tail 150' || true
      - if: always()
        run: bash scripts/staging-sim.sh down

  # Spec §3.2: every green master is deployed to staging, once a server
  # exists; without the STAGING_SSH_HOST secret the job skips its steps and
  # succeeds. Manual runs (rollback) use the same workflow.
  deploy-staging:
    needs: [images, staging-sim]
    if: github.event_name == 'push' && github.ref == 'refs/heads/master'
    uses: ./.github/workflows/deploy-staging.yml
    with:
      sha: ${{ github.sha }}
    secrets: inherit
```

Create `.github/workflows/deploy-staging.yml`:

```yaml
name: Deploy staging

# Spec §3.2. Called by CI for every green master push, and run by hand to
# roll back (or forward) to any master commit whose images are in GHCR.
# Without the STAGING_SSH_HOST secret every step after the first is skipped
# and the job succeeds: master stays green before a server exists.
on:
  workflow_call:
    inputs:
      sha:
        type: string
        required: true
      seed:
        type: boolean
        default: false
  workflow_dispatch:
    inputs:
      sha:
        description: Meta commit SHA (40 characters) whose images to deploy
        type: string
        required: true
      seed:
        description: Run seed_staging (creates the demo academy if it is missing)
        type: boolean
        default: false

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    # One deploy at a time, and a running one is never cancelled.
    concurrency:
      group: staging
      cancel-in-progress: false
    timeout-minutes: 30
    steps:
      # Job-level `if:` cannot read secrets; this step can, and every other
      # step is conditional on its answer.
      - name: Is staging configured?
        id: gate
        env:
          HOST: ${{ secrets.STAGING_SSH_HOST }}
        run: |
          if [ -z "$HOST" ]; then
            echo "::notice title=Staging not configured::No STAGING_SSH_HOST secret, so nothing was deployed. See infra/STAGING.md."
            echo "configured=false" >> "$GITHUB_OUTPUT"
          else
            echo "configured=true" >> "$GITHUB_OUTPUT"
          fi
      - if: steps.gate.outputs.configured == 'true'
        uses: actions/checkout@v7
        with:
          ref: ${{ inputs.sha }}
          submodules: recursive
          token: ${{ secrets.SUBMODULE_TOKEN }}
      - name: SSH key and known hosts, as files
        if: steps.gate.outputs.configured == 'true'
        env:
          KEY: ${{ secrets.STAGING_SSH_KEY }}
          KNOWN_HOSTS: ${{ secrets.STAGING_KNOWN_HOSTS }}
        run: |
          set +x
          umask 077
          printf '%s\n' "$KEY" > "$RUNNER_TEMP/staging_key"
          printf '%s\n' "$KNOWN_HOSTS" > "$RUNNER_TEMP/staging_known_hosts"
      - name: Deploy, then smoke-check
        if: steps.gate.outputs.configured == 'true'
        env:
          DEPLOY_SHA: ${{ inputs.sha }}
          STAGING_SSH_HOST: ${{ secrets.STAGING_SSH_HOST }}
          STAGING_SSH_USER: ${{ secrets.STAGING_SSH_USER }}
          STAGING_SSH_KEY_FILE: ${{ runner.temp }}/staging_key
          STAGING_KNOWN_HOSTS_FILE: ${{ runner.temp }}/staging_known_hosts
          STAGING_BASE_URL: ${{ secrets.STAGING_BASE_URL }}
          REGISTRY_TOKEN: ${{ secrets.GHCR_READ_TOKEN }}
          REGISTRY_USER: ${{ github.repository_owner }}
          SEED: ${{ inputs.seed && '1' || '0' }}
        run: bash scripts/deploy-staging.sh "$DEPLOY_SHA"
      - name: Remove the key
        if: always() && steps.gate.outputs.configured == 'true'
        run: rm -f "$RUNNER_TEMP/staging_key" "$RUNNER_TEMP/staging_known_hosts"
```

- [ ] **Step 4: Lint the workflows, and check the skip by reading**

```bash
actionlint .github/workflows/ci.yml .github/workflows/deploy-staging.yml
grep -c "if: steps.gate.outputs.configured == 'true'" .github/workflows/deploy-staging.yml   # expect 3
grep -c "if: always() && steps.gate.outputs.configured == 'true'" .github/workflows/deploy-staging.yml   # expect 1
```

Expected: no actionlint output; `3` and `1`: every step after the gate is conditional on it, so without `STAGING_SSH_HOST` the job runs one step and succeeds. The hosted run is checked in Task 9.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/deploy-staging.yml scripts/staging-sim-needed.sh
git commit -m "ci: build and push images, run the staging simulation, deploy staging

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: `STAGING.md`, `STATE.md`, and the pull requests

**Files:**
- Create: `infra/STAGING.md`
- Modify: `infra/CLAUDE.md`, `STATE.md` (meta), submodule pointers (meta, after merge)

**Interfaces:**
- Consumes: everything above.
- Produces: the operator's guide (D16) and the project state.

- [ ] **Step 1: Write the guide**

Create `infra/STAGING.md`:

````markdown
# Staging: going live on a real server

Every green `master` is built into images and pushed to GHCR; the
`deploy-staging` job then deploys them to the staging server. Until the
staging secrets exist, that job skips its steps and succeeds. The same
deploy runs on every `master` push against a simulated server
(`scripts/staging-sim.sh` in the meta repo). Going live is configuration
only: a server, DNS, secrets and `.env.production`.

## 1. The server

- Linux with Docker Engine and the compose plugin (`docker compose version`),
  plus `bash`, `rsync` and `curl`.
- Disk: at least 40 GB. `ship.sh` refuses to start a deploy with less than
  5 GB free on `/var/lib/docker`, and keeps the last 24 hours of images for
  rollback.
- Ports 80 and 443 open to the internet; nothing else (Mailpit listens on
  the server's 127.0.0.1:8025 only).
- A `deploy` user in the `docker` group that logs in with an SSH key only,
  and owns `/opt/etqan`:

  ```bash
  sudo adduser --disabled-password deploy && sudo usermod -aG docker deploy
  sudo install -d -o deploy -g deploy /opt/etqan
  ```

- The layout after the first deploy (CI copies everything but the two
  server-owned files):

  ```
  /opt/etqan/
    .env.production            yours, chmod 600; CI never reads or overwrites it
    .active-color              written by ship.sh (blue or green)
    docker-compose.production.yml  docker-compose.staging.yml
    caddy/  scripts/  monitoring/  staging-sim/  STAGING.md  ...
  ```

## 2. DNS

With `<domain>` the Etqan zone and `staging.<domain>` the staging base
domain, point both records at the server's public IP:

- `staging.<domain>` (A): the staff admin;
- `*.staging.<domain>` (A): every academy (`demo.staging.<domain>`, ...).

With `TLS_MODE=internal` no DNS provider API is needed. With Cloudflare
(section 7), both records must be DNS-only (grey cloud).

## 3. Secrets

In the meta repo, Settings → Environments → `staging` (create it), add:

| Secret | Value |
|---|---|
| `STAGING_SSH_USER` | `deploy` |
| `STAGING_SSH_KEY` | the private key whose public half is in `~deploy/.ssh/authorized_keys` (a key made for CI only: `ssh-keygen -t ed25519 -N "" -f staging_ci`) |
| `STAGING_KNOWN_HOSTS` | the server's host key line, from a trusted shell on the server: `echo "<host> $(cut -d' ' -f1-2 /etc/ssh/ssh_host_ed25519_key.pub)"` (for a port other than 22: `[<host>]:<port> ...`) |
| `GHCR_READ_TOKEN` | a classic personal access token with `read:packages` only, from an org member with access to the three packages |
| `STAGING_BASE_URL` | `https://demo.staging.<domain>` |
| `STAGING_SSH_HOST` | the server's IP or name. **Add this one last**: it switches the deploy on |

If the organisation's plan offers no environments for private repositories,
add the same names as repository secrets; the workflow reads them the same
way.

GHCR: the first `master` push creates `ghcr.io/etqan-agency/{backend,dashboard,marketing}`,
linked to the meta repo. If a package of that name already exists, open its
settings → Manage Actions access, and give `etqan_tutor` the Write role.

## 4. `.env.production` for staging

On the server, as `deploy`:

```bash
cd /opt/etqan
# From a checkout of infra/: copy .env.staging.example here first.
cp .env.staging.example .env.production && chmod 600 .env.production
```

Then edit it: set `BASE_DOMAIN=staging.<domain>`, replace every
`CHANGE_ME_*` with a new random value (`openssl rand -hex 32`), and set
`DJANGO_DEFAULT_FROM_EMAIL`. `ETQAN_OVERLAY=staging` makes `ship.sh` add
`docker-compose.staging.yml` (an S3 store and Mailpit), and `TLS_MODE=internal`
makes Caddy issue every certificate from its own CA. The file never leaves
the server.

## 5. The first deploy

1. With every secret but `STAGING_SSH_HOST` in place, add `STAGING_SSH_HOST`.
2. Actions → Deploy staging → Run workflow, with `sha` the latest `master`
   commit and `seed` checked. It copies `infra/`, logs the server in to
   GHCR, runs `ship.sh`, creates the `demo` academy (`seed_staging`: the
   dev data, its admin `admin@demo.test` with `DJANGO_STAGING_DEMO_PASSWORD`),
   and runs the smoke check.
3. From then on, every green `master` deploys by itself, without seeding.

Until the first seeded run, an automatic deploy fails its smoke check on the
academy's home page (no `demo` academy yet): run step 2.

Browsers do not trust the internal CA. To trust it on a tester's machine:
`ssh deploy@<server> bash /opt/etqan/scripts/edge-ca.sh > etqan-staging-root.crt`,
then import that file as a trusted root.

Useful on the server:

- a management command in the live colour: `bash /opt/etqan/scripts/manage.sh <command>`;
- the mail staging sent: `ssh -L 8025:127.0.0.1:8025 deploy@<server>`, then
  open http://localhost:8025.

## 6. Rollback

Actions → Deploy staging → Run workflow, with `sha` an earlier `master`
commit (its images stay in GHCR). It copies that commit's `infra/` and runs
`ship.sh` with its images: the same blue/green switch. A deploy that fails
before the switch leaves the old colour serving; one that fails its smoke
check after the switch is rolled back the same way. Migrations are never
reversed, so every migration must stay compatible with the previous
release (expand first, contract in a later release).

Deploys run one at a time (`concurrency: staging`). GitHub keeps only the
newest waiting run in that group, so start a rollback when no other deploy
is waiting.

## 7. Toward production settings

Each is a change to `.env.production` on the server and the next deploy:

- **Cloudflare TLS**: `TLS_MODE=cloudflare`, a real `CF_API_TOKEN` (Zone:DNS:Edit
  on the zone) and the grey-cloud records of section 2. Caddy then gets the
  wildcard certificate by DNS-01 and custom domains on demand, as in
  production, and browsers trust it.
- **Real S3**: the `DJANGO_S3_*` and `AWS_*` values of
  `.env.production.example` (bucket, region, keys, public-read policy on
  `tenants/*`). Uploaded images then load in the browser; with the overlay's
  store they are linked at its in-network address and do not.
- **Real email**: the SES `DJANGO_EMAIL_*` values of `.env.production.example`.
  Staging then emails real people: do it only on purpose.
- **No overlay**: with all three done, remove `ETQAN_OVERLAY` and the server
  runs production's compose file alone.

## 8. What the simulated server does not prove

The simulated server runs the same `ship.sh`, compose files and images,
but it cannot show:

- DNS records and public reachability of ports 80 and 443;
- a Cloudflare DNS-01 certificate (it runs `TLS_MODE=internal`);
- the GHCR login with `GHCR_READ_TOKEN` (it logs in to a local registry the
  same way);
- the server's disk, memory and Docker versions.

Check those on the first real deploy.
````

In `infra/CLAUDE.md`, replace:

```markdown
- `scripts/ship.sh` — blue-green deploy orchestration (called by CI via SSH)
- `monitoring/` — Prometheus, Grafana, Loki, Uptime Kuma
```

with:

```markdown
- `scripts/ship.sh` — blue-green deploy orchestration (called by CI via SSH); `ETQAN_OVERLAY=staging` in `.env.production` adds `docker-compose.staging.yml`
- `docker-compose.staging.yml` — staging overlay: an S3 store (RustFS) and Mailpit; `.env.staging.example` is its env
- `scripts/smoke.sh` — the post-deploy smoke check; `scripts/manage.sh` (manage.py in the live colour), `scripts/edge-ca.sh` (internal CA root)
- `scripts/tests/` — ship, smoke and compose tests (`bash scripts/tests/<name>_test.sh`)
- `staging-sim/` — the simulated staging server used by the meta repo's `scripts/staging-sim.sh`
- `STAGING.md` — taking staging live on a real server
- `monitoring/` — Prometheus, Grafana, Loki, Uptime Kuma
```

and replace:

```markdown
- `caddy/Caddyfile` — edge config: per-academy path routing, wildcard cert via Cloudflare DNS-01, on-demand TLS for custom domains gated by Django's `/internal/tls-allowed`
```

with:

```markdown
- `caddy/Caddyfile` — edge config: per-academy path routing, wildcard cert via Cloudflare DNS-01, on-demand TLS for custom domains gated by Django's `/internal/tls-allowed`; `TLS_MODE=internal` uses Caddy's own CA instead (staging)
```

- [ ] **Step 2: Update `STATE.md`**

In `STATE.md`, replace the whole `## Where we are` paragraph (from `Plan 8 (notifications, B0 milestone 8) built and in review` to `each settings switch names its type.`) with:

```markdown
Plan 9 (E2E and staging deploy, B0 milestone 9, the last) built and in review: branch `feat/staging`
in infra, backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-27-staging-design.md`,
plan `docs/superpowers/plans/2026-09-27-plan-9-staging.md`). CI builds the three images after the
tests and, on `master`, pushes `ghcr.io/etqan-agency/<name>:<meta-sha>` and `:master`; the
`staging-sim` job deploys them twice (blue/green under a health poll), fails one deploy on purpose,
seeds, smoke-checks and walks `e2e/journey.spec.ts` on a simulated server (sshd + Docker-in-Docker,
`scripts/staging-sim.sh`, `just staging-sim`); `deploy-staging` (reusable, also run by hand for
rollback) deploys to the real server once the `staging` secrets exist and skips green until then.
The edge takes `TLS_MODE` (`cloudflare` default, byte-identical; `internal`), `ship.sh` takes
`ETQAN_OVERLAY=staging` from `.env.production` (S3 store and Mailpit overlay), and `seed_staging`
creates the demo academy once. The journey (Etqan creates an academy → parent reads the absence)
runs in the CI e2e job too.
```

Replace the whole `## Next` paragraph with:

```markdown
Open PRs (infra, backend, dashboard, meta), get meta CI green with the submodules at their
`feat/staging` heads, merge infra, backend and dashboard, bump meta pointers, merge meta, and check
on the first `master` run that `images` pushed and `deploy-staging` skipped green. Then going live is
configuration only (infra/STAGING.md): a server, DNS, the `staging` secrets, `.env.production`, and
a first manual deploy with `seed`. B0 (the parity roadmap's first phase) is then complete.
```

Replace the heading `## Follow-ups (from Plans 4–8)` with:

```markdown
## Follow-ups (from Plans 4–9)

- Staging uploads are linked at the S3 store's in-network address (`http://s3:9000/...`), so
  browsers cannot load them until staging uses real S3 or a public custom domain (STAGING.md §7).
- MinIO's images are no longer pullable; the overlay uses RustFS 1.0.0 (service `s3`).
- `deploy-staging` declares `environment: staging`; if the org's plan has no environments for
  private repos, drop that line and use repository secrets (STAGING.md §3).
- GitHub keeps only the newest pending deploy per concurrency group: start a rollback when no
  deploy is waiting.
- The production deploy workflow, monitoring alerts, backups and restore drills are not built.
```

In `## Standing warnings`, replace:

```markdown
- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
```

with:

```markdown
- No staging server or domain yet: `deploy-staging` skips until the `staging` secrets exist (infra/STAGING.md). No production deploy workflow. Wildcard TLS (`*.domain`) uses Cloudflare DNS-01 (`TLS_MODE=cloudflare`, the default).
```

- [ ] **Step 3: Check the docs against the code**

```bash
grep -o 'STAGING_[A-Z_]*\|GHCR_READ_TOKEN' infra/STAGING.md | sort -u
grep -o 'secrets\.[A-Z_]*' .github/workflows/deploy-staging.yml | sort -u
```

Expected: the six names in `STAGING.md` (`GHCR_READ_TOKEN`, `STAGING_BASE_URL`, `STAGING_KNOWN_HOSTS`, `STAGING_SSH_HOST`, `STAGING_SSH_KEY`, `STAGING_SSH_USER`) are exactly the workflow's six secrets besides `SUBMODULE_TOKEN`.

- [ ] **Step 4: Commit, push, open PRs, and check the runs**

```bash
git -C infra add STAGING.md CLAUDE.md
git -C infra commit -m "docs: going live on a real staging server

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git add STATE.md docs/superpowers/plans/2026-09-27-plan-9-staging.md
git commit -m "chore: state for Plan 9 — E2E and staging deploy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C infra push -u origin feat/staging
git -C backend push -u origin feat/staging
git -C dashboard push -u origin feat/staging
# Workflow files: over SSH (the gh HTTPS token cannot push them).
git push git@github.com:Etqan-agency/etqan_tutor.git feat/staging
```

Open one PR per repo (infra, backend, dashboard → `main`; meta → `master`), bodies ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. For meta CI to test the new code before the submodules merge, the meta PR first points `infra`, `backend` and `dashboard` at their `feat/staging` heads (`git add infra backend dashboard`, commit `chore: point submodules at feat/staging for CI` with the trailer). On that PR, check:
- `caddy`, `infra-scripts`, `e2e` (18 specs) and `images` (three builds, no push) pass;
- `sim-needed` says `true` (the PR touches the workflows) and `staging-sim` passes on the hosted runner;
- `deploy-staging` does not run (not a `master` push).

Nothing merges without the user's approval. After the submodule PRs merge, point meta at their merge commits (`git add infra backend dashboard`), commit `chore: bump infra, backend and dashboard for Plan 9 — staging` with the trailer, push (SSH), and merge meta. On the first `master` run:

```bash
gh run list --branch master --workflow CI --limit 1
gh run view <id> --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
```

Expected: every job `success`, including `images (backend|dashboard|marketing)` (now pushed: check `ghcr.io/etqan-agency/<name>:<sha>` in the org's packages), `staging-sim`, and `deploy-staging / deploy-staging`, whose log shows the notice "Staging not configured" and its later steps skipped. If `images` is denied pushing, an existing package is not linked to the meta repo: `STAGING.md` §3 (Manage Actions access). If `deploy-staging` fails on `environment: staging` because the organisation's plan has no environments for private repositories, remove the `environment:` line (the secrets then come from repository secrets, `STAGING.md` §3) in a follow-up commit.
