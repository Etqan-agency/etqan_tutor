# Plan 10 — Student and Teacher Profile Depth — Design

**Date:** 2026-09-27
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B1 (accounts & access), plan 1 of 4. B1 is split as follows (owner decision):
- 10: profile depth;
- 11: family accounts and payer;
- 12: roles and permissions, with the supervisor role;
- 13: per-academy feature toggles.

Study groups move to B2.

**Builds on:** Plan 3 (`2026-09-24-people-catalogue-design.md`): people, the student and teacher profiles, the statuses (active, trial, in progress, paused, inactive), the students bulk action, CSV, and the staff-only fields.

**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`:
- PEOPLE-001: the student form's tags, XP points, nationality and age group;
- note 15: 21 preset student tags and 22 preset teacher tags, each with an emoji;
- the gap rows 920–922.

Roadmap rule R4 applies.

## 1. Goal

Academies can describe and motivate their people the way TutorHamster does:
- emoji tags on students and teachers (for example "⭐ star of the month", "📖 skilled reader"), which the academy can edit;
- XP points on students;
- a student's nationality;
- an age group derived from the date of birth.

All of these are usable in the lists: they show in rows and can be filtered, exported and bulk-applied.

## 2. Decisions

| # | Decision |
|---|---|
| PD-1 | Everything lives in `etqan.identity`, which owns people. There is no new app. |
| PD-2 | **Tags are editable per academy (owner decision).** Each academy starts with TutorHamster's presets, one list for students and one for teachers. Admins can add, rename, reorder, retire and restore tags. There is no hard delete, so history stays. |
| PD-3 | XP is a plain number, from 0 to 1,000,000, edited by admins, as in TutorHamster. Automatic XP (for example from attendance) is a possible later extra. |
| PD-4 | Nationality is optional: `arab` or `foreign`, as in TutorHamster. |
| PD-5 | The age group is **derived, never stored**. From `date_of_birth` and today on the academy's calendar: `child` is under 13, `teen` is 13–17, and `adult` is 18 and over. It is blank without a date of birth. The `minor` filter means child or teen. |
| PD-6 | Out of scope: the pending status (self-registration, B9), the wallet balance (B3), per-student notification preferences (B5), photos, alias email, postal code, the honour board (B6) and automatic XP. |

## 3. Data (`etqan.identity`)

### 3.1 Tag (new)

| Field | Notes |
|---|---|
| `kind` | `student · teacher` |
| `emoji` | optional, up to 8 characters (a flag or a ZWJ sequence fits) |
| `name_ar`, `name_en` | required, up to 60 characters each |
| `position` | integer, for ordering (unique per kind is not required; ties break by id) |
| `is_active` | default `true`. A retired tag stays on the people who have it but can't be newly assigned. |
| `created_at`, `updated_at` | |

It is unique on (`kind`, `name_en`) and on (`kind`, `name_ar`), compared case-insensitively.

**Seeding:**
- The presets are defined once in code, as the ar/en names and emoji of TutorHamster's 21 student and 22 teacher tags, taken from the audit where known and filled out in the same spirit.
- A data migration seeds them into every existing academy.
- `create_academy` seeds new ones.
- Seeding is idempotent: it skips any tag whose name already exists.

### 3.2 Profiles (existing)

- `StudentProfile.tags` and `TeacherProfile.tags` are many-to-many to `Tag`. The `kind` must match the profile type, and the services enforce it.
- `StudentProfile.xp`: a positive integer, default 0, at most 1,000,000.
- `StudentProfile.nationality`: `arab · foreign`, blank allowed.

## 4. Behaviour

### 4.1 Tags admin

- Admins only (every other role gets 403).
- A duplicate name within the same kind is a 400 on that field.
- Retiring a tag keeps every assignment. Restoring it makes it assignable again.
- The list is ordered by `position`, then `id`, and each row carries the number of active people with the tag.

### 4.2 On people

- **Assigning tags:** `tag_ids` replaces the whole set. A tag of the wrong kind, a retired tag, or an unknown id is a 400 on `tag_ids`. A retired tag the person already has may stay in the set, so editing a person never forces a retired tag off.
- **Filters** (student and teacher lists):
  - `?tag=<id>`, which can be repeated to match any of the tags;
  - for students also `?nationality=arab|foreign`;
  - for students also `?age_group=child|teen|adult|minor`, computed in SQL from `date_of_birth` against the academy's today, so counts and paging stay exact.
- **Bulk:** the students bulk action gains `add_tag` and `remove_tag` with a `tag_id`, using the same rules as assignment.
- **CSV:** the student export gains Tags (emoji and name in the academy's default language, joined), XP, Nationality and Age group. The teacher export gains Tags.

### 4.3 Who sees what

The people endpoints stay admin-only (Plan 3), so every other role gets a 403 there, and only admins change tags, XP or nationality. Non-admins read through `/api/v1/me/`:

| Who | Sees (through `me/`) |
|---|---|
| Student | their own tags, XP and age group |
| Parent | each child's tags, XP and age group, in the `children` summaries |
| Teacher | their own teacher tags |

Nationality is admin-only everywhere. Showing students' tags to their teachers is deferred: no teacher screen shows a student's profile today.


## 5. API (existing `/api/v1/people/` conventions)

| Method | Path | Notes |
|---|---|---|
| GET | `tags/?kind=student\|teacher` | Admins only. Each row: `id, kind, emoji, name_ar, name_en, position, is_active, people`. |
| POST | `tags/` | Admins only. Returns 201 with a fresh read. |
| PATCH | `tags/<id>/` | Admins only: name, emoji, position, active. Returns a fresh read. |

There is no `DELETE` and no `PUT`.

**Changes to the existing person payloads:**
- Student and teacher rows and details gain `tags: [{id, emoji, name_ar, name_en}]`.
- Students also gain `xp`, `nationality` and `age_group`. Nationality is admin-only.
- Create and PATCH accept `tag_ids`, plus `xp` and `nationality` for students.
- The bulk action accepts `add_tag` and `remove_tag` with a `tag_id`.

## 6. Dashboard (`/app/`, en/ar, RTL, phone width)

- **Settings → Tags (admin):**
  - two tabs, Student tags and Teacher tags;
  - each row shows the emoji, the name in the reader's language, the number of people, and Edit, Retire or Restore;
  - an Add tag dialog (emoji, Arabic name, English name);
  - reordering with up and down buttons.
- **Forms:** student and teacher forms gain a Tags multi-select (active tags, plus any retired tag the person already has, which is marked as retired). The student form also gains XP and Nationality.
- **Lists:**
  - tag chips (emoji plus name) in each row;
  - filters for Tag, and for students also Nationality and Age group;
  - the bulk bar gains Add tag and Remove tag.
- **Detail pages:** tags on both. For students, also XP and age group, and nationality for admins only.
- **Student, parent and teacher views:** the student's tags and XP on their own page; the parent's children's; the teacher's own tags on their profile.
- **Reuse:** the shared helpers (Pager, `clean`/`csvUrl`, `applyServerErrors`, `useFieldError`). Every string is in en and ar.

## 7. Seeds

The presets go into every academy. In `demo`:
- demo students and teachers get one or two tags each;
- students get some XP;
- a few students get a nationality and a date of birth, so that child, teen and adult all appear.

It is idempotent, and the `other` academy gets only the presets.

## 8. Testing

- **Tags:**
  - a duplicate name (either language, case-insensitive) is refused;
  - a wrong-kind or retired tag is refused on assignment and in bulk;
  - a retired tag stays on the people who have it, and survives an edit of the person;
  - there is no delete.
- **Age group:**
  - boundaries the day before and the day of turning 13 and 18;
  - the academy's calendar in a timezone whose date differs from UTC's;
  - the `minor` filter;
  - the filters stay exact across pages.
- **Access:**
  - nationality never appears outside admin payloads;
  - `me/` shows a student their own tags, XP and age group, a parent only their children's, and a teacher their own tags;
  - every people and tag endpoint answers 403 to non-admins.
- **Isolation and performance:**
  - another academy's tags are never visible or assignable (with `until_pk_exceeds`);
  - the list's query count stays flat with tags attached.
- **Migration and seeding:** the presets migration seeds existing academies once, and `create_academy` seeds new ones.
- **Dashboard and e2e:**
  - dashboard unit tests for each piece;
  - one e2e journey: an admin creates a tag, tags a student in bulk, and filters by it; the student sees the tag on their page.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Age filters drift at day boundaries | Computed in SQL against the academy's today, with boundary tests in a non-UTC zone |
| N+1 queries from tags on lists | `prefetch_related` and query-count tests |
| Retired tags silently stripped by edits | A retired tag already on a person is allowed to stay, and there's a test for it |

## 10. Out of scope

See PD-6.
