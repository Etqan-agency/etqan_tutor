# Plan 12 — Staff Roles, Permissions and Supervision — Design

**Date:** 2026-09-28
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B1 (accounts & access), plan 3 of 4 (10 profile depth → 11 families → **12 roles & permissions** → 13 feature toggles).

This spec is delivered as **two plans, in order**:
- **12a:** staff accounts, roles, the permission matrix, the Supervisor preset, and enforcement on every route and screen.
- **12b:** session supervision, which builds on 12a.

**Builds on:**
- Plan 1: one `User` per academy with a single `role` (admin, teacher, student, parent), the invite flow, and `me/`.
- Plans 3–11: every admin-only route (`IsAdmin`, `IsAdmin | ReadOnly`, `IsAcademyAdmin`), the dashboard's admin-only nav and route guards, and `Session`/`Subscription` (Plan 4).

**Evidence:**
- `docs/PHASE_1_SYSTEM_AUDIT.md`:
  - RBAC-001…010: the role editor, 71 resources × 12 verbs, and page and widget permissions;
  - §5.1: the Supervisor actor;
  - the session fields `supervisor_id`, `supervisor_attendance` and `is_session_opened_by_supervisor`;
  - the "general supervision" flag (`نظام الاشراف العام`).
- `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`:
  - PEOPLE-008: admin users with several roles;
  - the gap rows 899, 900, 934 and 988.

Roadmap rule R4 applies.

## 1. Goal

An academy can give people other than its admins controlled access to the dashboard. The admin composes staff roles from TutorHamster's permission matrix and assigns them to staff accounts. Every route and screen then honours those permissions.

A preset **Supervisor** role ships with every academy. With general supervision switched on, a supervisor can be assigned to subscriptions and sessions, can open those sessions, and records their own attendance.

## 2. Decisions

| # | Decision |
|---|---|
| R-1 | **The full TutorHamster matrix (owner decision).** Each resource carries TH's 12 verbs, and there are also page and widget permissions. Where the product has no action for a verb yet, the editor shows that verb greyed as "not used yet". |
| R-2 | **Permission codes are defined in code, and roles are data (approach A).** A registry in code lists resources, verbs, pages and widgets. Each academy stores its own roles as sets of codes. Django's model permissions and third-party packages are not used. |
| R-3 | **A new account type, `staff`.** It joins admin, teacher, student and parent, and an account still has exactly one type. A staff account holds one or more staff roles; this is how TH's "more than one role" (PEOPLE-008) is met. |
| R-4 | **Admin is the academy's super admin.** It always has every permission and can't be restricted. Only admins create or edit admins. |
| R-5 | **Staff see all of the academy's data for the resources they can view.** There is no per-teacher or per-student narrowing, which matches TH's admin roles. |
| R-6 | **Session supervision is in this spec (owner decision) and ships as plan 12b.** It is switched on by an academy setting, "General supervision", off by default, which Plan 13's toggles will absorb. |
| R-7 | Out of scope: <ul><li>notifying staff according to their permissions;</li><li>per-record scoping for staff;</li><li>two-factor login;</li><li>TH's vendor-only pages (quick translate, themes, system status);</li><li>chat for supervisors (B5);</li><li>an activity log of permission changes.</li></ul> |

## 3. Data

### 3.1 Accounts (`etqan.identity`)

- `User.Role` gains `staff`.
- A staff account signs in to the same `/app/` dashboard, through the same invite and password flows as a teacher.
- A staff account with no active role can sign in but sees only their own profile.

### 3.2 Roles (new tenant app `etqan.access`, in `TENANT_APPS`)

**`StaffRole`**

| Field | Notes |
|---|---|
| `name_ar`, `name_en` | Required, up to 60 characters. Each is unique within the academy, compared case-insensitively. |
| `permissions` | A set of permission codes (§3.3). Unknown codes are refused. |
| `is_active` | Default `true`. A retired role keeps its assignments but grants nothing. |
| `created_at`, `updated_at` | |

