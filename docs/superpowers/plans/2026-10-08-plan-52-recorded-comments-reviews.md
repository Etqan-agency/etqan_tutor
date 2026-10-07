# Plan 52 — B7e Recorded Courses: Comments and Reviews — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrolled students discuss each lesson under its video, with replies from the office (and from the comment's own author). Students rate a course they are enrolled in, and the office approves or rejects each rating. Approved ratings then appear on the authenticated storefront with first names, and anonymously on the public catalogue and the marketing pages.

**Architecture:** The B7a app `etqan.recorded` gains two tables:

- `Comment`: one-level threads per video, hidden or visible.
- `Review`: one per student and playlist, pending, approved or rejected.

Two service modules come with them: `services/comments.py` (posting, threading, visibility, moderation, `comment_events`) and `services/reviews.py` (my review, the office decision, `ratings_for`, `latest_reviews`). The B7b storefront and public-catalogue dataclasses gain a rating and the latest approved reviews.

Views live in one new module, `api/feedback_views.py`. The student routes sit under `my/`, the office routes under `videos/`, `comments/`, `playlists/` and `reviews/`.

On the dashboard, the player gains a discussion panel and a review dialog, the course page gains Comments and Reviews tabs, and the store shows ratings. The marketing pages show the average, the count and anonymous approved reviews.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest + RTL; Astro + Vitest (AstroContainer); Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7e-recorded-comments-reviews-design.md` (E-1…E-8, §3–§6). Phase decisions come from `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md` (B7-6, B7-7, B7-9, §4). B7b S-2 and S-9 are in `docs/superpowers/specs/2026-10-08-b7b-selling-recorded-courses-design.md`. Read all three before any task.

**Requires:** B7a (plan 49, `docs/superpowers/plans/2026-10-08-plan-49-recorded-courses.md`) and B7b (plan 51, `docs/superpowers/plans/2026-10-08-plan-51-selling-recorded-courses.md`). Both must be merged first. Nothing is needed from other phases.

**Written in spec-only mode** (ledger D45, 2026-10-08). No stack existed when this plan was written, so no command below has been run. Build only after B7a and B7b have merged and the conductor has given B7 a slot.

## Global Constraints

- Branches. Create `feat/b7e-recorded-feedback` in the meta worktree, `backend/`, `dashboard/` and `marketing/`:
  - each submodule: `git fetch origin && git switch -c feat/b7e-recorded-feedback origin/main`;
  - meta: `origin/master`.
  - Never run `git submodule update` or any `git submodule` command that writes.
- Command prefixes, after `set -a; . ./.env.stream; set +a` in the meta worktree:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>`
  - `F <cmd>` = the same with the `dashboard` service
  - `M <cmd>` = the same with the `marketing` service
  - Whole suites: `just test`, `just lint`, `just e2e …`, `just migrate`, `just seed`.
- Reuse the names from plans 49 and 51 exactly:
  - `etqan/recorded/services/` is a package whose `services/__init__.py` re-exports and keeps `__all__`;
  - `can_watch`, `enrolment_for`, `get_video`, `get_playlist`;
  - `services/store.py`: `StoreItem`, `StoreDetail`, `_detail`, `storefront`, `store_detail`, `public_playlists`, `public_playlist`;
  - `api/serializers.py`: `_url`, `store_item`, `store_detail_data`, `public_playlist_data`;
  - `api/params.py` `int_param`;
  - test helpers `as_user`, `png`, and the fixtures `people` and `course` in `tests/conftest.py`;
  - dashboard `src/features/recorded/` (`schemas.ts`, `api.ts`, `queries.ts`, `fixtures.ts`, `index.ts`, `CoursePlayer.tsx`, `PlaylistPage.tsx`, `Store.tsx`, `StoreDetail.tsx`) and `locales/{en,ar}/recorded.json`, which has no wrapper: the file name is the area and keys read `recorded.*`;
  - marketing `src/lib/recorded.ts` and the pages under `src/pages/[lang]/recorded-courses/`.
