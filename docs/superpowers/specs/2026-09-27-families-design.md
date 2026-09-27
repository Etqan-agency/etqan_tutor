# Plan 11 — Family Accounts and Payer — Design

**Date:** 2026-09-27
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B1 (accounts & access), plan 2 of 4 (10 profile depth → **11 families** → 12 roles & permissions → 13 feature toggles).

**Builds on:**
- Plan 3: people, guardianship, the students bulk action, CSV.
- Plan 6 (`2026-09-25-billing-design.md`): the one payer rule, `billing/services/payers.py` (P6-4). It is used by the invoice form's payer choices, manual invoices, and the invoices created automatically for subscriptions.
- Plan 10: the student list filters and the bulk bar.

**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`:
- PEOPLE-001 (the account type, and the bulk "convert to family account" and "create family account" actions);
- PEOPLE-002 (Family accounts: name, linked family-type students each in only one family, the account responsible for payment, notes, active);
- gap rows 921, 926 and A2.

Roadmap rule R4 applies.

## 1. Goal

An academy can group siblings into a family and name who pays for it. New invoices for any student in the family then default to that payer, everywhere billing chooses a payer. This mirrors TutorHamster's family accounts without changing subscriptions or sessions.

## 2. Decisions

| # | Decision |
|---|---|
| F-1 | The family lives in `etqan.identity`, next to guardianship. Billing asks identity for a student's family payer through a service, and the payer rule stays in `billing/services/payers.py`. |
| F-2 | **The payer can be a student or a parent (owner decision):** any student in the family, or any active parent linked to one of those students. |
| F-3 | A student belongs to at most one family. `account_type` (`individual` or `family`) is derived from membership, and the linking services keep it consistent. |
| F-4 | The payer is never silently repointed. When it becomes invalid (the payer student leaves, or the payer parent is deactivated or unlinked), the family is flagged `payer_needs_choosing` until an admin picks a new one. While it is flagged, or while the family is retired, the family supplies no payer. |
| F-5 | Existing invoices never change. Only newly chosen payers follow the new rule. |
| F-6 | Out of scope: family and group subscriptions and rosters (B2), combined family invoices, family wallets and balances (B3), quick-login links (B9), and a family portal login. |

## 3. Data (`etqan.identity`)

### 3.1 Family (new)

| Field | Notes |
|---|---|
| `name` | required, up to 120 characters |
| `notes` | text, admin-only |
| `is_active` | default `true` |
| `payer` | → User (protect). Must be one of the family's students or an active parent of one of them (F-2), checked by the services. |
| `created_at`, `updated_at` | |

### 3.2 StudentProfile (existing)

- `family` → Family, nullable, set null on delete. At most one family per student.
- `account_type` is `individual` or `family`, default `individual`. It is `family` exactly when `family` is set, and the linking services set both together.

### 3.3 Derived: `payer_needs_choosing`

A family's payer is valid when either:
- the payer is an active user who is one of the family's students; or
- the payer is an active parent linked (by guardianship) to one of the family's students.

`payer_needs_choosing` is `not valid`. It is computed when read, never stored.

## 4. Behaviour

### 4.1 Families

- **Create:** `name`, `student_ids` (at least one) and `payer_id`, plus optional notes.
  - Every id must be a student not already in another family, otherwise a 400 on `student_ids`.
  - The payer must be valid for those students (F-2), otherwise a 400 on `payer_id`.
  - Everything is checked before anything is written.
- **Update:**
  - Name, notes and active can change.
  - The payer can change, and must be valid for the resulting student set.
  - `student_ids` replaces the whole set: at least one student, and none in another family. Removed students go back to `individual`.
  - An update may leave the current payer invalid only when `payer_id` isn't part of that update. The family is then flagged (F-4).
- **Retire and restore:** set `is_active`. Links are kept. A retired family supplies no payer.

### 4.2 The payer rule (billing, P6-4 extended)

`payer_choices(student)`, deduplicated, in this order:
1. the family payer, when the student is in an active family whose payer is valid;
2. the student's active guardians, earliest-linked first;
3. the student.

The default payer is still `payer_choices(...)[0]`, and a payer is still valid exactly when it appears in the list. The invoice form's choices label the family payer "Family payer".

### 4.3 Students (people)

- Rows and details gain `account_type` and `family {id, name} | null`.
- The student list gains two filters: `?account_type=individual|family` and `?family=<id>`.
- The students bulk action gains three actions:
  - `create_family` with `{name, payer_id}`, using the selected students;
  - `add_to_family` with `{family_id}`;
  - `remove_from_family`.

  They follow the §4.1 rules. A student who is already in another family is reported and skipped, never moved. The response reports `{updated, skipped: [{id, full_name, reason}]}`.
- The student CSV gains Account type and Family columns.

### 4.4 Who sees what

- Families are admin-only: every other role gets 403. Family notes are admin-only.
- `me/`:
  - a student sees their own family name;
  - a parent sees each child's family name.

## 5. API (`/api/v1/people/`, existing conventions)

| Method | Path | Notes |
|---|---|---|
| GET | `families/` | Paged; `?search=` on the name, `?active=`. Each row: `id, name, is_active, payer {id, full_name, role}, payer_needs_choosing, students [{id, full_name}], notes, created_at`. |
| POST | `families/` | Returns 201 with a fresh read. |
| GET | `families/<id>/` | One family. |
| PATCH | `families/<id>/` | Returns a fresh read. |

There is no DELETE and no PUT. The student payloads, filters, bulk actions and CSV change as described in §4.3.

## 6. Dashboard (`/app/`, en/ar, RTL, phone width)

- **People → Families (admin):**
  - the list shows the name, student chips, the payer (with a "Choose a new payer" warning when flagged), and active;
  - search and an active filter;
  - Add and Edit dialogs:
    - name;
    - a student multi-select, showing students not in another family plus this family's own;
    - a payer select, listing this family's students and their active parents, recomputed when the students change;
    - notes;
  - Retire and Restore.
- **Students list:**
  - an Account type column;
  - a family chip that links to the family;
  - Account type and Family filters;
  - bulk actions Create family (a name and a payer from the selected students and their parents), Add to family and Remove from family, reporting any skipped students.
- **Student form and detail:** show the family as read-only, with a link.
- **Invoice form:** the family payer is listed first as "Family payer".
- **Profile cards:** a student's own card shows the family name; a parent's card shows each child's.
- **Reuse:** the shared helpers. Every string is in en and ar.

## 7. Seeds

In `demo`:
- one family, "Omar family", with two demo students and the parent Omar as payer;
- the other demo students stay individual.

It is idempotent, and `other` gets nothing.

## 8. Testing

- **Rules:**
  - one family per student (a 400 on create, update and bulk; the database also forbids it);
  - an invalid payer is refused;
  - removing the payer student, or deactivating or unlinking the payer parent, flags `payer_needs_choosing`;
  - a retired or flagged family supplies no payer;
  - `account_type` always matches membership.
- **Billing:**
  - a new manual invoice for a family student defaults to the family payer;
  - an explicitly chosen valid payer still wins;
  - a subscription's automatic invoice uses the family payer;
  - existing invoices are unchanged;
  - `payer_choices` has no duplicates when the family payer is also a guardian.
- **Bulk:** create, add and remove, with already-linked students reported.
- **Access and isolation:**
  - families are admin-only, and notes are hidden from `me/`;
  - another academy's families and students are never visible or linkable (tested with `until_pk_exceeds`).
- **Performance:** query counts stay flat on the families list, the student list with families, and `payer_choices`.
- **Dashboard and e2e:**
  - dashboard unit tests;
  - one e2e journey: an admin creates a family from two students with a parent as payer; a new invoice for one student preselects the family payer.

## 9. Risks

| Risk | Mitigation |
|---|---|
| A payer silently pointing at someone who no longer qualifies | Computed validity, a visible flag, and no automatic repointing |
| Two families racing for one student | A database constraint (one family per student) plus a checked 400 |
| Billing depending on identity internals | Billing calls one identity service; `lint-imports` enforces it |

## 10. Out of scope

See F-6.
