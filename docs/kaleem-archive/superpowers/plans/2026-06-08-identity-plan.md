---
spec: docs/superpowers/specs/2026-06-08-identity-module.md
status: done
---

## Overview

Build the `kaleem.identity` module from scratch using TDD. Every step: write failing test first,
then the code, then verify green. Each step is ≤2h of focused work.

Dependency: Phase 0 bootstrap must be complete (Django scaffold, Postgres running, pre-commit
hooks installed). Check with `just test-backend` before starting.

---

## Steps

### Step 1 — Module scaffold and custom User model
- [x] Run `just new-module identity` to create the directory skeleton.
- [x] Create `kaleem/identity/apps.py` with `IdentityConfig`.
- [x] Create `kaleem/identity/models.py` with a custom `User` model:
  - Extends `AbstractBaseUser` + `PermissionsMixin`.
  - `email` as `USERNAME_FIELD` (unique). No `username` field.
  - Fields: `email`, `full_name`, `is_active`, `is_staff`, `date_joined`.
  - Custom `UserManager` with `create_user` and `create_superuser`.
- [x] Set `AUTH_USER_MODEL = "identity.User"` in `config/settings/base.py`.
- [x] Write and run the initial migration.
- [x] **Tests:** `test_user_creation`, `test_superuser_creation`, `test_email_is_username`.
- [x] Verify: `pytest kaleem/identity/tests/test_models.py` green.

### Step 2 — Profile models and ParentStudent link
- [x] Add to `kaleem/identity/models.py`:
  - `StudentProfile`: `user` (OneToOne), `time_preferences` (JSONField),
    `teacher_gender_preference` (CharField, choices), `notes` (TextField, blank).
  - `TeacherProfile`: `user` (OneToOne), `availability` (JSONField),
    `is_in_pool` (bool, default False), `internal_notes` (TextField, blank).
  - `ParentProfile`: `user` (OneToOne).
  - `ParentInvite`: `parent` (FK→ParentProfile), `code` (CharField, unique),
    `expires_at` (DateTimeField), `used` (bool, default False).
  - `ParentStudent`: `parent` (FK→ParentProfile), `student` (FK→StudentProfile),
    `created_at` (DateTimeField). `unique_together(parent, student)`.
- [x] Write and run migrations.
- [x] **Tests:** profile creation, ParentStudent link, invite expiry logic,
  duplicate ParentStudent raises IntegrityError.
- [x] Verify: all tests green.

### Step 3 — Services layer
- [x] Create `kaleem/identity/services.py` with:
  - `get_user(user_id: int) → User`
  - `get_student_profile(user_id: int) → StudentProfile | None`
  - `get_teacher_profile(user_id: int) → TeacherProfile | None`
  - `get_parent_profile(user_id: int) → ParentProfile | None`
  - `get_children(parent_user_id: int) → QuerySet[StudentProfile]`
  - `is_parent_of(parent_user_id: int, student_user_id: int) → bool`
  - `create_child(parent_user_id: int, full_name: str, preferences: dict) → StudentProfile`
    Creates User + StudentProfile + ParentStudent atomically.
  - `create_invite(parent_user_id: int) → ParentInvite`
    Expires any existing unused invite first. Sets expiry to 24h from now.
  - `accept_invite(student_user_id: int, code: str) → ParentStudent`
    Validates code not expired, not used, student has no existing parent.
    Raises typed exceptions on failure.
- [x] **Tests:** one test per service function covering happy path + key failure cases.
- [x] Verify: all tests green. Run `lint-imports` — no boundary violations.

### Step 4 — allauth wiring and registration API
- [x] Configure allauth in settings: email-only auth, mandatory verification,
  no username, custom `User` model.
- [x] Create `kaleem/identity/api/serializers.py`:
  - `RegisterSerializer`: validates email uniqueness, hashes password,
    `account_type` field (student | parent).
  - `LoginSerializer`: wraps allauth authenticate.
  - `MeSerializer`: returns user + profile list + children (if parent).
  - `StudentProfileSerializer`: time_preferences + teacher_gender_preference.
  - `ChildCreateSerializer`: full_name + preferences.
