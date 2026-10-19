# Roles and permissions

Decides who can do what inside an academy. It combines three things:

- the account's fixed **role** (`User.role`)
- **staff roles**, which are sets of permission codes that an academy gives its `staff` accounts
- Etqan's per-academy **feature switches**

Academy admins hold every code. Staff hold only the codes their active roles grant. Teachers, students and parents never hold codes: they reach only the routes that serve them their own data. Admins, and staff with the right codes, manage roles and staff under Settings → Roles and People → Staff.

## Concepts

| Thing | Where | Purpose |
|---|---|---|
| `User.role` | `identity` (academy schema) | Exactly one of `admin`, `staff`, `teacher`, `student`, `parent`. Admin and staff are the **office** roles (`platform/permissions.py:OFFICE_ROLES`). |
| `access.StaffRole` | `access` (academy schema, `TENANT_APPS`) | `name_ar` and `name_en` (each unique, case-insensitive), `permissions` (a JSON list of registry codes), `is_active`, and `members` (M2M to `User`, `related_name="staff_roles"`). Never deleted: a retired role keeps its members but grants nothing. |
| Permission registry | `access/registry.py` (code, not data) | Every code a role can hold. **Resource codes** are `<resource>.<verb>`; verbs are TutorHamster's 12 plus `supervise` and `export_margins`. Also `page.*` and `widget.*` entries. Each resource marks which of its verbs are `in_use`. The rest are stored and shown greyed out. `access/tests/test_routes.py` checks that `in_use` matches the codes the routes declare. |
| Supervisor preset | `access/presets.py` | Seeded into every academy by `tenants.services.create_academy`: read access to people, families, subscriptions, sessions, attendance and session reports, plus `session.update`, `attendance.update`, `session_report.update` and `session.supervise`. |
| Feature switches | `platform/features.py`; values on `tenants.Academy.features` (public schema) | Etqan turns whole areas on or off per academy. A missing key means the feature's default. A feature is on only when everything it `requires` is also on. |

Etqan staff (public-schema `is_staff` users) aren't part of this system. They only use the Django admin.

## How it works

**Loading codes**

- `access.apps.AccessConfig.ready` registers `access.services.codes_for` with `platform.permissions.register_code_loader`, so the platform layer never imports a business app.
- `codes_for(user)` returns:
  - for an admin: `registry.CODES`, with no query
  - for staff: the union of their active roles' codes, intersected with the registry, in one query
  - for anyone else: nothing
- `codes_of(user)` caches the result on the user object, once per request.

**Enforcing in views** (`etqan/platform/permissions.py`)

- `HasCode`:
  - An admin always passes.
  - A staff user passes when they hold the code the view declares in `permission_codes`. The map is keyed by HTTP method, or by viewset action through `viewset_codes()`. A tuple value means "any one of these".
  - Everyone else fails.
  - A view that declares no code for the method is **admin-only**, for example `people/admins/`, `identity/google/settings/` and `identity/security-log/`.
- `FeatureOn` is listed after `HasCode`. If the view's `feature`, or its method → feature map, is off, it raises 404 "as if the route weren't there". A caller refused by the code check still gets 403 first.
- Role classes `IsAdmin`, `IsTeacher`, `IsParent`, `IsStudent`, `ReadOnly` and `ReadsOwn` combine with `HasCode` on routes that also serve teachers, students and parents. For example: `[HasCode | (ReadOnly & ReadsOwn)]`.
- **Row scope:** office roles see every row of what they are allowed to view (R-5). Other roles get only their own rows, through each app's `scope_for` / queryset helpers. Rows outside scope return 404.
- `NotImpersonating` refuses credential, money and messaging actions during quick login (see [sign-in.md](sign-in.md)).

**Anti-escalation rules for staff editors** (`access/services.py`). These apply only when `by` is a staff account; admins are never limited.

1. In a role's codes, staff can add **and remove** only codes they hold themselves.
2. Staff can retire or restore a role only if they hold every code it grants: retiring removes all of its codes from every member at once (ETQAN-QA-021). Renaming is not limited: it changes no one's access.
3. Staff can grant or remove a role only if they hold all of its codes. For removal, retired roles count too (`_roles_to_assign`, `_guard_removed_roles`).
4. Staff can change another staff account's email or active state only if they outrank it: they must hold every code that account's roles grant, retired roles included (`_guard_stronger_account`).
5. Staff can never change their own roles or deactivate themselves.
6. Unknown codes are refused (400), and role names must be unique in each language whatever the case.

**Staff accounts**

- `create_staff` creates the account through `identity.services.create_person("staff", …)`. An email is required, and the person receives the usual set-password invite.
- Deactivating a staff account signs them out everywhere, as for any person.
- Admins never appear in the staff list.

