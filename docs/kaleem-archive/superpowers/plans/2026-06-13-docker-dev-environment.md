# Docker Dev Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the entire stack (backend + dashboard + marketing + support services) up with one command, in Docker, behind a Traefik reverse proxy on `*.kaleem.localhost`, with zero root-owned files on the host.

**Architecture:** Dev containers run as the host developer's UID/GID (injected by the justfile, baked into each `dev` Dockerfile stage) so bind-mounted files are owned by the user, never root. Frontends get a `dev` Dockerfile stage running their native dev server with `node_modules` in a named volume. Traefik fronts everything and routes ADR-0019 subdomains, so same-site cookie auth is exercised locally.

**Tech Stack:** Docker Compose, Traefik v3, Vite (dashboard), Astro (marketing), Django (backend), pnpm, just.

**Repos touched (each has its own git-flow):**
- `backend/` submodule — settings + Dockerfile (`feat/docker-dev` → main)
- `dashboard/` submodule — Dockerfile + vite config (`feat/docker-dev` → main)
- `marketing/` submodule — Dockerfile + astro config (`feat/docker-dev` → main)
- meta repo — `docker-compose.local.yml`, `justfile`, `.env.example`, docs (current `docs/docker-dev-environment` branch; pointer bumps after submodule PRs merge)

> **Verification note:** This is infra/config work. Most tasks are verified by concrete smoke commands (curl through Traefik, `stat` for ownership, HMR observation) rather than unit tests — those are the honest acceptance checks here. Where a real assertion exists (a settings value), the task makes it.

**Implementation order:** Tasks 1–6 can be built and committed in their own repos. Task 7 wires the compose file that depends on all of them. Tasks 8–9 are integration + docs. Build in order.

---

### Task 1: Meta — `.env.example` for dev container config

**Files:**
- Modify: `/.env.example` (create if absent)
- Verify: `/.gitignore` already ignores `.env`

- [ ] **Step 1: Add the documented dev knobs to `.env.example`**

Append (or create the file with):

```bash
# ── Local dev container config (docker-compose.local.yml) ──
# Host UID/GID the dev containers run as, so bind-mounted files stay owned by
# you (not root). The justfile injects these automatically from `id -u`/`id -g`;
# you normally do NOT need to set them by hand. Override only if your login
# shell makes `id -u` unavailable.
HOST_UID=1000
HOST_GID=1000

# Dashboard talks to the API through Traefik in dev.
VITE_API_URL=http://api.kaleem.localhost
```

- [ ] **Step 2: Confirm `.env` is gitignored**

Run: `git check-ignore .env`
Expected: prints `.env` (already ignored). If it prints nothing, add `.env` to `/.gitignore`.

- [ ] **Step 3: Commit (meta repo)**

```bash
git add .env.example
git commit -m "chore: document dev container env (HOST_UID/GID, VITE_API_URL)"
```

---

### Task 2: Backend — dev settings exercise the `*.kaleem.localhost` subdomains

**Files:**
- Modify: `backend/config/settings/local.py:18-31` (the `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS` block)
- Test: `backend/tests/test_local_settings.py` (create)

This is the one place a real assertion fits: the cookie/CORS config is pure data.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_local_settings.py`:

```python
"""The local dev settings must exercise the ADR-0019 same-site subdomain model."""
import importlib
import os


def _load_local():
    os.environ.setdefault("DJANGO_SECRET_KEY", "test")
    return importlib.import_module("config.settings.local")


def test_traefik_subdomains_are_trusted():
    s = _load_local()
    for origin in (
        "http://app.kaleem.localhost",
        "http://api.kaleem.localhost",
        "http://kaleem.localhost",
    ):
        assert origin in s.CORS_ALLOWED_ORIGINS, origin
        assert origin in s.CSRF_TRUSTED_ORIGINS, origin


