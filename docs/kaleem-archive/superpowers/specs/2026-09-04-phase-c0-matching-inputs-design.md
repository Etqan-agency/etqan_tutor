---
name: phase-c0-matching-inputs
phase: C
modules: [identity, curriculum]
status: shipped
created: 2026-09-04
closed: 2026-09-05
---

## Goal

Create the data a teacher–student matcher needs, and nothing else.

Phase C is scheduling. Its centrepiece is matching: given a student, choose a teacher. That
algorithm cannot be written today, because **the inputs it would read do not exist**:

- Students state a `teacher_gender_preference`. **Teachers have no gender.** The preference
  has been collectable since Phase A and has never been satisfiable.
- kaleem teaches Quran, Tafsir and Arabic. **There is no subject anywhere in the schema** —
  not on a teacher, not on a student, not as a table. A matcher has no way to avoid pairing
  a student who wants Arabic with a teacher who only teaches Quran.

So C0 adds those inputs and stops. It contains no matching logic, no booking, no video. It is
the smallest change that turns C1 from impossible into merely hard.

**Why this is its own spec.** Matching, booking-with-quota, and video are three subsystems;
specced together they produce a plan that sprawls and a branch that lives for weeks (D6, D11).
The dependency order is strict — you cannot match on fields that do not exist, cannot book
without an assignment, cannot create a room without a session — so the cut points are given
rather than chosen. C0 is the first.

## Phase numbering

The roadmap labels scheduling **B2**. Phase B closed on 2026-09-04 as billing only, and
`STATE.md` and the journal both use B1/B2 for the two *billing* specs. Reusing "B2" would
collide with a closed record, so scheduling is **Phase C** here. The roadmap document is not
amended by this spec; the discrepancy is noted and nothing else depends on the label.

## Decisions taken

Settled during brainstorming, recorded so the plan does not relitigate them:

1. **Subject is a real model, not an enum.** Admin-manageable, so adding a fourth subject is
   a row rather than a migration and a deploy.
