# Phase 0 — Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A healthy, agent-friendly, CI-green empty skeleton where `git clone --recursive && just setup && just dev` brings up the full local stack, all linters and tests pass, monitoring is live, and a fresh developer/agent can start Phase A without asking questions.

**Architecture:** Meta repo with 4 git submodules (`backend`, `dashboard`, `marketing`, `infra`). Backend is a Django 5.x + DRF modular monolith with a single `platform` module (no business modules yet). Dashboard is a React 19 + TanStack Router + TanStack Query + Tailwind + shadcn skeleton. Marketing is an Astro skeleton. Infrastructure is Docker Compose for local and production, with a Prometheus + Grafana + Loki + Uptime Kuma monitoring stack.

**Tech Stack:** Python 3.12, Django 5.x, DRF, Celery, Postgres 16, Redis 7, React 19, Vite, TanStack Router/Query, Tailwind CSS, shadcn/ui, Astro, Docker Compose, GitHub Actions, Sentry, Prometheus, Grafana, Loki, Uptime Kuma, just, ruff, mypy, biome, import-linter, pre-commit, gitleaks.

**Spec:** `docs/superpowers/specs/2026-04-11-rebuild-roadmap-design.md` — Phase 0 section.

---

## Scope note

Phase 0 is infrastructure, not feature code. There are no business models, no API endpoints beyond health checks, no frontend routes beyond a placeholder. **Do not add feature code.** If you're tempted, that's Phase A.

The "tests" in Phase 0 are primarily verification steps (does the system start, do linters pass, does CI go green) plus a small set of real tests for the `platform` module's health check endpoints and middleware.

## Task dependency graph

```
Task 1 (meta repo)
├── Task 2 (backend scaffold) ──► Task 3 (Docker local) ──► Task 4 (platform module)
│                                                           ├── Task 5 (import-linter)
│                                                           └── Task 6 (pre-commit + ruff + mypy)
├── Task 7 (dashboard scaffold)
├── Task 8 (marketing scaffold)
├── Task 9 (infra + monitoring)
├── Task 13 (agent tooling)
├── Task 14 (docs skeleton)
│   └── Task 15 (ADRs)
└── Task 18 (state files + READMEs)

Task 10 (CI) ◄── Tasks 2, 6, 7
Task 11 (Sentry) ◄── Tasks 2, 7
Task 12 (justfile) ◄── Tasks 2, 3, 7, 8
Task 16 (seed data) ◄── Tasks 2, 4
Task 17 (staging VPS) ◄── Task 9
Task 19 (final verification) ◄── all tasks
```

Tasks on the same level can be parallelized if using subagent-driven development.

---

## Task 1: Initialize meta repo and submodule repos

**Files:**
- Create: `.gitignore`
- Create: `.editorconfig`
- Modify: existing `CLAUDE.md` (already committed)

This task transforms the current repo into the meta repo structure and creates the 4 submodule repos.

- [ ] **Step 1: Create the 4 submodule repos on GitHub**

Create empty repos (no README, no .gitignore) on GitHub:
- `kaleem-backend`
- `kaleem-dashboard`
- `kaleem-marketing`
- `kaleem-infra`

```bash
gh repo create kaleem-backend --private --confirm
gh repo create kaleem-dashboard --private --confirm
gh repo create kaleem-marketing --private --confirm
gh repo create kaleem-infra --private --confirm
```

- [ ] **Step 2: Move old code to a reference branch**

The existing `kaleem/` Django project becomes read-only reference. Move it to a branch so it's not in the working tree:

```bash
git checkout -b archive/mvp-reference
git checkout master
```

The old code remains accessible via `git log archive/mvp-reference` and `git show archive/mvp-reference:kaleem/...` but is not in the working directory on `master`.

- [ ] **Step 3: Clean the master branch for the new structure**

Remove the old `kaleem/` directory from master (it's preserved on the archive branch):

```bash
git rm -r kaleem/
git commit -m "chore: remove old MVP code from master (archived on archive/mvp-reference branch)"
```

- [ ] **Step 4: Add the 4 submodules**

```bash
git submodule add git@github.com:<your-username>/kaleem-backend.git backend
git submodule add git@github.com:<your-username>/kaleem-dashboard.git dashboard
git submodule add git@github.com:<your-username>/kaleem-marketing.git marketing
git submodule add git@github.com:<your-username>/kaleem-infra.git infra
```

- [ ] **Step 5: Create `.editorconfig`**

```ini
# .editorconfig
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{js,ts,tsx,jsx,json,yml,yaml,css,html,astro}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab

[justfile]
indent_style = space
indent_size = 4
```

- [ ] **Step 6: Update `.gitignore` for the meta repo**

```gitignore
# OS
.DS_Store
Thumbs.db

# IDE
.idea/
.vscode/
*.swp
*.swo

# Environment
.env
.env.*
!.env.example

# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/

# Node
node_modules/

# Build artifacts
dist/
build/
staticfiles/

# Claude
.claude/memory/
```

- [ ] **Step 7: Commit the meta repo structure**

```bash
git add .editorconfig .gitignore .gitmodules backend dashboard marketing infra
git commit -m "chore: initialize meta repo with 4 submodules (backend, dashboard, marketing, infra)"
```

---

## Task 2: Backend submodule — Django project scaffold

**Files (inside `backend/`):**
- Create: `pyproject.toml`
- Create: `config/settings/base.py`, `config/settings/local.py`, `config/settings/test.py`, `config/settings/production.py`
- Create: `config/urls.py`, `config/wsgi.py`, `config/asgi.py`, `config/celery_app.py`, `config/api_router.py`
- Create: `manage.py`
- Create: `requirements/base.txt`, `requirements/local.txt`, `requirements/production.txt`
- Create: `.gitignore`
- Create: `CLAUDE.md` (backend-specific)

- [ ] **Step 1: Initialize the backend submodule with a Django project**

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install django djangorestframework django-environ django-allauth drf-spectacular django-cors-headers celery django-celery-beat redis whitenoise argon2-cffi django-import-linter
django-admin startproject config .
```

- [ ] **Step 2: Restructure settings into split files**

Replace the generated `config/settings.py` with a settings package:

```bash
rm config/settings.py
mkdir -p config/settings
touch config/settings/__init__.py
```

Create `config/settings/base.py` with the foundation settings from the roadmap spec. Key differences from the old code:
- `AUTH_USER_MODEL = "identity.User"` (not `users.User`)
- CSRF middleware is **enabled** (not commented out)
- `REST_FRAMEWORK` uses `SessionAuthentication` (not the CSRF-exempt hack)
- `LOCAL_APPS` starts with only `"kaleem.platform"` — no business modules yet
- Structured JSON logging
- `INSTALLED_APPS` includes `import_linter`

```python
# config/settings/base.py
"""Base settings for kaleem."""

from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve(strict=True).parent.parent.parent
APPS_DIR = BASE_DIR / "kaleem"
env = environ.Env()

READ_DOT_ENV_FILE = env.bool("DJANGO_READ_DOT_ENV_FILE", default=False)
if READ_DOT_ENV_FILE:
    env.read_env(str(BASE_DIR / ".env"))

# GENERAL
DEBUG = env.bool("DJANGO_DEBUG", False)
TIME_ZONE = "UTC"
LANGUAGE_CODE = "en-us"
LANGUAGES = [
    ("en", "English"),
    ("ar", "Arabic"),
]
SITE_ID = 1
USE_I18N = True
USE_TZ = True
LOCALE_PATHS = [str(BASE_DIR / "locale")]

# DATABASES
DATABASES = {"default": env.db("DATABASE_URL")}
DATABASES["default"]["ATOMIC_REQUESTS"] = True
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# URLS
ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

# APPS
DJANGO_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.sites",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.admin",
    "django.forms",
]
THIRD_PARTY_APPS = [
    "allauth",
    "allauth.account",
    "allauth.mfa",
    "allauth.socialaccount",
    "django_celery_beat",
    "rest_framework",
    "corsheaders",
    "drf_spectacular",
]
LOCAL_APPS = [
    "kaleem.platform",
    # Business modules added here as they are built in later phases
]
INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

# AUTHENTICATION
AUTHENTICATION_BACKENDS = [
    "django.contrib.auth.backends.ModelBackend",
    "allauth.account.auth_backends.AuthenticationBackend",
]
# AUTH_USER_MODEL will be set to "identity.User" in Phase A.
# For Phase 0, we use Django's default User since identity module doesn't exist yet.
# AUTH_USER_MODEL = "identity.User"
LOGIN_REDIRECT_URL = "/"
LOGIN_URL = "account_login"

# PASSWORDS
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
    "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
]

# MIDDLEWARE
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",  # CSRF ENABLED — never disable
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "allauth.account.middleware.AccountMiddleware",
    "kaleem.platform.middleware.RequestIDMiddleware",
]

# STATIC
STATIC_ROOT = str(BASE_DIR / "staticfiles")
STATIC_URL = "/static/"
STATICFILES_DIRS = [str(APPS_DIR / "static")]

# MEDIA
MEDIA_ROOT = str(APPS_DIR / "media")
MEDIA_URL = "/media/"

