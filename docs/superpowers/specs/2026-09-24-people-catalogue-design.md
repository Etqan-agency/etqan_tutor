# Plan 3 — People & Catalogue — Design

**Date:** 2026-09-24
**Status:** Approved in brainstorming (sections 1–4), pending written-spec review.
**Phase:** B0, milestone 3 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`).
**Builds on:** v1 spec §4.1–4.3, §6.1–6.4 (`2026-09-23-etqan-tutor-v1-design.md`); academy-sites spec (branding, branded emails, dashboard under `/app/`).
**Evidence:** TutorHamster field inventories in `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §2.1 (PEOPLE-001…008) and §2.2 (CATALOG-001, CATALOG-003). Roadmap rule R4 applies: TutorHamster names and option lists are used wherever that costs nothing; scope does not otherwise grow.

## 1. Goal

An academy admin can set up everything the timetable will later need: students, parents (linked to their children), teachers (linked to the courses they teach), admins, courses, packages and the academy's own settings. Everyone the admin creates with an email receives a branded invite in their own language and can sign in to `/app/`. Non-admins see only their own profile until Plan 4.

## 2. Decisions

| # | Decision |
|---|---|
| P3-1 | Sign-in is **email + password only**. Phone is a contact field. A student may exist without an email and then has no login. |
| P3-2 | Accounts are **created by admins only**. Kaleem's self-registration (`identity/register/`), parent-created children (`identity/children/…`) and parent invite codes (`identity/invites/…`) are removed; self-registration returns in B9. |
| P3-3 | New accounts receive a **set-password invite** (no admin-typed passwords). Admins can resend the invite, send a password-reset link, deactivate and reactivate. |
| P3-4 | **One role per account** (`admin · teacher · student · parent`), as v1 §4.2. Several admins per academy. An admin cannot deactivate themselves; the last active admin cannot be deactivated. |
| P3-5 | People are **deactivated, never deleted**. Courses and packages are deactivated rather than deleted once referenced (in Plan 3: a course with teachers may still be deleted; Plan 4 adds the subscription check). |
| P3-6 | Teachers are linked to the **courses they teach** (TutorHamster CATALOG-001 "teachers" multi-select, required there; optional here so a course can exist before its teachers). |
| P3-7 | Package duration uses TutorHamster's units: **number + `day · month`**. `weeks = ceil(days / 7)` for days; a month counts as **4 weeks**. `sessions_total = sessions_per_week × weeks`. Plan 4's subscription arithmetic must use this same function. |
| P3-8 | Users get **`preferred_language` (`ar · en`)**. All identity emails are rendered in the recipient's language, and the From display name and subject prefix use the academy name in that language. This replaces academy-sites decision P2 ("English name until a user locale exists"). |
| P3-9 | Academy settings in this plan are only **timezone, default currency, default language**. The v1 §4.1 operating switches are added by the milestones that use them. Name, logo and colours stay in Plan 2's `Branding`. |

## 3. Data (tenant schema, app `etqan.identity` unless noted)

### 3.1 User (existing, adjusted)

| Field | Change |
|---|---|
| `email` | now `null=True, blank=True`, unique when present (case-insensitive). `USERNAME_FIELD` stays `email`; a user without email has an unusable password and `is_active` true or false as set by the admin but can never authenticate. |
| `full_name` | required (non-blank) for all roles created in this plan. |
| `phone` | **new**, E.164 string, optional, validated `^\+[1-9]\d{6,14}$`. |
| `preferred_language` | **new**, `ar · en`, default = academy default language. |
| `timezone` | existing; default becomes the academy's timezone at creation. |
| `role` | existing enum, required. |
| `birthdate` | moves to `StudentProfile.date_of_birth` / `TeacherProfile.date_of_birth` (data migrated), then dropped. |

### 3.2 Profiles

| Model | Fields |
|---|---|
| `StudentProfile` | `user` 1:1 · `date_of_birth` (optional) · `gender` `male · female` (optional) · `country` (ISO 3166-1 alpha-2, optional) · `status` `active · trial · in_progress · paused · inactive` (default `active`; TutorHamster PEOPLE-001 values) · `notes` |
| `TeacherProfile` | `user` 1:1 · `gender` `male · female` (required) · `date_of_birth` (optional) · `bio` · `default_meeting_url` (optional URL) · `pay_currency` (ISO 4217, default academy currency) · `payout_method` (optional; TutorHamster PEOPLE-005 list: `vodafone_cash · instapay · bank_account · mashreq_neo · western_union · wise · paypal · telda · abu_dhabi_bank · cash · stc_pay`) · `payout_details` (text, required when `payout_method` is set) |
| `ParentProfile` | `user` 1:1 · `has_whatsapp` (bool) · `notes` |
| `Guardianship` | `parent` → ParentProfile · `student` → StudentProfile · `created_at`; unique pair. Renamed from Kaleem's `ParentStudent` (data kept). |