- Imports. `etqan.recorded` keeps plan 49's contract; B7e adds no import of another app.
- Ids. People are addressed by **user id** in the API. `Review.student` is a `StudentProfile` (resolved with `identity.services.get_student_profile` through B7a's enrolment row).
- Text is plain (D2). Bodies are stripped. Comments are 1–2 000 characters, review comments at most 1 000, reasons at most 500.
- **First name** = the first whitespace-separated token of `User.full_name`, falling back to `"Student"` (E-2). The office is shown as "Academy" (dashboard string, keyed on `by_office`).
- The public payloads carry **no reviewer name** (E-5).
- Migrations only create B7's own tables (B7-14).
- Shared files outside the B7 markers each change in **one commit** under a ledger claim, released right after (from the meta worktree):
  - `python3 scripts/orchestration/ledger.py claim B7 <path> --reason "<why>"` … commit … `python3 scripts/orchestration/ledger.py release B7 <path>`;
  - the files are `backend/config/settings/base.py` (`DEFAULT_THROTTLE_RATES`) and `marketing/src/lib/i18n.ts`.
- Strings: en and ar only, key-equal (D22).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Stage explicit paths only; never `git commit -a`.

## Review Focus

1. **A student reading what they should not:**
   - another student's hidden comment;
   - the replies under someone else's hidden thread;
   - any comment after their enrolment is revoked.

   Expected: absent, or 404 after revocation. The author alone still sees their hidden comment with the note, and the office's replies under it. Pinned in Task 2, `test_visibility_rules` and `test_revoked_enrolment_loses_the_discussion`.
2. **A reply to a reply, or a student replying in another student's thread.** Expected: the reply attaches to the top-level comment, so there is never a second level. A student who is not the thread's author gets 403. Pinned in Task 2, `test_replies_stay_one_level` and `test_only_the_author_and_the_office_reply`.
3. **The average on a half-way value, and the reviews that must not count.** Expected:
   - 4.625 becomes `4.63` (ROUND_HALF_UP, not banker's);
   - pending and rejected reviews are not counted;
   - no approved reviews gives `null` and a count of 0.

   Pinned in Task 3, `test_average_rounds_half_up_over_approved_only`.
4. **A student editing an approved review to sneak new text onto the storefront.** Expected: the edit returns it to `pending`, so it leaves the public lists until approved again. Pinned in Task 3, `test_edit_returns_to_pending`, and Task 4, `test_store_shows_approved_only`.
5. **The public catalogue leaking a reviewer's name.** Expected: the public list and detail carry `rating`, `comment` and `date` only, while the authenticated storefront also carries `name`. Pinned in Task 4, `test_public_reviews_are_anonymous`.

---

## File Structure

```text
backend/etqan/recorded/
  models.py                          + Comment, Review
  migrations/0003_comments_reviews.py   (generated)
  services/
    comments.py                      first_name, post_comment, reply_as_student, reply_as_office,
                                     student_threads, office_threads, delete_own_comment,
                                     set_comment_hidden, delete_comment, get_comment,
                                     CommentEvent, comment_events
    reviews.py                       Rating, NO_RATING, my_review, save_my_review, delete_my_review,
                                     playlist_reviews, get_review, decide_review, ratings_for,
                                     rating_of, latest_reviews
    store.py                         StoreItem.rating; StoreDetail.rating/reviews; _detail(...)
    __init__.py                      re-exports
  api/
    feedback_views.py                student and office comment / review routes
    serializers.py                   comment_data, thread_data, my_review_data, office_review_data,
                                     store additions (rating_average, rating_count, reviews)
    urls.py                          + routes
  tests/
    test_feedback_models.py test_comments.py test_reviews.py test_store_ratings.py
    test_api_feedback.py test_api_feedback_office.py
Modified: backend/etqan/access/registry.py (B7 marker), backend/etqan/access/tests/test_routes.py
Modified (claim): backend/config/settings/base.py

dashboard/src/features/recorded/
  schemas.ts api.ts queries.ts fixtures.ts index.ts   (+ feedback types, calls, hooks)
  Discussion.tsx Discussion.test.tsx  ReviewDialog.tsx ReviewDialog.test.tsx
  CommentsTab.tsx CommentsTab.test.tsx  ReviewsTab.tsx ReviewsTab.test.tsx
  RatingSummary.tsx RatingSummary.test.tsx
  CoursePlayer.tsx PlaylistPage.tsx Store.tsx StoreDetail.tsx   (modified)
dashboard/src/locales/{en,ar}/recorded.json
dashboard/e2e/b7-recorded-feedback.spec.ts

marketing/src/lib/recorded.ts                         type, validator, ratingText
marketing/src/pages/[lang]/recorded-courses/index.astro, [slug].astro   (rating, reviews)
marketing/test/recorded.test.ts
Modified (claim): marketing/src/lib/i18n.ts
```

---

### Task 1: The comment and review tables

**Files:**
- Modify: `backend/etqan/recorded/models.py`
- Generate: `backend/etqan/recorded/migrations/0003_comments_reviews.py`
- Test: `backend/etqan/recorded/tests/test_feedback_models.py`

**Interfaces:**
- Produces: `Comment` (fields per spec §3, `related_name` `comments` on the video and `replies` on the parent), and `Review` with `Review.Status` = `pending | approved | rejected` and the constraints `recorded_review_one_per_student`, `recorded_review_rating_range`, and `recorded_comment_body_not_empty`.

- [ ] **Step 1: Write the failing model tests**

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.recorded import services
from etqan.recorded.models import Comment
from etqan.recorded.models import Review

pytestmark = pytest.mark.django_db


@pytest.fixture
def lesson(people, course):
    pl = course()
    video = pl.videos.filter(status="published").first()
    return pl, video


def test_one_review_per_student_and_playlist(people, lesson):
    pl, _ = lesson
    Review.objects.create(playlist=pl, student=people.profile, rating=5)
    with pytest.raises(IntegrityError), transaction.atomic():
        Review.objects.create(playlist=pl, student=people.profile, rating=4)


@pytest.mark.parametrize("rating", [0, 6])
def test_rating_is_one_to_five(people, lesson, rating):
    pl, _ = lesson
    with pytest.raises(IntegrityError), transaction.atomic():
        Review.objects.create(playlist=pl, student=people.profile, rating=rating)


def test_comment_body_not_empty_and_replies_cascade(people, lesson):
    _, video = lesson
    with pytest.raises(IntegrityError), transaction.atomic():
        Comment.objects.create(video=video, author=people.student, body="")
    top = Comment.objects.create(video=video, author=people.student, body="Q?")
    Comment.objects.create(video=video, parent=top, author=people.student, body="Also")
    top.delete()
    assert not Comment.objects.exists()


def test_deleting_a_video_deletes_its_comments(people, lesson):
    pl, video = lesson
    Comment.objects.create(video=video, author=people.student, body="Q?")
    services.delete_video(video)  # no watches: allowed (B7a A-12)
    assert not Comment.objects.exists()
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_feedback_models.py -q`
Expected: FAIL with `ImportError: cannot import name 'Comment'`.

- [ ] **Step 3: Add the models** (append to `models.py`)

```python
class Comment(models.Model):
    """B7e E-1…E-3: a lesson's discussion. One level: a reply's parent is a
    top-level comment (the services attach a reply to a reply to its top)."""

    video = models.ForeignKey(
        PlaylistVideo, on_delete=models.CASCADE, related_name="comments"
    )
    parent = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.CASCADE, related_name="replies"
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    by_office = models.BooleanField(default=False)
    body = models.TextField(max_length=2000)
    hidden = models.BooleanField(default=False)
    hidden_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    hidden_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ("created_at", "id")
        indexes = [models.Index(fields=["video", "created_at"])]
        constraints = [
            models.CheckConstraint(
                condition=~Q(body=""), name="recorded_comment_body_not_empty"
            )
        ]

    def __str__(self):
        return f"Comment<{self.video_id}, {self.pk}>"


class Review(models.Model):
    """B7e E-4: one rating per student and course, approved by the office."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"

    playlist = models.ForeignKey(
        Playlist, on_delete=models.CASCADE, related_name="reviews"
    )
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True, default="", max_length=1000)
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.PENDING
    )
    reason = models.TextField(blank=True, default="", max_length=500)
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at", "id")
        constraints = [
            models.UniqueConstraint(
                fields=["playlist", "student"], name="recorded_review_one_per_student"
            ),
            models.CheckConstraint(
                condition=Q(rating__gte=1) & Q(rating__lte=5),
                name="recorded_review_rating_range",
            ),
        ]
        indexes = [models.Index(fields=["playlist", "status"])]

    def __str__(self):
        return f"Review<{self.playlist_id}, {self.student_id}, {self.status}>"
```

`models.py` already imports `settings`, `MinValueValidator`, `MaxValueValidator`, `models`, `Q` and `timezone` (plan 49 Task 1).

Generate the migration: `B python manage.py makemigrations recorded --name comments_reviews`, then `just migrate`. Check that it creates only the two tables and their indexes and constraints.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded/tests/test_feedback_models.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/models.py etqan/recorded/migrations/0003_comments_reviews.py etqan/recorded/tests/test_feedback_models.py
git -C backend commit -m "feat(recorded): B7e comment and review tables" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Comment services — posting, threads, visibility, moderation, events

**Files:**
- Create: `backend/etqan/recorded/services/comments.py`, `backend/etqan/recorded/tests/test_comments.py`
- Modify: `backend/etqan/recorded/services/__init__.py`

**Interfaces:**
- Consumes: `can_watch(user, video) -> bool` (plan 49: a student, an active enrolment, a published video in a published playlist); `is_office(user)`; `get_video(pk)`.
- Produces:
  - `first_name(user | None) -> str`
  - `post_comment(user, video_id, body) -> Comment`
  - `reply_as_student(user, comment_id, body) -> Comment` and `reply_as_office(user, comment_id, body) -> Comment` (both attach to the top-level comment)
  - `Thread(comment, replies: list[Comment])`, `student_threads(user, video_id) -> list[Thread]` and `office_threads(video_id) -> list[Thread]`
  - `delete_own_comment(user, comment_id) -> None`, `set_comment_hidden(comment, hidden: bool, *, by) -> Comment`, `delete_comment(comment) -> None`, `get_comment(pk) -> Comment`
  - `CommentEvent(comment_id, playlist_id, video_id, author_user_id, by_office, parent_id, top_author_user_id, at)` and `comment_events(*, since, until) -> list[CommentEvent]` (one query, window `[since, until)`).

- [ ] **Step 1: Write the failing tests** (`tests/test_comments.py`)

```python
from datetime import timedelta

import pytest
from django.utils import timezone

from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import services
from etqan.recorded.models import Comment

pytestmark = pytest.mark.django_db


@pytest.fixture
def lesson(people, course, api_for):
    pl = course()
    video = pl.videos.filter(status="published").order_by("position").first()
    admin = api_for("admin").user
    for user in (people.student, people.other):
        services.enrol_by_office(
            playlist=pl, student_user_id=user.pk, method="free", amount_minor=0, by=admin
        )
    return pl, video, admin


def ids(threads):
    return [(t.comment.pk, [r.pk for r in t.replies]) for t in threads]


def test_first_name():
    class U:
        full_name = "  Yusuf Omar  "

    class Blank:
        full_name = ""

    assert services.first_name(U()) == "Yusuf"
    assert services.first_name(Blank()) == "Student"
    assert services.first_name(None) == "Student"


def test_post_and_read(people, lesson):
    _, video, _ = lesson
    c = services.post_comment(people.student, video.pk, "  What is idgham?  ")
    assert (c.body, c.by_office, c.parent_id) == ("What is idgham?", False, None)
    assert ids(services.student_threads(people.other, video.pk)) == [(c.pk, [])]


@pytest.mark.parametrize("body", ["", "   ", "x" * 2001])
def test_body_limits(people, lesson, body):
    _, video, _ = lesson
    with pytest.raises(ValidationError) as err:
        services.post_comment(people.student, video.pk, body)
    assert err.value.field == "body"


def test_only_enrolled_students_on_published_lessons(people, lesson, course, api_for):
    pl, video, _ = lesson
    draft = pl.videos.filter(status="draft").first()
    with pytest.raises(NotFoundError):
        services.post_comment(people.student, draft.pk, "Q?")
    stranger = api_for("student").user
    with pytest.raises(NotFoundError):
        services.post_comment(stranger, video.pk, "Q?")
    with pytest.raises(NotFoundError):
        services.student_threads(people.parent, video.pk)


def test_replies_stay_one_level(people, lesson):
    """Review Focus 2."""
    _, video, admin = lesson
    top = services.post_comment(people.student, video.pk, "Q?")
    office = services.reply_as_office(admin, top.pk, "Answer")
    again = services.reply_as_student(people.student, office.pk, "Thanks")
    assert office.parent_id == top.pk and again.parent_id == top.pk
    assert office.by_office is True and again.by_office is False
    assert ids(services.student_threads(people.student, video.pk)) == [
        (top.pk, [office.pk, again.pk])
    ]


def test_only_the_author_and_the_office_reply(people, lesson):
    """Review Focus 2."""
    _, video, _ = lesson
    top = services.post_comment(people.student, video.pk, "Q?")
    with pytest.raises(ForbiddenError):
        services.reply_as_student(people.other, top.pk, "Me too")


def test_visibility_rules(people, lesson):
    """Review Focus 1."""
    _, video, admin = lesson
    mine = services.post_comment(people.student, video.pk, "Hidden question")
    answer = services.reply_as_office(admin, mine.pk, "Private answer")
    other = services.post_comment(people.other, video.pk, "Visible")
    services.set_comment_hidden(mine, True, by=admin)
    # The author still sees the hidden thread and the office's reply.
    assert ids(services.student_threads(people.student, video.pk)) == [
        (mine.pk, [answer.pk]), (other.pk, []),
    ]
    # Others see neither the hidden comment nor the replies under it.
    assert ids(services.student_threads(people.other, video.pk)) == [(other.pk, [])]
    # A hidden reply in a visible thread: only its author sees it.
    reply = services.reply_as_student(people.other, other.pk, "Edit")
    services.set_comment_hidden(reply, True, by=admin)
    assert ids(services.student_threads(people.student, video.pk))[1] == (other.pk, [])
    assert ids(services.student_threads(people.other, video.pk)) == [(other.pk, [reply.pk])]
    # The office sees everything.
    assert ids(services.office_threads(video.pk)) == [
        (mine.pk, [answer.pk]), (other.pk, [reply.pk]),
    ]
    services.set_comment_hidden(mine, False, by=admin)
    assert ids(services.student_threads(people.other, video.pk))[0] == (mine.pk, [answer.pk])


def test_revoked_enrolment_loses_the_discussion(people, lesson):
    """Review Focus 1."""
    pl, video, admin = lesson
    c = services.post_comment(people.student, video.pk, "Q?")
    services.revoke(services.enrolment_for(people.student.pk, pl.pk), by=admin)
    with pytest.raises(NotFoundError):
        services.student_threads(people.student, video.pk)
    with pytest.raises(NotFoundError):
        services.delete_own_comment(people.student, c.pk)


def test_delete_own_and_moderation(people, lesson):
    _, video, admin = lesson
    top = services.post_comment(people.student, video.pk, "Q?")
    services.reply_as_office(admin, top.pk, "A")
    with pytest.raises(NotFoundError):
        services.delete_own_comment(people.other, top.pk)
    services.delete_own_comment(people.student, top.pk)
    assert not Comment.objects.exists()
    again = services.post_comment(people.student, video.pk, "Q2")
    hidden = services.set_comment_hidden(again, True, by=admin)
    assert hidden.hidden_by == admin and hidden.hidden_at is not None
    shown = services.set_comment_hidden(again, False, by=admin)
    assert (shown.hidden, shown.hidden_by, shown.hidden_at) == (False, None, None)
    services.delete_comment(again)
    assert not Comment.objects.exists()


def test_comment_events(people, lesson, django_assert_num_queries):
    pl, video, admin = lesson
    before = timezone.now() - timedelta(seconds=1)
    top = services.post_comment(people.student, video.pk, "Q?")
    reply = services.reply_as_office(admin, top.pk, "A")
    after = timezone.now() + timedelta(seconds=1)
    with django_assert_num_queries(1):
        events = services.comment_events(since=before, until=after)
    assert [(e.comment_id, e.parent_id, e.by_office, e.top_author_user_id) for e in events] == [
        (top.pk, None, False, people.student.pk),
        (reply.pk, top.pk, True, people.student.pk),
    ]
    assert {(e.playlist_id, e.video_id) for e in events} == {(pl.pk, video.pk)}
    assert events[1].author_user_id == admin.pk
    assert services.comment_events(since=after, until=after + timedelta(hours=1)) == []
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_comments.py -q`
Expected: FAIL with `AttributeError: module 'etqan.recorded.services' has no attribute 'first_name'`.

- [ ] **Step 3: Implement** `services/comments.py`

```python
"""B7e E-1…E-3, E-7: a lesson's discussion. A student with an active
enrolment writes under a published lesson; the office and the thread's own
author reply; one level only. Hidden comments are seen by their author and
the office; a hidden top-level comment hides its thread from other students."""

from dataclasses import dataclass
from datetime import datetime

from django.db import transaction
from django.utils import timezone

from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded.models import Comment
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.services.scope import can_watch

BODY_MAX = 2000


@dataclass(frozen=True)
class Thread:
    comment: Comment
    replies: list


@dataclass(frozen=True)
class CommentEvent:
    comment_id: int
    playlist_id: int
    video_id: int
    author_user_id: int | None
    by_office: bool
    parent_id: int | None
    top_author_user_id: int | None
    at: datetime


def first_name(user) -> str:
    """E-2: the first token of the full name; identity has no first name."""
    parts = (getattr(user, "full_name", "") or "").split()
    return parts[0] if parts else "Student"


def _body(body) -> str:
    text = (body or "").strip()
    if not text:
        raise ValidationError("Write a comment.", field="body")
    if len(text) > BODY_MAX:
        raise ValidationError(f"Keep it to {BODY_MAX} characters.", field="body")
    return text


def _watchable(user, video_id) -> PlaylistVideo:
    video = PlaylistVideo.objects.select_related("playlist").filter(pk=video_id).first()
    if video is None or not can_watch(user, video):
        raise NotFoundError("Video", video_id)
    return video


def _sees(user, c: Comment) -> bool:
    """E-3, for a student: their own; else not hidden and, for a reply, not
    under a hidden thread unless the thread is theirs."""
    if c.author_id == user.pk:
        return True
    if c.hidden:
        return False
    top = c.parent
    return top is None or not top.hidden or top.author_id == user.pk


def _threads(rows, keep) -> list[Thread]:
    tops: dict[int, Thread] = {}
    for c in rows:
        if c.parent_id is None and keep(c):
            tops[c.pk] = Thread(c, [])
    for c in rows:
        if c.parent_id in tops and keep(c):
            tops[c.parent_id].replies.append(c)
    return list(tops.values())


def _rows(video_id):
    return list(
        Comment.objects.filter(video_id=video_id)
        .select_related("author", "parent")
        .order_by("created_at", "id")
    )


def student_threads(user, video_id) -> list[Thread]:
    _watchable(user, video_id)
    return _threads(_rows(video_id), lambda c: _sees(user, c))


def office_threads(video_id) -> list[Thread]:
    if not PlaylistVideo.objects.filter(pk=video_id).exists():
        raise NotFoundError("Video", video_id)
    return _threads(_rows(video_id), lambda c: True)


def post_comment(user, video_id, body) -> Comment:
    video = _watchable(user, video_id)
    return Comment.objects.create(
        video=video, author=user, by_office=False, body=_body(body)
    )


def get_comment(pk) -> Comment:
    row = Comment.objects.select_related("parent", "author", "video").filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Comment", pk)
    return row


def reply_as_student(user, comment_id, body) -> Comment:
    """E-1: only the top-level comment's author replies (besides the office)."""
    target = get_comment(comment_id)
    top = target.parent or target
    _watchable(user, top.video_id)
    if not _sees(user, top):
        raise NotFoundError("Comment", comment_id)
    if top.author_id != user.pk:
        raise ForbiddenError("Only the comment's author and the academy reply here.")
    return Comment.objects.create(
        video_id=top.video_id, parent=top, author=user, by_office=False, body=_body(body)
    )


def reply_as_office(user, comment_id, body) -> Comment:
    target = get_comment(comment_id)
    top = target.parent or target
    return Comment.objects.create(
        video_id=top.video_id, parent=top, author=user, by_office=True, body=_body(body)
    )


def delete_own_comment(user, comment_id) -> None:
    """E-3: a student deletes their own comment or reply (its replies go too)."""
    row = get_comment(comment_id)
    if row.author_id != user.pk:
        raise NotFoundError("Comment", comment_id)
    _watchable(user, row.video_id)
    row.delete()


@transaction.atomic
def set_comment_hidden(comment, hidden: bool, *, by) -> Comment:
    row = Comment.objects.select_for_update().get(pk=comment.pk)
    row.hidden = hidden
    row.hidden_by = by if hidden else None
    row.hidden_at = timezone.now() if hidden else None
    row.save(update_fields=["hidden", "hidden_by", "hidden_at"])
    return row


def delete_comment(comment) -> None:
    Comment.objects.filter(pk=comment.pk).delete()


def comment_events(*, since, until) -> list[CommentEvent]:
    """E-7 (for B5, D39): comments and replies created in [since, until),
    aware UTC, oldest first, in one query."""
    rows = (
        Comment.objects.filter(created_at__gte=since, created_at__lt=until)
        .select_related("video", "parent")
        .order_by("created_at", "id")
    )
    return [
        CommentEvent(
            comment_id=c.pk,
            playlist_id=c.video.playlist_id,
            video_id=c.video_id,
            author_user_id=c.author_id,
            by_office=c.by_office,
            parent_id=c.parent_id,
            top_author_user_id=(c.parent.author_id if c.parent else c.author_id),
            at=c.created_at,
        )
        for c in rows
    ]
```

Re-export from `services/__init__.py` and add to `__all__`: `Thread`, `CommentEvent`, `first_name`, `post_comment`, `reply_as_student`, `reply_as_office`, `student_threads`, `office_threads`, `delete_own_comment`, `set_comment_hidden`, `delete_comment`, `get_comment`, `comment_events`.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded/tests/test_comments.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/services/comments.py etqan/recorded/services/__init__.py etqan/recorded/tests/test_comments.py
git -C backend commit -m "feat(recorded): B7e lesson discussion services" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Review services — my review, the office decision, ratings

**Files:**
- Create: `backend/etqan/recorded/services/reviews.py`, `backend/etqan/recorded/tests/test_reviews.py`
- Modify: `backend/etqan/recorded/services/__init__.py`

**Interfaces:**
- Consumes: `enrolment_for(student_user_id, playlist_id)` (active only); `role_of`.
- Produces:
  - `Rating(average: Decimal | None, count: int)` and `NO_RATING`
  - `my_review(user, playlist_id) -> Review | None`, `save_my_review(user, playlist_id, *, rating, comment="") -> Review`, `delete_my_review(user, playlist_id) -> None`
  - `playlist_reviews(playlist_id, status="") -> QuerySet[Review]` (pending first, then newest), `get_review(pk) -> Review`, `decide_review(review, *, status, reason="", by) -> Review`
  - `ratings_for(playlist_ids) -> dict[int, Rating]` (one query), `rating_of(playlist_id) -> Rating`, `latest_reviews(playlist_id, limit=5) -> list[Review]` (approved, student's user selected)

- [ ] **Step 1: Write the failing tests** (`tests/test_reviews.py`)

```python
from decimal import Decimal

import pytest

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import services
from etqan.recorded.models import Review

pytestmark = pytest.mark.django_db


@pytest.fixture
def enrolled(people, course, api_for):
    pl = course()
    admin = api_for("admin").user
    services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free", amount_minor=0, by=admin
    )
    return pl, admin


def test_save_and_read_my_review(people, enrolled):
    pl, _ = enrolled
    assert services.my_review(people.student, pl.pk) is None
    r = services.save_my_review(people.student, pl.pk, rating=4, comment="  Clear.  ")
    assert (r.rating, r.comment, r.status) == (4, "Clear.", "pending")
    assert services.my_review(people.student, pl.pk) == r


@pytest.mark.parametrize(
    ("rating", "comment", "field"),
    [(0, "", "rating"), (6, "", "rating"), (None, "", "rating"), (3, "x" * 1001, "comment")],
)
def test_limits(people, enrolled, rating, comment, field):
    pl, _ = enrolled
    with pytest.raises(ValidationError) as err:
        services.save_my_review(people.student, pl.pk, rating=rating, comment=comment)
    assert err.value.field == field


def test_only_an_enrolled_student(people, enrolled, api_for):
    pl, admin = enrolled
    with pytest.raises(NotFoundError):
        services.save_my_review(people.other, pl.pk, rating=5)
    with pytest.raises(NotFoundError):
        services.my_review(people.parent, pl.pk)
    services.save_my_review(people.student, pl.pk, rating=5)
    services.revoke(services.enrolment_for(people.student.pk, pl.pk), by=admin)
    with pytest.raises(NotFoundError):
        services.save_my_review(people.student, pl.pk, rating=1)
    # E-4: the review stays when the enrolment is revoked.
    assert Review.objects.count() == 1


def test_edit_returns_to_pending(people, enrolled):
    """Review Focus 4."""
    pl, admin = enrolled
    r = services.save_my_review(people.student, pl.pk, rating=5)
    services.decide_review(r, status="rejected", reason="Off topic", by=admin)
    again = services.save_my_review(people.student, pl.pk, rating=3, comment="Better")
    assert (again.pk, again.status, again.reason, again.decided_by) == (r.pk, "pending", "", None)


def test_decide(people, enrolled):
    pl, admin = enrolled
    r = services.save_my_review(people.student, pl.pk, rating=5)
    with pytest.raises(ValidationError) as err:
        services.decide_review(r, status="pending", by=admin)
    assert err.value.field == "status"
    with pytest.raises(ValidationError) as err:
        services.decide_review(r, status="rejected", reason="x" * 501, by=admin)
    assert err.value.field == "reason"
    done = services.decide_review(r, status="approved", by=admin)
    assert (done.status, done.decided_by) == ("approved", admin)
    assert done.decided_at is not None


def test_delete_my_review(people, enrolled):
    pl, _ = enrolled
    services.delete_my_review(people.student, pl.pk)  # none: a no-op
    services.save_my_review(people.student, pl.pk, rating=5)
    services.delete_my_review(people.student, pl.pk)
    assert not Review.objects.exists()


def _students(n):
    return [
        identity_services.create_person("student", full_name=f"S{i} Last")
        for i in range(n)
    ]


def test_average_rounds_half_up_over_approved_only(people, course, api_for, django_assert_num_queries):
    """Review Focus 3: 37 / 8 = 4.625 → 4.63 (half up, not banker's 4.62)."""
    pl = course()
    other = course(slug="other", code="OT")
    admin = api_for("admin").user
    for user, rating in zip(_students(8), [5, 5, 5, 5, 5, 5, 5, 2], strict=True):
        services.enrol_by_office(
            playlist=pl, student_user_id=user.pk, method="free", amount_minor=0, by=admin
        )
        r = services.save_my_review(user, pl.pk, rating=rating)
        services.decide_review(r, status="approved", by=admin)
    for user, status in zip(_students(2), ["pending", "rejected"], strict=True):
        services.enrol_by_office(
            playlist=pl, student_user_id=user.pk, method="free", amount_minor=0, by=admin
        )
        r = services.save_my_review(user, pl.pk, rating=1)
        if status == "rejected":
            services.decide_review(r, status="rejected", by=admin)
    with django_assert_num_queries(1):
        ratings = services.ratings_for([pl.pk, other.pk])
    assert ratings[pl.pk] == services.Rating(Decimal("4.63"), 8)
    assert other.pk not in ratings
    assert services.rating_of(other.pk) == services.NO_RATING == services.Rating(None, 0)


def test_latest_and_office_list(people, enrolled):
    pl, admin = enrolled
    r = services.save_my_review(people.student, pl.pk, rating=4, comment="Good")
    assert services.latest_reviews(pl.pk) == []
    services.decide_review(r, status="approved", by=admin)
    assert [x.pk for x in services.latest_reviews(pl.pk)] == [r.pk]
    assert [x.pk for x in services.playlist_reviews(pl.pk, status="approved")] == [r.pk]
    assert list(services.playlist_reviews(pl.pk, status="pending")) == []
    with pytest.raises(ValidationError):
        list(services.playlist_reviews(pl.pk, status="nope"))
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_reviews.py -q`
Expected: FAIL with `AttributeError: module 'etqan.recorded.services' has no attribute 'my_review'`.

- [ ] **Step 3: Implement** `services/reviews.py`

```python
"""B7e E-4, E-5: one review per student and course, pending until the office
approves it; only approved reviews count. The average is exact: a Decimal
AVG, quantized once to 2 places ROUND_HALF_UP."""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP
from decimal import Decimal

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Avg
from django.db.models import Case
from django.db.models import Count
from django.db.models import DecimalField
from django.db.models import IntegerField
from django.db.models import Value
from django.db.models import When
from django.utils import timezone

from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.recorded.models import Review
from etqan.recorded.services.watching import enrolment_for

COMMENT_MAX = 1000
REASON_MAX = 500
LATEST = 5
CENT = Decimal("0.01")


@dataclass(frozen=True)
class Rating:
    average: Decimal | None
    count: int


NO_RATING = Rating(None, 0)


def _enrolment(user, playlist_id):
    """A student with an active enrolment in a published course; else 404."""
    if role_of(user) != "student":
        raise NotFoundError("Recorded course", playlist_id)
    e = enrolment_for(user.pk, playlist_id)
    if e is None or not e.playlist.is_published:
        raise NotFoundError("Recorded course", playlist_id)
    return e


def my_review(user, playlist_id) -> Review | None:
    e = _enrolment(user, playlist_id)
    return Review.objects.filter(playlist_id=playlist_id, student_id=e.student_id).first()


def _rating(value) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 5:
        raise ValidationError("Choose 1 to 5 stars.", field="rating")
    return value


def _comment(text) -> str:
    text = (text or "").strip()
    if len(text) > COMMENT_MAX:
        raise ValidationError(f"Keep it to {COMMENT_MAX} characters.", field="comment")
    return text


@transaction.atomic
def save_my_review(user, playlist_id, *, rating, comment="") -> Review:
    """E-4: create or edit; an edit goes back to pending."""
    e = _enrolment(user, playlist_id)
    values = {
        "rating": _rating(rating),
        "comment": _comment(comment),
        "status": Review.Status.PENDING,
        "reason": "",
        "decided_by": None,
        "decided_at": None,
    }
    mine = Review.objects.select_for_update().filter(
        playlist_id=playlist_id, student_id=e.student_id
    )
    row = mine.first()
    if row is None:
        try:
            with transaction.atomic():
                return Review.objects.create(
                    playlist_id=playlist_id, student_id=e.student_id, **values
                )
        except IntegrityError:
            row = mine.get()  # a second tab saved first: edit theirs
    for key, value in values.items():
        setattr(row, key, value)
    row.save()
    return row


def delete_my_review(user, playlist_id) -> None:
    e = _enrolment(user, playlist_id)
    Review.objects.filter(playlist_id=playlist_id, student_id=e.student_id).delete()


def playlist_reviews(playlist_id, status=""):
    qs = Review.objects.filter(playlist_id=playlist_id).select_related("student__user")
    if status:
        if status not in Review.Status.values:
            raise ValidationError("Unknown status.", field="status")
        qs = qs.filter(status=status)
    pending_first = Case(
        When(status=Review.Status.PENDING, then=Value(0)),
        default=Value(1),
        output_field=IntegerField(),
    )
    return qs.order_by(pending_first, "-updated_at", "-id")


def get_review(pk) -> Review:
    row = Review.objects.select_related("student__user").filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Review", pk)
    return row


@transaction.atomic
def decide_review(review, *, status, reason="", by) -> Review:
    if status not in (Review.Status.APPROVED, Review.Status.REJECTED):
        raise ValidationError("Approve or reject.", field="status")
    reason = (reason or "").strip()
    if len(reason) > REASON_MAX:
        raise ValidationError(f"Keep it to {REASON_MAX} characters.", field="reason")
    row = Review.objects.select_for_update().get(pk=review.pk)
    row.status, row.reason = status, reason
    row.decided_by, row.decided_at = by, timezone.now()
    row.save()
    return row


def ratings_for(playlist_ids) -> dict[int, Rating]:
    """E-5: approved reviews' exact average and count per course, one query.
    Courses with none are absent (callers use NO_RATING)."""
    rows = (
        Review.objects.filter(
            playlist_id__in=list(playlist_ids), status=Review.Status.APPROVED
        )
        .values("playlist_id")
        .annotate(
            avg=Avg("rating", output_field=DecimalField(max_digits=10, decimal_places=6)),
            n=Count("id"),
        )
    )
    return {
        r["playlist_id"]: Rating(
            Decimal(r["avg"]).quantize(CENT, rounding=ROUND_HALF_UP), r["n"]
        )
        for r in rows
    }


def rating_of(playlist_id) -> Rating:
    return ratings_for([playlist_id]).get(playlist_id, NO_RATING)


def latest_reviews(playlist_id, limit=LATEST) -> list[Review]:
    return list(
        Review.objects.filter(playlist_id=playlist_id, status=Review.Status.APPROVED)
        .select_related("student__user")
        .order_by("-decided_at", "-id")[:limit]
    )
```

`decimal_places=6` keeps an exact four-place AVG before the single quantize. PostgreSQL's `AVG` over an integer column returns `numeric`, so no float is ever involved. If the generated SQL casts to a narrower `numeric`, raise `decimal_places` and confirm `4.625` still comes back exact.

Re-export from `services/__init__.py` and add to `__all__`: `Rating`, `NO_RATING`, `my_review`, `save_my_review`, `delete_my_review`, `playlist_reviews`, `get_review`, `decide_review`, `ratings_for`, `rating_of`, `latest_reviews`.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded/tests/test_reviews.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/services/reviews.py etqan/recorded/services/__init__.py etqan/recorded/tests/test_reviews.py
git -C backend commit -m "feat(recorded): B7e course reviews and ratings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Ratings and approved reviews on the storefront and the public catalogue (E-5)

**Files:**
- Modify: `backend/etqan/recorded/services/store.py`, `backend/etqan/recorded/api/serializers.py`
- Create: `backend/etqan/recorded/tests/test_store_ratings.py`

**Interfaces:**
- Consumes: `ratings_for`, `rating_of`, `latest_reviews`, `NO_RATING`, `first_name`.
- Produces:
  - `StoreItem.rating: Rating` (default `NO_RATING`); `StoreDetail.rating: Rating` and `StoreDetail.reviews: tuple[Review, ...]`. Both have defaults, so plan 51's positional constructions keep working.
  - JSON: `StoreItemJSON` and the public JSON gain `rating_average: str | null` (two decimals, for example `"4.63"`) and `rating_count: int`. `StoreDetailJSON` gains `reviews: [{name, rating, comment, date}]`. The public JSON gains `reviews: [{rating, comment, date}]`, with **no** name. The public list carries `reviews: []`; only the detail fills it.

- [ ] **Step 1: Write the failing tests** (`tests/test_store_ratings.py`)

```python
import pytest
from rest_framework.test import APIClient

from etqan.recorded import services
from etqan.recorded.tests.conftest import as_user

pytestmark = pytest.mark.django_db


@pytest.fixture
def reviewed(people, course, api_for):
    pl = course()
    admin = api_for("admin").user
    for user in (people.student, people.other):
        services.enrol_by_office(
            playlist=pl, student_user_id=user.pk, method="free", amount_minor=0, by=admin
        )
    people.student.full_name = "Yusuf Omar"
    people.student.save(update_fields=["full_name"])
    approved = services.save_my_review(people.student, pl.pk, rating=5, comment="Great")
    services.decide_review(approved, status="approved", by=admin)
    services.save_my_review(people.other, pl.pk, rating=1, comment="Pending text")
    return pl


def test_store_shows_approved_only(people, reviewed):
    """Review Focus 4."""
    item = as_user(people.student).get("/api/v1/recorded/store/").json()[0]
    assert (item["rating_average"], item["rating_count"]) == ("5.00", 1)
    detail = as_user(people.student).get(f"/api/v1/recorded/store/{reviewed.pk}/").json()
    assert detail["reviews"] == [
        {"name": "Yusuf", "rating": 5, "comment": "Great", "date": detail["reviews"][0]["date"]}
    ]
    assert "Pending text" not in str(detail)


def test_public_reviews_are_anonymous(people, reviewed):
    """Review Focus 5."""
    listed = APIClient().get("/api/v1/recorded/public/playlists/").json()[0]
    assert (listed["rating_average"], listed["rating_count"], listed["reviews"]) == ("5.00", 1, [])
    detail = APIClient().get("/api/v1/recorded/public/playlists/tajweed/").json()
    assert [set(r) for r in detail["reviews"]] == [{"rating", "comment", "date"}]
    assert "Yusuf" not in str(detail)


def test_no_reviews_is_null(people, course):
    pl = course()
    item = as_user(people.student).get("/api/v1/recorded/store/").json()[0]
    assert (item["rating_average"], item["rating_count"]) == (None, 0)
    detail = APIClient().get(f"/api/v1/recorded/public/playlists/{pl.slug}/").json()
    assert detail["reviews"] == []
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_store_ratings.py -q`
Expected: FAIL with `KeyError: 'rating_average'`.

- [ ] **Step 3: Implement**

`services/store.py`. Import from the new module and widen the two dataclasses with defaulted fields:

```python
from etqan.recorded.services.reviews import NO_RATING
from etqan.recorded.services.reviews import Rating
from etqan.recorded.services.reviews import latest_reviews
from etqan.recorded.services.reviews import rating_of
from etqan.recorded.services.reviews import ratings_for


@dataclass(frozen=True)
class StoreItem:
    playlist: object
    net_minor: int
    enrolled: bool
    rating: Rating = NO_RATING


@dataclass(frozen=True)
class StoreDetail:
    playlist: object
    net_minor: int
    enrolled: bool
    outline: list
    rating: Rating = NO_RATING
    reviews: tuple = ()
```

Replace `storefront`, `_detail` and `public_playlists` with:

```python
def storefront(user, student_user_id=None) -> list[StoreItem]:
    sid = buyer_student_id(user, student_user_id)
    enrolled = _enrolled_ids(sid)
    playlists = list(for_sale())
    ratings = ratings_for([p.pk for p in playlists])
    return [
        StoreItem(p, net_price(p), p.pk in enrolled, ratings.get(p.pk, NO_RATING))
        for p in playlists
    ]


def _detail(playlist, enrolled: bool, *, rating=None, with_reviews=True) -> StoreDetail:
    """B7e E-5: the detail carries the rating and the latest approved reviews;
    a list item carries the rating only (its reviews stay empty)."""
    return StoreDetail(
        playlist,
        net_price(playlist),
        enrolled,
        outline(playlist),
        rating=rating if rating is not None else rating_of(playlist.pk),
        reviews=tuple(latest_reviews(playlist.pk)) if with_reviews else (),
    )


def public_playlists() -> list[StoreDetail]:
    playlists = list(for_sale()[:PUBLIC_MAX])
    ratings = ratings_for([p.pk for p in playlists])
    return [
        _detail(p, False, rating=ratings.get(p.pk, NO_RATING), with_reviews=False)
        for p in playlists
    ]
```

`store_detail` and `public_playlist` keep calling `_detail(playlist, …)` unchanged. They get the rating and the reviews by default.

`api/serializers.py`. Add a helper and extend the three store serializers:

```python
from etqan.recorded.services import first_name


def _average(rating) -> str | None:
    return None if rating.average is None else f"{rating.average:.2f}"


def _review(r, *, named: bool) -> dict:
    data = {"rating": r.rating, "comment": r.comment, "date": r.created_at.date().isoformat()}
    if named:
        data = {"name": first_name(r.student.user), **data}
    return data
```

In `store_item(item)`, add these two keys to the returned dict:

```python
        "rating_average": _average(item.rating),
        "rating_count": item.rating.count,
```

In `store_detail_data(detail)`, add:

```python
        "reviews": [_review(r, named=True) for r in detail.reviews],
```

In `public_playlist_data(detail)`, after `data.pop("enrolled")`:

```python
    data["reviews"] = [_review(r, named=False) for r in detail.reviews]
```

If importing `first_name` from `etqan.recorded.services` into `serializers.py` creates an import cycle, import it from `etqan.recorded.services.comments` instead.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded -q`
Expected: PASS. That includes plan 51's store and public tests, which compare whole dicts only where they build them from these serializers. If one of them asserts an exact key set, add the three new keys there.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/services/store.py etqan/recorded/api/serializers.py etqan/recorded/tests/test_store_ratings.py etqan/recorded/tests
git -C backend commit -m "feat(recorded): B7e ratings and approved reviews in the store and catalogue" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The student API and the throttles (E-1…E-4, E-8)

**Files:**
- Create: `backend/etqan/recorded/api/feedback_views.py`, `backend/etqan/recorded/tests/test_api_feedback.py`
- Modify: `backend/etqan/recorded/api/serializers.py`, `backend/etqan/recorded/api/urls.py`, `backend/etqan/access/tests/test_routes.py` (`SELF_SERVICE`)
- Modify (claim): `backend/config/settings/base.py` (`DEFAULT_THROTTLE_RATES`)

**Interfaces:**
- Produces these routes, all with `[IsStudent, FeatureOn]` and `feature = "recorded_courses"`. Parents get 403 from the role check (E-2: parents do not see comments).

  | Route | Answer |
  |---|---|
  | `GET my/videos/<id>/comments/` | `[ThreadJSON]` |
  | `POST my/videos/<id>/comments/` | `{body}` → 201 `ThreadJSON` |
  | `DELETE my/comments/<id>/` | 204 |
  | `POST my/comments/<id>/replies/` | `{body}` → 201 `CommentJSON` |
  | `GET my/<playlist id>/review/` | `MyReviewJSON` or `null` |
  | `PUT my/<playlist id>/review/` | `{rating, comment?}` → 200 `MyReviewJSON` |
  | `DELETE my/<playlist id>/review/` | 204 |

- JSON shapes, used by Task 7:
  - `CommentJSON = {id, parent, author_name, by_office, mine, body, hidden, created_at}`, where `author_name` is the first name, or `""` for the office;
  - `ThreadJSON = CommentJSON + {replies: [CommentJSON]}`;
  - `MyReviewJSON = {id, rating, comment, status, reason, updated_at}`.
- Throttles: comment writes use `recorded_comment` (`60/hour`) and review writes use `recorded_review` (`10/hour`). Reads are never throttled.

- [ ] **Step 1: Write the failing tests** (`tests/test_api_feedback.py`)

```python
import pytest

from etqan.recorded import services
from etqan.recorded.tests.conftest import as_user

pytestmark = pytest.mark.django_db
M = "/api/v1/recorded/my/"


@pytest.fixture
def lesson(people, course, api_for):
    pl = course()
    video = pl.videos.filter(status="published").order_by("position").first()
    admin = api_for("admin").user
    for user in (people.student, people.other):
        services.enrol_by_office(
            playlist=pl, student_user_id=user.pk, method="free", amount_minor=0, by=admin
        )
    return pl, video, admin


def test_discussion_round_trip(people, lesson):
    pl, video, admin = lesson
    client = as_user(people.student)
    made = client.post(f"{M}videos/{video.pk}/comments/", {"body": "Q?"}, format="json")
    assert made.status_code == 201, made.content
    thread = made.json()
    assert {k: thread[k] for k in ("body", "by_office", "mine", "hidden", "replies", "parent")} == {
        "body": "Q?", "by_office": False, "mine": True, "hidden": False, "replies": [], "parent": None,
    }
    services.reply_as_office(admin, thread["id"], "A")
    seen = as_user(people.other).get(f"{M}videos/{video.pk}/comments/").json()
    assert seen[0]["mine"] is False
    assert [r["by_office"] for r in seen[0]["replies"]] == [True]
    assert seen[0]["replies"][0]["author_name"] == ""
    reply = client.post(f"{M}comments/{thread['id']}/replies/", {"body": "Thanks"}, format="json")
    assert (reply.status_code, reply.json()["parent"]) == (201, thread["id"])
    other = as_user(people.other).post(f"{M}comments/{thread['id']}/replies/", {"body": "x"}, format="json")
    assert other.status_code == 403
    assert client.delete(f"{M}comments/{thread['id']}/").status_code == 204


def test_bad_body_is_400(people, lesson):
    _, video, _ = lesson
    resp = as_user(people.student).post(f"{M}videos/{video.pk}/comments/", {"body": " "}, format="json")
    assert (resp.status_code, list(resp.json())) == (400, ["body"])


def test_review_round_trip(people, lesson):
    pl, _, _ = lesson
    client = as_user(people.student)
    assert client.get(f"{M}{pl.pk}/review/").json() is None
    resp = client.put(f"{M}{pl.pk}/review/", {"rating": 4, "comment": "Good"}, format="json")
    assert resp.status_code == 200, resp.content
    assert {k: resp.json()[k] for k in ("rating", "comment", "status", "reason")} == {
        "rating": 4, "comment": "Good", "status": "pending", "reason": "",
    }
    bad = client.put(f"{M}{pl.pk}/review/", {"rating": 9}, format="json")
    assert (bad.status_code, list(bad.json())) == (400, ["rating"])
    assert client.delete(f"{M}{pl.pk}/review/").status_code == 204


def test_access(people, lesson, api_for, set_features):
    pl, video, _ = lesson
    assert as_user(people.parent).get(f"{M}videos/{video.pk}/comments/").status_code == 403
    assert as_user(people.parent).get(f"{M}{pl.pk}/review/").status_code == 403
    assert api_for("admin").get(f"{M}videos/{video.pk}/comments/").status_code == 403
    stranger = as_user(api_for("student").user)
    assert stranger.get(f"{M}videos/{video.pk}/comments/").status_code == 404
    assert stranger.put(f"{M}{pl.pk}/review/", {"rating": 5}, format="json").status_code == 404
    set_features(recorded_courses=False)
    assert as_user(people.student).get(f"{M}videos/{video.pk}/comments/").status_code == 404


def test_comment_throttle_is_60_an_hour(people, lesson):
    _, video, _ = lesson
    client = as_user(people.student)
    url = f"{M}videos/{video.pk}/comments/"
    codes = [client.post(url, {"body": f"c{i}"}, format="json").status_code for i in range(61)]
    assert codes[:60] == [201] * 60 and codes[60] == 429
    assert client.get(url).status_code == 200  # reads are not throttled


def test_review_throttle_is_10_an_hour(people, lesson):
    pl, _, _ = lesson
    client = as_user(people.student)
    codes = [
        client.put(f"{M}{pl.pk}/review/", {"rating": 5}, format="json").status_code
        for _ in range(11)
    ]
    assert codes[:10] == [200] * 10 and codes[10] == 429
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_api_feedback.py -q`
Expected: FAIL (404: the routes are missing).

- [ ] **Step 3: Claim, edit, commit and release `base.py`** (the throttle scopes)

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/config/settings/base.py --reason "B7e E-8: throttle scopes recorded_comment, recorded_review"
```

In `DEFAULT_THROTTLE_RATES`, after B7b's `"recorded_public": "60/minute",` line:

```python
        # B7e E-8: per user, writes only.
        "recorded_comment": "60/hour",
        "recorded_review": "10/hour",
```

```bash
git -C backend add config/settings/base.py
git -C backend commit -m "chore(settings): recorded_comment and recorded_review throttle scopes (B7e)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/config/settings/base.py
```

- [ ] **Step 4: Implement**

`api/serializers.py`. Append:

```python
class BodyInput(serializers.Serializer):
    body = serializers.CharField(allow_blank=True, max_length=4000, trim_whitespace=False)


class ReviewInput(serializers.Serializer):
    rating = serializers.IntegerField(required=False, allow_null=True, default=None)
    comment = serializers.CharField(required=False, allow_blank=True, default="", max_length=2000)


class DecideInput(serializers.Serializer):
    status = serializers.CharField(max_length=12)
    reason = serializers.CharField(required=False, allow_blank=True, default="", max_length=1000)


class HiddenInput(serializers.Serializer):
    hidden = serializers.BooleanField()


def comment_data(c, viewer, *, office: bool = False) -> dict:
    data = {
        "id": c.pk,
        "parent": c.parent_id,
        "author_name": "" if c.by_office else first_name(c.author),
        "by_office": c.by_office,
        "mine": c.author_id == viewer.pk,
        "body": c.body,
        "hidden": c.hidden,
        "created_at": c.created_at.isoformat(),
    }
    if office:
        data["author_full_name"] = c.author.full_name if c.author else ""
    return data


def thread_data(thread, viewer, *, office: bool = False) -> dict:
    return {
        **comment_data(thread.comment, viewer, office=office),
        "replies": [comment_data(r, viewer, office=office) for r in thread.replies],
    }


def my_review_data(r) -> dict | None:
    if r is None:
        return None
    return {
        "id": r.pk,
        "rating": r.rating,
        "comment": r.comment,
        "status": r.status,
        "reason": r.reason,
        "updated_at": r.updated_at.isoformat(),
    }


def office_review_data(r) -> dict:
    return {
        "id": r.pk,
        "student": {"id": r.student.user_id, "full_name": r.student.user.full_name},
        "rating": r.rating,
        "comment": r.comment,
        "status": r.status,
        "reason": r.reason,
        "created_at": r.created_at.isoformat(),
        "decided_at": r.decided_at.isoformat() if r.decided_at else None,
    }
```

`api/feedback_views.py` (the student part; Task 6 appends the office views):

```python
"""B7e: a lesson's discussion and a course's reviews. Students act on their
own (role check, then E-1…E-4 scoping in the services, 404 outside it);
parents get 403 (E-2). Writes are throttled per user (E-8); reads are not."""

from django.http import Http404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import IsStudent
from etqan.recorded import services
from etqan.recorded.api import serializers as s

FEATURE = "recorded_courses"
STUDENT = [IsStudent, FeatureOn]
READS = ("GET", "HEAD", "OPTIONS")


def _valid(serializer_class, request) -> dict:
    data = serializer_class(data=request.data)
    data.is_valid(raise_exception=True)
    return dict(data.validated_data)


class _Throttled(APIView):
    """E-8: the view's scope applies to writes only."""

    throttle_scope = ""

    def get_throttles(self):
        if self.request.method in READS or not self.throttle_scope:
            return []
        return [ScopedRateThrottle()]


class MyVideoCommentsView(_Throttled):
    feature = FEATURE
    permission_classes = STUDENT
    throttle_scope = "recorded_comment"

    def get(self, request, pk):
        try:
            threads = services.student_threads(request.user, pk)
        except NotFoundError:
            raise Http404 from None
        return Response([s.thread_data(t, request.user) for t in threads])

    def post(self, request, pk):
        body = _valid(s.BodyInput, request)["body"]
        try:
            c = services.post_comment(request.user, pk, body)
        except NotFoundError:
            raise Http404 from None
        return Response(
            s.thread_data(services.Thread(c, []), request.user),
            status=status.HTTP_201_CREATED,
        )


class MyCommentView(APIView):
    feature = FEATURE
    permission_classes = STUDENT

    def delete(self, request, pk):
        try:
            services.delete_own_comment(request.user, pk)
        except NotFoundError:
            raise Http404 from None
        return Response(status=status.HTTP_204_NO_CONTENT)


class MyCommentRepliesView(_Throttled):
    feature = FEATURE
    permission_classes = STUDENT
    throttle_scope = "recorded_comment"

    def post(self, request, pk):
        body = _valid(s.BodyInput, request)["body"]
        try:
            c = services.reply_as_student(request.user, pk, body)
        except NotFoundError:
            raise Http404 from None
        return Response(s.comment_data(c, request.user), status=status.HTTP_201_CREATED)


class MyReviewView(_Throttled):
    feature = FEATURE
    permission_classes = STUDENT
    throttle_scope = "recorded_review"

    def get(self, request, pk):
        try:
            return Response(s.my_review_data(services.my_review(request.user, pk)))
        except NotFoundError:
            raise Http404 from None

    def put(self, request, pk):
        v = _valid(s.ReviewInput, request)
        try:
            r = services.save_my_review(
                request.user, pk, rating=v["rating"], comment=v["comment"]
            )
        except NotFoundError:
            raise Http404 from None
        return Response(s.my_review_data(r))

    def delete(self, request, pk):
        try:
            services.delete_my_review(request.user, pk)
        except NotFoundError:
            raise Http404 from None
        return Response(status=status.HTTP_204_NO_CONTENT)
```

`ForbiddenError` and `ValidationError` from the services reach the platform's exception handler as 403 and 400. Only `NotFoundError` is turned into `Http404` here, as plan 49's views do.

`api/urls.py`. Add:

```python
from etqan.recorded.api import feedback_views as fv
    path("my/videos/<int:pk>/comments/", fv.MyVideoCommentsView.as_view()),
    path("my/comments/<int:pk>/", fv.MyCommentView.as_view()),
    path("my/comments/<int:pk>/replies/", fv.MyCommentRepliesView.as_view()),
    path("my/<int:pk>/review/", fv.MyReviewView.as_view()),
```

`access/tests/test_routes.py`, `SELF_SERVICE`, under a `# Phase B7, slice B7e` comment:

```python
    "etqan.recorded.api.feedback_views.MyVideoCommentsView": "an enrolled student's lesson discussion; scoped in the service",
    "etqan.recorded.api.feedback_views.MyCommentView": "a student's own comment; scoped in the service",
    "etqan.recorded.api.feedback_views.MyCommentRepliesView": "the thread author's reply; scoped in the service",
    "etqan.recorded.api.feedback_views.MyReviewView": "an enrolled student's own review; scoped in the service",
```

- [ ] **Step 5: Run them to see them pass**

Run: `B pytest etqan/recorded etqan/access -q && B ruff check etqan/recorded`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/recorded/api etqan/recorded/tests/test_api_feedback.py etqan/access/tests/test_routes.py
git -C backend commit -m "feat(recorded): B7e student discussion and review API" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The office API and access resources (E-3, E-4, E-6)

**Files:**
- Modify: `backend/etqan/recorded/api/feedback_views.py`, `backend/etqan/recorded/api/urls.py`, `backend/etqan/access/registry.py` (B7 marker), `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`)
- Create: `backend/etqan/recorded/tests/test_api_feedback_office.py`

