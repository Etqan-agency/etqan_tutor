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
    git submodule update --init --recursive
    @echo "Building images…"
    just _compose build
    just _compose up -d postgres redis
    @echo "Waiting for Postgres…"
    sleep 3
    just migrate
    just seed
    @echo "Setup complete. Run 'just dev'."

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

# ─── Testing ──────────────────────────────────────────────────

# Run all tests (backend + frontend + boundary linter)
test: test-backend test-frontend check-boundaries

# Backend tests (in container)
# The --cov flag MUST match the `backend` job in .github/workflows/ci.yml
# exactly (--cov=etqan). A mismatch measures a different set of files than
# the ratchet floor was set from, and `just test` fails against a floor
# nothing pointed at. Changing the measured package? Change it in both places.
test-backend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm \
      -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan \
      django pytest -v --cov=etqan --cov-report=term-missing

# Frontend type check (in container)
test-frontend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm tsc --noEmit

# Escape hatch: run backend tests on the host (uses local .venv)
test-backend-host:
    cd backend && DATABASE_URL=postgres://etqan:etqan@localhost:${ETQAN_PG_PORT:-5432}/etqan pytest -v --cov=etqan --cov-report=term-missing

# ─── Linting ──────────────────────────────────────────────────

# Run all linters
lint: lint-backend lint-frontend check-boundaries

lint-backend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django sh -euc 'ruff check . && ruff format --check .'

lint-frontend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm dlx @biomejs/biome check .

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
    @echo "  1. Add 'etqan.{{name}}' to TENANT_APPS (and SHARED_APPS only if it must exist in public)"
    @echo "  2. Add import-linter contracts in pyproject.toml"
    @echo "  3. Create docs/architecture/{{name}}.md"
