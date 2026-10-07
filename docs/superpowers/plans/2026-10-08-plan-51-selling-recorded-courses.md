# Plan 51 — B7b Selling Recorded Courses — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Students and parents can browse the academy's published recorded courses, enrol for free or pay online with Stripe or PayPal, and are enrolled once the provider confirms the payment. Every sale becomes a billing payment record (revenue). Visitors can browse the same catalogue on the public site.

**Architecture:** The B7a app `etqan.recorded` gains:
- a `Purchase` row, which is the checkout's `reference_id`;
- storefront and public-catalogue services;
- the gateways purpose `recorded_course`, whose `prepare` and `complete` are registered in `RecordedConfig.ready()`;
- the store, buy and public API routes.

Money reaches billing only through `billing.services.record_link_payment`, and reaches gateways only through `gateways.services`. The dashboard gains store pages under `/learning/recorded/store…`, a branch on the gateways return page, and two attention codes. The Astro marketing site gains `/{lang}/recorded-courses[/{slug}]`.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest + RTL; Astro + Vitest (AstroContainer); Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7b-selling-recorded-courses-design.md` (S-1…S-12, §3–§6). Phase decisions come from `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md`: B7-3, B7-4, B7-6, B7-7 and §4. Read both before any task.

**Requires:** B7a (plan 49, `docs/superpowers/plans/2026-10-08-plan-49-recorded-courses.md`), which must be merged first. From other phases this needs only merged work: B3b, B3c and B3g (`etqan.gateways`, `billing.services.record_link_payment`).

**Written in spec-only mode** (ledger D45, 2026-10-08). No stack existed when this plan was written, so no command below has been run. Build only after B7a has merged and the conductor has given B7 a slot.

## Global Constraints

- Branches. Create `feat/b7b-recorded-store` in the meta worktree, `backend/`, `dashboard/` and `marketing/`:
  - each submodule: `git fetch origin && git switch -c feat/b7b-recorded-store origin/main`;
  - meta: `origin/master`.
  - Never run `git submodule update` or any `git submodule` command that writes.
- Command prefixes, after `set -a; . ./.env.stream; set +a` in the meta worktree:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>`
  - `F <cmd>` = the same with the `dashboard` service
  - `M <cmd>` = the same with the `marketing` service
  - Whole suites: `just test`, `just lint`, `just e2e …`, `just migrate`.
- Reuse plan 49's names exactly:
  - `etqan/recorded/services/` (package; `services/__init__.py` re-exports and keeps `__all__`);
  - `enrol_from_sale`, `enrolment_for`, `get_playlist`, `playlists_queryset`, `student_profile`;
  - `api/serializers.py` `_url`, `api/my_views.py`, `api/urls.py`;
  - the `people` fixture and the `as_user`/`png` helpers in `tests/conftest.py`;
  - dashboard `src/features/recorded/` (`schemas.ts`, `api.ts`, `queries.ts`, `errors.ts`, `fixtures.ts`, `index.ts`) and `locales/{en,ar}/recorded.json`.
- `int_param`. `etqan.platform.params` has no `int_param` (it has `as_int`), so plan 49 Task 9 creates `etqan/recorded/api/params.py` with `int_param`. Import it from there.
- Imports. `etqan.recorded` imports only `etqan.platform`, `etqan.identity.services`, `etqan.academy.services`, `etqan.billing.services` and `etqan.gateways.services`. Plan 49's contract already lists the last one.
- Ids. People are addressed by **user id** in the API and the services. `record_link_payment(student_id=…)` takes the **StudentProfile pk**. `identity.services.is_parent_of(parent_user_id, student_user_id)` takes user ids.
- Money is integer minor units plus a 3-letter currency, never summed across currencies. Revenue is amount + fee (D16).
- Migrations only create tables or add nullable columns on B7's own tables (B7-14).
- Shared files outside the B7 markers each change in **one commit** under a ledger claim, released right after:
  - `python3 scripts/orchestration/ledger.py claim B7 <path> --reason "<why>"` … commit … `python3 scripts/orchestration/ledger.py release B7 <path>`
  - Run these from the meta worktree.
  - Files: `backend/config/settings/base.py` (`DEFAULT_THROTTLE_RATES`), `backend/pyproject.toml` (the "gateways imports no business app" contract), `dashboard/src/features/gateways/ReturnPage.tsx`, `dashboard/src/features/gateways/schemas.ts` + `dashboard/src/locales/{en,ar}/gateways.json`, `marketing/src/components/Header.astro`, `marketing/src/lib/i18n.ts`, `marketing/src/pages/sitemap.xml.ts`.
- Plain text only (D2). The marketing pages render escaped text. Thumbnail and intro URLs pass `isUpload` (https or `/media/`).
- Strings: en and ar only in `recorded.json`, key-equal (D22). The gateways strings stay key-equal too.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Stage explicit paths only; never `git commit -a`.

## Review Focus

1. **The provider event arriving twice, or two checkouts of one purchase both paid.** Expected: one enrolment, one billing record; the second answers `already_recorded` or `purchase_paid`, never a 500. Pinned in Task 5: `test_second_delivery_records_nothing` and `test_second_checkout_is_purchase_paid`.
2. **An office or free enrolment winning the race against the payment.** Expected: `already_enrolled` and **no** billing row. The inner block must roll back. Pinned in Task 5: `test_enrolment_race_rolls_back_the_payment`.
3. **A price change between "Buy" and payment.** Expected:
   - PayPal's capture re-check refuses: `still_payable` is False.
   - Stripe still completes at the old price.
   - The next "Buy" makes a new purchase.
   
   Pinned in Task 4, `test_price_change_refuses_recheck`, and Task 5, `test_cancelled_purchase_still_taken`.
4. **A parent buying for someone else's child, or a staff member using the store.** Expected: 404 for the stranger's child and 403 for staff. A quick-login session gets 403 too. Pinned in Task 7, `test_store_access`.
5. **The public catalogue leaking student data or draft content.** Expected:
   - only published, non-app-only playlists;
   - no enrolment counts;
   - no video URLs or file names in the outline.
   
   Pinned in Task 3, `test_outline_has_no_urls`, and Task 8, `test_public_payload_has_no_student_data`.

---

## File Structure

```text
backend/etqan/recorded/
  models.py                      + Purchase; Enrolment.accepted_terms_at
  migrations/0002_purchase.py    (generated)
  apps.py                        ready() also calls services.purpose.register()
  services/
    store.py                     net_price, buyer_student_id, storefront, store_detail, outline,
                                 public_playlists, public_playlist
    purchases.py                 enrol_free, start_purchase, purchase_for
    purpose.py                   NAME, prepare, complete, register
    enrolments.py                enrol_from_sale gains "free" and accepted_terms_at
    __init__.py                  re-exports
  api/
    store_views.py               store/, store/<id>/, enrol/, buy/, providers/
    public_views.py              public/playlists/, public/playlists/<slug>/
    serializers.py               store_item, store_detail_data, public_playlist_data, StoreBuyInput
    urls.py                      + routes (buy/ wrapped in transaction.non_atomic_requests)
  tests/
    conftest.py                  + online_on, stripe_on, paypal_on, course fixtures
    test_store.py test_purchases.py test_purpose.py test_purpose_e2e.py
    test_api_store.py test_api_public.py
Modified (claims): backend/config/settings/base.py, backend/pyproject.toml
Modified: backend/etqan/access/tests/test_routes.py (SELF_SERVICE)

dashboard/src/features/recorded/
  schemas.ts api.ts queries.ts fixtures.ts index.ts   (+ store types, calls, hooks)
  Store.tsx Store.test.tsx StoreDetail.tsx StoreDetail.test.tsx BuyPanel.tsx BuyPanel.test.tsx
  EnrolmentDialog.tsx (S-12 line)  EnrolmentDialog.test.tsx
dashboard/src/routes/_authed/learning.recorded.store.index.tsx
dashboard/src/routes/_authed/learning.recorded.store.$playlistId.tsx
dashboard/src/features/shell/nav.ts (B7 marker)
dashboard/src/locales/{en,ar}/recorded.json
Modified (claims): dashboard/src/features/gateways/ReturnPage.tsx (+ test),
  dashboard/src/features/gateways/schemas.ts, dashboard/src/locales/{en,ar}/gateways.json
dashboard/e2e/b7-recorded-store.spec.ts

marketing/src/lib/recorded.ts                         fetchers, flag cache, price text
marketing/src/pages/[lang]/recorded-courses/index.astro
marketing/src/pages/[lang]/recorded-courses/[slug].astro
marketing/test/recorded.test.ts
Modified (claims): marketing/src/components/Header.astro, marketing/src/lib/i18n.ts,
  marketing/src/pages/sitemap.xml.ts
```

---

### Task 1: The purchase row, terms timestamps and free sales

**Files:**
- Modify: `backend/etqan/recorded/models.py`, `backend/etqan/recorded/services/enrolments.py`
- Generate: `backend/etqan/recorded/migrations/0002_purchase.py`
- Test: `backend/etqan/recorded/tests/test_purchases.py` (new; this task adds the model tests)

**Interfaces:**
- Produces:
  - `Purchase` (`Status.PENDING|PAID|CANCELLED`; fields per spec §3);
  - `Enrolment.accepted_terms_at`;
  - `enrol_from_sale(*, playlist, student_user_id, method, amount_minor, currency, transaction_number, payment_id, by=None, accepted_terms_at=None) -> Enrolment`, which now also accepts `method="free"` (forcing amount 0).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/recorded/tests/test_purchases.py`:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.recorded import services
from etqan.recorded.models import Purchase
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


@pytest.fixture
def pl():
    return services.create_playlist(
        title="Tajweed", slug="tajweed", description="d", code="TAJ",
        content_language="ar", terms="t", thumbnail=png(), currency="USD",
        price_minor=2000, discount_minor=500, is_published=True,
    )


def test_purchase_amount_must_be_positive(pl, people):
    with pytest.raises(IntegrityError), transaction.atomic():
        Purchase.objects.create(
            playlist=pl, student=people.profile, amount_minor=0, currency="USD",
            accepted_terms_at=timezone.now(),
        )


def test_purchase_defaults(pl, people):
    p = Purchase.objects.create(
        playlist=pl, student=people.profile, amount_minor=1500, currency="USD",
        accepted_terms_at=timezone.now(),
    )
    assert (p.status, p.enrolment, p.paid_at) == ("pending", None, None)


def test_free_sale_forces_zero_and_records_terms(pl, people):
    when = timezone.now()
    e = services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=999, currency="USD", transaction_number="",
        payment_id=None, by=people.student, accepted_terms_at=when,
    )
    assert (e.method, e.amount_minor, e.accepted_terms_at) == ("free", 0, when)
    assert e.enrolled_by == people.student
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_purchases.py -q`
Expected: FAIL with `ImportError: cannot import name 'Purchase'`.

- [ ] **Step 3: Implement**

`models.py`: add to `Enrolment` (after `revoked_at`):

```python
    # B7b S-2: when the buyer ticked "I accept the terms" (store sales only).
    accepted_terms_at = models.DateTimeField(null=True, blank=True)
```

and append:

```python
class Purchase(models.Model):
    """B7b S-4 (B7-3): a checkout's reference. It holds the price snapshot
    and who the sale is for, because a completed checkout carries neither a
    user nor params."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PAID = "paid", "Paid"
        CANCELLED = "cancelled", "Cancelled"

    playlist = models.ForeignKey(
        Playlist, on_delete=models.PROTECT, related_name="purchases"
    )
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    status = models.CharField(
        max_length=9, choices=Status.choices, default=Status.PENDING
    )
    enrolment = models.ForeignKey(
        Enrolment, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    accepted_terms_at = models.DateTimeField()

    class Meta:
        ordering = ("-created_at", "id")
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0),
                name="recorded_purchase_amount_positive",
            )
        ]
        indexes = [models.Index(fields=["playlist", "student", "status"])]

    def __str__(self):
        return f"Purchase<{self.playlist_id}, {self.student_id}, {self.status}>"
```

`services/enrolments.py`: change `SALE_METHODS` and `enrol_from_sale`:

```python
SALE_METHODS = (
    Enrolment.Method.STRIPE,
    Enrolment.Method.PAYPAL,
    Enrolment.Method.CODE,
    # B7b S-3: the store's free path (no checkout, no billing record).
    Enrolment.Method.FREE,
)


@transaction.atomic
def enrol_from_sale(  # noqa: PLR0913 -- keyword-only; one sale
    *,
    playlist,
    student_user_id,
    method,
    amount_minor,
    currency,
    transaction_number,
    payment_id,
    by=None,
    accepted_terms_at=None,
) -> Enrolment:
    if method not in SALE_METHODS:
        raise ValidationError("Not a sale method.", field="method")
    return _create(
        playlist=playlist,
        student=student_profile(student_user_id),
        amount_minor=0 if method == Enrolment.Method.FREE else int(amount_minor),
        currency=currency,
        method=method,
        transaction_number=_transaction(transaction_number),
        payment_id=payment_id,
        enrolled_by=by,
        accepted_terms_at=accepted_terms_at,
    )
```

Plan 49's `test_from_sale_only_sale_methods` still passes: it refuses `manual`.

Generate the migration with `B python manage.py makemigrations recorded --name purchase`, then run `just migrate`. Check that the file only creates `Purchase` and adds the nullable `Enrolment.accepted_terms_at`.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/models.py etqan/recorded/migrations/0002_purchase.py etqan/recorded/services/enrolments.py etqan/recorded/tests/test_purchases.py
git -C backend commit -m "feat(recorded): B7b purchase row and free sales" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Test fixtures for selling

**Files:**
- Modify: `backend/etqan/recorded/tests/conftest.py`

**Interfaces:**
- Produces these fixtures, for Tasks 3–8:
  - `online_on`: `recorded_courses`, `invoices` and `online_payments` on;
  - `stripe_on` and `paypal_on`: enabled test-mode accounts, with `GATEWAYS_SIMULATE` on in tests;
  - `course(**overrides)`: a published USD playlist priced 2000 with discount 500, holding two published videos (one link, one file) and a draft video.
- Consumes: `etqan.gateways.tests.conftest.TEST_KEYS` and `PAYPAL_KEYS`. Tests may import anything (contract `ignore_imports`).

- [ ] **Step 1: Add the fixtures** (append to `tests/conftest.py`)

```python
from etqan.gateways import services as gateways_services
from etqan.gateways.tests.conftest import PAYPAL_KEYS
from etqan.gateways.tests.conftest import TEST_KEYS


@pytest.fixture
def online_on(set_features):
    """B7b: buying needs recorded_courses and online_payments (which itself
    requires invoices, B3b)."""
    return set_features(recorded_courses=True, invoices=True, online_payments=True)


@pytest.fixture
def stripe_on():
    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    return gateways_services.stripe_account()


@pytest.fixture
def paypal_on():
    gateways_services.update_settings(paypal=PAYPAL_KEYS, by=None)
    return gateways_services.paypal_account()


@pytest.fixture
def course():
    """`course(**overrides)`: a published USD course, net 1500, with two
    published videos (link, file) and one draft."""
    from etqan.recorded import services  # noqa: PLC0415

    def make(**overrides):
        fields = {
            "title": "Tajweed", "slug": "tajweed", "description": "Rules.",
            "code": "TAJ", "content_language": "ar", "terms": "Be kind.",
            "thumbnail": png(), "currency": "USD", "price_minor": 2000,
            "discount_minor": 500, "is_published": True, "content": "Body",
            **overrides,
        }
        pl = services.create_playlist(**fields)
        services.create_video(
            pl, code="L", title="Lesson one", slug="l", kind="link",
            url="https://youtu.be/dQw4w9WgXcQ", duration_seconds=60,
            status="published",
        )
        services.create_video(
            pl, code="F", title="Lesson two", slug="f", kind="file",
            file=mp4(), duration_seconds=120, status="published",
        )
        services.create_video(
            pl, code="D", title="Draft", slug="d", kind="link",
            url="https://x.test/d", duration_seconds=30, status="draft",
        )
        return services.get_playlist(pl.pk)

    return make
```

If plan 49's `create_video` names the upload argument differently than `file=`, use its name. Task 4 of plan 49 defines it.

- [ ] **Step 2: Run** `B pytest etqan/recorded -q`. Expected: PASS (no new tests yet; this checks the imports).
- [ ] **Step 3: Commit**