def test_cookie_domain_spans_subdomains():
    s = _load_local()
    assert s.SESSION_COOKIE_DOMAIN == ".kaleem.localhost"
    assert s.CSRF_COOKIE_DOMAIN == ".kaleem.localhost"


def test_subdomains_in_allowed_hosts():
    s = _load_local()
    for host in ("app.kaleem.localhost", "api.kaleem.localhost", "kaleem.localhost"):
        assert host in s.ALLOWED_HOSTS, host
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd backend && DJANGO_SETTINGS_MODULE=config.settings.local pytest tests/test_local_settings.py -v`
Expected: FAIL — the new origins / cookie-domain settings don't exist yet.

- [ ] **Step 3: Update `backend/config/settings/local.py`**

Replace the `ALLOWED_HOSTS` line and the `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS` block:

```python
ALLOWED_HOSTS = [  # noqa: S104
    "localhost",
    "0.0.0.0",
    "127.0.0.1",
    "app.kaleem.localhost",
    "api.kaleem.localhost",
    "kaleem.localhost",
]

# Dev mirrors ADR-0019: app-/api- share the registrable domain, so a cookie
# scoped to the parent domain flows across both on cross-subdomain XHR. Getting
# this wrong silently breaks login — which is exactly why we run it locally.
CORS_ALLOWED_ORIGINS = [
    "http://localhost:5173",
    "http://localhost:4321",
    "http://app.kaleem.localhost",
    "http://api.kaleem.localhost",
    "http://kaleem.localhost",
]
CORS_ALLOW_CREDENTIALS = True
CSRF_TRUSTED_ORIGINS = [
    "http://localhost:5173",
    "http://localhost:4321",
    "http://app.kaleem.localhost",
    "http://api.kaleem.localhost",
    "http://kaleem.localhost",
]
SESSION_COOKIE_DOMAIN = ".kaleem.localhost"
CSRF_COOKIE_DOMAIN = ".kaleem.localhost"
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd backend && DJANGO_SETTINGS_MODULE=config.settings.local pytest tests/test_local_settings.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit (backend submodule, on `feat/docker-dev`)**

```bash
cd backend && git checkout -b feat/docker-dev
git add config/settings/local.py tests/test_local_settings.py
git commit -m "feat: trust *.kaleem.localhost dev subdomains (ADR-0019 same-site)"
```

---

### Task 3: Backend — `dev` Dockerfile stage runs as host UID/GID

**Files:**
- Modify: `backend/Dockerfile` (the `FROM base AS dev` stage)

- [ ] **Step 1: Replace the `dev` stage in `backend/Dockerfile`**

```dockerfile
FROM base AS dev
RUN pip install --no-cache-dir -r requirements/local.txt
# Run as the host developer's UID/GID so files the container writes into the
# bind-mounted ./backend (.coverage, .pytest_cache, .ruff_cache, migrations)
# are owned by the developer, never root. Defaults match a typical Linux login.
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} app && useradd -u ${UID} -g app -m app \
    && chown -R app:app /app
COPY --chown=app:app . .
USER app
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
```

(The `production` stage is unchanged.)

- [ ] **Step 2: Build the dev stage to verify it compiles**

Run: `cd backend && docker build --target dev --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t kaleem-backend-dev:test .`
Expected: build succeeds.

- [ ] **Step 3: Verify the container runs as your UID (not root)**

Run: `docker run --rm kaleem-backend-dev:test id -u`
Expected: prints your host UID (e.g. `1000`), not `0`.

- [ ] **Step 4: Commit (backend submodule, `feat/docker-dev`)**

```bash
cd backend && git add Dockerfile
git commit -m "feat: dev image runs as host UID/GID to avoid root-owned files"
```

---

### Task 4: Dashboard — `dev` Dockerfile stage + Vite proxy/HMR config

**Files:**
- Modify: `dashboard/Dockerfile` (add a `dev` stage before `production`)
- Modify: `dashboard/vite.config.ts`

- [ ] **Step 1: Add a `dev` stage to `dashboard/Dockerfile`**

