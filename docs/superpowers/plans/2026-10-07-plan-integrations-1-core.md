# Integrations slice 1 — Accounts, resolver, email, Settings → Integrations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** Integrations 1 (integrations core). Not a phase: built outside the B2–B11 streams (spec §7).
**Requires:** — (nothing unmerged). **Unblocks:** B5c (WhatsApp, ledger D41), slice 2 (metering and Etqan invoices), the B3 Stripe Connect follow-up, Zoom (B2) and AI (B10) on the resolver.

**Goal:** Every outside service has one place that says which account it uses in the current academy: the academy's own account when connected and on, else Etqan's default when Etqan has it on, the academy's feature switch allows it and Etqan has not suspended the academy's defaults, else nothing. Email moves onto that resolver now (Etqan's default is today's sending; an academy may connect its own SMTP server and from address). Academy admins see one card per service under Settings → Integrations and connect, edit, test and disconnect their own email account; Etqan staff edit and test Etqan's default accounts in the platform admin.

**Architecture:**
- **Backend:** a new package `etqan.integrations` made of two Django apps: `etqan.integrations` (SHARED_APPS, public schema: `PlatformAccount`, the services, the API, the platform admin, the email task) and `etqan.integrations.accounts` (TENANT_APPS, label `integrations_accounts`: `AcademyAccount`). `services/resolver.py` holds `resolve(service)` with its per-request cache on the academy object; `services/accounts.py` connects, disconnects and probes accounts; `services/email.py` sends every email through the resolved account. `providers/` is the small provider interface (`clean`, `last4`, `probe`): email is real (SMTP), WhatsApp, payments, video and AI are `NotYet` stubs. `Academy` gains `etqan_defaults_suspended`. `etqan.platform.tasks.send_email_message` is retired: identity and notifications send through `integrations.services`.
- **API:** `GET /api/v1/integrations/`, `PUT|DELETE /api/v1/integrations/<service>/`, `POST /api/v1/integrations/<service>/test/`, behind the new access resource `integration` (`view`, `update`). No feature switch.
- **Platform admin:** `PlatformAccount` on the bare base domain's Django admin: enable, config, write-only secrets, a Test action.
- **Dashboard:** `src/features/integrations/` (schemas, api, queries, errors, `IntegrationsPage`, `EmailAccountForm`), the route `/settings/integrations`, a Settings nav item, `src/locales/{en,ar}/integrations.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Celery, `cryptography` Fernet through `etqan.platform.secrets`, Django's SMTP backend; React 19 + TanStack Router/Query, react-hook-form + zod 4, i18next.

**Spec:** `docs/superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md` — slice 1 of §7: §3 (accounts and resolution), §4 email row, §6 Settings → Integrations and the platform admin's default accounts, §8 resolver/secrets/probe tests. Out of this slice: metering, prices, invoices, billing screens and the suspend switch's admin control (slice 2); Stripe Connect onboarding (B3 follow-up); the WhatsApp, Zoom and AI providers (their phases).

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), the meta repo (trunk `master`). `marketing/` and `infra/` are not touched.
- Work on `feat/integrations` in `backend/`, `dashboard/` and the meta worktree (all three already exist and are checked out in `/home/abdulkhalek/Projects/etqan_tutor-wt/integrations`). Check first: `git -C backend branch --show-current` and `git -C dashboard branch --show-current` print `feat/integrations`.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`); in meta commit only explicit paths, never `git commit -a` (it captures submodule pointers). Do not touch `/home/abdulkhalek/Projects/etqan_tutor` or any other worktree.
- Commits use Conventional Commits and end with the trailer `Co-Authored-By: <implementing model> <noreply@anthropic.com>`, where `<implementing model>` is the name of the model that runs the task (for example `Claude Opus 5.5 (1M context)`). Set it once per shell: `TRAILER="Co-Authored-By: <implementing model> <noreply@anthropic.com>"` with the real name filled in; every commit below passes `-m "$TRAILER"`.

**Tenancy**
- django-tenants: one schema per academy; `PlatformAccount` is SHARED_APPS (public schema only), `AcademyAccount` is TENANT_APPS (every academy schema). Migrate with `migrate_schemas` (the stack's `migrate` already is); never assume one schema.
- Code never imports `etqan.tenants`: the academy is read from `django.db.connection.tenant` (as `etqan.platform.features` does). A task queued from an academy carries `connection.schema_name` and runs inside `etqan.platform.tenancy.academy_context(schema_name)`.
- Any user-facing URL is built with `etqan.platform.frontend.frontend_url()` (none is new in this slice).

**Shared lists.** This work is not a phase: never add lines under a `── phase Bn ──` marker. Every shared list gets its lines in one block whose comment reads `Integrations (spec 2026-10-07; not a phase)`, placed directly above that list's `Parallel phases` comment (the first marker's lead-in), or at the end of a list that has no markers (`SHARED_APPS`, the route test table `ROUTES`). That covers `config/settings/base.py`, `config/api_router.py`, `etqan/access/registry.py`, `pyproject.toml` (two places), `src/features/shell/nav.ts`. `etqan/platform/tests/test_phase_sections.py` keeps passing because no marker moves. Test tables take additive edits only.

**Money and time.** No money moves in this slice. Money anywhere is integer minor units plus a currency. Stored instants are UTC (`last_test_at` comes from `etqan.integrations.clock.now()`, timezone-aware UTC).

**Secrets.** Every secret is stored only through `etqan.platform.secrets.encrypt` / `decrypt` (Fernet; a missing key fails closed with a 503 `gateways.no_key`). A secret is never serialised: not by the API, not on the admin change page, not in `repr`. The screens show `secret_last4` only.

**API.** All routes under `/api/v1/`. Domain errors are `etqan.platform.exceptions` (400 `ValidationError` with `field` or `code`, 404 `NotFoundError`, 503 `UnavailableError`).

**Language.** en and ar only (ledger D11), real Arabic (brand names such as Stripe, PayPal, Zoom, SMTP stay Latin). No Spanish file (ledger D22).

**Backend commands.** Run from the meta worktree, inside this worktree's own stack. If `.env.stream` is missing, write it for a slot no running stream uses (slot 4 is free in merge-only mode per STATE.md; check `docker ps --format '{{.Names}}' | grep etqan-`): `bash scripts/orchestration/stream-env.sh integrations 4 .`, then `just dev-backend`. Load it in every shell:
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/integrations
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Targeted tests: `$DJ pytest etqan/integrations -q` (add `--create-db` once after a task adds a migration).
- Migrations: `$DJ python manage.py makemigrations <app_label>`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- Whole suite: `just test-backend`.

**Dashboard commands.** From the meta worktree (with `.env.stream` loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
export HOST_UID=$(id -u) HOST_GID=$(id -g)
```
- One test file: `$DASH pnpm vitest run src/features/integrations/<file>`.
- Full tests with coverage: `$DASH pnpm test:coverage`.
- Types: `just test-frontend` (`tsc --noEmit`). Lint: `just lint-frontend` (biome + `check-colors.mjs`: semantic tokens only, no hex, no Tailwind palette utilities).
- A new route file regenerates `src/routeTree.gen.ts` with `$DASH pnpm exec vite build` before `tsc`; never hand-edit it.
- Format: `$DASH pnpm exec biome check --write src`.

**Coverage and gates.** Backend coverage ≥ 80 % (`just test-backend`). Dashboard lines and statements ≥ 80, branches and functions ≥ 70 (`pnpm test:coverage`). Before the PRs: `just test`, `just lint`, and the full `just e2e` (every e2e journey that reads Mailpit now sends through the resolver).

## Decisions (gaps the spec left, filled here)

| # | Decision |
|---|---|
| D1 | **Two Django apps in one package.** `etqan.integrations` (label `integrations`, SHARED_APPS) holds `PlatformAccount`; `etqan.integrations.accounts` (label `integrations_accounts`, TENANT_APPS) holds `AcademyAccount`. django-tenants routes migrations per app: one app in both lists would create both tables in every schema, and an academy's empty `integrations_platformaccount` would shadow the public one on the `search_path`. |
| D2 | **The "suspend Etqan defaults" flag lives on the tenant `Academy`**: `etqan_defaults_suspended = BooleanField(default=False, db_default=False)` in the public schema. The resolver reads it from `connection.tenant` like `Academy.features`: no query, no import of `etqan.tenants`; the platform admin already edits `Academy`, so slice 2 adds one field to its change form. Rejected: a public row keyed by academy (a query on every resolve and a new shared model before slice 2 needs one). Slice 1 adds the column and honours it; slice 2 adds the switch. |
| D3 | **An academy's own email account is SMTP only**: config `{host, port, username, security ∈ starttls|ssl|none, from_address}`, secret `{password}`. Postmark, Amazon SES and SendGrid all offer SMTP relays, so no provider SDK and no new dependency. A provider-API mode can be added later as another `security`/kind without a migration (config is JSON). |
| D4 | **Provider interface** `clean(fields, *, stored) -> (config, secrets)`, `last4(secrets) -> str`, `probe(*, config, secrets, tester_email) -> None` raising `ProbeError`. WhatsApp, payments, video and AI are `NotYet` providers: their own account cannot be connected (400 `integrations.not_available`), Etqan cannot switch their default on in the admin, and their probe says which phase brings them. |
| D5 | `secret_last4` is a stored, non-secret column (no decrypt on every read). It is filled only for a secret of 12 characters or more; a shorter one shows no characters ("Connected"). |
| D6 | **Etqan's email default ships on**, with an empty config meaning today's sending (`settings.EMAIL_*`, `DEFAULT_FROM_EMAIL`); a data migration creates the five `PlatformAccount` rows (email enabled, the others off). Etqan may give the email default its own SMTP server and from address in the admin; the same email rules then apply. |
| D7 | **Feature switches gating Etqan's default (spec §3.2):** email none (no switch exists); payments `online_payments`; video `zoom_api` (the registry's Zoom switch); AI `ai_assistant` or `ai_reports` (either on is enough); WhatsApp none until B5c registers its switch and adds it to `SWITCHES`. The switch never gates the academy's own account. |
| D8 | **Per-request cache:** answers are kept in a dict set on `connection.tenant` (attribute `_etqan_integrations`). django-tenants loads the academy afresh for every request and `academy_context` for every task, so that is one request or one task (the pattern of `platform.permissions.codes_of`). `connect`, `disconnect` clear it. The root `conftest.py` clears the session-shared test academies before and after every test. |
| D9 | The spec's `integrations.services.test(service, scope)` is named **`probe(service, *, scope, tester_email)`**: a function named `test` imported into a test module would be collected by pytest. `scope` is `"academy"` or `"etqan"`; the tester is the signed-in user's email. A failed probe is an answer (row `last_test_ok=False`, 200), not an error. |
| D10 | **The public schema has no `AcademyAccount` table:** the resolver skips step 1 there. Etqan staff mail (public schema) resolves to Etqan's default. |
| D11 | **One email path.** `etqan.platform.tasks.send_email_message` is deleted. `integrations.services.queue_email(...)` queues the Celery task `integrations.send_email` with the caller's schema (identity); `integrations.services.send_email_now(...)` sends in-process (notifications' own task). The task retries only `OSError` (SMTP); `NotSetUpError` is logged and returns `"not_set_up"` without retry; notifications records it on the row as `failed` with the reason. |
| D12 | **Reply-to:** `site.emails.brand_email` returns `reply_to` = `[Branding.contact_email]` (or `[]`; `[]` in the public schema). It is used only for Etqan's default (spec §4); an own account's mail has no reply-to (its From is already the academy's). The From keeps the academy's display name and takes the account's `from_address` when it has one. |
| D13 | **Metering seam:** `integrations.services.email.meter_email(resolved, *, accepted)` is called once after every accepted send and records nothing in slice 1. Slice 2 fills it with `etqan_billing.record_usage(...)` for `resolved.source == "etqan"` only. |
| D14 | **Payments in slice 1:** the card reports Etqan's (unbuilt) Stripe Connect default and links to B3's Payment gateways screen, where the academy's own Stripe/PayPal keys stay (`GatewayAccount`). `resolve("payments")` is not called by `etqan.gateways` until the B3 follow-up. |
| D15 | **API shape:** `GET integrations/` → `{"services": [card…]}` in spec order; `PUT integrations/<service>/` connects or edits (a blank or missing `password` keeps the stored one), `DELETE` disconnects (idempotent), `POST …/test/` probes; each write answers the fresh card. A card is `{service, using: academy|etqan|none, default_status: available|disabled|feature_off|suspended, connectable, own: null | {enabled, config, secret_last4, last_test_at, last_test_ok, last_test_error, updated_at}}`. Codes `integration.view` (GET) and `integration.update` (writes); admins always pass; no feature switch; not `NotImpersonating` (no money moves, ledger D19). |
| D16 | The card's "default's price" (spec §6) arrives with prices in slice 2. |
| D17 | A change of server or secret (academy or Etqan row) clears the last test (`last_test_at/ok/error`), which no longer describes the account. A save that changes neither keeps it. |

## Review Focus

1. **A secret reaching a response.** The password, or its Fernet token, in the API card, the list, the admin change page or `repr(Resolved)`. Tests: `test_the_token_never_shows_in_the_resolved_repr` (Task 3), `test_connecting_email_returns_the_card_without_the_password` (Task 5), `test_etqan_gives_email_its_own_server_and_the_password_never_comes_back` (Task 6), `"shows the own account's last four and last test, never the password"` (Task 8).
2. **A stale or foreign cached answer.** The per-request cache serving the answer from before a connect/disconnect, or one academy's answer to another. Tests: `test_the_answer_is_kept_for_the_request`, `test_connecting_and_disconnecting_refresh_the_answer`, `test_each_academy_answers_for_itself` (Task 3).
3. **The public schema.** Etqan staff mail resolving in `public`, where no `AcademyAccount` table exists. Tests: `test_the_public_schema_never_reads_an_academy_table` (Task 3), `test_etqan_staff_mail_in_the_public_schema_goes_out_on_the_default` (Task 4).
4. **A queued email resolving in the wrong academy.** Identity queues from a request; the worker must resolve in the academy that queued it, not the worker's schema. Tests: `test_a_queued_email_resolves_in_the_academy_that_queued_it`, `test_a_password_reset_goes_out_from_the_academys_own_account` (Task 4).
5. **Editing without retyping the password.** A blank password must keep the stored one, and a new server must clear the old "tested OK". Tests: `test_a_blank_password_keeps_the_stored_one` (Task 2), `test_an_edit_without_the_password_keeps_it_and_a_new_server_resets_the_test` (Task 3), `test_a_blank_password_keeps_the_stored_one` (Task 5), `"keeps a blank password out of an edit"` (Task 8).

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/integrations/__init__.py`, `apps.py` | the shared app |
| `etqan/integrations/models.py` | `Service`, `AccountFields` (abstract), `PlatformAccount` |
| `etqan/integrations/migrations/0001_initial.py` (generated), `0002_default_accounts.py` | table, the five rows |
| `etqan/integrations/accounts/{__init__,apps,models}.py`, `accounts/migrations/0001_initial.py` (generated) | the tenant app, `AcademyAccount` |
| `etqan/integrations/clock.py` | `now()` |
| `etqan/integrations/providers/{__init__,base,email}.py` | `PROVIDERS`, `get`, `Provider`, `NotYet`, `ProbeError`, `EmailProvider`, `mail_connection` |
| `etqan/integrations/services/{__init__,resolver,accounts,email}.py` | resolver, accounts, email |
| `etqan/integrations/tasks.py` | `send_email` |
| `etqan/integrations/api/{__init__,payloads,views,urls}.py` | the API |
| `etqan/integrations/admin.py` | the platform admin |
| `etqan/integrations/tests/{__init__,conftest,fakes}.py`, `test_models.py`, `test_providers.py`, `test_resolver.py`, `test_accounts.py`, `test_email.py`, `test_api.py`, `test_admin.py` | tests |
| `etqan/tenants/models.py`, `etqan/tenants/migrations/0005_*.py` (generated) | `etqan_defaults_suspended` |
| `config/settings/base.py`, `config/api_router.py`, `pyproject.toml` | wiring, contracts |
| `conftest.py` | clear the resolver cache on the shared academies |
| `etqan/site/emails.py`, `etqan/site/tests/test_emails.py` | `reply_to` |
| `etqan/identity/adapter.py`, `etqan/identity/services.py`, `etqan/identity/tests/test_async_email.py` | identity mail through integrations |
| `etqan/notifications/channels/email.py`, `etqan/notifications/tests/test_email.py` | notification mail through integrations |
| `etqan/platform/tasks.py` | deleted |
| `etqan/access/registry.py`, `etqan/access/tests/test_registry.py`, `etqan/access/tests/test_routes.py` | resource and route table |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/integrations/schemas.ts` | types, `emailFormSchema`, `emailDefaults`, `emailBody` |
| `src/features/integrations/api.ts`, `queries.ts`, `errors.ts`, `index.ts` | data layer |
| `src/features/integrations/IntegrationsPage.tsx`, `EmailAccountForm.tsx` | the page |
| `src/routes/_authed/settings.integrations.tsx` | the route |
| `src/features/shell/nav.ts`, `nav.test.ts`, `src/routes/permissions.test.ts` | wiring |
| `src/locales/{en,ar}/integrations.json` | strings |
| `src/test/integrations-fixtures.ts` | fixtures |

**Meta:** `CLAUDE.md`, `STATE.md`.

---

### Task 1: The two apps, the models, the suspend flag and the boundaries

**Files:**
- Create: `backend/etqan/integrations/__init__.py`, `backend/etqan/integrations/apps.py`, `backend/etqan/integrations/models.py`, `backend/etqan/integrations/migrations/__init__.py`, `backend/etqan/integrations/migrations/0001_initial.py` (generated), `backend/etqan/integrations/migrations/0002_default_accounts.py`, `backend/etqan/integrations/accounts/__init__.py`, `backend/etqan/integrations/accounts/apps.py`, `backend/etqan/integrations/accounts/models.py`, `backend/etqan/integrations/accounts/migrations/__init__.py`, `backend/etqan/integrations/accounts/migrations/0001_initial.py` (generated), `backend/etqan/integrations/tests/__init__.py`, `backend/etqan/integrations/tests/test_models.py`, `backend/etqan/tenants/migrations/0005_academy_etqan_defaults_suspended.py` (generated; commit the name `makemigrations` writes)
- Modify: `backend/etqan/tenants/models.py`, `backend/config/settings/base.py`, `backend/pyproject.toml`

**Interfaces:**
- Consumes: `django_tenants` app routing (SHARED_APPS / TENANT_APPS).
- Produces: `etqan.integrations.models.Service` (TextChoices, values `("whatsapp", "email", "payments", "video", "ai")`), `AccountFields` (abstract: `enabled: bool`, `config: dict`, `secret_enc: str`, `secret_last4: str`, `last_test_at: datetime | None`, `last_test_ok: bool | None`, `last_test_error: str`), `PlatformAccount(AccountFields)` (`service` unique, `updated_at`); `etqan.integrations.accounts.models.AcademyAccount(AccountFields)` (`service` unique, `updated_by` FK user, `updated_at`); `Academy.etqan_defaults_suspended: bool`.

- [ ] **Step 1: Write the failing test**

Create `backend/etqan/integrations/__init__.py` with one line:

```python
"""Outside-service accounts and their resolution (spec 2026-10-07)."""
```

Create `backend/etqan/integrations/tests/__init__.py` empty, and `backend/etqan/integrations/tests/test_models.py`:

```python
"""Spec §3.1: Etqan's default accounts live once, in the public schema;
each academy's own accounts live in its schema; the suspend flag (plan D2)
is on the academy."""

import pytest
from django.db import IntegrityError
from django.db import connection
from django.db import transaction

from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.models import Service

pytestmark = pytest.mark.django_db


def _schemas_of(table: str) -> set[str]:
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT table_schema FROM information_schema.tables WHERE table_name = %s",
            [table],
        )
        return {row[0] for row in cursor.fetchall()}


def test_the_services_are_the_five_of_the_spec_in_order():
    assert Service.values == ["whatsapp", "email", "payments", "video", "ai"]


def test_etqan_has_one_default_per_service_and_only_email_starts_on():
    enabled = dict(PlatformAccount.objects.values_list("service", "enabled"))
    assert enabled == {
        "whatsapp": False,
        "email": True,
        "payments": False,
        "video": False,
        "ai": False,
    }
    email = PlatformAccount.objects.get(service="email")
    assert (email.config, email.secret_enc, email.last_test_ok) == ({}, "", None)