```bash
git -C backend add etqan/recorded/tests/conftest.py
git -C backend commit -m "test(recorded): B7b selling fixtures" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Storefront and public catalogue services (S-1, S-2, S-9)

**Files:**
- Create: `backend/etqan/recorded/services/store.py`, `backend/etqan/recorded/tests/test_store.py`
- Modify: `backend/etqan/recorded/services/__init__.py`

**Interfaces:**
- Consumes: `playlists_queryset()` (annotated `lessons`, `seconds`), `enrolment_for`, `identity.services.is_parent_of`.
- Produces:
  - `net_price(playlist) -> int`
  - `buyer_student_id(user, student_user_id: int | None) -> int`. A student gets themself. A parent gets their child (404 for anyone else's). Every other role, staff and admin included, gets `ForbiddenError`.
  - `for_sale() -> QuerySet[Playlist]` (published, not app-only, newest first)
  - `storefront(user, student_user_id=None) -> list[StoreItem]`
  - `store_detail(playlist_id, user, student_user_id=None) -> StoreDetail` (404 when not for sale)
  - `outline(playlist) -> list[OutlineItem]`
  - `public_playlists() -> list[StoreDetail]` (max 100)
  - `public_playlist(slug) -> StoreDetail` (404 when not for sale)
  - dataclasses `OutlineItem(title, duration_seconds)`, `StoreItem(playlist, net_minor, enrolled)` and `StoreDetail(playlist, net_minor, enrolled, outline)`.

- [ ] **Step 1: Write the failing tests** (`tests/test_store.py`)

```python
import pytest

from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.recorded import services

pytestmark = pytest.mark.django_db


def test_lists_published_not_app_only(people, course):
    shown = course()
    course(slug="draft", code="DR", is_published=False)
    course(slug="app", code="AP", app_only=True)
    items = services.storefront(people.student)
    assert [i.playlist.pk for i in items] == [shown.pk]
    assert (items[0].net_minor, items[0].enrolled) == (1500, False)
    assert (items[0].playlist.lessons, items[0].playlist.seconds) == (2, 180)


def test_enrolled_flag_for_the_student_and_a_parents_child(people, course):
    pl = course()
    services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, currency="USD", transaction_number="", payment_id=None,
    )
    assert services.storefront(people.student)[0].enrolled is True
    assert services.storefront(people.parent, people.student.pk)[0].enrolled is True
    assert services.storefront(people.other)[0].enrolled is False


def test_buyer(people, api_for):
    assert services.buyer_student_id(people.student, None) == people.student.pk
    assert services.buyer_student_id(people.student, 999) == people.student.pk
    assert services.buyer_student_id(people.parent, people.student.pk) == people.student.pk
    with pytest.raises(NotFoundError):
        services.buyer_student_id(people.parent, people.other.pk)
    with pytest.raises(NotFoundError):
        services.buyer_student_id(people.parent, None)
    for role in ("admin", "staff", "teacher"):
        with pytest.raises(ForbiddenError):
            services.buyer_student_id(api_for(role).user, None)


def test_outline_has_no_urls(people, course):
    pl = course()
    detail = services.store_detail(pl.pk, people.student)
    assert [(o.title, o.duration_seconds) for o in detail.outline] == [
        ("Lesson one", 60), ("Lesson two", 120),
    ]
    assert set(vars(detail.outline[0])) == {"title", "duration_seconds"}


def test_detail_404_when_not_for_sale(people, course):
    pl = course(is_published=False)
    with pytest.raises(NotFoundError):
        services.store_detail(pl.pk, people.student)
    with pytest.raises(NotFoundError):
        services.public_playlist(pl.slug)


def test_public(course):
    pl = course()
    course(slug="app", code="AP", app_only=True)
    assert [d.playlist.pk for d in services.public_playlists()] == [pl.pk]
    assert services.public_playlist("tajweed").net_minor == 1500
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_store.py -q`
Expected: FAIL with `AttributeError: module 'etqan.recorded.services' has no attribute 'storefront'`.

- [ ] **Step 3: Implement** `services/store.py`:

```python
"""B7b S-1, S-2, S-9: what is for sale, to whom, and what the public sees.
Prices are the playlist's own (B7-5); the net is price minus discount."""

from dataclasses import dataclass

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import role_of
from etqan.recorded.models import Enrolment
from etqan.recorded.models import PlaylistVideo
from etqan.recorded.services.playlists import playlists_queryset

PUBLIC_MAX = 100


@dataclass(frozen=True)
class OutlineItem:
    title: str
    duration_seconds: int


@dataclass(frozen=True)
class StoreItem:
    playlist: object
    net_minor: int
    enrolled: bool


@dataclass(frozen=True)
class StoreDetail:
    playlist: object
    net_minor: int
    enrolled: bool
    outline: list


def net_price(playlist) -> int:
    return playlist.price_minor - playlist.discount_minor


def buyer_student_id(user, student_user_id: int | None) -> int:
    """S-7: a student buys for themself, a parent for their child; staff and
    admins enrol from the office (403); someone else's child is a 404."""
    role = role_of(user)
    if role == "student":
        return user.pk
    if role == "parent":
        if student_user_id is not None and identity_services.is_parent_of(
            user.pk, student_user_id
        ):
            return student_user_id
        raise NotFoundError("Student", student_user_id)
    raise ForbiddenError("Recorded courses are bought by students and parents.")


def for_sale():
    return playlists_queryset().filter(is_published=True, app_only=False).order_by(
        "-created_at", "-id"
    )


def _enrolled_ids(student_user_id: int | None) -> set[int]:
    if student_user_id is None:
        return set()
    return set(
        Enrolment.objects.filter(
            student__user_id=student_user_id, status=Enrolment.Status.ACTIVE
        ).values_list("playlist_id", flat=True)
    )


def outline(playlist) -> list[OutlineItem]:
    return [
        OutlineItem(title=t, duration_seconds=d)
        for t, d in PlaylistVideo.objects.filter(
            playlist=playlist, status=PlaylistVideo.Status.PUBLISHED
        )
        .order_by("position", "id")
        .values_list("title", "duration_seconds")
    ]


def storefront(user, student_user_id=None) -> list[StoreItem]:
    sid = buyer_student_id(user, student_user_id)
    enrolled = _enrolled_ids(sid)
    return [StoreItem(p, net_price(p), p.pk in enrolled) for p in for_sale()]


def _detail(playlist, enrolled: bool) -> StoreDetail:
    return StoreDetail(playlist, net_price(playlist), enrolled, outline(playlist))


def store_detail(playlist_id, user, student_user_id=None) -> StoreDetail:
    sid = buyer_student_id(user, student_user_id)
    playlist = for_sale().filter(pk=playlist_id).first()
    if playlist is None:
        raise NotFoundError("Recorded course", playlist_id)
    return _detail(playlist, playlist.pk in _enrolled_ids(sid))


def public_playlists() -> list[StoreDetail]:
    return [_detail(p, False) for p in for_sale()[:PUBLIC_MAX]]


def public_playlist(slug: str) -> StoreDetail:
    playlist = for_sale().filter(slug=slug).first()
    if playlist is None:
        raise NotFoundError("Recorded course", slug)
    return _detail(playlist, False)
```

Re-export from `services/__init__.py` (and add the names to `__all__`): `net_price`, `buyer_student_id`, `for_sale`, `storefront`, `store_detail`, `outline`, `public_playlists`, `public_playlist`, `OutlineItem`, `StoreItem`, `StoreDetail`.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded/tests/test_store.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/services/store.py etqan/recorded/services/__init__.py etqan/recorded/tests/test_store.py
git -C backend commit -m "feat(recorded): B7b storefront and public catalogue services" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Free enrolment, starting a purchase, and `prepare` (S-3, S-4, S-5)

**Files:**
- Create: `backend/etqan/recorded/services/purchases.py`, `backend/etqan/recorded/services/purpose.py` (`prepare` only in this task)
- Modify: `services/__init__.py`, `tests/test_purchases.py`
- Create: `backend/etqan/recorded/tests/test_purpose.py`

**Interfaces:**
- Consumes: `gateways.services.start_checkout(purpose, reference_id, provider, *, user, params=None) -> StartedCheckout`, `gateways.services.Prepared`, `gateways.services.RECHECK`, `etqan.platform.features.enabled`.
- Produces:
  - `enrol_free(playlist, *, student_user_id, by, accept_terms: bool) -> Enrolment`. It raises 409 `recorded.not_free` when the net price is > 0, 400 `accept_terms` without acceptance, and the store's 404 / 409 otherwise.
  - `start_purchase(playlist, *, student_user_id, provider, by, accept_terms: bool) -> StartedCheckout`.
  - `purpose.NAME = "recorded_course"`.
  - `purpose.prepare(reference_id, user, params) -> Prepared`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_purchases.py`:

```python
import threading

from django.db import connection

from etqan.gateways.models import Checkout
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError


def test_free_enrolment(people, course):
    pl = course(price_minor=0, discount_minor=0)
    e = services.enrol_free(
        pl, student_user_id=people.student.pk, by=people.student, accept_terms=True
    )
    assert (e.method, e.amount_minor, e.payment_id) == ("free", 0, None)
    assert e.accepted_terms_at is not None
    from etqan.billing.models import Payment

    assert not Payment.objects.exists()


@pytest.mark.parametrize(
    ("extra", "accept", "error", "code"),
    [
        ({}, True, ConflictError, "recorded.not_free"),
        ({"price_minor": 0, "discount_minor": 0}, False, ValidationError, None),
        ({"price_minor": 0, "discount_minor": 0, "is_published": False}, True,
         NotFoundError, None),
    ],
)
def test_free_enrolment_refusals(people, course, extra, accept, error, code):
    pl = course(**extra)
    with pytest.raises(error) as caught:
        services.enrol_free(
            pl, student_user_id=people.student.pk, by=people.student,
            accept_terms=accept,
        )
    if code:
        assert caught.value.code == code


def test_start_purchase_creates_then_reuses(people, course, online_on, stripe_on):
    pl = course()
    first = services.start_purchase(
        pl, student_user_id=people.student.pk, provider="stripe",
        by=people.student, accept_terms=True,
    )
    again = services.start_purchase(
        pl, student_user_id=people.student.pk, provider="stripe",
        by=people.student, accept_terms=True,
    )
    assert Purchase.objects.count() == 1
    assert (first.amount_minor, first.currency) == (1500, "USD")
    assert again.id == first.id  # gateways' own reuse (same price, same starter)
    checkout = Checkout.objects.get(pk=first.id)
    assert (checkout.purpose, checkout.reference_id) == (
        "recorded_course", Purchase.objects.get().pk,
    )


def test_price_change_replaces_the_purchase(people, course, online_on, stripe_on):
    pl = course()
    services.start_purchase(
        pl, student_user_id=people.student.pk, provider="stripe",
        by=people.student, accept_terms=True,
    )
    services.update_playlist(pl, discount_minor=0)
    services.start_purchase(
        services.get_playlist(pl.pk), student_user_id=people.student.pk,
        provider="stripe", by=people.student, accept_terms=True,
    )
    assert sorted(Purchase.objects.values_list("status", "amount_minor")) == [
        ("cancelled", 1500), ("pending", 2000),
    ]


def test_start_purchase_refusals(people, course, online_on, stripe_on):
    pl = course(price_minor=0, discount_minor=0)
    with pytest.raises(ConflictError) as caught:
        services.start_purchase(
            pl, student_user_id=people.student.pk, provider="stripe",
            by=people.student, accept_terms=True,
        )
    assert caught.value.code == "recorded.free"
    pl = course(slug="p", code="P")
    with pytest.raises(ValidationError) as caught:
        services.start_purchase(
            pl, student_user_id=people.student.pk, provider="stripe",
            by=people.student, accept_terms=False,
        )
    assert caught.value.field == "accept_terms"


@pytest.mark.django_db(transaction=True)
def test_concurrent_buys_keep_one_pending(tenants, people, course, set_features):
    """S-4: under the playlist lock two starts share one pending purchase."""
    connection.set_tenant(tenants.main)
    set_features(recorded_courses=True, invoices=True, online_payments=True)
    from etqan.gateways import services as gateways_services
    from etqan.gateways.tests.conftest import TEST_KEYS

    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    pl = course()

    def go():
        connection.set_tenant(tenants.main)
        try:
            services.start_purchase(
                pl, student_user_id=people.student.pk, provider="stripe",
                by=people.student, accept_terms=True,
            )
        except ConflictError:
            pass  # gateways.checkout_starting: the other start is mid-call
        finally:
            connection.close()

    threads = [threading.Thread(target=go) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert Purchase.objects.filter(status="pending").count() == 1
```

Create `tests/test_purpose.py`:

```python
import pytest
from django.utils import timezone

from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.recorded import services
from etqan.recorded.models import Purchase
from etqan.recorded.services import purpose

pytestmark = pytest.mark.django_db


@pytest.fixture
def bought(people, course, online_on):
    pl = course()
    p = Purchase.objects.create(
        playlist=pl, student=people.profile, amount_minor=1500, currency="USD",
        created_by=people.parent, accepted_terms_at=timezone.now(),
    )
    return pl, p


def test_prepare_prices_from_the_snapshot(people, bought):
    pl, p = bought
    prepared = purpose.prepare(p.pk, people.student, None)
    assert prepared == gateways_services.Prepared(
        amount_minor=1500, currency="USD", description="Recorded course TAJ",
        add_fee=True, use_switch=True,
    )
    assert purpose.prepare(p.pk, people.parent, gateways_services.RECHECK).amount_minor == 1500


def _code(fn):
    with pytest.raises((ConflictError, NotFoundError)) as caught:
        fn()
    return caught.value.code


def test_prepare_refusals_in_order(people, bought, set_features, api_for):
    pl, p = bought
    call = lambda user=people.student: purpose.prepare(p.pk, user, None)  # noqa: E731
    # (3) not the student nor a parent of the student; no user at all
    assert _code(lambda: call(people.other)) == "not_found"
    assert _code(lambda: call(None)) == "not_found"
    assert _code(lambda: call(api_for("admin").user)) == "not_found"
    # (6) price changed
    services.update_playlist(pl, discount_minor=0)
    assert _code(call) == "recorded.price_changed"
    # (5) already enrolled
    services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, currency="USD", transaction_number="", payment_id=None,
    )
    assert _code(call) == "recorded.already_enrolled"
    # (4) no longer for sale
    services.update_playlist(pl, app_only=True)
    assert _code(call) == "recorded.not_for_sale"
    # (2) not pending
    Purchase.objects.filter(pk=p.pk).update(status="paid")
    assert _code(call) == "not_found"
    # (1) switch off
    set_features(recorded_courses=False)
    assert _code(call) == "not_found"


def test_price_change_refuses_recheck(people, bought, stripe_on):
    """Review Focus 3: gateways' capture-time re-check fails once the price moves."""
    from etqan.gateways.models import Checkout
    from etqan.gateways.services.captures import still_payable

    pl, p = bought
    started = gateways_services.start_checkout(
        "recorded_course", p.pk, "stripe", user=people.parent
    )
    checkout = Checkout.objects.get(pk=started.id)
    assert still_payable(checkout) is True
    services.update_playlist(pl, discount_minor=0)
    assert still_payable(checkout) is False
```

(`NotFoundError.code` is `"not_found"`; check `etqan/platform/exceptions.py`. If it differs, assert on `type(...)` instead.) `test_price_change_refuses_recheck` needs the purpose registered, which Task 5 does. Until then, mark it `@pytest.mark.xfail(strict=True, reason="registered in Task 5")` and remove the mark in Task 5.

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_purchases.py etqan/recorded/tests/test_purpose.py -q`
Expected: FAIL with missing `enrol_free` / `start_purchase` / `services.purpose`.

- [ ] **Step 3: Implement**

`services/purchases.py`:

```python
"""B7b S-3, S-4: the free path and starting a paid purchase. The purchase is
created or reused under a lock on the playlist row (lock order: playlist,
then purchase, as in `complete` and `enrol_from_sale`); the provider is
called only after that block commits, outside any transaction (the buy view
is non-atomic, as gateways' start route)."""

from django.db import transaction
from django.utils import timezone