2. **A new `curriculum` module owns it**, opened ahead of the roadmap's phase order. Not
   `identity` (which is about people, and would have to give the taxonomy back later); not
   `platform` (which is infrastructure and deliberately has zero models — putting business
   reference data there erodes the one module whose contract is "imports no business
   modules").
3. **Both join tables live in `curriculum`**, keyed to `AUTH_USER_MODEL` by string. This is
   what keeps the dependency arrow pointing the way the roadmap specifies: curriculum →
   identity. Had `StudentSubjectInterest` lived on the student profile, identity would depend
   on curriculum and the roadmap's module graph would invert.
4. **Teacher gender lives on `TeacherProfile`**, not `User`. Only teachers' gender is needed,
   and only for matching; scoping it to the role means students and parents never carry the
   field at all. That is data minimisation by construction, and it is symmetric with
   `teacher_gender_preference` already living on `StudentProfile`.

## Data model delta

```text
identity.TeacherProfile
  + gender  CharField(choices=male|female, blank default "")   # "" = undeclared

curriculum.Subject                    (new)
    slug        SlugField unique      # quran | tafsir | arabic
    name        CharField
    is_active   BooleanField default True
    created_at / updated_at

curriculum.TeacherSubject             (new)      curriculum.StudentSubjectInterest  (new)
    user     FK AUTH_USER_MODEL                      user     FK AUTH_USER_MODEL
    subject  FK Subject                              subject  FK Subject
    unique_together (user, subject)                  unique_together (user, subject)

  User ─┬─< TeacherSubject >─┐
        └─< StudentSubjectInterest >─┴─ Subject
```

Many-over-time by construction (rule #7): a teacher's taught subjects and a student's
interests are sets that change, so they are rows, not a `OneToOneField` and not a JSON blob
on the profile (rule #3).

**`gender` permits "undeclared", and that is forced, not chosen.** Teacher rows already exist;
a migration cannot invent a value for them, and defaulting every existing teacher to one
gender would be both wrong and, in this product, offensive. So `""` is a real state that C1
must handle: **an undeclared teacher is excluded from a match whose student expressed a
gender preference, and eligible for a student who expressed `no_preference`.** That rule is
stated here so C1 inherits it rather than inventing it.

**Subjects are seeded by data migration** — `quran`, `tafsir`, `arabic` — so a fresh database
and `seed_e2e` both have them without a fixture step.

## API delta

All under `/api/v1/` via `config.api_router` (ADR-0029; a new module mounted straight onto
`config/urls.py` fails `test_api_versioning_is_enforced`).

| Method | Path | Who | Shape |
| --- | --- | --- | --- |
| `GET` | `/subjects/` | any authenticated user | `[{slug, name}]`, active only |
| `GET` / `PUT` | `/me/teacher-subjects/` | teacher | `{subjects: [slug]}` — what they teach |
| `GET` / `PUT` | `/me/student-subjects/` | student | `{subjects: [slug]}` — what they want to study |
| `PATCH` | `/me/teacher-profile/` | teacher | `{gender}` |

**The two subject endpoints are deliberately role-explicit rather than one `/me/subjects/`.**
A person may hold both profiles (the roadmap allows it), so a single endpoint would have to
guess which set a caller meant, or reject the ambiguity with a 400 that has no correct
follow-up. Two paths make the dual-role case ordinary instead of an error, and they mirror the
existing `/me/student-profile/` naming. Each 403s for a caller without the matching profile.

`PUT` replaces the whole set. Unknown slugs and inactive subjects are a typed 400, not a
silent drop (rule #8).

## Frontend

Extends the existing account page rather than adding a route — these are profile attributes,
and `/account` already renders role-conditional panels with exactly this shape.

- **Subjects panel.** Heading differs by role ("Subjects you teach" / "What you want to
  study"); a checkbox group over `GET /subjects/`, saving via `PUT /me/teacher-subjects/` or
  `PUT /me/student-subjects/` according to which panel it is. Loading, empty (no active
  subjects — an admin problem, say so), error, and saved states. A user with both profiles
  sees both panels, independently.
- **Gender field**, teachers only, on the same page: a select with male / female /
  "prefer not to say", the last mapping to `""`. Copy must say why it is asked — it drives
  teacher matching — because a gender field with no stated purpose reads as intrusive.
- Both panels hidden entirely for a parent with neither profile.
- i18n keys in `en` and `ar`, RTL verified. Values from tokens, never hardcoded.

**Done** = built, on staging, clicked through in a real browser.

## Module boundaries

`curriculum` is new and owns all three models. It depends on `identity` only through
`AUTH_USER_MODEL` string references — it imports no identity models and calls
`identity.services` if it needs anything else.

New import-linter contracts, mirroring billing's pair:

- `curriculum imports no business modules except identity` — forbids every business sibling.
- `curriculum does not reach past identity's public API` — `allow_indirect_imports`, forbidding
  a direct `kaleem.identity.models` import, with the tests exemption. **This second contract
  is the one scheduling silently lacked until 2026-09-04**; writing it now is why the new
  module starts closed rather than being retrofitted.

`identity` gains nothing outward-facing: the `gender` field is read by C1 through
`identity.services`, not by importing the model.

**C1 will need `scheduling → curriculum`**, which the roadmap's module graph does not list.
That is a real deviation and gets its own ADR when C1 is specced — not silently in an
implementation PR.

## Out of scope

- **All matching logic.** No `TeacherAssignment`, no ranking, no auto-assignment. C1.
- **Booking, sessions, quota, video.** C2 and C3.
- Course / Unit / Lesson — the rest of `curriculum` per the roadmap. This module starts as
  three tables and grows later.
- Subject *proficiency* or level (a teacher teaching beginner vs advanced Arabic). Real, but
  it is a matching refinement and C1 can add it if the ranking needs it.
- Admin UI beyond Django admin for `Subject`.
- Backfilling gender for existing teachers. They declare it themselves.

## Test plan

TDD throughout (D3): failing test first. Backend floor 97, dashboard 92/87/84 — raise them if
this slice lifts coverage.

**Backend**
- A teacher sets taught subjects; a student sets interests; each reads back exactly.
- `PUT` replaces rather than appends; sending `[]` clears.
- Unknown slug → typed 400. Inactive subject → typed 400. Duplicate slugs in one payload →
  one row, not an IntegrityError.
- Each endpoint 403s for a caller lacking that profile; a user holding **both** profiles can
  set taught subjects and study interests independently, and neither leaks into the other.
- `gender` accepts the two choices and `""`; anything else is a typed 400.
- The data migration seeds exactly three subjects and is idempotent when re-run.
- `test_api_versioning_is_enforced` still passes with the new module mounted.
- **`lint-imports` is verified by breaking it**: a probe `from kaleem.identity.models import
  User` in `curriculum/services.py` must turn the new contract red, and the run must be green
  once removed. A contract nobody has watched fail is not known to work — that is exactly how
  scheduling's hole survived.

**Dashboard** — panel renders per role; save round-trips; server error surfaces; the panel is
absent for a parent; Arabic renders RTL.

**e2e** (D3 requires it for a user-facing area) — a teacher sets subjects and they survive a
reload; a student sets interests and they survive a reload; a parent sees neither panel.
`seed_e2e` must seed subjects, and the accounts it creates must be safe to mutate repeatedly.

## Open questions

None blocking. Two to answer while building, neither of which changes the data model:

- **OQ-C0-1.** Should `GET /subjects/` be public rather than authenticated? A marketing page
  listing subjects would want it. Deferred until something actually needs it.
- **OQ-C0-2.** Does the gender select need a "prefer not to say" option distinct from simply
  never having answered? Both map to `""` today. If C1's matching makes the distinction
  matter — a teacher who declined versus one who has not been asked — it becomes a third
  state and a migration.
