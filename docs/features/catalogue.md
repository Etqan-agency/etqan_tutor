# Catalogue: courses and packages

The catalogue is what an academy sells and teaches. **Courses** are the subjects taught
(Quran, Arabic, and so on), each with the teachers allowed to teach it. **Packages** are
the plans a subscription is sold from: sessions per week, minutes per session, how long
it lasts, how many freeze days it allows, and the price. Admins and staff manage both.
Teachers can read active ones. Students and parents never read the catalogue directly.
They see a course and package only through their subscriptions.

## Concepts

| Model (`backend/etqan/catalogue/models.py`) | Purpose |
|---|---|
| `Course` | Bilingual name and description (`name_ar`/`name_en`), `language` (`ar`, `en`, `both`), `teachers` (M2M to `identity.TeacherProfile`, referenced by string), `is_active`. |
| `Package` | `sessions_per_week` (1–14), `session_minutes` (15–240), `duration_value` (1–365) + `duration_unit` (`day`/`month`), `freeze_days_allowed` (0–365), `price_minor` + `currency` (ISO 4217), `is_active`. |
| `PackageCountryPrice` | B3d: what a student from one country (ISO 3166 alpha-2) pays for a package, in any currency. One row per (package, country). |

Relations to other apps: `scheduling.Subscription`, `Session` and `TrialRequest` point at
`Course`/`Package` with `PROTECT`. System-code batches (vouchers, B3f) also protect
packages. Levels, curriculum, recorded courses and consultations live in their own apps.
The dashboard shows them under `/catalogue`, but this page does not cover them.

## How it works

- **Sessions total.** `catalogue/services.py:sessions_total` is the only place the
  package total is computed: `sessions_per_week × weeks`. A month counts as 4 weeks, and
  days round up to whole weeks (`weeks`, `compute_sessions_total`). The total is never
  stored on the package. It is copied onto each subscription when the subscription is
  created (see [subscriptions.md](subscriptions.md)).
- **Package edits never reach existing subscriptions.** A subscription copies the
  duration, total, minutes, freeze days and price when it is created.
- **Delete vs deactivate.** `delete_course` / `delete_package` turn the `ProtectedError`
  into a 409 `catalogue.in_use`. A course or package that has subscriptions, sessions or
  system codes must be deactivated (`is_active=false`) instead.
- **Duplicate.** `duplicate_course` / `duplicate_package` copy the row with a
  " (copy)" / " (نسخة)" suffix (the name is shortened so it still fits) and set
  `is_active=False`. A duplicated course keeps its teachers. A duplicated package keeps
  its country prices.
- **Teachers per course.** `create_course` / `update_course` take `teacher_ids` (User
  ids). `set_teacher_courses` sets it from the teacher's side (used by people screens).
  `course_ids_for_teachers` and `teacher_user_ids_for_course` are the reads other apps
  use. Scheduling requires the teacher of a subscription, trial or manual session to
  teach the course when the course lists any teachers.
- **Price resolution (B3d).** `package_price(package, country=)` is the one resolver. It
  returns the country's row while the `country_pricing` feature is on and a row exists,
  and otherwise the package's own price. `price_for_student` uses the student profile's
  country. `scheduling.create_subscription` and renewal always price through it.
- **Country price list.** `set_country_prices` replaces the whole list in one
  transaction, under a row lock on the package. The list holds at most 250 rows, with no
  duplicate countries and a price ≥ 0. Errors are keyed `rows.<i>.<field>`.
- **Visibility** (`catalogue/scopes.py:scope_for`): office (admin and staff) sees all
  rows. A teacher sees only `is_active=True` rows. Everyone else sees none.

## API

All routes are under `/api/v1/catalogue/` (`backend/etqan/catalogue/api/urls.py`).

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET, POST | `/api/v1/catalogue/courses/` | code `course.view_any` / `course.create`; teachers read-only | List (filters `is_active`, `q`; `?format=csv` export) / create |
| GET, PATCH, DELETE | `/api/v1/catalogue/courses/<id>/` | `course.view` / `.update` / `.delete` | Read / edit (incl. `teacher_ids`) / delete (409 if in use) |
| POST | `/api/v1/catalogue/courses/<id>/duplicate/` | `course.replicate` | Inactive copy |
| GET, POST | `/api/v1/catalogue/packages/` | `package.view_any` / `.create`; teachers read-only | List / create |
| GET, PATCH, DELETE | `/api/v1/catalogue/packages/<id>/` | `package.*` | Read / edit / delete |
| POST | `/api/v1/catalogue/packages/<id>/duplicate/` | `package.replicate` | Inactive copy |
| GET, PUT | `/api/v1/catalogue/packages/<id>/country-prices/` | `package.view_any` / `package.update`; feature `country_pricing` | Read / replace the country price list |
| GET | `/api/v1/catalogue/packages/<id>/price/?student=<user id>` | `package.view_any` (staff also need `student.view_any` to pass `student`) | Resolved price used to prefill office forms; no feature gate |

PUT is not offered on the viewsets (`http_method_names` excludes it).

## Dashboard

- Routes: `dashboard/src/routes/_authed/catalogue.tsx` (office only, via `requireOffice`),
  `catalogue.index.tsx` (redirects to `/catalogue/courses`), `catalogue.courses.index.tsx`,
  `catalogue.courses.$courseId.tsx`, `catalogue.packages.index.tsx`,
  `catalogue.packages.$packageId.tsx`.
- Feature folder `dashboard/src/features/catalogue/`: `CatalogueList` (shared list for
  both), `CourseForm`, `PackageForm`, `CountryPricesCard` (shown when `country_pricing`
  is on), `PriceByPermission`, `sessions-total.ts` (mirrors the backend formula for the
  form preview), `api.ts`, `queries.ts`, `schemas.ts`.

## Configuration

- Feature switch `country_pricing` (off by default) turns per-country prices on.
- Permission codes `course.*` and `package.*` (`view_any`, `view`, `create`, `update`,
  `delete`, `replicate`) come from the access registry.

## Code map

- `backend/etqan/catalogue/models.py`, `services.py`, `scopes.py`
- `backend/etqan/catalogue/api/views.py`, `serializers.py`, `urls.py`
- `backend/etqan/catalogue/tests/`
- `dashboard/src/features/catalogue/`
- `dashboard/src/routes/_authed/catalogue.*.tsx`

## Design history

- [Plan 3 people and catalogue spec](../superpowers/specs/2026-09-24-people-catalogue-design.md): courses, packages, sessions-total rule (P3-7). Current.
- [Plan 3 plan](../superpowers/plans/2026-09-24-plan-3-people-catalogue.md): implementation plan, D15 (catalogue never imports identity models).
- [B3d countries and currencies spec](../superpowers/specs/2026-10-05-b3d-countries-currencies-design.md): `PackageCountryPrice`, the price resolver, and currency checks on subscription forms.
- [Plan 36 country prices](../superpowers/plans/2026-10-05-plan-36-country-prices.md): implementation of B3d's catalogue part.
- [Roles and permissions spec](../superpowers/specs/2026-09-28-roles-permissions-design.md): staff see all rows (R-5), and the permission-code model the views use.