from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.recorded.models import Enrolment
from etqan.recorded.models import Playlist
from etqan.recorded.models import Purchase
from etqan.recorded.services.enrolments import enrol_from_sale
from etqan.recorded.services.enrolments import student_profile
from etqan.recorded.services.store import net_price

NAME = "recorded_course"


def _terms(accept_terms: bool) -> None:
    if not accept_terms:
        raise ValidationError("Accept the terms and conditions.", field="accept_terms")


def _for_sale(playlist) -> None:
    if not playlist.is_published or playlist.app_only:
        raise NotFoundError("Recorded course", playlist.pk)


def _not_enrolled(playlist, student_user_id) -> None:
    if Enrolment.objects.filter(
        playlist=playlist,
        student__user_id=student_user_id,
        status=Enrolment.Status.ACTIVE,
    ).exists():
        raise ConflictError(
            "This student is already enrolled in this course.",
            code="recorded.already_enrolled",
        )


def enrol_free(playlist, *, student_user_id, by, accept_terms: bool) -> Enrolment:
    _for_sale(playlist)
    if net_price(playlist) > 0:
        raise ConflictError("This course is not free.", code="recorded.not_free")
    _terms(accept_terms)
    return enrol_from_sale(
        playlist=playlist,
        student_user_id=student_user_id,
        method=Enrolment.Method.FREE,
        amount_minor=0,
        currency=playlist.currency,
        transaction_number="",
        payment_id=None,
        by=by,
        accepted_terms_at=timezone.now(),
    )


@transaction.atomic
def _pending_purchase(playlist, *, student_user_id, by) -> Purchase:
    Playlist.objects.select_for_update().filter(pk=playlist.pk).first()
    fresh = Playlist.objects.get(pk=playlist.pk)
    _for_sale(fresh)
    _not_enrolled(fresh, student_user_id)
    amount = net_price(fresh)
    if amount <= 0:
        raise ConflictError("This course is free: enrol instead.", code="recorded.free")
    profile = student_profile(student_user_id)
    pending = Purchase.objects.select_for_update().filter(
        playlist=fresh, student=profile, status=Purchase.Status.PENDING
    )
    for old in pending:
        if (old.amount_minor, old.currency) == (amount, fresh.currency):
            return old
        old.status = Purchase.Status.CANCELLED
        old.save(update_fields=["status"])
    return Purchase.objects.create(
        playlist=fresh,
        student=profile,
        amount_minor=amount,
        currency=fresh.currency,
        created_by=by,
        accepted_terms_at=timezone.now(),
    )


def start_purchase(playlist, *, student_user_id, provider, by, accept_terms: bool):
    """S-4: returns gateways' StartedCheckout; gateways' refusals pass through."""
    _terms(accept_terms)
    purchase = _pending_purchase(playlist, student_user_id=student_user_id, by=by)
    return gateways_services.start_checkout(NAME, purchase.pk, provider, user=by)
```

`services/purpose.py` (`prepare` now; `complete` and `register` come in Task 5):

```python
"""B7b S-5, S-6 (B7-3, B7-4): the `recorded_course` purpose. Its reference is
a Purchase. `prepare` reads only that row and the playlist, never request
data (D28); `complete` records the money in billing and enrols, in one
inner atomic block, or records nothing and says why."""

import logging

from etqan.gateways import services as gateways_services
from etqan.identity import services as identity_services
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.recorded.models import Enrolment
from etqan.recorded.models import Purchase
from etqan.recorded.services.store import net_price

NAME = "recorded_course"
FEATURE = "recorded_courses"
logger = logging.getLogger(__name__)


def _may_pay(user, purchase) -> bool:
    if user is None or not getattr(user, "is_authenticated", False):
        return False
    student_user_id = purchase.student.user_id
    return user.pk == student_user_id or identity_services.is_parent_of(
        user.pk, student_user_id
    )


def prepare(reference_id: int, user, params) -> gateways_services.Prepared:
    if not features.enabled(FEATURE):
        raise NotFoundError("Purchase", reference_id)
    purchase = (
        Purchase.objects.select_related("playlist", "student")
        .filter(pk=reference_id, status=Purchase.Status.PENDING)
        .first()
    )
    if purchase is None or not _may_pay(user, purchase):
        raise NotFoundError("Purchase", reference_id)
    playlist = purchase.playlist
    if not playlist.is_published or playlist.app_only:
        raise ConflictError(
            "This course is not for sale.", code="recorded.not_for_sale"
        )
    if Enrolment.objects.filter(
        playlist=playlist,
        student=purchase.student,
        status=Enrolment.Status.ACTIVE,
    ).exists():
        raise ConflictError(
            "This student is already enrolled in this course.",
            code="recorded.already_enrolled",
        )
    if (purchase.amount_minor, purchase.currency) != (
        net_price(playlist),
        playlist.currency,
    ):
        raise ConflictError(
            "The price has changed. Buy again.", code="recorded.price_changed"
        )
    return gateways_services.Prepared(
        amount_minor=purchase.amount_minor,
        currency=purchase.currency,
        description=f"Recorded course {playlist.code}",
        add_fee=True,
        use_switch=True,
    )
```

Re-export `enrol_free` and `start_purchase` from `services/__init__.py`. Do **not** re-export `purpose`'s functions: tests import the module `etqan.recorded.services.purpose`.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded/tests/test_purchases.py etqan/recorded/tests/test_purpose.py -q`
Expected: PASS, with `test_price_change_refuses_recheck` showing as xfail. `start_checkout` raises `Unknown purpose` until Task 5 registers the purpose, so the two `start_purchase` happy-path tests also need the same `xfail(strict=True)` mark until Task 5. Add it now.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded/services etqan/recorded/tests/test_purchases.py etqan/recorded/tests/test_purpose.py
git -C backend commit -m "feat(recorded): B7b free enrolment, purchase start and prepare" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `complete`, registration, and end-to-end through the simulator (S-6)

**Files:**
- Modify: `backend/etqan/recorded/services/purpose.py`, `backend/etqan/recorded/apps.py`, `tests/test_purpose.py`, `tests/test_purchases.py` (remove the xfail marks)
- Create: `backend/etqan/recorded/tests/test_purpose_e2e.py`

**Interfaces:**
- Consumes:
  - `billing.services.record_link_payment(*, student_id (profile pk), customer_name, customer_email, customer_phone, amount_minor, fee_minor, currency, method, transaction_number, notes) -> Payment`;
  - `gateways.services.CompletedCheckout`, `gateways.services.Applied`, `gateways.services.register_purpose`, `gateways.services.simulate(checkout_id, outcome, *, user)`;
  - `billing.services.revenue_between(first, following) -> list[dict]`.
- Produces: `purpose.complete(done) -> Applied`, `purpose.register()`. `RecordedConfig.ready()` calls `register()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_purpose.py`:

```python
import threading
import uuid
from datetime import date

from django.db import IntegrityError
from django.db import connection

from etqan.billing.models import Payment
from etqan.recorded.models import Enrolment


def done(p, **extra):
    fields = {
        "id": uuid.uuid4(), "purpose": "recorded_course", "reference_id": p.pk,
        "provider": "stripe", "amount_minor": 1500, "fee_minor": 75,
        "currency": "USD", "transaction_number": "pi_1",
        "completed_at": timezone.now(), **extra,
    }
    return gateways_services.CompletedCheckout(**fields)


def test_complete_records_the_money_and_enrols(people, bought):
    pl, p = bought
    assert purpose.complete(done(p)) == gateways_services.Applied(ok=True)
    pay = Payment.objects.get()
    assert (pay.amount_minor, pay.fee_minor, pay.currency, pay.method) == (
        1500, 75, "USD", "stripe",
    )
    assert (pay.student_id, pay.invoice_id, pay.notes) == (
        people.profile.pk, None, "Recorded course: Tajweed",
    )
    p.refresh_from_db()
    e = Enrolment.objects.get()
    assert (p.status, p.enrolment, p.paid_at is not None) == ("paid", e, True)
    assert (e.method, e.amount_minor, e.payment_id, e.transaction_number) == (
        "stripe", 1500, pay.pk, "pi_1",
    )
    assert e.accepted_terms_at == p.accepted_terms_at


def test_second_delivery_records_nothing(people, bought):
    pl, p = bought
    purpose.complete(done(p))
    again = purpose.complete(done(p))
    assert again == gateways_services.Applied(ok=False, reason="purchase_paid")
    assert Payment.objects.count() == 1


def test_second_checkout_is_purchase_paid(people, bought):
    pl, p = bought
    purpose.complete(done(p))
    assert purpose.complete(done(p, transaction_number="pi_2")).reason == "purchase_paid"
    assert Payment.objects.count() == 1


def test_already_enrolled_records_nothing(people, bought):
    pl, p = bought
    services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, currency="USD", transaction_number="", payment_id=None,
    )
    assert purpose.complete(done(p)).reason == "already_enrolled"
    assert not Payment.objects.exists()


def test_currency_mismatch_and_missing(people, bought):
    pl, p = bought
    assert purpose.complete(done(p, currency="EUR")).reason == "currency_mismatch"
    assert purpose.complete(done(p, reference_id=999999)).reason == "reference_missing"
    assert not Payment.objects.exists()


def test_cancelled_purchase_still_taken(people, bought):
    pl, p = bought
    Purchase.objects.filter(pk=p.pk).update(status="cancelled")
    services.update_playlist(pl, is_published=False)  # not re-checked at completion
    assert purpose.complete(done(p)).ok is True
    assert Enrolment.objects.get().amount_minor == 1500


def test_transaction_clash_is_already_recorded(people, bought):
    pl, p = bought
    Payment.objects.create(
        customer_type="unregistered", customer_name="X", amount_minor=1,
        currency="USD", method="stripe", transaction_number="pi_1",
        paid_on=date(2026, 10, 1),
    )
    assert purpose.complete(done(p)).reason == "already_recorded"
    assert not Enrolment.objects.exists()


def test_integrity_race_is_already_recorded(people, bought, monkeypatch):
    pl, p = bought
    from etqan.billing import services as billing_services

    class Diag:
        constraint_name = "billing_payment_transaction_unique"

    def boom(**kw):
        cause = Exception()
        cause.diag = Diag()
        err = IntegrityError("dup")
        err.__cause__ = cause
        raise err

    monkeypatch.setattr(billing_services, "record_link_payment", boom)
    assert purpose.complete(done(p)).reason == "already_recorded"


def test_enrolment_race_rolls_back_the_payment(people, bought, monkeypatch):
    """Review Focus 2: an office enrolment wins between the check and the
    enrol; the billing row goes with the inner block."""
    pl, p = bought
    from etqan.recorded.services import enrolments

    real = enrolments.enrol_from_sale

    def racing(**kw):
        Enrolment.objects.create(
            playlist=pl, student=people.profile, amount_minor=0, currency="USD",
            method="free",
        )
        return real(**kw)

    monkeypatch.setattr(purpose, "enrol_from_sale", racing)
    assert purpose.complete(done(p)).reason == "already_enrolled"
    assert not Payment.objects.exists()


def test_other_billing_refusal_is_attention(people, bought, monkeypatch):
    pl, p = bought
    from etqan.billing import services as billing_services
    from etqan.platform.exceptions import ValidationError

    def refuse(**kw):
        raise ValidationError("bad", field="customer_email")

    monkeypatch.setattr(billing_services, "record_link_payment", refuse)
    assert purpose.complete(done(p)) == gateways_services.Applied(ok=False)
```

Create `tests/test_purpose_e2e.py`:

```python
"""B7b §6: a real checkout through the gateways simulator, Stripe and
PayPal, ends in an enrolment; the month's revenue includes amount + fee."""

import pytest

from etqan.billing import services as billing_services
from etqan.gateways import services as gateways_services
from etqan.gateways.models import Checkout
from etqan.recorded import services
from etqan.recorded.models import Enrolment

pytestmark = pytest.mark.django_db


@pytest.mark.parametrize("provider", ["stripe", "paypal"])
def test_simulated_payment_enrols(people, course, online_on, stripe_on, paypal_on, provider):
    pl = course()
    started = services.start_purchase(
        pl, student_user_id=people.student.pk, provider=provider,
        by=people.parent, accept_terms=True,
    )
    assert gateways_services.simulate(started.id, "pay", user=people.parent) == "completed"
    checkout = Checkout.objects.get(pk=started.id)
    assert checkout.applied is True
    e = Enrolment.objects.get()
    assert (e.method, e.amount_minor, e.payment_id is not None) == (provider, 1500, True)
    paid_on = e.enrolled_at.date()
    first = paid_on.replace(day=1)
    following = (first.replace(day=28) + __import__("datetime").timedelta(days=4)).replace(day=1)
    revenue = billing_services.revenue_between(first, following)
    usd = next(r for r in revenue if r["currency"] == "USD")
    assert usd["amount_minor"] == 1500 + checkout.fee_minor


def test_stripe_session_of_a_replaced_purchase_still_pays(people, course, online_on, stripe_on):
    """Spec §6: a cancelled purchase's Stripe session stays payable."""
    pl = course()
    old = services.start_purchase(
        pl, student_user_id=people.student.pk, provider="stripe",
        by=people.student, accept_terms=True,
    )
    services.update_playlist(pl, discount_minor=0)
    services.start_purchase(
        services.get_playlist(pl.pk), student_user_id=people.student.pk,
        provider="stripe", by=people.student, accept_terms=True,
    )
    assert gateways_services.simulate(old.id, "pay", user=people.student) == "completed"
    assert Enrolment.objects.get().amount_minor == 1500
```

(`revenue_between` returns rows keyed `currency` and `amount_minor`; check its body in `billing/services/summary.py:22` and adjust the key names to what it returns.)

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_purpose.py etqan/recorded/tests/test_purpose_e2e.py -q`
Expected: FAIL with `AttributeError: module ... has no attribute 'complete'`.

- [ ] **Step 3: Implement**

Append to `services/purpose.py`:

```python
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.platform.exceptions import ValidationError
from etqan.recorded.models import Playlist
from etqan.recorded.services.enrolments import enrol_from_sale

TRANSACTION_UNIQUE = "billing_payment_transaction_unique"
NOTES_MAX = 500
Applied = gateways_services.Applied


def _apply(purchase, done) -> Applied:
    """One inner block: the billing record, the enrolment and the purchase
    move together, or none of them does (B7-4)."""
    student = purchase.student
    try:
        with transaction.atomic():
            payment = billing_services.record_link_payment(
                student_id=student.pk,  # billing takes the profile pk here
                customer_name="",
                customer_email=student.user.email or "",
                customer_phone="",
                amount_minor=done.amount_minor,
                fee_minor=done.fee_minor,
                currency=done.currency,
                method=done.provider,
                transaction_number=done.transaction_number,
                notes=f"Recorded course: {purchase.playlist.title}"[:NOTES_MAX],
            )
            enrolment = enrol_from_sale(
                playlist=purchase.playlist,
                student_user_id=student.user_id,
                method=done.provider,
                amount_minor=done.amount_minor,
                currency=done.currency,
                transaction_number=done.transaction_number,
                payment_id=payment.pk,
                accepted_terms_at=purchase.accepted_terms_at,
            )
            purchase.status = Purchase.Status.PAID
            purchase.enrolment = enrolment
            purchase.paid_at = timezone.now()
            purchase.save(update_fields=["status", "enrolment", "paid_at"])
    except ConflictError as exc:
        if exc.code != "recorded.already_enrolled":
            raise
        return Applied(ok=False, reason="already_enrolled")
    except ValidationError as exc:
        if exc.field == "transaction_number":
            return Applied(ok=False, reason="already_recorded")
        # Money already paid that billing refuses: attention, never a webhook
        # 500 the provider retries forever. Logged by field only (no PII).
        logger.warning("recorded_course %s not recorded: refused on %s", done.id, exc.field)
        return Applied(ok=False)
    except IntegrityError as exc:
        diag = getattr(exc.__cause__, "diag", None)
        if getattr(diag, "constraint_name", None) != TRANSACTION_UNIQUE:
            raise
        return Applied(ok=False, reason="already_recorded")
    return Applied(ok=True)


