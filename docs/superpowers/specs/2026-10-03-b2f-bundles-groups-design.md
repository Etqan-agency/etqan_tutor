# Slice B2f — Study Groups and Subscription Bundles — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); its 16 findings are applied below.
**Phase:** B2, slice f (`2026-10-03-b2-scheduling-depth-design.md` §3, as amended by B2b: B2f = bundles & groups).
**Builds on:** Plan 4 (subscriptions, slots, generation, renewal, pauses, P4-9 clashes), Plan 6 (billing applied per
subscription in the view), Plan 11 (families: `identity.Family`, one family per student, payer), Plan 12b
(supervision), Plan 13 (switches, `requires`, per-route gating), B2a (one create route per kind, A-13), B2b–B2e,
ledger D6 (group class = one session row per student), D7 (bundles over subscriptions), D10, D14.
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §1.3 #6, #8, §2.3 SUB-001 (details repeater), PEOPLE-003,
§5.2–5.4; `docs/PHASE_1_SYSTEM_AUDIT.md` SUB-001, SUB-006, SUB-008, PEOPLE-002, PEOPLE-003, BR-09, BR-10, BR-14–BR-17.
The TH audit's §5.2 / §5.4 list multi-course, family, roster and groups as v1 NON-GOALs (v1 D8); phase B2-3 and B2-13
supersede them for B2.

## 1. Goal

TutorHamster's subscription can hold several courses (each with its own teacher and package), several students of a
family, or a whole study group taught together. We keep `Subscription` as it is (ledger D7) and add a **bundle** that
groups several subscriptions created, renewed, paused, cancelled and archived as one, plus **study groups** (named sets
of students, each student in at most one).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| F-1 | **Study group**: name\*, students\* (individual or family accounts; each student in at most one group), notes, active. Lives in `etqan.scheduling`; the registry's `study_groups` line is flipped to built. One group may have several bundles (e.g. one per course). | P1 PEOPLE-003, BR-17; phase B2-13 · [assumed] several bundles |
| F-2 | **Bundle kinds**: `multi_course` (one student, two or more distinct courses, each row with its own teacher, package and slots), `family` (students of one active family, two or more rows, each a student + course + teacher + package + slots; a student may have several rows, student + course distinct), `group` (one study group: one course, teacher, package and slot set, one subscription per active member). A plain subscription stays TutorHamster's "individual, normal". Packages of any type are accepted (TH's package type individual / group is not built). | TH SUB-001 (details repeater; subscription type individual / family; individual type normal / group); ledger D7; phase B2-3 · [assumed] row rules |
| F-3 | Each row of a bundle **is an ordinary `Subscription`** with a nullable `bundle` link: its own term, package snapshot, price, pauses, slots, sessions, derived numbers, invoices and payroll, exactly as today. Billing, payroll and notifications are unchanged (ledger D7). The bundle's totals are sums over its current, non-cancelled members, shown on read, never stored (BR-09, BR-10). | ledger D7; P1 BR-09, BR-10 |
| F-4 | **Group class = one session row per student** (ledger D6): the group's subscriptions share the slot times, so generation makes one row per student at the same time, each with its own attendance and consumption. A pair of sessions of subscriptions in the same `group` bundle with the same start and minutes is **not a clash** (P4-9 conflicts, B2b `teacher_busy`). The exemption and the sessions' group label stay while `group_subscriptions` is off. | ledger D6; P1 SCHED-004 (`group` on a session) |
| F-5 | A bundle's **current members** are the last link of each renewal chain in it (no renewal at all, cancelled or not). **Bundle actions apply to the current members at once, all or nothing**; any refusal refuses the whole action and names the member (§4.6). Members stay editable one by one with today's subscription actions. | phase B2-3 ("created, renewed, paused and cancelled as one"); review · [assumed] all-or-nothing |
| F-6 | **A renewal stays in the bundle, whatever the route**: `renew_subscription` copies `bundle` onto the renewal. A bundled member's renewal may change teacher or package but not course (400 on `course_id`), so multi-course courses stay distinct and a group stays one class. | review · [assumed] |
| F-7 | **Group roster changes**: adding a student creates their subscription from the bundle's template (§4.3) from a given start date; removing a student cancels their live members (the current one and a pending renewal). A study group's membership and a bundle's roster are separate: changing the group does not change bundles; a new group bundle starts from the group's active members. Likewise a family bundle does not follow later family changes. | TH SUB-008 (roster tab) · [assumed] |
| F-8 | **Family bundles** need `families` on; at creation every student must be in the bundle's family and active, and the family active. TutorHamster's "only individual-account students on an individual subscription" (BR-14) is **not enforced** on plain subscriptions: it would refuse subscriptions that exist today. | P1 BR-14, BR-15; spec Plan 11 · [assumed] not enforced |
| F-9 | **Dissolving a bundle** unlinks its members (they become plain subscriptions) and deletes the bundle. Deleting a member subscription (Plan 4 `delete_subscription`) that leaves the bundle empty deletes the bundle too; a bundle may drop below its creation minimum. | [assumed]; review |
| F-10 | **Roster tab** (SUB-008): per student, their user id, current member's course, teacher and status, and the number of sessions over their members in this bundle with `status = completed` and `student_attendance = present`. | TH §1.3 #8, SUB-008 (TH's UID: we have no student code, the user id stands in) |
| F-11 | Switches, off by default: `study_groups` (flipped in place), `multi_course_subscriptions`, `family_subscriptions` (requires `families`), `group_subscriptions` (requires `study_groups`) — new lines under the B2 marker. **One create route per kind**, each gated by its feature (as B2a A-13); `groups/*` gated by `study_groups`. The shared bundle read and action routes are **not gated** (listed as intentionally ungated in the route-table test): bundles made while a switch was on keep working (FT-4, B2a A-13 precedent). | PO-5; spec Plan 13 FT-4, per-route `FeatureOn`; review |