def test_the_defaults_are_in_public_and_the_own_accounts_in_each_academy(tenants):
    assert _schemas_of("integrations_platformaccount") == {"public"}
    academy = _schemas_of("integrations_accounts_academyaccount")
    assert {tenants.main.schema_name, tenants.other.schema_name} <= academy
    assert "public" not in academy


def test_an_academy_has_one_account_per_service():
    AcademyAccount.objects.create(service="email")
    with pytest.raises(IntegrityError), transaction.atomic():
        AcademyAccount.objects.create(service="email")


def test_the_suspend_flag_is_off_with_a_database_default(tenants):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT is_nullable, column_default FROM information_schema.columns"
            " WHERE table_schema = 'public' AND table_name = 'tenants_academy'"
            " AND column_name = 'etqan_defaults_suspended'"
        )
        assert cursor.fetchone() == ("NO", "false")
    assert tenants.main.etqan_defaults_suspended is False


def test_the_rows_name_themselves():
    email = PlatformAccount.objects.get(service="email")
    assert str(email) == "PlatformAccount<email, True>"
    assert str(AcademyAccount(service="email", enabled=True)) == (
        "AcademyAccount<email, True>"
    )
```

- [ ] **Step 2: Run it to see it fail**

Run: `$DJ pytest etqan/integrations/tests/test_models.py -q`
Expected: collection error `ModuleNotFoundError: No module named 'etqan.integrations.accounts'`.

- [ ] **Step 3: Implement**

`backend/etqan/integrations/apps.py`:

```python
from django.apps import AppConfig


class IntegrationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.integrations"
    label = "integrations"
    verbose_name = "Integrations"
```

`backend/etqan/integrations/models.py`:

```python
"""Accounts for the outside services (spec 2026-10-07 §3.1).

Etqan's default account per service lives here, in the public schema
(SHARED_APPS); each academy's own account lives in its schema, in
`etqan.integrations.accounts` (plan D1). Secrets are Fernet tokens of a
JSON object (`etqan.platform.secrets`), never the values. Business rules
live in `etqan.integrations.services`."""

from django.db import models


class Service(models.TextChoices):
    WHATSAPP = "whatsapp", "WhatsApp"
    EMAIL = "email", "Email"
    PAYMENTS = "payments", "Online payments"
    VIDEO = "video", "Video meetings"
    AI = "ai", "AI"


class AccountFields(models.Model):
    """What an Etqan default and an academy's own account share."""

    enabled = models.BooleanField(default=False)
    # Non-secret settings: a server, a from address, a phone number id.
    config = models.JSONField(default=dict, blank=True)
    # A Fernet token of a JSON object of secrets; "" when there are none.
    secret_enc = models.TextField(blank=True, default="")
    # Plan D5: the main secret's last four characters, for the screens;
    # blank when that secret is shorter than 12 characters.
    secret_last4 = models.CharField(max_length=4, blank=True, default="")
    last_test_at = models.DateTimeField(null=True, blank=True)
    last_test_ok = models.BooleanField(null=True, blank=True)
    last_test_error = models.CharField(max_length=500, blank=True, default="")

    class Meta:
        abstract = True