Insert this stage **between** the `build` stage and the `FROM nginx:alpine AS production` line:

```dockerfile
# ── Dev stage: native Vite dev server, runs as host UID/GID ──
FROM node:22-alpine AS dev
ARG UID=1000
ARG GID=1000
RUN corepack enable && corepack prepare pnpm@10.28.0 --activate \
    && apk add --no-cache git
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
# Same BuildKit secret as the build stage; token never persists in a layer.
RUN --mount=type=secret,id=tokens_token sh -euc '\
  git config --global url."https://x-access-token:$(cat /run/secrets/tokens_token)@github.com/".insteadOf "https://github.com/"; \
  git config --global url."https://x-access-token:$(cat /run/secrets/tokens_token)@github.com/".insteadOf "git@github.com:"; \
  pnpm install --frozen-lockfile; \
  rm -f /root/.gitconfig'
# Recreate the default node user as the host UID/GID and own /app, so the
# node_modules named volume (which inherits this path's ownership when first
# populated) and any bind-mounted writes are owned by the developer.
RUN deluser node 2>/dev/null || true; \
    addgroup -g ${GID} app && adduser -u ${UID} -G app -D app && \
    chown -R app:app /app
USER app
EXPOSE 5173
CMD ["pnpm", "dev"]
```

- [ ] **Step 2: Configure Vite for the proxy + HMR-through-Traefik**

Replace `dashboard/vite.config.ts` with:

```ts
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react-swc";
import { TanStackRouterVite } from "@tanstack/router-plugin/vite";
import { defineConfig } from "vite";
import path from "path";

export default defineConfig({
  plugins: [TanStackRouterVite(), react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    // Listen on all interfaces so Traefik (another container) can reach it.
    host: true,
    port: 5173,
    // Vite rejects unknown Host headers; allow the Traefik vhost.
    allowedHosts: ["app.kaleem.localhost"],
    // HMR is a websocket. The page is served via Traefik on :80, so the HMR
    // client must connect back on 80 — not Vite's internal 5173.
    hmr: { clientPort: 80 },
  },
});
```

- [ ] **Step 3: Build the dev stage to verify it compiles**

Run: `cd dashboard && DOCKER_BUILDKIT=1 docker build --target dev --build-arg UID=$(id -u) --build-arg GID=$(id -g) --secret id=tokens_token,env=GH_TOKEN -t kaleem-dash-dev:test .`
(Set `GH_TOKEN` to a PAT with read access to `kaleem-lms/tokens` first.)
Expected: build succeeds.

- [ ] **Step 4: Verify it runs as your UID**

Run: `docker run --rm kaleem-dash-dev:test id -u`
Expected: your host UID, not `0`.

- [ ] **Step 5: Commit (dashboard submodule, `feat/docker-dev`)**

```bash
cd dashboard && git checkout -b feat/docker-dev
git add Dockerfile vite.config.ts
git commit -m "feat: dev Dockerfile stage + Vite proxy/HMR config for Traefik"
```

---

### Task 5: Marketing — `dev` Dockerfile stage + Astro proxy/HMR config

**Files:**
- Modify: `marketing/Dockerfile` (add a `dev` stage before `production`)
- Modify: `marketing/astro.config.mjs`

- [ ] **Step 1: Add a `dev` stage to `marketing/Dockerfile`**

Insert between the `build` stage and `FROM nginx:alpine AS production`:

```dockerfile
# ── Dev stage: native Astro dev server, runs as host UID/GID ──
FROM node:22-alpine AS dev
ARG UID=1000
ARG GID=1000
RUN corepack enable && corepack prepare pnpm@10.28.0 --activate \
    && apk add --no-cache git
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=secret,id=tokens_token sh -euc '\
  git config --global url."https://x-access-token:$(cat /run/secrets/tokens_token)@github.com/".insteadOf "https://github.com/"; \
  git config --global url."https://x-access-token:$(cat /run/secrets/tokens_token)@github.com/".insteadOf "git@github.com:"; \
  pnpm install --frozen-lockfile; \
  rm -f /root/.gitconfig'
RUN deluser node 2>/dev/null || true; \
    addgroup -g ${GID} app && adduser -u ${UID} -G app -D app && \
    chown -R app:app /app
USER app
EXPOSE 4321
CMD ["pnpm", "dev"]
```