## 3. Data (all in `etqan.scheduling`)

### 3.1 `StudyGroup`, `StudyGroupMember` (new)

`StudyGroup`: `name` (120), `notes`, `is_active` (default true), `created_at`, `updated_at`.
`StudyGroupMember`: `group` → StudyGroup (CASCADE, `related_name="members"`), `student` → StudentProfile (CASCADE,
**unique**: one group per student, BR-17), `added_at`.

### 3.2 `SubscriptionBundle` (new)

| Field | Notes |
|---|---|
| `kind` | `multi_course` \| `family` \| `group` |
| `student` | → StudentProfile, nullable, PROTECT (multi_course) |
| `family` | → `identity.Family` (string reference; families are never deleted), nullable, PROTECT (family) |
| `study_group` | → StudyGroup, nullable, PROTECT (group) |
| `notes` | text |
| `created_by` | → User, nullable, SET_NULL |
| `created_at`, `updated_at` | auto |

Check: exactly the field of its kind is set.

### 3.3 Subscription (existing)

`bundle` → SubscriptionBundle, nullable, PROTECT, `related_name="subscriptions"` (B2-16: nullable, no data change).

## 4. Behaviour

**Lock order:** bundle → all its member subscriptions, locked up front (pk order) → their sessions (Plan 4). Every
bundle action locks the bundle row and then every member before any per-member service call.

### 4.1 Study groups

`create_group(name, student_ids, notes)`, `update_group(group, fields)` (name, notes, active, students as a full list),
`delete_group(group)`: refused while a bundle uses it (409 `scheduling.group_in_use`). A student already in another
group → 400 on `student_ids` naming them (BR-17). Inactive students may stay members; a new member must be active.

### 4.2 Creating a bundle

`create_bundle(kind, by, *, starts_on, rows, student_id=None, family_id=None, group_id=None, supervisor_id=None,
notes="")`. `rows` use the subscription create body's keys (`course`, `teacher`, `package`, `price_minor?`, `slots`;
family rows add `student`); for `group`, exactly one row, applied to every active member of the group (at least one).

1. Validate the kind (F-2, F-8). Errors are 400 on `rows[i].<field>` (the bundle service re-keys the `field` of a
   `ValidationError` raised by `create_subscription`).
2. Create the bundle, then each subscription through `create_subscription(..., bundle=bundle)` (additive parameter),
   in one transaction; any failure rolls all back.
3. The view calls billing's `invoice_subscription(new.pk, by=…)` for each created subscription inside the same
   transaction, as the subscription create view does.