class PlatformAccount(AccountFields):
    """Etqan's default account for one service. Edited only by Etqan staff
    in the platform admin."""

    service = models.CharField(max_length=16, choices=Service.choices, unique=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["service"]

    def __str__(self):
        return f"PlatformAccount<{self.service}, {self.enabled}>"
```

`backend/etqan/integrations/accounts/__init__.py`:

```python
"""Each academy's own accounts (TENANT_APPS; plan D1)."""
```

`backend/etqan/integrations/accounts/apps.py`:

```python
from django.apps import AppConfig


class AcademyAccountsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.integrations.accounts"
    label = "integrations_accounts"
    verbose_name = "Integrations: academy accounts"
```

`backend/etqan/integrations/accounts/models.py`:

```python
"""An academy's own account per service (spec §3.1), in the academy's
schema. For `payments` the row will hold only the Stripe Connect account
id (the B3 follow-up); the academy's own Stripe and PayPal keys stay in
`etqan.gateways`."""

from django.conf import settings
from django.db import models

from etqan.integrations.models import AccountFields
from etqan.integrations.models import Service


class AcademyAccount(AccountFields):
    service = models.CharField(max_length=16, choices=Service.choices, unique=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"AcademyAccount<{self.service}, {self.enabled}>"
```

Create empty `backend/etqan/integrations/migrations/__init__.py` and `backend/etqan/integrations/accounts/migrations/__init__.py`.

In `backend/etqan/tenants/models.py`, after the `features = models.JSONField(...)` line, add:

```python
    # Integrations (spec 2026-10-07 §5, plan D2): Etqan may stop this
    # academy's use of Etqan's default accounts; its own accounts keep
    # working. Read by etqan.integrations from the academy on the
    # connection, so asking costs no query. Switched in the platform admin
    # from slice 2. A database default too, as `features`, for the old colour.
    etqan_defaults_suspended = models.BooleanField(default=False, db_default=False)
```

In `backend/config/settings/base.py`, end `SHARED_APPS` with:

```python
    "etqan.identity",
    # Integrations (spec 2026-10-07; not a phase): Etqan's default accounts.
    "etqan.integrations",
]
```

and in `TENANT_APPS` replace

```python
    "etqan.access",
    # Parallel phases (spec 2026-10-02 §6.1): add a phase's apps under its own marker.
```

with

```python
    "etqan.access",
    # Integrations (spec 2026-10-07; not a phase): each academy's own accounts.
    "etqan.integrations.accounts",
    # Parallel phases (spec 2026-10-02 §6.1): add a phase's apps under its own marker.
```

Generate the schema migrations:

Run: `$DJ python manage.py makemigrations integrations integrations_accounts tenants`
Expected: `etqan/integrations/migrations/0001_initial.py`, `etqan/integrations/accounts/migrations/0001_initial.py`, `etqan/tenants/migrations/0005_academy_etqan_defaults_suspended.py`.

Write the data migration `backend/etqan/integrations/migrations/0002_default_accounts.py` by hand (plan D6):

```python
"""Plan D6: Etqan's five default accounts. Email is on with no config,
which is today's sending (settings.EMAIL_*); the others stay off until
their providers are built."""

from django.db import migrations

SERVICES = ("whatsapp", "email", "payments", "video", "ai")


def create_defaults(apps, schema_editor):
    account = apps.get_model("integrations", "PlatformAccount")
    for service in SERVICES:
        account.objects.get_or_create(
            service=service, defaults={"enabled": service == "email"}
        )


class Migration(migrations.Migration):
    dependencies = [("integrations", "0001_initial")]

    operations = [migrations.RunPython(create_defaults, migrations.RunPython.noop)]
```

In `backend/pyproject.toml`, in the contract `platform imports no business modules`, replace

```toml
    "etqan.access",
    # Parallel phases (spec 2026-10-02 §6.1): every new app is forbidden to platform, under its phase's marker.
```

with

```toml
    "etqan.access",
    # Integrations (spec 2026-10-07; not a phase).
    "etqan.integrations",
    # Parallel phases (spec 2026-10-02 §6.1): every new app is forbidden to platform, under its phase's marker.
```

and replace

```toml
# Parallel phases (spec 2026-10-02 §6.1): a phase's new contracts go under its marker.
# ── phase B2 ──
```

with

```toml
# Integrations (spec 2026-10-07; not a phase).
[[tool.importlinter.contracts]]
name = "integrations imports only the platform"
type = "forbidden"
# IN-7: every service asks integrations; integrations asks nobody but the
# platform. The academy is read from the connection, never from tenants.
source_modules = ["etqan.integrations"]
forbidden_modules = [
    "etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue",
    "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.finance", "etqan.gateways", "etqan.learning", "etqan.employment", "etqan.library",
    "etqan.registration", "etqan.systemstatus", "etqan.translations",
]
ignore_imports = ["etqan.integrations.tests.** -> etqan.**"]

[[tool.importlinter.contracts]]
name = "other apps reach integrations only through its services"
type = "forbidden"
source_modules = [
    "etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants",
    "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.finance", "etqan.gateways", "etqan.learning", "etqan.employment", "etqan.library",
    "etqan.registration", "etqan.systemstatus", "etqan.translations",
]
forbidden_modules = [
    "etqan.integrations.models", "etqan.integrations.accounts", "etqan.integrations.api",
    "etqan.integrations.providers", "etqan.integrations.tasks", "etqan.integrations.clock",
    "etqan.integrations.admin",
]
allow_indirect_imports = true

# Parallel phases (spec 2026-10-02 §6.1): a phase's new contracts go under its marker.
# ── phase B2 ──
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DJ pytest etqan/integrations/tests/test_models.py etqan/tenants etqan/platform/tests/test_phase_sections.py -q --create-db && $DJ lint-imports`
Expected: all pass; `lint-imports` reports every contract kept.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/integrations etqan/tenants/models.py etqan/tenants/migrations config/settings/base.py pyproject.toml
git -C backend commit -m "feat(integrations): platform and academy account models, suspend flag" -m "$TRAILER"
```

---

### Task 2: The provider interface, email over SMTP and the not-yet providers

**Files:**
- Create: `backend/etqan/integrations/providers/__init__.py`, `backend/etqan/integrations/providers/base.py`, `backend/etqan/integrations/providers/email.py`, `backend/etqan/integrations/tests/fakes.py`, `backend/etqan/integrations/tests/test_providers.py`

**Interfaces:**
- Consumes: `etqan.platform.exceptions.ValidationError(message, field=None, code=...)`, `NotFoundError(resource, identifier)`; Django `get_connection`, `EmailMessage`, `validate_email`; `settings.EMAIL_TIMEOUT`, `settings.DEFAULT_FROM_EMAIL`.
- Produces: `providers.PROVIDERS: dict[str, Provider]` (keys in `Service` order), `providers.get(service: str) -> Provider` (raises `NotFoundError`), `providers.Provider` (Protocol: `service: str`, `connectable: bool`, `clean(fields: dict, *, stored: dict) -> tuple[dict, dict]`, `last4(values: dict) -> str`, `probe(*, config: dict, secrets: dict, tester_email: str) -> None`), `providers.ProbeError(message)` (`.message: str`), `providers.NotYet(service, until)`, `providers.NOT_AVAILABLE = "integrations.not_available"`, `providers.EmailProvider`, `providers.mail_connection(config: dict, values: dict) -> BaseEmailBackend`; module constant `etqan.integrations.providers.email.SMTP_BACKEND` (read at call time).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/integrations/tests/fakes.py`:

```python
"""Mail backends that stand in for an SMTP server in the tests: point
`etqan.integrations.providers.email.SMTP_BACKEND` at one of them."""

import smtplib
from typing import ClassVar

from django.core.mail.backends.base import BaseEmailBackend
from django.core.mail.backends.locmem import EmailBackend as LocmemBackend


class Recording(LocmemBackend):
    """Delivers to `mail.outbox` and remembers what it was opened with."""

    opened: ClassVar[list[dict]] = []

    def __init__(self, **kwargs):
        Recording.opened.append(dict(kwargs))
        super().__init__(**kwargs)


class RefusingBackend(BaseEmailBackend):
    def send_messages(self, email_messages):
        raise smtplib.SMTPAuthenticationError(535, b"5.7.8 Authentication failed")


class SenderRefusedBackend(BaseEmailBackend):
    def send_messages(self, email_messages):
        raise smtplib.SMTPSenderRefused(553, b"Sender rejected", "office@noor.test")


class UnreachableBackend(BaseEmailBackend):
    def send_messages(self, email_messages):
        raise ConnectionRefusedError(111, "Connection refused")
```

`backend/etqan/integrations/tests/test_providers.py`:

```python
"""Spec §3.3, plan D3/D4: each service's provider. Email is real (SMTP);
the other four say when they come."""

import pytest
from django.core import mail
from django.test import override_settings

from etqan.integrations import providers
from etqan.integrations.providers import email as email_provider
from etqan.integrations.tests.fakes import Recording
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

FIELDS = {
    "host": " smtp.noor.test ",
    "port": 587,
    "username": "mailer@noor.test",
    "password": "app-password-1234",
    "security": "starttls",
    "from_address": "office@noor.test",
}
CONFIG = {
    "host": "smtp.noor.test",
    "port": 587,
    "username": "mailer@noor.test",
    "security": "starttls",
    "from_address": "office@noor.test",
}
FAKES = "etqan.integrations.tests.fakes"
EMAIL = providers.get("email")


def test_every_service_has_a_provider_and_only_email_connects():
    assert list(providers.PROVIDERS) == ["whatsapp", "email", "payments", "video", "ai"]
    assert [p.connectable for p in providers.PROVIDERS.values()] == [
        False,
        True,
        False,
        False,
        False,
    ]


def test_an_unknown_service_is_not_found():
    with pytest.raises(NotFoundError):
        providers.get("sms")


def test_email_fields_are_cleaned_into_config_and_secrets():
    config, values = EMAIL.clean(dict(FIELDS), stored={})
    assert config == CONFIG
    assert values == {"password": "app-password-1234"}


def test_a_blank_password_keeps_the_stored_one():
    _, values = EMAIL.clean(
        {**FIELDS, "password": ""}, stored={"password": "kept-password-99"}
    )
    assert values == {"password": "kept-password-99"}


def test_no_user_name_needs_no_password():
    config, values = EMAIL.clean({**FIELDS, "username": "", "password": ""}, stored={})
    assert (config["username"], values) == ("", {})


@pytest.mark.parametrize(
    ("change", "field"),
    [
        ({"host": ""}, "host"),
        ({"host": "x" * 254}, "host"),
        ({"port": 0}, "port"),
        ({"port": 65536}, "port"),
        ({"port": "587"}, "port"),
        ({"port": True}, "port"),
        ({"security": "tls13"}, "security"),
        ({"from_address": "not-an-address"}, "from_address"),
        ({"from_address": None}, "from_address"),
        ({"password": ""}, "password"),
        ({"password": 1234}, "password"),
        ({"password": "x" * 513}, "password"),
        ({"username": 5}, "username"),
    ],
)
def test_email_refuses_a_bad_field_on_that_field(change, field):
    with pytest.raises(ValidationError) as caught:
        EMAIL.clean({**FIELDS, **change}, stored={})
    assert caught.value.field == field


def test_the_last_four_show_only_for_a_long_secret():
    assert EMAIL.last4({"password": "app-password-1234"}) == "1234"
    assert EMAIL.last4({"password": "short-pw"}) == ""
    assert EMAIL.last4({}) == ""


def test_the_connection_follows_the_security_choice():
    ssl = email_provider.mail_connection(
        {**CONFIG, "security": "ssl", "port": 465}, {"password": "p"}
    )
    assert (ssl.use_ssl, ssl.use_tls, ssl.port, ssl.timeout) == (True, False, 465, 5)
    plain = email_provider.mail_connection(
        {**CONFIG, "security": "none", "username": ""}, {}
    )
    # Never Etqan's own EMAIL_HOST_USER for a blank user name.
    assert (plain.use_ssl, plain.use_tls, plain.username, plain.password) == (
        False,
        False,
        "",
        "",
    )


def test_the_probe_sends_a_test_email_through_the_server(monkeypatch):
    Recording.opened.clear()
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", f"{FAKES}.Recording")
    EMAIL.probe(
        config=CONFIG,
        secrets={"password": "app-password-1234"},
        tester_email="admin@noor.test",
    )
    (message,) = mail.outbox
    assert (message.from_email, message.to) == ("office@noor.test", ["admin@noor.test"])
    assert Recording.opened[0]["host"] == "smtp.noor.test"
    assert Recording.opened[0]["password"] == "app-password-1234"


@override_settings(DEFAULT_FROM_EMAIL="etqan <noreply@etqan.test>")
def test_etqans_default_without_a_server_probes_todays_sending():
    EMAIL.probe(config={}, secrets={}, tester_email="ops@etqan.test")
    (message,) = mail.outbox
    assert (message.from_email, message.to) == (
        "etqan <noreply@etqan.test>",
        ["ops@etqan.test"],
    )


@pytest.mark.parametrize(
    ("backend", "reason"),
    [
        ("RefusingBackend", "The server refused the user name or password."),
        (
            "SenderRefusedBackend",
            "The server refused the from address or the recipient.",
        ),
        (
            "UnreachableBackend",
            "Could not send through this server (ConnectionRefusedError).",
        ),
    ],
)
def test_a_failed_probe_says_why_in_our_words(monkeypatch, backend, reason):
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", f"{FAKES}.{backend}")
    with pytest.raises(providers.ProbeError) as caught:
        EMAIL.probe(config=CONFIG, secrets={"password": "x"}, tester_email="a@noor.test")
    assert caught.value.message == reason


def test_the_other_services_say_when_they_come():
    whatsapp = providers.get("whatsapp")
    with pytest.raises(ValidationError) as caught:
        whatsapp.clean({"token": "x"}, stored={})
    assert caught.value.code == "integrations.not_available"
    with pytest.raises(providers.ProbeError) as probed:
        whatsapp.probe(config={}, secrets={}, tester_email="a@b.test")
    assert probed.value.message == (
        "Not available until WhatsApp messaging (phase B5c) ships."
    )
    assert whatsapp.last4({"token": "abcdefghijklmnop"}) == ""
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/integrations/tests/test_providers.py -q`
Expected: collection error `ModuleNotFoundError: No module named 'etqan.integrations.providers'`.

- [ ] **Step 3: Implement**

`backend/etqan/integrations/providers/base.py`:

```python
"""The provider interface (spec §3.3, plan D4): a service's rules for its
account fields and the probe Settings → Integrations' Test runs. Tests swap
a provider for a fake through `PROVIDERS`."""

from typing import Protocol

from etqan.platform.exceptions import ValidationError

NOT_AVAILABLE = "integrations.not_available"


class ProbeError(Exception):
    """The probe's verdict: the account does not work. ``message`` is our
    own wording, safe to show and to store."""

    def __init__(self, message: str):
        self.message = message
        super().__init__(message)


class Provider(Protocol):
    service: str
    connectable: bool

    def clean(self, fields: dict, *, stored: dict) -> tuple[dict, dict]:
        """``fields`` as sent and ``stored`` the secrets kept now; returns the
        non-secret config and the secrets to store, or raises ValidationError
        on the field at fault."""

    def last4(self, values: dict) -> str:
        """The main secret's last four characters, or "" (plan D5)."""

    def probe(self, *, config: dict, secrets: dict, tester_email: str) -> None:
        """Raises ProbeError when the account does not work."""


class NotYet:
    """A service whose provider comes with a later phase: its own account
    cannot be connected yet, Etqan cannot switch its default on, and its
    probe says when it comes."""

    connectable = False

    def __init__(self, service: str, until: str):
        self.service = service
        self.until = until

    def clean(self, fields: dict, *, stored: dict) -> tuple[dict, dict]:
        raise ValidationError(
            f"Connecting your own account is not available until {self.until} ships.",
            code=NOT_AVAILABLE,
        )

    def last4(self, values: dict) -> str:
        return ""

    def probe(self, *, config: dict, secrets: dict, tester_email: str) -> None:
        raise ProbeError(f"Not available until {self.until} ships.")
```

`backend/etqan/integrations/providers/email.py`:

```python
"""Email (spec §4, plan D3): an academy's own account is an SMTP server and
its from address; Etqan's default without a server is today's sending
(`settings.EMAIL_*`). Postmark, Amazon SES and SendGrid all offer SMTP
relays, so no provider SDK is needed."""

import smtplib

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.mail import EmailMessage
from django.core.mail import get_connection
from django.core.validators import validate_email

from etqan.integrations.providers.base import ProbeError
from etqan.platform.exceptions import ValidationError

# Read at call time, so the tests stand a fake server in for it.
SMTP_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
SECURITY = ("starttls", "ssl", "none")
MAX_PORT = 65535
MAX_PASSWORD = 512
LAST4_FROM = 12  # plan D5: a shorter secret shows no characters at all
TEST_SUBJECT = "Etqan: your email account works"
TEST_BODY = (
    "This test was sent from Settings → Integrations to check the email "
    "account. Nothing else to do."
)


def _text(fields: dict, name: str, limit: int, *, required: bool = False) -> str:
    value = fields.get(name, "")
    if not isinstance(value, str):
        raise ValidationError("Enter text.", field=name)
    value = value.strip()
    if required and not value:
        raise ValidationError("This field is required.", field=name)
    if len(value) > limit:
        raise ValidationError(f"Use at most {limit} characters.", field=name)
    return value


def _port(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError("Enter a port from 1 to 65535.", field="port")
    if not 1 <= value <= MAX_PORT:
        raise ValidationError("Enter a port from 1 to 65535.", field="port")
    return value


def _security(value: object) -> str:
    if value not in SECURITY:
        raise ValidationError("Choose STARTTLS, SSL/TLS or none.", field="security")
    return str(value)


def _address(fields: dict) -> str:
    address = _text(fields, "from_address", 254, required=True)
    try:
        validate_email(address)
    except DjangoValidationError:
        raise ValidationError(
            "Enter a valid email address.", field="from_address"
        ) from None
    return address


def _password(fields: dict, stored: dict) -> str:
    value = fields.get("password", "")
    if not isinstance(value, str) or len(value) > MAX_PASSWORD:
        raise ValidationError(
            "Enter the password as text, at most 512 characters.", field="password"
        )
    return value or stored.get("password", "")


def mail_connection(config: dict, values: dict):
    """The connection an account sends through. Without a host (Etqan's
    default as shipped) it is today's sending; otherwise the account's own
    server, with every setting passed explicitly so a blank user name never
    falls back to Etqan's EMAIL_HOST_USER."""
    if not config.get("host"):
        return get_connection(fail_silently=False)
    security = config.get("security", "starttls")
    return get_connection(
        SMTP_BACKEND,
        fail_silently=False,
        host=config["host"],
        port=config["port"],
        username=config.get("username", ""),
        password=values.get("password", ""),
        use_tls=security == "starttls",
        use_ssl=security == "ssl",
        timeout=settings.EMAIL_TIMEOUT,
    )


class EmailProvider:
    service = "email"
    connectable = True

    def clean(self, fields: dict, *, stored: dict) -> tuple[dict, dict]:
        config = {
            "host": _text(fields, "host", 253, required=True),
            "port": _port(fields.get("port")),
            "username": _text(fields, "username", 254),
            "security": _security(fields.get("security", "starttls")),
            "from_address": _address(fields),
        }
        password = _password(fields, stored)
        if config["username"] and not password:
            raise ValidationError("Enter the password.", field="password")
        return config, ({"password": password} if password else {})

    def last4(self, values: dict) -> str:
        password = values.get("password", "")
        return password[-4:] if len(password) >= LAST4_FROM else ""

    def probe(self, *, config: dict, secrets: dict, tester_email: str) -> None:
        message = EmailMessage(
            subject=TEST_SUBJECT,
            body=TEST_BODY,
            from_email=config.get("from_address") or settings.DEFAULT_FROM_EMAIL,
            to=[tester_email],
            connection=mail_connection(config, secrets),
        )
        try:
            message.send()
        except smtplib.SMTPAuthenticationError:
            raise ProbeError(
                "The server refused the user name or password."
            ) from None
        except (smtplib.SMTPSenderRefused, smtplib.SMTPRecipientsRefused):
            raise ProbeError(
                "The server refused the from address or the recipient."
            ) from None
        except OSError as exc:
            raise ProbeError(
                f"Could not send through this server ({type(exc).__name__})."
            ) from None
```

`backend/etqan/integrations/providers/__init__.py`:

```python
"""Each service's provider (spec §3.3, plan D4)."""

from etqan.integrations.providers.base import NOT_AVAILABLE
from etqan.integrations.providers.base import NotYet
from etqan.integrations.providers.base import ProbeError
from etqan.integrations.providers.base import Provider
from etqan.integrations.providers.email import EmailProvider
from etqan.integrations.providers.email import mail_connection
from etqan.platform.exceptions import NotFoundError

PROVIDERS: dict[str, Provider] = {
    "whatsapp": NotYet("whatsapp", "WhatsApp messaging (phase B5c)"),
    "email": EmailProvider(),
    "payments": NotYet("payments", "Stripe Connect (the B3 follow-up)"),
    "video": NotYet("video", "Zoom meetings (phase B2)"),
    "ai": NotYet("ai", "the AI features (phase B10)"),
}


def get(service: str) -> Provider:
    try:
        return PROVIDERS[service]
    except KeyError:
        raise NotFoundError("Integration", service) from None


__all__ = [
    "NOT_AVAILABLE",
    "PROVIDERS",
    "EmailProvider",
    "NotYet",
    "ProbeError",
    "Provider",
    "get",
    "mail_connection",
]
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DJ pytest etqan/integrations/tests/test_providers.py -q && $DJ lint-imports`
Expected: all pass; contracts kept.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/integrations
git -C backend commit -m "feat(integrations): provider interface, SMTP email provider, not-yet stubs" -m "$TRAILER"
```

---

### Task 3: The resolver and the account services

**Files:**
- Create: `backend/etqan/integrations/clock.py`, `backend/etqan/integrations/services/__init__.py`, `backend/etqan/integrations/services/resolver.py`, `backend/etqan/integrations/services/accounts.py`, `backend/etqan/integrations/tests/conftest.py`, `backend/etqan/integrations/tests/test_resolver.py`, `backend/etqan/integrations/tests/test_accounts.py`
- Modify: `backend/conftest.py`

**Interfaces:**
- Consumes: `providers.get`, `ProbeError`; `etqan.platform.features.enabled(code) -> bool`, `features.CODES`; `etqan.platform.secrets.encrypt/decrypt`; `connection.tenant.etqan_defaults_suspended` (Task 1).
- Produces (all from `etqan.integrations.services`): `ACADEMY = "academy"`, `ETQAN = "etqan"`, `SERVICES: tuple[str, ...]`, `SWITCHES: dict[str, tuple[str, ...]]`, `AVAILABLE/DISABLED/FEATURE_OFF/SUSPENDED`, `Resolved(service: str, source: str, config: dict, secret_enc: str)` with `.secrets() -> dict`, `resolve(service: str) -> Resolved | None`, `default_status(service: str) -> str`, `clear_cache(tenant=None) -> None`, `read_secrets(token: str) -> dict`, `write_secrets(values: dict) -> str`, `connectable(service: str) -> bool`, `own_account(service: str) -> AcademyAccount | None`, `connect(service: str, *, fields: object, by) -> AcademyAccount`, `disconnect(service: str) -> None`, `probe(service: str, *, scope: str, tester_email: str) -> AcademyAccount | PlatformAccount`, `apply_platform_change(account: PlatformAccount, *, enabled: bool, config: object, new_secrets: dict | None, clear_secrets: bool) -> dict`, `NOT_CONNECTED = "integrations.not_connected"`, `NO_TESTER_EMAIL = "integrations.no_tester_email"`; `etqan.integrations.clock.now() -> datetime`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/integrations/tests/conftest.py`:

```python
"""Integrations fixtures. The email provider keeps its real field rules,
its probe is faked (there is no SMTP server in tests); `own_email` connects
the academy's own account."""

import pytest
from django.db import connection

from etqan.integrations import providers
from etqan.integrations import services
from etqan.integrations.providers.email import EmailProvider

SMTP = {
    "host": "smtp.noor.test",
    "port": 587,
    "username": "mailer@noor.test",
    "password": "app-password-1234",
    "security": "starttls",
    "from_address": "office@noor.test",
}
SMTP_CONFIG = {key: value for key, value in SMTP.items() if key != "password"}
LOCMEM = "django.core.mail.backends.locmem.EmailBackend"


class FakeEmail(EmailProvider):
    """The real email rules; the probe is recorded, and fails when told."""

    def __init__(self):
        self.probed: list[dict] = []
        self.failure = ""

    def probe(self, *, config, secrets, tester_email):
        self.probed.append({"config": config, "secrets": secrets, "to": tester_email})
        if self.failure:
            raise providers.ProbeError(self.failure)


@pytest.fixture
def fake_email(monkeypatch):
    fake = FakeEmail()
    monkeypatch.setitem(providers.PROVIDERS, "email", fake)
    return fake


@pytest.fixture
def admin_user(api_for):
    return api_for("admin").user


@pytest.fixture
def own_email(fake_email, admin_user):
    return services.connect("email", fields=dict(SMTP), by=admin_user)


@pytest.fixture
def suspended():
    """Etqan's defaults suspended for the academy on the connection (plan
    D2): in the database, so a request sees it, and on the object, so a
    direct call does."""
    academy = connection.tenant
    type(academy).objects.filter(pk=academy.pk).update(etqan_defaults_suspended=True)
    academy.etqan_defaults_suspended = True
    services.clear_cache()
    yield academy
    academy.etqan_defaults_suspended = False
```

`backend/etqan/integrations/tests/test_resolver.py`:

```python
"""Spec §3.2: the academy's own account, else Etqan's default when it is
on, the feature switch allows it and the academy is not suspended, else
nothing; kept for the request (plan D8)."""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.integrations import services
from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.tests.conftest import SMTP
from etqan.integrations.tests.conftest import SMTP_CONFIG
from etqan.platform import features

pytestmark = pytest.mark.django_db


def switch_on(service: str) -> None:
    PlatformAccount.objects.filter(service=service).update(enabled=True)
    services.clear_cache()


def test_email_resolves_to_etqans_default_out_of_the_box():
    resolved = services.resolve("email")
    assert (resolved.service, resolved.source, resolved.config) == (
        "email",
        "etqan",
        {},
    )
    assert resolved.secrets() == {}
    assert services.default_status("email") == "available"


def test_the_academys_own_connected_account_wins(own_email):
    resolved = services.resolve("email")
    assert (resolved.source, resolved.config) == ("academy", SMTP_CONFIG)
    assert resolved.secrets() == {"password": "app-password-1234"}


def test_the_token_never_shows_in_the_resolved_repr(own_email):
    text = repr(services.resolve("email"))
    assert own_email.secret_enc not in text
    assert "app-password-1234" not in text


def test_an_own_account_switched_off_falls_back_to_the_default(own_email):
    AcademyAccount.objects.filter(service="email").update(enabled=False)
    services.clear_cache()
    assert services.resolve("email").source == "etqan"


def test_nothing_resolves_while_etqans_default_is_off():
    PlatformAccount.objects.filter(service="email").update(enabled=False)
    assert services.resolve("email") is None
    assert services.default_status("email") == "disabled"


def test_the_feature_switch_gates_etqans_default(set_features):
    switch_on("payments")
    set_features(invoices=True, online_payments=False)
    assert services.resolve("payments") is None
    assert services.default_status("payments") == "feature_off"
    set_features(invoices=True, online_payments=True)
    services.clear_cache()
    assert services.resolve("payments").source == "etqan"


def test_ai_needs_either_ai_switch(set_features):
    switch_on("ai")
    set_features(ai_assistant=False, ai_reports=False)
    assert services.resolve("ai") is None
    set_features(ai_reports=True)
    services.clear_cache()
    assert services.resolve("ai").source == "etqan"


def test_every_switch_named_is_a_registered_feature():
    named = {code for codes in services.SWITCHES.values() for code in codes}
    assert named <= features.CODES
    assert tuple(services.SWITCHES) == services.SERVICES


def test_a_suspended_academy_loses_etqans_defaults_but_keeps_its_own(
    suspended, fake_email, admin_user
):
    assert services.resolve("email") is None
    assert services.default_status("email") == "suspended"
    services.connect("email", fields=dict(SMTP), by=admin_user)
    assert services.resolve("email").source == "academy"


def test_the_answer_is_kept_for_the_request(django_assert_num_queries):
    first = services.resolve("email")
    with django_assert_num_queries(0):
        assert services.resolve("email") is first


def test_connecting_and_disconnecting_refresh_the_answer(fake_email, admin_user):
    assert services.resolve("email").source == "etqan"
    services.connect("email", fields=dict(SMTP), by=admin_user)
    assert services.resolve("email").source == "academy"
    services.disconnect("email")
    assert services.resolve("email").source == "etqan"


def test_each_academy_answers_for_itself(own_email, tenants):
    assert services.resolve("email").source == "academy"
    with tenant_context(tenants.other):
        assert services.resolve("email").source == "etqan"
    assert services.resolve("email").source == "academy"


def test_the_public_schema_never_reads_an_academy_table():
    connection.set_schema_to_public()
    with CaptureQueriesContext(connection) as queries:
        resolved = services.resolve("email")
    assert resolved.source == "etqan"
    assert not any("academyaccount" in q["sql"] for q in queries.captured_queries)


def test_an_unknown_service_is_a_programming_error():
    with pytest.raises(LookupError):
        services.resolve("sms")
```

`backend/etqan/integrations/tests/test_accounts.py`:

```python
"""Spec §3.1, §3.3, §6: connect, disconnect and test the academy's own
account; Etqan's defaults changed from the platform admin."""

from datetime import UTC
from datetime import datetime

import pytest

from etqan.integrations import clock
from etqan.integrations import services
from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.tests.conftest import SMTP
from etqan.integrations.tests.conftest import SMTP_CONFIG
from etqan.platform import secrets
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
NOW = datetime(2026, 10, 7, 8, 0, tzinfo=UTC)
ETQAN_SMTP = {
    "host": "smtp.etqan.test",
    "port": 587,
    "username": "noreply@etqan.test",
    "security": "starttls",
    "from_address": "noreply@etqan.test",
}


@pytest.fixture(autouse=True)
def _pinned(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: NOW)


def test_connecting_stores_the_password_only_as_a_token(own_email, admin_user):
    row = AcademyAccount.objects.get(service="email")
    assert row.config == SMTP_CONFIG
    assert "app-password-1234" not in row.secret_enc
    assert secrets.decrypt(row.secret_enc) == '{"password": "app-password-1234"}'
    assert (row.secret_last4, row.enabled, row.updated_by) == ("1234", True, admin_user)
    assert (row.last_test_at, row.last_test_ok) == (None, None)


def test_an_edit_without_the_password_keeps_it_and_a_new_server_resets_the_test(
    own_email, admin_user, fake_email
):
    services.probe("email", scope=services.ACADEMY, tester_email="admin@noor.test")
    services.connect("email", fields={**SMTP, "password": ""}, by=admin_user)
    row = AcademyAccount.objects.get(service="email")
    assert (row.last_test_ok, row.last_test_at) == (True, NOW)
    services.connect(
        "email",
        fields={**SMTP, "password": "", "host": "smtp2.noor.test"},
        by=admin_user,
    )
    row.refresh_from_db()
    assert services.read_secrets(row.secret_enc) == {"password": "app-password-1234"}
    assert (row.last_test_ok, row.last_test_at, row.last_test_error) == (None, None, "")


def test_switching_the_own_account_off_keeps_it(own_email, admin_user):
    services.connect("email", fields={**SMTP, "enabled": False}, by=admin_user)
    assert AcademyAccount.objects.get(service="email").enabled is False


def test_enabled_must_be_true_or_false(fake_email, admin_user):
    with pytest.raises(ValidationError) as caught:
        services.connect("email", fields={**SMTP, "enabled": "yes"}, by=admin_user)
    assert caught.value.field == "enabled"
    assert not AcademyAccount.objects.exists()


def test_the_fields_must_be_an_object(fake_email, admin_user):
    with pytest.raises(ValidationError):
        services.connect("email", fields=["host"], by=admin_user)


def test_a_service_not_built_yet_cannot_be_connected(admin_user):
    with pytest.raises(ValidationError) as caught:
        services.connect("whatsapp", fields={"token": "x"}, by=admin_user)
    assert caught.value.code == "integrations.not_available"
    assert not AcademyAccount.objects.exists()
    assert services.connectable("whatsapp") is False
    assert services.connectable("email") is True


def test_an_unknown_service_is_not_found(admin_user):
    with pytest.raises(NotFoundError):
        services.connect("sms", fields={}, by=admin_user)
    with pytest.raises(NotFoundError):
        services.disconnect("sms")
    with pytest.raises(NotFoundError):
        services.probe("sms", scope=services.ACADEMY, tester_email="a@b.test")


def test_disconnecting_twice_is_harmless(own_email):
    services.disconnect("email")
    services.disconnect("email")
    assert services.own_account("email") is None


def test_a_probe_records_success_then_failure_without_raising(own_email, fake_email):
    services.probe("email", scope=services.ACADEMY, tester_email="admin@noor.test")
    assert fake_email.probed == [
        {
            "config": SMTP_CONFIG,
            "secrets": {"password": "app-password-1234"},
            "to": "admin@noor.test",
        }
    ]
    fake_email.failure = "The server refused the user name or password."
    row = services.probe(
        "email", scope=services.ACADEMY, tester_email="admin@noor.test"
    )
    assert (row.last_test_ok, row.last_test_error, row.last_test_at) == (
        False,
        "The server refused the user name or password.",
        NOW,
    )


def test_a_long_failure_is_cut_to_its_column(own_email, fake_email):
    fake_email.failure = "x" * 600
    row = services.probe("email", scope=services.ACADEMY, tester_email="a@noor.test")
    assert len(row.last_test_error) == 500


def test_a_probe_needs_an_own_account(fake_email):
    with pytest.raises(ValidationError) as caught:
        services.probe("email", scope=services.ACADEMY, tester_email="a@noor.test")
    assert caught.value.code == "integrations.not_connected"


def test_a_probe_needs_the_testers_address(own_email):
    with pytest.raises(ValidationError) as caught:
        services.probe("email", scope=services.ACADEMY, tester_email="")
    assert caught.value.code == "integrations.no_tester_email"


def test_etqans_default_is_probed_and_recorded_on_its_row(fake_email):
    services.probe("email", scope=services.ETQAN, tester_email="ops@etqan.test")
    row = PlatformAccount.objects.get(service="email")
    assert (row.last_test_ok, row.last_test_at) == (True, NOW)
    assert fake_email.probed[0]["config"] == {}


def test_etqans_email_default_may_get_its_own_server():
    account = PlatformAccount.objects.get(service="email")
    config = services.apply_platform_change(
        account,
        enabled=True,
        config=dict(ETQAN_SMTP),
        new_secrets={"password": "etqan-smtp-secret-1999"},
        clear_secrets=False,
    )
    assert config == ETQAN_SMTP
    assert services.read_secrets(account.secret_enc) == {
        "password": "etqan-smtp-secret-1999"
    }
    assert (account.secret_last4, account.enabled) == ("1999", True)


def test_an_empty_config_is_todays_sending_and_clearing_drops_the_secrets():
    account = PlatformAccount.objects.get(service="email")
    account.secret_enc = secrets.encrypt('{"password": "old-password-0000"}')
    config = services.apply_platform_change(
        account, enabled=True, config={}, new_secrets=None, clear_secrets=True
    )
    assert (config, account.secret_enc, account.secret_last4) == ({}, "", "")


def test_etqans_email_default_follows_the_email_rules():
    account = PlatformAccount.objects.get(service="email")
    with pytest.raises(ValidationError) as caught:
        services.apply_platform_change(
            account,
            enabled=True,
            config={**ETQAN_SMTP, "port": 0},
            new_secrets={"password": "etqan-smtp-secret-1999"},
            clear_secrets=False,
        )
    assert caught.value.field == "port"


def test_a_service_not_built_yet_cannot_be_switched_on_by_etqan():
    account = PlatformAccount.objects.get(service="whatsapp")
    with pytest.raises(ValidationError) as caught:
        services.apply_platform_change(
            account, enabled=True, config={}, new_secrets=None, clear_secrets=False
        )
    assert caught.value.field == "enabled"


def test_the_platform_config_must_be_an_object():
    account = PlatformAccount.objects.get(service="email")
    with pytest.raises(ValidationError) as caught:
        services.apply_platform_change(
            account, enabled=True, config=["x"], new_secrets=None, clear_secrets=False
        )
    assert caught.value.field == "config"
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/integrations/tests/test_resolver.py etqan/integrations/tests/test_accounts.py -q`
Expected: collection error `ImportError: cannot import name 'services' from 'etqan.integrations'`.

- [ ] **Step 3: Implement**

`backend/etqan/integrations/clock.py`:

```python
"""The only clock integrations reads, so tests pin it by monkeypatching
`now`: when a connection was last tested."""

from datetime import datetime

from django.utils import timezone


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()
```

`backend/etqan/integrations/services/resolver.py`:

```python
"""The resolver (spec §3.2): which account a service uses in the current
academy. Every caller asks here and stores no keys of its own (IN-7).

The answer is kept on the academy object on the connection for as long as
that object lives (plan D8): django-tenants loads the academy afresh for
every request and `academy_context` does for every task, so that is one
request or one task, the pattern of `platform.permissions.codes_of`. A
change through these services forgets it at once."""

import json
from dataclasses import dataclass
from dataclasses import field

from django.db import connection
from django_tenants.utils import get_public_schema_name

from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.models import Service
from etqan.platform import features
from etqan.platform import secrets

ACADEMY = "academy"
ETQAN = "etqan"
SERVICES: tuple[str, ...] = tuple(Service.values)
# Plan D7: Plan 13's switches gating Etqan's default; any one on is enough.
# Email has no switch; WhatsApp's comes with phase B5c, which adds it here.
SWITCHES: dict[str, tuple[str, ...]] = {
    "whatsapp": (),
    "email": (),
    "payments": ("online_payments",),
    "video": ("zoom_api",),
    "ai": ("ai_assistant", "ai_reports"),
}
AVAILABLE = "available"
DISABLED = "disabled"
FEATURE_OFF = "feature_off"
SUSPENDED = "suspended"
CACHE = "_etqan_integrations"


@dataclass(frozen=True)
class Resolved:
    service: str
    source: str
    config: dict
    secret_enc: str = field(default="", repr=False)

    def secrets(self) -> dict:
        """The account's secrets, decrypted for the provider that uses them."""
        return read_secrets(self.secret_enc)


def read_secrets(token: str) -> dict:
    return json.loads(secrets.decrypt(token)) if token else {}


def write_secrets(values: dict) -> str:
    return secrets.encrypt(json.dumps(values, sort_keys=True)) if values else ""


def _tenant():
    return getattr(connection, "tenant", None)


def _store() -> dict:
    tenant = _tenant()
    if tenant is None:
        return {}
    store = getattr(tenant, CACHE, None)
    if store is None:
        store = {}
        setattr(tenant, CACHE, store)
    return store


def clear_cache(tenant=None) -> None:
    """Forget the answers kept on ``tenant`` (by default the academy on the
    connection)."""
    target = tenant if tenant is not None else _tenant()
    if target is not None:
        vars(target).pop(CACHE, None)


def _etqan_default(service: str) -> tuple[PlatformAccount | None, str]:
    account = PlatformAccount.objects.filter(service=service).first()
    if account is None or not account.enabled:
        return None, DISABLED
    switches = SWITCHES[service]
    if switches and not any(features.enabled(code) for code in switches):
        return None, FEATURE_OFF
    if getattr(_tenant(), "etqan_defaults_suspended", False):
        return None, SUSPENDED
    return account, AVAILABLE


def default_status(service: str) -> str:
    """Whether Etqan's default is there for this academy, and if not why:
    ``available``, ``disabled``, ``feature_off`` or ``suspended``."""
    return _etqan_default(service)[1]


def _resolve(service: str) -> Resolved | None:
    # Plan D10: the public schema has no academy accounts.
    if connection.schema_name != get_public_schema_name():
        own = AcademyAccount.objects.filter(service=service, enabled=True).first()
        if own is not None:
            return Resolved(service, ACADEMY, dict(own.config), own.secret_enc)
    account, _ = _etqan_default(service)
    if account is None:
        return None
    return Resolved(service, ETQAN, dict(account.config), account.secret_enc)


def resolve(service: str) -> Resolved | None:
    """Spec §3.2. Callers meter only when ``source == "etqan"``."""
    if service not in SWITCHES:
        raise LookupError(f"Unknown service: {service!r}")
    store = _store()
    if service not in store:
        store[service] = _resolve(service)
    return store[service]
```

`backend/etqan/integrations/services/accounts.py`:

```python
"""The academy's own accounts and Etqan's defaults (spec §3.1, §3.3).
Secrets are written here only, as Fernet tokens of a JSON object; nothing
here returns them except to the provider that uses them."""

from django.db import transaction

from etqan.integrations import clock
from etqan.integrations import providers
from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.services.resolver import ACADEMY
from etqan.integrations.services.resolver import ETQAN
from etqan.integrations.services.resolver import clear_cache
from etqan.integrations.services.resolver import read_secrets
from etqan.integrations.services.resolver import write_secrets
from etqan.platform.exceptions import ValidationError

NOT_CONNECTED = "integrations.not_connected"
NO_TESTER_EMAIL = "integrations.no_tester_email"
ERROR_LENGTH = 500


def connectable(service: str) -> bool:
    return providers.get(service).connectable


def own_account(service: str) -> AcademyAccount | None:
    return AcademyAccount.objects.filter(service=service).first()


def _forget_test(account) -> None:
    """Plan D17: the last test no longer describes a changed account."""
    account.last_test_at = None
    account.last_test_ok = None
    account.last_test_error = ""


@transaction.atomic
def connect(service: str, *, fields: object, by) -> AcademyAccount:
    """Connect or edit the academy's own account (spec §6). A blank or
    missing secret keeps the stored one (plan D15)."""
    provider = providers.get(service)
    if not isinstance(fields, dict):
        raise ValidationError("Send the account's fields as an object.")
    account = (
        AcademyAccount.objects.select_for_update().filter(service=service).first()
        or AcademyAccount(service=service)
    )
    stored = read_secrets(account.secret_enc)
    config, values = provider.clean(fields, stored=stored)
    enabled = fields.get("enabled", True)
    if not isinstance(enabled, bool):
        raise ValidationError("Must be true or false.", field="enabled")
    if account.pk is None or config != account.config or values != stored:
        _forget_test(account)
    account.config = config
    account.secret_enc = write_secrets(values)
    account.secret_last4 = provider.last4(values)
    account.enabled = enabled
    account.updated_by = by
    account.save()
    clear_cache()
    return account


def disconnect(service: str) -> None:
    """Remove the academy's own account; idempotent."""
    providers.get(service)
    AcademyAccount.objects.filter(service=service).delete()
    clear_cache()


def probe(service: str, *, scope: str, tester_email: str):
    """Spec §3.3 (plan D9): run the provider's probe against the academy's
    own account (``scope="academy"``) or Etqan's default (``"etqan"``) and
    record the verdict on that row. A failed probe is an answer, not an
    error."""
    provider = providers.get(service)
    if scope == ACADEMY:
        account = own_account(service)
        if account is None:
            raise ValidationError("Connect an account first.", code=NOT_CONNECTED)
    elif scope == ETQAN:
        account = PlatformAccount.objects.get(service=service)
    else:
        raise ValueError(f"Unknown scope: {scope!r}")
    if not tester_email:
        raise ValidationError(
            "Your account has no email address to send the test to.",
            code=NO_TESTER_EMAIL,
        )
    try:
        provider.probe(
            config=dict(account.config),
            secrets=read_secrets(account.secret_enc),
            tester_email=tester_email,
        )
    except providers.ProbeError as exc:
        account.last_test_ok = False
        account.last_test_error = exc.message[:ERROR_LENGTH]
    else:
        account.last_test_ok = True
        account.last_test_error = ""
    account.last_test_at = clock.now()
    account.save(update_fields=["last_test_at", "last_test_ok", "last_test_error"])
    return account


def apply_platform_change(
    account: PlatformAccount,
    *,
    enabled: bool,
    config: object,
    new_secrets: dict | None,
    clear_secrets: bool,
) -> dict:
    """The platform admin's change to one of Etqan's defaults, checked and
    applied to ``account`` in memory (the admin saves it). Email with no
    server is today's sending (plan D6); with one, the email rules apply.
    Returns the config to store."""
    provider = providers.get(account.service)
    if not isinstance(config, dict):
        raise ValidationError("Enter a JSON object.", field="config")
    if enabled and not provider.connectable:
        raise ValidationError(
            "This service cannot be switched on before it is built.", field="enabled"
        )
    before = read_secrets(account.secret_enc)
    stored = {} if clear_secrets else before
    values = {**stored, **(new_secrets or {})}
    if config and provider.connectable:
        config, values = provider.clean({**config, **values}, stored=stored)
    if config != account.config or values != before:
        _forget_test(account)
    account.enabled = enabled
    account.config = config
    account.secret_enc = write_secrets(values)
    account.secret_last4 = provider.last4(values)
    return config
```

`backend/etqan/integrations/services/__init__.py`:

```python
"""Public API of integrations. Other apps import only this package."""

from etqan.integrations.services.accounts import NO_TESTER_EMAIL
from etqan.integrations.services.accounts import NOT_CONNECTED
from etqan.integrations.services.accounts import apply_platform_change
from etqan.integrations.services.accounts import connect
from etqan.integrations.services.accounts import connectable
from etqan.integrations.services.accounts import disconnect
from etqan.integrations.services.accounts import own_account
from etqan.integrations.services.accounts import probe
from etqan.integrations.services.resolver import ACADEMY
from etqan.integrations.services.resolver import AVAILABLE
from etqan.integrations.services.resolver import DISABLED
from etqan.integrations.services.resolver import ETQAN
from etqan.integrations.services.resolver import FEATURE_OFF
from etqan.integrations.services.resolver import SERVICES
from etqan.integrations.services.resolver import SUSPENDED
from etqan.integrations.services.resolver import SWITCHES
from etqan.integrations.services.resolver import Resolved
from etqan.integrations.services.resolver import clear_cache
from etqan.integrations.services.resolver import default_status
from etqan.integrations.services.resolver import read_secrets
from etqan.integrations.services.resolver import resolve
from etqan.integrations.services.resolver import write_secrets

__all__ = [
    "ACADEMY",
    "AVAILABLE",
    "DISABLED",
    "ETQAN",
    "FEATURE_OFF",
    "NOT_CONNECTED",
    "NO_TESTER_EMAIL",
    "SERVICES",
    "SUSPENDED",
    "SWITCHES",
    "Resolved",
    "apply_platform_change",
    "clear_cache",
    "connect",
    "connectable",
    "default_status",
    "disconnect",
    "own_account",
    "probe",
    "read_secrets",
    "resolve",
    "write_secrets",
]
```

In `backend/conftest.py`, replace the body of `_academy_schema` after its docstring

```python
    connection.set_tenant(tenants.main)
    yield
    connection.set_schema_to_public()
```

with

```python
    _forget_integrations(tenants)
    connection.set_tenant(tenants.main)
    yield
    connection.set_schema_to_public()
    _forget_integrations(tenants)


def _forget_integrations(tenants):
    """The integrations resolver keeps its answers on the academy object for
    one request (plan D8); a request loads its academy afresh, but these
    session-shared test academies must not carry them to the next test."""
    from etqan.integrations.services import clear_cache  # noqa: PLC0415

    for academy in (tenants.public, tenants.main, tenants.other):
        clear_cache(academy)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DJ pytest etqan/integrations -q && $DJ lint-imports`
Expected: all pass; contracts kept.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/integrations conftest.py
git -C backend commit -m "feat(integrations): resolver with per-request cache, connect, disconnect and probe" -m "$TRAILER"
```

---

### Task 4: Email on the resolver

**Files:**
- Create: `backend/etqan/integrations/services/email.py`, `backend/etqan/integrations/tasks.py`, `backend/etqan/integrations/tests/test_email.py`
- Modify: `backend/etqan/integrations/services/__init__.py`, `backend/etqan/site/emails.py`, `backend/etqan/site/tests/test_emails.py`, `backend/etqan/identity/adapter.py`, `backend/etqan/identity/services.py`, `backend/etqan/identity/tests/test_async_email.py`, `backend/etqan/notifications/channels/email.py`, `backend/etqan/notifications/tests/test_email.py`
- Delete: `backend/etqan/platform/tasks.py`

**Interfaces:**
- Consumes: `resolve("email")`, `Resolved.secrets()`, `mail_connection(config, values)`, `etqan.platform.tenancy.academy_context(schema_name)`, `site.emails.brand_email(...)`.
- Produces: `services.send_email_now(*, subject: str, body: str, from_email: str, to: list[str], alternatives: list | None = None, reply_to: list[str] | None = None) -> Resolved` (raises `NotSetUpError`; SMTP `OSError` propagates), `services.queue_email(*, subject, body, from_email, to, alternatives=None, reply_to=None) -> None`, `services.meter_email(resolved: Resolved, *, accepted: int) -> None` (the slice-2 metering seam), `services.NotSetUpError`; Celery task `etqan.integrations.tasks.send_email(schema_name: str, *, subject, body, from_email, to, alternatives=None, reply_to=None) -> str` named `integrations.send_email`, returning `"academy" | "etqan" | "not_set_up"`; `brand_email(...)["reply_to"]: list[str]`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/integrations/tests/test_email.py`:

```python
"""Spec §4 (email): every email goes out on the account the academy
resolves to. Etqan's default keeps today's sending and the academy's
reply-to; an own account sends through its server from its address."""

import pytest
from allauth.account.models import EmailAddress
from django.core import mail
from django.db import connection
from rest_framework.test import APIClient

from etqan.integrations import services
from etqan.integrations import tasks
from etqan.integrations.models import PlatformAccount
from etqan.integrations.providers import email as email_provider
from etqan.integrations.services import email as email_service
from etqan.integrations.tests.conftest import LOCMEM
from etqan.integrations.tests.fakes import Recording

pytestmark = pytest.mark.django_db
FAKES = "etqan.integrations.tests.fakes"
BRANDED = {
    "subject": "[Noor Academy] Hello",
    "body": "Body",
    "from_email": '"Noor Academy" <noreply@etqan.test>',
    "alternatives": [["<p>Body</p>", "text/html"]],
    "reply_to": ["hi@noor.test"],
}


def test_etqans_default_is_todays_sending_with_the_academys_reply_to():
    resolved = services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    assert resolved.source == "etqan"
    (message,) = mail.outbox
    assert message.from_email == '"Noor Academy" <noreply@etqan.test>'
    assert message.reply_to == ["hi@noor.test"]
    assert message.to == ["yusuf@family.test"]
    assert message.alternatives[0][1] == "text/html"


def test_an_own_account_sends_through_its_server_from_its_address(
    own_email, monkeypatch
):
    Recording.opened.clear()
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", f"{FAKES}.Recording")
    resolved = services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    assert resolved.source == "academy"
    (message,) = mail.outbox
    assert message.from_email == '"Noor Academy" <office@noor.test>'
    assert message.reply_to == []
    assert Recording.opened == [
        {
            "fail_silently": False,
            "host": "smtp.noor.test",
            "port": 587,
            "username": "mailer@noor.test",
            "password": "app-password-1234",
            "use_tls": True,
            "use_ssl": False,
            "timeout": 5,
        }
    ]


def test_etqans_default_may_send_through_its_own_server(monkeypatch):
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", LOCMEM)
    PlatformAccount.objects.filter(service="email").update(
        config={
            "host": "smtp.etqan.test",
            "port": 587,
            "username": "",
            "security": "starttls",
            "from_address": "noreply@etqan.agency",
        }
    )
    services.clear_cache()
    services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    (message,) = mail.outbox
    assert message.from_email == '"Noor Academy" <noreply@etqan.agency>'
    assert message.reply_to == ["hi@noor.test"]


def test_the_meter_is_called_once_with_how_the_email_resolved(monkeypatch):
    seen = []
    monkeypatch.setattr(
        email_service,
        "meter_email",
        lambda resolved, *, accepted: seen.append((resolved.source, accepted)),
    )
    services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    assert seen == [("etqan", 1)]


def test_with_nothing_set_up_nothing_is_sent():
    PlatformAccount.objects.filter(service="email").update(enabled=False)
    with pytest.raises(services.NotSetUpError):
        services.send_email_now(**BRANDED, to=["yusuf@family.test"])
    assert mail.outbox == []


def test_a_queued_email_resolves_in_the_academy_that_queued_it(own_email, monkeypatch):
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", LOCMEM)
    services.queue_email(**BRANDED, to=["yusuf@family.test"])
    (message,) = mail.outbox
    assert message.from_email == '"Noor Academy" <office@noor.test>'


def test_the_task_reports_not_set_up_without_retrying():
    PlatformAccount.objects.filter(service="email").update(enabled=False)
    result = tasks.send_email.delay(
        connection.schema_name, **BRANDED, to=["yusuf@family.test"]
    )
    assert result.get() == "not_set_up"
    assert mail.outbox == []


def test_etqan_staff_mail_in_the_public_schema_goes_out_on_the_default():
    connection.set_schema_to_public()
    result = tasks.send_email.delay(
        "public", **{**BRANDED, "reply_to": []}, to=["ops@etqan.test"]
    )
    assert result.get() == "etqan"
    assert mail.outbox[0].to == ["ops@etqan.test"]


def test_a_password_reset_goes_out_from_the_academys_own_account(
    own_email, monkeypatch, api_for
):
    monkeypatch.setattr(email_provider, "SMTP_BACKEND", LOCMEM)
    user = api_for("student", email="yusuf@family.test").user
    EmailAddress.objects.update_or_create(
        user=user, email=user.email, defaults={"primary": True, "verified": True}
    )
    resp = APIClient().post(
        "/api/v1/identity/password-reset/",
        {"email": "yusuf@family.test"},
        format="json",
    )
    assert resp.status_code == 200
    (message,) = mail.outbox
    assert message.to == ["yusuf@family.test"]
    assert message.from_email.endswith("<office@noor.test>")
```

Replace `backend/etqan/identity/tests/test_async_email.py` with:

```python
"""Account emails are rendered in-request but sent via a Celery task, which
resolves the academy's email account (integrations, plan D11)."""

from unittest.mock import patch

import pytest
from allauth.account.models import EmailAddress
from rest_framework.test import APIClient

from etqan.identity.models import User
from etqan.integrations.services import queue_email


@pytest.fixture
def api():
    return APIClient()


@pytest.mark.django_db
class TestAsyncEmail:
    def test_a_queued_message_is_sent(self, mailoutbox):
        queue_email(
            subject="Hello",
            body="Body",
            from_email="from@example.com",
            to=["to@example.com"],
        )
        assert len(mailoutbox) == 1
        assert mailoutbox[0].subject == "Hello"
        assert mailoutbox[0].to == ["to@example.com"]

    def test_resend_dispatched_to_celery_with_the_academy(self, api, settings, tenants):
        settings.ACCOUNT_EMAIL_VERIFICATION = "mandatory"
        user = User.objects.create_user(email="ahmad@example.com", password="pw")
        EmailAddress.objects.create(
            user=user, email=user.email, primary=True, verified=False
        )
        with patch("etqan.integrations.tasks.send_email.delay") as delay:
            resp = api.post(
                "/api/v1/identity/resend-verification/",
                {"email": "ahmad@example.com"},
                format="json",
            )
        assert resp.status_code == 200
        assert delay.called
        assert delay.call_args.args == (tenants.main.schema_name,)
```

In `backend/etqan/site/tests/test_emails.py`, append:

```python
@pytest.mark.django_db
def test_replies_go_to_the_academys_contact_address(branded):
    """Integrations plan D12: Etqan's default email replies to the academy."""
    assert brand_email(subject="s", body="b")["reply_to"] == ["hi@noor.test"]
    Branding.objects.update(contact_email="")
    assert brand_email(subject="s", body="b")["reply_to"] == []


@pytest.mark.django_db
def test_public_mail_has_no_reply_to():
    connection.set_schema_to_public()
    assert brand_email(subject="Hello", body="Body")["reply_to"] == []
```

In `backend/etqan/notifications/tests/test_email.py`, replace `real = email.send_email_message` with `real = email.send_email_now`, and both `monkeypatch.setattr(email, "send_email_message", …)` calls with `monkeypatch.setattr(email, "send_email_now", …)` (same second argument). Then append:

```python
def test_with_no_email_account_the_row_fails_with_the_reason(family, monkeypatch):
    """Integrations plan D11: nothing resolves, so nothing is sent and the
    row says why, at once (no retry)."""
    monkeypatch.setattr(
        "etqan.integrations.services.email.resolve", lambda service: None
    )
    row = notice(family.student)
    result = email.deliver_email.apply(args=[connection.schema_name, row.pk])
    assert result.get() == "failed"
    row.refresh_from_db()
    assert (row.email_status, row.email_error, mail.outbox) == (
        "failed",
        "Email is not set up for this academy.",
        [],
    )
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/integrations/tests/test_email.py etqan/identity/tests/test_async_email.py etqan/site/tests/test_emails.py etqan/notifications/tests/test_email.py -q`
Expected: `test_email.py` and `test_async_email.py` fail to collect (`ImportError: cannot import name 'tasks'` / `cannot import name 'queue_email'`); `test_emails.py` fails with `KeyError: 'reply_to'`; the notifications tests fail with `AttributeError: … has no attribute 'send_email_now'`.

- [ ] **Step 3: Implement**

`backend/etqan/integrations/services/email.py`:

```python
"""Email on the resolver (spec §4, email row). Every email the product
sends goes through here: the academy's own server and from address when it
has connected one, else Etqan's default (today's sending, from noreply@
with the academy's name, replies to the academy's contact address)."""

from email.utils import parseaddr
from email.utils import quote as email_quote

from django.core.mail import EmailMultiAlternatives
from django.db import connection

from etqan.integrations.providers.email import mail_connection
from etqan.integrations.services.resolver import ACADEMY
from etqan.integrations.services.resolver import Resolved
from etqan.integrations.services.resolver import resolve

EMAIL = "email"


class NotSetUpError(Exception):
    """No email account resolves: the academy has none of its own and
    Etqan's default is off or suspended for it (spec §3.2, step 3)."""


def _sender(resolved: Resolved, branded: str) -> str:
    """The branded From with the account's own address, when it has one; the
    academy's display name is kept (plan D12)."""
    address = resolved.config.get("from_address")
    if not address:
        return branded
    name, _ = parseaddr(branded)
    name = name.replace("\r", "").replace("\n", "")
    return f'"{email_quote(name)}" <{address}>' if name else address


def meter_email(resolved: Resolved, *, accepted: int) -> None:
    """The one place email is metered (spec §5, plan D13). Slice 2 fills it
    in: when ``resolved.source == "etqan"`` it calls
    ``etqan_billing.record_usage(service="email", unit="email",
    quantity=accepted, ...)``. Email on the academy's own account is never
    charged (IN-5). Slice 1 records nothing."""


def send_email_now(  # noqa: PLR0913 -- the branded message's parts
    *,
    subject: str,
    body: str,
    from_email: str,
    to: list[str],
    alternatives: list | None = None,
    reply_to: list[str] | None = None,
) -> Resolved:
    """Send one already-branded email now through the account the current
    academy resolves to. Raises NotSetUpError when none does; SMTP errors
    (``OSError``) propagate for the caller to retry."""
    resolved = resolve(EMAIL)
    if resolved is None:
        raise NotSetUpError("Email is not set up for this academy.")
    message = EmailMultiAlternatives(
        subject=subject,
        body=body,
        from_email=_sender(resolved, from_email),
        to=to,
        # Spec §4: the default's replies go to the academy; an own account's
        # From already is the academy's.
        reply_to=[] if resolved.source == ACADEMY else list(reply_to or []),
        connection=mail_connection(resolved.config, resolved.secrets()),
    )
    for content, mimetype in alternatives or []:
        message.attach_alternative(content, mimetype)
    accepted = message.send()
    meter_email(resolved, accepted=accepted)
    return resolved


def queue_email(  # noqa: PLR0913 -- the branded message's parts
    *,
    subject: str,
    body: str,
    from_email: str,
    to: list[str],
    alternatives: list | None = None,
    reply_to: list[str] | None = None,
) -> None:
    """Hand an already-branded email to Celery with this academy's schema,
    so the worker resolves the same academy's account (plan D11)."""
    from etqan.integrations.tasks import send_email  # noqa: PLC0415 -- the task imports this module

    send_email.delay(
        connection.schema_name,
        subject=subject,
        body=body,
        from_email=from_email,
        to=to,
        alternatives=alternatives,
        reply_to=reply_to,
    )
```

`backend/etqan/integrations/tasks.py`:

```python
"""Email delivery off the request (spec §4, plan D11): the message is
rendered in the web process; the worker resolves the account inside the
academy that queued it."""

import logging

from celery import shared_task

from etqan.integrations.services import email
from etqan.platform.tenancy import academy_context

logger = logging.getLogger(__name__)
SEND = "integrations.send_email"
NOT_SET_UP = "not_set_up"


@shared_task(
    name=SEND,
    autoretry_for=(OSError,),
    retry_backoff=True,
    retry_kwargs={"max_retries": 3},
)
def send_email(  # noqa: PLR0913 -- the schema and the branded message's parts
    schema_name: str,
    *,
    subject: str,
    body: str,
    from_email: str,
    to: list[str],
    alternatives: list | None = None,
    reply_to: list[str] | None = None,
) -> str:
    """Send one queued email; returns how it resolved (``academy`` or
    ``etqan``), or ``not_set_up`` (logged, never retried). An SMTP error
    (``OSError``) retries with backoff."""
    with academy_context(schema_name):
        try:
            resolved = email.send_email_now(
                subject=subject,
                body=body,
                from_email=from_email,
                to=to,
                alternatives=alternatives,
                reply_to=reply_to,
            )
        except email.NotSetUpError:
            logger.warning("Email not sent: not set up in %s", schema_name)
            return NOT_SET_UP
    return resolved.source
```

In `backend/etqan/integrations/services/__init__.py`, add after the `accounts` imports:

```python
from etqan.integrations.services.email import NotSetUpError
from etqan.integrations.services.email import meter_email
from etqan.integrations.services.email import queue_email
from etqan.integrations.services.email import send_email_now
```

and add `"NotSetUpError"`, `"meter_email"`, `"queue_email"`, `"send_email_now"` to `__all__` (keeping it sorted: `"NotSetUpError"` after `"NO_TESTER_EMAIL"`, `"meter_email"` after `"disconnect"`, `"queue_email"` after `"probe"`, `"send_email_now"` after `"resolve"`).

In `backend/etqan/site/emails.py`: in `brand_email`'s docstring, replace

```python
    Returns ``{"subject", "body", "html", "from_email"}``. Unbranded (public
    schema only) returns ``[Etqan] <subject>``, the body unchanged, ``html=None``, and
    ``from_email=settings.DEFAULT_FROM_EMAIL``.
```

with

```python
    Returns ``{"subject", "body", "html", "from_email", "reply_to"}``.
    ``reply_to`` is the academy's contact address, or ``[]`` (integrations
    plan D12: used only on Etqan's default account). Unbranded (public
    schema only) returns ``[Etqan] <subject>``, the body unchanged,
    ``html=None``, ``from_email=settings.DEFAULT_FROM_EMAIL`` and no reply-to.
```

In the public branch's returned dict add `"reply_to": [],` after `"from_email": settings.DEFAULT_FROM_EMAIL,`; in the academy branch's returned dict add, after `"from_email": _quoted_from_header(name, address),`:

```python
        "reply_to": [branding.contact_email] if branding.contact_email else [],
```

In `backend/etqan/identity/adapter.py`, replace `from etqan.platform.tasks import send_email_message` with `from etqan.integrations.services import queue_email` (keep import order: it goes before `from etqan.platform.frontend import app_url`), and replace

```python
        send_email_message.delay(
            subject=branded["subject"],
            body=branded["body"],
            from_email=branded["from_email"],
            to=list(message.to),
            alternatives=[[branded["html"], "text/html"]] if branded["html"] else None,
        )
```

with

```python
        queue_email(
            subject=branded["subject"],
            body=branded["body"],
            from_email=branded["from_email"],
            to=list(message.to),
            alternatives=[[branded["html"], "text/html"]] if branded["html"] else None,
            reply_to=branded["reply_to"],
        )
```

In `backend/etqan/identity/services.py`, remove `from etqan.platform.tasks import send_email_message`, add `from etqan.integrations.services import queue_email` in sorted position among the `etqan.` imports, and replace the body of `_send` after its docstring

```python
    if not to:
        return
    msg = brand_email(subject=subject, body=body, language=language)
    send_email_message.delay(
        subject=msg["subject"],
        body=msg["body"],
        from_email=msg["from_email"],
        to=[to],
        alternatives=[[msg["html"], "text/html"]] if msg["html"] else None,
    )
```

with

```python
    if not to:
        return
    msg = brand_email(subject=subject, body=body, language=language)
    queue_email(
        subject=msg["subject"],
        body=msg["body"],
        from_email=msg["from_email"],
        to=[to],
        alternatives=[[msg["html"], "text/html"]] if msg["html"] else None,
        reply_to=msg["reply_to"],
    )
```

In `backend/etqan/notifications/channels/email.py`: replace the module docstring's last line `sent by the platform's send path, once."""` with `sent once, through the email account the academy resolves to (integrations)."""`; replace `from etqan.platform.tasks import send_email_message` with `from etqan.integrations.services import send_email_now` (placed before `from etqan.notifications import clock`); in `compose`, add to the returned dict after `"from_email": message["from_email"],`:

```python
        "reply_to": message["reply_to"],
```

and in `send` replace `send_email_message(**compose(notification), to=[address])` with `send_email_now(**compose(notification), to=[address])`.

Delete the retired task:

```bash
git -C backend rm etqan/platform/tasks.py
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DJ pytest etqan/integrations etqan/identity etqan/site etqan/notifications etqan/registration -q && $DJ lint-imports`
Expected: all pass (every identity, site, notifications and registration mail test now sends through the resolver to the locmem backend); contracts kept.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/integrations etqan/site etqan/identity etqan/notifications
git -C backend commit -m "feat(integrations): send every email through the resolved account" -m "$TRAILER"
```

---

### Task 5: The Settings → Integrations API and its permission codes

**Files:**
- Create: `backend/etqan/integrations/api/__init__.py`, `backend/etqan/integrations/api/payloads.py`, `backend/etqan/integrations/api/views.py`, `backend/etqan/integrations/api/urls.py`, `backend/etqan/integrations/tests/test_api.py`
- Modify: `backend/config/api_router.py`, `backend/etqan/access/registry.py`, `backend/etqan/access/tests/test_registry.py`, `backend/etqan/access/tests/test_routes.py`

**Interfaces:**
- Consumes: `services.resolve`, `default_status`, `connectable`, `own_account`, `connect`, `disconnect`, `probe`, `SERVICES`, `ACADEMY`; `etqan.platform.permissions.HasCode` (reads `permission_codes` by method).
- Produces: `GET /api/v1/integrations/` → `200 {"services": [card, …]}`; `PUT /api/v1/integrations/<service>/` → `200 card`; `DELETE /api/v1/integrations/<service>/` → `200 card`; `POST /api/v1/integrations/<service>/test/` → `200 card`. Card per plan D15. Access resource `integration` with in-use verbs `("view", "update")`. `payloads.card(service: str) -> dict`, `payloads.cards() -> list[dict]`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/integrations/tests/test_api.py`:

```python
"""Spec §6: Settings → Integrations, one card per service; secrets never
leave the server (Review Focus 1)."""

import pytest

from etqan.integrations import services
from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.tests.conftest import SMTP
from etqan.integrations.tests.conftest import SMTP_CONFIG

pytestmark = pytest.mark.django_db
URL = "/api/v1/integrations/"


def test_the_admin_reads_one_card_per_service_in_order(api_for):
    body = api_for("admin").get(URL).json()
    assert [card["service"] for card in body["services"]] == [
        "whatsapp",
        "email",
        "payments",
        "video",
        "ai",
    ]
    assert body["services"][1] == {
        "service": "email",
        "using": "etqan",
        "default_status": "available",
        "connectable": True,
        "own": None,
    }
    assert body["services"][0] == {
        "service": "whatsapp",
        "using": "none",
        "default_status": "disabled",
        "connectable": False,
        "own": None,
    }


def test_connecting_email_returns_the_card_without_the_password(api_for, fake_email):
    client = api_for("admin")
    resp = client.put(f"{URL}email/", SMTP, format="json")
    assert resp.status_code == 200
    body = resp.json()
    assert body["using"] == "academy"
    assert body["own"]["config"] == SMTP_CONFIG
    assert body["own"]["secret_last4"] == "1234"
    assert (body["own"]["enabled"], body["own"]["last_test_ok"]) == (True, None)
    token = AcademyAccount.objects.get(service="email").secret_enc
    for text in (resp.content.decode(), client.get(URL).content.decode()):
        assert "app-password-1234" not in text
        assert token not in text


def test_a_blank_password_keeps_the_stored_one(api_for, own_email):
    resp = api_for("admin").put(
        f"{URL}email/",
        {**SMTP, "password": "", "host": "smtp2.noor.test"},
        format="json",
    )
    assert resp.status_code == 200
    services.clear_cache()
    assert services.resolve("email").secrets() == {"password": "app-password-1234"}


def test_a_refused_field_is_a_400_on_that_field(api_for, fake_email):
    resp = api_for("admin").put(f"{URL}email/", {**SMTP, "port": 70000}, format="json")
    assert (resp.status_code, list(resp.json())) == (400, ["port"])


def test_a_service_not_built_yet_cannot_be_connected(api_for):
    resp = api_for("admin").put(f"{URL}whatsapp/", {"token": "x"}, format="json")
    assert resp.status_code == 400
    assert resp.json()["code"] == "integrations.not_available"


def test_an_unknown_service_is_a_404(api_for):
    client = api_for("admin")
    assert client.put(f"{URL}sms/", {}, format="json").status_code == 404
    assert client.delete(f"{URL}sms/").status_code == 404
    assert client.post(f"{URL}sms/test/").status_code == 404


def test_a_test_records_success_and_failure_and_answers_200(
    api_for, own_email, fake_email
):
    client = api_for("admin", email="tester@noor.test")
    passed = client.post(f"{URL}email/test/")
    assert (passed.status_code, passed.json()["own"]["last_test_ok"]) == (200, True)
    assert fake_email.probed[-1]["to"] == "tester@noor.test"
    fake_email.failure = "The server refused the user name or password."
    failed = client.post(f"{URL}email/test/").json()
    assert (failed["own"]["last_test_ok"], failed["own"]["last_test_error"]) == (
        False,
        "The server refused the user name or password.",
    )


def test_testing_without_an_account_is_a_400(api_for):
    resp = api_for("admin").post(f"{URL}email/test/")
    assert (resp.status_code, resp.json()["code"]) == (400, "integrations.not_connected")


def test_disconnecting_falls_back_to_etqans_default(api_for, own_email):
    body = api_for("admin").delete(f"{URL}email/").json()
    assert (body["using"], body["own"]) == ("etqan", None)


def test_staff_need_the_codes(staff_for):
    assert staff_for().get(URL).status_code == 403
    reader = staff_for("integration.view")
    assert reader.get(URL).status_code == 200
    assert reader.put(f"{URL}email/", SMTP, format="json").status_code == 403
    assert reader.post(f"{URL}email/test/").status_code == 403


def test_teachers_never_see_integrations(api_for):
    assert api_for("teacher").get(URL).status_code == 403
```

In `backend/etqan/access/tests/test_registry.py`, in `test_resources_carry_the_12_verbs_and_the_role_resource_6`, before `assert by_code["session"].verbs == …`, add:

```python
    # Integrations (spec 2026-10-07 §6; not a phase).
    assert by_code["integration"].in_use == ("view", "update")
```

In `backend/etqan/access/tests/test_routes.py`, end `ROUTES` with the integrations rows: replace

```python
    ("DELETE", "/api/v1/translations/en/common.save/", "page.quick_translate"),
]
```

with

```python
    ("DELETE", "/api/v1/translations/en/common.save/", "page.quick_translate"),
    # Integrations (spec 2026-10-07 §6; not a phase): no feature switch.
    ("GET", "/api/v1/integrations/", "integration.view"),
    ("PUT", "/api/v1/integrations/email/", "integration.update"),
    ("DELETE", "/api/v1/integrations/email/", "integration.update"),
    ("POST", "/api/v1/integrations/email/test/", "integration.update"),
]
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DJ pytest etqan/integrations/tests/test_api.py etqan/access -q`
Expected: `test_api.py` fails with 404s on `/api/v1/integrations/`; `test_registry.py` fails with `KeyError: 'integration'`; `test_routes.py` fails (`Resolver404` for the new rows).

- [ ] **Step 3: Implement**

Create `backend/etqan/integrations/api/__init__.py` empty.

`backend/etqan/integrations/api/payloads.py`:

```python
"""JSON shapes for Settings → Integrations (spec §6, plan D15). A secret
never appears: only its last four characters when long enough (plan D5)."""

from etqan.integrations import services

NONE = "none"


def _own(account) -> dict | None:
    if account is None:
        return None
    return {
        "enabled": account.enabled,
        "config": dict(account.config),
        "secret_last4": account.secret_last4,
        "last_test_at": account.last_test_at,
        "last_test_ok": account.last_test_ok,
        "last_test_error": account.last_test_error,
        "updated_at": account.updated_at,
    }


def card(service: str) -> dict:
    resolved = services.resolve(service)
    return {
        "service": service,
        "using": resolved.source if resolved else NONE,
        "default_status": services.default_status(service),
        "connectable": services.connectable(service),
        "own": _own(services.own_account(service)),
    }


def cards() -> list[dict]:
    return [card(service) for service in services.SERVICES]
```

`backend/etqan/integrations/api/views.py`:

```python
"""Settings → Integrations (spec §6). Thin: call one service, answer the
fresh card. Admins always pass; staff need the codes (plan D15)."""

from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.integrations import services
from etqan.integrations.api import payloads
from etqan.platform.permissions import HasCode

VIEW = "integration.view"
UPDATE = "integration.update"


class IntegrationListView(APIView):
    permission_classes = [HasCode]
    permission_codes = {"GET": VIEW}

    def get(self, request):
        return Response({"services": payloads.cards()})


class IntegrationView(APIView):
    permission_classes = [HasCode]
    permission_codes = {"PUT": UPDATE, "DELETE": UPDATE}

    def put(self, request, service):
        services.connect(service, fields=request.data, by=request.user)
        return Response(payloads.card(service))

    def delete(self, request, service):
        services.disconnect(service)
        return Response(payloads.card(service))


class IntegrationTestView(APIView):
    """Spec §3.3: the probe sends to the signed-in tester (plan D9)."""

    permission_classes = [HasCode]
    permission_codes = {"POST": UPDATE}

    def post(self, request, service):
        services.probe(
            service, scope=services.ACADEMY, tester_email=request.user.email or ""
        )
        return Response(payloads.card(service))
```

`backend/etqan/integrations/api/urls.py`:

```python
from django.urls import path

from etqan.integrations.api import views

app_name = "integrations"
urlpatterns = [
    path("", views.IntegrationListView.as_view(), name="list"),
    path("<slug:service>/", views.IntegrationView.as_view(), name="account"),
    path("<slug:service>/test/", views.IntegrationTestView.as_view(), name="test"),
]
```

In `backend/config/api_router.py`, replace

```python
    path("access/", include("etqan.access.api.urls")),
    # Parallel phases (spec 2026-10-02 §6.1): add a phase's routes under its own marker.
```

with

```python
    path("access/", include("etqan.access.api.urls")),
    # Integrations (spec 2026-10-07; not a phase): the academy's outside-service accounts.
    path("integrations/", include("etqan.integrations.api.urls")),
    # Parallel phases (spec 2026-10-02 §6.1): add a phase's routes under its own marker.
```

In `backend/etqan/access/registry.py`, replace

```python
    Resource("role", "Roles", "الأدوار", EDIT, verbs=ROLE_VERBS),
    # Parallel phases (spec 2026-10-02 §6.1): a phase's new resources go
```

with

```python
    Resource("role", "Roles", "الأدوار", EDIT, verbs=ROLE_VERBS),
    # Integrations (spec 2026-10-07 §6; not a phase): Settings → Integrations.
    Resource("integration", "Integrations", "التكاملات", ("view", "update")),
    # Parallel phases (spec 2026-10-02 §6.1): a phase's new resources go
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DJ pytest etqan/integrations etqan/access etqan/platform -q && $DJ lint-imports`
Expected: all pass, including `test_every_route_declares_its_code_or_is_named_exempt`, the staff/admin route matrix and `test_every_phase_has_its_marker_in_order`.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/integrations config/api_router.py etqan/access
git -C backend commit -m "feat(integrations): Settings → Integrations API and integration codes" -m "$TRAILER"
```

---

### Task 6: Etqan's default accounts in the platform admin

**Files:**
- Create: `backend/etqan/integrations/admin.py`, `backend/etqan/integrations/tests/test_admin.py`

**Interfaces:**
- Consumes: `services.apply_platform_change`, `services.probe(service, scope=services.ETQAN, tester_email=…)`, `etqan.platform.exceptions.EtqanError` (`.message`, optional `.field`).
- Produces: `PlatformAccountAdmin` registered on `django.contrib.admin.site` (served only by `config/urls_public.py`, the bare base domain): list of the five defaults; change form with `enabled`, `config` (JSON), write-only `secret` (JSON object of text) and `clear_secret`; read-only secret status and last test; action `test_accounts`; no add, no delete.

- [ ] **Step 1: Write the failing test**

`backend/etqan/integrations/tests/test_admin.py`:

```python
"""Spec §6: Etqan's default accounts in the platform admin, on the bare
base domain only; secrets are write-only (Review Focus 1)."""

import json

import pytest
from django.db import connection

from etqan.identity.models import User
from etqan.integrations import providers
from etqan.integrations import services
from etqan.integrations.models import PlatformAccount
from etqan.integrations.models import Service
from etqan.integrations.tests.conftest import FakeEmail

pytestmark = pytest.mark.django_db
PUBLIC_HOST = "etqan.localhost"
LIST = "/admin/integrations/platformaccount/"
ETQAN_SMTP = {
    "host": "smtp.etqan.test",
    "port": 587,
    "username": "noreply@etqan.test",
    "security": "starttls",
    "from_address": "noreply@etqan.test",
}


@pytest.fixture
def staff_client(client):
    connection.set_schema_to_public()
    staff = User.objects.create_superuser(email="ops@etqan.test", password="pw-12345678")
    client.force_login(staff)
    return client


def change_url(service: str) -> str:
    pk = PlatformAccount.objects.get(service=service).pk
    return f"{LIST}{pk}/change/"


def save(client, service: str, **data):
    return client.post(
        change_url(service), {**data, "_save": "Save"}, HTTP_HOST=PUBLIC_HOST
    )


def test_the_list_shows_the_five_defaults(staff_client):
    resp = staff_client.get(LIST, HTTP_HOST=PUBLIC_HOST)
    assert resp.status_code == 200
    page = resp.content.decode()
    for _, label in Service.choices:
        assert f">{label}<" in page


def test_the_admin_is_not_served_on_an_academy_host(client):
    assert client.get(LIST, HTTP_HOST="testserver").status_code == 404


def test_etqan_gives_email_its_own_server_and_the_password_never_comes_back(
    staff_client,
):
    resp = save(
        staff_client,
        "email",
        enabled="on",
        config=json.dumps(ETQAN_SMTP),
        secret=json.dumps({"password": "etqan-smtp-secret-1999"}),
    )
    assert resp.status_code == 302, resp.content[:2000]
    account = PlatformAccount.objects.get(service="email")
    assert account.config == ETQAN_SMTP
    assert services.read_secrets(account.secret_enc) == {
        "password": "etqan-smtp-secret-1999"
    }
    page = staff_client.get(change_url("email"), HTTP_HOST=PUBLIC_HOST)
    text = page.content.decode()
    assert "etqan-smtp-secret-1999" not in text
    assert account.secret_enc not in text
    assert "Set · ••••1999" in text


def test_a_bad_field_is_shown_on_the_form(staff_client):
    resp = save(
        staff_client,
        "email",
        enabled="on",
        config=json.dumps({**ETQAN_SMTP, "port": 0}),
        secret=json.dumps({"password": "etqan-smtp-secret-1999"}),
    )
    assert resp.status_code == 200
    assert "Enter a port from 1 to 65535." in resp.content.decode()
    assert PlatformAccount.objects.get(service="email").config == {}


def test_the_secret_must_be_a_json_object_of_text(staff_client):
    resp = save(staff_client, "email", enabled="on", config="{}", secret="not json")
    assert resp.status_code == 200
    assert "Enter a JSON object of text values." in resp.content.decode()


def test_a_service_not_built_yet_cannot_be_switched_on(staff_client):
    resp = save(staff_client, "whatsapp", enabled="on", config="{}")
    assert resp.status_code == 200
    assert "cannot be switched on before it is built" in resp.content.decode()
    assert PlatformAccount.objects.get(service="whatsapp").enabled is False


def test_the_test_action_probes_and_reports(staff_client, monkeypatch):
    fake = FakeEmail()
    monkeypatch.setitem(providers.PROVIDERS, "email", fake)
    account = PlatformAccount.objects.get(service="email")
    resp = staff_client.post(
        LIST,
        {"action": "test_accounts", "_selected_action": [account.pk]},
        HTTP_HOST=PUBLIC_HOST,
        follow=True,
    )
    assert "email: test sent to ops@etqan.test." in resp.content.decode()
    assert fake.probed[0]["to"] == "ops@etqan.test"
    assert PlatformAccount.objects.get(service="email").last_test_ok is True


def test_a_failed_test_is_reported_with_its_reason(staff_client):
    account = PlatformAccount.objects.get(service="whatsapp")
    resp = staff_client.post(
        LIST,
        {"action": "test_accounts", "_selected_action": [account.pk]},
        HTTP_HOST=PUBLIC_HOST,
        follow=True,
    )
    assert (
        "whatsapp: the test failed: Not available until WhatsApp messaging "
        "(phase B5c) ships."
    ) in resp.content.decode()


def test_there_is_no_adding(staff_client):
    assert staff_client.get(f"{LIST}add/", HTTP_HOST=PUBLIC_HOST).status_code == 403
```

- [ ] **Step 2: Run it to see it fail**

Run: `$DJ pytest etqan/integrations/tests/test_admin.py -q`
Expected: failures with `404` on `/admin/integrations/platformaccount/` (the model is not registered).

- [ ] **Step 3: Implement**

`backend/etqan/integrations/admin.py`:

```python
"""Spec §6: Etqan's default accounts in the platform admin (the bare base
domain only: `config/urls_public.py`). Secrets are write-only: the form
takes a JSON object and never renders it back."""

import json

from django import forms
from django.contrib import admin
from django.contrib import messages

from etqan.integrations import services
from etqan.integrations.models import PlatformAccount
from etqan.platform.exceptions import EtqanError

# A service error's field, as this form names it.
FORM_FIELDS = {"password": "secret"}


class PlatformAccountForm(forms.ModelForm):
    secret = forms.CharField(
        required=False,
        widget=forms.PasswordInput(render_value=False),
        help_text=(
            'Write-only. A JSON object of text, e.g. {"password": "…"}; '
            "blank keeps what is stored."
        ),
    )
    clear_secret = forms.BooleanField(required=False, label="Remove the stored secrets")

    class Meta:
        model = PlatformAccount
        fields = ["enabled", "config"]

    def clean_secret(self) -> dict | None:
        text = self.cleaned_data["secret"].strip()
        if not text:
            return None
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            value = None
        if not isinstance(value, dict) or not all(
            isinstance(key, str) and isinstance(item, str)
            for key, item in value.items()
        ):
            raise forms.ValidationError("Enter a JSON object of text values.")
        return value

    def clean(self):
        cleaned = super().clean()
        if self.errors:
            return cleaned
        try:
            cleaned["config"] = services.apply_platform_change(
                self.instance,
                enabled=bool(cleaned.get("enabled")),
                config=cleaned.get("config") or {},
                new_secrets=cleaned.get("secret"),
                clear_secrets=bool(cleaned.get("clear_secret")),
            )
        except EtqanError as exc:
            field = getattr(exc, "field", None)
            target = FORM_FIELDS.get(field, field)
            if target not in self.fields:
                target = "config" if field else None
            self.add_error(target, exc.message)
        return cleaned


@admin.register(PlatformAccount)
class PlatformAccountAdmin(admin.ModelAdmin):
    form = PlatformAccountForm
    list_display = ["service", "enabled", "secret_status", "last_test_at", "last_test_ok"]
    fields = [
        "service",
        "enabled",
        "config",
        "secret",
        "clear_secret",
        "secret_status",
        "last_test_at",
        "last_test_ok",
        "last_test_error",
        "updated_at",
    ]
    readonly_fields = [
        "service",
        "secret_status",
        "last_test_at",
        "last_test_ok",
        "last_test_error",
        "updated_at",
    ]
    actions = ["test_accounts"]

    def has_add_permission(self, request):
        # The five rows come from the migration (plan D6).
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    @admin.display(description="Secrets")
    def secret_status(self, obj) -> str:
        if not obj.secret_enc:
            return "Not set"
        return f"Set · ••••{obj.secret_last4}" if obj.secret_last4 else "Set"

    @admin.action(description="Test the selected accounts")
    def test_accounts(self, request, queryset):
        for account in queryset:
            try:
                tested = services.probe(
                    account.service,
                    scope=services.ETQAN,
                    tester_email=request.user.email,
                )
            except EtqanError as exc:
                self.message_user(
                    request, f"{account.service}: {exc.message}", messages.ERROR
                )
                continue
            if tested.last_test_ok:
                self.message_user(
                    request,
                    f"{account.service}: test sent to {request.user.email}.",
                    messages.SUCCESS,
                )
            else:
                self.message_user(
                    request,
                    f"{account.service}: the test failed: {tested.last_test_error}",
                    messages.WARNING,
                )
```

- [ ] **Step 4: Run the test to see it pass**

Run: `$DJ pytest etqan/integrations/tests/test_admin.py etqan/tenants/tests/test_admin.py -q && $DJ lint-imports`
Expected: all pass.

- [ ] **Step 5: Format and commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .'
git -C backend add etqan/integrations
git -C backend commit -m "feat(integrations): Etqan default accounts in the platform admin" -m "$TRAILER"
```

---

### Task 7: Dashboard data layer and strings

**Files:**
- Create: `dashboard/src/features/integrations/schemas.ts`, `dashboard/src/features/integrations/api.ts`, `dashboard/src/features/integrations/queries.ts`, `dashboard/src/features/integrations/errors.ts`, `dashboard/src/features/integrations/index.ts`, `dashboard/src/features/integrations/schemas.test.ts`, `dashboard/src/features/integrations/api.test.ts`, `dashboard/src/features/integrations/queries.test.tsx`, `dashboard/src/features/integrations/errors.test.ts`, `dashboard/src/test/integrations-fixtures.ts`, `dashboard/src/locales/en/integrations.json`, `dashboard/src/locales/ar/integrations.json`

**Interfaces:**
- Consumes: `api` from `@/lib/api` (base `/api/v1/`), `parseApiError` from `@/features/identity/api`, `errorText` from `@/lib/form-errors`; the API of Task 5.
- Produces: types `Service`, `Using`, `DefaultStatus`, `EmailSecurity`, `OwnAccount`, `IntegrationCard`, `IntegrationsList`, `EmailConfig`, `EmailBody`, `EmailForm`; `SERVICES`, `EMAIL_SECURITY`, `emailFormSchema`, `emailDefaults(own: OwnAccount | null): EmailForm`, `emailBody(values: EmailForm): EmailBody`; `integrationsApi.list(): Promise<IntegrationsList>`, `.connect({ service, body }): Promise<IntegrationCard>`, `.disconnect(service): Promise<IntegrationCard>`, `.probe(service): Promise<IntegrationCard>`; `integrationsKey`, `useIntegrations()`, `useIntegrationsMutation(write)`; `integrationsErrorText(error, t): string`; fixtures `ownEmail(overrides)`, `card(service, overrides)`, `integrations(emailOverrides)`; locale area `integrations`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/test/integrations-fixtures.ts`:

```ts
import type {
	IntegrationCard,
	IntegrationsList,
	OwnAccount,
	Service,
} from "@/features/integrations/schemas";

export function ownEmail(overrides: Partial<OwnAccount> = {}): OwnAccount {
	return {
		enabled: true,
		config: {
			host: "smtp.noor.test",
			port: 587,
			username: "mailer@noor.test",
			security: "starttls",
			from_address: "office@noor.test",
		},
		secret_last4: "1234",
		last_test_at: "2026-10-07T08:00:00Z",
		last_test_ok: true,
		last_test_error: "",
		updated_at: "2026-10-07T07:00:00Z",
		...overrides,
	};
}

export function card(
	service: Service,
	overrides: Partial<IntegrationCard> = {},
): IntegrationCard {
	const email = service === "email";
	return {
		service,
		using: email ? "etqan" : "none",
		default_status: email ? "available" : "disabled",
		connectable: email,
		own: null,
		...overrides,
	};
}

/** The five cards as a fresh academy sees them; `email` changes the email card. */
export function integrations(
	email: Partial<IntegrationCard> = {},
): IntegrationsList {
	return {
		services: [
			card("whatsapp"),
			card("email", email),
			card("payments"),
			card("video"),
			card("ai"),
		],
	};
}
```

`dashboard/src/features/integrations/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { ownEmail } from "@/test/integrations-fixtures";
import {
	type EmailForm,
	emailBody,
	emailDefaults,
	emailFormSchema,
} from "./schemas";

const valid: EmailForm = {
	host: "smtp.noor.test",
	port: "587",
	security: "starttls",
	username: "",
	password: "",
	from_address: "office@noor.test",
	enabled: true,
};

describe("emailFormSchema", () => {
	it("accepts a server with no user name", () => {
		expect(emailFormSchema.safeParse(valid).success).toBe(true);
	});

	it.each([
		["port", "0"],
		["port", "70000"],
		["port", "58a"],
		["host", ""],
		["from_address", "nope"],
	])("refuses a bad %s (%s)", (field, value) => {
		const result = emailFormSchema.safeParse({ ...valid, [field]: value });
		expect(result.success).toBe(false);
		expect(result.error?.issues[0].path).toEqual([field]);
	});
});

describe("emailBody", () => {
	it("sends the port as a number and leaves a blank password out", () => {
		expect(emailBody(valid)).toEqual({
			host: "smtp.noor.test",
			port: 587,
			security: "starttls",
			username: "",
			from_address: "office@noor.test",
			enabled: true,
		});
	});

	it("sends a typed password", () => {
		expect(emailBody({ ...valid, password: "app-password-1234" }).password).toBe(
			"app-password-1234",
		);
	});
});

describe("emailDefaults", () => {
	it("fills the form from the own account, never the password", () => {
		expect(emailDefaults(ownEmail({ enabled: false }))).toEqual({
			host: "smtp.noor.test",
			port: "587",
			security: "starttls",
			username: "mailer@noor.test",
			password: "",
			from_address: "office@noor.test",
			enabled: false,
		});
	});

	it("starts a new account on port 587 with STARTTLS, switched on", () => {
		expect(emailDefaults(null)).toEqual({
			host: "",
			port: "587",
			security: "starttls",
			username: "",
			password: "",
			from_address: "",
			enabled: true,
		});
	});
});
```

`dashboard/src/features/integrations/api.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { integrationsApi } from "./api";

const body = {
	host: "smtp.noor.test",
	port: 587,
	security: "starttls" as const,
	username: "",
	from_address: "office@noor.test",
	enabled: true,
};

describe("integrationsApi", () => {
	afterEach(() => vi.restoreAllMocks());

	it("lists the services", async () => {
		const get = vi
			.spyOn(api, "get")
			.mockResolvedValue({ data: { services: [] } } as never);
		expect(await integrationsApi.list()).toEqual({ services: [] });
		expect(get).toHaveBeenCalledWith("integrations/");
	});

	it("connects with a PUT on the service", async () => {
		const put = vi.spyOn(api, "put").mockResolvedValue({ data: {} } as never);
		await integrationsApi.connect({ service: "email", body });
		expect(put).toHaveBeenCalledWith("integrations/email/", body);
	});

	it("disconnects with a DELETE and tests with a POST", async () => {
		const del = vi.spyOn(api, "delete").mockResolvedValue({ data: {} } as never);
		const post = vi.spyOn(api, "post").mockResolvedValue({ data: {} } as never);
		await integrationsApi.disconnect("email");
		await integrationsApi.probe("email");
		expect(del).toHaveBeenCalledWith("integrations/email/");
		expect(post).toHaveBeenCalledWith("integrations/email/test/");
	});
});
```

`dashboard/src/features/integrations/queries.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { integrations } from "@/test/integrations-fixtures";
import { integrationsApi } from "./api";
import {
	integrationsKey,
	useIntegrations,
	useIntegrationsMutation,
} from "./queries";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		integrationsApi: {
			...actual.integrationsApi,
			list: vi.fn(),
			disconnect: vi.fn(),
		},
	};
});