def complete(done) -> Applied:
    """S-6. Lock order: playlist, then purchase (as start_purchase and
    enrol_from_sale). Whether the course is still published is not checked:
    money already paid still enrols."""
    playlist_id = (
        Purchase.objects.filter(pk=done.reference_id)
        .values_list("playlist_id", flat=True)
        .first()
    )
    if playlist_id is None:
        return Applied(ok=False, reason="reference_missing")
    with transaction.atomic():
        Playlist.objects.select_for_update().filter(pk=playlist_id).first()
        purchase = (
            Purchase.objects.select_for_update(of=("self",))
            .select_related("playlist", "student__user")
            .filter(pk=done.reference_id, playlist_id=playlist_id)
            .first()
        )
        if purchase is None:
            return Applied(ok=False, reason="reference_missing")
        if purchase.status == Purchase.Status.PAID:
            return Applied(ok=False, reason="purchase_paid")
        if done.currency != purchase.currency:
            return Applied(ok=False, reason="currency_mismatch")
        if Enrolment.objects.filter(
            playlist_id=playlist_id,
            student=purchase.student,
            status=Enrolment.Status.ACTIVE,
        ).exists():
            return Applied(ok=False, reason="already_enrolled")
        return _apply(purchase, done)


def register() -> None:
    gateways_services.register_purpose(NAME, prepare=prepare, complete=complete)
```

Move the new imports to the top of the module with the others. `ruff` sorts them.

`apps.py`. Add to the existing `ready()`, after whatever plan 49 put there (or create `ready()` if there is none):

```python
    def ready(self):
        # (plan 49's lines stay as they are)
        from etqan.recorded.services import purpose  # noqa: PLC0415

        purpose.register()
```

Remove the `xfail` marks added in Task 4.

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded etqan/gateways -q`
Expected: PASS. Then run `B lint-imports`; it fails on `etqan.gateways` until Task 6 adds recorded to the gateways contract. That is acceptable only between these two commits; run Task 6 next.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded
git -C backend commit -m "feat(recorded): B7b recorded_course purpose completion" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Contract and throttles (shared files, under claims)

**Files:**
- Modify: `backend/pyproject.toml` (the "gateways imports no business app" contract), `backend/config/settings/base.py` (`DEFAULT_THROTTLE_RATES`)

- [ ] **Step 1: Claim, edit, commit and release `pyproject.toml`**

From the meta worktree, claim the file:

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/pyproject.toml --reason "B7b: add etqan.recorded to 'gateways imports no business app' (phase spec §4, D53)"
```

In `forbidden_modules` of the contract named `gateways imports no business app`, append `"etqan.recorded",` after `"etqan.finance",`.

Then:

1. Run `B lint-imports`. Expected: PASS. The contract proves gateways never imports `etqan.recorded`.
2. Commit:

   ```bash
   git -C backend add pyproject.toml
   git -C backend commit -m "chore(gateways): gateways never imports etqan.recorded (B7b, D53)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
   ```

3. Release the claim:

   ```bash
   python3 scripts/orchestration/ledger.py release B7 backend/pyproject.toml
   ```

- [ ] **Step 2: Claim, edit, commit and release `base.py`**

Claim the file:

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/config/settings/base.py --reason "B7b: throttle scope recorded_public (S-9)"
```

In `DEFAULT_THROTTLE_RATES`, after `"payment_link": "60/minute",`:

```python
        # B7b S-9: the public recorded-course catalogue, per IP.
        "recorded_public": "60/minute",
```

Commit:

```bash
git -C backend add config/settings/base.py
git -C backend commit -m "chore(settings): recorded_public throttle scope (B7b)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Release the claim:

```bash
python3 scripts/orchestration/ledger.py release B7 backend/config/settings/base.py
```

---

### Task 7: The store API (S-2…S-4, S-7)

**Files:**
- Create: `backend/etqan/recorded/api/store_views.py`, `backend/etqan/recorded/tests/test_api_store.py`
- Modify: `backend/etqan/recorded/api/serializers.py`, `backend/etqan/recorded/api/urls.py`, `backend/etqan/access/tests/test_routes.py` (`SELF_SERVICE`)

**Interfaces:**
- Produces these routes:

  | Route | Answer |
  |---|---|
  | `GET recorded/store/?student=` | `[StoreItemJSON]` |
  | `GET recorded/store/<id>/?student=` | `StoreDetailJSON` |
  | `POST recorded/store/<id>/enrol/` | `{student_id?, accept_terms}` → 201 `{id, playlist}` |
  | `POST recorded/store/<id>/buy/` | `{student_id?, provider, accept_terms}` → 201 `{id, redirect_url, amount_minor, fee_minor, currency}` |
  | `GET recorded/store/<id>/providers/` | `{providers: ["stripe", "paypal"]}` |

- JSON shapes, used by Task 9:
  - `StoreItemJSON = {id, title, slug, thumbnail_url, content_language, lessons, seconds, price_minor, discount_minor, net_minor, currency, enrolled}`
  - `StoreDetailJSON = StoreItemJSON + {description, content, terms, intro_video_url, outline: [{title, duration_seconds}]}`

- [ ] **Step 1: Write the failing tests** (`tests/test_api_store.py`)

```python
import pytest

from etqan.recorded.models import Enrolment
from etqan.recorded.models import Purchase
from etqan.recorded.tests.conftest import as_user

pytestmark = pytest.mark.django_db
S = "/api/v1/recorded/store/"


def test_list_and_detail(people, course):
    pl = course()
    rows = as_user(people.student).get(S).json()
    assert [r["id"] for r in rows] == [pl.pk]
    assert {k: rows[0][k] for k in ("net_minor", "enrolled", "lessons", "seconds")} == {
        "net_minor": 1500, "enrolled": False, "lessons": 2, "seconds": 180,
    }
    detail = as_user(people.parent).get(f"{S}{pl.pk}/", {"student": people.student.pk}).json()
    assert detail["outline"] == [
        {"title": "Lesson one", "duration_seconds": 60},
        {"title": "Lesson two", "duration_seconds": 120},
    ]
    assert detail["terms"] == "Be kind."


def test_free_enrol(people, course):
    pl = course(price_minor=0, discount_minor=0)
    client = as_user(people.student)
    assert client.post(f"{S}{pl.pk}/enrol/", {}, format="json").status_code == 400
    resp = client.post(f"{S}{pl.pk}/enrol/", {"accept_terms": True}, format="json")
    assert resp.status_code == 201
    assert Enrolment.objects.get().method == "free"
    again = client.post(f"{S}{pl.pk}/enrol/", {"accept_terms": True}, format="json")
    assert (again.status_code, again.json()["code"]) == (409, "recorded.already_enrolled")


def test_buy(people, course, online_on, stripe_on):
    pl = course()
    resp = as_user(people.parent).post(
        f"{S}{pl.pk}/buy/",
        {"student_id": people.student.pk, "provider": "stripe", "accept_terms": True},
        format="json",
    )
    assert resp.status_code == 201, resp.content
    assert set(resp.json()) == {"id", "redirect_url", "amount_minor", "fee_minor", "currency"}
    assert Purchase.objects.get().created_by == people.parent


def test_providers(people, course, online_on, stripe_on, set_features):
    pl = course()
    assert as_user(people.student).get(f"{S}{pl.pk}/providers/").json() == {
        "providers": ["stripe"]
    }
    set_features(online_payments=False)
    assert as_user(people.student).get(f"{S}{pl.pk}/providers/").status_code == 404


def test_store_access(people, course, online_on, stripe_on, api_for, set_features):
    """Review Focus 4."""
    pl = course()
    body = {"student_id": people.other.pk, "provider": "stripe", "accept_terms": True}
    assert as_user(people.parent).post(f"{S}{pl.pk}/buy/", body, format="json").status_code == 404
    assert as_user(people.parent).get(S).status_code == 404  # a parent must name a child
    for role in ("admin", "staff", "teacher"):
        assert api_for(role).get(S).status_code == 403
    client = as_user(people.student)
    session = client.session
    session["etqan.impersonator"] = {"id": 1}
    session.save()
    assert client.post(
        f"{S}{pl.pk}/buy/", {"provider": "stripe", "accept_terms": True}, format="json"
    ).status_code == 403
    set_features(online_payments=False)
    assert as_user(people.student).post(
        f"{S}{pl.pk}/buy/", {"provider": "stripe", "accept_terms": True}, format="json"
    ).status_code == 404
    set_features(recorded_courses=False)
    assert as_user(people.student).get(S).status_code == 404
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_api_store.py -q`
Expected: FAIL with 404s on the unknown routes.

- [ ] **Step 3: Implement**

Append to `api/serializers.py`:

```python
class StoreEnrolInput(serializers.Serializer):
    student_id = serializers.IntegerField(required=False, min_value=1)
    accept_terms = serializers.BooleanField(required=False, default=False)


class StoreBuyInput(StoreEnrolInput):
    provider = serializers.ChoiceField(choices=["stripe", "paypal"])


def store_item(item) -> dict:
    p = item.playlist
    return {
        "id": p.pk,
        "title": p.title,
        "slug": p.slug,
        "thumbnail_url": _url(p.thumbnail),
        "content_language": p.content_language,
        "lessons": getattr(p, "lessons", 0),
        "seconds": getattr(p, "seconds", 0),
        "price_minor": p.price_minor,
        "discount_minor": p.discount_minor,
        "net_minor": item.net_minor,
        "currency": p.currency,
        "enrolled": item.enrolled,
    }


def store_detail_data(detail) -> dict:
    p = detail.playlist
    return {
        **store_item(detail),
        "description": p.description,
        "content": p.content,
        "terms": p.terms,
        "intro_video_url": _url(p.intro_video),
        "outline": [
            {"title": o.title, "duration_seconds": o.duration_seconds}
            for o in detail.outline
        ],
    }
```

`api/store_views.py`:

```python
"""B7b S-2…S-4, S-7: the store for students and parents. Staff and admins
get 403 from the role check; a quick-login session cannot buy or enrol (D19);
buying also needs online_payments (404 while it is off)."""

from django.http import Http404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from etqan.gateways import services as gateways_services
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import NotImpersonating
from etqan.recorded import services
from etqan.recorded.api.params import int_param
from etqan.recorded.api.serializers import StoreBuyInput
from etqan.recorded.api.serializers import StoreEnrolInput
from etqan.recorded.api.serializers import store_detail_data
from etqan.recorded.api.serializers import store_item

FAMILY = [IsStudent | IsParent, FeatureOn]
WRITERS = [IsStudent | IsParent, NotImpersonating, FeatureOn]


def _sale_target(request, pk, body):
    try:
        sid = services.buyer_student_id(request.user, body.get("student_id"))
        services.store_detail(pk, request.user, sid)
    except NotFoundError:
        raise Http404 from None
    return services.get_playlist(pk), sid


class StoreListView(APIView):
    feature = "recorded_courses"
    permission_classes = FAMILY

    def get(self, request):
        try:
            items = services.storefront(
                request.user, int_param(request.query_params, "student")
            )
        except NotFoundError:
            raise Http404 from None
        return Response([store_item(i) for i in items])


class StoreDetailView(APIView):
    feature = "recorded_courses"
    permission_classes = FAMILY

    def get(self, request, pk):
        try:
            detail = services.store_detail(
                pk, request.user, int_param(request.query_params, "student")
            )
        except NotFoundError:
            raise Http404 from None
        return Response(store_detail_data(detail))


class StoreProvidersView(APIView):
    feature = "recorded_courses"
    permission_classes = FAMILY

    def get(self, request, pk):
        if not features.enabled("online_payments"):
            raise Http404
        try:
            detail = services.store_detail(
                pk, request.user, int_param(request.query_params, "student")
            )
        except NotFoundError:
            raise Http404 from None
        return Response(
            {
                "providers": gateways_services.providers_for(
                    detail.playlist.currency, detail.net_minor, add_fee=True
                )
            }
        )


class StoreEnrolView(APIView):
    feature = "recorded_courses"
    permission_classes = WRITERS

    def post(self, request, pk):
        body = StoreEnrolInput(data=request.data)
        body.is_valid(raise_exception=True)
        playlist, sid = _sale_target(request, pk, body.validated_data)
        e = services.enrol_free(
            playlist,
            student_user_id=sid,
            by=request.user,
            accept_terms=body.validated_data["accept_terms"],
        )
        return Response({"id": e.pk, "playlist": e.playlist_id}, status=status.HTTP_201_CREATED)


class StoreBuyView(APIView):
    """Non-atomic (as gateways' start route): the purchase commits before
    the provider is called."""

    feature = "recorded_courses"
    permission_classes = WRITERS
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "gateway_start"
    atomic_request = False

    def post(self, request, pk):
        if not features.enabled("online_payments"):
            raise Http404
        body = StoreBuyInput(data=request.data)
        body.is_valid(raise_exception=True)
        playlist, sid = _sale_target(request, pk, body.validated_data)
        started = services.start_purchase(
            playlist,
            student_user_id=sid,
            provider=body.validated_data["provider"],
            by=request.user,
            accept_terms=body.validated_data["accept_terms"],
        )
        return Response(
            {
                "id": str(started.id),
                "redirect_url": started.redirect_url,
                "amount_minor": started.amount_minor,
                "fee_minor": started.fee_minor,
                "currency": started.currency,
            },
            status=status.HTTP_201_CREATED,
        )
```

`api/urls.py`. Add the import `from django.db import transaction`, `from etqan.recorded.api import store_views`, and:

```python
    path("store/", store_views.StoreListView.as_view()),
    path("store/<int:pk>/", store_views.StoreDetailView.as_view()),
    path("store/<int:pk>/providers/", store_views.StoreProvidersView.as_view()),
    path("store/<int:pk>/enrol/", store_views.StoreEnrolView.as_view()),
    path(
        "store/<int:pk>/buy/",
        transaction.non_atomic_requests(store_views.StoreBuyView.as_view()),
    ),
```

`access/tests/test_routes.py` `SELF_SERVICE`, under a `# Phase B7, slice B7b` comment:

```python
    "etqan.recorded.api.store_views.StoreListView": "a family's own store (role check, scoped in the service)",
    "etqan.recorded.api.store_views.StoreDetailView": "a family's own store (role check, scoped in the service)",
    "etqan.recorded.api.store_views.StoreProvidersView": "a family's own store (role check, scoped in the service)",
    "etqan.recorded.api.store_views.StoreEnrolView": "a family enrols its own student (role check, scoped in the service)",
    "etqan.recorded.api.store_views.StoreBuyView": "a family buys for its own student (role check, scoped in the service)",
```

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded etqan/access etqan/platform/tests/test_drf.py -q`
Expected: PASS. `test_drf` checks that the non-atomic view is wrapped.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded etqan/access/tests/test_routes.py
git -C backend commit -m "feat(recorded): B7b store API" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The public catalogue API (S-9)

**Files:**
- Create: `backend/etqan/recorded/api/public_views.py`, `backend/etqan/recorded/tests/test_api_public.py`
- Modify: `api/serializers.py`, `api/urls.py`, `access/tests/test_routes.py` (`SELF_SERVICE`)

**Interfaces:**
- Produces: `GET recorded/public/playlists/` → `[PublicJSON]` and `GET recorded/public/playlists/<slug>/` → `PublicJSON`, where `PublicJSON = StoreDetailJSON` without `enrolled`.

- [ ] **Step 1: Write the failing tests**

```python
import pytest
from rest_framework.test import APIClient

pytestmark = pytest.mark.django_db
P = "/api/v1/recorded/public/playlists/"


def test_public_list_and_detail(people, course):
    pl = course()
    course(slug="hidden", code="H", is_published=False)
    anon = APIClient()
    rows = anon.get(P).json()
    assert [r["slug"] for r in rows] == ["tajweed"]
    assert rows[0]["id"] == pl.pk
    assert anon.get(f"{P}tajweed/").json()["net_minor"] == 1500
    assert anon.get(f"{P}hidden/").status_code == 404


def test_public_payload_has_no_student_data(people, course):
    """Review Focus 5."""
    from etqan.recorded import services

    pl = course()
    services.enrol_from_sale(
        playlist=pl, student_user_id=people.student.pk, method="free",
        amount_minor=0, currency="USD", transaction_number="", payment_id=None,
    )
    body = APIClient().get(f"{P}tajweed/").json()
    assert "enrolled" not in body and "enrolments" not in body
    assert people.student.full_name not in str(body)
    assert all(set(o) == {"title", "duration_seconds"} for o in body["outline"])


def test_public_off_is_404(people, course, set_features):
    course()
    set_features(recorded_courses=False)
    assert APIClient().get(P).status_code == 404
