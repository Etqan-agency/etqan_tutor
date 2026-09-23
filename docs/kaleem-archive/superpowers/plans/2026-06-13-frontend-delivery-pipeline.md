# Frontend Delivery Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the React dashboard and Astro marketing site to staging end-to-end behind Traefik, with same-site session auth across `app-`/`api-` subdomains, and codify "every feature ships its frontend" into the process.

**Architecture:** Each frontend becomes a multi-stage `pnpm build → nginx:alpine` image pushed to GHCR (same flow as the backend). Compose adds two singleton static services routed by Traefik; the backend moves to `api-staging.kaleem.academy`. Session/CSRF cookies are scoped to `.kaleem.academy` so they flow same-site across subdomains. CI builds + pushes all three images and `ship.sh` recreates the static services after the backend blue-green.

**Tech Stack:** Vite/React 19, Astro, nginx:alpine, Docker, Traefik v3, GitHub Actions, Django (django-environ, corsheaders).

**Spec:** `docs/superpowers/specs/2026-06-13-frontend-delivery-pipeline-design.md`

**Repos touched (each has its own git-flow `feat → dev → PR → trunk`):** `backend`, `dashboard`, `marketing`, `infra`, and the meta repo (docs + submodule pointer bumps). Use a `feat/frontend-delivery-pipeline` branch in every submodule. Note: much of this work is infra/config, not unit-testable logic — where TDD does not apply, the verification step is a `docker build`/`curl` smoke check, and the final end-to-end browser check is the real gate (Task 9).

---

## Task 1: Backend — env-driven cookie domain + SameSite (repo: `backend`)

**Files:**
- Modify: `config/settings/production.py`
- Test: `tests/settings/test_cookie_domain.py` (create)

- [ ] **Step 1: Branch**

```bash
cd backend
git checkout dev && git pull
git checkout -b feat/frontend-delivery-pipeline
```

- [ ] **Step 2: Write the failing test**

Create `tests/settings/test_cookie_domain.py`:

```python
import importlib


def test_cookie_domain_and_samesite_are_env_driven(monkeypatch):
    """Production scopes session/CSRF cookies to the parent domain so they
    flow same-site across app-/api- subdomains, with SameSite=Lax."""
    monkeypatch.setenv("DJANGO_COOKIE_DOMAIN", ".kaleem.academy")
    monkeypatch.setenv("DJANGO_SECRET_KEY", "test-only")
    monkeypatch.setenv("DJANGO_ALLOWED_HOSTS", "api-staging.kaleem.academy")
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@localhost:5432/d")

    from config.settings import production

    importlib.reload(production)

    assert production.SESSION_COOKIE_DOMAIN == ".kaleem.academy"
    assert production.CSRF_COOKIE_DOMAIN == ".kaleem.academy"
    assert production.SESSION_COOKIE_SAMESITE == "Lax"
    assert production.CSRF_COOKIE_SAMESITE == "Lax"
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `pytest tests/settings/test_cookie_domain.py -v`
Expected: FAIL — `AttributeError: module 'config.settings.production' has no attribute 'SESSION_COOKIE_DOMAIN'` (or `None != ".kaleem.academy"`).

- [ ] **Step 4: Add the settings**

In `config/settings/production.py`, after the existing `CSRF_TRUSTED_ORIGINS` line, add:

```python
# Cross-subdomain session: scope cookies to the parent domain so the dashboard
# (app-…) and API (api-…) share them same-site. See ADR-0019 (frontend delivery).
SESSION_COOKIE_DOMAIN = env("DJANGO_COOKIE_DOMAIN", default=None)
CSRF_COOKIE_DOMAIN = env("DJANGO_COOKIE_DOMAIN", default=None)
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SAMESITE = "Lax"
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `pytest tests/settings/test_cookie_domain.py -v`
Expected: PASS.

- [ ] **Step 6: Run lint + full suite**