function wrapper() {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	const spy = vi.spyOn(client, "invalidateQueries");
	const wrap = ({ children }: { children: ReactNode }) => (
		<QueryClientProvider client={client}>{children}</QueryClientProvider>
	);
	return { wrap, spy };
}

describe("integrations queries", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads the list", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue(integrations());
		const { wrap } = wrapper();
		const { result } = renderHook(() => useIntegrations(), { wrapper: wrap });
		await waitFor(() => expect(result.current.data?.services).toHaveLength(5));
	});

	it("refreshes the list after a write", async () => {
		vi.mocked(integrationsApi.disconnect).mockResolvedValue(
			integrations().services[1],
		);
		const { wrap, spy } = wrapper();
		const { result } = renderHook(
			() => useIntegrationsMutation(integrationsApi.disconnect),
			{ wrapper: wrap },
		);
		await act(() => result.current.mutateAsync("email"));
		expect(integrationsApi.disconnect).toHaveBeenCalledWith("email");
		expect(spy).toHaveBeenCalledWith({ queryKey: integrationsKey });
	});
});
```

`dashboard/src/features/integrations/errors.test.ts`:

```ts
import { AxiosError } from "axios";
import { describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { integrationsErrorText } from "./errors";

const fail = (status: number, data: unknown) =>
	new AxiosError("x", String(status), undefined, undefined, {
		status,
		data,
	} as never);

describe("integrationsErrorText", () => {
	it("words an integrations code from integrations.json", () => {
		expect(
			integrationsErrorText(
				fail(400, { detail: "x", code: "integrations.not_connected" }),
				i18n.t,
			),
		).toBe("Connect an account first.");
	});

	it("words a server without a secrets key", () => {
		expect(
			integrationsErrorText(
				fail(503, { detail: "x", code: "gateways.no_key" }),
				i18n.t,
			),
		).toBe("Keys cannot be stored on this server right now. Contact Etqan.");
	});

	it("falls back to the server's own sentence", () => {
		expect(
			integrationsErrorText(fail(400, { detail: "Something else." }), i18n.t),
		).toBe("Something else.");
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DASH pnpm vitest run src/features/integrations`
Expected: every file fails to resolve `./schemas`, `./api`, `./queries` or `./errors` (`Failed to resolve import`).

- [ ] **Step 3: Implement**

`dashboard/src/features/integrations/schemas.ts`:

```ts
import { z } from "zod";

// Spec 2026-10-07 §3.1, in the spec's order.
export const SERVICES = ["whatsapp", "email", "payments", "video", "ai"] as const;
export type Service = (typeof SERVICES)[number];
export type Using = "academy" | "etqan" | "none";
export type DefaultStatus =
	| "available"
	| "disabled"
	| "feature_off"
	| "suspended";
export const EMAIL_SECURITY = ["starttls", "ssl", "none"] as const;
export type EmailSecurity = (typeof EMAIL_SECURITY)[number];

/** The academy's own account as the API shows it: never a secret (plan D15). */
export interface OwnAccount {
	enabled: boolean;
	config: Record<string, unknown>;
	secret_last4: string;
	last_test_at: string | null;
	last_test_ok: boolean | null;
	last_test_error: string;
	updated_at: string;
}

export interface IntegrationCard {
	service: Service;
	using: Using;
	default_status: DefaultStatus;
	connectable: boolean;
	own: OwnAccount | null;
}

export interface IntegrationsList {
	services: IntegrationCard[];
}

export interface EmailConfig {
	host: string;
	port: number;
	username: string;
	security: EmailSecurity;
	from_address: string;
}

export interface EmailBody extends EmailConfig {
	enabled: boolean;
	/** Left out to keep the stored one (plan D15). */
	password?: string;
}

const E = "integrations.errors";

export const emailFormSchema = z.object({
	host: z
		.string()
		.trim()
		.min(1, `${E}.hostRequired`)
		.max(253, `${E}.tooLong`),
	port: z
		.string()
		.trim()
		.regex(/^\d{1,5}$/, `${E}.port`)
		.refine((value) => Number(value) >= 1 && Number(value) <= 65535, `${E}.port`),
	security: z.enum(EMAIL_SECURITY),
	username: z.string().trim().max(254, `${E}.tooLong`),
	password: z.string().max(512, `${E}.tooLong`),
	from_address: z.string().trim().pipe(z.email(`${E}.fromAddress`)),
	enabled: z.boolean(),
});
export type EmailForm = z.infer<typeof emailFormSchema>;

export function emailDefaults(own: OwnAccount | null): EmailForm {
	const config = (own?.config ?? {}) as Partial<EmailConfig>;
	return {
		host: config.host ?? "",
		port: config.port === undefined ? "587" : String(config.port),
		security: config.security ?? "starttls",
		username: config.username ?? "",
		password: "",
		from_address: config.from_address ?? "",
		enabled: own?.enabled ?? true,
	};
}

export function emailBody(values: EmailForm): EmailBody {
	const body: EmailBody = {
		host: values.host.trim(),
		port: Number(values.port),
		security: values.security,
		username: values.username.trim(),
		from_address: values.from_address.trim(),
		enabled: values.enabled,
	};
	if (values.password) body.password = values.password;
	return body;
}
```

`dashboard/src/features/integrations/api.ts`:

```ts
import { api } from "@/lib/api";
import type {
	EmailBody,
	IntegrationCard,
	IntegrationsList,
	Service,
} from "./schemas";

const I = "integrations/";

export const integrationsApi = {
	list: async () => (await api.get<IntegrationsList>(I)).data,
	connect: async ({ service, body }: { service: Service; body: EmailBody }) =>
		(await api.put<IntegrationCard>(`${I}${service}/`, body)).data,
	disconnect: async (service: Service) =>
		(await api.delete<IntegrationCard>(`${I}${service}/`)).data,
	probe: async (service: Service) =>
		(await api.post<IntegrationCard>(`${I}${service}/test/`)).data,
};
```

`dashboard/src/features/integrations/queries.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { integrationsApi } from "./api";

/** Every integrations query lives under this key. */
export const integrationsKey = ["integrations"] as const;

export function useIntegrations() {
	return useQuery({ queryKey: integrationsKey, queryFn: integrationsApi.list });
}

/** An integrations write: the cards are read again afterwards. */
export function useIntegrationsMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () => qc.invalidateQueries({ queryKey: integrationsKey }),
	});
}
```

`dashboard/src/features/integrations/errors.ts`:

```ts
import type { TFunction } from "i18next";
import { parseApiError } from "@/features/identity/api";
import { errorText } from "@/lib/form-errors";

const PREFIX = "integrations.";
/** The 503 codes of a server that cannot store secrets (platform.secrets). */
const NO_SECRETS = new Set(["gateways.no_key", "gateways.bad_key"]);

/** An integrations error code's own wording (integrations.json), else the shared one. */
export function integrationsErrorText(error: unknown, t: TFunction): string {
	const code = parseApiError(error).code;
	if (code && NO_SECRETS.has(code)) {
		return t("integrations.errors.secrets_unavailable");
	}
	if (code?.startsWith(PREFIX)) {
		return t(`integrations.errors.${code.slice(PREFIX.length)}`);
	}
	return errorText(error, t);
}
```

`dashboard/src/features/integrations/index.ts`:

```ts
export { integrationsApi } from "./api";
export { integrationsErrorText } from "./errors";
export * from "./queries";
export * from "./schemas";
```

`dashboard/src/locales/en/integrations.json`:

```json
{
	"nav": {
		"title": "Integrations"
	},
	"page": {
		"subtitle": "The outside services your academy uses. Each works on Etqan's default account until you connect your own."
	},
	"using": {
		"academy": "Using your own account",
		"etqan": "Using Etqan's default",
		"none": "Not set up"
	},
	"default": {
		"available": "Etqan's default account is available to your academy.",
		"disabled": "Etqan does not offer a default account for this yet.",
		"feature_off": "This feature is switched off for your academy.",
		"suspended": "Etqan's default accounts are suspended for your academy. Contact Etqan."
	},
	"services": {
		"whatsapp": {
			"title": "WhatsApp",
			"body": "Messages to families on WhatsApp.",
			"availableWhen": "Connecting your own WhatsApp number will be available when WhatsApp messaging ships."
		},
		"email": {
			"title": "Email",
			"body": "Every email the academy sends: invitations, password resets and notifications."
		},
		"payments": {
			"title": "Online payments",
			"body": "Families pay invoices online.",
			"availableWhen": "Etqan's Stripe Connect default will be available when it ships. Your own Stripe or PayPal keys are set in Payment gateways.",
			"manage": "Open Payment gateways"
		},
		"video": {
			"title": "Video meetings",
			"body": "Zoom meetings for sessions.",
			"availableWhen": "Connecting your own Zoom account will be available when Zoom meetings ship."
		},
		"ai": {
			"title": "AI",
			"body": "The AI assistant and AI reports.",
			"availableWhen": "Connecting your own Claude API key will be available when the AI features ship."
		}
	},
	"own": {
		"connected": "Connected",
		"connectedHint": "Connected · ••••{{last4}}",
		"switchedOff": "Your own account is switched off, so Etqan's default is used if available."
	},
	"test": {
		"never": "Not tested yet",
		"ok": "Tested OK on {{date}}",
		"failed": "Test failed on {{date}}: {{error}}",
		"okToast": "Test email sent. Check your inbox.",
		"failedToast": "The test failed. See the reason on the card."
	},
	"actions": {
		"connect": "Connect your own account",
		"edit": "Edit",
		"test": "Send a test",
		"disconnect": "Disconnect",
		"save": "Save",
		"cancel": "Cancel"
	},
	"disconnect": {
		"title": "Disconnect your email account?",
		"body": "Email will go out on Etqan's default account again, if it is available to your academy.",
		"confirm": "Disconnect",
		"done": "Disconnected."
	},
	"saved": "Saved.",
	"email": {
		"host": "SMTP server",
		"port": "Port",
		"security": "Security",
		"securities": {
			"starttls": "STARTTLS",
			"ssl": "SSL/TLS",
			"none": "None"
		},
		"username": "User name",
		"password": "Password",
		"passwordKept": "Saved — leave blank to keep it",
		"fromAddress": "From address",
		"enabled": "Send the academy's email through this account",
		"providersHint": "Postmark, Amazon SES and SendGrid all give you SMTP settings to enter here."
	},
	"errors": {
		"hostRequired": "Enter the SMTP server.",
		"port": "Enter a port from 1 to 65535.",
		"fromAddress": "Enter a valid email address.",
		"tooLong": "This is too long.",
		"passwordRequired": "Enter the password.",
		"not_available": "This service cannot be connected yet.",
		"not_connected": "Connect an account first.",
		"no_tester_email": "Your account has no email address to send the test to.",
		"secrets_unavailable": "Keys cannot be stored on this server right now. Contact Etqan."
	}
}
```

`dashboard/src/locales/ar/integrations.json`:

```json
{
	"nav": {
		"title": "التكاملات"
	},
	"page": {
		"subtitle": "الخدمات الخارجية التي تستخدمها أكاديميتك. تعمل كل خدمة على حساب إتقان الافتراضي حتى تربط حسابك الخاص."
	},
	"using": {
		"academy": "تستخدم حسابك الخاص",
		"etqan": "تستخدم حساب إتقان الافتراضي",
		"none": "غير مُعدّة"
	},
	"default": {
		"available": "حساب إتقان الافتراضي متاح لأكاديميتك.",
		"disabled": "لا تقدّم إتقان حسابًا افتراضيًا لهذه الخدمة بعد.",
		"feature_off": "هذه الميزة متوقفة لأكاديميتك.",
		"suspended": "حسابات إتقان الافتراضية موقوفة لأكاديميتك. تواصل مع إتقان."
	},
	"services": {
		"whatsapp": {
			"title": "واتساب",
			"body": "رسائل إلى العائلات عبر واتساب.",
			"availableWhen": "سيتاح ربط رقم واتساب الخاص بك عند إطلاق رسائل واتساب."
		},
		"email": {
			"title": "البريد الإلكتروني",
			"body": "كل بريد ترسله الأكاديمية: الدعوات واستعادة كلمات المرور والإشعارات."
		},
		"payments": {
			"title": "الدفع الإلكتروني",
			"body": "تدفع العائلات الفواتير عبر الإنترنت.",
			"availableWhen": "سيتاح حساب Stripe Connect الافتراضي من إتقان عند إطلاقه. تُضبط مفاتيح Stripe أو PayPal الخاصة بك في بوابات الدفع.",
			"manage": "فتح بوابات الدفع"
		},
		"video": {
			"title": "الاجتماعات المرئية",
			"body": "اجتماعات Zoom للحصص.",
			"availableWhen": "سيتاح ربط حساب Zoom الخاص بك عند إطلاق اجتماعات Zoom."
		},
		"ai": {
			"title": "الذكاء الاصطناعي",
			"body": "المساعد الذكي وتقارير الذكاء الاصطناعي.",
			"availableWhen": "سيتاح ربط مفتاح Claude API الخاص بك عند إطلاق ميزات الذكاء الاصطناعي."
		}
	},
	"own": {
		"connected": "متصل",
		"connectedHint": "متصل · ••••{{last4}}",
		"switchedOff": "حسابك الخاص متوقف، لذا يُستخدم حساب إتقان الافتراضي إن كان متاحًا."
	},
	"test": {
		"never": "لم يُختبر بعد",
		"ok": "نجح الاختبار في {{date}}",
		"failed": "فشل الاختبار في {{date}}: {{error}}",
		"okToast": "أُرسلت رسالة الاختبار. تحقّق من بريدك.",
		"failedToast": "فشل الاختبار. السبب ظاهر على البطاقة."
	},
	"actions": {
		"connect": "اربط حسابك الخاص",
		"edit": "تعديل",
		"test": "إرسال اختبار",
		"disconnect": "فصل",
		"save": "حفظ",
		"cancel": "إلغاء"
	},
	"disconnect": {
		"title": "فصل حساب بريدك الإلكتروني؟",
		"body": "سيُرسل البريد عبر حساب إتقان الافتراضي مجددًا إن كان متاحًا لأكاديميتك.",
		"confirm": "فصل",
		"done": "تم الفصل."
	},
	"saved": "تم الحفظ.",
	"email": {
		"host": "خادم SMTP",
		"port": "المنفذ",
		"security": "الحماية",
		"securities": {
			"starttls": "STARTTLS",
			"ssl": "SSL/TLS",
			"none": "بدون"
		},
		"username": "اسم المستخدم",
		"password": "كلمة المرور",
		"passwordKept": "محفوظة — اتركها فارغة للإبقاء عليها",
		"fromAddress": "عنوان المُرسِل",
		"enabled": "أرسل بريد الأكاديمية عبر هذا الحساب",
		"providersHint": "تمنحك Postmark وAmazon SES وSendGrid إعدادات SMTP لإدخالها هنا."
	},
	"errors": {
		"hostRequired": "أدخل خادم SMTP.",
		"port": "أدخل منفذًا من 1 إلى 65535.",
		"fromAddress": "أدخل عنوان بريد صحيحًا.",
		"tooLong": "هذا طويل جدًا.",
		"passwordRequired": "أدخل كلمة المرور.",
		"not_available": "لا يمكن ربط هذه الخدمة بعد.",
		"not_connected": "اربط حسابًا أولًا.",
		"no_tester_email": "ليس لحسابك عنوان بريد لإرسال الاختبار إليه.",
		"secrets_unavailable": "لا يمكن حفظ المفاتيح على هذا الخادم الآن. تواصل مع إتقان."
	}
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DASH pnpm vitest run src/features/integrations src/locales`
Expected: all pass (the locales suite confirms en and ar have the same keys).

- [ ] **Step 5: Format and commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/integrations src/test/integrations-fixtures.ts src/locales/en/integrations.json src/locales/ar/integrations.json
git -C dashboard commit -m "feat(integrations): data layer, error wording and strings" -m "$TRAILER"
```

---

### Task 8: Settings → Integrations page, route and nav

**Files:**
- Create: `dashboard/src/features/integrations/IntegrationsPage.tsx`, `dashboard/src/features/integrations/EmailAccountForm.tsx`, `dashboard/src/features/integrations/IntegrationsPage.test.tsx`, `dashboard/src/routes/_authed/settings.integrations.tsx`
- Modify: `dashboard/src/features/integrations/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/permissions.test.ts`, `dashboard/src/routeTree.gen.ts` (generated)

**Interfaces:**
- Consumes: Task 7's exports; `useCan`, `useHasFeature`, `CanProvider` (`@/features/identity/permissions`); `requireOffice`; `usePageTitle`; `@/ui` (`Card`, `StatusChip`, `AlertDialog…`, `Field`, `Input`, `Select`, `Checkbox`, `SubmitButton`, `toast`); `useFieldError`; `parseApiError`.
- Produces: `IntegrationsPage()` and `dayOf(iso: string, language: string): string` exported from `IntegrationsPage.tsx`; `EmailAccountForm({ own, onDone })`; route `/_authed/settings/integrations` with `staticData: { permission: "integration.view" }`; nav item `/settings/integrations` (`integrations.nav.title`, group `settings`, code `integration.view`).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/integrations/IntegrationsPage.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { integrations, ownEmail } from "@/test/integrations-fixtures";
import { renderWithRouter } from "@/test/render";
import { integrationsApi } from "./api";
import { dayOf, IntegrationsPage } from "./IntegrationsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		integrationsApi: {
			list: vi.fn(),
			connect: vi.fn(),
			disconnect: vi.fn(),
			probe: vi.fn(),
		},
	};
});