# TEMPLATES
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [str(APPS_DIR / "templates")],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.template.context_processors.i18n",
                "django.template.context_processors.media",
                "django.template.context_processors.static",
                "django.template.context_processors.tz",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

FORM_RENDERER = "django.forms.renderers.TemplatesSetting"

# SECURITY
SESSION_COOKIE_HTTPONLY = True
CSRF_COOKIE_HTTPONLY = False  # False so JS can read it for AJAX
X_FRAME_OPTIONS = "DENY"

# EMAIL
EMAIL_BACKEND = env(
    "DJANGO_EMAIL_BACKEND",
    default="django.core.mail.backends.smtp.EmailBackend",
)
EMAIL_TIMEOUT = 5

# ADMIN
ADMIN_URL = "admin/"

# LOGGING — structured JSON
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "()": "kaleem.platform.logging.JSONFormatter",
        },
        "verbose": {
            "format": "%(levelname)s %(asctime)s %(name)s %(message)s",
        },
    },
    "handlers": {
        "console": {
            "level": "DEBUG",
            "class": "logging.StreamHandler",
            "formatter": "json",
        },
    },
    "root": {"level": "INFO", "handlers": ["console"]},
}

# CELERY
if USE_TZ:
    CELERY_TIMEZONE = TIME_ZONE
CELERY_BROKER_URL = env("CELERY_BROKER_URL", default="redis://localhost:6379/0")
CELERY_RESULT_BACKEND = CELERY_BROKER_URL
CELERY_RESULT_EXTENDED = True
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TASK_TIME_LIMIT = 5 * 60
CELERY_TASK_SOFT_TIME_LIMIT = 60
CELERY_BEAT_SCHEDULER = "django_celery_beat.schedulers:DatabaseScheduler"

# ALLAUTH
ACCOUNT_ALLOW_REGISTRATION = env.bool("DJANGO_ACCOUNT_ALLOW_REGISTRATION", True)
ACCOUNT_AUTHENTICATION_METHOD = "email"
ACCOUNT_EMAIL_REQUIRED = True
ACCOUNT_USERNAME_REQUIRED = False
ACCOUNT_USER_MODEL_USERNAME_FIELD = None
ACCOUNT_EMAIL_VERIFICATION = "mandatory"

# DRF
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework.authentication.SessionAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_PAGINATION_CLASS": "kaleem.platform.pagination.StandardPagination",
    "PAGE_SIZE": 25,
}

SPECTACULAR_SETTINGS = {
    "TITLE": "kaleem API",
    "DESCRIPTION": "API documentation for kaleem LMS",
    "VERSION": "0.1.0",
    "SERVE_PERMISSIONS": ["rest_framework.permissions.AllowAny"],
    "SCHEMA_PATH_PREFIX": "/api/",
}

# STRIPE (Phase B — placeholder for now)
STRIPE_SECRET_KEY = env("STRIPE_SECRET_KEY", default="")
STRIPE_WEBHOOK_SECRET = env("STRIPE_WEBHOOK_SECRET", default="")

# SENTRY
SENTRY_DSN = env("SENTRY_DSN", default="")
if SENTRY_DSN:
    import sentry_sdk
    sentry_sdk.init(
        dsn=SENTRY_DSN,
        traces_sample_rate=env.float("SENTRY_TRACES_SAMPLE_RATE", default=0.1),
        profiles_sample_rate=env.float("SENTRY_PROFILES_SAMPLE_RATE", default=0.1),
    )
```

- [ ] **Step 3: Create local and test settings**

`config/settings/local.py`:
```python
"""Local development settings."""
from .base import *  # noqa: F401, F403

DEBUG = True
SECRET_KEY = env(
    "DJANGO_SECRET_KEY",
    default="local-dev-secret-key-change-in-production",
)
ALLOWED_HOSTS = ["localhost", "0.0.0.0", "127.0.0.1"]

# CORS — allow the local frontend
CORS_ALLOWED_ORIGINS = [
    "http://localhost:5173",  # Vite dev server
    "http://localhost:4321",  # Astro dev server
]
CORS_ALLOW_CREDENTIALS = True
CSRF_TRUSTED_ORIGINS = [
    "http://localhost:5173",
    "http://localhost:4321",
]

# EMAIL — console backend for local
EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"

# DEBUG TOOLBAR
INSTALLED_APPS += ["debug_toolbar"]  # noqa: F405
MIDDLEWARE += ["debug_toolbar.middleware.DebugToolbarMiddleware"]  # noqa: F405
INTERNAL_IPS = ["127.0.0.1"]

# Use verbose formatter locally for readability
LOGGING["handlers"]["console"]["formatter"] = "verbose"  # noqa: F405
```

`config/settings/test.py`:
```python
"""Test settings."""
from .base import *  # noqa: F401, F403

SECRET_KEY = "test-secret-key-not-for-production"
TEST_RUNNER = "django.test.runner.DiscoverRunner"
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
CELERY_TASK_ALWAYS_EAGER = True
```

`config/settings/production.py`:
```python
"""Production settings."""
from .base import *  # noqa: F401, F403

SECRET_KEY = env("DJANGO_SECRET_KEY")
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")
SECURE_SSL_REDIRECT = env.bool("DJANGO_SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True

CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])
CORS_ALLOW_CREDENTIALS = True
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])
```

- [ ] **Step 4: Create the app directory structure**

```bash
mkdir -p kaleem/platform
mkdir -p kaleem/static
mkdir -p kaleem/media
mkdir -p kaleem/templates
touch kaleem/__init__.py
touch kaleem/platform/__init__.py
```

- [ ] **Step 5: Create `config/urls.py`**

```python
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path

from kaleem.platform.views import health_live, health_ready