Run: `ruff check . && ruff format --check . && lint-imports && pytest -q`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add config/settings/production.py tests/settings/test_cookie_domain.py
git commit -m "feat(settings): env-driven cookie domain + SameSite for cross-subdomain auth"
```

---

## Task 1b: Mailpit local email backend (repo: `backend`, same branch as Task 1)

Dev verification emails currently print to the django container's stdout (console
backend) while the `mailpit` service in `docker-compose.local.yml` (SMTP `:1025`,
web UI `:8025`) sits idle. Point local email at mailpit so links are inspectable.

**Files:**
- Modify: `config/settings/local.py`

- [ ] **Step 1: Replace the console backend with mailpit SMTP**

In `config/settings/local.py`, replace:

```python
EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"
```
with:

```python
# Local email → the mailpit container (web UI at http://localhost:8025), so
# allauth verification links are inspectable instead of buried in stdout.
EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = env("DJANGO_EMAIL_HOST", default="mailpit")
EMAIL_PORT = env.int("DJANGO_EMAIL_PORT", default=1025)
EMAIL_USE_TLS = False
```

(`env` is already imported in `local.py` via `from .base import *`.)

- [ ] **Step 2: Verify end-to-end against mailpit (verification)**

Run (from repo root, with the local stack up):
```bash
docker compose -f docker-compose.local.yml up -d mailpit django
docker compose -f docker-compose.local.yml exec django python -c "from django.core.mail import send_mail; send_mail('ping','body','noreply@kaleem.academy',['dev@example.com'])"
curl -s http://localhost:8025/api/v1/messages | grep -o '"total":[0-9]*'
```
Expected: `"total":1` (or higher) — the message landed in mailpit, not stdout.

- [ ] **Step 3: Commit**

```bash
git add config/settings/local.py
git commit -m "feat(dev): send local email to mailpit instead of console"
```

---

## Task 2: Dashboard — Dockerfile + nginx (repo: `dashboard`)

**Files:**
- Create: `dashboard/Dockerfile`
- Create: `dashboard/nginx.conf`
- Create: `dashboard/.dockerignore`

The axios client (`src/lib/api.ts`) already reads `VITE_API_URL` and sends credentials/CSRF — no app code change needed.

- [ ] **Step 1: Branch**

```bash
cd dashboard
git checkout dev && git pull
git checkout -b feat/frontend-delivery-pipeline
```

- [ ] **Step 2: Create `dashboard/.dockerignore`**

```
node_modules
dist
.tanstack
.git
```

- [ ] **Step 3: Create `dashboard/nginx.conf`**

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Content-hashed bundles — cache hard and forever.
    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    # SPA fallback: every unknown path serves the shell for TanStack Router.
    location / {
        add_header Cache-Control "no-cache";
        try_files $uri $uri/ /index.html;
    }
}
```

- [ ] **Step 4: Create `dashboard/Dockerfile`**

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
# Baked into the bundle at build time; differs per environment.
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN pnpm build

FROM nginx:alpine AS production
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
```

- [ ] **Step 5: Build the image (verification)**

Run:
```bash
docker build -f Dockerfile --target production \
  --build-arg VITE_API_URL=https://api-staging.kaleem.academy/api/v1/ \
  -t dashboard-test .
```
Expected: build succeeds; final image based on nginx.

- [ ] **Step 6: Run + smoke-test nginx routing**

Run:
```bash
docker run -d --rm -p 8088:80 --name dash-test dashboard-test
sleep 2
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/                    # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/some/deep/route      # 200 (SPA fallback)
curl -s http://localhost:8088/ | grep -o "<title>.*</title>"                        # serves index.html
docker stop dash-test
```
Expected: `/` → 200, deep route → 200 (not 404), title present.

- [ ] **Step 7: Commit**

```bash
git add Dockerfile nginx.conf .dockerignore
git commit -m "feat: containerize dashboard (multi-stage pnpm build + nginx, SPA fallback)"
```

---

## Task 3: Marketing — Dockerfile + nginx (repo: `marketing`)

**Files:**
- Create: `marketing/Dockerfile`
- Create: `marketing/nginx.conf`
- Create: `marketing/.dockerignore`

- [ ] **Step 1: Branch**

```bash
cd marketing
git checkout dev && git pull
git checkout -b feat/frontend-delivery-pipeline
```

- [ ] **Step 2: Create `marketing/.dockerignore`**

```
node_modules
dist
.astro
.git
```

- [ ] **Step 3: Create `marketing/nginx.conf`**

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Astro emits static multi-page HTML; resolve extensionless routes too.
    location / {
        try_files $uri $uri/ $uri.html =404;
    }
}
```

- [ ] **Step 4: Create `marketing/Dockerfile`**

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM nginx:alpine AS production
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
```

- [ ] **Step 5: Build + smoke-test (verification)**

Run:
```bash
docker build -f Dockerfile --target production -t marketing-test .
docker run -d --rm -p 8089:80 --name mkt-test marketing-test
sleep 2
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8089/   # 200
docker stop mkt-test
```
Expected: build succeeds, `/` → 200.

- [ ] **Step 6: Commit**

```bash
git add Dockerfile nginx.conf .dockerignore
git commit -m "feat: containerize marketing (Astro static + nginx)"
```

---

## Task 4: Infra — compose services + Traefik routes (repo: `infra`)

**Files:**
- Modify: `docker-compose.production.yml`
- Modify: `.env.production.example`

- [ ] **Step 1: Branch**

```bash
cd infra
git checkout dev && git pull
git checkout -b feat/frontend-delivery-pipeline
```

- [ ] **Step 2: Repoint the django routers to `API_DOMAIN`**

In `docker-compose.production.yml`, in BOTH `django-blue` and `django-green` label blocks, change the router rule from `APP_DOMAIN` to `API_DOMAIN`:

```yaml
      - "traefik.http.routers.django-blue.rule=Host(`${API_DOMAIN}`)"