Removed: `ParentInvite`, `TeacherProfile.is_in_pool`, `TeacherProfile.internal_notes` (its content is appended to `bio` by the data migration), `StudentProfile.teacher_gender_preference`.

Account active/inactive is `User.is_active`; student lifecycle status is `StudentProfile.status` and is independent of login (a paused student may still sign in).

### 3.3 Catalogue (new tenant app `etqan.catalogue`)

| Model | Fields |
|---|---|
| `Course` | `name_ar`, `name_en` (required) · `description_ar`, `description_en` (optional) · `language` `ar · en · both` · `teachers` M2M → TeacherProfile · `is_active` · timestamps |
| `Package` | `name_ar`, `name_en` (required) · `description_ar`, `description_en` (optional) · `sessions_per_week` (1–14) · `session_minutes` (15–240; the form offers 30 / 45 / 60 / other) · `duration_value` (1–365) · `duration_unit` `day · month` · `freeze_days_allowed` (0–365, default 0) · `price_minor` (≥ 0 int) · `currency` (ISO 4217) · `is_active` · timestamps. Derived, not stored: `sessions_total` (P3-7). |

The catalogue app talks to identity only through `etqan.identity.services` (teacher lookups); import-linter contract added.

### 3.4 Academy settings (new tenant app `etqan.academy`)

`AcademySettings` singleton: `timezone` (IANA), `default_currency` (ISO 4217), `default_language` (`ar · en`), timestamps. Created by `create_academy` from the `Academy` row's timezone and currency (language `ar`), and self-healed on first read for existing academies, like `Branding`.

## 4. Behaviour

### 4.1 Creating and inviting