urlpatterns = [
    path(settings.ADMIN_URL, admin.site.urls),
    path("api/", include("config.api_router")),
    path("health/live", health_live, name="health-live"),
    path("health/ready", health_ready, name="health-ready"),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    if "debug_toolbar" in settings.INSTALLED_APPS:
        import debug_toolbar
        urlpatterns = [path("__debug__/", include(debug_toolbar.urls))] + urlpatterns
```

- [ ] **Step 6: Create `config/api_router.py`**

```python
from django.conf import settings
from rest_framework.routers import DefaultRouter, SimpleRouter

router = DefaultRouter() if settings.DEBUG else SimpleRouter()

# Business module viewsets will be registered here as they are built.
# Phase 0: no viewsets registered.

app_name = "api"
urlpatterns = router.urls
```

- [ ] **Step 7: Create `config/celery_app.py`**

```python
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.local")

app = Celery("kaleem")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
```

- [ ] **Step 8: Create `pyproject.toml`**

```toml
[tool.pytest.ini_options]
minversion = "6.0"
addopts = "--ds=config.settings.test --reuse-db --import-mode=importlib"
python_files = ["tests.py", "test_*.py"]

[tool.coverage.run]
include = ["kaleem/**"]
omit = ["*/migrations/*", "*/tests/*"]

[tool.mypy]
python_version = "3.12"
check_untyped_defs = true
ignore_missing_imports = true
warn_unused_ignores = true
warn_redundant_casts = true
plugins = ["mypy_django_plugin.main", "mypy_drf_plugin.main"]

[[tool.mypy.overrides]]
module = "*.migrations.*"
ignore_errors = true

[tool.django-stubs]
django_settings_module = "config.settings.test"

[tool.ruff]
target-version = "py312"
extend-exclude = ["*/migrations/*.py", "staticfiles/*"]

[tool.ruff.lint]
select = [
    "F", "E", "W", "C90", "I", "N", "UP", "YTT", "ASYNC", "S", "BLE",
    "FBT", "B", "A", "COM", "C4", "DTZ", "T10", "DJ", "EM", "EXE", "FA",
    "ISC", "ICN", "G", "INP", "PIE", "T20", "PYI", "PT", "Q", "RSE",
    "RET", "SLF", "SLOT", "SIM", "TID", "TCH", "INT", "PTH", "ERA", "PD",
    "PGH", "PL", "TRY", "FLY", "PERF", "RUF",
]
ignore = ["S101", "RUF012", "SIM102"]

[tool.ruff.lint.isort]
force-single-line = true

[tool.importlinter]
root_packages = ["kaleem"]

[[tool.importlinter.contracts]]
name = "platform imports no business modules"
type = "independence"
modules = [
    "kaleem.platform",
]
# More contracts will be added as business modules are created in later phases
```

- [ ] **Step 9: Create requirements files**

`requirements/base.txt`:
```
django>=5.1,<5.2
djangorestframework>=3.15
django-environ>=0.11
django-allauth[mfa]>=64.0
drf-spectacular>=0.27
django-cors-headers>=4.4
django-celery-beat>=2.7
celery[redis]>=5.4
redis>=5.0
whitenoise>=6.7
argon2-cffi>=23.1
sentry-sdk[django]>=2.0
opentelemetry-api>=1.24
opentelemetry-sdk>=1.24
opentelemetry-instrumentation-django>=0.45b0
import-linter>=2.0
psycopg[binary]>=3.2
```

`requirements/local.txt`:
```
-r base.txt
django-debug-toolbar>=4.4
django-silk>=5.1
pytest>=8.0
pytest-django>=4.8
pytest-cov>=5.0
factory-boy>=3.3
django-stubs>=5.0
djangorestframework-stubs>=3.15
mypy>=1.10
```

`requirements/production.txt`:
```
-r base.txt
gunicorn>=22.0
```

- [ ] **Step 10: Create `.env.example` and backend `.gitignore`**

`.env.example`:
```
DATABASE_URL=postgres://kaleem:kaleem@localhost:5432/kaleem
CELERY_BROKER_URL=redis://localhost:6379/0
DJANGO_SECRET_KEY=change-me-in-production
DJANGO_DEBUG=True
DJANGO_READ_DOT_ENV_FILE=True
SENTRY_DSN=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
```

`.gitignore`:
```
__pycache__/
*.py[cod]
*.egg-info/
.venv/
*.sqlite3
staticfiles/
media/
.env
.env.*
!.env.example
htmlcov/
.coverage
.mypy_cache/
.pytest_cache/
```

- [ ] **Step 11: Create backend `CLAUDE.md`**

```markdown
# Backend — kaleem Django API

This is the Django + DRF modular monolith backend for kaleem.

## Quick start

From the meta repo root: `just dev` brings up everything.
From this directory: `just test-backend` or `pytest`.

## Module structure

All business modules live under `kaleem/`. Currently only `kaleem.platform` exists (Phase 0).
Business modules (identity, billing, scheduling, etc.) will be added in later phases.

## Rules

- CSRF middleware is ENABLED. Never disable it.
- Module boundaries enforced by import-linter. Run `lint-imports` to check.
- Business logic goes in `<module>/services.py`, never on models.
- No module may import another module's models. Use the public API.
- All settings in env vars via django-environ. Never hardcode secrets.

## Settings

- Local: `config.settings.local`
- Test: `config.settings.test`
- Production: `config.settings.production`
```

- [ ] **Step 12: Commit the backend scaffold**

```bash
cd backend
git add -A
git commit -m "chore: scaffold Django 5 project with split settings, Celery, DRF, allauth"
git push origin main
cd ..
git add backend
git commit -m "chore: update backend submodule — Django scaffold"
```

---

## Task 3: Backend — Docker Compose for local dev

**Files:**
- Create: `backend/Dockerfile`
- Create: `docker-compose.local.yml` (meta repo root)

- [ ] **Step 1: Create the backend Dockerfile**

`backend/Dockerfile`:
```dockerfile
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements/ requirements/
RUN pip install --no-cache-dir -r requirements/local.txt

COPY . .

FROM base AS dev
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
```

- [ ] **Step 2: Create `docker-compose.local.yml` in meta repo root**

```yaml
# docker-compose.local.yml — local development stack
services:
  django:
    build:
      context: ./backend
      target: dev
    command: python manage.py runserver 0.0.0.0:8000
    volumes:
      - ./backend:/app
    ports:
      - "8000:8000"
    env_file:
      - ./backend/.env
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.local
      - DJANGO_READ_DOT_ENV_FILE=True
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: kaleem
      POSTGRES_USER: kaleem
      POSTGRES_PASSWORD: kaleem
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kaleem"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  celery_worker:
    build:
      context: ./backend
      target: dev
    command: celery -A config.celery_app worker -l info
    volumes:
      - ./backend:/app
    env_file:
      - ./backend/.env
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.local
      - DJANGO_READ_DOT_ENV_FILE=True
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  celery_beat:
    build:
      context: ./backend
      target: dev
    command: celery -A config.celery_app beat -l info
    volumes:
      - ./backend:/app
    env_file:
      - ./backend/.env
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.local
      - DJANGO_READ_DOT_ENV_FILE=True
    depends_on:
      redis:
        condition: service_healthy

  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "8025:8025"  # web UI
      - "1025:1025"  # SMTP

volumes:
  postgres_data:
```

- [ ] **Step 3: Create backend `.env` from example**

```bash
cp backend/.env.example backend/.env
```

- [ ] **Step 4: Verify the stack starts**

```bash
docker compose -f docker-compose.local.yml up -d --build
docker compose -f docker-compose.local.yml exec django python manage.py migrate
docker compose -f docker-compose.local.yml exec django python manage.py createsuperuser --noinput --email admin@kaleem.test 2>/dev/null || true
```

Expected: all services healthy, Django responds on `http://localhost:8000/health/live` (will 404 until platform module is built in Task 4).

- [ ] **Step 5: Commit**

```bash
cd backend
git add Dockerfile
git commit -m "chore: add Dockerfile for local development"
git push origin main
cd ..
git add docker-compose.local.yml backend
git commit -m "chore: add Docker Compose local stack (Django, Postgres, Redis, Celery, Mailpit)"
```

---

## Task 4: Backend — Platform module

**Files (inside `backend/`):**
- Create: `kaleem/platform/apps.py`
- Create: `kaleem/platform/middleware.py`
- Create: `kaleem/platform/logging.py`
- Create: `kaleem/platform/pagination.py`
- Create: `kaleem/platform/exceptions.py`
- Create: `kaleem/platform/views.py`
- Create: `kaleem/platform/tests/__init__.py`
- Create: `kaleem/platform/tests/test_health.py`
- Create: `kaleem/platform/tests/test_middleware.py`

The `platform` module is the only business-adjacent module in Phase 0. It provides cross-cutting utilities: health checks, request ID propagation, structured JSON logging, pagination base classes, and common exceptions.

- [ ] **Step 1: Create `apps.py`**

```python
# kaleem/platform/apps.py
from django.apps import AppConfig


class PlatformConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "kaleem.platform"
    verbose_name = "Platform"
```

- [ ] **Step 2: Create `middleware.py` — request ID middleware**

```python
# kaleem/platform/middleware.py
import uuid

from django.http import HttpRequest, HttpResponse


class RequestIDMiddleware:
    """Attach a unique request ID to every request for tracing."""

    HEADER = "X-Request-ID"

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        request_id = request.headers.get(self.HEADER, str(uuid.uuid4()))
        request.request_id = request_id
        response = self.get_response(request)
        response[self.HEADER] = request_id
        return response
```

- [ ] **Step 3: Create `logging.py` — structured JSON formatter**

```python
# kaleem/platform/logging.py
import json
import logging
from datetime import datetime, timezone


class JSONFormatter(logging.Formatter):
    """Format log records as single-line JSON for Loki/ELK ingestion."""

    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "timestamp": datetime.now(tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }
        if hasattr(record, "request_id"):
            log_entry["request_id"] = record.request_id
        if record.exc_info and record.exc_info[1]:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry, default=str)
```

- [ ] **Step 4: Create `pagination.py`**

```python
# kaleem/platform/pagination.py
from rest_framework.pagination import PageNumberPagination


class StandardPagination(PageNumberPagination):
    page_size = 25
    page_size_query_param = "page_size"
    max_page_size = 100
```

- [ ] **Step 5: Create `exceptions.py`**

```python
# kaleem/platform/exceptions.py


class KaleemError(Exception):
    """Base exception for all kaleem domain errors."""

    def __init__(self, message: str, code: str = "error"):
        self.message = message
        self.code = code
        super().__init__(message)


class NotFoundError(KaleemError):
    """Raised when a requested resource does not exist."""

    def __init__(self, resource: str, identifier: str | int):
        super().__init__(
            message=f"{resource} with identifier '{identifier}' not found.",
            code="not_found",
        )


class PermissionDeniedError(KaleemError):
    """Raised when a user lacks permission for an action."""

    def __init__(self, action: str):
        super().__init__(
            message=f"Permission denied for action: {action}.",
            code="permission_denied",
        )


class ValidationError(KaleemError):
    """Raised when input validation fails."""

    def __init__(self, message: str, field: str | None = None):
        self.field = field
        super().__init__(message=message, code="validation_error")
```

- [ ] **Step 6: Create `views.py` — health check endpoints**

```python
# kaleem/platform/views.py
from django.db import connection
from django.http import JsonResponse


def health_live(request):
    """Liveness probe — is the process running?"""
    return JsonResponse({"status": "ok"})


def health_ready(request):
    """Readiness probe — can the app serve traffic?"""
    checks = {}

    # Database
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = f"error: {e}"

    all_ok = all(v == "ok" for v in checks.values())
    status_code = 200 if all_ok else 503
    return JsonResponse({"status": "ok" if all_ok else "degraded", "checks": checks}, status=status_code)
```

- [ ] **Step 7: Write the failing tests**

`kaleem/platform/tests/__init__.py` — empty file.

`kaleem/platform/tests/test_health.py`:
```python
# kaleem/platform/tests/test_health.py
import pytest
from django.test import Client


@pytest.mark.django_db
class TestHealthEndpoints:
    def test_live_returns_200(self):
        client = Client()
        response = client.get("/health/live")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"

    def test_ready_returns_200_when_db_is_up(self):
        client = Client()
        response = client.get("/health/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["checks"]["database"] == "ok"
```

`kaleem/platform/tests/test_middleware.py`:
```python
# kaleem/platform/tests/test_middleware.py
from django.test import Client, RequestFactory

from kaleem.platform.middleware import RequestIDMiddleware


class TestRequestIDMiddleware:
    def test_generates_request_id_when_not_provided(self):
        client = Client()
        response = client.get("/health/live")
        assert "X-Request-ID" in response
        assert len(response["X-Request-ID"]) == 36  # UUID4 format

    def test_preserves_provided_request_id(self):
        client = Client()
        response = client.get("/health/live", HTTP_X_REQUEST_ID="test-id-123")
        assert response["X-Request-ID"] == "test-id-123"
```

- [ ] **Step 8: Run the tests**

```bash
cd backend
pip install -r requirements/local.txt
pytest kaleem/platform/tests/ -v
```

Expected: all 4 tests pass.

- [ ] **Step 9: Commit**

```bash
cd backend
git add kaleem/platform/
git commit -m "feat: add platform module (health checks, request ID middleware, JSON logging, pagination, exceptions)"
git push origin main
cd ..
git add backend
git commit -m "chore: update backend submodule — platform module"
```

---

## Task 5: Backend — Import-linter configuration

**Files:**
- Modify: `backend/pyproject.toml` (already has basic config from Task 2)

The import-linter contracts are already defined in the `pyproject.toml` from Task 2. This task verifies they work.

- [ ] **Step 1: Verify import-linter passes on the empty project**

```bash
cd backend
lint-imports
```

Expected: `SUCCESS: No contracts violated.`

- [ ] **Step 2: Write a quick test to confirm the contract catches violations**

Create a temporary file to test:
```bash
echo "from kaleem.platform import views" > /tmp/test_violation.py
```

The contract says `kaleem.platform` must be independent — it cannot import from business modules. Since there are no business modules yet, all imports should pass. The real power of import-linter comes in Phase A+ when business modules exist.

- [ ] **Step 3: Commit (nothing to commit — config was in Task 2)**

No new files. Just verification that import-linter works.

---

## Task 6: Backend — Pre-commit + ruff + mypy

**Files:**
- Create: `backend/.pre-commit-config.yaml`

- [ ] **Step 1: Create `.pre-commit-config.yaml`**

```yaml
# backend/.pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-toml
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: check-merge-conflict

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.0
    hooks:
      - id: ruff
        args: ['--fix']
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.11.0
    hooks:
      - id: mypy
        additional_dependencies:
          - django-stubs>=5.0
          - djangorestframework-stubs>=3.15
        args: ['--config-file=pyproject.toml']

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks

  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v3.4.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
```

- [ ] **Step 2: Install and run pre-commit**

```bash
cd backend
pip install pre-commit
pre-commit install
pre-commit install --hook-type commit-msg
pre-commit run --all-files
```

Expected: all hooks pass (trailing whitespace, ruff, etc.).

- [ ] **Step 3: Run ruff separately to confirm**

```bash
cd backend
ruff check .
ruff format --check .
```

Expected: no errors.

- [ ] **Step 4: Run mypy to confirm**

```bash
cd backend
mypy kaleem/
```

Expected: no errors (or only minor ones to fix).

- [ ] **Step 5: Commit**

```bash
cd backend
git add .pre-commit-config.yaml
git commit -m "chore: add pre-commit hooks (ruff, mypy, gitleaks, conventional-commits)"
git push origin main
cd ..
git add backend
git commit -m "chore: update backend submodule — pre-commit hooks"
```

---

## Task 7: Dashboard submodule — React scaffold

**Files (inside `dashboard/`):**
- Standard Vite + React scaffold
- TanStack Router + Query setup
- Tailwind + shadcn/ui init
- `CLAUDE.md` (dashboard-specific)

- [ ] **Step 1: Scaffold with Vite**

```bash
cd dashboard
pnpm create vite@latest . -- --template react-ts
pnpm install
```

- [ ] **Step 2: Install core dependencies**

```bash
pnpm add @tanstack/react-router @tanstack/react-query \
  tailwindcss @tailwindcss/vite \
  axios zod zustand \
  class-variance-authority clsx tailwind-merge
```

Dev dependencies:
```bash
pnpm add -D @tanstack/router-plugin @tanstack/router-devtools \
  @biomejs/biome typescript @types/react @types/react-dom
```

- [ ] **Step 3: Initialize Tailwind**

Add the Tailwind Vite plugin to `vite.config.ts`:
```typescript
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
});
```

Create `src/index.css`:
```css
@import "tailwindcss";
```

- [ ] **Step 4: Initialize shadcn/ui**

```bash
pnpm dlx shadcn@latest init
```

Select: TypeScript, default style, CSS variables.

- [ ] **Step 5: Set up TanStack Router with a placeholder route**

Create `src/routes/__root.tsx`:
```tsx
import { createRootRoute, Outlet } from "@tanstack/react-router";

export const Route = createRootRoute({
  component: () => (
    <div className="min-h-screen bg-background text-foreground">
      <Outlet />
    </div>
  ),
});
```

Create `src/routes/index.tsx`:
```tsx
import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  component: () => (
    <div className="flex items-center justify-center min-h-screen">
      <h1 className="text-4xl font-bold">kaleem</h1>
      <p className="text-muted-foreground mt-2">Phase 0 — Bootstrap complete</p>
    </div>
  ),
});
```

Create `src/main.tsx`:
```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { RouterProvider, createRouter } from "@tanstack/react-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { routeTree } from "./routeTree.gen";
import "./index.css";

const queryClient = new QueryClient();
const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </StrictMode>
);
```

- [ ] **Step 6: Set up Biome for linting/formatting**

```bash
pnpm dlx @biomejs/biome init
```

Update `biome.json`:
```json
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": { "recommended": true }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "tab",
    "lineWidth": 100
  }
}
```

- [ ] **Step 7: Create the API client scaffold**

Create `src/lib/api.ts`:
```typescript
import axios from "axios";

const API_BASE_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000/api/";

export const api = axios.create({
  baseURL: API_BASE_URL,
  withCredentials: true,
  withXSRFToken: true,
  xsrfCookieName: "csrftoken",
  xsrfHeaderName: "X-CSRFToken",
});
```

- [ ] **Step 8: Create feature directory stubs**

```bash
mkdir -p src/features/{identity,billing,scheduling,assessment,curriculum,content,messaging,notifications,engagement,analytics,admin}
mkdir -p src/ui
```

Each directory gets an empty `index.ts` as a placeholder.

- [ ] **Step 9: Create dashboard `CLAUDE.md`**

```markdown
# Dashboard — kaleem React App

Authenticated single-page application for students, parents, teachers, and admins.

## Quick start

From the meta repo root: `just dev` brings up everything.
From this directory: `pnpm dev` (requires backend running on port 8000).

## Stack

React 19, TanStack Router (file-based), TanStack Query, Tailwind CSS, shadcn/ui, Zustand (minimal), Biome (lint/format).

## Rules

- API base URL comes from `VITE_API_URL` env var. Never hardcode URLs.
- Each feature folder mirrors a backend module. No cross-feature imports.
- Shared UI components go in `src/ui/`. Feature-specific components stay in `src/features/<name>/`.
- All API calls go through `src/lib/api.ts` (Axios with CSRF configured).
- Use TanStack Query for all server state. Zustand only for pure client state (theme, sidebar open).
```

- [ ] **Step 10: Verify the dev server starts**

```bash
cd dashboard
pnpm dev
```

Expected: Vite dev server on `http://localhost:5173` showing the "kaleem — Phase 0" placeholder.

- [ ] **Step 11: Commit**

```bash
cd dashboard
git add -A
git commit -m "chore: scaffold React 19 + TanStack Router/Query + Tailwind + shadcn dashboard"
git push origin main
cd ..
git add dashboard
git commit -m "chore: update dashboard submodule — React scaffold"
```

---

## Task 8: Marketing submodule — Astro scaffold

**Files (inside `marketing/`):**
- Standard Astro scaffold with Tailwind
- One placeholder landing page
- `CLAUDE.md`

- [ ] **Step 1: Scaffold with Astro**

```bash
cd marketing
pnpm create astro@latest . -- --template minimal --typescript strict
pnpm add @astrojs/tailwind tailwindcss
```

- [ ] **Step 2: Create a placeholder landing page**

`src/pages/index.astro`:
```astro
---
import Layout from '../layouts/Layout.astro';
---

<Layout title="kaleem — Learn Islamic Sciences">
  <main class="flex items-center justify-center min-h-screen">
    <div class="text-center">
      <h1 class="text-5xl font-bold">kaleem</h1>
      <p class="text-xl text-gray-600 mt-4">Learn Quran, Tafsir, and Arabic from expert teachers</p>
      <p class="text-sm text-gray-400 mt-8">Coming soon</p>
    </div>
  </main>
</Layout>
```

`src/layouts/Layout.astro`:
```astro
---
interface Props { title: string; }
const { title } = Astro.props;
---
<!doctype html>
<html lang="en" dir="ltr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title}</title>
</head>
<body>
  <slot />
</body>
</html>
```

- [ ] **Step 3: Create marketing `CLAUDE.md`**

```markdown
# Marketing — kaleem public website

Static marketing site built with Astro. SEO-optimized, fast, minimal JS.

## Quick start

`pnpm dev` — runs on http://localhost:4321

## Rules

- This is a static site. No client-side state, no API calls.
- Shared Tailwind theme with the dashboard for visual consistency.
- All content is in Astro components or MDX. No CMS yet.
```

- [ ] **Step 4: Verify and commit**

```bash
cd marketing
pnpm dev  # verify it starts
git add -A
git commit -m "chore: scaffold Astro marketing site with placeholder landing page"
git push origin main
cd ..
git add marketing
git commit -m "chore: update marketing submodule — Astro scaffold"
```

---

## Task 9: Infra submodule — Docker Compose production + monitoring

**Files (inside `infra/`):**
- Create: `docker-compose.production.yml`
- Create: `monitoring/docker-compose.monitoring.yml`
- Create: `monitoring/prometheus/prometheus.yml`
- Create: `monitoring/grafana/provisioning/datasources/default.yaml`
- Create: `monitoring/loki/loki-config.yaml`
- Create: `monitoring/uptime-kuma/` (directory)
- Create: `nginx/nginx.conf`
- Create: `CLAUDE.md`

- [ ] **Step 1: Create production Docker Compose**

`docker-compose.production.yml`:
```yaml
services:
  django:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/kaleem-backend:latest
    command: gunicorn config.wsgi --bind 0.0.0.0:8000 --workers 3 --timeout 120
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    env_file:
      - .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/live')"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:16-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    env_file:
      - .env.production
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  celery_worker:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/kaleem-backend:latest
    command: celery -A config.celery_app worker -l info
    env_file:
      - .env.production
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  celery_beat:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/kaleem-backend:latest
    command: celery -A config.celery_app beat -l info
    env_file:
      - .env.production
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.production
    depends_on:
      redis:
        condition: service_healthy

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - certbot_certs:/etc/letsencrypt:ro
    depends_on:
      - django

volumes:
  postgres_data:
  certbot_certs:
```

- [ ] **Step 2: Create monitoring stack**

`monitoring/docker-compose.monitoring.yml`:
```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}

  loki:
    image: grafana/loki:latest
    volumes:
      - ./loki/loki-config.yaml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    command: -config.file=/etc/promtail/config.yml

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    volumes:
      - uptime_kuma_data:/app/data
    ports:
      - "3001:3001"

volumes:
  prometheus_data:
  grafana_data:
  loki_data:
  uptime_kuma_data:
```

- [ ] **Step 3: Create Prometheus config**

`monitoring/prometheus/prometheus.yml`:
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "django"
    metrics_path: "/metrics"
    static_configs:
      - targets: ["django:8000"]

  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
```

- [ ] **Step 4: Create Grafana datasource provisioning**

`monitoring/grafana/provisioning/datasources/default.yaml`:
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
```

- [ ] **Step 5: Create Loki config**

`monitoring/loki/loki-config.yaml`:
```yaml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
```

- [ ] **Step 6: Create nginx config stub**

`nginx/nginx.conf`:
```nginx
events {
    worker_connections 1024;
}

http {
    upstream django {
        server django:8000;
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://django;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /static/ {
            alias /app/staticfiles/;
        }
    }
}
```

- [ ] **Step 7: Create infra `CLAUDE.md`**

```markdown
# Infra — kaleem deployment and monitoring

Docker Compose configs for production and monitoring.

## Structure

- `docker-compose.production.yml` — main production stack
- `monitoring/` — Prometheus, Grafana, Loki, Uptime Kuma
- `nginx/` — reverse proxy config

## Usage

Production: `docker compose -f docker-compose.production.yml up -d`
Monitoring: `docker compose -f monitoring/docker-compose.monitoring.yml up -d`
```

- [ ] **Step 8: Commit**

```bash
cd infra
git add -A
git commit -m "chore: add production Docker Compose, nginx, and monitoring stack (Prometheus, Grafana, Loki, Uptime Kuma)"
git push origin main
cd ..
git add infra
git commit -m "chore: update infra submodule — production and monitoring configs"
```

---

## Task 10: CI pipeline

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the CI workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  pull_request:
    branches: [master, main]
  push:
    branches: [master, main]

concurrency:
  group: ${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

jobs:
  backend-lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install dependencies
        run: pip install -r requirements/local.txt
      - name: Ruff check
        run: ruff check .
      - name: Ruff format check
        run: ruff format --check .
      - name: Mypy
        run: mypy kaleem/
      - name: Import linter
        run: lint-imports

  backend-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: kaleem_test
          POSTGRES_USER: kaleem
          POSTGRES_PASSWORD: kaleem
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    defaults:
      run:
        working-directory: backend
    env:
      DATABASE_URL: postgres://kaleem:kaleem@localhost:5432/kaleem_test
      CELERY_BROKER_URL: redis://localhost:6379/0
      DJANGO_SETTINGS_MODULE: config.settings.test
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install dependencies
        run: pip install -r requirements/local.txt
      - name: Run migrations
        run: python manage.py migrate --noinput
      - name: Run tests with coverage
        run: pytest --cov=kaleem --cov-report=term-missing -v

  dashboard-lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: dashboard
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: pnpm/action-setup@v4
        with:
          version: 9
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "pnpm"
          cache-dependency-path: dashboard/pnpm-lock.yaml
      - name: Install dependencies
        run: pnpm install --frozen-lockfile
      - name: Biome check
        run: pnpm dlx @biomejs/biome check .
      - name: TypeScript check
        run: pnpm tsc --noEmit

  dashboard-build:
    runs-on: ubuntu-latest
    needs: dashboard-lint
    defaults:
      run:
        working-directory: dashboard
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: pnpm/action-setup@v4
        with:
          version: 9
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "pnpm"
          cache-dependency-path: dashboard/pnpm-lock.yaml
      - name: Install dependencies
        run: pnpm install --frozen-lockfile
      - name: Build
        run: pnpm build
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add CI pipeline (backend lint/test, dashboard lint/build)"
```

---

## Task 11: Sentry integration

**Files:**
- Modify: `backend/config/settings/base.py` (already has Sentry init from Task 2)
- Modify: `dashboard/src/main.tsx`

Sentry is already configured in `base.py` from Task 2 (conditional on `SENTRY_DSN`). This task adds the frontend integration and verifies the flow.

- [ ] **Step 1: Add Sentry to the dashboard**

```bash
cd dashboard
pnpm add @sentry/react
```

Update `src/main.tsx` to add Sentry initialization before the app renders:
```typescript
import * as Sentry from "@sentry/react";

const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN;
if (SENTRY_DSN) {
  Sentry.init({
    dsn: SENTRY_DSN,
    tracesSampleRate: 0.1,
  });
}
```

Add this block at the top of `main.tsx`, before the `createRoot` call.

- [ ] **Step 2: Create a test error endpoint in Django (dev only)**

Add to `config/urls.py` (inside the `if settings.DEBUG:` block):
```python
def sentry_test(request):
    raise Exception("Sentry test error — delete this endpoint after verification")

if settings.DEBUG:
    urlpatterns += [path("sentry-test/", sentry_test)]
```

- [ ] **Step 3: Verify Sentry receives the error**

Set `SENTRY_DSN` in `backend/.env`, restart Django, hit `http://localhost:8000/sentry-test/`. Confirm the error appears in Sentry.

- [ ] **Step 4: Remove the test endpoint and commit**

Remove the `sentry_test` function and URL from `config/urls.py`. Commit both submodules.

```bash
cd dashboard
git add -A
git commit -m "feat: add Sentry SDK for frontend error tracking"
git push origin main
cd backend
git add -A
git commit -m "chore: verify Sentry integration"
git push origin main
cd ..
git add dashboard backend
git commit -m "feat: Sentry integration verified in backend and dashboard"
```

---

## Task 12: Justfile

**Files:**
- Create: `justfile` (meta repo root)

- [ ] **Step 1: Create the justfile**

```just
# justfile — kaleem task runner
# Run `just` to see all available commands.

# Default: list available commands
default:
    @just --list

# ─── Setup ────────────────────────────────────────────────────

# Clone submodules, install deps, create DBs, seed data
setup:
    git submodule update --init --recursive
    docker compose -f docker-compose.local.yml up -d postgres redis
    @echo "Waiting for Postgres..."
    sleep 3
    cd backend && pip install -r requirements/local.txt
    cd backend && python manage.py migrate
    cd dashboard && pnpm install
    cd marketing && pnpm install
    @echo "Setup complete. Run 'just dev' to start."

# ─── Development ──────────────────────────────────────────────

# Bring up everything locally
dev:
    docker compose -f docker-compose.local.yml up -d

# Stop all local services
stop:
    docker compose -f docker-compose.local.yml down

# ─── Testing ──────────────────────────────────────────────────

# Run all tests (backend + frontend + boundary linter)
test: test-backend test-frontend check-boundaries

# Run backend tests
test-backend:
    cd backend && pytest -v --cov=kaleem --cov-report=term-missing

# Run frontend type check (no test framework in Phase 0)
test-frontend:
    cd dashboard && pnpm tsc --noEmit

# ─── Linting ──────────────────────────────────────────────────

# Run all linters
lint: lint-backend lint-frontend check-boundaries

# Lint backend (ruff + mypy)
lint-backend:
    cd backend && ruff check .
    cd backend && ruff format --check .
    cd backend && mypy kaleem/

# Lint frontend (biome)
lint-frontend:
    cd dashboard && pnpm dlx @biomejs/biome check .

# Check module boundary contracts
check-boundaries:
    cd backend && lint-imports

# ─── Database ─────────────────────────────────────────────────

# Run Django migrations
migrate:
    cd backend && python manage.py migrate

# Open Django shell
shell:
    cd backend && python manage.py shell_plus 2>/dev/null || cd backend && python manage.py shell

# Reset DB and load seed data
seed:
    cd backend && python manage.py flush --noinput
    @echo "Seed data will be available after Phase A."

# ─── Infrastructure ───────────────────────────────────────────

# Deploy to staging (placeholder)
deploy:
    @echo "Deploy runbook: see docs/runbook/deploy.md"

# Scaffold a new backend module
new-module name:
    @echo "Creating module kaleem/{{name}}..."
    mkdir -p backend/kaleem/{{name}}/{api,tests}
    touch backend/kaleem/{{name}}/__init__.py
    touch backend/kaleem/{{name}}/apps.py
    touch backend/kaleem/{{name}}/models.py
    touch backend/kaleem/{{name}}/services.py
    touch backend/kaleem/{{name}}/api/__init__.py
    touch backend/kaleem/{{name}}/api/serializers.py
    touch backend/kaleem/{{name}}/api/views.py
    touch backend/kaleem/{{name}}/tests/__init__.py
    @echo "Module scaffolded. Remember to:"
    @echo "  1. Add 'kaleem.{{name}}' to LOCAL_APPS in settings"
    @echo "  2. Add import-linter contracts in pyproject.toml"
    @echo "  3. Create docs/architecture/{{name}}.md"
```

- [ ] **Step 2: Install just**

```bash
# On Arch Linux
sudo pacman -S just

# Or via cargo
cargo install just
```

- [ ] **Step 3: Verify commands work**

```bash
just              # shows command list
just lint-backend # should pass
just test-backend # should pass (4 platform tests)
```

- [ ] **Step 4: Commit**

```bash
git add justfile
git commit -m "chore: add justfile with setup, dev, test, lint, and scaffold commands"
```

---

## Task 13: Agent tooling — hooks, skills, per-submodule CLAUDE.md

**Files:**
- Create: `.claude/settings.json`
- Create: `.claude/commands/new-feature.md`
- Create: `.claude/commands/new-adr.md`
- Create: `.claude/commands/ship.md`
- Create: `.claude/commands/journal.md`
- Create: `AGENTS.md` (symlink to `CLAUDE.md`)
- Create: `.github/copilot-instructions.md`

Note: per-submodule `CLAUDE.md` files were created in Tasks 2, 7, 8, 9.

- [ ] **Step 1: Create `.claude/settings.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "intercept",
            "command": "echo \"$TOOL_INPUT\" | grep -qE '(rm -rf|git push --force|git reset --hard|git checkout \\.)' && echo 'BLOCKED: Destructive command detected. Use with explicit approval only.' && exit 1 || exit 0"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "notification",
            "command": "FILE=$(echo \"$TOOL_INPUT\" | grep -oP '\"file_path\":\\s*\"\\K[^\"]+'); if [[ \"$FILE\" == *.py ]]; then cd backend && ruff check --fix \"$FILE\" 2>/dev/null && ruff format \"$FILE\" 2>/dev/null; fi"
          }
        ]
      }
    ]
  }
}
```

Note: These hooks are intentionally minimal for Phase 0. More sophisticated hooks (model change detection, public API warnings, etc.) will be added as modules are built.

- [ ] **Step 2: Create slash command templates**

`.claude/commands/new-feature.md`:
```markdown
Create a new feature spec from the template.

Usage: /new-feature <name>

Steps:
1. Copy docs/templates/spec.md to docs/superpowers/specs/$(date +%Y-%m-%d)-<name>.md
2. Fill in the frontmatter (name, phase, modules)
3. Open the file for editing
4. Do NOT proceed to code until the spec is committed and approved
```

`.claude/commands/new-adr.md`:
```markdown
Create a new Architecture Decision Record.

Usage: /new-adr <title>

Steps:
1. Find the highest-numbered ADR in docs/adr/
2. Create docs/adr/NNNN-<title>.md from docs/templates/adr.md
3. Fill in the date and title
4. Open the file for editing
```

`.claude/commands/ship.md`:
```markdown
Walk the Definition of Done checklist (D9) for the current feature.

Verify each item:
- [ ] Spec committed and status=shipped
- [ ] Plan committed and status=done, all steps checked
- [ ] All tests passing locally and in CI
- [ ] import-linter green
- [ ] Coverage on new code >= 80% on services/models
- [ ] Self-review checklist walked
- [ ] Manually tested golden path in browser
- [ ] 2 edge cases manually tested
- [ ] Deployed to staging, smoke-tested
- [ ] Module architecture doc updated if public API changed
- [ ] Journal entry written
- [ ] STATE.md updated
- [ ] ISSUES.md reviewed for new issues

Do NOT mark the feature as complete until ALL items are checked.
```

`.claude/commands/journal.md`:
```markdown
Open (or create) this week's journal entry.

Steps:
1. Calculate current ISO week: $(date +%Y-%W)
2. Open docs/superpowers/journal/$(date +%Y)-$(date +%W).md
3. If it doesn't exist, create it from docs/templates/journal-week.md
4. Fill in the frontmatter with current phase from STATE.md
```

- [ ] **Step 3: Create `AGENTS.md` symlink and Copilot instructions**

```bash
ln -s CLAUDE.md AGENTS.md
mkdir -p .github
```

`.github/copilot-instructions.md`:
```markdown
# kaleem — Copilot Instructions

This is a modular-monolith LMS. Key rules:

1. No module may import another module's models. Use `<module>/services.py` public API.
2. CSRF middleware is ENABLED. Never disable it.
3. Every feature needs a spec in docs/superpowers/specs/ BEFORE any code.
4. TDD: write failing test first, then code.
5. Business logic goes in services.py, never on models.
6. Full roadmap: docs/superpowers/specs/2026-04-11-rebuild-roadmap-design.md
7. Current state: see STATE.md
```

- [ ] **Step 4: Commit**

```bash
git add .claude/ AGENTS.md .github/copilot-instructions.md
git commit -m "chore: add agent tooling (Claude hooks, slash commands, AGENTS.md, Copilot instructions)"
```

---

## Task 14: Documentation skeleton + templates

**Files:**
- Create: `docs/templates/spec.md`
- Create: `docs/templates/plan.md`
- Create: `docs/templates/adr.md`
- Create: `docs/templates/journal-week.md`
- Create: `docs/architecture/overview.md`
- Create: `docs/developer-guide/local-setup.md`
- Create: `docs/developer-guide/testing.md`
- Create: `docs/developer-guide/common-tasks.md`
- Create: `docs/developer-guide/self-review.md`
- Create: `docs/runbook/deploy.md`
- Create: `docs/runbook/backup-restore.md`
- Create: directories: `docs/adr/`, `docs/runbook/`, `docs/superpowers/journal/`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p docs/{templates,architecture,adr,developer-guide,runbook,superpowers/journal,superpowers/plans}
```

- [ ] **Step 2: Create spec template**

Copy the template from Section 4.3 of the roadmap spec into `docs/templates/spec.md`.

- [ ] **Step 3: Create plan template**

Copy the plan template from Section 4.3 into `docs/templates/plan.md`.

- [ ] **Step 4: Create ADR template**

Copy the ADR template from Section 4.3 into `docs/templates/adr.md`.

- [ ] **Step 5: Create journal template**

Copy the journal template from Section 4.3 into `docs/templates/journal-week.md`.

- [ ] **Step 6: Create `docs/architecture/overview.md`**

```markdown
# kaleem Architecture Overview

## Module map

```mermaid
graph TD
    platform[platform<br/>cross-cutting utilities]

    identity[identity<br/>users, profiles, auth]
    billing[billing<br/>plans, subscriptions, stripe]
    scheduling[scheduling<br/>availability, bookings, sessions]
    assessment[assessment<br/>reports, ratings, progress]
    curriculum[curriculum<br/>courses, lessons]
    content[content<br/>resources, files]
    messaging[messaging<br/>chat, messages]
    notifications[notifications<br/>email, in-app, reminders]
    engagement[engagement<br/>points, badges, streaks]
    analytics[analytics<br/>dashboards, aggregation]

    scheduling --> identity
    scheduling --> billing
    scheduling --> notifications
    billing --> identity
    assessment --> identity
    assessment --> scheduling
    curriculum --> identity
    curriculum --> content
    content --> identity
    messaging --> identity
    messaging --> notifications
    notifications --> identity
    engagement --> identity
    analytics --> identity
    analytics --> scheduling
    analytics --> assessment
    analytics --> billing
    analytics --> engagement
```

## Boundary rules

1. No business module imports another module's models
2. All inter-module calls go through `<module>/services.py`
3. `analytics` is read-only — it never writes to other modules
4. `platform` is imported by all, imports from none
5. No circular dependencies at the module level
6. Enforced by `import-linter` in CI

## Current state

**Phase 0** — only `platform` module exists. All other modules are placeholders in the diagram above.
```

- [ ] **Step 7: Create developer guide docs**

`docs/developer-guide/local-setup.md`:
```markdown
# Local Development Setup

## Prerequisites

- Docker + Docker Compose
- Python 3.12+
- Node.js 22+ with pnpm
- just (task runner): `cargo install just` or `sudo pacman -S just`

## Quick start

1. Clone the repo with submodules:
   ```bash
   git clone --recursive <repo-url>
   cd kaleem
   ```

2. Run the setup command:
   ```bash
   just setup
   ```

3. Start all services:
   ```bash
   just dev
   ```

4. Verify:
   - Backend API: http://localhost:8000/health/live
   - Django admin: http://localhost:8000/admin/
   - Dashboard: http://localhost:5173
   - Marketing: http://localhost:4321
   - Mailpit: http://localhost:8025

## Test users

After running `just seed` (available from Phase A):
- Admin: admin@kaleem.test / admin123
- Teacher 1: teacher1@kaleem.test / test123
- Teacher 2: teacher2@kaleem.test / test123
- Student 1-5: student{1-5}@kaleem.test / test123
- Parent 1-3: parent{1-3}@kaleem.test / test123
```

`docs/developer-guide/testing.md`:
```markdown
# Testing Guide

## Running tests

```bash
just test           # all tests (backend + frontend + boundaries)
just test-backend   # backend only
just test-frontend  # frontend only (type check in Phase 0)
```

## TDD workflow (D3)

1. Write the failing test
2. Run it — verify it fails with the expected error
3. Write the minimal code to make it pass
4. Run it — verify it passes
5. Refactor if needed, tests still passing
6. Commit

## Coverage targets

- Services/models: ≥ 80%
- identity module specifically: ≥ 90%
- Views/serializers: best effort, no hard target
```

Copy the self-review checklist from Section 4.5 of the roadmap spec into `docs/developer-guide/self-review.md`.

Create `docs/developer-guide/common-tasks.md` with recipes for: adding a new module, adding a new endpoint, adding a new model, running migrations.

- [ ] **Step 8: Create runbook stubs**

`docs/runbook/deploy.md`:
```markdown
# Deploy Runbook

## Prerequisites
- SSH access to staging/production VPS
- Docker and Docker Compose installed on the VPS
- `.env.production` configured on the VPS

## Steps

1. SSH into the VPS
2. Pull latest images: `docker compose -f docker-compose.production.yml pull`
3. Run migrations: `docker compose -f docker-compose.production.yml exec django python manage.py migrate`
4. Restart services: `docker compose -f docker-compose.production.yml up -d`
5. Verify health: `curl http://localhost:8000/health/ready`
6. Check Sentry for new errors
7. Check Uptime Kuma for any downtime alerts

## Rollback

1. `docker compose -f docker-compose.production.yml down`
2. Tag the previous working image and re-deploy
3. Write an incident note in docs/runbook/incidents.md
```

`docs/runbook/backup-restore.md`:
```markdown
# Backup & Restore Runbook

## Backup (automated daily via cron)

```bash
pg_dump -U kaleem kaleem | gzip > /backups/kaleem-$(date +%Y%m%d).sql.gz
```

## Restore

```bash
gunzip < /backups/kaleem-YYYYMMDD.sql.gz | psql -U kaleem kaleem
```

## Backup drill

Every 2 months, actually restore to a scratch database and verify data integrity.
Record the result in this file.

### Drill log
- (none yet — first drill after staging is live)
```

- [ ] **Step 9: Commit**

```bash
git add docs/
git commit -m "docs: add documentation skeleton (templates, architecture overview, developer guide, runbooks)"
```

---

## Task 15: ADRs 0001–0011

**Files:**
- Create: `docs/adr/0001-modular-monolith.md` through `docs/adr/0011-zoom-v1-webrtc-v2.md`

Each ADR follows the template from Task 14. I'll list each one with its key content. Each is short (20-40 lines).

- [ ] **Step 1: Write ADR-0001 through ADR-0005**

`docs/adr/0001-modular-monolith.md`: Decision to use a modular monolith. Alternatives: flat monolith, microservices. Consequences: import-linter enforcement, module boundary contracts, future service extraction is possible.

`docs/adr/0002-identity-model.md`: Single User + per-role profile tables. Alternatives: multi-table inheritance (old code), JSON blobs. Consequences: one person can have multiple roles, clean FK semantics, no re-hydration queries.

`docs/adr/0003-session-auth-csrf.md`: Session cookies + real CSRF. Alternatives: JWT, CSRF-exempt session (old code). Consequences: simpler, more secure, no refresh token dance, JWT escape hatch (E3) exists for mobile.

`docs/adr/0004-allauth-wrapped.md`: Keep allauth wrapped behind identity module. Alternatives: custom auth. Consequences: auth edge cases solved by allauth, replaceable if needed, escape hatch E6 exists.

`docs/adr/0005-big-v1-scope.md`: User chose the full ~20-feature v1 scope against the recommended minimal v1. Consequences: 18-24 month timeline, escape hatch E4 (phased launch) pre-approved, risks R1 and R2 elevated.

- [ ] **Step 2: Write ADR-0006 through ADR-0011**

`docs/adr/0006-sentry-monitoring.md`: Sentry for error tracking + OpenTelemetry for instrumentation. Alternatives: self-hosted alternatives, no monitoring.

`docs/adr/0007-docker-compose-not-k8s.md`: Docker Compose for orchestration. Alternatives: Kubernetes. Consequences: simpler ops for solo dev, limited to vertical scaling per VPS.

`docs/adr/0008-git-submodules.md`: Meta repo with git submodules. Alternatives: monorepo with pnpm workspaces, fully separate repos. Consequences: submodule friction exists, escape hatch E1.

`docs/adr/0009-csrf-session-not-jwt.md`: (Detailed version of 0003 focusing on the technical rationale — CSRF token flow with React, `withXSRFToken: true` in Axios, `SESSION_COOKIE_HTTPONLY=True`, `CSRF_COOKIE_HTTPONLY=False`.)

`docs/adr/0010-allauth-wrap-strategy.md`: How allauth is wrapped — identity/services.py is the public API, no other module imports from allauth, adapter pattern for customization.

`docs/adr/0011-zoom-v1-webrtc-v2.md`: Zoom integration via adapter in v1, custom WebRTC in v2. The adapter interface (`create_room`, `get_join_url`, `end_room`) is stable across the swap.

- [ ] **Step 3: Commit**

```bash
git add docs/adr/
git commit -m "docs: add ADR-0001 through ADR-0011 (foundational architecture decisions)"
```

---

## Task 16: Seed data scaffolding

**Files (inside `backend/`):**
- Create: `kaleem/platform/management/__init__.py`
- Create: `kaleem/platform/management/commands/__init__.py`
- Create: `kaleem/platform/management/commands/seed.py`

- [ ] **Step 1: Create the management command structure**

```bash
mkdir -p backend/kaleem/platform/management/commands
touch backend/kaleem/platform/management/__init__.py
touch backend/kaleem/platform/management/commands/__init__.py
```

- [ ] **Step 2: Create the seed command scaffold**

`backend/kaleem/platform/management/commands/seed.py`:
```python
"""Seed the database with test data.

Usage:
    python manage.py seed basic    # small dataset for dev
    python manage.py seed rich     # larger dataset for UI/perf testing
"""
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Seed the database with test data"

    def add_arguments(self, parser):
        parser.add_argument(
            "dataset",
            type=str,
            choices=["basic", "rich"],
            help="Which dataset to load: 'basic' (small) or 'rich' (large)",
        )

    def handle(self, *args, **options):
        dataset = options["dataset"]

        if dataset == "basic":
            self._seed_basic()
        elif dataset == "rich":
            self._seed_rich()

    def _seed_basic(self):
        """Phase 0 placeholder — real seed data added in Phase A."""
        self.stdout.write(
            self.style.WARNING(
                "Seed data requires the identity module (Phase A). "
                "Currently only platform module exists."
            )
        )

    def _seed_rich(self):
        """Phase 0 placeholder — real seed data added in Phase B+."""
        self.stdout.write(
            self.style.WARNING(
                "Rich seed data requires billing + scheduling modules (Phase B). "
                "Currently only platform module exists."
            )
        )
```

- [ ] **Step 3: Verify**

```bash
cd backend
python manage.py seed basic
```

Expected: warning message that seed data requires Phase A.

- [ ] **Step 4: Commit**

```bash
cd backend
git add kaleem/platform/management/
git commit -m "chore: scaffold seed data management command (populated in Phase A)"
git push origin main
cd ..
git add backend
git commit -m "chore: update backend submodule — seed command scaffold"
```

---

## Task 17: Staging VPS + deploy runbook verification

This task is about provisioning, which is manual and environment-specific. The steps here are a checklist, not automatable code.

- [ ] **Step 1: Provision a VPS**

Provision a VPS (e.g., Hetzner, DigitalOcean, Contabo) with:
- Ubuntu 24.04 LTS or Debian 12
- ≥ 2 CPU cores, ≥ 4GB RAM, ≥ 40GB SSD
- SSH key authentication (no password login)

- [ ] **Step 2: Install Docker on the VPS**

```bash
ssh root@staging-ip
curl -fsSL https://get.docker.com | sh
apt-get install -y docker-compose-plugin
```

- [ ] **Step 3: Deploy the monitoring stack first**

```bash
scp -r infra/monitoring/ root@staging-ip:/opt/kaleem/monitoring/
ssh root@staging-ip "cd /opt/kaleem/monitoring && docker compose -f docker-compose.monitoring.yml up -d"
```

Verify:
- Grafana on port 3000
- Uptime Kuma on port 3001

- [ ] **Step 4: Configure Uptime Kuma**

Open `http://staging-ip:3001`, create an admin account, add monitors for:
- `http://staging-ip:8000/health/live` — Django liveness
- `http://staging-ip:8000/health/ready` — Django readiness

- [ ] **Step 5: Deploy the application stack**

```bash
scp infra/docker-compose.production.yml root@staging-ip:/opt/kaleem/
scp infra/nginx/nginx.conf root@staging-ip:/opt/kaleem/nginx/
# Create .env.production on the VPS with real secrets
ssh root@staging-ip "cd /opt/kaleem && docker compose -f docker-compose.production.yml up -d"
```

- [ ] **Step 6: Verify staging is live**

```bash
curl http://staging-ip:8000/health/live
# Expected: {"status": "ok"}
curl http://staging-ip:8000/health/ready
# Expected: {"status": "ok", "checks": {"database": "ok"}}
```

- [ ] **Step 7: Update the deploy runbook with actual staging IP**

Update `docs/runbook/deploy.md` with the real staging server address and any environment-specific notes discovered during provisioning.

---

## Task 18: State files + README files

**Files:**
- Create: `STATE.md`
- Create: `ISSUES.md`
- Create: `CONTRIBUTING.md`
- Update: `README.md`

- [ ] **Step 1: Create `STATE.md`**

```markdown
---
current_phase: "0"
active_spec: "2026-04-11-rebuild-roadmap-design"
active_branch: "master"
last_green_ci: null
---

# kaleem Project State

## Current phase: Phase 0 — Bootstrap

## Active spec
docs/superpowers/specs/2026-04-11-rebuild-roadmap-design.md

## In progress
Phase 0 bootstrap tasks (see docs/superpowers/plans/2026-04-12-phase-0-bootstrap-plan.md)

## Next
Phase A — Identity module
```

- [ ] **Step 2: Create `ISSUES.md`**

```markdown
# ISSUES

Spotted-a-problem backlog. Write it here in 15 seconds, keep going (D10).

## Now (next 1-2 weeks)

(empty — Phase 0 just started)

## Soon (next month or two)

(empty)

## Someday / Won't fix

(empty)
```

- [ ] **Step 3: Create `CONTRIBUTING.md`**

```markdown
# Contributing to kaleem

## Process

Every feature follows this lifecycle (no exceptions):

1. **Spec** — write a spec in `docs/superpowers/specs/` from the template
2. **Plan** — write an implementation plan in `docs/superpowers/plans/`
3. **Tests** — write failing tests first
4. **Code** — make tests pass
5. **Review** — self-review against the spec + boundary check
6. **Ship** — merge to main, deploy to staging
7. **Journal** — one-paragraph entry for the week

## Rules

- One feature branch at a time (D6)
- CI must be green before merge (D5)
- No `--no-verify`, no `--force` (D5)
- Module boundaries enforced by import-linter — no cross-module model imports
- See CLAUDE.md for the full operating manual
```

- [ ] **Step 4: Update `README.md`**

```markdown
# kaleem

An LMS for teaching non-Arabic speakers Islamic sciences (Quran, Tafsir, Arabic language).

## Quick start

```bash
git clone --recursive <repo-url>
cd kaleem
just setup
just dev
```

- Backend API: http://localhost:8000
- Dashboard: http://localhost:5173
- Marketing: http://localhost:4321
- Mailpit: http://localhost:8025
- Django Admin: http://localhost:8000/admin/

## Project structure

| Directory | Purpose |
| --- | --- |
| `backend/` | Django + DRF modular monolith (submodule) |
| `dashboard/` | React + TanStack authenticated app (submodule) |
| `marketing/` | Astro marketing site (submodule) |
| `infra/` | Docker, nginx, monitoring (submodule) |
| `docs/` | Specs, ADRs, architecture, developer guide |

## Documentation

- [Architecture overview](docs/architecture/overview.md)
- [Local setup](docs/developer-guide/local-setup.md)
- [Full rebuild roadmap](docs/superpowers/specs/2026-04-11-rebuild-roadmap-design.md)
- [Current state](STATE.md)

## Commands

Run `just` to see all available commands.
```

- [ ] **Step 5: Commit**

```bash
git add STATE.md ISSUES.md CONTRIBUTING.md README.md
git commit -m "docs: add STATE.md, ISSUES.md, CONTRIBUTING.md, and update README"
```

---

## Task 19: Final verification — Phase 0 exit criteria

This is not a task that produces code. It is a checklist that must be walked manually before Phase 0 is declared complete.

- [ ] **Step 1: Fresh clone test**

On a clean machine (or a fresh directory):
```bash
git clone --recursive <repo-url> /tmp/kaleem-test
cd /tmp/kaleem-test
just setup
just dev
```

Verify:
- All Docker services start and are healthy
- `http://localhost:8000/health/live` returns `{"status": "ok"}`
- `http://localhost:8000/health/ready` returns `{"status": "ok", "checks": {"database": "ok"}}`
- `http://localhost:5173` shows the "kaleem — Phase 0" placeholder
- `http://localhost:4321` shows the Astro landing page

- [ ] **Step 2: Test and lint pass**

```bash
just test
just lint
```

Both must complete with zero failures.

- [ ] **Step 3: CI is green**

Push to a branch, open a PR, verify all 4 CI jobs pass:
- backend-lint
- backend-test
- dashboard-lint
- dashboard-build

- [ ] **Step 4: Sentry receives a test error**

Trigger a test error and verify it appears in the Sentry dashboard.

- [ ] **Step 5: Uptime Kuma shows staging as "up"**

Open the Uptime Kuma dashboard and verify the staging monitors are green.

- [ ] **Step 6: Architecture diagram exists**

Verify `docs/architecture/overview.md` contains the module map Mermaid diagram.

- [ ] **Step 7: Onboarding test**

A fresh reader of `CLAUDE.md` + `docs/developer-guide/local-setup.md` should be able to:
1. Understand what kaleem is
2. Get it running locally
3. Know where to find the roadmap, specs, and ADRs
4. Know the D1-D11 rules

If any of these fail, fix the docs before declaring Phase 0 complete.

- [ ] **Step 8: Update STATE.md**

Update `STATE.md`:
```markdown
---
current_phase: "A"
active_spec: null
active_branch: "master"
last_green_ci: "<commit-sha>"
---
```

- [ ] **Step 9: Write the Phase 0 journal entry**

Create `docs/superpowers/journal/2026-<week>.md` from the template. Fill in what shipped, note the phase transition from 0 to A, and record your energy level.

- [ ] **Step 10: Commit final state**

```bash
git add STATE.md docs/superpowers/journal/
git commit -m "chore: complete Phase 0 — Bootstrap done, transition to Phase A"
```

**Phase 0 is complete. The next step is to write the Phase A spec for the identity module.**

---

## Self-review notes

- **Spec coverage:** All Phase 0 deliverables from the roadmap spec are covered: meta repo (T1), backend scaffold (T2-T6), dashboard (T7), marketing (T8), infra + monitoring (T9), CI (T10), Sentry (T11), justfile (T12), agent tooling (T13), docs (T14), ADRs (T15), seed data (T16), staging VPS (T17), state files (T18), exit criteria verification (T19).
- **Placeholder scan:** Task 16 (seed data) and Task 17 (VPS) are intentionally scaffolds — seed data can't be populated until Phase A creates the identity module, and VPS provisioning is manual/environment-specific. Both are documented as such.
- **Type consistency:** No cross-task type dependencies in Phase 0 (it's infrastructure, not feature code with shared interfaces).
- **Missing from spec:** The spec mentions `.claude/skills/` with `/run-tests`, `/check-boundaries`, and `/ship` commands. These are covered in Task 13 as `.claude/commands/` (Claude Code's native format). `/run-tests` and `/check-boundaries` are covered by `just test` and `just check-boundaries` in the justfile — no separate slash command needed.