```
```yaml
      - "traefik.http.routers.django-green.rule=Host(`${API_DOMAIN}`)"
```

- [ ] **Step 3: Add the two static services**

In `docker-compose.production.yml`, after the `flower` service (still in the "Always running" group), add:

```yaml
  # ─── Static frontends (singletons; no blue-green — no migrations) ─────
  dashboard:
    image: ghcr.io/kaleem-lms/dashboard:${DEPLOY_SHA:-latest}
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`${DASHBOARD_DOMAIN}`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.services.dashboard.loadbalancer.server.port=80"

  marketing:
    image: ghcr.io/kaleem-lms/marketing:${DEPLOY_SHA:-latest}
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.marketing.rule=Host(`${MARKETING_DOMAIN}`)"
      - "traefik.http.routers.marketing.entrypoints=websecure"
      - "traefik.http.routers.marketing.tls.certresolver=letsencrypt"
      - "traefik.http.services.marketing.loadbalancer.server.port=80"
```

- [ ] **Step 4: Update `.env.production.example`**

Replace the `APP_DOMAIN=staging.kaleem.academy` line and the CORS/CSRF lines with:

```bash
# Traefik / Deploy — one-label hosts only (Cloudflare cert covers *.kaleem.academy)
API_DOMAIN=api-staging.kaleem.academy
DASHBOARD_DOMAIN=app-staging.kaleem.academy
MARKETING_DOMAIN=staging.kaleem.academy
ACME_EMAIL=admin@kaleem.academy
DEPLOY_SHA=latest
```

And update the auth/origin block:

```bash
DJANGO_ALLOWED_HOSTS=api-staging.kaleem.academy
DJANGO_COOKIE_DOMAIN=.kaleem.academy
CORS_ALLOWED_ORIGINS=https://app-staging.kaleem.academy
CSRF_TRUSTED_ORIGINS=https://app-staging.kaleem.academy
```

- [ ] **Step 5: Validate compose syntax (verification)**

Run:
```bash
DEPLOY_SHA=latest API_DOMAIN=x DASHBOARD_DOMAIN=y MARKETING_DOMAIN=z \
FLOWER_DOMAIN=f TRAEFIK_FLOWER_AUTH=a \
docker compose -f docker-compose.production.yml config >/dev/null && echo OK
```
Expected: `OK` (no YAML/interpolation errors; `dashboard` and `marketing` services resolve).

- [ ] **Step 6: Commit**

```bash
git add docker-compose.production.yml .env.production.example
git commit -m "feat: route dashboard/marketing via Traefik; backend → API_DOMAIN"
```

---

## Task 5: Infra — `ship.sh` recreates the static frontends (repo: `infra`)

**Files:**
- Modify: `scripts/ship.sh`

- [ ] **Step 1: Recreate static services after the color swap**

In `scripts/ship.sh`, after step 9 (`echo "$NEW" > "$STATE_FILE"`) and before the final summary `echo` block, insert:

```bash
# ─── 10. Recreate static frontends with the new image ────────
# Static (no migrations, no health-gate): a plain recreate is a sub-second blip,
# masked by Cloudflare asset caching. The images were already pulled in step 3.
echo "Recreating static frontends (dashboard, marketing)..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d dashboard marketing
```

- [ ] **Step 2: Lint the script (verification)**

Run: `bash -n scripts/ship.sh && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 3: Commit**

```bash
git add scripts/ship.sh
git commit -m "feat(ship): recreate dashboard/marketing static services on deploy"
```

---

## Task 6: Meta CI — build + push the two frontend images (repo: meta, branch `feat/frontend-delivery-pipeline`)

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a marketing build-check job (PR parity with `dashboard-build`)**

In `.github/workflows/ci.yml`, after the `dashboard-build` job, add:

```yaml
  marketing-build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: marketing
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.SUBMODULE_TOKEN }}
      - uses: pnpm/action-setup@v4
        with:
          version: 9
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "pnpm"
          cache-dependency-path: marketing/pnpm-lock.yaml
      - name: Install dependencies
        run: pnpm install --frozen-lockfile
      - name: Build
        run: pnpm build
```