**Interfaces:**
- Produces these routes, all `[HasCode, FeatureOn]`:

  | Route | Code | Answer |
  |---|---|---|
  | `GET videos/<id>/comments/` | `rc_comment.view_any` | `[ThreadJSON + author_full_name]` |
  | `POST comments/<id>/replies/` | `rc_comment.create` | `{body}` → 201 `CommentJSON` |
  | `PATCH comments/<id>/` | `rc_comment.update` | `{hidden}` → 200 `CommentJSON` |
  | `DELETE comments/<id>/` | `rc_comment.delete` | 204 |
  | `GET playlists/<id>/reviews/?status=` | `rc_review.view_any` | `[OfficeReviewJSON]` |
  | `PATCH reviews/<id>/` | `rc_review.update` | `{status, reason?}` → 200 `OfficeReviewJSON` |

- `OfficeReviewJSON = {id, student: {id, full_name}, rating, comment, status, reason, created_at, decided_at}`.
- Resources: `rc_comment` (`view_any`, `create`, `update`, `delete`) and `rc_review` (`view_any`, `update`).

- [ ] **Step 1: Write the failing tests** (`tests/test_api_feedback_office.py`)

```python
import pytest

from etqan.recorded import services

pytestmark = pytest.mark.django_db


@pytest.fixture
def thread(people, course, api_for):
    pl = course()
    video = pl.videos.filter(status="published").order_by("position").first()
    admin = api_for("admin")
    services.enrol_by_office(
        playlist=pl, student_user_id=people.student.pk, method="free", amount_minor=0,
        by=admin.user,
    )
    top = services.post_comment(people.student, video.pk, "Q?")
    return pl, video, top, admin


def test_comments_moderation(people, thread):
    pl, video, top, admin = thread
    rows = admin.get(f"/api/v1/recorded/videos/{video.pk}/comments/").json()
    assert rows[0]["author_full_name"] == people.student.full_name
    reply = admin.post(f"/api/v1/recorded/comments/{top.pk}/replies/", {"body": "A"}, format="json")
    assert (reply.status_code, reply.json()["by_office"]) == (201, True)
    hidden = admin.patch(f"/api/v1/recorded/comments/{top.pk}/", {"hidden": True}, format="json")
    assert hidden.json()["hidden"] is True
    assert admin.delete(f"/api/v1/recorded/comments/{top.pk}/").status_code == 204
    assert admin.get(f"/api/v1/recorded/videos/{video.pk}/comments/").json() == []
    assert admin.patch("/api/v1/recorded/comments/999999/", {"hidden": True}, format="json").status_code == 404


def test_reviews_moderation(people, thread):
    pl, _, _, admin = thread
    r = services.save_my_review(people.student, pl.pk, rating=4, comment="Good")
    listed = admin.get(f"/api/v1/recorded/playlists/{pl.pk}/reviews/", {"status": "pending"}).json()
    assert [x["id"] for x in listed] == [r.pk]
    assert listed[0]["student"] == {"id": people.student.pk, "full_name": people.student.full_name}
    resp = admin.patch(
        f"/api/v1/recorded/reviews/{r.pk}/", {"status": "rejected", "reason": "Spam"}, format="json"
    )
    assert (resp.json()["status"], resp.json()["reason"]) == ("rejected", "Spam")
    bad = admin.patch(f"/api/v1/recorded/reviews/{r.pk}/", {"status": "pending"}, format="json")
    assert (bad.status_code, list(bad.json())) == (400, ["status"])
    bad = admin.get(f"/api/v1/recorded/playlists/{pl.pk}/reviews/", {"status": "nope"})
    assert bad.status_code == 400


def test_codes(people, thread, staff_for, api_for):
    pl, video, top, _ = thread
    assert staff_for().get(f"/api/v1/recorded/videos/{video.pk}/comments/").status_code == 403
    assert staff_for("rc_comment.view_any").get(
        f"/api/v1/recorded/videos/{video.pk}/comments/"
    ).status_code == 200
    for role in ("student", "parent", "teacher"):
        assert api_for(role).get(f"/api/v1/recorded/playlists/{pl.pk}/reviews/").status_code == 403
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_api_feedback_office.py -q`
Expected: FAIL (404: the routes are missing).

