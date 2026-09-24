# Plan 3 — People & Catalogue — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An academy admin can create and manage students, parents (linked to their children), teachers (linked to the courses they teach), admins, courses, packages and the academy's own settings; everyone created with an email gets a branded set-password invite in their own language and can sign in to `/app/`, where non-admins see only their own profile.

**Architecture:** `etqan.identity` is reshaped in place: nullable case-insensitive email, phone, `preferred_language`, TutorHamster-shaped profiles, `ParentStudent` renamed to `Guardianship`, and Kaleem's self-registration, parent-created children and invite codes removed. Two new tenant apps are added. `etqan.academy` holds the `AcademySettings` singleton (timezone, currency, language). `etqan.catalogue` holds `Course` (M2M to `TeacherProfile`) and `Package`, and owns the single `sessions_total` rule. Admin endpoints live under `/api/v1/people/…`, `/api/v1/catalogue/…` and `/api/v1/academy/settings/`. They share role permissions and CSV export from `etqan.platform`, and each app has a `scope_for` function. The dashboard gets People, Catalogue and Settings → Academy areas. Every identity email is rendered in the recipient's language.

**Tech Stack:** Django 6 / DRF / django-tenants 3.14 / django-allauth, PostgreSQL 18, Celery; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-24-people-catalogue-design.md` (Phase B0 milestone 3 of `2026-09-24-parity-roadmap-design.md`; builds on `2026-09-23-etqan-tutor-v1-design.md` §4.1–4.3, §6 and `2026-09-23-academy-sites-design.md`).

## Global Constraints

- Repos: `backend/` (`Etqan-agency/etqan_tutor_backend`, trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`). Feature branch `feat/people-catalogue` in every touched repo. The meta branch already exists; create it in `backend/` and `dashboard/` before their first task (`git -C backend switch -c feat/people-catalogue`, same for `dashboard`). Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Backend commands run from `backend/` with the virtualenv `backend/.venv` and this environment exported once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
  Tests: `.venv/bin/pytest …` (add `--create-db` once after any task that adds migrations). Linters: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`.
- Dashboard commands run from `dashboard/` with pnpm through `npx pnpm@10` (`npx pnpm@10 tsc --noEmit`, `npx pnpm@10 lint`, `npx pnpm@10 test:coverage`, `npx pnpm@10 build`). `pnpm lint` = `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities (`bg-red-500`, `bg-black/50`, …) in `src/`, comments included. Only semantic tokens (`bg-primary`, `text-muted-foreground`, `text-destructive`, …).
- New route files are picked up by the TanStack Router plugin; regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`.
- Coverage: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; academies `demo` (`admin@demo.test`) and `other` (`admin@other.test`).
- Tenancy: new business apps go in `TENANT_APPS` only; migrate with `migrate_schemas`; background work loops academies with `tenant_context`; every user-facing URL is built with `etqan.platform.frontend.app_url()` / `frontend_url()`.
- Business logic lives in `<app>/services.py`. Apps talk to each other only through services, and `lint-imports` contracts enforce it. All API routes are under `/api/v1/`. Money is integer minor units + ISO 4217 currency; stored instants are UTC.
- Roles, one per account: `admin · teacher · student · parent`. Languages: `ar · en`. Phone: E.164, `^\+[1-9]\d{6,14}$`, optional.
- Student status values: `active · trial · in_progress · paused · inactive` (default `active`). Gender values: `male · female`. Teacher payout methods: `vodafone_cash · instapay · bank_account · mashreq_neo · western_union · wise · paypal · telda · abu_dhabi_bank · cash · stc_pay`. `payout_details` is required when `payout_method` is set.
- Course: `name_ar`/`name_en` required, `description_ar`/`description_en` optional, `language` `ar · en · both`, `teachers` M2M → `TeacherProfile` (optional), `is_active`.
- Package: `sessions_per_week` 1–14, `session_minutes` 15–240 (form offers 30/45/60/other), `duration_value` 1–365, `duration_unit` `day · month`, `freeze_days_allowed` 0–365 (default 0), `price_minor` ≥ 0 int, `currency` ISO 4217, `is_active`. `sessions_total = sessions_per_week × weeks`, `weeks(n, "month") = 4n`, `weeks(n, "day") = ceil(n / 7)`. The only implementation is `etqan.catalogue.services`.
- Access: people (list/create/edit/account actions) admin only; own user + profile via `identity/me/` for every role; parents read their linked children's profiles; courses/packages admin CRUD, teacher read active; academy settings admin write, every signed-in role read. One permission class per role plus `scope_for(user, queryset)` per app; out-of-scope objects return 404.
- People are deactivated, never deleted. An admin cannot deactivate themselves, and the last active admin cannot be deactivated.
- CSV export: `?format=csv` on every admin list, current filters applied, all matching rows, UTF-8 with BOM.
- Every dashboard string exists in `src/locales/en/common.json` and `src/locales/ar/common.json`; bilingual pairs use `BilingualField`; screens work RTL and at phone width.

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — Kaleem endpoints are retired first (Task 1), not last.** The columns Task 3 drops (`birthdate`, `teacher_gender_preference`, `is_in_pool`, `ParentInvite`) are read by those endpoints, so they have to go before the columns. Task 1 also retires `identity/me/student-profile/` and `identity/me/teacher-profile/`. The spec does not list them, but their only fields are being removed; the role profile moves into `identity/me/`. It retires `create_teacher_account` too (replaced by `create_person`). allauth's own HTML sign-up at `/accounts/signup/` is still open today, so the adapter now refuses sign-ups (P3-2). The dashboard's `/register` and `/family` go in Task 11.
- **D2 — `academy` settings come before identity services.** `create_person` needs the academy's default language, timezone and currency, so `etqan.academy` is Task 2.
- **D3 — `User.preferred_language` has a model default of `en`.** A model default cannot read a per-academy setting. `create_person` and `create_academy_admin` apply `AcademySettings.default_language` (default `ar`). Users created directly (tests, Etqan staff) stay English.
- **D4 — Admin changes someone's email.** If the person has never set a password (invite pending, or no email yet), the new address replaces the old one at once and a fresh invite goes out. Django's reset token hashes the email, so the old invite link stops working. If the person has signed in, the address goes to `User.pending_email` and gets allauth's confirmation email. When it is confirmed, the `email_confirmed` signal makes it primary and the old address receives a security alert; the old address keeps working until then. An email cannot be removed once set.
- **D5 — `account_state` is derived, not stored:** `no_login` (no email) → `inactive` (`is_active` false) → `invited` (email, no usable password) → `active`. `resend_invite` works only in `invited`. `send_password_reset` needs an email and an active account.
- **D6 — People URLs use the User id.** `people/<kind>/<id>/`, `guardians/<parent_id>/`, `teacher_ids` and `course_ids` all carry User ids for people. Profile ids never leave the backend.
- **D7 — Nested payload `{user: {...}, profile: {...}}`; validation errors come back nested the same way** (`{"user": {"email": ["…"]}}`). The dashboard flattens them to `user.email`, a react-hook-form path.
- **D8 — Country and currency codes are format-checked only** (`^[A-Z]{2}$`, `^[A-Z]{3}$`, upper-cased on input). The dashboard offers the ISO 3166-1 list and a curated currency list. Timezones are checked against `zoneinfo.available_timezones()`.
- **D9 — CSV:** English column labels, UTF-8 BOM, every filtered row (no pagination). Cells starting with `=`, `@`, tab or CR, or with `+`/`-` followed by anything other than digits, get a leading `'` against formula injection. Phone numbers stay intact.
- **D10 — Duplicate** gives "`<name_en>` (copy)" / "`<name_ar>` (نسخة)" and `is_active=False`. A duplicated course keeps its teachers.
- **D11 — Legacy teachers keep `gender=""`** in the database (the field predates the requirement). The API requires `male`/`female` on create and refuses `""` on edit.
- **D12 — `birthdate` is copied to `StudentProfile.date_of_birth` / `TeacherProfile.date_of_birth` when the user has that profile.** Parents' and admins' birthdates are dropped because the spec gives them no field.
- **D13 — Parents read their children through `identity/me/`** (`children[].profile`). No separate parent endpoint.
- **D14 — Deactivation ends sessions** by deleting the user's rows in the academy's session table. `ModelBackend` also rejects inactive users on the next request.
- **D15 — Import boundaries.** `etqan.academy` imports no business module. `etqan.catalogue` reaches identity only through `etqan.identity.services`. In identity, only `etqan.identity.api` may import `etqan.catalogue.services`, for the teacher ↔ courses link. Platform role permissions check `user.role` strings, so `etqan.platform` still imports no business module.
- **D16 — Domain errors roll back the request.** `etqan.platform.drf.exception_handler` now calls DRF's `set_rollback()` for `EtqanError`, as DRF's own handler does. With `ATOMIC_REQUESTS=True`, a service that fails after a partial write must not commit it.
- **D17 — Seeded people get no password and no email is sent.** They show as "Invite pending"; an admin can send the invite from the UI.
- **D18 — The E2E suite reads the invite email.** In CI, Django runs with `CELERY_TASK_ALWAYS_EAGER=True` and the file email backend (`DJANGO_EMAIL_FILE_PATH`), and Playwright reads `E2E_MAIL_DIR`. Locally it reads Mailpit's API.
- **D19 — Nav groups:** `NavItem.group` is `people · catalogue · settings`. Website moves into the Settings group next to Academy.

## Review Focus

- **People with no email must work everywhere that currently assumes `user.email`.** This covers `__str__`, the admin list, the CSV, invite/reset/security emails (skipped or refused, never sent to `None`), the login form (such a person can never authenticate) and search. Adding an email later sends exactly one invite. Tests: Task 3 (`test_models`), Task 5 (`test_people_services`), Task 7 (`test_people_api` CSV row), Task 8 (actions).
- **An admin must never lock the academy out.** Self-deactivation and deactivating the last active admin are refused through the service, the detail action and the bulk endpoint. Reactivation works, and a deactivated user's open session stops working at once. Tests: Task 5 (`TestDeactivate`), Task 8 (`test_people_actions_api`).
- **Academy B's people must never appear on academy A's host** in list, detail, CSV, guardian linking (a parent id from the other academy is 404) or teacher course filters. Tests: Task 7 (`test_other_academy_people_never_leak`), Task 8 (`test_guardian_from_other_academy_is_404`).
- **Each identity email arrives in the recipient's language** with the academy name in that language in the From header and subject prefix, `dir="rtl"` for Arabic HTML, and both names in the layout. This covers invites, resets, security alerts and allauth's confirmation. Public-schema mail keeps `[Etqan]`. Tests: Task 4 (`test_email_language`).
- **`sessions_total` edge values** (1 day → 1 week, 7 → 1, 8 → 2, 365 days → 53, 1 month → 4, 365 months × 14 = 20 440) must agree between the backend and the dashboard's live preview. Out-of-range inputs must be rejected, not clamped. Tests: Task 6 (`test_sessions_total`), Task 9 (API bounds), Task 13 (`sessions-total.test.ts`).

---

## File Structure

```
backend/
  config/settings/base.py        TENANT_APPS += etqan.academy, etqan.catalogue; CELERY_TASK_ALWAYS_EAGER / EMAIL_FILE_PATH from env
  config/api_router.py           + people/, catalogue/, academy/
  conftest.py                    + api_for fixture
  pyproject.toml                 import-linter contracts (academy, catalogue, identity↔catalogue)
  etqan/platform/
    permissions.py               + role_of, IsAdmin, IsTeacher, IsParent, IsStudent, ReadOnly
    validators.py                NEW clean_phone / clean_timezone / clean_currency / clean_country / clean_language / from_django
    csv.py                       NEW CSVRenderer, CSVExportMixin, safe_cell
    drf.py                       set_rollback() for EtqanError
  etqan/academy/                 NEW tenant app: models (AcademySettings), services, api/, migrations 0001 + 0002 (data)
  etqan/identity/
    models.py                    User (nullable ci-unique email, phone, preferred_language, pending_email), profiles, Guardianship
    migrations/0010_people_fields.py 0011_people_data.py 0012_people_cleanup.py
    services.py                  create_person, update_person, change_person_email, promote_pending_email, account_state,
                                 resend_invite, send_password_reset, deactivate, activate, bulk_update_students,
                                 link_guardian, unlink_guardian, guardians_of, children_of, people_queryset, get_person,
                                 teacher_profiles_for, has_people (Kaleem child/invite/register services removed)
    emails.py                    NEW render_email(kind, language, **context)
    signals.py                   NEW email_confirmed → promote_pending_email
    scopes.py                    NEW scope_for
    adapter.py                   localized allauth templates, sign-up closed
    api/payloads.py              NEW user_payload, profile_payload, person_rows
    api/people_serializers.py    NEW PersonWriteSerializer, StudentBulkSerializer, as_drf
    api/people_filters.py        NEW filter_people
    api/people_views.py          NEW list/create/detail/actions/guardians/children/bulk
    api/people_urls.py           NEW
    api/{views,serializers,urls}.py  Kaleem views removed; me/ payload extended
  etqan/catalogue/               NEW tenant app: models (Course, Package), services, scopes, api/, migrations 0001
  etqan/site/emails.py           brand_email(..., language)
  etqan/templates/email/layout.html            dir/lang per recipient
  etqan/templates/email/identity/*.{ar,en}.txt NEW invite, reset, security_* bodies
  etqan/templates/account/email/email_confirmation_{ar,en}_{subject,message}.txt NEW
  etqan/tenants/services.py      create_academy → ensure_settings
  etqan/tenants/management/commands/seed_dev.py  people + catalogue seeds
dashboard/
  src/features/shell/{nav.ts,AppSidebar.tsx}   groups + new items
  src/features/identity/…        Kaleem screens removed; require-admin.ts moved here; Me extended; ProfileEditForm + MyProfileCard
  src/features/academy/{api,queries,AcademySettingsForm}.ts(x)
  src/features/people/{schemas,api,queries,PeopleList,UserFieldsSection,AccountActions,StudentForm,StudentsList,GuardiansPanel,
                       ParentForm,ParentsList,TeacherForm,TeachersList,AdminsList}.ts(x)
  src/features/catalogue/{schemas,api,queries,sessions-total,CoursesList,CourseForm,PackagesList,PackageForm}.ts(x)
  src/lib/{countries,currencies,timezones}.ts
  src/routes/_authed/{people.*,catalogue.*,settings.academy}.tsx
  src/locales/{en,ar}/common.json
  e2e/{mail.ts,people-catalogue.spec.ts}
meta: .github/workflows/ci.yml (e2e env), STATE.md, submodule pointers
```

---
### Task 1: Retire Kaleem self-registration, parent-created children and invite codes (backend)

**Files:**
- Create: `backend/etqan/identity/tests/test_retired.py`
- Modify: `backend/etqan/identity/services.py`, `backend/etqan/identity/api/views.py`, `backend/etqan/identity/api/serializers.py`, `backend/etqan/identity/api/urls.py`, `backend/etqan/identity/adapter.py`, `backend/config/settings/base.py` (delete `ACCOUNT_ALLOW_REGISTRATION`)
- Delete: `backend/etqan/identity/tests/test_api_children_invites.py`, `backend/etqan/identity/tests/test_teacher_profile_api.py`
- Modify tests that used the removed code: `test_api_auth.py`, `test_api_resend_verification.py`, `test_email_branding.py`, `test_async_email.py`, `test_api_versioning.py`, `test_services.py`, `test_admin.py`, `test_roles.py` (all in `backend/etqan/identity/tests/`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `identity/register/`, `identity/children/…`, `identity/invites/…`, `identity/me/student-profile/`, `identity/me/teacher-profile/` return 404. These services are gone: `register_user`, `set_student_profile`, `get_student_preferences`, `set_teacher_gender`, `create_child`, `create_invite`, `accept_invite`, `set_child_password`, `set_child_email`, `set_child_preferences`, `resend_child_verification`, `create_teacher_account`. `_send_child_set_password_link(user)` is renamed `_send_invite(user)` (private, used by `create_academy_admin`). `CeleryAccountAdapter.is_open_for_signup(request) -> False`.

- [ ] **Step 1: Branch**

```bash
git -C backend switch -c feat/people-catalogue
```

- [ ] **Step 2: Write the failing test** — `backend/etqan/identity/tests/test_retired.py`

```python
"""P3-2: accounts are created by admins only. Kaleem's self-service paths are gone."""

import pytest
from rest_framework.test import APIClient

from etqan.identity import services
from etqan.identity.models import User

RETIRED = [
    ("post", "/api/v1/identity/register/"),
    ("get", "/api/v1/identity/children/"),
    ("post", "/api/v1/identity/children/1/set-password/"),
    ("post", "/api/v1/identity/children/1/email/"),
    ("put", "/api/v1/identity/children/1/preferences/"),
    ("post", "/api/v1/identity/children/1/resend-verification/"),
    ("post", "/api/v1/identity/invites/"),
    ("post", "/api/v1/identity/invites/accept/"),
    ("get", "/api/v1/identity/me/student-profile/"),
    ("get", "/api/v1/identity/me/teacher-profile/"),
]


@pytest.mark.django_db
@pytest.mark.parametrize(("method", "path"), RETIRED)
def test_retired_endpoint_is_gone(method, path):
    user = User.objects.create_user(
        email="p@x.test", password="pw-12345678", role="parent"
    )
    client = APIClient()
    client.force_login(user)
    assert getattr(client, method)(path, {}, format="json").status_code == 404


@pytest.mark.parametrize(
    "name",
    [
        "register_user",
        "set_student_profile",
        "get_student_preferences",
        "set_teacher_gender",
        "create_child",
        "create_invite",
        "accept_invite",
        "set_child_password",
        "set_child_email",
        "set_child_preferences",
        "resend_child_verification",
        "create_teacher_account",
    ],
)
def test_retired_service_is_gone(name):
    assert not hasattr(services, name)


@pytest.mark.django_db
def test_allauth_html_signup_is_closed():
    resp = APIClient().post(
        "/accounts/signup/",
        {
            "email": "walk-in@x.test",
            "password1": "sup3r-secret-pw",
            "password2": "sup3r-secret-pw",
        },
    )
    assert resp.status_code in (200, 302)
    assert not User.objects.filter(email="walk-in@x.test").exists()
```

- [ ] **Step 3: Run it to verify it fails**

Run: `.venv/bin/pytest etqan/identity/tests/test_retired.py -q`
Expected: FAIL. The endpoints return 201/200/403/400 instead of 404, the services still exist, and the sign-up creates a user.

- [ ] **Step 4: Remove the code**

`etqan/identity/services.py`:
- Delete `register_user`, `set_student_profile`, `get_student_preferences`, `set_teacher_gender`, `_child_email_in_use`, `_send_child_activation`, `create_child`, `create_invite`, `accept_invite`, `set_child_password`, `_get_own_child`, `set_child_email`, `set_child_preferences`, `resend_child_verification`, `create_teacher_account`, and the now-unused `INVITE_TTL`, `ACCOUNT_TYPES`, `import secrets`, `from datetime import date`, `from datetime import timedelta`, `from django.utils import timezone`, `from etqan.identity.models import ParentInvite`.
- Rename `_send_child_set_password_link` to `_send_invite` (same body, same signature `(child_user: User)` → rename the parameter to `user`), and update its one caller in `create_academy_admin`.

`etqan/identity/api/views.py`: delete `RegisterView`, `StudentProfileView`, `TeacherProfileView`, `ChildListCreateView`, `ChildSetPasswordView`, `ChildEmailView`, `ChildPreferencesView`, `ChildResendVerificationView`, `InviteCreateView`, `InviteAcceptView`, their serializer imports, `from etqan.identity.models import StudentProfile` and `from etqan.platform.exceptions import PermissionDeniedError`. Delete the `from etqan.platform.exceptions import NotFoundError` import too, since nothing else in the file uses it.

`etqan/identity/api/serializers.py`: delete `RegisterSerializer`, `StudentProfileSerializer`, `TeacherProfileSerializer`, `TeacherProfileResponseSerializer`, `ChildCreateSerializer`, `SetChildPasswordSerializer`, `ChildEmailSerializer`, `InviteAcceptSerializer`, `RegisterResponseSerializer`, `ChildResponseSerializer`, `ChildCreatedResponseSerializer`, `InviteResponseSerializer`, `InviteAcceptedResponseSerializer`, `StudentProfileResponseSerializer`, and the `timedelta`, `timezone`, `StudentProfile`, `TeacherProfile` imports.

`etqan/identity/api/urls.py` becomes:

```python
from django.urls import path

from etqan.identity.api.views import ChangePasswordView
from etqan.identity.api.views import CsrfView
from etqan.identity.api.views import EmailDeleteView
from etqan.identity.api.views import EmailListCreateView
from etqan.identity.api.views import EmailPrimaryView
from etqan.identity.api.views import LoginView
from etqan.identity.api.views import LogoutView
from etqan.identity.api.views import MeView
from etqan.identity.api.views import PasswordResetConfirmView
from etqan.identity.api.views import PasswordResetView
from etqan.identity.api.views import ResendVerificationView
from etqan.identity.api.views import VerifyEmailView

app_name = "identity"

urlpatterns = [
    path("csrf/", CsrfView.as_view(), name="csrf"),
    path(
        "resend-verification/",
        ResendVerificationView.as_view(),
        name="resend-verification",
    ),
    path("verify-email/", VerifyEmailView.as_view(), name="verify-email"),
    path("login/", LoginView.as_view(), name="login"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("me/", MeView.as_view(), name="me"),
    path("me/password/", ChangePasswordView.as_view(), name="change-password"),
    path("password/reset/", PasswordResetView.as_view(), name="password-reset"),
    path(
        "password/reset/confirm/",
        PasswordResetConfirmView.as_view(),
        name="password-reset-confirm",
    ),
    path("me/emails/", EmailListCreateView.as_view(), name="emails"),
    path(
        "me/emails/<int:email_id>/", EmailDeleteView.as_view(), name="email-detail"
    ),
    path(
        "me/emails/<int:email_id>/primary/",
        EmailPrimaryView.as_view(),
        name="email-primary",
    ),
]
```

`etqan/identity/adapter.py`: add to `CeleryAccountAdapter`:

```python
    def is_open_for_signup(self, request):
        # P3-2: accounts are created by academy admins only. allauth's HTML
        # sign-up under /accounts/ would otherwise let anyone self-register.
        return False
```

`config/settings/base.py`: delete the `ACCOUNT_ALLOW_REGISTRATION = …` line (nothing reads it).

- [ ] **Step 5: Rewrite the tests that used the removed code**

Delete `etqan/identity/tests/test_api_children_invites.py` and `etqan/identity/tests/test_teacher_profile_api.py`.

`test_roles.py`: keep only `test_me_includes_role` and its imports (`pytest`, `APIClient`, `User`).

`test_admin.py`: delete `class TestCreateTeacherAccount` and the now-unused imports `EmailAddress`, `services`, `ValidationError`.

`test_services.py`: delete `TestCreateChild`, `TestSetChildPassword`, `TestSetChildEmail`, `TestSetChildPreferences`, `TestResendChildVerification`, `TestInvites`, and the imports `timedelta`, `timezone`, `EmailAddress`, `ParentInvite`.

`test_api_auth.py`:
- delete `_register_payload`, `class TestRegister`, `class TestRegisterBirthdate`, `class TestStudentProfileEndpoint`, `TestEmailVerification.test_register_records_email_for_verification`, and the imports `date`, `timedelta`, `timezone`;
- add below the `api` fixture:

```python
def _student(*, email="ahmad@example.com", password="sup3r-secret-pw"):
    user = User.objects.create_user(
        email=email, password=password, full_name="Ahmad Ali", role="student"
    )
    StudentProfile.objects.create(user=user)
    EmailAddress.objects.create(user=user, email=email, primary=True, verified=False)
    return user
```

- in `TestLogin`, delete the `_register` method and replace every `self._register(api)` with `_student()`; in `TestEmailVerification.test_login_blocked_when_email_unverified` and `test_login_allowed_once_email_verified` replace `api.post("/api/v1/identity/register/", _register_payload(), format="json")` with `_student()`;
- replace `TestMe.test_me_parent_includes_children` with:

```python
    def test_me_parent_includes_children(self, api):
        parent_user = User.objects.create_user(
            email="p@example.com", password="pw", role="parent"
        )
        parent = ParentProfile.objects.create(user=parent_user)
        child_user = User.objects.create_user(
            email="yusuf@example.com", password="pw", full_name="Yusuf Ali"
        )
        child = StudentProfile.objects.create(user=child_user)
        ParentStudent.objects.create(parent=parent, student=child)
        api.force_authenticate(user=parent_user)
        resp = api.get("/api/v1/identity/me/")
        assert resp.status_code == 200
        assert resp.data["profiles"] == ["parent"]
        assert [c["full_name"] for c in resp.data["children"]] == ["Yusuf Ali"]
```

  (add `from etqan.identity.models import ParentStudent`; drop `from etqan.identity import services` if now unused).

`test_api_resend_verification.py` and `test_email_branding.py`: replace the `_register(api, email=…)` helper with the one below. Replace every `_register(api)` / `_register(api, email=…)` call with `_unverified_user()` / `_unverified_user(email=…)`, add `from allauth.account.models import EmailAddress` and `from etqan.identity.models import User` where missing, and in `test_email_branding.py` delete `test_signup_confirmation_body_has_no_pii` (the sign-up path no longer exists):

```python
def _unverified_user(*, email="ahmad@example.com"):
    user = User.objects.create_user(
        email=email, password="sup3r-secret-pw", full_name="Ahmad Ali"
    )
    EmailAddress.objects.create(user=user, email=email, primary=True, verified=False)
    return user
```

`test_async_email.py`: delete `_register_payload` and `test_verification_email_dispatched_to_celery`, then replace `test_resend_dispatched_to_celery` with:

```python
    def test_resend_dispatched_to_celery(self, api, settings):
        settings.ACCOUNT_EMAIL_VERIFICATION = "mandatory"
        user = User.objects.create_user(email="ahmad@example.com", password="pw")
        EmailAddress.objects.create(
            user=user, email=user.email, primary=True, verified=False
        )
        with patch("etqan.platform.tasks.send_email_message.delay") as delay:
            resp = api.post(
                "/api/v1/identity/resend-verification/",
                {"email": "ahmad@example.com"},
                format="json",
            )
        assert resp.status_code == 200
        assert delay.called
```

(imports: `from allauth.account.models import EmailAddress`, `from etqan.identity.models import User`).

`test_api_versioning.py`: replace `test_register_works_under_v1` with:

```python
    def test_login_works_under_v1(self, api):
        User.objects.create_user(email="v@example.com", password="sup3r-secret-pw")
        resp = api.post(
            "/api/v1/identity/login/",
            {"email": "v@example.com", "password": "sup3r-secret-pw"},
            format="json",
        )
        assert resp.status_code == 200
```

(import `from etqan.identity.models import User`).

`test_api_docs.py`: replace `test_schema_documents_register_request_and_response` with:

```python
    def test_schema_documents_login_request(self, api):
        schema = api.get("/api/v1/schema/?format=json").json()
        login = schema["paths"]["/api/v1/identity/login/"]["post"]
        req_ref = login["requestBody"]["content"]["application/json"]["schema"]
        assert req_ref["$ref"].endswith("/Login")
```

- [ ] **Step 6: Run the whole suite and linters**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`
Expected: all pass, coverage ≥ 80%. `test_retired.py` passes: the removed URLs 404, and the allauth sign-up re-renders its closed page with no user created.

- [ ] **Step 7: Commit**

```bash
git -C backend add -A
git -C backend commit -m "refactor(identity)!: retire self-registration, parent-created children and invite codes

Accounts are created by academy admins only (P3-2). Also retires the
me/student-profile and me/teacher-profile endpoints whose fields are being
removed, and closes allauth's HTML sign-up.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Role permissions, rollback on domain errors, `etqan.academy` settings app + API

**Files:**
- Create: `backend/etqan/platform/validators.py`, `backend/etqan/platform/tests/test_validators.py`, `backend/etqan/platform/tests/test_role_permissions.py`
- Create: `backend/etqan/academy/{__init__,apps,models,services}.py`, `backend/etqan/academy/api/{__init__,serializers,views,urls}.py`, `backend/etqan/academy/migrations/{__init__,0001_initial,0002_settings_from_academy}.py`, `backend/etqan/academy/tests/{__init__,test_services,test_api}.py`
- Modify: `backend/etqan/platform/permissions.py`, `backend/etqan/platform/drf.py`, `backend/config/settings/base.py` (`TENANT_APPS`), `backend/config/api_router.py`, `backend/etqan/tenants/services.py`, `backend/etqan/tenants/tests/test_services.py`, `backend/conftest.py`, `backend/pyproject.toml`

**Interfaces:**
- Produces:
  - `etqan.platform.permissions`: `role_of(user) -> str | None`, permission classes `IsAdmin`, `IsTeacher`, `IsParent`, `IsStudent`, `ReadOnly` (authenticated + safe method). They compose with DRF `|`/`&`, e.g. `[IsAdmin | ReadOnly]`.
  - `etqan.platform.validators`: `clean_phone(value: str | None, field="phone") -> str` (`""` allowed), `clean_timezone(value: str, field="timezone") -> str`, `clean_currency(value: str, field: str) -> str` (upper-cased), `clean_country(value: str | None, field="country") -> str` (`""` allowed, upper-cased), `clean_language(value: str, field="preferred_language") -> str`, `from_django(exc: django ValidationError) -> etqan ValidationError` (first field error). All raise `etqan.platform.exceptions.ValidationError(message, field=…)`.
  - `etqan.platform.drf.exception_handler` calls `set_rollback()` for every `EtqanError`.
  - `etqan.academy.models.AcademySettings` (`timezone`, `default_currency`, `default_language` (`AcademySettings.Language.AR/EN`, default `ar`), `created_at`, `updated_at`).
  - `etqan.academy.services`: `ensure_settings(*, timezone="UTC", currency="USD", language="ar") -> AcademySettings`, `get_settings() -> AcademySettings` (self-heals from `connection.tenant.timezone/currency`), `update_settings(*, timezone=None, default_currency=None, default_language=None) -> AcademySettings`.
  - `GET /api/v1/academy/settings/` (any signed-in role), `PATCH` (admin) → `{"timezone", "default_currency", "default_language", "updated_at"}`.
  - `create_academy(...)` stores the academy's timezone/currency in `AcademySettings` (language `ar`).
  - Root fixture `api_for(role="admin", **user_fields) -> APIClient` (logged-in client with `.user`).

- [ ] **Step 1: Write the failing tests**

`backend/conftest.py` — append (keeps the deferred-import style of the file):

```python
@pytest.fixture
def api_for(db):
    """`api_for("teacher")` → an APIClient logged in as a new user of that role.

    The user is on `client.user`. Extra keyword arguments go to `create_user`.
    """
    import itertools  # noqa: PLC0415

    from rest_framework.test import APIClient  # noqa: PLC0415

    from etqan.identity.models import User  # noqa: PLC0415

    counter = itertools.count(1)

    def make(role="admin", **fields):
        n = next(counter)
        user = User.objects.create_user(
            email=fields.pop("email", f"{role}{n}@x.test"),
            password="pw-12345678",
            full_name=fields.pop("full_name", f"{role.title()} {n}"),
            role=role,
            **fields,
        )
        client = APIClient()
        client.force_login(user)
        client.user = user
        return client

    return make
```

`backend/etqan/platform/tests/test_validators.py`:

```python
import pytest
from django.core.exceptions import ValidationError as DjangoValidationError

from etqan.platform import validators
from etqan.platform.exceptions import ValidationError


@pytest.mark.parametrize("value", ["", None, "+201001234567", "+44 20 7946 0958"])
def test_valid_phones(value):
    assert validators.clean_phone(value) in ("", "+201001234567", "+442079460958")


@pytest.mark.parametrize("value", ["01001234567", "+0123456789", "+12", "phone"])
def test_invalid_phones(value):
    with pytest.raises(ValidationError) as exc:
        validators.clean_phone(value)
    assert exc.value.field == "phone"


def test_timezone_currency_country_language():
    assert validators.clean_timezone("Africa/Cairo") == "Africa/Cairo"
    assert validators.clean_currency("egp", field="pay_currency") == "EGP"
    assert validators.clean_country("eg") == "EG"
    assert validators.clean_country("") == ""
    assert validators.clean_language("ar") == "ar"
    for call in (
        lambda: validators.clean_timezone("Mars/Base"),
        lambda: validators.clean_currency("EURO", field="c"),
        lambda: validators.clean_country("Egypt"),
        lambda: validators.clean_language("fr"),
    ):
        with pytest.raises(ValidationError):
            call()


def test_from_django_keeps_the_first_field_error():
    exc = DjangoValidationError({"payout_details": ["Enter details."]})
    out = validators.from_django(exc)
    assert (out.field, out.message) == ("payout_details", "Enter details.")
    assert validators.from_django(DjangoValidationError("Plain.")).field is None
```

`backend/etqan/platform/tests/test_role_permissions.py`:

```python
from types import SimpleNamespace

import pytest

from etqan.platform import drf
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import role_of


def _request(role, method="GET", *, authenticated=True):
    user = SimpleNamespace(is_authenticated=authenticated, role=role)
    return SimpleNamespace(user=user, method=method)


def test_role_of_ignores_anonymous():
    assert role_of(SimpleNamespace(is_authenticated=False, role="admin")) is None
    assert role_of(None) is None


@pytest.mark.parametrize(
    ("role", "admin", "teacher"),
    [("admin", True, False), ("teacher", False, True), ("parent", False, False)],
)
def test_role_classes(role, admin, teacher):
    assert IsAdmin().has_permission(_request(role), None) is admin
    assert IsTeacher().has_permission(_request(role), None) is teacher


def test_read_only_needs_auth_and_safe_method():
    assert ReadOnly().has_permission(_request("student"), None) is True
    assert ReadOnly().has_permission(_request("student", "PATCH"), None) is False
    anon = _request(None, authenticated=False)
    assert ReadOnly().has_permission(anon, None) is False


def test_domain_errors_roll_back_the_request_transaction(monkeypatch):
    calls = []
    monkeypatch.setattr(drf, "set_rollback", lambda: calls.append(True))
    response = drf.exception_handler(ValidationError("Bad.", field="f"), {})
    assert response.status_code == 400
    assert calls == [True]
```

`backend/etqan/academy/tests/__init__.py` — empty. `backend/etqan/academy/tests/test_services.py`:

```python
import pytest
from django.db import connection

from etqan.academy import services
from etqan.academy.models import AcademySettings
from etqan.platform.exceptions import ValidationError


def test_existing_academy_got_settings_from_its_migration():
    # Created by migration 0002 when the test academy's schema was migrated.
    assert AcademySettings.objects.count() == 1
    s = AcademySettings.objects.get()
    assert (s.timezone, s.default_currency, s.default_language) == ("UTC", "USD", "ar")


def test_get_settings_self_heals_from_the_academy_row(monkeypatch):
    AcademySettings.objects.all().delete()
    monkeypatch.setattr(connection.tenant, "timezone", "Africa/Cairo")
    monkeypatch.setattr(connection.tenant, "currency", "EGP")
    s = services.get_settings()
    assert (s.timezone, s.default_currency, s.default_language) == (
        "Africa/Cairo",
        "EGP",
        "ar",
    )
    assert services.get_settings().pk == s.pk


def test_ensure_settings_is_idempotent():
    first = services.ensure_settings(timezone="Asia/Riyadh", currency="SAR")
    assert services.ensure_settings(timezone="UTC").pk == first.pk


def test_update_settings_validates_and_normalises():
    s = services.update_settings(
        timezone="Asia/Dubai", default_currency="aed", default_language="en"
    )
    assert (s.timezone, s.default_currency, s.default_language) == (
        "Asia/Dubai",
        "AED",
        "en",
    )
    with pytest.raises(ValidationError) as exc:
        services.update_settings(timezone="Nowhere/Land")
    assert exc.value.field == "timezone"
```

`backend/etqan/academy/tests/test_api.py`:

```python
import pytest
from rest_framework.test import APIClient

URL = "/api/v1/academy/settings/"


@pytest.mark.parametrize("role", ["admin", "teacher", "parent", "student"])
def test_every_signed_in_role_reads(api_for, role):
    resp = api_for(role).get(URL)
    assert resp.status_code == 200
    assert resp.json()["default_language"] == "ar"


def test_anonymous_is_refused():
    assert APIClient().get(URL).status_code == 403


@pytest.mark.parametrize("role", ["teacher", "parent", "student"])
def test_only_admin_writes(api_for, role):
    resp = api_for(role).patch(URL, {"timezone": "Africa/Cairo"}, format="json")
    assert resp.status_code == 403


def test_admin_updates(api_for):
    resp = api_for("admin").patch(
        URL,
        {"timezone": "Africa/Cairo", "default_currency": "egp", "default_language": "en"},
        format="json",
    )
    assert resp.status_code == 200, resp.json()
    assert resp.json()["default_currency"] == "EGP"


def test_unknown_timezone_is_a_field_error(api_for):
    resp = api_for("admin").patch(URL, {"timezone": "Mars/Base"}, format="json")
    assert resp.status_code == 400
    assert "timezone" in resp.json()
```

`backend/etqan/tenants/tests/test_services.py` — append:

```python
@pytest.mark.django_db
def test_create_academy_records_its_settings(in_public):
    from etqan.academy.models import AcademySettings  # noqa: PLC0415

    academy = services.create_academy(
        name="Delta",
        subdomain="delta",
        admin_email="d@delta.test",
        timezone="Africa/Cairo",
        currency="EGP",
    )
    with tenant_context(academy):
        s = AcademySettings.objects.get()
        assert (s.timezone, s.default_currency, s.default_language) == (
            "Africa/Cairo",
            "EGP",
            "ar",
        )
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/platform/tests/test_validators.py etqan/platform/tests/test_role_permissions.py -q`
Expected: FAIL with `ModuleNotFoundError: etqan.platform.validators` / `ImportError: cannot import name 'IsAdmin'`. (The academy tests can't be collected until the app exists.)

- [ ] **Step 3: Implement platform pieces**

`backend/etqan/platform/validators.py`:

```python
"""Format checks shared by business modules. They raise etqan ValidationError."""

import re
from functools import cache
from zoneinfo import available_timezones

from django.core.exceptions import NON_FIELD_ERRORS
from django.core.exceptions import ValidationError as DjangoValidationError

from etqan.platform.exceptions import ValidationError

PHONE_RE = re.compile(r"^\+[1-9]\d{6,14}$")
CURRENCY_RE = re.compile(r"^[A-Z]{3}$")
COUNTRY_RE = re.compile(r"^[A-Z]{2}$")
LANGUAGES = ("ar", "en")


@cache
def _timezones() -> frozenset[str]:
    return frozenset(available_timezones())


def clean_phone(value: str | None, field: str = "phone") -> str:
    phone = re.sub(r"[\s-]", "", value or "")
    if phone and not PHONE_RE.fullmatch(phone):
        raise ValidationError(
            "Use international format, like +201001234567.", field=field
        )
    return phone


def clean_timezone(value: str, field: str = "timezone") -> str:
    if value not in _timezones():
        raise ValidationError("Unknown timezone.", field=field)
    return value


def clean_currency(value: str, field: str) -> str:
    code = (value or "").strip().upper()
    if not CURRENCY_RE.fullmatch(code):
        raise ValidationError(
            "Use a three-letter currency code, like EGP.", field=field
        )
    return code


def clean_country(value: str | None, field: str = "country") -> str:
    code = (value or "").strip().upper()
    if code and not COUNTRY_RE.fullmatch(code):
        raise ValidationError("Use a two-letter country code, like EG.", field=field)
    return code


def clean_language(value: str, field: str = "preferred_language") -> str:
    if value not in LANGUAGES:
        raise ValidationError("Choose Arabic or English.", field=field)
    return value


def from_django(exc: DjangoValidationError) -> ValidationError:
    """First message of a Django model ValidationError, as a domain error."""
    if hasattr(exc, "error_dict"):
        for field, messages in exc.message_dict.items():
            name = None if field == NON_FIELD_ERRORS else field
            return ValidationError(messages[0], field=name)
    return ValidationError(exc.messages[0])
```

`backend/etqan/platform/permissions.py` — add below `DocsPermission`:

```python
from rest_framework.permissions import SAFE_METHODS  # at the top with the other import


def role_of(user) -> str | None:
    """The signed-in user's academy role, or None for anonymous visitors."""
    if user is None or not getattr(user, "is_authenticated", False):
        return None
    return getattr(user, "role", None)


class _HasRole(BasePermission):
    role = ""

    def has_permission(self, request, view):
        return role_of(request.user) == self.role


class IsAdmin(_HasRole):
    role = "admin"


class IsTeacher(_HasRole):
    role = "teacher"


class IsParent(_HasRole):
    role = "parent"


class IsStudent(_HasRole):
    role = "student"


class ReadOnly(BasePermission):
    """Any signed-in user, safe methods only. Compose: `[IsAdmin | ReadOnly]`."""

    def has_permission(self, request, view):
        return role_of(request.user) is not None and request.method in SAFE_METHODS
```

`backend/etqan/platform/drf.py`: change the import line to `from rest_framework.views import exception_handler as drf_exception_handler` **plus** `from rest_framework.views import set_rollback`, and make the first line inside `if isinstance(exc, EtqanError):` be:

```python
        # Same as DRF's own handler: with ATOMIC_REQUESTS a domain error raised
        # after a partial write must not commit that write (D16).
        set_rollback()
```

- [ ] **Step 4: Implement the academy app**

`backend/etqan/academy/__init__.py` and `backend/etqan/academy/api/__init__.py` and `backend/etqan/academy/migrations/__init__.py` — empty.

`backend/etqan/academy/apps.py`:

```python
from django.apps import AppConfig


class AcademyConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.academy"
    label = "academy"
    verbose_name = "Academy settings"
```

`backend/etqan/academy/models.py`:

```python
from django.core.validators import RegexValidator
from django.db import models


class AcademySettings(models.Model):
    """One row per academy schema. Name, logo and colours stay in site.Branding."""

    class Language(models.TextChoices):
        AR = "ar", "Arabic"
        EN = "en", "English"

    timezone = models.CharField(max_length=64, default="UTC")
    default_currency = models.CharField(
        max_length=3, default="USD", validators=[RegexValidator(r"^[A-Z]{3}$")]
    )
    default_language = models.CharField(
        max_length=2, choices=Language.choices, default=Language.AR
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "academy settings"

    def __str__(self):
        return f"AcademySettings<{self.timezone}, {self.default_currency}>"
```

`backend/etqan/academy/services.py`:

```python
"""Public API for the academy module: the per-academy settings singleton."""

from django.db import connection

from etqan.academy.models import AcademySettings
from etqan.platform.validators import clean_currency
from etqan.platform.validators import clean_language
from etqan.platform.validators import clean_timezone


def ensure_settings(
    *, timezone: str = "UTC", currency: str = "USD", language: str = "ar"
) -> AcademySettings:
    """Create the current academy's settings row if it is missing. Idempotent."""
    existing = AcademySettings.objects.first()
    if existing is not None:
        return existing
    return AcademySettings.objects.create(
        timezone=timezone, default_currency=currency, default_language=language
    )


def get_settings() -> AcademySettings:
    """The current academy's settings, self-healed from its Academy row."""
    existing = AcademySettings.objects.first()
    if existing is not None:
        return existing
    tenant = getattr(connection, "tenant", None)
    return ensure_settings(
        timezone=getattr(tenant, "timezone", None) or "UTC",
        currency=getattr(tenant, "currency", None) or "USD",
    )


def update_settings(
    *,
    timezone: str | None = None,
    default_currency: str | None = None,
    default_language: str | None = None,
) -> AcademySettings:
    settings_row = get_settings()
    if timezone is not None:
        settings_row.timezone = clean_timezone(timezone)
    if default_currency is not None:
        settings_row.default_currency = clean_currency(
            default_currency, field="default_currency"
        )
    if default_language is not None:
        settings_row.default_language = clean_language(
            default_language, field="default_language"
        )
    settings_row.save()
    return settings_row
```

`backend/etqan/academy/api/serializers.py`:

```python
from rest_framework import serializers


class AcademySettingsSerializer(serializers.Serializer):
    timezone = serializers.CharField(max_length=64, required=False)
    default_currency = serializers.CharField(max_length=3, required=False)
    default_language = serializers.ChoiceField(choices=["ar", "en"], required=False)
    updated_at = serializers.DateTimeField(read_only=True)
```

`backend/etqan/academy/api/views.py`:

```python
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.academy import services
from etqan.academy.api.serializers import AcademySettingsSerializer
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import ReadOnly


class AcademySettingsView(APIView):
    permission_classes = [IsAdmin | ReadOnly]

    def get(self, request):
        return Response(AcademySettingsSerializer(services.get_settings()).data)

    def patch(self, request):
        serializer = AcademySettingsSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        updated = services.update_settings(**serializer.validated_data)
        return Response(AcademySettingsSerializer(updated).data)
```

`backend/etqan/academy/api/urls.py`:

```python
from django.urls import path

from etqan.academy.api.views import AcademySettingsView

app_name = "academy"
urlpatterns = [path("settings/", AcademySettingsView.as_view(), name="settings")]
```

`config/settings/base.py`: append `"etqan.academy",` to `TENANT_APPS` (after `"etqan.site"`). `config/api_router.py`: add `path("academy/", include("etqan.academy.api.urls")),` after the `site/` line.

Generate the schema migration: `.venv/bin/python manage.py makemigrations academy` (creates `0001_initial.py`). Then write the data migration `backend/etqan/academy/migrations/0002_settings_from_academy.py`:

```python
"""Existing academies get a settings row from their public Academy row."""

from django.db import migrations


def forwards(apps, schema_editor):
    schema = schema_editor.connection.schema_name
    AcademySettings = apps.get_model("academy", "AcademySettings")
    if AcademySettings.objects.exists():
        return
    with schema_editor.connection.cursor() as cursor:
        cursor.execute(
            "SELECT timezone, currency FROM public.tenants_academy "
            "WHERE schema_name = %s",
            [schema],
        )
        row = cursor.fetchone()
    timezone, currency = row if row else ("UTC", "USD")
    AcademySettings.objects.create(
        timezone=timezone, default_currency=currency, default_language="ar"
    )


class Migration(migrations.Migration):
    dependencies = [("academy", "0001_initial")]
    operations = [migrations.RunPython(forwards, migrations.RunPython.noop)]
```

`etqan/tenants/services.py` — in `create_academy`, import `from etqan.academy import services as academy_services` and make the first line inside `with tenant_context(academy):`:

```python
        academy_services.ensure_settings(timezone=timezone, currency=currency)
```

`pyproject.toml`: add `"etqan.academy"` to the `forbidden_modules` of "platform imports no business modules", and append:

```toml
[[tool.importlinter.contracts]]
name = "academy imports no other business module"
type = "forbidden"
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site"]
```

- [ ] **Step 5: Run the tests**

Run: `.venv/bin/pytest --create-db -q etqan/platform etqan/academy etqan/tenants/tests/test_services.py`
Expected: PASS.

- [ ] **Step 6: Full suite, linters, commit**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`
Expected: PASS.

```bash
git -C backend add -A
git -C backend commit -m "feat(academy): academy settings app, role permissions and rollback on domain errors

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Identity data model — email-optional users, TutorHamster profiles, `Guardianship`

**Files:**
- Modify: `backend/etqan/identity/models.py`, `backend/etqan/identity/admin.py`, `backend/etqan/identity/services.py` (`ParentStudent` → `Guardianship` in `get_children`, `is_parent_of`, `get_parent_user_ids`)
- Create: `backend/etqan/identity/migrations/0010_people_fields.py`, `0011_people_data.py`, `0012_people_cleanup.py`
- Test: `backend/etqan/identity/tests/test_models.py`, `test_profiles.py` (rewrite), `test_admin.py`, `test_services.py`, `test_api_auth.py` (rename `ParentStudent` → `Guardianship`)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `User.email` nullable, unique case-insensitively (constraint `identity_user_email_ci_unique`), `""` stored as `NULL`. `User.phone` (str, `""` default), `User.preferred_language` (`User.Language.AR/EN`, default `en`), `User.pending_email` (str, `""`). `str(user)` = email or full name or `User <pk>`. `User.birthdate` is removed.
  - `UserManager.create_user(email=None, password=None, **extra)` accepts no email; `create_superuser` still requires one.
  - Module-level `Gender` choices (`male`, `female`).
  - `StudentProfile(user, date_of_birth, gender, country, status=StudentProfile.Status.ACTIVE, notes)`; `StudentProfile.Status` values `active · trial · in_progress · paused · inactive`.
  - `TeacherProfile(user, gender, date_of_birth, bio, default_meeting_url, pay_currency="USD", payout_method, payout_details)`; `TeacherProfile.PayoutMethod`; `TeacherProfile.clean()` requires `payout_details` when `payout_method` is set.
  - `ParentProfile(user, has_whatsapp=False, notes)`.
  - `Guardianship(parent → ParentProfile related_name="child_links", student → StudentProfile related_name="guardian_links", created_at)`, unique pair.
  - Removed: `ParentInvite`, `StudentProfile.teacher_gender_preference`, `TeacherProfile.is_in_pool`, `TeacherProfile.internal_notes`.

- [ ] **Step 1: Write the failing tests**

`test_models.py` — delete `test_create_user_requires_email` and `test_str_is_email`, and add to `class TestUser`:

```python
    def test_user_without_email_is_allowed_and_cannot_sign_in(self):
        user = User.objects.create_user(email=None, full_name="Aisha")
        assert user.email is None
        assert not user.has_usable_password()
        assert authenticate(username=None, password="") is None

    def test_blank_email_is_stored_as_null_so_many_can_exist(self):
        first = User.objects.create_user(email="", full_name="A")
        User.objects.create_user(email="", full_name="B")
        first.refresh_from_db()
        assert first.email is None

    def test_email_is_unique_case_insensitively(self):
        User.objects.create_user(email="Dup@example.com", password="pw")
        with pytest.raises(IntegrityError):
            User.objects.create_user(email="dup@example.com", password="pw")

    def test_str_falls_back_to_full_name(self):
        assert str(User.objects.create_user(email="who@example.com")) == (
            "who@example.com"
        )
        assert str(User.objects.create_user(email=None, full_name="Zaid")) == "Zaid"

    def test_new_contact_fields_default_empty(self):
        user = User.objects.create_user(email="d@example.com")
        assert (user.phone, user.preferred_language, user.pending_email) == (
            "",
            "en",
            "",
        )

    def test_superuser_still_requires_email(self):
        with pytest.raises(ValueError, match="email"):
            User.objects.create_superuser(email=None, password="pw")
```

(add `from django.contrib.auth import authenticate`).

`test_profiles.py` — replace the whole file:

```python
import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError

from etqan.identity.models import Guardianship
from etqan.identity.models import ParentProfile
from etqan.identity.models import StudentProfile
from etqan.identity.models import TeacherProfile
from etqan.identity.models import User


def _user(email):
    return User.objects.create_user(email=email, password="pw")


@pytest.mark.django_db
class TestProfiles:
    def test_student_defaults(self):
        p = StudentProfile.objects.create(user=_user("kid@example.com"))
        assert (p.status, p.gender, p.country, p.date_of_birth, p.notes) == (
            "active",
            "",
            "",
            None,
            "",
        )

    def test_student_country_is_a_two_letter_code(self):
        p = StudentProfile(user=_user("k2@example.com"), country="Egypt")
        with pytest.raises(ValidationError) as exc:
            p.full_clean(exclude=["user"])
        assert "country" in exc.value.message_dict

    def test_teacher_defaults(self):
        p = TeacherProfile.objects.create(user=_user("t@example.com"))
        assert (p.pay_currency, p.bio, p.payout_method, p.default_meeting_url) == (
            "USD",
            "",
            "",
            "",
        )

    def test_teacher_payout_details_required_with_a_method(self):
        p = TeacherProfile(
            user=_user("t2@example.com"), gender="male", payout_method="wise"
        )
        with pytest.raises(ValidationError) as exc:
            p.full_clean(exclude=["user"])
        assert "payout_details" in exc.value.message_dict
        p.payout_details = "IBAN EG00 0000"
        p.full_clean(exclude=["user"])

    def test_parent_defaults(self):
        p = ParentProfile.objects.create(user=_user("mum@example.com"))
        assert (p.has_whatsapp, p.notes) == (False, "")

    def test_one_profile_per_user(self):
        user = _user("once@example.com")
        StudentProfile.objects.create(user=user)
        with pytest.raises(IntegrityError):
            StudentProfile.objects.create(user=user)


@pytest.mark.django_db
class TestGuardianship:
    def test_a_student_may_have_two_guardians(self):
        student = StudentProfile.objects.create(user=_user("s@example.com"))
        for email in ("p1@example.com", "p2@example.com"):
            parent = ParentProfile.objects.create(user=_user(email))
            Guardianship.objects.create(parent=parent, student=student)
        assert student.guardian_links.count() == 2

    def test_duplicate_link_raises(self):
        parent = ParentProfile.objects.create(user=_user("p@example.com"))
        student = StudentProfile.objects.create(user=_user("s2@example.com"))
        Guardianship.objects.create(parent=parent, student=student)
        with pytest.raises(IntegrityError):
            Guardianship.objects.create(parent=parent, student=student)
```

`test_admin.py` — the registration parametrize list becomes `[User, StudentProfile, TeacherProfile, ParentProfile, Guardianship]` (imports adjusted).

`test_services.py` and `test_api_auth.py` — replace every `ParentStudent` with `Guardianship` (import included).

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/identity/tests/test_models.py etqan/identity/tests/test_profiles.py -q`
Expected: FAIL. `ImportError: cannot import name 'Guardianship'`, and `ValueError: Users must have an email address.`

- [ ] **Step 3: Rewrite `etqan/identity/models.py`**

```python
from django.contrib.auth.models import AbstractBaseUser
from django.contrib.auth.models import BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.core.exceptions import ValidationError
from django.core.validators import RegexValidator
from django.db import models
from django.db.models.functions import Lower
from django.utils import timezone

COUNTRY_CODE = RegexValidator(r"^[A-Z]{2}$", "Use a two-letter country code.")
CURRENCY_CODE = RegexValidator(r"^[A-Z]{3}$", "Use a three-letter currency code.")


class Gender(models.TextChoices):
    MALE = "male", "Male"
    FEMALE = "female", "Female"


class UserManager(BaseUserManager["User"]):
    """Manager for the email-based custom User model. Email is optional (P3-1)."""

    use_in_migrations = True

    def create_user(self, email=None, password=None, **extra_fields):
        email = self.normalize_email(email) if email else None
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError("Superusers must have an email address.")
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """One account, one role. A user without email has no login (P3-1)."""

    class Role(models.TextChoices):
        ADMIN = "admin", "Admin"
        TEACHER = "teacher", "Teacher"
        STUDENT = "student", "Student"
        PARENT = "parent", "Parent"

    class Language(models.TextChoices):
        AR = "ar", "Arabic"
        EN = "en", "English"

    # NULL (not "") when absent, so the unique constraints allow many
    # email-less students.
    email = models.EmailField(unique=True, null=True, blank=True)  # noqa: DJ001
    full_name = models.CharField(max_length=255, blank=True, default="")
    phone = models.CharField(max_length=16, blank=True, default="")
    preferred_language = models.CharField(
        max_length=2, choices=Language.choices, default=Language.EN
    )
    # An admin-requested new address awaiting verification (plan D4).
    pending_email = models.EmailField(blank=True, default="")
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    date_joined = models.DateTimeField(default=timezone.now)
    timezone = models.CharField(max_length=64, default="UTC")
    role = models.CharField(max_length=16, choices=Role.choices, default=Role.STUDENT)

    objects = UserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    class Meta:
        constraints = [
            models.UniqueConstraint(
                Lower("email"), name="identity_user_email_ci_unique"
            ),
        ]

    def __str__(self):
        return self.email or self.full_name or f"User {self.pk}"

    def save(self, *args, **kwargs):
        if not self.email:
            self.email = None
        super().save(*args, **kwargs)


class StudentProfile(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        TRIAL = "trial", "Trial"
        IN_PROGRESS = "in_progress", "In progress"
        PAUSED = "paused", "Paused"
        INACTIVE = "inactive", "Inactive"

    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="student_profile"
    )
    date_of_birth = models.DateField(null=True, blank=True)
    gender = models.CharField(
        max_length=10, choices=Gender.choices, blank=True, default=""
    )
    country = models.CharField(
        max_length=2, blank=True, default="", validators=[COUNTRY_CODE]
    )
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.ACTIVE
    )
    notes = models.TextField(blank=True, default="")

    def __str__(self):
        return f"StudentProfile<{self.user}>"


class TeacherProfile(models.Model):
    class PayoutMethod(models.TextChoices):
        VODAFONE_CASH = "vodafone_cash", "Vodafone Cash"
        INSTAPAY = "instapay", "InstaPay"
        BANK_ACCOUNT = "bank_account", "Bank account"
        MASHREQ_NEO = "mashreq_neo", "Mashreq Neo"
        WESTERN_UNION = "western_union", "Western Union"
        WISE = "wise", "Wise"
        PAYPAL = "paypal", "PayPal"
        TELDA = "telda", "Telda"
        ABU_DHABI_BANK = "abu_dhabi_bank", "Abu Dhabi Bank"
        CASH = "cash", "Cash"
        STC_PAY = "stc_pay", "STC Pay"

    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="teacher_profile"
    )
    # "" only on rows that predate the requirement (plan D11); the API requires
    # male/female for every new or edited teacher.
    gender = models.CharField(
        max_length=10, choices=Gender.choices, blank=True, default=""
    )
    date_of_birth = models.DateField(null=True, blank=True)
    bio = models.TextField(blank=True, default="")
    default_meeting_url = models.URLField(blank=True, default="")
    pay_currency = models.CharField(
        max_length=3, default="USD", validators=[CURRENCY_CODE]
    )
    payout_method = models.CharField(
        max_length=32, choices=PayoutMethod.choices, blank=True, default=""
    )
    payout_details = models.TextField(blank=True, default="")

    def __str__(self):
        return f"TeacherProfile<{self.user}>"

    def clean(self):
        if self.payout_method and not self.payout_details.strip():
            raise ValidationError(
                {"payout_details": "Enter the payout details for this method."}
            )


class ParentProfile(models.Model):
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="parent_profile"
    )
    has_whatsapp = models.BooleanField(default=False)
    notes = models.TextField(blank=True, default="")

    def __str__(self):
        return f"ParentProfile<{self.user}>"


class Guardianship(models.Model):
    """A parent linked to a child. Many-to-many: a student may have several."""

    parent = models.ForeignKey(
        ParentProfile, on_delete=models.CASCADE, related_name="child_links"
    )
    student = models.ForeignKey(
        StudentProfile, on_delete=models.CASCADE, related_name="guardian_links"
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        unique_together = ("parent", "student")

    def __str__(self):
        return f"{self.parent.user} → {self.student.user}"
```

- [ ] **Step 4: Write the migrations by hand** (`makemigrations` cannot detect the rename non-interactively)

`backend/etqan/identity/migrations/0010_people_fields.py`:

```python
import django.core.validators
import django.db.models.deletion
from django.db import migrations
from django.db import models
from django.db.models.functions import Lower

GENDER = [("male", "Male"), ("female", "Female")]
STATUS = [
    ("active", "Active"),
    ("trial", "Trial"),
    ("in_progress", "In progress"),
    ("paused", "Paused"),
    ("inactive", "Inactive"),
]
PAYOUT = [
    ("vodafone_cash", "Vodafone Cash"),
    ("instapay", "InstaPay"),
    ("bank_account", "Bank account"),
    ("mashreq_neo", "Mashreq Neo"),
    ("western_union", "Western Union"),
    ("wise", "Wise"),
    ("paypal", "PayPal"),
    ("telda", "Telda"),
    ("abu_dhabi_bank", "Abu Dhabi Bank"),
    ("cash", "Cash"),
    ("stc_pay", "STC Pay"),
]
COUNTRY = django.core.validators.RegexValidator(
    "^[A-Z]{2}$", "Use a two-letter country code."
)
CURRENCY = django.core.validators.RegexValidator(
    "^[A-Z]{3}$", "Use a three-letter currency code."
)


class Migration(migrations.Migration):
    dependencies = [("identity", "0009_user_role")]

    operations = [
        migrations.AlterField(
            model_name="user",
            name="email",
            field=models.EmailField(
                blank=True, max_length=254, null=True, unique=True
            ),
        ),
        migrations.AddField(
            model_name="user",
            name="phone",
            field=models.CharField(blank=True, default="", max_length=16),
        ),
        migrations.AddField(
            model_name="user",
            name="preferred_language",
            field=models.CharField(
                choices=[("ar", "Arabic"), ("en", "English")],
                default="en",
                max_length=2,
            ),
        ),
        migrations.AddField(
            model_name="user",
            name="pending_email",
            field=models.EmailField(blank=True, default="", max_length=254),
        ),
        migrations.AddConstraint(
            model_name="user",
            constraint=models.UniqueConstraint(
                Lower("email"), name="identity_user_email_ci_unique"
            ),
        ),
        migrations.AddField(
            model_name="studentprofile",
            name="date_of_birth",
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="studentprofile",
            name="gender",
            field=models.CharField(
                blank=True, choices=GENDER, default="", max_length=10
            ),
        ),
        migrations.AddField(
            model_name="studentprofile",
            name="country",
            field=models.CharField(
                blank=True, default="", max_length=2, validators=[COUNTRY]
            ),
        ),
        migrations.AddField(
            model_name="studentprofile",
            name="status",
            field=models.CharField(choices=STATUS, default="active", max_length=16),
        ),
        migrations.AddField(
            model_name="teacherprofile",
            name="date_of_birth",
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="teacherprofile",
            name="bio",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="teacherprofile",
            name="default_meeting_url",
            field=models.URLField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="teacherprofile",
            name="pay_currency",
            field=models.CharField(
                default="USD", max_length=3, validators=[CURRENCY]
            ),
        ),
        migrations.AddField(
            model_name="teacherprofile",
            name="payout_method",
            field=models.CharField(
                blank=True, choices=PAYOUT, default="", max_length=32
            ),
        ),
        migrations.AddField(
            model_name="teacherprofile",
            name="payout_details",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="parentprofile",
            name="has_whatsapp",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="parentprofile",
            name="notes",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.RenameModel(old_name="ParentStudent", new_name="Guardianship"),
        migrations.AlterField(
            model_name="guardianship",
            name="parent",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="child_links",
                to="identity.parentprofile",
            ),
        ),
        migrations.AlterField(
            model_name="guardianship",
            name="student",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="guardian_links",
                to="identity.studentprofile",
            ),
        ),
    ]
```

`backend/etqan/identity/migrations/0011_people_data.py`:

```python
"""birthdate → profile date_of_birth; teacher internal_notes appended to bio (D12)."""

from django.db import migrations


def forwards(apps, schema_editor):
    User = apps.get_model("identity", "User")
    StudentProfile = apps.get_model("identity", "StudentProfile")
    TeacherProfile = apps.get_model("identity", "TeacherProfile")
    for user_id, birthdate in User.objects.exclude(birthdate=None).values_list(
        "id", "birthdate"
    ):
        StudentProfile.objects.filter(user_id=user_id, date_of_birth=None).update(
            date_of_birth=birthdate
        )
        TeacherProfile.objects.filter(user_id=user_id, date_of_birth=None).update(
            date_of_birth=birthdate
        )
    for teacher in TeacherProfile.objects.exclude(internal_notes=""):
        teacher.bio = f"{teacher.bio}\n\n{teacher.internal_notes}".strip()
        teacher.save(update_fields=["bio"])


class Migration(migrations.Migration):
    dependencies = [("identity", "0010_people_fields")]
    operations = [migrations.RunPython(forwards, migrations.RunPython.noop)]
```

`backend/etqan/identity/migrations/0012_people_cleanup.py`:

```python
from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [("identity", "0011_people_data")]

    operations = [
        migrations.RemoveField(model_name="user", name="birthdate"),
        migrations.RemoveField(
            model_name="studentprofile", name="teacher_gender_preference"
        ),
        migrations.RemoveField(model_name="teacherprofile", name="is_in_pool"),
        migrations.RemoveField(model_name="teacherprofile", name="internal_notes"),
        migrations.DeleteModel(name="ParentInvite"),
    ]
```

- [ ] **Step 5: Update `admin.py` and `services.py` references**

`etqan/identity/admin.py`:
- drop the `ParentInvite` import and `ParentInviteAdmin`;
- `ParentStudent` → `Guardianship` (`GuardianshipAdmin`, same `list_display`/`raw_id_fields`);
- `UserAdmin.list_display = ("id", "email", "full_name", "role", "is_active", "date_joined")`, `list_filter = ("role", "is_active", "is_staff")`, `search_fields = ("email", "full_name", "phone")`;
- `StudentProfileAdmin.list_display = ("id", "user", "status")` with `list_filter = ("status",)`;
- `TeacherProfileAdmin.list_display = ("id", "user", "gender", "pay_currency")` with `list_filter = ("gender",)`. In `send_password_set_email`, skip profiles whose `user.email` is empty before building the form.

`etqan/identity/services.py`: import `Guardianship` instead of `ParentStudent`. In `get_children`, filter `guardian_links__parent__user_id=parent_user_id`. In `is_parent_of` and `get_parent_user_ids`, use `Guardianship.objects`.

- [ ] **Step 6: Migrate and run**

Run: `.venv/bin/python manage.py makemigrations identity --check --dry-run`
Expected: `No changes detected` (the hand-written migrations match the models).

Run: `.venv/bin/pytest --create-db -q etqan/identity`
Expected: PASS.

Check the data migration once against a dev database that has data (`just seed` beforehand):

```bash
.venv/bin/python manage.py migrate_schemas --settings=config.settings.local
```

Expected: `identity.0010…0012` apply to `public`, `academy_demo` and `academy_other` without error.

- [ ] **Step 7: Full suite, linters, commit**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`

```bash
git -C backend add -A
git -C backend commit -m "feat(identity)!: email-optional users, phone and language, TutorHamster profiles, Guardianship

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Identity emails in the recipient's language

**Files:**
- Create: `backend/etqan/identity/emails.py`, `backend/etqan/templates/email/identity/{invite,reset,security_added,security_set_primary,security_password}.{ar,en}.txt`, `backend/etqan/templates/account/email/email_confirmation_{ar,en}_subject.txt`, `backend/etqan/templates/account/email/email_confirmation_{ar,en}_message.txt`, `backend/etqan/identity/tests/test_email_language.py`
- Modify: `backend/etqan/site/emails.py`, `backend/etqan/templates/email/layout.html`, `backend/etqan/identity/services.py`, `backend/etqan/identity/adapter.py`, `backend/etqan/site/tests/test_emails.py`

**Interfaces:**
- Consumes: `User.preferred_language` (Task 3).
- Produces:
  - `etqan.site.emails.brand_email(*, subject: str, body: str, language: str = "en") -> dict`. Inside an academy, From display name and subject prefix use `name_ar` when `language == "ar"`, else `name_en`; the HTML body cell carries `dir="rtl" lang="ar"` or `dir="ltr" lang="en"`; the text/HTML layout still shows both names. The public schema is unchanged (`[Etqan] …`).
  - `etqan.identity.emails.render_email(kind: str, language: str, **context) -> tuple[str, str]` (subject, body) with `kind ∈ {"invite", "reset", "security_added", "security_set_primary", "security_password"}` and `language_of(value) -> "ar" | "en"`.
  - `etqan.identity.services._send(to: str | None, subject: str, body: str, *, language: str)` skips a missing recipient. `_send_invite(user)` renders `invite` in `user.preferred_language`. `_send_email_security_alert(*, to_email, action, language)`.
  - `CeleryAccountAdapter.send_mail` renders `<prefix>_<lang>` templates when they exist (confirmation emails), falling back to allauth's.

- [ ] **Step 1: Write the failing tests** — `backend/etqan/identity/tests/test_email_language.py`

```python
import pytest
from allauth.account.models import EmailAddress
from django.core import mail
from django.db import connection
from django.test import override_settings

from etqan.identity import services
from etqan.identity.models import User
from etqan.site.emails import brand_email
from etqan.site.models import Branding
from etqan.site.services import ensure_site_defaults

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def branded():
    ensure_site_defaults("x")
    Branding.objects.update(name_en="Noor Academy", name_ar="أكاديمية نور")


@override_settings(DEFAULT_FROM_EMAIL="etqan <noreply@etqan.test>")
def test_brand_email_uses_the_arabic_name_for_arabic_readers():
    out = brand_email(subject="عيّن كلمة المرور", body="نص", language="ar")
    assert out["subject"] == "[أكاديمية نور] عيّن كلمة المرور"
    assert out["from_email"] == '"أكاديمية نور" <noreply@etqan.test>'
    assert 'dir="rtl"' in out["html"]
    assert "Noor Academy" in out["body"]  # the layout keeps both names


def test_brand_email_defaults_to_english():
    out = brand_email(subject="Hello", body="Body")
    assert out["subject"] == "[Noor Academy] Hello"
    assert 'dir="ltr"' in out["html"]


def test_public_schema_mail_keeps_etqan_in_english():
    connection.set_schema_to_public()
    assert brand_email(subject="Hi", body="b", language="ar")["subject"] == (
        "[Etqan] Hi"
    )


def _user(language, email="r@x.test"):
    user = User.objects.create_user(
        email=email, password="pw-12345678", preferred_language=language
    )
    EmailAddress.objects.create(user=user, email=email, primary=True, verified=True)
    return user


def test_reset_email_arabic():
    _user("ar")
    services.request_password_reset("r@x.test")
    msg = mail.outbox[-1]
    assert msg.subject == "[أكاديمية نور] إعادة تعيين كلمة المرور"
    assert "/app/reset-password?uid=" in msg.body
    assert "طلبًا لإعادة تعيين" in msg.body


def test_reset_email_english():
    _user("en")
    services.request_password_reset("r@x.test")
    assert mail.outbox[-1].subject == "[Noor Academy] Reset your password"


def test_security_alert_follows_the_language():
    user = _user("ar")
    services.change_password(user.id, "pw-12345678", "new-pw-12345678")
    assert "تنبيه أمني" in mail.outbox[-1].subject


def test_allauth_confirmation_is_arabic_for_arabic_readers():
    user = User.objects.create_user(
        email="c@x.test", password="pw", preferred_language="ar"
    )
    address = EmailAddress.objects.create(
        user=user, email="c@x.test", primary=True, verified=False
    )
    address.send_confirmation(None)
    msg = mail.outbox[-1]
    assert msg.subject == "[أكاديمية نور] تأكيد عنوان البريد الإلكتروني"
    assert "/app/verify-email?key=" in msg.body
    assert "c@x.test" not in msg.body


def test_no_recipient_sends_nothing():
    services._send(None, "s", "b", language="en")  # noqa: SLF001
    assert mail.outbox == []
```

In `backend/etqan/site/tests/test_emails.py`, `test_brand_email_in_academy` is unchanged. It still passes because the default language is `en`.

- [ ] **Step 2: Run it to verify it fails**

Run: `.venv/bin/pytest etqan/identity/tests/test_email_language.py -q`
Expected: FAIL (`TypeError: brand_email() got an unexpected keyword argument 'language'`).

- [ ] **Step 3: Implement**

`etqan/site/emails.py` — change the signature and the academy branch:

```python
def brand_email(*, subject: str, body: str, language: str = "en") -> dict:
    """Wrap ``subject``/``body`` with the current academy's branding.

    ``language`` (``ar`` or ``en``) picks the academy name used in the From
    display name and the subject prefix, and the HTML text direction. The
    layout always shows both names (P3-8).
    """
```

and replace the block from `context = {` to the `return` with:

```python
    arabic = language == "ar"
    name = branding.name_ar if arabic else branding.name_en
    context = {
        "name_en": branding.name_en,
        "name_ar": branding.name_ar,
        "body": body,
        "contact_email": branding.contact_email,
        "contact_phone": branding.contact_phone,
        "home_url": home,
        "primary_color": branding.primary_color,
        "primary_text": branding.primary_text,
        "logo_url": logo_url,
        "dir": "rtl" if arabic else "ltr",
        "lang": "ar" if arabic else "en",
    }
    _, address = parseaddr(settings.DEFAULT_FROM_EMAIL)
    return {
        "subject": f"[{name}] {subject}",
        "body": render_to_string("email/layout.txt", context).strip() + "\n",
        "html": render_to_string("email/layout.html", context),
        "from_email": _quoted_from_header(name, address),
    }
```

`etqan/templates/email/layout.html` — the body row becomes:

```html
<tr><td dir="{{ dir }}" lang="{{ lang }}" style="padding:24px;font-size:15px;line-height:1.6;white-space:pre-line;text-align:start">{{ body|urlize }}</td></tr>
```

`etqan/identity/emails.py`:

```python
"""Identity email bodies in Arabic and English (P3-8)."""

from django.template.loader import render_to_string

LANGUAGES = ("ar", "en")
_SECURITY = {
    "en": "Security alert: a change was made to your account",
    "ar": "تنبيه أمني: تم إجراء تغيير على حسابك",
}
SUBJECTS = {
    "invite": {"en": "Set your password", "ar": "عيّن كلمة المرور"},
    "reset": {"en": "Reset your password", "ar": "إعادة تعيين كلمة المرور"},
    "security_added": _SECURITY,
    "security_set_primary": _SECURITY,
    "security_password": _SECURITY,
}


def language_of(value) -> str:
    return value if value in LANGUAGES else "en"


def render_email(kind: str, language: str, **context) -> tuple[str, str]:
    lang = language_of(language)
    body = render_to_string(f"email/identity/{kind}.{lang}.txt", context).strip()
    return SUBJECTS[kind][lang], body
```

Templates under `etqan/templates/email/identity/` (keep every URL on its own line with nothing after it, per ADR-0023):

`invite.en.txt`
```
{% autoescape off %}Hello{% if name %} {{ name }}{% endif %},

An account was created for you. Set your password to get started:

{{ link }}

If you weren't expecting this, you can ignore this email.{% endautoescape %}
```

`invite.ar.txt`
```
{% autoescape off %}مرحبًا{% if name %} {{ name }}{% endif %}،

أُنشئ لك حساب. عيّن كلمة المرور للبدء:

{{ link }}

إن لم تكن تتوقع هذه الرسالة فيمكنك تجاهلها.{% endautoescape %}
```

`reset.en.txt`
```
{% autoescape off %}We received a request to reset your password.

Reset it here:
{{ link }}

If you didn't request this, you can safely ignore this email.{% endautoescape %}
```

`reset.ar.txt`
```
{% autoescape off %}تلقّينا طلبًا لإعادة تعيين كلمة المرور الخاصة بك.

أعد تعيينها من هنا:
{{ link }}

إن لم تطلب ذلك فيمكنك تجاهل هذه الرسالة.{% endautoescape %}
```

`security_added.en.txt`
```
{% autoescape off %}A new email address was added to your account and is pending verification. If this wasn't you, change your password immediately and contact support.

Review your account's email addresses:
{{ review_url }}{% endautoescape %}
```

`security_added.ar.txt`
```
{% autoescape off %}أُضيف عنوان بريد إلكتروني جديد إلى حسابك وهو بانتظار التأكيد. إن لم تكن أنت، فغيّر كلمة المرور فورًا وتواصل مع الدعم.

راجع عناوين البريد في حسابك:
{{ review_url }}{% endautoescape %}
```

`security_set_primary.en.txt`
```
{% autoescape off %}The primary email address on your account was changed. If this wasn't you, change your password immediately and contact support.

Review your account:
{{ review_url }}{% endautoescape %}
```

`security_set_primary.ar.txt`
```
{% autoescape off %}تم تغيير عنوان البريد الأساسي لحسابك. إن لم تكن أنت، فغيّر كلمة المرور فورًا وتواصل مع الدعم.

راجع حسابك:
{{ review_url }}{% endautoescape %}
```

`security_password.en.txt`
```
{% autoescape off %}The password on your account was changed. If this wasn't you, reset your password immediately and contact support.

Reset your password:
{{ reset_url }}{% endautoescape %}
```

`security_password.ar.txt`
```
{% autoescape off %}تم تغيير كلمة مرور حسابك. إن لم تكن أنت، فأعد تعيين كلمة المرور فورًا وتواصل مع الدعم.

أعد تعيين كلمة المرور:
{{ reset_url }}{% endautoescape %}
```

allauth confirmation templates under `etqan/templates/account/email/`:

`email_confirmation_en_subject.txt` → `Confirm your email address`
`email_confirmation_ar_subject.txt` → `تأكيد عنوان البريد الإلكتروني`

`email_confirmation_en_message.txt`
```
{% autoescape off %}Please confirm this email address for your account.

To confirm, follow this link:

{{ activate_url }}

If you did not request this, you can safely ignore this email.{% endautoescape %}
```

`email_confirmation_ar_message.txt`
```
{% autoescape off %}يُرجى تأكيد عنوان البريد الإلكتروني هذا لحسابك.

للتأكيد افتح الرابط التالي:

{{ activate_url }}

إن لم تطلب ذلك فيمكنك تجاهل هذه الرسالة.{% endautoescape %}
```

`etqan/identity/services.py` — import `from etqan.identity.emails import render_email`, then replace `_send`, `_send_invite`, the body of `request_password_reset` after the token lines, and `_send_email_security_alert`:

```python
def _send(to: str | None, subject: str, body: str, *, language: str) -> None:
    """Brand for the current academy in ``language`` and hand off to Celery.

    A person without an email simply gets nothing (P3-1).
    """
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


def _send_invite(user: User) -> None:
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = default_token_generator.make_token(user)
    link = app_url(f"/reset-password?uid={uid}&token={token}")
    subject, body = render_email(
        "invite", user.preferred_language, name=user.full_name, link=link
    )
    _send(user.email, subject, body, language=user.preferred_language)
```

In `request_password_reset`, after `reset_url = …`:

```python
    subject, body = render_email("reset", user.preferred_language, link=reset_url)
    _send(email, subject, body, language=user.preferred_language)
```

```python
_ALERT_KINDS = {
    "added": "security_added",
    "set_primary": "security_set_primary",
    "password_changed": "security_password",
    "password_reset": "security_password",
}


def _send_email_security_alert(*, to_email: str, action: str, language: str) -> None:
    """Security alert about ``action``. Never names the changed address (ADR-0023).

    An unknown ``action`` raises: a typo must not tell a user the wrong reason
    for a change to their credentials.
    """
    kind = _ALERT_KINDS.get(action)
    if kind is None:
        raise ValueError(f"Unknown security alert action: {action!r}")
    subject, body = render_email(
        kind,
        language,
        review_url=app_url("/account"),
        reset_url=app_url("/forgot-password"),
    )
    _send(to_email, subject, body, language=language)
```

Pass `language=user.preferred_language` at the four existing call sites (`change_password`, `confirm_password_reset`, `add_email_address`, `set_primary_email`). If an existing test asserts the `ValueError` for an unknown action, update its call to pass `language="en"`.

`etqan/identity/adapter.py`:

```python
from allauth.account.adapter import DefaultAccountAdapter
from django.template import TemplateDoesNotExist

from etqan.identity.emails import language_of
from etqan.platform.frontend import app_url
from etqan.platform.tasks import send_email_message
from etqan.site.emails import brand_email


class CeleryAccountAdapter(DefaultAccountAdapter):
    """allauth emails rendered in the recipient's language, sent via Celery."""

    def send_mail(self, template_prefix, email, context):
        user = context.get("user")
        language = language_of(getattr(user, "preferred_language", None))
        try:
            message = self.render_mail(f"{template_prefix}_{language}", email, context)
        except TemplateDoesNotExist:
            message = self.render_mail(template_prefix, email, context)
        branded = brand_email(
            subject=message.subject, body=message.body, language=language
        )
        send_email_message.delay(
            subject=branded["subject"],
            body=branded["body"],
            from_email=branded["from_email"],
            to=list(message.to),
            alternatives=[[branded["html"], "text/html"]] if branded["html"] else None,
        )
```

Keep `get_email_confirmation_url` and `is_open_for_signup` unchanged.

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest -q etqan/identity etqan/site etqan/tenants`
Expected: PASS. Existing English assertions still hold because model-created users default to `en`.

- [ ] **Step 5: Linters, commit**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports
git -C backend add -A
git -C backend commit -m "feat(identity): emails in the recipient's language with the academy name in that language

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: People services — create, edit, invite, account actions, guardianship

**Files:**
- Create: `backend/etqan/identity/signals.py`, `backend/etqan/identity/scopes.py`, `backend/etqan/identity/tests/test_people_services.py`
- Modify: `backend/etqan/identity/services.py`, `backend/etqan/identity/apps.py`

**Interfaces:**
- Consumes: `academy_services.get_settings()` (Task 2); `clean_*`/`from_django` (Task 2); models (Task 3); `_send_invite`, `_send_email_security_alert`, `render_email` (Task 4).
- Produces (all in `etqan.identity.services`, all raise `etqan.platform.exceptions.ValidationError(message, field)` on bad input):
  - `create_person(role: str, *, full_name: str, email: str | None = None, phone: str | None = None, preferred_language: str | None = None, timezone: str | None = None, profile: dict | None = None, invite: bool = True, created_by: User | None = None) -> User`
  - `update_person(user: User, *, fields: dict | None = None, profile: dict | None = None) -> User` (`fields` keys: `full_name, email, phone, preferred_language, timezone`)
  - `change_person_email(user: User, email: str | None) -> None` (plan D4)
  - `promote_pending_email(address: EmailAddress) -> None` (called by the `email_confirmed` signal)
  - `account_state(user: User) -> str` ∈ `no_login · inactive · invited · active`
  - `resend_invite(user: User) -> None`, `send_password_reset(user: User) -> None`
  - `deactivate(user: User, *, by: User | None) -> None`, `activate(user: User) -> None`
  - `bulk_update_students(user_ids: list[int], action: str, *, status: str | None = None, by: User | None = None) -> int` (`action ∈ activate · deactivate · set_status`)
  - `link_guardian(parent: User, student: User) -> None`, `unlink_guardian(parent: User, student: User) -> None` (both idempotent), `guardians_of(student: User) -> list[User]`, `children_of(parent: User) -> list[User]`
  - `people_queryset(role: str) -> QuerySet[User]` (profile `select_related`, parent children prefetched), `get_person(role: str, user_id: int) -> User` (raises `NotFoundError`)
  - `teacher_profiles_for(user_ids: list[int]) -> list[TeacherProfile]` (raises `ValidationError(field="teacher_ids")` when any id is not a teacher)
  - `has_people() -> bool` (any non-admin user exists)
  - `PROFILE_FIELDS: dict[str, frozenset[str]]`, `USER_FIELDS = frozenset({"full_name", "email", "phone", "preferred_language", "timezone"})`
  - `etqan.identity.scopes.scope_for(user, queryset)`: admins get the queryset, everyone else `queryset.none()`.

- [ ] **Step 1: Write the failing tests** — `backend/etqan/identity/tests/test_people_services.py`

```python
import pytest
from allauth.account.models import EmailAddress
from allauth.account.models import EmailConfirmationHMAC
from django.contrib.auth import authenticate
from django.contrib.auth.tokens import default_token_generator
from django.core import mail
from django.test import Client
from django.test import RequestFactory
from django_tenants.utils import tenant_context

from etqan.academy import services as academy_services
from etqan.identity import services
from etqan.identity.models import Guardianship
from etqan.identity.models import User
from etqan.identity.scopes import scope_for
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


def admin(email="boss@x.test"):
    return User.objects.create_user(email=email, password="pw-12345678", role="admin")


def student(**kw):
    kw.setdefault("full_name", "Yusuf")
    kw.setdefault("profile", {})
    return services.create_person("student", **kw)


class TestCreatePerson:
    def test_student_without_email_has_no_login_and_no_mail(self):
        user = student()
        assert user.email is None
        assert services.account_state(user) == "no_login"
        assert user.student_profile.status == "active"
        assert mail.outbox == []
        assert authenticate(username=None, password="") is None

    def test_defaults_come_from_academy_settings(self):
        academy_services.update_settings(
            timezone="Africa/Cairo", default_language="ar", default_currency="EGP"
        )
        user = services.create_person(
            "teacher", full_name="Bilal", profile={"gender": "male"}
        )
        assert (user.timezone, user.preferred_language) == ("Africa/Cairo", "ar")
        assert user.teacher_profile.pay_currency == "EGP"

    def test_with_email_sends_one_branded_invite_in_their_language(self):
        user = student(email="Yusuf@Example.com", preferred_language="ar")
        assert user.email == "Yusuf@example.com"
        assert services.account_state(user) == "invited"
        assert len(mail.outbox) == 1
        assert mail.outbox[0].to == ["Yusuf@example.com"]
        assert "/app/reset-password?uid=" in mail.outbox[0].body
        assert "عيّن كلمة المرور" in mail.outbox[0].subject
        assert not EmailAddress.objects.get(user=user).verified

    def test_invite_false_sends_nothing(self):
        student(email="quiet@x.test", invite=False)
        assert mail.outbox == []

    @pytest.mark.parametrize("taken", ["DUP@x.test", "dup@X.TEST"])
    def test_duplicate_email_case_insensitive(self, taken):
        student(email="dup@x.test")
        with pytest.raises(ValidationError) as exc:
            student(email=taken)
        assert exc.value.field == "email"

    def test_email_taken_by_a_secondary_address_is_refused(self):
        other = admin()
        EmailAddress.objects.create(user=other, email="second@x.test")
        with pytest.raises(ValidationError):
            student(email="second@x.test")

    @pytest.mark.parametrize(
        ("kwargs", "field"),
        [
            ({"full_name": "  "}, "full_name"),
            ({"phone": "0100"}, "phone"),
            ({"timezone": "Mars/Base"}, "timezone"),
            ({"preferred_language": "fr"}, "preferred_language"),
            ({"profile": {"country": "Egypt"}}, "country"),
            ({"profile": {"status": "graduated"}}, "status"),
            ({"profile": {"favourite_colour": "green"}}, "favourite_colour"),
        ],
    )
    def test_invalid_input_names_the_field(self, kwargs, field):
        with pytest.raises(ValidationError) as exc:
            student(**kwargs)
        assert exc.value.field == field
        assert not User.objects.filter(role="student").exists()

    def test_teacher_needs_gender_and_payout_details_with_a_method(self):
        with pytest.raises(ValidationError) as exc:
            services.create_person("teacher", full_name="T", profile={})
        assert exc.value.field == "gender"
        with pytest.raises(ValidationError) as exc:
            services.create_person(
                "teacher",
                full_name="T",
                profile={"gender": "female", "payout_method": "wise"},
            )
        assert exc.value.field == "payout_details"

    def test_admin_has_no_profile(self):
        user = services.create_person("admin", full_name="A2", email="a2@x.test")
        assert services.get_profile_types(user.id) == []

    def test_unknown_role(self):
        with pytest.raises(ValidationError):
            services.create_person("wizard", full_name="W")


class TestUpdatePerson:
    def test_adding_an_email_later_sends_exactly_one_invite(self):
        user = student()
        services.update_person(user, fields={"email": "later@x.test"})
        user.refresh_from_db()
        assert user.email == "later@x.test"
        assert services.account_state(user) == "invited"
        assert [m.to for m in mail.outbox] == [["later@x.test"]]

    def test_changing_an_invited_email_replaces_it_and_kills_the_old_link(self):
        user = student(email="typo@x.test")
        old_token = default_token_generator.make_token(user)
        services.update_person(user, fields={"email": "right@x.test"})
        user.refresh_from_db()
        assert user.email == "right@x.test"
        assert not default_token_generator.check_token(user, old_token)
        assert list(EmailAddress.objects.filter(user=user).values_list("email")) == [
            ("right@x.test",)
        ]

    def test_signed_in_user_keeps_old_email_until_new_one_is_verified(self):
        user = student(email="old@x.test", invite=False)
        user.set_password("pw-12345678")
        user.save()
        mail.outbox.clear()
        services.update_person(user, fields={"email": "new@x.test"})
        user.refresh_from_db()
        assert (user.email, user.pending_email) == ("old@x.test", "new@x.test")
        assert mail.outbox[-1].to == ["new@x.test"]
        address = EmailAddress.objects.get(email="new@x.test")
        EmailConfirmationHMAC(address).confirm(RequestFactory().get("/"))
        user.refresh_from_db()
        assert (user.email, user.pending_email) == ("new@x.test", "")
        assert mail.outbox[-1].to == ["old@x.test"]  # security alert

    def test_an_email_cannot_be_removed(self):
        user = student(email="keep@x.test")
        with pytest.raises(ValidationError):
            services.update_person(user, fields={"email": ""})

    def test_profile_and_contact_fields(self):
        user = student()
        services.update_person(
            user,
            fields={"phone": "+201001234567", "full_name": "Yusuf O."},
            profile={"status": "paused", "country": "eg"},
        )
        user.refresh_from_db()
        assert (user.phone, user.full_name) == ("+201001234567", "Yusuf O.")
        assert (user.student_profile.status, user.student_profile.country) == (
            "paused",
            "EG",
        )

    def test_teacher_gender_cannot_be_cleared(self):
        teacher = services.create_person(
            "teacher", full_name="T", profile={"gender": "male"}
        )
        with pytest.raises(ValidationError) as exc:
            services.update_person(teacher, profile={"gender": ""})
        assert exc.value.field == "gender"


class TestInvitesAndResets:
    def test_resend_invite_only_while_invited(self):
        with pytest.raises(ValidationError):
            services.resend_invite(student())
        user = student(email="inv@x.test")
        services.resend_invite(user)
        assert len(mail.outbox) == 2
        user.set_password("pw-12345678")
        user.save()
        with pytest.raises(ValidationError):
            services.resend_invite(user)

    def test_password_reset_needs_an_email_and_an_active_account(self):
        with pytest.raises(ValidationError):
            services.send_password_reset(student())
        user = student(email="r@x.test", invite=False)
        services.send_password_reset(user)
        assert "/app/reset-password?uid=" in mail.outbox[-1].body
        services.deactivate(user, by=None)
        with pytest.raises(ValidationError):
            services.send_password_reset(user)

    def test_using_the_invite_verifies_the_email(self):
        user = student(email="use@x.test")
        uid = mail.outbox[-1].body.split("uid=")[1].split("&")[0]
        token = default_token_generator.make_token(user)
        services.confirm_password_reset(uid, token, "brand-new-pw-1")
        assert EmailAddress.objects.get(user=user).verified
        assert services.account_state(User.objects.get(pk=user.pk)) == "active"


class TestDeactivate:
    def test_admin_cannot_deactivate_themselves(self):
        me = admin()
        admin("second@x.test")
        with pytest.raises(ValidationError, match="your own"):
            services.deactivate(me, by=me)

    def test_last_active_admin_cannot_be_deactivated(self):
        only = admin()
        with pytest.raises(ValidationError, match="at least one active admin"):
            services.deactivate(only, by=None)
        second = admin("second@x.test")
        services.deactivate(second, by=only)
        with pytest.raises(ValidationError):
            services.deactivate(only, by=None)

    def test_deactivation_ends_sessions_and_activation_restores(self):
        user = student(email="s@x.test", invite=False)
        user.set_password("pw-12345678")
        user.save()
        browser = Client()
        browser.force_login(user)
        assert browser.get("/api/v1/identity/me/").status_code == 200
        services.deactivate(user, by=admin())
        assert services.account_state(User.objects.get(pk=user.pk)) == "inactive"
        assert browser.get("/api/v1/identity/me/").status_code == 403
        services.activate(user)
        assert User.objects.get(pk=user.pk).is_active

    def test_bulk_updates_only_students(self):
        a, b = student(), student(full_name="Aisha")
        boss = admin()
        assert services.bulk_update_students([a.id, b.id, boss.id], "deactivate") == 2
        assert User.objects.get(pk=boss.pk).is_active
        n = services.bulk_update_students([a.id], "set_status", status="trial")
        assert n == 1
        assert User.objects.get(pk=a.pk).student_profile.status == "trial"
        with pytest.raises(ValidationError):
            services.bulk_update_students([a.id], "set_status", status="bogus")


class TestGuardianship:
    def test_link_is_idempotent_and_lists_both_ways(self):
        parent = services.create_person("parent", full_name="Omar", profile={})
        kid = student()
        services.link_guardian(parent, kid)
        services.link_guardian(parent, kid)
        assert Guardianship.objects.count() == 1
        assert services.guardians_of(kid) == [parent]
        assert services.children_of(parent) == [kid]
        services.unlink_guardian(parent, kid)
        services.unlink_guardian(parent, kid)
        assert services.children_of(parent) == []

    def test_roles_must_match(self):
        kid = student()
        with pytest.raises(ValidationError):
            services.link_guardian(kid, kid)


class TestLookups:
    def test_get_person_is_role_scoped(self):
        kid = student()
        assert services.get_person("student", kid.id) == kid
        with pytest.raises(NotFoundError):
            services.get_person("teacher", kid.id)

    def test_teacher_profiles_for_rejects_non_teachers(self):
        t = services.create_person("teacher", full_name="T", profile={"gender": "male"})
        assert services.teacher_profiles_for([t.id]) == [t.teacher_profile]
        with pytest.raises(ValidationError) as exc:
            services.teacher_profiles_for([t.id, student().id])
        assert exc.value.field == "teacher_ids"

    def test_scope_for_admins_only(self):
        student()
        qs = services.people_queryset("student")
        assert scope_for(admin(), qs).count() == 1
        teacher = User.objects.create_user(email="t@x.test", role="teacher")
        assert scope_for(teacher, qs).count() == 0

    def test_has_people(self):
        admin()
        assert services.has_people() is False
        student()
        assert services.has_people() is True


def test_people_are_per_academy(tenants):
    student(full_name="Main Kid")
    with tenant_context(tenants.other):
        assert not services.people_queryset("student").filter(
            full_name="Main Kid"
        ).exists()
```

- [ ] **Step 2: Run to verify it fails**

Run: `.venv/bin/pytest etqan/identity/tests/test_people_services.py -q`
Expected: FAIL (`ModuleNotFoundError: etqan.identity.scopes` / `AttributeError: create_person`).

- [ ] **Step 3: Implement**

`etqan/identity/scopes.py`:

```python
"""Who may see which people (spec §4.5). Out-of-scope rows simply vanish → 404."""

from etqan.platform.permissions import role_of


def scope_for(user, queryset):
    if role_of(user) == "admin":
        return queryset
    return queryset.none()
```

`etqan/identity/signals.py`:

```python
from allauth.account.signals import email_confirmed
from django.dispatch import receiver

from etqan.identity import services


@receiver(email_confirmed)
def promote_pending_email(sender, request, email_address, **kwargs):
    services.promote_pending_email(email_address)
```

`etqan/identity/apps.py` — add:

```python
    def ready(self):
        from etqan.identity import signals  # noqa: F401, PLC0415
```

`etqan/identity/services.py` — add imports:

```python
from django.contrib.sessions.models import Session
from django.core.exceptions import ValidationError as DjangoValidationError

from etqan.academy import services as academy_services
from etqan.identity.models import Guardianship
from etqan.platform.validators import clean_country
from etqan.platform.validators import clean_currency
from etqan.platform.validators import clean_language
from etqan.platform.validators import clean_phone
from etqan.platform.validators import clean_timezone
from etqan.platform.validators import from_django
```

(`timezone` from `django.utils` is needed again for `Session` expiry: `from django.utils import timezone as dj_timezone` — the `timezone` name is a parameter below.)

Then append:

```python
# ── People (Plan 3) ───────────────────────────────────────────────────────────

USER_FIELDS = frozenset(
    {"full_name", "email", "phone", "preferred_language", "timezone"}
)
PROFILE_FIELDS = {
    "student": frozenset({"date_of_birth", "gender", "country", "status", "notes"}),
    "teacher": frozenset(
        {
            "gender",
            "date_of_birth",
            "bio",
            "default_meeting_url",
            "pay_currency",
            "payout_method",
            "payout_details",
        }
    ),
    "parent": frozenset({"has_whatsapp", "notes"}),
    "admin": frozenset(),
}
_PROFILE_MODELS = {
    "student": StudentProfile,
    "teacher": TeacherProfile,
    "parent": ParentProfile,
}
_PROFILE_RELATION = {
    "student": "student_profile",
    "teacher": "teacher_profile",
    "parent": "parent_profile",
}
BULK_ACTIONS = ("activate", "deactivate", "set_status")


def _normalize_email(email: str | None) -> str | None:
    value = (email or "").strip()
    return User.objects.normalize_email(value) if value else None


def _email_taken(email: str, *, exclude_user_id: int | None = None) -> bool:
    users = User.objects.filter(email__iexact=email)
    addresses = EmailAddress.objects.filter(email__iexact=email)
    if exclude_user_id is not None:
        users = users.exclude(pk=exclude_user_id)
        addresses = addresses.exclude(user_id=exclude_user_id)
    return users.exists() or addresses.exists()


def _clean_name(value: str | None) -> str:
    name = (value or "").strip()
    if not name:
        raise ValidationError("Enter a name.", field="full_name")
    return name


def _apply_profile(role: str, profile_obj, data: dict) -> None:
    unknown = sorted(set(data) - PROFILE_FIELDS[role])
    if unknown:
        raise ValidationError("Unknown field.", field=unknown[0])
    if "country" in data:
        data["country"] = clean_country(data["country"])
    if "pay_currency" in data:
        data["pay_currency"] = clean_currency(data["pay_currency"], "pay_currency")
    for key, value in data.items():
        # A JSON null clears a text field to "" (dates alone are nullable).
        blank = value is None and key != "date_of_birth"
        setattr(profile_obj, key, "" if blank else value)
    if role == "teacher" and not profile_obj.gender:
        raise ValidationError("Choose male or female.", field="gender")
    try:
        profile_obj.full_clean(exclude=["user"])
    except DjangoValidationError as exc:
        raise from_django(exc) from None


@transaction.atomic
def create_person(  # noqa: PLR0913 -- keyword-only; signature fixed by spec §4.1
    role: str,
    *,
    full_name: str,
    email: str | None = None,
    phone: str | None = None,
    preferred_language: str | None = None,
    timezone: str | None = None,
    profile: dict | None = None,
    invite: bool = True,
    created_by: User | None = None,  # spec §4.1 signature; the audit log is B1
) -> User:
    """Create a user and their role profile; invite them when they have an email."""
    if role not in PROFILE_FIELDS:
        raise ValidationError("Unknown role.", field="role")
    academy = academy_services.get_settings()
    name = _clean_name(full_name)
    address = _normalize_email(email)
    if address and _email_taken(address):
        raise ValidationError("This email is already in use.", field="email")
    user = User(
        email=address,
        full_name=name,
        phone=clean_phone(phone),
        preferred_language=clean_language(
            preferred_language or academy.default_language
        ),
        timezone=clean_timezone(timezone or academy.timezone),
        role=role,
    )
    user.set_unusable_password()
    user.save()
    model = _PROFILE_MODELS.get(role)
    if model is not None:
        profile_obj = model(user=user)
        if role == "teacher":
            profile_obj.pay_currency = academy.default_currency
        _apply_profile(role, profile_obj, dict(profile or {}))
        profile_obj.save()
    elif profile:
        raise ValidationError("Admins have no profile.", field=sorted(profile)[0])
    if address:
        EmailAddress.objects.create(
            user=user, email=address, primary=True, verified=False
        )
        if invite:
            _send_invite(user)
    return user


@transaction.atomic
def update_person(
    user: User, *, fields: dict | None = None, profile: dict | None = None
) -> User:
    fields = dict(fields or {})
    if "email" in fields:
        change_person_email(user, fields.pop("email"))
    unknown = sorted(set(fields) - USER_FIELDS)
    if unknown:
        raise ValidationError("Unknown field.", field=unknown[0])
    if "full_name" in fields:
        user.full_name = _clean_name(fields["full_name"])
    if "phone" in fields:
        user.phone = clean_phone(fields["phone"])
    if "preferred_language" in fields:
        user.preferred_language = clean_language(fields["preferred_language"])
    if "timezone" in fields:
        user.timezone = clean_timezone(fields["timezone"])
    user.save()
    if profile:
        model = _PROFILE_MODELS.get(user.role)
        if model is None:
            raise ValidationError("Admins have no profile.", field=sorted(profile)[0])
        profile_obj, _ = model.objects.get_or_create(user=user)
        _apply_profile(user.role, profile_obj, dict(profile))
        profile_obj.save()
    return user


def change_person_email(user: User, email: str | None) -> None:
    """Admin-initiated email change (plan D4)."""
    new = _normalize_email(email)
    if new is None:
        if user.email:
            raise ValidationError(
                "An email cannot be removed once set.", field="email"
            )
        return
    if user.email and new.lower() == user.email.lower():
        return
    if _email_taken(new, exclude_user_id=user.pk):
        raise ValidationError("This email is already in use.", field="email")
    if not user.has_usable_password():
        # Never signed in: nothing to protect yet, so replace and re-invite.
        # The reset token hashes the email, so the old link dies with it.
        EmailAddress.objects.filter(user=user).delete()
        user.email = new
        user.pending_email = ""
        user.save(update_fields=["email", "pending_email"])
        EmailAddress.objects.create(user=user, email=new, primary=True, verified=False)
        _send_invite(user)
        return
    if user.pending_email:
        EmailAddress.objects.filter(
            user=user, email__iexact=user.pending_email, verified=False
        ).delete()
    address = EmailAddress.objects.create(
        user=user, email=new, primary=False, verified=False
    )
    user.pending_email = new
    user.save(update_fields=["pending_email"])
    address.send_confirmation(None)


def promote_pending_email(address: EmailAddress) -> None:
    user = address.user
    if not user.pending_email or user.pending_email.lower() != address.email.lower():
        return
    previous = user.email
    address.set_as_primary()  # also syncs and saves user.email
    User.objects.filter(pk=user.pk).update(pending_email="")
    if previous:
        _send_email_security_alert(
            to_email=previous, action="set_primary", language=user.preferred_language
        )


def account_state(user: User) -> str:
    if not user.email:
        return "no_login"
    if not user.is_active:
        return "inactive"
    if not user.has_usable_password():
        return "invited"
    return "active"


def resend_invite(user: User) -> None:
    if account_state(user) != "invited":
        raise ValidationError(
            "Only someone who has not set a password yet can be re-invited.",
            field="email",
        )
    _send_invite(user)


def send_password_reset(user: User) -> None:
    if not user.email:
        raise ValidationError("Add an email address first.", field="email")
    if not user.is_active:
        raise ValidationError("Activate this account first.")
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = default_token_generator.make_token(user)
    link = app_url(f"/reset-password?uid={uid}&token={token}")
    subject, body = render_email("reset", user.preferred_language, link=link)
    _send(user.email, subject, body, language=user.preferred_language)


def _end_sessions(user: User) -> None:
    for session in Session.objects.filter(expire_date__gt=dj_timezone.now()):
        if session.get_decoded().get("_auth_user_id") == str(user.pk):
            session.delete()


@transaction.atomic
def deactivate(user: User, *, by: User | None) -> None:
    if by is not None and by.pk == user.pk:
        raise ValidationError("You cannot deactivate your own account.")
    if user.role == User.Role.ADMIN and user.is_active:
        active_admins = list(
            User.objects.select_for_update()
            .filter(role=User.Role.ADMIN, is_active=True)
            .values_list("pk", flat=True)
        )
        if active_admins == [user.pk]:
            raise ValidationError("An academy needs at least one active admin.")
    user.is_active = False
    user.save(update_fields=["is_active"])
    _end_sessions(user)


def activate(user: User) -> None:
    user.is_active = True
    user.save(update_fields=["is_active"])


@transaction.atomic
def bulk_update_students(
    user_ids: list[int],
    action: str,
    *,
    status: str | None = None,
    by: User | None = None,
) -> int:
    if action not in BULK_ACTIONS:
        raise ValidationError("Unknown action.", field="action")
    if action == "set_status" and status not in StudentProfile.Status.values:
        raise ValidationError("Choose a status.", field="status")
    students = list(User.objects.filter(pk__in=user_ids, role=User.Role.STUDENT))
    for user in students:
        if action == "activate":
            activate(user)
        elif action == "deactivate":
            deactivate(user, by=by)
    if action == "set_status":
        StudentProfile.objects.filter(user__in=students).update(status=status)
    return len(students)


def _profile_of(user: User, role: str):
    if user.role != role:
        raise ValidationError(f"This person is not a {role}.", field=f"{role}_id")
    model = _PROFILE_MODELS[role]
    profile_obj, _ = model.objects.get_or_create(user=user)
    return profile_obj


def link_guardian(parent: User, student: User) -> None:
    Guardianship.objects.get_or_create(
        parent=_profile_of(parent, "parent"), student=_profile_of(student, "student")
    )


def unlink_guardian(parent: User, student: User) -> None:
    Guardianship.objects.filter(parent__user=parent, student__user=student).delete()


def guardians_of(student: User) -> list[User]:
    return list(
        User.objects.filter(
            parent_profile__child_links__student__user=student
        ).order_by("full_name", "id")
    )


def children_of(parent: User) -> list[User]:
    return list(
        User.objects.filter(
            student_profile__guardian_links__parent__user=parent
        ).order_by("full_name", "id")
    )


def people_queryset(role: str):
    qs = User.objects.filter(role=role)
    relation = _PROFILE_RELATION.get(role)
    if relation:
        qs = qs.select_related(relation)
    if role == "parent":
        qs = qs.prefetch_related("parent_profile__child_links__student__user")
    return qs.order_by("full_name", "id")


def get_person(role: str, user_id: int) -> User:
    try:
        return people_queryset(role).get(pk=user_id)
    except User.DoesNotExist:
        raise NotFoundError(role.title(), user_id) from None


def teacher_profiles_for(user_ids: list[int]) -> list[TeacherProfile]:
    wanted = set(user_ids)
    profiles = list(
        TeacherProfile.objects.filter(user_id__in=wanted, user__role="teacher")
    )
    if len(profiles) != len(wanted):
        raise ValidationError("Choose teachers from the list.", field="teacher_ids")
    return profiles


def has_people() -> bool:
    return User.objects.exclude(role=User.Role.ADMIN).exists()
```

Also update `create_academy_admin` so the first admin gets the academy's language and timezone. Replace its `User.objects.create_user(...)` call with:

```python
    academy = academy_services.get_settings()
    user = User.objects.create_user(
        email=email,
        password=password,
        full_name=full_name,
        role=User.Role.ADMIN,
        preferred_language=academy.default_language,
        timezone=academy.timezone,
    )
```

Its duplicate check becomes `if _email_taken(User.objects.normalize_email(email)):`.

No new import-linter contract here: identity → academy is allowed. Task 6 adds the identity ↔ catalogue contracts.

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest -q etqan/identity etqan/tenants`
Expected: PASS.

- [ ] **Step 5: Linters, commit**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports
git -C backend add -A
git -C backend commit -m "feat(identity): create_person, invites, account actions and guardianship services

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: `etqan.catalogue` — courses, packages and the one `sessions_total` rule

**Files:**
- Create: `backend/etqan/catalogue/{__init__,apps,models,services,scopes}.py`, `backend/etqan/catalogue/migrations/{__init__,0001_initial}.py` (generated), `backend/etqan/catalogue/tests/{__init__,test_sessions_total,test_services}.py`
- Modify: `backend/config/settings/base.py` (`TENANT_APPS`), `backend/pyproject.toml`

**Interfaces:**
- Consumes: `identity_services.teacher_profiles_for(user_ids)`, `identity_services.get_teacher_profile(user_id)` (Task 5); `from_django` (Task 2).
- Produces:
  - `Course(name_ar, name_en, description_ar, description_en, language ∈ Course.Language{AR,EN,BOTH}, teachers M2M "identity.TeacherProfile" related_name="courses", is_active=True, created_at, updated_at)`
  - `Package(name_ar, name_en, description_ar, description_en, sessions_per_week, session_minutes, duration_value, duration_unit ∈ Package.DurationUnit{DAY,MONTH}, freeze_days_allowed=0, price_minor, currency, is_active=True, created_at, updated_at)` with the spec bounds as model validators.
  - `etqan.catalogue.services`:
    - `weeks(duration_value: int, duration_unit: str) -> int`
    - `compute_sessions_total(sessions_per_week: int, duration_value: int, duration_unit: str) -> int`
    - `sessions_total(package: Package) -> int` (**the** rule Plan 4 must call)
    - `create_course(*, teacher_ids: list[int] | None = None, **fields) -> Course`, `update_course(course, *, teacher_ids=None, **fields) -> Course`, `delete_course(course) -> None`, `duplicate_course(course) -> Course`, `course_teacher_ids(course) -> list[int]` (User ids)
    - `create_package(**fields) -> Package`, `update_package(package, **fields) -> Package`, `delete_package(package) -> None`, `duplicate_package(package) -> Package`
    - `set_teacher_courses(teacher_user_id: int, course_ids: list[int]) -> None`, `course_ids_for_teachers(user_ids: list[int]) -> dict[int, list[int]]`, `teacher_user_ids_for_course(course_id: int) -> list[int]`
    - `has_catalogue() -> bool`
  - `etqan.catalogue.scopes.scope_for(user, queryset)`: admin → all; teacher → `is_active=True`; others → none.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/catalogue/tests/__init__.py` — empty.

`backend/etqan/catalogue/tests/test_sessions_total.py`:

```python
import pytest

from etqan.catalogue.services import compute_sessions_total
from etqan.catalogue.services import weeks

pytestmark = pytest.mark.django_db


@pytest.mark.parametrize(
    ("value", "unit", "expected"),
    [
        (1, "day", 1),
        (6, "day", 1),
        (7, "day", 1),
        (8, "day", 2),
        (14, "day", 2),
        (15, "day", 3),
        (30, "day", 5),
        (365, "day", 53),
        (1, "month", 4),
        (3, "month", 12),
        (365, "month", 1460),
    ],
)
def test_weeks(value, unit, expected):
    assert weeks(value, unit) == expected


@pytest.mark.parametrize(
    ("per_week", "value", "unit", "expected"),
    [
        (1, 1, "day", 1),
        (2, 1, "month", 8),
        (3, 30, "day", 15),
        (14, 365, "month", 20440),
        (14, 365, "day", 742),
    ],
)
def test_sessions_total(per_week, value, unit, expected):
    assert compute_sessions_total(per_week, value, unit) == expected


def test_unknown_unit_raises():
    with pytest.raises(ValueError, match="week"):
        weeks(1, "week")
```

`backend/etqan/catalogue/tests/test_services.py`:

```python
import pytest

from etqan.catalogue import services
from etqan.catalogue.models import Course
from etqan.catalogue.scopes import scope_for
from etqan.identity import services as identity_services
from etqan.identity.models import User
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db

PACKAGE = {
    "name_ar": "باقة شهرية",
    "name_en": "Monthly",
    "sessions_per_week": 2,
    "session_minutes": 45,
    "duration_value": 1,
    "duration_unit": "month",
    "price_minor": 150000,
    "currency": "EGP",
}


def teacher(name="Bilal"):
    return identity_services.create_person(
        "teacher", full_name=name, profile={"gender": "male"}
    )


def course(**kw):
    return services.create_course(
        name_ar=kw.pop("name_ar", "تجويد"), name_en=kw.pop("name_en", "Tajweed"), **kw
    )


def test_course_with_teachers_round_trips_user_ids():
    t1, t2 = teacher(), teacher("Maryam")
    c = course(teacher_ids=[t1.id, t2.id])
    assert services.course_teacher_ids(c) == sorted([t1.id, t2.id])
    services.update_course(c, teacher_ids=[t2.id], name_en="Tajweed 2")
    c.refresh_from_db()
    assert (c.name_en, services.course_teacher_ids(c)) == ("Tajweed 2", [t2.id])


def test_course_teachers_must_be_teachers():
    kid = identity_services.create_person("student", full_name="K", profile={})
    with pytest.raises(ValidationError) as exc:
        course(teacher_ids=[kid.id])
    assert exc.value.field == "teacher_ids"


def test_names_required_in_both_languages():
    with pytest.raises(ValidationError) as exc:
        course(name_ar="")
    assert exc.value.field == "name_ar"


def test_duplicate_course_is_inactive_copy_with_teachers():
    t = teacher()
    c = course(teacher_ids=[t.id])
    copy = services.duplicate_course(c)
    assert (copy.name_en, copy.name_ar, copy.is_active) == (
        "Tajweed (copy)",
        "تجويد (نسخة)",
        False,
    )
    assert services.course_teacher_ids(copy) == [t.id]


def test_course_with_teachers_can_be_deleted_in_plan_3():
    c = course(teacher_ids=[teacher().id])
    services.delete_course(c)
    assert not Course.objects.exists()


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("sessions_per_week", 0),
        ("sessions_per_week", 15),
        ("session_minutes", 14),
        ("session_minutes", 241),
        ("duration_value", 0),
        ("duration_value", 366),
        ("freeze_days_allowed", 366),
        ("duration_unit", "week"),
        ("currency", "EURO"),
    ],
)
def test_package_bounds_are_rejected_not_clamped(field, value):
    with pytest.raises(ValidationError) as exc:
        services.create_package(**{**PACKAGE, field: value})
    assert exc.value.field == field


def test_package_negative_price_rejected():
    with pytest.raises(ValidationError):
        services.create_package(**{**PACKAGE, "price_minor": -1})


def test_package_total_and_duplicate():
    p = services.create_package(**PACKAGE)
    assert services.sessions_total(p) == 8
    copy = services.duplicate_package(p)
    assert (copy.name_en, copy.is_active, copy.price_minor) == (
        "Monthly (copy)",
        False,
        150000,
    )


def test_teacher_side_course_links():
    t = teacher()
    a, b = course(), course(name_en="Quran", name_ar="قرآن")
    services.set_teacher_courses(t.id, [a.id, b.id])
    assert services.course_ids_for_teachers([t.id]) == {t.id: sorted([a.id, b.id])}
    assert services.teacher_user_ids_for_course(a.id) == [t.id]
    with pytest.raises(ValidationError) as exc:
        services.set_teacher_courses(t.id, [a.id, 999999])
    assert exc.value.field == "course_ids"


def test_scope_for_roles():
    course()
    course(name_en="Old", name_ar="قديم", is_active=False)
    qs = Course.objects.all()
    admin = User.objects.create_user(email="a@x.test", role="admin")
    t = User.objects.create_user(email="t@x.test", role="teacher")
    parent = User.objects.create_user(email="p@x.test", role="parent")
    assert scope_for(admin, qs).count() == 2
    assert scope_for(t, qs).count() == 1
    assert scope_for(parent, qs).count() == 0


def test_has_catalogue():
    assert services.has_catalogue() is False
    course()
    assert services.has_catalogue() is True
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest etqan/catalogue -q`
Expected: FAIL (`ModuleNotFoundError: No module named 'etqan.catalogue'`).

- [ ] **Step 3: Implement**

`backend/etqan/catalogue/__init__.py`, `migrations/__init__.py` — empty.

`backend/etqan/catalogue/apps.py`:

```python
from django.apps import AppConfig


class CatalogueConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.catalogue"
    label = "catalogue"
```

`backend/etqan/catalogue/models.py`:

```python
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models


def _between(low, high):
    return [MinValueValidator(low), MaxValueValidator(high)]


class Course(models.Model):
    class Language(models.TextChoices):
        AR = "ar", "Arabic"
        EN = "en", "English"
        BOTH = "both", "Arabic and English"

    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    description_ar = models.TextField(blank=True, default="")
    description_en = models.TextField(blank=True, default="")
    language = models.CharField(
        max_length=4, choices=Language.choices, default=Language.AR
    )
    # String reference: catalogue never imports identity's models (plan D15).
    teachers = models.ManyToManyField(
        "identity.TeacherProfile", related_name="courses", blank=True
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name_en", "id"]

    def __str__(self):
        return self.name_en


class Package(models.Model):
    class DurationUnit(models.TextChoices):
        DAY = "day", "Day"
        MONTH = "month", "Month"

    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    description_ar = models.TextField(blank=True, default="")
    description_en = models.TextField(blank=True, default="")
    sessions_per_week = models.PositiveSmallIntegerField(validators=_between(1, 14))
    session_minutes = models.PositiveSmallIntegerField(validators=_between(15, 240))
    duration_value = models.PositiveSmallIntegerField(validators=_between(1, 365))
    duration_unit = models.CharField(max_length=5, choices=DurationUnit.choices)
    freeze_days_allowed = models.PositiveSmallIntegerField(
        default=0, validators=_between(0, 365)
    )
    price_minor = models.BigIntegerField(validators=[MinValueValidator(0)])
    currency = models.CharField(
        max_length=3, validators=[RegexValidator(r"^[A-Z]{3}$")]
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name_en", "id"]

    def __str__(self):
        return self.name_en
```

`backend/etqan/catalogue/services.py`:

```python
"""Public API for the catalogue module (spec §3.3, §4.3)."""

from collections import defaultdict

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction

from etqan.catalogue.models import Course
from etqan.catalogue.models import Package
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.platform.validators import from_django

COPY_SUFFIX = {"en": " (copy)", "ar": " (نسخة)"}
DAYS_PER_WEEK = 7
WEEKS_PER_MONTH = 4


def weeks(duration_value: int, duration_unit: str) -> int:
    """P3-7: a month counts as 4 weeks; days round UP to whole weeks."""
    if duration_unit == Package.DurationUnit.MONTH:
        return WEEKS_PER_MONTH * duration_value
    if duration_unit == Package.DurationUnit.DAY:
        return -(-duration_value // DAYS_PER_WEEK)
    raise ValueError(f"Unknown duration unit: {duration_unit!r}")


def compute_sessions_total(
    sessions_per_week: int, duration_value: int, duration_unit: str
) -> int:
    return sessions_per_week * weeks(duration_value, duration_unit)


def sessions_total(package: Package) -> int:
    """The only implementation of the package total. Plan 4 must call this."""
    return compute_sessions_total(
        package.sessions_per_week, package.duration_value, package.duration_unit
    )


def _save(obj) -> None:
    try:
        obj.full_clean()
    except DjangoValidationError as exc:
        raise from_django(exc) from None
    obj.save()


def _set_fields(obj, fields: dict) -> None:
    for key, value in fields.items():
        setattr(obj, key, value)


# ── Courses ───────────────────────────────────────────────────────────────────


def course_teacher_ids(course: Course) -> list[int]:
    return sorted(course.teachers.values_list("user_id", flat=True))


def _set_course_teachers(course: Course, teacher_ids: list[int]) -> None:
    course.teachers.set(identity_services.teacher_profiles_for(teacher_ids))


@transaction.atomic
def create_course(*, teacher_ids: list[int] | None = None, **fields) -> Course:
    course = Course(**fields)
    _save(course)
    if teacher_ids:
        _set_course_teachers(course, teacher_ids)
    return course


@transaction.atomic
def update_course(
    course: Course, *, teacher_ids: list[int] | None = None, **fields
) -> Course:
    _set_fields(course, fields)
    _save(course)
    if teacher_ids is not None:
        _set_course_teachers(course, teacher_ids)
    return course


def delete_course(course: Course) -> None:
    # P3-5: in Plan 3 nothing references a course yet; Plan 4 refuses deleting
    # a course that has subscriptions and asks the admin to deactivate it.
    course.delete()


@transaction.atomic
def duplicate_course(course: Course) -> Course:
    copy = Course.objects.create(
        name_ar=course.name_ar + COPY_SUFFIX["ar"],
        name_en=course.name_en + COPY_SUFFIX["en"],
        description_ar=course.description_ar,
        description_en=course.description_en,
        language=course.language,
        is_active=False,
    )
    copy.teachers.set(course.teachers.all())
    return copy


@transaction.atomic
def set_teacher_courses(teacher_user_id: int, course_ids: list[int]) -> None:
    [profile] = identity_services.teacher_profiles_for([teacher_user_id])
    wanted = set(course_ids)
    courses = list(Course.objects.filter(pk__in=wanted))
    if len(courses) != len(wanted):
        raise ValidationError("Choose courses from the list.", field="course_ids")
    profile.courses.set(courses)


def course_ids_for_teachers(user_ids: list[int]) -> dict[int, list[int]]:
    rows = Course.teachers.through.objects.filter(
        teacherprofile__user_id__in=list(user_ids)
    ).values_list("teacherprofile__user_id", "course_id")
    found: dict[int, list[int]] = defaultdict(list)
    for user_id, course_id in rows:
        found[user_id].append(course_id)
    return {user_id: sorted(ids) for user_id, ids in found.items()}


def teacher_user_ids_for_course(course_id: int) -> list[int]:
    return list(
        Course.teachers.through.objects.filter(course_id=course_id).values_list(
            "teacherprofile__user_id", flat=True
        )
    )


# ── Packages ──────────────────────────────────────────────────────────────────


def _clean_package_fields(fields: dict) -> dict:
    if "currency" in fields:
        fields["currency"] = clean_currency(fields["currency"], "currency")
    return fields


def create_package(**fields) -> Package:
    package = Package(**_clean_package_fields(fields))
    _save(package)
    return package


def update_package(package: Package, **fields) -> Package:
    _set_fields(package, _clean_package_fields(fields))
    _save(package)
    return package


def delete_package(package: Package) -> None:
    package.delete()


def duplicate_package(package: Package) -> Package:
    copy = Package.objects.get(pk=package.pk)
    copy.pk = None
    copy.name_ar = package.name_ar + COPY_SUFFIX["ar"]
    copy.name_en = package.name_en + COPY_SUFFIX["en"]
    copy.is_active = False
    copy.save()
    return copy


def has_catalogue() -> bool:
    return Course.objects.exists() or Package.objects.exists()
```

`backend/etqan/catalogue/scopes.py`:

```python
"""Catalogue visibility (spec §4.5): admin all, teacher active only, others none."""

from etqan.platform.permissions import role_of


def scope_for(user, queryset):
    role = role_of(user)
    if role == "admin":
        return queryset
    if role == "teacher":
        return queryset.filter(is_active=True)
    return queryset.none()
```

`config/settings/base.py`: append `"etqan.catalogue",` to `TENANT_APPS`. Generate the migration: `.venv/bin/python manage.py makemigrations catalogue` (depends on `identity.0012_people_cleanup`).

`pyproject.toml`: add `"etqan.catalogue"` to the platform contract's `forbidden_modules` and to the academy contract's `forbidden_modules`, then append:

```toml
[[tool.importlinter.contracts]]
name = "catalogue reaches identity only through its services"
type = "forbidden"
source_modules = ["etqan.catalogue"]
forbidden_modules = ["etqan.identity.models", "etqan.identity.api", "etqan.tenants", "etqan.site"]
# catalogue.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true
ignore_imports = [
    "etqan.catalogue.tests.* -> etqan.identity.models",
]

[[tool.importlinter.contracts]]
name = "identity core does not import the catalogue"
type = "forbidden"
source_modules = ["etqan.identity.models", "etqan.identity.services", "etqan.identity.emails", "etqan.identity.scopes"]
forbidden_modules = ["etqan.catalogue"]
```

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest --create-db -q etqan/catalogue`
Expected: PASS.

- [ ] **Step 5: Full suite, linters, commit**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`

```bash
git -C backend add -A
git -C backend commit -m "feat(catalogue): courses with teachers, packages and the sessions_total rule

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: People API — list, search, filters, CSV, create, detail, edit

**Files:**
- Create: `backend/etqan/platform/csv.py`, `backend/etqan/platform/tests/test_csv.py`, `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_serializers.py`, `backend/etqan/identity/api/people_filters.py`, `backend/etqan/identity/api/people_views.py`, `backend/etqan/identity/api/people_urls.py`, `backend/etqan/identity/tests/test_people_api.py`
- Modify: `backend/config/api_router.py`

**Interfaces:**
- Consumes: Task 5 services and `scope_for`; `catalogue_services.course_ids_for_teachers`, `set_teacher_courses`, `teacher_user_ids_for_course` (Task 6); `IsAdmin` (Task 2).
- Produces:
  - `etqan.platform.csv`: `CSVRenderer` (`format="csv"`, UTF-8 BOM, columns from `view.csv_columns: tuple[tuple[path, label], ...]` with dotted paths into each row dict), `CSVExportMixin` (`csv_columns`, `csv_filename`, `wants_csv() -> bool`, `csv_response(rows: list[dict]) -> Response` with `Content-Disposition: attachment; filename="<csv_filename>.csv"`), `safe_cell(value) -> str`.
  - `etqan.identity.api.payloads`: `user_payload(user) -> dict`, `profile_payload(user, *, course_ids: list[int] | None = None) -> dict`, `person_summary(user) -> {"id","full_name","email","phone"}`, `person_rows(users: list[User], *, viewer: User) -> list[dict]`.
  - Row shape: `{"id", "role", "user": {"full_name","email","phone","preferred_language","timezone","is_active","account_state","pending_email"}, "profile": {...}}`. The profile per role is: student `{date_of_birth, gender, country, status, notes}`; teacher `{gender, date_of_birth, bio, default_meeting_url, pay_currency, payout_method, payout_details, course_ids}`; parent `{has_whatsapp, notes, children: [summary]}`; admin `{}`. Admin rows add `"deactivation_blocked": "self" | "last_admin" | null`.
  - `etqan.identity.api.people_serializers`: `PersonWriteSerializer` (context `role`, nested `user` + `profile`; teacher profile accepts `course_ids`), `as_drf(exc) -> serializers.ValidationError` (nests a service error under `user` or `profile`).
  - Endpoints (all `IsAdmin`, 404 outside scope): `GET/POST /api/v1/people/<kind>/` (`kind ∈ students|parents|teachers|admins`; `q`, `is_active`; students `status, country, gender`; teachers `course, gender`; parents `has_whatsapp`; `page`, `page_size`; `format=csv`), `GET/PATCH /api/v1/people/<kind>/<id>/` (no DELETE → 405).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/platform/tests/test_csv.py`:

```python
from etqan.platform.csv import safe_cell


def test_safe_cell():
    assert safe_cell(None) == ""
    assert safe_cell(True) == "yes"
    assert safe_cell("+201001234567") == "+201001234567"
    assert safe_cell("-5") == "-5"
    assert safe_cell("=1+1") == "'=1+1"
    assert safe_cell("@SUM(A1)") == "'@SUM(A1)"
    assert safe_cell("+cmd|' /C calc'!A0") == "'+cmd|' /C calc'!A0"
    assert safe_cell([{"full_name": "Yusuf"}, {"full_name": "Aisha"}]) == (
        "Yusuf; Aisha"
    )
    assert safe_cell([3, 4]) == "3; 4"
```

`backend/etqan/identity/tests/test_people_api.py`:

```python
import csv
import io

import pytest
from django.core import mail
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.catalogue import services as catalogue_services
from etqan.identity import services

pytestmark = pytest.mark.django_db
B = "/api/v1/people/"
KINDS = ["students", "parents", "teachers", "admins"]


@pytest.fixture
def admin(api_for):
    return api_for("admin")


def names(client, url):
    return [row["user"]["full_name"] for row in client.get(url).json()["results"]]


@pytest.mark.parametrize("role", ["teacher", "parent", "student"])
@pytest.mark.parametrize("kind", KINDS)
def test_non_admins_are_refused(api_for, role, kind):
    client = api_for(role)
    assert client.get(f"{B}{kind}/").status_code == 403
    body = {"user": {"full_name": "X"}}
    assert client.post(f"{B}{kind}/", body, format="json").status_code == 403


def test_anonymous_is_refused():
    assert APIClient().get(f"{B}students/").status_code == 403


def test_create_student_without_email(admin):
    resp = admin.post(
        f"{B}students/",
        {"user": {"full_name": "Aisha"}, "profile": {"status": "trial", "country": "eg"}},
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    body = resp.json()
    assert body["user"]["email"] is None
    assert body["user"]["account_state"] == "no_login"
    assert (body["profile"]["status"], body["profile"]["country"]) == ("trial", "EG")
    assert mail.outbox == []


def test_create_student_with_email_sends_invite(admin):
    resp = admin.post(
        f"{B}students/",
        {"user": {"full_name": "Yusuf", "email": "yusuf@x.test"}},
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    assert resp.json()["user"]["account_state"] == "invited"
    assert mail.outbox[-1].to == ["yusuf@x.test"]


def test_duplicate_email_error_is_nested_under_user(admin):
    services.create_person("student", full_name="A", email="dup@x.test", profile={})
    resp = admin.post(
        f"{B}students/",
        {"user": {"full_name": "B", "email": "DUP@x.test"}},
        format="json",
    )
    assert resp.status_code == 400
    assert "email" in resp.json()["user"]


def test_bad_phone_is_nested_under_user(admin):
    resp = admin.post(
        f"{B}parents/", {"user": {"full_name": "P", "phone": "0100"}}, format="json"
    )
    assert resp.status_code == 400
    assert "phone" in resp.json()["user"]


def test_teacher_needs_gender_and_links_courses(admin):
    resp = admin.post(f"{B}teachers/", {"user": {"full_name": "T"}}, format="json")
    assert resp.status_code == 400
    assert "gender" in resp.json()["profile"]
    course = catalogue_services.create_course(name_ar="تجويد", name_en="Tajweed")
    resp = admin.post(
        f"{B}teachers/",
        {
            "user": {"full_name": "T"},
            "profile": {
                "gender": "female",
                "course_ids": [course.id],
                "payout_method": "wise",
                "payout_details": "IBAN EG00",
            },
        },
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    assert resp.json()["profile"]["course_ids"] == [course.id]


def test_unknown_course_rolls_the_teacher_back(admin):
    resp = admin.post(
        f"{B}teachers/",
        {"user": {"full_name": "Ghost"}, "profile": {"gender": "male", "course_ids": [999999]}},
        format="json",
    )
    assert resp.status_code == 400
    assert "course_ids" in resp.json()["profile"]
    assert not services.people_queryset("teacher").filter(full_name="Ghost").exists()


def test_search_filters_and_pagination(admin):
    services.create_person(
        "student",
        full_name="Yusuf Omar",
        email="yo@x.test",
        phone="+201001234567",
        profile={"status": "trial"},
        invite=False,
    )
    services.create_person(
        "student", full_name="Aisha", profile={"status": "paused", "gender": "female"}
    )
    url = f"{B}students/"
    assert names(admin, url) == ["Aisha", "Yusuf Omar"]
    assert names(admin, url + "?q=100123") == ["Yusuf Omar"]
    assert names(admin, url + "?q=yo@x") == ["Yusuf Omar"]
    assert names(admin, url + "?status=paused") == ["Aisha"]
    assert names(admin, url + "?gender=female") == ["Aisha"]
    assert names(admin, url + "?is_active=false") == []
    page = admin.get(url + "?page_size=1").json()
    assert (page["count"], len(page["results"])) == (2, 1)


def test_teacher_course_filter(admin):
    a = services.create_person("teacher", full_name="A", profile={"gender": "male"})
    services.create_person("teacher", full_name="B", profile={"gender": "female"})
    course = catalogue_services.create_course(
        name_ar="تجويد", name_en="Tajweed", teacher_ids=[a.id]
    )
    assert names(admin, f"{B}teachers/?course={course.id}") == ["A"]
    assert names(admin, f"{B}teachers/?gender=female") == ["B"]


def test_parents_list_children_and_whatsapp(admin):
    parent = services.create_person(
        "parent", full_name="Omar", profile={"has_whatsapp": True}
    )
    kid = services.create_person("student", full_name="Yusuf", profile={})
    services.link_guardian(parent, kid)
    rows = admin.get(f"{B}parents/?has_whatsapp=true").json()["results"]
    assert [c["full_name"] for c in rows[0]["profile"]["children"]] == ["Yusuf"]
    assert admin.get(f"{B}parents/?has_whatsapp=false").json()["count"] == 0


def test_csv_respects_filters_and_opens_in_excel(admin):
    services.create_person("student", full_name="يوسف", profile={"status": "trial"})
    services.create_person(
        "student",
        full_name='=HYPERLINK("x")',
        phone="+201001234567",
        profile={"status": "trial"},
    )
    services.create_person("student", full_name="Paused", profile={"status": "paused"})
    resp = admin.get(f"{B}students/?status=trial&format=csv")
    assert resp.status_code == 200
    assert resp["Content-Type"].startswith("text/csv")
    assert 'filename="students.csv"' in resp["Content-Disposition"]
    assert resp.content.startswith("﻿".encode())
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0][:4] == ["ID", "Name", "Email", "Phone"]
    by_name = {row[1]: row for row in rows[1:]}
    assert sorted(by_name) == ["'=HYPERLINK(\"x\")", "يوسف"]
    assert by_name["'=HYPERLINK(\"x\")"][3] == "+201001234567"
    assert by_name["يوسف"][2] == ""  # no email → empty cell, not "None"


def test_other_academy_people_never_leak(admin, tenants):
    with tenant_context(tenants.other):
        other = services.create_person(
            "student", full_name="Other Academy Kid", profile={}
        )
    assert "Other Academy Kid" not in str(admin.get(f"{B}students/").json())
    csv_body = admin.get(f"{B}students/?format=csv").content.decode("utf-8-sig")
    assert "Other Academy Kid" not in csv_body
    assert admin.get(f"{B}students/{other.id}/").status_code == 404


def test_detail_patch_and_no_delete(admin):
    user = services.create_person("student", full_name="Kid", profile={})
    url = f"{B}students/{user.id}/"
    assert admin.get(url).json()["user"]["full_name"] == "Kid"
    resp = admin.patch(
        url,
        {"user": {"email": "kid@x.test"}, "profile": {"status": "paused"}},
        format="json",
    )
    assert resp.status_code == 200, resp.json()
    assert resp.json()["user"]["account_state"] == "invited"
    assert resp.json()["profile"]["status"] == "paused"
    assert mail.outbox[-1].to == ["kid@x.test"]
    assert admin.delete(url).status_code == 405
    assert admin.get(f"{B}teachers/{user.id}/").status_code == 404
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest etqan/platform/tests/test_csv.py etqan/identity/tests/test_people_api.py -q`
Expected: FAIL (`ModuleNotFoundError: etqan.platform.csv`; the people URLs 404).

- [ ] **Step 3: Implement**

`backend/etqan/platform/csv.py`:

```python
"""`?format=csv` for admin lists (spec §5, plan D9)."""

import csv
import io
import json
import re

from rest_framework.renderers import BaseRenderer
from rest_framework.response import Response

_INTEGER = re.compile(r"^[+-]?\d+$")
_FORMULA_START = ("=", "@", "\t", "\r", "+", "-")


def _text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, dict):
        return str(value.get("full_name") or value.get("name_en") or "")
    if isinstance(value, list | tuple):
        return "; ".join(_text(item) for item in value)
    return str(value)


def safe_cell(value) -> str:
    """Text for one CSV cell, defused against spreadsheet formula injection."""
    text = _text(value)
    if text.startswith(_FORMULA_START) and not _INTEGER.fullmatch(text):
        return "'" + text
    return text


def _lookup(row: dict, path: str):
    value = row
    for part in path.split("."):
        value = value.get(part) if isinstance(value, dict) else None
    return value


class CSVRenderer(BaseRenderer):
    media_type = "text/csv"
    format = "csv"
    charset = "utf-8"

    def render(self, data, accepted_media_type=None, renderer_context=None):
        if not isinstance(data, list):  # an error body, e.g. a 403
            return json.dumps(data, default=str).encode()
        view = (renderer_context or {}).get("view")
        columns = getattr(view, "csv_columns", ())
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow([label for _, label in columns])
        for row in data:
            writer.writerow([safe_cell(_lookup(row, path)) for path, _ in columns])
        # The BOM makes Excel open the file as UTF-8 (Arabic names intact).
        return ("﻿" + buffer.getvalue()).encode("utf-8")


class CSVExportMixin:
    csv_columns: tuple[tuple[str, str], ...] = ()
    csv_filename = "export"

    def get_renderers(self):
        return [*super().get_renderers(), CSVRenderer()]

    def wants_csv(self) -> bool:
        renderer = getattr(self.request, "accepted_renderer", None)
        return getattr(renderer, "format", None) == "csv"

    def csv_response(self, rows: list[dict]) -> Response:
        response = Response(rows)
        response["Content-Disposition"] = (
            f'attachment; filename="{self.csv_filename}.csv"'
        )
        return response
```

`backend/etqan/identity/api/payloads.py`:

```python
"""JSON shapes for people (plan D7): one place, so me/, lists and CSV agree."""

from etqan.catalogue import services as catalogue_services
from etqan.identity import services
from etqan.identity.models import User


def _iso(value):
    return value.isoformat() if value else None


def person_summary(user: User) -> dict:
    return {
        "id": user.id,
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
    }


def user_payload(user: User) -> dict:
    return {
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
        "preferred_language": user.preferred_language,
        "timezone": user.timezone,
        "is_active": user.is_active,
        "account_state": services.account_state(user),
        "pending_email": user.pending_email,
    }


def profile_payload(user: User, *, course_ids: list[int] | None = None) -> dict:
    if user.role == "student":
        p = getattr(user, "student_profile", None)
        if p is None:
            return {}
        return {
            "date_of_birth": _iso(p.date_of_birth),
            "gender": p.gender,
            "country": p.country,
            "status": p.status,
            "notes": p.notes,
        }
    if user.role == "teacher":
        p = getattr(user, "teacher_profile", None)
        if p is None:
            return {}
        return {
            "gender": p.gender,
            "date_of_birth": _iso(p.date_of_birth),
            "bio": p.bio,
            "default_meeting_url": p.default_meeting_url,
            "pay_currency": p.pay_currency,
            "payout_method": p.payout_method,
            "payout_details": p.payout_details,
            "course_ids": course_ids or [],
        }
    if user.role == "parent":
        p = getattr(user, "parent_profile", None)
        if p is None:
            return {}
        return {
            "has_whatsapp": p.has_whatsapp,
            "notes": p.notes,
            "children": [
                person_summary(link.student.user) for link in p.child_links.all()
            ],
        }
    return {}


def _deactivation_blocked(user: User, viewer: User, active_admins: int) -> str | None:
    if user.pk == viewer.pk:
        return "self"
    if user.is_active and active_admins <= 1:
        return "last_admin"
    return None


def person_rows(users: list[User], *, viewer: User) -> list[dict]:
    teacher_ids = [u.id for u in users if u.role == "teacher"]
    courses = (
        catalogue_services.course_ids_for_teachers(teacher_ids) if teacher_ids else {}
    )
    active_admins = None
    rows = []
    for user in users:
        row = {
            "id": user.id,
            "role": user.role,
            "user": user_payload(user),
            "profile": profile_payload(user, course_ids=courses.get(user.id)),
        }
        if user.role == "admin":
            if active_admins is None:
                active_admins = User.objects.filter(
                    role="admin", is_active=True
                ).count()
            row["deactivation_blocked"] = _deactivation_blocked(
                user, viewer, active_admins
            )
        rows.append(row)
    return rows
```

`backend/etqan/identity/api/people_serializers.py`:

```python
from rest_framework import serializers

from etqan.identity.models import ParentProfile
from etqan.identity.models import StudentProfile
from etqan.identity.models import TeacherProfile
from etqan.identity.services import USER_FIELDS
from etqan.platform.exceptions import ValidationError as EtqanValidationError

LANGUAGES = [("ar", "Arabic"), ("en", "English")]


class UserInputSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=255)
    email = serializers.EmailField(required=False, allow_null=True, allow_blank=True)
    phone = serializers.CharField(required=False, allow_blank=True, max_length=32)
    preferred_language = serializers.ChoiceField(choices=LANGUAGES, required=False)
    timezone = serializers.CharField(required=False, max_length=64)


class StudentProfileInput(serializers.ModelSerializer):
    class Meta:
        model = StudentProfile
        fields = ["date_of_birth", "gender", "country", "status", "notes"]
        # Upper-cased by the service before the model validator runs.
        extra_kwargs = {"country": {"validators": []}}


class TeacherProfileInput(serializers.ModelSerializer):
    course_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False
    )

    class Meta:
        model = TeacherProfile
        fields = [
            "gender",
            "date_of_birth",
            "bio",
            "default_meeting_url",
            "pay_currency",
            "payout_method",
            "payout_details",
            "course_ids",
        ]
        extra_kwargs = {
            "gender": {"required": True, "allow_blank": False},
            "pay_currency": {"required": False, "validators": []},
        }


class ParentProfileInput(serializers.ModelSerializer):
    class Meta:
        model = ParentProfile
        fields = ["has_whatsapp", "notes"]


PROFILE_INPUT = {
    "student": StudentProfileInput,
    "teacher": TeacherProfileInput,
    "parent": ParentProfileInput,
}


class PersonWriteSerializer(serializers.Serializer):
    """`{"user": {...}, "profile": {...}}` — `context["role"]` picks the profile."""

    user = UserInputSerializer()
    profile = serializers.DictField(required=False)

    def validate_profile(self, value):
        input_class = PROFILE_INPUT.get(self.context["role"])
        if input_class is None:
            if value:
                raise serializers.ValidationError("Admins have no profile.")
            return {}
        nested = input_class(data=value, partial=self.partial)
        nested.is_valid(raise_exception=True)
        return dict(nested.validated_data)


class GuardianLinkSerializer(serializers.Serializer):
    parent_id = serializers.IntegerField(min_value=1)


class StudentBulkSerializer(serializers.Serializer):
    ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), allow_empty=False, max_length=500
    )
    action = serializers.ChoiceField(choices=["activate", "deactivate", "set_status"])
    status = serializers.ChoiceField(
        choices=StudentProfile.Status.choices, required=False
    )

    def validate(self, attrs):
        if attrs["action"] == "set_status" and not attrs.get("status"):
            raise serializers.ValidationError({"status": ["Choose a status."]})
        return attrs


def as_drf(exc: EtqanValidationError) -> serializers.ValidationError:
    """Nest a service error the way the payload is nested (plan D7)."""
    if exc.field is None:
        return serializers.ValidationError({"non_field_errors": [exc.message]})
    section = "user" if exc.field in USER_FIELDS else "profile"
    return serializers.ValidationError({section: {exc.field: [exc.message]}})
```

`backend/etqan/identity/api/people_filters.py`:

```python
from django.db.models import Q

from etqan.catalogue import services as catalogue_services

_BOOL = {"true": True, "false": False}


def filter_people(queryset, role: str, params):
    if q := params.get("q", "").strip():
        queryset = queryset.filter(
            Q(full_name__icontains=q) | Q(email__icontains=q) | Q(phone__icontains=q)
        )
    if (active := params.get("is_active")) in _BOOL:
        queryset = queryset.filter(is_active=_BOOL[active])
    if role == "student":
        for key in ("status", "country", "gender"):
            if value := params.get(key):
                queryset = queryset.filter(**{f"student_profile__{key}": value.strip()})
    elif role == "teacher":
        if gender := params.get("gender"):
            queryset = queryset.filter(teacher_profile__gender=gender)
        if (course := params.get("course", "")).isdigit():
            ids = catalogue_services.teacher_user_ids_for_course(int(course))
            queryset = queryset.filter(pk__in=ids)
    elif role == "parent" and (whatsapp := params.get("has_whatsapp")) in _BOOL:
        queryset = queryset.filter(parent_profile__has_whatsapp=_BOOL[whatsapp])
    return queryset
```

`backend/etqan/identity/api/people_views.py`:

```python
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.catalogue import services as catalogue_services
from etqan.identity import services
from etqan.identity.api.payloads import person_rows
from etqan.identity.api.people_filters import filter_people
from etqan.identity.api.people_serializers import PersonWriteSerializer
from etqan.identity.api.people_serializers import as_drf
from etqan.identity.scopes import scope_for
from etqan.platform.csv import CSVExportMixin
from etqan.platform.exceptions import ValidationError as EtqanValidationError
from etqan.platform.permissions import IsAdmin

KINDS = {
    "students": "student",
    "parents": "parent",
    "teachers": "teacher",
    "admins": "admin",
}
_COMMON = (
    ("id", "ID"),
    ("user.full_name", "Name"),
    ("user.email", "Email"),
    ("user.phone", "Phone"),
    ("user.preferred_language", "Language"),
    ("user.account_state", "Account"),
    ("user.is_active", "Active"),
)
CSV_COLUMNS = {
    "students": _COMMON
    + (
        ("profile.status", "Status"),
        ("profile.gender", "Gender"),
        ("profile.country", "Country"),
        ("profile.date_of_birth", "Date of birth"),
    ),
    "parents": _COMMON
    + (("profile.has_whatsapp", "WhatsApp"), ("profile.children", "Children")),
    "teachers": _COMMON
    + (
        ("profile.gender", "Gender"),
        ("profile.pay_currency", "Pay currency"),
        ("profile.payout_method", "Payout method"),
        ("profile.course_ids", "Course IDs"),
    ),
    "admins": _COMMON,
}


def people_in_scope(request, role: str):
    return scope_for(request.user, services.people_queryset(role))


def person_or_404(request, role: str, pk):
    return get_object_or_404(people_in_scope(request, role), pk=pk)


def _split_profile(validated: dict) -> tuple[dict, list[int] | None]:
    profile = dict(validated.get("profile") or {})
    return profile, profile.pop("course_ids", None)


class PersonListCreateView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [IsAdmin]

    @property
    def csv_columns(self):
        return CSV_COLUMNS[self.kwargs["kind"]]

    @property
    def csv_filename(self):
        return self.kwargs["kind"]

    def get(self, request, kind):
        role = KINDS[kind]
        queryset = filter_people(people_in_scope(request, role), role, request.query_params)
        if self.wants_csv():
            return self.csv_response(person_rows(list(queryset), viewer=request.user))
        page = self.paginate_queryset(queryset)
        return self.get_paginated_response(person_rows(page, viewer=request.user))

    def post(self, request, kind):
        role = KINDS[kind]
        serializer = PersonWriteSerializer(data=request.data, context={"role": role})
        serializer.is_valid(raise_exception=True)
        profile, course_ids = _split_profile(serializer.validated_data)
        try:
            with transaction.atomic():
                user = services.create_person(
                    role,
                    **serializer.validated_data["user"],
                    profile=profile,
                    created_by=request.user,
                )
                if course_ids is not None:
                    catalogue_services.set_teacher_courses(user.id, course_ids)
        except EtqanValidationError as exc:
            raise as_drf(exc) from exc
        user = services.get_person(role, user.pk)
        return Response(
            person_rows([user], viewer=request.user)[0], status=status.HTTP_201_CREATED
        )


class PersonDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, kind, pk):
        user = person_or_404(request, KINDS[kind], pk)
        return Response(person_rows([user], viewer=request.user)[0])

    def patch(self, request, kind, pk):
        user = person_or_404(request, KINDS[kind], pk)
        serializer = PersonWriteSerializer(
            data=request.data, partial=True, context={"role": user.role}
        )
        serializer.is_valid(raise_exception=True)
        profile, course_ids = _split_profile(serializer.validated_data)
        try:
            with transaction.atomic():
                services.update_person(
                    user,
                    fields=dict(serializer.validated_data.get("user") or {}),
                    profile=profile,
                )
                if course_ids is not None:
                    catalogue_services.set_teacher_courses(user.id, course_ids)
        except EtqanValidationError as exc:
            raise as_drf(exc) from exc
        user = services.get_person(user.role, user.pk)
        return Response(person_rows([user], viewer=request.user)[0])
```

`backend/etqan/identity/api/people_urls.py`:

```python
from django.urls import re_path

from etqan.identity.api import people_views as views

KIND = r"(?P<kind>students|parents|teachers|admins)"

app_name = "people"
urlpatterns = [
    re_path(rf"^{KIND}/$", views.PersonListCreateView.as_view(), name="list"),
    re_path(rf"^{KIND}/(?P<pk>\d+)/$", views.PersonDetailView.as_view(), name="detail"),
]
```

`config/api_router.py`: add `path("people/", include("etqan.identity.api.people_urls")),`.

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest -q etqan/platform/tests/test_csv.py etqan/identity/tests/test_people_api.py`
Expected: PASS.

- [ ] **Step 5: Full suite, linters, commit**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`

```bash
git -C backend add -A
git -C backend commit -m "feat(people): admin people API with search, filters, CSV export, create and edit

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: People API — account actions, guardians, bulk, `identity/me/`

**Files:**
- Create: `backend/etqan/identity/tests/test_people_actions_api.py`
- Modify: `backend/etqan/identity/api/people_views.py`, `backend/etqan/identity/api/people_urls.py`, `backend/etqan/identity/api/views.py` (`_me_payload`, `MeView.patch`), `backend/etqan/identity/api/serializers.py` (`MeUpdateSerializer`, `MeResponseSerializer`)

**Interfaces:**
- Consumes: Task 5 services; Task 7 `person_rows`, `person_summary`, `profile_payload`, `person_or_404`, `people_in_scope`, `GuardianLinkSerializer`, `StudentBulkSerializer`.
- Produces:
  - `POST /api/v1/people/<kind>/<id>/{invite|password-reset|deactivate|activate}/` → the updated person row; service refusals → 400 (`{"detail": …}` or `{"email": […]}`).
  - `GET /api/v1/people/students/<id>/guardians/` → `[summary]`; `POST` `{parent_id}` → 201 `[summary]` (idempotent; a non-parent or other-academy id → 404); `DELETE /api/v1/people/students/<id>/guardians/<parent_id>/` → 204.
  - `GET /api/v1/people/parents/<id>/children/` → `[summary]`.
  - `POST /api/v1/people/students/bulk/` `{ids, action, status?}` → `{"updated": n}` (only in-scope students are touched).
  - `GET /api/v1/identity/me/` adds `phone`, `preferred_language`, `timezone`, `profile` (the role profile; teachers get their real `course_ids`), and for parents `children[].profile`. `PATCH` accepts `full_name`, `phone`, `preferred_language`, `timezone`.

- [ ] **Step 1: Write the failing tests** — `backend/etqan/identity/tests/test_people_actions_api.py`

```python
import pytest
from django.core import mail
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services

pytestmark = pytest.mark.django_db
B = "/api/v1/people/"
ME = "/api/v1/identity/me/"


def kid(name="Yusuf", **kw):
    return services.create_person("student", full_name=name, profile={}, **kw)


def test_invite_and_reset_actions(api_for):
    admin = api_for("admin")
    student = kid()
    url = f"{B}students/{student.id}/"
    assert admin.post(url + "invite/").status_code == 400  # no email yet
    services.update_person(student, fields={"email": "kid@x.test"})
    mail.outbox.clear()
    assert admin.post(url + "invite/").status_code == 200
    assert mail.outbox[-1].to == ["kid@x.test"]
    resp = admin.post(url + "password-reset/")
    assert resp.status_code == 200
    assert resp.json()["user"]["account_state"] == "invited"


def test_self_guard_and_deactivating_another_admin(api_for):
    me = api_for("admin")
    resp = me.post(f"{B}admins/{me.user.id}/deactivate/")
    assert resp.status_code == 400
    assert "your own" in resp.json()["detail"]
    other = api_for("admin")
    rows = {r["id"]: r for r in me.get(f"{B}admins/").json()["results"]}
    assert rows[me.user.id]["deactivation_blocked"] == "self"
    assert rows[other.user.id]["deactivation_blocked"] is None
    resp = me.post(f"{B}admins/{other.user.id}/deactivate/")
    assert resp.status_code == 200
    assert resp.json()["user"]["account_state"] == "inactive"
    assert other.get(ME).status_code == 403  # their open session ended
    assert me.post(f"{B}admins/{other.user.id}/activate/").status_code == 200


def test_guardians_link_unlink_and_children(api_for):
    admin = api_for("admin")
    parent = services.create_person("parent", full_name="Omar", profile={})
    student = kid()
    url = f"{B}students/{student.id}/guardians/"
    resp = admin.post(url, {"parent_id": parent.id}, format="json")
    assert resp.status_code == 201
    assert [g["full_name"] for g in resp.json()] == ["Omar"]
    assert admin.post(url, {"parent_id": parent.id}, format="json").status_code == 201
    children = admin.get(f"{B}parents/{parent.id}/children/").json()
    assert [c["id"] for c in children] == [student.id]
    assert admin.delete(f"{url}{parent.id}/").status_code == 204
    assert admin.get(url).json() == []


def test_guardian_from_other_academy_is_404(api_for, tenants):
    admin = api_for("admin")
    student = kid()
    not_a_parent = kid("Sibling")
    with tenant_context(tenants.other):
        foreign = services.create_person("parent", full_name="Foreign", profile={})
    url = f"{B}students/{student.id}/guardians/"
    assert admin.post(url, {"parent_id": not_a_parent.id}, format="json").status_code == 404
    assert admin.post(url, {"parent_id": foreign.id}, format="json").status_code == 404
    assert services.guardians_of(student) == []


def test_bulk(api_for):
    admin = api_for("admin")
    a, b = kid(), kid("Aisha")
    body = {"ids": [a.id, b.id, admin.user.id], "action": "set_status", "status": "paused"}
    assert admin.post(f"{B}students/bulk/", body, format="json").json() == {"updated": 2}
    missing = {"ids": [a.id], "action": "set_status"}
    assert admin.post(f"{B}students/bulk/", missing, format="json").status_code == 400
    off = {"ids": [a.id], "action": "deactivate"}
    assert admin.post(f"{B}students/bulk/", off, format="json").json() == {"updated": 1}
    assert api_for("teacher").post(f"{B}students/bulk/", off, format="json").status_code == 403


def test_me_shows_own_profile_and_updates_contact_fields():
    user = services.create_person(
        "student",
        full_name="Sara",
        email="sara@x.test",
        profile={"status": "trial"},
        invite=False,
    )
    client = APIClient()
    client.force_login(user)
    me = client.get(ME).json()
    assert (me["profile"]["status"], me["preferred_language"]) == ("trial", "ar")
    resp = client.patch(
        ME, {"phone": "+201001234567", "preferred_language": "en"}, format="json"
    )
    assert resp.status_code == 200
    assert (resp.json()["phone"], resp.json()["preferred_language"]) == (
        "+201001234567",
        "en",
    )
    assert client.patch(ME, {"phone": "123"}, format="json").status_code == 400
    assert client.get(f"{B}students/").status_code == 403


def test_parent_me_reads_children_profiles():
    parent = services.create_person("parent", full_name="Omar", profile={})
    services.link_guardian(parent, kid())
    client = APIClient()
    client.force_login(parent)
    children = client.get(ME).json()["children"]
    assert children[0]["full_name"] == "Yusuf"
    assert children[0]["profile"]["status"] == "active"
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest etqan/identity/tests/test_people_actions_api.py -q`
Expected: FAIL (404s for action/guardian/bulk URLs; `KeyError: 'profile'` on `me`).

- [ ] **Step 3: Implement**

Append to `etqan/identity/api/people_views.py`:

```python
from etqan.identity.api.payloads import person_summary  # add to the imports
from etqan.identity.api.people_serializers import GuardianLinkSerializer  # imports
from etqan.identity.api.people_serializers import StudentBulkSerializer  # imports

ACTIONS = {
    "invite": lambda user, by: services.resend_invite(user),
    "password-reset": lambda user, by: services.send_password_reset(user),
    "deactivate": lambda user, by: services.deactivate(user, by=by),
    "activate": lambda user, by: services.activate(user),
}


class PersonActionView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, kind, pk, action):
        user = person_or_404(request, KINDS[kind], pk)
        ACTIONS[action](user, request.user)
        user = services.get_person(user.role, user.pk)
        return Response(person_rows([user], viewer=request.user)[0])


class GuardianListView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        student = person_or_404(request, "student", pk)
        return Response([person_summary(u) for u in services.guardians_of(student)])

    def post(self, request, pk):
        student = person_or_404(request, "student", pk)
        serializer = GuardianLinkSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        parent = person_or_404(request, "parent", serializer.validated_data["parent_id"])
        services.link_guardian(parent, student)
        return Response(
            [person_summary(u) for u in services.guardians_of(student)],
            status=status.HTTP_201_CREATED,
        )


class GuardianDeleteView(APIView):
    permission_classes = [IsAdmin]

    def delete(self, request, pk, parent_id):
        student = person_or_404(request, "student", pk)
        parent = person_or_404(request, "parent", parent_id)
        services.unlink_guardian(parent, student)
        return Response(status=status.HTTP_204_NO_CONTENT)


class ChildrenListView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        parent = person_or_404(request, "parent", pk)
        return Response([person_summary(u) for u in services.children_of(parent)])


class StudentBulkView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        serializer = StudentBulkSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        ids = list(
            people_in_scope(request, "student")
            .filter(pk__in=data["ids"])
            .values_list("pk", flat=True)
        )
        updated = services.bulk_update_students(
            ids, data["action"], status=data.get("status"), by=request.user
        )
        return Response({"updated": updated})
```

`etqan/identity/api/people_urls.py` — `urlpatterns` becomes:

```python
urlpatterns = [
    re_path(r"^students/bulk/$", views.StudentBulkView.as_view(), name="bulk"),
    re_path(
        r"^students/(?P<pk>\d+)/guardians/$",
        views.GuardianListView.as_view(),
        name="guardians",
    ),
    re_path(
        r"^students/(?P<pk>\d+)/guardians/(?P<parent_id>\d+)/$",
        views.GuardianDeleteView.as_view(),
        name="guardian",
    ),
    re_path(
        r"^parents/(?P<pk>\d+)/children/$",
        views.ChildrenListView.as_view(),
        name="children",
    ),
    re_path(rf"^{KIND}/$", views.PersonListCreateView.as_view(), name="list"),
    re_path(rf"^{KIND}/(?P<pk>\d+)/$", views.PersonDetailView.as_view(), name="detail"),
    re_path(
        rf"^{KIND}/(?P<pk>\d+)/(?P<action>invite|password-reset|deactivate|activate)/$",
        views.PersonActionView.as_view(),
        name="action",
    ),
]
```

`etqan/identity/api/serializers.py`:

```python
class MeUpdateSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=255, required=False)
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    preferred_language = serializers.ChoiceField(
        choices=[("ar", "Arabic"), ("en", "English")], required=False
    )
    timezone = serializers.CharField(max_length=64, required=False)
```

In `MeResponseSerializer` (documentation only), add `phone = serializers.CharField()`, `preferred_language = serializers.CharField()`, `timezone = serializers.CharField()`, `role = serializers.CharField()`, `profile = serializers.DictField()`, and make `email = serializers.EmailField(allow_null=True)`.

`etqan/identity/api/views.py`:

```python
from etqan.catalogue import services as catalogue_services  # imports
from etqan.identity.api.payloads import profile_payload  # imports


def _me_payload(user) -> dict:
    profiles = services.get_profile_types(user.id)
    course_ids = None
    if user.role == "teacher":
        course_ids = catalogue_services.course_ids_for_teachers([user.id]).get(user.id)
    payload = {
        "id": user.id,
        "email": user.email,
        "full_name": user.full_name,
        "phone": user.phone,
        "preferred_language": user.preferred_language,
        "timezone": user.timezone,
        "role": user.role,
        "profiles": profiles,
        "profile": profile_payload(user, course_ids=course_ids),
    }
    if "parent" in profiles:
        payload["children"] = [
            {
                "id": child.user_id,
                "full_name": child.user.full_name,
                "student_profile_id": child.id,
                "profile": profile_payload(child.user),
            }
            for child in services.get_children(user.id).select_related("user")
        ]
    return payload
```

`MeView.patch` becomes:

```python
    @extend_schema(request=MeUpdateSerializer, responses={200: MeResponseSerializer})
    def patch(self, request):
        serializer = MeUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        services.update_person(request.user, fields=dict(serializer.validated_data))
        return Response(_me_payload(request.user))
```

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest -q etqan/identity`
Expected: PASS (existing `TestMe` / `test_patch_me_*` tests still pass).

- [ ] **Step 5: Full suite, linters, commit**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`

```bash
git -C backend add -A
git -C backend commit -m "feat(people): account actions, guardians, bulk student actions and a richer me endpoint

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Catalogue API — courses and packages

**Files:**
- Create: `backend/etqan/catalogue/api/{__init__,serializers,views,urls}.py`, `backend/etqan/catalogue/tests/test_api.py`
- Modify: `backend/config/api_router.py`

**Interfaces:**
- Consumes: Task 6 services and `scope_for`; `CSVExportMixin` (Task 7); `IsAdmin`, `IsTeacher`, `ReadOnly` (Task 2).
- Produces:
  - `/api/v1/catalogue/courses/` and `/api/v1/catalogue/packages/`: `GET` list (paginated; `is_active=true|false`, `q` over both names, `format=csv`), `POST`; `/<id>/` `GET`, `PATCH`, `PUT`, `DELETE` (204); `/<id>/duplicate/` `POST` → 201 copy.
  - Course body: `name_ar, name_en, description_ar, description_en, language, is_active, teacher_ids` (User ids; in responses always present).
  - Package body: all package fields; response adds read-only `sessions_total`.
  - Permissions: admin everything; teacher `GET` active rows only; parent/student 403.

- [ ] **Step 1: Write the failing tests** — `backend/etqan/catalogue/tests/test_api.py`

```python
import csv
import io

import pytest

from etqan.catalogue import services
from etqan.identity import services as identity_services

pytestmark = pytest.mark.django_db
C = "/api/v1/catalogue/"
PACKAGE = {
    "name_ar": "شهري",
    "name_en": "Monthly",
    "sessions_per_week": 2,
    "session_minutes": 45,
    "duration_value": 1,
    "duration_unit": "month",
    "price_minor": 150000,
    "currency": "egp",
}


def test_roles(api_for):
    services.create_course(name_ar="أ", name_en="Active")
    services.create_course(name_ar="ب", name_en="Retired", is_active=False)
    teacher = api_for("teacher")
    rows = teacher.get(f"{C}courses/").json()["results"]
    assert [r["name_en"] for r in rows] == ["Active"]
    assert teacher.post(f"{C}courses/", {}, format="json").status_code == 403
    for role in ("parent", "student"):
        assert api_for(role).get(f"{C}courses/").status_code == 403
    assert len(api_for("admin").get(f"{C}courses/").json()["results"]) == 2


def test_course_crud_with_teachers(api_for):
    admin = api_for("admin")
    t = identity_services.create_person(
        "teacher", full_name="Bilal", profile={"gender": "male"}
    )
    resp = admin.post(
        f"{C}courses/",
        {"name_ar": "تجويد", "name_en": "Tajweed", "language": "both", "teacher_ids": [t.id]},
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    course_id = resp.json()["id"]
    assert resp.json()["teacher_ids"] == [t.id]
    resp = admin.patch(f"{C}courses/{course_id}/", {"teacher_ids": []}, format="json")
    assert resp.json()["teacher_ids"] == []
    assert admin.post(f"{C}courses/", {"name_ar": "", "name_en": "X"}, format="json").status_code == 400
    assert admin.delete(f"{C}courses/{course_id}/").status_code == 204


@pytest.mark.parametrize(
    ("field", "value"),
    [("sessions_per_week", 15), ("session_minutes", 10), ("duration_unit", "week"), ("price_minor", -1)],
)
def test_package_bounds(api_for, field, value):
    resp = api_for("admin").post(
        f"{C}packages/", {**PACKAGE, field: value}, format="json"
    )
    assert resp.status_code == 400
    assert field in resp.json()


def test_package_sessions_total_is_derived_and_read_only(api_for):
    admin = api_for("admin")
    resp = admin.post(f"{C}packages/", {**PACKAGE, "sessions_total": 999}, format="json")
    assert resp.status_code == 201, resp.json()
    assert (resp.json()["sessions_total"], resp.json()["currency"]) == (8, "EGP")
    package_id = resp.json()["id"]
    resp = admin.patch(
        f"{C}packages/{package_id}/",
        {"duration_value": 8, "duration_unit": "day"},
        format="json",
    )
    assert resp.json()["sessions_total"] == 4


def test_duplicate(api_for):
    admin = api_for("admin")
    course = services.create_course(name_ar="تجويد", name_en="Tajweed")
    resp = admin.post(f"{C}courses/{course.id}/duplicate/")
    assert resp.status_code == 201
    assert (resp.json()["name_en"], resp.json()["is_active"]) == ("Tajweed (copy)", False)
    assert api_for("teacher").post(f"{C}courses/{course.id}/duplicate/").status_code == 403


def test_filters_and_csv(api_for):
    admin = api_for("admin")
    services.create_package(**{**PACKAGE, "currency": "EGP"})
    services.create_package(**{**PACKAGE, "currency": "EGP", "name_en": "Old", "name_ar": "قديم", "is_active": False})
    assert [r["name_en"] for r in admin.get(f"{C}packages/?is_active=false").json()["results"]] == ["Old"]
    assert [r["name_en"] for r in admin.get(f"{C}packages/?q=شهري").json()["results"]] == ["Monthly"]
    resp = admin.get(f"{C}packages/?is_active=true&format=csv")
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0][:3] == ["ID", "Name (English)", "Name (Arabic)"]
    assert [r[1] for r in rows[1:]] == ["Monthly"]
    assert "Sessions total" in rows[0]
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest etqan/catalogue/tests/test_api.py -q`
Expected: FAIL (404 on `/api/v1/catalogue/…`).

- [ ] **Step 3: Implement**

`backend/etqan/catalogue/api/__init__.py` — empty.

`backend/etqan/catalogue/api/serializers.py`:

```python
from rest_framework import serializers

from etqan.catalogue import services
from etqan.catalogue.models import Course
from etqan.catalogue.models import Package

READ_ONLY = ["id", "created_at", "updated_at"]


class CourseSerializer(serializers.ModelSerializer):
    teacher_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False, write_only=True
    )

    class Meta:
        model = Course
        fields = [
            "id",
            "name_ar",
            "name_en",
            "description_ar",
            "description_en",
            "language",
            "is_active",
            "teacher_ids",
            "created_at",
            "updated_at",
        ]
        read_only_fields = READ_ONLY

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["teacher_ids"] = services.course_teacher_ids(instance)
        return data


class PackageSerializer(serializers.ModelSerializer):
    class Meta:
        model = Package
        fields = [
            "id",
            "name_ar",
            "name_en",
            "description_ar",
            "description_en",
            "sessions_per_week",
            "session_minutes",
            "duration_value",
            "duration_unit",
            "freeze_days_allowed",
            "price_minor",
            "currency",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = READ_ONLY
        # Upper-cased by the service before the model validator runs.
        extra_kwargs = {"currency": {"validators": []}}

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["sessions_total"] = services.sessions_total(instance)
        return data
```

`backend/etqan/catalogue/api/views.py`:

```python
from django.db.models import Q
from rest_framework import status
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from etqan.catalogue import services
from etqan.catalogue.api.serializers import CourseSerializer
from etqan.catalogue.api.serializers import PackageSerializer
from etqan.catalogue.models import Course
from etqan.catalogue.models import Package
from etqan.catalogue.scopes import scope_for
from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import ReadOnly

_BOOL = {"true": True, "false": False}
_NAMES = (("id", "ID"), ("name_en", "Name (English)"), ("name_ar", "Name (Arabic)"))


class _CatalogueViewSet(CSVExportMixin, viewsets.ModelViewSet):
    permission_classes = [IsAdmin | (IsTeacher & ReadOnly)]
    model: type = Course

    def get_queryset(self):
        queryset = scope_for(self.request.user, self.model.objects.all())
        params = self.request.query_params
        if (active := params.get("is_active")) in _BOOL:
            queryset = queryset.filter(is_active=_BOOL[active])
        if q := params.get("q", "").strip():
            queryset = queryset.filter(Q(name_ar__icontains=q) | Q(name_en__icontains=q))
        return queryset.order_by("name_en", "id")

    def list(self, request, *args, **kwargs):
        if self.wants_csv():
            rows = self.get_serializer(self.get_queryset(), many=True).data
            return self.csv_response(list(rows))
        return super().list(request, *args, **kwargs)

    def _split(self, serializer):
        data = dict(serializer.validated_data)
        return data, data.pop("teacher_ids", None)

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        copy = self.duplicate_object(self.get_object())
        return Response(self.get_serializer(copy).data, status=status.HTTP_201_CREATED)


class CourseViewSet(_CatalogueViewSet):
    model = Course
    serializer_class = CourseSerializer
    csv_filename = "courses"
    csv_columns = _NAMES + (
        ("language", "Language"),
        ("is_active", "Active"),
        ("teacher_ids", "Teacher IDs"),
    )

    def perform_create(self, serializer):
        data, teacher_ids = self._split(serializer)
        serializer.instance = services.create_course(teacher_ids=teacher_ids, **data)

    def perform_update(self, serializer):
        data, teacher_ids = self._split(serializer)
        serializer.instance = services.update_course(
            serializer.instance, teacher_ids=teacher_ids, **data
        )

    def perform_destroy(self, instance):
        services.delete_course(instance)

    def duplicate_object(self, obj):
        return services.duplicate_course(obj)


class PackageViewSet(_CatalogueViewSet):
    model = Package
    serializer_class = PackageSerializer
    csv_filename = "packages"
    csv_columns = _NAMES + (
        ("sessions_per_week", "Sessions per week"),
        ("session_minutes", "Session minutes"),
        ("duration_value", "Duration"),
        ("duration_unit", "Duration unit"),
        ("sessions_total", "Sessions total"),
        ("freeze_days_allowed", "Freeze days"),
        ("price_minor", "Price (minor units)"),
        ("currency", "Currency"),
        ("is_active", "Active"),
    )

    def perform_create(self, serializer):
        serializer.instance = services.create_package(**serializer.validated_data)

    def perform_update(self, serializer):
        serializer.instance = services.update_package(
            serializer.instance, **serializer.validated_data
        )

    def perform_destroy(self, instance):
        services.delete_package(instance)

    def duplicate_object(self, obj):
        return services.duplicate_package(obj)
```

`backend/etqan/catalogue/api/urls.py`:

```python
from rest_framework.routers import SimpleRouter

from etqan.catalogue.api.views import CourseViewSet
from etqan.catalogue.api.views import PackageViewSet

router = SimpleRouter()
router.register("courses", CourseViewSet, basename="courses")
router.register("packages", PackageViewSet, basename="packages")

app_name = "catalogue"
urlpatterns = router.urls
```

`config/api_router.py`: add `path("catalogue/", include("etqan.catalogue.api.urls")),`.

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest -q etqan/catalogue`
Expected: PASS.

- [ ] **Step 5: Full suite, linters, commit**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`

```bash
git -C backend add -A
git -C backend commit -m "feat(catalogue): course and package API with duplicate, filters and CSV

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dev seeds and e2e mail settings

**Files:**
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py`, `backend/etqan/tenants/tests/test_seed_dev.py`, `backend/config/settings/base.py`

**Interfaces:**
- Consumes: `identity_services.create_person`, `link_guardian`, `has_people`, `children_of`; `catalogue_services.create_course`, `create_package`, `set_teacher_courses`, `has_catalogue`.
- Produces:
  - `seed_dev` seeds people and catalogue once per academy. It skips an academy that already has any non-admin person or any course/package. Demo gets 2 teachers linked to courses, 2 courses, 2 packages (one `month`, one `day`), 2 parents (Omar Hassan with two children), and 3 students (Aisha Omar has no email). Other gets 1 teacher, 1 course, 1 package, 1 parent, 1 student. Seeded people get no password and no email (plan D17).
  - Settings: `CELERY_TASK_ALWAYS_EAGER = env.bool("CELERY_TASK_ALWAYS_EAGER", default=False)`, `EMAIL_FILE_PATH = env("DJANGO_EMAIL_FILE_PATH", default=str(BASE_DIR / "tmp" / "mail"))`.

- [ ] **Step 1: Write the failing test** — append to `backend/etqan/tenants/tests/test_seed_dev.py`

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_adds_people_and_catalogue_once():
    from etqan.catalogue.models import Course  # noqa: PLC0415
    from etqan.catalogue.models import Package  # noqa: PLC0415
    from etqan.identity import services as identity_services  # noqa: PLC0415

    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert User.objects.filter(role="teacher").count() == 2
        assert User.objects.filter(role="parent").count() == 2
        students = User.objects.filter(role="student")
        assert students.count() == 3
        assert students.filter(email=None).count() == 1
        assert Course.objects.count() == 2
        assert all(course.teachers.exists() for course in Course.objects.all())
        assert sorted(Package.objects.values_list("duration_unit", flat=True)) == [
            "day",
            "month",
        ]
        omar = User.objects.get(full_name="Omar Hassan")
        assert len(identity_services.children_of(omar)) == 2
    with tenant_context(other):
        assert User.objects.filter(role="student").count() == 1
        assert Course.objects.get().name_en == "Arabic Grammar"
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py -q`
Expected: FAIL (`assert 0 == 2`).

- [ ] **Step 3: Implement** — in `seed_dev.py` add imports `from etqan.catalogue import services as catalogue_services` and `from etqan.identity import services as identity_services`, then:

```python
PEOPLE = {
    "demo": {
        "courses": [
            {"name_en": "Tajweed", "name_ar": "التجويد", "language": "ar"},
            {
                "name_en": "Quran Memorisation",
                "name_ar": "تحفيظ القرآن",
                "language": "both",
            },
        ],
        "packages": [
            {
                "name_en": "Monthly, 2 a week",
                "name_ar": "شهري، حصتان أسبوعيًا",
                "sessions_per_week": 2,
                "session_minutes": 45,
                "duration_value": 1,
                "duration_unit": "month",
                "price_minor": 150000,
                "currency": "EGP",
            },
            {
                "name_en": "Two-week intensive",
                "name_ar": "مكثّف أسبوعان",
                "sessions_per_week": 5,
                "session_minutes": 30,
                "duration_value": 14,
                "duration_unit": "day",
                "price_minor": 90000,
                "currency": "EGP",
            },
        ],
        "teachers": [
            {
                "full_name": "Ustadh Bilal",
                "email": "bilal@demo.test",
                "gender": "male",
                "courses": ["Tajweed", "Quran Memorisation"],
            },
            {
                "full_name": "Ustadha Maryam",
                "email": "maryam@demo.test",
                "gender": "female",
                "courses": ["Quran Memorisation"],
            },
        ],
        "parents": [
            {
                "full_name": "Omar Hassan",
                "email": "omar@demo.test",
                "phone": "+201001234567",
                "has_whatsapp": True,
            },
            {"full_name": "Huda Ali", "email": "huda@demo.test", "has_whatsapp": False},
        ],
        "students": [
            {
                "full_name": "Yusuf Omar",
                "email": "yusuf@demo.test",
                "status": "active",
                "parents": ["Omar Hassan"],
            },
            {
                "full_name": "Aisha Omar",
                "email": None,
                "status": "trial",
                "parents": ["Omar Hassan"],
            },
            {
                "full_name": "Zaid Huda",
                "email": "zaid@demo.test",
                "status": "paused",
                "parents": ["Huda Ali"],
            },
        ],
    },
    "other": {
        "courses": [{"name_en": "Arabic Grammar", "name_ar": "النحو", "language": "ar"}],
        "packages": [
            {
                "name_en": "Monthly",
                "name_ar": "شهري",
                "sessions_per_week": 1,
                "session_minutes": 60,
                "duration_value": 1,
                "duration_unit": "month",
                "price_minor": 4000,
                "currency": "USD",
            }
        ],
        "teachers": [
            {
                "full_name": "Ustadh Kareem",
                "email": "kareem@other.test",
                "gender": "male",
                "courses": ["Arabic Grammar"],
            }
        ],
        "parents": [
            {"full_name": "Salma Nabil", "email": "salma@other.test", "has_whatsapp": True}
        ],
        "students": [
            {
                "full_name": "Layla Nabil",
                "email": "layla@other.test",
                "status": "active",
                "parents": ["Salma Nabil"],
            }
        ],
    },
}


def seed_people(spec: dict) -> None:
    """Idempotent: an academy that already has people or catalogue is left alone."""
    if identity_services.has_people() or catalogue_services.has_catalogue():
        return
    courses = {
        c["name_en"]: catalogue_services.create_course(**c) for c in spec["courses"]
    }
    for package in spec["packages"]:
        catalogue_services.create_package(**package)
    for t in spec["teachers"]:
        teacher = identity_services.create_person(
            "teacher",
            full_name=t["full_name"],
            email=t["email"],
            profile={"gender": t["gender"]},
            invite=False,
        )
        catalogue_services.set_teacher_courses(
            teacher.id, [courses[name].id for name in t["courses"]]
        )
    parents = {
        p["full_name"]: identity_services.create_person(
            "parent",
            full_name=p["full_name"],
            email=p["email"],
            phone=p.get("phone"),
            profile={"has_whatsapp": p["has_whatsapp"]},
            invite=False,
        )
        for p in spec["parents"]
    }
    for s in spec["students"]:
        student = identity_services.create_person(
            "student",
            full_name=s["full_name"],
            email=s["email"],
            profile={"status": s["status"]},
            invite=False,
        )
        for name in s["parents"]:
            identity_services.link_guardian(parents[name], student)
```

and in `handle`, after `site_services.seed_site(**SITES[subdomain])` inside the same `with tenant_context(academy):` block:

```python
                seed_people(PEOPLE[subdomain])
```

`config/settings/base.py` — in the CELERY section add:

```python
# The CI e2e job runs Django without a worker; eager tasks send its email inline.
CELERY_TASK_ALWAYS_EAGER = env.bool("CELERY_TASK_ALWAYS_EAGER", default=False)
```

and in the EMAIL section:

```python
# Used only with the file backend (the CI e2e job reads invites from here).
EMAIL_FILE_PATH = env("DJANGO_EMAIL_FILE_PATH", default=str(BASE_DIR / "tmp" / "mail"))
```

(`config/settings/test.py` keeps `CELERY_TASK_ALWAYS_EAGER = True`.)

- [ ] **Step 4: Run**

Run: `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py`
Expected: PASS.

- [ ] **Step 5: Full suite, linters, commit, open the backend PR**

Run: `.venv/bin/pytest -q --cov=etqan && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`
Expected: PASS, coverage ≥ 80%.

```bash
git -C backend add -A
git -C backend commit -m "feat(seed): people and catalogue for the demo and other academies

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C backend push -u origin feat/people-catalogue
```

---
### Task 11: Dashboard — retire Kaleem screens, grouped admin nav, My account

**Files:**
- Delete: `dashboard/src/routes/register.tsx`, `dashboard/src/routes/_authed/family.tsx`, `dashboard/src/routes/_authed/family.test.tsx`, and in `dashboard/src/features/identity/components/`: `RegisterForm`, `AddChildForm`, `ChildrenCard`, `InviteCard`, `AcceptInviteCard`, `ChangeChildEmailDialog`, `SetChildPasswordDialog`, `EditChildPreferencesDialog`, `StudentPreferencesCard`, `TeacherGenderCard` (each `.tsx` and `.test.tsx`), `dashboard/src/features/website/require-admin.ts`
- Create: `dashboard/src/features/identity/require-admin.ts`, `dashboard/src/features/identity/components/MyProfileCard.tsx`, `dashboard/src/features/identity/components/MyProfileCard.test.tsx`, `dashboard/src/lib/timezones.ts`, `dashboard/src/lib/timezones.test.ts`, `dashboard/src/ui/textarea.tsx`, `dashboard/src/ui/textarea.test.tsx`
- Modify: `dashboard/src/features/identity/{api.ts,api.test.ts,schemas.ts,schemas.test.ts,queries.ts,queries.test.tsx,index.ts}`, `dashboard/src/features/identity/components/{ProfileEditForm.tsx,ProfileEditForm.test.tsx}`, `dashboard/src/features/shell/{nav.ts,nav.test.ts,AppSidebar.tsx,AppSidebar.test.tsx}`, `dashboard/src/routes/_authed/{index.tsx,index.test.tsx,account.tsx,account.test.tsx,website.tsx,website.guard.test.tsx}`, `dashboard/src/routes/{login.tsx,login.test.tsx}`, `dashboard/src/ui/index.ts`, `dashboard/src/locales/{en,ar}/common.json`

**Interfaces:**
- Consumes: `identity/me/` payload from Task 8.
- Produces:
  - `Me` gains optional `phone?: string`, `preferred_language?: Language`, `timezone?: string`, `profile?: Record<string, unknown>`; `email: string | null`; `ChildSummary.profile?: Record<string, unknown>`. `type Language = "ar" | "en"`.
  - `parseApiError` flattens nested DRF errors into dotted keys (`{"user": {"email": ["x"]}}` → `fieldErrors["user.email"] = "x"`).
  - `requireAdmin(context)` now lives at `@/features/identity/require-admin`.
  - `NavItem.group?: NavGroup` (`"people" | "catalogue" | "settings"`), `groupNavItems(items) -> { group?: NavGroup; items: NavItem[] }[]` (consecutive runs), and `NAV_ITEMS` order: `/`, people (`/people/students`, `/people/parents`, `/people/teachers`, `/people/admins`), catalogue (`/catalogue/courses`, `/catalogue/packages`), settings (`/website`, `/settings/academy`), `/account`. Every grouped item has `requiresRole: "admin"`.
  - `timezoneOptions(current?: string) -> string[]` (IANA list, always containing `UTC` and `current`).
  - `<Textarea>` in `@/ui` (same props as a native `<textarea>`).
  - `ProfileEditForm` edits `full_name`, `phone`, `preferred_language`, `timezone`, and after saving switches i18n to `preferred_language`.
  - `<MyProfileCard me>` shows the signed-in user's own role profile (read-only) and, for parents, their children's names and statuses.

- [ ] **Step 1: Branch**

```bash
git -C dashboard switch -c feat/people-catalogue
```

- [ ] **Step 2: Write the failing tests**

`src/features/shell/nav.test.ts` — replace the `describe("NAV_ITEMS", …)` block with:

```ts
describe("NAV_ITEMS", () => {
	it("ships the grouped admin areas in order", () => {
		expect(NAV_ITEMS.map((i) => i.to)).toEqual([
			"/",
			"/people/students",
			"/people/parents",
			"/people/teachers",
			"/people/admins",
			"/catalogue/courses",
			"/catalogue/packages",
			"/website",
			"/settings/academy",
			"/account",
		]);
	});

	it("gates every grouped item to admins", () => {
		for (const item of NAV_ITEMS.filter((i) => i.group)) {
			expect(item.requiresRole).toBe("admin");
		}
	});

	it("shows only home and account to non-admins", () => {
		for (const role of ["teacher", "student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/account",
			]);
		}
	});

	it("groups consecutive items", () => {
		const groups = groupNavItems(visibleNavItems(NAV_ITEMS, [], "admin"));
		expect(groups.map((g) => g.group)).toEqual([
			undefined,
			"people",
			"catalogue",
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(4);
	});
});
```

(import `groupNavItems` from `./nav`; the `visibleNavItems` describe block above stays.)

`src/features/shell/AppSidebar.test.tsx` — append:

```tsx
it("labels each group of links", async () => {
	renderSidebar();
	expect(await screen.findByText("People")).toBeInTheDocument();
	expect(screen.getByText("Catalogue")).toBeInTheDocument();
	expect(screen.getByText("Settings")).toBeInTheDocument();
	expect(screen.getByRole("link", { name: "Students" })).toBeInTheDocument();
});
```

(inside the existing `describe("AppSidebar", …)`; `renderSidebar` passes all `NAV_ITEMS` unfiltered.)

`src/features/identity/api.test.ts` — add to `describe("parseApiError", …)`:

```ts
	it("flattens nested field errors into dotted paths", () => {
		const error = new AxiosError("Bad", "400", undefined, undefined, {
			status: 400,
			data: { user: { email: ["Taken."] }, profile: { gender: ["Pick one."] } },
		} as never);
		expect(parseApiError(error).fieldErrors).toEqual({
			"user.email": "Taken.",
			"profile.gender": "Pick one.",
		});
	});
```

`src/features/identity/components/ProfileEditForm.test.tsx` — change the `me` fixture to include `phone: ""`, `preferred_language: "en" as const`, `timezone: "UTC"`, mock `updateMe` in each test, and add:

```tsx
	it("switches the dashboard language to the saved preference", async () => {
		vi.mocked(identityApi.updateMe).mockResolvedValue({
			...me,
			preferred_language: "ar",
		});
		const user = userEvent.setup();
		render(<ProfileEditForm me={me} />, { wrapper });
		await user.selectOptions(screen.getByLabelText(/preferred language/i), "ar");
		await user.click(screen.getByRole("button", { name: /save changes/i }));
		await waitFor(() => expect(i18n.language).toBe("ar"));
		expect(identityApi.updateMe).toHaveBeenCalledWith(
			expect.objectContaining({ preferred_language: "ar" }),
		);
		await act(() => i18n.changeLanguage("en"));
	});

	it("rejects a phone that is not in international format", async () => {
		const user = userEvent.setup();
		render(<ProfileEditForm me={me} />, { wrapper });
		await user.type(screen.getByLabelText(/phone/i), "0100");
		await user.click(screen.getByRole("button", { name: /save changes/i }));
		expect(await screen.findByText(/international format/i)).toBeInTheDocument();
		expect(identityApi.updateMe).not.toHaveBeenCalled();
	});
```

(imports: `waitFor` from Testing Library, `i18n from "@/lib/i18n"`.)

`src/features/identity/components/MyProfileCard.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import type { Me } from "../schemas";
import { MyProfileCard } from "./MyProfileCard";

const base: Me = {
	id: 1,
	email: null,
	full_name: "Sara",
	role: "student",
	profiles: ["student"],
};

describe("MyProfileCard", () => {
	it("shows a student's own status and country", () => {
		render(
			<MyProfileCard
				me={{ ...base, profile: { status: "trial", country: "EG", gender: "" } }}
			/>,
		);
		expect(screen.getByText("Trial")).toBeInTheDocument();
		expect(screen.getByText("Egypt")).toBeInTheDocument();
	});

	it("lists a parent's children with their status", () => {
		render(
			<MyProfileCard
				me={{
					...base,
					role: "parent",
					profiles: ["parent"],
					profile: { has_whatsapp: true, notes: "" },
					children: [
						{
							id: 9,
							full_name: "Yusuf",
							student_profile_id: 3,
							profile: { status: "paused" },
						},
					],
				}}
			/>,
		);
		expect(screen.getByText("Yusuf")).toBeInTheDocument();
		expect(screen.getByText("Paused")).toBeInTheDocument();
	});

	it("renders nothing for an admin", () => {
		const { container } = render(
			<MyProfileCard me={{ ...base, role: "admin", profiles: [], profile: {} }} />,
		);
		expect(container).toBeEmptyDOMElement();
	});
});
```

`src/lib/timezones.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { timezoneOptions } from "./timezones";

describe("timezoneOptions", () => {
	it("lists IANA zones and always includes UTC and the current value", () => {
		const zones = timezoneOptions("Etc/GMT+3");
		expect(zones).toContain("Africa/Cairo");
		expect(zones).toContain("UTC");
		expect(zones[0]).toBe("Etc/GMT+3");
	});
});
```

`src/ui/textarea.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Textarea } from "./textarea";

describe("Textarea", () => {
	it("renders a native textarea with the given props", () => {
		render(<Textarea aria-label="Notes" defaultValue="x" rows={3} />);
		const box = screen.getByRole("textbox", { name: "Notes" });
		expect(box.tagName).toBe("TEXTAREA");
		expect(box).toHaveValue("x");
	});
});
```

`src/routes/login.test.tsx` — the test becomes "tells visitors to ask their academy for an account":

```tsx
		expect(
			screen.getByText(/ask your academy for an account/i),
		).toBeInTheDocument();
		expect(screen.queryByRole("link", { name: /ask your academy/i })).toBeNull();
```

`src/routes/_authed/index.test.tsx` — replace the two family spotlight tests with:

```tsx
	it("shows people and catalogue tiles to an admin", async () => {
		renderHome({ ...student, role: "admin", profiles: [] });
		expect(await screen.findByText("Students")).toBeInTheDocument();
		expect(screen.getByText("Courses")).toBeInTheDocument();
	});

	it("shows a student only their account tile", async () => {
		renderHome(student);
		expect(await screen.findByText("Account")).toBeInTheDocument();
		expect(screen.queryByText("Students")).toBeNull();
	});
```

`src/routes/_authed/account.test.tsx` — drop `getStudentProfile` from the mock and `beforeEach`, and replace the two learning-preferences tests with:

```tsx
	it("shows the student's own profile card", async () => {
		renderAccount({ ...student, profile: { status: "active", country: "" } });
		expect(await screen.findByText("My profile")).toBeInTheDocument();
		expect(screen.getByText("Active")).toBeInTheDocument();
	});
```

In `src/features/identity/schemas.test.ts`, delete the registration, children/invites and preferences describe blocks, keep the login one, and add:

```ts
describe("profile edit schema", () => {
	it("accepts an empty or international phone and rejects others", () => {
		const base = { full_name: "A", preferred_language: "ar", timezone: "UTC" };
		expect(profileEditSchema.safeParse({ ...base, phone: "" }).success).toBe(true);
		expect(
			profileEditSchema.safeParse({ ...base, phone: "+201001234567" }).success,
		).toBe(true);
		expect(profileEditSchema.safeParse({ ...base, phone: "0100" }).success).toBe(
			false,
		);
	});
});
```

In `src/features/identity/queries.test.tsx`, delete the `children + invite queries` and `student profile queries` describe blocks.

- [ ] **Step 3: Run to verify failure**

Run: `npx pnpm@10 vitest run src/features/shell src/features/identity src/lib/timezones.test.ts src/ui/textarea.test.tsx src/routes`
Expected: FAIL (`groupNavItems` not exported, no `Textarea`, `MyProfileCard` missing, and so on).

- [ ] **Step 4: Implement**

Delete the files listed under "Delete". Remove every export that belonged to them from `src/features/identity/index.ts`.

`src/features/identity/schemas.ts` — delete `accountTypeSchema`, `registerSchema`, `RegisterInput`, `Child`, `Invite`, `addChildSchema`, `AddChildInput`, `changeChildEmailSchema`, `ChangeChildEmailInput`, `setChildPasswordSchema`, `SetChildPasswordInput`, `acceptInviteSchema`, `AcceptInviteInput`, `TimeSlot`, `TeacherGender`, `StudentProfile`, `DeclaredGender`, `TeacherProfile`, `WEEKDAYS`, `timeSlotSchema`, `studentPreferencesSchema`, `StudentPreferencesInput`, `childPreferencesSchema`, `ChildPreferencesInput`. Replace `profileEditSchema`, `ChildSummary` and `Me` with:

```ts
export type Language = "ar" | "en";

export const phoneSchema = z
	.string()
	.trim()
	.regex(/^(\+[1-9]\d{6,14})?$/, "Use international format, like +201001234567.");

export const profileEditSchema = z.object({
	full_name: z.string().trim().min(1),
	phone: phoneSchema,
	preferred_language: z.enum(["ar", "en"]),
	timezone: z.string().min(1),
});

export interface ChildSummary {
	id: number;
	full_name: string;
	student_profile_id: number;
	profile?: Record<string, unknown>;
}

export interface Me {
	id: number;
	email: string | null;
	full_name: string;
	phone?: string;
	preferred_language?: Language;
	timezone?: string;
	role: Role;
	profiles: readonly ProfileType[];
	profile?: Record<string, unknown>;
	children?: readonly ChildSummary[];
}
```

`src/features/identity/api.ts` — delete `RegisterResponse` and the `identityApi` members `register`, `listChildren`, `addChild`, `setChildPassword`, `setChildEmail`, `setChildPreferences`, `resendChildVerification`, `createInvite`, `acceptInvite`, `getStudentProfile`, `saveStudentProfile`, `getTeacherProfile`, `saveTeacherProfile` (and their type imports). Replace the loop in `parseApiError` with:

```ts
function collect(
	path: string,
	value: unknown,
	out: ParsedApiError,
): void {
	if (value && typeof value === "object" && !Array.isArray(value)) {
		for (const [key, nested] of Object.entries(value)) {
			collect(path ? `${path}.${key}` : key, nested, out);
		}
		return;
	}
	const msg = Array.isArray(value) ? String(value[0]) : String(value);
	if (path === "non_field_errors" || path === "detail") out.message = msg;
	else out.fieldErrors[path] = msg;
}
```

and in `parseApiError`: `if (data && typeof data === "object") collect("", data, result);`.

`src/features/identity/queries.ts` — delete `useRegister`, `childrenQueryKey`, `childrenQueryOptions`, `useChildren`, `useAddChild`, `useSetChildPassword`, `useSetChildEmail`, `useSetChildPreferences`, `useResendChildVerification`, `useCreateInvite`, `useAcceptInvite`, `studentProfileQueryKey`, `studentProfileQueryOptions`, `useStudentProfile`, `useSaveStudentProfile`, `teacherProfileQueryKey`, `useTeacherProfile`, `useSaveTeacherProfile`, and their type imports.

Move `src/features/website/require-admin.ts` verbatim to `src/features/identity/require-admin.ts`, then update the imports in `src/routes/_authed/website.tsx` and `src/routes/_authed/website.guard.test.tsx` to `@/features/identity/require-admin`.

`src/lib/timezones.ts`:

```ts
function allZones(): string[] {
	const intl = Intl as unknown as {
		supportedValuesOf?: (key: string) => string[];
	};
	return intl.supportedValuesOf ? intl.supportedValuesOf("timeZone") : [];
}

/** IANA timezones for a <select>, with UTC and the current value always present. */
export function timezoneOptions(current?: string): string[] {
	const zones = allZones();
	const withUtc = zones.includes("UTC") ? zones : ["UTC", ...zones];
	return current && !withUtc.includes(current) ? [current, ...withUtc] : withUtc;
}
```

`src/ui/textarea.tsx`:

```tsx
import type * as React from "react";
import { cn } from "@/lib/cn";

/** Multi-line text input matching `Input`'s border, focus and RTL behaviour. */
export function Textarea({
	className,
	...props
}: React.ComponentProps<"textarea">) {
	return (
		<textarea
			className={cn(
				"flex min-h-24 w-full rounded-md border border-input bg-background px-3 py-2 text-base text-foreground sm:text-sm",
				"transition-colors motion-reduce:transition-none hover:border-ring/60",
				"placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
				"aria-invalid:border-destructive text-start",
				className,
			)}
			{...props}
		/>
	);
}
```

and `export { Textarea } from "./textarea";` in `src/ui/index.ts`.

`src/features/shell/nav.ts`:

```ts
import type { LucideIcon } from "lucide-react";
import {
	BookOpen,
	Globe,
	GraduationCap,
	Home,
	Package,
	Presentation,
	Settings,
	ShieldCheck,
	User,
	Users,
} from "lucide-react";
import type { ProfileType, Role } from "@/features/identity/schemas";

export type NavGroup = "people" | "catalogue" | "settings";

export type NavItem = {
	to: string;
	labelKey: string;
	icon: LucideIcon;
	requires?: ProfileType;
	requiresAny?: ProfileType[];
	requiresRole?: Role;
	group?: NavGroup;
};

const admin = (
	to: string,
	labelKey: string,
	icon: LucideIcon,
	group: NavGroup,
): NavItem => ({ to, labelKey, icon, group, requiresRole: "admin" });

export const NAV_ITEMS: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
	admin("/people/admins", "nav.admins", ShieldCheck, "people"),
	admin("/catalogue/courses", "nav.courses", BookOpen, "catalogue"),
	admin("/catalogue/packages", "nav.packages", Package, "catalogue"),
	admin("/website", "nav.website", Globe, "settings"),
	admin("/settings/academy", "nav.academy", Settings, "settings"),
	{ to: "/account", labelKey: "auth.account", icon: User },
];

export function visibleNavItems(
	items: NavItem[],
	profiles: readonly ProfileType[],
	role?: Role,
): NavItem[] {
	return items.filter((i) => {
		if (i.requiresRole) return i.requiresRole === role;
		if (i.requires) return profiles.includes(i.requires);
		if (i.requiresAny) return i.requiresAny.some((r) => profiles.includes(r));
		return true;
	});
}

export function groupNavItems(
	items: NavItem[],
): { group?: NavGroup; items: NavItem[] }[] {
	const groups: { group?: NavGroup; items: NavItem[] }[] = [];
	for (const item of items) {
		const last = groups.at(-1);
		if (last && last.group === item.group && item.group !== undefined) {
			last.items.push(item);
		} else {
			groups.push({ group: item.group, items: [item] });
		}
	}
	return groups;
}
```

`src/features/shell/AppSidebar.tsx` (the long `className` on `Link` is copied unchanged from the current file as `LINK_CLASSES`):

```tsx
import { Link } from "@tanstack/react-router";
import { Fragment } from "react";
import { useTranslation } from "react-i18next";
import { groupNavItems, type NavItem } from "./nav";

const LINK_CLASSES =
	"relative flex min-h-11 items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground aria-[current=page]:bg-[color-mix(in_oklab,var(--color-accent)_14%,var(--color-card))] aria-[current=page]:font-semibold aria-[current=page]:text-foreground aria-[current=page]:before:absolute aria-[current=page]:before:inset-y-1.5 aria-[current=page]:before:start-0 aria-[current=page]:before:w-1 aria-[current=page]:before:rounded-full aria-[current=page]:before:bg-accent aria-[current=page]:before:content-['']";

export function AppSidebar({
	items,
	onNavigate,
}: {
	items: NavItem[];
	onNavigate?: () => void;
}) {
	const { t } = useTranslation();
	return (
		<nav aria-label={t("nav.primary")} className="flex flex-col gap-1 p-3">
			{groupNavItems(items).map((group, index) => (
				<Fragment key={group.group ?? `ungrouped-${index}`}>
					{group.group ? (
						<p className="px-3 pt-4 pb-1 text-xs font-semibold text-muted-foreground">
							{t(`nav.group.${group.group}`)}
						</p>
					) : null}
					{group.items.map((item) => {
						const Icon = item.icon;
						return (
							<Link
								key={item.to}
								to={item.to}
								activeOptions={{ exact: item.to === "/" }}
								activeProps={{ "aria-current": "page" }}
								onClick={onNavigate}
								className={LINK_CLASSES}
							>
								<Icon className="size-4 shrink-0" />
								{t(item.labelKey)}
							</Link>
						);
					})}
				</Fragment>
			))}
		</nav>
	);
}
```

`src/routes/_authed/index.tsx`: delete the `spotlight` block and its `Card` markup, and the `isParent`/`isStudent` variables. `DESCRIPTION_KEY` becomes `{ "/account": "home.accountDesc" }`, and the tiles are `visibleNavItems(NAV_ITEMS, me.profiles, me.role).filter((item) => item.to !== "/")`.

`src/routes/login.tsx`: replace the `<Link to="/register">…</Link>` paragraph with `<p className="pt-4 text-sm text-muted-foreground">{t("auth.newToEtqan")}</p>`.

`src/features/identity/components/ProfileEditForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { timezoneOptions } from "@/lib/timezones";
import {
	Alert,
	AlertDescription,
	Field,
	Input,
	Select,
	SubmitButton,
	toast,
} from "@/ui";
import { parseApiError } from "../api";
import { useUpdateMe } from "../queries";
import { type Me, type ProfileEditInput, profileEditSchema } from "../schemas";

export function ProfileEditForm({ me }: { me: Me }) {
	const { t, i18n } = useTranslation();
	const update = useUpdateMe();
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<ProfileEditInput>({
		resolver: zodResolver(profileEditSchema),
		defaultValues: {
			full_name: me.full_name,
			phone: me.phone ?? "",
			preferred_language:
				me.preferred_language ?? (i18n.language === "ar" ? "ar" : "en"),
			timezone: me.timezone ?? "UTC",
		},
	});

	async function onSubmit(values: ProfileEditInput) {
		try {
			const saved = await update.mutateAsync(values);
			const language = saved.preferred_language ?? values.preferred_language;
			if (i18n.language !== language) await i18n.changeLanguage(language);
			toast({ description: t("auth.saved"), variant: "success" });
		} catch (error) {
			const parsed = parseApiError(error);
			for (const [field, message] of Object.entries(parsed.fieldErrors)) {
				setError(field as keyof ProfileEditInput, { message });
			}
			if (parsed.message) setError("root.server", { message: parsed.message });
		}
	}

	return (
		<form
			onSubmit={handleSubmit(onSubmit)}
			className="flex flex-col gap-4"
			noValidate
		>
			<Field id="full_name" label={t("auth.fullName")} error={errors.full_name?.message}>
				<Input autoComplete="name" {...register("full_name")} />
			</Field>
			<Field id="phone" label={t("account.phone")} error={errors.phone?.message}>
				<Input type="tel" dir="ltr" autoComplete="tel" {...register("phone")} />
			</Field>
			<Field
				id="preferred_language"
				label={t("account.preferredLanguage")}
				error={errors.preferred_language?.message}
			>
				<Select {...register("preferred_language")}>
					<option value="ar">العربية</option>
					<option value="en">English</option>
				</Select>
			</Field>
			<Field id="timezone" label={t("account.timezone")} error={errors.timezone?.message}>
				<Select dir="ltr" {...register("timezone")}>
					{timezoneOptions(me.timezone).map((zone) => (
						<option key={zone} value={zone}>
							{zone}
						</option>
					))}
				</Select>
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{errors.root.server.message}</AlertDescription>
				</Alert>
			) : null}
			<SubmitButton pending={isSubmitting}>{t("auth.save")}</SubmitButton>
		</form>
	);
}
```

`src/features/identity/components/MyProfileCard.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Card, CardContent, CardHeader, CardTitle } from "@/ui";
import type { Me } from "../schemas";

const FIELDS: Record<string, readonly string[]> = {
	student: ["status", "gender", "date_of_birth", "country"],
	teacher: ["gender", "default_meeting_url", "pay_currency"],
	parent: ["has_whatsapp"],
};

function useDisplay() {
	const { t, i18n } = useTranslation();
	const regions = new Intl.DisplayNames([i18n.language], { type: "region" });
	return (field: string, value: unknown): string => {
		if (value === "" || value === null || value === undefined) return "—";
		if (typeof value === "boolean") return t(value ? "people.yes" : "people.no");
		if (field === "status") return t(`people.status.${value}`);
		if (field === "gender") return t(`people.gender.${value}`);
		if (field === "country") return regions.of(String(value)) ?? String(value);
		return String(value);
	};
}

/** The signed-in user's own role profile, read-only (non-admins see only this). */
export function MyProfileCard({ me }: { me: Me }) {
	const { t } = useTranslation();
	const display = useDisplay();
	const fields = FIELDS[me.role];
	if (!fields) return null;
	const profile = me.profile ?? {};
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("account.myProfile")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
					{fields.map((field) => (
						<div key={field} className="contents">
							<dt className="text-muted-foreground">{t(`people.field.${field}`)}</dt>
							<dd>{display(field, profile[field])}</dd>
						</div>
					))}
				</dl>
				{me.children && me.children.length > 0 ? (
					<div className="flex flex-col gap-2">
						<h3 className="text-sm font-semibold">{t("account.children")}</h3>
						<ul className="flex flex-col gap-1 text-sm">
							{me.children.map((child) => (
								<li key={child.id} className="flex justify-between gap-4">
									<span>{child.full_name}</span>
									<span className="text-muted-foreground">
										{display("status", child.profile?.status)}
									</span>
								</li>
							))}
						</ul>
					</div>
				) : null}
			</CardContent>
		</Card>
	);
}
```

`src/routes/_authed/account.tsx`: remove the `StudentPreferencesCard`/`TeacherGenderCard` imports and usage along with `isStudent`/`isTeacher`, and render `<MyProfileCard me={me} />` after `<ChangePasswordCard />`.

Locales: delete the `family`, `prefs`, `teacherProfile` blocks, `home.familyTitle`/`familyDesc`/`goToFamily`, `nav.family`, and `auth` keys used only by registration (`birthdate`, `createAccount`, `registerSubtitle`, `accountType`, `register`, `haveAccount`). Confirm with `grep -rn "family\.\|prefs\.\|teacherProfile\." src` (expect no matches). Then add these keys (merge into the existing objects).

`en/common.json`:

```json
{
	"nav": {
		"students": "Students",
		"parents": "Parents",
		"teachers": "Teachers",
		"admins": "Admins",
		"courses": "Courses",
		"packages": "Packages",
		"academy": "Academy",
		"group": { "people": "People", "catalogue": "Catalogue", "settings": "Settings" }
	},
	"account": {
		"phone": "Phone",
		"preferredLanguage": "Preferred language",
		"timezone": "Time zone",
		"myProfile": "My profile",
		"children": "My children"
	},
	"people": {
		"yes": "Yes",
		"no": "No",
		"field": {
			"status": "Status",
			"gender": "Gender",
			"date_of_birth": "Date of birth",
			"country": "Country",
			"notes": "Notes",
			"bio": "Bio",
			"default_meeting_url": "Default meeting link",
			"pay_currency": "Pay currency",
			"payout_method": "Payout method",
			"payout_details": "Payout details",
			"has_whatsapp": "Has WhatsApp",
			"courses": "Courses taught"
		},
		"status": {
			"active": "Active",
			"trial": "Trial",
			"in_progress": "In progress",
			"paused": "Paused",
			"inactive": "Inactive"
		},
		"gender": { "male": "Male", "female": "Female" }
	}
}
```

`ar/common.json`:

```json
{
	"nav": {
		"students": "الطلاب",
		"parents": "أولياء الأمور",
		"teachers": "المعلمون",
		"admins": "المشرفون",
		"courses": "الدورات",
		"packages": "الباقات",
		"academy": "الأكاديمية",
		"group": { "people": "الأشخاص", "catalogue": "الكتالوج", "settings": "الإعدادات" }
	},
	"account": {
		"phone": "الهاتف",
		"preferredLanguage": "اللغة المفضلة",
		"timezone": "المنطقة الزمنية",
		"myProfile": "ملفي",
		"children": "أبنائي"
	},
	"people": {
		"yes": "نعم",
		"no": "لا",
		"field": {
			"status": "الحالة",
			"gender": "الجنس",
			"date_of_birth": "تاريخ الميلاد",
			"country": "الدولة",
			"notes": "ملاحظات",
			"bio": "نبذة",
			"default_meeting_url": "رابط الاجتماع الافتراضي",
			"pay_currency": "عملة الأجر",
			"payout_method": "طريقة الدفع",
			"payout_details": "تفاصيل الدفع",
			"has_whatsapp": "لديه واتساب",
			"courses": "الدورات التي يدرّسها"
		},
		"status": {
			"active": "نشط",
			"trial": "تجريبي",
			"in_progress": "قيد التقدم",
			"paused": "متوقف مؤقتًا",
			"inactive": "غير نشط"
		},
		"gender": { "male": "ذكر", "female": "أنثى" }
	}
}
```

- [ ] **Step 5: Verify**

Run: `npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage`
Expected: all pass; floors hold. The route tree no longer has `/register` or `/family`, and the grouped nav links point to routes that do not exist yet. Links to unknown paths are allowed by `to: string` and resolve in Tasks 12–14.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard)!: retire self-registration and family screens; grouped admin nav; my account language and phone

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 12: Dashboard — people data layer, shared people UI, Students screens

**Files:**
- Create: `dashboard/src/features/academy/{api.ts,queries.ts,index.ts}`, `dashboard/src/features/people/{schemas.ts,api.ts,queries.ts,form-errors.ts,UserFieldsSection.tsx,AccountActions.tsx,PeopleList.tsx,StudentsList.tsx,StudentForm.tsx,GuardiansPanel.tsx,index.ts}` + tests `{api.test.ts,AccountActions.test.tsx,StudentsList.test.tsx,StudentForm.test.tsx,GuardiansPanel.test.tsx}`, `dashboard/src/lib/countries.ts`, `dashboard/src/lib/countries.test.ts`, `dashboard/src/test/render.tsx`
- Create routes: `dashboard/src/routes/_authed/people.tsx`, `people.students.index.tsx`, `people.students.$personId.tsx`
- Modify: `dashboard/src/locales/{en,ar}/common.json`

**Interfaces:**
- Consumes: `/api/v1/people/…` (Tasks 7–8), `/api/v1/academy/settings/` (Task 2), `parseApiError` (Task 11), `requireAdmin` (Task 11), `Textarea` (Task 11), `timezoneOptions` (Task 11).
- Produces:
  - `academyApi.get() -> Promise<AcademySettings>`, `academyApi.update(body)`; `useAcademySettings()`, `useUpdateAcademySettings()`; `academySettingsKey = ["academy", "settings"]`; `type AcademySettings = { timezone: string; default_currency: string; default_language: Language; updated_at?: string }`.
  - `people/schemas.ts`: `Kind`, `AccountState`, `PersonAction`, `BulkAction`, `STUDENT_STATUSES`, `GENDERS`, `PAYOUT_METHODS`, `PersonUser`, `PersonSummary`, `StudentProfile`, `TeacherProfile`, `ParentProfile`, `Person<P>`, `Paginated<T>`, `userFieldsSchema`/`UserFields`, `studentFormSchema`/`StudentFormValues`, `parentFormSchema`/`ParentFormValues`, `teacherFormSchema`/`TeacherFormValues`, `adminFormSchema`/`AdminFormValues`, `emptyUser(academy?) -> UserFields`, `userDefaults(user: PersonUser) -> UserFields`, `toUserPayload(user: UserFields) -> Record<string, unknown>`.
  - `people/api.ts`: `peopleApi.{list, get, create, update, action, guardians, linkGuardian, unlinkGuardian, bulkStudents}`, `csvUrl(kind, params) -> string`, `type ListParams`, `type PersonBody`.
  - `people/queries.ts`: `peopleKey(kind)`, `usePeople<P>(kind, params, {enabled}?)`, `usePerson<P>(kind, id?)`, `useSavePerson<P>(kind, id?)`, `usePersonAction(kind)`, `guardiansKey(id)`, `useGuardians(id)`, `useLinkGuardian(id)`, `useUnlinkGuardian(id)`, `useBulkStudents()`.
  - `applyServerErrors(error, setError) -> ParsedApiError`.
  - Components: `<UserFieldsSection emailHint?>` (inside a `FormProvider`), `<AccountStateChip state>`, `<AccountActions kind person compact?>`, `<PeopleList kind columns params onParamsChange filters? selection? actions? detailTo? emptyLabel>`, `<StudentsList>`, `<StudentForm personId>` (`"new"` creates), `<GuardiansPanel studentId>`.
  - `countryOptions(language) -> { code: string; name: string }[]` (ISO 3166-1 alpha-2, localised names).
  - Test helper `renderWithRouter(ui, { path?, initial?, extraPaths? })` in `src/test/render.tsx`.
  - Routes `/people/students` and `/people/students/$personId`, both behind `requireAdmin`.

- [ ] **Step 1: Write the failing tests**

`src/test/render.tsx` (helper, excluded from coverage):

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render } from "@testing-library/react";
import type { ReactNode } from "react";
import { Toaster } from "@/ui";

export function renderWithRouter(
	ui: ReactNode,
	{
		path = "/",
		initial = "/",
		extraPaths = [],
	}: { path?: string; initial?: string; extraPaths?: string[] } = {},
) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	const rootRoute = createRootRoute();
	const main = createRoute({
		getParentRoute: () => rootRoute,
		path,
		component: () => <>{ui}</>,
	});
	const others = extraPaths.map((p) =>
		createRoute({
			getParentRoute: () => rootRoute,
			path: p,
			component: () => <p>{`at ${p}`}</p>,
		}),
	);
	const router = createRouter({
		routeTree: rootRoute.addChildren([main, ...others]),
		history: createMemoryHistory({ initialEntries: [initial] }),
	});
	const view = render(
		<QueryClientProvider client={client}>
			<RouterProvider router={router} />
			<Toaster />
		</QueryClientProvider>,
	);
	return { client, router, ...view };
}
```

`src/lib/countries.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { countryOptions } from "./countries";

describe("countryOptions", () => {
	it("lists ISO codes with names in the reader's language", () => {
		const en = countryOptions("en");
		expect(en.length).toBeGreaterThan(240);
		expect(en.find((c) => c.code === "EG")?.name).toBe("Egypt");
		expect(countryOptions("ar").find((c) => c.code === "EG")?.name).toBe("مصر");
	});
});
```

`src/features/people/api.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { csvUrl } from "./api";
import { toUserPayload } from "./schemas";

describe("csvUrl", () => {
	it("keeps filters, drops paging and empty values, asks for CSV", () => {
		const url = csvUrl("students", { status: "paused", q: "", page: 3, page_size: 25 });
		expect(url).toBe("/api/v1/people/students/?status=paused&format=csv");
	});
});

describe("toUserPayload", () => {
	it("sends an empty email as null so the student has no login", () => {
		expect(
			toUserPayload({
				full_name: " Aisha ",
				email: "",
				phone: "",
				preferred_language: "ar",
				timezone: "UTC",
			}),
		).toEqual({
			full_name: "Aisha",
			email: null,
			phone: "",
			preferred_language: "ar",
			timezone: "UTC",
		});
	});
});
```

`src/features/people/AccountActions.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { AccountActions } from "./AccountActions";
import { peopleApi } from "./api";
import type { Person, PersonUser } from "./schemas";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, action: vi.fn() } };
});

const user: PersonUser = {
	full_name: "Yusuf",
	email: "y@x.test",
	phone: "",
	preferred_language: "en",
	timezone: "UTC",
	is_active: true,
	account_state: "invited",
	pending_email: "",
};
const person = (over: Partial<PersonUser>, extra: Partial<Person<unknown>> = {}) =>
	({ id: 7, role: "student", user: { ...user, ...over }, profile: {}, ...extra }) as Person<unknown>;

describe("AccountActions", () => {
	beforeEach(() => vi.clearAllMocks());

	it("offers a fresh invite while the invite is pending", async () => {
		vi.mocked(peopleApi.action).mockResolvedValue(person({}));
		renderWithRouter(<AccountActions kind="students" person={person({})} />);
		expect(await screen.findByText("Invite pending")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Send invite" }));
		await waitFor(() =>
			expect(peopleApi.action).toHaveBeenCalledWith("students", 7, "invite"),
		);
		expect(await screen.findByText("Invite sent.")).toBeInTheDocument();
	});

	it("offers a password reset to an active account", async () => {
		renderWithRouter(
			<AccountActions kind="students" person={person({ account_state: "active" })} />,
		);
		expect(
			await screen.findByRole("button", { name: "Send password reset" }),
		).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Send invite" })).toBeNull();
	});

	it("says 'No login' for a student without email", async () => {
		renderWithRouter(
			<AccountActions
				kind="students"
				person={person({ email: null, account_state: "no_login" })}
			/>,
		);
		expect(await screen.findByText("No login")).toBeInTheDocument();
	});

	it("disables deactivation of yourself and says why", async () => {
		renderWithRouter(
			<AccountActions
				kind="admins"
				person={person({ account_state: "active" }, { role: "admin", deactivation_blocked: "self" })}
			/>,
		);
		expect(await screen.findByRole("button", { name: "Deactivate" })).toBeDisabled();
		expect(screen.getByText("You can't deactivate your own account.")).toBeInTheDocument();
	});

	it("shows the server's refusal", async () => {
		vi.mocked(peopleApi.action).mockRejectedValue(
			Object.assign(new Error("400"), {
				isAxiosError: true,
				response: { status: 400, data: { detail: "An academy needs at least one active admin." } },
			}),
		);
		renderWithRouter(
			<AccountActions kind="admins" person={person({ account_state: "active" }, { role: "admin", deactivation_blocked: null })} />,
		);
		await userEvent.click(await screen.findByRole("button", { name: "Deactivate" }));
		expect(
			await screen.findByText("An academy needs at least one active admin."),
		).toBeInTheDocument();
	});

	it("reactivates an inactive account", async () => {
		vi.mocked(peopleApi.action).mockResolvedValue(person({}));
		renderWithRouter(
			<AccountActions kind="students" person={person({ is_active: false, account_state: "inactive" })} />,
		);
		await userEvent.click(await screen.findByRole("button", { name: "Activate" }));
		await waitFor(() =>
			expect(peopleApi.action).toHaveBeenCalledWith("students", 7, "activate"),
		);
	});
});
```

`src/features/people/StudentsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import type { Person, StudentProfile } from "./schemas";
import { StudentsList } from "./StudentsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: { ...actual.peopleApi, list: vi.fn(), bulkStudents: vi.fn() },
	};
});

const row = (id: number, name: string, email: string | null): Person<StudentProfile> => ({
	id,
	role: "student",
	user: {
		full_name: name,
		email,
		phone: "",
		preferred_language: "ar",
		timezone: "UTC",
		is_active: true,
		account_state: email ? "invited" : "no_login",
		pending_email: "",
	},
	profile: { date_of_birth: null, gender: "", country: "EG", status: "trial", notes: "" },
});

const page = (results: Person<StudentProfile>[]) => ({
	count: results.length,
	next: null,
	previous: null,
	results,
});

function lastParams() {
	return vi.mocked(peopleApi.list).mock.calls.at(-1)?.[1];
}

describe("StudentsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([row(1, "Yusuf", "y@x.test"), row(2, "Aisha", null)]),
		);
	});

	it("lists students with their account state", async () => {
		renderWithRouter(<StudentsList />, { extraPaths: ["/people/students/$personId"] });
		expect(await screen.findByRole("link", { name: "Yusuf" })).toBeInTheDocument();
		expect(screen.getByText("No login")).toBeInTheDocument();
	});

	it("filters by status tab and searches", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByRole("tab", { name: "Paused" }));
		await waitFor(() => expect(lastParams()).toMatchObject({ status: "paused", page: 1 }));
		await user.type(screen.getByRole("searchbox"), "yu");
		await waitFor(() => expect(lastParams()).toMatchObject({ q: "yu", status: "paused" }));
		const csv = screen.getByRole("link", { name: "Export CSV" });
		expect(csv.getAttribute("href")).toContain("status=paused");
		expect(csv.getAttribute("href")).toContain("format=csv");
	});

	it("applies a bulk status change to the selected rows", async () => {
		vi.mocked(peopleApi.bulkStudents).mockResolvedValue({ updated: 2 });
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Yusuf"));
		await user.click(screen.getByLabelText("Select Aisha"));
		const bar = screen.getByRole("region", { name: "2 selected" });
		await user.selectOptions(within(bar).getByLabelText("New status"), "paused");
		await user.click(within(bar).getByRole("button", { name: "Set status" }));
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenCalledWith({
				ids: [1, 2],
				action: "set_status",
				status: "paused",
			}),
		);
	});

	it("shows an empty state", async () => {
		vi.mocked(peopleApi.list).mockResolvedValue(page([]));
		renderWithRouter(<StudentsList />);
		expect(await screen.findByText("No students yet.")).toBeInTheDocument();
	});
});
```

`src/features/people/StudentForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import type { Person, StudentProfile } from "./schemas";
import { StudentForm } from "./StudentForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			get: vi.fn(),
			create: vi.fn(),
			update: vi.fn(),
			guardians: vi.fn(),
			list: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({
	academyApi: { get: vi.fn(), update: vi.fn() },
}));

const saved: Person<StudentProfile> = {
	id: 5,
	role: "student",
	user: {
		full_name: "Aisha",
		email: null,
		phone: "",
		preferred_language: "ar",
		timezone: "Africa/Cairo",
		is_active: true,
		account_state: "no_login",
		pending_email: "",
	},
	profile: { date_of_birth: null, gender: "", country: "", status: "active", notes: "" },
};

describe("StudentForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
		});
		vi.mocked(peopleApi.guardians).mockResolvedValue([]);
	});

	it("creates a student without email and opens the new record", async () => {
		vi.mocked(peopleApi.create).mockResolvedValue(saved);
		const user = userEvent.setup();
		renderWithRouter(<StudentForm personId="new" />, {
			extraPaths: ["/people/students/$personId"],
		});
		await user.type(await screen.findByLabelText(/full name/i), "Aisha");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(peopleApi.create).toHaveBeenCalled());
		const [kind, body] = vi.mocked(peopleApi.create).mock.calls[0] ?? [];
		expect(kind).toBe("students");
		expect(body).toMatchObject({
			user: { full_name: "Aisha", email: null, preferred_language: "ar", timezone: "Africa/Cairo" },
			profile: { status: "active", date_of_birth: null },
		});
		expect(await screen.findByText("at /people/students/$personId")).toBeInTheDocument();
	});

	it("shows a nested server error under the email field", async () => {
		vi.mocked(peopleApi.create).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { user: { email: ["This email is already in use."] } },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<StudentForm personId="new" />);
		await user.type(await screen.findByLabelText(/full name/i), "Aisha");
		await user.type(screen.getByLabelText(/^email/i), "dup@x.test");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("This email is already in use.")).toBeInTheDocument();
	});

	it("edits an existing student and shows account and guardians", async () => {
		vi.mocked(peopleApi.get).mockResolvedValue(saved);
		vi.mocked(peopleApi.update).mockResolvedValue(saved);
		const user = userEvent.setup();
		renderWithRouter(<StudentForm personId="5" />);
		expect(await screen.findByDisplayValue("Aisha")).toBeInTheDocument();
		expect(screen.getByText("No login")).toBeInTheDocument();
		expect(screen.getByText("Guardians")).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Status"), "paused");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(peopleApi.update).toHaveBeenCalledWith(
				"students",
				5,
				expect.objectContaining({ profile: expect.objectContaining({ status: "paused" }) }),
			),
		);
	});
});
```

`src/features/people/GuardiansPanel.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { GuardiansPanel } from "./GuardiansPanel";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			guardians: vi.fn(),
			linkGuardian: vi.fn(),
			unlinkGuardian: vi.fn(),
			list: vi.fn(),
			create: vi.fn(),
		},
	};
});

vi.mock("@/features/academy/api", () => ({
	academyApi: {
		get: vi.fn().mockResolvedValue({
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
		}),
	},
}));

const omar = { id: 3, full_name: "Omar", email: "o@x.test", phone: "" };

describe("GuardiansPanel", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.guardians).mockResolvedValue([omar]);
	});

	it("lists and unlinks guardians", async () => {
		vi.mocked(peopleApi.unlinkGuardian).mockResolvedValue(undefined);
		renderWithRouter(<GuardiansPanel studentId={9} />);
		expect(await screen.findByText("Omar")).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Unlink Omar" }));
		await waitFor(() => expect(peopleApi.unlinkGuardian).toHaveBeenCalledWith(9, 3));
	});

	it("finds an existing parent and links them", async () => {
		vi.mocked(peopleApi.guardians).mockResolvedValue([]);
		vi.mocked(peopleApi.list).mockResolvedValue({
			count: 1,
			next: null,
			previous: null,
			results: [
				{
					id: 4,
					role: "parent",
					user: { ...omar, full_name: "Huda", preferred_language: "ar", timezone: "UTC", is_active: true, account_state: "invited", pending_email: "" },
					profile: { has_whatsapp: false, notes: "", children: [] },
				},
			],
		});
		vi.mocked(peopleApi.linkGuardian).mockResolvedValue([]);
		const user = userEvent.setup();
		renderWithRouter(<GuardiansPanel studentId={9} />);
		await user.type(await screen.findByLabelText("Find a parent"), "hu");
		await user.click(await screen.findByRole("button", { name: "Link Huda" }));
		await waitFor(() => expect(peopleApi.linkGuardian).toHaveBeenCalledWith(9, 4));
	});

	it("creates a new parent and links them", async () => {
		vi.mocked(peopleApi.create).mockResolvedValue({
			id: 11,
			role: "parent",
			user: { ...omar, full_name: "Salma", preferred_language: "ar", timezone: "UTC", is_active: true, account_state: "invited", pending_email: "" },
			profile: { has_whatsapp: true, notes: "", children: [] },
		});
		vi.mocked(peopleApi.linkGuardian).mockResolvedValue([]);
		const user = userEvent.setup();
		renderWithRouter(<GuardiansPanel studentId={9} />);
		await user.click(await screen.findByRole("button", { name: "New parent" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/full name/i), "Salma");
		await user.click(within(dialog).getByLabelText("Has WhatsApp"));
		await user.click(within(dialog).getByRole("button", { name: "Create and link" }));
		await waitFor(() =>
			expect(peopleApi.create).toHaveBeenCalledWith(
				"parents",
				expect.objectContaining({ profile: { has_whatsapp: true, notes: "" } }),
			),
		);
		await waitFor(() => expect(peopleApi.linkGuardian).toHaveBeenCalledWith(9, 11));
	});
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx pnpm@10 vitest run src/features/people src/lib/countries.test.ts`
Expected: FAIL (modules not found).

- [ ] **Step 3: Implement**

`src/features/academy/api.ts`:

```ts
import type { Language } from "@/features/identity/schemas";
import { api } from "@/lib/api";

export interface AcademySettings {
	timezone: string;
	default_currency: string;
	default_language: Language;
	updated_at?: string;
}

export const academyApi = {
	get: async () => (await api.get<AcademySettings>("academy/settings/")).data,
	update: async (body: Partial<AcademySettings>) =>
		(await api.patch<AcademySettings>("academy/settings/", body)).data,
};
```

`src/features/academy/queries.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { type AcademySettings, academyApi } from "./api";

export const academySettingsKey = ["academy", "settings"] as const;

export function useAcademySettings() {
	return useQuery({
		queryKey: academySettingsKey,
		queryFn: academyApi.get,
		staleTime: 60_000,
	});
}

export function useUpdateAcademySettings() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: Partial<AcademySettings>) => academyApi.update(body),
		onSuccess: (data) => qc.setQueryData(academySettingsKey, data),
	});
}
```

`src/features/academy/index.ts`: `export * from "./api"; export * from "./queries";` (Task 14 adds the form export).

`src/lib/countries.ts`:

```ts
// ISO 3166-1 alpha-2. Names come from Intl in the reader's language.
const CODES =
	"AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW".split(
		" ",
	);

export function countryOptions(language: string): { code: string; name: string }[] {
	const names = new Intl.DisplayNames([language], { type: "region" });
	return CODES.map((code) => ({ code, name: names.of(code) ?? code })).sort(
		(a, b) => a.name.localeCompare(b.name, language),
	);
}
```

`src/features/people/schemas.ts`:

```ts
import { z } from "zod";
import type { AcademySettings } from "@/features/academy/api";
import { type Language, phoneSchema } from "@/features/identity/schemas";

export type Kind = "students" | "parents" | "teachers" | "admins";
export type AccountState = "no_login" | "invited" | "active" | "inactive";
export type PersonAction = "invite" | "password-reset" | "deactivate" | "activate";
export type BulkAction = "activate" | "deactivate" | "set_status";

export const STUDENT_STATUSES = [
	"active",
	"trial",
	"in_progress",
	"paused",
	"inactive",
] as const;
export type StudentStatus = (typeof STUDENT_STATUSES)[number];
export const GENDERS = ["male", "female"] as const;
export type Gender = (typeof GENDERS)[number];
export const PAYOUT_METHODS = [
	"vodafone_cash",
	"instapay",
	"bank_account",
	"mashreq_neo",
	"western_union",
	"wise",
	"paypal",
	"telda",
	"abu_dhabi_bank",
	"cash",
	"stc_pay",
] as const;
export type PayoutMethod = (typeof PAYOUT_METHODS)[number];

export interface PersonUser {
	full_name: string;
	email: string | null;
	phone: string;
	preferred_language: Language;
	timezone: string;
	is_active: boolean;
	account_state: AccountState;
	pending_email: string;
}
export interface PersonSummary {
	id: number;
	full_name: string;
	email: string | null;
	phone: string;
}
export interface StudentProfile {
	date_of_birth: string | null;
	gender: "" | Gender;
	country: string;
	status: StudentStatus;
	notes: string;
}
export interface TeacherProfile {
	gender: "" | Gender;
	date_of_birth: string | null;
	bio: string;
	default_meeting_url: string;
	pay_currency: string;
	payout_method: "" | PayoutMethod;
	payout_details: string;
	course_ids: number[];
}
export interface ParentProfile {
	has_whatsapp: boolean;
	notes: string;
	children: PersonSummary[];
}
export interface Person<P> {
	id: number;
	role: "admin" | "teacher" | "student" | "parent";
	user: PersonUser;
	profile: P;
	deactivation_blocked?: "self" | "last_admin" | null;
}
export interface Paginated<T> {
	count: number;
	next: string | null;
	previous: string | null;
	results: T[];
}

export const userFieldsSchema = z.object({
	full_name: z.string().trim().min(1, "Enter a name."),
	email: z.union([z.email(), z.literal("")]),
	phone: phoneSchema,
	preferred_language: z.enum(["ar", "en"]),
	timezone: z.string().min(1),
});
export type UserFields = z.infer<typeof userFieldsSchema>;

export const studentFormSchema = z.object({
	user: userFieldsSchema,
	profile: z.object({
		date_of_birth: z.string(),
		gender: z.enum(["", "male", "female"]),
		country: z.string(),
		status: z.enum(STUDENT_STATUSES),
		notes: z.string(),
	}),
});
export type StudentFormValues = z.infer<typeof studentFormSchema>;

export const parentFormSchema = z.object({
	user: userFieldsSchema,
	profile: z.object({ has_whatsapp: z.boolean(), notes: z.string() }),
});
export type ParentFormValues = z.infer<typeof parentFormSchema>;

export const teacherFormSchema = z.object({
	user: userFieldsSchema,
	profile: z
		.object({
			gender: z
				.enum(["", "male", "female"])
				.refine((g) => g !== "", "Choose male or female."),
			date_of_birth: z.string(),
			bio: z.string(),
			default_meeting_url: z.union([z.url(), z.literal("")]),
			pay_currency: z.string().regex(/^[A-Z]{3}$/),
			payout_method: z.union([z.literal(""), z.enum(PAYOUT_METHODS)]),
			payout_details: z.string(),
			course_ids: z.array(z.number()),
		})
		.refine((p) => !p.payout_method || p.payout_details.trim().length > 0, {
			path: ["payout_details"],
			message: "Enter the payout details for this method.",
		}),
});
export type TeacherFormValues = z.infer<typeof teacherFormSchema>;

export const adminFormSchema = z.object({ user: userFieldsSchema });
export type AdminFormValues = z.infer<typeof adminFormSchema>;

export function emptyUser(academy?: AcademySettings): UserFields {
	return {
		full_name: "",
		email: "",
		phone: "",
		preferred_language: academy?.default_language ?? "ar",
		timezone: academy?.timezone ?? "UTC",
	};
}

export function userDefaults(user: PersonUser): UserFields {
	return {
		full_name: user.full_name,
		email: user.email ?? "",
		phone: user.phone,
		preferred_language: user.preferred_language,
		timezone: user.timezone,
	};
}

export function toUserPayload(user: UserFields): Record<string, unknown> {
	return {
		full_name: user.full_name.trim(),
		email: user.email.trim() || null,
		phone: user.phone.trim(),
		preferred_language: user.preferred_language,
		timezone: user.timezone,
	};
}
```

`src/features/people/api.ts`:

```ts
import { api } from "@/lib/api";
import type {
	BulkAction,
	Kind,
	Paginated,
	Person,
	PersonAction,
	PersonSummary,
	StudentStatus,
} from "./schemas";

export type ListParams = Record<string, string | number | undefined>;
export interface PersonBody {
	user?: Record<string, unknown>;
	profile?: Record<string, unknown>;
}

function clean(params: ListParams): Record<string, string> {
	const out: Record<string, string> = {};
	for (const [key, value] of Object.entries(params)) {
		if (value !== undefined && value !== "") out[key] = String(value);
	}
	return out;
}

export const peopleApi = {
	list: async <P>(kind: Kind, params: ListParams) =>
		(await api.get<Paginated<Person<P>>>(`people/${kind}/`, { params: clean(params) }))
			.data,
	get: async <P>(kind: Kind, id: number) =>
		(await api.get<Person<P>>(`people/${kind}/${id}/`)).data,
	create: async <P>(kind: Kind, body: PersonBody) =>
		(await api.post<Person<P>>(`people/${kind}/`, body)).data,
	update: async <P>(kind: Kind, id: number, body: PersonBody) =>
		(await api.patch<Person<P>>(`people/${kind}/${id}/`, body)).data,
	action: async (kind: Kind, id: number, action: PersonAction) =>
		(await api.post<Person<unknown>>(`people/${kind}/${id}/${action}/`)).data,
	guardians: async (studentId: number) =>
		(await api.get<PersonSummary[]>(`people/students/${studentId}/guardians/`)).data,
	linkGuardian: async (studentId: number, parentId: number) =>
		(
			await api.post<PersonSummary[]>(`people/students/${studentId}/guardians/`, {
				parent_id: parentId,
			})
		).data,
	unlinkGuardian: async (studentId: number, parentId: number) => {
		await api.delete(`people/students/${studentId}/guardians/${parentId}/`);
	},
	bulkStudents: async (body: {
		ids: number[];
		action: BulkAction;
		status?: StudentStatus;
	}) => (await api.post<{ updated: number }>("people/students/bulk/", body)).data,
};

/** Same filters as the list, every row (no paging), as CSV (spec §5). */
export function csvUrl(kind: Kind, params: ListParams): string {
	const filters = Object.fromEntries(
		Object.entries(params).filter(([key]) => key !== "page" && key !== "page_size"),
	);
	const query = new URLSearchParams({ ...clean(filters), format: "csv" });
	return `${api.defaults.baseURL ?? "/api/v1/"}people/${kind}/?${query.toString()}`;
}
```

`src/features/people/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { type ListParams, type PersonBody, peopleApi } from "./api";
import type { BulkAction, Kind, PersonAction, StudentStatus } from "./schemas";

export const peopleKey = (kind: Kind) => ["people", kind] as const;
export const guardiansKey = (studentId: number) =>
	["people", "students", "guardians", studentId] as const;

export function usePeople<P>(
	kind: Kind,
	params: ListParams,
	options: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...peopleKey(kind), "list", params],
		queryFn: () => peopleApi.list<P>(kind, params),
		placeholderData: keepPreviousData,
		enabled: options.enabled ?? true,
	});
}

export function usePerson<P>(kind: Kind, id: number | undefined) {
	return useQuery({
		queryKey: [...peopleKey(kind), "detail", id],
		queryFn: () => peopleApi.get<P>(kind, id as number),
		enabled: id !== undefined,
	});
}

export function useSavePerson<P>(kind: Kind, id?: number) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: PersonBody) =>
			id === undefined
				? peopleApi.create<P>(kind, body)
				: peopleApi.update<P>(kind, id, body),
		onSuccess: () => qc.invalidateQueries({ queryKey: peopleKey(kind) }),
	});
}

export function usePersonAction(kind: Kind) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: ({ id, action }: { id: number; action: PersonAction }) =>
			peopleApi.action(kind, id, action),
		onSuccess: () => qc.invalidateQueries({ queryKey: peopleKey(kind) }),
	});
}

export function useGuardians(studentId: number) {
	return useQuery({
		queryKey: guardiansKey(studentId),
		queryFn: () => peopleApi.guardians(studentId),
	});
}

export function useLinkGuardian(studentId: number) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (parentId: number) => peopleApi.linkGuardian(studentId, parentId),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: guardiansKey(studentId) });
			qc.invalidateQueries({ queryKey: peopleKey("parents") });
		},
	});
}

export function useUnlinkGuardian(studentId: number) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (parentId: number) => peopleApi.unlinkGuardian(studentId, parentId),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: guardiansKey(studentId) });
			qc.invalidateQueries({ queryKey: peopleKey("parents") });
		},
	});
}

export function useBulkStudents() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: { ids: number[]; action: BulkAction; status?: StudentStatus }) =>
			peopleApi.bulkStudents(body),
		onSuccess: () => qc.invalidateQueries({ queryKey: peopleKey("students") }),
	});
}
```

`src/features/people/form-errors.ts`:

```ts
import type { FieldValues, Path, UseFormSetError } from "react-hook-form";
import { type ParsedApiError, parseApiError } from "@/features/identity/api";

/** Put nested DRF errors (`user.email`, `profile.gender`) on their fields. */
export function applyServerErrors<T extends FieldValues>(
	error: unknown,
	setError: UseFormSetError<T>,
): ParsedApiError {
	const parsed = parseApiError(error);
	for (const [field, message] of Object.entries(parsed.fieldErrors)) {
		setError(field as Path<T>, { message });
	}
	if (parsed.message) setError("root.server", { message: parsed.message });
	return parsed;
}
```

`src/features/people/UserFieldsSection.tsx`:

```tsx
import { useFormContext } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { timezoneOptions } from "@/lib/timezones";
import { Field, Input, Select } from "@/ui";
import type { UserFields } from "./schemas";

/** Name, email, phone, language and time zone. Use inside a `FormProvider`. */
export function UserFieldsSection({ emailHint }: { emailHint?: string }) {
	const { t } = useTranslation();
	const {
		register,
		watch,
		formState: { errors },
	} = useFormContext<{ user: UserFields }>();
	const e = errors.user;
	return (
		<fieldset className="grid gap-4 sm:grid-cols-2">
			<legend className="sr-only">{t("people.contact")}</legend>
			<Field id="user.full_name" label={t("auth.fullName")} error={e?.full_name?.message} required>
				<Input autoComplete="off" {...register("user.full_name")} />
			</Field>
			<Field id="user.email" label={t("auth.email")} error={e?.email?.message}>
				<Input type="email" dir="ltr" autoComplete="off" {...register("user.email")} />
			</Field>
			<Field id="user.phone" label={t("account.phone")} error={e?.phone?.message}>
				<Input type="tel" dir="ltr" {...register("user.phone")} />
			</Field>
			<Field
				id="user.preferred_language"
				label={t("account.preferredLanguage")}
				error={e?.preferred_language?.message}
			>
				<Select {...register("user.preferred_language")}>
					<option value="ar">العربية</option>
					<option value="en">English</option>
				</Select>
			</Field>
			<Field id="user.timezone" label={t("account.timezone")} error={e?.timezone?.message}>
				<Select dir="ltr" {...register("user.timezone")}>
					{timezoneOptions(watch("user.timezone")).map((zone) => (
						<option key={zone} value={zone}>
							{zone}
						</option>
					))}
				</Select>
			</Field>
			{emailHint ? (
				<p className="text-sm text-muted-foreground sm:col-span-2">{emailHint}</p>
			) : null}
		</fieldset>
	);
}
```

`src/features/people/AccountActions.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { parseApiError } from "@/features/identity/api";
import { cn } from "@/lib/cn";
import { Button, StatusChip, toast } from "@/ui";
import { usePersonAction } from "./queries";
import type { AccountState, Kind, Person, PersonAction } from "./schemas";

const TONE: Record<AccountState, "live" | "neutral" | "warning"> = {
	active: "live",
	invited: "neutral",
	no_login: "neutral",
	inactive: "warning",
};

export function AccountStateChip({ state }: { state: AccountState }) {
	const { t } = useTranslation();
	return <StatusChip tone={TONE[state]}>{t(`people.account.${state}`)}</StatusChip>;
}

export function AccountActions({
	kind,
	person,
	compact = false,
}: {
	kind: Kind;
	person: Person<unknown>;
	compact?: boolean;
}) {
	const { t } = useTranslation();
	const run = usePersonAction(kind);
	const state = person.user.account_state;
	const blocked = person.deactivation_blocked ?? null;
	const reasonId = `deactivate-reason-${person.id}`;

	function act(action: PersonAction, doneKey: string) {
		run.mutate(
			{ id: person.id, action },
			{
				onSuccess: () => toast({ description: t(doneKey), variant: "success" }),
				onError: (error) => {
					const parsed = parseApiError(error);
					toast({
						description:
							parsed.message ??
							Object.values(parsed.fieldErrors)[0] ??
							t("people.genericError"),
						variant: "destructive",
					});
				},
			},
		);
	}

	return (
		<section
			aria-label={t("people.account.title")}
			className={cn(
				"flex flex-col gap-3",
				!compact && "rounded-lg border border-border p-4",
			)}
		>
			<div className="flex flex-wrap items-center gap-2">
				{compact ? null : (
					<h2 className="me-auto font-semibold">{t("people.account.title")}</h2>
				)}
				<AccountStateChip state={state} />
			</div>
			{person.user.pending_email ? (
				<p className="text-sm text-muted-foreground">
					{t("people.account.pendingEmail", { email: person.user.pending_email })}
				</p>
			) : null}
			<div className="flex flex-wrap gap-2">
				{state === "invited" ? (
					<Button size="sm" variant="outline" disabled={run.isPending} onClick={() => act("invite", "people.account.inviteSent")}>
						{t("people.account.sendInvite")}
					</Button>
				) : null}
				{state === "active" ? (
					<Button size="sm" variant="outline" disabled={run.isPending} onClick={() => act("password-reset", "people.account.resetSent")}>
						{t("people.account.sendReset")}
					</Button>
				) : null}
				{person.user.is_active ? (
					<Button
						size="sm"
						variant="destructive"
						disabled={run.isPending || blocked !== null}
						aria-describedby={blocked ? reasonId : undefined}
						onClick={() => act("deactivate", "people.account.deactivated")}
					>
						{t("people.account.deactivate")}
					</Button>
				) : (
					<Button size="sm" disabled={run.isPending} onClick={() => act("activate", "people.account.activated")}>
						{t("people.account.activate")}
					</Button>
				)}
			</div>
			{blocked ? (
				<p id={reasonId} className="text-sm text-muted-foreground">
					{t(`people.account.blocked.${blocked}`)}
				</p>
			) : null}
		</section>
	);
}
```

`src/features/people/PeopleList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Search, Users } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	Checkbox,
	EmptyState,
	Input,
	Spinner,
} from "@/ui";
import { csvUrl, type ListParams } from "./api";
import { usePeople } from "./queries";
import type { Kind, Person } from "./schemas";

export type Column<P> = { key: string; header: string; cell: (p: Person<P>) => ReactNode };
// Only routes that exist may appear here (TanStack types `to`); Task 14 adds
// the parent and teacher detail routes.
export type DetailTo = "/people/students/$personId";

const PAGE_SIZE = 25;

export function PeopleList<P>({
	kind,
	columns,
	params,
	onParamsChange,
	filters,
	selection,
	actions,
	detailTo,
	emptyLabel,
}: {
	kind: Kind;
	columns: Column<P>[];
	params: ListParams;
	onParamsChange: (next: ListParams) => void;
	filters?: ReactNode;
	selection?: { selected: number[]; onChange: (ids: number[]) => void };
	actions?: ReactNode;
	detailTo?: DetailTo;
	emptyLabel: string;
}) {
	const { t } = useTranslation();
	const { data, isPending, isError } = usePeople<P>(kind, params);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const set = (patch: ListParams) => onParamsChange({ ...params, page: 1, ...patch });

	function toggle(id: number) {
		if (!selection) return;
		const { selected, onChange } = selection;
		onChange(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]);
	}

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<label className="relative min-w-48 flex-1">
					<span className="sr-only">{t("people.search")}</span>
					<Search className="pointer-events-none absolute start-3 top-3.5 size-4 text-muted-foreground" />
					<Input
						type="search"
						className="ps-9"
						placeholder={t("people.search")}
						value={String(params.q ?? "")}
						onChange={(e) => set({ q: e.target.value })}
					/>
				</label>
				{filters}
				<Button asChild variant="outline" size="sm">
					<a href={csvUrl(kind, params)} download>
						{t("people.exportCsv")}
					</a>
				</Button>
				{actions}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("people.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={Users} title={emptyLabel} />
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-start text-muted-foreground">
							<tr>
								{selection ? <th className="w-10 p-3" /> : null}
								{columns.map((c) => (
									<th key={c.key} scope="col" className="p-3 text-start font-medium">
										{c.header}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((p) => (
								<tr key={p.id} className="border-t border-border">
									{selection ? (
										<td className="p-3">
											<Checkbox
												id={`select-${p.id}`}
												checked={selection.selected.includes(p.id)}
												onCheckedChange={() => toggle(p.id)}
											/>
											<label htmlFor={`select-${p.id}`} className="sr-only">
												{t("people.select", { name: p.user.full_name })}
											</label>
										</td>
									) : null}
									{columns.map((c, i) => (
										<td key={c.key} className="p-3">
											{i === 0 && detailTo ? (
												<Link
													to={detailTo}
													params={{ personId: String(p.id) }}
													className="font-medium text-primary-text underline-offset-4 hover:underline"
												>
													{c.cell(p)}
												</Link>
											) : (
												c.cell(p)
											)}
										</td>
									))}
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			{pages > 1 ? (
				<nav aria-label={t("people.pagination")} className="flex items-center justify-between gap-2">
					<Button variant="outline" size="sm" disabled={page <= 1} onClick={() => onParamsChange({ ...params, page: page - 1 })}>
						{t("people.previous")}
					</Button>
					<span className="text-sm text-muted-foreground">
						{t("people.page", { page, pages })}
					</span>
					<Button variant="outline" size="sm" disabled={page >= pages} onClick={() => onParamsChange({ ...params, page: page + 1 })}>
						{t("people.next")}
					</Button>
				</nav>
			) : null}
		</div>
	);
}
```

`src/features/people/StudentsList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { countryOptions } from "@/lib/countries";
import { Button, Select, toast } from "@/ui";
import { AccountStateChip } from "./AccountActions";
import type { ListParams } from "./api";
import { type Column, PeopleList } from "./PeopleList";
import { useBulkStudents } from "./queries";
import { STUDENT_STATUSES, type StudentProfile, type StudentStatus } from "./schemas";

const TABS = ["all", ...STUDENT_STATUSES] as const;

export function StudentsList() {
	const { t, i18n } = useTranslation();
	const [params, setParams] = useState<ListParams>({ page: 1 });
	const [selected, setSelected] = useState<number[]>([]);
	const [bulkStatus, setBulkStatus] = useState<StudentStatus>("active");
	const bulk = useBulkStudents();
	const current = String(params.status ?? "all");
	const update = (patch: ListParams) => {
		setSelected([]);
		setParams({ ...params, page: 1, ...patch });
	};

	const columns: Column<StudentProfile>[] = [
		{ key: "name", header: t("people.columns.name"), cell: (p) => p.user.full_name },
		{ key: "email", header: t("people.columns.email"), cell: (p) => p.user.email ?? "—" },
		{ key: "phone", header: t("people.columns.phone"), cell: (p) => <span dir="ltr">{p.user.phone || "—"}</span> },
		{ key: "status", header: t("people.columns.status"), cell: (p) => t(`people.status.${p.profile.status}`) },
		{ key: "account", header: t("people.columns.account"), cell: (p) => <AccountStateChip state={p.user.account_state} /> },
	];

	function runBulk(action: "activate" | "deactivate" | "set_status") {
		bulk.mutate(
			{ ids: selected, action, ...(action === "set_status" ? { status: bulkStatus } : {}) },
			{
				onSuccess: ({ updated }) => {
					setSelected([]);
					toast({ description: t("people.bulk.done", { count: updated }), variant: "success" });
				},
				onError: () => toast({ description: t("people.genericError"), variant: "destructive" }),
			},
		);
	}

	return (
		<div className="flex flex-col gap-4">
			<div role="tablist" aria-label={t("people.columns.status")} className="flex flex-wrap gap-2 border-b border-border pb-2">
				{TABS.map((tab) => (
					<button
						key={tab}
						type="button"
						role="tab"
						aria-selected={current === tab}
						onClick={() => update({ status: tab === "all" ? undefined : tab })}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{tab === "all" ? t("people.tabs.all") : t(`people.status.${tab}`)}
					</button>
				))}
			</div>
			{selected.length > 0 ? (
				<section
					aria-label={t("people.bulk.selected", { count: selected.length })}
					className="flex flex-wrap items-end gap-2 rounded-lg border border-border bg-secondary p-3"
				>
					<span className="me-auto text-sm font-medium">
						{t("people.bulk.selected", { count: selected.length })}
					</span>
					<Button size="sm" variant="outline" onClick={() => runBulk("activate")}>
						{t("people.account.activate")}
					</Button>
					<Button size="sm" variant="outline" onClick={() => runBulk("deactivate")}>
						{t("people.account.deactivate")}
					</Button>
					{/* aria-label, not a wrapping <label>: a wrapping label's text
					    would include every option's text. */}
					<Select
						aria-label={t("people.bulk.newStatus")}
						className="w-auto"
						value={bulkStatus}
						onChange={(e) => setBulkStatus(e.target.value as StudentStatus)}
					>
						{STUDENT_STATUSES.map((s) => (
							<option key={s} value={s}>
								{t(`people.status.${s}`)}
							</option>
						))}
					</Select>
					<Button size="sm" onClick={() => runBulk("set_status")}>
						{t("people.bulk.setStatus")}
					</Button>
				</section>
			) : null}
			<PeopleList<StudentProfile>
				kind="students"
				columns={columns}
				params={params}
				onParamsChange={(next) => {
					setSelected([]);
					setParams(next);
				}}
				detailTo="/people/students/$personId"
				emptyLabel={t("people.students.empty")}
				selection={{ selected, onChange: setSelected }}
				filters={
					<>
						<Select aria-label={t("people.filters.active")} className="w-auto" value={String(params.is_active ?? "")} onChange={(e) => update({ is_active: e.target.value })}>
							<option value="">{t("people.filters.anyAccount")}</option>
							<option value="true">{t("people.account.active")}</option>
							<option value="false">{t("people.account.inactive")}</option>
						</Select>
						<Select aria-label={t("people.field.gender")} className="w-auto" value={String(params.gender ?? "")} onChange={(e) => update({ gender: e.target.value })}>
							<option value="">{t("people.filters.anyGender")}</option>
							<option value="male">{t("people.gender.male")}</option>
							<option value="female">{t("people.gender.female")}</option>
						</Select>
						<Select aria-label={t("people.field.country")} className="w-auto" value={String(params.country ?? "")} onChange={(e) => update({ country: e.target.value })}>
							<option value="">{t("people.filters.anyCountry")}</option>
							{countryOptions(i18n.language).map((c) => (
								<option key={c.code} value={c.code}>
									{c.name}
								</option>
							))}
						</Select>
					</>
				}
				actions={
					<Button asChild size="sm">
						<Link to="/people/students/$personId" params={{ personId: "new" }}>
							<Plus className="size-4" />
							{t("people.students.new")}
						</Link>
					</Button>
				}
			/>
		</div>
	);
}
```

`src/features/people/StudentForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { countryOptions } from "@/lib/countries";
import {
	Alert,
	AlertDescription,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { AccountActions } from "./AccountActions";
import { applyServerErrors } from "./form-errors";
import { GuardiansPanel } from "./GuardiansPanel";
import { usePerson, useSavePerson } from "./queries";
import {
	emptyUser,
	type Person,
	STUDENT_STATUSES,
	type StudentFormValues,
	type StudentProfile,
	studentFormSchema,
	toUserPayload,
	userDefaults,
} from "./schemas";

function defaults(person: Person<StudentProfile>): StudentFormValues {
	const p = person.profile;
	return {
		user: userDefaults(person.user),
		profile: {
			date_of_birth: p.date_of_birth ?? "",
			gender: p.gender,
			country: p.country,
			status: p.status,
			notes: p.notes,
		},
	};
}

export function StudentForm({ personId }: { personId: string }) {
	const { t, i18n } = useTranslation();
	const navigate = useNavigate();
	const isNew = personId === "new";
	const id = isNew ? undefined : Number(personId);
	const { data: person } = usePerson<StudentProfile>("students", id);
	const { data: academy, isPending: academyPending } = useAcademySettings();
	const save = useSavePerson<StudentProfile>("students", id);
	const methods = useForm<StudentFormValues>({
		resolver: zodResolver(studentFormSchema),
		values: isNew
			? academyPending
				? undefined
				: {
						user: emptyUser(academy),
						profile: { date_of_birth: "", gender: "", country: "", status: "active", notes: "" },
					}
			: person
				? defaults(person)
				: undefined,
	});
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = methods;

	async function onSubmit(values: StudentFormValues) {
		try {
			const saved = await save.mutateAsync({
				user: toUserPayload(values.user),
				profile: { ...values.profile, date_of_birth: values.profile.date_of_birth || null },
			});
			toast({ description: t("people.saved"), variant: "success" });
			if (isNew) {
				navigate({ to: "/people/students/$personId", params: { personId: String(saved.id) } });
			}
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	if ((!isNew && !person) || (isNew && academyPending)) return <Spinner />;

	return (
		<div className="flex flex-col gap-6">
			<FormProvider {...methods}>
				<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-6" noValidate>
					<UserFieldsSection emailHint={t("people.students.emailHint")} />
					<div className="grid gap-4 sm:grid-cols-2">
						<Field id="profile.date_of_birth" label={t("people.field.date_of_birth")} error={errors.profile?.date_of_birth?.message}>
							<Input type="date" {...register("profile.date_of_birth")} />
						</Field>
						<Field id="profile.gender" label={t("people.field.gender")} error={errors.profile?.gender?.message}>
							<Select {...register("profile.gender")}>
								<option value="">—</option>
								<option value="male">{t("people.gender.male")}</option>
								<option value="female">{t("people.gender.female")}</option>
							</Select>
						</Field>
						<Field id="profile.country" label={t("people.field.country")} error={errors.profile?.country?.message}>
							<Select {...register("profile.country")}>
								<option value="">—</option>
								{countryOptions(i18n.language).map((c) => (
									<option key={c.code} value={c.code}>
										{c.name}
									</option>
								))}
							</Select>
						</Field>
						<Field id="profile.status" label={t("people.field.status")} error={errors.profile?.status?.message}>
							<Select {...register("profile.status")}>
								{STUDENT_STATUSES.map((s) => (
									<option key={s} value={s}>
										{t(`people.status.${s}`)}
									</option>
								))}
							</Select>
						</Field>
					</div>
					<Field id="profile.notes" label={t("people.field.notes")} error={errors.profile?.notes?.message}>
						<Textarea rows={4} {...register("profile.notes")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{errors.root.server.message}</AlertDescription>
						</Alert>
					) : null}
					<SubmitButton pending={isSubmitting} className="self-start">
						{t("people.save")}
					</SubmitButton>
				</form>
			</FormProvider>
			{person ? (
				<>
					<AccountActions kind="students" person={person} />
					<GuardiansPanel studentId={person.id} />
				</>
			) : null}
		</div>
	);
}
```

(add `import { UserFieldsSection } from "./UserFieldsSection";` to the imports.)

`src/features/people/GuardiansPanel.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import {
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Checkbox,
	Dialog,
	DialogClose,
	DialogContent,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	toast,
} from "@/ui";
import { applyServerErrors } from "./form-errors";
import {
	useGuardians,
	useLinkGuardian,
	usePeople,
	useSavePerson,
	useUnlinkGuardian,
} from "./queries";
import {
	emptyUser,
	type ParentFormValues,
	type ParentProfile,
	parentFormSchema,
	toUserPayload,
} from "./schemas";
import { UserFieldsSection } from "./UserFieldsSection";

export function GuardiansPanel({ studentId }: { studentId: number }) {
	const { t } = useTranslation();
	const { data: guardians = [] } = useGuardians(studentId);
	const [query, setQuery] = useState("");
	const searching = query.trim().length >= 2;
	const { data: matches } = usePeople<ParentProfile>(
		"parents",
		{ q: query.trim(), page_size: 5 },
		{ enabled: searching },
	);
	const link = useLinkGuardian(studentId);
	const unlink = useUnlinkGuardian(studentId);
	const linkedIds = new Set(guardians.map((g) => g.id));
	const fail = () => toast({ description: t("people.genericError"), variant: "destructive" });

	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("people.guardians.title")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{guardians.length === 0 ? (
					<p className="text-sm text-muted-foreground">{t("people.guardians.none")}</p>
				) : (
					<ul className="flex flex-col gap-2">
						{guardians.map((g) => (
							<li key={g.id} className="flex items-center justify-between gap-2">
								<span>{g.full_name}</span>
								<Button
									size="sm"
									variant="outline"
									aria-label={t("people.guardians.unlinkName", { name: g.full_name })}
									onClick={() => unlink.mutate(g.id, { onError: fail })}
								>
									{t("people.guardians.unlink")}
								</Button>
							</li>
						))}
					</ul>
				)}
				<Field id={`guardian-search-${studentId}`} label={t("people.guardians.search")}>
					<Input type="search" value={query} onChange={(e) => setQuery(e.target.value)} />
				</Field>
				{searching && matches ? (
					<ul className="flex flex-col gap-2">
						{matches.results
							.filter((p) => !linkedIds.has(p.id))
							.map((p) => (
								<li key={p.id} className="flex items-center justify-between gap-2">
									<span>{p.user.full_name}</span>
									<Button
										size="sm"
										aria-label={t("people.guardians.linkName", { name: p.user.full_name })}
										onClick={() => link.mutate(p.id, { onError: fail })}
									>
										{t("people.guardians.link")}
									</Button>
								</li>
							))}
					</ul>
				) : null}
				<NewParentDialog onCreated={(parentId) => link.mutate(parentId, { onError: fail })} />
			</CardContent>
		</Card>
	);
}

function NewParentDialog({ onCreated }: { onCreated: (parentId: number) => void }) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const save = useSavePerson<ParentProfile>("parents");
	const methods = useForm<ParentFormValues>({
		resolver: zodResolver(parentFormSchema),
		values: { user: emptyUser(academy), profile: { has_whatsapp: false, notes: "" } },
	});
	const whatsapp = methods.watch("profile.has_whatsapp");

	async function onSubmit(values: ParentFormValues) {
		try {
			const parent = await save.mutateAsync({ user: toUserPayload(values.user), profile: values.profile });
			onCreated(parent.id);
			setOpen(false);
			methods.reset();
		} catch (error) {
			applyServerErrors(error, methods.setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline" className="self-start">
					{t("people.guardians.newParent")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("people.guardians.newParent")}</DialogTitle>
				<FormProvider {...methods}>
					<form onSubmit={methods.handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
						<UserFieldsSection />
						<label htmlFor="new-parent-whatsapp" className="flex items-center gap-2 text-sm">
							<Checkbox
								id="new-parent-whatsapp"
								checked={whatsapp}
								onCheckedChange={(v) => methods.setValue("profile.has_whatsapp", v)}
							/>
							{t("people.field.has_whatsapp")}
						</label>
						<DialogFooter className="mt-0">
							<DialogClose asChild>
								<Button type="button" variant="outline">
									{t("people.cancel")}
								</Button>
							</DialogClose>
							<Button type="submit" disabled={methods.formState.isSubmitting}>
								{t("people.guardians.createAndLink")}
							</Button>
						</DialogFooter>
					</form>
				</FormProvider>
			</DialogContent>
		</Dialog>
	);
}
```

`src/features/people/index.ts` — re-export every component, hook, api and type above.

Routes:

`src/routes/_authed/people.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireAdmin } from "@/features/identity/require-admin";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/people")({
	beforeLoad: ({ context }) => requireAdmin(context),
	component: () => (
		<PageContainer>
			<Outlet />
		</PageContainer>
	),
});
```

`src/routes/_authed/people.students.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { StudentsList } from "@/features/people";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/people/students/")({
	component: function StudentsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.students"));
		return (
			<>
				<PageHeader title={t("nav.students")} />
				<StudentsList />
			</>
		);
	},
});
```

`src/routes/_authed/people.students.$personId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { StudentForm } from "@/features/people";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/people/students/$personId")({
	component: function StudentRoute() {
		const { t } = useTranslation();
		const { personId } = Route.useParams();
		const title = personId === "new" ? t("people.students.new") : t("people.students.edit");
		usePageTitle(title);
		return (
			<>
				<PageHeader title={title} />
				<StudentForm personId={personId} />
			</>
		);
	},
});
```

Locales — merge into `people` (en):

```json
{
	"contact": "Contact details",
	"search": "Search by name, email or phone",
	"exportCsv": "Export CSV",
	"select": "Select {{name}}",
	"pagination": "Pages",
	"previous": "Previous",
	"next": "Next",
	"page": "Page {{page}} of {{pages}}",
	"save": "Save",
	"saved": "Saved.",
	"cancel": "Cancel",
	"loadError": "Couldn't load this list.",
	"genericError": "Something went wrong. Please try again.",
	"tabs": { "all": "All" },
	"columns": {
		"name": "Name",
		"email": "Email",
		"phone": "Phone",
		"status": "Status",
		"account": "Account",
		"children": "Children",
		"whatsapp": "WhatsApp",
		"gender": "Gender",
		"courses": "Courses"
	},
	"filters": {
		"active": "Account",
		"anyAccount": "Any account",
		"anyGender": "Any gender",
		"anyCountry": "Any country",
		"anyCourse": "Any course",
		"anyWhatsapp": "WhatsApp: any"
	},
	"bulk": {
		"selected": "{{count}} selected",
		"newStatus": "New status",
		"setStatus": "Set status",
		"done": "{{count}} updated."
	},
	"account": {
		"title": "Account",
		"no_login": "No login",
		"invited": "Invite pending",
		"active": "Active",
		"inactive": "Deactivated",
		"sendInvite": "Send invite",
		"sendReset": "Send password reset",
		"deactivate": "Deactivate",
		"activate": "Activate",
		"inviteSent": "Invite sent.",
		"resetSent": "Password reset sent.",
		"deactivated": "Deactivated.",
		"activated": "Activated.",
		"pendingEmail": "Waiting for {{email}} to be confirmed.",
		"blocked": {
			"self": "You can't deactivate your own account.",
			"last_admin": "The academy needs at least one active admin."
		}
	},
	"guardians": {
		"title": "Guardians",
		"none": "No guardians linked yet.",
		"search": "Find a parent",
		"link": "Link",
		"linkName": "Link {{name}}",
		"unlink": "Unlink",
		"unlinkName": "Unlink {{name}}",
		"newParent": "New parent",
		"createAndLink": "Create and link"
	},
	"students": {
		"new": "New student",
		"edit": "Student",
		"empty": "No students yet.",
		"emailHint": "Leave the email empty for a student without a login. Adding one later sends an invite."
	}
}
```

(ar):

```json
{
	"contact": "بيانات التواصل",
	"search": "ابحث بالاسم أو البريد أو الهاتف",
	"exportCsv": "تصدير CSV",
	"select": "تحديد {{name}}",
	"pagination": "الصفحات",
	"previous": "السابق",
	"next": "التالي",
	"page": "صفحة {{page}} من {{pages}}",
	"save": "حفظ",
	"saved": "تم الحفظ.",
	"cancel": "إلغاء",
	"loadError": "تعذّر تحميل هذه القائمة.",
	"genericError": "حدث خطأ ما. حاول مرة أخرى.",
	"tabs": { "all": "الكل" },
	"columns": {
		"name": "الاسم",
		"email": "البريد الإلكتروني",
		"phone": "الهاتف",
		"status": "الحالة",
		"account": "الحساب",
		"children": "الأبناء",
		"whatsapp": "واتساب",
		"gender": "الجنس",
		"courses": "الدورات"
	},
	"filters": {
		"active": "الحساب",
		"anyAccount": "أي حساب",
		"anyGender": "أي جنس",
		"anyCountry": "أي دولة",
		"anyCourse": "أي دورة",
		"anyWhatsapp": "واتساب: الكل"
	},
	"bulk": {
		"selected": "{{count}} محدد",
		"newStatus": "الحالة الجديدة",
		"setStatus": "تعيين الحالة",
		"done": "تم تحديث {{count}}."
	},
	"account": {
		"title": "الحساب",
		"no_login": "بلا تسجيل دخول",
		"invited": "الدعوة معلّقة",
		"active": "نشط",
		"inactive": "معطّل",
		"sendInvite": "إرسال دعوة",
		"sendReset": "إرسال إعادة تعيين كلمة المرور",
		"deactivate": "تعطيل",
		"activate": "تفعيل",
		"inviteSent": "تم إرسال الدعوة.",
		"resetSent": "تم إرسال رابط إعادة التعيين.",
		"deactivated": "تم التعطيل.",
		"activated": "تم التفعيل.",
		"pendingEmail": "بانتظار تأكيد {{email}}.",
		"blocked": {
			"self": "لا يمكنك تعطيل حسابك.",
			"last_admin": "تحتاج الأكاديمية إلى مشرف نشط واحد على الأقل."
		}
	},
	"guardians": {
		"title": "أولياء الأمور",
		"none": "لا يوجد أولياء أمور مرتبطون بعد.",
		"search": "ابحث عن ولي أمر",
		"link": "ربط",
		"linkName": "ربط {{name}}",
		"unlink": "إلغاء الربط",
		"unlinkName": "إلغاء ربط {{name}}",
		"newParent": "ولي أمر جديد",
		"createAndLink": "إنشاء وربط"
	},
	"students": {
		"new": "طالب جديد",
		"edit": "الطالب",
		"empty": "لا يوجد طلاب بعد.",
		"emailHint": "اترك البريد فارغًا لطالب بلا تسجيل دخول. إضافته لاحقًا ترسل دعوة."
	}
}
```

- [ ] **Step 4: Verify**

Run: `npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage`
Expected: all pass; floors hold. If the page title tests for the new routes are missing coverage, `usePageTitle` lines in route files are covered by the build only. That is acceptable because route files follow the existing Website route pattern.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): students list and form with guardians, account actions, bulk and CSV

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 13: Dashboard — Catalogue (courses, packages, live `sessions_total`)

**Files:**
- Create: `dashboard/src/features/catalogue/{schemas.ts,api.ts,queries.ts,sessions-total.ts,CatalogueList.tsx,CourseForm.tsx,PackageForm.tsx,index.ts}` + tests `{sessions-total.test.ts,CatalogueList.test.tsx,CourseForm.test.tsx,PackageForm.test.tsx}`, `dashboard/src/lib/money.ts`, `dashboard/src/lib/money.test.ts`, `dashboard/src/lib/currencies.ts`
- Create routes: `dashboard/src/routes/_authed/catalogue.tsx`, `catalogue.courses.index.tsx`, `catalogue.courses.$courseId.tsx`, `catalogue.packages.index.tsx`, `catalogue.packages.$packageId.tsx`
- Modify: `dashboard/src/locales/{en,ar}/common.json`

**Interfaces:**
- Consumes: `/api/v1/catalogue/…` (Task 9); `usePeople("teachers", …)` (Task 12); `BilingualField` (`@/features/website`); `requireAdmin`; `Textarea`.
- Produces:
  - `sessionsTotal(sessionsPerWeek: number, durationValue: number, durationUnit: DurationUnit) -> number` and `weeks(durationValue, durationUnit)`. These mirror `etqan.catalogue.services` and are for the live preview only; the saved value always comes from the API.
  - `minorDigits(currency) -> number`, `toMinor(major: string, currency) -> number`, `toMajor(minor: number, currency) -> string`, `formatMoney(minor, currency, language) -> string`.
  - `CURRENCIES` (curated ISO 4217 list).
  - `catalogueApi.{list, get, create, update, remove, duplicate}(kind: "courses" | "packages", …)`, `csvUrl`; hooks `useCatalogue(kind, params)`, `useCatalogueItem(kind, id?)`, `useSaveCatalogueItem(kind, id?)`, `useDeleteCatalogueItem(kind)`, `useDuplicateCatalogueItem(kind)`; types `Course`, `Package`, `DurationUnit`, `courseFormSchema`, `packageFormSchema`.
  - `<CatalogueList kind>`, `<CourseForm courseId>`, `<PackageForm packageId>`; routes `/catalogue/courses[/$courseId]`, `/catalogue/packages[/$packageId]` behind `requireAdmin`.

- [ ] **Step 1: Write the failing tests**

`src/features/catalogue/sessions-total.test.ts` (the same table as the backend's `test_sessions_total.py`):

```ts
import { describe, expect, it } from "vitest";
import { sessionsTotal, weeks } from "./sessions-total";

describe("weeks (P3-7, mirrors etqan.catalogue.services)", () => {
	it.each([
		[1, "day", 1],
		[6, "day", 1],
		[7, "day", 1],
		[8, "day", 2],
		[14, "day", 2],
		[15, "day", 3],
		[30, "day", 5],
		[365, "day", 53],
		[1, "month", 4],
		[3, "month", 12],
		[365, "month", 1460],
	] as const)("%i %s → %i weeks", (value, unit, expected) => {
		expect(weeks(value, unit)).toBe(expected);
	});
});

describe("sessionsTotal", () => {
	it.each([
		[1, 1, "day", 1],
		[2, 1, "month", 8],
		[3, 30, "day", 15],
		[14, 365, "month", 20440],
		[14, 365, "day", 742],
	] as const)("%i/week × %i %s = %i", (perWeek, value, unit, expected) => {
		expect(sessionsTotal(perWeek, value, unit)).toBe(expected);
	});

	it("is 0 while an input is not a whole number yet", () => {
		expect(sessionsTotal(Number.NaN, 1, "month")).toBe(0);
		expect(sessionsTotal(2, 0, "day")).toBe(0);
	});
});
```

`src/lib/money.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { formatMoney, minorDigits, toMajor, toMinor } from "./money";

describe("money", () => {
	it("knows each currency's minor digits", () => {
		expect(minorDigits("EGP")).toBe(2);
		expect(minorDigits("KWD")).toBe(3);
		expect(minorDigits("JPY")).toBe(0);
	});

	it("converts without floating-point drift", () => {
		expect(toMinor("1500", "EGP")).toBe(150000);
		expect(toMinor("19.99", "USD")).toBe(1999);
		expect(toMinor("1.005", "KWD")).toBe(1005);
		expect(toMajor(150000, "EGP")).toBe("1500.00");
		expect(toMajor(1005, "KWD")).toBe("1.005");
	});

	it("formats for display", () => {
		expect(formatMoney(150000, "EGP", "en")).toContain("1,500.00");
	});
});
```

`src/features/catalogue/CatalogueList.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { catalogueApi } from "./api";
import { CatalogueList } from "./CatalogueList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn(), duplicate: vi.fn() },
	};
});

const pkg = {
	id: 1,
	name_ar: "شهري",
	name_en: "Monthly",
	description_ar: "",
	description_en: "",
	sessions_per_week: 2,
	session_minutes: 45,
	duration_value: 1,
	duration_unit: "month" as const,
	freeze_days_allowed: 0,
	price_minor: 150000,
	currency: "EGP",
	is_active: true,
	sessions_total: 8,
};

describe("CatalogueList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(catalogueApi.list).mockResolvedValue({
			count: 1,
			next: null,
			previous: null,
			results: [pkg],
		});
	});

	it("lists packages with their total and price", async () => {
		renderWithRouter(<CatalogueList kind="packages" />);
		expect(await screen.findByText("Monthly")).toBeInTheDocument();
		expect(screen.getByText("8 sessions")).toBeInTheDocument();
		expect(screen.getByText(/1,500\.00/)).toBeInTheDocument();
	});

	it("filters by active state and duplicates", async () => {
		vi.mocked(catalogueApi.duplicate).mockResolvedValue({ ...pkg, id: 2 });
		const user = userEvent.setup();
		renderWithRouter(<CatalogueList kind="packages" />);
		await screen.findByText("Monthly");
		await user.selectOptions(screen.getByLabelText("Active"), "false");
		await waitFor(() =>
			expect(vi.mocked(catalogueApi.list).mock.calls.at(-1)?.[1]).toMatchObject({
				is_active: "false",
			}),
		);
		await user.click(screen.getByRole("button", { name: "Duplicate Monthly" }));
		await waitFor(() => expect(catalogueApi.duplicate).toHaveBeenCalledWith("packages", 1));
	});
});
```

`src/features/catalogue/PackageForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { catalogueApi } from "./api";
import { PackageForm } from "./PackageForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, get: vi.fn(), create: vi.fn(), update: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

describe("PackageForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
		});
	});

	it("shows sessions_total live and saves minor units", async () => {
		vi.mocked(catalogueApi.create).mockResolvedValue({ id: 3 } as never);
		const user = userEvent.setup();
		renderWithRouter(<PackageForm packageId="new" />, {
			extraPaths: ["/catalogue/packages"],
		});
		await user.type(await screen.findByLabelText("Name (Arabic)"), "مكثف");
		await user.type(screen.getByLabelText("Name (English)"), "Intensive");
		await user.clear(screen.getByLabelText("Sessions per week"));
		await user.type(screen.getByLabelText("Sessions per week"), "5");
		await user.clear(screen.getByLabelText("Duration"));
		await user.type(screen.getByLabelText("Duration"), "8");
		await user.selectOptions(screen.getByLabelText("Duration unit"), "day");
		expect(screen.getByText("10 sessions in total")).toBeInTheDocument();
		await user.type(screen.getByLabelText("Price"), "900");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(catalogueApi.create).toHaveBeenCalled());
		expect(vi.mocked(catalogueApi.create).mock.calls[0]?.[1]).toMatchObject({
			sessions_per_week: 5,
			duration_value: 8,
			duration_unit: "day",
			price_minor: 90000,
			currency: "EGP",
			session_minutes: 45,
		});
	});

	it("rejects out-of-range values before saving", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PackageForm packageId="new" />);
		await user.clear(await screen.findByLabelText("Sessions per week"));
		await user.type(screen.getByLabelText("Sessions per week"), "15");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText(/at most 14/i)).toBeInTheDocument();
		expect(catalogueApi.create).not.toHaveBeenCalled();
	});

	it("offers a custom session length", async () => {
		const user = userEvent.setup();
		renderWithRouter(<PackageForm packageId="new" />);
		await user.selectOptions(await screen.findByLabelText("Session length"), "other");
		expect(screen.getByLabelText("Minutes")).toBeInTheDocument();
	});
});
```

`src/features/catalogue/CourseForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { catalogueApi } from "./api";
import { CourseForm } from "./CourseForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, get: vi.fn(), create: vi.fn(), update: vi.fn(), remove: vi.fn() },
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const bilal = {
	id: 21,
	role: "teacher" as const,
	user: { full_name: "Bilal", email: null, phone: "", preferred_language: "ar" as const, timezone: "UTC", is_active: true, account_state: "no_login" as const, pending_email: "" },
	profile: {},
};

describe("CourseForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue({ count: 1, next: null, previous: null, results: [bilal] });
	});

	it("requires both names and links teachers", async () => {
		vi.mocked(catalogueApi.create).mockResolvedValue({ id: 1 } as never);
		const user = userEvent.setup();
		renderWithRouter(<CourseForm courseId="new" />, { extraPaths: ["/catalogue/courses"] });
		await user.type(await screen.findByLabelText("Name (English)"), "Tajweed");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findAllByRole("alert")).not.toHaveLength(0);
		expect(catalogueApi.create).not.toHaveBeenCalled();
		await user.type(screen.getByLabelText("Name (Arabic)"), "تجويد");
		await user.click(await screen.findByLabelText("Bilal"));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(catalogueApi.create).toHaveBeenCalledWith(
				"courses",
				expect.objectContaining({ name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [21] }),
			),
		);
	});

	it("deletes an existing course after confirmation", async () => {
		vi.mocked(catalogueApi.get).mockResolvedValue({
			id: 4, name_ar: "تجويد", name_en: "Tajweed", description_ar: "", description_en: "",
			language: "ar", is_active: true, teacher_ids: [],
		});
		vi.mocked(catalogueApi.remove).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(<CourseForm courseId="4" />, { extraPaths: ["/catalogue/courses"] });
		await user.click(await screen.findByRole("button", { name: "Delete" }));
		await user.click(await screen.findByRole("button", { name: "Delete course" }));
		await waitFor(() => expect(catalogueApi.remove).toHaveBeenCalledWith("courses", 4));
	});
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx pnpm@10 vitest run src/features/catalogue src/lib/money.test.ts`
Expected: FAIL (modules not found).

- [ ] **Step 3: Implement**

`src/features/catalogue/sessions-total.ts`:

```ts
export type DurationUnit = "day" | "month";

const DAYS_PER_WEEK = 7;
const WEEKS_PER_MONTH = 4;

/** P3-7, mirroring etqan.catalogue.services.weeks — for the live preview only. */
export function weeks(durationValue: number, durationUnit: DurationUnit): number {
	return durationUnit === "month"
		? WEEKS_PER_MONTH * durationValue
		: Math.ceil(durationValue / DAYS_PER_WEEK);
}

export function sessionsTotal(
	sessionsPerWeek: number,
	durationValue: number,
	durationUnit: DurationUnit,
): number {
	if (!Number.isInteger(sessionsPerWeek) || !Number.isInteger(durationValue)) return 0;
	if (sessionsPerWeek < 1 || durationValue < 1) return 0;
	return sessionsPerWeek * weeks(durationValue, durationUnit);
}
```

`src/lib/currencies.ts`:

```ts
/** Curated ISO 4217 codes offered in pickers (plan D8); the API accepts any code. */
export const CURRENCIES = [
	"EGP", "SAR", "AED", "KWD", "QAR", "BHD", "OMR", "JOD", "MAD", "TND", "DZD",
	"LYD", "IQD", "TRY", "PKR", "INR", "IDR", "MYR", "NGN", "USD", "EUR", "GBP",
	"CAD", "AUD",
] as const;
```

`src/lib/money.ts`:

```ts
/** Money is integer minor units + ISO 4217 currency (project rule). */
export function minorDigits(currency: string): number {
	return (
		new Intl.NumberFormat("en", { style: "currency", currency }).resolvedOptions()
			.maximumFractionDigits ?? 2
	);
}

export function toMinor(major: string, currency: string): number {
	const digits = minorDigits(currency);
	const [whole = "0", fraction = ""] = major.trim().split(".");
	const padded = (fraction + "0".repeat(digits)).slice(0, digits);
	const sign = whole.startsWith("-") ? -1 : 1;
	const units = Math.abs(Number(whole || "0")) * 10 ** digits + Number(padded || "0");
	return sign * units;
}

export function toMajor(minor: number, currency: string): string {
	const digits = minorDigits(currency);
	return (minor / 10 ** digits).toFixed(digits);
}

export function formatMoney(minor: number, currency: string, language: string): string {
	return new Intl.NumberFormat(language, { style: "currency", currency }).format(
		Number(toMajor(minor, currency)),
	);
}
```

`src/features/catalogue/schemas.ts`:

```ts
import { z } from "zod";
import type { DurationUnit } from "./sessions-total";

export type CatalogueKind = "courses" | "packages";
export type CourseLanguage = "ar" | "en" | "both";

export interface Course {
	id: number;
	name_ar: string;
	name_en: string;
	description_ar: string;
	description_en: string;
	language: CourseLanguage;
	is_active: boolean;
	teacher_ids: number[];
}

export interface Package {
	id: number;
	name_ar: string;
	name_en: string;
	description_ar: string;
	description_en: string;
	sessions_per_week: number;
	session_minutes: number;
	duration_value: number;
	duration_unit: DurationUnit;
	freeze_days_allowed: number;
	price_minor: number;
	currency: string;
	is_active: boolean;
	sessions_total: number;
}

const int = (min: number, max: number) =>
	z
		.number({ error: "Enter a whole number." })
		.int("Enter a whole number.")
		.min(min, `At least ${min}.`)
		.max(max, `At most ${max}.`);

const names = {
	name_ar: z.string().trim().min(1, "This field is required."),
	name_en: z.string().trim().min(1, "This field is required."),
	description_ar: z.string(),
	description_en: z.string(),
	is_active: z.boolean(),
};

export const courseFormSchema = z.object({
	...names,
	language: z.enum(["ar", "en", "both"]),
	teacher_ids: z.array(z.number()),
});
export type CourseFormValues = z.infer<typeof courseFormSchema>;

export const packageFormSchema = z.object({
	...names,
	sessions_per_week: int(1, 14),
	session_length: z.enum(["30", "45", "60", "other"]),
	session_minutes: int(15, 240),
	duration_value: int(1, 365),
	duration_unit: z.enum(["day", "month"]),
	freeze_days_allowed: int(0, 365),
	price: z.string().regex(/^\d+(\.\d{1,3})?$/, "Enter an amount, like 150 or 150.50."),
	currency: z.string().regex(/^[A-Z]{3}$/),
});
export type PackageFormValues = z.infer<typeof packageFormSchema>;
```

`src/features/catalogue/api.ts`:

```ts
import { api } from "@/lib/api";
import type { Paginated } from "@/features/people/schemas";
import type { CatalogueKind } from "./schemas";

export type CatalogueParams = Record<string, string | number | undefined>;

function clean(params: CatalogueParams): Record<string, string> {
	return Object.fromEntries(
		Object.entries(params)
			.filter(([, v]) => v !== undefined && v !== "")
			.map(([k, v]) => [k, String(v)]),
	);
}

export const catalogueApi = {
	list: async <T>(kind: CatalogueKind, params: CatalogueParams) =>
		(await api.get<Paginated<T>>(`catalogue/${kind}/`, { params: clean(params) })).data,
	get: async <T>(kind: CatalogueKind, id: number) =>
		(await api.get<T>(`catalogue/${kind}/${id}/`)).data,
	create: async <T>(kind: CatalogueKind, body: Record<string, unknown>) =>
		(await api.post<T>(`catalogue/${kind}/`, body)).data,
	update: async <T>(kind: CatalogueKind, id: number, body: Record<string, unknown>) =>
		(await api.patch<T>(`catalogue/${kind}/${id}/`, body)).data,
	remove: async (kind: CatalogueKind, id: number) => {
		await api.delete(`catalogue/${kind}/${id}/`);
	},
	duplicate: async <T>(kind: CatalogueKind, id: number) =>
		(await api.post<T>(`catalogue/${kind}/${id}/duplicate/`)).data,
};

export function catalogueCsvUrl(kind: CatalogueKind, params: CatalogueParams): string {
	const filters = Object.fromEntries(
		Object.entries(params).filter(([key]) => key !== "page" && key !== "page_size"),
	);
	const query = new URLSearchParams({ ...clean(filters), format: "csv" });
	return `${api.defaults.baseURL ?? "/api/v1/"}catalogue/${kind}/?${query.toString()}`;
}
```

`src/features/catalogue/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { type CatalogueParams, catalogueApi } from "./api";
import type { CatalogueKind } from "./schemas";

export const catalogueKey = (kind: CatalogueKind) => ["catalogue", kind] as const;

export function useCatalogue<T>(kind: CatalogueKind, params: CatalogueParams) {
	return useQuery({
		queryKey: [...catalogueKey(kind), "list", params],
		queryFn: () => catalogueApi.list<T>(kind, params),
		placeholderData: keepPreviousData,
	});
}

export function useCatalogueItem<T>(kind: CatalogueKind, id: number | undefined) {
	return useQuery({
		queryKey: [...catalogueKey(kind), "detail", id],
		queryFn: () => catalogueApi.get<T>(kind, id as number),
		enabled: id !== undefined,
	});
}

export function useSaveCatalogueItem<T>(kind: CatalogueKind, id?: number) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: Record<string, unknown>) =>
			id === undefined
				? catalogueApi.create<T>(kind, body)
				: catalogueApi.update<T>(kind, id, body),
		onSuccess: () => qc.invalidateQueries({ queryKey: catalogueKey(kind) }),
	});
}

export function useDeleteCatalogueItem(kind: CatalogueKind) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => catalogueApi.remove(kind, id),
		onSuccess: () => qc.invalidateQueries({ queryKey: catalogueKey(kind) }),
	});
}

export function useDuplicateCatalogueItem(kind: CatalogueKind) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => catalogueApi.duplicate(kind, id),
		onSuccess: () => qc.invalidateQueries({ queryKey: catalogueKey(kind) }),
	});
}
```

`src/features/catalogue/CatalogueList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { BookOpen, Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { formatMoney } from "@/lib/money";
import { Button, Card, CardContent, EmptyState, Input, Select, Spinner, StatusChip, toast } from "@/ui";
import { type CatalogueParams, catalogueCsvUrl } from "./api";
import { useCatalogue, useDuplicateCatalogueItem } from "./queries";
import type { CatalogueKind, Course, Package } from "./schemas";

type Item = Course | Package;

export function CatalogueList({ kind }: { kind: CatalogueKind }) {
	const { t, i18n } = useTranslation();
	const [params, setParams] = useState<CatalogueParams>({ page: 1 });
	const { data, isPending } = useCatalogue<Item>(kind, params);
	const duplicate = useDuplicateCatalogueItem(kind);
	const isAr = i18n.language === "ar";
	const detail = kind === "courses" ? "/catalogue/courses/$courseId" : "/catalogue/packages/$packageId";
	const paramName = kind === "courses" ? "courseId" : "packageId";
	const rows = data?.results ?? [];

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<label className="min-w-48 flex-1">
					<span className="sr-only">{t("catalogue.search")}</span>
					<Input type="search" placeholder={t("catalogue.search")} value={String(params.q ?? "")} onChange={(e) => setParams({ ...params, page: 1, q: e.target.value })} />
				</label>
				<Select
					aria-label={t("catalogue.active")}
					className="w-auto"
					value={String(params.is_active ?? "")}
					onChange={(e) => setParams({ ...params, page: 1, is_active: e.target.value })}
				>
					<option value="">{t("catalogue.any")}</option>
					<option value="true">{t("people.yes")}</option>
					<option value="false">{t("people.no")}</option>
				</Select>
				<Button asChild variant="outline" size="sm">
					<a href={catalogueCsvUrl(kind, params)} download>
						{t("people.exportCsv")}
					</a>
				</Button>
				<Button asChild size="sm">
					<Link to={detail} params={{ [paramName]: "new" } as never}>
						<Plus className="size-4" />
						{t(`catalogue.${kind}.new`)}
					</Link>
				</Button>
			</div>
			{isPending ? (
				<Spinner />
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={BookOpen} title={t(`catalogue.${kind}.empty`)} />
					</CardContent>
				</Card>
			) : (
				<ul className="flex flex-col gap-2">
					{rows.map((item) => {
						const name = isAr ? item.name_ar : item.name_en;
						return (
							<li key={item.id}>
								<Card>
									<CardContent className="flex flex-wrap items-center justify-between gap-3">
										<div className="flex flex-col gap-1">
											<Link to={detail} params={{ [paramName]: String(item.id) } as never} className="font-medium text-primary-text underline-offset-4 hover:underline">
												{name}
											</Link>
											{"sessions_total" in item ? (
												<span className="flex gap-2 text-sm text-muted-foreground">
													<span>{t("catalogue.packages.totalShort", { count: item.sessions_total })}</span>
													<span dir="ltr">{formatMoney(item.price_minor, item.currency, i18n.language)}</span>
												</span>
											) : null}
										</div>
										<div className="flex items-center gap-2">
											<StatusChip tone={item.is_active ? "live" : "neutral"}>
												{item.is_active ? t("catalogue.isActive") : t("catalogue.isInactive")}
											</StatusChip>
											<Button
												size="sm"
												variant="outline"
												aria-label={t("catalogue.duplicateName", { name })}
												onClick={() =>
													duplicate.mutate(item.id, {
														onSuccess: () => toast({ description: t("catalogue.duplicated"), variant: "success" }),
														onError: () => toast({ description: t("people.genericError"), variant: "destructive" }),
													})
												}
											>
												{t("catalogue.duplicate")}
											</Button>
										</div>
									</CardContent>
								</Card>
							</li>
						);
					})}
				</ul>
			)}
		</div>
	);
}
```

(`params … as never` is needed because `detail` is a union of two route ids with different param names. Keep it confined to these two `Link`s.)

`src/features/catalogue/CourseForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { type FieldError, useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { applyServerErrors } from "@/features/people/form-errors";
import { usePeople } from "@/features/people/queries";
import { BilingualField } from "@/features/website";
import {
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
	Checkbox,
	Field,
	Select,
	Spinner,
	SubmitButton,
	toast,
} from "@/ui";
import { useCatalogueItem, useDeleteCatalogueItem, useSaveCatalogueItem } from "./queries";
import { type Course, type CourseFormValues, courseFormSchema } from "./schemas";

const EMPTY: CourseFormValues = {
	name_ar: "",
	name_en: "",
	description_ar: "",
	description_en: "",
	language: "ar",
	is_active: true,
	teacher_ids: [],
};

export function CourseForm({ courseId }: { courseId: string }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const isNew = courseId === "new";
	const id = isNew ? undefined : Number(courseId);
	const { data: course } = useCatalogueItem<Course>("courses", id);
	const { data: teachers } = usePeople("teachers", { is_active: "true", page_size: 100 });
	const save = useSaveCatalogueItem<Course>("courses", id);
	const remove = useDeleteCatalogueItem("courses");
	const { register, handleSubmit, control, setError, formState: { errors, isSubmitting } } =
		useForm<CourseFormValues>({
			resolver: zodResolver(courseFormSchema),
			values: isNew ? EMPTY : course ? { ...EMPTY, ...course } : undefined,
		});
	const active = useController({ control, name: "is_active", defaultValue: true });
	const chosen = useController({ control, name: "teacher_ids", defaultValue: [] });
	const bilingualErrors = errors as unknown as Record<string, FieldError | undefined>;

	async function onSubmit(values: CourseFormValues) {
		try {
			await save.mutateAsync(values);
			toast({ description: t("people.saved"), variant: "success" });
			navigate({ to: "/catalogue/courses" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	if (!isNew && !course) return <Spinner />;

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-6" noValidate>
			<BilingualField name="name" label={t("catalogue.name")} register={register} errors={bilingualErrors} required />
			<BilingualField name="description" label={t("catalogue.description")} register={register} errors={bilingualErrors} multiline />
			<div className="grid gap-4 sm:grid-cols-2">
				<Field id="language" label={t("catalogue.courses.language")}>
					<Select {...register("language")}>
						<option value="ar">{t("catalogue.courses.languages.ar")}</option>
						<option value="en">{t("catalogue.courses.languages.en")}</option>
						<option value="both">{t("catalogue.courses.languages.both")}</option>
					</Select>
				</Field>
				<label htmlFor="is_active" className="flex items-center gap-2 self-end text-sm">
					<Checkbox id="is_active" checked={active.field.value} onCheckedChange={active.field.onChange} />
					{t("catalogue.isActive")}
				</label>
			</div>
			<fieldset className="flex flex-col gap-2">
				<legend className="text-sm font-medium">{t("catalogue.courses.teachers")}</legend>
				{(teachers?.results ?? []).map((teacher) => {
					const checked = chosen.field.value.includes(teacher.id);
					return (
						<label key={teacher.id} htmlFor={`teacher-${teacher.id}`} className="flex items-center gap-2 text-sm">
							<Checkbox
								id={`teacher-${teacher.id}`}
								checked={checked}
								onCheckedChange={(on) =>
									chosen.field.onChange(
										on ? [...chosen.field.value, teacher.id] : chosen.field.value.filter((x) => x !== teacher.id),
									)
								}
							/>
							{teacher.user.full_name}
						</label>
					);
				})}
			</fieldset>
			<div className="flex flex-wrap gap-2">
				<SubmitButton pending={isSubmitting}>{t("people.save")}</SubmitButton>
				{course ? (
					<AlertDialog>
						<AlertDialogTrigger asChild>
							<Button type="button" variant="destructive">{t("catalogue.delete")}</Button>
						</AlertDialogTrigger>
						<AlertDialogContent>
							<AlertDialogTitle>{t("catalogue.courses.deleteTitle")}</AlertDialogTitle>
							<AlertDialogDescription>{t("catalogue.deleteBody")}</AlertDialogDescription>
							<AlertDialogFooter>
								<AlertDialogCancel asChild>
									<Button type="button" variant="outline">{t("people.cancel")}</Button>
								</AlertDialogCancel>
								<AlertDialogAction asChild>
									<Button
										type="button"
										variant="destructive"
										onClick={() =>
											remove.mutate(course.id, {
												onSuccess: () => navigate({ to: "/catalogue/courses" }),
												onError: () => toast({ description: t("people.genericError"), variant: "destructive" }),
											})
										}
									>
										{t("catalogue.courses.deleteTitle")}
									</Button>
								</AlertDialogAction>
							</AlertDialogFooter>
						</AlertDialogContent>
					</AlertDialog>
				) : null}
			</div>
		</form>
	);
}
```

`src/features/catalogue/PackageForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { type FieldError, useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { applyServerErrors } from "@/features/people/form-errors";
import { BilingualField } from "@/features/website";
import { CURRENCIES } from "@/lib/currencies";
import { toMajor, toMinor } from "@/lib/money";
import { Checkbox, Field, Input, Select, Spinner, SubmitButton, toast } from "@/ui";
import { useCatalogueItem, useSaveCatalogueItem } from "./queries";
import { type Package, type PackageFormValues, packageFormSchema } from "./schemas";
import { sessionsTotal } from "./sessions-total";

const PRESETS = ["30", "45", "60"] as const;

function toValues(p: Package): PackageFormValues {
	const preset = PRESETS.find((m) => Number(m) === p.session_minutes);
	return {
		name_ar: p.name_ar,
		name_en: p.name_en,
		description_ar: p.description_ar,
		description_en: p.description_en,
		is_active: p.is_active,
		sessions_per_week: p.sessions_per_week,
		session_length: preset ?? "other",
		session_minutes: p.session_minutes,
		duration_value: p.duration_value,
		duration_unit: p.duration_unit,
		freeze_days_allowed: p.freeze_days_allowed,
		price: toMajor(p.price_minor, p.currency),
		currency: p.currency,
	};
}

export function PackageForm({ packageId }: { packageId: string }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const isNew = packageId === "new";
	const id = isNew ? undefined : Number(packageId);
	const { data: pkg } = useCatalogueItem<Package>("packages", id);
	const { data: academy, isPending: academyPending } = useAcademySettings();
	const save = useSaveCatalogueItem<Package>("packages", id);
	const empty: PackageFormValues = {
		name_ar: "",
		name_en: "",
		description_ar: "",
		description_en: "",
		is_active: true,
		sessions_per_week: 2,
		session_length: "45",
		session_minutes: 45,
		duration_value: 1,
		duration_unit: "month",
		freeze_days_allowed: 0,
		price: "",
		currency: academy?.default_currency ?? "USD",
	};
	const { register, handleSubmit, control, watch, setError, formState: { errors, isSubmitting } } =
		useForm<PackageFormValues>({
			resolver: zodResolver(packageFormSchema),
			values: isNew ? (academyPending ? undefined : empty) : pkg ? toValues(pkg) : undefined,
		});
	const active = useController({ control, name: "is_active", defaultValue: true });
	const bilingualErrors = errors as unknown as Record<string, FieldError | undefined>;
	const length = watch("session_length");
	const total = sessionsTotal(
		Number(watch("sessions_per_week")),
		Number(watch("duration_value")),
		watch("duration_unit") ?? "month",
	);

	async function onSubmit(values: PackageFormValues) {
		const { session_length, price, ...rest } = values;
		try {
			await save.mutateAsync({
				...rest,
				session_minutes: session_length === "other" ? values.session_minutes : Number(session_length),
				price_minor: toMinor(price, values.currency),
			});
			toast({ description: t("people.saved"), variant: "success" });
			navigate({ to: "/catalogue/packages" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	if ((!isNew && !pkg) || (isNew && academyPending)) return <Spinner />;
	const num = { valueAsNumber: true } as const;

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-6" noValidate>
			<BilingualField name="name" label={t("catalogue.name")} register={register} errors={bilingualErrors} required />
			<BilingualField name="description" label={t("catalogue.description")} register={register} errors={bilingualErrors} multiline />
			<div className="grid gap-4 sm:grid-cols-3">
				<Field id="sessions_per_week" label={t("catalogue.packages.sessionsPerWeek")} error={errors.sessions_per_week?.message}>
					<Input type="number" min={1} max={14} {...register("sessions_per_week", num)} />
				</Field>
				<Field id="session_length" label={t("catalogue.packages.sessionLength")}>
					<Select {...register("session_length")}>
						{PRESETS.map((m) => (
							<option key={m} value={m}>
								{t("catalogue.packages.minutes", { count: Number(m) })}
							</option>
						))}
						<option value="other">{t("catalogue.packages.other")}</option>
					</Select>
				</Field>
				{length === "other" ? (
					<Field id="session_minutes" label={t("catalogue.packages.customMinutes")} error={errors.session_minutes?.message}>
						<Input type="number" min={15} max={240} {...register("session_minutes", num)} />
					</Field>
				) : null}
				<Field id="duration_value" label={t("catalogue.packages.duration")} error={errors.duration_value?.message}>
					<Input type="number" min={1} max={365} {...register("duration_value", num)} />
				</Field>
				<Field id="duration_unit" label={t("catalogue.packages.durationUnit")}>
					<Select {...register("duration_unit")}>
						<option value="day">{t("catalogue.packages.days")}</option>
						<option value="month">{t("catalogue.packages.months")}</option>
					</Select>
				</Field>
				<Field id="freeze_days_allowed" label={t("catalogue.packages.freezeDays")} error={errors.freeze_days_allowed?.message}>
					<Input type="number" min={0} max={365} {...register("freeze_days_allowed", num)} />
				</Field>
				<Field id="price" label={t("catalogue.packages.price")} error={errors.price?.message}>
					<Input inputMode="decimal" dir="ltr" {...register("price")} />
				</Field>
				<Field id="currency" label={t("catalogue.packages.currency")}>
					<Select dir="ltr" {...register("currency")}>
						{CURRENCIES.map((c) => (
							<option key={c} value={c}>
								{c}
							</option>
						))}
					</Select>
				</Field>
			</div>
			<p aria-live="polite" className="rounded-md bg-secondary p-3 text-sm font-medium">
				{t("catalogue.packages.total", { count: total })}
			</p>
			<label htmlFor="is_active" className="flex items-center gap-2 text-sm">
				<Checkbox id="is_active" checked={active.field.value} onCheckedChange={active.field.onChange} />
				{t("catalogue.isActive")}
			</label>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
		</form>
	);
}
```

`src/features/catalogue/index.ts` — re-export the components, hooks, api and types.

Routes (same pattern as the people routes, with `usePageTitle`):
- `src/routes/_authed/catalogue.tsx`: `createFileRoute("/_authed/catalogue")({ beforeLoad: ({ context }) => requireAdmin(context), component: () => <PageContainer><Outlet /></PageContainer> })`
- `catalogue.courses.index.tsx`: `/_authed/catalogue/courses/` → `<PageHeader title={t("nav.courses")} /><CatalogueList kind="courses" />`
- `catalogue.courses.$courseId.tsx`: `/_authed/catalogue/courses/$courseId` → title `catalogue.courses.new` / `catalogue.courses.edit`, `<CourseForm courseId={courseId} />`
- `catalogue.packages.index.tsx`: `/_authed/catalogue/packages/` → `<CatalogueList kind="packages" />`
- `catalogue.packages.$packageId.tsx`: `/_authed/catalogue/packages/$packageId` → `<PackageForm packageId={packageId} />`

Locales — new top-level `catalogue` block (en):

```json
{
	"search": "Search by name",
	"active": "Active",
	"any": "Any",
	"isActive": "Active",
	"isInactive": "Inactive",
	"name": "Name",
	"description": "Description",
	"duplicate": "Duplicate",
	"duplicateName": "Duplicate {{name}}",
	"duplicated": "Copy created (inactive).",
	"delete": "Delete",
	"deleteBody": "This can't be undone.",
	"courses": {
		"new": "New course",
		"edit": "Course",
		"empty": "No courses yet.",
		"language": "Teaching language",
		"languages": { "ar": "Arabic", "en": "English", "both": "Arabic and English" },
		"teachers": "Teachers",
		"deleteTitle": "Delete course"
	},
	"packages": {
		"new": "New package",
		"edit": "Package",
		"empty": "No packages yet.",
		"sessionsPerWeek": "Sessions per week",
		"sessionLength": "Session length",
		"minutes": "{{count}} minutes",
		"other": "Other",
		"customMinutes": "Minutes",
		"duration": "Duration",
		"durationUnit": "Duration unit",
		"days": "Days",
		"months": "Months",
		"freezeDays": "Freeze days allowed",
		"price": "Price",
		"currency": "Currency",
		"total": "{{count}} sessions in total",
		"totalShort": "{{count}} sessions"
	}
}
```

(ar):

```json
{
	"search": "ابحث بالاسم",
	"active": "نشط",
	"any": "الكل",
	"isActive": "نشط",
	"isInactive": "غير نشط",
	"name": "الاسم",
	"description": "الوصف",
	"duplicate": "نسخ",
	"duplicateName": "نسخ {{name}}",
	"duplicated": "أُنشئت نسخة (غير نشطة).",
	"delete": "حذف",
	"deleteBody": "لا يمكن التراجع عن ذلك.",
	"courses": {
		"new": "دورة جديدة",
		"edit": "الدورة",
		"empty": "لا توجد دورات بعد.",
		"language": "لغة التدريس",
		"languages": { "ar": "العربية", "en": "الإنجليزية", "both": "العربية والإنجليزية" },
		"teachers": "المعلمون",
		"deleteTitle": "حذف الدورة"
	},
	"packages": {
		"new": "باقة جديدة",
		"edit": "الباقة",
		"empty": "لا توجد باقات بعد.",
		"sessionsPerWeek": "الحصص أسبوعيًا",
		"sessionLength": "مدة الحصة",
		"minutes": "{{count}} دقيقة",
		"other": "أخرى",
		"customMinutes": "الدقائق",
		"duration": "المدة",
		"durationUnit": "وحدة المدة",
		"days": "أيام",
		"months": "أشهر",
		"freezeDays": "أيام التجميد المسموحة",
		"price": "السعر",
		"currency": "العملة",
		"total": "{{count}} حصة إجمالًا",
		"totalShort": "{{count}} حصة"
	}
}
```

`BilingualField` renders its labels as `"<label> (<website.lang.xx>)"`, which gives "Name (Arabic)" and "Name (English)" as the tests expect.

- [ ] **Step 4: Verify**

Run: `npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): courses and packages with teachers, duplicate and live sessions total

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: Dashboard — Parents, Teachers, Admins, Settings → Academy

**Files:**
- Create: `dashboard/src/features/people/{ParentsList.tsx,ParentForm.tsx,TeachersList.tsx,TeacherForm.tsx,AdminsList.tsx}` + tests `{ParentForm.test.tsx,TeachersList.test.tsx,TeacherForm.test.tsx,AdminsList.test.tsx}`, `dashboard/src/features/academy/AcademySettingsForm.tsx`, `dashboard/src/features/academy/AcademySettingsForm.test.tsx`
- Create routes: `dashboard/src/routes/_authed/people.parents.index.tsx`, `people.parents.$personId.tsx`, `people.teachers.index.tsx`, `people.teachers.$personId.tsx`, `people.admins.tsx`, `settings.academy.tsx`
- Modify: `dashboard/src/features/people/PeopleList.tsx` (`DetailTo` adds the parent and teacher detail routes), `dashboard/src/features/people/index.ts`, `dashboard/src/features/academy/index.ts`, `dashboard/src/locales/{en,ar}/common.json`

**Interfaces:**
- Consumes: Task 12 people layer, `useCatalogue("courses", …)` (Task 13), `useAcademySettings`/`useUpdateAcademySettings` (Task 12), `CURRENCIES`, `timezoneOptions`.
- Produces: `<ParentsList>`, `<ParentForm personId>`, `<TeachersList>`, `<TeacherForm personId>`, `<AdminsList>` (inline account actions + "Invite admin" dialog), `<AcademySettingsForm>`. Routes `/people/parents[/$personId]`, `/people/teachers[/$personId]`, `/people/admins`, `/settings/academy` (admin only).

- [ ] **Step 1: Write the failing tests**

`src/features/people/TeacherForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { TeacherForm } from "./TeacherForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, get: vi.fn(), create: vi.fn(), update: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

describe("TeacherForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC", default_currency: "EGP", default_language: "en" });
		vi.mocked(catalogueApi.list).mockResolvedValue({
			count: 1, next: null, previous: null,
			results: [{ id: 4, name_ar: "تجويد", name_en: "Tajweed", description_ar: "", description_en: "", language: "ar", is_active: true, teacher_ids: [] }],
		});
	});

	it("requires gender and payout details when a payout method is chosen", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TeacherForm personId="new" />);
		await user.type(await screen.findByLabelText(/full name/i), "Maryam");
		await user.selectOptions(screen.getByLabelText("Payout method"), "wise");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("Choose male or female.")).toBeInTheDocument();
		expect(screen.getByText("Enter the payout details for this method.")).toBeInTheDocument();
		expect(peopleApi.create).not.toHaveBeenCalled();
	});

	it("creates a teacher with courses, pay currency from the academy", async () => {
		vi.mocked(peopleApi.create).mockResolvedValue({ id: 30 } as never);
		const user = userEvent.setup();
		renderWithRouter(<TeacherForm personId="new" />, { extraPaths: ["/people/teachers/$personId"] });
		await user.type(await screen.findByLabelText(/full name/i), "Maryam");
		await user.selectOptions(screen.getByLabelText("Gender"), "female");
		await user.click(await screen.findByLabelText("Tajweed"));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(peopleApi.create).toHaveBeenCalledWith(
				"teachers",
				expect.objectContaining({
					profile: expect.objectContaining({ gender: "female", pay_currency: "EGP", course_ids: [4], date_of_birth: null }),
				}),
			),
		);
	});
});
```

`src/features/people/TeachersList.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { TeachersList } from "./TeachersList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

describe("TeachersList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(catalogueApi.list).mockResolvedValue({
			count: 1, next: null, previous: null,
			results: [{ id: 4, name_ar: "تجويد", name_en: "Tajweed", description_ar: "", description_en: "", language: "ar", is_active: true, teacher_ids: [9] }],
		});
		vi.mocked(peopleApi.list).mockResolvedValue({
			count: 1, next: null, previous: null,
			results: [{
				id: 9, role: "teacher",
				user: { full_name: "Bilal", email: "b@x.test", phone: "", preferred_language: "ar", timezone: "UTC", is_active: true, account_state: "active", pending_email: "" },
				profile: { gender: "male", date_of_birth: null, bio: "", default_meeting_url: "", pay_currency: "EGP", payout_method: "", payout_details: "", course_ids: [4] },
			}],
		});
	});

	it("shows course names and filters by course", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TeachersList />);
		expect(await screen.findByText("Tajweed")).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Course"), "4");
		await waitFor(() =>
			expect(vi.mocked(peopleApi.list).mock.calls.at(-1)?.[1]).toMatchObject({ course: "4" }),
		);
	});
});
```

`src/features/people/ParentForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { ParentForm } from "./ParentForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, get: vi.fn(), update: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

describe("ParentForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC", default_currency: "EGP", default_language: "ar" });
		vi.mocked(peopleApi.get).mockResolvedValue({
			id: 3, role: "parent",
			user: { full_name: "Omar", email: "o@x.test", phone: "+201001234567", preferred_language: "ar", timezone: "UTC", is_active: true, account_state: "invited", pending_email: "" },
			profile: { has_whatsapp: false, notes: "", children: [{ id: 7, full_name: "Yusuf", email: null, phone: "" }] },
		});
	});

	it("shows children as links and saves WhatsApp", async () => {
		vi.mocked(peopleApi.update).mockResolvedValue({} as never);
		const user = userEvent.setup();
		renderWithRouter(<ParentForm personId="3" />, { extraPaths: ["/people/students/$personId"] });
		expect(await screen.findByRole("link", { name: "Yusuf" })).toBeInTheDocument();
		await user.click(screen.getByLabelText("Has WhatsApp"));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(peopleApi.update).toHaveBeenCalledWith("parents", 3, expect.objectContaining({ profile: { has_whatsapp: true, notes: "" } })),
		);
	});
});
```

`src/features/people/AdminsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { AdminsList } from "./AdminsList";
import { peopleApi } from "./api";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn(), create: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const admin = (id: number, name: string, blocked: "self" | "last_admin" | null) => ({
	id, role: "admin" as const, profile: {}, deactivation_blocked: blocked,
	user: { full_name: name, email: `${id}@x.test`, phone: "", preferred_language: "en" as const, timezone: "UTC", is_active: true, account_state: "active" as const, pending_email: "" },
});

describe("AdminsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "UTC", default_currency: "EGP", default_language: "ar" });
		vi.mocked(peopleApi.list).mockResolvedValue({ count: 2, next: null, previous: null, results: [admin(1, "Me", "self"), admin(2, "Huda", null)] });
	});

	it("disables deactivating yourself with the reason", async () => {
		renderWithRouter(<AdminsList />);
		const mine = (await screen.findByText("Me")).closest("li") as HTMLElement;
		expect(within(mine).getByRole("button", { name: "Deactivate" })).toBeDisabled();
		expect(within(mine).getByText("You can't deactivate your own account.")).toBeInTheDocument();
		const other = screen.getByText("Huda").closest("li") as HTMLElement;
		expect(within(other).getByRole("button", { name: "Deactivate" })).toBeEnabled();
	});

	it("invites a new admin", async () => {
		vi.mocked(peopleApi.create).mockResolvedValue(admin(3, "Salma", null));
		const user = userEvent.setup();
		renderWithRouter(<AdminsList />);
		await user.click(await screen.findByRole("button", { name: "Invite admin" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/full name/i), "Salma");
		await user.type(within(dialog).getByLabelText(/^email/i), "salma@x.test");
		await user.click(within(dialog).getByRole("button", { name: "Send invite" }));
		await waitFor(() =>
			expect(peopleApi.create).toHaveBeenCalledWith("admins", { user: expect.objectContaining({ email: "salma@x.test" }) }),
		);
	});

	it("requires an email to invite an admin", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AdminsList />);
		await user.click(await screen.findByRole("button", { name: "Invite admin" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/full name/i), "Salma");
		await user.click(within(dialog).getByRole("button", { name: "Send invite" }));
		expect(await within(dialog).findByText("An admin needs an email to sign in.")).toBeInTheDocument();
		expect(peopleApi.create).not.toHaveBeenCalled();
	});
});
```

`src/features/academy/AcademySettingsForm.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { Toaster } from "@/ui";
import { AcademySettingsForm } from "./AcademySettingsForm";
import { academyApi } from "./api";

vi.mock("./api", () => ({ academyApi: { get: vi.fn(), update: vi.fn() } }));

function renderForm() {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	render(
		<QueryClientProvider client={client}>
			<AcademySettingsForm />
			<Toaster />
		</QueryClientProvider>,
	);
}

describe("AcademySettingsForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({ timezone: "Africa/Cairo", default_currency: "EGP", default_language: "ar" });
	});

	it("loads and saves timezone, currency and language", async () => {
		vi.mocked(academyApi.update).mockResolvedValue({ timezone: "Asia/Riyadh", default_currency: "SAR", default_language: "en" });
		const user = userEvent.setup();
		renderForm();
		expect(await screen.findByDisplayValue("Africa/Cairo")).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Time zone"), "Asia/Riyadh");
		await user.selectOptions(screen.getByLabelText("Default currency"), "SAR");
		await user.selectOptions(screen.getByLabelText("Default language"), "en");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(academyApi.update).toHaveBeenCalledWith({ timezone: "Asia/Riyadh", default_currency: "SAR", default_language: "en" }),
		);
		expect(await screen.findByText("Saved.")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx pnpm@10 vitest run src/features/people src/features/academy`
Expected: FAIL (components not found).

- [ ] **Step 3: Implement**

`src/features/people/PeopleList.tsx` — widen the detail route type:

```ts
export type DetailTo =
	| "/people/students/$personId"
	| "/people/parents/$personId"
	| "/people/teachers/$personId";
```

`src/features/people/TeacherForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { FormProvider, useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { useCatalogue } from "@/features/catalogue/queries";
import type { Course } from "@/features/catalogue/schemas";
import { CURRENCIES } from "@/lib/currencies";
import { Alert, AlertDescription, Checkbox, Field, Input, Select, Spinner, SubmitButton, Textarea, toast } from "@/ui";
import { AccountActions } from "./AccountActions";
import { applyServerErrors } from "./form-errors";
import { usePerson, useSavePerson } from "./queries";
import {
	emptyUser,
	PAYOUT_METHODS,
	type Person,
	type TeacherFormValues,
	type TeacherProfile,
	teacherFormSchema,
	toUserPayload,
	userDefaults,
} from "./schemas";
import { UserFieldsSection } from "./UserFieldsSection";

function defaults(person: Person<TeacherProfile>): TeacherFormValues {
	const p = person.profile;
	return {
		user: userDefaults(person.user),
		profile: {
			gender: p.gender,
			date_of_birth: p.date_of_birth ?? "",
			bio: p.bio,
			default_meeting_url: p.default_meeting_url,
			pay_currency: p.pay_currency,
			payout_method: p.payout_method,
			payout_details: p.payout_details,
			course_ids: p.course_ids,
		},
	};
}

export function TeacherForm({ personId }: { personId: string }) {
	const { t, i18n } = useTranslation();
	const navigate = useNavigate();
	const isNew = personId === "new";
	const id = isNew ? undefined : Number(personId);
	const { data: person } = usePerson<TeacherProfile>("teachers", id);
	const { data: academy, isPending: academyPending } = useAcademySettings();
	const { data: courses } = useCatalogue<Course>("courses", { is_active: "true", page_size: 100 });
	const save = useSavePerson<TeacherProfile>("teachers", id);
	const methods = useForm<TeacherFormValues>({
		resolver: zodResolver(teacherFormSchema),
		values: isNew
			? academyPending
				? undefined
				: {
						user: emptyUser(academy),
						profile: {
							gender: "",
							date_of_birth: "",
							bio: "",
							default_meeting_url: "",
							pay_currency: academy?.default_currency ?? "USD",
							payout_method: "",
							payout_details: "",
							course_ids: [],
						},
					}
			: person
				? defaults(person)
				: undefined,
	});
	const { register, handleSubmit, control, setError, formState: { errors, isSubmitting } } = methods;
	const chosen = useController({ control, name: "profile.course_ids", defaultValue: [] });
	const pe = errors.profile;

	async function onSubmit(values: TeacherFormValues) {
		try {
			const saved = await save.mutateAsync({
				user: toUserPayload(values.user),
				profile: { ...values.profile, date_of_birth: values.profile.date_of_birth || null },
			});
			toast({ description: t("people.saved"), variant: "success" });
			if (isNew) navigate({ to: "/people/teachers/$personId", params: { personId: String(saved.id) } });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	if ((!isNew && !person) || (isNew && academyPending)) return <Spinner />;
	const isAr = i18n.language === "ar";

	return (
		<div className="flex flex-col gap-6">
			<FormProvider {...methods}>
				<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-6" noValidate>
					<UserFieldsSection />
					<div className="grid gap-4 sm:grid-cols-2">
						<Field id="profile.gender" label={t("people.field.gender")} error={pe?.gender?.message} required>
							<Select {...register("profile.gender")}>
								<option value="">—</option>
								<option value="male">{t("people.gender.male")}</option>
								<option value="female">{t("people.gender.female")}</option>
							</Select>
						</Field>
						<Field id="profile.date_of_birth" label={t("people.field.date_of_birth")}>
							<Input type="date" {...register("profile.date_of_birth")} />
						</Field>
						<Field id="profile.default_meeting_url" label={t("people.field.default_meeting_url")} error={pe?.default_meeting_url?.message}>
							<Input type="url" dir="ltr" {...register("profile.default_meeting_url")} />
						</Field>
						<Field id="profile.pay_currency" label={t("people.field.pay_currency")}>
							<Select dir="ltr" {...register("profile.pay_currency")}>
								{CURRENCIES.map((c) => (
									<option key={c} value={c}>
										{c}
									</option>
								))}
							</Select>
						</Field>
						<Field id="profile.payout_method" label={t("people.field.payout_method")}>
							<Select {...register("profile.payout_method")}>
								<option value="">—</option>
								{PAYOUT_METHODS.map((m) => (
									<option key={m} value={m}>
										{t(`people.payout.${m}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field id="profile.payout_details" label={t("people.field.payout_details")} error={pe?.payout_details?.message}>
							<Input {...register("profile.payout_details")} />
						</Field>
					</div>
					<Field id="profile.bio" label={t("people.field.bio")}>
						<Textarea rows={4} {...register("profile.bio")} />
					</Field>
					<fieldset className="flex flex-col gap-2">
						<legend className="text-sm font-medium">{t("people.field.courses")}</legend>
						{(courses?.results ?? []).map((course) => (
							<label key={course.id} htmlFor={`course-${course.id}`} className="flex items-center gap-2 text-sm">
								<Checkbox
									id={`course-${course.id}`}
									checked={chosen.field.value.includes(course.id)}
									onCheckedChange={(on) =>
										chosen.field.onChange(
											on ? [...chosen.field.value, course.id] : chosen.field.value.filter((x) => x !== course.id),
										)
									}
								/>
								{isAr ? course.name_ar : course.name_en}
							</label>
						))}
					</fieldset>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{errors.root.server.message}</AlertDescription>
						</Alert>
					) : null}
					<SubmitButton pending={isSubmitting} className="self-start">
						{t("people.save")}
					</SubmitButton>
				</form>
			</FormProvider>
			{person ? <AccountActions kind="teachers" person={person} /> : null}
		</div>
	);
}
```

`src/features/people/TeachersList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCatalogue } from "@/features/catalogue/queries";
import type { Course } from "@/features/catalogue/schemas";
import { Button, Select } from "@/ui";
import { AccountStateChip } from "./AccountActions";
import type { ListParams } from "./api";
import { type Column, PeopleList } from "./PeopleList";
import type { TeacherProfile } from "./schemas";

export function TeachersList() {
	const { t, i18n } = useTranslation();
	const [params, setParams] = useState<ListParams>({ page: 1 });
	const { data: courses } = useCatalogue<Course>("courses", { page_size: 100 });
	const isAr = i18n.language === "ar";
	const courseName = new Map((courses?.results ?? []).map((c) => [c.id, isAr ? c.name_ar : c.name_en]));
	const update = (patch: ListParams) => setParams({ ...params, page: 1, ...patch });

	const columns: Column<TeacherProfile>[] = [
		{ key: "name", header: t("people.columns.name"), cell: (p) => p.user.full_name },
		{ key: "gender", header: t("people.columns.gender"), cell: (p) => (p.profile.gender ? t(`people.gender.${p.profile.gender}`) : "—") },
		{ key: "courses", header: t("people.columns.courses"), cell: (p) => p.profile.course_ids.map((id) => courseName.get(id)).filter(Boolean).join("، ") || "—" },
		{ key: "account", header: t("people.columns.account"), cell: (p) => <AccountStateChip state={p.user.account_state} /> },
	];

	return (
		<PeopleList<TeacherProfile>
			kind="teachers"
			columns={columns}
			params={params}
			onParamsChange={setParams}
			detailTo="/people/teachers/$personId"
			emptyLabel={t("people.teachers.empty")}
			filters={
				<>
					<Select aria-label={t("people.filters.course")} className="w-auto" value={String(params.course ?? "")} onChange={(e) => update({ course: e.target.value })}>
						<option value="">{t("people.filters.anyCourse")}</option>
						{(courses?.results ?? []).map((c) => (
							<option key={c.id} value={String(c.id)}>
								{isAr ? c.name_ar : c.name_en}
							</option>
						))}
					</Select>
					<Select aria-label={t("people.field.gender")} className="w-auto" value={String(params.gender ?? "")} onChange={(e) => update({ gender: e.target.value })}>
						<option value="">{t("people.filters.anyGender")}</option>
						<option value="male">{t("people.gender.male")}</option>
						<option value="female">{t("people.gender.female")}</option>
					</Select>
					<Select aria-label={t("people.filters.active")} className="w-auto" value={String(params.is_active ?? "")} onChange={(e) => update({ is_active: e.target.value })}>
						<option value="">{t("people.filters.anyAccount")}</option>
						<option value="true">{t("people.account.active")}</option>
						<option value="false">{t("people.account.inactive")}</option>
					</Select>
				</>
			}
			actions={
				<Button asChild size="sm">
					<Link to="/people/teachers/$personId" params={{ personId: "new" }}>
						<Plus className="size-4" />
						{t("people.teachers.new")}
					</Link>
				</Button>
			}
		/>
	);
}
```

`src/features/people/ParentForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Link, useNavigate } from "@tanstack/react-router";
import { FormProvider, useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { Card, CardContent, CardHeader, CardTitle, Checkbox, Field, Spinner, SubmitButton, Textarea, toast } from "@/ui";
import { AccountActions } from "./AccountActions";
import { applyServerErrors } from "./form-errors";
import { usePerson, useSavePerson } from "./queries";
import { emptyUser, type ParentFormValues, type ParentProfile, parentFormSchema, toUserPayload, userDefaults } from "./schemas";
import { UserFieldsSection } from "./UserFieldsSection";

export function ParentForm({ personId }: { personId: string }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const isNew = personId === "new";
	const id = isNew ? undefined : Number(personId);
	const { data: person } = usePerson<ParentProfile>("parents", id);
	const { data: academy, isPending: academyPending } = useAcademySettings();
	const save = useSavePerson<ParentProfile>("parents", id);
	const methods = useForm<ParentFormValues>({
		resolver: zodResolver(parentFormSchema),
		values: isNew
			? academyPending
				? undefined
				: { user: emptyUser(academy), profile: { has_whatsapp: false, notes: "" } }
			: person
				? { user: userDefaults(person.user), profile: { has_whatsapp: person.profile.has_whatsapp, notes: person.profile.notes } }
				: undefined,
	});
	const whatsapp = useController({ control: methods.control, name: "profile.has_whatsapp", defaultValue: false });

	async function onSubmit(values: ParentFormValues) {
		try {
			const saved = await save.mutateAsync({ user: toUserPayload(values.user), profile: values.profile });
			toast({ description: t("people.saved"), variant: "success" });
			if (isNew) navigate({ to: "/people/parents/$personId", params: { personId: String(saved.id) } });
		} catch (error) {
			applyServerErrors(error, methods.setError);
		}
	}

	if ((!isNew && !person) || (isNew && academyPending)) return <Spinner />;

	return (
		<div className="flex flex-col gap-6">
			<FormProvider {...methods}>
				<form onSubmit={methods.handleSubmit(onSubmit)} className="flex flex-col gap-6" noValidate>
					<UserFieldsSection />
					<label htmlFor="profile.has_whatsapp" className="flex items-center gap-2 text-sm">
						<Checkbox id="profile.has_whatsapp" checked={whatsapp.field.value} onCheckedChange={whatsapp.field.onChange} />
						{t("people.field.has_whatsapp")}
					</label>
					<Field id="profile.notes" label={t("people.field.notes")}>
						<Textarea rows={4} {...methods.register("profile.notes")} />
					</Field>
					<SubmitButton pending={methods.formState.isSubmitting} className="self-start">
						{t("people.save")}
					</SubmitButton>
				</form>
			</FormProvider>
			{person ? (
				<>
					<AccountActions kind="parents" person={person} />
					<Card>
						<CardHeader className="border-b border-border">
							<CardTitle>{t("people.parents.children")}</CardTitle>
						</CardHeader>
						<CardContent>
							{person.profile.children.length === 0 ? (
								<p className="text-sm text-muted-foreground">{t("people.parents.noChildren")}</p>
							) : (
								<ul className="flex flex-col gap-2">
									{person.profile.children.map((child) => (
										<li key={child.id}>
											<Link to="/people/students/$personId" params={{ personId: String(child.id) }} className="text-primary-text underline-offset-4 hover:underline">
												{child.full_name}
											</Link>
										</li>
									))}
								</ul>
							)}
						</CardContent>
					</Card>
				</>
			) : null}
		</div>
	);
}
```

Children are linked from the student's Guardians panel (spec §6: the student form links parents). The parent form lists the children and links to each one.

`src/features/people/ParentsList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Button, Select } from "@/ui";
import { AccountStateChip } from "./AccountActions";
import type { ListParams } from "./api";
import { type Column, PeopleList } from "./PeopleList";
import type { ParentProfile } from "./schemas";

export function ParentsList() {
	const { t } = useTranslation();
	const [params, setParams] = useState<ListParams>({ page: 1 });
	const update = (patch: ListParams) => setParams({ ...params, page: 1, ...patch });
	const columns: Column<ParentProfile>[] = [
		{ key: "name", header: t("people.columns.name"), cell: (p) => p.user.full_name },
		{ key: "phone", header: t("people.columns.phone"), cell: (p) => <span dir="ltr">{p.user.phone || "—"}</span> },
		{ key: "whatsapp", header: t("people.columns.whatsapp"), cell: (p) => t(p.profile.has_whatsapp ? "people.yes" : "people.no") },
		{ key: "children", header: t("people.columns.children"), cell: (p) => p.profile.children.map((c) => c.full_name).join("، ") || "—" },
		{ key: "account", header: t("people.columns.account"), cell: (p) => <AccountStateChip state={p.user.account_state} /> },
	];
	return (
		<PeopleList<ParentProfile>
			kind="parents"
			columns={columns}
			params={params}
			onParamsChange={setParams}
			detailTo="/people/parents/$personId"
			emptyLabel={t("people.parents.empty")}
			filters={
				<>
					<Select aria-label={t("people.columns.whatsapp")} className="w-auto" value={String(params.has_whatsapp ?? "")} onChange={(e) => update({ has_whatsapp: e.target.value })}>
						<option value="">{t("people.filters.anyWhatsapp")}</option>
						<option value="true">{t("people.yes")}</option>
						<option value="false">{t("people.no")}</option>
					</Select>
					<Select aria-label={t("people.filters.active")} className="w-auto" value={String(params.is_active ?? "")} onChange={(e) => update({ is_active: e.target.value })}>
						<option value="">{t("people.filters.anyAccount")}</option>
						<option value="true">{t("people.account.active")}</option>
						<option value="false">{t("people.account.inactive")}</option>
					</Select>
				</>
			}
			actions={
				<Button asChild size="sm">
					<Link to="/people/parents/$personId" params={{ personId: "new" }}>
						<Plus className="size-4" />
						{t("people.parents.new")}
					</Link>
				</Button>
			}
		/>
	);
}
```

`src/features/people/AdminsList.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { Button, Card, CardContent, Dialog, DialogClose, DialogContent, DialogFooter, DialogTitle, DialogTrigger, Spinner, toast } from "@/ui";
import { AccountActions } from "./AccountActions";
import { applyServerErrors } from "./form-errors";
import { usePeople, useSavePerson } from "./queries";
import { type AdminFormValues, adminFormSchema, emptyUser, toUserPayload } from "./schemas";
import { UserFieldsSection } from "./UserFieldsSection";

const inviteSchema = adminFormSchema.refine((v) => v.user.email.trim() !== "", {
	path: ["user", "email"],
	message: "An admin needs an email to sign in.",
});

export function AdminsList() {
	const { t } = useTranslation();
	const { data, isPending } = usePeople<Record<string, never>>("admins", { page_size: 100 });
	return (
		<div className="flex flex-col gap-4">
			<InviteAdminDialog />
			{isPending ? (
				<Spinner />
			) : (
				<ul className="flex flex-col gap-2">
					{(data?.results ?? []).map((admin) => (
						<li key={admin.id}>
							<Card>
								<CardContent className="flex flex-wrap items-start justify-between gap-4">
									<div className="flex flex-col gap-1">
										<span className="font-medium">{admin.user.full_name}</span>
										<span className="text-sm text-muted-foreground">{admin.user.email}</span>
									</div>
									<AccountActions kind="admins" person={admin} compact />
								</CardContent>
							</Card>
						</li>
					))}
				</ul>
			)}
		</div>
	);
}

function InviteAdminDialog() {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const save = useSavePerson("admins");
	const methods = useForm<AdminFormValues>({
		resolver: zodResolver(inviteSchema),
		values: { user: emptyUser(academy) },
	});

	async function onSubmit(values: AdminFormValues) {
		try {
			await save.mutateAsync({ user: toUserPayload(values.user) });
			toast({ description: t("people.account.inviteSent"), variant: "success" });
			methods.reset();
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, methods.setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" className="self-end">
					{t("people.admins.invite")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("people.admins.invite")}</DialogTitle>
				<FormProvider {...methods}>
					<form onSubmit={methods.handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
						<UserFieldsSection />
						<DialogFooter className="mt-0">
							<DialogClose asChild>
								<Button type="button" variant="outline">
									{t("people.cancel")}
								</Button>
							</DialogClose>
							<Button type="submit" disabled={methods.formState.isSubmitting}>
								{t("people.account.sendInvite")}
							</Button>
						</DialogFooter>
					</form>
				</FormProvider>
			</DialogContent>
		</Dialog>
	);
}
```

`src/features/academy/AcademySettingsForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { parseApiError } from "@/features/identity/api";
import { CURRENCIES } from "@/lib/currencies";
import { timezoneOptions } from "@/lib/timezones";
import { Field, Select, Spinner, SubmitButton, toast } from "@/ui";
import { useAcademySettings, useUpdateAcademySettings } from "./queries";

const schema = z.object({
	timezone: z.string().min(1),
	default_currency: z.string().regex(/^[A-Z]{3}$/),
	default_language: z.enum(["ar", "en"]),
});
type Values = z.infer<typeof schema>;

export function AcademySettingsForm() {
	const { t } = useTranslation();
	const { data } = useAcademySettings();
	const update = useUpdateAcademySettings();
	const { register, handleSubmit, setError, formState: { errors, isSubmitting } } = useForm<Values>({
		resolver: zodResolver(schema),
		values: data
			? { timezone: data.timezone, default_currency: data.default_currency, default_language: data.default_language }
			: undefined,
	});

	async function onSubmit(values: Values) {
		try {
			await update.mutateAsync(values);
			toast({ description: t("people.saved"), variant: "success" });
		} catch (error) {
			for (const [field, message] of Object.entries(parseApiError(error).fieldErrors)) {
				setError(field as keyof Values, { message });
			}
		}
	}

	if (!data) return <Spinner />;
	const currencies = CURRENCIES.includes(data.default_currency as (typeof CURRENCIES)[number])
		? [...CURRENCIES]
		: [data.default_currency, ...CURRENCIES];

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex max-w-md flex-col gap-4" noValidate>
			<Field id="timezone" label={t("academySettings.timezone")} error={errors.timezone?.message}>
				<Select dir="ltr" {...register("timezone")}>
					{timezoneOptions(data.timezone).map((zone) => (
						<option key={zone} value={zone}>
							{zone}
						</option>
					))}
				</Select>
			</Field>
			<Field id="default_currency" label={t("academySettings.currency")} error={errors.default_currency?.message}>
				<Select dir="ltr" {...register("default_currency")}>
					{currencies.map((c) => (
						<option key={c} value={c}>
							{c}
						</option>
					))}
				</Select>
			</Field>
			<Field id="default_language" label={t("academySettings.language")} error={errors.default_language?.message}>
				<Select {...register("default_language")}>
					<option value="ar">العربية</option>
					<option value="en">English</option>
				</Select>
			</Field>
			<p className="text-sm text-muted-foreground">{t("academySettings.hint")}</p>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
		</form>
	);
}
```

Routes (same shape as Task 12's, each calling `usePageTitle` and rendering a `PageHeader`):
- `people.parents.index.tsx` → `/_authed/people/parents/` → `<ParentsList />` (title `nav.parents`)
- `people.parents.$personId.tsx` → `<ParentForm personId={personId} />` (titles `people.parents.new` / `people.parents.edit`)
- `people.teachers.index.tsx` → `<TeachersList />`; `people.teachers.$personId.tsx` → `<TeacherForm personId={personId} />`
- `people.admins.tsx` → `/_authed/people/admins` → `<AdminsList />` (title `nav.admins`)
- `settings.academy.tsx` → `createFileRoute("/_authed/settings/academy")({ beforeLoad: ({ context }) => requireAdmin(context), component: … <PageContainer><PageHeader title={t("nav.academy")} description={t("academySettings.subtitle")} /><AcademySettingsForm /></PageContainer> })`

Locales — merge into `people` (en):

```json
{
	"filters": { "course": "Course" },
	"parents": {
		"new": "New parent",
		"edit": "Parent",
		"empty": "No parents yet.",
		"children": "Children",
		"noChildren": "No children linked. Link a parent from the student's page."
	},
	"teachers": { "new": "New teacher", "edit": "Teacher", "empty": "No teachers yet." },
	"admins": { "invite": "Invite admin" },
	"payout": {
		"vodafone_cash": "Vodafone Cash",
		"instapay": "InstaPay",
		"bank_account": "Bank account",
		"mashreq_neo": "Mashreq Neo",
		"western_union": "Western Union",
		"wise": "Wise",
		"paypal": "PayPal",
		"telda": "Telda",
		"abu_dhabi_bank": "Abu Dhabi Bank",
		"cash": "Cash",
		"stc_pay": "STC Pay"
	}
}
```

plus a new top-level block `"academySettings": { "subtitle": "Defaults for new people and packages.", "timezone": "Time zone", "currency": "Default currency", "language": "Default language", "hint": "New people get this language and time zone unless you choose others; new teachers are paid in this currency." }`.

(ar) `people`:

```json
{
	"filters": { "course": "الدورة" },
	"parents": {
		"new": "ولي أمر جديد",
		"edit": "ولي الأمر",
		"empty": "لا يوجد أولياء أمور بعد.",
		"children": "الأبناء",
		"noChildren": "لا يوجد أبناء مرتبطون. اربط ولي الأمر من صفحة الطالب."
	},
	"teachers": { "new": "معلم جديد", "edit": "المعلم", "empty": "لا يوجد معلمون بعد." },
	"admins": { "invite": "دعوة مشرف" },
	"payout": {
		"vodafone_cash": "فودافون كاش",
		"instapay": "إنستاباي",
		"bank_account": "حساب بنكي",
		"mashreq_neo": "مشرق نيو",
		"western_union": "ويسترن يونيون",
		"wise": "وايز",
		"paypal": "باي بال",
		"telda": "تلدا",
		"abu_dhabi_bank": "بنك أبوظبي",
		"cash": "نقدًا",
		"stc_pay": "STC Pay"
	}
}
```

and `"academySettings": { "subtitle": "القيم الافتراضية للأشخاص والباقات الجديدة.", "timezone": "المنطقة الزمنية", "currency": "العملة الافتراضية", "language": "اللغة الافتراضية", "hint": "يحصل الأشخاص الجدد على هذه اللغة والمنطقة الزمنية ما لم تختر غيرهما، ويُدفع للمعلمين الجدد بهذه العملة." }`.

Export the new components from `src/features/people/index.ts` and `AcademySettingsForm` from `src/features/academy/index.ts`.

- [ ] **Step 4: Verify**

Run: `npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage`
Expected: all pass, floors hold.

Check by hand in the running stack (`just dev`). Sign in as `admin@demo.test` / `e2e-EtqanTest-2026` on `http://demo.etqan.localhost/app/`. Each People, Catalogue and Settings page should load with the seeded data, switch to Arabic (RTL), and show no horizontal page scroll at 375 px width, apart from the tables' own scroll areas.

- [ ] **Step 5: Commit, push**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): parents, teachers, admins and academy settings screens

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C dashboard push -u origin feat/people-catalogue
```

---

### Task 15: End-to-end through Caddy, CI mail wiring, STATE.md

**Files:**
- Create: `dashboard/e2e/mail.ts`, `dashboard/e2e/people-catalogue.spec.ts`
- Modify: `.github/workflows/ci.yml` (meta, `e2e` job), `STATE.md` (meta), submodule pointers (meta)

**Interfaces:**
- Consumes: everything above; `seed_dev` (Task 10); `CELERY_TASK_ALWAYS_EAGER`, `DJANGO_EMAIL_FILE_PATH` settings (Task 10); the existing `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD` from `e2e/fixtures.ts`.
- Produces: `latestLink(address: string, pattern: RegExp) -> Promise<string>` in `e2e/mail.ts` (reads `E2E_MAIL_DIR` files, else Mailpit at `E2E_MAILPIT_URL`, default `http://localhost:8025`); the e2e spec from spec §8.

- [ ] **Step 1: Write the e2e spec** — `dashboard/e2e/mail.ts`

```ts
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const MAIL_DIR = process.env.E2E_MAIL_DIR;
const MAILPIT = process.env.E2E_MAILPIT_URL ?? "http://localhost:8025";

function fromDir(address: string): string {
	if (!MAIL_DIR) return "";
	const files = readdirSync(MAIL_DIR)
		.map((name) => join(MAIL_DIR, name))
		.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
	for (const file of files) {
		const text = readFileSync(file, "utf8");
		if (text.includes(`To: ${address}`)) return text;
	}
	return "";
}

async function fromMailpit(address: string): Promise<string> {
	const search = await fetch(
		`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${address}"`)}`,
	);
	if (!search.ok) return "";
	const { messages = [] } = (await search.json()) as { messages?: { ID: string }[] };
	if (!messages[0]) return "";
	const message = await fetch(`${MAILPIT}/api/v1/message/${messages[0].ID}`);
	return message.ok ? ((await message.json()) as { Text: string }).Text : "";
}

/** The first link matching `pattern` in the newest email to `address`. */
export async function latestLink(address: string, pattern: RegExp): Promise<string> {
	for (let attempt = 0; attempt < 30; attempt++) {
		const text = MAIL_DIR ? fromDir(address) : await fromMailpit(address);
		const match = text.match(pattern);
		if (match) return match[0];
		await new Promise((resolve) => setTimeout(resolve, 500));
	}
	throw new Error(`No email with a matching link reached ${address}`);
}
```

`dashboard/e2e/people-catalogue.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { latestLink } from "./mail";

const INVITE = /http:\/\/[^\s"<]+\/app\/reset-password\?uid=[^\s"<&]+&token=[^\s"<]+/;

// Spec §8: the admin sets up a teacher linked to a course, a package, a parent and
// a student; the student's invite sets a password and they see only their profile.
test("an admin sets up people and catalogue, and the invited student signs in", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const teacher = `E2E Teacher ${stamp}`;
	const parent = `E2E Parent ${stamp}`;
	const student = `E2E Student ${stamp}`;
	const studentEmail = `e2e-student-${stamp}@e2e.test`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Teacher
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/full name/i).fill(teacher);
	await page.getByLabel("Gender").selectOption("male");
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);

	// Course linked to the teacher
	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel("Name (Arabic)").fill(`دورة ${stamp}`);
	await page.getByLabel("Name (English)").fill(`E2E Course ${stamp}`);
	await page.getByLabel(teacher).click();
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);
	await expect(page.getByText(`E2E Course ${stamp}`)).toBeVisible();

	// The teacher's list row shows the course
	await page.goto(`${DEMO_URL}/app/people/teachers`);
	await page.getByRole("searchbox").fill(teacher);
	await expect(page.getByRole("row", { name: new RegExp(teacher) })).toContainText(
		`E2E Course ${stamp}`,
	);

	// Package with a live total
	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel("Name (Arabic)").fill(`باقة ${stamp}`);
	await page.getByLabel("Name (English)").fill(`E2E Package ${stamp}`);
	await page.getByLabel("Sessions per week").fill("3");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await expect(page.getByText("12 sessions in total")).toBeVisible();
	await page.getByLabel("Price").fill("600");
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page.getByText(`E2E Package ${stamp}`)).toBeVisible();

	// Parent, then a student linked to them, then the invite
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/full name/i).fill(parent);
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/full name/i).fill(student);
	await page.getByLabel(/^email/i).fill(studentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	await page.getByLabel("Find a parent").fill(parent);
	await page.getByRole("button", { name: `Link ${parent}` }).click();
	await expect(
		page.getByRole("button", { name: `Unlink ${parent}` }),
	).toBeVisible();
	await expect(page.getByText("Invite pending")).toBeVisible();
	await page.getByRole("button", { name: "Send invite" }).click();
	await expect(page.getByText("Invite sent.")).toBeVisible();

	// The student uses the emailed link, sets a password and signs in
	const link = await latestLink(studentEmail, INVITE);
	const context = await browser.newContext();
	const kid = await context.newPage();
	await kid.goto(link);
	await kid.getByLabel("New password").fill("e2e-Student-2026");
	await kid.getByRole("button", { name: "Reset password" }).click();
	await expect(kid.getByText(/you can now sign in/i)).toBeVisible();
	await kid.goto(`${DEMO_URL}/app/login`);
	await kid.getByRole("textbox", { name: /email/i }).fill(studentEmail);
	await kid.getByRole("textbox", { name: /password/i }).fill("e2e-Student-2026");
	await kid.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(kid, new RegExp(student));

	// Only their own profile: no People/Catalogue nav, admin pages bounce home
	await expect(kid.getByRole("link", { name: "Students" })).toHaveCount(0);
	await kid.goto(`${DEMO_URL}/app/account`);
	await expect(kid.getByText("My profile")).toBeVisible();
	await kid.goto(`${DEMO_URL}/app/people/students`);
	await expect(kid).toHaveURL(/\/app\/?$/);
	await context.close();
});
```

- [ ] **Step 2: Wire mail into the CI e2e job** — in `.github/workflows/ci.yml`, job `e2e`:
  - in `env:` add `CELERY_TASK_ALWAYS_EAGER: "true"` and `DJANGO_EMAIL_FILE_PATH: /tmp/etqan-mail`, and change `DJANGO_EMAIL_BACKEND` to `django.core.mail.backends.filebased.EmailBackend`;
  - in the Playwright step's `env:` add `E2E_MAIL_DIR: /tmp/etqan-mail`;
  - in the `Backend up with seeded academies` step, add `mkdir -p /tmp/etqan-mail` before `seed_dev`.

- [ ] **Step 3: Run the e2e suite locally against the Caddy stack**

```bash
just migrate && just seed
just dev-backend
cd dashboard && E2E_MAILPIT_URL=http://localhost:8025 npx pnpm@10 e2e
```

Expected: `people-catalogue.spec.ts`, `academy-sites.spec.ts` and `tenant-login.spec.ts` all pass. The `seed_dev` output must also show the demo academy's people. If the local stack uses a non-default Mailpit port, set `E2E_MAILPIT_URL` to match `ETQAN_MAIL_UI_PORT`.

- [ ] **Step 4: Update `STATE.md`** — replace "Where we are" / "Next" with:

```markdown
## Where we are

Plan 3 (people & catalogue, B0 milestone 3) in review: branch `feat/people-catalogue` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-24-people-catalogue-design.md`, plan
`docs/superpowers/plans/2026-09-24-plan-3-people-catalogue.md`). Admins manage students, parents,
teachers, admins, courses, packages and academy settings; invites arrive in each person's language.
Self-registration and parent-created children are gone (returns in B9).

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 4: subscriptions, weekly slots and session generation. It must call
`etqan.catalogue.services.sessions_total` and add the "course/package has subscriptions" delete guard.
```

- [ ] **Step 5: Commit (dashboard first, then meta with the pointers), open PRs**

```bash
git -C dashboard add e2e
git -C dashboard commit -m "test(e2e): admin sets up people and catalogue; invited student signs in

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C dashboard push
git add .github/workflows/ci.yml STATE.md backend dashboard
git commit -m "chore: people & catalogue e2e mail wiring, state, submodule pointers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/people-catalogue
```

Open one PR per repo: backend → `main`, dashboard → `main`, meta → `master`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Nothing merges without the user's approval. After the submodule PRs merge, bump the meta pointers to the merge commits and push.
