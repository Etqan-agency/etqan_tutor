---
title: "Session reviews and honour board"
---

**Session reviews** are 1–5 star ratings, with an optional comment, of one attended session. The student
or a parent writes them, and the office can also write them. The session's teacher reads them but never
writes them. The **honour board** is a list of recognitions ("Star of the month") per student and month.
The office writes the entries, and teachers, students and parents see the published ones. Both features
live in `etqan.learning` and do not change pay, levels or anything else.

## Concepts

| Model | Key fields | Notes |
|---|---|---|
| `SessionReview` | `session` (one-to-one `scheduling.Session`, CASCADE), `rating`, `comment` (≤ 2000), `written_by` | One review per session. DB check: rating 1–5. A later write replaces the review and records the new writer. |
| `HonourEntry` | `student`, `title` (≤ 120), `message` (≤ 1000), `emoji` (≤ 16 chars, so ZWJ/flag sequences fit), `month` (DB check: the 1st), `is_published`, `created_by` | An entry for a deactivated student stays, as history. |

**Eligible session** (`services/reviews.py:ELIGIBLE`, `_eligible_sessions`) means all of these:
- `status == "completed"`
- `student_attendance == "present"`
- the session has a subscription
- `kind != "trial"`

Scheduling's values are compared as strings. If a session stops being eligible, its review is kept but
left out of every list, count and hook.

## How it works

**Reviews** (`etqan/learning/services/reviews.py`):
- `reviews_queryset(user, …)` scopes by role:
  - Office: all reviews.
  - Teacher: reviews of sessions they are the current teacher of. This is not the live-subscription rule
    used elsewhere in learning.
  - Student: their own sessions' reviews.
  - Parent: their children's sessions' reviews.
  - Anyone else: 404.
- `write_review` creates or replaces the review:
  - It runs in a transaction, locks the existing row, and retries an `IntegrityError` from a concurrent
    create as an update.
  - It checks session eligibility first (400 `session`), then ownership (404), then the rating.
- **Window** (`WINDOW_DAYS = 30`): a student or parent can write or delete only while the academy's today
  is no later than `occurs_on + 30 days`. Outside that, it is 409 `learning.review_window_closed`. The
  office has no window.
- `review_editable` sets the `editable` flag that lists return. `delete_review` refuses teachers (403).
- `reviewable_sessions` returns eligible sessions with no review yet. A student sees their own; a parent
  or the office must pass `student`. Students and parents get only the last 30 days.
- `reviews_average(qs)` adds `average` to the list response.
- Hooks:
  - `reviews_of(student_user_id, *, month)` feeds the monthly student reports.
  - `review_summary(teacher_user_id=…, student_user_id=…, since, until)` exists for teacher-quality
    reads.

**Honour board** (`etqan/learning/services/honour.py`):
- `honour_queryset(user, month=…)`: the office sees every entry. Teachers, students and parents see
  `is_published=True` only. Anyone else sees nothing.
- `create_entry`, `update_entry` (a partial update; the student can be changed) and `delete_entry`. All of
  them are for the office only.
- The board shows the student's name only. It is not on the public marketing site.

## API

All routes are under `/api/v1/learning/`. Each ends with `FeatureOn`.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/learning/reviews/?teacher=&course=&student=&rating=` | `session_review.view_any`; teacher, student, parent (scoped) | Paginated list plus `average` |
| GET | `/api/v1/learning/reviews/reviewable/?student=` | `session_review.update`; student, parent (read) | Sessions still to review |
| GET | `/api/v1/learning/reviews/<id>/` | `session_review.view`; readers in scope | One review |
| DELETE | `/api/v1/learning/reviews/<id>/` | `session_review.delete`; student or parent within the window | Delete |
| PUT | `/api/v1/learning/sessions/<session_id>/review/` | `session_review.update`; student or parent | Create or replace `{rating, comment}` |
| GET | `/api/v1/learning/honour/?month=YYYY-MM` | `honour_entry.view_any`; teacher, student, parent (published only) | Paginated entries |
| POST | `/api/v1/learning/honour/` | `honour_entry.create` | Add an entry |
| PATCH / DELETE | `/api/v1/learning/honour/<id>/` | `honour_entry.update` / `.delete` | Edit / delete |

## Dashboard

| Route file (`dashboard/src/routes/_authed/`) | Who | Component |
|---|---|---|
| `scheduling.reviews.tsx` | Office | `ReviewsList` + `AddReviewDialog`, `ReviewDialog` |
| `teaching.reviews.tsx` | Teacher | `MyReviews` (read-only, with average) |
| `learning.reviews.tsx` | Student / parent | `RateLessons` ("to review" plus "my reviews"; a parent picks a child) |
| `people.honour.tsx` | Office | `HonourAdmin`, `HonourDialog` |
| `teaching.honour.tsx`, `learning.honour.tsx` | Teacher / student / parent | `HonourBoard` (published entries grouped by month) |

Feature folders: `dashboard/src/features/reviews/` (also `StarRating`, `ReviewEditor`) and
`dashboard/src/features/honour/`.

## Background jobs

None. Neither feature sends notifications.

## Configuration

- Switches: `session_reviews` and `honour_board` (both built and off by default).
- Access resources: `session_review` (`view_any`, `view`, `update`, `delete`; `update` is
  create-or-replace) and `honour_entry` (`view_any`, `create`, `update`, `delete`).
- Demo data: `etqan/tenants/seeds/b6.py:seed_b6_reviews`, `seed_b6_honour`.

## Code map

- `backend/etqan/learning/models.py`: `SessionReview`, `HonourEntry`.
- `backend/etqan/learning/services/reviews.py`, `honour.py`.
- `backend/etqan/learning/api/review_views.py`, `honour_views.py`.
- `dashboard/src/features/reviews/`, `dashboard/src/features/honour/`.

Recorded-course reviews and consultation reviews are separate features, in `etqan.recorded` and
`etqan.consultations`.

## Design history

- [B6c spec: reviews and honour board](../superpowers/specs/2026-10-05-b6c-reviews-honour-design.md),
  decisions R-1…R-10.
- [Plan 38](../superpowers/plans/2026-10-05-plan-38-reviews-honour.md).
- R-5 says B4 (teacher quality) reads `review_summary`. Nothing outside learning calls it today. The
  monthly reports use `reviews_of` and compute their own summary in memory.
