# People

The academy's directory of accounts: admins, staff, teachers, students and parents, their role profiles, tags, guardian links and families. Academy admins and staff (with the right permission codes) manage everyone under People; every signed-in person reads and edits their own account under My account (`identity/me/`). Etqan staff never appear here: their accounts live in the `public` schema and only use the Django admin on the base domain.

## Concepts

All models below are in `etqan.identity`, which is in both `SHARED_APPS` and `TENANT_APPS`. Academy people live in each academy's schema. Etqan staff are `User` rows in `public` with `is_staff`/`is_superuser`.

| Model | Purpose |
|---|---|
| `User` | One account, one `role`: `admin`, `teacher`, `student`, `parent`, `staff`. Email is optional and unique case-insensitively (`NULL` when absent, so many students can have no email). No email means no login. Also holds `phone`, `preferred_language` (`ar`/`en`/`es`), `timezone`, `pending_email`, and the last-login fields (`last_login_ip`, `last_login_device`, `last_login_timezone`). |
| `StudentProfile` | One-to-one with a student: date of birth, gender, country, `status` (active / trial / in_progress / paused / inactive), notes, `xp` (0 to 1,000,000), nationality (arab / foreign), tags, and `family` (FK, at most one family). |
| `TeacherProfile` | Gender (required for new and edited teachers), date of birth, bio, `default_meeting_url`, `pay_currency`, `payout_method` + `payout_details` (details required when a method is set), tags. |
| `ParentProfile` | `has_whatsapp`, notes. |
| `Guardianship` | Parent ↔ student link, many-to-many (a student can have several parents). |
| `Tag` | Emoji tag of `kind` student or teacher, with Arabic and English names and a `position`. Never deleted; a retired tag (`is_active=False`) stays on people but can't be newly assigned. Every academy is seeded with TutorHamster's presets (`identity/presets.py`). |
| `Family` | Siblings under one `payer` (a `User`). Never deleted; retired families keep their students but supply no payer. |

Staff accounts have no profile. Their roles are `access.StaffRole` (see [roles-permissions.md](roles-permissions.md)). allauth's `EmailAddress` rows hold each user's addresses and verification state.

Derived values (computed when read, never stored):

- **Account state** (`services.account_state`): `no_login` (no email), `inactive`, `invited` (no usable password yet), `active`.
- **Age group** (`identity/ages.py`): `child` < 13, `teen` 13–17, `adult` ≥ 18, measured against the academy's own "today" (`identity/clock.py`). The list filter also accepts `minor`.
- **Account type** (`services.account_type`): `family` when the student has a family, otherwise `individual`.
- **Payer needs choosing** (`services.payer_needs_choosing`): the payer must be active and either one of the family's students or a parent linked to one of them.

## How it works

**Creating people** (`etqan/identity/services.py:create_person`)

1. The office creates a person with a role and a profile dict. Admins and staff must have an email. Duplicate emails are refused across both `User.email` and every `EmailAddress`.
2. Language, timezone and a teacher's `pay_currency` default to the academy's settings.
3. An unverified primary `EmailAddress` is created. If an email was given, an invite email is queued after commit. The invite is a set-password link to `/app/reset-password?uid=…&token=…`.
4. Following the link sets the password and marks the primary email verified (`confirm_password_reset`).
5. Self-registered people come in through `register_person` instead (inactive, with their own password). See [registration.md](registration.md).

**Editing** (`update_person`, `change_person_email`)