4. Answer the bundle with its members and the clashes of the members' new sessions: the bundle service runs
   `generation.conflicts` over them, with F-4 applied (`create_subscription`'s own result is not exposed today).

### 4.3 Bundle actions

- **Renew** `renew_bundle(bundle, by, *, starts_on=None)`: `renew_subscription` on each current member that is not
  `cancelled`; none renewable → 409 `scheduling.nothing_to_renew`. The view invoices every renewal (billing hook), as
  `RenewView` does.
- **Pause** `pause_bundle(bundle, by, *, from_date, to_date, reason)`: `add_pause` on each current member whose term
  contains `from_date` (so an old link and its not-yet-started renewal never both get it). A member's freeze cap
  refuses the whole action, naming the member and its remaining freeze days.
- **Cancel** `cancel_bundle(bundle, by)`: `cancel_subscription` on each current member that is live (active or
  paused).
- **Archive / restore** (B2d, `subscription_archive` on): archive needs every member ended (409 naming the first live
  member); members already in the target state are filtered out before calling `archive_subscription` /
  `restore_subscription`.
- **Group: add** `add_to_group_bundle(bundle, by, *, student_id, starts_on)`: the student must be active and have no
  live member in the bundle. The **template** is the most recently created current, non-cancelled member: its course,
  teacher, package and active slots (copied as renewal copies slots). The view invoices the new subscription.
- **Group: remove** `remove_from_group_bundle(bundle, by, *, student_id)`: cancels the student's live members;
  refused when there is none (409 `scheduling.not_allowed_in_status`).
- **Notes** `update_bundle(bundle, *, notes)`.
- **Dissolve** `dissolve_bundle(bundle)`: F-9.

### 4.4 Clashes inside a group (F-4)

`generation.conflicts` and B2b's `teacher_busy` load each session's `subscription__bundle_id` and
`subscription__bundle__kind` and leave out a pair whose subscriptions share a `group` bundle and whose start and minutes
are equal.

### 4.5 Reading

Bundle payload: kind, the kind's owner (student / family / group name), notes, all members (each a subscription row
with status, derived numbers, `current`), totals over current non-cancelled members (sessions total; price per
currency), the roster (F-10). The subscription payload gains `bundle` (`{id, kind}`); the subscriptions list gains
filters `bundle` and `bundle_kind`. Session payloads gain `group` (`{bundle_id, name}`) for sessions of a group bundle.
The bundles list filters: kind, student, family, group, `state` (`live`: has a live current member; `ended`).

### 4.6 Errors naming a member

`ConflictError` and `ValidationError` (`etqan.platform.exceptions`) gain an optional `member_id` (additive), which the
exception handler adds to the body when set. A bundle action catches a member's refusal and re-raises it with
`member_id` = that subscription's id, keeping its status (400 / 409), code and field. Example: a group renewal where a
former student's account is now inactive refuses with 400 on `student`, `member_id` set (the office removes that
student first).

## 5. Access

New resource under the B2 marker: `study_group` ("Study groups" / "المجموعات الدراسية", `verbs=ALL_VERBS`), in use:
view, view_any, create, update, delete (TH `group`).

Bundles use `subscription` codes: list `subscription.view_any`, read `subscription.view`, create `subscription.create`,
renew / pause / cancel / members / notes / dissolve `subscription.update`, archive `subscription.delete`, restore
`subscription.restore`.

Teachers, students and parents: 404 on bundle and group routes (an `is_office` check before `HasCode`, as B2d §5);
they see their own subscriptions and sessions with the bundle / group label.

## 6. API (`/api/v1/`)

| Route | Method | Feature | Notes |
|---|---|---|---|
| `groups/`, `groups/<id>/` | GET, POST / GET, PATCH, DELETE | `study_groups` | Study groups. |
| `bundles/multi-course/` | POST | `multi_course_subscriptions` | §4.2. |
| `bundles/family/` | POST | `family_subscriptions` | §4.2. |
| `bundles/group/` | POST | `group_subscriptions` | §4.2. |
| `bundles/` | GET | — (ungated) | List. |
| `bundles/<id>/` | GET, PATCH, DELETE | — | Read; notes; dissolve. |
| `bundles/<id>/renew/`, `pause/`, `cancel/` | POST | — | §4.3. Pause body `{from_date, to_date, reason}`. |
| `bundles/<id>/archive/` | POST, DELETE | `subscription_archive` | Archive / restore. |
| `bundles/<id>/members/` | POST | — | Group: add `{student_id, starts_on}`. |
| `bundles/<id>/members/<student_id>/` | DELETE | — | Group: remove. |

New codes: 409 `scheduling.group_in_use`, `scheduling.nothing_to_renew`; member refusals keep their own codes with
`member_id`.

## 7. Dashboard (`/app/`)