- **Assignment:** a staff account links to any number of roles, many-to-many.
- **No deletion:** roles are never deleted; they are retired and restored.

### 3.3 The permission registry (`etqan.access.registry`, defined once in code)

**Resources.** Every area the product has at the time of the plan: students, teachers, parents, families, tags, courses, packages, subscriptions, sessions, attendance, session reports, invoices, payments, payroll rates, payroll adjustments, payslips, academy settings, notification settings, site pages and branding, inquiries, staff, and roles. Each has Arabic and English labels.

**Verbs.** TH's 12, with Arabic and English labels:

| Code | English | Arabic |
|---|---|---|
| `view` | view | عرض |
| `view_any` | view all | عرض الكل |
| `create` | create | إضافة |
| `update` | update | تعديل |
| `restore` | restore | استرجاع |
| `restore_any` | restore all | استرجاع الكل |
| `replicate` | replicate | استنساخ |
| `reorder` | reorder | إعادة ترتيب |
| `delete` | delete | حذف |
| `delete_any` | delete all | حذف الكل |
| `force_delete` | force delete | إجبار الحذف |
| `force_delete_any` | force delete all | إجبار حذف أي |

The `role` resource has TH's 6 verbs only: `view`, `view_any`, `create`, `update`, `delete`, `delete_any` (RBAC-003).

**Codes.**
- A resource permission is `<resource>.<verb>`, for example `invoice.create`.
- The registry marks, for each resource, which verbs are **in use**: some route or screen checks them. The rest are stored and shown, but greyed.

**Pages and widgets** (RBAC-004/006):
- **Widgets:** TH's five stats widgets become `widget.students_stats`, `widget.subscriptions_stats`, `widget.revenue_stats`, `widget.sessions_stats` and `widget.students_overview`.
  - Each gates the matching card or summary where the dashboard has one. For example, `widget.revenue_stats` gates the billing summary figures.
  - A widget with no screen yet is greyed "not used yet". The plan's table names which screen each one gates.
- **Pages:** TH's pages (quick translate, themes, two-factor, system status) are vendor-only and out of scope (R-7). The Pages tab lists their codes greyed "not used yet", for parity. Our own screens are gated by resource codes only, never by a second page code.

**Session supervision (12b):**
- adds the code `session.supervise`;
- adds the supervision verbs to the registry's in-use set when 12b ships.

### 3.4 The Supervisor preset

**Seeding.** The preset goes into every existing academy by data migration and into new academies through `create_academy`. It is idempotent by name ("مشرف" / "Supervisor") and editable like any other role.

**Its codes:**
- `view` and `view_any` on students, teachers, parents, families, subscriptions, sessions, attendance and session reports;
- `update` on sessions, attendance and session reports;
- `session.supervise`, from 12b.

It has nothing on billing, payroll, settings, site, staff or roles.

### 3.5 Session supervision (12b, `etqan.scheduling` and `etqan.academy`)

**Academy settings** gain `supervision_enabled` (boolean, `db_default=False`).

**`Subscription`** gains `supervisor`, a nullable FK to User with `SET_NULL`.

**`Session`** gains:
- `supervisor` (nullable FK to User, `SET_NULL`);
- `supervisor_attendance` (`not_set · present · absent`, `db_default="not_set"`);
- `opened_by_supervisor_at` (a nullable UTC instant).

**Who can supervise.** A supervisor must be an active staff account holding `session.supervise` through an active role. Otherwise the assignment is a 400 on `supervisor_id`.

**Where the supervisor comes from.**
- Generated sessions take the subscription's supervisor when they are created.
- Changing a subscription's supervisor updates its sessions that have not started. Sessions that have started keep their supervisor.
- A single session's supervisor can be overridden.

## 4. Behaviour

### 4.1 Enforcement

One permission class checks the code a route declares:
- admins always pass;
- staff pass when any of their active roles holds the code;
- other account types never pass a code check.