```

- [ ] **Step 2: Run them to see them fail**

Run: `B pytest etqan/recorded/tests/test_api_public.py -q`
Expected: FAIL (404 on unknown route for the list).

- [ ] **Step 3: Implement**

`api/serializers.py`:

```python
def public_playlist_data(detail) -> dict:
    data = store_detail_data(detail)
    data.pop("enrolled")
    return data
```

`api/public_views.py`:

```python
"""B7b S-9: the public catalogue for the marketing site. Anonymous (no
session read, so no CSRF), throttled per IP, 404 while recorded_courses is
off; only published, not app-only courses; no student data."""

from django.http import Http404
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.recorded import services
from etqan.recorded.api.serializers import public_playlist_data


class PublicPlaylistsView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny, FeatureOn]
    feature = "recorded_courses"
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "recorded_public"
    http_method_names = ["get", "options"]

    def get(self, request):
        return Response([public_playlist_data(d) for d in services.public_playlists()])


class PublicPlaylistView(PublicPlaylistsView):
    def get(self, request, slug):
        try:
            return Response(public_playlist_data(services.public_playlist(slug)))
        except NotFoundError:
            raise Http404 from None
```

`api/urls.py`:

```python
from etqan.recorded.api import public_views
    path("public/playlists/", public_views.PublicPlaylistsView.as_view()),
    path("public/playlists/<slug:slug>/", public_views.PublicPlaylistView.as_view()),
```

`SELF_SERVICE`:

```python
    "etqan.recorded.api.public_views.PublicPlaylistsView": "the public site (recorded_courses; throttled per IP)",
    "etqan.recorded.api.public_views.PublicPlaylistView": "the public site (recorded_courses; throttled per IP)",
```

- [ ] **Step 4: Run them to see them pass**

Run: `B pytest etqan/recorded etqan/access -q && B ruff check etqan/recorded && B lint-imports`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/recorded etqan/access/tests/test_routes.py
git -C backend commit -m "feat(recorded): B7b public catalogue API" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard data layer and strings

**Files:**
- Modify: `dashboard/src/features/recorded/schemas.ts`, `api.ts`, `api.test.ts`, `queries.ts`, `fixtures.ts`, `index.ts`
- Modify: `dashboard/src/locales/en/recorded.json`, `dashboard/src/locales/ar/recorded.json`

**Interfaces:**
- Produces:
  - types `StoreItem`, `StoreDetail`, `OutlineItem`;
  - `recordedApi.store(student?)`, `storeDetail(id, student?)`, `storeProviders(id)`, `enrolFree(id, body)`, `buy(id, body)`;
  - hooks `useStore(student?, enabled)`, `useStoreDetail(id, student?, enabled)`, `useStoreProviders(id, enabled)`, `useEnrolFree(id)`, `useBuy(id)`;
  - fixtures `storeItem`, `storeDetail`.
- Consumes: `Provider` and `StartedCheckout` from `@/features/gateways/schemas`.

- [ ] **Step 1: Write the failing test** (append to `api.test.ts`)

```ts
describe("store calls", () => {
	beforeEach(() => vi.restoreAllMocks());

	it("reads the store for a child and buys", async () => {
		const get = vi.spyOn(api, "get").mockResolvedValue({ data: [] });
		await recordedApi.store(21);
		expect(get).toHaveBeenCalledWith("recorded/store/", { params: { student: 21 } });
		await recordedApi.store();
		expect(get).toHaveBeenLastCalledWith("recorded/store/", { params: {} });
		await recordedApi.storeDetail(4, 21);
		expect(get).toHaveBeenLastCalledWith("recorded/store/4/", { params: { student: 21 } });
		get.mockResolvedValue({ data: { providers: ["stripe"] } });
		expect(await recordedApi.storeProviders(4)).toEqual(["stripe"]);
		const post = vi.spyOn(api, "post").mockResolvedValue({ data: { id: "x" } });
		await recordedApi.buy(4, { student_id: 21, provider: "stripe", accept_terms: true });
		expect(post).toHaveBeenCalledWith("recorded/store/4/buy/", {
			student_id: 21, provider: "stripe", accept_terms: true,
		});
		await recordedApi.enrolFree(4, { accept_terms: true });
		expect(post).toHaveBeenLastCalledWith("recorded/store/4/enrol/", { accept_terms: true });
	});
});
```

- [ ] **Step 2: Run** `F pnpm vitest run src/features/recorded/api.test.ts`
Expected: FAIL with `recordedApi.store is not a function`.

- [ ] **Step 3: Implement**

`schemas.ts`. Append:

```ts
export interface OutlineItem {
	title: string;
	duration_seconds: number;
}

/** B7b S-1: a course for sale; `enrolled` is for the viewing student. */
export interface StoreItem {
	id: number;
	title: string;
	slug: string;
	thumbnail_url: string;
	content_language: ContentLanguage;
	lessons: number;
	seconds: number;
	price_minor: number;
	discount_minor: number;
	net_minor: number;
	currency: string;
	enrolled: boolean;
}

export interface StoreDetail extends StoreItem {
	description: string;
	content: string;
	terms: string;
	intro_video_url: string;
	outline: OutlineItem[];
}
```

`api.ts`. Add the imports `import type { Provider, StartedCheckout } from "@/features/gateways/schemas";` and `StoreDetail`, `StoreItem` from `./schemas`. Then add the bodies and the calls inside `recordedApi`:

```ts
export interface StoreEnrolBody {
	student_id?: number;
	accept_terms: boolean;
}
export interface StoreBuyBody extends StoreEnrolBody {
	provider: Provider;
}

const studentParams = (student?: number) =>
	student === undefined ? {} : { student };
```

```ts
	store: async (student?: number) =>
		(await api.get<StoreItem[]>(`${B}store/`, { params: studentParams(student) }))
			.data,
	storeDetail: async (id: number, student?: number) =>
		(
			await api.get<StoreDetail>(`${B}store/${id}/`, {
				params: studentParams(student),
			})
		).data,
	storeProviders: async (id: number) =>
		(await api.get<{ providers: Provider[] }>(`${B}store/${id}/providers/`)).data
			.providers,
	enrolFree: async (id: number, body: StoreEnrolBody) =>
		(await api.post<{ id: number; playlist: number }>(`${B}store/${id}/enrol/`, body))
			.data,
	buy: async (id: number, body: StoreBuyBody) =>
		(await api.post<StartedCheckout>(`${B}store/${id}/buy/`, body)).data,
```

`queries.ts`:

```ts
export const useStore = (student?: number, enabled = true) =>
	useQuery({
		queryKey: [...recordedKey, "store", student ?? null],
		queryFn: () => recordedApi.store(student),
		enabled,
	});
export const useStoreDetail = (id: number, student?: number, enabled = true) =>
	useQuery({
		queryKey: [...recordedKey, "store", id, student ?? null],
		queryFn: () => recordedApi.storeDetail(id, student),
		enabled,
	});
export const useStoreProviders = (id: number, enabled = true) =>
	useQuery({
		queryKey: [...recordedKey, "store", id, "providers"],
		queryFn: () => recordedApi.storeProviders(id),
		enabled,
		retry: false,
	});
export const useEnrolFree = (id: number) =>
	useInvalidating((body: StoreEnrolBody) => recordedApi.enrolFree(id, body));
export const useBuy = (id: number) =>
	useMutation({ mutationFn: (body: StoreBuyBody) => recordedApi.buy(id, body) });
```

(Import `StoreBuyBody` and `StoreEnrolBody` from `./api`.)

`fixtures.ts`:

```ts
export const storeItem: StoreItem = {
	id: 4,
	title: "Tajweed, level 1",
	slug: "tajweed-1",
	thumbnail_url: "/t.png",
	content_language: "ar",
	lessons: 2,
	seconds: 180,
	price_minor: 2000,
	discount_minor: 500,
	net_minor: 1500,
	currency: "USD",
	enrolled: false,
};

export const storeDetail: StoreDetail = {
	...storeItem,
	description: "Rules of recitation.",
	content: "What you will learn.",
	terms: "Be kind.",
	intro_video_url: "/media/intro.mp4",
	outline: [
		{ title: "Lesson one", duration_seconds: 60 },
		{ title: "Lesson two", duration_seconds: 120 },
	],
};
```

`index.ts`. Export `Store` and `StoreDetailPage` (Task 10).

`locales/en/recorded.json`. Add, keeping the top-level `recorded` object:

```json
"nav": { "office": "Recorded courses", "mine": "My recorded courses", "store": "Recorded courses store" },
"store": {
	"empty": "No recorded courses are for sale yet.",
	"enrolled": "Enrolled",
	"open": "Open course",
	"free": "Free",
	"lessons_one": "{{count}} lesson",
	"lessons_other": "{{count}} lessons",
	"outline": "Course outline",
	"terms": "Terms and conditions",
	"accept": "I accept the terms and conditions",
	"enrolFree": "Enrol for free",
	"buyWith": "Buy with {{provider}}",
	"noProviders": "Online payment is not available for this course.",
	"priceWas": "Was {{price}}",
	"introVideo": "Introduction"
},
"return": { "open": "Open my recorded courses", "store": "Back to the store" }
```

Also add `"not_free": "This course is not free."`, `"not_for_sale": "This course is not for sale."`, `"price_changed": "The price has changed. Buy again."` and `"free": "This course is free: enrol instead."` to `recorded.errors`.

`locales/ar/recorded.json` gets the same keys:

```json
"nav": { "office": "الدورات المسجلة", "mine": "دوراتي المسجلة", "store": "متجر الدورات المسجلة" },
"store": {
	"empty": "لا توجد دورات مسجلة للبيع بعد.",
	"enrolled": "مشترك",
	"open": "افتح الدورة",
	"free": "مجانية",
	"lessons_zero": "{{count}} درس",
	"lessons_one": "درس واحد",
	"lessons_two": "درسان",
	"lessons_few": "{{count}} دروس",
	"lessons_many": "{{count}} درسًا",
	"lessons_other": "{{count}} درس",
	"outline": "محتوى الدورة",
	"terms": "الشروط والأحكام",
	"accept": "أوافق على الشروط والأحكام",
	"enrolFree": "اشترك مجانًا",
	"buyWith": "اشترِ عبر {{provider}}",
	"noProviders": "الدفع الإلكتروني غير متاح لهذه الدورة.",
	"priceWas": "كان {{price}}",
	"introVideo": "مقدمة"
},
"return": { "open": "افتح دوراتي المسجلة", "store": "العودة إلى المتجر" }
```

The errors in Arabic are: `"not_free": "هذه الدورة ليست مجانية."`, `"not_for_sale": "هذه الدورة غير معروضة للبيع."`, `"price_changed": "تغيّر السعر. اشترِ مرة أخرى."` and `"free": "هذه الدورة مجانية: اشترك بدلًا من ذلك."`.

The ar/en key-equality test treats plural suffixes the way the existing `*_one`/`*_other` keys already are. Check `src/locales/locales.test.ts`'s rule. If it requires equal key sets, give en the same six plural keys (en uses `_one` and `_other` at runtime).

- [ ] **Step 4: Run them to see them pass**

Run: `F pnpm vitest run src/features/recorded src/locales && F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded src/locales/en/recorded.json src/locales/ar/recorded.json
git -C dashboard commit -m "feat(recorded): B7b store data layer and strings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Store pages, buy flow, routes and nav (S-1…S-4)

**Files:**
- Create: `dashboard/src/features/recorded/Store.tsx`, `Store.test.tsx`, `StoreDetail.tsx`, `StoreDetail.test.tsx`, `BuyPanel.tsx`, `BuyPanel.test.tsx`
- Create: `dashboard/src/routes/_authed/learning.recorded.store.index.tsx`, `dashboard/src/routes/_authed/learning.recorded.store.$playlistId.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B7 ──`, after B7a's "mine" item), `dashboard/src/features/recorded/index.ts`, `dashboard/src/routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: `useMe`, `useStore`, `useStoreDetail`, `useStoreProviders`, `useEnrolFree`, `useBuy`, `formatMoney` (`@/lib/money`), `formatDuration`, `go` (`@/features/gateways/redirect`), `PROVIDER_NAMES` (`@/features/gateways/schemas`), `Money` (`@/features/billing`).
- Produces:
  - `<Store />`: cards linking to `/learning/recorded/store/$playlistId?student=`;
  - `<StoreDetailPage playlistId student? />`;
  - `<BuyPanel detail student? />`.

- [ ] **Step 1: Write the failing tests**

`BuyPanel.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { go } from "@/features/gateways/redirect";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { BuyPanel } from "./BuyPanel";
import { storeDetail } from "./fixtures";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, recordedApi: { ...actual.recordedApi, storeProviders: vi.fn(), buy: vi.fn(), enrolFree: vi.fn() } };
});
vi.mock("@/features/gateways/redirect", () => ({ go: vi.fn() }));

describe("BuyPanel", () => {
	beforeEach(() => vi.clearAllMocks());

	it("buys only after the terms are accepted, then shows the fee sheet", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.storeProviders).mockResolvedValue(["stripe"]);
		vi.mocked(recordedApi.buy).mockResolvedValue({
			id: "c1", redirect_url: "https://pay.test/c1", amount_minor: 1500, fee_minor: 75, currency: "USD",
		});
		renderWithRouter(<BuyPanel detail={storeDetail} student={21} />);
		const buy = await screen.findByRole("button", { name: "Buy with Stripe" });
		expect(buy).toBeDisabled();
		await user.click(screen.getByLabelText("I accept the terms and conditions"));
		await user.click(buy);
		expect(recordedApi.buy).toHaveBeenCalledWith(4, { student_id: 21, provider: "stripe", accept_terms: true });
		const sheet = await screen.findByRole("dialog");
		expect(sheet).toHaveTextContent("15.75");
		await user.click(screen.getByRole("button", { name: "Continue to Stripe" }));
		expect(go).toHaveBeenCalledWith("https://pay.test/c1");
	});

	it("enrols for free without a checkout", async () => {
		const user = userEvent.setup();
		vi.mocked(recordedApi.enrolFree).mockResolvedValue({ id: 9, playlist: 4 });
		renderWithRouter(<BuyPanel detail={{ ...storeDetail, net_minor: 0, price_minor: 0, discount_minor: 0 }} />);
		await user.click(screen.getByLabelText("I accept the terms and conditions"));
		await user.click(screen.getByRole("button", { name: "Enrol for free" }));
		expect(recordedApi.enrolFree).toHaveBeenCalledWith(4, { accept_terms: true });
		expect(recordedApi.buy).not.toHaveBeenCalled();
	});

	it("opens the course when already enrolled", () => {
		renderWithRouter(<BuyPanel detail={{ ...storeDetail, enrolled: true }} />, {
			extraPaths: ["/learning/recorded/$playlistId"],
		});
		expect(screen.getByRole("link", { name: "Open course" })).toHaveAttribute(
			"href", expect.stringContaining("/learning/recorded/4"),
		);
	});

	it("says when no provider can take it", async () => {
		vi.mocked(recordedApi.storeProviders).mockResolvedValue([]);
		renderWithRouter(<BuyPanel detail={storeDetail} />);
		expect(await screen.findByText("Online payment is not available for this course.")).toBeVisible();
	});

	it("shows a price change as its message", async () => {
		const user = userEvent.setup();
		const { AxiosError } = await import("axios");
		vi.mocked(recordedApi.storeProviders).mockResolvedValue(["stripe"]);
		vi.mocked(recordedApi.buy).mockRejectedValue(
			new AxiosError("409", "409", undefined, undefined, {
				status: 409, data: { detail: "x", code: "recorded.price_changed" },
			} as never),
		);
		renderWithRouter(<BuyPanel detail={storeDetail} />);
		await user.click(await screen.findByLabelText("I accept the terms and conditions"));
		await user.click(screen.getByRole("button", { name: "Buy with Stripe" }));
		expect(await screen.findByText("The price has changed. Buy again.")).toBeVisible();
	});
});
```