- **Study groups** (`/app/people/groups`, next to families; NAV under the B2 marker with `study_groups` on): list
  (name, members, status), form (name, students multi-select excluding students in other groups, notes, active).
- **Subscriptions → New**: a type choice (individual / multi-course / family / group, by switches) leading to the
  bundle form: the owner (student / family / group), then rows (course, teacher, package, slots; family rows add the
  student). Totals shown live from the chosen packages.
- **Bundle page** (`/app/scheduling/bundles/<id>`): members table (current ones marked), roster tab, notes, actions
  (renew, pause, cancel, archive, add / remove for groups, dissolve), each with a confirm and the refusing member shown.
- **Subscription page:** "Part of bundle …" link; list badge and filters.
- **Sessions / teacher's lists:** a "Group: {name}" label.
- Strings in en and ar in new area files `bundles.json` and `studyGroups.json`; RTL, phone width, semantic tokens.

## 8. Seeds

In `demo`, under the B2 marker, with the four switches among `features.BUILT`: one study group of three students with a
group bundle; one multi-course bundle (two courses, two teachers); one family bundle over the existing demo family.
Idempotent; `other` gets nothing.

## 9. Testing

- **Groups:** one group per student (BR-17); active rules; delete refused in use.
- **Create:** each kind's validation and row rules; re-keyed errors; all-or-nothing rollback; billing per member;
  clashes with F-4.
- **Current members:** a cancelled renewal makes its link current (cancelled, skipped): a removed group student is
  never re-enrolled by a bundle renewal.
- **Actions:** renew (renewals join the bundle via any route; cancelled skipped; nothing to renew; course change
  refused), pause (only members whose term contains the date; freeze cap refuses all), cancel, archive / restore,
  add (template) / remove (with a pending renewal), notes, dissolve, deleting the last member deletes the bundle;
  `member_id` in errors; lock order (SQL capture).
- **Clashes:** group siblings never conflict; a different-time or different-bundle overlap still does.
- **Unchanged reads:** derived numbers, invoices, payroll and notifications of a member equal those of a plain
  subscription.
- **Access & switches:** the code matrix; non-office 404; per-kind create routes 404 when off; ungated routes listed;
  `requires`; cross-academy isolation.
- **Existing suites** pass unchanged.
- **Dashboard:** group form, bundle form per kind, bundle page actions and errors, labels.
- **e2e** (`e2e/b2-bundles.spec.ts`, spec-owned data): the admin creates a study group of two students, creates a
  group bundle for it, sees two subscriptions and same-time sessions without clash warnings, pauses the bundle.

## 10. Known limits (accepted)

- **A group class of N students is paid N times** by today's payroll rule (one row per student, D6; `payroll_sessions`
  unchanged, D9) until B4 decides group pay.
- Postponing or cancelling one student's group session moves or cancels only that row; group-wide session actions use
  the existing bulk route.
- Bundle totals are per currency and only shown, not invoiced as one (billing stays per subscription).
- A bundle does not follow later changes of its study group or family.

## 11. Out of scope

Payment fields on the bundle (B3, ledger D10); student levels on subscriptions (B6); weekly-schedule objects over a
bundle's slots (B2g); group pay (B4); package type individual / group.

## Amendments from plan 37 (2026-10-05)

These are the shipped contract where they differ from the sections above (plan 37 rulings).

- **D5 — Pause and Cancel (§4.3).** Pause applies to every live member whose term holds `from_date`, not only current members. Cancel cancels every live member, both the old link and a pending renewal. With no candidate, pause is a 400 on `from_date`, and cancel is a 409 `scheduling.not_allowed_in_status`.
- **D7 — Course change on renewal (F-6).** A member's renewal that changes course is refused with a 400 on `course` (the body key), not on `course_id`.
- **D13 — New route (§6).** `GET groups/candidates/?q=&group=<id>` answers who may join a study group. It needs `study_group.create` or `study_group.update`, and the `study_groups` feature.
- **D15 — Service signatures (§4.3).** These drop the unused `by`:
  - `pause_bundle`, `cancel_bundle`, `add_to_group_bundle`, `remove_from_group_bundle`, `update_bundle` and `dissolve_bundle` take no `by`.
  - `renew_bundle`, `archive_bundle` and `restore_bundle` take it keyword-only.
- **D1 / ledger D34 — Row error keys.** Errors on bundle rows are keyed `rows.<i>.<field>` (dot form) everywhere, including B3d's group currency refusal on `rows.0.price_minor`.