- [x] Create `kaleem/identity/api/views.py`:
  - `RegisterView` (POST) — creates User + correct Profile, triggers email verification.
  - `LoginView` (POST) — authenticates, sets session cookie.
  - `LogoutView` (POST) — clears session.
  - `MeView` (GET, PATCH) — current user info + update.
  - `StudentProfileView` (POST) — set/update StudentProfile preferences.
- [x] Wire into `config/api_router.py`.
- [x] **Tests:** full request-level tests for each endpoint (happy path + edge cases
  from the spec test plan). Use `pytest-django`'s `Client`.
- [x] Verify: all tests green, `ruff check`, `mypy kaleem/identity/`.

### Step 5 — Children and invite API
- [x] Add views:
  - `ChildListCreateView` (GET, POST) — parent lists/adds children.
  - `ChildSetPasswordView` (POST) — parent sets child password.
  - `InviteCreateView` (POST) — parent generates invite code.
  - `InviteAcceptView` (POST) — student accepts invite code.
- [x] **Tests:** parent adds child via POST, child appears in GET. Parent generates
  invite, student accepts, ParentStudent created. Expired invite returns 400.
  Student with existing parent cannot accept a second invite.
- [x] Verify: all tests green.

### Step 6 — Admin registration (teacher account creation)
- [x] Add a Django admin action: create a teacher account (email → sends
  password-set email → `TeacherProfile` created with `is_in_pool=False`).
- [x] Register `User`, `StudentProfile`, `TeacherProfile`, `ParentProfile`,
  `ParentStudent`, `ParentInvite` in `kaleem/identity/admin.py`.
- [x] **Tests:** admin can create teacher account via `create_teacher_account` service function.
- [x] Verify: log in to Django admin at `/admin/`, confirm all models visible.

### Step 7 — Import-linter contract
- [x] Add contract to `pyproject.toml`:
  ```toml
  [[tool.importlinter.contracts]]
  name = "identity imports no other business modules"
  type = "independence"
  modules = ["kaleem.identity"]
  ```
- [x] Run `lint-imports` — must pass.
- [x] Verify: intentionally import `kaleem.platform` from identity → confirm linter
  catches it → revert.

### Step 8 — Coverage check and final cleanup
- [x] Run `pytest --cov=kaleem/identity --cov-report=term-missing`.
- [x] Target: ≥80% coverage on `models.py` and `services.py`.
- [x] Fill any gaps with missing tests (focus on services).
- [x] Run full suite: `just test` — all green.
- [x] Run `just lint` — all clean.
- [x] Commit with message: `feat: identity module (User, profiles, parent-child, auth, invite flow)`.

---

## Risks

| Risk | Likelihood | Fallback |
|---|---|---|
| allauth conflicts with custom User model | Medium | Follow allauth headless setup docs; custom User is a supported pattern |
| JSONField for time_preferences gets messy | Low | If validation is complex, extract to a separate `TimeSlot` model in Phase C |
| Email verification blocks local testing | Low | Set `ACCOUNT_EMAIL_VERIFICATION = "none"` in `test.py` settings |
| `AUTH_USER_MODEL` change breaks existing migrations | Low | Phase 0 has no data; drop and recreate DB if needed |

---

## Verification

Each step is verified immediately after completion (tests green + linters clean).

Full phase verified when:
- [x] `just test` passes (all identity tests + platform tests).
- [x] `just lint` passes (ruff, mypy, import-linter).
- [x] Manual smoke test: register as student → verify email → log in → `GET /api/identity/me/`
  returns correct payload.
- [x] Manual smoke test: register as parent → add child → generate invite → log in as child
  → accept invite → child appears in parent's children list.
- [x] Django admin: create a teacher account → teacher receives password-set email.
- [x] Coverage report: ≥80% on services and models.
