---
number: "0002"
title: Single User with per-role profile tables
status: accepted
date: 2026-04-12
---

## Context
The old MVP used Django multi-table inheritance (Student(User), Teacher(User), Parent(User)), causing duplicate role sources, painful re-hydration queries, and preventing a person from having multiple roles.

## Decision
Single `User` model (via allauth) plus optional `StudentProfile`, `TeacherProfile`, `ParentProfile` tables as OneToOne. A user can have multiple profiles. Admin is `User.is_staff=True`.

## Alternatives considered
- **Multi-table inheritance**: rejected — the old code's approach, caused all the problems.
- **JSON blobs on User**: rejected — no schema, no queries, no validation.

## Consequences
- One person, one email, one password, one session.
- A teacher who is also a parent has both profiles.
- Clean FK semantics (user.teacher_profile.students).
- No re-hydration queries.