- [ ] **Step 2: Configure Astro for the proxy + HMR**

Replace `marketing/astro.config.mjs` with:

```js
// @ts-check
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

// https://astro.build/config
export default defineConfig({
  server: {
    host: true,
    port: 4321,
  },
  vite: {
    plugins: [tailwindcss()],
    server: {
      allowedHosts: ["kaleem.localhost"],
      hmr: { clientPort: 80 },
    },
  },
});
```

- [ ] **Step 3: Build the dev stage**

Run: `cd marketing && DOCKER_BUILDKIT=1 docker build --target dev --build-arg UID=$(id -u) --build-arg GID=$(id -g) --secret id=tokens_token,env=GH_TOKEN -t kaleem-mkt-dev:test .`
Expected: build succeeds.

- [ ] **Step 4: Verify it runs as your UID**

Run: `docker run --rm kaleem-mkt-dev:test id -u`
Expected: your host UID, not `0`.

- [ ] **Step 5: Commit (marketing submodule, `feat/docker-dev`)**

```bash
cd marketing && git checkout -b feat/docker-dev
git add Dockerfile astro.config.mjs
git commit -m "feat: dev Dockerfile stage + Astro proxy/HMR config for Traefik"
```

---

### Task 6: Meta — `docker-compose.local.yml` gains Traefik + frontends

**Files:**
- Modify: `/docker-compose.local.yml`

> Submodule changes (Tasks 2–5) are committed but not yet merged/pointer-bumped. That's fine — this compose file `build:`s from the submodule working trees, which already contain the new `dev` stages.

- [ ] **Step 1: Add a build-args anchor and apply it to every backend service**

At the top of the file (above `services:`), add:

```yaml
# Inject the host UID/GID into every dev image so containers write
# bind-mounted files as the developer, not root. HOST_UID/HOST_GID come from
# the justfile (`id -u`/`id -g`); 1000 is the fallback.
x-uidgid: &uidgid
  UID: ${HOST_UID:-1000}
  GID: ${HOST_GID:-1000}
```

For **each** backend service (`django`, `celery_worker`, `celery_beat`, `flower`) change its `build:` block from:

```yaml
    build:
      context: ./backend
      target: dev
```

to:

```yaml
    build:
      context: ./backend
      target: dev
      args: *uidgid
```

- [ ] **Step 2: Add the Traefik service**

Add this service (inside `services:`):

```yaml
  traefik:
    image: traefik:v3.3
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --api.insecure=true
      - --api.dashboard=true
    ports:
      - "80:80"
      - "8080:8080" # Traefik dashboard → http://localhost:8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

- [ ] **Step 3: Add Traefik router labels to `django`, `mailpit`, `flower`**

On the `django` service add:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.api.rule=Host(`api.kaleem.localhost`)
      - traefik.http.routers.api.entrypoints=web
      - traefik.http.services.api.loadbalancer.server.port=8000
```

On `mailpit` add:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.mail.rule=Host(`mail.kaleem.localhost`)
      - traefik.http.routers.mail.entrypoints=web
      - traefik.http.services.mail.loadbalancer.server.port=8025
```

On `flower` add:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.flower.rule=Host(`flower.kaleem.localhost`)
      - traefik.http.routers.flower.entrypoints=web
      - traefik.http.services.flower.loadbalancer.server.port=5555
```

- [ ] **Step 4: Add the `dashboard` and `marketing` services**

