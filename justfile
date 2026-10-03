# justfile — etqan task runner
# Run `just` to see all available commands.

# Orchestration streams (docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md §3.3):
# a phase worktree's git-ignored .env.stream sets COMPOSE_PROJECT_NAME and every
# port, so several stacks run side by side. Without the file nothing changes.
set dotenv-load := true
set dotenv-filename := ".env.stream"

default:
    @just --list

# ─── Internal ─────────────────────────────────────────────────

# docker compose with host UID/GID + a resolved GitHub token (for the private
# @etqan/tokens build secret). Prefers $GH_TOKEN, else the gh CLI (stripping
# any empty GH_TOKEN/GITHUB_TOKEN that would otherwise shadow gh's keyring).
# Fails fast with guidance if neither yields a token. Used by build/up recipes.
_compose *args:
    #!/usr/bin/env bash
    set -euo pipefail
    token="${GH_TOKEN:-}"
    if [ -z "$token" ]; then
      token="$(env -u GH_TOKEN -u GITHUB_TOKEN gh auth token 2>/dev/null || true)"
    fi
    if [ -z "$token" ]; then
      echo "ERROR: no GitHub token for the private @etqan/tokens package." >&2
      echo "Provide one (either works):" >&2
      echo "  • export GH_TOKEN=<PAT with read access to Etqan-agency/etqan_tutor_tokens>   # most reliable" >&2
      echo "  • gh auth login                                                # unlocks the gh keyring, then retry" >&2
      exit 1
    fi
    HOST_UID="$(id -u)" HOST_GID="$(id -g)" GH_TOKEN="$token" \
      docker compose -f docker-compose.local.yml {{args}}

# ─── Setup ────────────────────────────────────────────────────

# Clone submodules, build images, run migrations + seed (all in Docker)
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    # In a phase worktree (scripts/orchestration/launch-phase.sh) the submodule
    # dirs are already `git worktree`s of the main checkout's submodules:
    # `git submodule update --init` there rewrites the MAIN checkout's
    # .git/modules/<sub>/config core.worktree to point at the phase worktree,
    # breaking `git status` back in the main checkout. Only the main checkout
    # (git-dir == git-common-dir) runs it.
    if [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]; then
      git submodule update --init --recursive
    else
      echo "phase worktree: its submodules are worktrees already (scripts/orchestration/launch-phase.sh); skipping git submodule update"
    fi
    echo "Building images…"
    just _compose build
    just _compose up -d postgres redis
    echo "Waiting for Postgres…"
    sleep 3
    just migrate
    just seed
    echo "Setup complete. Run 'just dev'."

# ─── Development ──────────────────────────────────────────────

# Bring up the entire stack in Docker, behind Caddy. Ctrl-C stops it.
dev: _urls
    just _compose up

# Bring up the stack detached
dev-backend:
    just _compose up -d
    @just _urls

_urls:
    @echo "Academy site:    http://demo.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/"
    @echo "Dashboard:       http://demo.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/app/"
    @echo "API:             http://demo.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/api/v1/"
    @echo "Staff admin:     http://etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/admin/"
    @echo "Mail / Flower:   http://mail.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}  http://flower.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}"

# Rebuild images (after dependency or Dockerfile changes)
rebuild:
    just _compose build

# Tail logs for one service, e.g. `just logs dashboard`
logs service:
    docker compose -f docker-compose.local.yml logs -f {{service}}

# Stop the backend stack
stop:
    docker compose -f docker-compose.local.yml down

