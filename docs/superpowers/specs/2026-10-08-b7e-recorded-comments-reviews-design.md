# Slice B7e — Recorded courses: comments and reviews — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (PO-3). Spec-only mode (ledger D45).
**Phase:** B7, slice e (`2026-10-08-b7-add-on-sales-design.md` §3).
**Requires:** B7a and B7b (same phase; the storefront and public catalogue show reviews). Nothing from
other phases.
**Evidence:** P1 RC-004 ("التعليقات") and RC-005 ("التقييمات"). Both are CONFIRMED to exist, but their
fields are UNKNOWN. Everything below is `[assumed]` unless cited.

## 1. Goal

Enrolled students discuss a lesson under its video, and the office answers. Students rate a course they
are enrolled in. After the office's approval, the rating appears on the storefront and the public
catalogue.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| E-1 | **Comments** belong to a published video. A top-level comment is written by a student with an active enrolment in the playlist. A **reply** (one level only: a reply to a reply attaches to the same top-level comment) is written by the office, or by the student who wrote the top-level comment. Other students cannot join a thread [assumed: TutorHamster's behaviour is unknown]. The body is plain text, 1–2 000 characters (D2). | P1 RC-004 · [assumed] |
| E-2 | **Who reads comments:** the office, and students with an active enrolment in the playlist. Each sees the visible comments of a video, oldest first, with replies under them. An author is shown by **first name**, or as "Academy" for the office. First name means the first whitespace-separated token of `User.full_name` (identity has no first-name field), falling back to "Student". Parents do not see comments. | B7-6 · [assumed] |
| E-3 | **Moderation.** The office hides or unhides a comment (`rc_comment.update`) or deletes it (`rc_comment.delete`; its replies go too). A student may delete their own comment or reply. A hidden comment shows to its author with a "Hidden by the academy" note, and to no other student. Hiding a top-level comment hides its whole thread from other students; its author still sees the office's replies. | [assumed] |
| E-4 | **Reviews.** One per student and playlist, while the enrolment is active: rating 1–5 and an optional comment of up to 1 000 characters. A new review starts `pending`. The student may edit it, which sets it back to `pending`, or delete it. The office approves or rejects it (`rc_review.update`), with an optional reason shown to the student. A review stays when its enrolment is revoked, for example after a refund; the office may reject it. The same rule (pending, then approved) holds for consultation reviews (B7d K-12), so both review lists behave alike. | P1 RC-005 · [assumed] |
| E-5 | **Where reviews show.** The storefront detail (B7b S-2) and the public catalogue (B7b S-9) gain `rating_average` and `rating_count`. The average is a Decimal `Avg` over approved reviews, quantized to 2 places ROUND_HALF_UP, and null when there are none; it is computed in one aggregate query with `Count`. They also gain the 5 latest approved reviews. On the **authenticated storefront** each review shows first name, rating, comment and date. On the **public catalogue** the reviewer is shown only as "Student", with no name: many students are minors and these pages are cached and public. This is the one exception to S-9's "no student data": the comments are student text, shown anonymously. Lists show the average and the count. | [assumed]; B7b S-9 |
| E-6 | **Access resources** (under the B7 marker). `rc_comment` ("Recorded course comments" / "تعليقات الدورات المسجلة"): `view_any`, `create` (an office reply), `update`, `delete`. `rc_review` ("Recorded course reviews" / "تقييمات الدورات المسجلة"): `view_any`, `update`. Students pass by role and E-1/E-4 scoping. | P1 permission keys `rc::comments`, `rc::reviews` |
| E-7 | **Notifications** (B7-9). None are sent. `recorded.services.comment_events(*, since, until)` (new comments and replies, with the playlist, video, author user id, `by_office`, and the top-level author's user id) is exported for B5. | ledger D39 |
| E-8 | **Throttling.** Comments use scope `recorded_comment` (`60/hour` per user) and reviews use `recorded_review` (`10/hour`). These are lines in `DEFAULT_THROTTLE_RATES`, which has no phase markers, so they go in the same claimed commit as B7b's `recorded_public` when both slices are built, or under their own claim otherwise. | [assumed] |

## 3. Data

```text
etqan.recorded.Comment
  video      FK PlaylistVideo  CASCADE  related_name="comments"
  parent     FK self null  CASCADE  related_name="replies"   (top-level only: CHECK via service)
  author     FK AUTH_USER  null  SET_NULL  related_name="+"
  by_office  BooleanField
  body       TextField(max 2000)
  hidden     BooleanField(default False); hidden_by FK AUTH_USER null SET_NULL; hidden_at null
  created_at
  indexes (video, created_at)

etqan.recorded.Review
  playlist   FK Playlist  CASCADE  related_name="reviews"
  student    FK identity.StudentProfile  PROTECT  related_name="+"
  rating     PositiveSmallIntegerField 1..5
  comment    TextField(blank, max 1000)
  status     CharField(8) pending | approved | rejected (default pending)
  reason     TextField(blank, max 500)
  decided_by FK AUTH_USER null SET_NULL; decided_at null
  created_at, updated_at
  UNIQUE (playlist, student)
```

A video with comments is not "in use" for B7a's delete rule (A-12): its comments are deleted with it.

## 4. API (`/api/v1/recorded/`)

| Route | Methods | Who |
|---|---|---|
| `my/videos/<id>/comments/` | GET, POST | an enrolled student (E-1, E-2) |
| `my/comments/<id>/` | DELETE | the author |
| `my/comments/<id>/replies/` | POST | the top-level author |
| `my/<playlist id>/review/` | GET, PUT, DELETE | the enrolled student (E-4) |
| `videos/<id>/comments/` | GET | `rc_comment.view_any` |
| `comments/<id>/replies/` | POST | `rc_comment.create` |
| `comments/<id>/` | PATCH (`hidden`), DELETE | `rc_comment.update` / `.delete` |
| `playlists/<id>/reviews/` | GET | `rc_review.view_any` (`?status=`) |
| `reviews/<id>/` | PATCH (`status`, `reason`) | `rc_review.update` |

Every route has `FeatureOn` (`recorded_courses`).

## 5. Screens

- **Student player** (B7a §6): a "Discussion" panel under the video, with a comment box, threads, reply
  and delete. "Rate this course" in the course header opens the review dialog, which shows the review's
  status and reason.
- **Office**: the recorded course page gains **Comments** (by video, with hide, unhide, reply and delete)
  and **Reviews** (pending first, with approve and reject with a reason) tabs. The pending count shows on
  the tab.
- **Storefront and marketing**: E-5's rating and approved reviews.

## 6. Tests

- **Comments.** Who may comment and reply (E-1). The one-level threading. Visibility per role, including a
  hidden comment seen only by its author. Moderation. Cascade deletion. A revoked enrolment losing access.
  The throttle.
- **Reviews.** One per student and playlist. An edit returning it to pending. Approve and reject. Only
  approved reviews counted in the average, rounded to 2 places, and null when there are none. The public
  payload showing first names only.
- **Access.** The E-6 matrix (`in_use` equality). 404 for others. 404 when switched off.
- **`comment_events`.** The window and its query count.
- **Dashboard.** The discussion panel, the review dialog, the office tabs, and ar/en key equality.
- **e2e** (`e2e/b7-recorded-feedback.spec.ts`): the demo student comments on a video, and the office
  replies. The student rates the course, the office approves the rating, and the storefront shows it.
