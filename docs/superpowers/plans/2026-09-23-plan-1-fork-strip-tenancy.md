# Plan 1 — Fork, Strip, and Multi-Academy Tenancy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a fork of Kaleem into the etqan_tutor foundation: unused Kaleem features removed, everything rebranded, and every academy running in its own PostgreSQL schema on its own subdomain, with an Etqan super-admin console that creates academies.

**Architecture:** Five repos forked into `Etqan-agency` (meta + backend + dashboard + infra + tokens; marketing dropped). Backend keeps Kaleem's Django/DRF `identity` and `platform` apps, renames the Python package `kaleem` → `etqan`, and adds `django-tenants` with a new `etqan.tenants` app (`Academy` tenant model + `Domain`). Tenant hosts (`{academy}.etqan.localhost`) serve the React dashboard and, on the **same host**, `/api/`; the bare domain (`etqan.localhost`) serves only the Django admin used by Etqan staff. Cookies become host-only, so CORS and cookie-domain plumbing is deleted.

**Tech Stack:** Python 3.13, Django 5.x, DRF, django-allauth, django-tenants 3.x, Celery/Redis, PostgreSQL 18, pytest-django; React 19, TanStack Router/Query, Vite 8, Vitest, Playwright, Biome, pnpm 10; Traefik v3 (local), Docker Compose; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-23-etqan-tutor-v1-design.md` (§2 Repositories, §3 Tenancy, §9 milestones 1–2). This is Plan 1 of several; later plans cover milestones 3–9.

## Global Constraints

- GitHub org: `Etqan-agency`. Meta repo `Etqan-agency/etqan_tutor` (trunk `master`); submodule repos `etqan_tutor_backend`, `etqan_tutor_dashboard`, `etqan_tutor_infra`, `etqan_tutor_tokens` (trunk `main`). `kaleem-lms/marketing` is **not** forked.
- Python package name: `etqan`. Brand strings: `Etqan` / `etqan`. Tokens package: `@etqan/tokens`.
- Tenancy: `django-tenants`, schema per academy; schema name `academy_<subdomain with - → _>`; academy domain `<subdomain>.<TENANT_BASE_DOMAIN>`; local `TENANT_BASE_DOMAIN` = `etqan.localhost`.
- Accounts are per academy (identity lives in every tenant schema). Etqan staff accounts live in the `public` schema.
- Dashboard calls the API same-origin at `/api/v1/`. No shared cookie domain, no CORS.
- API stays under `/api/v1/` (Kaleem's versioning test stays).
- Backend coverage floor: **80%**. Dashboard coverage floors: **lines 80, branches 70, functions 70, statements 80**.
- CI keeps only: backend lint + import boundaries + tests, dashboard typecheck + lint + unit tests + build, e2e, secret scan. No deploy job in this plan.
- Dev-only fixed password for seeded accounts: `e2e-EtqanTest-2026`.
- Every commit message uses Conventional Commits (the pre-commit hook enforces it) and ends with:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

## Review Focus

- **A request to a host with no academy** (typo subdomain, `nope.etqan.localhost`) must get a 404, never another academy's data or the public admin. Test pinned in Task 9.
- **A session cookie or login from academy A presented to academy B** must be anonymous/401-403 in B. Tests pinned in Task 9.
- **A suspended academy** must be blocked on every API route but still answer `/health/`. Test pinned in Task 9.
- **Password-reset and invite links emailed from inside an academy** must point at that academy's host, not a global URL. Test pinned in Task 7.
- **Creating an academy with a bad, reserved, or duplicate subdomain** must fail with a clear message and leave no half-created schema. Tests pinned in Task 8.

---

## File Structure (end state of this plan)

```
etqan_tutor/                          meta repo (Etqan-agency/etqan_tutor, trunk master)
  .gitmodules                          backend, dashboard, infra, tokens → Etqan-agency forks
  justfile                             rebranded; seed → seed_dev; cov → etqan
  docker-compose.local.yml             traefik wildcard *.etqan.localhost; no signaling/marketing
  .env.example
  .github/workflows/ci.yml             rewritten, 6 jobs
  scripts/check-token-pin.mjs          consumers = dashboard only
  README.md, CLAUDE.md, STATE.md       rewritten for etqan_tutor
  docs/PHASE_1_SYSTEM_AUDIT.md, docs/PHASE_2_SYSTEM_DESIGN.md
  docs/superpowers/specs/2026-09-23-etqan-tutor-v1-design.md
  docs/superpowers/plans/2026-09-23-plan-1-fork-strip-tenancy.md
  docs/kaleem-archive/                 all of Kaleem's docs/ moved here, untouched
backend/                               Etqan-agency/etqan_tutor_backend
  conftest.py                          NEW: session tenants + autouse tenant schema
  config/settings/{base,local,test,production}.py
  config/urls.py                       tenant URLconf (api, accounts, health)
  config/urls_public.py                NEW: public URLconf (admin, health)
  config/api_router.py                 identity only
  etqan/platform/frontend.py           NEW: frontend_url()
  etqan/identity/...                   User.role added; create_academy_admin()
  etqan/tenants/                       NEW app
    apps.py models.py services.py admin.py middleware.py
    management/commands/{create_academy.py, seed_dev.py}
    migrations/0001_initial.py
    tests/{test_models.py,test_services.py,test_admin.py,test_middleware.py,
           test_isolation.py,test_commands.py,test_frontend_url.py}
dashboard/                             Etqan-agency/etqan_tutor_dashboard
  src/features/{identity,shell,notifications(empty)}  others deleted
  src/routes/_authed/{index,account,family}.tsx
  e2e/{fixtures.ts, tenant-login.spec.ts, design-preview.spec.ts}