- [ ] **Step 3: Implement**

Append to `api/feedback_views.py`:

```python
from etqan.platform.permissions import HasCode

OFFICE = [HasCode, FeatureOn]


def _comment(pk):
    try:
        return services.get_comment(pk)
    except NotFoundError:
        raise Http404 from None


class VideoCommentsView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": "rc_comment.view_any"}

    def get(self, request, pk):
        try:
            threads = services.office_threads(pk)
        except NotFoundError:
            raise Http404 from None
        return Response([s.thread_data(t, request.user, office=True) for t in threads])


class CommentRepliesView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"POST": "rc_comment.create"}

    def post(self, request, pk):
        body = _valid(s.BodyInput, request)["body"]
        c = services.reply_as_office(request.user, _comment(pk).pk, body)
        return Response(
            s.comment_data(c, request.user, office=True), status=status.HTTP_201_CREATED
        )


class CommentDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"PATCH": "rc_comment.update", "DELETE": "rc_comment.delete"}

    def patch(self, request, pk):
        hidden = _valid(s.HiddenInput, request)["hidden"]
        c = services.set_comment_hidden(_comment(pk), hidden, by=request.user)
        return Response(s.comment_data(services.get_comment(c.pk), request.user, office=True))

    def delete(self, request, pk):
        services.delete_comment(_comment(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class PlaylistReviewsView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"GET": "rc_review.view_any"}

    def get(self, request, pk):
        try:
            services.get_playlist(pk)
        except NotFoundError:
            raise Http404 from None
        qs = services.playlist_reviews(pk, status=request.query_params.get("status", ""))
        return Response([s.office_review_data(r) for r in qs])


class ReviewDetailView(APIView):
    feature = FEATURE
    permission_classes = OFFICE
    permission_codes = {"PATCH": "rc_review.update"}

    def patch(self, request, pk):
        v = _valid(s.DecideInput, request)
        try:
            review = services.get_review(pk)
        except NotFoundError:
            raise Http404 from None
        done = services.decide_review(
            review, status=v["status"], reason=v["reason"], by=request.user
        )
        return Response(s.office_review_data(services.get_review(done.pk)))
```

`api/urls.py`. Add:

```python
    path("videos/<int:pk>/comments/", fv.VideoCommentsView.as_view()),
    path("comments/<int:pk>/replies/", fv.CommentRepliesView.as_view()),
    path("comments/<int:pk>/", fv.CommentDetailView.as_view()),
    path("playlists/<int:pk>/reviews/", fv.PlaylistReviewsView.as_view()),
    path("reviews/<int:pk>/", fv.ReviewDetailView.as_view()),
```

`access/registry.py`, under `# ── phase B7 ──` after B7a's three resources (E-6):

```python
    Resource(
        "rc_comment",
        "Recorded course comments",
        "تعليقات الدورات المسجلة",
        ("view_any", "create", "update", "delete"),
    ),
    Resource(
        "rc_review",
        "Recorded course reviews",
        "تقييمات الدورات المسجلة",
        ("view_any", "update"),
    ),
```

`access/tests/test_routes.py`. In `ROUTES`, append:

```python
    # Phase B7, slice B7e
    ("GET", f"/api/v1/recorded/videos/{N}/comments/", "rc_comment.view_any"),
    ("POST", f"/api/v1/recorded/comments/{N}/replies/", "rc_comment.create"),
    ("PATCH", f"/api/v1/recorded/comments/{N}/", "rc_comment.update"),
    ("DELETE", f"/api/v1/recorded/comments/{N}/", "rc_comment.delete"),
    ("GET", f"/api/v1/recorded/playlists/{N}/reviews/", "rc_review.view_any"),
    ("PATCH", f"/api/v1/recorded/reviews/{N}/", "rc_review.update"),
```

In `FEATURES`, append:

```python
    # Phase B7, slice B7e
    **dict.fromkeys(
        (
            ("GET", f"/api/v1/recorded/videos/{N}/comments/"),
            ("POST", f"/api/v1/recorded/comments/{N}/replies/"),
            ("PATCH", f"/api/v1/recorded/comments/{N}/"),
            ("DELETE", f"/api/v1/recorded/comments/{N}/"),
            ("GET", f"/api/v1/recorded/playlists/{N}/reviews/"),
            ("PATCH", f"/api/v1/recorded/reviews/{N}/"),
        ),
        "recorded_courses",
    ),
```

`FEATURE_WORDS` already maps `/recorded/` (B7a).

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded etqan/access -q && B lint-imports`
Expected: PASS. That includes `test_every_code_in_the_table_is_in_the_registry_and_in_use`, which checks that the six new codes equal the two resources' `in_use`.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/api etqan/recorded/tests/test_api_feedback_office.py etqan/access/registry.py etqan/access/tests/test_routes.py
git -C backend commit -m "feat(recorded): B7e office moderation API and access resources" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Dashboard data layer and strings

**Files:**
- Modify: `dashboard/src/features/recorded/schemas.ts`, `api.ts`, `api.test.ts`, `queries.ts`, `fixtures.ts`, `index.ts`
- Modify: `dashboard/src/locales/en/recorded.json`, `dashboard/src/locales/ar/recorded.json`

**Interfaces:**
- Produces:
  - types `RecordedComment`, `CommentThread`, `MyReview`, `OfficeReview`, `ReviewStatus`, `StoreReview`; `StoreItem` gains `rating_average: string | null` and `rating_count: number`; `StoreDetail` gains `reviews: StoreReview[]`;
  - `recordedApi.myComments(videoId)`, `postComment(videoId, body)`, `replyMine(commentId, body)`, `deleteMine(commentId)`, `myReview(playlistId)`, `saveMyReview(playlistId, body)`, `deleteMyReview(playlistId)`, `videoComments(videoId)`, `officeReply(commentId, body)`, `setHidden(commentId, hidden)`, `deleteComment(commentId)`, `playlistReviews(playlistId, status?)`, `decideReview(id, body)`;
  - hooks `useMyComments`, `usePostComment`, `useReplyMine`, `useDeleteMine`, `useMyReview`, `useSaveMyReview`, `useDeleteMyReview`, `useVideoComments`, `useOfficeReply`, `useSetHidden`, `useDeleteComment`, `usePlaylistReviews`, `useDecideReview`;
  - fixtures `thread`, `myReview`, `officeReview` (`storeItem`/`storeDetail` updated).

- [ ] **Step 1: Write the failing test** (append to `api.test.ts`)

```ts
describe("feedback calls", () => {
	beforeEach(() => vi.restoreAllMocks());

	it("addresses the discussion and the reviews", async () => {
		const get = vi.spyOn(api, "get").mockResolvedValue({ data: [] });
		const post = vi.spyOn(api, "post").mockResolvedValue({ data: {} });
		const put = vi.spyOn(api, "put").mockResolvedValue({ data: {} });
		const patch = vi.spyOn(api, "patch").mockResolvedValue({ data: {} });
		const del = vi.spyOn(api, "delete").mockResolvedValue({ data: {} });
		await recordedApi.myComments(10);
		expect(get).toHaveBeenCalledWith("recorded/my/videos/10/comments/");
		await recordedApi.postComment(10, "Q?");
		expect(post).toHaveBeenCalledWith("recorded/my/videos/10/comments/", { body: "Q?" });
		await recordedApi.replyMine(5, "Thanks");
		expect(post).toHaveBeenLastCalledWith("recorded/my/comments/5/replies/", { body: "Thanks" });
		await recordedApi.deleteMine(5);
		expect(del).toHaveBeenCalledWith("recorded/my/comments/5/");
		await recordedApi.saveMyReview(4, { rating: 5, comment: "" });
		expect(put).toHaveBeenCalledWith("recorded/my/4/review/", { rating: 5, comment: "" });
		await recordedApi.setHidden(5, true);
		expect(patch).toHaveBeenCalledWith("recorded/comments/5/", { hidden: true });
		await recordedApi.playlistReviews(4, "pending");
		expect(get).toHaveBeenLastCalledWith("recorded/playlists/4/reviews/", { params: { status: "pending" } });
		await recordedApi.playlistReviews(4);
		expect(get).toHaveBeenLastCalledWith("recorded/playlists/4/reviews/", { params: {} });
		await recordedApi.decideReview(9, { status: "approved", reason: "" });
		expect(patch).toHaveBeenLastCalledWith("recorded/reviews/9/", { status: "approved", reason: "" });
	});
});
```

- [ ] **Step 2: Run** `F pnpm vitest run src/features/recorded/api.test.ts`
Expected: FAIL with `recordedApi.myComments is not a function`.

- [ ] **Step 3: Implement**

`schemas.ts`. Append the new types, and add the rating fields to `StoreItem` and the reviews to `StoreDetail`:

```ts
export interface RecordedComment {
	id: number;
	parent: number | null;
	/** The first name; "" for the academy (show `recorded.discussion.academy`). */
	author_name: string;
	by_office: boolean;
	mine: boolean;
	body: string;
	hidden: boolean;
	created_at: string;
	/** Office answers only. */
	author_full_name?: string;
}

export interface CommentThread extends RecordedComment {
	replies: RecordedComment[];
}

export type ReviewStatus = "pending" | "approved" | "rejected";

export interface MyReview {
	id: number;
	rating: number;
	comment: string;
	status: ReviewStatus;
	reason: string;
	updated_at: string;
}

export interface OfficeReview {
	id: number;
	student: { id: number; full_name: string };
	rating: number;
	comment: string;
	status: ReviewStatus;
	reason: string;
	created_at: string;
	decided_at: string | null;
}

export interface StoreReview {
	name: string;
	rating: number;
	comment: string;
	date: string;
}
```

In `interface StoreItem`, add:

```ts
	/** B7e E-5: approved reviews only; two decimals, null when none. */
	rating_average: string | null;
	rating_count: number;
```

In `interface StoreDetail`, add `reviews: StoreReview[];`.

`api.ts`. Import the new types, then add to `recordedApi`:

```ts
	myComments: async (videoId: number) =>
		(await api.get<CommentThread[]>(`${B}my/videos/${videoId}/comments/`)).data,
	postComment: async (videoId: number, body: string) =>
		(await api.post<CommentThread>(`${B}my/videos/${videoId}/comments/`, { body })).data,
	replyMine: async (commentId: number, body: string) =>
		(await api.post<RecordedComment>(`${B}my/comments/${commentId}/replies/`, { body })).data,
	deleteMine: async (commentId: number) => {
		await api.delete(`${B}my/comments/${commentId}/`);
	},
	myReview: async (playlistId: number) =>
		(await api.get<MyReview | null>(`${B}my/${playlistId}/review/`)).data,
	saveMyReview: async (playlistId: number, body: { rating: number; comment: string }) =>
		(await api.put<MyReview>(`${B}my/${playlistId}/review/`, body)).data,
	deleteMyReview: async (playlistId: number) => {
		await api.delete(`${B}my/${playlistId}/review/`);
	},
	videoComments: async (videoId: number) =>
		(await api.get<CommentThread[]>(`${B}videos/${videoId}/comments/`)).data,
	officeReply: async (commentId: number, body: string) =>
		(await api.post<RecordedComment>(`${B}comments/${commentId}/replies/`, { body })).data,
	setHidden: async (commentId: number, hidden: boolean) =>
		(await api.patch<RecordedComment>(`${B}comments/${commentId}/`, { hidden })).data,
	deleteComment: async (commentId: number) => {
		await api.delete(`${B}comments/${commentId}/`);
	},
	playlistReviews: async (playlistId: number, status?: ReviewStatus) =>
		(
			await api.get<OfficeReview[]>(`${B}playlists/${playlistId}/reviews/`, {
				params: status ? { status } : {},
			})
		).data,
	decideReview: async (
		id: number,
		body: { status: "approved" | "rejected"; reason: string },
	) => (await api.patch<OfficeReview>(`${B}reviews/${id}/`, body)).data,
```

`queries.ts`. Add (beside the B7a hooks; `useInvalidating` and `recordedKey` are in this file):

```ts
export const useMyComments = (videoId: number) =>
	useQuery({
		queryKey: [...recordedKey, "comments", "my", videoId],
		queryFn: () => recordedApi.myComments(videoId),
	});
export const usePostComment = (videoId: number) =>
	useInvalidating((body: string) => recordedApi.postComment(videoId, body));
export const useReplyMine = () =>
	useInvalidating(({ id, body }: { id: number; body: string }) =>
		recordedApi.replyMine(id, body),
	);
export const useDeleteMine = () =>
	useInvalidating((id: number) => recordedApi.deleteMine(id));
export const useMyReview = (playlistId: number) =>
	useQuery({
		queryKey: [...recordedKey, "review", "my", playlistId],
		queryFn: () => recordedApi.myReview(playlistId),
	});
export const useSaveMyReview = (playlistId: number) =>
	useInvalidating((body: { rating: number; comment: string }) =>
		recordedApi.saveMyReview(playlistId, body),
	);
export const useDeleteMyReview = (playlistId: number) =>
	useInvalidating(() => recordedApi.deleteMyReview(playlistId));
export const useVideoComments = (videoId: number | undefined) =>
	useQuery({
		queryKey: [...recordedKey, "comments", "office", videoId],
		queryFn: () => recordedApi.videoComments(videoId as number),
		enabled: videoId !== undefined,
	});
export const useOfficeReply = () =>
	useInvalidating(({ id, body }: { id: number; body: string }) =>
		recordedApi.officeReply(id, body),
	);
export const useSetHidden = () =>
	useInvalidating(({ id, hidden }: { id: number; hidden: boolean }) =>
		recordedApi.setHidden(id, hidden),
	);
export const useDeleteComment = () =>
	useInvalidating((id: number) => recordedApi.deleteComment(id));
export const usePlaylistReviews = (
	playlistId: number,
	status?: ReviewStatus,
	enabled = true,
) =>
	useQuery({
		queryKey: [...recordedKey, "reviews", playlistId, status ?? "all"],
		queryFn: () => recordedApi.playlistReviews(playlistId, status),
		enabled,
	});
export const useDecideReview = () =>
	useInvalidating(
		({ id, status, reason }: { id: number; status: "approved" | "rejected"; reason: string }) =>
			recordedApi.decideReview(id, { status, reason }),
	);
```

`fixtures.ts`. Add `rating_average: "4.50", rating_count: 2` to `storeItem` and `reviews: [{ name: "Yusuf", rating: 5, comment: "Clear lessons.", date: "2026-10-08" }]` to `storeDetail`. Then append:

```ts
export const thread: CommentThread = {
	id: 30,
	parent: null,
	author_name: "Yusuf",
	by_office: false,
	mine: true,
	body: "What is idgham?",
	hidden: false,
	created_at: "2026-10-08T09:00:00+00:00",
	replies: [
		{
			id: 31,
			parent: 30,
			author_name: "",
			by_office: true,
			mine: false,
			body: "Merging one letter into the next.",
			hidden: false,
			created_at: "2026-10-08T10:00:00+00:00",
		},
	],
};

export const myReview: MyReview = {
	id: 40,
	rating: 4,
	comment: "Clear lessons.",
	status: "rejected",
	reason: "Please add detail.",
	updated_at: "2026-10-08T09:00:00+00:00",
};

export const officeReview: OfficeReview = {
	id: 40,
	student: { id: 21, full_name: "Yusuf Omar" },
	rating: 4,
	comment: "Clear lessons.",
	status: "pending",
	reason: "",
	created_at: "2026-10-08T09:00:00+00:00",
	decided_at: null,
};
```

`index.ts`. Export the new types and hooks, plus (from later tasks) `Discussion`, `ReviewDialog`, `CommentsTab`, `ReviewsTab` and `RatingSummary`.

`locales/en/recorded.json`. Add `"comments": "Comments", "reviews": "Reviews"` to the existing `tabs` object, `"reviews": "Reviews"` to the existing `store` object, and these top-level keys:

```json
"discussion": {
	"title": "Discussion",
	"add": "Add a comment",
	"post": "Post",
	"reply": "Reply",
	"replyLabel": "Your reply",
	"send": "Send reply",
	"delete": "Delete",
	"academy": "Academy",
	"hiddenNote": "Hidden by the academy",
	"empty": "No comments yet. Start the discussion."
},
"review": {
	"open": "Rate this course",
	"title": "Your review",
	"rating": "Rating",
	"stars_one": "{{count}} star",
	"stars_other": "{{count}} stars",
	"comment": "Comment (optional)",
	"save": "Save review",
	"delete": "Delete review",
	"status": {
		"pending": "Waiting for approval",
		"approved": "Approved",
		"rejected": "Rejected"
	},
	"reason": "Reason: {{reason}}",
	"saved": "Thank you. Your review was sent for approval.",
	"deleted": "Your review was deleted."
},
"comments": {
	"video": "Video",
	"empty": "No comments on this video.",
	"hide": "Hide",
	"unhide": "Unhide",
	"hidden": "Hidden",
	"reply": "Reply as the academy",
	"send": "Send reply",
	"delete": "Delete",
	"deleteConfirm": "Delete this comment and its replies?"
},
"reviews": {
	"filter": "Status",
	"all": "All",
	"empty": "No reviews yet.",
	"approve": "Approve",
	"reject": "Reject",
	"reason": "Reason (shown to the student)",
	"confirmReject": "Reject review"
},
"rating": {
	"none": "No ratings yet",
	"count_one": "{{count}} rating",
	"count_other": "{{count}} ratings",
	"label": "Rated {{average}} out of 5"
}
```

`locales/ar/recorded.json`. The same keys:

```json
"discussion": {
	"title": "النقاش",
	"add": "أضف تعليقًا",
	"post": "نشر",
	"reply": "رد",
	"replyLabel": "ردك",
	"send": "إرسال الرد",
	"delete": "حذف",
	"academy": "الأكاديمية",
	"hiddenNote": "أخفته الأكاديمية",
	"empty": "لا توجد تعليقات بعد. ابدأ النقاش."
},
"review": {
	"open": "قيّم هذه الدورة",
	"title": "تقييمك",
	"rating": "التقييم",
	"stars_one": "نجمة واحدة",
	"stars_other": "{{count}} نجوم",
	"comment": "تعليق (اختياري)",
	"save": "حفظ التقييم",
	"delete": "حذف التقييم",
	"status": {
		"pending": "بانتظار الموافقة",
		"approved": "مقبول",
		"rejected": "مرفوض"
	},
	"reason": "السبب: {{reason}}",
	"saved": "شكرًا لك. أُرسل تقييمك للموافقة.",
	"deleted": "حُذف تقييمك."
},
"comments": {
	"video": "الفيديو",
	"empty": "لا توجد تعليقات على هذا الفيديو.",
	"hide": "إخفاء",
	"unhide": "إظهار",
	"hidden": "مخفي",
	"reply": "الرد باسم الأكاديمية",
	"send": "إرسال الرد",
	"delete": "حذف",
	"deleteConfirm": "هل تحذف هذا التعليق وردوده؟"
},
"reviews": {
	"filter": "الحالة",
	"all": "الكل",
	"empty": "لا توجد تقييمات بعد.",
	"approve": "قبول",
	"reject": "رفض",
	"reason": "السبب (يظهر للطالب)",
	"confirmReject": "رفض التقييم"
},
"rating": {
	"none": "لا توجد تقييمات بعد",
	"count_one": "تقييم واحد",
	"count_other": "{{count}} تقييمات",
	"label": "التقييم {{average}} من 5"
}
```

Plus `"comments": "التعليقات", "reviews": "التقييمات"` in `tabs` and `"reviews": "التقييمات"` in `store`. If the ar/en equality test needs the extra Arabic plural forms (`_zero`, `_two`, `_few`, `_many`) to mirror en's `_one`/`_other` exactly, follow what the existing area files do. Check `locales/ar/curriculum.json` for a plural key and copy its pattern.

- [ ] **Step 4: Run** `F pnpm vitest run src/features/recorded src/locales && F pnpm tsc --noEmit`
Expected: PASS, including the ar/en key-equality test. Fix any plan 51 test that builds a `StoreItem` or `StoreDetail` literal by spreading the updated fixtures.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded src/locales/en/recorded.json src/locales/ar/recorded.json
git -C dashboard commit -m "feat(recorded): B7e dashboard data layer and strings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The discussion panel and the review dialog in the player

**Files:**
- Create: `dashboard/src/features/recorded/Discussion.tsx`, `Discussion.test.tsx`, `ReviewDialog.tsx`, `ReviewDialog.test.tsx`
- Modify: `dashboard/src/features/recorded/CoursePlayer.tsx`, `CoursePlayer.test.tsx`

**Interfaces:**
- Consumes: Task 7's hooks.
- Produces: `<Discussion videoId />` and `<ReviewDialog playlistId />`. `CoursePlayer` renders both for a student only: in a parent's read-only view (`student !== undefined`), neither is rendered.

- [ ] **Step 1: Write the failing tests**

`Discussion.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { Discussion } from "./Discussion";
import { thread } from "./fixtures";