```yaml
  dashboard:
    build:
      context: ./dashboard
      target: dev
      args: *uidgid
      secrets:
        - tokens_token
    environment:
      - VITE_API_URL=http://api.kaleem.localhost
    volumes:
      - ./dashboard:/app
      - dashboard_node_modules:/app/node_modules
    labels:
      - traefik.enable=true
      - traefik.http.routers.app.rule=Host(`app.kaleem.localhost`)
      - traefik.http.routers.app.entrypoints=web
      - traefik.http.services.app.loadbalancer.server.port=5173

  marketing:
    build:
      context: ./marketing
      target: dev
      args: *uidgid
      secrets:
        - tokens_token
    volumes:
      - ./marketing:/app
      - marketing_node_modules:/app/node_modules
    labels:
      - traefik.enable=true
      - traefik.http.routers.web.rule=Host(`kaleem.localhost`)
      - traefik.http.routers.web.entrypoints=web
      - traefik.http.services.web.loadbalancer.server.port=4321
```

- [ ] **Step 5: Declare the new volumes and the build secret**

Extend the `volumes:` block:

```yaml
volumes:
  postgres_data:
  dashboard_node_modules:
  marketing_node_modules:
```

Add a top-level `secrets:` block (the token is read from the `GH_TOKEN` env var at build time, never committed):

```yaml
secrets:
  tokens_token:
    environment: GH_TOKEN
```

- [ ] **Step 6: Validate the compose file parses**

Run: `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml config -q`
Expected: no output, exit 0 (valid). Fix any YAML/anchor errors it reports.

- [ ] **Step 7: Commit (meta repo)**

```bash
git add docker-compose.local.yml
git commit -m "feat: dev compose adds Traefik + dashboard/marketing, runs as host UID/GID"
```

---

### Task 7: Meta — justfile one-command workflow

**Files:**
- Modify: `/justfile`

- [ ] **Step 1: Replace `setup`, `dev`, and the per-frontend recipes**

Replace the `setup` recipe with a container-first version:

```make
# Clone submodules, build images, run migrations + seed (all in Docker)
setup:
    git submodule update --init --recursive
    @echo "Building images (needs GH_TOKEN with read access to kaleem-lms/tokens)…"
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml build
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml up -d postgres redis
    @echo "Waiting for Postgres…"
    sleep 3
    just migrate
    just seed
    @echo "Setup complete. Run 'just dev'."
```

Replace `dev` (and drop the host-frontend plumbing):

```make
# Bring up the entire stack in Docker, behind Traefik. Ctrl-C stops it.
dev:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml up

# Bring up the stack detached
dev-backend:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml up -d

# Rebuild images (after dependency or Dockerfile changes)
rebuild:
    HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml build

# Tail logs for one service, e.g. `just logs dashboard`
logs service:
    docker compose -f docker-compose.local.yml logs -f {{service}}
```

Delete the old standalone `dashboard:` and `marketing:` recipes (they ran host pnpm; the stack now serves both). Keep `stop:` as-is.

- [ ] **Step 2: Point `migrate`, `seed`, `shell` at the running container**

Replace those three recipes:

```make
# Run Django migrations (inside the django container)
migrate:
    docker compose -f docker-compose.local.yml run --rm django python manage.py migrate

# Open Django shell (inside the django container)
shell:
    docker compose -f docker-compose.local.yml run --rm django python manage.py shell_plus 2>/dev/null \
      || docker compose -f docker-compose.local.yml run --rm django python manage.py shell

# Reset DB and load seed data
seed:
    docker compose -f docker-compose.local.yml run --rm django python manage.py seed basic
```

- [ ] **Step 3: Add in-container test/lint, keep host versions as an escape hatch**

Replace the testing/linting section. Default targets run in-container (CI parity); `*-host` keep the old fast host path for IDE-integrated runs:

