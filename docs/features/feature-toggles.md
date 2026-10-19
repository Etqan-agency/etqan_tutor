# Feature toggles

Etqan switches whole parts of the product on or off for each academy. A feature that is off
disappears from that academy's API (404), dashboard (nav hidden, a "feature off" screen) and
background jobs. Turning it back on restores everything, because turning it off deletes nothing.
Only Etqan staff change switches, in the platform admin. The academy admin sees a read-only list.
Every feature developer uses this: almost every slice since B2 ships behind a switch that is off by
default.

## Concepts

- **Registry in code**: `backend/etqan/platform/features.py:REGISTRY` lists every `Feature(code,
  label_en, label_ar, group, default, built, requires)`. It has 88 entries in six groups
  (`people`, `teaching`, `money`, `communication`, `content`, `platform`).
- **Values on the academy**: `Academy.features` (public schema) is a JSON map from code to bool.
  A missing key, or a non-bool value, means the registry default.
- **Effective state**: `is_on(code)` means the feature's own switch is on **and** every code in
  `requires` is on, recursively. `held_by(code)` names the prerequisites holding a switched-on
  feature off.
- **`built=False`**: a switch that is stored and editable but has no code checking it yet. Only
  `free_sessions` and `public_links` are left.
- Defaults that are on: `families`, `parents`, `session_reports`, `invoices`, `auto_notifications`,
  `teacher_attendance`, `export`. Everything else is off by default.
- Prerequisite pairs: `online_payments`→`invoices`, `payment_links`→`online_payments`,
  `payment_receipts`→`invoices`, `verified_certificates`→`certificates`,
  `report_deductions`→`session_reports`+`payroll_rules`, `registration_waitlist`→`self_registration`,
  `family_subscriptions`→`families`, `group_subscriptions`→`study_groups`,
  `push_notifications`→`installable_app`.

## How it works

1. **Reading a switch costs no query.** `features.enabled(code)` reads
   `connection.tenant.features`. django-tenants has already loaded that academy for the request, or
   `for_each_academy` has loaded it for a task. In the public schema, every feature reads its
   default. The platform app never imports `tenants`.
2. **Gating an API route**: add `FeatureOn` after the code check and declare `feature`:
   ```python
   permission_classes = [HasCode, FeatureOn]
   feature = "faqs"              # or {"GET": "x", "POST": "y"}
   ```
   `FeatureOn` raises 404 "This feature is not enabled for this academy." The role and code check
   runs first, so a caller who lacks the permission still gets 403
   (`platform/permissions.py:FeatureOn`).
3. **Gating inside logic**: call `features.enabled("code")` in services and serializers. For
   example, `postpone_limit_minutes` is hidden and refused unless `postponement` is on, and public
   site sections drop out when their feature is off. Background jobs check it per academy inside
   `for_each_academy`.
4. **Dashboard**: `GET /api/v1/identity/me/` returns `features: enabled_codes()`, the effective
   on-codes in registry order.
   - `hasFeature(me, code)` / `useHasFeature()` in `dashboard/src/features/identity/permissions`
     read that list. When `me.features` is missing, every feature counts as on.
   - A nav item declares `feature` (`dashboard/src/features/shell/nav.ts`, the `office(...)` helper).
   - A route declares `staticData.feature`. `PermissionGate` (`features/shell/PermissionGate.tsx`)
     shows `NoAccess` when a permission code is missing and `FeatureOff` when a feature is off. The
     code is checked first, as on the server.
   - The `FeatureCode` union in `dashboard/src/features/identity/schemas.ts` must list the code.
5. **Etqan staff edit switches** on the academy change page in the Django admin
   (`tenants/admin.py:AcademyChangeForm`). There is one checkbox per feature, grouped. Each checkbox
   shows the feature's own switch, notes an unbuilt feature, and shows "Held off: needs …" when a
   prerequisite blocks it. Only changed checkboxes are written, so an untouched feature keeps
   following its default. "Changed" means changed on that page: each field carries the value the
   page showed (a hidden initial), so a page opened before a feature was switched elsewhere (for
   example by `set_features`) leaves that newer switch alone (ETQAN-QA-014). The "Copy features from another academy" action
   (`services.copy_features`) copies one academy's stored map onto the selected academies.
6. **Scripts**: `manage.py set_features <subdomain> --on a b --off c`
   (`tenants/services.py:set_features`). An unknown code is an error. Dev seeds call
   `seed_features`, which only switches on codes that have no stored value yet.

### Adding a feature

1. Add a `Feature(...)` under your phase's marker in `REGISTRY`, with `built=True` and normally
   `default=False`.
2. Gate the API views (`FeatureOn`) and any service, serializer or task branches (`enabled`).
3. Add the code to the dashboard `FeatureCode` union. Set `feature` on the nav item and
   `staticData.feature` on the routes.
4. No dashboard translation is needed for the label. The Features page shows `label_ar` /
   `label_en` from the API, and English for Spanish. Only a new group would need a key under
   `features.groups` in `dashboard/src/locales/<lng>/features.json`.

## API

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/academy/features/` | Academy admins only (`HasCode` with no code) | Every feature with `code`, `label_ar`, `label_en`, `group`, `on` (effective), `built`, `held_by`. No write endpoint exists. |
| GET | `/api/v1/identity/me/` | Any signed-in user | `features`: the effective on-codes |

## Dashboard

- `/app/settings/features` (`routes/_authed/settings.features.tsx` → `features/academy/FeaturesPage.tsx`):
  a read-only grouped list for admins (`ADMINS_ONLY`).
- `features/shell/FeatureOff.tsx`: the screen shown when someone opens a switched-off screen directly.

## Background jobs

None of its own. Each task checks `features.enabled(...)` per academy inside `for_each_academy`.

## Configuration

The switches themselves are the configuration. They are set per academy in the Django admin on the
base domain, or with `set_features`.

## Code map

- `backend/etqan/platform/features.py`: registry, `enabled`, `enabled_codes`, `describe`, `is_on`,
  `held_by`
- `backend/etqan/platform/permissions.py`: `FeatureOn`, `required_feature`
- `backend/etqan/tenants/services.py`: `set_features`, `copy_features`, `seed_features`
- `backend/etqan/tenants/admin.py`: feature checkboxes and the copy action
- `backend/etqan/tenants/management/commands/set_features.py`
- `backend/etqan/academy/api/views.py`: `AcademyFeaturesView`
- `backend/etqan/identity/api/views.py`: the `features` key of `me/`
- `dashboard/src/features/identity/permissions.tsx`: `hasFeature`, `useHasFeature`
- `dashboard/src/features/shell/PermissionGate.tsx`, `FeatureOff.tsx`, `nav.ts`
- `dashboard/src/features/academy/FeaturesPage.tsx`

## Design history

- [Feature toggles design (Plan 13)](../superpowers/specs/2026-09-30-feature-toggles-design.md):
  FT-1 (Etqan sets, the admin sees), FT-2 (the full TutorHamster list stored now), FT-3 (registry
  in code, values on the academy). This spec moved `AcademySettings.supervision_enabled` into the
  `supervision` switch.
- [Plan 13](../superpowers/plans/2026-09-30-plan-13-feature-toggles.md): implementation.
- [Parallel orchestration design](../superpowers/specs/2026-10-02-parallel-orchestration-design.md):
  PO-5, every phase's new work is off by default. Each later phase spec flips its entries to
  `built=True` in place.