The routes that serve teachers, students and parents their own data are unchanged. Routes that currently combine roles (`IsAdmin | ReadOnly`, `IsAdmin | IsTeacher`) keep their other branches, and the admin branch becomes the code check.

**Verb mapping**, one fixed rule:

| Request | Verb |
|---|---|
| a list | `view_any` |
| one record | `view` |
| POST | `create` |
| PATCH | `update` |
| state changes: cancel, renew, void, issue, end pause, retire/restore through `is_active` | `update` |
| generate (sessions, payslips) | `create` |
| a bulk action | `update` on that resource |
| CSV export | `view_any` |

**Every `/api/v1/` route declares its code** in the plan's route table. A test fails if any authenticated, non-self-service route lacks one.

**Loading.** A request loads the user's codes once: one query for staff, none for admins.

### 4.2 Staff and roles admin

These routes need the `staff.*` or `role.*` codes, which only admins hold by default.

Guards against escalation, each a 400 or 403 that names its field:
- a staff user can grant a role only if they themselves hold every code in it;
- a staff user can only add codes to a role that they themselves hold;
- a staff user can't change their own roles or deactivate themselves;
- staff never edit, deactivate or see the edit forms of admin accounts;
- only admins create or edit admins.

**Other rules:**
- Creating a staff user sends the Plan 1 invite email.
- Deactivating a staff user blocks their login, as it does for teachers.
- Retiring a role keeps every assignment. Restoring the role makes its codes count again.

### 4.3 `me/`

`me/` gains `permissions`, a list of codes:
- an admin gets every registry code;
- a staff account gets the union of its active roles' codes;
- teachers, students and parents get an empty list.

It also gains `is_super_admin` (true for admins).

### 4.4 Session supervision (12b)

While `supervision_enabled` is off, the supervisor fields are hidden from the API and the dashboard, and the supervision routes answer 404.

When it is on:
- Assigning a supervisor needs `subscription.update` (on a subscription) or `session.update` (on a session).
- A supervisor sees **My supervision**: their sessions for today and the upcoming ones, newest first and paged. Each row shows the student, teacher, course, time, the teacher's and student's attendance, and their own attendance.
- **Open**, allowed from 10 minutes before the start until the session ends, stores `opened_by_supervisor_at` once and returns the meeting URL.
- A supervisor marks **their own** `supervisor_attendance`, and only on sessions assigned to them. Admins and staff holding `attendance.update` can also set it.
- Admin session detail and session lists show the supervisor and the supervisor's attendance.

## 5. API (`/api/v1/`, existing conventions)

### 5.1 Plan 12a (`access/`)

| Method | Path | Notes |
|---|---|---|
| GET | `access/registry/` | Resources (with ar/en labels, verbs and the in-use verbs), plus pages and widgets. Needs `role.view_any`. |
| GET | `access/roles/` | Paged, `?active=`. Each row: `id, name_ar, name_en, permissions, is_active, members, created_at`. |
| POST | `access/roles/` | 201, with a fresh read. |
| GET, PATCH | `access/roles/<id>/` | No DELETE and no PUT. |
| GET | `access/staff/` | Paged, `?search=`, `?role=`, `?active=`. Each row: `id, full_name, email, is_active, roles [{id, name_ar, name_en}], invited, created_at`. |
| POST | `access/staff/` | 201, and sends the invite. |
| GET, PATCH | `access/staff/<id>/` | Name, email, active and `role_ids`. |

- `me/` gains `permissions` and `is_super_admin`.
- The existing routes change only their permission class, as the route table sets out.

### 5.2 Plan 12b

- `academy/settings/` gains `supervision_enabled`.
- The subscription create and PATCH routes accept `supervisor_id`, and the session PATCH route accepts `supervisor_id` and `supervisor_attendance`.
- Rows gain `supervisor {id, full_name} | null`, `supervisor_attendance` and `opened_by_supervisor_at`.
- `GET scheduling/supervision/` lists the caller's supervised sessions.
- `POST scheduling/supervision/<id>/open/` records the opening and returns `{meeting_url}`.
- `POST scheduling/supervision/<id>/attendance/` takes `{"status": "present"|"absent"}`.