```make
# ─── Testing ──────────────────────────────────────────────────

test: test-backend test-frontend check-boundaries

# Backend tests (in container)
test-backend:
    docker compose -f docker-compose.local.yml run --rm \
      -e DATABASE_URL=postgres://kaleem:kaleem@postgres:5432/kaleem \
      django pytest -v --cov=kaleem --cov-report=term-missing

# Frontend type check (in container)
test-frontend:
    docker compose -f docker-compose.local.yml run --rm dashboard pnpm tsc --noEmit

# Escape hatch: run backend tests on the host (uses local .venv)
test-backend-host:
    cd backend && DATABASE_URL=postgres://kaleem:kaleem@localhost:5432/kaleem pytest -v --cov=kaleem --cov-report=term-missing

# ─── Linting ──────────────────────────────────────────────────

lint: lint-backend lint-frontend check-boundaries

lint-backend:
    docker compose -f docker-compose.local.yml run --rm django sh -euc 'ruff check . && ruff format --check .'

lint-frontend:
    docker compose -f docker-compose.local.yml run --rm dashboard pnpm dlx @biomejs/biome check .

check-boundaries:
    docker compose -f docker-compose.local.yml run --rm django lint-imports
```

- [ ] **Step 4: Verify the justfile parses and lists**

Run: `just --list`
Expected: lists `dev`, `rebuild`, `logs`, `test`, `test-backend-host`, etc. with no parse error.

- [ ] **Step 5: Commit (meta repo)**

```bash
git add justfile
git commit -m "feat: one-command Dockerized dev workflow + in-container test/lint"
```

---

### Task 8: Integration — full-stack smoke (the spec's Definition of Done)

No new files. This runs the real acceptance checks from the spec. Requires `GH_TOKEN` exported (read access to `kaleem-lms/tokens`).

- [ ] **Step 1: Cold build + bring the stack up**

Run: `export GH_TOKEN=<pat>; just rebuild && just dev-backend`
Expected: all services start; `docker compose -f docker-compose.local.yml ps` shows `django`, `dashboard`, `marketing`, `traefik`, `postgres`, `redis`, `mailpit`, `flower` up.

- [ ] **Step 2: Verify `*.localhost` resolution**

Run: `getent hosts app.kaleem.localhost`
Expected: resolves to `127.0.0.1`. If it does NOT resolve, add a fallback line to `/etc/hosts`: `127.0.0.1 app.kaleem.localhost api.kaleem.localhost kaleem.localhost mail.kaleem.localhost flower.kaleem.localhost` and note it in the developer guide.