vi.mock("./api", () => ({
	recordedApi: { myComments: vi.fn(), postComment: vi.fn(), replyMine: vi.fn(), deleteMine: vi.fn() },
}));

describe("Discussion", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.myComments).mockResolvedValue([thread]);
		vi.mocked(recordedApi.postComment).mockResolvedValue(thread);
		vi.mocked(recordedApi.replyMine).mockResolvedValue(thread.replies[0]);
	});

	it("shows threads with the academy's reply and posts a comment", async () => {
		const user = userEvent.setup();
		renderWithRouter(<Discussion videoId={10} />);
		const article = (await screen.findByText("What is idgham?")).closest("article") as HTMLElement;
		expect(within(article).getByText("Yusuf")).toBeInTheDocument();
		expect(within(article).getByText("Academy")).toBeInTheDocument();
		await user.type(screen.getByLabelText("Add a comment"), "  Another  ");
		await user.click(screen.getByRole("button", { name: "Post" }));
		expect(recordedApi.postComment).toHaveBeenCalledWith(10, "Another");
	});

	it("lets the author reply and delete; others cannot", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.myComments).mockResolvedValue([
			thread,
			{ ...thread, id: 32, mine: false, author_name: "Zaid", body: "Not mine", replies: [] },
		]);
		renderWithRouter(<Discussion videoId={10} />);
		const mine = (await screen.findByText("What is idgham?")).closest("article") as HTMLElement;
		const theirs = screen.getByText("Not mine").closest("article") as HTMLElement;
		expect(within(theirs).queryByRole("button", { name: "Reply" })).toBeNull();
		expect(within(theirs).queryByRole("button", { name: "Delete" })).toBeNull();
		await user.click(within(mine).getByRole("button", { name: "Reply" }));
		await user.type(within(mine).getByLabelText("Your reply"), "Thanks");
		await user.click(within(mine).getByRole("button", { name: "Send reply" }));
		expect(recordedApi.replyMine).toHaveBeenCalledWith(30, "Thanks");
	});

	it("marks the author's hidden comment", async () => {
		vi.mocked(recordedApi.myComments).mockResolvedValue([{ ...thread, hidden: true }]);
		renderWithRouter(<Discussion videoId={10} />);
		expect(await screen.findByText("Hidden by the academy")).toBeInTheDocument();
	});

	it("says when there is nothing yet", async () => {
		vi.mocked(recordedApi.myComments).mockResolvedValue([]);
		renderWithRouter(<Discussion videoId={10} />);
		expect(await screen.findByText("No comments yet. Start the discussion.")).toBeInTheDocument();
	});
});
```

`ReviewDialog.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { myReview } from "./fixtures";
import { ReviewDialog } from "./ReviewDialog";

vi.mock("./api", () => ({
	recordedApi: { myReview: vi.fn(), saveMyReview: vi.fn(), deleteMyReview: vi.fn() },
}));