const connected = () => integrations({ using: "academy", own: ownEmail() });
const refused = (status: number, data: unknown) =>
	new AxiosError("x", String(status), undefined, undefined, {
		status,
		data,
	} as never);

describe("IntegrationsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(integrationsApi.list).mockResolvedValue(integrations());
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("shows one card per service and what each uses", async () => {
		renderWithRouter(<IntegrationsPage />);
		expect(await screen.findByText("WhatsApp")).toBeVisible();
		for (const title of ["Email", "Online payments", "Video meetings", "AI"]) {
			expect(screen.getByText(title)).toBeVisible();
		}
		expect(screen.getByText("Using Etqan's default")).toBeVisible();
		expect(screen.getAllByText("Not set up")).toHaveLength(4);
		expect(
			screen.getByText(
				"Connecting your own WhatsApp number will be available when WhatsApp messaging ships.",
			),
		).toBeVisible();
		expect(
			screen.getByRole("button", { name: "Connect your own account" }),
		).toBeVisible();
	});

	it("shows the own account's last four and last test, never the password", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		renderWithRouter(<IntegrationsPage />);
		expect(await screen.findByText("Connected · ••••1234")).toBeVisible();
		expect(screen.getByText("Using your own account")).toBeVisible();
		expect(
			screen.getByText(`Tested OK on ${dayOf("2026-10-07T08:00:00Z", "en")}`),
		).toBeVisible();
		await userEvent.setup().click(screen.getByRole("button", { name: "Edit" }));
		expect(screen.getByLabelText(/SMTP server/)).toHaveValue("smtp.noor.test");
		expect(screen.getByLabelText(/^Password/)).toHaveValue("");
		expect(screen.getByText("Saved — leave blank to keep it")).toBeVisible();
	});

	it("connects an email account with what was typed", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.connect).mockResolvedValue(connected().services[1]);
		renderWithRouter(<IntegrationsPage />);
		await user.click(
			await screen.findByRole("button", { name: "Connect your own account" }),
		);
		await user.type(screen.getByLabelText(/SMTP server/), "smtp.noor.test");
		await user.type(screen.getByLabelText(/User name/), "mailer@noor.test");
		await user.type(screen.getByLabelText(/^Password/), "app-password-1234");
		await user.type(screen.getByLabelText(/From address/), "office@noor.test");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(integrationsApi.connect).toHaveBeenCalledWith({
				service: "email",
				body: {
					host: "smtp.noor.test",
					port: 587,
					security: "starttls",
					username: "mailer@noor.test",
					password: "app-password-1234",
					from_address: "office@noor.test",
					enabled: true,
				},
			}),
		);
		expect(await screen.findByText("Saved.")).toBeVisible();
	});

	it("asks for the password of a new account with a user name", async () => {
		const user = userEvent.setup();
		renderWithRouter(<IntegrationsPage />);
		await user.click(
			await screen.findByRole("button", { name: "Connect your own account" }),
		);
		await user.type(screen.getByLabelText(/SMTP server/), "smtp.noor.test");
		await user.type(screen.getByLabelText(/User name/), "mailer@noor.test");
		await user.type(screen.getByLabelText(/From address/), "office@noor.test");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("Enter the password.")).toBeVisible();
		expect(integrationsApi.connect).not.toHaveBeenCalled();
	});

	it("keeps a blank password out of an edit", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		vi.mocked(integrationsApi.connect).mockResolvedValue(connected().services[1]);
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		const host = screen.getByLabelText(/SMTP server/);
		await user.clear(host);
		await user.type(host, "smtp2.noor.test");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(integrationsApi.connect).toHaveBeenCalled());
		const { body } = vi.mocked(integrationsApi.connect).mock.calls[0][0];
		expect(body.host).toBe("smtp2.noor.test");
		expect("password" in body).toBe(false);
	});

	it("refuses a port out of range before sending", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		const port = screen.getByLabelText(/^Port/);
		await user.clear(port);
		await user.type(port, "70000");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(
			await screen.findByText("Enter a port from 1 to 65535."),
		).toBeVisible();
		expect(integrationsApi.connect).not.toHaveBeenCalled();
	});

	it("puts a refused field on its field, and a refusal without one in words", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		vi.mocked(integrationsApi.connect)
			.mockRejectedValueOnce(
				refused(400, { host: ["The server name is not valid."] }),
			)
			.mockRejectedValueOnce(
				refused(503, { detail: "x", code: "gateways.no_key" }),
			);
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(
			await screen.findByText("The server name is not valid."),
		).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(
			await screen.findByText(
				"Keys cannot be stored on this server right now. Contact Etqan.",
			),
		).toBeVisible();
	});

	it("closes the form on Cancel", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		await user.click(screen.getByRole("button", { name: "Cancel" }));
		expect(screen.queryByLabelText(/SMTP server/)).toBeNull();
		expect(screen.getByRole("button", { name: "Edit" })).toBeVisible();
	});

	it("sends a test and says how it went", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		vi.mocked(integrationsApi.probe)
			.mockResolvedValueOnce(connected().services[1])
			.mockResolvedValueOnce({
				...connected().services[1],
				own: ownEmail({ last_test_ok: false, last_test_error: "Refused." }),
			});
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Send a test" }));
		expect(integrationsApi.probe).toHaveBeenCalledWith("email");
		expect(
			await screen.findByText("Test email sent. Check your inbox."),
		).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Send a test" }));
		expect(
			await screen.findByText("The test failed. See the reason on the card."),
		).toBeVisible();
	});

	it("shows why a test could not run", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		vi.mocked(integrationsApi.probe).mockRejectedValue(
			refused(400, { detail: "x", code: "integrations.no_tester_email" }),
		);
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Send a test" }));
		expect(
			await screen.findByText(
				"Your account has no email address to send the test to.",
			),
		).toBeVisible();
	});

	it("disconnects after confirming", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		vi.mocked(integrationsApi.disconnect).mockResolvedValue(
			integrations().services[1],
		);
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Disconnect" }));
		const dialog = await screen.findByRole("alertdialog");
		await user.click(within(dialog).getByRole("button", { name: "Disconnect" }));
		await waitFor(() =>
			expect(integrationsApi.disconnect).toHaveBeenCalledWith("email"),
		);
		expect(await screen.findByText("Disconnected.")).toBeVisible();
	});

	it("shows a failed test, a switched-off account and a suspended default", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue(
			integrations({
				using: "none",
				default_status: "suspended",
				own: ownEmail({
					enabled: false,
					last_test_ok: false,
					last_test_error: "Boom",
				}),
			}),
		);
		renderWithRouter(<IntegrationsPage />);
		expect(
			await screen.findByText(
				`Test failed on ${dayOf("2026-10-07T08:00:00Z", "en")}: Boom`,
			),
		).toBeVisible();
		expect(
			screen.getByText(
				"Your own account is switched off, so Etqan's default is used if available.",
			),
		).toBeVisible();
		expect(
			screen.getByText(
				"Etqan's default accounts are suspended for your academy. Contact Etqan.",
			),
		).toBeVisible();
	});

	it("says a short secret is connected and an untested account was never tested", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue(
			integrations({
				using: "academy",
				own: ownEmail({
					secret_last4: "",
					last_test_at: null,
					last_test_ok: null,
				}),
			}),
		);
		renderWithRouter(<IntegrationsPage />);
		expect(await screen.findByText("Connected")).toBeVisible();
		expect(screen.getByText("Not tested yet")).toBeVisible();
	});

	it("hides every action from staff without integration.update", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue(connected());
		renderWithRouter(
			<CanProvider me={staffMe("integration.view")}>
				<IntegrationsPage />
			</CanProvider>,
		);
		expect(await screen.findByText("Connected · ••••1234")).toBeVisible();
		expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Send a test" })).toBeNull();
	});

	it("links payments to Payment gateways only while online payments is on", async () => {
		const first = renderWithRouter(
			<CanProvider me={adminWith("online_payments")}>
				<IntegrationsPage />
			</CanProvider>,
		);
		expect(
			await screen.findByRole("link", { name: "Open Payment gateways" }),
		).toHaveAttribute("href", "/settings/gateways");
		first.unmount();
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<IntegrationsPage />
			</CanProvider>,
		);
		expect(await screen.findByText("Online payments")).toBeVisible();
		expect(
			screen.queryByRole("link", { name: "Open Payment gateways" }),
		).toBeNull();
	});

	it("says so when the list cannot load", async () => {
		vi.mocked(integrationsApi.list).mockRejectedValue(new Error("down"));
		renderWithRouter(<IntegrationsPage />);
		expect(await screen.findByText(i18n.t("errors.generic"))).toBeVisible();
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, in the expected `NAV_ITEMS` list of `"ships the grouped admin areas in order"`, replace

```ts
			"/settings/roles",
			"/billing/payments",
```

with

```ts
			"/settings/roles",
			// Integrations (spec 2026-10-07; not a phase)
			"/settings/integrations",
			"/billing/payments",
```

In `dashboard/src/routes/permissions.test.ts`, append:

```ts
// Integrations (spec 2026-10-07; not a phase)
describe("Settings → Integrations", () => {
	it("needs integration.view and belongs to no feature", () => {
		const route = (router.routesById as unknown as Record<string, AnyRoute>)[
			"/_authed/settings/integrations"
		];
		expect(route?.options.staticData).toEqual({
			permission: "integration.view",
		});
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `$DASH pnpm vitest run src/features/integrations/IntegrationsPage.test.tsx src/features/shell/nav.test.ts src/routes/permissions.test.ts`
Expected: `IntegrationsPage.test.tsx` fails to resolve `./IntegrationsPage`; `nav.test.ts` fails (`/settings/integrations` missing from `NAV_ITEMS`); `permissions.test.ts` fails (`route` is `undefined`).

- [ ] **Step 3: Implement**

`dashboard/src/features/integrations/EmailAccountForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { parseApiError } from "@/features/identity/api";
import { useFieldError } from "@/lib/field-error";
import {
	Alert,
	AlertDescription,
	Button,
	Checkbox,
	Field,
	Input,
	Select,
	SubmitButton,
	toast,
} from "@/ui";
import { integrationsApi } from "./api";
import { integrationsErrorText } from "./errors";
import { useIntegrationsMutation } from "./queries";
import {
	EMAIL_SECURITY,
	type EmailForm,
	emailBody,
	emailDefaults,
	emailFormSchema,
	type OwnAccount,
} from "./schemas";

const FIELDS: readonly (keyof EmailForm)[] = [
	"host",
	"port",
	"security",
	"username",
	"password",
	"from_address",
	"enabled",
];

/** Connect or edit the academy's own SMTP account (plan D3). The password is
 * write-only: blank on an edit keeps the stored one. */
export function EmailAccountForm({
	own,
	onDone,
}: {
	own: OwnAccount | null;
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const save = useIntegrationsMutation(integrationsApi.connect);
	const [failure, setFailure] = useState("");
	const {
		register,
		control,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<EmailForm>({
		resolver: zodResolver(emailFormSchema),
		defaultValues: emailDefaults(own),
	});
	const enabled = useController({ control, name: "enabled" });

	async function onSubmit(values: EmailForm) {
		setFailure("");
		if (!own && values.username && !values.password) {
			setError("password", { message: "integrations.errors.passwordRequired" });
			return;
		}
		try {
			await save.mutateAsync({ service: "email", body: emailBody(values) });
			toast({ description: t("integrations.saved"), variant: "success" });
			onDone();
		} catch (error) {
			let shown = false;
			for (const [key, message] of Object.entries(
				parseApiError(error).fieldErrors,
			)) {
				const name = FIELDS.find((field) => field === key);
				if (name) {
					setError(name, { message });
					shown = true;
				}
			}
			if (!shown) setFailure(integrationsErrorText(error, t));
		}
	}

	return (
		<form
			onSubmit={handleSubmit(onSubmit)}
			className="flex max-w-xl flex-col gap-4"
			noValidate
		>
			<p className="text-sm text-muted-foreground">
				{t("integrations.email.providersHint")}
			</p>
			<Field
				id="email_host"
				label={t("integrations.email.host")}
				error={fieldError(errors.host?.message)}
			>
				<Input dir="ltr" autoComplete="off" {...register("host")} />
			</Field>
			<Field
				id="email_port"
				label={t("integrations.email.port")}
				error={fieldError(errors.port?.message)}
			>
				<Input dir="ltr" inputMode="numeric" {...register("port")} />
			</Field>
			<Field
				id="email_security"
				label={t("integrations.email.security")}
				error={fieldError(errors.security?.message)}
			>
				<Select {...register("security")}>
					{EMAIL_SECURITY.map((value) => (
						<option key={value} value={value}>
							{t(`integrations.email.securities.${value}`)}
						</option>
					))}
				</Select>
			</Field>
			<Field
				id="email_username"
				label={t("integrations.email.username")}
				error={fieldError(errors.username?.message)}
			>
				<Input dir="ltr" autoComplete="off" {...register("username")} />
			</Field>
			<Field
				id="email_password"
				label={t("integrations.email.password")}
				error={fieldError(errors.password?.message)}
			>
				<Input
					dir="ltr"
					type="password"
					autoComplete="new-password"
					{...register("password")}
				/>
			</Field>
			{own ? (
				<p className="text-sm text-muted-foreground">
					{t("integrations.email.passwordKept")}
				</p>
			) : null}
			<Field
				id="email_from_address"
				label={t("integrations.email.fromAddress")}
				error={fieldError(errors.from_address?.message)}
			>
				<Input
					dir="ltr"
					type="email"
					autoComplete="off"
					{...register("from_address")}
				/>
			</Field>
			<label htmlFor="email_enabled" className="flex items-center gap-2 text-sm">
				<Checkbox
					id="email_enabled"
					checked={enabled.field.value}
					onCheckedChange={(value) => enabled.field.onChange(value === true)}
				/>
				{t("integrations.email.enabled")}
			</label>
			{failure ? (
				<Alert variant="destructive">
					<AlertDescription>{failure}</AlertDescription>
				</Alert>
			) : null}
			<div className="flex flex-wrap gap-2">
				<SubmitButton pending={isSubmitting}>
					{t("integrations.actions.save")}
				</SubmitButton>
				<Button type="button" variant="outline" onClick={onDone}>
					{t("integrations.actions.cancel")}
				</Button>
			</div>
		</form>
	);
}
```

`dashboard/src/features/integrations/IntegrationsPage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import type { TFunction } from "i18next";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import {
	Alert,
	AlertDescription,
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { integrationsApi } from "./api";
import { EmailAccountForm } from "./EmailAccountForm";
import { integrationsErrorText } from "./errors";
import { useIntegrations, useIntegrationsMutation } from "./queries";
import type { IntegrationCard, OwnAccount, Using } from "./schemas";

const TONE: Record<Using, "live" | "neutral" | "warning"> = {
	academy: "live",
	etqan: "neutral",
	none: "warning",
};

/** The day a test ran, in the reader's language. */
export function dayOf(iso: string, language: string): string {
	return new Intl.DateTimeFormat(language, { dateStyle: "medium" }).format(
		new Date(iso),
	);
}

function testLine(own: OwnAccount, t: TFunction, language: string): string {
	if (own.last_test_at === null || own.last_test_ok === null) {
		return t("integrations.test.never");
	}
	const date = dayOf(own.last_test_at, language);
	return own.last_test_ok
		? t("integrations.test.ok", { date })
		: t("integrations.test.failed", { date, error: own.last_test_error });
}

function OwnStatus({ own }: { own: OwnAccount }) {
	const { t, i18n } = useTranslation();
	return (
		<div className="flex flex-col gap-1 text-sm">
			<p>
				{own.secret_last4
					? t("integrations.own.connectedHint", { last4: own.secret_last4 })
					: t("integrations.own.connected")}
			</p>
			{own.enabled ? null : (
				<p className="text-muted-foreground">
					{t("integrations.own.switchedOff")}
				</p>
			)}
			<p
				className={
					own.last_test_ok === false
						? "text-destructive"
						: "text-muted-foreground"
				}
			>
				{testLine(own, t, i18n.language)}
			</p>
		</div>
	);
}

function Actions({
	card,
	onEdit,
}: {
	card: IntegrationCard;
	onEdit: () => void;
}) {
	const { t } = useTranslation();
	const probe = useIntegrationsMutation(integrationsApi.probe);
	const disconnect = useIntegrationsMutation(integrationsApi.disconnect);
	const [failure, setFailure] = useState("");

	async function runTest() {
		setFailure("");
		try {
			const fresh = await probe.mutateAsync(card.service);
			const ok = fresh.own?.last_test_ok === true;
			toast({
				description: t(
					ok ? "integrations.test.okToast" : "integrations.test.failedToast",
				),
				variant: ok ? "success" : "destructive",
			});
		} catch (error) {
			setFailure(integrationsErrorText(error, t));
		}
	}

	async function runDisconnect() {
		setFailure("");
		try {
			await disconnect.mutateAsync(card.service);
			toast({
				description: t("integrations.disconnect.done"),
				variant: "success",
			});
		} catch (error) {
			setFailure(integrationsErrorText(error, t));
		}
	}

	if (!card.own) {
		return (
			<Button type="button" className="self-start" onClick={onEdit}>
				{t("integrations.actions.connect")}
			</Button>
		);
	}
	return (
		<div className="flex flex-col gap-2">
			<div className="flex flex-wrap gap-2">
				<Button type="button" variant="outline" onClick={onEdit}>
					{t("integrations.actions.edit")}
				</Button>
				<Button
					type="button"
					variant="outline"
					disabled={probe.isPending}
					onClick={() => void runTest()}
				>
					{t("integrations.actions.test")}
				</Button>
				<AlertDialog>
					<AlertDialogTrigger asChild>
						<Button type="button" variant="destructive">
							{t("integrations.actions.disconnect")}
						</Button>
					</AlertDialogTrigger>
					<AlertDialogContent>
						<AlertDialogTitle>{t("integrations.disconnect.title")}</AlertDialogTitle>
						<AlertDialogDescription>
							{t("integrations.disconnect.body")}
						</AlertDialogDescription>
						<AlertDialogFooter>
							<AlertDialogCancel asChild>
								<Button type="button" variant="outline">
									{t("integrations.actions.cancel")}
								</Button>
							</AlertDialogCancel>
							<AlertDialogAction asChild>
								<Button
									type="button"
									variant="destructive"
									onClick={() => void runDisconnect()}
								>
									{t("integrations.disconnect.confirm")}
								</Button>
							</AlertDialogAction>
						</AlertDialogFooter>
					</AlertDialogContent>
				</AlertDialog>
			</div>
			{failure ? (
				<Alert variant="destructive">
					<AlertDescription>{failure}</AlertDescription>
				</Alert>
			) : null}
		</div>
	);
}

function CardActions({
	card,
	editable,
}: {
	card: IntegrationCard;
	editable: boolean;
}) {
	const { t } = useTranslation();
	const [editing, setEditing] = useState(false);
	if (!card.connectable) {
		return (
			<p className="text-sm">
				{t(`integrations.services.${card.service}.availableWhen`)}
			</p>
		);
	}
	if (!editable) return null;
	if (editing) {
		return <EmailAccountForm own={card.own} onDone={() => setEditing(false)} />;
	}
	return <Actions card={card} onEdit={() => setEditing(true)} />;
}

/** Plan D14: the academy's own Stripe and PayPal keys stay on B3's screen. */
function PaymentsLink() {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	if (!(can("gateway.view") && hasFeature("online_payments"))) return null;
	return (
		<Link
			to="/settings/gateways"
			className="self-start text-sm font-medium text-primary underline-offset-4 hover:underline"
		>
			{t("integrations.services.payments.manage")}
		</Link>
	);
}

function ServiceCard({
	card,
	editable,
}: {
	card: IntegrationCard;
	editable: boolean;
}) {
	const { t } = useTranslation();
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<div className="flex flex-wrap items-center justify-between gap-2">
					<CardTitle>{t(`integrations.services.${card.service}.title`)}</CardTitle>
					<StatusChip tone={TONE[card.using]}>
						{t(`integrations.using.${card.using}`)}
					</StatusChip>
				</div>
				<CardDescription>
					{t(`integrations.services.${card.service}.body`)}
				</CardDescription>
			</CardHeader>
			<CardContent className="flex flex-col gap-3 pt-4">
				<p className="text-sm text-muted-foreground">
					{t(`integrations.default.${card.default_status}`)}
				</p>
				{card.own ? <OwnStatus own={card.own} /> : null}
				<CardActions card={card} editable={editable} />
				{card.service === "payments" ? <PaymentsLink /> : null}
			</CardContent>
		</Card>
	);
}

/** Spec §6: Settings → Integrations, one card per service. */
export function IntegrationsPage() {
	const { t } = useTranslation();
	const can = useCan();
	const { data, isError } = useIntegrations();
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("errors.generic")}</AlertDescription>
			</Alert>
		);
	}
	if (!data) return <Spinner />;
	const editable = can("integration.update");
	return (
		<div className="grid gap-6 lg:grid-cols-2">
			{data.services.map((card) => (
				<ServiceCard key={card.service} card={card} editable={editable} />
			))}
		</div>
	);
}
```

Replace `dashboard/src/features/integrations/index.ts` with:

```ts
export { integrationsApi } from "./api";
export { EmailAccountForm } from "./EmailAccountForm";
export { integrationsErrorText } from "./errors";
export { IntegrationsPage } from "./IntegrationsPage";
export * from "./queries";
export * from "./schemas";
```

`dashboard/src/routes/_authed/settings.integrations.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { requireOffice } from "@/features/identity/require-admin";
import { IntegrationsPage } from "@/features/integrations";
import { PageContainer, PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/settings/integrations")({
	staticData: { permission: "integration.view" },
	beforeLoad: ({ context }) => requireOffice(context),
	component: function IntegrationsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("integrations.nav.title"));
		return (
			<PageContainer>
				<PageHeader
					title={t("integrations.nav.title")}
					description={t("integrations.page.subtitle")}
				/>
				<IntegrationsPage />
			</PageContainer>
		);
	},
});
```

In `dashboard/src/features/shell/nav.ts`, add `Plug,` to the `lucide-react` import list (between `Package,` and `Presentation,`), and replace

```ts
	office("/settings/roles", "nav.roles", KeyRound, "settings", "role.view_any"),
	// Parallel phases (spec 2026-10-02 §6.1): a phase's items go under its own