- [ ] **Step 3: Verify routing through Traefik (DoD #2)**

Run:
```bash
curl -s -o /dev/null -w "app=%{http_code}\n" http://app.kaleem.localhost/
curl -s -o /dev/null -w "mkt=%{http_code}\n" http://kaleem.localhost/
curl -s -o /dev/null -w "api=%{http_code}\n" http://api.kaleem.localhost/admin/
```
Expected: `app=200`, `mkt=200`, `api=200` (or `302` for the admin redirect to login).

- [ ] **Step 4: Verify HMR (DoD #3)**

Open `http://app.kaleem.localhost/` in a browser, edit a string in a `dashboard/src` component, save.
Expected: the browser updates without a full reload. (Check the devtools console shows `[vite] hot updated` and no websocket errors.) Repeat for `marketing/src` at `http://kaleem.localhost/`.

- [ ] **Step 5: Verify same-site cookie auth (DoD #4)**

Log in through `http://app.kaleem.localhost/`. In devtools → Application → Cookies, confirm the session/CSRF cookies have `Domain=.kaleem.localhost`, and that an authenticated XHR to `http://api.kaleem.localhost/...` succeeds (200, not 401/403).

- [ ] **Step 6: Verify NO root-owned files (DoD #5 — the core ask)**

Run a test pass, then scan every bind mount for root-owned files:
```bash
just test-backend
find backend dashboard marketing -xdev -user root -not -path '*/node_modules/*' -print
```
Expected: the `find` prints **nothing**. (If `backend/.coverage` is still root-owned from before, delete it with `sudo rm` once — new runs will be host-owned.)

- [ ] **Step 7: Verify in-container test/lint pass (DoD #6)**

Run: `just test && just lint`
Expected: backend tests, frontend type-check, and boundary check all pass.

---

### Task 9: Docs + state

**Files:**
- Create: `docs/developer-guide/local-dev.md`
- Modify: `STATE.md`, `docs/superpowers/journal/2026-24.md` (this week)

- [ ] **Step 1: Write the developer guide**

Create `docs/developer-guide/local-dev.md`:

```markdown
# Local development

One command brings the whole stack up in Docker behind Traefik.

## Prerequisites
- Docker + Docker Compose, `just`, git.
- `GH_TOKEN` env var: a GitHub PAT with read access to `kaleem-lms/tokens`
  (the private design-token package the frontends install).

## First run
```bash
export GH_TOKEN=<your-pat>
just setup     # submodules + build images + migrate + seed
just dev       # brings everything up (Ctrl-C to stop)
```

## URLs (no /etc/hosts edits needed — *.localhost resolves to 127.0.0.1)
| Service | URL |
| --- | --- |
| Dashboard | http://app.kaleem.localhost |
| Marketing | http://kaleem.localhost |
| API / admin | http://api.kaleem.localhost |
| Mailpit | http://mail.kaleem.localhost |
| Flower | http://flower.kaleem.localhost |
| Traefik dashboard | http://localhost:8080 |

## Why subdomains?
They reproduce ADR-0019's same-site cookie auth locally, so login/CSRF/CORS
bugs surface in dev instead of on staging.

## Ownership
Containers run as your host UID/GID (the justfile injects them), so files they
write into bind mounts are owned by you, never root.

## Fallback: *.localhost doesn't resolve
Add to /etc/hosts:
`127.0.0.1 app.kaleem.localhost api.kaleem.localhost kaleem.localhost mail.kaleem.localhost flower.kaleem.localhost`

## Escape hatches
- `just test-backend-host` runs backend tests on the host `.venv` for speed.
- `just logs <service>` tails one service.
```

- [ ] **Step 2: Update `STATE.md`**

Add a line under the current phase noting the Dockerized one-command dev environment shipped, linking the spec and plan.

- [ ] **Step 3: Append to this week's journal**

Add an entry to `docs/superpowers/journal/2026-24.md` recording the DX work (link spec + plan; note the ADR-0019 same-site-in-dev win).

- [ ] **Step 4: Commit (meta repo)**

```bash
git add docs/developer-guide/local-dev.md STATE.md docs/superpowers/journal/2026-24.md
git commit -m "docs: local dev guide + state/journal for Dockerized dev env"
```

---

## Post-implementation: integration across repos

After all tasks pass:

1. Open submodule PRs (`feat/docker-dev` → `main`) for `backend`, `dashboard`, `marketing`. Merge on green CI.
2. In the meta repo, bump the three submodule pointers to the merged commits.
3. Open the meta PR (`docs/docker-dev-environment` → `develop`) carrying the compose/justfile/docs changes + pointer bumps.
4. Run `/ship` to walk the Definition of Done.

## Self-review notes

- **Spec coverage:** D-1 (host UID/GID) → Tasks 3,4,5; D-2 (node_modules volume) → Task 6 Step 4–5; D-3 (Traefik subdomains) → Task 6 + Task 8; D-4 (in-container test/lint + host hatch) → Task 7. Backend CORS/CSRF/cookie → Task 2. `.env` → Task 1. Docs/DoD → Tasks 8–9. All spec sections covered.
- **`just setup` cleanup** (raised during brainstorming) folded into Task 7 Step 1.
- **Naming:** `HOST_UID`/`HOST_GID` used consistently (justfile → compose `${HOST_UID}` → build arg `UID`) to dodge the bash readonly `UID`/`GID` clash.
- **No fabricated unit tests:** only Task 2 has a true assertion (settings are data); the rest use honest smoke verification, as flagged at the top.
```