- [ ] **Step 2: Gate deploy on the new job**

Change the `deploy-staging` `needs:` line to include `marketing-build`:

```yaml
    needs: [backend-lint, backend-test, dashboard-lint, dashboard-build, marketing-build]
```

- [ ] **Step 3: Build + push the dashboard and marketing images in `deploy-staging`**

In the `deploy-staging` job, after the "Push backend image" step and before "Sync infra config to staging", add:

```yaml
      - name: Build dashboard image
        run: |
          docker build \
            -f dashboard/Dockerfile \
            --target production \
            --build-arg VITE_API_URL=https://api-staging.kaleem.academy/api/v1/ \
            -t ghcr.io/kaleem-lms/dashboard:${{ env.SHORT_SHA }} \
            -t ghcr.io/kaleem-lms/dashboard:latest \
            dashboard/

      - name: Push dashboard image
        run: |
          docker push ghcr.io/kaleem-lms/dashboard:${{ env.SHORT_SHA }}
          docker push ghcr.io/kaleem-lms/dashboard:latest

      - name: Build marketing image
        run: |
          docker build \
            -f marketing/Dockerfile \
            --target production \
            -t ghcr.io/kaleem-lms/marketing:${{ env.SHORT_SHA }} \
            -t ghcr.io/kaleem-lms/marketing:latest \
            marketing/

      - name: Push marketing image
        run: |
          docker push ghcr.io/kaleem-lms/marketing:${{ env.SHORT_SHA }}
          docker push ghcr.io/kaleem-lms/marketing:latest
```

- [ ] **Step 4: Validate the workflow (verification)**

Run (from repo root): `npx --yes @action-validator/cli .github/workflows/ci.yml 2>/dev/null || python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"`
Expected: `YAML OK` (or action-validator passes). The `VITE_API_URL` build-arg ends in `/api/v1/` to match `src/lib/api.ts`'s base.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build + push dashboard and marketing images on deploy"
```

---

## Task 7: ADR + process changes (repo: meta, same branch)

**Files:**

- Create: `docs/adr/0019-frontend-delivery-and-same-site-auth.md` (already created; ADR-0019)
- Modify: `CLAUDE.md` (auth line)
- Modify: `docs/templates/spec.md` (add Frontend section)

- [ ] **Step 1: Write the ADR**

Run `/new-adr` (or copy `docs/templates/`'s ADR format). Content must record:
- **Decision:** separate `app-`/`api-` subdomains; same-site (not same-origin) session auth via `Domain=.kaleem.academy; SameSite=Lax` cookies + CORS allow-list with credentials.
- **Decision:** static frontends served as nginx images via GHCR (option A), Cloudflare edge-caches immutable assets; option B (CDN/Pages) reserved as escape hatch E2.
- **Consequence:** updates CLAUDE.md's "same-origin frontend/backend" wording to "same-site".
- **Status:** Accepted.

- [ ] **Step 2: Update CLAUDE.md auth wording**

In `CLAUDE.md`, change the Auth line under "The architecture in 30 seconds" from:

```
- **Auth:** session cookies + real CSRF, same-origin frontend/backend. No JWT, no CSRF-exempt hacks.
```
to:

```
- **Auth:** session cookies + real CSRF. Frontend (`app-`) and API (`api-`) are same-site subdomains sharing cookies via `Domain=.kaleem.academy; SameSite=Lax` (see ADR-0019). No JWT, no CSRF-exempt hacks.
```

- [ ] **Step 3: Add a required Frontend section to the spec template**

In `docs/templates/spec.md`, after the `## API delta` section, add:

```markdown
## Frontend

Required for every feature. The dashboard slice that exposes this:
- Routes (TanStack Router paths) and which role(s) see them.
- Components / states (loading, empty, error, success).
- API calls (which endpoints, via `src/lib/api.ts`).
- "Done" = built, deployed to staging, and verified in the browser end-to-end.
```

- [ ] **Step 4: Commit**

```bash
git add docs/adr/ CLAUDE.md docs/templates/spec.md
git commit -m "docs: ADR for frontend delivery + same-site auth; spec template Frontend section"
```

---

## Task 8: Integrate via git-flow + submodule pointer bumps (all repos)

This task lands the per-repo branches and updates the meta pointers. The DoD's
"green CI" (D5) gates each merge.

- [ ] **Step 1: Open a PR per submodule into its `dev`, merge after green CI**