```

with

```ts
	office("/settings/roles", "nav.roles", KeyRound, "settings", "role.view_any"),
	// Integrations (spec 2026-10-07; not a phase): the academy's outside-service accounts.
	office(
		"/settings/integrations",
		"integrations.nav.title",
		Plug,
		"settings",
		"integration.view",
	),
	// Parallel phases (spec 2026-10-02 §6.1): a phase's items go under its own
```

Regenerate the route tree:

Run: `$DASH pnpm exec vite build`
Expected: build succeeds; `src/routeTree.gen.ts` now contains `/_authed/settings/integrations`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `$DASH pnpm vitest run src/features/integrations src/features/shell src/routes && just test-frontend && just lint-frontend`
Expected: all pass; `tsc` clean; biome and the colour check clean.

- [ ] **Step 5: Format and commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/integrations src/routes/_authed/settings.integrations.tsx src/routeTree.gen.ts src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts
git -C dashboard commit -m "feat(integrations): Settings → Integrations page" -m "$TRAILER"
```

---

### Task 9: Docs, state and the gates

**Files:**
- Modify: `CLAUDE.md` (meta), `STATE.md` (meta)

**Interfaces:**
- Consumes: everything above.
- Produces: the project rule every later phase follows (spec §7), the current position.

- [ ] **Step 1: Write the failing check**

