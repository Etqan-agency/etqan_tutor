# Slice B6c — Session Reviews & Honour Board — Design

**Date:** 2026-10-05
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied 2026-10-05.
**Phase spec:** `2026-10-05-b6-learning-design.md` (B6-1…B6-11 bind; §3 row B6c is the contract).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (P1) and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (TH). Both
features' **fields are UNKNOWN** in the audits (P1 SCHED-010, PEOPLE-007: list pages exist, create forms not observed), so
most decisions below are `[assumed]` (ledger D1), kept as small as the audits allow.
**Requires:** B6a (the `etqan.learning` app; B6b's merge is not needed). No other phase's slice.

## 1. Goal

Let the people who sat a lesson rate it, so the office and the teacher see how lessons land; and give the academy an
honour board on which the office recognises students. Both behind switches, off by default.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| R-1 | **A session review** is a 1–5 star rating with an optional comment about **one attended session**, from the student's side. One review per session (a unique row). A student's "own" reviews are the reviews of sessions whose student is them (a parent: their children), whoever wrote them. The student, a parent of the student, or the office writes it; a later write by any of them replaces it and records the new writer in `written_by`. Create-or-replace runs in `transaction.atomic` with the row locked (`select_for_update` then update, else create; an `IntegrityError` from a concurrent create is retried as an update), so a student/parent race never 500s. In group classes (ledger D6) each roster row is its own session, so each student reviews their own row. | P1 SCHED-010 ("تقييمات الحصص", office "إضافة تقييم"; fields UNKNOWN); TH §1.3 #18 (reviews button on the sessions page); TH CNT-005 star scale (1–5 ⭐) · [assumed] fields, one per session, student-side author |
| R-2 | **Eligible sessions**: `status == "completed"` and `student_attendance == "present"` (strings; learning never imports scheduling's models), with a subscription (`subscription_id` not null) and `kind != "trial"` (a string check, a no-op until B2e adds the kind). Others → 400 `session` (checked first). **Window** for students and parents, on both PUT and DELETE: allowed while `academy_today() <= session.occurs_on + 30 days` (`academy_today()` = `scheduling.services.today()`, as B6a), else 409 `learning.review_window_closed` (checked after eligibility). The office has no window. A review whose session later stops being eligible (attendance cleared, cancelled) is kept but left out of every list, count and hook (they all filter on eligibility); deleting the session deletes the review (CASCADE). | [assumed] (scheduling statuses: Plan 5; kinds: ledger D8) |
| R-3 | **Who reads**: the office (with codes); the teacher of the session — the session's **current** `teacher` (`session.teacher.user_id`), not B6-5's live-subscription rule, because a review is about a past lesson — read-only; the student and their parents (their own, R-1). Anyone else → 404. | B6-4 · [assumed] teacher reads own sessions' reviews |
| R-4 | **Who writes/deletes**: the student or a parent of the student (their own, within the window — including a review the office or the other party wrote), and the office (any, any time). Teachers never write or delete. | B6-4 ("session reviews in B6c" are student/parent writes) · [assumed] |
| R-5 | Reviews never change pay, levels or anything else. B4 (teacher quality) and B10 (reports) read them only through `learning.services.review_summary(*, teacher_user_id=None, student_user_id=None, since: date, until: date) -> ReviewSummary(count: int, average: float \| None)` — eligible reviewed sessions with `since <= occurs_on < until` (`occurs_on` is already the academy-local date), `average` rounded to 2 places, `None` when `count == 0` — and `reviews_of(student_user_id, *, month: date) -> list[ReviewMonth(session_id, occurs_on, course_id, course_name_en, course_name_ar, teacher_user_id, teacher_name, rating, comment)]` for eligible reviewed sessions whose `occurs_on` falls in that calendar month, oldest first. Recorded in the ledger, extending D26/D29. | B6-9 |
| R-6 | **The honour board** is a list of **entries**: student\*, title\* (e.g. "Star of the month", ≤ 120), message (optional, ≤ 1000), the month it honours (`month`: first day of a month), emoji (optional, ≤ 8 characters — TH's tags use an emoji), published flag. The office creates, edits, publishes, unpublishes and deletes entries. | P1 PEOPLE-007 (list + "add new honour board"; fields UNKNOWN); TH §3 #12 ("21 emoji tags … and an honor board"), P1 §4.4 student tags · [assumed] fields |
| R-7 | **Who sees the board**: teachers, students and parents see **published** entries, newest month first; the office (admins, and staff holding `honour_entry.view_any`) also sees unpublished ones. The board shows the student's name only (no photo, no contact data); entries of a deactivated student stay (they are history) [assumed]. Showing a student's name to every parent of the academy is a privacy choice, [assumed] from TH's board being academy-wide. Not on the public site (B8 owns it; ledger D2 unaffected). | [assumed] |
| R-8 | Switches (new, under the B6 marker, group `teaching` / `people`): `session_reviews` ("Session reviews" / "تقييمات الحصص") and `honour_board` ("Honour board" / "لوحة الشرف"), built, off. Off → 404 after the role check; records kept. | B6-2; FT-4 |
| R-9 | Access resources (new, under the B6 marker), `in_use` exactly the codes §5 declares: `session_review` ("Session reviews" / "تقييمات الحصص": `view_any`, `view`, `update`, `delete` — `update` is create-or-replace) and `honour_entry` ("Honour board" / "لوحة الشرف": `view_any`, `create`, `update`, `delete`). Student/parent writes and teacher/student/parent reads pass by role + scoping. | P1 permission keys `session::review`, `honor::board` |
| R-10 | No column on any existing table; two new tables in `etqan.learning` (B6-10). B6c sends no notifications (B6-6); `review_events` is not built (B5 has no review notice in COMM-004). | B6-6, B6-10 |

## 3. Data

```text
etqan.learning.SessionReview
  session       OneToOne scheduling.Session  CASCADE  related_name="+"   (a deleted session takes its review)
  rating        PositiveSmallIntegerField  1..5   (CHECK)
  comment       TextField(blank, max 2000)
  written_by    FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at, updated_at
  ordering (-created_at, -id)

etqan.learning.HonourEntry
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  title         CharField(120)  required
  message       TextField(blank, max 1000)
  emoji         CharField(16, blank)   (one emoji; ZWJ / flag sequences fit)
  month         DateField   (CHECK day = 1)
  is_published  BooleanField(default False)
  created_by    FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at, updated_at
  ordering (-month, -id)
```

## 4. Services (`services/reviews.py`, `services/honour.py`)

- `reviews_queryset(user, *, teacher=None, course=None, student=None, rating=None)`; `get_review(user, id)`.
- `reviewable_sessions(user, *, student_user_id=None)` — the caller's (or child's) sessions eligible under R-2 within the
  window and without a review, newest first (for the student/parent page).
- `write_review(*, session_id, rating, comment="", by)` — create or replace (R-1, R-2, R-4); 400 `rating` outside 1–5.
- `delete_review(review, *, by)` — R-4.
- `review_summary(...)`, `reviews_of(...)` — R-5.
- `honour_queryset(user, *, month=None)`; `create_entry`, `update_entry`, `delete_entry` (office); `month` must be a
  first-of-month date (400 `month`); the student must be a student (400 `student`).

## 5. API (`/api/v1/learning/`, `FeatureOn` last)

| Method & path | Permission (staff code) | Feature |
|---|---|---|
| `GET reviews/?teacher=&course=&student=&rating=&page=` | `HasCode \| (ReadOnly & ReadsOwn)` — `session_review.view_any` | `session_reviews` |
| `GET reviews/<id>/` | same — `session_review.view` | `session_reviews` |
| `PUT sessions/<session_id>/review/` | `HasCode \| IsStudent \| IsParent` — `session_review.update` (create or replace) | `session_reviews` |
| `DELETE reviews/<id>/` | `HasCode \| IsStudent \| IsParent` — `session_review.delete` | `session_reviews` |
| `GET reviews/reviewable/?student=` | `HasCode \| (ReadOnly & (IsStudent \| IsParent))` — `session_review.update` (it lists what the caller may review) | `session_reviews` |
| `GET honour/?month=` | `HasCode \| (ReadOnly & ReadsOwn)` — `honour_entry.view_any` (teachers, students, parents read published) | `honour_board` |
| `POST honour/`, `PATCH honour/<id>/`, `DELETE honour/<id>/` | `HasCode` — `honour_entry.create` / `update` / `delete` | `honour_board` |

Students are addressed by **user id**. `reviewable/`: a student omits `student` (self); a parent and the office must pass it
(a parent only for their child, else 404); the office gets no window filter. `ROUTES` / `FEATURES` gain every row above;
`FEATURE_WORDS` gains `"/learning/reviews": "session_reviews"`, `"/review/": "session_reviews"`,
`"/learning/honour": "honour_board"`. Numeric query params use B6a's ASCII-only `_int_param`. Review item: `{id, session:{id, occurs_on, course:{id,name_en,name_ar},
teacher:{id,full_name}, student:{id,full_name}}, rating, comment, written_by:{id,full_name}|null, created_at, updated_at}`.
Honour item: `{id, student:{id, full_name}, title, message, emoji, month, is_published}`.

## 6. Screens (dashboard `src/features/reviews/`, `src/features/honour/`; locale areas `reviews.json`, `honour.json`)

| Who | Where | What |
|---|---|---|
| Office | Scheduling → Session reviews `/scheduling/reviews` (`session_review.view_any`, `session_reviews`) | List: date · student · teacher · course · stars · comment; filters teacher, course, rating; open → edit / delete; "Add review" picks a completed session (by student) and writes it. |
| Teacher | Teaching → My reviews `/teaching/reviews` | Read-only list of reviews of their sessions with the average. |
| Student / parent | Learning → Rate lessons `/learning/reviews` | "To review" (eligible sessions) with a star picker + comment; "My reviews" (edit / delete within the window); parent picks a child. |
| Office | People → Honour board `/people/honour` (`honour_entry.view_any`, `honour_board`) | Entries by month; add / edit (student, title, emoji, message, month, published), publish toggle, delete. |
| Teacher / student / parent | Teaching → Honour board `/teaching/honour`, Learning → Honour board `/learning/honour` (feature `honour_board`) | Published entries grouped by month (emoji, title, student name, message). The office reads the same board from its People screen. |

## 7. Seeds and tests

- `seed_b6` gains: one review on a completed demo session (if any) and two honour entries for the current month (one
  published).
- Backend: R-1…R-9 rules (eligibility incl. excused/absent/not completed/no subscription, window day 30 allowed and day 31 refused for PUT and DELETE, an ineligible-after-review session dropped from lists and hooks, concurrent replace, window edge for student and none for office,
  replace keeps one row and updates `written_by`, scoping per role incl. teacher reading only their sessions and parent
  child / not child, delete rights, rating bounds), `review_summary` / `reviews_of`, honour CRUD + month rule + published
  visibility per role; route tables; seed.
- Dashboard: each screen per role; star picker accessibility (radio group); locale parity.
- e2e `e2e/b6-reviews.spec.ts`: switches on; a student rates a completed session; the office sees it; the teacher sees it in
  My reviews; the office publishes an honour entry; the student sees it on the board.