For each of `backend`, `dashboard`, `marketing`, `infra`:
```bash
cd <submodule>
git push -u origin feat/frontend-delivery-pipeline
gh pr create --base dev --fill
# after review + green CI:
gh pr merge --squash --delete-branch
# then dev → trunk via its own PR per ADR-0014
```

- [ ] **Step 2: Provision the new env on the staging VPS (one-time, manual)**

On the VPS, edit `/opt/kaleem/.env.production`: rename `APP_DOMAIN` → `API_DOMAIN=api-staging.kaleem.academy`, add `DASHBOARD_DOMAIN=app-staging.kaleem.academy`, `MARKETING_DOMAIN=staging.kaleem.academy`, `DJANGO_COOKIE_DOMAIN=.kaleem.academy`, and set `DJANGO_ALLOWED_HOSTS`/`CORS_ALLOWED_ORIGINS`/`CSRF_TRUSTED_ORIGINS` per Task 4 Step 4. Add Cloudflare DNS records for `api-staging`, `app-staging` (A → VPS IP, proxied). `staging` already exists.

- [ ] **Step 3: Bump submodule pointers in the meta branch**

```bash
cd <meta repo root>
git submodule update --remote backend dashboard marketing infra
git add backend dashboard marketing infra
git commit -m "chore: bump submodule pointers for frontend delivery pipeline"
```

- [ ] **Step 4: Push meta branch + open PR to `master`**

```bash
git push -u origin feat/frontend-delivery-pipeline
gh pr create --base master --fill
```
Merging to `master` triggers `deploy-staging`, which builds/pushes all three images and runs `ship.sh`.

---

## Task 9: End-to-end verification (the DoD gate)

- [ ] **Step 1: Wait for the `deploy-staging` run to go green**

Run: `gh run watch` (in the meta repo) — or check the Actions tab.
Expected: backend blue-green completes, then dashboard + marketing recreated.

- [ ] **Step 2: Routing smoke test**

Run:
```bash
curl -s -o /dev/null -w "dash %{http_code}\n" https://app-staging.kaleem.academy/
curl -s -o /dev/null -w "api  %{http_code}\n" https://api-staging.kaleem.academy/health/ready/
curl -s -o /dev/null -w "mkt  %{http_code}\n" https://staging.kaleem.academy/
curl -s -o /dev/null -w "spa  %{http_code}\n" https://app-staging.kaleem.academy/some/deep/route
```
Expected: dash 200, api 200, mkt 200, spa 200 (fallback).

- [ ] **Step 3: Asset cache header**

Run: `curl -sI https://app-staging.kaleem.academy/assets/$(curl -s https://app-staging.kaleem.academy/ | grep -oE 'assets/[^"]+\.js' | head -1 | cut -d/ -f2) | grep -i cache-control`
Expected: `Cache-Control: public, max-age=31536000, immutable`.

- [ ] **Step 4: End-to-end auth in the browser (manual — the real gate)**

In a browser, open `https://app-staging.kaleem.academy`, register a real address → verify email → log in → confirm an authenticated `GET /me/` succeeds. In DevTools → Network, confirm: the `sessionid`/`csrftoken` cookies have `Domain=.kaleem.academy`, the cross-subdomain XHR to `api-staging` sends them, the CSRF `X-CSRFToken` header is present on mutations, and the CORS preflight returns the allow-origin header.
Expected: full flow works cross-subdomain with no CORS/CSRF errors.

- [ ] **Step 5: Close out (repo: meta)**

Update `STATE.md` (note the pipeline shipped, staging frontends live) and remove the resolved "Frontend deploy gap" bullet from `ISSUES.md`. Commit on a docs change per git-flow.

---

## Self-review notes

- **Spec coverage:** domains (Tasks 4, 8) · same-site auth (Task 1 + ADR Task 7) · nginx-image serving (Tasks 2, 3) · compose/Traefik (Task 4) · ship.sh recreate (Task 5) · CI three images (Task 6) · DoD + template + ADR process change (Task 7) · end-to-end gate (Task 9). All spec sections map to a task.
- **Out-of-scope honored:** no production wiring (staging only), no CDN/option-B, mailpit excluded (separate).
- **Type/name consistency:** `VITE_API_URL` ends in `/api/v1/` everywhere (matches `src/lib/api.ts`); `DEPLOY_SHA` tag shared by all three images; env names `API_DOMAIN`/`DASHBOARD_DOMAIN`/`MARKETING_DOMAIN`/`DJANGO_COOKIE_DOMAIN` identical across infra, ci, and VPS steps.
- **ADR number:** ADR-0019 (`docs/adr/0019-frontend-delivery-and-same-site-auth.md`).