infra/                                 Etqan-agency/etqan_tutor_infra  (coturn/signaling/marketing removed)
tokens/                                Etqan-agency/etqan_tutor_tokens (@etqan/tokens v0.3.0)
```

---

### Task 1: Create the forks and the local workspace

**Files:**
- Create: GitHub repos `Etqan-agency/{etqan_tutor,etqan_tutor_backend,etqan_tutor_dashboard,etqan_tutor_infra,etqan_tutor_tokens}`
- Modify: `.gitmodules`
- Move: `PHASE_1_SYSTEM_AUDIT.md`, `PHASE_2_SYSTEM_DESIGN.md` → `docs/`; Kaleem `docs/*` → `docs/kaleem-archive/`

**Interfaces:**
- Produces: a working tree at `/home/abdulkhalek/Projects/etqan_tutor` that is a clone of `Etqan-agency/etqan_tutor` with four submodules checked out on branch `feat/etqan-foundation`. Every later task commits on that branch in the relevant repo.

- [ ] **Step 1: Fork each repo into the org (fallback to mirror if forking private repos is blocked)**

```bash
set -euo pipefail
for pair in "Kaleem:etqan_tutor" "backend:etqan_tutor_backend" "dashboard:etqan_tutor_dashboard" "infra:etqan_tutor_infra" "tokens:etqan_tutor_tokens"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  if gh repo fork "kaleem-lms/$src" --org Etqan-agency --fork-name "$dst" --clone=false; then
    echo "forked $src -> $dst"
  else
    echo "fork refused for $src; mirroring instead"
    gh repo create "Etqan-agency/$dst" --private
    tmp="$(mktemp -d)"
    git clone --mirror "https://github.com/kaleem-lms/$src.git" "$tmp/$src.git"
    git -C "$tmp/$src.git" push --mirror "https://github.com/Etqan-agency/$dst.git"
    rm -rf "$tmp"
  fi
done
gh repo list Etqan-agency --limit 50 | grep -E "etqan_tutor|etqan-(backend|dashboard|infra|tokens)"
```

Expected: five lines listing the new repos.

- [ ] **Step 2: Turn the current folder into a clone of the meta fork**

The folder already holds `PHASE_*.md` and `docs/superpowers/` (spec + this plan); none of those paths exist in Kaleem, so checkout does not collide.

```bash
cd /home/abdulkhalek/Projects/etqan_tutor
git init -b master
git remote add origin https://github.com/Etqan-agency/etqan_tutor.git
git fetch origin
git checkout -t origin/master
git switch -c feat/etqan-foundation
```

- [ ] **Step 3: Repoint submodules, drop marketing, check out every submodule**

Replace `.gitmodules` entirely with:

```ini
[submodule "backend"]
	path = backend
	url = https://github.com/Etqan-agency/etqan_tutor_backend.git
[submodule "dashboard"]
	path = dashboard
	url = https://github.com/Etqan-agency/etqan_tutor_dashboard.git
[submodule "infra"]
	path = infra
	url = https://github.com/Etqan-agency/etqan_tutor_infra.git
[submodule "tokens"]
	path = tokens
	url = https://github.com/Etqan-agency/etqan_tutor_tokens.git
```

```bash
git rm -r --cached marketing && rm -rf marketing .git/modules/marketing
git submodule sync
git submodule update --init
for s in backend dashboard infra; do git -C "$s" switch -c feat/etqan-foundation origin/main; done
git -C tokens fetch origin main && git -C tokens switch -c feat/etqan-foundation origin/main
git submodule status
```

Expected: four submodules, each showing `feat/etqan-foundation` when you run `git -C <s> branch --show-current`.

- [ ] **Step 4: Archive Kaleem docs and file the etqan docs**

```bash
mkdir -p docs/kaleem-archive
for p in docs/*; do
  case "$p" in docs/kaleem-archive|docs/superpowers) ;; *) git mv "$p" docs/kaleem-archive/ ;; esac
done
# Kaleem's own superpowers journal/plans/specs go to the archive too; ours stay.
mkdir -p docs/kaleem-archive/superpowers
for d in journal; do git mv "docs/superpowers/$d" docs/kaleem-archive/superpowers/ 2>/dev/null || true; done
for f in $(git ls-files docs/superpowers/plans docs/superpowers/specs); do
  mkdir -p "docs/kaleem-archive/$(dirname "${f#docs/}")"; git mv "$f" "docs/kaleem-archive/${f#docs/}"
done
git mv ISSUES.md docs/kaleem-archive/ISSUES.md
git mv tasks.todo docs/kaleem-archive/tasks.todo
mv PHASE_1_SYSTEM_AUDIT.md PHASE_2_SYSTEM_DESIGN.md docs/
git add docs .gitmodules
git status --short | head -20
```

Expected: `docs/superpowers/specs/2026-09-23-etqan-tutor-v1-design.md` and `docs/superpowers/plans/2026-09-23-plan-1-fork-strip-tenancy.md` are the only files left under `docs/superpowers/`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: fork kaleem as etqan_tutor, drop marketing, archive kaleem docs

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: USER ACTION — CI secrets**

Tell the user: the org needs one fine-grained PAT with **read** access to `Etqan-agency/etqan_tutor_backend`, `etqan_tutor_dashboard`, `etqan_tutor_infra`, `etqan_tutor_tokens`. Ask them to run:

```bash
gh secret set SUBMODULE_TOKEN --repo Etqan-agency/etqan_tutor
gh secret set TOKENS_REPO_TOKEN --repo Etqan-agency/etqan_tutor
gh secret set TOKENS_REPO_TOKEN --repo Etqan-agency/etqan_tutor_dashboard
```

Do not create or paste tokens yourself. Continue with Task 2 while waiting; CI is only needed in Task 13.

---

### Task 2: Rename the tokens package to `@etqan/tokens`

**Files:**
- Modify: `tokens/package.json`, `tokens/README.md`, `tokens/build.mjs`, `tokens/tokens.css`, `tokens/src/color.primitive.tokens.json`, `tokens/.github/workflows/ci.yml`

**Interfaces:**
- Produces: tag `v0.3.0` on `Etqan-agency/etqan_tutor_tokens` exporting `@etqan/tokens/tokens.css`, `@etqan/tokens/theme.css`, `@etqan/tokens/contrast.mjs` (same files as before, new package name).

- [ ] **Step 1: Rename**

```bash
cd tokens
sed -i -e 's/@kaleem\/tokens/@etqan\/tokens/g' -e 's/\bkaleem-lms\b/Etqan-agency/g' \
       -e 's/\bKaleem\b/Etqan/g' -e 's/\bkaleem\b/etqan/g' \
       package.json README.md build.mjs src/color.primitive.tokens.json .github/workflows/ci.yml
node -e 'const p=require("./package.json"); p.version="0.3.0"; require("fs").writeFileSync("package.json", JSON.stringify(p,null,2)+"\n")'
grep -rn -i kaleem --exclude-dir=node_modules . || echo "no kaleem left"
```

- [ ] **Step 2: Rebuild and run the package's own checks**

Run: `node build.mjs && node build.mjs --check && node --test`
Expected: build writes `tokens.css` with the `etqan` header comment; `--check` exits 0; all `node --test` tests pass.

- [ ] **Step 3: Commit, push, tag**

```bash
git add -A
git commit -m "chore: rename package to @etqan/tokens v0.3.0

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/etqan-foundation
# Tag the feature-branch head; the PR is merged later, with the user's approval, in Task 15.
git tag v0.3.0 && git push origin v0.3.0
gh pr create --repo Etqan-agency/etqan_tutor_tokens --base main --head feat/etqan-foundation \
  --title "chore: rename package to @etqan/tokens v0.3.0" \
  --body $'Rename for the etqan_tutor fork.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)'
cd ..
```

---

### Task 3: Strip the backend down to identity + platform

**Files:**
- Delete: `backend/kaleem/billing/`, `backend/kaleem/curriculum/`, `backend/kaleem/scheduling/`, `backend/signaling/`, `backend/tests/stripe_clock/`, `backend/tests/test_marker_deselection.py`, `backend/tests/settings/test_cookie_domain.py`
- Modify: `backend/config/settings/{base,local,test,production}.py`, `backend/config/api_router.py`, `backend/pyproject.toml`, `backend/requirements/{base,local}.txt`, `backend/Dockerfile`, `backend/tests/settings/{test_allowed_hosts,test_sentry}.py`

**Interfaces:**
- Produces: a backend whose only local apps are `kaleem.platform` and `kaleem.identity` (renamed in Task 4), with a green test suite.

- [ ] **Step 1: Delete the removed apps and their tests**

```bash
cd backend
git rm -r -q kaleem/billing kaleem/curriculum kaleem/scheduling signaling \
  tests/stripe_clock tests/test_marker_deselection.py tests/settings/test_cookie_domain.py
```

- [ ] **Step 2: Clean `config/settings/base.py`**

Make these exact edits:
1. Delete line `import stripe`.
2. `LOCAL_APPS = ["kaleem.platform", "kaleem.identity"]`.
3. Delete the whole `# BILLING` block containing `BILLING_WEBHOOK_SILENCE_HOURS`.
4. Replace the whole `CELERY_BEAT_SCHEDULE = {...}` dict (and the 4 comment lines above it) with:
   ```python
   # Periodic jobs are declared here as they are built (none yet).
   CELERY_BEAT_SCHEDULE: dict = {}
   ```
   and delete `from celery.schedules import crontab` (now unused).
5. Delete the second `# BILLING` block (`BILLING_PAYMENT_PROVIDER` … `STRIPE_API_VERSION`), and the `# VIDEO`, signaling and `# TURN` blocks (`VIDEO_PROVIDER`, `SIGNALING_SECRET`, `SIGNALING_URL`, `TURN_SECRET`, `TURN_URLS`).
6. In `REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]` keep only `"email": "5/hour"`.

- [ ] **Step 3: Clean the other settings modules**

- `config/settings/test.py`: delete the whole `REST_FRAMEWORK = {...}` override block and its comment (the only override was `call-diagnostics`).
- `config/settings/local.py`: delete the whole `REST_FRAMEWORK = {...}` override block and the long comment above it.
- `config/settings/production.py`: delete the two `STRIPE_*` lines and the comment line above them.
- `tests/settings/test_allowed_hosts.py` and `tests/settings/test_sentry.py`: delete the two `monkeypatch.setenv("DJANGO_STRIPE_…")` lines in each.

- [ ] **Step 4: Clean URLs**

In `config/api_router.py` delete the three `path(...)` lines for `billing/`, `scheduling/`, `curriculum/`.

- [ ] **Step 5: Clean dependencies and Docker**

- `requirements/base.txt`: delete the `stripe…`, `starlette…`, `uvicorn[standard]…` lines.
- `requirements/local.txt`: delete the `httpx2…` line.
- `Dockerfile`: in the production `collectstatic` `RUN`, delete the `DJANGO_STRIPE_SECRET_KEY=…` and `DJANGO_STRIPE_WEBHOOK_SECRET=…` lines.

- [ ] **Step 6: Clean `pyproject.toml`**

1. `[tool.pytest.ini_options]` becomes:
   ```toml
   [tool.pytest.ini_options]
   minversion = "6.0"
   addopts = "--ds=config.settings.test --reuse-db --import-mode=importlib"
   python_files = ["tests.py", "test_*.py"]
   ```
2. Replace everything from `[tool.coverage.run]` through the end of `[tool.coverage.report]` with:
   ```toml
   [tool.coverage.run]
   include = ["kaleem/**"]
   omit = ["*/migrations/*", "*/tests/*"]
   branch = true

   [tool.coverage.report]
   precision = 1
   fail_under = 80.0
   show_missing = true
   ```
3. Replace everything from `[tool.importlinter]` to the end of the file with:
   ```toml
   [tool.importlinter]
   root_packages = ["kaleem"]

   [[tool.importlinter.contracts]]
   name = "platform imports no business modules"
   type = "forbidden"
   source_modules = ["kaleem.platform"]
   forbidden_modules = ["kaleem.identity"]
   ```

- [ ] **Step 7: Run the suite and the linters**

Run (Postgres must be up: `docker compose -f ../docker-compose.local.yml up -d postgres redis`):
```bash
pip install -r requirements/local.txt
export DATABASE_URL=postgres://kaleem:kaleem@localhost:5432/kaleem
pytest --create-db -q
ruff check . && ruff format --check . && lint-imports
```
Expected: all identity/platform tests pass (≈210); ruff clean; `lint-imports` reports 1 contract kept. If `ruff` flags now-unused imports in settings, delete them.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: remove billing, curriculum, scheduling and signaling

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 4: Rename the backend package and brand to etqan

**Files:**
- Move: `backend/kaleem/` → `backend/etqan/`
- Modify: every text file in `backend/` that says `kaleem`/`Kaleem`, including `pyproject.toml`, `config/**`, `etqan/**`, `tests/**`, `Dockerfile`, `.env.example`, `CLAUDE.md`, `etqan/templates/account/email/*.txt`, `etqan/identity/migrations/0003_set_site_name_domain.py`
- Rename in code: class `KaleemError` → `EtqanError`

**Interfaces:**
- Produces: importable package `etqan` (`etqan.platform`, `etqan.identity`); `etqan.platform.exceptions.EtqanError(message: str, code: str = "error")` with `.message` and `.code`.

- [ ] **Step 1: Move and rewrite**

```bash
cd backend
git mv kaleem etqan
grep -rlI -i --exclude-dir=.git --exclude-dir=.venv 'kaleem' . \
  | xargs sed -i -e 's/KaleemError/EtqanError/g' -e 's/\bKALEEM\b/ETQAN/g' \
                 -e 's/\bKaleem\b/Etqan/g' -e 's/\bkaleem\b/etqan/g' -e 's/kaleem\.academy/etqan.academy/g'
grep -rnI -i --exclude-dir=.git 'kaleem' . || echo "clean"
```

Expected: `clean`. (`kaleem-lms` in comments becomes `etqan-lms`; fix any such URL by hand to `Etqan-agency` if the grep in Step 2 shows one.)

- [ ] **Step 2: Check leftovers that sed cannot judge**

Run: `grep -rnI 'etqan-lms\|etqan\.localhost\|app\.etqan\|api\.etqan' --exclude-dir=.git . | head -30`
These are the old Kaleem hostnames now spelled etqan (e.g. `app.etqan.localhost` in `config/settings/local.py`, `base.py` `FRONTEND_URL` default, `tests/test_local_settings.py`). Leave them — Task 10 rewrites the host model. Replace any `etqan-lms` GitHub URL with `Etqan-agency`.

- [ ] **Step 3: Run the suite and the linters**

Run: `pytest --create-db -q && ruff check . && ruff format --check . && lint-imports`
Expected: same pass count as Task 3, all clean. (`--create-db` because migration module paths changed.)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename python package kaleem to etqan and rebrand

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 5: Add a single `role` to every user

**Files:**
- Modify: `backend/etqan/identity/models.py`, `backend/etqan/identity/services.py`, `backend/etqan/identity/api/views.py`
- Create: `backend/etqan/identity/migrations/0009_user_role.py` (generated)
- Test: `backend/etqan/identity/tests/test_roles.py`

**Interfaces:**
- Produces: `User.Role` TextChoices `ADMIN="admin"`, `TEACHER="teacher"`, `STUDENT="student"`, `PARENT="parent"`; field `User.role` (default `"student"`); `/api/v1/identity/me/` payload gains `"role": str`; `register_user` sets role = `account_type`; `create_teacher_account` sets `teacher`; `create_child` sets `student`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/identity/tests/test_roles.py`:

```python
import pytest
from rest_framework.test import APIClient

from etqan.identity import services
from etqan.identity.models import User


@pytest.mark.django_db
def test_register_student_gets_student_role():
    user = services.register_user("Sara", "sara@example.com", "pw-12345678", "student")
    assert user.role == User.Role.STUDENT


@pytest.mark.django_db
def test_register_parent_gets_parent_role():
    user = services.register_user("Pat", "pat@example.com", "pw-12345678", "parent")
    assert user.role == User.Role.PARENT


@pytest.mark.django_db
def test_teacher_account_gets_teacher_role():
    user = services.create_teacher_account("t@example.com", "Tariq")
    assert user.role == User.Role.TEACHER


@pytest.mark.django_db
def test_me_includes_role():
    user = User.objects.create_user(
        email="a@example.com", password="pw-12345678", role=User.Role.ADMIN
    )
    client = APIClient()
    client.force_login(user)
    resp = client.get("/api/v1/identity/me/")
    assert resp.status_code == 200
    assert resp.data["role"] == "admin"
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest etqan/identity/tests/test_roles.py -q`
Expected: FAIL — `AttributeError: type object 'User' has no attribute 'Role'`.

- [ ] **Step 3: Implement**

In `etqan/identity/models.py`, inside `class User`, directly after the class docstring:

```python
    class Role(models.TextChoices):
        ADMIN = "admin", "Admin"
        TEACHER = "teacher", "Teacher"
        STUDENT = "student", "Student"
        PARENT = "parent", "Parent"
```

and after the `timezone` field:

```python
    role = models.CharField(max_length=16, choices=Role.choices, default=Role.STUDENT)
```

In `etqan/identity/services.py`:
- `register_user`: change the create call to
  `User.objects.create_user(email=email, password=password, full_name=full_name, birthdate=birthdate, role=account_type)`.
- `create_teacher_account`: `User.objects.create_user(email=email, full_name=full_name, role=User.Role.TEACHER)`.
- `create_child`: find its `User.objects.create_user(` call and add `role=User.Role.STUDENT` to it.

In `etqan/identity/api/views.py` `_me_payload`, add `"role": user.role,` after `"full_name": user.full_name,`.

Then: `python manage.py makemigrations identity --name user_role`

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `pytest etqan/identity/tests/test_roles.py -q && pytest -q`
Expected: 4 passed; full suite passes. If an existing `/me` test asserts the exact payload dict, add `"role": "<expected role>"` to that expected dict.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(identity): add a single role per user and expose it on /me

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 6: Install django-tenants with an `Academy` tenant model

**Files:**
- Create: `backend/etqan/tenants/__init__.py`, `apps.py`, `models.py`, `services.py`, `migrations/__init__.py`, `migrations/0001_initial.py` (generated), `tests/__init__.py`, `tests/test_models.py`
- Create: `backend/conftest.py`, `backend/config/urls_public.py`
- Modify: `backend/requirements/base.txt`, `backend/config/settings/{base,test}.py`, `backend/config/urls.py`, `backend/pyproject.toml` (import-linter)
- Delete: `backend/etqan/identity/management/commands/seed_e2e.py`, `backend/etqan/identity/tests/test_seed_e2e.py` (replaced by `seed_dev` in Task 10)

**Interfaces:**
- Produces:
  - `etqan.tenants.models.Academy(TenantMixin)` fields: `name: str`, `subdomain: str|None` (unique, null for public), `status: "active"|"suspended"` (`Academy.Status`), `timezone: str="UTC"`, `currency: str="USD"`, `plan_label: str`, `plan_notes: str`, `created_at`; `auto_create_schema=True`, `auto_drop_schema=False`.
  - `etqan.tenants.models.Domain(DomainMixin)`.
  - `etqan.tenants.services.ensure_public_tenant() -> Academy` (idempotent; domains `TENANT_BASE_DOMAIN` + `PUBLIC_EXTRA_DOMAINS`).
  - Settings: `TENANT_BASE_DOMAIN`, `PUBLIC_EXTRA_DOMAINS`, `TENANT_URL_TEMPLATE`.
  - pytest fixture `tenants` (session) → `SimpleNamespace(public, main, other)`; `main` is served at host `testserver`, `other` at `pytest-other.etqan.localhost`; every test runs with `connection` set to `main` unless it switches.

- [ ] **Step 1: Dependency**

Append to `requirements/base.txt`: `django-tenants>=3.7,<4.0` then `pip install -r requirements/local.txt`.

- [ ] **Step 2: Create the app skeleton and models**

`etqan/tenants/__init__.py`: empty. `etqan/tenants/migrations/__init__.py`: empty. `etqan/tenants/tests/__init__.py`: empty.

`etqan/tenants/apps.py`:

```python
from django.apps import AppConfig


class TenantsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.tenants"
    label = "tenants"
```

`etqan/tenants/models.py`:

```python
from django.db import models
from django_tenants.models import DomainMixin
from django_tenants.models import TenantMixin


class Academy(TenantMixin):
    """One customer academy = one PostgreSQL schema. The public schema is also a row."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        SUSPENDED = "suspended", "Suspended"

    name = models.CharField(max_length=200)
    subdomain = models.SlugField(max_length=63, unique=True, null=True, blank=True)
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.ACTIVE
    )
    timezone = models.CharField(max_length=64, default="UTC")
    currency = models.CharField(max_length=3, default="USD")
    plan_label = models.CharField(max_length=100, blank=True, default="")
    plan_notes = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    auto_create_schema = True
    auto_drop_schema = False

    class Meta:
        verbose_name_plural = "academies"

    def __str__(self):
        return self.name


class Domain(DomainMixin):
    pass
```

`etqan/tenants/services.py` (first version; Task 8 extends it):

```python
"""Public API for the tenants module."""

from django.conf import settings
from django_tenants.utils import get_public_schema_name

from etqan.tenants.models import Academy
from etqan.tenants.models import Domain


def ensure_public_tenant() -> Academy:
    """Create the public-schema tenant row and its domains if missing. Idempotent."""
    public, _ = Academy.objects.get_or_create(
        schema_name=get_public_schema_name(), defaults={"name": "Etqan"}
    )
    hosts = [settings.TENANT_BASE_DOMAIN, *settings.PUBLIC_EXTRA_DOMAINS]
    for index, host in enumerate(hosts):
        Domain.objects.get_or_create(
            domain=host, defaults={"tenant": public, "is_primary": index == 0}
        )
    return public
```

- [ ] **Step 3: Settings**

In `config/settings/base.py`:

1. After `DATABASES["default"]["ATOMIC_REQUESTS"] = True` add:
   ```python
   DATABASES["default"]["ENGINE"] = "django_tenants.postgresql_backend"
   DATABASE_ROUTERS = ("django_tenants.routers.TenantSyncRouter",)
   ```
2. Replace the `DJANGO_APPS` / `THIRD_PARTY_APPS` / `LOCAL_APPS` / `INSTALLED_APPS` block with:
   ```python
   # TENANCY (django-tenants): SHARED_APPS migrate into the public schema,
   # TENANT_APPS into every academy schema. identity is in both: Etqan staff
   # accounts live in public, academy accounts in each academy schema.
   SHARED_APPS = [
       "django_tenants",
       "etqan.tenants",
       "django.contrib.contenttypes",
       "django.contrib.auth",
       "django.contrib.sessions",
       "django.contrib.sites",
       "django.contrib.messages",
       "django.contrib.staticfiles",
       "django.contrib.admin",
       "django.forms",
       "allauth",
       "allauth.account",
       "allauth.mfa",
       "allauth.socialaccount",
       "django_celery_beat",
       "rest_framework",
       "corsheaders",
       "drf_spectacular",
       "etqan.platform",
       "etqan.identity",
   ]
   TENANT_APPS = [
       "django.contrib.contenttypes",
       "django.contrib.auth",
       "django.contrib.sessions",
       "django.contrib.sites",
       "django.contrib.admin",
       "django.contrib.messages",
       "allauth",
       "allauth.account",
       "allauth.mfa",
       "allauth.socialaccount",
       "etqan.identity",
   ]
   INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
   TENANT_MODEL = "tenants.Academy"
   TENANT_DOMAIN_MODEL = "tenants.Domain"
   PUBLIC_SCHEMA_URLCONF = "config.urls_public"
   TENANT_BASE_DOMAIN = env("DJANGO_TENANT_BASE_DOMAIN", default="etqan.localhost")
   PUBLIC_EXTRA_DOMAINS = env.list(
       "DJANGO_PUBLIC_EXTRA_DOMAINS", default=["localhost", "127.0.0.1"]
   )
   # How an academy's dashboard URL is built from its domain (emails use it).
   TENANT_URL_TEMPLATE = env("DJANGO_TENANT_URL_TEMPLATE", default="http://{domain}")
   ```
3. Make `"django_tenants.middleware.main.TenantMainMiddleware"` the **first** entry of `MIDDLEWARE`.
4. In `CACHES["default"]` add:
   ```python
       "KEY_FUNCTION": "django_tenants.cache.make_key",
       "REVERSE_KEY_FUNCTION": "django_tenants.cache.reverse_key",
   ```
5. Change the `FRONTEND_URL` default to `"http://etqan.localhost"` (it is now only the public/staff fallback).

In `config/settings/test.py`:
- Add `KEY_FUNCTION`/`REVERSE_KEY_FUNCTION` (same two lines) inside the LocMemCache dict.
- Add at the end:
  ```python
  ALLOWED_HOSTS = ["testserver", ".etqan.localhost", "etqan.localhost", "localhost"]
  TENANT_BASE_DOMAIN = "etqan.localhost"
  PUBLIC_EXTRA_DOMAINS = ["localhost"]
  TENANT_URL_TEMPLATE = "http://{domain}"
  ```

- [ ] **Step 4: Split URLconfs**

`config/urls.py` (academy hosts) — remove the `path(settings.ADMIN_URL, admin.site.urls)` line and the `from django.contrib import admin` import. Everything else stays.

`config/urls_public.py` (bare domain, Etqan staff):

```python
from django.conf import settings
from django.contrib import admin
from django.urls import path

from etqan.platform.views import health_live
from etqan.platform.views import health_ready

admin.site.site_header = "Etqan — academies"
admin.site.site_title = "Etqan admin"

urlpatterns = [
    path(settings.ADMIN_URL, admin.site.urls),
    path("health/live/", health_live, name="health-live"),
    path("health/ready/", health_ready, name="health-ready"),
]
```

- [ ] **Step 5: Import boundaries**

Append to `pyproject.toml`:

```toml
[[tool.importlinter.contracts]]
name = "identity does not import tenants"
type = "forbidden"
source_modules = ["etqan.identity"]
forbidden_modules = ["etqan.tenants"]
```

and add `"etqan.tenants"` to the platform contract's `forbidden_modules`.

- [ ] **Step 6: Remove Kaleem's e2e seed**

```bash
git rm -q etqan/identity/management/commands/seed_e2e.py etqan/identity/tests/test_seed_e2e.py
```

- [ ] **Step 7: Root conftest that runs every test inside a test academy**

`backend/conftest.py`:

```python
"""Every test runs inside a real academy schema.

`main` is mapped to the host `testserver` (the Django test client's default host),
so existing API tests hit an academy without changes. `other` exists for
cross-academy isolation tests. Both are created once per session, outside the
per-test transaction, and reused across `--reuse-db` runs.
"""

from types import SimpleNamespace

import pytest
from django.db import connection

MAIN = ("pytest_main", "Pytest Main Academy", "pytest-main", "testserver")
OTHER = (
    "pytest_other",
    "Pytest Other Academy",
    "pytest-other",
    "pytest-other.etqan.localhost",
)


def _get_or_create_academy(schema, name, subdomain, host):
    from etqan.tenants.models import Academy
    from etqan.tenants.models import Domain

    academy = Academy.objects.filter(schema_name=schema).first()
    if academy is None:
        academy = Academy.objects.create(
            schema_name=schema, name=name, subdomain=subdomain
        )
    Domain.objects.get_or_create(
        domain=host, defaults={"tenant": academy, "is_primary": True}
    )
    return academy


@pytest.fixture(scope="session")
def tenants(django_db_setup, django_db_blocker):
    from etqan.tenants.services import ensure_public_tenant

    with django_db_blocker.unblock():
        connection.set_schema_to_public()
        public = ensure_public_tenant()
        main = _get_or_create_academy(*MAIN)
        other = _get_or_create_academy(*OTHER)
        connection.set_schema_to_public()
    return SimpleNamespace(public=public, main=main, other=other)


@pytest.fixture(autouse=True)
def _academy_schema(tenants):
    connection.set_tenant(tenants.main)
    yield
    connection.set_schema_to_public()
```

- [ ] **Step 8: Write the model test**

`etqan/tenants/tests/test_models.py`:

```python
import pytest
from django.db import connection
from django_tenants.utils import schema_exists

from etqan.identity.models import User


@pytest.mark.django_db
def test_test_academies_have_their_own_schemas(tenants):
    assert schema_exists(tenants.main.schema_name)
    assert schema_exists(tenants.other.schema_name)
    assert tenants.main.status == "active"


@pytest.mark.django_db
def test_public_tenant_serves_the_base_domain(tenants):
    domains = set(tenants.public.domains.values_list("domain", flat=True))
    assert {"etqan.localhost", "localhost"} <= domains


@pytest.mark.django_db
def test_users_are_per_schema(tenants):
    User.objects.create_user(email="only-in-main@example.com", password="pw-12345678")
    connection.set_tenant(tenants.other)
    assert not User.objects.filter(email="only-in-main@example.com").exists()
```

- [ ] **Step 9: Generate the migration and run everything**

```bash
python manage.py makemigrations tenants
pytest --create-db -q
ruff check . && ruff format --check . && lint-imports
```

Expected: new tests pass and the whole pre-existing identity suite still passes, now running inside `pytest_main`. `tests/test_api_versioning_is_enforced.py` still passes (it walks `ROOT_URLCONF`, the academy URLconf). If `tests/test_local_settings.py` fails, leave it — Task 10 rewrites it — but note it; nothing else may fail.

If schema creation errors with "cannot create tenant inside a transaction" (it should not with pytest-django's `django_db_blocker`), stop and report the exact error rather than working around it.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat(tenants): schema-per-academy tenancy with django-tenants

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 7: Links in emails point at the academy's own host

**Files:**
- Create: `backend/etqan/platform/frontend.py`, `backend/etqan/tenants/tests/test_frontend_url.py`
- Modify: `backend/etqan/identity/services.py` (4 uses), `backend/etqan/identity/adapter.py` (1 use), `backend/etqan/identity/tests/test_adapter.py`, and any identity test that compares against `settings.FRONTEND_URL`

**Interfaces:**
- Produces: `etqan.platform.frontend.frontend_url() -> str` — no trailing slash; academy context → `TENANT_URL_TEMPLATE.format(domain=<primary domain>)`; public context → `settings.FRONTEND_URL`.

- [ ] **Step 1: Write the failing tests**

`etqan/tenants/tests/test_frontend_url.py`:

```python
import pytest
from django.core import mail
from django.db import connection
from django.test import override_settings

from etqan.identity import services
from etqan.identity.models import User
from etqan.platform.frontend import frontend_url


@pytest.mark.django_db
@override_settings(TENANT_URL_TEMPLATE="https://{domain}")
def test_inside_an_academy_the_url_is_that_academys_host(tenants):
    connection.set_tenant(tenants.other)
    assert frontend_url() == "https://pytest-other.etqan.localhost"


@pytest.mark.django_db
@override_settings(FRONTEND_URL="https://etqan.example")
def test_in_public_schema_the_url_is_the_platform_url():
    connection.set_schema_to_public()
    assert frontend_url() == "https://etqan.example"


@pytest.mark.django_db
def test_password_reset_email_links_to_the_academy_host(tenants):
    connection.set_tenant(tenants.other)
    User.objects.create_user(email="r@example.com", password="pw-12345678")
    services.request_password_reset("r@example.com")
    assert len(mail.outbox) == 1
    assert "http://pytest-other.etqan.localhost/reset-password?uid=" in mail.outbox[0].body
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest etqan/tenants/tests/test_frontend_url.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'etqan.platform.frontend'`.

- [ ] **Step 3: Implement**

`etqan/platform/frontend.py`:

```python
"""Where the dashboard lives for whoever we are serving right now."""

from django.conf import settings
from django.db import connection
from django_tenants.utils import get_public_schema_name


def frontend_url() -> str:
    """Base URL of the dashboard for the current academy, or the platform URL."""
    tenant = getattr(connection, "tenant", None)
    if tenant is None or tenant.schema_name == get_public_schema_name():
        return settings.FRONTEND_URL.rstrip("/")
    domain = tenant.get_primary_domain()
    if domain is None:
        return settings.FRONTEND_URL.rstrip("/")
    return settings.TENANT_URL_TEMPLATE.format(domain=domain.domain).rstrip("/")
```

Replace every `settings.FRONTEND_URL` in `etqan/identity/services.py` (lines that build `link`, `reset_url`, `review_url`) and `etqan/identity/adapter.py` with `frontend_url()`, adding `from etqan.platform.frontend import frontend_url`. Remove `from django.conf import settings` from `adapter.py` if it becomes unused.

In `etqan/identity/tests/test_adapter.py`, replace `@override_settings(FRONTEND_URL="https://app.example.com")` with `@override_settings(TENANT_URL_TEMPLATE="https://{domain}")` and change the expected prefix `https://app.example.com` to `https://testserver`.

Then run `grep -rn "FRONTEND_URL" etqan/identity/tests` and, in each hit that builds an expected URL, replace `settings.FRONTEND_URL` with `frontend_url()` (import it from `etqan.platform.frontend`).

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `pytest etqan/tenants/tests/test_frontend_url.py -q && pytest -q && ruff check . && lint-imports`
Expected: 3 passed; full suite green; contracts kept.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(platform): build email links from the current academy's host

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 8: Create academies — service, CLI command, and Etqan admin console

**Files:**
- Modify: `backend/etqan/tenants/services.py`, `backend/etqan/identity/services.py`
- Create: `backend/etqan/tenants/admin.py`, `backend/etqan/tenants/management/__init__.py`, `backend/etqan/tenants/management/commands/__init__.py`, `backend/etqan/tenants/management/commands/create_academy.py`
- Test: `backend/etqan/tenants/tests/test_services.py`, `backend/etqan/tenants/tests/test_admin.py`, `backend/etqan/tenants/tests/test_commands.py`

**Interfaces:**
- Consumes: `Academy`, `Domain`, `ensure_public_tenant()` (Task 6); `frontend_url()` (Task 7); `User.Role` (Task 5).
- Produces:
  - `etqan.identity.services.create_academy_admin(email: str, full_name: str = "", password: str | None = None) -> User` — role admin, verified primary email; when `password is None` emails a set-password link.
  - `etqan.tenants.services.validate_subdomain(subdomain: str) -> str` (normalised; raises `etqan.platform.exceptions.ValidationError(field="subdomain")`).
  - `etqan.tenants.services.schema_name_for(subdomain: str) -> str`, `domain_for(subdomain: str) -> str`.
  - `etqan.tenants.services.create_academy(*, name: str, subdomain: str, admin_email: str, admin_full_name: str = "", admin_password: str | None = None, timezone: str = "UTC", currency: str = "USD") -> Academy`.
  - `etqan.tenants.services.set_status(academy_ids: list[int], status: str) -> int` (never touches public).
  - CLI: `python manage.py create_academy --name N --subdomain S --admin-email E [--admin-name A] [--timezone TZ] [--currency CUR]`.

- [ ] **Step 1: Write the failing service tests**

`etqan/tenants/tests/test_services.py`:

```python
import pytest
from django.core import mail
from django.db import connection
from django_tenants.utils import schema_exists
from django_tenants.utils import tenant_context

from etqan.identity.models import User
from etqan.platform.exceptions import ValidationError
from etqan.tenants import services
from etqan.tenants.models import Academy


@pytest.fixture
def in_public():
    connection.set_schema_to_public()


@pytest.mark.django_db
def test_create_academy_makes_schema_domain_and_admin(in_public):
    academy = services.create_academy(
        name="Beta Academy", subdomain="beta", admin_email="boss@beta.test"
    )
    assert academy.schema_name == "academy_beta"
    assert schema_exists("academy_beta")
    assert academy.get_primary_domain().domain == "beta.etqan.localhost"
    with tenant_context(academy):
        admin = User.objects.get(email="boss@beta.test")
        assert admin.role == User.Role.ADMIN
        assert not admin.has_usable_password()
    assert "http://beta.etqan.localhost/reset-password?uid=" in mail.outbox[-1].body


@pytest.mark.django_db
def test_admin_with_password_gets_no_email(in_public):
    academy = services.create_academy(
        name="Gamma", subdomain="gamma", admin_email="g@gamma.test",
        admin_password="pw-12345678",
    )
    with tenant_context(academy):
        assert User.objects.get(email="g@gamma.test").check_password("pw-12345678")
    assert mail.outbox == []


@pytest.mark.django_db
def test_hyphenated_subdomain_gets_underscored_schema(in_public):
    academy = services.create_academy(
        name="Noor", subdomain="noor-quran", admin_email="n@n.test"
    )
    assert academy.schema_name == "academy_noor_quran"


@pytest.mark.django_db
@pytest.mark.parametrize(
    "bad", ["", "UPPER", "-lead", "trail-", "has space", "a" * 33, "dot.ted"]
)
def test_invalid_subdomain_is_rejected(in_public, bad):
    with pytest.raises(ValidationError) as exc:
        services.validate_subdomain(bad)
    assert exc.value.field == "subdomain"


@pytest.mark.django_db
@pytest.mark.parametrize("reserved", ["www", "admin", "api", "public", "mail"])
def test_reserved_subdomain_is_rejected(in_public, reserved):
    with pytest.raises(ValidationError):
        services.validate_subdomain(reserved)


@pytest.mark.django_db
def test_taken_subdomain_is_rejected_and_nothing_is_created(in_public):
    before = Academy.objects.count()
    with pytest.raises(ValidationError):
        services.create_academy(
            name="Dup", subdomain="pytest-other", admin_email="d@d.test"
        )
    assert Academy.objects.count() == before


@pytest.mark.django_db
def test_set_status_never_suspends_public(in_public, tenants):
    changed = services.set_status([tenants.public.pk, tenants.other.pk], "suspended")
    assert changed == 1
    tenants.public.refresh_from_db()
    tenants.other.refresh_from_db()
    assert tenants.public.status == "active"
    assert tenants.other.status == "suspended"
```

Note `"UPPER"` is rejected on purpose: `validate_subdomain` strips whitespace but does **not** lowercase, so an operator sees their typo instead of silently getting a different domain than they typed.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest etqan/tenants/tests/test_services.py -q`
Expected: FAIL — `AttributeError: module 'etqan.tenants.services' has no attribute 'create_academy'`.

- [ ] **Step 3: Implement the identity helper**

Append to `etqan/identity/services.py`:

```python
@transaction.atomic
def create_academy_admin(
    email: str, full_name: str = "", password: str | None = None
) -> User:
    """First admin of a new academy. Must be called inside that academy's schema."""
    if User.objects.filter(email__iexact=email).exists():
        raise ValidationError("A user with this email already exists.", field="email")
    user = User.objects.create_user(
        email=email, password=password, full_name=full_name, role=User.Role.ADMIN
    )
    EmailAddress.objects.create(user=user, email=user.email, primary=True, verified=True)
    if password is None:
        _send_child_set_password_link(user)
    return user
```

- [ ] **Step 4: Implement the tenants service**

Replace `etqan/tenants/services.py` with:

```python
"""Public API for the tenants module."""

import re

from django.conf import settings
from django.db import transaction
from django_tenants.utils import get_public_schema_name
from django_tenants.utils import tenant_context

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.tenants.models import Academy
from etqan.tenants.models import Domain

SUBDOMAIN_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$")
RESERVED_SUBDOMAINS = frozenset(
    {"www", "admin", "api", "app", "public", "static", "media", "mail", "flower",
     "traefik", "etqan"}
)


def ensure_public_tenant() -> Academy:
    """Create the public-schema tenant row and its domains if missing. Idempotent."""
    public, _ = Academy.objects.get_or_create(
        schema_name=get_public_schema_name(), defaults={"name": "Etqan"}
    )
    hosts = [settings.TENANT_BASE_DOMAIN, *settings.PUBLIC_EXTRA_DOMAINS]
    for index, host in enumerate(hosts):
        Domain.objects.get_or_create(
            domain=host, defaults={"tenant": public, "is_primary": index == 0}
        )
    return public


def schema_name_for(subdomain: str) -> str:
    return "academy_" + subdomain.replace("-", "_")


def domain_for(subdomain: str) -> str:
    return f"{subdomain}.{settings.TENANT_BASE_DOMAIN}"


def validate_subdomain(subdomain: str) -> str:
    value = subdomain.strip()
    if not SUBDOMAIN_RE.fullmatch(value):
        raise ValidationError(
            "Use 1-32 lowercase letters, digits or hyphens; "
            "it cannot start or end with a hyphen.",
            field="subdomain",
        )
    if value in RESERVED_SUBDOMAINS:
        raise ValidationError("This subdomain is reserved.", field="subdomain")
    if Academy.objects.filter(subdomain=value).exists():
        raise ValidationError("This subdomain is already taken.", field="subdomain")
    return value


@transaction.atomic
def create_academy(
    *,
    name: str,
    subdomain: str,
    admin_email: str,
    admin_full_name: str = "",
    admin_password: str | None = None,
    timezone: str = "UTC",
    currency: str = "USD",
) -> Academy:
    """Create an academy: schema (migrated), primary domain, and its first admin."""
    value = validate_subdomain(subdomain)
    academy = Academy(
        schema_name=schema_name_for(value),
        name=name,
        subdomain=value,
        timezone=timezone,
        currency=currency,
    )
    academy.save()
    Domain.objects.create(domain=domain_for(value), tenant=academy, is_primary=True)
    with tenant_context(academy):
        identity_services.create_academy_admin(
            email=admin_email, full_name=admin_full_name, password=admin_password
        )
    return academy


def set_status(academy_ids: list[int], status: str) -> int:
    if status not in Academy.Status.values:
        raise ValidationError("Unknown status.", field="status")
    return (
        Academy.objects.filter(pk__in=academy_ids)
        .exclude(schema_name=get_public_schema_name())
        .update(status=status)
    )
```

Also add to `ValidationError` usage expectations: confirm `etqan/platform/exceptions.py` `ValidationError` stores `field` as `self.field` (it does in Kaleem: `ValidationError(message, field=None)`); if it doesn't, add `self.field = field` in its `__init__`.

- [ ] **Step 5: Run the service tests**

Run: `pytest etqan/tenants/tests/test_services.py -q`
Expected: all pass. Each `create_academy` test creates a schema inside the test transaction; PostgreSQL rolls the schema back with it.

- [ ] **Step 6: Write the failing admin + command tests**

`etqan/tenants/tests/test_admin.py`:

```python
import pytest
from django.db import connection
from django_tenants.utils import schema_exists

from etqan.identity.models import User
from etqan.tenants.models import Academy

PUBLIC_HOST = "etqan.localhost"


@pytest.fixture
def staff_client(client):
    connection.set_schema_to_public()
    staff = User.objects.create_superuser(email="ops@etqan.test", password="pw-12345678")
    client.force_login(staff)
    return client


@pytest.mark.django_db
def test_admin_is_served_on_the_public_host(staff_client):
    resp = staff_client.get("/admin/tenants/academy/", HTTP_HOST=PUBLIC_HOST)
    assert resp.status_code == 200


@pytest.mark.django_db
def test_admin_is_not_served_on_an_academy_host(client):
    resp = client.get("/admin/", HTTP_HOST="testserver")
    assert resp.status_code == 404


@pytest.mark.django_db
def test_adding_an_academy_through_admin_creates_it(staff_client):
    resp = staff_client.post(
        "/admin/tenants/academy/add/",
        {
            "name": "Delta Academy",
            "subdomain": "delta",
            "timezone": "Africa/Cairo",
            "currency": "EGP",
            "plan_label": "Starter",
            "plan_notes": "",
            "admin_email": "admin@delta.test",
            "admin_full_name": "Delta Admin",
        },
        HTTP_HOST=PUBLIC_HOST,
    )
    assert resp.status_code == 302, resp.content[:2000]
    connection.set_schema_to_public()
    academy = Academy.objects.get(subdomain="delta")
    assert academy.plan_label == "Starter"
    assert academy.currency == "EGP"
    assert schema_exists("academy_delta")


@pytest.mark.django_db
def test_admin_rejects_a_reserved_subdomain(staff_client):
    resp = staff_client.post(
        "/admin/tenants/academy/add/",
        {"name": "X", "subdomain": "admin", "timezone": "UTC", "currency": "USD",
         "plan_label": "", "plan_notes": "", "admin_email": "x@x.test",
         "admin_full_name": ""},
        HTTP_HOST=PUBLIC_HOST,
    )
    assert resp.status_code == 200
    assert b"This subdomain is reserved." in resp.content


@pytest.mark.django_db
def test_suspend_action(staff_client, tenants):
    resp = staff_client.post(
        "/admin/tenants/academy/",
        {"action": "suspend_academies", "_selected_action": [tenants.other.pk]},
        HTTP_HOST=PUBLIC_HOST,
    )
    assert resp.status_code == 302
    connection.set_schema_to_public()
    tenants.other.refresh_from_db()
    assert tenants.other.status == "suspended"
```

`etqan/tenants/tests/test_commands.py`:

```python
import pytest
from django.core.management import call_command
from django.db import connection

from etqan.tenants.models import Academy


@pytest.mark.django_db
def test_create_academy_command():
    connection.set_schema_to_public()
    call_command(
        "create_academy", "--name", "Epsilon", "--subdomain", "epsilon",
        "--admin-email", "e@e.test", "--timezone", "Asia/Riyadh", "--currency", "SAR",
    )
    connection.set_schema_to_public()
    academy = Academy.objects.get(subdomain="epsilon")
    assert academy.timezone == "Asia/Riyadh"
    assert academy.currency == "SAR"
```

- [ ] **Step 7: Run to verify failure**

Run: `pytest etqan/tenants/tests/test_admin.py etqan/tenants/tests/test_commands.py -q`
Expected: FAIL — admin URL 404 (`Academy` not registered) and `Unknown command: 'create_academy'`.

- [ ] **Step 8: Implement the admin**

`etqan/tenants/admin.py`:

```python
from django import forms
from django.contrib import admin
from django.contrib import messages

from etqan.platform.exceptions import ValidationError as EtqanValidationError
from etqan.tenants import services
from etqan.tenants.models import Academy


class AcademyCreationForm(forms.ModelForm):
    admin_email = forms.EmailField(help_text="The academy's first admin; gets a set-password email.")
    admin_full_name = forms.CharField(required=False)

    class Meta:
        model = Academy
        fields = ["name", "subdomain", "timezone", "currency", "plan_label", "plan_notes"]

    def clean_subdomain(self):
        try:
            return services.validate_subdomain(self.cleaned_data.get("subdomain") or "")
        except EtqanValidationError as exc:
            raise forms.ValidationError(exc.message) from exc


@admin.register(Academy)
class AcademyAdmin(admin.ModelAdmin):
    list_display = ["name", "subdomain", "status", "plan_label", "currency", "created_at"]
    list_filter = ["status"]
    search_fields = ["name", "subdomain"]
    actions = ["suspend_academies", "reactivate_academies"]

    def get_queryset(self, request):
        return super().get_queryset(request).exclude(schema_name="public")

    def get_form(self, request, obj=None, change=False, **kwargs):
        if obj is None:
            kwargs["form"] = AcademyCreationForm
        return super().get_form(request, obj, change=change, **kwargs)

    def get_fields(self, request, obj=None):
        if obj is None:
            return [*AcademyCreationForm.Meta.fields, "admin_email", "admin_full_name"]
        return ["name", "subdomain", "schema_name", "status", "timezone", "currency",
                "plan_label", "plan_notes", "created_at"]

    def get_readonly_fields(self, request, obj=None):
        if obj is None:
            return []
        return ["subdomain", "schema_name", "created_at"]

    def save_model(self, request, obj, form, change):
        if change:
            super().save_model(request, obj, form, change)
            return
        data = form.cleaned_data
        created = services.create_academy(
            name=data["name"],
            subdomain=data["subdomain"],
            admin_email=data["admin_email"],
            admin_full_name=data.get("admin_full_name", ""),
            timezone=data["timezone"],
            currency=data["currency"],
        )
        created.plan_label = data.get("plan_label", "")
        created.plan_notes = data.get("plan_notes", "")
        created.save(update_fields=["plan_label", "plan_notes"])
        obj.pk = created.pk
        obj.schema_name = created.schema_name

    @admin.action(description="Suspend selected academies")
    def suspend_academies(self, request, queryset):
        count = services.set_status(list(queryset.values_list("pk", flat=True)), "suspended")
        self.message_user(request, f"Suspended {count} academies.", messages.SUCCESS)

    @admin.action(description="Reactivate selected academies")
    def reactivate_academies(self, request, queryset):
        count = services.set_status(list(queryset.values_list("pk", flat=True)), "active")
        self.message_user(request, f"Reactivated {count} academies.", messages.SUCCESS)
```

Note: `clean_subdomain` calls `validate_subdomain`, and `create_academy` calls it again — the second call is the authoritative one (it runs inside the transaction).

- [ ] **Step 9: Implement the command**

`etqan/tenants/management/__init__.py` and `etqan/tenants/management/commands/__init__.py`: empty.

`etqan/tenants/management/commands/create_academy.py`:

```python
from django.core.management.base import BaseCommand
from django.core.management.base import CommandError
from django.db import connection

from etqan.platform.exceptions import ValidationError
from etqan.tenants import services


class Command(BaseCommand):
    help = "Create an academy (schema + domain + first admin, who gets a set-password email)."

    def add_arguments(self, parser):
        parser.add_argument("--name", required=True)
        parser.add_argument("--subdomain", required=True)
        parser.add_argument("--admin-email", required=True)
        parser.add_argument("--admin-name", default="")
        parser.add_argument("--timezone", default="UTC")
        parser.add_argument("--currency", default="USD")

    def handle(self, *args, **opts):
        connection.set_schema_to_public()
        try:
            academy = services.create_academy(
                name=opts["name"],
                subdomain=opts["subdomain"],
                admin_email=opts["admin_email"],
                admin_full_name=opts["admin_name"],
                timezone=opts["timezone"],
                currency=opts["currency"],
            )
        except ValidationError as exc:
            raise CommandError(exc.message) from exc
        self.stdout.write(self.style.SUCCESS(
            f"Created {academy.name} at {academy.get_primary_domain().domain}"
        ))
```

- [ ] **Step 10: Run all tenants tests and the suite**

Run: `pytest etqan/tenants -q && pytest -q && ruff check . && ruff format --check . && lint-imports`
Expected: all green.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat(tenants): create academies from the Etqan admin and the CLI

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 9: Suspended academies are blocked; academies cannot see each other

**Files:**
- Create: `backend/etqan/tenants/middleware.py`, `backend/etqan/tenants/tests/test_middleware.py`, `backend/etqan/tenants/tests/test_isolation.py`
- Modify: `backend/config/settings/base.py` (MIDDLEWARE)

**Interfaces:**
- Produces: `etqan.tenants.middleware.SuspendedAcademyMiddleware` — on an academy host whose `status == "suspended"`, every path except `/health/…` returns `403` JSON `{"detail": "This academy is suspended. Please contact Etqan.", "code": "tenant.suspended"}`.

- [ ] **Step 1: Write the failing tests**

`etqan/tenants/tests/test_middleware.py`:

```python
import pytest
from django.db import connection
from rest_framework.test import APIClient

from etqan.tenants.models import Academy

OTHER = "pytest-other.etqan.localhost"


@pytest.fixture
def suspended_other(tenants):
    Academy.objects.filter(pk=tenants.other.pk).update(status="suspended")


@pytest.mark.django_db
def test_suspended_academy_api_is_blocked(suspended_other):
    resp = APIClient().get("/api/v1/identity/csrf/", HTTP_HOST=OTHER)
    assert resp.status_code == 403
    assert resp.json()["code"] == "tenant.suspended"


@pytest.mark.django_db
def test_suspended_academy_still_answers_health(suspended_other):
    resp = APIClient().get("/health/live/", HTTP_HOST=OTHER)
    assert resp.status_code == 200


@pytest.mark.django_db
def test_active_academy_is_not_blocked():
    resp = APIClient().get("/api/v1/identity/csrf/", HTTP_HOST="testserver")
    assert resp.status_code == 200
```

`etqan/tenants/tests/test_isolation.py`:

```python
import pytest
from django.db import connection
from rest_framework.test import APIClient

from etqan.identity.models import User

OTHER = "pytest-other.etqan.localhost"


@pytest.fixture
def main_user(tenants):
    connection.set_tenant(tenants.main)
    return User.objects.create_user(email="m@main.test", password="pw-12345678")


@pytest.mark.django_db
def test_unknown_academy_host_is_404():
    resp = APIClient().get("/api/v1/identity/csrf/", HTTP_HOST="nope.etqan.localhost")
    assert resp.status_code == 404


@pytest.mark.django_db
def test_login_from_one_academy_fails_on_another(main_user):
    resp = APIClient().post(
        "/api/v1/identity/login/",
        {"email": "m@main.test", "password": "pw-12345678"},
        format="json",
        HTTP_HOST=OTHER,
    )
    assert resp.status_code == 400


@pytest.mark.django_db
def test_login_works_on_own_academy(main_user):
    resp = APIClient().post(
        "/api/v1/identity/login/",
        {"email": "m@main.test", "password": "pw-12345678"},
        format="json",
        HTTP_HOST="testserver",
    )
    assert resp.status_code == 200


@pytest.mark.django_db
def test_session_from_one_academy_is_anonymous_on_another(main_user):
    client = APIClient()
    client.force_login(main_user)
    assert client.get("/api/v1/identity/me/").status_code == 200
    resp = client.get("/api/v1/identity/me/", HTTP_HOST=OTHER)
    assert resp.status_code in (401, 403)


@pytest.mark.django_db
def test_academy_api_is_not_served_on_the_public_host():
    resp = APIClient().get("/api/v1/identity/csrf/", HTTP_HOST="etqan.localhost")
    assert resp.status_code == 404
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest etqan/tenants/tests/test_middleware.py etqan/tenants/tests/test_isolation.py -q`
Expected: the two suspended tests FAIL (200 instead of 403); isolation tests should already pass — if any isolation test fails, stop: tenancy from Task 6 is wrong and must be fixed before continuing.

- [ ] **Step 3: Implement**

`etqan/tenants/middleware.py`:

```python
from django.http import JsonResponse
from django_tenants.utils import get_public_schema_name


class SuspendedAcademyMiddleware:
    """Block every non-health request to a suspended academy."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        tenant = getattr(request, "tenant", None)
        if (
            tenant is not None
            and tenant.schema_name != get_public_schema_name()
            and tenant.status == "suspended"
            and not request.path.startswith("/health/")
        ):
            return JsonResponse(
                {
                    "detail": "This academy is suspended. Please contact Etqan.",
                    "code": "tenant.suspended",
                },
                status=403,
            )
        return self.get_response(request)
```

In `config/settings/base.py` `MIDDLEWARE`, insert `"etqan.tenants.middleware.SuspendedAcademyMiddleware",` as the **second** entry (right after `TenantMainMiddleware`).

- [ ] **Step 4: Run to verify pass**

Run: `pytest etqan/tenants -q && pytest -q && lint-imports`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(tenants): block suspended academies and prove academy isolation

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 10: Host model for local, test and production + the dev seed

**Files:**
- Modify: `backend/config/settings/local.py`, `backend/config/settings/production.py`, `backend/.env.example`, `backend/tests/test_local_settings.py`, `backend/tests/settings/test_allowed_hosts.py`
- Create: `backend/etqan/tenants/management/commands/seed_dev.py`, `backend/etqan/tenants/tests/test_seed_dev.py`
- Modify: `backend/etqan/platform/management/commands/seed.py` (delete it: placeholder only)

**Interfaces:**
- Produces: `python manage.py seed_dev` (DEBUG only, idempotent) → public tenant + academies `demo` (`admin@demo.test`) and `other` (`admin@other.test`), both with password `e2e-EtqanTest-2026`. Constants importable from `etqan.tenants.management.commands.seed_dev`: `DEV_PASSWORD`, `ACADEMIES`.

- [ ] **Step 1: Write the failing tests**

Replace `tests/test_local_settings.py` with:

```python
"""Local dev serves every academy on *.etqan.localhost with host-only cookies."""

import importlib
import os


def _load_local():
    os.environ.setdefault("DJANGO_SECRET_KEY", "test")
    return importlib.import_module("config.settings.local")


def test_every_academy_subdomain_is_allowed():
    s = _load_local()
    assert ".etqan.localhost" in s.ALLOWED_HOSTS
    assert "etqan.localhost" in s.ALLOWED_HOSTS


def test_cookies_are_host_only():
    s = _load_local()
    assert getattr(s, "SESSION_COOKIE_DOMAIN", None) is None
    assert getattr(s, "CSRF_COOKIE_DOMAIN", None) is None
```

In `tests/settings/test_allowed_hosts.py`, change the env value and assertion from `api-staging.etqan.academy` to `.etqan.example` (keep the localhost assertions).

`etqan/tenants/tests/test_seed_dev.py`:

```python
import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.identity.models import User
from etqan.tenants.management.commands.seed_dev import DEV_PASSWORD
from etqan.tenants.models import Academy


@pytest.mark.django_db
def test_seed_dev_refuses_without_debug():
    with pytest.raises(CommandError):
        call_command("seed_dev")


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_creates_two_academies_idempotently():
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    assert Academy.objects.filter(subdomain="other").count() == 1
    with tenant_context(demo):
        admin = User.objects.get(email="admin@demo.test")
        assert admin.role == "admin"
        assert admin.check_password(DEV_PASSWORD)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && pytest tests/test_local_settings.py etqan/tenants/tests/test_seed_dev.py -q`
Expected: FAIL (old host list / unknown command `seed_dev`).

- [ ] **Step 3: Implement settings**

`config/settings/local.py`: replace the `ALLOWED_HOSTS` list and everything from `_KALEEM_ORIGINS`/`_ETQAN_ORIGINS` through `CSRF_COOKIE_DOMAIN = ...` with:

```python
# Every academy is <subdomain>.etqan.localhost; the bare domain is the Etqan admin.
# The dashboard and the API share each academy's host (Traefik routes /api to
# Django), so cookies are host-only and no CORS is needed.
ALLOWED_HOSTS = [".etqan.localhost", "etqan.localhost", "localhost", "127.0.0.1", "0.0.0.0"]  # noqa: S104
TENANT_URL_TEMPLATE = env("DJANGO_TENANT_URL_TEMPLATE", default="http://{domain}")
```

`config/settings/production.py`: delete the `CORS_ALLOWED_ORIGINS`, `CORS_ALLOW_CREDENTIALS` lines and the two `*_COOKIE_DOMAIN` lines with their comment; keep `SESSION_COOKIE_SAMESITE`/`CSRF_COOKIE_SAMESITE = "Lax"`. After `FRONTEND_URL = env("DJANGO_FRONTEND_URL")` add:

```python
TENANT_BASE_DOMAIN = env("DJANGO_TENANT_BASE_DOMAIN")
TENANT_URL_TEMPLATE = env("DJANGO_TENANT_URL_TEMPLATE", default="https://{domain}")
```

and add `monkeypatch.setenv("DJANGO_TENANT_BASE_DOMAIN", "etqan.example")` to `tests/settings/test_allowed_hosts.py` and `tests/settings/test_sentry.py` next to their other `setenv` calls.

`backend/.env.example`: remove any `STRIPE`, `SIGNALING`, `TURN`, `VIDEO`, `COOKIE_DOMAIN`, `CORS` lines; add
```
DJANGO_TENANT_BASE_DOMAIN=etqan.localhost
DJANGO_TENANT_URL_TEMPLATE=http://{domain}
```

- [ ] **Step 4: Implement `seed_dev`**

`etqan/tenants/management/commands/seed_dev.py`:

```python
"""Known academies and accounts for local development and the e2e suite. DEBUG only."""

from django.conf import settings
from django.core.management.base import BaseCommand
from django.core.management.base import CommandError
from django.db import connection

from etqan.tenants import services
from etqan.tenants.models import Academy

DEV_PASSWORD = "e2e-EtqanTest-2026"  # noqa: S105 -- dev/e2e fixture credential
ACADEMIES = (
    ("demo", "Demo Academy", "admin@demo.test"),
    ("other", "Other Academy", "admin@other.test"),
)


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError("seed_dev only runs with DEBUG=True.")
        connection.set_schema_to_public()
        services.ensure_public_tenant()
        for subdomain, name, email in ACADEMIES:
            if Academy.objects.filter(subdomain=subdomain).exists():
                self.stdout.write(f"exists: {subdomain}")
                continue
            services.create_academy(
                name=name,
                subdomain=subdomain,
                admin_email=email,
                admin_full_name=f"{name} Admin",
                admin_password=DEV_PASSWORD,
            )
            connection.set_schema_to_public()
            self.stdout.write(self.style.SUCCESS(f"created: {services.domain_for(subdomain)}"))
```

Delete `etqan/platform/management/commands/seed.py` (Kaleem's placeholder): `git rm -q etqan/platform/management/commands/seed.py`.

- [ ] **Step 5: Run to verify pass**

Run: `pytest -q && ruff check . && ruff format --check . && lint-imports && pytest --cov=etqan -q | tail -3`
Expected: all green; coverage line shows ≥ 80.0%.

- [ ] **Step 6: Commit and open the backend PR**

```bash
git add -A
git commit -m "feat(tenants): wildcard academy hosts, host-only cookies, seed_dev

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/etqan-foundation
cd ..
```

(The PR is opened in Task 15 once the meta CI can test it.)

---

### Task 11: Strip the dashboard to identity + shell

**Files:**
- Delete: `dashboard/src/features/{analytics,assessment,billing,booking,call,content,curriculum,engagement,matching,messaging,scheduling,admin}/`, `dashboard/src/routes/_call.tsx`, `dashboard/src/routes/_call/`, `dashboard/src/routes/_authed/{schedule,match-requests,billing,availability}.tsx` and their `.test.tsx`, `dashboard/src/routes/_authed/{assessments,curriculum,insights,messages}.tsx`, `dashboard/src/routes/_authed/module-scaffolds.test.tsx`, `dashboard/src/features/identity/components/StudentAvailabilityCard.tsx` (+ `.test.tsx`), `dashboard/e2e/*` except `fixtures.ts` and `design-preview.spec.ts`
- Modify: `dashboard/src/features/shell/nav.ts`, `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/_authed/index.tsx`, `dashboard/src/routes/_authed/index.test.tsx`, `dashboard/src/routes/_authed/account.tsx`, `dashboard/src/routes/_authed/account.test.tsx`, `dashboard/src/locales/{en,ar}/common.json`, `dashboard/vitest.config.ts`, `dashboard/src/routes/__root.tsx` (comment only)

**Interfaces:**
- Produces: `NAV_ITEMS` = `/`, `/family` (parent|student), `/account`; `Home({ me })` with no spotlight except Family; route tree with `/`, `/account`, `/family`, auth routes, `/design-preview`.

- [ ] **Step 1: Delete**

```bash
cd dashboard
git rm -r -q src/features/{analytics,assessment,billing,booking,call,content,curriculum,engagement,matching,messaging,scheduling,admin} \
  src/routes/_call.tsx src/routes/_call \
  src/routes/_authed/{schedule,match-requests,billing,availability}.tsx \
  src/routes/_authed/{schedule,match-requests,billing,availability}.test.tsx \
  src/routes/_authed/{assessments,curriculum,insights,messages}.tsx \
  src/routes/_authed/module-scaffolds.test.tsx \
  src/features/identity/components/StudentAvailabilityCard.tsx
git rm -q src/features/identity/components/StudentAvailabilityCard.test.tsx 2>/dev/null || true
find e2e -type f ! -name fixtures.ts ! -name design-preview.spec.ts -print0 | xargs -0 git rm -q
```

- [ ] **Step 2: Rewrite the nav**

`src/features/shell/nav.ts`:

```ts
import type { LucideIcon } from "lucide-react";
import { Home, User, Users } from "lucide-react";
import type { ProfileType } from "@/features/identity/schemas";

export type NavItem = {
	to: string;
	labelKey: string;
	icon: LucideIcon;
	requires?: ProfileType;
	requiresAny?: ProfileType[];
};

export const NAV_ITEMS: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	{
		to: "/family",
		labelKey: "nav.family",
		icon: Users,
		requiresAny: ["parent", "student"],
	},
	{ to: "/account", labelKey: "auth.account", icon: User },
];

export function visibleNavItems(
	items: NavItem[],
	profiles: readonly ProfileType[],
): NavItem[] {
	return items.filter((i) => {
		if (i.requires) return profiles.includes(i.requires);
		if (i.requiresAny) return i.requiresAny.some((r) => profiles.includes(r));
		return true;
	});
}
```

In `src/features/shell/nav.test.ts` keep the whole `describe("visibleNavItems", …)` block and replace the `describe("NAV_ITEMS", …)` block with:

```ts
describe("NAV_ITEMS", () => {
	it("ships home, family and account in order", () => {
		expect(NAV_ITEMS.map((i) => i.to)).toEqual(["/", "/family", "/account"]);
	});

	it("gates Family to parents or students", () => {
		const family = NAV_ITEMS.find((i) => i.to === "/family");
		expect(family?.requiresAny).toEqual(["parent", "student"]);
	});

	it("shows only home and account to a teacher", () => {
		expect(visibleNavItems(NAV_ITEMS, ["teacher"]).map((i) => i.to)).toEqual([
			"/",
			"/account",
		]);
	});
});
```

- [ ] **Step 3: Rewrite Home**

In `src/routes/_authed/index.tsx`:
- Delete the `SOON` set and its comment.
- Replace `DESCRIPTION_KEY` with:
  ```ts
  const DESCRIPTION_KEY: Record<string, string> = {
  	"/family": "home.familyDesc",
  	"/account": "home.accountDesc",
  };
  ```
- Replace the `spotlight` expression with:
  ```ts
  	const spotlight =
  		isParent || isStudent
  			? {
  					to: "/family",
  					title: t("home.familyTitle"),
  					desc: t("home.familyDesc"),
  					cta: t("home.goToFamily"),
  				}
  			: null;
  ```
  and delete the now-unused `isTeacher` line.
- In the `BentoTile`, delete the `badge={…}` prop.

In `src/routes/_authed/index.test.tsx` replace the second and third `it(...)` blocks with:

```tsx
	it("shows the family spotlight for a parent", async () => {
		renderHome(parent);
		expect(
			await screen.findByRole("heading", { level: 2, name: /your family/i }),
		).toBeInTheDocument();
	});

	it("shows no family spotlight to a teacher", async () => {
		renderHome({ ...student, profiles: ["teacher"] });
		await screen.findByText(/sara/i);
		expect(screen.queryByRole("heading", { level: 2, name: /your family/i })).toBeNull();
	});
```

- [ ] **Step 4: Rewrite Account**

In `src/routes/_authed/account.tsx`: delete the imports of `SubjectsCard`, `StudentAvailabilityCard`, `ChildrensTeachersCard`, `MyTeacherCard`; delete the JSX lines rendering them (the `SubjectsCard` pair and its comment, `MyTeacherCard`, `ChildrensTeachersCard`, and the `StudentAvailabilityCard` line with its comment); delete the `isParent` constant if now unused.

In `src/routes/_authed/account.test.tsx`: delete the `vi.mock("@/features/scheduling/queries", …)` block, the `useMyMatchRequestsMock`/`useAssignmentsMock` declarations and the `vi.mock("@/features/matching/queries", …)` block (with its comment), every `beforeEach` line that configures those mocks, and every `it(...)` whose assertions mention availability, subjects, "my teacher", "children's teachers" or match requests.

- [ ] **Step 5: Prune translations**

```bash
node -e '
const fs=require("fs");
for (const lang of ["en","ar"]) {
  const f=`src/locales/${lang}/common.json`; const d=JSON.parse(fs.readFileSync(f,"utf8"));
  for (const k of ["call","booking","matching","billing","availability","subjects"]) delete d[k];
  for (const k of ["schedule","curriculum","assessments","messages","insights","comingSoon"]) if (d.modules) delete d.modules[k];
  if (d.modules && Object.keys(d.modules).length===0) delete d.modules;
  for (const k of ["schedule","curriculum","assessments","messages","billing","insights","availability","matchRequests"]) if (d.nav) delete d.nav[k];
  for (const k of Object.keys(d.home||{})) if (k.startsWith("availability") || k==="setAvailability") delete d.home[k];
  fs.writeFileSync(f, JSON.stringify(d,null,"\t")+"\n");
}'
```

- [ ] **Step 6: Lower coverage floors**

In `vitest.config.ts`, set the coverage `thresholds` to `{ lines: 80, branches: 70, functions: 70, statements: 80 }` and delete the comment paragraphs that justify the old numbers.

- [ ] **Step 7: Typecheck, lint, test, build**

```bash
pnpm install
pnpm tsc --noEmit
pnpm lint
pnpm test:coverage
pnpm build
```

Expected: all pass; `pnpm build` regenerates `src/routeTree.gen.ts` without the removed routes. Fix any leftover import of a deleted module the typechecker reports by deleting that import and its usage (it can only be in a kept file that referenced removed UI). `grep -rn "features/\(call\|booking\|matching\|billing\|scheduling\|curriculum\)" src e2e` must print nothing.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: remove call, booking, matching, billing, scheduling and placeholder modules

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd ..
```

---

### Task 12: Dashboard rebrand, same-origin API, role, and the tenant e2e

**Files:**
- Modify: `dashboard/package.json`, `dashboard/pnpm-lock.yaml`, `dashboard/index.html`, `dashboard/src/index.css`, `dashboard/src/test/a11y.test.tsx`, `dashboard/src/lib/{api,theme,i18n,direction}.tsx?`, `dashboard/src/features/shell/AppTopbar.tsx`, `dashboard/src/ui/auth-layout.tsx`, `dashboard/src/locales/{en,ar}/common.json`, `dashboard/src/routes/login.tsx`, `dashboard/src/features/identity/schemas.ts`, `dashboard/vite.config.ts`, `dashboard/playwright.config.ts`, `dashboard/Dockerfile`, `dashboard/scripts/check-colors.mjs`, `dashboard/CLAUDE.md`
- Rewrite: `dashboard/e2e/fixtures.ts`; Create: `dashboard/e2e/tenant-login.spec.ts`

**Interfaces:**
- Consumes: backend `seed_dev` accounts (`admin@demo.test`, `admin@other.test`, password `e2e-EtqanTest-2026`) and `/me` `role` (Task 5).
- Produces: `Me.role: "admin" | "teacher" | "student" | "parent"`; axios `baseURL` default `/api/v1/`; Vite dev/preview proxy `/api` → `VITE_PROXY_TARGET` (default `http://127.0.0.1:8000`) preserving the Host header.

- [ ] **Step 1: Point at `@etqan/tokens` and rebrand**

```bash
cd dashboard
sed -i 's#"@kaleem/tokens": "github:kaleem-lms/tokens\#v0.2.2"#"@etqan/tokens": "github:Etqan-agency/etqan_tutor_tokens\#v0.3.0"#' package.json
node -e 'const p=require("./package.json"); p.name="etqan_tutor_dashboard"; require("fs").writeFileSync("package.json", JSON.stringify(p,null,"\t")+"\n")'
grep -rlI --exclude-dir=node_modules --exclude-dir=.git --exclude=pnpm-lock.yaml -e '@kaleem/tokens' . | xargs sed -i 's#@kaleem/tokens#@etqan/tokens#g'
grep -rlI --exclude-dir=node_modules --exclude-dir=.git --exclude=pnpm-lock.yaml -e 'kaleem' -e 'Kaleem' . \
  | xargs sed -i -e 's/newToKaleem/newToEtqan/g' -e 's/\bKaleem\b/Etqan/g' -e 's/\bkaleem\b/etqan/g'
pnpm install
grep -rnI -i --exclude-dir=node_modules --exclude=pnpm-lock.yaml kaleem . || echo clean
```

Then fix the brand-visible strings by hand:
- `index.html`: `<title>Etqan Tutor</title>`.
- `src/locales/ar/common.json`: the Arabic brand name "كَلِيم" → "إتقان" (every occurrence).
- `src/locales/en/common.json`: `auth.newToEtqan` → `"New here? Ask your academy for an account"`; `auth.registerSubtitle` → `"Create your Etqan account."`.

- [ ] **Step 2: Same-origin API and proxy**

`src/lib/api.ts`: change the default in the `baseURL` expression from `"http://localhost:8000/api/v1/"` to `"/api/v1/"`; delete the comment line mentioning `features/call/diagnosticsApi.ts`.

`vite.config.ts`: replace the `server` block with:

```ts
	server: {
		host: true,
		port: 5173,
		allowedHosts: [".etqan.localhost"],
		hmr: { clientPort: 80 },
		proxy: { "/api": { target: apiTarget } },
	},
	preview: {
		host: true,
		port: 4173,
		allowedHosts: [".etqan.localhost"],
		proxy: { "/api": { target: apiTarget } },
	},
```

and above `export default` add:

```ts
// The dashboard calls /api on its own host (one host per academy). In `vite` and
// `vite preview` that path is proxied to Django with the Host header untouched,
// so django-tenants still resolves the academy from it.
const apiTarget = process.env.VITE_PROXY_TARGET ?? "http://127.0.0.1:8000";
```

If `pnpm tsc --noEmit` reports `Cannot find name 'process'` for `vite.config.ts`, run `pnpm add -D @types/node`.

`Dockerfile`: change any `ARG VITE_API_URL=…` default to `ARG VITE_API_URL=/api/v1/`.

- [ ] **Step 3: Add the role to `Me`**

In `src/features/identity/schemas.ts` add above `export interface Me`:

```ts
export type Role = "admin" | "teacher" | "student" | "parent";
```

and inside `Me`, after `full_name: string;`, add `role: Role;`. Then run `pnpm tsc --noEmit` and add `role: "student"` (or the matching role) to every `Me` object literal in tests that the compiler flags.

- [ ] **Step 4: Rewrite e2e fixtures and add the tenant spec**

`e2e/fixtures.ts`:

```ts
import { expect, type Page } from "@playwright/test";

// Must match backend/etqan/tenants/management/commands/seed_dev.py
export const DEV_PASSWORD = "e2e-EtqanTest-2026";
export const DEMO_URL = process.env.E2E_DEMO_URL ?? "http://demo.etqan.localhost:4173";
export const OTHER_URL = process.env.E2E_OTHER_URL ?? "http://other.etqan.localhost:4173";
export const DEMO_ADMIN = "admin@demo.test";
export const OTHER_ADMIN = "admin@other.test";

export async function login(page: Page, baseUrl: string, email: string) {
	await page.goto(`${baseUrl}/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
	await page.getByRole("button", { name: /sign in/i }).click();
}

export async function expectLoggedIn(page: Page, name: RegExp) {
	await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();
}
```

`e2e/tenant-login.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import {
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
	OTHER_ADMIN,
	OTHER_URL,
} from "./fixtures";

test.describe("academies", () => {
	test("an academy admin signs in on their own academy", async ({ page }) => {
		await login(page, DEMO_URL, DEMO_ADMIN);
		await expectLoggedIn(page, /demo academy admin/i);
	});

	test("an admin of one academy cannot sign in on another", async ({ page }) => {
		await login(page, OTHER_URL, DEMO_ADMIN);
		await expect(page.getByRole("alert")).toBeVisible();
		await expect(page).toHaveURL(/\/login/);
	});

	test("each academy keeps its own session", async ({ browser }) => {
		const context = await browser.newContext();
		const page = await context.newPage();
		await login(page, OTHER_URL, OTHER_ADMIN);
		await expectLoggedIn(page, /other academy admin/i);
		await page.goto(`${DEMO_URL}/`);
		await expect(page).toHaveURL(/\/login/);
		await context.close();
	});
});
```

If `design-preview.spec.ts` imports anything from `./fixtures` that no longer exists, change it to `page.goto(`${DEMO_URL}/design-preview`)` using `DEMO_URL`.

`playwright.config.ts`: change the default `baseURL` to `process.env.E2E_APP_URL ?? "http://demo.etqan.localhost:4173"` and delete the fake-media `launchOptions.args` flags (they existed for the call specs).

- [ ] **Step 5: Verify**

```bash
pnpm tsc --noEmit && pnpm lint && pnpm test:coverage && pnpm build
```

Expected: all pass. Then run e2e locally against a real backend:

```bash
# terminal A (backend, DEBUG settings)
cd ../backend && export DATABASE_URL=postgres://etqan:etqan@localhost:5432/etqan DJANGO_SETTINGS_MODULE=config.settings.local \
  DJANGO_TENANT_URL_TEMPLATE='http://{domain}:4173' DJANGO_EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
python manage.py migrate_schemas --shared && python manage.py seed_dev && python manage.py runserver 127.0.0.1:8000
# terminal B
cd dashboard && pnpm build && pnpm preview &
pnpm exec playwright install chromium && pnpm e2e
```

Expected: 3 `tenant-login` tests + design-preview pass. (The Postgres from Task 3 used `kaleem` credentials; after Task 14 compose uses `etqan`. For this local run use whichever DB is up and export the matching `DATABASE_URL`.)

- [ ] **Step 6: Commit and push**

```bash
git add -A
git commit -m "feat: rebrand dashboard to etqan, same-origin api, role on me, academy e2e

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/etqan-foundation
cd ..
```

---

### Task 13: Strip infra of coturn, signaling and marketing

**Files:**
- Delete: `infra/coturn/`
- Modify: `infra/docker-compose.production.yml`, `infra/scripts/ship.sh`, `infra/.env.production.example`, `infra/CLAUDE.md`

**Interfaces:**
- Produces: a production compose with services traefik, postgres, redis, flower, dashboard, django-{blue,green}, celery-worker-{blue,green}, celery-beat-{blue,green}; images `ghcr.io/etqan-agency/{backend,dashboard}`. Wildcard TLS and deploy wiring are **out of scope** (deploy plan).

- [ ] **Step 1: Remove**

```bash
cd infra
git rm -r -q coturn
```

In `docker-compose.production.yml` delete the `coturn`, `signaling` and `marketing` service blocks, any `DJANGO_SIGNALING_URL` / `DJANGO_TURN_*` / `WS_DOMAIN` / `MARKETING_DOMAIN` environment lines, and comments referring to them.

In `scripts/ship.sh`: remove `coturn signaling` from the `up -d` list, delete the coturn config hash/restart block (the block that hashes `coturn/turnserver.conf` and restarts coturn), delete the signaling image capture, its `/health/live/` check and `restore_signaling` function and its call, and change `up -d dashboard marketing` to `up -d dashboard`.

In `.env.production.example` delete `MARKETING_DOMAIN`, `WS_DOMAIN`, `DJANGO_SIGNALING_SECRET`, `DJANGO_TURN_SECRET`, `TURN_REALM`, `DJANGO_TURN_URLS`, `DJANGO_VIDEO_PROVIDER`, `DJANGO_COOKIE_DOMAIN`, `CORS_ALLOWED_ORIGINS` and their comments; add `DJANGO_TENANT_BASE_DOMAIN=` and `DJANGO_TENANT_URL_TEMPLATE=https://{domain}`.

- [ ] **Step 2: Rebrand**

```bash
grep -rlI -e kaleem -e Kaleem . | xargs sed -i -e 's#ghcr.io/kaleem-lms#ghcr.io/etqan-agency#g' -e 's/\bKaleem\b/Etqan/g' -e 's/\bkaleem\b/etqan/g'
grep -rnI -i -e kaleem -e coturn -e signaling -e marketing -e turn: . || echo clean
```

- [ ] **Step 3: Validate**

Run:
```bash
DEPLOY_SHA=x DJANGO_SECRET_KEY=x API_DOMAIN=a DASHBOARD_DOMAIN=b FLOWER_DOMAIN=c TRAEFIK_FLOWER_AUTH=x \
POSTGRES_DB=etqan POSTGRES_USER=etqan POSTGRES_PASSWORD=x docker compose -f docker-compose.production.yml config -q && echo ok
bash -n scripts/ship.sh && echo syntax-ok
```
Expected: `ok` and `syntax-ok`. If `compose config` names another required variable, pass a dummy value for it the same way.

- [ ] **Step 4: Commit and push**

```bash
git add -A
git commit -m "chore: remove coturn, signaling and marketing; rebrand to etqan

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/etqan-foundation
cd ..
```

---

### Task 14: Meta repo — local stack, justfile, docs

**Files:**
- Rewrite: `docker-compose.local.yml`, `.env.example`, `README.md`, `STATE.md`, `CLAUDE.md`
- Modify: `justfile`, `scripts/check-token-pin.mjs`, `.github/dependabot.yml`, `.github/copilot-instructions.md`, `.lighthouserc.json` (delete), `.github/workflows/lighthouse.yml` (delete), `.github/workflows/stripe-clock.yml` (delete), `.claude/commands/*` (rebrand)

**Interfaces:**
- Produces: `just setup` → builds, migrates (`migrate_schemas`), runs `seed_dev`; `just dev` → `http://demo.etqan.localhost` (academy), `http://etqan.localhost/admin/` (Etqan staff), `http://mail.etqan.localhost`, `http://flower.etqan.localhost`.

- [ ] **Step 1: Write `docker-compose.local.yml`**

```yaml
# Local stack. Every academy is http://<subdomain>.etqan.localhost (dashboard + /api on
# the same host); http://etqan.localhost/admin/ is the Etqan staff console.
x-uidgid: &uidgid
  UID: ${HOST_UID:-1000}
  GID: ${HOST_GID:-1000}

x-django-env: &django-env
  DJANGO_SETTINGS_MODULE: config.settings.local
  DJANGO_READ_DOT_ENV_FILE: "True"
  DATABASE_URL: postgres://etqan:etqan@postgres:5432/etqan
  CELERY_BROKER_URL: redis://redis:6379/0
  DJANGO_TENANT_BASE_DOMAIN: etqan.localhost
  DJANGO_TENANT_URL_TEMPLATE: http://{domain}

services:
  traefik:
    image: traefik:v3.6
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --api.insecure=true
      - --api.dashboard=true
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  django:
    build: { context: ./backend, target: dev, args: *uidgid }
    command: python manage.py runserver 0.0.0.0:8000
    volumes: [./backend:/app]
    ports: ["8000:8000"]
    env_file: [./backend/.env]
    environment: *django-env
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    labels:
      - traefik.enable=true
      # Academy API paths on any academy host, and the whole bare domain (staff admin).
      - traefik.http.routers.api.rule=(HostRegexp(`^[a-z0-9-]+\.etqan\.localhost$`) && (PathPrefix(`/api`) || PathPrefix(`/accounts`) || PathPrefix(`/health`))) || Host(`etqan.localhost`)
      - traefik.http.routers.api.priority=100
      - traefik.http.routers.api.entrypoints=web
      - traefik.http.services.api.loadbalancer.server.port=8000

  postgres:
    image: postgres:18-alpine
    volumes: [postgres_data:/var/lib/postgresql]
    environment: { POSTGRES_DB: etqan, POSTGRES_USER: etqan, POSTGRES_PASSWORD: etqan }
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U etqan"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:8-alpine
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  celery_worker:
    build: { context: ./backend, target: dev, args: *uidgid }
    command: celery -A config.celery_app worker -l info
    volumes: [./backend:/app]
    env_file: [./backend/.env]
    environment: *django-env
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }

  celery_beat:
    build: { context: ./backend, target: dev, args: *uidgid }
    command: celery -A config.celery_app beat -l info
    volumes: [./backend:/app]
    env_file: [./backend/.env]
    environment: *django-env
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }

  flower:
    build: { context: ./backend, target: dev, args: *uidgid }
    command: celery -A config.celery_app flower --port=5555
    volumes: [./backend:/app]
    ports: ["5555:5555"]
    env_file: [./backend/.env]
    environment: *django-env
    depends_on:
      redis: { condition: service_healthy }
    labels:
      - traefik.enable=true
      - traefik.http.routers.flower.rule=Host(`flower.etqan.localhost`)
      - traefik.http.routers.flower.priority=200
      - traefik.http.routers.flower.entrypoints=web
      - traefik.http.services.flower.loadbalancer.server.port=5555

  mailpit:
    image: axllent/mailpit:latest
    ports: ["8025:8025", "1025:1025"]
    labels:
      - traefik.enable=true
      - traefik.http.routers.mail.rule=Host(`mail.etqan.localhost`)
      - traefik.http.routers.mail.priority=200
      - traefik.http.routers.mail.entrypoints=web
      - traefik.http.services.mail.loadbalancer.server.port=8025

  dashboard:
    build:
      context: ./dashboard
      target: dev
      args: *uidgid
      secrets: [tokens_token]
    environment:
      - VITE_PROXY_TARGET=http://django:8000
    volumes:
      - ./dashboard:/app
      - dashboard_node_modules:/app/node_modules
    labels:
      - traefik.enable=true
      - traefik.http.routers.app.rule=HostRegexp(`^[a-z0-9-]+\.etqan\.localhost$`)
      - traefik.http.routers.app.priority=10
      - traefik.http.routers.app.entrypoints=web
      - traefik.http.services.app.loadbalancer.server.port=5173

volumes:
  postgres_data:
  dashboard_node_modules:

secrets:
  tokens_token:
    environment: GH_TOKEN
```

Validate: `docker compose -f docker-compose.local.yml config -q && echo ok` → `ok`.

- [ ] **Step 2: Update the justfile**

Apply to `justfile`:
- Header comment `kaleem` → `etqan_tutor`; every `@kaleem/tokens` → `@etqan/tokens`; every `kaleem-lms/tokens` → `Etqan-agency/etqan_tutor_tokens`.
- `postgres://kaleem:kaleem@…/kaleem` → `postgres://etqan:etqan@…/etqan` (two places).
- `--cov=kaleem --cov=signaling` → `--cov=etqan` (two places).
- `migrate` recipe body → `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django python manage.py migrate_schemas`.
- `seed` recipe body → `… run --rm django python manage.py seed_dev` (same compose prefix), and its comment → `# Create the public tenant and the demo/other dev academies`.
- `new-module` recipe: every `backend/kaleem/` → `backend/etqan/`, `'kaleem.{{name}}'` → `'etqan.{{name}}'`, and the LOCAL_APPS hint → `Add 'etqan.{{name}}' to TENANT_APPS (and SHARED_APPS only if it must exist in public)`.

Run: `just --list` → lists recipes without error; `grep -n -i kaleem justfile || echo clean` → `clean`.

- [ ] **Step 3: Small files**

- `.env.example`: replace `VITE_API_URL=…` with nothing (delete the line and its comment); keep `HOST_UID`/`HOST_GID`.
- `scripts/check-token-pin.mjs`: `CONSUMERS = ["dashboard/package.json"]`; replace `@kaleem/tokens` → `@etqan/tokens`, `kaleem-lms/tokens` → `Etqan-agency/etqan_tutor_tokens`.
- `git rm -q .lighthouserc.json .github/workflows/lighthouse.yml .github/workflows/stripe-clock.yml`
- `.github/dependabot.yml`: delete the marketing comment line.
- `.github/copilot-instructions.md` and `.claude/commands/*.md`: `sed -i -e 's/\bKaleem\b/Etqan/g' -e 's/\bkaleem\b/etqan/g'`.
- `.gitleaksignore`: leave untouched (historical fingerprints).

- [ ] **Step 4: Rewrite README.md, STATE.md, CLAUDE.md**

`README.md`:

```markdown
# etqan_tutor

Multi-academy tutoring operations SaaS by Etqan Agency. Each academy gets its own
workspace (PostgreSQL schema + subdomain); academy admins manage students, teachers,
subscriptions, schedules, sessions, billing and payroll.

Forked from Kaleem (history preserved); Kaleem's docs live in `docs/kaleem-archive/`.

## Quick start

    git clone --recursive https://github.com/Etqan-agency/etqan_tutor.git
    cd etqan_tutor
    just setup   # build, migrate all schemas, seed demo academies
    just dev

- Academy: http://demo.etqan.localhost  (admin@demo.test / e2e-EtqanTest-2026)
- Second academy: http://other.etqan.localhost  (admin@other.test)
- Etqan staff console: http://etqan.localhost/admin/  (`docker compose -f docker-compose.local.yml run --rm django python manage.py createsuperuser`)
- Mail: http://mail.etqan.localhost

Create an academy from the CLI:

    docker compose -f docker-compose.local.yml run --rm django \
      python manage.py create_academy --name "Noor" --subdomain noor --admin-email admin@noor.test

## Docs

- Product spec: `docs/superpowers/specs/2026-09-23-etqan-tutor-v1-design.md`
- Plans: `docs/superpowers/plans/`
- Source analysis: `docs/PHASE_1_SYSTEM_AUDIT.md`, `docs/PHASE_2_SYSTEM_DESIGN.md`
```

`STATE.md`:

```markdown
# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 1 (fork, strip, tenancy) — see `docs/superpowers/plans/2026-09-23-plan-1-fork-strip-tenancy.md`.

## Next

Plan 2: people & catalogue (spec §9 milestone 3).

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
```

`CLAUDE.md` — replace the whole file with:

```markdown
# etqan_tutor

Multi-academy tutoring operations SaaS (Etqan Agency). Fork of Kaleem.

## Layout
Meta repo with submodules: `backend/` (Django + DRF, package `etqan`), `dashboard/`
(React + TanStack), `infra/`, `tokens/` (`@etqan/tokens`). Trunk: `master` here, `main`
in submodules. Work on a `feat/*` branch in each touched repo, PR, merge; then bump the
submodule pointers here.

## Tenancy (read before touching models)
- django-tenants, one PostgreSQL schema per academy; `etqan.tenants.Academy` is the tenant.
- SHARED_APPS migrate into `public`; TENANT_APPS into every academy. New business apps go
  in TENANT_APPS.
- Academy host `<subdomain>.<TENANT_BASE_DOMAIN>` serves the dashboard and `/api/v1/`
  same-origin. The bare domain serves only Django admin for Etqan staff.
- Migrate with `migrate_schemas`, never assume a single schema.
- Background jobs must loop over academies explicitly (`tenant_context`).
- Build any user-facing URL with `etqan.platform.frontend.frontend_url()`.

## Rules
- Spec → plan → code. Specs/plans in `docs/superpowers/`.
- TDD. Backend coverage ≥ 80%; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Business logic in `<app>/services.py`; apps talk to each other only through services.
  `lint-imports` enforces the boundaries.
- All API routes under `/api/v1/`.
- Money is integer minor units + currency. Stored instants are UTC.
- Keep it simple: this is a CRUD-first product. Check the spec's non-goals before adding
  anything.

## Commands
`just setup`, `just dev`, `just test`, `just lint`, `just migrate`, `just seed`.
```

- [ ] **Step 5: Bring the stack up and smoke-test it**

```bash
just setup
just dev-backend
curl -s -o /dev/null -w "%{http_code}\n" http://etqan.localhost/health/live/          # 200
curl -s -o /dev/null -w "%{http_code}\n" http://demo.etqan.localhost/api/v1/identity/csrf/  # 200
curl -s -o /dev/null -w "%{http_code}\n" http://nope.etqan.localhost/api/v1/identity/csrf/  # 404
curl -s -o /dev/null -w "%{http_code}\n" http://etqan.localhost/admin/login/          # 200
```

Then open `http://demo.etqan.localhost/login` in a browser and sign in as `admin@demo.test` / `e2e-EtqanTest-2026`; the home page greets "Demo Academy Admin". Report the four status codes and the browser result.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: etqan local stack with wildcard academy hosts; rewrite docs

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: CI rewrite, pull requests, merge

**Files:**
- Rewrite: `.github/workflows/ci.yml`
- Delete: `.github/scripts/classify-changes.sh`, `.github/scripts/test-classify-changes.sh`

**Interfaces:**
- Consumes: secrets `SUBMODULE_TOKEN`, `TOKENS_REPO_TOKEN` (Task 1 Step 6).
- Produces: CI jobs `backend`, `dashboard`, `e2e`, `security` on every PR and push to `master`.

- [ ] **Step 1: Write the workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [master]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  PYTHON_VERSION: "3.13"
  NODE_VERSION: "22"

jobs:
  backend:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:18-alpine
        env: { POSTGRES_DB: etqan_test, POSTGRES_USER: etqan, POSTGRES_PASSWORD: etqan }
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U etqan" --health-interval 5s --health-timeout 3s --health-retries 10
    env:
      DATABASE_URL: postgres://etqan:etqan@localhost:5432/etqan_test
    defaults: { run: { working-directory: backend } }
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - uses: actions/setup-python@v5
        with: { python-version: "${{ env.PYTHON_VERSION }}", cache: pip, cache-dependency-path: backend/requirements/*.txt }
      - run: pip install -r requirements/local.txt
      - run: ruff check . && ruff format --check .
      - run: lint-imports
      - run: pytest --create-db --cov=etqan -q

  dashboard:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: dashboard } }
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - uses: pnpm/action-setup@v4
        with: { version: 10 }
      - uses: actions/setup-node@v4
        with: { node-version: "${{ env.NODE_VERSION }}", cache: pnpm, cache-dependency-path: dashboard/pnpm-lock.yaml }
      - run: git config --global url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "https://github.com/"
      - run: node ../scripts/check-token-pin.mjs
      - run: pnpm install --frozen-lockfile
      - run: pnpm tsc --noEmit
      - run: pnpm lint
      - run: pnpm test:coverage
      - run: pnpm build

  e2e:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:18-alpine
        env: { POSTGRES_DB: etqan, POSTGRES_USER: etqan, POSTGRES_PASSWORD: etqan }
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U etqan" --health-interval 5s --health-timeout 3s --health-retries 10
      # The cache is Redis in local settings; allauth's login rate limiting uses it.
      redis:
        image: redis:8-alpine
        ports: ["6379:6379"]
        options: >-
          --health-cmd "redis-cli ping" --health-interval 5s --health-timeout 3s --health-retries 10
    env:
      DATABASE_URL: postgres://etqan:etqan@localhost:5432/etqan
      CELERY_BROKER_URL: redis://localhost:6379/0
      DJANGO_SETTINGS_MODULE: config.settings.local
      DJANGO_SECRET_KEY: ci-only
      DJANGO_EMAIL_BACKEND: django.core.mail.backends.locmem.EmailBackend
      DJANGO_TENANT_URL_TEMPLATE: http://{domain}:4173
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - uses: actions/setup-python@v5
        with: { python-version: "${{ env.PYTHON_VERSION }}", cache: pip, cache-dependency-path: backend/requirements/*.txt }
      - uses: pnpm/action-setup@v4
        with: { version: 10 }
      - uses: actions/setup-node@v4
        with: { node-version: "${{ env.NODE_VERSION }}", cache: pnpm, cache-dependency-path: dashboard/pnpm-lock.yaml }
      - run: git config --global url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "https://github.com/"
      - name: Backend up with seeded academies
        working-directory: backend
        run: |
          pip install -r requirements/local.txt
          python manage.py migrate_schemas --shared
          python manage.py seed_dev
          nohup python manage.py runserver 127.0.0.1:8000 > /tmp/django.log 2>&1 &
          for i in $(seq 1 30); do curl -sf -H "Host: etqan.localhost" http://127.0.0.1:8000/health/live/ && break; sleep 1; done
      - name: Dashboard preview + Playwright
        working-directory: dashboard
        run: |
          pnpm install --frozen-lockfile
          pnpm build
          nohup pnpm preview > /tmp/preview.log 2>&1 &
          for i in $(seq 1 30); do curl -sf http://127.0.0.1:4173/ >/dev/null && break; sleep 1; done
          pnpm exec playwright install --with-deps chromium
          pnpm e2e
      - if: failure()
        run: tail -n 200 /tmp/django.log /tmp/preview.log

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0, submodules: recursive, token: "${{ secrets.SUBMODULE_TOKEN }}" }
      - uses: gitleaks/gitleaks-action@v2
        env: { GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
```

Note: no Celery worker runs in e2e. Nothing the e2e specs touch calls `.delay()` (seeded admins already have passwords, so no email is sent); a later plan that adds an emailing e2e flow must start a worker or make tasks eager in this job.

```bash
git rm -q .github/scripts/classify-changes.sh .github/scripts/test-classify-changes.sh
```

- [ ] **Step 2: Open PRs for each submodule (pointing at the fork's `main`)**

```bash
for s in backend dashboard infra; do
  repo="Etqan-agency/etqan-$s"
  gh pr create --repo "$repo" --base main --head feat/etqan-foundation \
    --title "Etqan foundation: strip Kaleem features, rebrand, tenancy" \
    --body $'Part of Plan 1 (docs/superpowers/plans/2026-09-23-plan-1-fork-strip-tenancy.md in etqan_tutor).\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)'
done
```

- [ ] **Step 3: Point the meta repo at the submodule branch heads, push, open the meta PR**

```bash
git add backend dashboard infra tokens .github
git commit -m "ci: rewrite CI for etqan and bump submodules to the foundation branches

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/etqan-foundation
gh pr create --repo Etqan-agency/etqan_tutor --base master --head feat/etqan-foundation \
  --title "Etqan foundation (Plan 1): fork, strip, multi-academy tenancy" \
  --body $'Implements docs/superpowers/plans/2026-09-23-plan-1-fork-strip-tenancy.md.\n\n- Kaleem features removed (billing, scheduling, matching, calls, marketing)\n- Package and brand renamed to etqan\n- django-tenants: one schema per academy, subdomain routing, Etqan admin console\n- New CI: backend, dashboard, e2e, secret scan\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)'
gh pr checks --repo Etqan-agency/etqan_tutor --watch
```

Expected: `backend`, `dashboard`, `e2e`, `security` all pass. If `security` flags secrets that are inherited Kaleem history, confirm they already appear in `.gitleaksignore`; if a finding is new, stop and report it — do not add it to the ignore file without the user's say.

- [ ] **Step 4: USER CHECKPOINT — merge**

Report the four CI results and the PR links to the user and ask for approval to merge. On approval:

```bash
for s in tokens backend dashboard infra; do gh pr merge --repo "Etqan-agency/etqan-$s" --merge; done
for s in backend dashboard infra; do git -C "$s" fetch origin && git -C "$s" switch main && git -C "$s" pull --ff-only; done
git -C tokens fetch --tags && git -C tokens checkout v0.3.0
git add backend dashboard infra tokens
git commit -m "chore: bump submodules to merged main

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push
gh pr checks --repo Etqan-agency/etqan_tutor --watch
gh pr merge --repo Etqan-agency/etqan_tutor --merge
```

Then update `STATE.md` "Where we are" to `Plan 1 merged <date>; next: Plan 2 (people & catalogue).` and commit it directly to `master` with a `docs:` message.