`Store.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { useMe } from "@/features/identity/queries";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { storeItem } from "./fixtures";
import { Store } from "./Store";

vi.mock("@/features/identity/queries", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/queries")>();
	return { ...actual, useMe: vi.fn() };
});
vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, recordedApi: { ...actual.recordedApi, store: vi.fn() } };
});
const asMe = (data: object) => vi.mocked(useMe).mockReturnValue({ data, isPending: false } as never);

describe("Store", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(recordedApi.store).mockResolvedValue([storeItem, { ...storeItem, id: 5, title: "Enrolled one", enrolled: true }]);
	});

	it("lists courses with the struck price and an enrolled badge", async () => {
		asMe({ id: 21, role: "student" });
		renderWithRouter(<Store />);
		expect(await screen.findByRole("link", { name: /Tajweed, level 1/ })).toHaveAttribute(
			"href", expect.stringContaining("/learning/recorded/store/4"),
		);
		expect(screen.getByText("Enrolled")).toBeVisible();
		expect(screen.getByText(/Was/)).toBeVisible();
		expect(recordedApi.store).toHaveBeenCalledWith(undefined);
	});

	it("a parent picks a child", async () => {
		const user = userEvent.setup();
		asMe({ id: 30, role: "parent", children: [
			{ id: 21, full_name: "Yusuf", student_profile_id: 1 },
			{ id: 22, full_name: "Maryam", student_profile_id: 2 },
		] });
		renderWithRouter(<Store />);
		await screen.findByRole("link", { name: /Tajweed/ });
		expect(recordedApi.store).toHaveBeenCalledWith(21);
		await user.selectOptions(screen.getByLabelText("Child"), "22");
		expect(recordedApi.store).toHaveBeenLastCalledWith(22);
	});

	it("shows an empty state", async () => {
		asMe({ id: 21, role: "student" });
		vi.mocked(recordedApi.store).mockResolvedValue([]);
		renderWithRouter(<Store />);
		expect(await screen.findByText("No recorded courses are for sale yet.")).toBeVisible();
	});
});
```

`StoreDetail.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { recordedApi } from "./api";
import { storeDetail } from "./fixtures";
import { StoreDetailPage } from "./StoreDetail";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, recordedApi: { ...actual.recordedApi, storeDetail: vi.fn(), storeProviders: vi.fn() } };
});

describe("StoreDetailPage", () => {
	it("shows the outline (titles and durations only), the terms and the intro", async () => {
		vi.mocked(recordedApi.storeDetail).mockResolvedValue(storeDetail);
		vi.mocked(recordedApi.storeProviders).mockResolvedValue(["stripe"]);
		const { container } = renderWithRouter(<StoreDetailPage playlistId={4} student={21} />);
		expect(await screen.findByRole("heading", { name: "Tajweed, level 1" })).toBeVisible();
		expect(screen.getByText("Lesson one")).toBeVisible();
		expect(screen.getByText("00:01:00")).toBeVisible();
		expect(screen.getByText("Be kind.")).toBeVisible();
		expect(container.querySelector("video")?.getAttribute("src")).toBe("/media/intro.mp4");
		expect(recordedApi.storeDetail).toHaveBeenCalledWith(4, 21);
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `F pnpm vitest run src/features/recorded`
Expected: FAIL (modules missing).

- [ ] **Step 3: Implement**

`BuyPanel.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { go } from "@/features/gateways/redirect";
import { PROVIDER_NAMES, type Provider, type StartedCheckout } from "@/features/gateways/schemas";
import {
	Alert, AlertDescription, Button, buttonVariants, Checkbox, Dialog, DialogContent,
	DialogDescription, DialogFooter, DialogTitle, FormError,
} from "@/ui";
import { recordedErrorText } from "./errors";
import { useBuy, useEnrolFree, useStoreProviders } from "./queries";
import type { StoreDetail } from "./schemas";

/** B7b S-2…S-4: the terms gate, then the free enrol or a provider's
 * checkout; the sheet shows the server's own fee before the redirect. */
export function BuyPanel({ detail, student }: { detail: StoreDetail; student?: number }) {
	const { t } = useTranslation();
	const [accepted, setAccepted] = useState(false);
	const [sheet, setSheet] = useState<(StartedCheckout & { provider: Provider }) | null>(null);
	const free = detail.net_minor === 0;
	const providers = useStoreProviders(detail.id, !detail.enrolled && !free);
	const enrol = useEnrolFree(detail.id);
	const buy = useBuy(detail.id);
	const target = student === undefined ? {} : { student_id: student };
	const failure = enrol.error ?? buy.error;

	if (detail.enrolled)
		return (
			<Link
				to="/learning/recorded/$playlistId"
				params={{ playlistId: String(detail.id) }}
				search={student === undefined ? {} : { student }}
				className={buttonVariants()}
			>
				{t("recorded.store.open")}
			</Link>
		);

	async function begin(provider: Provider) {
		const started = await buy.mutateAsync({ ...target, provider, accept_terms: true });
		setSheet({ ...started, provider });
	}

	return (
		<div className="flex flex-col gap-3">
			<label className="flex items-center gap-2 text-sm">
				<Checkbox checked={accepted} onCheckedChange={(v) => setAccepted(v === true)}
					aria-label={t("recorded.store.accept")} />
				{t("recorded.store.accept")}
			</label>
			{failure ? <FormError>{recordedErrorText(failure, t)}</FormError> : null}
			{free ? (
				<Button disabled={!accepted || enrol.isPending}
					onClick={() => enrol.mutate({ ...target, accept_terms: true })}>
					{t("recorded.store.enrolFree")}
				</Button>
			) : providers.data && providers.data.length === 0 ? (
				<Alert><AlertDescription>{t("recorded.store.noProviders")}</AlertDescription></Alert>
			) : (
				<div className="flex flex-wrap gap-2">
					{(providers.data ?? []).map((p) => (
						<Button key={p} disabled={!accepted || buy.isPending}
							onClick={() => void begin(p).catch(() => undefined)}>
							{t("recorded.store.buyWith", { provider: PROVIDER_NAMES[p] })}
						</Button>
					))}
				</div>
			)}
			<Dialog open={sheet !== null} onOpenChange={(open) => !open && setSheet(null)}>
				{sheet ? (
					<DialogContent>
						<DialogTitle>{t("gateways.pay.title")}</DialogTitle>
						<DialogDescription className="sr-only">{t("gateways.pay.title")}</DialogDescription>
						<dl className="grid grid-cols-2 gap-2 text-sm">
							<dt>{t("gateways.pay.balance")}</dt>
							<dd><Money minor={sheet.amount_minor} currency={sheet.currency} /></dd>
							<dt>{t("gateways.pay.fee")}</dt>
							<dd><Money minor={sheet.fee_minor} currency={sheet.currency} /></dd>
							<dt className="font-medium">{t("gateways.pay.total")}</dt>
							<dd className="font-medium">
								<Money minor={sheet.amount_minor + sheet.fee_minor} currency={sheet.currency} />
							</dd>
						</dl>
						<DialogFooter>
							<Button variant="outline" onClick={() => setSheet(null)}>{t("gateways.pay.cancel")}</Button>
							<Button onClick={() => go(sheet.redirect_url)}>
								{t("gateways.pay.continue", { provider: PROVIDER_NAMES[sheet.provider] })}
							</Button>
						</DialogFooter>
					</DialogContent>
				) : null}
			</Dialog>
		</div>
	);
}
```

(If `@/ui` has no `Checkbox` with `onCheckedChange`, use the native `<input type="checkbox">` that plan 49's forms use. Check `src/ui/index.ts`.)

`Store.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { ShoppingBag } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { formatMoney } from "@/lib/money";
import { Badge, Card, CardContent, CardGrid, EmptyState, Field, FormError, Select, Spinner } from "@/ui";
import { formatDuration } from "./duration";
import { recordedErrorText } from "./errors";
import { useStore } from "./queries";
import type { StoreItem } from "./schemas";

export function Price({ item }: { item: StoreItem }) {
	const { t, i18n } = useTranslation();
	if (item.net_minor === 0) return <span>{t("recorded.store.free")}</span>;
	return (
		<span className="flex items-baseline gap-2">
			<span className="font-medium">{formatMoney(item.net_minor, item.currency, i18n.language)}</span>
			{item.discount_minor > 0 ? (
				<s className="text-sm text-muted-foreground">
					{t("recorded.store.priceWas", { price: formatMoney(item.price_minor, item.currency, i18n.language) })}
				</s>
			) : null}
		</span>
	);
}

export function Store() {
	const { t } = useTranslation();
	const { data: me, isPending } = useMe();
	const children = me?.children ?? [];
	const isParent = me?.role === "parent";
	const [picked, setPicked] = useState<number>();
	const child = isParent ? (picked ?? children[0]?.id) : undefined;
	const list = useStore(child, !isPending && (!isParent || child !== undefined));

	if (isPending || (list.isPending && list.fetchStatus !== "idle"))
		return <div className="flex justify-center py-6"><Spinner /></div>;
	return (
		<div className="flex flex-col gap-4">
			{isParent && children.length > 0 ? (
				<Field id="rs-child" label={t("recorded.my.childPicker")}>
					<Select className="w-auto" value={child ?? ""} onChange={(e) => setPicked(Number(e.target.value))}>
						{children.map((c) => <option key={c.id} value={c.id}>{c.full_name}</option>)}
					</Select>
				</Field>
			) : null}
			{list.isError ? (
				<FormError>{recordedErrorText(list.error, t)}</FormError>
			) : !list.data || list.data.length === 0 ? (
				<Card><CardContent><EmptyState icon={ShoppingBag} title={t("recorded.store.empty")} /></CardContent></Card>
			) : (
				<CardGrid>
					{list.data.map((item) => (
						<Card key={item.id}>
							<CardContent className="flex flex-col gap-2 pt-4">
								<Link to="/learning/recorded/store/$playlistId" params={{ playlistId: String(item.id) }}
									search={child === undefined ? {} : { student: child }}
									className="flex flex-col gap-2 font-medium">
									<img src={item.thumbnail_url} alt="" className="aspect-video w-full rounded object-cover" />
									{item.title}
								</Link>
								<p className="text-sm text-muted-foreground">
									{t("recorded.store.lessons", { count: item.lessons })} · {formatDuration(item.seconds)}
								</p>
								<div className="flex items-center justify-between gap-2">
									<Price item={item} />
									{item.enrolled ? <Badge>{t("recorded.store.enrolled")}</Badge> : null}
								</div>
							</CardContent>
						</Card>
					))}
				</CardGrid>
			)}
		</div>
	);
}
```

(`formatMoney`'s argument order follows plan 49 Task 12's usage of `@/lib/money`; match it there.)

`StoreDetail.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { Card, CardContent, FormError, PageHeader, Spinner } from "@/ui";
import { BuyPanel } from "./BuyPanel";
import { formatDuration } from "./duration";
import { recordedErrorText } from "./errors";
import { useStoreDetail } from "./queries";
import { Price } from "./Store";

export function StoreDetailPage({ playlistId, student }: { playlistId: number; student?: number }) {
	const { t } = useTranslation();
	const q = useStoreDetail(playlistId, student);
	usePageTitle(q.data?.title ?? t("recorded.nav.store"));
	if (q.isPending) return <div className="flex justify-center py-6"><Spinner /></div>;
	if (q.isError || !q.data) return <FormError>{recordedErrorText(q.error, t)}</FormError>;
	const d = q.data;
	return (
		<>
			<PageHeader title={d.title} />
			<div className="grid gap-4 lg:grid-cols-3">
				<Card className="lg:col-span-2">
					<CardContent className="flex flex-col gap-4 pt-4">
						{d.intro_video_url ? (
							<figure>
								<video controls preload="metadata" src={d.intro_video_url} poster={d.thumbnail_url}
									className="aspect-video w-full rounded" aria-label={t("recorded.store.introVideo")} />
							</figure>
						) : (
							<img src={d.thumbnail_url} alt="" className="aspect-video w-full rounded object-cover" />
						)}
						<p className="whitespace-pre-line">{d.description}</p>
						{d.content ? <p className="whitespace-pre-line text-sm">{d.content}</p> : null}
						<section>
							<h2 className="font-medium">{t("recorded.store.outline")}</h2>
							<ol className="mt-2 flex flex-col gap-1 text-sm">
								{d.outline.map((o, i) => (
									<li key={`${i}-${o.title}`} className="flex justify-between gap-2">
										<span>{o.title}</span>
										<span className="text-muted-foreground">{formatDuration(o.duration_seconds)}</span>
									</li>
								))}
							</ol>
						</section>
					</CardContent>
				</Card>
				<Card>
					<CardContent className="flex flex-col gap-4 pt-4">
						<Price item={d} />
						<p className="text-sm text-muted-foreground">
							{t("recorded.store.lessons", { count: d.lessons })} · {formatDuration(d.seconds)}
						</p>
						<section>
							<h2 className="font-medium">{t("recorded.store.terms")}</h2>
							<p className="mt-1 max-h-48 overflow-y-auto whitespace-pre-line text-sm">{d.terms}</p>
						</section>
						<BuyPanel detail={d} student={student} />
					</CardContent>
				</Card>
			</div>
		</>
	);
}
```

Routes. `learning.recorded.store.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { Store } from "@/features/recorded";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/recorded/store/")({
	staticData: { feature: "recorded_courses" },
	component: function RecordedStoreRoute() {
		const { t } = useTranslation();
		usePageTitle(t("recorded.nav.store"));
		return (
			<>
				<PageHeader title={t("recorded.nav.store")} />
				<Store />
			</>
		);
	},
});
```

`learning.recorded.store.$playlistId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { StoreDetailPage } from "@/features/recorded";

export const Route = createFileRoute("/_authed/learning/recorded/store/$playlistId")({
	staticData: { feature: "recorded_courses" },
	validateSearch: (search: Record<string, unknown>): { student?: number } => {
		const student = Number(search.student);
		return Number.isInteger(student) && student > 0 ? { student } : {};
	},
	component: function RecordedStoreDetailRoute() {
		const { playlistId } = Route.useParams();
		const { student } = Route.useSearch();
		return <StoreDetailPage playlistId={Number(playlistId)} student={student} />;
	},
});
```

`nav.ts`. Add `ShoppingBag` to the lucide import. Under `// ── phase B7 ──`, after B7a's `/learning/recorded` item:

```ts
	{
		to: "/learning/recorded/store",
		labelKey: "recorded.nav.store",
		icon: ShoppingBag,
		group: "learning",
		requiresRole: ["student", "parent"],
		feature: "recorded_courses",
	},
```

`index.ts`: `export { Store } from "./Store";` and `export { StoreDetailPage } from "./StoreDetail";`.

Regenerate the route tree with `F pnpm tsr generate`, or with the command plan 49 Task 12 used.

- [ ] **Step 4: Run them to see them pass**

Run: `F pnpm vitest run src/features/recorded src/features/shell src/test/a11y.test.tsx && F pnpm tsc --noEmit && F pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded src/features/shell/nav.ts src/routes/_authed/learning.recorded.store.index.tsx "src/routes/_authed/learning.recorded.store.\$playlistId.tsx" src/routeTree.gen.ts
git -C dashboard commit -m "feat(recorded): B7b store pages and buy flow" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Return-page branch and attention codes (S-8, S-11; shared files under claims)

**Files:**
- Modify (claim 1): `dashboard/src/features/gateways/ReturnPage.tsx`, `dashboard/src/features/gateways/ReturnPage.test.tsx`
- Modify (claim 2): `dashboard/src/features/gateways/schemas.ts`, `dashboard/src/locales/en/gateways.json`, `dashboard/src/locales/ar/gateways.json`

- [ ] **Step 1: Claim the return page, then write its failing test**

```bash
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/gateways/ReturnPage.tsx --reason "B7b S-8: recorded_course branch"
```

Append to `ReturnPage.test.tsx` inside the `describe`:

```tsx
	it("links a paid course purchase to My recorded courses, without asking who the payer is", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			...body("completed"), purpose: "recorded_course", reference_id: 77,
		} as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, {
			extraPaths: ["/learning/recorded", "/learning/recorded/store"],
		});
		expect(await screen.findByRole("link", { name: "Open my recorded courses" })).toHaveAttribute(
			"href", expect.stringContaining("/learning/recorded"),
		);
		expect(identityApi.me).not.toHaveBeenCalled();
	});

	it("sends an unpaid course purchase back to the store", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			...body("failed"), purpose: "recorded_course", reference_id: 77,
		} as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, {
			extraPaths: ["/learning/recorded", "/learning/recorded/store"],
		});
		expect(await screen.findByRole("link", { name: "Back to the store" })).toHaveAttribute(
			"href", expect.stringContaining("/learning/recorded/store"),
		);
	});