## 6. Dashboard (`/app/`, en/ar, RTL, phone width)

### 6.1 Plan 12a

**Settings → Roles:**
- the list shows the name in the reader's language, the member count and whether the role is active, with Edit, Retire and Restore;
- the editor has the name fields and TH's tabs **Resources · Pages · Widgets**;
- there is "Select all" for the whole role and for each resource row;
- verbs that aren't in use are greyed and labelled "not used yet".

**People → Staff:**
- the list shows name, email, roles and active, with search and Role and Status filters;
- Add and Edit dialogs cover name, email, a roles multi-select and active;
- adding sends the invite.

**Gating:**
- A `can(code)` helper, fed by `me/.permissions`, filters the nav, routes and action buttons.
- A route opened directly without the permission shows "You don't have access to this page."
- The server still enforces every route.

**Reuse:** the shared helpers (Pager, `clean`, `applyServerErrors`, `useFieldError`, `Fact`). Every string is in en and ar.

### 6.2 Plan 12b

- **Academy settings:** a "General supervision" switch.
- **Subscription form and session detail:** a Supervisor select, listing active staff who hold `session.supervise`, with a "Supervisor attendance" control. These show only while the switch is on.
- **My supervision:** the supervisor's list with Open and their attendance buttons. It is in the nav for anyone holding `session.supervise` while supervision is on.

## 7. Seeds

**`demo`:**
- the Supervisor preset;
- a staff account, "Sara Supervisor", holding it;
- once 12b ships: supervision switched on, and one demo subscription supervised by Sara.

**`other`:** the preset only.

Both are idempotent.

## 8. Testing

**12a**

Registry:
- codes are unique;
- labels exist in both languages;
- the `role` resource has 6 verbs.

Route coverage:
- a test walks every URL pattern and fails on any non-self-service route that has no declared code.

Enforcement:
- for each resource, a staff user is allowed with the code and gets 403 without it, for every verb in use;
- a retired role grants nothing;
- admins pass everything;
- teachers, students and parents are unaffected on their own routes.

Escalation: each §4.2 guard has a test.

Roles:
- an unknown code is refused;
- a duplicate name (either language, case-insensitive) is refused;
- retire and restore work;
- there is no delete.

Isolation: other academies' roles and staff are never visible or assignable (`until_pk_exceeds`).

Performance: the permission check costs at most one query per request, and the roles list, the staff list and `me/` keep flat query counts.

**12b**
- The setting off hides the fields and 404s the routes.
- Inheritance from the subscription; a supervisor change updates only unstarted sessions; the per-session override.
- A non-staff supervisor, or one without the code, is refused.
- The open window's boundaries, in a non-UTC academy.
- A supervisor can mark only their own sessions.

**Dashboard and e2e**
- Dashboard unit tests for each piece.
- 12a e2e: an admin creates a role and a staff user; the staff user accepts the invite, sees only the allowed nav, gets "You don't have access" on a direct URL, and gets 403 from the API.
- 12b e2e: the admin switches supervision on and assigns Sara; Sara opens her session and marks herself present.

## 9. Risks

| Risk | Mitigation |
|---|---|
| A route left unguarded or given the wrong code | One declared code per route, a coverage test, one verb-mapping rule, and the route table in the plan |
| Staff escalating their own access | The §4.2 guards, each with its own test |
| The permission check slowing every request | Codes are loaded once per request, and query-count tests enforce it |
| The dashboard hiding what the server allows, or the reverse | Both read the same codes from `me/`, and the server stays the authority |
| 12b's supervision flow differing from TH's unobserved one | It sits behind a setting that is off by default, and R7's checkpoint can revise it in B2 |

## 10. Out of scope

See R-7.