Run: `grep -c "integrations.services.resolve" CLAUDE.md STATE.md`
Expected: `CLAUDE.md:0` and `STATE.md:0` (exit status 1).

- [ ] **Step 2: Run the whole suite before the docs**

Run: `just test && just lint`
Expected: backend and dashboard suites, `lint-imports`, ruff, biome and the secret scan pass; backend coverage ≥ 80 %. Then `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage` — lines and statements ≥ 80, branches and functions ≥ 70. Then `just e2e` (the full suite; every journey that reads Mailpit now sends through the resolver): all pass.

- [ ] **Step 3: Implement**

In `CLAUDE.md`, replace

```markdown
- Money is integer minor units + currency. Stored instants are UTC.
```

with

```markdown
- Money is integer minor units + currency. Stored instants are UTC.
- Outside services (email, WhatsApp, payments, video, AI) get their account only from
  `etqan.integrations.services.resolve(service)`; no app stores keys of its own. Email goes out
  only through `integrations.services.queue_email` / `send_email_now`. Secrets go through
  `etqan.platform.secrets`.
```

In `STATE.md`, replace

```markdown
## Follow-ups (from Plans 4–9)
```

with

```markdown
## Integrations (outside the phases)

Slice 1 of `docs/superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md` is built:
`etqan.integrations` (`PlatformAccount` in public, `AcademyAccount` per academy), the resolver
`integrations.services.resolve(service)` (own account → Etqan default if on, feature switch allows
it and `Academy.etqan_defaults_suspended` is off → none), email sent only through it, Settings →
Integrations (codes `integration.view` / `integration.update`) and Etqan's defaults in the platform
admin. Next: slice 2 (metering through `integrations.services.email.meter_email`, prices, Etqan
invoices, the suspend switch in the admin); B5c builds WhatsApp on the resolver (D41).

## Follow-ups (from Plans 4–9)
```