**Supervisors** (Plan 12b): `supervisors_queryset()` returns active staff who hold `session.supervise` through an active role. Admins are never supervisors.

**`me/`** returns `permissions` (sorted codes), `features` (enabled switch codes in registry order) and `is_super_admin`. The dashboard uses these to hide what the server would refuse.

## API

All paths are under `/api/v1/access/`. There is no PUT and no DELETE: roles are retired, not deleted.

| Method | Path | Codes | Purpose |
|---|---|---|---|
| GET | `registry/` | any of `role.view_any`, `role.view`, `role.create`, `role.update` | Verbs, resources (with `in_use`), pages, widgets |
| GET | `roles/` | any of `role.view_any`, `staff.create`, `staff.update` | Roles with `members` count; `?active=` |
| POST | `roles/` | `role.create` | Create a role |
| GET, PATCH | `roles/<id>/` | `role.view` / `role.update` | Read / rename, change codes, retire or restore |
| GET | `staff/` | `staff.view_any` | Staff with their roles and `invited` flag; `?search=`, `?role=`, `?active=` |
| POST | `staff/` | `staff.create` | `full_name`, `email`, `role_ids` |
| GET, PATCH | `staff/<id>/` | `staff.view` / `staff.update` | Edit name, email, `is_active`, `role_ids` |

Etqan staff edit the feature switches in the platform's Django admin (`tenants/admin.py`). Academy admins see them read-only at `/settings/features`. See [feature-toggles.md](feature-toggles.md).

## Dashboard

- **Route guards:**
  - `features/identity/require-admin.ts`: `requireRole`, `requireAdmin`, and `requireOffice` (admin or staff). Teachers, students and parents are sent to `/`.
  - `features/shell/PermissionGate.tsx` reads each matched route's `staticData.permission` (a code, `ADMINS_ONLY`, or `newOrView(param, resource)`) and `staticData.feature`. It renders `NoAccess` or `FeatureOff` instead of the page.
- **In-page checks** (`features/identity/permissions.tsx`):
  - `can(me, code)` and `useCan()` hide office actions. Only staff are ever narrowed.
  - `hasFeature` and `useHasFeature()` hide switched-off areas from everyone.
  - `useRole()` is for the few screens that differ by role.
- **Navigation:** `features/shell/nav.ts` uses `office(path, label, icon, group, code)` to build entries shown only when `can()` passes.
- **Screens** (`features/access/`):
  - `/settings/roles`: `RolesList`
  - `/settings/roles/$roleId`: `RoleEditor`, the permission matrix built from `registry/`; `new` creates a role
  - `/people/staff`: `StaffList`, `StaffDialog`

## Background jobs

None.

## Configuration

- No env vars.
- The Supervisor preset and the registry are code. Roles and their members are per-academy data.
- When a phase adds a resource, it goes under that phase's `── phase Bn ──` marker in `access/registry.py`.

## Code map

- `backend/etqan/platform/permissions.py`: `HasCode`, `FeatureOn`, role classes, `codes_of`, `required_code`, `viewset_codes`, `NotImpersonating`
- `backend/etqan/platform/features.py`: switch registry and `enabled()`
- `backend/etqan/access/registry.py`, `models.py`, `services.py`, `presets.py`, `apps.py`
- `backend/etqan/access/api/urls.py`, `views.py`, `serializers.py`, `payloads.py`, `filters.py`
- `backend/etqan/access/tests/test_routes.py`: keeps the registry's `in_use` honest
- `backend/etqan/identity/scopes.py`: people scope
- `dashboard/src/features/access/`, `dashboard/src/features/identity/permissions.tsx`, `require-admin.ts`
- `dashboard/src/features/shell/PermissionGate.tsx`, `nav.ts`

## Design history

- [Roles & permissions design](../superpowers/specs/2026-09-28-roles-permissions-design.md): the `staff` account type, registry, roles-as-data, R-5 (staff see all rows), anti-escalation rules, supervision.
- [Plan 12a roles](../superpowers/plans/2026-09-28-plan-12a-roles.md) and [plan 12b supervision](../superpowers/plans/2026-09-29-plan-12b-supervision.md): the build. The removal guard and the "include retired roles" guard were tightened in final review and are in `access/services.py`.
- [Feature toggles](../superpowers/specs/2026-09-30-feature-toggles-design.md) and [plan 13](../superpowers/plans/2026-09-30-plan-13-feature-toggles.md): `FeatureOn` (404), `me.features`, `hasFeature`.
- [People & catalogue design](../superpowers/specs/2026-09-24-people-catalogue-design.md) §4.5: the original admin-only access table, superseded for office routes by Plan 12.
- Each later phase spec (B2–B11) adds its own resources to the registry. See the `── phase Bn ──` markers.