`etqan.identity.services.create_person(role, *, full_name, email=None, phone=None, preferred_language=None, profile: dict, invite=True, created_by) -> User` creates user + profile atomically. With an email and `invite=True`, it sends the set-password invite (reusing the set-password token flow that `create_academy` uses for the first admin, link `app_url("/reset-password?...")`, branded, in the recipient's language).

- Duplicate email (case-insensitive) → validation error on `email`.
- Student without email: created with an unusable password; no invite. When an admin later adds an email, the invite is sent; the address counts as verified only once the invite link is used.
- Admins must have an email; an admin without one is refused on `email`.
- Changing an existing user's email (amended at merge to match plan decision D4):
  - Invited or never signed in (no password set yet): the address is replaced at once and a fresh invite goes to the new address. The old invite link stops working, because the set-password token hashes the email. A deactivated person gets no invite; the address still changes.
  - Signed in: the new address stays pending until its owner confirms it through the verification link. On confirmation it replaces the old address, which receives a security alert and stops working for sign-in and resets. Until then the old address keeps working.
- Invite links expire. An invited person whose link has expired can renew it through "Forgot password": for the unverified primary address of an active account that has never set a password, a fresh invite is sent instead of a reset link. The response is the same either way, so accounts cannot be enumerated.

Account actions (admin only): `resend_invite(user)`, `send_password_reset(user)`, `deactivate(user, by)`, `activate(user)`. `deactivate` refuses the acting admin themselves and the last active admin, and ends the user's sessions.

### 4.2 Guardianship

`link_guardian(parent, student)` / `unlink_guardian(parent, student)`; idempotent. The student form can link an existing parent or create a new parent inline (same `create_person` path).

### 4.3 Packages

`sessions_total(package) = sessions_per_week × weeks(duration_value, duration_unit)` with `weeks(n, "month") = 4n`, `weeks(n, "day") = ceil(n / 7)`. Lives in `etqan.catalogue.services` and is the only implementation.

### 4.4 Emails in the recipient's language

`etqan.site.emails.brand_email` gains `language` (`ar · en`) and uses `name_ar` / `name_en` accordingly for the From display name and subject prefix; the layout keeps both names. Every identity email passes the recipient's `preferred_language`. Email bodies exist in Arabic and English (Django templates per language). Public-schema emails keep `[Etqan]` in English.

### 4.5 Access

| Resource | Admin | Teacher | Parent | Student |
|---|---|---|---|---|
| Students / parents / teachers / admins (list, create, edit, account actions) | ✓ | – | – | – |
| Own user + own profile (`me/`) | ✓ | ✓ | ✓ | ✓ |
| Linked children's profiles | – | – | read | – |
| Courses, packages | ✓ CRUD | read active | – | – |
| Academy settings | ✓ | read | read | read |

One permission class per role plus a `scope_for(user, queryset)` function per resource, as v1 §6.1; out-of-scope objects return 404.

## 5. API (`/api/v1/`, existing conventions)

| Route | Methods | Notes |
|---|---|---|
| `people/students/` · `people/parents/` · `people/teachers/` · `people/admins/` | GET list (search `q` over name/email/phone; filters per resource: students `status, is_active, country, gender`; teachers `course, is_active, gender`; parents `is_active, has_whatsapp`), POST | nested `user` + `profile` payload |
| `people/<kind>/<id>/` | GET, PATCH | no DELETE |
| `people/<kind>/<id>/invite/` · `…/password-reset/` · `…/deactivate/` · `…/activate/` | POST | |
| `people/students/<id>/guardians/` | GET, POST `{parent_id}` | |
| `people/students/<id>/guardians/<parent_id>/` | DELETE | unlink only |
| `people/parents/<id>/children/` | GET | |
| `catalogue/courses/` · `catalogue/packages/` | GET (filter `is_active`, `q`), POST | |
| `catalogue/courses/<id>/` · `catalogue/packages/<id>/` | GET, PATCH, DELETE (DELETE only while unreferenced) | packages expose read-only `sessions_total` |
| `catalogue/courses/<id>/duplicate/` · `catalogue/packages/<id>/duplicate/` | POST | copy named "<name> (copy)", inactive |
| `academy/settings/` | GET, PATCH (admin) | |
| any admin list + `?format=csv` | GET | current filters applied; UTF-8 with BOM for Excel |
| `identity/me/` | existing | adds `phone`, `preferred_language`, role profile |

Removed: `identity/register/`, `identity/children/…`, `identity/invites/…` and their services/tests.

Bulk actions: `people/students/bulk/` POST `{ids, action: activate|deactivate|set_status, status?}`.

## 6. Dashboard (`/app/`, admin screens unless noted)

- **Navigation:** new groups **People** (Students, Parents, Teachers, Admins) and **Catalogue** (Courses, Packages), `requiresRole: "admin"`; **Settings → Academy** next to Website.
- **Students:** status tabs (active · trial · in progress · paused · inactive · all), search, filters, pagination, CSV export, bulk activate / deactivate / set status. Form: name, email (optional), phone, preferred language, timezone, date of birth, gender, country, status, notes; guardians panel (link existing / create new parent); account actions (send invite, send reset, deactivate/activate) with their current state ("invite sent", "active", "no login").
- **Parents:** list with children and WhatsApp columns; form with children links.
- **Teachers:** list with course filter; form with gender, bio, meeting link, pay currency, payout method + details, courses taught.
- **Admins:** list, invite admin, deactivate (with the self / last-admin guards shown as disabled buttons with a reason).
- **Courses / Packages:** list + form with `BilingualField`, active toggle, duplicate; package form shows `sessions_total` live using the same rule as the backend.
- **Academy settings:** timezone, currency, language.
- **My account (all roles):** adds phone and preferred language; changing preferred language switches the dashboard language.
- Arabic and English, RTL; lists responsive to phone width.

## 7. Migration and seeds

- Migrations are additive then cleaning, per academy via `migrate_schemas`: add fields/models → data migration (birthdate → profiles; `ParentStudent` → `Guardianship`; `AcademySettings` from `Academy`) → drop removed fields/models.
- `seed_dev`: demo gets 2 teachers (linked to courses), 2 courses, 2 packages (one `month`, one `day` duration), 2 parents (one with two children), 3 students (one without email); other gets a distinct smaller set.

## 8. Testing

- **Backend:** per endpoint × role (admin allowed; teacher/parent/student limited per §4.5; anonymous refused); cross-academy isolation; create/invite/resend/reset/deactivate; last-admin and self guards; email-less student cannot authenticate and gets an invite once an email is added; email change needs verification; duplicate email (case-insensitive); `sessions_total` for day and month units and edge values; CSV output respects filters and is Excel-readable; removed endpoints return 404; emails in `ar` and `en` with the right academy name. Coverage ≥ 80%.
- **Dashboard:** each list and form, bilingual fields, guardian linking, account-action states, live `sessions_total`; coverage floors unchanged; full `pnpm lint` passes.
- **E2E (through Caddy):** admin creates a teacher and a course and links them; creates a package; creates a parent and a student, links them and sends an invite; the invite email's link sets a password and the student signs in and sees only their own profile.

## 9. Risks

- Reshaping Kaleem's profile tables touches Plan 1 identity code; existing auth, reset and email-change tests must keep passing.
- Making `email` nullable affects allauth and every `user.email` use (display, `__str__`, emails). All call sites are checked; `__str__` falls back to `full_name`.
- P3-7 must be reused, not reimplemented, by Plan 4.

## 10. Out of scope (roadmap phase)

Family accounts and account type, groups, tags, XP, age group, nationality (B1); student balance, per-country prices, discount codes (B3); group packages, trial pipeline (B2); teacher contracts, ratings, home-page teachers, consultations (B4/B6/B7/B9); course pages, categories, SEO, images (B8); phone/OTP login, Google sign-in, self-registration, quick-login links (B9).