- [ ] **Step 4: Run the check to see it pass**

Run: `grep -c "integrations.services.resolve" CLAUDE.md STATE.md`
Expected: `CLAUDE.md:1` and `STATE.md:1`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md STATE.md
git commit -m "docs: integrations slice 1 rule and state" -m "$TRAILER"
```

Then open the PRs (backend and dashboard `feat/integrations` → `main`; meta `feat/integrations` → `master` with `--repo Etqan-agency/etqan_tutor`), merge after review, and bump the submodule pointers in meta with explicit paths (`git add backend dashboard`), never `git commit -a`.

---

## Self-review

**Spec coverage (slice 1):**
- §3.1 models — Task 1 (`PlatformAccount` SHARED, `AcademyAccount` TENANT, fields incl. test fields, `updated_by`/`updated_at`); secrets never returned — Tasks 3, 5, 6, 8 (Review Focus 1).
- §3.2 resolver, three steps, feature switch, suspended academy, per-request cache, two small rows — Task 3 (`resolve`, `SWITCHES`, `etqan_defaults_suspended`, cache tests, `django_assert_num_queries(0)`).
- §3.3 testing a connection — Task 2 (provider probes: real SMTP for email, `NotYet` for the rest) and Task 3 (`probe` records on the row), exposed in Tasks 5 and 6.
- §4 email row — Task 4: Etqan default = today's sending, from noreply@ with the academy's display name, reply-to the academy's contact address; own SMTP and from address; metering seam `meter_email` named and called once (no metering).
- §6 Settings → Integrations — Tasks 5 and 8: one card per service, default vs own, Connect/Edit/Test/Disconnect for email, last test, "available when" for the other four, payments links to B3's screen; codes `integration.view` / `integration.update`. Platform admin's Etqan default accounts (keys, Test, enabled) — Task 6. The default's price, the suspend switch, invoices, usage — slice 2 (D16, D2).
- §8 tests — resolver (own/default/none, switch off, suspended, caching): Task 3; secrets never serialised and probes with faked providers: Tasks 2, 3, 5, 6; role gates and never showing a secret on the screens: Tasks 5 and 8. Metering/invoice tests belong to slice 2.

**Placeholder scan:** every step carries the full test code, the exact command and expected result, the full implementation and an exact commit command. The only angle-bracketed token is the trailer's `<implementing model>`, which the Global Constraints define (set once in `$TRAILER`). Generated files (`0001_initial.py`, `0005_*.py`, `routeTree.gen.ts`) are produced by the named commands.

**Name consistency:** `ACADEMY`/`ETQAN`, `resolve`, `default_status`, `clear_cache`, `read_secrets`, `write_secrets`, `connect`, `disconnect`, `probe`, `own_account`, `connectable`, `apply_platform_change`, `send_email_now`, `queue_email`, `meter_email`, `NotSetUpError` (exported in Task 4) match their uses in Tasks 4–6 and the root `conftest.py`. `ProbeError`, `NotYet`, `PROVIDERS`, `get`, `mail_connection`, `SMTP_BACKEND` match between Task 2 and the fakes, conftest and tests. Task name `integrations.send_email`, function `etqan.integrations.tasks.send_email` (patched in `test_async_email.py`). Error codes `integrations.not_available` / `not_connected` / `no_tester_email` match the backend constants, the API tests and the `integrations.errors.*` keys. Dashboard: `integrationsApi.{list,connect,disconnect,probe}`, `useIntegrations`, `useIntegrationsMutation`, `integrationsKey`, `emailFormSchema`, `emailDefaults`, `emailBody`, `dayOf`, fixtures `ownEmail`/`card`/`integrations` agree across Tasks 7 and 8. The card shape (`service`, `using`, `default_status`, `connectable`, `own{…}`) is the same in `payloads.py`, `test_api.py`, `schemas.ts` and the fixtures.

**Fixed inline during review:** the spec's `services.test` renamed `probe` (D9) because pytest would collect it; `mail_connection` passes `username`/`password` as `""`, never `None`, so Django never falls back to Etqan's `EMAIL_HOST_USER` for an academy server (tested in Task 2); exceptions end in `Error` (ruff N818: `ProbeError`, `NotSetUpError`); the notifications contract test uses a string monkeypatch path, so it imports no integrations module beyond its services.