# Refuses in the main checkout, whose volumes are the owner's dev data
# (scripts/orchestration/teardown-phase.sh runs it; CONDUCTOR.md).
# Phase worktree only: stop this stream's stack and delete its volumes
stream-down:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f .env.stream ] || [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
      echo "stream-down: no .env.stream here; it only runs in a phase worktree" >&2
      exit 1
    fi
    docker compose -f docker-compose.local.yml down -v --remove-orphans

# ─── Testing ──────────────────────────────────────────────────

# Run all tests (backend + frontend + boundary linter)
test: test-backend test-frontend test-marketing check-boundaries

# Backend tests (in container)
# The --cov flag MUST match the `backend` job in .github/workflows/ci.yml
# exactly (--cov=etqan). A mismatch measures a different set of files than
# the ratchet floor was set from, and `just test` fails against a floor
# nothing pointed at. Changing the measured package? Change it in both places.
test-backend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm \
      -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan \
      -e DJANGO_EMAIL_SUBJECT_PREFIX= \
      django pytest -v --cov=etqan --cov-report=term-missing

# Marketing unit tests (in container). CI runs them without SITE_SCHEME, so the
# code's https default; the stack's own SITE_SCHEME=http is for serving only.
test-marketing:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm \
      -e SITE_SCHEME=https marketing pnpm test:coverage

# Frontend type check (in container)
test-frontend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm tsc --noEmit

# In a phase worktree .env.stream points the suite's URLs and Mailpit at the
# stream's ports, and its management commands (e2e/manage.ts) run in this
# stack's django container, so they write this stack's database. Set
# E2E_MANAGE yourself to override. Needs the stack up (`just dev-backend`).
# Playwright e2e suite against this checkout's stack, e.g. `just e2e e2e/journey.spec.ts`
e2e *args:
    #!/usr/bin/env bash
    set -euo pipefail
    export E2E_MANAGE="${E2E_MANAGE:-just --justfile {{justfile()}} _stack-manage}"
    cd dashboard
    # The dashboard container mounts its own node_modules volume here, so the
    # host may have only an empty (possibly root-owned) directory.
    if [ ! -x node_modules/.bin/playwright ]; then
      npx --yes pnpm@10 install --frozen-lockfile || {
        echo 'e2e: host install failed; if dashboard/node_modules is root-owned, run: sudo chown -R "$USER" dashboard/node_modules' >&2
        exit 1
      }
    fi
    npx --yes pnpm@10 exec playwright install chromium
    # One worker, as in CI: the suite shares one seeded database (playwright.config.ts),
    # and parallel specs race (features.spec switches demo's families off mid-families.spec).
    npx --yes pnpm@10 exec playwright test --workers=1 {{args}}

# manage.py in this stack's django container, for E2E_MANAGE: e2e/manage.ts
# passes every argument shell-quoted, as it does for ssh, so `sh` unquotes them.
_stack-manage *args:
    @docker compose -f docker-compose.local.yml exec -T django python manage.py {{args}}

# Escape hatch: run backend tests on the host (uses local .venv)
test-backend-host:
    cd backend && DATABASE_URL=postgres://etqan:etqan@localhost:${ETQAN_PG_PORT:-5432}/etqan pytest -v --cov=etqan --cov-report=term-missing

# ─── Linting ──────────────────────────────────────────────────

# Run all linters
lint: lint-backend lint-frontend check-boundaries

lint-backend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django sh -euc 'ruff check . && ruff format --check .'

lint-frontend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm lint

check-boundaries:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django lint-imports

# ─── Database ─────────────────────────────────────────────────

# Run Django migrations (inside the django container)
migrate:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django python manage.py migrate_schemas

# Open Django shell (inside the django container)
shell:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django python manage.py shell_plus 2>/dev/null \
      || HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django python manage.py shell

# Create the public tenant and the demo/other dev academies
seed:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django python manage.py seed_dev

# ─── Infrastructure ───────────────────────────────────────────

# Staging deploys from CI on every green master (infra/STAGING.md)
deploy:
    @echo "Staging deploys from CI on every green master; see infra/STAGING.md."

# Prove the staging deploy on a simulated server (privileged Docker-in-Docker)
staging-sim:
    bash scripts/staging-sim.sh all

# Scaffold a new backend module
new-module name:
    @echo "Creating module etqan/{{name}}..."
    mkdir -p backend/etqan/{{name}}/{api,tests}
    touch backend/etqan/{{name}}/__init__.py
    touch backend/etqan/{{name}}/apps.py
    touch backend/etqan/{{name}}/models.py
    touch backend/etqan/{{name}}/services.py
    touch backend/etqan/{{name}}/api/__init__.py
    touch backend/etqan/{{name}}/api/serializers.py
    touch backend/etqan/{{name}}/api/views.py
    touch backend/etqan/{{name}}/tests/__init__.py
    @echo "Module scaffolded. Remember to:"
    @echo "  1. Add 'etqan.{{name}}' to TENANT_APPS under your phase's '── phase Bn ──' marker"
    @echo "  2. Add import-linter contracts in pyproject.toml under your phase's marker, and the app to the platform contract's forbidden list"
    @echo "  3. Create docs/architecture/{{name}}.md"

# ─── Orchestra (the parallel-phases dashboard) ────────────────

# Build the web app when its sources changed, then serve http://127.0.0.1:7700
orchestra:
    #!/usr/bin/env bash
    set -euo pipefail
    cd orchestra/web
    [ -d node_modules ] || npx pnpm@10 install --frozen-lockfile
    if [ ! -f dist/index.html ] || [ -n "$(find src index.html package.json vite.config.ts tsconfig.json -newer dist/index.html -print -quit)" ]; then
      npx pnpm@10 build
    fi
    cd ../server
    exec python3 -m orchestra_server

# Work on the UI: the server plus Vite on :5174 with /api proxied
orchestra-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd orchestra/server && ORCHESTRA_DEV=1 exec python3 -m orchestra_server) &
    trap 'kill %1' EXIT
    cd orchestra/web && npx pnpm@10 dev

# Orchestra's tests: server, web, types and lint
orchestra-test:
    cd orchestra/server && python3 -m unittest discover -s tests -t .
    cd orchestra/web && npx pnpm@10 test:coverage && npx pnpm@10 build && npx pnpm@10 lint