```

Run `F pnpm vitest run src/features/gateways/ReturnPage.test.tsx`. Expected: FAIL (no link found).

- [ ] **Step 2: Implement the branch**

In `ReturnPage.tsx`, add after `InvoiceLink`:

```tsx
/** B7b S-8: a course purchase. The checkout's reference is the purchase,
 * so a paid one opens My recorded courses and anything else the store; the
 * same for a student and a parent, so no `me` call. */
function RecordedLink({ paid }: { paid: boolean }) {
	const { t } = useTranslation();
	return (
		<Button asChild variant="outline" size="sm">
			{paid ? (
				<Link to="/learning/recorded">{t("recorded.return.open")}</Link>
			) : (
				<Link to="/learning/recorded/store">{t("recorded.return.store")}</Link>
			)}
		</Button>
	);
}
```

and replace the `link` helper with:

```tsx
	const link = (label: string) =>
		data.purpose === "recorded_course" ? (
			<RecordedLink paid={status === "completed"} />
		) : invoice ? (
			<InvoiceLink
				invoiceId={String(data.reference_id)}
				office={office}
				label={label}
			/>
		) : null;
```

The `useMe({ enabled: data?.purpose === "invoice" })` line is unchanged.

Run `F pnpm vitest run src/features/gateways`. Expected: PASS.

Commit:

```bash
git -C dashboard add src/features/gateways/ReturnPage.tsx src/features/gateways/ReturnPage.test.tsx
git -C dashboard commit -m "feat(gateways): return-page branch for recorded_course (B7b S-8)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Release the claim:

```bash
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/gateways/ReturnPage.tsx
```

- [ ] **Step 3: Claim the attention codes, then add them**

Claim both files:

```bash
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/gateways/schemas.ts --reason "B7b S-11: attention codes already_enrolled, purchase_paid"
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/locales/en/gateways.json --reason "B7b S-11 (en+ar gateways.json)"
```

`schemas.ts`. In `ATTENTION_CODES`, after `"link_closed",`:

```ts
	// B7b S-11: a recorded-course sale that could not be applied.
	"already_enrolled",
	"purchase_paid",
```

`locales/en/gateways.json` `attention`:

```json
		"already_enrolled": "The student was already enrolled; refund or keep as credit by hand.",
		"purchase_paid": "This course purchase was already paid by another checkout; refund one."
```

`locales/ar/gateways.json` `attention`:

```json
		"already_enrolled": "كان الطالب مشتركًا بالفعل؛ استرد المبلغ أو احتفظ به رصيدًا يدويًا.",
		"purchase_paid": "دُفعت عملية شراء هذه الدورة بالفعل عبر دفعة أخرى؛ استرد إحداهما."
```

Run `F pnpm vitest run src/features/gateways src/locales`. Expected: PASS. The existing `attention codes` test now checks the two new keys too.

Commit:

```bash
git -C dashboard add src/features/gateways/schemas.ts src/locales/en/gateways.json src/locales/ar/gateways.json
git -C dashboard commit -m "feat(gateways): attention codes for recorded-course sales (B7b S-11)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Release both claims:

```bash
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/gateways/schemas.ts
python3 scripts/orchestration/ledger.py release B7 dashboard/src/locales/en/gateways.json
```

---

### Task 12: Office enrolment line for online sales (S-12)

**Files:**
- Modify: `dashboard/src/features/recorded/EnrolmentDialog.tsx` (plan 49 Task 15), `EnrolmentDialog.test.tsx`, `locales/{en,ar}/recorded.json`

**Interfaces:**
- Consumes: `useCan` (`@/features/identity/permissions`), and `Enrolment.payment_id` and `transaction_number` from plan 49.
- Produces, on an online enrolment's dialog (`stripe`, `paypal`), a line "Transaction {{number}}" and a link "View payments" to `/billing/payments` when the viewer holds `payment.view_any`. The dashboard has no single-payment page, so the link goes to the payments list (spec gap noted in the report).

- [ ] **Step 1: Write the failing test** (append to `EnrolmentDialog.test.tsx`; reuse its `setup`/`can` helpers)

```tsx
	it("shows an online sale's transaction and links to the payments", async () => {
		renderDialog({ ...enrolment, method: "stripe", transaction_number: "pi_9", payment_id: 12 },
			["payment.view_any", "rc_enrolment.update"]);
		expect(await screen.findByText("Transaction pi_9")).toBeVisible();
		expect(screen.getByRole("link", { name: "View payments" })).toHaveAttribute(
			"href", expect.stringContaining("/billing/payments"),
		);
	});
```

(Name the helper the same as plan 49 Task 15's own test. If it is not `renderDialog`, use its name.)

- [ ] **Step 2: Run** `F pnpm vitest run src/features/recorded/EnrolmentDialog.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `EnrolmentDialog.tsx`, under the existing summary `<p>` for an existing enrolment:

```tsx
					{enrolment && (enrolment.method === "stripe" || enrolment.method === "paypal") ? (
						<p className="flex flex-wrap items-center gap-2 text-sm">
							<span>{t("recorded.enrolments.transactionLine", { number: enrolment.transaction_number })}</span>
							{enrolment.payment_id !== null && can("payment.view_any") ? (
								<Link to="/billing/payments" className="underline">{t("recorded.enrolments.viewPayments")}</Link>
							) : null}
						</p>
					) : null}
```

Add `"transactionLine": "Transaction {{number}}"` and `"viewPayments": "View payments"` to en `recorded.enrolments`, and `"transactionLine": "رقم المعاملة {{number}}"` and `"viewPayments": "عرض المدفوعات"` to ar. Import `Link` from `@tanstack/react-router` if the file does not already.

- [ ] **Step 4: Run them to see them pass**

Run: `F pnpm vitest run src/features/recorded src/locales && F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/recorded src/locales/en/recorded.json src/locales/ar/recorded.json
git -C dashboard commit -m "feat(recorded): B7b online sale line on the enrolment" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Marketing fetchers and pages (S-9, S-10)

**Files:**
- Create: `marketing/src/lib/recorded.ts`, `marketing/src/pages/[lang]/recorded-courses/index.astro`, `marketing/src/pages/[lang]/recorded-courses/[slug].astro`, `marketing/test/recorded.test.ts`

**Interfaces:**
- Consumes: `fetchSiteJson`, `normalizeHost`, `isValidHost` and `SitePayload` from `./site`; `isUpload` from `./videos`; `absoluteUrl` from `./seo`; the `Layout`, `Header`, `Footer`, `PageNotFound` and `StatusPage` components; `isLang`, `pick`, `preferredLang` and `ui` from `./i18n`.
- Produces:
  - `PublicPlaylist` (the backend's `PublicJSON`);
  - `getRecordedList(host)`, `getRecorded(host, slug)`;
  - `hasRecordedCourses(host): Promise<boolean>`, cached per host for 60 s and capped at 1000 hosts, never throwing;
  - `priceText(minor, currency, lang)`;
  - `safeMedia(site, url)` (`isUpload`, then absolute, else "").

- [ ] **Step 1: Write the failing tests** (`marketing/test/recorded.test.ts`)

```ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { afterEach, describe, expect, it, vi } from "vitest";
import * as http from "../src/lib/http";
import * as recorded from "../src/lib/recorded";
import Detail from "../src/pages/[lang]/recorded-courses/[slug].astro";
import Index from "../src/pages/[lang]/recorded-courses/index.astro";
import { demoSite } from "./fixtures";

const playlist = (patch: Partial<recorded.PublicPlaylist> = {}): recorded.PublicPlaylist => ({
	id: 4, title: "Tajweed", slug: "tajweed", thumbnail_url: "/media/t.png",
	content_language: "ar", lessons: 2, seconds: 180, price_minor: 2000,
	discount_minor: 500, net_minor: 1500, currency: "USD", description: "Rules <b>bold</b>",
	content: "Body", terms: "Be kind.", intro_video_url: "/media/intro.mp4",
	outline: [{ title: "Lesson one", duration_seconds: 60 }], ...patch,
});
const locals = { host: "demo.etqan.localhost", siteResult: { kind: "ok" as const, site: demoSite } };
const render = async (page: never, params: Record<string, string>, path: string) =>
	(await AstroContainer.create()).renderToResponse(page, {
		params, locals, request: new Request(`https://demo.example${path}`),
	});

afterEach(() => {
	vi.restoreAllMocks();
	recorded.clearRecordedCache();
});

describe("recorded fetchers", () => {
	it("reads the list and a detail by slug, refusing bad slugs", async () => {
		const spy = vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: [playlist()] });
		expect((await recorded.getRecordedList("Demo.Example")).kind).toBe("ok");
		expect(spy).toHaveBeenCalledWith("/api/v1/recorded/public/playlists/", "demo.example");
		spy.mockResolvedValue({ status: 200, body: playlist() });
		expect((await recorded.getRecorded("demo.example", "tajweed")).kind).toBe("ok");
		expect(spy).toHaveBeenLastCalledWith("/api/v1/recorded/public/playlists/tajweed/", "demo.example");
		expect((await recorded.getRecorded("demo.example", "../x")).kind).toBe("notfound");
	});

	it("caches the header flag and never throws", async () => {
		const spy = vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: [playlist()] });
		expect(await recorded.hasRecordedCourses("demo.example")).toBe(true);
		expect(await recorded.hasRecordedCourses("demo.example")).toBe(true);
		expect(spy).toHaveBeenCalledTimes(1);
		spy.mockResolvedValue({ status: 404, body: null });
		expect(await recorded.hasRecordedCourses("off.example")).toBe(false);
		spy.mockRejectedValue(new Error("down"));
		expect(await recorded.hasRecordedCourses("down.example")).toBe(false);
		expect(await recorded.hasRecordedCourses(undefined)).toBe(false);
	});

	it("formats prices in minor units", () => {
		expect(recorded.priceText(1500, "USD", "en")).toContain("15.00");
		expect(recorded.priceText(1500, "JPY", "en")).toContain("1,500");
	});
});

describe("recorded pages", () => {
	it("lists courses with a buy link into the dashboard, text escaped", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: [playlist()] });
		const html = await (await render(Index as never, { lang: "en" }, "/en/recorded-courses")).text();
		expect(html).toContain('href="/en/recorded-courses/tajweed"');
		expect(html).toContain("Rules &lt;b&gt;bold&lt;/b&gt;");
	});

	it("is a 404 when the list is empty or off", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: [] });
		expect((await render(Index as never, { lang: "en" }, "/en/recorded-courses")).status).toBe(404);
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 404, body: null });
		expect((await render(Index as never, { lang: "en" }, "/en/recorded-courses")).status).toBe(404);
	});

	it("shows a detail with the outline, the intro video and the buy link", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: playlist() });
		const html = await (await render(Detail as never, { lang: "en", slug: "tajweed" }, "/en/recorded-courses/tajweed")).text();
		expect(html).toContain('href="/app/learning/recorded/store/4"');
		expect(html).toContain("Lesson one");
		expect(html).toContain('src="https://demo.example/media/intro.mp4"');
		expect(html).toContain("Sign in, then open Recorded courses");
	});

	it("drops an unsafe media URL", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({
			status: 200, body: playlist({ intro_video_url: "javascript:alert(1)" }),
		});
		const html = await (await render(Detail as never, { lang: "en", slug: "tajweed" }, "/en/recorded-courses/tajweed")).text();
		expect(html).not.toContain("javascript:");
	});
});
```

(If `absoluteUrl` builds the site's own canonical host instead of the request host, adjust the expected `src` to `absoluteUrl(demoSite, "/media/intro.mp4")`, computed in the test.)

- [ ] **Step 2: Run them to see them fail**

Run: `M pnpm vitest run test/recorded.test.ts`
Expected: FAIL (modules missing).

- [ ] **Step 3: Implement**

`src/lib/recorded.ts`:

```ts
import { absoluteUrl } from "./seo";
import { type Fetched, fetchSiteJson, isValidHost, normalizeHost, type SitePayload } from "./site";
import { getJson } from "./http";
import { isUpload } from "./videos";

// B7b S-9, S-10: the public recorded-course catalogue. The list and detail
// are uncached (like the video fetchers); the header's "has courses" flag is
// cached per host, separately from the site payload, and never throws.

export type PublicPlaylist = {
	id: number;
	title: string;
	slug: string;
	thumbnail_url: string;
	content_language: string;
	lessons: number;
	seconds: number;
	price_minor: number;
	discount_minor: number;
	net_minor: number;
	currency: string;
	description: string;
	content: string;
	terms: string;
	intro_video_url: string;
	outline: { title: string; duration_seconds: number }[];
};

export const RECORDED_SLUG_RE = /^[a-z0-9-]{1,80}$/;
const isObj = (v: unknown): v is Record<string, unknown> =>
	typeof v === "object" && v !== null && !Array.isArray(v);
const isNum = (v: unknown) => typeof v === "number" && Number.isFinite(v);
const isStr = (v: unknown) => typeof v === "string";

export const isPublicPlaylist = (v: unknown): v is PublicPlaylist =>
	isObj(v) &&
	Number.isInteger(v.id) &&
	isStr(v.title) &&
	isStr(v.slug) &&
	isStr(v.thumbnail_url) &&
	isNum(v.lessons) &&
	isNum(v.seconds) &&
	isNum(v.price_minor) &&
	isNum(v.discount_minor) &&
	isNum(v.net_minor) &&
	typeof v.currency === "string" &&
	/^[A-Z]{3}$/.test(v.currency) &&
	isStr(v.description) &&
	isStr(v.content) &&
	isStr(v.terms) &&
	isStr(v.intro_video_url) &&
	Array.isArray(v.outline) &&
	v.outline.every((o) => isObj(o) && isStr(o.title) && isNum(o.duration_seconds));

const isList = (v: unknown) => Array.isArray(v) && v.every(isPublicPlaylist);

export function getRecordedList(host: string): Promise<Fetched<PublicPlaylist[]>> {
	return fetchSiteJson(host, "/api/v1/recorded/public/playlists/", isList);
}

export function getRecorded(host: string, slug: string): Promise<Fetched<PublicPlaylist>> {
	if (!RECORDED_SLUG_RE.test(slug)) return Promise.resolve({ kind: "notfound" });
	return fetchSiteJson(host, `/api/v1/recorded/public/playlists/${slug}/`, isPublicPlaylist);
}

const TTL = 60_000;
const MAX = 1000;
const flags = new Map<string, { expires: number; value: boolean }>();

export function clearRecordedCache(): void {
	flags.clear();
}

/** Whether the header shows "Recorded courses": a non-empty list. */
export async function hasRecordedCourses(rawHost: string | undefined): Promise<boolean> {
	if (!rawHost) return false;
	const host = normalizeHost(rawHost);
	if (!isValidHost(host)) return false;
	const hit = flags.get(host);
	if (hit && hit.expires > Date.now()) return hit.value;
	let value = false;
	try {
		const { status, body } = await getJson("/api/v1/recorded/public/playlists/", host);
		value = status === 200 && Array.isArray(body) && body.length > 0;
	} catch {
		return false; // transient: never cached
	}
	if (flags.size >= MAX && !flags.has(host)) {
		const oldest = flags.keys().next().value;
		if (oldest !== undefined) flags.delete(oldest);
	}
	flags.set(host, { expires: Date.now() + TTL, value });
	return value;
}

export function priceText(minor: number, currency: string, lang: string): string {
	const fmt = new Intl.NumberFormat(lang, { style: "currency", currency });
	const digits = fmt.resolvedOptions().maximumFractionDigits ?? 2;
	return fmt.format(minor / 10 ** digits);
}

/** A thumbnail or intro URL the page may render (D2), absolute; else "". */
export function safeMedia(site: SitePayload, url: string): string {
	return url && isUpload(url) ? absoluteUrl(site, url) : "";
}