describe("ReviewDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.saveMyReview).mockResolvedValue({ ...myReview, status: "pending" });
	});

	it("starts empty and sends a new review", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.myReview).mockResolvedValue(null);
		renderWithRouter(<ReviewDialog playlistId={4} />);
		await user.click(await screen.findByRole("button", { name: "Rate this course" }));
		await user.selectOptions(screen.getByLabelText("Rating"), "3");
		await user.type(screen.getByLabelText("Comment (optional)"), "Good");
		await user.click(screen.getByRole("button", { name: "Save review" }));
		expect(recordedApi.saveMyReview).toHaveBeenCalledWith(4, { rating: 3, comment: "Good" });
		expect(screen.queryByRole("button", { name: "Delete review" })).toBeNull();
	});

	it("shows an existing review's status and reason, and deletes it", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.myReview).mockResolvedValue(myReview);
		renderWithRouter(<ReviewDialog playlistId={4} />);
		await user.click(await screen.findByRole("button", { name: "Rate this course" }));
		expect(screen.getByText("Rejected")).toBeInTheDocument();
		expect(screen.getByText("Reason: Please add detail.")).toBeInTheDocument();
		expect(screen.getByLabelText("Rating")).toHaveValue("4");
		await user.click(screen.getByRole("button", { name: "Delete review" }));
		expect(recordedApi.deleteMyReview).toHaveBeenCalledWith(4);
	});
});
```

In `CoursePlayer.test.tsx`, add `myComments: vi.fn().mockResolvedValue([])` and `myReview: vi.fn().mockResolvedValue(null)` to the mocked `recordedApi`, then add:

```tsx
	it("shows the discussion and the review button to the student only", async () => {
		renderWithRouter(<CoursePlayer playlistId={4} />);
		expect(await screen.findByRole("heading", { name: "Discussion" })).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Rate this course" })).toBeInTheDocument();
	});

	it("a parent sees neither", async () => {
		renderWithRouter(<CoursePlayer playlistId={4} student={21} />);
		await screen.findByText("Lesson 1");
		expect(screen.queryByRole("heading", { name: "Discussion" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Rate this course" })).toBeNull();
	});
```

Match the existing `CoursePlayer.test.tsx` mock and render setup: if it mocks `./api` with a fixed object, add the two functions there.

- [ ] **Step 2: Run** `F pnpm vitest run src/features/recorded`
Expected: FAIL (the modules are missing).

- [ ] **Step 3: Implement**

`Discussion.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Button, Field, FormError, Spinner, Textarea, toast } from "@/ui";
import { recordedErrorText } from "./errors";
import { useDeleteMine, useMyComments, usePostComment, useReplyMine } from "./queries";
import type { CommentThread, RecordedComment } from "./schemas";

function Author({ c }: { c: RecordedComment }) {
	const { t, i18n } = useTranslation();
	return (
		<p className="flex flex-wrap items-baseline gap-2 text-xs text-muted-foreground">
			<span className="font-medium text-foreground">
				{c.by_office ? t("recorded.discussion.academy") : c.author_name}
			</span>
			<time dateTime={c.created_at}>
				{new Date(c.created_at).toLocaleString(i18n.language)}
			</time>
			{c.hidden ? <span>{t("recorded.discussion.hiddenNote")}</span> : null}
		</p>
	);
}

function ThreadView({ thread }: { thread: CommentThread }) {
	const { t } = useTranslation();
	const reply = useReplyMine();
	const remove = useDeleteMine();
	const [open, setOpen] = useState(false);
	const [body, setBody] = useState("");
	const fail = (error: unknown) =>
		toast({ description: recordedErrorText(error, t), variant: "destructive" });
	return (
		<article className="flex flex-col gap-2 rounded-lg border border-border p-3">
			<Author c={thread} />
			<p className="whitespace-pre-line text-sm">{thread.body}</p>
			{thread.replies.length > 0 ? (
				<ul className="flex flex-col gap-2 border-s-2 border-border ps-3">
					{thread.replies.map((r) => (
						<li key={r.id}>
							<Author c={r} />
							<p className="whitespace-pre-line text-sm">{r.body}</p>
						</li>
					))}
				</ul>
			) : null}
			{thread.mine ? (
				<div className="flex flex-wrap gap-2">
					<Button size="sm" variant="outline" onClick={() => setOpen((o) => !o)}>
						{t("recorded.discussion.reply")}
					</Button>
					<Button size="sm" variant="outline"
						onClick={() => remove.mutate(thread.id, { onError: fail })}>
						{t("recorded.discussion.delete")}
					</Button>
				</div>
			) : null}
			{open ? (
				<form className="flex flex-col gap-2"
					onSubmit={(e) => {
						e.preventDefault();
						reply.mutate(
							{ id: thread.id, body: body.trim() },
							{ onSuccess: () => { setBody(""); setOpen(false); }, onError: fail },
						);
					}}>
					<Field id={`rc-reply-${thread.id}`} label={t("recorded.discussion.replyLabel")}>
						<Textarea value={body} maxLength={2000} onChange={(e) => setBody(e.target.value)} />
					</Field>
					<Button type="submit" size="sm" className="self-start"
						disabled={!body.trim() || reply.isPending}>
						{t("recorded.discussion.send")}
					</Button>
				</form>
			) : null}
		</article>
	);
}

/** B7e E-1…E-3: a lesson's discussion, for its enrolled student. */
export function Discussion({ videoId }: { videoId: number }) {
	const { t } = useTranslation();
	const threads = useMyComments(videoId);
	const post = usePostComment(videoId);
	const [body, setBody] = useState("");
	return (
		<section className="flex flex-col gap-3" aria-labelledby="rc-discussion">
			<h2 id="rc-discussion" className="text-lg font-semibold">
				{t("recorded.discussion.title")}
			</h2>
			<form className="flex flex-col gap-2"
				onSubmit={(e) => {
					e.preventDefault();
					post.mutate(body.trim(), {
						onSuccess: () => setBody(""),
						onError: (error) =>
							toast({ description: recordedErrorText(error, t), variant: "destructive" }),
					});
				}}>
				<Field id={`rc-comment-${videoId}`} label={t("recorded.discussion.add")}>
					<Textarea value={body} maxLength={2000} onChange={(e) => setBody(e.target.value)} />
				</Field>
				<Button type="submit" size="sm" className="self-start" disabled={!body.trim() || post.isPending}>
					{t("recorded.discussion.post")}
				</Button>
			</form>
			{threads.isPending ? (
				<Spinner />
			) : threads.isError ? (
				<FormError>{recordedErrorText(threads.error, t)}</FormError>
			) : threads.data.length === 0 ? (
				<p className="text-sm text-muted-foreground">{t("recorded.discussion.empty")}</p>
			) : (
				threads.data.map((th) => <ThreadView key={th.id} thread={th} />)
			)}
		</section>
	);
}
```

`ReviewDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	Button,
	Dialog,
	DialogContent,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Select,
	Textarea,
	toast,
} from "@/ui";
import { recordedErrorText } from "./errors";
import { useDeleteMyReview, useMyReview, useSaveMyReview } from "./queries";

/** B7e E-4: the student's one review of a course, pending until approved. */
export function ReviewDialog({ playlistId }: { playlistId: number }) {
	const { t } = useTranslation();
	const review = useMyReview(playlistId);
	const save = useSaveMyReview(playlistId);
	const remove = useDeleteMyReview(playlistId);
	const [open, setOpen] = useState(false);
	const [rating, setRating] = useState(5);
	const [comment, setComment] = useState("");
	const fail = (error: unknown) =>
		toast({ description: recordedErrorText(error, t), variant: "destructive" });
	const current = review.data ?? null;

	return (
		<Dialog
			open={open}
			onOpenChange={(next) => {
				if (next) {
					setRating(current?.rating ?? 5);
					setComment(current?.comment ?? "");
				}
				setOpen(next);
			}}
		>
			<DialogTrigger asChild>
				<Button variant="outline" size="sm" disabled={review.isPending}>
					{t("recorded.review.open")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("recorded.review.title")}</DialogTitle>
				{current ? (
					<div className="text-sm">
						<p className="font-medium">{t(`recorded.review.status.${current.status}`)}</p>
						{current.reason ? <p>{t("recorded.review.reason", { reason: current.reason })}</p> : null}
					</div>
				) : null}
				<form
					id="rc-review"
					className="flex flex-col gap-3"
					onSubmit={(e) => {
						e.preventDefault();
						save.mutate(
							{ rating, comment: comment.trim() },
							{
								onSuccess: () => {
									toast({ description: t("recorded.review.saved"), variant: "success" });
									setOpen(false);
								},
								onError: fail,
							},
						);
					}}
				>
					<Field id="rc-review-rating" label={t("recorded.review.rating")}>
						<Select value={String(rating)} onChange={(e) => setRating(Number(e.target.value))}>
							{[5, 4, 3, 2, 1].map((n) => (
								<option key={n} value={n}>{t("recorded.review.stars", { count: n })}</option>
							))}
						</Select>
					</Field>
					<Field id="rc-review-comment" label={t("recorded.review.comment")}>
						<Textarea value={comment} maxLength={1000} onChange={(e) => setComment(e.target.value)} />
					</Field>
				</form>
				<DialogFooter>
					{current ? (
						<Button variant="outline"
							onClick={() =>
								remove.mutate(undefined, {
									onSuccess: () => {
										toast({ description: t("recorded.review.deleted"), variant: "success" });
										setOpen(false);
									},
									onError: fail,
								})
							}>
							{t("recorded.review.delete")}
						</Button>
					) : null}
					<Button type="submit" form="rc-review" disabled={save.isPending}>
						{t("recorded.review.save")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
```

`useDeleteMyReview` is built with `useInvalidating(() => …)`, so `mutate(undefined, …)` type-checks. If `useInvalidating` requires one argument, declare the function as `(_: void) => recordedApi.deleteMyReview(playlistId)`.

`CoursePlayer.tsx`:
- Import `Discussion` and `ReviewDialog`.
- Replace `<PageHeader title={playlist.title} />` with:

```tsx
			<div className="flex flex-wrap items-center justify-between gap-2">
				<PageHeader title={playlist.title} />
				{readOnly ? null : <ReviewDialog playlistId={playlist.id} />}
			</div>
```

- Inside the current-video `<section>`, after the mark-watched block, add `{readOnly ? null : <Discussion videoId={current.id} />}`.

- [ ] **Step 4: Run** `F pnpm vitest run src/features/recorded && F pnpm tsc --noEmit && F pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded
git -C dashboard commit -m "feat(recorded): B7e discussion panel and review dialog in the player" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The office's Comments and Reviews tabs

**Files:**
- Create: `dashboard/src/features/recorded/CommentsTab.tsx`, `CommentsTab.test.tsx`, `ReviewsTab.tsx`, `ReviewsTab.test.tsx`
- Modify: `dashboard/src/features/recorded/PlaylistPage.tsx`, `PlaylistPage.test.tsx`

**Interfaces:**
- Consumes: `useVideos(playlistId)` (B7a; all statuses), `useVideoComments`, `useOfficeReply`, `useSetHidden`, `useDeleteComment`, `usePlaylistReviews`, `useDecideReview`, `useCan`.
- Produces:
  - `<CommentsTab playlistId />`: a video picker, then the threads. Hide/unhide is shown with `rc_comment.update`, delete with `rc_comment.delete`, the reply box with `rc_comment.create`.
  - `<ReviewsTab playlistId />`: a status filter and the rows. Approve/reject is shown with `rc_review.update`; reject asks for an optional reason.
  - `PlaylistPage` gains the tabs `comments` (with `rc_comment.view_any`) and `reviews` (with `rc_review.view_any`). The reviews tab's label carries the pending count: `Reviews (2)`.

- [ ] **Step 1: Write the failing tests**

`CommentsTab.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { CommentsTab } from "./CommentsTab";
import { linkVideo, thread } from "./fixtures";

vi.mock("./api", () => ({
	recordedApi: {
		videos: vi.fn(), videoComments: vi.fn(), officeReply: vi.fn(),
		setHidden: vi.fn(), deleteComment: vi.fn(),
	},
}));

const office = { ...thread, mine: false, author_full_name: "Yusuf Omar" };

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<CommentsTab playlistId={4} />
		</CanProvider>,
	);
}

describe("CommentsTab", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.videos).mockResolvedValue([linkVideo]);
		vi.mocked(recordedApi.videoComments).mockResolvedValue([office]);
		vi.mocked(recordedApi.setHidden).mockResolvedValue({ ...office, hidden: true });
		vi.mocked(recordedApi.officeReply).mockResolvedValue(office.replies[0]);
	});

	it("lists a video's threads with full names and moderates them", async () => {
		const user = userEvent.setup();
		show("rc_comment.view_any", "rc_comment.update", "rc_comment.create", "rc_comment.delete");
		const article = (await screen.findByText("What is idgham?")).closest("article") as HTMLElement;
		expect(within(article).getByText("Yusuf Omar")).toBeInTheDocument();
		expect(recordedApi.videoComments).toHaveBeenCalledWith(10);
		// The top-level comment's own Hide comes first (the reply has its own).
		await user.click(within(article).getAllByRole("button", { name: "Hide" })[0]);
		expect(recordedApi.setHidden).toHaveBeenCalledWith(30, true);
		await user.type(within(article).getByLabelText("Reply as the academy"), "See lesson 2");
		await user.click(within(article).getByRole("button", { name: "Send reply" }));
		expect(recordedApi.officeReply).toHaveBeenCalledWith(30, "See lesson 2");
	});

	it("hides actions without their codes", async () => {
		show("rc_comment.view_any");
		const article = (await screen.findByText("What is idgham?")).closest("article") as HTMLElement;
		expect(within(article).queryByRole("button", { name: "Hide" })).toBeNull();
		expect(within(article).queryByRole("button", { name: "Delete" })).toBeNull();
		expect(within(article).queryByLabelText("Reply as the academy")).toBeNull();
	});
});
```

`ReviewsTab.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { officeReview } from "./fixtures";
import { ReviewsTab } from "./ReviewsTab";

vi.mock("./api", () => ({ recordedApi: { playlistReviews: vi.fn(), decideReview: vi.fn() } }));

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<ReviewsTab playlistId={4} />
		</CanProvider>,
	);
}

describe("ReviewsTab", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.playlistReviews).mockResolvedValue([officeReview]);
		vi.mocked(recordedApi.decideReview).mockResolvedValue({ ...officeReview, status: "approved" });
	});

	it("approves, and rejects with a reason", async () => {
		const user = userEvent.setup();
		show("rc_review.view_any", "rc_review.update");
		const row = (await screen.findByText("Yusuf Omar")).closest("li") as HTMLElement;
		await user.click(within(row).getByRole("button", { name: "Approve" }));
		expect(recordedApi.decideReview).toHaveBeenCalledWith(40, { status: "approved", reason: "" });
		await user.click(within(row).getByRole("button", { name: "Reject" }));
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText("Reason (shown to the student)"), "Spam");
		await user.click(within(dialog).getByRole("button", { name: "Reject review" }));
		expect(recordedApi.decideReview).toHaveBeenLastCalledWith(40, { status: "rejected", reason: "Spam" });
	});

	it("filters by status and hides actions without the code", async () => {
		const user = userEvent.setup();
		show("rc_review.view_any");
		await screen.findByText("Yusuf Omar");
		expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
		await user.selectOptions(screen.getByLabelText("Status"), "pending");
		expect(recordedApi.playlistReviews).toHaveBeenLastCalledWith(4, "pending");
	});
});
```

In `PlaylistPage.test.tsx`, add `playlistReviews: vi.fn()` and `videoComments: vi.fn()` to the mocked `recordedApi`, then add:

```tsx
	it("adds Comments and Reviews tabs by code, with the pending count", async () => {
		vi.mocked(recordedApi.playlistReviews).mockResolvedValue([officeReview, { ...officeReview, id: 41 }]);
		show("playlist.view", "rc_comment.view_any", "rc_review.view_any");
		expect(await screen.findByRole("tab", { name: "Comments" })).toBeInTheDocument();
		expect(await screen.findByRole("tab", { name: "Reviews (2)" })).toBeInTheDocument();
	});
```

Import `officeReview` from `./fixtures`.

- [ ] **Step 2: Run** `F pnpm vitest run src/features/recorded`
Expected: FAIL (the modules are missing).

- [ ] **Step 3: Implement**

`CommentsTab.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import {
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
	Field,
	FormError,
	Select,
	Spinner,
	StatusChip,
	Textarea,
	toast,
} from "@/ui";
import { recordedErrorText } from "./errors";
import {
	useDeleteComment,
	useOfficeReply,
	useSetHidden,
	useVideoComments,
	useVideos,
} from "./queries";
import type { CommentThread, RecordedComment } from "./schemas";

function Line({ c }: { c: RecordedComment }) {
	const { t, i18n } = useTranslation();
	return (
		<p className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
			<span className="font-medium text-foreground">
				{c.by_office ? t("recorded.discussion.academy") : c.author_full_name || c.author_name}
			</span>
			<time dateTime={c.created_at}>{new Date(c.created_at).toLocaleString(i18n.language)}</time>
			{c.hidden ? <StatusChip>{t("recorded.comments.hidden")}</StatusChip> : null}
		</p>
	);
}

function Moderation({ c }: { c: RecordedComment }) {
	const { t } = useTranslation();
	const can = useCan();
	const hide = useSetHidden();
	const remove = useDeleteComment();
	const fail = (error: unknown) =>
		toast({ description: recordedErrorText(error, t), variant: "destructive" });
	return (
		<div className="flex flex-wrap gap-2">
			{can("rc_comment.update") ? (
				<Button size="sm" variant="outline"
					onClick={() => hide.mutate({ id: c.id, hidden: !c.hidden }, { onError: fail })}>
					{t(c.hidden ? "recorded.comments.unhide" : "recorded.comments.hide")}
				</Button>
			) : null}
			{can("rc_comment.delete") ? (
				<AlertDialog>
					<AlertDialogTrigger asChild>
						<Button size="sm" variant="outline">{t("recorded.comments.delete")}</Button>
					</AlertDialogTrigger>
					<AlertDialogContent>
						<AlertDialogTitle>{t("recorded.comments.delete")}</AlertDialogTitle>
						<AlertDialogDescription>{t("recorded.comments.deleteConfirm")}</AlertDialogDescription>
						<AlertDialogFooter>
							<AlertDialogCancel>{t("recorded.cancel")}</AlertDialogCancel>
							<AlertDialogAction onClick={() => remove.mutate(c.id, { onError: fail })}>
								{t("recorded.comments.delete")}
							</AlertDialogAction>
						</AlertDialogFooter>
					</AlertDialogContent>
				</AlertDialog>
			) : null}
		</div>
	);
}

function OfficeThread({ thread }: { thread: CommentThread }) {
	const { t } = useTranslation();
	const can = useCan();
	const reply = useOfficeReply();
	const [body, setBody] = useState("");
	return (
		<article className="flex flex-col gap-2 rounded-lg border border-border p-3">
			<Line c={thread} />
			<p className="whitespace-pre-line text-sm">{thread.body}</p>
			<Moderation c={thread} />
			{thread.replies.length > 0 ? (
				<ul className="flex flex-col gap-2 border-s-2 border-border ps-3">
					{thread.replies.map((r) => (
						<li key={r.id} className="flex flex-col gap-1">
							<Line c={r} />
							<p className="whitespace-pre-line text-sm">{r.body}</p>
							<Moderation c={r} />
						</li>
					))}
				</ul>
			) : null}
			{can("rc_comment.create") ? (
				<form className="flex flex-col gap-2"
					onSubmit={(e) => {
						e.preventDefault();
						reply.mutate(
							{ id: thread.id, body: body.trim() },
							{
								onSuccess: () => setBody(""),
								onError: (error) =>
									toast({ description: recordedErrorText(error, t), variant: "destructive" }),
							},
						);
					}}>
					<Field id={`rc-office-reply-${thread.id}`} label={t("recorded.comments.reply")}>
						<Textarea value={body} maxLength={2000} onChange={(e) => setBody(e.target.value)} />
					</Field>
					<Button type="submit" size="sm" className="self-start" disabled={!body.trim() || reply.isPending}>
						{t("recorded.comments.send")}
					</Button>
				</form>
			) : null}
		</article>
	);
}

/** B7e E-3: the office reads and moderates a course's discussions by video. */
export function CommentsTab({ playlistId }: { playlistId: number }) {
	const { t } = useTranslation();
	const videos = useVideos(playlistId);
	const [picked, setPicked] = useState<number>();
	const videoId = picked ?? videos.data?.[0]?.id;
	const threads = useVideoComments(videoId);
	if (videos.isPending) return <Spinner />;
	if (videos.isError) return <FormError>{recordedErrorText(videos.error, t)}</FormError>;
	return (
		<div className="flex flex-col gap-3">
			<Field id="rc-comments-video" label={t("recorded.comments.video")}>
				<Select className="w-auto" value={videoId ?? ""} onChange={(e) => setPicked(Number(e.target.value))}>
					{videos.data.map((v) => <option key={v.id} value={v.id}>{v.title}</option>)}
				</Select>
			</Field>
			{videoId === undefined || threads.isPending ? (
				videoId === undefined ? null : <Spinner />
			) : threads.isError ? (
				<FormError>{recordedErrorText(threads.error, t)}</FormError>
			) : threads.data.length === 0 ? (
				<p className="text-sm text-muted-foreground">{t("recorded.comments.empty")}</p>
			) : (
				threads.data.map((th) => <OfficeThread key={th.id} thread={th} />)
			)}
		</div>
	);
}
```

`ReviewsTab.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import {
	Button,
	Dialog,
	DialogContent,
	DialogFooter,
	DialogTitle,
	Field,
	FormError,
	Select,
	Spinner,
	StatusChip,
	Textarea,
	toast,
} from "@/ui";
import { recordedErrorText } from "./errors";
import { useDecideReview, usePlaylistReviews } from "./queries";
import type { OfficeReview, ReviewStatus } from "./schemas";

/** B7e E-4: pending first; approve, or reject with a reason the student sees. */
export function ReviewsTab({ playlistId }: { playlistId: number }) {
	const { t } = useTranslation();
	const can = useCan();
	const [status, setStatus] = useState<ReviewStatus | "">("");
	const reviews = usePlaylistReviews(playlistId, status || undefined);
	const decide = useDecideReview();
	const [rejecting, setRejecting] = useState<OfficeReview>();
	const [reason, setReason] = useState("");
	const fail = (error: unknown) =>
		toast({ description: recordedErrorText(error, t), variant: "destructive" });

	return (
		<div className="flex flex-col gap-3">
			<Field id="rc-reviews-status" label={t("recorded.reviews.filter")}>
				<Select className="w-auto" value={status} onChange={(e) => setStatus(e.target.value as ReviewStatus | "")}>
					<option value="">{t("recorded.reviews.all")}</option>
					{(["pending", "approved", "rejected"] as const).map((s) => (
						<option key={s} value={s}>{t(`recorded.review.status.${s}`)}</option>
					))}
				</Select>
			</Field>
			{reviews.isPending ? (
				<Spinner />
			) : reviews.isError ? (
				<FormError>{recordedErrorText(reviews.error, t)}</FormError>
			) : reviews.data.length === 0 ? (
				<p className="text-sm text-muted-foreground">{t("recorded.reviews.empty")}</p>
			) : (
				<ul className="flex flex-col gap-2">
					{reviews.data.map((r) => (
						<li key={r.id} className="flex flex-col gap-2 rounded-lg border border-border p-3">
							<p className="flex flex-wrap items-center gap-2 text-sm">
								<span className="font-medium">{r.student.full_name}</span>
								<span aria-label={t("recorded.review.stars", { count: r.rating })}>
									{"★".repeat(r.rating)}{"☆".repeat(5 - r.rating)}
								</span>
								<StatusChip>{t(`recorded.review.status.${r.status}`)}</StatusChip>
							</p>
							{r.comment ? <p className="whitespace-pre-line text-sm">{r.comment}</p> : null}
							{r.reason ? <p className="text-xs text-muted-foreground">{t("recorded.review.reason", { reason: r.reason })}</p> : null}
							{can("rc_review.update") ? (
								<div className="flex flex-wrap gap-2">
									<Button size="sm" disabled={r.status === "approved"}
										onClick={() => decide.mutate({ id: r.id, status: "approved", reason: "" }, { onError: fail })}>
										{t("recorded.reviews.approve")}
									</Button>
									<Button size="sm" variant="outline" disabled={r.status === "rejected"}
										onClick={() => { setReason(""); setRejecting(r); }}>
										{t("recorded.reviews.reject")}
									</Button>
								</div>
							) : null}
						</li>
					))}
				</ul>
			)}
			<Dialog open={rejecting !== undefined} onOpenChange={(open) => { if (!open) setRejecting(undefined); }}>
				<DialogContent>
					<DialogTitle>{t("recorded.reviews.confirmReject")}</DialogTitle>
					<Field id="rc-reject-reason" label={t("recorded.reviews.reason")}>
						<Textarea value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} />
					</Field>
					<DialogFooter>
						<Button
							onClick={() => {
								if (!rejecting) return;
								decide.mutate(
									{ id: rejecting.id, status: "rejected", reason: reason.trim() },
									{ onSuccess: () => setRejecting(undefined), onError: fail },
								);
							}}
						>
							{t("recorded.reviews.confirmReject")}
						</Button>
					</DialogFooter>
				</DialogContent>
			</Dialog>
		</div>
	);
}
```

`PlaylistPage.tsx`:
- `type Tab = "details" | "videos" | "enrolments" | "comments" | "reviews";`
- After the enrolments push:

```tsx
	if (!isNew && can("rc_comment.view_any")) tabs.push("comments");
	if (!isNew && can("rc_review.view_any")) tabs.push("reviews");
	const pending = usePlaylistReviews(
		id ?? 0,
		"pending",
		!isNew && id !== undefined && can("rc_review.view_any"),
	);
	const label = (k: Tab) =>
		k === "reviews" && pending.data && pending.data.length > 0
			? `${t("recorded.tabs.reviews")} (${pending.data.length})`
			: t(`recorded.tabs.${k}`);
```

  The hook must run before the early returns. Move the `usePlaylistReviews` call (and `can`) above the `if (!isNew && query.isPending)` return. Keep the `tabs` computation where it is.
- Render the buttons with `{label(k)}` instead of `{t(`recorded.tabs.${k}`)}`.
- Extend the body chain before the enrolments branch:

```tsx
			) : tab === "comments" && id !== undefined ? (
				<CommentsTab playlistId={id} />
			) : tab === "reviews" && id !== undefined ? (
				<ReviewsTab playlistId={id} />
```

- Import `CommentsTab`, `ReviewsTab` and `usePlaylistReviews`.

- [ ] **Step 4: Run** `F pnpm vitest run src/features/recorded && F pnpm tsc --noEmit && F pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded
git -C dashboard commit -m "feat(recorded): B7e office comments and reviews tabs" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Ratings and reviews in the dashboard store

**Files:**
- Create: `dashboard/src/features/recorded/RatingSummary.tsx`, `RatingSummary.test.tsx`
- Modify: `dashboard/src/features/recorded/Store.tsx`, `Store.test.tsx`, `StoreDetail.tsx`, `StoreDetail.test.tsx`

**Interfaces:**
- Produces: `<RatingSummary average: string | null count: number />`. It renders "No ratings yet" when the count is 0, otherwise `★ 4.50 · 2 ratings`, with an `aria-label` of "Rated 4.50 out of 5".

- [ ] **Step 1: Write the failing tests**

`RatingSummary.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { RatingSummary } from "./RatingSummary";

describe("RatingSummary", () => {
	it("shows the average and the count", () => {
		render(<RatingSummary average="4.50" count={2} />);
		expect(screen.getByLabelText("Rated 4.50 out of 5")).toBeInTheDocument();
		expect(screen.getByText("2 ratings")).toBeInTheDocument();
	});
	it("says when there are none", () => {
		render(<RatingSummary average={null} count={0} />);
		expect(screen.getByText("No ratings yet")).toBeInTheDocument();
	});
});
```

Append to `StoreDetail.test.tsx` (it already mocks `recordedApi.storeDetail` with the `storeDetail` fixture):

```tsx
	it("shows the rating and the approved reviews with first names", async () => {
		renderDetail();
		expect(await screen.findByLabelText("Rated 4.50 out of 5")).toBeInTheDocument();
		const reviews = screen.getByRole("region", { name: "Reviews" });
		expect(within(reviews).getByText("Yusuf")).toBeInTheDocument();
		expect(within(reviews).getByText("Clear lessons.")).toBeInTheDocument();
	});
```

Use the file's existing render helper in place of `renderDetail()`, and import `within`. Append to `Store.test.tsx` an assertion in its list test: `expect(await screen.findByLabelText("Rated 4.50 out of 5")).toBeInTheDocument();`.

- [ ] **Step 2: Run** `F pnpm vitest run src/features/recorded`
Expected: FAIL.

- [ ] **Step 3: Implement**

`RatingSummary.tsx`:

```tsx
import { useTranslation } from "react-i18next";

/** B7e E-5: approved reviews' average and count. */
export function RatingSummary({ average, count }: { average: string | null; count: number }) {
	const { t } = useTranslation();
	if (count === 0 || average === null)
		return <span className="text-sm text-muted-foreground">{t("recorded.rating.none")}</span>;
	return (
		<span className="flex items-center gap-2 text-sm">
			<span aria-label={t("recorded.rating.label", { average })}>
				<span aria-hidden="true">★ {average}</span>
			</span>
			<span className="text-muted-foreground">{t("recorded.rating.count", { count })}</span>
		</span>
	);
}
```

`Store.tsx`. Under each card's lessons line, add `<RatingSummary average={item.rating_average} count={item.rating_count} />`.

`StoreDetail.tsx`:
- In the side card, after `<Price item={d} />`, add `<RatingSummary average={d.rating_average} count={d.rating_count} />`.
- In the main card, after the outline section, add:

```tsx
						{d.reviews.length > 0 ? (
							<section aria-labelledby="rc-store-reviews">
								<h2 id="rc-store-reviews" className="font-medium">{t("recorded.store.reviews")}</h2>
								<ul className="mt-2 flex flex-col gap-2 text-sm">
									{d.reviews.map((r, i) => (
										<li key={`${i}-${r.date}`} className="flex flex-col gap-1">
											<p className="flex items-center gap-2">
												<span className="font-medium">{r.name}</span>
												<span aria-label={t("recorded.review.stars", { count: r.rating })}>
													{"★".repeat(r.rating)}{"☆".repeat(5 - r.rating)}
												</span>
												<time dateTime={r.date} className="text-muted-foreground">{r.date}</time>
											</p>
											{r.comment ? <p className="whitespace-pre-line">{r.comment}</p> : null}
										</li>
									))}
								</ul>
							</section>
						) : null}
```

- Import `RatingSummary` in both files.

- [ ] **Step 4: Run** `F pnpm vitest run src/features/recorded && F pnpm tsc --noEmit && F pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded
git -C dashboard commit -m "feat(recorded): B7e ratings and reviews in the store" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Ratings and anonymous reviews on the marketing pages

**Files:**
- Modify: `marketing/src/lib/recorded.ts`, `marketing/src/pages/[lang]/recorded-courses/index.astro`, `marketing/src/pages/[lang]/recorded-courses/[slug].astro`, `marketing/test/recorded.test.ts`
- Modify (claim): `marketing/src/lib/i18n.ts`

**Interfaces:**
- Produces:
  - `PublicPlaylist` gains `rating_average: string | null`, `rating_count: number` and `reviews: { rating: number; comment: string; date: string }[]`, all checked by `isPublicPlaylist`;
  - `ratingText(average, count, lang) -> string` (`"★ 4.50 (2)"`, or `""` when the count is 0);
  - `ui(lang)` keys `courseReviews`, `anonymousStudent`.

- [ ] **Step 1: Write the failing tests**

In `marketing/test/recorded.test.ts`, extend the `playlist()` factory's defaults with `rating_average: "4.50", rating_count: 2, reviews: [{ rating: 5, comment: "Clear <i>lessons</i>", date: "2026-10-08" }]`, then append:

```ts
describe("ratings", () => {
	it("formats the rating, empty when none", () => {
		expect(recorded.ratingText("4.50", 2, "en")).toBe("★ 4.50 (2)");
		expect(recorded.ratingText(null, 0, "en")).toBe("");
	});

	it("rejects a payload without the rating fields", () => {
		const { rating_count: _, ...old } = playlist();
		expect(recorded.isPublicPlaylist(old)).toBe(false);
	});

	it("shows the rating on the list and anonymous reviews on the detail", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: [playlist()] });
		const list = await (await render(Index as never, { lang: "en" }, "/en/recorded-courses")).text();
		expect(list).toContain("★ 4.50 (2)");
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: playlist() });
		const html = await (await render(Detail as never, { lang: "en", slug: "tajweed" }, "/en/recorded-courses/tajweed")).text();
		expect(html).toContain("Reviews");
		expect(html).toContain("Student");
		expect(html).toContain("Clear &lt;i&gt;lessons&lt;/i&gt;");
	});
});
```

- [ ] **Step 2: Run** `M pnpm vitest run test/recorded.test.ts`
Expected: FAIL (`ratingText` missing).

- [ ] **Step 3: Claim, then add the strings**

```bash
python3 scripts/orchestration/ledger.py claim B7 marketing/src/lib/i18n.ts --reason "B7e E-5: recorded-course review strings"
```

In `src/lib/i18n.ts`, add `courseReviews: "التقييمات", anonymousStudent: "طالب",` to the `ar` table and `courseReviews: "Reviews", anonymousStudent: "Student",` to the `en` table.

```bash
git -C marketing add src/lib/i18n.ts
git -C marketing commit -m "feat(marketing): B7e review strings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 marketing/src/lib/i18n.ts
```

- [ ] **Step 4: Implement**

`src/lib/recorded.ts`. Add to the `PublicPlaylist` type:

```ts
	rating_average: string | null;
	rating_count: number;
	reviews: { rating: number; comment: string; date: string }[];
```

Add these clauses to `isPublicPlaylist`, before the final `outline` check:

```ts
	(v.rating_average === null || (typeof v.rating_average === "string" && /^\d\.\d{2}$/.test(v.rating_average))) &&
	Number.isInteger(v.rating_count) &&
	Array.isArray(v.reviews) &&
	v.reviews.every(
		(r) => isObj(r) && Number.isInteger(r.rating) && isStr(r.comment) && isStr(r.date) && !("name" in r),
	) &&
```

Append:

```ts
/** B7e E-5: "★ 4.50 (2)"; "" without approved reviews. */
export function ratingText(average: string | null, count: number, lang: string): string {
	if (!average || count === 0) return "";
	return `★ ${average} (${new Intl.NumberFormat(lang).format(count)})`;
}
```

The validator's `!("name" in r)` guard makes the page refuse a payload that would name a reviewer. That is defence in depth for E-5.

`index.astro`. Import `ratingText`, and after each card's lessons line add:

```astro
						{ratingText(p.rating_average, p.rating_count, lang) && (
							<p class="text-sm">{ratingText(p.rating_average, p.rating_count, lang)}</p>
						)}
```

`[slug].astro`. Import `ratingText`. In the aside, after the price, add the same rating line. After the outline `<ol>`, add:

```astro
				{p.reviews.length > 0 && (
					<section>
						<h2 class="font-medium">{ui(lang).courseReviews}</h2>
						<ul class="mt-2 flex flex-col gap-2 text-sm">
							{p.reviews.map((r) => (
								<li>
									<p><span class="font-medium">{ui(lang).anonymousStudent}</span> · {"★".repeat(r.rating)} · <time datetime={r.date}>{r.date}</time></p>
									{r.comment && <p class="whitespace-pre-line">{r.comment}</p>}
								</li>
							))}
						</ul>
					</section>
				)}
```

- [ ] **Step 5: Run** `M pnpm vitest run && M pnpm astro check`
Expected: PASS. That includes plan 51's tests, whose factory now carries the new fields.

- [ ] **Step 6: Commit**

```bash
git -C marketing add src/lib/recorded.ts "src/pages/[lang]/recorded-courses" test/recorded.test.ts
git -C marketing commit -m "feat(marketing): B7e ratings and anonymous reviews on recorded courses" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: e2e journey

**Files:**
- Create: `dashboard/e2e/b7-recorded-feedback.spec.ts`

**Interfaces:**
- Consumes:
  - `e2e/fixtures.ts`: `DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD`, `expectLoggedIn`, `acceptInvite`, `postAsAdmin`;
  - `e2e/manage.ts`;
  - the seeded `QURAN-INTRO` (plan 49 Task 10: free, published, three YouTube link videos).
- The test uses a fresh student enrolled in its own setup, as plans 49 and 51 do.

- [ ] **Step 1: Write the spec**

```ts
import { type Browser, expect, type Locator, type Page, test } from "@playwright/test";
import { acceptInvite, DEMO_ADMIN, DEMO_URL, DEV_PASSWORD, expectLoggedIn, postAsAdmin } from "./fixtures";
import { manage } from "./manage";

// Plan 52 (B7e): a student comments on a lesson and the office replies; the
// student rates the course, the office approves, and the store shows it.

const PASSWORD = "e2e-Student-B7e";

async function visit(page: Page, url: string, ready: Locator) {
	for (let attempt = 1; ; attempt++) {
		await page.goto(url);
		try {
			await expect(ready).toBeVisible({ timeout: 15_000 });
			return;
		} catch (error) {
			if (attempt === 2) throw error;
		}
	}
}

async function signInStudent(browser: Browser, email: string, name: string) {
	const context = await browser.newContext();
	const page = await context.newPage();
	await visit(page, `${DEMO_URL}/app/forgot-password`, page.getByRole("textbox", { name: "Email" }));
	await page.getByRole("textbox", { name: "Email" }).fill(email);
	const requested = Date.now();
	await page.getByRole("button", { name: "Send reset link" }).click();
	await expect(page.getByText("If that account exists, a reset link is on its way.")).toBeVisible();
	await context.close();
	return acceptInvite(browser, email, PASSWORD, name, { after: requested });
}

test("discussion and an approved review on a recorded course", async ({ page, browser }) => {
	test.setTimeout(240_000);
	manage("set_features", "demo", "--on", "recorded_courses");
	const stamp = Date.now();
	const student = `Rater${stamp} Student`;
	const email = `b7e-${stamp}@demo.test`;
	const question = `Question ${stamp}`;
	const answer = `Answer ${stamp}`;
	const opinion = `Opinion ${stamp}`;

	// Admin: a fresh student, enrolled free in the seeded course
	await visit(page, `${DEMO_URL}/app/login`, page.getByRole("textbox", { name: /email/i }));
	await page.getByRole("textbox", { name: /email/i }).fill(DEMO_ADMIN);
	await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	const made = await postAsAdmin(page, "people/students/", { user: { full_name: student, email }, profile: {} });
	expect(made.status(), await made.text()).toBe(201);
	const studentId = ((await made.json()) as { id: number }).id;
	const found = await page.request.get(`${DEMO_URL}/api/v1/recorded/playlists/?q=QURAN-INTRO`);
	const [course] = (await found.json()) as { id: number; title: string }[];
	const enrolled = await postAsAdmin(page, `recorded/playlists/${course.id}/enrolments/`, {
		student_id: studentId, method: "free", amount_minor: 0,
	});
	expect(enrolled.status(), await enrolled.text()).toBe(201);

	// Student: comment under the first lesson, and rate the course
	const learner = await signInStudent(browser, email, student);
	await learner.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await visit(learner, `${DEMO_URL}/app/learning/recorded/${course.id}`, learner.getByRole("heading", { name: "Discussion" }));
	await learner.getByLabel("Add a comment").fill(question);
	await learner.getByRole("button", { name: "Post" }).click();
	await expect(learner.getByText(question)).toBeVisible();
	await learner.getByRole("button", { name: "Rate this course" }).click();
	const dialog = learner.getByRole("dialog");
	await dialog.getByLabel("Rating").selectOption("5");
	await dialog.getByLabel("Comment (optional)").fill(opinion);
	await dialog.getByRole("button", { name: "Save review" }).click();
	await expect(dialog).toBeHidden();

	// Office: reply in the Comments tab, approve in the Reviews tab
	await visit(page, `${DEMO_URL}/app/catalogue/recorded/${course.id}`, page.getByRole("tab", { name: "Comments" }));
	await page.getByRole("tab", { name: "Comments" }).click();
	const thread = page.locator("article", { hasText: question });
	await thread.getByLabel("Reply as the academy").fill(answer);
	await thread.getByRole("button", { name: "Send reply" }).click();
	await expect(thread.getByText(answer)).toBeVisible();
	await page.getByRole("tab", { name: /^Reviews/ }).click();
	const row = page.locator("li", { hasText: student });
	await row.getByRole("button", { name: "Approve" }).click();
	await expect(row.getByText("Approved")).toBeVisible();

	// Student: sees the reply, and the review in the store
	await learner.reload();
	await expect(learner.getByText(answer)).toBeVisible();
	await visit(learner, `${DEMO_URL}/app/learning/recorded/store/${course.id}`, learner.getByRole("heading", { name: "Reviews" }));
	await expect(learner.getByText(opinion)).toBeVisible();
	await expect(learner.getByText(`Rater${stamp}`)).toBeVisible();
});
```

`postAsAdmin(page, path, body)` posts to `/api/v1/<path>`, as plan 51 Task 15 uses it. If the students endpoint answers the profile's id rather than the user id, read `user.id` from the answer instead. Check the shape the B7b spec's e2e relies on in `e2e/b3-*` or `e2e/b6-*`.

- [ ] **Step 2: Run** `just e2e e2e/b7-recorded-feedback.spec.ts` on the stream stack once it is up (`just dev-backend`, `just seed`).
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b7-recorded-feedback.spec.ts
git -C dashboard commit -m "test(recorded): B7e feedback e2e journey" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Gates, final review and queue

These run only once the phase holds a slot and B7a and B7b are merged. No step was run when this plan was written.

- [ ] **Step 1:** `just test` (backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70; marketing tests) and `just lint` (ruff, biome, `lint-imports`, gitleaks, `astro check`). Both must pass.
- [ ] **Step 2:** `just seed`, then `just e2e`: the whole suite, since `b7-recorded`, `b7-recorded-store` and this spec share the seeded courses. It must pass.
- [ ] **Step 3:** Dispatch a fresh whole-slice reviewer against the spec (E-1…E-8, §3–§6) and this plan's Review Focus. Fix every critical or important finding. Log minor ones in `../_ledger/orchestration/phases/B7.md`.
- [ ] **Step 4:** In the meta worktree, commit the submodule pointers on `feat/b7e-recorded-feedback` with `git add backend dashboard marketing`, never `-a`. Then run `python3 scripts/orchestration/ledger.py queue B7e` and follow the merge-queue steps:
  - rebase every touched repo onto its trunk;
  - regenerate `routeTree.gen.ts` if routes moved;
  - regenerate `0003_comments_reviews.py` if B7's migrations moved (§6.2: delete it and make it again, never `--merge`);
  - rerun the gates;
  - push, open the four PRs, and record them with `slice B7e --prs "<urls>"`.
