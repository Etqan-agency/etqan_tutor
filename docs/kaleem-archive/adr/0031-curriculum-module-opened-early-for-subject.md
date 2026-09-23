---
number: 0031
title: Open the curriculum module early to own Subject
status: accepted
date: 2026-09-04
---

## Context

Phase C is scheduling, and its centrepiece is matching a student to a teacher. That
algorithm could not be written, because two of its inputs did not exist anywhere in the
schema:

- Students have stated a `teacher_gender_preference` since Phase A. **Teachers had no
  gender.** The preference was collectable and unsatisfiable for four months.
- kaleem teaches Quran, Tafsir and Arabic, and **there was no subject anywhere** — not on a
  teacher, not on a student, not as a table. Nothing prevented matching a student who wants
  Arabic to a teacher who only teaches Quran.

Gender is `identity`'s own concern and went on `TeacherProfile` without controversy. Subject
did not have an owner. The rebuild roadmap lists `curriculum` as owning `Course`, `Unit`,
`Lesson` — it never mentions `Subject` — and schedules that module several phases away.

## Decision

**Open `curriculum` now, owning `Subject` plus `TeacherSubject` and
`StudentSubjectInterest`.** The module starts as three tables and grows into its roadmap
scope later.

Both link tables live in `curriculum`, not on the identity profiles, and key to
`AUTH_USER_MODEL` by string. That is what keeps the dependency arrow pointing the way the
roadmap specifies: **curriculum → identity**.

`Subject` is a real admin-managed model rather than `TextChoices`, so adding a fourth
subject is a row rather than a migration and a deploy.

## Alternatives considered

**Put `Subject` and the link tables in `identity`.** No new module, no new cross-module
dependency, and matching would read one module. Rejected: `identity` is about people, and it
would then own curriculum taxonomy that has to be handed back — a migration across a module
boundary, which is the most expensive kind to undo.

**Put `Subject` in `platform`.** `platform` is importable by every module, so the boundary
question disappears. Rejected: `platform` is deliberately infrastructure-only and has zero
models today. Its contract is literally *"imports no business modules"*; putting business
reference data there erodes the one module whose independence the whole scheme rests on.

**Put `StudentSubjectInterest` on `StudentProfile` and `TeacherSubject` on
`TeacherProfile`.** Reads naturally and keeps subjects near their owner. Rejected: it makes
`identity` depend on `curriculum` for the FK, inverting the roadmap's module graph. The
inversion is invisible in a diff and expensive later.

**Skip subject entirely; match on gender and availability only.** By far the smallest change.
Rejected: it is a visible product failure rather than a technical one — a student asking for
Arabic gets a Quran teacher.

## Consequences

**Good.**

- Phase C1 can be written. Its inputs exist and are typed.
- The module starts closed: both import-linter contracts were written before any code, and
  the boundary one was verified by breaking it. `scheduling` shipped without that mirror and
  a direct model import there passed CI until 2026-09-04 — this module does not repeat that.
- No JSON blobs and no `OneToOneField`: the links are rows, so a teacher's subjects and a
  student's interests are sets that change over time (rules #3 and #7).

**Bad, or at least owed.**

- A module exists ahead of its roadmap phase, holding three tables and none of the
  `Course`/`Unit`/`Lesson` scope its architecture doc will eventually describe.
- **Phase C1 will need `scheduling → curriculum`**, a dependency the roadmap's module graph
  does not list. That is a real deviation and gets **its own ADR** when C1 is specced — not a
  line in an implementation PR.
- `Subject` as a real model means seeded rows are now part of every environment's expected
  state. The data migration is idempotent (`update_or_create`) so it converges rather than
  failing on a database where someone added a row by hand.
- When `curriculum` grows its roadmap scope, `Subject` will need to relate to `Course`. That
  is additive and was the reason to make it a model rather than an enum.