- All fields are validated before anything is written. Only the columns that were edited are saved.
- Changing an email:
  - **Never signed in:** the address is replaced and the invite is re-sent.
  - **Has signed in:** the new address goes into `pending_email` and gets a confirmation link. When it is confirmed, `promote_pending_email` (wired to allauth's `email_confirmed` signal) makes it primary, deletes the old address and alerts the old one.
- An email can't be removed once it has been set.

**Account actions** (`POST people/<kind>/<id>/<action>/`)

- `invite`: only while the account state is `invited`.
- `password-reset`: only for `active` accounts.
- `deactivate`:
  - You can't deactivate yourself, or the last active admin. A row lock prevents two concurrent requests from both passing that check.
  - Deactivating signs the person out everywhere (`_end_sessions` scans the session table once). It also ends any quick-login sessions that this person opened.
- `activate`.

**Bulk on students** (`bulk_update_students`, `bulk_family`)

- Actions: activate, deactivate, set_status, add_tag, remove_tag, create_family, add_to_family, remove_from_family. Up to 500 ids per request.
- A student who is already in another family is skipped and reported back, never moved.

**Guardians**

- `link_guardian` and `unlink_guardian` require the right roles.
- `guardians_by_link` returns active guardians in link order. Billing uses it to pick the default payer.

**Families** (`create_family`, `update_family`)

- A family needs at least one student, and none of its students can already be in another family.
- The payer must be one of the students or one of their parents.
- `_claim` is a conditional UPDATE, so if two admins race for the same student, only one wins.
- Removed students go back to `individual`.
- `family_payer(student_user_id)` is billing's first choice of payer.

**Visibility**

- `identity/scopes.py:scope_for`: admins and staff see every person. Anyone else gets an empty queryset, so the people routes return 404 for them.
- The route's permission code decides what admins and staff can do.
- `profile_payload(staff=False)` drops `notes` and `nationality` when a person, or their family, reads their own profile.

**Feature switches**

- `parents` off: the parents routes return 404 and parent sign-ins are refused.
- `families` off: the family routes return 404, and the family fields and filters are hidden.

**My account** (`me/`)

- Returns: the user, `profiles`, `profile`, `permissions` (registry codes), `features` (enabled switches), `impersonator`, `is_super_admin` (`role == "admin"`), and `children` for parents while `parents` is on.
- Each person edits their own name, phone, language and timezone. Phone changes are refused while impersonating, because phone is a sign-in identifier.

## API

All paths are under `/api/v1/`. `<kind>` is `students`, `parents`, `teachers` or `admins`. For `admins` no code is declared, so only admins pass.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET, POST | `people/<kind>/` | `<role>.view_any` / `<role>.create` | List (filters `q`, `is_active`, `tag` (repeatable), student `status`/`country`/`gender`/`nationality`/`age_group`/`account_type`/`family`, teacher `gender`/`course`, parent `has_whatsapp`; `?format=csv` exports) / create |
| GET, PATCH | `people/<kind>/<id>/` | `<role>.view` / `<role>.update` | Read / edit a person and their profile (teachers: `profile.course_ids`) |
| POST | `people/<kind>/<id>/invite\|password-reset\|deactivate\|activate/` | `<role>.update` | Account actions |
| POST | `people/students/bulk/` | `student.update` (+ `family.create` for create_family) | Bulk actions |
| GET, POST | `people/students/<id>/guardians/` | `student.view` / `student.update` | List / link guardians (`parents` on) |
| DELETE | `people/students/<id>/guardians/<parent_id>/` | `student.update` | Unlink |
| GET | `people/parents/<id>/children/` | `parent.view` | A parent's children |
| GET, POST | `people/tags/` | `tag.view_any` / `tag.create` | Tags (`?kind=`), never paginated |
| PATCH | `people/tags/<id>/` | `tag.update` | Rename, reorder, retire |
| GET, POST | `people/families/` | `family.view_any` / `family.create` | Families (`search`, `active`) |
| GET, PATCH | `people/families/<id>/` | `family.view` / `family.update` | One family |
| GET | `people/families/payers/?students=1,2` | `family.create`, `family.update` or `student.update` | Payer choices |
| GET, PATCH | `identity/me/` | signed in | Own account |

Staff accounts are managed under `access/staff/` (see [roles-permissions.md](roles-permissions.md)). Two-factor and quick-login routes under `people/` are covered in [sign-in.md](sign-in.md).

## Dashboard

The `/people/*` area is guarded by `requireOffice` (admin or staff). Each screen names its permission code in `staticData.permission`, which `features/shell/PermissionGate.tsx` checks.

| Route | Feature component |
|---|---|
| `/people/students`, `/people/students/$personId` (`new` creates) | `StudentsList`, `StudentForm`, `GuardiansPanel`, `BulkFamilyDialog` |
| `/people/teachers`, `/people/teachers/$personId` | `TeachersList`, `TeacherForm` |
| `/people/parents`, `/people/parents/$personId` (`parents` feature) | `ParentsList`, `ParentForm` |
| `/people/families`, `/people/families/$familyId` (`families` feature) | `FamiliesList`, `FamilyPage`, `FamilyDialog` |
| `/people/admins` (admins only) | `AdminsList` |
| `/settings/tags` | `TagsSettings`, `TagPicker` |
| `/account` | `ProfileEditForm`, `MyProfileCard`, `EmailAddresses`, `ChangePasswordCard` |

`AccountActions.tsx` holds the invite / reset / activate buttons and shows the account-state chip. It also embeds the quick-login and two-factor admin actions.

## Background jobs

There are no periodic jobs. Invites, resets and email-change confirmations are queued after commit through `integrations.services.queue_email`, branded per academy (`site.emails.brand_email`).

## Configuration

- Feature switches: `parents`, `families` (both on by default), `spanish` (lets people use `es`).
- Academy settings used as defaults: `default_language`, `timezone`, `default_currency`.
- `DJANGO_ACCOUNT_MAX_EMAIL_ADDRESSES` (default 5).

## Code map

- `backend/etqan/identity/models.py`: User, profiles, Tag, Family, Guardianship
- `backend/etqan/identity/services.py`: people, email changes, tags, families, guardians
- `backend/etqan/identity/api/people_urls.py`, `people_views.py`, `people_filters.py`, `people_serializers.py`, `payloads.py`
- `backend/etqan/identity/api/views.py`: `MeView`, `me_payload`
- `backend/etqan/identity/scopes.py`, `ages.py`, `clock.py`, `presets.py`
- `backend/etqan/tenants/services.py`: `create_academy` creates the first admin and seeds the tags
- `dashboard/src/features/people/`, `dashboard/src/features/identity/`
- `dashboard/src/routes/_authed/people.*.tsx`, `settings.tags.tsx`, `account.tsx`

## Design history

- [People & catalogue design](../superpowers/specs/2026-09-24-people-catalogue-design.md) and [plan 3](../superpowers/plans/2026-09-24-plan-3-people-catalogue.md): one role per account, invite flow, email-less students, account actions. Its §4.5 access table was later widened by Plan 12 (staff).
- [Profile depth](../superpowers/specs/2026-09-27-profile-depth-design.md) and [plan 10](../superpowers/plans/2026-09-27-plan-10-profile-depth.md): tags, age groups, XP, nationality, payout fields.
- [Families](../superpowers/specs/2026-09-27-families-design.md) and [plan 11](../superpowers/plans/2026-09-27-plan-11-families.md): families, payer rules, bulk family actions.
- [Roles & permissions](../superpowers/specs/2026-09-28-roles-permissions-design.md): added the `staff` role, and staff see all rows (R-5).
- [Feature toggles](../superpowers/specs/2026-09-30-feature-toggles-design.md) and [plan 13](../superpowers/plans/2026-09-30-plan-13-feature-toggles.md): the `parents` / `families` switches.
- [B9d languages](../superpowers/specs/2026-10-04-b9d-languages-design.md): `es` as a person's language, only while `spanish` is on.