export function durationText(seconds: number): string {
	const pad = (n: number) => String(n).padStart(2, "0");
	return `${pad(Math.floor(seconds / 3600))}:${pad(Math.floor((seconds % 3600) / 60))}:${pad(seconds % 60)}`;
}
```

(`getJson`'s exact return type is in `src/lib/http.ts:18`. Destructure the same `{ status, body }` that `resolveSite` uses.)

`src/pages/[lang]/recorded-courses/index.astro`:

```astro
---
import Footer from "../../../components/Footer.astro";
import Header from "../../../components/Header.astro";
import PageNotFound from "../../../components/PageNotFound.astro";
import StatusPage from "../../../components/StatusPage.astro";
import Layout from "../../../layouts/Layout.astro";
import { isLang, pick, preferredLang, ui } from "../../../lib/i18n";
import { durationText, getRecordedList, priceText, safeMedia } from "../../../lib/recorded";

// B7b S-10: the public catalogue; 404 (feature off or nothing for sale)
// renders the academy 404, like the B8 video pages.
const result = Astro.locals.siteResult;
const lang = Astro.params.lang;
const site = result.kind === "ok" ? result.site : null;
const fetched = site && isLang(lang) ? await getRecordedList(Astro.locals.host) : null;
const list = fetched?.kind === "ok" && fetched.data.length > 0 ? fetched.data : null;
const path = "/recorded-courses";
---
{!site ? (
	<StatusPage kind={result.kind === "ok" ? "notfound" : result.kind} />
) : !isLang(lang) ? (
	<PageNotFound site={site} lang={preferredLang(Astro.request.headers.get("accept-language"))} path="/" />
) : fetched?.kind === "unavailable" ? (
	<StatusPage kind="unavailable" />
) : !list ? (
	<PageNotFound site={site} lang={lang} path={path} />
) : (
	<Layout site={site} lang={lang} title={ui(lang).recordedCourses} description={pick(site.branding.name, lang)} path={path}>
		<Header site={site} lang={lang} path={path} />
		<main class="mx-auto max-w-5xl p-6">
			<h1 class="text-2xl font-semibold">{ui(lang).recordedCourses}</h1>
			<div class="mt-6 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
				{list.map((p) => (
					<article class="flex flex-col gap-2 rounded-lg border border-border p-4">
						<a href={`/${lang}/recorded-courses/${p.slug}`} class="flex flex-col gap-2 font-medium">
							{safeMedia(site, p.thumbnail_url) && (
								<img src={safeMedia(site, p.thumbnail_url)} alt="" class="aspect-video w-full rounded object-cover" loading="lazy" />
							)}
							<span>{p.title}</span>
						</a>
						<p class="text-sm">{p.description}</p>
						<p class="text-sm text-muted-foreground">
							{ui(lang).lessonsCount.replace("{n}", String(p.lessons))} · {durationText(p.seconds)}
						</p>
						<p class="font-medium">
							{p.net_minor === 0 ? ui(lang).free : priceText(p.net_minor, p.currency, lang)}
							{p.discount_minor > 0 && <s class="ms-2 text-sm text-muted-foreground">{priceText(p.price_minor, p.currency, lang)}</s>}
						</p>
					</article>
				))}
			</div>
		</main>
		<Footer site={site} lang={lang} />
	</Layout>
)}
```

`src/pages/[lang]/recorded-courses/[slug].astro`:

```astro
---
import Footer from "../../../components/Footer.astro";
import Header from "../../../components/Header.astro";
import PageNotFound from "../../../components/PageNotFound.astro";
import StatusPage from "../../../components/StatusPage.astro";
import Layout from "../../../layouts/Layout.astro";
import { isLang, preferredLang, ui } from "../../../lib/i18n";
import { durationText, getRecorded, priceText, safeMedia } from "../../../lib/recorded";

const result = Astro.locals.siteResult;
const lang = Astro.params.lang;
const slug = Astro.params.slug ?? "";
const site = result.kind === "ok" ? result.site : null;
const fetched = site && isLang(lang) ? await getRecorded(Astro.locals.host, slug) : null;
const p = fetched?.kind === "ok" ? fetched.data : null;
const path = `/recorded-courses/${slug}`;
const intro = site && p ? safeMedia(site, p.intro_video_url) : "";
const thumb = site && p ? safeMedia(site, p.thumbnail_url) : "";
---
{!site ? (
	<StatusPage kind={result.kind === "ok" ? "notfound" : result.kind} />
) : !isLang(lang) ? (
	<PageNotFound site={site} lang={preferredLang(Astro.request.headers.get("accept-language"))} path="/" />
) : fetched?.kind === "unavailable" ? (
	<StatusPage kind="unavailable" />
) : !p ? (
	<PageNotFound site={site} lang={lang} path="/recorded-courses" />
) : (
	<Layout site={site} lang={lang} title={p.title} description={p.description.slice(0, 160)} path={path}>
		<Header site={site} lang={lang} path={path} />
		<main class="mx-auto grid max-w-5xl gap-6 p-6 lg:grid-cols-3">
			<section class="flex flex-col gap-4 lg:col-span-2">
				<h1 class="text-2xl font-semibold">{p.title}</h1>
				{intro ? (
					<video controls preload="metadata" src={intro} poster={thumb || undefined} class="aspect-video w-full rounded"></video>
				) : thumb ? (
					<img src={thumb} alt="" class="aspect-video w-full rounded object-cover" />
				) : null}
				<p class="whitespace-pre-line">{p.description}</p>
				{p.content && <p class="whitespace-pre-line text-sm">{p.content}</p>}
				<h2 class="font-medium">{ui(lang).courseOutline}</h2>
				<ol class="flex flex-col gap-1 text-sm">
					{p.outline.map((o) => (
						<li class="flex justify-between gap-2"><span>{o.title}</span><span>{durationText(o.duration_seconds)}</span></li>
					))}
				</ol>
			</section>
			<aside class="flex flex-col gap-3 rounded-lg border border-border p-4">
				<p class="text-lg font-medium">{p.net_minor === 0 ? ui(lang).free : priceText(p.net_minor, p.currency, lang)}</p>
				<p class="text-sm">{ui(lang).lessonsCount.replace("{n}", String(p.lessons))} · {durationText(p.seconds)}</p>
				<a href={`/app/learning/recorded/store/${p.id}`} class="rounded-md bg-primary px-3 py-2 text-center text-primary-foreground">
					{p.net_minor === 0 ? ui(lang).enrolCourse : ui(lang).buyCourse}
				</a>
				<p class="text-xs text-muted-foreground">{ui(lang).signInToBuy}</p>
				<h2 class="font-medium">{ui(lang).courseTerms}</h2>
				<p class="max-h-48 overflow-y-auto whitespace-pre-line text-sm">{p.terms}</p>
			</aside>
		</main>
		<Footer site={site} lang={lang} />
	</Layout>
)}
```

The `ui(lang).*` keys used here are added in Task 14. Until then `astro check`/tsc fails, so run Task 14's Step 1 (i18n) before running these tests, and commit Tasks 13 and 14 in the order given.

- [ ] **Step 4: Run** after Task 14 Step 1: `M pnpm vitest run test/recorded.test.ts && M pnpm astro check`
Expected: PASS.
- [ ] **Step 5: Commit** (after Task 14 Step 1's commit)

```bash
git -C marketing add src/lib/recorded.ts "src/pages/[lang]/recorded-courses" test/recorded.test.ts
git -C marketing commit -m "feat(marketing): B7b public recorded-course pages" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Marketing strings, header link and sitemap (shared files under one claim)

**Files:**
- Modify: `marketing/src/lib/i18n.ts`, `marketing/src/components/Header.astro`, `marketing/src/pages/sitemap.xml.ts`
- Test: `marketing/test/recorded.test.ts` (append)

- [ ] **Step 1: Claim, then add the strings**

```bash
python3 scripts/orchestration/ledger.py claim B7 marketing/src/lib/i18n.ts --reason "B7b S-10: recorded-course strings, header link, sitemap (one commit: i18n.ts, Header.astro, sitemap.xml.ts)"
```

In `src/lib/i18n.ts`, add to the `ar` table:

```ts
		recordedCourses: "الدورات المسجلة",
		courseOutline: "محتوى الدورة",
		courseTerms: "الشروط والأحكام",
		lessonsCount: "{n} درس",
		free: "مجانية",
		buyCourse: "اشترِ الدورة",
		enrolCourse: "اشترك مجانًا",
		signInToBuy: "سجّل الدخول، ثم افتح «الدورات المسجلة».",
```

and to the `en` table:

```ts
		recordedCourses: "Recorded courses",
		courseOutline: "Course outline",
		courseTerms: "Terms and conditions",
		lessonsCount: "{n} lessons",
		free: "Free",
		buyCourse: "Buy this course",
		enrolCourse: "Enrol for free",
		signInToBuy: "Sign in, then open Recorded courses.",
```

(If the `ui` tables are typed by one shared key type, both tables need every key. The type check enforces this.)

- [ ] **Step 2: Write the failing header and sitemap tests** (append to `test/recorded.test.ts`)

```ts
import Header from "../src/components/Header.astro";
import { GET as sitemap } from "../src/pages/sitemap.xml";

describe("header and sitemap", () => {
	it("shows the Recorded courses link only when courses exist", async () => {
		const spy = vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: [playlist()] });
		const c = await AstroContainer.create();
		const on = await c.renderToString(Header, { props: { site: demoSite, lang: "en", path: "/" }, locals });
		expect(on).toContain('href="/en/recorded-courses"');
		recorded.clearRecordedCache();
		spy.mockResolvedValue({ status: 200, body: [] });
		const off = await c.renderToString(Header, { props: { site: demoSite, lang: "en", path: "/" }, locals });
		expect(off).not.toContain("/en/recorded-courses");
	});

	it("lists the courses in the sitemap when there are some", async () => {
		vi.spyOn(http, "getJson").mockImplementation(async (path: string) =>
			path.startsWith("/api/v1/recorded/")
				? { status: 200, body: [playlist()] }
				: { status: 404, body: null },
		);
		const resp = await sitemap({ locals } as never);
		const xml = await resp.text();
		expect(xml).toContain("/en/recorded-courses/tajweed");
		expect(xml).toContain("/ar/recorded-courses");
	});
});
```

Run `M pnpm vitest run test/recorded.test.ts`. Expected: FAIL (no link, no sitemap entry).

- [ ] **Step 3: Implement the header and sitemap**

`Header.astro`. In the frontmatter, add:

```ts
import { hasRecordedCourses } from "../lib/recorded";
const showRecorded = await hasRecordedCourses(Astro.locals?.host);
```

and in the nav, after the videos link:

```astro
			{showRecorded && <a href={`/${lang}/recorded-courses`}>{t.recordedCourses}</a>}
```

`sitemap.xml.ts`. After the videos block, before the paths are joined:

```ts
	// B7b S-10: recorded courses, when the academy sells any. A 404 (feature
	// off) leaves them out; trouble answers 503, like articles.
	const courses = await getRecordedList(locals.host);
	if (courses.kind === "unavailable") {
		return new Response("Unavailable", { status: 503 });
	}
	const coursePaths: { path: string }[] =
		courses.kind === "ok" && courses.data.length > 0
			? [
					{ path: "/recorded-courses" },
					...courses.data.map((c) => ({ path: `/recorded-courses/${c.slug}` })),
				]
			: [];
```

Then add `...coursePaths` to the same list the video paths go into, so that it is emitted for each language the same way. Import `getRecordedList` from `../lib/recorded`.

Run `M pnpm vitest run && M pnpm astro check && M pnpm lint`. Expected: PASS. The existing tests either pass no `locals.host` to the Header (flag false, no fetch) or mock `getJson`, which a 404 answers.

- [ ] **Step 4: Commit and release**

Commit:

```bash
git -C marketing add src/lib/i18n.ts src/components/Header.astro src/pages/sitemap.xml.ts test/recorded.test.ts
git -C marketing commit -m "feat(marketing): recorded-courses header link, strings and sitemap (B7b S-10)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Release the claim:

```bash
python3 scripts/orchestration/ledger.py release B7 marketing/src/lib/i18n.ts
```

Then commit Task 13's files (Task 13, Step 5).

---

### Task 15: e2e journey

**Files:**
- Create: `dashboard/e2e/b7-recorded-store.spec.ts`

**Interfaces:**
- Consumes:
  - `e2e/fixtures.ts`: `DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD`, `expectLoggedIn`, `acceptInvite`, `postAsAdmin`;
  - `e2e/manage.ts`;
  - the seeded `TAJWEED-1` (plan 49 Task 10: net 1 500 USD, published, not app-only);
  - the demo academy's simulated Stripe account (`seed_gateways`).
- The test uses a fresh student created in its own setup, who is not enrolled. This replaces the spec's "revoke the seeded enrolment": same journey, no shared-state edit.

- [ ] **Step 1: Write the spec**

```ts
import { type Browser, expect, type Locator, type Page, test } from "@playwright/test";
import { acceptInvite, DEMO_ADMIN, DEMO_URL, DEV_PASSWORD, expectLoggedIn, postAsAdmin } from "./fixtures";
import { manage } from "./manage";

// Plan 51 (B7b): a student buys a recorded course through the gateways
// simulator and opens it. Stamped names, so a second run works too.

const PASSWORD = "e2e-Student-B7b";

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

test("a student buys a recorded course through the simulator and opens it", async ({ page, browser }) => {
	test.setTimeout(240_000);
	manage("set_features", "demo", "--on", "recorded_courses", "invoices", "online_payments");
	const stamp = Date.now();
	const student = `B7b Buyer ${stamp}`;
	const email = `b7b-${stamp}@demo.test`;

	await visit(page, `${DEMO_URL}/app/login`, page.getByRole("textbox", { name: /email/i }));
	await page.getByRole("textbox", { name: /email/i }).fill(DEMO_ADMIN);
	await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, /demo academy admin/i);
	const made = await postAsAdmin(page, "people/students/", { user: { full_name: student, email }, profile: {} });
	expect(made.status(), await made.text()).toBe(201);
	const found = await page.request.get(`${DEMO_URL}/api/v1/recorded/playlists/?q=TAJWEED-1`);
	const [course] = (await found.json()) as { id: number; title: string }[];

	const learner = await signInStudent(browser, email, student);
	await learner.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await visit(learner, `${DEMO_URL}/app/learning/recorded/store`, learner.getByText(course.title));
	await learner.getByText(course.title).click();
	await learner.getByLabel("I accept the terms and conditions").check();
	await learner.getByRole("button", { name: "Buy with Stripe" }).click();
	const sheet = learner.getByRole("dialog");
	await expect(sheet.getByText(/15\.00/)).toBeVisible();
	await sheet.getByRole("button", { name: "Continue to Stripe" }).click();
	await expect(learner).toHaveURL(/\/app\/pay\/simulate\//);
	await learner.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(learner).toHaveURL(/\/app\/pay\/return\?checkout=/);
	await expect(learner.getByText("Paid — thank you.")).toBeVisible();
	await learner.getByRole("link", { name: "Open my recorded courses" }).click();
	await expect(learner.getByRole("link", { name: new RegExp(course.title) })).toBeVisible();
});
```

- [ ] **Step 2: Run** `just e2e e2e/b7-recorded-store.spec.ts` on the stream stack once it is up (`just dev-backend`, `just seed`).
Expected: PASS.
- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b7-recorded-store.spec.ts
git -C dashboard commit -m "test(recorded): B7b store e2e journey" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: Gates, final review and queue

These run only once the phase holds a slot and B7a is merged. No step was run when this plan was written.

- [ ] **Step 1:** `just test` (backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70; marketing tests) and `just lint` (ruff, biome, `lint-imports`, gitleaks, `astro check`). Both must pass.
- [ ] **Step 2:** `just seed`, then `just e2e`: the whole suite, because `b3-online-payments`, `b3-paypal` and the new store spec share the simulator. It must pass.
- [ ] **Step 3:** Dispatch a fresh whole-slice reviewer against the spec (S-1…S-12, §3–§6) and this plan's Review Focus. Fix every critical or important finding. Log minor ones in `../_ledger/orchestration/phases/B7.md`.
- [ ] **Step 4:** In the meta worktree, commit the submodule pointers on `feat/b7b-recorded-store` with `git add backend dashboard marketing`, never `-a`. Then run `python3 scripts/orchestration/ledger.py queue B7b` and follow the merge-queue steps:
  - rebase every touched repo onto its trunk;
  - regenerate `routeTree.gen.ts`;
  - regenerate `0002_purchase.py` if B7a's migrations moved (§6.2);
  - rerun the gates;
  - push, open the four PRs, and record them with `slice B7b --prs "<urls>"`.
