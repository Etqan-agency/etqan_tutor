# Plan 60 — B7d Consultation Booking Online — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A visitor on the public site, or a signed-in student or parent, books a consultation: they pick a product, a teacher and one of that teacher's free slots, give their contact details and pay with Stripe or PayPal. The request then waits for the office to confirm it. The booker follows it on a manage page, reached by an unguessable link. There they pay again while unpaid, ask to reschedule, and rate the consultation once it is complete.

**Architecture:** The B7c app `etqan.consultations` gains:
- B7d's columns on `Request` and a new `Review` table (one migration);
- a "live" rule that frees an unpaid self-booking's place once its 30-minute hold runs out;
- booking services (`booking.py`, `paying.py`, `manage.py`, `reviews.py`, `unpaid.py`, `notices.py`);
- the public gateways purpose `consultation` (`purpose.py`), registered in `ConsultationsConfig.ready()`;
- anonymous routes (`public/…`), family routes (`my/…`), office review routes (`reviews/…`);
- a Celery job that cancels unpaid holds.

Money reaches billing only through `billing.services.record_link_payment`, and gateways only through `gateways.services`. The dashboard gains a public booking wizard (`/app/consult/$productId`), a public manage page (`/app/consult/manage/$token`), the family pages under `/learning/consultations…`, an office reviews tab, a consultation branch on the gateways return page, and four attention codes. The Astro marketing site gains `/{lang}/consultations[/{id}]`, a header link and sitemap entries.

**Tech Stack:** Django 5 + DRF + django-tenants + Celery + pytest; React + TanStack Router/Query + Vitest + RTL; Astro + Vitest (AstroContainer); Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7d-consultation-booking-design.md` (K-1…K-16, §3–§6) is binding. Phase decisions come from `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md`: B7-3, B7-4, B7-10, §4. Ledger decisions: D13, D17, D19, D28, D30, D50, D51, D53, D65. Read the spec and those decisions before any task.

**Requires:** B7c, B7b (both merged first).
B7c is plan 50 (`docs/superpowers/plans/2026-10-08-plan-50-consultations-office.md`, branch `feat/b7c-consultations-office`). B7b is plan 51: this plan reuses its `etqan.platform.throttling.PublicScopedRateThrottle` (D65), its `e2e/b7-helpers.ts`, its marketing `src/lib/recorded.ts` helpers (`priceText`, `safeMedia`) and its `ReturnPage.tsx` branch, and inserts next to them. From other phases, merged work only: B3b, B3c and B3g (`gateways.services.start_checkout(..., user=None, params=...)` for public purposes, `billing.services.record_link_payment`), B2e (`scheduling.services.windows_of`, teacher availability) and B9c (`identity.services.send_notice`).

**Written in spec-only mode** (ledger D45, 2026-10-09). No stack existed when this plan was written, so no command below has been run. Build only after B7c (and B7b) have merged and the conductor has given B7 a slot.

## Global Constraints

- Branches. Create `feat/b7d-consultation-booking` in the meta worktree, `backend/`, `dashboard/` and `marketing/`:
  - each submodule: `git fetch origin && git switch -c feat/b7d-consultation-booking origin/main`;
  - meta: `git fetch origin && git switch -c feat/b7d-consultation-booking origin/master`.
  - Never run `git submodule update` or any `git submodule` command that writes.
- Command prefixes, after `set -a; . ./.env.stream; set +a` in the meta worktree:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>`
  - `F <cmd>` = the same with the `dashboard` service
  - `M <cmd>` = the same with the `marketing` service
  - Whole suites: `just test`, `just lint`, `just e2e …`, `just migrate`.
- Lint on every commit (B7a PF13, B7b PF4). Before each backend commit run `B ruff format <files>` and `B ruff check <files>`; before each dashboard or marketing commit run `F pnpm biome check --write <files>` / `M pnpm biome check --write <files>`. Imports sit only at the top of a module (no import inside a test or fixture).
- Reuse B7c's names exactly: `etqan/consultations/services/` (a package whose `__init__.py` re-exports and keeps `__all__` sorted), `common.now()`, `common.academy_zone()`, `common.lock_teacher(profile_id)`, `requests_queryset()`, `get_request`, `free_slots`, `check_capacity`, `products_queryset()`, `opted_in_ids()`; the test helpers `people`, `booking`, `new_request`, `product_row`, `MONDAY_4PM` in `tests/conftest.py`; dashboard `src/features/consultations/` (`schemas.ts`, `api.ts`, `queries.ts`, `errors.ts`, `fixtures.ts`, `index.ts`) and `locales/{en,ar}/consultations.json`.
- Imports. `etqan.consultations` imports only `etqan.platform`, and the `services` modules of `identity`, `academy`, `billing`, `scheduling` and `gateways`. The `gateways.services` whitelist is added to the consultations contract in the first commit that imports it (Task 5), as B7b PF1 ruled.
- Ids. People are addressed by **user id** in the API and the services. `Request.student_id` and `record_link_payment(student_id=…)` are the **StudentProfile pk**. `Request.teacher_id` and `lock_teacher(…)` are the **TeacherProfile pk**.
- Money is integer minor units plus a 3-letter currency, never summed across currencies. Revenue is amount + fee (D16). `Request.amount_minor` stores the amount without the fee; `fee_minor` the fee.
- Times. Stored instants are UTC. Slot windows and "today" are on the academy's clock (`common.academy_zone()`). The booker's own timezone is only for display and the email.
- Locks (one order everywhere): booker advisory lock → teacher advisory lock → `Request` row (`select_for_update`). `complete` runs under gateways' checkout row lock, then teacher lock → row. The unpaid job takes only the row lock and never an advisory lock after it. Lock-order tests read captured SQL; **no** `transaction=True` or threaded test (B7a ruling, B7b PF11).
- Public routes: `authentication_classes = []`, `permission_classes = [AllowAny, FeatureOn]`, `throttle_classes = [PublicScopedRateThrottle]` (D65; the header is honoured only under `settings.TRUST_INTERNAL_HEADER`). Views that start a checkout set `atomic_request = False` and their URL is wrapped in `transaction.non_atomic_requests`.
- `prepare` never reads request data: the token comes from the row (book, `my/…/pay`) or from the URL (`public/manage/<token>/pay`), never from a body or query (D28).
- Plain text only (D2). Reviews, notes, names and descriptions are rendered escaped, with line breaks.
- Migrations only create tables or add columns on B7's own tables (B7-14).
- Strings: en and ar only, key-equal (D22), in `consultations.json`; the gateways and marketing strings stay key-equal too.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Stage explicit paths only; never `git commit -a` (meta especially: it would capture submodule pointers).

## Shared files and claims

Every file outside B7's own folders changes in **one commit per task** under a ledger claim on that exact path, released right after that commit (claims are per path, B7b PF24). Run from the meta worktree:

```bash
python3 scripts/orchestration/ledger.py claim B7 <path> --reason "<why>"
# … edit, run the named tests, commit …
python3 scripts/orchestration/ledger.py release B7 <path>
```

| Path | What changes | Task |
|---|---|---|
| `backend/pyproject.toml` | the consultations contract's `gateways.services` whitelist (B7 block) and `"etqan.consultations"` in "gateways imports no business app" (D53), one commit | 5 |
| `backend/config/settings/base.py` | `CELERY_BEAT_SCHEDULE` entry `consultations.cancel_unpaid` (K-7) | 8 |
| `backend/config/settings/base.py` | `DEFAULT_THROTTLE_RATES`: `consultation_book`, `consultation_manage`, `consultation_public` (K-8) | 10 |
| `backend/etqan/access/registry.py` | resource `consultation_review` under `── phase B7 ──` (K-16) | 13 |
| `backend/etqan/access/tests/test_routes.py` | B7d `SELF_SERVICE` lines for the views each task adds (10, 11, 12), then `ROUTES` and `FEATURES` for reviews (13); one commit and claim per task | 10, 11, 12, 13 |
| `dashboard/src/features/shell/nav.ts` | `/learning/consultations` under `── phase B7 ──` | 15 |
| `dashboard/src/features/shell/nav.test.ts` | the new item in the path list, feature map and family list | 15 |
| `dashboard/src/routes/permissions.test.ts` | `FEATURE_SCREENS` lines: two in Task 15, one in Task 16 (one commit and claim each) | 15, 16 |
| `dashboard/src/features/gateways/schemas.ts` | four `ATTENTION_CODES` (K-6) | 18 |
| `dashboard/src/locales/en/gateways.json` | four `attention.*` strings | 18 |
| `dashboard/src/locales/ar/gateways.json` | four `attention.*` strings | 18 |
| `dashboard/src/features/gateways/ReturnPage.tsx` | the consultation branch (K-15) | 18 |
| `dashboard/src/features/gateways/ReturnPage.test.tsx` | its tests | 18 |
| `marketing/src/lib/i18n.ts` | the consultation strings | 20 |
| `marketing/src/components/Header.astro` | the "Consultations" link | 20 |
| `marketing/src/pages/sitemap.xml.ts` | the consultation URLs | 20 |
| any `marketing/test/*.test.ts` that Task 20's new fetch breaks | scope its assertion to its own path, as B7b PF25 did | 20 |

Not claimed: `dashboard/src/routeTree.gen.ts` is generated by `F pnpm build`, never edited by hand, and is regenerated at queue time by the merge-queue rebase (B7b precedent). Everything else this plan touches lives in B7-owned folders: `backend/etqan/consultations/`, `dashboard/src/features/consultations/`, `dashboard/src/locales/{en,ar}/consultations.json`, new dashboard route files, `dashboard/e2e/b7-*.ts`, `marketing/src/lib/consultations.ts`, `marketing/src/pages/[lang]/consultations/`, `marketing/test/consultations.test.ts`.

## Decisions this plan takes where the spec is silent

Each is `[assumed]`; the plan's tests pin it.

1. **Email language column.** K-9 sends the manage link "with `language=<page language>`" from `complete`, long after the booking request. §3 has no column for it, so `Request` gains `language` (`"en"`|`"ar"`, default `"en"`), set from the booking body.
2. **`not_bookable` in `complete`.** K-6 lists four new attention codes, including `not_bookable`, but does not say when `complete` returns it. Following B7-4 ("product off: records nothing"), `complete` returns `not_bookable` when the product is archived or disabled, checked after `request_cancelled` and before `currency_mismatch`.
3. **A teacher changed twice during `complete`.** K-6 retries once. If the teacher changed again, `complete` raises `ConflictError(code="consultations.request_changed")`: the provider event fails and the provider retries it later. Nothing is recorded.
4. **A start that is not one of the offered slots** when booking (a junk time, a full slot or a slot taken by an overlap) answers 409 `consultations.slot_full`, the one capacity refusal K-3 names.
5. **The slot horizon** is inclusive: days from the academy's today to today + min(`validity_days`, 31).
6. **Re-hold on Pay** (K-10) also refuses a start less than 12 hours ahead (`slot_taken`), as booking would. `prepare` and `complete` check capacity only (K-5 (4), K-6: "full").
7. **The unpaid job** cancels only `pending_review` rows. A request the office already confirmed while unpaid is the office's to cancel.
8. **The manage routes** need only `consultations`. Its Pay action also needs `online_payments`. The catalogue, slots and booking routes need both (K-1).
9. **Signed-in contact fallback.** On `my/book`, a blank name, email, WhatsApp or timezone falls back to the signed-in user's own (the booker's), not the child's.
10. **A parent who names no child** books with no student, as themself.
11. **The family list** hides requests the unpaid job cancelled, as the office list does by default.
12. **Public review attribution.** K-12 says "Visitor" or "Student" with no name; §5's line "public reviews carrying the first name only" is read as K-12 says (no name), the stricter of the two.
13. **The return page hint** (K-15 "use the link we emailed you") shows only on an anonymous read (no `purpose` in the payload), with no remembered link, once the checkout is completed. It is worded so that a payment-link payer can ignore it.
14. **"Offered the signed-in wizard"** (K-14) is a link on the public wizard to `/app/learning/consultations/book?product=<id>`. The public page makes no `me` call.
15. **Provider start failure on booking** answers 201 with `checkout: null`. The wizard then links to the manage page, where Pay works while the hold lasts (K-3).

## Review Focus

1. **Two bookers racing for the last place.** Expected: one gets the request, the other 409 `consultations.slot_full`; a held but unpaid place counts until its hold ends. Pinned in Task 4 (`test_a_full_slot_is_refused`, `test_booker_lock_then_teacher_lock_then_count`) and Task 1 (`test_an_unexpired_hold_takes_a_place`).
2. **A payment that arrives late, after the hold, when someone else took the place.** Expected: `slot_taken` attention, no billing row; with room left it is still taken and recorded. Pinned in Task 6 (`test_late_payment_for_a_taken_place_is_slot_taken`, `test_late_payment_with_room_is_recorded`) and Task 7 (`test_paypal_recheck_refuses_once_the_place_is_taken`).
3. **The manage link leaking or being guessed.** Expected: a malformed token never reaches the database; another token is a 404; the payload never carries email, WhatsApp, name or notes; the page sends no referrer. Pinned in Task 9 (`test_a_malformed_token_makes_no_query`), Task 11 (`test_manage_payload_has_no_contact_details`) and Task 16 (`ManagePage` "sends no referrer").
4. **The same provider event delivered twice, or two checkouts of one booking both paid.** Expected: one billing record; the second is `already_recorded` or `request_paid`, never a 500. Pinned in Task 6 (`test_second_checkout_is_request_paid`) and Task 7 (`test_a_redelivered_event_records_once`).
5. **A booker flooding the form, or a quick-login admin paying as a student.** Expected: the fourth unpaid booking per email or IP is 409 `consultations.too_many_pending`; the 11th booking in an hour from one IP is 429; a quick-login session gets 403 on every `my/` write. Pinned in Task 4 (`test_three_unpaid_per_email_then_409`, `test_three_unpaid_per_ip_then_409`), Task 11 (`test_book_is_throttled_per_ip`) and Task 12 (`test_writes_refuse_a_quick_login_session`).

---

## File Structure

```text
backend/etqan/consultations/
  models.py                          Request (+ §3 columns, language, CancelReason); Review
  migrations/0002_booking.py         (generated)
  apps.py                            ready(): purpose.register()
  tasks.py                           consultations.cancel_unpaid (every 15 min, every academy)
  services/
    common.py                        + HOLD, LEAD, TOKEN_RE, live_q, expired_hold_q, hold_expired, lock_booker
    slots.py                         live_q in counts; room_left; free_slots(not_before=, last_date=)
    requests.py                      clean_contact/clean_notes/default_link made public; filter_requests(self_booked=)
    transitions.py                   cancel_reason "office"; reschedule/decline clear proposed_starts_at
    reads.py                         ConsultationEvent/ConsultationStart gain self_booked
    booking.py                       K-1, K-2, K-3, K-8: what is bookable, slots, book(), manage_url()
    purpose.py                       K-5, K-6: NAME, prepare, complete, register
    notices.py                       K-9: the manage-link email
    paying.py                        K-4, K-10: require_provider, providers_for_request, rehold, start_payment
    unpaid.py                        K-7: cancel_unpaid (one academy)
    manage.py                        K-10…K-13: by_token, family_requests, actions, ask_reschedule, leave_review
    reviews.py                       K-12: moderation, review_summary, ratings_by_product
    __init__.py                      re-exports
  api/
    params.py                        client_ip(request)
    booking_serializers.py           inputs and payloads of B7d's routes
    answers.py                       manage_answer, family_answer, book_answer
    public_views.py                  public/products…, public/book, public/manage/<token>…
    my_views.py                      my/, my/book/, my/<id>/…
    review_views.py                  reviews/, reviews/<id>/
    request_views.py                 list gains ?self_booked=
    serializers.py                   request_data gains B7d fields
    urls.py                          + routes
  tests/
    conftest.py                      + _clear_cache, frozen, online, stripe_on, paypal_on, book_one, SUNDAY_NOON
    test_live.py test_office_self_booked.py test_booking_reads.py test_book.py
    test_purpose_prepare.py test_purpose_complete.py test_paying.py test_unpaid.py
    test_manage.py test_reviews.py test_api_public.py test_api_manage.py test_api_my.py test_api_reviews.py
Modified (claims): backend/pyproject.toml (gateways contract), backend/config/settings/base.py (×2),
  backend/etqan/access/registry.py, backend/etqan/access/tests/test_routes.py

dashboard/src/features/consultations/
  schemas.ts api.ts queries.ts errors.ts fixtures.ts index.ts   (+ booking types; `given` exported)
  bookingApi.ts bookingQueries.ts manageLink.ts manageLink.test.ts
  BookingWizard.tsx BookingWizard.test.tsx BookingSlots.tsx
  ManagePage.tsx ManagePage.test.tsx
  FamilyConsultations.tsx FamilyConsultations.test.tsx BookPicker.tsx
  ReviewsAdmin.tsx ReviewsAdmin.test.tsx
  RequestsAdmin.tsx RequestsAdmin.test.tsx RequestsTabs.tsx RequestsTabs.test.tsx
dashboard/src/routes/consult.$productId.tsx                 (public)
dashboard/src/routes/consult.manage.$token.tsx              (public)
dashboard/src/routes/consult.test.ts
dashboard/src/routes/_authed/learning.consultations.index.tsx
dashboard/src/routes/_authed/learning.consultations.book.tsx
dashboard/src/routes/_authed/learning.consultations.$requestId.tsx
dashboard/src/routes/_authed/scheduling.consultations.tsx  (view=reviews)
dashboard/src/locales/{en,ar}/consultations.json
Modified (claims): shell/nav.ts, shell/nav.test.ts, routes/permissions.test.ts,
  gateways/ReturnPage.tsx (+ test), gateways/schemas.ts, locales/{en,ar}/gateways.json
dashboard/e2e/b7-helpers.ts (+ patchAsAdmin)   dashboard/e2e/b7-consultation-booking.spec.ts

marketing/src/lib/consultations.ts
marketing/src/pages/[lang]/consultations/index.astro
marketing/src/pages/[lang]/consultations/[id].astro
marketing/test/consultations.test.ts
Modified (claims): marketing/src/lib/i18n.ts, marketing/src/components/Header.astro,
  marketing/src/pages/sitemap.xml.ts
```

---

### Task 1: B7d's columns, the review table and the live rule (§3, K-7, C-5)

**Files:**
- Modify: `backend/etqan/consultations/models.py`, `backend/etqan/consultations/services/common.py`, `backend/etqan/consultations/services/slots.py`, `backend/etqan/consultations/services/transitions.py`, `backend/etqan/consultations/services/__init__.py`
- Generate: `backend/etqan/consultations/migrations/0002_booking.py`
- Test: `backend/etqan/consultations/tests/test_live.py` (new)

**Interfaces:**
- Consumes: B7c's `Request`, `Product`, `LIVE`, `lock_teacher`, `free_slots`, `check_capacity`, `cancel`.
- Produces:
  - `Request` columns `self_booked`, `manage_token`, `hold_until`, `proposed_starts_at`, `cancel_reason` (`Request.CancelReason.NONE|UNPAID|OFFICE`), `booked_ip_hash`, `language`, `price_minor`, `price_currency`, `price_fee_enabled`;
  - `Review(request, rating, comment, status, reason, created_at, decided_by, decided_at)` with `Review.Status.PENDING|APPROVED|REJECTED`, `related_name="review"`;
  - `common.HOLD = timedelta(minutes=30)`, `common.LEAD = timedelta(hours=12)`, `common.TOKEN_RE` (43 url-safe characters, use with `fullmatch`);
  - `common.expired_hold_q(at) -> Q`, `common.live_q(at=None) -> Q`, `common.hold_expired(row) -> bool`, `common.lock_booker(ip_digest: str) -> None`;
  - `room_left(product, profile_id, starts_at, *, exclude_id=None) -> int` (exported from `services`);
  - `free_slots(product, teacher_user_id, start_date, days, *, request=None, not_before=None, last_date=None) -> SlotList`;
  - `cancel(row, *, by)` now also sets `cancel_reason="office"`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_live.py`:

```python
from datetime import timedelta

import pytest
from django.db import IntegrityError
from django.db import connection
from django.db import transaction
from django.test.utils import CaptureQueriesContext

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.models import Review
from etqan.consultations.services import common
from etqan.consultations.slot_math import Slot
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request
from etqan.platform.exceptions import ConflictError

pytestmark = pytest.mark.django_db
NOW = MONDAY_4PM - timedelta(days=1)
HALF = timedelta(minutes=30)


@pytest.fixture
def pinned(monkeypatch):
    monkeypatch.setattr(common, "now", lambda: NOW)


def held(b, *, until, paid_method="", status="pending_review", self_booked=True):
    return Request.objects.create(
        product=b.product,
        teacher=b.teacher_profile,
        name="n",
        email="n@x.test",
        whatsapp="1",
        timezone="UTC",
        status=status,
        starts_at=MONDAY_4PM,
        ends_at=MONDAY_4PM + HALF,
        self_booked=self_booked,
        hold_until=until,
        paid_method=paid_method,
    )


def test_new_columns_default_for_an_office_request(booking):
    row = new_request(booking)
    assert (
        row.self_booked,
        row.manage_token,
        row.hold_until,
        row.proposed_starts_at,
        row.cancel_reason,
        row.booked_ip_hash,
        row.language,
        row.price_minor,
        row.price_currency,
        row.price_fee_enabled,
    ) == (False, None, None, None, "", "", "en", None, "", None)


def test_manage_token_is_unique_but_may_be_null(booking):
    held(booking, until=None)
    held(booking, until=None)  # two nulls are fine
    Request.objects.filter(pk=held(booking, until=None).pk).update(manage_token="t" * 43)
    with pytest.raises(IntegrityError), transaction.atomic():
        Request.objects.filter(pk=held(booking, until=None).pk).update(
            manage_token="t" * 43
        )


def test_a_review_is_one_per_request_with_a_rating_from_1_to_5(booking):
    row = new_request(booking)
    review = Review.objects.create(request=row, rating=5)
    assert (review.status, review.comment, review.reason) == ("pending", "", "")
    assert row.review == review
    with pytest.raises(IntegrityError), transaction.atomic():
        Review.objects.create(request=row, rating=4)
    other = new_request(booking, starts_at=MONDAY_4PM + HALF)
    with pytest.raises(IntegrityError), transaction.atomic():
        Review.objects.create(request=other, rating=6)


def test_an_unexpired_hold_takes_a_place(booking, pinned):
    held(booking, until=NOW + timedelta(minutes=5))
    held(booking, until=NOW + timedelta(minutes=5))  # the product seats 2
    with pytest.raises(ConflictError) as caught:
        services.check_capacity(booking.product, booking.teacher_profile, MONDAY_4PM)
    assert caught.value.code == "consultations.slot_full"


def test_an_expired_unpaid_hold_frees_its_place(booking, pinned):
    held(booking, until=NOW - timedelta(minutes=1))
    held(booking, until=NOW)  # ends exactly now: expired
    services.check_capacity(booking.product, booking.teacher_profile, MONDAY_4PM)
    assert services.room_left(booking.product, booking.teacher_profile.pk, MONDAY_4PM) == 2


def test_paid_self_bookings_and_office_requests_stay_live(booking, pinned):
    held(booking, until=None, paid_method="stripe")
    held(booking, until=None, self_booked=False)
    assert services.room_left(booking.product, booking.teacher_profile.pk, MONDAY_4PM) == 0


def test_room_left_can_leave_one_request_out(booking, pinned):
    row = held(booking, until=NOW + HALF)
    pk = booking.teacher_profile.pk
    assert services.room_left(booking.product, pk, MONDAY_4PM) == 1
    assert services.room_left(booking.product, pk, MONDAY_4PM, exclude_id=row.pk) == 2


def test_free_slots_count_only_live_holds(booking, pinned):
    day = MONDAY_4PM.date()
    held(booking, until=NOW + HALF)
    held(booking, until=NOW - HALF)
    slots = services.free_slots(booking.product, booking.teacher.pk, day, 1).slots
    assert slots[0] == Slot(MONDAY_4PM, 1)


def test_free_slots_take_a_lead_and_a_last_day(booking):
    day = MONDAY_4PM.date()
    later = services.free_slots(
        booking.product, booking.teacher.pk, day, 1, not_before=MONDAY_4PM + HALF
    ).slots
    assert later[0].starts_at == MONDAY_4PM + HALF
    assert (
        services.free_slots(
            booking.product,
            booking.teacher.pk,
            day,
            7,
            last_date=day - timedelta(days=1),
        ).slots
        == []
    )


def test_office_cancel_records_its_reason(booking):
    row = services.cancel(new_request(booking), by=booking.admin)
    assert (row.status, row.cancel_reason) == ("cancelled", "office")
    row.refresh_from_db()
    assert row.cancel_reason == "office"


def test_lock_booker_takes_the_advisory_lock_with_the_exact_key():
    with CaptureQueriesContext(connection) as ctx:
        common.lock_booker("abc")
    key = f"consultations.booker.{connection.schema_name}.abc"
    assert any(
        "pg_advisory_xact_lock(hashtext(" in q["sql"] and f"'{key}'" in q["sql"]
        for q in ctx.captured_queries
    )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_live.py -q`
Expected: FAIL with `ImportError: cannot import name 'Review'` (and, once that exists, `AttributeError: … 'room_left'`).

- [ ] **Step 3: Add the columns and the review table**

In `backend/etqan/consultations/models.py`, add the import `from django.utils.timezone import now` (already there) and, inside `class Request`, after `class PaidMethod`:

```python
    class CancelReason(models.TextChoices):
        NONE = "", "None"
        UNPAID = "unpaid", "Unpaid"
        OFFICE = "office", "Office"
```

After the `teacher_share_bp` field of `Request`:

```python
    # Slice B7d §3: self-booking. The price is snapshot at booking (B7-3).
    self_booked = models.BooleanField(default=False)
    manage_token = models.CharField(max_length=64, unique=True, null=True, blank=True)
    hold_until = models.DateTimeField(null=True, blank=True)
    proposed_starts_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.CharField(
        max_length=10, choices=CancelReason.choices, blank=True, default=""
    )
    booked_ip_hash = models.CharField(max_length=64, blank=True, default="")
    # The booking page's language, for K-9's email ([assumed]: §3 has none).
    language = models.CharField(max_length=2, default="en")
    price_minor = models.BigIntegerField(null=True, blank=True)
    price_currency = models.CharField(max_length=3, blank=True, default="")
    price_fee_enabled = models.BooleanField(null=True, blank=True)
```

In `Request.Meta.indexes` add `models.Index(fields=["self_booked", "status", "hold_until"]),`.

At the end of the module:

```python
class Review(models.Model):
    """Slice B7d K-12 (CONS-003, B7-16): the booker's rating of a completed
    consultation, moderated by the office."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"

    request = models.OneToOneField(
        Request, on_delete=models.CASCADE, related_name="review"
    )
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True, default="", max_length=1000)
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.PENDING
    )
    reason = models.TextField(blank=True, default="", max_length=500)
    created_at = models.DateTimeField(default=now)
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at", "-id")
        constraints = [
            models.CheckConstraint(
                condition=Q(rating__gte=1) & Q(rating__lte=5),
                name="consult_review_rating_range",
            ),
        ]

    def __str__(self):
        return f"Review of {self.request_id}"
```

Generate the migration:

Run: `B python manage.py makemigrations consultations --name booking`
Expected: `etqan/consultations/migrations/0002_booking.py` with `AddField` × 10, `AddIndex`, `CreateModel Review`. It touches only consultations tables (B7-14).

- [ ] **Step 4: The live rule and the booker lock**

In `backend/etqan/consultations/services/common.py`, add the imports `import re`, `from datetime import timedelta` and `from django.db.models import Q`, change the `LIVE` comment, and add after `URL_MAX`:

```python
# C-5: a request that holds its place; B7d's `live_q` adds unexpired holds.
LIVE = ("pending_review", "confirmed", "reschedule_requested")
# Slice B7d K-3 (B7-17): an unpaid self-booking holds its place this long.
HOLD = timedelta(minutes=30)
# B7-10: self-booking's lead time, and the latest a booker may ask to move.
LEAD = timedelta(hours=12)
# K-9: secrets.token_urlsafe(32) is 43 url-safe characters (use fullmatch).
TOKEN_RE = re.compile(r"[A-Za-z0-9_-]{43}")
```

(The `LIVE` line replaces B7c's; its value is unchanged.) Replace `lock_teacher` and add the helpers below it:

```python
def _advisory(key: str) -> None:
    with connection.cursor() as cursor:
        cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", [key])


def lock_teacher(profile_id: int) -> None:
    """§4: one teacher's starts are set one at a time, in this academy.
    Transaction-scoped; taken before any place is counted."""
    _advisory(f"consultations.teacher.{connection.schema_name}.{profile_id}")


def lock_booker(ip_digest: str) -> None:
    """K-3: one booker's (one address's) bookings are counted one at a time.
    Taken before the teacher's lock."""
    _advisory(f"consultations.booker.{connection.schema_name}.{ip_digest}")


def expired_hold_q(at) -> Q:
    """K-7: a self-booking still unpaid whose hold has run out."""
    return Q(self_booked=True, paid_method="") & (
        Q(hold_until__isnull=True) | Q(hold_until__lte=at)
    )


def live_q(at=None) -> Q:
    """C-5 + K-7: a request that holds its place: a live status, unless it
    is a self-booking whose unpaid hold has run out."""
    return Q(status__in=LIVE) & ~expired_hold_q(now() if at is None else at)


def hold_expired(row) -> bool:
    """Whether an unpaid self-booked row's hold has run out."""
    return row.hold_until is None or row.hold_until <= now()
```

In `backend/etqan/consultations/services/slots.py`:
- replace `from etqan.consultations.services.common import LIVE` with `from etqan.consultations.services.common import live_q`;
- in `_live_requests`, replace `Request.objects.filter(teacher_id=profile_id, status__in=LIVE, starts_at__lt=until, ends_at__gt=since)` with:

```python
    qs = Request.objects.filter(
        live_q(), teacher_id=profile_id, starts_at__lt=until, ends_at__gt=since
    )
```

- replace `check_capacity` with:

```python
def room_left(product, profile_id: int, starts_at, *, exclude_id=None) -> int:
    """C-5, K-5: the places still free at one start of one product and teacher."""
    taken = Request.objects.filter(
        live_q(), product=product, teacher_id=profile_id, starts_at=starts_at
    )
    if exclude_id is not None:
        taken = taken.exclude(pk=exclude_id)
    return product.participants - taken.count()


def check_capacity(product, profile, starts_at, *, exclude_id=None) -> None:
    """C-5: the one refusal. Call under `lock_teacher(profile.pk)`."""
    if room_left(product, profile.pk, starts_at, exclude_id=exclude_id) <= 0:
        raise ConflictError("This slot is full.", code="consultations.slot_full")
```

- give `free_slots` the two keyword arguments and pass them on:

```python
def free_slots(  # noqa: PLR0913 -- keyword-only after the first four
    product,
    teacher_user_id,
    start_date: date,
    days: int,
    *,
    request=None,
    not_before=None,
    last_date: date | None = None,
):
```

and replace the `candidate_starts(...)` call with:

```python
    limit = _last_date(product, request)
    if last_date is not None:
        limit = last_date if limit is None else min(limit, last_date)
    starts = candidate_starts(
        windows,
        start_date=start_date,
        days=days,
        minutes=product.duration_minutes,
        zone=academy_zone(),
        last_date=limit,
        not_before=not_before,
    )
```

In `backend/etqan/consultations/services/transitions.py`, `cancel` becomes:

```python
@transaction.atomic
def cancel(row, *, by) -> Request:
    fresh = _from(row, S.PENDING_REVIEW, S.CONFIRMED, S.RESCHEDULE_REQUESTED)
    fresh.status, fresh.cancelled_at = S.CANCELLED, common.now()
    fresh.cancel_reason = Request.CancelReason.OFFICE
    return _save(fresh, "status", "cancelled_at", "cancel_reason")
```

In `services/__init__.py` add `from etqan.consultations.services.slots import room_left` and `"room_left"` to `__all__` (sorted).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `B pytest etqan/consultations -q`
Expected: PASS — the new file and every B7c test (B7c's `test_lock_teacher_takes_the_advisory_lock_with_the_exact_key` and `test_lock_taken_before_places_are_counted` still hold).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/consultations/models.py etqan/consultations/migrations/0002_booking.py \
  etqan/consultations/services/common.py etqan/consultations/services/slots.py \
  etqan/consultations/services/transitions.py etqan/consultations/services/__init__.py \
  etqan/consultations/tests/test_live.py
git -C backend commit -m "feat(consultations): booking columns, reviews and the unpaid-hold live rule (B7d §3, K-7)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The office list, its payload and B5's reads see self-booking (K-7, K-16, §6)

**Files:**
- Modify: `backend/etqan/consultations/services/requests.py`, `backend/etqan/consultations/services/reads.py`, `backend/etqan/consultations/api/request_views.py`, `backend/etqan/consultations/api/serializers.py`
- Test: `backend/etqan/consultations/tests/test_office_self_booked.py` (new)

**Interfaces:**
- Consumes: Task 1's columns.
- Produces:
  - `filter_requests(qs, *, …, self_booked: bool | None = None, …)`; without `paid_method="unpaid"` it hides rows with `cancel_reason="unpaid"`;
  - `GET requests/?self_booked=true|false`;
  - `request_data(row)` gains `self_booked`, `hold_until`, `proposed_starts_at`, `cancel_reason`;
  - `ConsultationEvent.self_booked: bool` and `ConsultationStart.self_booked: bool` (last field, default `False`).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_office_self_booked.py`:

```python
from datetime import timedelta

import pytest
from django.utils import timezone

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request

pytestmark = pytest.mark.django_db
R = "/api/v1/consultations/requests/"
HALF = timedelta(minutes=30)


@pytest.fixture
def rows(booking):
    office = new_request(booking)
    online = new_request(booking, starts_at=MONDAY_4PM + HALF)
    gone = new_request(booking, starts_at=MONDAY_4PM + 2 * HALF)
    Request.objects.filter(pk__in=[online.pk, gone.pk]).update(self_booked=True)
    Request.objects.filter(pk=gone.pk).update(status="cancelled", cancel_reason="unpaid")
    return office, online, gone


def ids(qs):
    return sorted(r.pk for r in qs)


def test_filter_by_self_booked(rows):
    office, online, _gone = rows
    qs = services.requests_queryset()
    assert ids(services.filter_requests(qs, self_booked=True)) == [online.pk]
    assert ids(services.filter_requests(qs, self_booked=False)) == [office.pk]


def test_unpaid_cancellations_show_only_under_unpaid(rows):
    office, online, gone = rows
    qs = services.requests_queryset()
    assert ids(services.filter_requests(qs)) == sorted([office.pk, online.pk])
    assert ids(services.filter_requests(qs, status="cancelled")) == []
    assert ids(services.filter_requests(qs, paid_method="unpaid")) == sorted(
        [office.pk, online.pk, gone.pk]
    )


def test_the_list_takes_the_filter_and_shows_the_new_fields(rows, api_for):
    _office, online, _gone = rows
    resp = api_for("admin").get(R, {"self_booked": "true"})
    assert resp.status_code == 200
    [row] = resp.json()["results"]
    assert row["id"] == online.pk
    assert (
        row["self_booked"],
        row["hold_until"],
        row["proposed_starts_at"],
        row["cancel_reason"],
    ) == (True, None, None, "")
    assert "fee_minor" in row["payment"]


def test_b5_reads_carry_self_booked(rows):
    office, online, _gone = rows
    at = timezone.now()  # new_request stamps created_at with the real clock
    events = services.consultation_events(
        since=at - timedelta(days=1), until=at + timedelta(days=1)
    )
    flags = {e.request_id: e.self_booked for e in events if e.kind == "created"}
    assert (flags[office.pk], flags[online.pk]) == (False, True)
    Request.objects.filter(pk__in=[office.pk, online.pk]).update(status="confirmed")
    starts = services.consultations_starting(
        since=MONDAY_4PM, until=MONDAY_4PM + timedelta(hours=2)
    )
    assert {s.request_id: s.self_booked for s in starts} == {
        office.pk: False,
        online.pk: True,
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_office_self_booked.py -q`
Expected: FAIL with `TypeError: filter_requests() got an unexpected keyword argument 'self_booked'`.

- [ ] **Step 3: Implement**

In `services/requests.py`, add `self_booked: bool | None = None` to `filter_requests`'s keyword arguments (after `status=""`) and replace its `paid_method` block with:

```python
    if self_booked is not None:
        qs = qs.filter(self_booked=self_booked)
    if paid_method == "unpaid":
        qs = qs.filter(paid_method="")
    else:
        # K-7: self-bookings the unpaid job cancelled show only under "unpaid".
        qs = qs.exclude(cancel_reason=Request.CancelReason.UNPAID)
        if paid_method:
            qs = qs.filter(paid_method=paid_method)
```

In `api/request_views.py`, add at module level:

```python
FLAGS = {"true": True, "false": False}
```

and pass `self_booked=FLAGS.get(p.get("self_booked", "")),` to `services.filter_requests(...)` in `RequestListView.get`.

In `api/serializers.py`, in `request_data`'s `data` dict, after `"reschedule_note": row.reschedule_note,`:

```python
        "self_booked": row.self_booked,
        "hold_until": _iso(row.hold_until),
        "proposed_starts_at": _iso(row.proposed_starts_at),
        "cancel_reason": row.cancel_reason,
```

In `services/reads.py`, add `self_booked: bool = False` as the **last** field of both `ConsultationEvent` and `ConsultationStart`, and pass `self_booked=row.self_booked,` in both constructors.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `B pytest etqan/consultations -q`
Expected: PASS (B7c's list and reads tests unchanged).

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/consultations/services/requests.py etqan/consultations/services/reads.py \
  etqan/consultations/api/request_views.py etqan/consultations/api/serializers.py \
  etqan/consultations/tests/test_office_self_booked.py
git -C backend commit -m "feat(consultations): office list filters self-booking and hides unpaid cancellations (B7d K-7, K-16)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: What may be booked, with whom and when (K-1, K-2)

**Files:**
- Modify: `backend/etqan/consultations/tests/conftest.py` (fixtures), `backend/etqan/consultations/services/__init__.py`
- Create: `backend/etqan/consultations/services/booking.py`
- Test: `backend/etqan/consultations/tests/test_booking_reads.py` (new)

**Interfaces:**
- Consumes: Task 1's `free_slots(..., not_before=, last_date=)`, `common.LEAD`; B7c's `products_queryset`, `opted_in_ids`; `identity.services.active_teachers(user_ids)`.
- Produces (all exported from `services`):
  - `booking_open() -> bool` (`consultations` and `online_payments` on);
  - `has_slots(product) -> bool` (not `email`);
  - `self_bookable(product) -> bool` (`product.bookable`, and `teacher_availability` on for a slot product);
  - `require_open() -> None` (raises `NotFoundError`);
  - `bookable_products() -> list[Product]` (featured first, as `Product.Meta.ordering`);
  - `bookable_product(pk) -> Product` (`NotFoundError`);
  - `offered_teachers(product) -> list[TeacherProfile]` (with `.user`), `offered_teacher(product, teacher_user_id) -> TeacherProfile` (400 `teacher`);
  - `academy_today() -> date`, `last_bookable_day(product) -> date`;
  - `booking_slots(product, teacher_user_id, start_date: date | None, days: int) -> list[Slot]`.
- Test fixtures (in `tests/conftest.py`): `SUNDAY_NOON`, autouse `_clear_cache`, `frozen` (pins `common.now`; call `frozen(at)` to move it), `online` (the `booking` world with self-booking open and the clock at `SUNDAY_NOON`), `stripe_on`, `paypal_on`.

- [ ] **Step 1: Add the fixtures**

In `backend/etqan/consultations/tests/conftest.py`, add to the imports at the top:

```python
from django.core.cache import cache

from etqan.consultations.services import common
from etqan.gateways import services as gateways_services
from etqan.gateways.tests.conftest import PAYPAL_KEYS
from etqan.gateways.tests.conftest import TEST_KEYS
```

and at the end of the module:

```python
# A Sunday, 28 hours before MONDAY_4PM (academy zone UTC in tests).
SUNDAY_NOON = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)


@pytest.fixture(autouse=True)
def _clear_cache():
    """Throttle counters and PayPal tokens must not leak between tests (B7b PF6)."""
    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def frozen(monkeypatch):
    """`frozen(at)` pins the consultations clock (`common.now`); it starts at
    SUNDAY_NOON."""

    def pin(at):
        monkeypatch.setattr(common, "now", lambda: at)

    pin(SUNDAY_NOON)
    return pin


@pytest.fixture
def online(booking, set_features, frozen):
    """`booking`'s world with self-booking open (online_payments needs
    invoices, B3b) and the clock on SUNDAY_NOON."""
    set_features(invoices=True, online_payments=True)
    return booking


@pytest.fixture
def stripe_on():
    gateways_services.update_settings(stripe=TEST_KEYS, by=None)
    return gateways_services.stripe_account()


@pytest.fixture
def paypal_on():
    gateways_services.update_settings(paypal=PAYPAL_KEYS, by=None)
    return gateways_services.paypal_account()
```

- [ ] **Step 2: Write the failing tests**

`backend/etqan/consultations/tests/test_booking_reads.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

import pytest

from etqan.consultations import services
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)
MONDAY = MONDAY_4PM.date()


def written(b, **extra):
    """An email consultation of Bilal's (no slots)."""
    return services.create_product(
        name_ar="سؤال",
        name_en="Written",
        description_en="d",
        price_minor=2000,
        currency="USD",
        duration_minutes=30,
        validity_days=7,
        delivery_mode="email",
        teacher_user_ids=[b.teacher.pk],
        **extra,
    )


def test_open_needs_consultations_and_online_payments(online, set_features):
    assert services.booking_open()
    set_features(online_payments=False)
    assert not services.booking_open()
    with pytest.raises(NotFoundError):
        services.bookable_products()
    set_features(online_payments=True, consultations=False)
    with pytest.raises(NotFoundError):
        services.bookable_product(online.product.pk)


def test_slot_products_hide_while_availability_is_off(online, set_features):
    email = written(online)
    assert [p.pk for p in services.bookable_products()] == [online.product.pk, email.pk]
    set_features(teacher_availability=False)
    assert [p.pk for p in services.bookable_products()] == [email.pk]
    with pytest.raises(NotFoundError):
        services.bookable_product(online.product.pk)
    assert services.bookable_product(email.pk) == email


def test_featured_first_and_closed_products_left_out(online):
    email = written(online, featured=True)
    assert [p.pk for p in services.bookable_products()] == [email.pk, online.product.pk]
    services.update_product(online.product, enabled=False)
    assert [p.pk for p in services.bookable_products()] == [email.pk]
    services.update_product(online.product, enabled=True, status="archived")
    assert [p.pk for p in services.bookable_products()] == [email.pk]


def test_teachers_are_the_products_opted_in_active_ones(online):
    assert [t.user_id for t in services.offered_teachers(online.product)] == [
        online.teacher.pk
    ]
    services.set_consultant(online.teacher.pk, offers=False, by=online.admin)
    assert services.offered_teachers(online.product) == []
    services.set_consultant(online.teacher.pk, offers=True, by=online.admin)
    online.teacher.is_active = False
    online.teacher.save()
    assert services.offered_teachers(online.product) == []


def test_slots_start_twelve_hours_ahead(online, frozen):
    frozen(datetime(2026, 10, 12, 4, 30, tzinfo=UTC))  # 16:00 is 11.5 h away
    slots = services.booking_slots(online.product, online.teacher.pk, MONDAY, 1)
    assert [s.starts_at for s in slots] == [
        MONDAY_4PM + HALF,
        MONDAY_4PM + 2 * HALF,
        MONDAY_4PM + 3 * HALF,
    ]


def test_slots_run_to_the_validity_or_31_days(online):
    # Validity 7 from Sunday 11 October: the last day is Sunday 18 October.
    assert services.last_bookable_day(online.product) == date(2026, 10, 18)
    assert (
        services.booking_slots(online.product, online.teacher.pk, date(2026, 10, 19), 7)
        == []
    )
    services.update_product(online.product, validity_days=60)
    assert services.last_bookable_day(online.product) == date(2026, 11, 11)
    nov9 = services.booking_slots(online.product, online.teacher.pk, date(2026, 11, 9), 1)
    assert nov9[0].starts_at == datetime(2026, 11, 9, 16, 0, tzinfo=UTC)
    assert (
        services.booking_slots(online.product, online.teacher.pk, date(2026, 11, 16), 1)
        == []
    )


def test_a_day_before_today_starts_today(online):
    slots = services.booking_slots(online.product, online.teacher.pk, date(2026, 10, 1), 2)
    assert slots[0].starts_at == MONDAY_4PM


def test_an_unknown_teacher_is_400_and_email_products_have_no_slots(online):
    with pytest.raises(ValidationError) as caught:
        services.booking_slots(online.product, 999999, MONDAY, 1)
    assert caught.value.field == "teacher"
    assert services.booking_slots(written(online), online.teacher.pk, MONDAY, 1) == []
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_booking_reads.py -q`
Expected: FAIL with `AttributeError: module 'etqan.consultations.services' has no attribute 'booking_open'`.

- [ ] **Step 4: Implement**

`backend/etqan/consultations/services/booking.py`:

```python
"""Slice B7d K-1, K-2: what a visitor or a family may book, with whom and
when. Task 4 adds the booking itself."""

from datetime import date
from datetime import timedelta
from zoneinfo import ZoneInfo

from etqan.consultations.models import Product
from etqan.consultations.services import common
from etqan.consultations.services.consultants import opted_in_ids
from etqan.consultations.services.products import products_queryset
from etqan.consultations.services.slots import free_slots
from etqan.identity import services as identity_services
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

FEATURE = "consultations"
ONLINE = "online_payments"
AVAILABILITY = "teacher_availability"
# K-2 [assumed]: slots run at most this many days ahead (inclusive).
HORIZON_DAYS = 31


def booking_open() -> bool:
    """K-1: no unpaid self-booking, so paying online must be on too."""
    return features.enabled(FEATURE) and features.enabled(ONLINE)


def has_slots(product) -> bool:
    return product.delivery_mode != Product.Mode.EMAIL


def self_bookable(product) -> bool:
    """K-1: a slot product also needs teacher availability (B7-10)."""
    return product.bookable and (
        not has_slots(product) or features.enabled(AVAILABILITY)
    )


def require_open() -> None:
    if not booking_open():
        raise NotFoundError("Consultation")


def bookable_products() -> list[Product]:
    require_open()
    return [p for p in products_queryset() if self_bookable(p)]


def bookable_product(pk) -> Product:
    require_open()
    product = products_queryset().filter(pk=pk).first()
    if product is None or not self_bookable(product):
        raise NotFoundError("Consultation", pk)
    return product


def offered_teachers(product) -> list:
    """K-2: the product's teachers who are opted in (C-3) and active."""
    ids = [t.user_id for t in product.teachers.all()]
    opted = opted_in_ids()
    return [t for t in identity_services.active_teachers(ids) if t.pk in opted]


def offered_teacher(product, teacher_user_id):
    for profile in offered_teachers(product):
        if profile.user_id == teacher_user_id:
            return profile
    raise ValidationError(
        "Choose one of this consultation's teachers.", field="teacher"
    )


def academy_today() -> date:
    return common.now().astimezone(ZoneInfo(common.academy_zone())).date()


def last_bookable_day(product) -> date:
    """K-2 (BR-26): payment happens now, so slots end at the earlier of the
    validity and the horizon."""
    return academy_today() + timedelta(days=min(product.validity_days, HORIZON_DAYS))


def booking_slots(product, teacher_user_id, start_date: date | None, days: int) -> list:
    """K-2: B7c's free slots from today, at least 12 hours ahead, up to the
    last bookable day. An email product has none."""
    offered_teacher(product, teacher_user_id)
    if not has_slots(product):
        return []
    today = academy_today()
    first = max(start_date or today, today)
    last = last_bookable_day(product)
    if first > last:
        return []
    span = min(days, (last - first).days + 1)
    return free_slots(
        product,
        teacher_user_id,
        first,
        span,
        not_before=common.now() + common.LEAD,
        last_date=last,
    ).slots
```

In `services/__init__.py`, import from `etqan.consultations.services.booking`: `academy_today`, `bookable_product`, `bookable_products`, `booking_open`, `booking_slots`, `has_slots`, `last_bookable_day`, `offered_teacher`, `offered_teachers`, `require_open`, `self_bookable`; add each name to `__all__` (sorted).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `B pytest etqan/consultations -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/consultations/services/booking.py etqan/consultations/services/__init__.py \
  etqan/consultations/tests/conftest.py etqan/consultations/tests/test_booking_reads.py
git -C backend commit -m "feat(consultations): bookable products, offered teachers and self-booking slots (B7d K-1, K-2)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Booking a request (K-3, K-8, K-13)

**Files:**
- Modify: `backend/etqan/consultations/services/booking.py`, `backend/etqan/consultations/services/requests.py` (three helpers made public), `backend/etqan/consultations/services/__init__.py`, `backend/etqan/consultations/tests/conftest.py` (`book_one`)
- Test: `backend/etqan/consultations/tests/test_book.py` (new)

**Interfaces:**
- Consumes: Task 3's `require_open`, `bookable_product`, `offered_teacher`, `has_slots`, `booking_slots`; Task 1's `common.HOLD`, `lock_booker`, `lock_teacher`.
- Produces:
  - `book(*, product_id, teacher_user_id, starts_at, name, email, whatsapp, timezone, notes, language, ip, user=None, student_user_id=None) -> Request` (atomic);
  - `ip_hash(ip: str) -> str`, `manage_url(row) -> str` (`app_url("/consult/manage/<token>")`);
  - `requests.clean_contact(name, email, whatsapp, timezone) -> dict`, `requests.clean_notes(notes) -> str`, `requests.default_link(profile) -> str` (renamed from B7c's private `_contact`, `_clean_notes`, `_default_link`);
  - test helper `book_one(b, **extra) -> Request`.
- Refusals: 400 on `product`, `teacher`, `name`, `email`, `whatsapp`, `timezone`, `notes`, `starts_at`; 404 (`NotFoundError`) while booking is closed or for another family's child; 409 `consultations.slot_full`, 409 `consultations.too_many_pending`.

- [ ] **Step 1: Write the failing tests**

Add to the end of `backend/etqan/consultations/tests/conftest.py`:

```python
def book_one(b, **extra):
    """A visitor's booking of Monday 16:00 with Bilal (`services.book`)."""
    data = {
        "product_id": b.product.pk,
        "teacher_user_id": b.teacher.pk,
        "starts_at": MONDAY_4PM,
        "name": "Sara",
        "email": "sara@x.test",
        "whatsapp": "+201000000009",
        "timezone": "Asia/Riyadh",
        "notes": "",
        "language": "en",
        "ip": "203.0.113.7",
        **extra,
    }
    return consult_services.book(**data)
```

`backend/etqan/consultations/tests/test_book.py`:

```python
import hashlib
import hmac
import re
from datetime import timedelta

import pytest
from django.conf import settings
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import SUNDAY_NOON
from etqan.consultations.tests.conftest import book_one
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)


def _code(fn):
    with pytest.raises(ConflictError) as caught:
        fn()
    return caught.value.code


def test_a_visitor_books_a_held_unpaid_request(online):
    row = book_one(online)
    assert (row.self_booked, row.status, row.paid) == (True, "pending_review", False)
    assert row.hold_until == SUNDAY_NOON + timedelta(minutes=30)
    assert re.fullmatch(r"[A-Za-z0-9_-]{43}", row.manage_token)
    assert row.booked_ip_hash == hmac.new(
        settings.SECRET_KEY.encode(), b"203.0.113.7", hashlib.sha256
    ).hexdigest()
    assert (row.price_minor, row.price_currency, row.price_fee_enabled) == (
        1500,
        "USD",
        False,
    )
    assert (row.student, row.created_by, row.language) == (None, None, "en")
    assert (row.name, row.email, row.whatsapp, row.timezone) == (
        "Sara",
        "sara@x.test",
        "+201000000009",
        "Asia/Riyadh",
    )
    assert (row.starts_at, row.ends_at, row.created_at) == (
        MONDAY_4PM,
        MONDAY_4PM + HALF,
        SUNDAY_NOON,
    )
    assert services.manage_url(row).endswith(f"/app/consult/manage/{row.manage_token}")


def test_the_page_language_is_kept(online):
    assert book_one(online, language="ar").language == "ar"
    assert book_one(online, language="fr", starts_at=MONDAY_4PM + HALF).language == "en"


@pytest.mark.parametrize(
    ("extra", "field"),
    [
        ({"product_id": 999999}, "product"),
        ({"teacher_user_id": 999999}, "teacher"),
        ({"name": "  "}, "name"),
        ({"email": "nope"}, "email"),
        ({"whatsapp": ""}, "whatsapp"),
        ({"timezone": "Mars/Base"}, "timezone"),
        ({"notes": "x" * 2001}, "notes"),
        ({"starts_at": None}, "starts_at"),
    ],
)
def test_bad_fields_are_400(online, extra, field):
    with pytest.raises(ValidationError) as caught:
        book_one(online, **extra)
    assert caught.value.field == field
    assert not Request.objects.exists()


def test_closed_booking_is_not_found(online, set_features):
    set_features(online_payments=False)
    with pytest.raises(NotFoundError):
        book_one(online)


def test_the_price_is_a_snapshot(online):
    row = book_one(online)
    services.update_product(online.product, price_minor=9900, fee_enabled=True)
    row.refresh_from_db()
    assert (row.price_minor, row.price_fee_enabled) == (1500, False)


@pytest.mark.parametrize(
    "start",
    [
        MONDAY_4PM + timedelta(minutes=10),  # not a step of the window
        MONDAY_4PM - timedelta(days=7),  # before today
        MONDAY_4PM + timedelta(days=14),  # after the last bookable day
    ],
)
def test_a_start_that_is_not_offered_is_slot_full(online, start):
    assert _code(lambda: book_one(online, starts_at=start)) == "consultations.slot_full"


def test_a_full_slot_is_refused(online):
    book_one(online, ip="1.1.1.1", email="a@x.test")
    book_one(online, ip="1.1.1.2", email="b@x.test")  # the product seats 2
    assert (
        _code(lambda: book_one(online, ip="1.1.1.3", email="c@x.test"))
        == "consultations.slot_full"
    )


def test_an_expired_hold_frees_the_place(online, frozen):
    book_one(online, ip="1.1.1.1", email="a@x.test")
    book_one(online, ip="1.1.1.2", email="b@x.test")
    frozen(SUNDAY_NOON + timedelta(minutes=31))
    assert book_one(online, ip="1.1.1.3", email="c@x.test").pk


def test_three_unpaid_per_email_then_409(online):
    for i in range(3):
        book_one(
            online,
            starts_at=MONDAY_4PM + i * HALF,
            ip=f"10.0.0.{i}",
            email="Sara@X.test" if i == 1 else "sara@x.test",
        )
    assert (
        _code(lambda: book_one(online, starts_at=MONDAY_4PM + 3 * HALF, ip="10.0.0.9"))
        == "consultations.too_many_pending"
    )


def test_three_unpaid_per_ip_then_409(online):
    for i in range(3):
        book_one(online, starts_at=MONDAY_4PM + i * HALF, email=f"p{i}@x.test")
    assert (
        _code(
            lambda: book_one(online, starts_at=MONDAY_4PM + 3 * HALF, email="p9@x.test")
        )
        == "consultations.too_many_pending"
    )


def test_paid_or_expired_bookings_do_not_count(online, frozen):
    first = book_one(online, starts_at=MONDAY_4PM)
    book_one(online, starts_at=MONDAY_4PM + HALF)
    book_one(online, starts_at=MONDAY_4PM + 2 * HALF)
    Request.objects.filter(pk=first.pk).update(paid_method="stripe", hold_until=None)
    book_one(online, starts_at=MONDAY_4PM + 3 * HALF)
    frozen(SUNDAY_NOON + timedelta(minutes=31))
    assert book_one(online, starts_at=MONDAY_4PM).pk  # every hold has run out


def test_booker_lock_then_teacher_lock_then_count(online):
    with CaptureQueriesContext(connection) as ctx:
        book_one(online)
    sql = [q["sql"] for q in ctx.captured_queries]
    booker = next(i for i, s in enumerate(sql) if "consultations.booker." in s)
    teacher = next(i for i, s in enumerate(sql) if "consultations.teacher." in s)
    count = next(
        i for i, s in enumerate(sql) if "COUNT(" in s and "consultations_request" in s
    )
    assert booker < teacher < count


def test_an_email_consultation_books_without_a_time(online):
    email = services.create_product(
        name_ar="سؤال",
        name_en="Written",
        description_en="d",
        price_minor=2000,
        currency="USD",
        duration_minutes=30,
        validity_days=7,
        delivery_mode="email",
        teacher_user_ids=[online.teacher.pk],
    )
    row = book_one(online, product_id=email.pk, starts_at=None)
    assert (row.starts_at, row.ends_at, row.meeting_url, row.price_minor) == (
        None,
        None,
        "",
        2000,
    )
    with pytest.raises(ValidationError) as caught:
        book_one(online, product_id=email.pk, starts_at=MONDAY_4PM)
    assert caught.value.field == "starts_at"


def test_a_student_books_for_themself_with_their_details(online):
    row = book_one(online, user=online.student, name="", email="", whatsapp="", timezone="")
    assert (row.student, row.created_by) == (online.student_profile, online.student)
    assert (row.name, row.email, row.whatsapp, row.timezone) == (
        "Yusuf Omar",
        "yusuf@x.test",
        "+201000000001",
        "Africa/Cairo",
    )
    other = book_one(
        online, user=online.student, student_user_id=999, starts_at=MONDAY_4PM + HALF
    )
    assert other.student == online.student_profile  # a student books for themself


def test_a_parent_books_for_their_own_child_only(online):
    parent = identity_services.create_person(
        "parent", full_name="Omar", email="omar@x.test", invite=False
    )
    identity_services.link_guardian(parent, online.student)
    row = book_one(
        online,
        user=parent,
        student_user_id=online.student.pk,
        name="",
        email="",
        whatsapp="+201000000002",
        timezone="",
    )
    assert (row.student, row.name, row.email, row.timezone, row.created_by) == (
        online.student_profile,
        "Omar",
        "omar@x.test",
        "UTC",
        parent,
    )
    alone = book_one(online, user=parent, starts_at=MONDAY_4PM + HALF)
    assert alone.student is None
    stranger = identity_services.create_person("student", full_name="Zaid", invite=False)
    with pytest.raises(NotFoundError):
        book_one(
            online,
            user=parent,
            student_user_id=stranger.pk,
            starts_at=MONDAY_4PM + 2 * HALF,
        )


def test_booking_sends_no_email(online, monkeypatch, django_capture_on_commit_callbacks):
    sent = []
    monkeypatch.setattr(
        identity_services, "send_notice", lambda *a, **kw: sent.append(a)
    )
    with django_capture_on_commit_callbacks(execute=True):
        book_one(online)
    assert sent == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_book.py -q`
Expected: FAIL with `AttributeError: module 'etqan.consultations.services' has no attribute 'book'`.

- [ ] **Step 3: Make three B7c helpers public**

In `backend/etqan/consultations/services/requests.py`, rename by word boundary (`_apply_contact` and `_swap_default_link` keep their names):

```bash
sed -i -E 's/\b_contact\(/clean_contact(/g; s/\b_clean_notes\(/clean_notes(/g; s/\b_default_link\(/default_link(/g' \
  backend/etqan/consultations/services/requests.py
```

Then `grep -n "clean_contact\|clean_notes\|default_link" backend/etqan/consultations/services/requests.py` must show the three `def` lines and their B7c call sites (`create_request`, `_apply_contact`, `_swap_default_link`).

- [ ] **Step 4: Implement `book`**

Append to `backend/etqan/consultations/services/booking.py` (the imports go to the top of the module):

```python
import hashlib
import hmac
import secrets

from django.conf import settings
from django.db import transaction

from etqan.consultations.models import Request
from etqan.consultations.services.requests import clean_contact
from etqan.consultations.services.requests import clean_notes
from etqan.consultations.services.requests import default_link
from etqan.platform.exceptions import ConflictError
from etqan.platform.frontend import app_url

PENDING_CAP = 3  # K-8 (B7-17): live unpaid self-bookings per email and per IP
LANGUAGES = ("en", "ar")


def ip_hash(ip: str) -> str:
    """K-3: who booked from where, without keeping the address."""
    return hmac.new(
        settings.SECRET_KEY.encode(), (ip or "").encode(), hashlib.sha256
    ).hexdigest()


def manage_url(row) -> str:
    return app_url(f"/consult/manage/{row.manage_token}")


def _student_for(user, student_user_id):
    """K-3, K-13: a visitor books for no student; a student for themself; a
    parent for one of their own children (404 otherwise) or, naming none,
    for no student ([assumed])."""
    if user is None:
        return None
    if getattr(user, "role", "") == "student":
        return identity_services.get_student_profile(user.pk)
    if student_user_id is None:
        return None
    if not identity_services.is_parent_of(user.pk, student_user_id):
        raise NotFoundError("Student", student_user_id)
    return identity_services.get_student_profile(student_user_id)


def _contact_for(user, name, email, whatsapp, timezone) -> dict:
    """A signed-in booker's blanks fall back to their own account ([assumed])."""
    if user is not None:
        name = name or user.full_name
        email = email or (user.email or "")
        whatsapp = whatsapp or (user.phone or "")
        timezone = timezone or user.timezone
    return clean_contact(name, email, whatsapp, timezone)


def _check_caps(email: str, digest: str, at) -> None:
    """K-8, under the booker's lock."""
    held = Request.objects.filter(
        self_booked=True,
        paid_method="",
        status=Request.Status.PENDING_REVIEW,
        hold_until__gt=at,
    )
    if (
        held.filter(email__iexact=email).count() >= PENDING_CAP
        or held.filter(booked_ip_hash=digest).count() >= PENDING_CAP
    ):
        raise ConflictError(
            "Too many bookings are waiting for payment. Pay one, or wait 30 minutes.",
            code="consultations.too_many_pending",
        )


def _check_place(product, teacher, starts_at) -> None:
    """K-3, under the teacher's lock: the start must be one of K-2's slots
    now; anything else is the one capacity refusal ([assumed])."""
    day = starts_at.astimezone(ZoneInfo(common.academy_zone())).date()
    offered = {s.starts_at for s in booking_slots(product, teacher.user_id, day, 1)}
    if starts_at not in offered:
        raise ConflictError(
            "This slot is full. Pick another time.", code="consultations.slot_full"
        )


@transaction.atomic
def book(  # noqa: PLR0913 -- keyword-only; mirrors the booking form
    *,
    product_id,
    teacher_user_id,
    starts_at,
    name,
    email,
    whatsapp,
    timezone,
    notes,
    language,
    ip,
    user=None,
    student_user_id=None,
) -> Request:
    """K-3: a held, unpaid, self-booked request with the price snapshot.
    Locks: the booker's, then the teacher's (§ Global Constraints)."""
    require_open()
    try:
        product = bookable_product(product_id)
    except NotFoundError:
        raise ValidationError("Choose a consultation.", field="product") from None
    teacher = offered_teacher(product, teacher_user_id)
    student = _student_for(user, student_user_id)
    contact = _contact_for(user, name, email, whatsapp, timezone)
    notes = clean_notes(notes)
    if has_slots(product) and starts_at is None:
        raise ValidationError("Choose a time.", field="starts_at")
    if not has_slots(product) and starts_at is not None:
        raise ValidationError("An email consultation has no time.", field="starts_at")
    digest = ip_hash(ip)
    at = common.now()
    common.lock_booker(digest)
    common.lock_teacher(teacher.pk)
    _check_caps(contact["email"], digest, at)
    if starts_at is not None:
        _check_place(product, teacher, starts_at)
    video = product.delivery_mode == Product.Mode.VIDEO_CALL
    return Request.objects.create(
        product=product,
        teacher=teacher,
        student=student,
        notes=notes,
        starts_at=starts_at,
        ends_at=(
            starts_at + timedelta(minutes=product.duration_minutes)
            if starts_at
            else None
        ),
        meeting_url=default_link(teacher) if video else "",
        self_booked=True,
        hold_until=at + common.HOLD,
        manage_token=secrets.token_urlsafe(32),
        booked_ip_hash=digest,
        language=language if language in LANGUAGES else "en",
        price_minor=product.price_minor,
        price_currency=product.currency,
        price_fee_enabled=product.fee_enabled,
        created_by=user,
        created_at=at,
        **contact,
    )
```

In `services/__init__.py`, export `book`, `ip_hash` and `manage_url` (sorted into `__all__`).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `B pytest etqan/consultations -q`
Expected: PASS (B7c's request tests still pass after the renames).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/consultations/services/booking.py etqan/consultations/services/requests.py \
  etqan/consultations/services/__init__.py etqan/consultations/tests/conftest.py \
  etqan/consultations/tests/test_book.py
git -C backend commit -m "feat(consultations): self-booking with a 30-minute hold, caps and a price snapshot (B7d K-3, K-8)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The purpose's `prepare`, and the import contracts (K-5, D28, D53)

**Files:**
- Create: `backend/etqan/consultations/services/purpose.py`
- Modify (**claim**, one commit): `backend/pyproject.toml` — the consultations contract's `gateways.services` whitelist (B7 block) and the gateways contract
- Test: `backend/etqan/consultations/tests/test_purpose_prepare.py` (new)

**Interfaces:**
- Consumes: Task 3's `booking_open`, `has_slots`, `AVAILABILITY`; Task 1's `room_left`, `common.hold_expired`, `common.TOKEN_RE`; `gateways.services.Prepared`, `RECHECK`.
- Produces (in `purpose.py`):
  - `NAME = "consultation"`;
  - `prepare(reference_id, user, params) -> Prepared`; refusals in order: (1) switches off → `NotFoundError`; (2) no request, or `params` neither `{"token": <its manage_token>}` nor gateways' `RECHECK` object → `NotFoundError`; (3) paid, not `pending_review`, or not self-booked → 409 `consultations.not_payable`; (4) hold expired and no room left without it → 409 `consultations.slot_taken`; (5) product not bookable → 409 `consultations.not_bookable`;
  - `not_payable() -> ConflictError`, `slot_taken() -> ConflictError`, `slot_gone(row) -> bool` (used by Tasks 6 and 7).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_purpose_prepare.py`:

```python
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.services import purpose
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import SUNDAY_NOON
from etqan.consultations.tests.conftest import book_one
from etqan.consultations.tests.conftest import new_request
from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)
LATER = SUNDAY_NOON + timedelta(minutes=31)


def mine(row):
    return {"token": row.manage_token}


def _code(row, params=None):
    with pytest.raises(ConflictError) as caught:
        purpose.prepare(row.pk, None, params or mine(row))
    return caught.value.code


def fill(online, start=MONDAY_4PM):
    """Both places of `start` taken by two other live bookings."""
    book_one(online, starts_at=start, ip="1.1.1.1", email="a@x.test")
    book_one(online, starts_at=start, ip="1.1.1.2", email="b@x.test")


def test_prepare_prices_from_the_snapshot(online):
    row = book_one(online)
    services.update_product(online.product, price_minor=9900)
    got = purpose.prepare(row.pk, None, mine(row))
    assert got == gateways_services.Prepared(
        amount_minor=1500,
        currency="USD",
        description=f"Consultation CR-{row.pk:06d}",
        add_fee=False,
        use_switch=False,
    )
    assert purpose.prepare(row.pk, None, gateways_services.RECHECK) == got


def test_the_fee_follows_the_snapshot_flag(online):
    services.update_product(online.product, fee_enabled=True)
    row = book_one(online)
    services.update_product(online.product, fee_enabled=False)
    assert purpose.prepare(row.pk, None, mine(row)).add_fee is True


@pytest.mark.parametrize(
    "params",
    [None, {}, {"token": "x"}, {"token": "A" * 43}, {"token": "A" * 44}, {"recheck": True}],
)
def test_without_its_token_it_is_not_found(online, params):
    row = book_one(online)
    with pytest.raises(NotFoundError):
        purpose.prepare(row.pk, None, params)


def test_a_missing_request_is_not_found(online):
    with pytest.raises(NotFoundError):
        purpose.prepare(999999, None, gateways_services.RECHECK)


@pytest.mark.parametrize(
    "switch", ["consultations", "online_payments", "teacher_availability"]
)
def test_switches_off_are_not_found_even_with_the_token(online, set_features, switch):
    row = book_one(online)
    set_features(**{switch: False})
    with pytest.raises(NotFoundError):
        purpose.prepare(row.pk, None, mine(row))


def test_paid_moved_on_or_office_requests_are_not_payable(online):
    row = book_one(online)
    Request.objects.filter(pk=row.pk).update(paid_method="stripe")
    assert _code(row) == "consultations.not_payable"
    with pytest.raises(NotFoundError):  # (2) before (3)
        purpose.prepare(row.pk, None, {"token": "B" * 43})
    other = book_one(online, starts_at=MONDAY_4PM + HALF)
    Request.objects.filter(pk=other.pk).update(status="confirmed")
    assert _code(other) == "consultations.not_payable"
    office = new_request(online, starts_at=MONDAY_4PM + 2 * HALF)
    assert _code(office, gateways_services.RECHECK) == "consultations.not_payable"


def test_an_expired_hold_whose_place_was_taken_is_slot_taken(online, frozen):
    row = book_one(online)
    frozen(LATER)
    assert purpose.prepare(row.pk, None, mine(row)).amount_minor == 1500  # room left
    fill(online)
    assert _code(row) == "consultations.slot_taken"


def test_a_product_closed_to_booking_is_not_bookable(online):
    row = book_one(online)
    services.update_product(online.product, enabled=False)
    assert _code(row) == "consultations.not_bookable"


def test_refusals_come_in_order(online, frozen):
    paid = book_one(online)
    Request.objects.filter(pk=paid.pk).update(paid_method="stripe", hold_until=None)
    late = book_one(online, starts_at=MONDAY_4PM + HALF)
    frozen(LATER)
    fill(online, MONDAY_4PM + HALF)
    services.update_product(online.product, enabled=False)
    assert _code(paid) == "consultations.not_payable"  # (3) before (5)
    assert _code(late) == "consultations.slot_taken"  # (4) before (5)


def test_prepare_only_reads(online):
    row = book_one(online)
    with CaptureQueriesContext(connection) as ctx:
        purpose.prepare(row.pk, None, mine(row))
    writes = [
        q["sql"]
        for q in ctx.captured_queries
        if q["sql"].lstrip().upper().startswith(("UPDATE", "INSERT", "DELETE"))
        or "FOR UPDATE" in q["sql"]
    ]
    assert writes == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_purpose_prepare.py -q`
Expected: FAIL with `ImportError: cannot import name 'purpose'`.

- [ ] **Step 3: Implement `prepare`**

`backend/etqan/consultations/services/purpose.py`:

```python
"""Slice B7d K-4…K-6 (B7-3, B7-4, D53): the public `consultation` purpose.
Its reference is a self-booked Request. `prepare` reads only that row and
the URL's token or gateways' RECHECK, never request data (D28). Task 6 adds
`complete`, which records the money in billing and marks the request paid
in one inner block, or records nothing and says why."""

import hmac
from collections.abc import Mapping

from etqan.consultations.models import Request
from etqan.consultations.services import booking
from etqan.consultations.services import common
from etqan.consultations.services.slots import room_left
from etqan.gateways import services as gateways_services
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError

NAME = "consultation"


def not_payable() -> ConflictError:
    return ConflictError(
        "This booking cannot be paid now.", code="consultations.not_payable"
    )


def slot_taken() -> ConflictError:
    return ConflictError(
        "Someone else took this time. Book another one.",
        code="consultations.slot_taken",
    )


def _allowed(params, row) -> bool:
    """K-5 (2): the booking's own token, or gateways' re-check marker itself."""
    if params is gateways_services.RECHECK:
        return True
    given = params.get("token") if isinstance(params, Mapping) else None
    return (
        isinstance(given, str)
        and common.TOKEN_RE.fullmatch(given) is not None
        and bool(row.manage_token)
        and hmac.compare_digest(given.encode(), row.manage_token.encode())
    )


def slot_gone(row) -> bool:
    """K-5 (4), K-6: an expired hold whose place someone else now holds."""
    return (
        row.starts_at is not None
        and common.hold_expired(row)
        and room_left(row.product, row.teacher_id, row.starts_at, exclude_id=row.pk)
        <= 0
    )


def prepare(reference_id: int, user, params) -> gateways_services.Prepared:
    """K-5: read-only (gateways' still_payable calls it). The price is the
    booking's snapshot, never the live product (B7-3, BR-26)."""
    if not booking.booking_open():
        raise NotFoundError("Consultation request", reference_id)
    row = Request.objects.select_related("product").filter(pk=reference_id).first()
    if row is None or not _allowed(params, row):
        raise NotFoundError("Consultation request", reference_id)
    product = row.product
    if booking.has_slots(product) and not features.enabled(booking.AVAILABILITY):
        raise NotFoundError("Consultation request", reference_id)
    if row.paid or row.status != Request.Status.PENDING_REVIEW or not row.self_booked:
        raise not_payable()
    if slot_gone(row):
        raise slot_taken()
    if not product.bookable:
        raise ConflictError(
            "This consultation takes no new bookings.",
            code="consultations.not_bookable",
        )
    return gateways_services.Prepared(
        amount_minor=row.price_minor,
        currency=row.price_currency,
        description=f"Consultation {row.reference}",
        add_fee=bool(row.price_fee_enabled),
        use_switch=False,
    )
```

- [ ] **Step 4: Both import contracts, in this first commit that imports `gateways.services` (claim `backend/pyproject.toml`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/pyproject.toml --reason "B7d: consultations may import gateways.services; gateways never imports etqan.consultations (phase spec §4, D53)"
```

In `backend/pyproject.toml`:
- in the contract named `consultations reach other apps only through their services` (under `# ── phase B7 ──`), add to `ignore_imports` after the `scheduling.services` line (without it lint-imports fails from this commit on: B7b PF1):

```toml
    "etqan.consultations.** -> etqan.gateways.services",
```

- in the contract named `gateways imports no business app`, append `"etqan.consultations",` to `forbidden_modules` right after `"etqan.recorded",` (B7b's line; on a trunk without it, after `"etqan.vouchers",`).

Run: `B pytest etqan/consultations -q` and `B lint-imports`
Expected: both PASS.

- [ ] **Step 5: Commit (then release the claim)**

```bash
git -C backend add etqan/consultations/services/purpose.py etqan/consultations/tests/test_purpose_prepare.py pyproject.toml
git -C backend commit -m "feat(consultations): the consultation purpose's prepare; import contracts (B7d K-5, D53)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/pyproject.toml
```

---

### Task 6: `complete`, the manage-link email and registration (K-6, K-9)

**Files:**
- Modify: `backend/etqan/consultations/services/purpose.py`, `backend/etqan/consultations/apps.py`, `backend/etqan/consultations/services/__init__.py`
- Create: `backend/etqan/consultations/services/notices.py`
- Test: `backend/etqan/consultations/tests/test_purpose_complete.py` (new)

**Interfaces:**
- Consumes: Task 5's `slot_gone`; `billing.services.record_link_payment(*, student_id, customer_name, customer_email, customer_phone, amount_minor, fee_minor, currency, method, transaction_number, notes) -> Payment`; `identity.services.send_notice(to, subject, body, *, language)`; Task 4's `manage_url`.
- Produces:
  - `purpose.complete(done: CompletedCheckout) -> Applied` with reasons, in order: `reference_missing`, `request_paid`, `request_cancelled`, `not_bookable`, `currency_mismatch`, `slot_taken`; billing refusals `already_recorded` or `Applied(ok=False)`; a second teacher change raises `ConflictError(code="consultations.request_changed")`;
  - `purpose.register()` (called in `ConsultationsConfig.ready()`), `public=True`;
  - `notices.manage_link_email(row) -> tuple[str, str]`, `notices.send_manage_link(request_id: int) -> None` (export `send_manage_link`).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_purpose_complete.py`:

```python
import uuid
from datetime import date
from datetime import timedelta

import pytest
from django.db import IntegrityError
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.billing.models import Payment
from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.services import common
from etqan.consultations.services import notices
from etqan.consultations.services import purpose
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import SUNDAY_NOON
from etqan.consultations.tests.conftest import book_one
from etqan.gateways import services as gateways_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
Applied = gateways_services.Applied
LATER = SUNDAY_NOON + timedelta(minutes=31)


def done(row, **extra):
    fields = {
        "id": uuid.uuid4(),
        "purpose": "consultation",
        "reference_id": row.pk,
        "provider": "stripe",
        "amount_minor": 1500,
        "fee_minor": 75,
        "currency": "USD",
        "transaction_number": "pi_1",
        "completed_at": timezone.now(),
        **extra,
    }
    return gateways_services.CompletedCheckout(**fields)


@pytest.fixture
def mailbox(monkeypatch):
    sent = []

    def send(to, subject, body, *, language):
        sent.append((to, subject, body, language))

    monkeypatch.setattr(identity_services, "send_notice", send)
    return sent


def fill(online):
    book_one(online, ip="1.1.1.1", email="a@x.test")
    book_one(online, ip="1.1.1.2", email="b@x.test")


def test_a_visitors_payment_is_recorded_and_the_link_emailed(
    online, mailbox, django_capture_on_commit_callbacks
):
    row = book_one(online, name="Zed Visitor", notes="Please call me at midnight")
    with django_capture_on_commit_callbacks(execute=True):
        assert purpose.complete(done(row)) == Applied(ok=True)
    pay = Payment.objects.get()
    assert (
        pay.customer_type,
        pay.student_id,
        pay.customer_name,
        pay.customer_email,
        pay.customer_phone,
    ) == ("unregistered", None, "Zed Visitor", "sara@x.test", "+201000000009")
    assert (
        pay.amount_minor,
        pay.fee_minor,
        pay.currency,
        pay.method,
        pay.transaction_number,
        pay.notes,
    ) == (1500, 75, "USD", "stripe", "pi_1", f"Consultation CR-{row.pk:06d}")
    row.refresh_from_db()
    assert (
        row.paid_method,
        row.payment_id,
        row.amount_minor,
        row.fee_minor,
        row.currency,
        row.transaction_number,
        row.paid_on,
        row.hold_until,
        row.status,
    ) == ("stripe", pay.pk, 1500, 75, "USD", "pi_1", pay.paid_on, None, "pending_review")
    [(to, subject, body, language)] = mailbox
    assert (to, language) == ("sara@x.test", "en")
    assert services.manage_url(row) in body
    assert "Placement" in body
    assert "استشارة" in body
    assert "2026-10-12 19:00 (Asia/Riyadh)" in body
    for booker_text in ("Zed Visitor", "at midnight"):
        assert booker_text not in body
        assert booker_text not in subject


def test_a_students_payment_names_the_student_and_sends_no_email(
    online, mailbox, django_capture_on_commit_callbacks
):
    row = book_one(online, user=online.student)
    with django_capture_on_commit_callbacks(execute=True):
        assert purpose.complete(done(row)).ok
    pay = Payment.objects.get()
    assert (pay.customer_type, pay.student_id) == ("student", online.student_profile.pk)
    assert mailbox == []


def test_an_email_consultations_link_has_no_time(online):
    email = services.create_product(
        name_ar="سؤال",
        name_en="Written",
        description_en="d",
        price_minor=2000,
        currency="USD",
        duration_minutes=30,
        validity_days=7,
        delivery_mode="email",
        teacher_user_ids=[online.teacher.pk],
    )
    row = book_one(online, product_id=email.pk, starts_at=None, language="ar")
    subject, body = notices.manage_link_email(row)
    assert "Written" in body
    assert "Time:" not in body
    assert subject == notices.SUBJECT


def test_second_checkout_is_request_paid(online):
    row = book_one(online)
    assert purpose.complete(done(row)).ok
    again = purpose.complete(done(row, transaction_number="pi_2"))
    assert again == Applied(ok=False, reason="request_paid")
    assert Payment.objects.count() == 1


def test_a_cancelled_request_records_nothing(online):
    row = book_one(online)
    services.cancel(row, by=online.admin)
    assert purpose.complete(done(row)) == Applied(ok=False, reason="request_cancelled")
    assert not Payment.objects.exists()


def test_a_closed_product_records_nothing(online):
    row = book_one(online)
    services.update_product(online.product, status="archived")
    assert purpose.complete(done(row)) == Applied(ok=False, reason="not_bookable")
    assert not Payment.objects.exists()


def test_currency_mismatch_and_missing(online):
    row = book_one(online)
    assert purpose.complete(done(row, currency="EUR")).reason == "currency_mismatch"
    Request.objects.filter(pk=row.pk).delete()
    assert purpose.complete(done(row)).reason == "reference_missing"


def test_a_payment_inside_the_hold_is_recorded(online):
    row = book_one(online)
    book_one(online, ip="1.1.1.1", email="a@x.test")  # now full, row included
    assert purpose.complete(done(row)).ok


def test_late_payment_with_room_is_recorded(online, frozen):
    row = book_one(online)
    frozen(SUNDAY_NOON + timedelta(hours=2))
    assert purpose.complete(done(row)).ok


def test_late_payment_for_a_taken_place_is_slot_taken(online, frozen):
    row = book_one(online)
    frozen(LATER)
    fill(online)
    assert purpose.complete(done(row)) == Applied(ok=False, reason="slot_taken")
    assert not Payment.objects.exists()
    row.refresh_from_db()
    assert not row.paid


def test_transaction_clash_is_already_recorded(online):
    row = book_one(online)
    Payment.objects.create(
        customer_type="unregistered",
        customer_name="X",
        amount_minor=1,
        currency="USD",
        method="stripe",
        transaction_number="pi_1",
        paid_on=date(2026, 10, 1),
    )
    assert purpose.complete(done(row)).reason == "already_recorded"
    row.refresh_from_db()
    assert not row.paid


def test_integrity_race_is_already_recorded(online, monkeypatch):
    row = book_one(online)

    class Diag:
        constraint_name = "billing_payment_transaction_unique"

    def boom(**kw):
        cause = Exception()
        cause.diag = Diag()
        err = IntegrityError("dup")
        err.__cause__ = cause
        raise err

    monkeypatch.setattr(billing_services, "record_link_payment", boom)
    assert purpose.complete(done(row)).reason == "already_recorded"


def test_other_integrity_error_propagates(online, monkeypatch):
    row = book_one(online)

    def boom(**kw):
        raise IntegrityError("other")

    monkeypatch.setattr(billing_services, "record_link_payment", boom)
    with pytest.raises(IntegrityError):
        purpose.complete(done(row))


def test_other_billing_refusal_is_attention(online, monkeypatch):
    row = book_one(online)

    def refuse(**kw):
        raise ValidationError("bad", field="customer_email")

    monkeypatch.setattr(billing_services, "record_link_payment", refuse)
    assert purpose.complete(done(row)) == Applied(ok=False)
    row.refresh_from_db()
    assert not row.paid


def test_teacher_lock_then_the_row(online):
    row = book_one(online)
    with CaptureQueriesContext(connection) as ctx:
        purpose.complete(done(row))
    sql = [q["sql"] for q in ctx.captured_queries]
    lock = next(i for i, s in enumerate(sql) if "consultations.teacher." in s)
    row_lock = next(
        i for i, s in enumerate(sql) if "FOR UPDATE" in s and "consultations_request" in s
    )
    assert lock < row_lock


def test_a_reassigned_teacher_is_locked_again(online, monkeypatch):
    row = book_one(online)
    seen = []
    real = common.lock_teacher

    def spy(pk):
        seen.append(pk)
        if len(seen) == 1:  # the office reassigns between the read and the lock
            Request.objects.filter(pk=row.pk).update(teacher=online.teacher2_profile)
        real(pk)

    monkeypatch.setattr(common, "lock_teacher", spy)
    assert purpose.complete(done(row)).ok
    assert seen == [online.teacher_profile.pk, online.teacher2_profile.pk]


def test_a_teacher_changed_twice_is_left_to_the_providers_retry(online, monkeypatch):
    row = book_one(online)
    order = [online.teacher2_profile, online.teacher_profile]
    real = common.lock_teacher

    def spy(pk):
        Request.objects.filter(pk=row.pk).update(teacher=order.pop(0))
        real(pk)

    monkeypatch.setattr(common, "lock_teacher", spy)
    with pytest.raises(ConflictError) as caught:
        purpose.complete(done(row))
    assert caught.value.code == "consultations.request_changed"
    assert not Payment.objects.exists()


def test_registered_as_a_public_purpose():
    handler = gateways_services.purpose_named("consultation")
    assert (handler.prepare, handler.complete) == (purpose.prepare, purpose.complete)
    assert gateways_services.is_public_purpose("consultation")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_purpose_complete.py -q`
Expected: FAIL with `ImportError: cannot import name 'notices'`.

- [ ] **Step 3: The manage-link email**

`backend/etqan/consultations/services/notices.py`:

```python
"""Slice B7d K-9 (B7-9): the manage-link email, the one notice B7 sends
itself. A fixed bilingual template: the product's names (office text), the
time on the booker's clock and the link. It carries no booker-supplied
text, so the booking form cannot relay mail."""

from zoneinfo import ZoneInfo

from etqan.consultations.models import Request
from etqan.consultations.services.booking import manage_url
from etqan.identity import services as identity_services

SUBJECT = "Your consultation booking · حجز استشارتك"


def _when(row) -> str:
    if row.starts_at is None:
        return ""
    local = row.starts_at.astimezone(ZoneInfo(row.timezone))
    return f"{local:%Y-%m-%d %H:%M} ({row.timezone})"


def manage_link_email(row) -> tuple[str, str]:
    when, url = _when(row), manage_url(row)
    en = [
        "Your consultation is booked and paid. The academy will confirm it soon.",
        f"Consultation: {row.product.name_en}",
    ]
    ar = [
        "تم حجز استشارتك ودفع ثمنها، وستؤكدها الأكاديمية قريبًا.",
        f"الاستشارة: {row.product.name_ar}",
    ]
    if when:
        en.append(f"Time: {when}")
        ar.append(f"الموعد: {when}")
    en.append(f"Manage your booking: {url}")
    ar.append(f"إدارة الحجز: {url}")
    return SUBJECT, "\n".join([*en, "", *ar])


def send_manage_link(request_id: int) -> None:
    row = (
        Request.objects.select_related("product")
        .filter(pk=request_id, self_booked=True)
        .first()
    )
    if row is None or not row.manage_token:
        return
    subject, body = manage_link_email(row)
    identity_services.send_notice(row.email, subject, body, language=row.language)
```

- [ ] **Step 4: `complete` and registration**

Append to `backend/etqan/consultations/services/purpose.py` (the imports go to the top of the module):

```python
import logging

from django.db import IntegrityError
from django.db import transaction

from etqan.billing import services as billing_services
from etqan.consultations.services import notices
from etqan.platform.exceptions import ValidationError

TRANSACTION_UNIQUE = "billing_payment_transaction_unique"
NAME_MAX, PHONE_MAX = 120, 30
Applied = gateways_services.Applied
logger = logging.getLogger(__name__)


def _record(row, done) -> Applied:
    """One inner block: the billing record and the request's paid fields
    move together, or neither does (B7-4)."""
    try:
        with transaction.atomic():
            payment = billing_services.record_link_payment(
                student_id=row.student_id,  # the StudentProfile pk, or None
                customer_name=row.name[:NAME_MAX],
                customer_email=row.email,
                customer_phone=row.whatsapp[:PHONE_MAX],
                amount_minor=done.amount_minor,
                fee_minor=done.fee_minor,
                currency=done.currency,
                method=done.provider,
                transaction_number=done.transaction_number,
                notes=f"Consultation {row.reference}",
            )
            row.paid_method, row.payment = done.provider, payment
            row.amount_minor, row.fee_minor = done.amount_minor, done.fee_minor
            row.currency = done.currency
            row.transaction_number = done.transaction_number
            row.paid_on, row.hold_until = payment.paid_on, None
            row.save(
                update_fields=[
                    "paid_method",
                    "payment",
                    "amount_minor",
                    "fee_minor",
                    "currency",
                    "transaction_number",
                    "paid_on",
                    "hold_until",
                ]
            )
    except ValidationError as exc:
        if exc.field == "transaction_number":
            return Applied(ok=False, reason="already_recorded")
        # Money already paid that billing refuses: attention, never a webhook
        # 500 the provider retries forever. Logged by field only (no PII).
        logger.warning("consultation %s not recorded: refused on %s", done.id, exc.field)
        return Applied(ok=False)
    except IntegrityError as exc:
        diag = getattr(exc.__cause__, "diag", None)
        if getattr(diag, "constraint_name", None) != TRANSACTION_UNIQUE:
            raise
        return Applied(ok=False, reason="already_recorded")
    if row.created_by_id is None:  # K-9: a visitor; a family sees its pages
        pk = row.pk
        transaction.on_commit(lambda: notices.send_manage_link(pk))
    return Applied(ok=True)


def _settle(row, done) -> Applied:
    if row.paid:
        return Applied(ok=False, reason="request_paid")
    if row.status == Request.Status.CANCELLED:
        return Applied(ok=False, reason="request_cancelled")
    if not row.product.bookable:
        return Applied(ok=False, reason="not_bookable")
    if done.currency != row.price_currency:
        return Applied(ok=False, reason="currency_mismatch")
    if slot_gone(row):
        return Applied(ok=False, reason="slot_taken")
    return _record(row, done)


def complete(done) -> Applied:
    """K-6. gateways' `finish` holds the checkout row; then the teacher's
    lock (the teacher read unlocked first), then the request row. A teacher
    reassigned in between is locked again once; twice, the provider's event
    fails and is retried later ([assumed]). The request stays under review
    for the office (FLOW-009)."""
    for _attempt in range(2):
        teacher_id = (
            Request.objects.filter(pk=done.reference_id)
            .values_list("teacher_id", flat=True)
            .first()
        )
        if teacher_id is None:
            return Applied(ok=False, reason="reference_missing")
        with transaction.atomic():
            common.lock_teacher(teacher_id)
            row = (
                Request.objects.select_for_update(of=("self",))
                .select_related("product")
                .filter(pk=done.reference_id)
                .first()
            )
            if row is None:
                return Applied(ok=False, reason="reference_missing")
            if row.teacher_id == teacher_id:
                return _settle(row, done)
    raise ConflictError(
        "This request changed; try again.", code="consultations.request_changed"
    )


def register() -> None:
    gateways_services.register_purpose(
        NAME, prepare=prepare, complete=complete, public=True
    )
```

`backend/etqan/consultations/apps.py`:

```python
from django.apps import AppConfig


class ConsultationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.consultations"

    def ready(self):
        from etqan.consultations.services import purpose  # noqa: PLC0415

        purpose.register()
```

In `services/__init__.py`, export `send_manage_link` from `notices` (sorted).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `B pytest etqan/consultations etqan/gateways -q`
Expected: PASS (gateways' own suite is unaffected by one more registered purpose).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/consultations/services/purpose.py etqan/consultations/services/notices.py \
  etqan/consultations/services/__init__.py etqan/consultations/apps.py \
  etqan/consultations/tests/test_purpose_complete.py
git -C backend commit -m "feat(consultations): complete records the payment in billing and emails the manage link (B7d K-6, K-9)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Starting and restarting payment, end to end through the simulator (K-4, K-10)

**Files:**
- Create: `backend/etqan/consultations/services/paying.py`
- Modify: `backend/etqan/consultations/services/__init__.py`
- Test: `backend/etqan/consultations/tests/test_paying.py` (new)

**Interfaces:**
- Consumes: Task 5's `NAME`, `not_payable`, `slot_taken`; Task 3's `bookable_product`; `gateways.services.start_checkout(purpose, reference_id, provider, *, user, params)`, `providers_for(currency, amount_minor, *, add_fee)`.
- Produces (exported from `services`):
  - `require_provider(product_id, provider) -> None` (400 `product` / `provider`);
  - `providers_for_product(product) -> list[str]` (the live price), `providers_for_request(row) -> list[str]` (the snapshot);
  - `rehold(row) -> Request` (atomic; locks booker → teacher → row only when the hold has expired);
  - `start_payment(row, provider, *, user) -> StartedCheckout` (not atomic; `params={"token": <the row's token>}`).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_paying.py`:

```python
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.billing import services as billing_services
from etqan.billing.models import Payment
from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.services import common
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import SUNDAY_NOON
from etqan.consultations.tests.conftest import book_one
from etqan.gateways import services as gateways_services
from etqan.gateways.models import Checkout
from etqan.gateways.services.captures import still_payable
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)
LATER = SUNDAY_NOON + timedelta(minutes=31)


def fill(online, start=MONDAY_4PM):
    book_one(online, starts_at=start, ip="1.1.1.1", email="a@x.test")
    book_one(online, starts_at=start, ip="1.1.1.2", email="b@x.test")


def _code(fn):
    with pytest.raises(ConflictError) as caught:
        fn()
    return caught.value.code


def test_start_payment_starts_a_public_checkout(online, stripe_on):
    row = book_one(online)
    started = services.start_payment(row, "stripe", user=None)
    c = Checkout.objects.get(pk=started.id)
    assert (c.purpose, c.reference_id, c.created_by, c.amount_minor, c.fee_minor) == (
        "consultation",
        row.pk,
        None,
        1500,
        0,
    )
    assert c.description == f"Consultation CR-{row.pk:06d}"


def test_a_signed_in_booker_is_the_checkouts_creator(online, stripe_on):
    row = book_one(online, user=online.student)
    started = services.start_payment(row, "stripe", user=online.student)
    assert Checkout.objects.get(pk=started.id).created_by == online.student


def test_the_snapshot_fee_applies_whatever_the_academy_switch(online, stripe_on):
    gateways_services.update_settings(fee={"enabled": False}, by=None)
    services.update_product(online.product, fee_enabled=True)
    row = book_one(online)
    started = services.start_payment(row, "stripe", user=None)
    expected = gateways_services.fee_for(1500, "USD", add_fee=True, use_switch=False)
    assert started.fee_minor == expected
    assert expected > 0


def test_require_provider_and_providers_for_request(online, stripe_on):
    services.require_provider(online.product.pk, "stripe")
    with pytest.raises(ValidationError) as caught:
        services.require_provider(online.product.pk, "paypal")  # not configured
    assert caught.value.field == "provider"
    with pytest.raises(ValidationError) as caught:
        services.require_provider(999999, "stripe")
    assert caught.value.field == "product"
    assert services.providers_for_product(online.product) == ["stripe"]
    assert services.providers_for_request(book_one(online)) == ["stripe"]


def test_pay_within_the_hold_keeps_it(online):
    row = book_one(online)
    assert services.rehold(row).hold_until == SUNDAY_NOON + common.HOLD


def test_pay_after_the_hold_holds_again_when_there_is_room(online, frozen):
    row = book_one(online)
    later = SUNDAY_NOON + timedelta(hours=1)
    frozen(later)
    assert services.rehold(row).hold_until == later + common.HOLD
    row.refresh_from_db()
    assert row.hold_until == later + common.HOLD


def test_pay_after_the_hold_refuses_a_taken_or_too_close_start(online, frozen):
    row = book_one(online)
    frozen(LATER)
    fill(online)
    assert _code(lambda: services.rehold(row)) == "consultations.slot_taken"
    other = book_one(online, starts_at=MONDAY_4PM + HALF, ip="3.3.3.3", email="c@x.test")
    frozen(MONDAY_4PM + HALF - timedelta(hours=11))  # 11 h before its start
    assert _code(lambda: services.rehold(other)) == "consultations.slot_taken"


def test_pay_refuses_a_paid_or_moved_on_request(online):
    row = book_one(online)
    Request.objects.filter(pk=row.pk).update(paid_method="stripe")
    assert _code(lambda: services.rehold(row)) == "consultations.not_payable"
    other = book_one(online, starts_at=MONDAY_4PM + HALF)
    Request.objects.filter(pk=other.pk).update(status="cancelled")
    assert _code(lambda: services.rehold(other)) == "consultations.not_payable"


def test_rehold_locks_booker_then_teacher_then_the_row(online, frozen):
    row = book_one(online)
    frozen(LATER)
    with CaptureQueriesContext(connection) as ctx:
        services.rehold(row)
    sql = [q["sql"] for q in ctx.captured_queries]
    booker = next(i for i, s in enumerate(sql) if "consultations.booker." in s)
    teacher = next(i for i, s in enumerate(sql) if "consultations.teacher." in s)
    row_lock = next(
        i for i, s in enumerate(sql) if "FOR UPDATE" in s and "consultations_request" in s
    )
    assert booker < teacher < row_lock


@pytest.mark.parametrize("provider", ["stripe", "paypal"])
def test_simulated_payment_records_the_booking(  # noqa: PLR0913 -- fixtures
    online, stripe_on, paypal_on, provider
):
    services.update_product(online.product, fee_enabled=True)
    row = book_one(online)
    started = services.start_payment(row, provider, user=None)
    assert gateways_services.simulate(started.id, "pay", user=None) == "completed"
    checkout = Checkout.objects.get(pk=started.id)
    assert (checkout.applied, checkout.attention) == (True, "")
    pay = Payment.objects.get()
    row.refresh_from_db()
    assert (row.paid_method, row.payment_id, row.fee_minor) == (
        provider,
        pay.pk,
        checkout.fee_minor,
    )
    first = pay.paid_on.replace(day=1)
    following = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    usd = next(
        r for r in billing_services.revenue_between(first, following) if r["currency"] == "USD"
    )
    assert usd["amount_minor"] == 1500 + checkout.fee_minor
    assert checkout.fee_minor > 0


def test_a_redelivered_event_records_once(online, stripe_on):
    row = book_one(online)
    started = services.start_payment(row, "stripe", user=None)
    for _ in range(2):
        gateways_services.simulate(started.id, "pay", user=None)
    checkout = Checkout.objects.get(pk=started.id)
    assert (checkout.applied, checkout.attention) == (True, "")
    assert Payment.objects.count() == 1


def test_paypal_recheck_refuses_once_the_place_is_taken(online, paypal_on, frozen):
    row = book_one(online)
    started = services.start_payment(row, "paypal", user=None)
    checkout = Checkout.objects.get(pk=started.id)
    assert still_payable(checkout) is True
    frozen(LATER)
    fill(online)
    assert still_payable(checkout) is False
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_paying.py -q`
Expected: FAIL with `AttributeError: module 'etqan.consultations.services' has no attribute 'start_payment'`.

- [ ] **Step 3: Implement**

`backend/etqan/consultations/services/paying.py`:

```python
"""Slice B7d K-4, K-10: starting a booking's checkout, first from the
booking and again from the manage page. The hold is renewed (under the
booker's and the teacher's locks) only once it has run out."""

from django.db import transaction

from etqan.consultations.models import Request
from etqan.consultations.services import booking
from etqan.consultations.services import common
from etqan.consultations.services.purpose import NAME
from etqan.consultations.services.purpose import not_payable
from etqan.consultations.services.purpose import slot_taken
from etqan.consultations.services.slots import room_left
from etqan.gateways import services as gateways_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError


def providers_for_product(product) -> list[str]:
    return gateways_services.providers_for(
        product.currency, product.price_minor, add_fee=product.fee_enabled
    )


def require_provider(product_id, provider) -> None:
    """A provider that can take this product's price now (else 400)."""
    try:
        product = booking.bookable_product(product_id)
    except NotFoundError:
        raise ValidationError("Choose a consultation.", field="product") from None
    if provider not in providers_for_product(product):
        raise ValidationError(
            "This payment method is not available.", field="provider"
        )


def providers_for_request(row) -> list[str]:
    return gateways_services.providers_for(
        row.price_currency, row.price_minor or 0, add_fee=bool(row.price_fee_enabled)
    )


def _refuse_unpayable(row) -> None:
    if row.paid or row.status != Request.Status.PENDING_REVIEW or not row.self_booked:
        raise not_payable()


@transaction.atomic
def rehold(row) -> Request:
    """K-10: an expired hold is renewed for 30 minutes when its start still
    has room and is at least 12 hours ahead ([assumed]); else slot_taken."""
    current = Request.objects.select_related("product").get(pk=row.pk)
    _refuse_unpayable(current)
    if not common.hold_expired(current):
        return current
    common.lock_booker(current.booked_ip_hash)
    common.lock_teacher(current.teacher_id)
    fresh = (
        Request.objects.select_for_update(of=("self",))
        .select_related("product")
        .get(pk=row.pk)
    )
    _refuse_unpayable(fresh)
    if fresh.teacher_id != current.teacher_id:
        raise ConflictError(
            "This request changed; try again.", code="consultations.request_changed"
        )
    if not common.hold_expired(fresh):
        return fresh
    at = common.now()
    if fresh.starts_at is not None and (
        fresh.starts_at < at + common.LEAD
        or room_left(fresh.product, fresh.teacher_id, fresh.starts_at, exclude_id=fresh.pk)
        <= 0
    ):
        raise slot_taken()
    fresh.hold_until = at + common.HOLD
    fresh.save(update_fields=["hold_until"])
    return fresh


def start_payment(row, provider, *, user):
    """K-4: not atomic: the hold commits before the provider is called (D10).
    The token comes from the row, never from the caller (D28)."""
    fresh = rehold(row)
    return gateways_services.start_checkout(
        NAME, fresh.pk, provider, user=user, params={"token": fresh.manage_token}
    )
```

In `services/__init__.py`, export `providers_for_product`, `providers_for_request`, `rehold`, `require_provider`, `start_payment` (sorted).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `B pytest etqan/consultations -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/consultations/services/paying.py etqan/consultations/services/__init__.py \
  etqan/consultations/tests/test_paying.py
git -C backend commit -m "feat(consultations): start and restart a booking's checkout, re-holding its place (B7d K-4, K-10)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Cancelling unpaid holds, every 15 minutes in every academy (K-7)

**Files:**
- Create: `backend/etqan/consultations/services/unpaid.py`, `backend/etqan/consultations/tasks.py`
- Modify: `backend/etqan/consultations/services/__init__.py`, `backend/config/settings/base.py` (**claim**: `CELERY_BEAT_SCHEDULE`)
- Test: `backend/etqan/consultations/tests/test_unpaid.py` (new)

**Interfaces:**
- Consumes: Task 5's `NAME`; `gateways.services.checkouts_queryset()`; `etqan.platform.tenancy.for_each_academy(job, *, name, atomic=True)`.
- Produces:
  - `services.cancel_unpaid() -> int` (one academy; each row in its own transaction, row lock only);
  - `unpaid.STARTING = timedelta(minutes=2)` (equals gateways' `STARTING_FOR`);
  - Celery task `consultations.cancel_unpaid` returning `{schema: "ok"|"failed"}`; beat entry of the same name, `crontab(minute="*/15")`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_unpaid.py`:

```python
import uuid
from datetime import timedelta

import pytest
from django.conf import settings
from django.utils import timezone
from django_tenants.utils import tenant_context

from etqan.consultations import services
from etqan.consultations import tasks
from etqan.consultations.models import Request
from etqan.consultations.services import purpose
from etqan.consultations.services import unpaid
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import SUNDAY_NOON
from etqan.consultations.tests.conftest import book_one
from etqan.consultations.tests.conftest import product_row
from etqan.gateways import services as gateways_services
from etqan.gateways.models import Checkout
from etqan.gateways.services.checkouts import STARTING_FOR
from etqan.identity import services as identity_services

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)
LATER = SUNDAY_NOON + timedelta(minutes=31)


def checkout_for(row, *, status="pending", age=timedelta(minutes=10)):
    c = Checkout.objects.create(
        purpose="consultation",
        reference_id=row.pk,
        provider="stripe",
        amount_minor=1500,
        currency="USD",
        status=status,
    )
    Checkout.objects.filter(pk=c.pk).update(created_at=LATER - age)
    return c


def test_an_expired_unpaid_booking_is_cancelled(online, frozen):
    row = book_one(online)
    frozen(LATER)
    assert services.cancel_unpaid() == 1
    row.refresh_from_db()
    assert (row.status, row.cancel_reason, row.cancelled_at) == (
        "cancelled",
        "unpaid",
        LATER,
    )


def test_live_paid_and_confirmed_bookings_stay(online, frozen):
    live = book_one(online)
    paid = book_one(online, starts_at=MONDAY_4PM + HALF)
    Request.objects.filter(pk=paid.pk).update(paid_method="stripe", hold_until=None)
    kept = book_one(online, starts_at=MONDAY_4PM + 2 * HALF)
    Request.objects.filter(pk=kept.pk).update(status="confirmed")
    assert services.cancel_unpaid() == 0  # live's hold has not run out
    frozen(LATER)
    assert services.cancel_unpaid() == 1
    statuses = dict(Request.objects.values_list("pk", "status"))
    assert (statuses[live.pk], statuses[paid.pk], statuses[kept.pk]) == (
        "cancelled",
        "pending_review",
        "confirmed",
    )


def test_a_checkout_in_flight_keeps_the_booking(online, frozen):
    pending = book_one(online)
    checkout_for(pending)
    starting = book_one(online, starts_at=MONDAY_4PM + HALF)
    checkout_for(starting, status="failed", age=timedelta(minutes=1))
    stale = book_one(online, starts_at=MONDAY_4PM + 2 * HALF)
    checkout_for(stale, status="failed", age=timedelta(minutes=5))
    frozen(LATER)
    assert services.cancel_unpaid() == 1
    statuses = dict(Request.objects.values_list("pk", "status"))
    assert (statuses[pending.pk], statuses[starting.pk], statuses[stale.pk]) == (
        "pending_review",
        "pending_review",
        "cancelled",
    )


def test_starting_matches_gateways():
    assert unpaid.STARTING == STARTING_FOR


def test_a_payment_after_the_cancel_is_attention(online, frozen):
    row = book_one(online)
    frozen(LATER)
    services.cancel_unpaid()
    done = gateways_services.CompletedCheckout(
        id=uuid.uuid4(),
        purpose="consultation",
        reference_id=row.pk,
        provider="stripe",
        amount_minor=1500,
        fee_minor=0,
        currency="USD",
        transaction_number="pi_late",
        completed_at=timezone.now(),
    )
    assert purpose.complete(done).reason == "request_cancelled"


def _other_academys_hold(tenants):
    with tenant_context(tenants.other):
        teacher = identity_services.create_person(
            "teacher", full_name="T", profile={"gender": "male"}, invite=False
        )
        row = Request.objects.create(
            product=product_row(),
            teacher=identity_services.get_teacher_profile(teacher.pk),
            name="n",
            email="n@x.test",
            whatsapp="1",
            timezone="UTC",
            self_booked=True,
            hold_until=SUNDAY_NOON,
            starts_at=MONDAY_4PM,
            ends_at=MONDAY_4PM + HALF,
        )
    return row.pk


def test_the_job_runs_in_every_academy(online, tenants, frozen):
    mine = book_one(online)
    theirs = _other_academys_hold(tenants)
    frozen(LATER)
    results = tasks.cancel_unpaid()
    assert results[tenants.main.schema_name] == "ok"
    assert results[tenants.other.schema_name] == "ok"
    assert Request.objects.get(pk=mine.pk).status == "cancelled"
    with tenant_context(tenants.other):
        assert Request.objects.get(pk=theirs).status == "cancelled"
    entry = settings.CELERY_BEAT_SCHEDULE["consultations.cancel_unpaid"]
    assert entry["task"] == tasks.cancel_unpaid.name == "consultations.cancel_unpaid"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_unpaid.py -q`
Expected: FAIL with `ImportError: cannot import name 'tasks'`.

- [ ] **Step 3: Implement the service and the task**

`backend/etqan/consultations/services/unpaid.py`:

```python
"""Slice B7d K-7: self-bookings still unpaid when their hold runs out are
cancelled, unless a checkout may still pay them. Each row in its own short
transaction, under its row lock only (never an advisory lock after it)."""

from datetime import timedelta

from django.db import transaction

from etqan.consultations.models import Request
from etqan.consultations.services import common
from etqan.consultations.services.purpose import NAME
from etqan.gateways import services as gateways_services

# gateways' STARTING_FOR: a checkout this young may still be talking to the
# provider (a test keeps the two equal).
STARTING = timedelta(minutes=2)


def _checkout_open(pk, at) -> bool:
    qs = gateways_services.checkouts_queryset().filter(purpose=NAME, reference_id=pk)
    return (
        qs.filter(status="pending").exists()
        or qs.filter(created_at__gt=at - STARTING).exists()
    )


def cancel_unpaid() -> int:
    """K-7, one academy. Only requests still under review ([assumed]): one
    the office confirmed is the office's to cancel."""
    at = common.now()
    candidates = list(
        Request.objects.filter(
            self_booked=True,
            paid_method="",
            status=Request.Status.PENDING_REVIEW,
            hold_until__lte=at,
        ).values_list("pk", flat=True)
    )
    cancelled = 0
    for pk in candidates:
        with transaction.atomic():
            row = Request.objects.select_for_update().filter(pk=pk).first()
            if (
                row is None
                or row.paid
                or row.status != Request.Status.PENDING_REVIEW
                or not common.hold_expired(row)
                or _checkout_open(pk, at)
            ):
                continue
            row.status, row.cancelled_at = Request.Status.CANCELLED, at
            row.cancel_reason = Request.CancelReason.UNPAID
            row.save(update_fields=["status", "cancelled_at", "cancel_reason"])
            cancelled += 1
    return cancelled
```

`backend/etqan/consultations/tasks.py`:

```python
from celery import shared_task

from etqan.consultations import services
from etqan.platform.tenancy import for_each_academy

CANCEL_UNPAID = "consultations.cancel_unpaid"


@shared_task(name=CANCEL_UNPAID, soft_time_limit=600, time_limit=660)
def cancel_unpaid() -> dict[str, str]:
    """K-7: every 15 minutes, in every academy (CLAUDE.md: jobs loop over
    academies). No outer transaction: each row commits on its own."""
    return for_each_academy(services.cancel_unpaid, name=CANCEL_UNPAID, atomic=False)
```

In `services/__init__.py`, export `cancel_unpaid` from `unpaid` (sorted).

- [ ] **Step 4: Run the service tests**

Run: `B pytest etqan/consultations/tests/test_unpaid.py -q`
Expected: every test PASSES except `test_the_job_runs_in_every_academy`, which fails with `KeyError: 'consultations.cancel_unpaid'` (the beat entry, next step).

- [ ] **Step 5: Commit the service and task**

```bash
git -C backend add etqan/consultations/services/unpaid.py etqan/consultations/tasks.py \
  etqan/consultations/services/__init__.py etqan/consultations/tests/test_unpaid.py
git -C backend commit -m "feat(consultations): cancel unpaid self-bookings once their hold runs out (B7d K-7)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: The beat entry (claim `backend/config/settings/base.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/config/settings/base.py --reason "B7d K-7: beat entry consultations.cancel_unpaid"
```

In `CELERY_BEAT_SCHEDULE`, after the `registration.expire_unconfirmed` entry:

```python
    # B7d K-7: every 15 minutes, unpaid self-bookings past their hold are
    # cancelled in every academy.
    "consultations.cancel_unpaid": {
        "task": "consultations.cancel_unpaid",
        "schedule": crontab(minute="*/15"),
    },
```

Run: `B pytest etqan/consultations/tests/test_unpaid.py -q`
Expected: PASS (all).

```bash
git -C backend add config/settings/base.py
git -C backend commit -m "chore(settings): beat consultations.cancel_unpaid every 15 minutes (B7d K-7)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/config/settings/base.py
```

---

### Task 9: The booker's view, the reschedule ask and reviews (K-9…K-13)

**Files:**
- Create: `backend/etqan/consultations/services/manage.py`, `backend/etqan/consultations/services/reviews.py`
- Modify: `backend/etqan/consultations/services/transitions.py` (the office's answer clears the proposal), `backend/etqan/consultations/services/__init__.py`
- Test: `backend/etqan/consultations/tests/test_manage.py`, `backend/etqan/consultations/tests/test_reviews.py` (new)

**Interfaces:**
- Consumes: Task 1's `common.TOKEN_RE`, `common.LEAD`, `Review`; Task 1's `free_slots(..., not_before=)`; B7c's `requests_queryset`, `reschedule`, `decline_reschedule`; `identity.services.get_children(parent_user_id)`; `etqan.platform.permissions.role_of(user)`.
- Produces (exported from `services`):
  - `by_token(token) -> Request` (404 `NotFoundError`; no query unless the token matches `TOKEN_RE` in full; compared with `hmac.compare_digest`);
  - `family_requests(user) -> QuerySet[Request]`, `family_request(user, pk) -> Request`;
  - `last_day(row) -> date | None` (`paid_on + validity_days`);
  - `review_of(row) -> Review | None`, `actions(row, review) -> {"pay": bool, "reschedule": bool, "review": bool}`;
  - `ask_reschedule(row, *, starts_at, note="") -> Request` (409 `wrong_status`, `not_reschedulable`, `too_late`; 400 `starts_at`, `note`);
  - `leave_review(row, *, rating, comment="") -> Review` (409 `not_completed`, `already_reviewed`; 400 `rating`, `comment`);
  - `reviews_queryset()`, `filter_reviews(qs, *, status="")`, `get_review(pk) -> Review`, `decide_review(review, *, status, reason="", by) -> Review` (400 `status`, `reason`);
  - `review_summary(product_id) -> {"rating_average": Decimal | None, "rating_count": int, "reviews": [{"rating", "comment", "created_at", "by": "student"|"visitor"}]}` (5 latest approved);
  - `ratings_by_product() -> dict[int, tuple[Decimal | None, int]]` (one query).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_manage.py`:

```python
from datetime import date
from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import SUNDAY_NOON
from etqan.consultations.tests.conftest import book_one
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)
PAID_ON = date(2026, 10, 11)


def paid(row):
    Request.objects.filter(pk=row.pk).update(
        paid_method="stripe", paid_on=PAID_ON, hold_until=None
    )
    return services.get_request(row.pk)


def confirmed(online, **extra):
    return services.confirm(paid(book_one(online, **extra)), by=online.admin)


def completed(online, frozen, **extra):
    row = confirmed(online, **extra)
    frozen(MONDAY_4PM + timedelta(hours=1))
    row = services.record_delivery(
        row,
        student_attendance="present",
        teacher_attendance="present",
        session_status="completed",
    )
    return services.complete(row, by=online.admin)


@pytest.fixture
def movable(online):
    services.update_product(online.product, reschedulable=True)
    return online


def _code(fn):
    with pytest.raises(ConflictError) as caught:
        fn()
    return caught.value.code


def test_by_token_finds_only_its_own_request(online):
    row = book_one(online)
    assert services.by_token(row.manage_token).pk == row.pk
    with pytest.raises(NotFoundError):
        services.by_token("A" * 43)


@pytest.mark.parametrize("token", ["", "short", "A" * 44, "A" * 42 + "/", None, 7])
def test_a_malformed_token_makes_no_query(online, token):
    with CaptureQueriesContext(connection) as ctx, pytest.raises(NotFoundError):
        services.by_token(token)
    assert ctx.captured_queries == []


def test_family_requests_are_scoped(online):
    parent = identity_services.create_person(
        "parent", full_name="Omar", email="omar@x.test", invite=False
    )
    identity_services.link_guardian(parent, online.student)
    stranger = identity_services.create_person("student", full_name="Zaid", invite=False)
    own = book_one(online, user=online.student, ip="7.0.0.1")
    by_parent = book_one(online, user=parent, starts_at=MONDAY_4PM + HALF, ip="7.0.0.2")
    for_child = book_one(
        online,
        user=parent,
        student_user_id=online.student.pk,
        starts_at=MONDAY_4PM + 2 * HALF,
        ip="7.0.0.3",
    )
    other = book_one(online, user=stranger, starts_at=MONDAY_4PM + 3 * HALF, ip="7.0.0.4")

    def ids(user):
        return {r.pk for r in services.family_requests(user)}

    assert ids(online.student) == {own.pk, for_child.pk}
    assert ids(parent) == {own.pk, by_parent.pk, for_child.pk}
    assert ids(stranger) == {other.pk}
    with pytest.raises(NotFoundError):
        services.family_request(online.student, other.pk)
    Request.objects.filter(pk=own.pk).update(status="cancelled", cancel_reason="unpaid")
    assert ids(online.student) == {for_child.pk}


def test_actions_follow_the_state(movable, frozen):
    row = book_one(movable)
    assert services.actions(row, None) == {"pay": True, "reschedule": False, "review": False}
    row = confirmed(movable, starts_at=MONDAY_4PM + HALF)
    assert services.actions(row, None) == {"pay": False, "reschedule": True, "review": False}
    # Booked while it is still Sunday; `completed` then moves the clock to
    # Monday 17:00, when 16:30 has passed (too late to move).
    done = completed(movable, frozen, starts_at=MONDAY_4PM + 2 * HALF)
    assert services.actions(row, None)["reschedule"] is False
    assert services.actions(done, None)["review"] is True
    review = services.leave_review(done, rating=5)
    assert services.review_of(done) == review
    assert services.actions(done, review)["review"] is False


def test_a_booker_asks_to_move_to_an_offered_time(movable):
    row = confirmed(movable)
    moved = services.ask_reschedule(row, starts_at=MONDAY_4PM + HALF, note="Later please")
    assert (
        moved.status,
        moved.proposed_starts_at,
        moved.reschedule_note,
        moved.reschedule_requested_at,
        moved.starts_at,
    ) == ("reschedule_requested", MONDAY_4PM + HALF, "Later please", SUNDAY_NOON, MONDAY_4PM)
    assert services.last_day(moved) == date(2026, 10, 18)


@pytest.mark.parametrize(
    "start",
    [MONDAY_4PM + timedelta(minutes=10), MONDAY_4PM + timedelta(days=7)],
)
def test_the_proposal_must_be_offered_and_within_validity(movable, start):
    row = confirmed(movable)
    with pytest.raises(ValidationError) as caught:
        services.ask_reschedule(row, starts_at=start)
    assert caught.value.field == "starts_at"


def test_reschedule_refusals(movable, online, frozen):
    pending = book_one(movable, starts_at=MONDAY_4PM + HALF)
    assert (
        _code(lambda: services.ask_reschedule(pending, starts_at=MONDAY_4PM))
        == "consultations.wrong_status"
    )
    row = confirmed(movable)
    with pytest.raises(ValidationError) as caught:
        services.ask_reschedule(row, starts_at=MONDAY_4PM + HALF, note="x" * 2001)
    assert caught.value.field == "note"
    services.update_product(online.product, reschedulable=False)
    assert (
        _code(lambda: services.ask_reschedule(row, starts_at=MONDAY_4PM + HALF))
        == "consultations.not_reschedulable"
    )
    services.update_product(online.product, reschedulable=True)
    frozen(MONDAY_4PM - timedelta(hours=11))
    assert (
        _code(lambda: services.ask_reschedule(row, starts_at=MONDAY_4PM + HALF))
        == "consultations.too_late"
    )


def test_the_offices_answer_clears_the_proposal(movable):
    row = services.ask_reschedule(confirmed(movable), starts_at=MONDAY_4PM + HALF)
    row = services.decline_reschedule(row, by=movable.admin)
    assert (row.status, row.proposed_starts_at) == ("confirmed", None)
    row = services.ask_reschedule(row, starts_at=MONDAY_4PM + HALF)
    row, _warnings = services.reschedule(row, starts_at=MONDAY_4PM + HALF, by=movable.admin)
    assert (row.starts_at, row.proposed_starts_at) == (MONDAY_4PM + HALF, None)


def test_one_review_once_complete(online, frozen):
    pending = book_one(online, starts_at=MONDAY_4PM + HALF)
    assert (
        _code(lambda: services.leave_review(pending, rating=5))
        == "consultations.not_completed"
    )
    row = completed(online, frozen)
    review = services.leave_review(row, rating=5, comment="  Helpful  ")
    assert (review.rating, review.comment, review.status) == (5, "Helpful", "pending")
    assert (
        _code(lambda: services.leave_review(row, rating=4))
        == "consultations.already_reviewed"
    )


@pytest.mark.parametrize(
    ("rating", "comment", "field"),
    [(0, "", "rating"), (6, "", "rating"), (True, "", "rating"), (4, "x" * 1001, "comment")],
)
def test_review_fields(online, frozen, rating, comment, field):
    row = completed(online, frozen)
    with pytest.raises(ValidationError) as caught:
        services.leave_review(row, rating=rating, comment=comment)
    assert caught.value.field == field
```

`backend/etqan/consultations/tests/test_reviews.py`:

```python
from datetime import timedelta
from decimal import Decimal

import pytest

from etqan.consultations import services
from etqan.consultations.models import Review
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
HALF = timedelta(minutes=30)


def reviewed(online, n, rating, status="approved", *, visitor=False, comment="c"):
    """A review on the n-th of eight places (four starts x two seats)."""
    extra = {"starts_at": MONDAY_4PM + (n % 4) * HALF}
    if visitor:
        extra |= {
            "student_user_id": None,
            "name": "V",
            "email": "v@x.test",
            "whatsapp": "1",
        }
    return Review.objects.create(
        request=new_request(online, **extra), rating=rating, status=status, comment=comment
    )


def test_none_is_null_and_half_rounds_up(online):
    assert services.review_summary(online.product.pk) == {
        "rating_average": None,
        "rating_count": 0,
        "reviews": [],
    }
    reviewed(online, 0, 5)
    reviewed(online, 1, 4)
    assert services.review_summary(online.product.pk)["rating_average"] == Decimal("4.50")


def test_the_summary_counts_only_approved_reviews(online):
    for n, (rating, status) in enumerate(
        [(5, "approved"), (4, "approved"), (4, "approved"), (1, "rejected"), (2, "pending")]
    ):
        reviewed(online, n, rating, status)
    summary = services.review_summary(online.product.pk)
    assert (summary["rating_average"], summary["rating_count"]) == (Decimal("4.33"), 3)
    assert [r["rating"] for r in summary["reviews"]] == [4, 4, 5]  # latest first
    assert services.ratings_by_product() == {online.product.pk: (Decimal("4.33"), 3)}


def test_five_latest_with_no_names(online):
    for n in range(5):
        reviewed(online, n, 5)
    reviewed(online, 5, 3, visitor=True, comment="From a visitor")
    reviews = services.review_summary(online.product.pk)["reviews"]
    assert len(reviews) == 5
    assert reviews[0] == {
        "rating": 3,
        "comment": "From a visitor",
        "created_at": reviews[0]["created_at"],
        "by": "visitor",
    }
    assert {r["by"] for r in reviews[1:]} == {"student"}
    assert all(set(r) == {"rating", "comment", "created_at", "by"} for r in reviews)


def test_the_office_decides(online):
    review = reviewed(online, 0, 3, "pending")
    out = services.decide_review(review, status="approved", by=online.admin)
    assert (out.status, out.decided_by, out.decided_at is not None) == (
        "approved",
        online.admin,
        True,
    )
    out = services.decide_review(review, status="rejected", reason="  Rude  ", by=online.admin)
    assert (out.status, out.reason) == ("rejected", "Rude")
    with pytest.raises(ValidationError) as caught:
        services.decide_review(review, status="pending", by=online.admin)
    assert caught.value.field == "status"
    with pytest.raises(ValidationError) as caught:
        services.decide_review(review, status="rejected", reason="x" * 501, by=online.admin)
    assert caught.value.field == "reason"
    assert [r.pk for r in services.filter_reviews(services.reviews_queryset(), status="rejected")] == [
        review.pk
    ]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_manage.py etqan/consultations/tests/test_reviews.py -q`
Expected: FAIL with `AttributeError: module 'etqan.consultations.services' has no attribute 'by_token'`.

- [ ] **Step 3: Implement**

`backend/etqan/consultations/services/manage.py`:

```python
"""Slice B7d K-9…K-13: the booker's own view of a request, by token (a
visitor) or by ownership (a family), and what they may do there."""

import hmac
from datetime import date
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db import transaction
from django.db.models import Q

from etqan.consultations.models import Request
from etqan.consultations.models import Review
from etqan.consultations.services import common
from etqan.consultations.services.requests import requests_queryset
from etqan.consultations.services.slots import free_slots
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of

S = Request.Status
NOTE_MAX = 2000  # the reschedule_note column
COMMENT_MAX = 1000


def by_token(token) -> Request:
    """K-9: a malformed token never reaches the database; a found one is
    compared again in constant time, on bytes (as gateways' link_by_token)."""
    row = None
    if isinstance(token, str) and common.TOKEN_RE.fullmatch(token):
        row = requests_queryset().filter(manage_token=token, self_booked=True).first()
    if row is None or not hmac.compare_digest(row.manage_token.encode(), token.encode()):
        raise NotFoundError("Consultation request")
    return row


def family_requests(user):
    """K-13: a student's own requests; a parent's children's and those the
    parent made. Requests the unpaid job cancelled are left out ([assumed])."""
    qs = requests_queryset().exclude(cancel_reason=Request.CancelReason.UNPAID)
    if role_of(user) == "student":
        return qs.filter(student__user_id=user.pk)
    children = list(identity_services.get_children(user.pk).values_list("pk", flat=True))
    return qs.filter(Q(student_id__in=children) | Q(created_by_id=user.pk))


def family_request(user, pk) -> Request:
    row = family_requests(user).filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Consultation request", pk)
    return row


def last_day(row) -> date | None:
    """BR-26: a paid consultation takes place on or before this day."""
    if row.paid_on is None:
        return None
    return row.paid_on + timedelta(days=row.product.validity_days)


def review_of(row) -> Review | None:
    return Review.objects.filter(request_id=row.pk).first()


def _can_reschedule(row) -> bool:
    return (
        row.status == S.CONFIRMED
        and row.product.reschedulable
        and row.starts_at is not None
        and row.starts_at - common.now() >= common.LEAD
    )


def actions(row, review) -> dict:
    """K-10: what the manage page offers. No booker cancellation (§8.4)."""
    return {
        "pay": row.self_booked and not row.paid and row.status == S.PENDING_REVIEW,
        "reschedule": _can_reschedule(row),
        "review": row.status == S.COMPLETED and review is None,
    }


@transaction.atomic
def ask_reschedule(row, *, starts_at, note="") -> Request:
    """K-11 (BR-27): a confirmed, reschedulable request, 12 hours or more
    ahead, to one of K-2's slots within paid_on + validity_days. The
    proposed slot is not held; the office decides (C-6)."""
    fresh = (
        Request.objects.select_for_update(of=("self",))
        .select_related("product", "teacher")
        .get(pk=row.pk)
    )
    if fresh.status != S.CONFIRMED:
        raise ConflictError(
            "This request cannot do that now.", code="consultations.wrong_status"
        )
    if not fresh.product.reschedulable:
        raise ConflictError(
            "This consultation cannot be rescheduled.",
            code="consultations.not_reschedulable",
        )
    at = common.now()
    if fresh.starts_at is None or fresh.starts_at - at < common.LEAD:
        raise ConflictError(
            "It is too late to move this consultation.", code="consultations.too_late"
        )
    note = note or ""
    if len(note) > NOTE_MAX:
        raise ValidationError("Keep the note under 2000 characters.", field="note")
    day = starts_at.astimezone(ZoneInfo(common.academy_zone())).date()
    offered = free_slots(
        fresh.product,
        fresh.teacher.user_id,
        day,
        1,
        request=fresh,
        not_before=at + common.LEAD,
    ).slots
    if starts_at not in {s.starts_at for s in offered}:
        raise ValidationError("Choose one of the offered times.", field="starts_at")
    fresh.status, fresh.proposed_starts_at = S.RESCHEDULE_REQUESTED, starts_at
    fresh.reschedule_requested_at, fresh.reschedule_note = at, note
    fresh.save(
        update_fields=[
            "status",
            "proposed_starts_at",
            "reschedule_requested_at",
            "reschedule_note",
        ]
    )
    return fresh


@transaction.atomic
def leave_review(row, *, rating, comment="") -> Review:
    """K-12: one review per completed request, pending until the office
    decides. Plain text (D2)."""
    fresh = Request.objects.select_for_update().get(pk=row.pk)
    if fresh.status != S.COMPLETED:
        raise ConflictError(
            "Rate a consultation once it is complete.",
            code="consultations.not_completed",
        )
    if Review.objects.filter(request_id=fresh.pk).exists():
        raise ConflictError(
            "You have rated this consultation already.",
            code="consultations.already_reviewed",
        )
    if isinstance(rating, bool) or not isinstance(rating, int) or not 1 <= rating <= 5:
        raise ValidationError("Choose 1 to 5 stars.", field="rating")
    comment = (comment or "").strip()
    if len(comment) > COMMENT_MAX:
        raise ValidationError(
            "Keep the comment under 1000 characters.", field="comment"
        )
    return Review.objects.create(
        request=fresh, rating=rating, comment=comment, created_at=common.now()
    )
```

`backend/etqan/consultations/services/reviews.py`:

```python
"""Slice B7d K-12 (CONS-003, B7-16): the office moderates the bookers'
ratings; the public product shows the approved ones' average, count and
latest comments, attributed only as "student" or "visitor"."""

from decimal import ROUND_HALF_UP
from decimal import Decimal

from django.db import transaction
from django.db.models import Avg
from django.db.models import Count
from django.db.models import DecimalField

from etqan.consultations.models import Review
from etqan.consultations.services import common
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

LATEST = 5
REASON_MAX = 500
TWO = Decimal("0.01")
DECIDED = (Review.Status.APPROVED, Review.Status.REJECTED)
_AVG = Avg("rating", output_field=DecimalField(max_digits=6, decimal_places=4))


def reviews_queryset():
    return Review.objects.select_related(
        "request__product", "request__student__user", "decided_by"
    ).order_by("-created_at", "-id")


def filter_reviews(qs, *, status: str = ""):
    return qs.filter(status=status) if status else qs


def get_review(pk) -> Review:
    row = reviews_queryset().filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Consultation review", pk)
    return row


@transaction.atomic
def decide_review(review, *, status, reason="", by) -> Review:
    if status not in DECIDED:
        raise ValidationError("Approve or reject the review.", field="status")
    reason = (reason or "").strip()
    if len(reason) > REASON_MAX:
        raise ValidationError("Keep the reason under 500 characters.", field="reason")
    fresh = Review.objects.select_for_update().get(pk=review.pk)
    fresh.status, fresh.reason = status, reason
    fresh.decided_by, fresh.decided_at = by, common.now()
    fresh.save(update_fields=["status", "reason", "decided_by", "decided_at"])
    return fresh


def _average(value) -> Decimal | None:
    return None if value is None else Decimal(value).quantize(TWO, ROUND_HALF_UP)


def ratings_by_product() -> dict[int, tuple[Decimal | None, int]]:
    """Every product's approved average and count, in one query."""
    rows = (
        Review.objects.filter(status=Review.Status.APPROVED)
        .values("request__product_id")
        .annotate(avg=_AVG, n=Count("id"))
    )
    return {r["request__product_id"]: (_average(r["avg"]), r["n"]) for r in rows}


def review_summary(product_id) -> dict:
    approved = Review.objects.filter(
        status=Review.Status.APPROVED, request__product_id=product_id
    )
    agg = approved.aggregate(avg=_AVG, n=Count("id"))
    latest = approved.select_related("request").order_by("-created_at", "-id")[:LATEST]
    return {
        "rating_average": _average(agg["avg"]),
        "rating_count": agg["n"],
        "reviews": [
            {
                "rating": r.rating,
                "comment": r.comment,
                "created_at": r.created_at,
                "by": "student" if r.request.student_id else "visitor",
            }
            for r in latest
        ],
    }
```

In `services/transitions.py`, the office's answer clears the booker's proposal:
- in `reschedule`, before `return _save(...)`, add `fresh.proposed_starts_at = None` and add `"proposed_starts_at"` to that `_save` field list;
- `decline_reschedule` becomes:

```python
@transaction.atomic
def decline_reschedule(row, *, note: str = "", by) -> Request:
    fresh = _from(row, S.RESCHEDULE_REQUESTED)
    fresh.status, fresh.reschedule_note = S.CONFIRMED, _note(note)
    fresh.proposed_starts_at = None
    return _save(fresh, "status", "reschedule_note", "proposed_starts_at")
```

In `services/__init__.py`, export from `manage`: `actions`, `ask_reschedule`, `by_token`, `family_request`, `family_requests`, `last_day`, `leave_review`, `review_of`; from `reviews`: `decide_review`, `filter_reviews`, `get_review`, `ratings_by_product`, `review_summary`, `reviews_queryset` (sorted into `__all__`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `B pytest etqan/consultations -q`
Expected: PASS (B7c's transition tests still pass).

- [ ] **Step 5: Commit**

```bash
git -C backend add etqan/consultations/services/manage.py etqan/consultations/services/reviews.py \
  etqan/consultations/services/transitions.py etqan/consultations/services/__init__.py \
  etqan/consultations/tests/test_manage.py etqan/consultations/tests/test_reviews.py
git -C backend commit -m "feat(consultations): manage by token, family scope, reschedule ask and reviews (B7d K-9…K-13)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The public catalogue routes and the throttle scopes (K-2, K-8, K-14)

**Files:**
- Create: `backend/etqan/consultations/api/params.py`, `backend/etqan/consultations/api/booking_serializers.py`, `backend/etqan/consultations/api/public_views.py`
- Modify: `backend/etqan/consultations/api/urls.py`; **claims**: `backend/config/settings/base.py` (`DEFAULT_THROTTLE_RATES`), `backend/etqan/access/tests/test_routes.py` (`SELF_SERVICE`)
- Test: `backend/etqan/consultations/tests/test_api_public.py` (new)

**Interfaces:**
- Consumes: Tasks 3, 7, 9 (`bookable_products`, `bookable_product`, `offered_teachers`, `booking_slots`, `last_bookable_day`, `providers_for_product`, `review_summary`, `ratings_by_product`); `PublicScopedRateThrottle`.
- Produces:
  - `api/params.py`: `client_ip(request) -> str`, `valid(serializer_class, data) -> dict`, `query_day(raw, field="from") -> date | None`;
  - `api/booking_serializers.py`: `teacher_data(profile)`, `public_product_data(product, rating=None)`, `public_detail_data(product, *, teachers, summary, providers)`, `PublicSlotsQuery`, `iso(value)`;
  - `api/public_views.py`: `PublicView` (base: anonymous, `FeatureOn("consultations")`, `PublicScopedRateThrottle`, scope `consultation_public`, `needs_online = True`), `ProductsView`, `ProductView`, `TeachersView`, `SlotsView`;
  - routes `GET public/products/`, `public/products/<id>/`, `public/products/<id>/teachers/`, `public/products/<id>/slots/?teacher=&from=&days=`.
- Payloads:
  - product: `id, name_ar, name_en, description_ar, description_en, price_minor, currency, fee_enabled, duration_minutes, validity_days, participants, delivery_mode, featured, reschedulable, cover_url, rating_average (number|null), rating_count`;
  - detail adds `teachers: [{user_id, full_name, initial, bio}]`, `reviews: [{rating, comment, created_at, by}]`, `providers: ["stripe"|"paypal"]`;
  - slots: `{academy_timezone, last_day, slots: [{starts_at, remaining}]}`.

- [ ] **Step 1: The throttle scopes (claim `backend/config/settings/base.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/config/settings/base.py --reason "B7d K-8: throttle scopes consultation_book, consultation_manage, consultation_public"
```

In `REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]`, after `"recorded_public": "60/minute",`:

```python
        # B7d K-8: self-booking consultations, per IP (my/book: per user).
        "consultation_book": "10/hour",
        "consultation_manage": "60/minute",
        "consultation_public": "60/minute",
```

```bash
git -C backend add config/settings/base.py
git -C backend commit -m "chore(settings): consultation booking throttle scopes (B7d K-8)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/config/settings/base.py
```

- [ ] **Step 2: Write the failing tests**

`backend/etqan/consultations/tests/test_api_public.py`:

```python
import pytest
from rest_framework.test import APIClient

from etqan.consultations import services
from etqan.consultations.models import Review
from etqan.consultations.tests.conftest import new_request

pytestmark = pytest.mark.django_db
P = "/api/v1/consultations/public/products/"
PRODUCT_KEYS = {
    "id",
    "name_ar",
    "name_en",
    "description_ar",
    "description_en",
    "price_minor",
    "currency",
    "fee_enabled",
    "duration_minutes",
    "validity_days",
    "participants",
    "delivery_mode",
    "featured",
    "reschedulable",
    "cover_url",
    "rating_average",
    "rating_count",
}


def test_the_list_is_anonymous_and_whitelisted(online):
    resp = APIClient().get(P)
    assert resp.status_code == 200
    [item] = resp.json()
    assert set(item) == PRODUCT_KEYS
    assert (
        item["id"],
        item["price_minor"],
        item["currency"],
        item["rating_average"],
        item["rating_count"],
    ) == (online.product.pk, 1500, "USD", None, 0)


@pytest.mark.parametrize("switch", ["consultations", "online_payments"])
def test_closed_booking_is_404(online, set_features, switch):
    set_features(**{switch: False})
    for path in (P, f"{P}{online.product.pk}/", f"{P}{online.product.pk}/teachers/"):
        assert APIClient().get(path).status_code == 404, path


def test_the_detail_embeds_teachers_reviews_and_providers(online, stripe_on):
    profile = online.teacher_profile
    profile.bio = "Ijazah in Hafs."
    profile.default_meeting_url = "https://meet.test/secret-room"
    profile.save()
    Review.objects.create(
        request=new_request(online), rating=4, comment="Clear", status="approved"
    )
    data = APIClient().get(f"{P}{online.product.pk}/").json()
    assert set(data) == PRODUCT_KEYS | {"teachers", "reviews", "providers"}
    assert data["teachers"] == [
        {
            "user_id": online.teacher.pk,
            "full_name": "Bilal",
            "initial": "B",
            "bio": "Ijazah in Hafs.",
        }
    ]
    assert (data["rating_average"], data["rating_count"]) == (4.0, 1)
    [review] = data["reviews"]
    assert (review["rating"], review["comment"], review["by"]) == (4, "Clear", "student")
    assert data["providers"] == ["stripe"]
    text = str(data)
    for private in ("secret-room", "Yusuf", "yusuf@x.test"):
        assert private not in text


def test_teachers_route(online):
    data = APIClient().get(f"{P}{online.product.pk}/teachers/").json()
    assert [t["user_id"] for t in data] == [online.teacher.pk]


def test_an_unknown_or_closed_product_is_404(online):
    assert APIClient().get(f"{P}999999/").status_code == 404
    services.update_product(online.product, enabled=False)
    assert APIClient().get(f"{P}{online.product.pk}/").status_code == 404


def test_slots(online):
    resp = APIClient().get(
        f"{P}{online.product.pk}/slots/",
        {"teacher": online.teacher.pk, "from": "2026-10-12", "days": 1},
    )
    assert resp.status_code == 200
    assert resp.json() == {
        "academy_timezone": "UTC",
        "last_day": "2026-10-18",
        "slots": [
            {"starts_at": f"2026-10-12T{t}:00+00:00", "remaining": 2}
            for t in ("16:00", "16:30", "17:00", "17:30")
        ],
    }


@pytest.mark.parametrize(
    ("query", "field"),
    [
        ({}, "teacher"),
        ({"teacher": "x"}, "teacher"),
        ({"days": 0}, "days"),
        ({"days": 32}, "days"),
        ({"from": "12/10/2026"}, "from"),
    ],
)
def test_bad_slot_queries_are_400(online, query, field):
    params = {"teacher": online.teacher.pk, **query} if query else {}
    resp = APIClient().get(f"{P}{online.product.pk}/slots/", params)
    assert (resp.status_code, list(resp.json())) == (400, [field])


def test_public_reads_are_throttled_per_ip(online):
    anon = APIClient()
    codes = [anon.get(P).status_code for _ in range(61)]
    assert codes[:60] == [200] * 60
    assert codes[60] == 429


def test_the_sites_own_calls_are_not_throttled(online, settings):
    settings.TRUST_INTERNAL_HEADER = True
    site = APIClient(HTTP_X_ETQAN_INTERNAL="1")
    assert {site.get(P).status_code for _ in range(65)} == {200}
```

(In the `({"teacher": "x"}, "teacher")` case the helper merges the query over a valid teacher, so `teacher="x"` wins.)

- [ ] **Step 3: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_api_public.py -q`
Expected: FAIL (404 for every route: none exists yet).

- [ ] **Step 4: Implement**

`backend/etqan/consultations/api/params.py`:

```python
"""Small request helpers B7d's routes share."""

from datetime import date

from rest_framework.throttling import BaseThrottle

from etqan.platform.exceptions import ValidationError


def client_ip(request) -> str:
    """DRF's client address, as its throttles see it (NUM_PROXIES=1:
    Caddy's last hop)."""
    return BaseThrottle().get_ident(request) or ""


def valid(serializer_class, data) -> dict:
    ser = serializer_class(data=data)
    ser.is_valid(raise_exception=True)
    return dict(ser.validated_data)


def query_day(raw, field: str = "from") -> date | None:
    if not raw:
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError:
        raise ValidationError("Use a date like 2026-10-12.", field=field) from None
```

`backend/etqan/consultations/api/booking_serializers.py`:

```python
"""Slice B7d: the inputs and payloads of the booking, manage, family and
review routes. Shape only: the services own every rule (and its field)."""

from rest_framework import serializers


def iso(value) -> str | None:
    return value.isoformat() if value else None


def teacher_data(profile) -> dict:
    """K-2: whitelisted; never payout details, birth date or meeting link."""
    name = profile.user.full_name
    return {
        "user_id": profile.user_id,
        "full_name": name,
        "initial": name[:1].upper(),
        "bio": profile.bio,
    }


def _rating(value) -> float | None:
    return None if value is None else float(value)


def public_product_data(p, rating=None) -> dict:
    average, count = rating or (None, 0)
    return {
        "id": p.pk,
        "name_ar": p.name_ar,
        "name_en": p.name_en,
        "description_ar": p.description_ar,
        "description_en": p.description_en,
        "price_minor": p.price_minor,
        "currency": p.currency,
        "fee_enabled": p.fee_enabled,
        "duration_minutes": p.duration_minutes,
        "validity_days": p.validity_days,
        "participants": p.participants,
        "delivery_mode": p.delivery_mode,
        "featured": p.featured,
        "reschedulable": p.reschedulable,
        "cover_url": p.cover.url if p.cover else "",
        "rating_average": _rating(average),
        "rating_count": count,
    }


def public_detail_data(p, *, teachers, summary, providers) -> dict:
    """K-12, K-14: the approved reviews, by "student" or "visitor" only."""
    rating = (summary["rating_average"], summary["rating_count"])
    return {
        **public_product_data(p, rating),
        "teachers": [teacher_data(t) for t in teachers],
        "reviews": [
            {**r, "created_at": iso(r["created_at"])} for r in summary["reviews"]
        ],
        "providers": providers,
    }


class PublicSlotsQuery(serializers.Serializer):
    teacher = serializers.IntegerField(min_value=1)
    # "from" is a Python keyword: the view reads it with `query_day`.
    days = serializers.IntegerField(min_value=1, max_value=31, default=7)
```

`backend/etqan/consultations/api/public_views.py`:

```python
"""Slice B7d K-2, K-14 (Task 11 adds K-3, K-10…K-12): the anonymous routes.
No authentication: no session is read, so no CSRF and no quick-login
session to refuse (ruling M2). Per-IP throttles that skip the marketing
site's own calls (D65). 404 while K-1's switches are off."""

from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.consultations import services
from etqan.consultations.api import booking_serializers as s
from etqan.consultations.api.params import query_day
from etqan.consultations.api.params import valid
from etqan.consultations.services import common
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.platform.throttling import PublicScopedRateThrottle


class PublicView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny, FeatureOn]
    feature = "consultations"
    throttle_classes = [PublicScopedRateThrottle]
    throttle_scope = "consultation_public"
    http_method_names = ["get", "options"]
    # K-1: the catalogue, the slots and booking also need paying online.
    needs_online = True

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if self.needs_online and not features.enabled("online_payments"):
            raise NotFoundError("Consultation")


class ProductsView(PublicView):
    def get(self, request):
        ratings = services.ratings_by_product()
        return Response(
            [
                s.public_product_data(p, ratings.get(p.pk))
                for p in services.bookable_products()
            ]
        )


class ProductView(PublicView):
    def get(self, request, pk):
        product = services.bookable_product(pk)
        return Response(
            s.public_detail_data(
                product,
                teachers=services.offered_teachers(product),
                summary=services.review_summary(product.pk),
                providers=services.providers_for_product(product),
            )
        )


class TeachersView(PublicView):
    def get(self, request, pk):
        product = services.bookable_product(pk)
        return Response([s.teacher_data(t) for t in services.offered_teachers(product)])


class SlotsView(PublicView):
    def get(self, request, pk):
        product = services.bookable_product(pk)
        q = valid(s.PublicSlotsQuery, request.query_params)
        start = query_day(request.query_params.get("from"))
        slots = services.booking_slots(product, q["teacher"], start, q["days"])
        return Response(
            {
                "academy_timezone": common.academy_zone(),
                "last_day": services.last_bookable_day(product).isoformat(),
                "slots": [
                    {"starts_at": x.starts_at.isoformat(), "remaining": x.remaining}
                    for x in slots
                ],
            }
        )
```

In `backend/etqan/consultations/api/urls.py`, add `from etqan.consultations.api import public_views as pv` and these patterns before `products/`:

```python
    path("public/products/", pv.ProductsView.as_view()),
    path("public/products/<int:pk>/", pv.ProductView.as_view()),
    path("public/products/<int:pk>/teachers/", pv.TeachersView.as_view()),
    path("public/products/<int:pk>/slots/", pv.SlotsView.as_view()),
```

- [ ] **Step 5: Name the new views as exempt (claim `backend/etqan/access/tests/test_routes.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/tests/test_routes.py --reason "B7d: SELF_SERVICE lines for the public consultation catalogue"
```

In `SELF_SERVICE`, after the B7c/B7b lines, add:

```python
    # Phase B7, slice B7d
    "etqan.consultations.api.public_views.ProductsView": (
        "the public site (consultations); anonymous, throttled per IP"
    ),
    "etqan.consultations.api.public_views.ProductView": (
        "the public site (consultations); anonymous, throttled per IP"
    ),
    "etqan.consultations.api.public_views.TeachersView": (
        "the public booking wizard; anonymous, throttled per IP"
    ),
    "etqan.consultations.api.public_views.SlotsView": (
        "the public booking wizard; anonymous, throttled per IP"
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `B pytest etqan/consultations etqan/access/tests/test_routes.py etqan/platform/tests -q`
Expected: PASS.

- [ ] **Step 7: Commit (then release the claim)**

```bash
git -C backend add etqan/consultations/api/params.py etqan/consultations/api/booking_serializers.py \
  etqan/consultations/api/public_views.py etqan/consultations/api/urls.py \
  etqan/consultations/tests/test_api_public.py etqan/access/tests/test_routes.py
git -C backend commit -m "feat(consultations): public catalogue, teachers and slots routes (B7d K-2, K-14)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/tests/test_routes.py
```

---

### Task 11: The public booking and manage routes (K-3, K-4, K-10…K-12)

**Files:**
- Create: `backend/etqan/consultations/api/answers.py`
- Modify: `backend/etqan/consultations/api/booking_serializers.py`, `backend/etqan/consultations/api/public_views.py`, `backend/etqan/consultations/api/urls.py`, `backend/etqan/consultations/tests/conftest.py` (`MANAGE_KEYS`, `book_body`); **claim**: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/consultations/tests/test_api_manage.py` (new)

**Interfaces:**
- Consumes: Tasks 4, 7, 9 (`book`, `manage_url`, `ip_hash`, `require_provider`, `start_payment`, `providers_for_request`, `by_token`, `actions`, `review_of`, `last_day`, `ask_reschedule`, `leave_review`).
- Produces:
  - `api/answers.py`: `manage_answer(row) -> dict`, `family_answer(row) -> dict` (used by Task 12), `book_answer(request, v, *, user, student=None) -> dict`;
  - `booking_serializers`: `BookInput`, `ProviderInput`, `AskRescheduleInput`, `ReviewInput`, `manage_data(row, *, actions, providers, review, last_day, zone)`, `started_data(started)`;
  - routes `POST public/book/` (scope `consultation_book`, non-atomic), `GET public/manage/<token>/`, `POST public/manage/<token>/pay/` (non-atomic), `POST …/reschedule/`, `POST …/review/` (scope `consultation_manage`);
  - book answer `{request: {id, manage_url}, checkout: {id, redirect_url, amount_minor, fee_minor, currency} | null}`;
  - manage payload keys `MANAGE_KEYS = {reference, status, product, teacher, timezone, academy_timezone, starts_at, ends_at, proposed_starts_at, meeting_url, hold_until, payment, last_day, providers, actions, review}`.

- [ ] **Step 1: Write the failing tests**

Add to `backend/etqan/consultations/tests/conftest.py`:

```python
MANAGE_KEYS = {
    "reference",
    "status",
    "product",
    "teacher",
    "timezone",
    "academy_timezone",
    "starts_at",
    "ends_at",
    "proposed_starts_at",
    "meeting_url",
    "hold_until",
    "payment",
    "last_day",
    "providers",
    "actions",
    "review",
}


def book_body(b, **extra):
    """The booking wizard's body for `book_one`'s booking."""
    return {
        "product": b.product.pk,
        "teacher": b.teacher.pk,
        "starts_at": MONDAY_4PM.isoformat(),
        "name": "Sara",
        "email": "sara@x.test",
        "whatsapp": "+201000000009",
        "timezone": "Asia/Riyadh",
        "notes": "",
        "provider": "stripe",
        "language": "en",
        **extra,
    }
```

`backend/etqan/consultations/tests/test_api_manage.py`:

```python
from datetime import date
from datetime import timedelta

import pytest
from rest_framework.test import APIClient

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import MANAGE_KEYS
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import book_body
from etqan.consultations.tests.conftest import book_one
from etqan.gateways import services as gateways_services
from etqan.gateways.models import Checkout
from etqan.platform.exceptions import ExternalServiceError

pytestmark = pytest.mark.django_db
B = "/api/v1/consultations/public/book/"
M = "/api/v1/consultations/public/manage/"
HALF = timedelta(minutes=30)


def test_a_visitor_books_and_gets_the_checkout(online, stripe_on):
    resp = APIClient().post(B, book_body(online), format="json", REMOTE_ADDR="198.51.100.4")
    assert resp.status_code == 201, resp.content
    data = resp.json()
    row = Request.objects.get()
    assert data["request"] == {"id": row.pk, "manage_url": services.manage_url(row)}
    checkout = Checkout.objects.get()
    assert data["checkout"] == {
        "id": str(checkout.pk),
        "redirect_url": checkout.redirect_url,
        "amount_minor": 1500,
        "fee_minor": 0,
        "currency": "USD",
    }
    assert row.booked_ip_hash == services.ip_hash("198.51.100.4")
    assert (row.created_by, checkout.created_by) == (None, None)


def test_a_session_is_not_read_on_the_public_route(online, stripe_on, api_for):
    resp = api_for("student").post(B, book_body(online), format="json")
    assert resp.status_code == 201
    assert (Request.objects.get().created_by, Request.objects.get().student) == (None, None)


@pytest.mark.parametrize(
    ("extra", "field"),
    [({"provider": "cash"}, "provider"), ({"email": "nope"}, "email"), ({"starts_at": None}, "starts_at")],
)
def test_bad_bodies_are_400(online, stripe_on, extra, field):
    resp = APIClient().post(B, book_body(online, **extra), format="json")
    assert (resp.status_code, list(resp.json())) == (400, [field])
    assert not Request.objects.exists()


def test_a_provider_that_cannot_take_it_is_400_before_booking(online, stripe_on):
    resp = APIClient().post(B, book_body(online, provider="paypal"), format="json")
    assert (resp.status_code, list(resp.json())) == (400, ["provider"])
    assert not Request.objects.exists()


def test_a_provider_start_failure_keeps_the_booking(online, stripe_on, monkeypatch):
    def fail(*args, **kwargs):
        raise ExternalServiceError("payment")

    monkeypatch.setattr(gateways_services, "start_checkout", fail)
    resp = APIClient().post(B, book_body(online), format="json")
    assert resp.status_code == 201
    assert resp.json()["checkout"] is None
    assert Request.objects.get().hold_until is not None


def test_closed_booking_is_404(online, set_features):
    set_features(online_payments=False)
    assert APIClient().post(B, book_body(online), format="json").status_code == 404


def test_book_is_throttled_per_ip(online):
    anon = APIClient()
    codes = [anon.post(B, {}, format="json").status_code for _ in range(11)]
    assert codes[:10] == [400] * 10
    assert codes[10] == 429


def test_manage_payload_has_no_contact_details(online):
    row = book_one(online, notes="private note")
    data = APIClient().get(f"{M}{row.manage_token}/").json()
    assert set(data) == MANAGE_KEYS
    assert (data["reference"], data["status"], data["timezone"], data["meeting_url"]) == (
        row.reference,
        "pending_review",
        "Asia/Riyadh",
        "",
    )
    assert data["actions"] == {"pay": True, "reschedule": False, "review": False}
    assert data["payment"] == {
        "paid": False,
        "method": "",
        "amount_minor": 1500,
        "fee_minor": 0,
        "currency": "USD",
        "paid_on": None,
    }
    text = str(data)
    for private in ("sara@x.test", "+201000000009", "Sara", "private note"):
        assert private not in text


def test_the_link_shows_only_once_confirmed(online):
    row = book_one(online)
    Request.objects.filter(pk=row.pk).update(
        meeting_url="https://meet.test/r",
        paid_method="stripe",
        paid_on=date(2026, 10, 11),
        hold_until=None,
    )
    url = f"{M}{row.manage_token}/"
    assert APIClient().get(url).json()["meeting_url"] == ""
    services.confirm(services.get_request(row.pk), by=online.admin)
    data = APIClient().get(url).json()
    assert (data["meeting_url"], data["last_day"]) == ("https://meet.test/r", "2026-10-18")
    assert data["payment"]["paid"] is True


def test_another_or_a_malformed_token_is_404(online):
    book_one(online)
    assert APIClient().get(f"{M}{'A' * 43}/").status_code == 404
    assert APIClient().get(f"{M}short/").status_code == 404


def test_manage_reads_while_online_payments_is_off(online, set_features, stripe_on):
    row = book_one(online)
    set_features(online_payments=False)
    assert APIClient().get(f"{M}{row.manage_token}/").status_code == 200
    resp = APIClient().post(f"{M}{row.manage_token}/pay/", {"provider": "stripe"}, format="json")
    assert resp.status_code == 404


def test_pay_again_uses_the_bookings_own_token(online, stripe_on, monkeypatch):
    row = book_one(online)
    seen = []
    real = gateways_services.start_checkout

    def spy(*args, **kwargs):
        seen.append(kwargs["params"])
        return real(*args, **kwargs)

    monkeypatch.setattr(gateways_services, "start_checkout", spy)
    resp = APIClient().post(
        f"{M}{row.manage_token}/pay/",
        {"provider": "stripe", "token": "X" * 43, "recheck": True},
        format="json",
    )
    assert resp.status_code == 201, resp.content
    assert seen == [{"token": row.manage_token}]


def test_reschedule_and_review_over_http(online, frozen):
    services.update_product(online.product, reschedulable=True)
    row = book_one(online)
    Request.objects.filter(pk=row.pk).update(
        paid_method="stripe", paid_on=date(2026, 10, 11), hold_until=None
    )
    services.confirm(services.get_request(row.pk), by=online.admin)
    later = (MONDAY_4PM + HALF).isoformat()
    resp = APIClient().post(
        f"{M}{row.manage_token}/reschedule/", {"starts_at": later}, format="json"
    )
    assert resp.status_code == 200, resp.content
    assert (resp.json()["status"], resp.json()["proposed_starts_at"]) == (
        "reschedule_requested",
        later,
    )
    services.decline_reschedule(services.get_request(row.pk), by=online.admin)
    frozen(MONDAY_4PM + timedelta(hours=1))
    done = services.record_delivery(
        services.get_request(row.pk),
        student_attendance="present",
        teacher_attendance="present",
        session_status="completed",
    )
    services.complete(done, by=online.admin)
    review = {"rating": 5, "comment": "Great"}
    resp = APIClient().post(f"{M}{row.manage_token}/review/", review, format="json")
    assert resp.status_code == 201, resp.content
    assert resp.json()["review"] == {"rating": 5, "comment": "Great", "status": "pending"}
    assert resp.json()["actions"]["review"] is False
    again = APIClient().post(f"{M}{row.manage_token}/review/", review, format="json")
    assert (again.status_code, again.json()["code"]) == (
        409,
        "consultations.already_reviewed",
    )


def test_manage_is_throttled_per_ip(online):
    anon = APIClient()
    codes = [anon.get(f"{M}{'A' * 43}/").status_code for _ in range(61)]
    assert codes[:60] == [404] * 60
    assert codes[60] == 429
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_api_manage.py -q`
Expected: FAIL (404: the routes do not exist yet).

- [ ] **Step 3: Implement the payloads and inputs**

Append to `backend/etqan/consultations/api/booking_serializers.py`:

```python
PROVIDERS = ("stripe", "paypal")
LINKED = ("video_call", "live_chat")


def started_data(started) -> dict:
    return {
        "id": str(started.id),
        "redirect_url": started.redirect_url,
        "amount_minor": started.amount_minor,
        "fee_minor": started.fee_minor,
        "currency": started.currency,
    }


def manage_data(row, *, actions, providers, review, last_day, zone) -> dict:  # noqa: PLR0913
    """K-10: never the booker's email, WhatsApp, name or notes: the link
    never expires and may be forwarded. The meeting link only once
    confirmed (video_call, live_chat)."""
    product, paid = row.product, row.paid
    linked = row.status == "confirmed" and product.delivery_mode in LINKED
    return {
        "reference": row.reference,
        "status": row.status,
        "product": {
            "id": product.pk,
            "name_ar": product.name_ar,
            "name_en": product.name_en,
            "delivery_mode": product.delivery_mode,
            "duration_minutes": product.duration_minutes,
            "reschedulable": product.reschedulable,
        },
        "teacher": {
            "user_id": row.teacher.user_id,
            "full_name": row.teacher.user.full_name,
        },
        "timezone": row.timezone,
        "academy_timezone": zone,
        "starts_at": iso(row.starts_at),
        "ends_at": iso(row.ends_at),
        "proposed_starts_at": iso(row.proposed_starts_at),
        "meeting_url": row.meeting_url if linked else "",
        "hold_until": None if paid else iso(row.hold_until),
        "payment": {
            "paid": paid,
            "method": row.paid_method,
            "amount_minor": row.amount_minor if paid else (row.price_minor or 0),
            "fee_minor": row.fee_minor if paid else 0,
            "currency": row.currency if paid else row.price_currency,
            "paid_on": iso(row.paid_on),
        },
        "last_day": iso(last_day),
        "providers": providers,
        "actions": actions,
        "review": None
        if review is None
        else {"rating": review.rating, "comment": review.comment, "status": review.status},
    }


# Caps match the columns (B7c PF8).
class BookInput(serializers.Serializer):
    product = serializers.IntegerField(min_value=1)
    teacher = serializers.IntegerField(min_value=1)
    starts_at = serializers.DateTimeField(required=False, allow_null=True, default=None)
    name = serializers.CharField(required=False, allow_blank=True, default="", max_length=120)
    email = serializers.CharField(required=False, allow_blank=True, default="", max_length=254)
    whatsapp = serializers.CharField(required=False, allow_blank=True, default="", max_length=30)
    timezone = serializers.CharField(required=False, allow_blank=True, default="", max_length=64)
    notes = serializers.CharField(required=False, allow_blank=True, default="", max_length=2000)
    provider = serializers.ChoiceField(choices=PROVIDERS)
    language = serializers.CharField(required=False, allow_blank=True, default="en", max_length=8)


class ProviderInput(serializers.Serializer):
    provider = serializers.ChoiceField(choices=PROVIDERS)


class AskRescheduleInput(serializers.Serializer):
    starts_at = serializers.DateTimeField()
    note = serializers.CharField(required=False, allow_blank=True, default="", max_length=4000)


class ReviewInput(serializers.Serializer):
    rating = serializers.IntegerField()
    comment = serializers.CharField(required=False, allow_blank=True, default="", max_length=4000)
```

`backend/etqan/consultations/api/answers.py`:

```python
"""Slice B7d: the answers the public and family routes share."""

import logging

from etqan.consultations import services
from etqan.consultations.api import booking_serializers as s
from etqan.consultations.api.params import client_ip
from etqan.consultations.services import common
from etqan.platform.exceptions import EtqanError

logger = logging.getLogger(__name__)


def manage_answer(row) -> dict:
    review = services.review_of(row)
    actions = services.actions(row, review)
    providers = (
        services.providers_for_request(row)
        if actions["pay"] and services.booking_open()
        else []
    )
    return s.manage_data(
        row,
        actions=actions,
        providers=providers,
        review=review,
        last_day=services.last_day(row),
        zone=common.academy_zone(),
    )


def family_answer(row) -> dict:
    """K-13: the manage view, plus the request's id and student."""
    student = row.student.user if row.student_id else None
    return {
        **manage_answer(row),
        "id": row.pk,
        "student": {"id": student.pk, "full_name": student.full_name} if student else None,
    }


def book_answer(request, v, *, user, student=None) -> dict:
    """K-3: the booking commits, then its checkout starts. If the provider
    does not start, the booking stays and its manage page offers Pay while
    the hold lasts ([assumed]: 201 with checkout null)."""
    services.require_provider(v["product"], v["provider"])
    row = services.book(
        product_id=v["product"],
        teacher_user_id=v["teacher"],
        starts_at=v["starts_at"],
        name=v["name"],
        email=v["email"],
        whatsapp=v["whatsapp"],
        timezone=v["timezone"],
        notes=v["notes"],
        language=v["language"],
        ip=client_ip(request),
        user=user,
        student_user_id=student,
    )
    try:
        checkout = s.started_data(services.start_payment(row, v["provider"], user=user))
    except EtqanError as exc:
        logger.warning("consultation %s: checkout not started (%s)", row.pk, type(exc).__name__)
        checkout = None
    return {"request": {"id": row.pk, "manage_url": services.manage_url(row)}, "checkout": checkout}
```

- [ ] **Step 4: Implement the views and routes**

Append to `backend/etqan/consultations/api/public_views.py` (add `from rest_framework import status` and `from etqan.consultations.api.answers import book_answer, manage_answer` — one name per import line — at the top):

```python
class BookView(PublicView):
    """K-3. Non-atomic (see urls): the booking commits before the provider
    is called."""

    throttle_scope = "consultation_book"
    http_method_names = ["post", "options"]
    atomic_request = False

    def post(self, request):
        v = valid(s.BookInput, request.data)
        return Response(book_answer(request, v, user=None), status=status.HTTP_201_CREATED)


class ManageView(PublicView):
    """K-10: anyone holding the token. Needs only `consultations` ([assumed])."""

    throttle_scope = "consultation_manage"
    needs_online = False

    def get(self, request, token):
        return Response(manage_answer(services.by_token(token)))


class ManagePayView(ManageView):
    """K-4, K-10: the purpose gets the booking's own token (the URL's); the
    body names the provider only (D28). Non-atomic (see urls)."""

    needs_online = True
    http_method_names = ["post", "options"]
    atomic_request = False

    def post(self, request, token):
        row = services.by_token(token)
        v = valid(s.ProviderInput, request.data)
        started = services.start_payment(row, v["provider"], user=None)
        return Response(s.started_data(started), status=status.HTTP_201_CREATED)


class ManageRescheduleView(ManageView):
    http_method_names = ["post", "options"]

    def post(self, request, token):
        v = valid(s.AskRescheduleInput, request.data)
        services.ask_reschedule(
            services.by_token(token), starts_at=v["starts_at"], note=v["note"]
        )
        return Response(manage_answer(services.by_token(token)))


class ManageReviewView(ManageView):
    http_method_names = ["post", "options"]

    def post(self, request, token):
        v = valid(s.ReviewInput, request.data)
        services.leave_review(
            services.by_token(token), rating=v["rating"], comment=v["comment"]
        )
        return Response(
            manage_answer(services.by_token(token)), status=status.HTTP_201_CREATED
        )
```

In `api/urls.py`, add `from django.db import transaction` and after the Task 10 routes:

```python
    path("public/book/", transaction.non_atomic_requests(pv.BookView.as_view())),
    path("public/manage/<str:token>/", pv.ManageView.as_view()),
    path(
        "public/manage/<str:token>/pay/",
        transaction.non_atomic_requests(pv.ManagePayView.as_view()),
    ),
    path("public/manage/<str:token>/reschedule/", pv.ManageRescheduleView.as_view()),
    path("public/manage/<str:token>/review/", pv.ManageReviewView.as_view()),
```

- [ ] **Step 5: Name the new views as exempt (claim `backend/etqan/access/tests/test_routes.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/tests/test_routes.py --reason "B7d: SELF_SERVICE lines for public booking and manage routes"
```

Under `# Phase B7, slice B7d` in `SELF_SERVICE`, add:

```python
    "etqan.consultations.api.public_views.BookView": (
        "a visitor books; anonymous, throttled per IP, capped per email and IP"
    ),
    "etqan.consultations.api.public_views.ManageView": (
        "the booking's manage page (its unguessable token); throttled per IP"
    ),
    "etqan.consultations.api.public_views.ManagePayView": (
        "the booking's manage page (its unguessable token); throttled per IP"
    ),
    "etqan.consultations.api.public_views.ManageRescheduleView": (
        "the booking's manage page (its unguessable token); throttled per IP"
    ),
    "etqan.consultations.api.public_views.ManageReviewView": (
        "the booking's manage page (its unguessable token); throttled per IP"
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `B pytest etqan/consultations etqan/access/tests/test_routes.py etqan/platform/tests/test_drf.py -q`
Expected: PASS (`test_non_atomic_views_and_routes_agree` sees `BookView` and `ManagePayView` wrapped).

- [ ] **Step 7: Commit (then release the claim)**

```bash
git -C backend add etqan/consultations/api/answers.py etqan/consultations/api/booking_serializers.py \
  etqan/consultations/api/public_views.py etqan/consultations/api/urls.py \
  etqan/consultations/tests/conftest.py etqan/consultations/tests/test_api_manage.py \
  etqan/access/tests/test_routes.py
git -C backend commit -m "feat(consultations): public booking and manage-by-token routes (B7d K-3, K-4, K-10…K-12)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/tests/test_routes.py
```

---

### Task 12: The family routes (K-13, D19)

**Files:**
- Create: `backend/etqan/consultations/api/my_views.py`
- Modify: `backend/etqan/consultations/api/booking_serializers.py` (`MyBookInput`), `backend/etqan/consultations/api/urls.py`; **claim**: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/consultations/tests/test_api_my.py` (new)

**Interfaces:**
- Consumes: Task 11's `family_answer`, `book_answer`; Task 9's `family_requests`, `family_request`.
- Produces: `GET my/`, `GET my/<id>/`, `POST my/book/` (scope `consultation_book`, non-atomic, body adds `student?`), `POST my/<id>/pay/` (scope `gateway_start`, non-atomic), `POST my/<id>/reschedule/`, `POST my/<id>/review/`. Reads `[IsStudent | IsParent, FeatureOn]`; writes `[IsStudent | IsParent, NotImpersonating, FeatureOn]`; booking and paying also need `online_payments` (404). Item = `MANAGE_KEYS | {"id", "student"}`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_api_my.py`:

```python
import time
from datetime import timedelta

import pytest
from rest_framework.test import APIClient

from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import MANAGE_KEYS
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import book_body
from etqan.consultations.tests.conftest import book_one
from etqan.gateways.models import Checkout
from etqan.identity import services as identity_services
from etqan.platform.permissions import IMPERSONATOR_KEY

pytestmark = pytest.mark.django_db
MY = "/api/v1/consultations/my/"
HALF = timedelta(minutes=30)


def client_for(user):
    client = APIClient()
    client.force_login(user)
    return client


@pytest.fixture
def family(online):
    online.parent = identity_services.create_person(
        "parent", full_name="Omar", email="omar@x.test", invite=False
    )
    identity_services.link_guardian(online.parent, online.student)
    return online


def test_a_student_lists_and_opens_their_own(family):
    own = book_one(family, user=family.student)
    visitors = book_one(family, starts_at=MONDAY_4PM + HALF, ip="9.9.9.9")
    client = client_for(family.student)
    rows = client.get(MY).json()
    assert [r["id"] for r in rows] == [own.pk]
    assert set(rows[0]) == MANAGE_KEYS | {"id", "student"}
    assert rows[0]["student"] == {"id": family.student.pk, "full_name": "Yusuf Omar"}
    assert client.get(f"{MY}{own.pk}/").status_code == 200
    assert client.get(f"{MY}{visitors.pk}/").status_code == 404


def test_a_parent_books_for_a_child_and_sees_it(family, stripe_on):
    client = client_for(family.parent)
    body = book_body(
        family,
        name="",
        email="",
        whatsapp="+201000000002",
        timezone="",
        student=family.student.pk,
    )
    resp = client.post(f"{MY}book/", body, format="json")
    assert resp.status_code == 201, resp.content
    row = Request.objects.get()
    assert (row.student, row.created_by, row.name, row.self_booked) == (
        family.student_profile,
        family.parent,
        "Omar",
        True,
    )
    assert Checkout.objects.get().created_by == family.parent
    assert [r["id"] for r in client.get(MY).json()] == [row.pk]
    stranger = identity_services.create_person("student", full_name="Zaid", invite=False)
    body["student"], body["starts_at"] = stranger.pk, (MONDAY_4PM + HALF).isoformat()
    assert client.post(f"{MY}book/", body, format="json").status_code == 404


def test_pay_and_the_other_actions_as_a_family(family, stripe_on):
    row = book_one(family, user=family.student)
    client = client_for(family.student)
    resp = client.post(f"{MY}{row.pk}/pay/", {"provider": "stripe"}, format="json")
    assert resp.status_code == 201, resp.content
    assert Checkout.objects.get().created_by == family.student
    moved = client.post(
        f"{MY}{row.pk}/reschedule/",
        {"starts_at": (MONDAY_4PM + HALF).isoformat()},
        format="json",
    )
    assert (moved.status_code, moved.json()["code"]) == (409, "consultations.wrong_status")
    rated = client.post(f"{MY}{row.pk}/review/", {"rating": 5}, format="json")
    assert (rated.status_code, rated.json()["code"]) == (409, "consultations.not_completed")


def test_writes_refuse_a_quick_login_session(family, api_for, set_features):
    set_features(quick_login=True)
    actor = api_for("admin").user
    client = client_for(family.student)
    session = client.session
    session[IMPERSONATOR_KEY] = {
        "id": actor.pk,
        "hash": actor.get_session_auth_hash(),
        "since": int(time.time()),
    }
    session.save()
    row = book_one(family, user=family.student)
    writes = (
        (f"{MY}book/", book_body(family)),
        (f"{MY}{row.pk}/pay/", {"provider": "stripe"}),
        (f"{MY}{row.pk}/reschedule/", {"starts_at": MONDAY_4PM.isoformat()}),
        (f"{MY}{row.pk}/review/", {"rating": 5}),
    )
    for path, data in writes:
        resp = client.post(path, data, format="json")
        assert (resp.status_code, resp.json()["code"]) == (403, "identity.impersonating"), path
    assert client.get(MY).status_code == 200


def test_staff_get_403_and_switches_off_404(family, api_for, set_features):
    for role in ("admin", "staff", "teacher"):
        assert api_for(role).get(MY).status_code == 403
    student = client_for(family.student)
    set_features(online_payments=False)
    assert student.post(f"{MY}book/", book_body(family), format="json").status_code == 404
    assert student.get(MY).status_code == 200
    set_features(consultations=False)
    assert student.get(MY).status_code == 404
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_api_my.py -q`
Expected: FAIL (404: the routes do not exist yet).

- [ ] **Step 3: Implement**

Append to `api/booking_serializers.py`:

```python
class MyBookInput(BookInput):
    """K-13: a parent may name a child (a user id)."""

    student = serializers.IntegerField(
        min_value=1, required=False, allow_null=True, default=None
    )
```

`backend/etqan/consultations/api/my_views.py`:

```python
"""Slice B7d K-13: a student's and a parent's consultations, the signed-in
twin of the manage routes, scoped by ownership (404 for anyone else's).
Staff get 403 from the role check. Writes refuse a quick-login session
(D19). Booking and paying also need online_payments (404)."""

from rest_framework import status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from etqan.consultations import services
from etqan.consultations.api import booking_serializers as s
from etqan.consultations.api.answers import book_answer
from etqan.consultations.api.answers import family_answer
from etqan.consultations.api.params import valid
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import NotImpersonating

FAMILY = [IsStudent | IsParent, FeatureOn]
WRITERS = [IsStudent | IsParent, NotImpersonating, FeatureOn]


def _online() -> None:
    if not features.enabled("online_payments"):
        raise NotFoundError("Consultation")


class MyListView(APIView):
    feature = "consultations"
    permission_classes = FAMILY

    def get(self, request):
        return Response([family_answer(r) for r in services.family_requests(request.user)])


class MyDetailView(APIView):
    feature = "consultations"
    permission_classes = FAMILY

    def get(self, request, pk):
        return Response(family_answer(services.family_request(request.user, pk)))


class _MyWrite(APIView):
    feature = "consultations"
    permission_classes = WRITERS
    http_method_names = ["post", "options"]


class MyBookView(_MyWrite):
    """Non-atomic (see urls): the booking commits before the provider is called."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "consultation_book"
    atomic_request = False

    def post(self, request):
        _online()
        v = valid(s.MyBookInput, request.data)
        answer = book_answer(request, v, user=request.user, student=v["student"])
        return Response(answer, status=status.HTTP_201_CREATED)


class MyPayView(_MyWrite):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "gateway_start"
    atomic_request = False

    def post(self, request, pk):
        _online()
        row = services.family_request(request.user, pk)
        v = valid(s.ProviderInput, request.data)
        started = services.start_payment(row, v["provider"], user=request.user)
        return Response(s.started_data(started), status=status.HTTP_201_CREATED)


class MyRescheduleView(_MyWrite):
    def post(self, request, pk):
        row = services.family_request(request.user, pk)
        v = valid(s.AskRescheduleInput, request.data)
        services.ask_reschedule(row, starts_at=v["starts_at"], note=v["note"])
        return Response(family_answer(services.family_request(request.user, pk)))


class MyReviewView(_MyWrite):
    def post(self, request, pk):
        row = services.family_request(request.user, pk)
        v = valid(s.ReviewInput, request.data)
        services.leave_review(row, rating=v["rating"], comment=v["comment"])
        return Response(
            family_answer(services.family_request(request.user, pk)),
            status=status.HTTP_201_CREATED,
        )
```

In `api/urls.py`, add `from etqan.consultations.api import my_views as mv` and:

```python
    path("my/", mv.MyListView.as_view()),
    path("my/book/", transaction.non_atomic_requests(mv.MyBookView.as_view())),
    path("my/<int:pk>/", mv.MyDetailView.as_view()),
    path("my/<int:pk>/pay/", transaction.non_atomic_requests(mv.MyPayView.as_view())),
    path("my/<int:pk>/reschedule/", mv.MyRescheduleView.as_view()),
    path("my/<int:pk>/review/", mv.MyReviewView.as_view()),
```

- [ ] **Step 4: Name the new views as exempt (claim `backend/etqan/access/tests/test_routes.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/tests/test_routes.py --reason "B7d: SELF_SERVICE lines for the family consultation routes"
```

Under `# Phase B7, slice B7d` in `SELF_SERVICE`, add:

```python
    "etqan.consultations.api.my_views.MyListView": (
        "a family's own consultations (role check, scoped in the service)"
    ),
    "etqan.consultations.api.my_views.MyDetailView": (
        "a family's own consultations (role check, scoped in the service)"
    ),
    "etqan.consultations.api.my_views.MyBookView": (
        "a family books for itself or its child (role check, scoped in the service)"
    ),
    "etqan.consultations.api.my_views.MyPayView": (
        "a family pays its own booking (role check, scoped in the service)"
    ),
    "etqan.consultations.api.my_views.MyRescheduleView": (
        "a family asks to move its own consultation (role check, scoped in the service)"
    ),
    "etqan.consultations.api.my_views.MyReviewView": (
        "a family rates its own consultation (role check, scoped in the service)"
    ),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `B pytest etqan/consultations etqan/access/tests/test_routes.py etqan/platform/tests/test_drf.py -q`
Expected: PASS.

- [ ] **Step 6: Commit (then release the claim)**

```bash
git -C backend add etqan/consultations/api/my_views.py etqan/consultations/api/booking_serializers.py \
  etqan/consultations/api/urls.py etqan/consultations/tests/test_api_my.py \
  etqan/access/tests/test_routes.py
git -C backend commit -m "feat(consultations): family routes to book, pay, move and rate (B7d K-13)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/tests/test_routes.py
```

---

### Task 13: Office review moderation and its access resource (K-12, K-16)

**Files:**
- Create: `backend/etqan/consultations/api/review_views.py`
- Modify: `backend/etqan/consultations/api/booking_serializers.py`, `backend/etqan/consultations/api/urls.py`; **claims**: `backend/etqan/access/registry.py`, `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/consultations/tests/test_api_reviews.py` (new)

**Interfaces:**
- Consumes: Task 9's `reviews_queryset`, `filter_reviews`, `get_review`, `decide_review`.
- Produces: resource `consultation_review` (`view_any`, `update`); `GET reviews/?status=` (paginated), `GET reviews/<id>/`, `PATCH reviews/<id>/ {status, reason}`; payload `{id, request: {id, reference, product: {id, name_ar, name_en}}, name, rating, comment, status, reason, created_at, decided_at, decided_by: {id, full_name} | null}`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_api_reviews.py`:

```python
import pytest

from etqan.consultations.models import Review
from etqan.consultations.tests.conftest import new_request

pytestmark = pytest.mark.django_db
REV = "/api/v1/consultations/reviews/"


@pytest.fixture
def review(online):
    return Review.objects.create(request=new_request(online), rating=4, comment="Clear")


def test_the_office_lists_and_decides(online, review, staff_for):
    reader = staff_for("consultation_review.view_any")
    page = reader.get(REV, {"status": "pending"}).json()
    [row] = page["results"]
    assert (row["id"], row["name"], row["rating"], row["status"], row["decided_by"]) == (
        review.pk,
        "Yusuf Omar",
        4,
        "pending",
        None,
    )
    assert row["request"]["reference"] == review.request.reference
    assert reader.patch(f"{REV}{review.pk}/", {"status": "approved"}, format="json").status_code == 403
    editor = staff_for("consultation_review.view_any", "consultation_review.update")
    resp = editor.patch(
        f"{REV}{review.pk}/", {"status": "rejected", "reason": "Off topic"}, format="json"
    )
    assert resp.status_code == 200, resp.content
    assert (resp.json()["status"], resp.json()["reason"]) == ("rejected", "Off topic")
    bad = editor.patch(f"{REV}{review.pk}/", {"status": "pending"}, format="json")
    assert (bad.status_code, list(bad.json())) == (400, ["status"])


def test_families_and_switch_off(online, review, api_for, set_features):
    assert api_for("student").get(REV).status_code == 403
    set_features(consultations=False)
    assert api_for("admin").get(REV).status_code == 404
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `B pytest etqan/consultations/tests/test_api_reviews.py -q`
Expected: FAIL (404: no route).

- [ ] **Step 3: Implement**

Append to `api/booking_serializers.py`:

```python
def office_review_data(r) -> dict:
    req = r.request
    return {
        "id": r.pk,
        "request": {
            "id": req.pk,
            "reference": req.reference,
            "product": {
                "id": req.product_id,
                "name_ar": req.product.name_ar,
                "name_en": req.product.name_en,
            },
        },
        "name": req.name,
        "rating": r.rating,
        "comment": r.comment,
        "status": r.status,
        "reason": r.reason,
        "created_at": iso(r.created_at),
        "decided_at": iso(r.decided_at),
        "decided_by": (
            {"id": r.decided_by.pk, "full_name": r.decided_by.full_name}
            if r.decided_by_id
            else None
        ),
    }


class DecideInput(serializers.Serializer):
    status = serializers.CharField(max_length=16)
    reason = serializers.CharField(required=False, allow_blank=True, default="", max_length=2000)
```

`backend/etqan/consultations/api/review_views.py`:

```python
"""Slice B7d K-12, K-16: the office moderates the bookers' ratings
(`consultation_review`)."""

from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.consultations import services
from etqan.consultations.api import booking_serializers as s
from etqan.consultations.api.params import valid
from etqan.platform.pagination import StandardPagination
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode

OFFICE = [HasCode, FeatureOn]


class ReviewListView(APIView):
    feature = "consultations"
    permission_classes = OFFICE
    permission_codes = {"GET": "consultation_review.view_any"}

    def get(self, request):
        qs = services.filter_reviews(
            services.reviews_queryset(), status=request.query_params.get("status", "")
        )
        paginator = StandardPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([s.office_review_data(r) for r in page])


class ReviewDetailView(APIView):
    feature = "consultations"
    permission_classes = OFFICE
    permission_codes = {
        "GET": "consultation_review.view_any",
        "PATCH": "consultation_review.update",
    }

    def get(self, request, pk):
        return Response(s.office_review_data(services.get_review(pk)))

    def patch(self, request, pk):
        v = valid(s.DecideInput, request.data)
        services.decide_review(
            services.get_review(pk), status=v["status"], reason=v["reason"], by=request.user
        )
        return Response(s.office_review_data(services.get_review(pk)))
```

In `api/urls.py`, add `from etqan.consultations.api import review_views as rw` and:

```python
    path("reviews/", rw.ReviewListView.as_view()),
    path("reviews/<int:pk>/", rw.ReviewDetailView.as_view()),
```

- [ ] **Step 4: The access resource (claim `backend/etqan/access/registry.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/registry.py --reason "B7d K-16: resource consultation_review"
```

In `RESOURCES`, after B7c's `consultation_schedule` resource (under `── phase B7 ──`):

```python
    Resource(
        "consultation_review",
        "Consultation reviews",
        "تقييمات الاستشارات",
        ("view_any", "update"),
    ),
```

- [ ] **Step 5: The route tables (claim `backend/etqan/access/tests/test_routes.py`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/tests/test_routes.py --reason "B7d: ROUTES and FEATURES lines for consultation reviews"
```

In `ROUTES`, after B7c's last line (`schedule/`):

```python
    # Phase B7, slice B7d
    ("GET", "/api/v1/consultations/reviews/", "consultation_review.view_any"),
    ("GET", f"/api/v1/consultations/reviews/{N}/", "consultation_review.view_any"),
    ("PATCH", f"/api/v1/consultations/reviews/{N}/", "consultation_review.update"),
```

In `FEATURES`, after B7c's block:

```python
    # Phase B7, slice B7d
    **dict.fromkeys(
        (
            ("GET", "/api/v1/consultations/reviews/"),
            ("GET", f"/api/v1/consultations/reviews/{N}/"),
            ("PATCH", f"/api/v1/consultations/reviews/{N}/"),
        ),
        "consultations",
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `B pytest etqan/consultations etqan/access -q`
Expected: PASS (`test_every_code_in_the_table_is_in_the_registry_and_in_use` sees both new codes in use).

- [ ] **Step 7: Commit (then release both claims)**

```bash
git -C backend add etqan/consultations/api/review_views.py etqan/consultations/api/booking_serializers.py \
  etqan/consultations/api/urls.py etqan/consultations/tests/test_api_reviews.py \
  etqan/access/registry.py etqan/access/tests/test_routes.py
git -C backend commit -m "feat(consultations): office review moderation and the consultation_review resource (B7d K-12, K-16)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/registry.py
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/tests/test_routes.py
```

---

### Task 14: Dashboard data layer and strings

**Files:**
- Modify: `dashboard/src/features/consultations/schemas.ts`, `api.ts` (export `given`), `fixtures.ts`, `index.ts`; `dashboard/src/locales/en/consultations.json`, `dashboard/src/locales/ar/consultations.json`
- Create: `dashboard/src/features/consultations/bookingApi.ts`, `bookingQueries.ts`, `manageLink.ts`
- Test: `dashboard/src/features/consultations/bookingApi.test.ts`, `manageLink.test.ts` (new)

**Interfaces:**
- Consumes: Tasks 10–13's routes and payloads.
- Produces:
  - types `PublicTeacher`, `PublicReview`, `PublicProduct`, `PublicProductDetail`, `BookingSlots`, `BookBody`, `BookAnswer`, `ManageView`, `FamilyRequest`, `OfficeReview`, `ReviewStatus`, `REVIEW_STATUSES`, `Booker = {kind: "public", token} | {kind: "my", id}`; `ConsultationRequest` gains `self_booked`, `hold_until`, `proposed_starts_at`, `cancel_reason`; `RequestFilters.self_booked?: boolean`;
  - `bookingApi`: `products()`, `product(id)`, `slots(id, {teacher, from?, days?})`, `book(body, signedIn)`, `manage(booker)`, `pay(booker, provider)`, `reschedule(booker, {starts_at, note})`, `review(booker, {rating, comment})`, `mine()`, `reviews({status?, page?})`, `decide(id, {status, reason})`;
  - hooks `useBookableProducts`, `usePublicProduct(id)`, `useBookingSlots(id, {teacher?, from?})`, `useBook(signedIn)`, `useManage(booker)`, `usePayBooking(booker)`, `useAskReschedule(booker)`, `useReviewBooking(booker)`, `useMyConsultations()`, `useOfficeReviews(f)`, `useDecideReview()`; query key root `bookingKey`;
  - `manageLink.ts`: `rememberManage(checkoutId, manageUrl)`, `manageTokenFor(checkoutId) -> string | null`, `tokenOf(manageUrl) -> string | null`, `useNoReferrer()`; the storage key is `consult:<checkout id>` (K-15);
  - fixtures `publicProduct`, `publicDetail`, `bookingSlots`, `TOKEN`, `manageView`, `familyRequest`, `officeReview`;
  - strings `consultations.{book,manage,family,reviews,return}.*`, `consultations.nav.family`, new `requests.*` and `errors.*` keys (en, ar).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/consultations/bookingApi.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { bookingApi } from "./bookingApi";

vi.mock("@/lib/api", () => ({
	api: { get: vi.fn(), post: vi.fn(), patch: vi.fn() },
}));

const TOKEN = "T".repeat(43);

describe("bookingApi", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		for (const fn of [api.get, api.post, api.patch])
			vi.mocked(fn).mockResolvedValue({ data: { ok: true } });
	});

	it("reads the public catalogue and slots", async () => {
		await bookingApi.products();
		expect(api.get).toHaveBeenCalledWith("consultations/public/products/");
		await bookingApi.product(3);
		expect(api.get).toHaveBeenCalledWith("consultations/public/products/3/");
		await bookingApi.slots(3, { teacher: 8, from: "2026-10-12", days: 7 });
		expect(api.get).toHaveBeenCalledWith(
			"consultations/public/products/3/slots/",
			{ params: { teacher: 8, from: "2026-10-12", days: 7 } },
		);
	});

	it("books on the public or the family route", async () => {
		const body = { product: 3 } as never;
		await bookingApi.book(body, false);
		expect(api.post).toHaveBeenCalledWith("consultations/public/book/", body);
		await bookingApi.book(body, true);
		expect(api.post).toHaveBeenCalledWith("consultations/my/book/", body);
	});

	it("acts on a booking by token or by id", async () => {
		const visitor = { kind: "public", token: TOKEN } as const;
		const family = { kind: "my", id: 5 } as const;
		await bookingApi.manage(visitor);
		expect(api.get).toHaveBeenCalledWith(
			`consultations/public/manage/${TOKEN}/`,
		);
		await bookingApi.pay(family, "stripe");
		expect(api.post).toHaveBeenCalledWith("consultations/my/5/pay/", {
			provider: "stripe",
		});
		await bookingApi.reschedule(visitor, { starts_at: "x", note: "" });
		expect(api.post).toHaveBeenCalledWith(
			`consultations/public/manage/${TOKEN}/reschedule/`,
			{ starts_at: "x", note: "" },
		);
		await bookingApi.review(family, { rating: 5, comment: "" });
		expect(api.post).toHaveBeenCalledWith("consultations/my/5/review/", {
			rating: 5,
			comment: "",
		});
		await bookingApi.mine();
		expect(api.get).toHaveBeenCalledWith("consultations/my/");
	});

	it("lists and decides reviews for the office", async () => {
		await bookingApi.reviews({ status: "pending", page: undefined });
		expect(api.get).toHaveBeenCalledWith("consultations/reviews/", {
			params: { status: "pending" },
		});
		await bookingApi.decide(9, { status: "approved", reason: "" });
		expect(api.patch).toHaveBeenCalledWith("consultations/reviews/9/", {
			status: "approved",
			reason: "",
		});
	});
});
```

`dashboard/src/features/consultations/manageLink.test.ts`:

```ts
import { renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import {
	manageTokenFor,
	rememberManage,
	tokenOf,
	useNoReferrer,
} from "./manageLink";

const TOKEN = "Ab_-".repeat(10) + "xyz"; // 43 url-safe characters
const URL = `http://demo.etqan.localhost/app/consult/manage/${TOKEN}`;

describe("manageLink", () => {
	afterEach(() => sessionStorage.clear());

	it("remembers a checkout's manage link for this tab (K-15)", () => {
		rememberManage("c-1", URL);
		expect(sessionStorage.getItem("consult:c-1")).toBe(URL);
		expect(manageTokenFor("c-1")).toBe(TOKEN);
		expect(manageTokenFor("c-2")).toBeNull();
	});

	it("reads only a well-formed token", () => {
		expect(tokenOf(URL)).toBe(TOKEN);
		expect(tokenOf(`/app/consult/manage/${TOKEN}`)).toBe(TOKEN);
		expect(tokenOf("/app/consult/manage/short")).toBeNull();
		expect(tokenOf(`${URL}/extra`)).toBeNull();
		sessionStorage.setItem("consult:c-3", "javascript:alert(1)");
		expect(manageTokenFor("c-3")).toBeNull();
	});

	it("asks the browser to send no referrer while mounted (K-9)", () => {
		const view = renderHook(() => useNoReferrer());
		const meta = document.head.querySelector('meta[name="referrer"]');
		expect(meta?.getAttribute("content")).toBe("no-referrer");
		view.unmount();
		expect(document.head.querySelector('meta[name="referrer"]')).toBeNull();
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `F pnpm vitest run src/features/consultations/bookingApi.test.ts src/features/consultations/manageLink.test.ts`
Expected: FAIL with `Failed to resolve import "./bookingApi"`.

- [ ] **Step 3: Types**

In `dashboard/src/features/consultations/schemas.ts`, add at the top `import type { Provider, StartedCheckout } from "@/features/gateways/schemas";`. In `ConsultationRequest`, after `reschedule_note: string;`:

```ts
	/** Slice B7d. */
	self_booked: boolean;
	hold_until: string | null;
	proposed_starts_at: string | null;
	cancel_reason: "" | "unpaid" | "office";
```

In `RequestFilters`, add `self_booked?: boolean;`. At the end of the module:

```ts
/** Slice B7d: the public catalogue, booking, the manage page and reviews. */
export interface PublicTeacher {
	user_id: number;
	full_name: string;
	initial: string;
	bio: string;
}

export interface PublicReview {
	rating: number;
	comment: string;
	created_at: string;
	by: "student" | "visitor";
}

export interface PublicProduct {
	id: number;
	name_ar: string;
	name_en: string;
	description_ar: string;
	description_en: string;
	price_minor: number;
	currency: string;
	fee_enabled: boolean;
	duration_minutes: number;
	validity_days: number;
	participants: number;
	delivery_mode: DeliveryMode;
	featured: boolean;
	reschedulable: boolean;
	cover_url: string;
	rating_average: number | null;
	rating_count: number;
}

export interface PublicProductDetail extends PublicProduct {
	teachers: PublicTeacher[];
	reviews: PublicReview[];
	providers: Provider[];
}

export interface BookingSlots {
	academy_timezone: string;
	last_day: string;
	slots: Slot[];
}

export interface BookBody {
	product: number;
	teacher: number;
	starts_at: string | null;
	name: string;
	email: string;
	whatsapp: string;
	timezone: string;
	notes: string;
	provider: Provider;
	language: "en" | "ar";
	/** my/book only: a parent's child (user id). */
	student?: number;
}

export interface BookAnswer {
	request: { id: number; manage_url: string };
	checkout: StartedCheckout | null;
}

export const REVIEW_STATUSES = ["pending", "approved", "rejected"] as const;
export type ReviewStatus = (typeof REVIEW_STATUSES)[number];

export interface ManageView {
	reference: string;
	status: RequestStatus;
	product: {
		id: number;
		name_ar: string;
		name_en: string;
		delivery_mode: DeliveryMode;
		duration_minutes: number;
		reschedulable: boolean;
	};
	teacher: { user_id: number; full_name: string };
	timezone: string;
	academy_timezone: string;
	starts_at: string | null;
	ends_at: string | null;
	proposed_starts_at: string | null;
	meeting_url: string;
	hold_until: string | null;
	payment: {
		paid: boolean;
		method: "" | "manual" | "stripe" | "paypal";
		amount_minor: number;
		fee_minor: number;
		currency: string;
		paid_on: string | null;
	};
	last_day: string | null;
	providers: Provider[];
	actions: { pay: boolean; reschedule: boolean; review: boolean };
	review: { rating: number; comment: string; status: ReviewStatus } | null;
}

export interface FamilyRequest extends ManageView {
	id: number;
	student: PersonRef | null;
}

export interface OfficeReview {
	id: number;
	request: {
		id: number;
		reference: string;
		product: { id: number; name_ar: string; name_en: string };
	};
	name: string;
	rating: number;
	comment: string;
	status: ReviewStatus;
	reason: string;
	created_at: string;
	decided_at: string | null;
	decided_by: PersonRef | null;
}

/** Who looks at a booking: a visitor by its link's token, a family by id. */
export type Booker = { kind: "public"; token: string } | { kind: "my"; id: number };
```

In `api.ts`, change `function given<T extends object>(` to `export function given<T extends object>(`.

- [ ] **Step 4: Calls, hooks and the manage-link helpers**

`dashboard/src/features/consultations/bookingApi.ts`:

```ts
import type { Provider, StartedCheckout } from "@/features/gateways/schemas";
import { api, type Paginated } from "@/lib/api";
import { given } from "./api";
import type {
	BookAnswer,
	BookBody,
	Booker,
	BookingSlots,
	FamilyRequest,
	ManageView,
	OfficeReview,
	PublicProduct,
	PublicProductDetail,
} from "./schemas";

const B = "consultations/";

/** A booking's routes: its link's token (anonymous) or the family's id. */
const base = (b: Booker) =>
	b.kind === "public" ? `${B}public/manage/${b.token}/` : `${B}my/${b.id}/`;

export const bookingApi = {
	products: async () =>
		(await api.get<PublicProduct[]>(`${B}public/products/`)).data,
	product: async (id: number) =>
		(await api.get<PublicProductDetail>(`${B}public/products/${id}/`)).data,
	slots: async (
		id: number,
		q: { teacher: number; from?: string; days?: number },
	) =>
		(
			await api.get<BookingSlots>(`${B}public/products/${id}/slots/`, {
				params: given(q),
			})
		).data,
	book: async (body: BookBody, signedIn: boolean) =>
		(
			await api.post<BookAnswer>(
				signedIn ? `${B}my/book/` : `${B}public/book/`,
				body,
			)
		).data,
	manage: async (b: Booker) => (await api.get<ManageView>(base(b))).data,
	pay: async (b: Booker, provider: Provider) =>
		(await api.post<StartedCheckout>(`${base(b)}pay/`, { provider })).data,
	reschedule: async (b: Booker, body: { starts_at: string; note: string }) =>
		(await api.post<ManageView>(`${base(b)}reschedule/`, body)).data,
	review: async (b: Booker, body: { rating: number; comment: string }) =>
		(await api.post<ManageView>(`${base(b)}review/`, body)).data,
	mine: async () => (await api.get<FamilyRequest[]>(`${B}my/`)).data,
	reviews: async (f: { status?: string; page?: number }) =>
		(
			await api.get<Paginated<OfficeReview>>(`${B}reviews/`, {
				params: given(f),
			})
		).data,
	decide: async (
		id: number,
		body: { status: "approved" | "rejected"; reason: string },
	) => (await api.patch<OfficeReview>(`${B}reviews/${id}/`, body)).data,
};
```

`dashboard/src/features/consultations/bookingQueries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import type { Provider } from "@/features/gateways/schemas";
import { bookingApi } from "./bookingApi";
import { consultationsKey } from "./queries";
import type { BookBody, Booker } from "./schemas";

export const bookingKey = [...consultationsKey, "booking"] as const;

function useRefreshing<A, R>(fn: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: () => qc.invalidateQueries({ queryKey: consultationsKey }),
	});
}

export const useBookableProducts = () =>
	useQuery({
		queryKey: [...bookingKey, "products"],
		queryFn: bookingApi.products,
		retry: false,
	});
export const usePublicProduct = (id: number) =>
	useQuery({
		queryKey: [...bookingKey, "product", id],
		queryFn: () => bookingApi.product(id),
		retry: false,
	});
export const useBookingSlots = (
	id: number,
	q: { teacher?: number; from?: string },
) =>
	useQuery({
		queryKey: [...bookingKey, "slots", id, q],
		queryFn: () =>
			bookingApi.slots(id, { teacher: q.teacher as number, from: q.from, days: 7 }),
		enabled: q.teacher !== undefined,
		placeholderData: keepPreviousData,
	});
export const useBook = (signedIn: boolean) =>
	useMutation({ mutationFn: (body: BookBody) => bookingApi.book(body, signedIn) });
export const useManage = (b: Booker) =>
	useQuery({
		queryKey: [...bookingKey, "manage", b],
		queryFn: () => bookingApi.manage(b),
		retry: false,
	});
export const usePayBooking = (b: Booker) =>
	useMutation({ mutationFn: (provider: Provider) => bookingApi.pay(b, provider) });
export const useAskReschedule = (b: Booker) =>
	useRefreshing((body: { starts_at: string; note: string }) =>
		bookingApi.reschedule(b, body),
	);
export const useReviewBooking = (b: Booker) =>
	useRefreshing((body: { rating: number; comment: string }) =>
		bookingApi.review(b, body),
	);
export const useMyConsultations = () =>
	useQuery({ queryKey: [...bookingKey, "mine"], queryFn: bookingApi.mine });
export const useOfficeReviews = (f: { status?: string; page?: number }) =>
	useQuery({
		queryKey: [...bookingKey, "reviews", f],
		queryFn: () => bookingApi.reviews(f),
		placeholderData: keepPreviousData,
	});
export const useDecideReview = () =>
	useRefreshing(
		({
			id,
			...body
		}: {
			id: number;
			status: "approved" | "rejected";
			reason: string;
		}) => bookingApi.decide(id, body),
	);
```

`dashboard/src/features/consultations/manageLink.ts`:

```ts
import { useEffect } from "react";

/** K-15: the wizard remembers each checkout's manage link for this tab, so
 * the public return page (whose anonymous read has no purpose) can link
 * back to the booking. The gateways return page reads the same key. */
const key = (checkoutId: string) => `consult:${checkoutId}`;
const TOKEN = /\/consult\/manage\/([A-Za-z0-9_-]{43})$/;

export function tokenOf(manageUrl: string): string | null {
	return TOKEN.exec(manageUrl)?.[1] ?? null;
}

export function rememberManage(checkoutId: string, manageUrl: string): void {
	try {
		sessionStorage.setItem(key(checkoutId), manageUrl);
	} catch {
		// Storage off (a private window): the emailed link still works.
	}
}

export function manageTokenFor(checkoutId: string): string | null {
	try {
		const url = sessionStorage.getItem(key(checkoutId));
		return url ? tokenOf(url) : null;
	} catch {
		return null;
	}
}

/** K-9: the page's token must not leave in a Referer header. */
export function useNoReferrer(): void {
	useEffect(() => {
		const meta = document.createElement("meta");
		meta.name = "referrer";
		meta.content = "no-referrer";
		document.head.appendChild(meta);
		return () => meta.remove();
	}, []);
}
```

In `index.ts`, add:

```ts
export { bookingApi } from "./bookingApi";
export * from "./bookingQueries";
export { manageTokenFor, rememberManage, tokenOf } from "./manageLink";
```

- [ ] **Step 5: Fixtures**

In `fixtures.ts`, add to `request`, after `reschedule_note: "",`:

```ts
	self_booked: false,
	hold_until: null,
	proposed_starts_at: null,
	cancel_reason: "",
```

and append (extend the type import with `FamilyRequest`, `ManageView`, `OfficeReview`, `PublicProduct`, `PublicProductDetail`, `BookingSlots`):

```ts
export const publicProduct: PublicProduct = {
	id: 3,
	name_ar: "استشارة تحديد المستوى",
	name_en: "Placement consultation",
	description_ar: "",
	description_en: "Thirty minutes with a teacher.",
	price_minor: 1500,
	currency: "USD",
	fee_enabled: false,
	duration_minutes: 30,
	validity_days: 14,
	participants: 1,
	delivery_mode: "video_call",
	featured: true,
	reschedulable: true,
	cover_url: "",
	rating_average: 4.5,
	rating_count: 2,
};

export const publicDetail: PublicProductDetail = {
	...publicProduct,
	teachers: [
		{ user_id: 8, full_name: "Ustadh Bilal", initial: "U", bio: "Ijazah in Hafs." },
	],
	reviews: [
		{ rating: 5, comment: "Clear", created_at: "2026-10-01T10:00:00+00:00", by: "visitor" },
	],
	providers: ["stripe", "paypal"],
};

export const bookingSlots: BookingSlots = {
	academy_timezone: "UTC",
	last_day: "2026-10-25",
	slots: [
		{ starts_at: "2026-10-12T16:00:00+00:00", remaining: 1 },
		{ starts_at: "2026-10-12T16:30:00+00:00", remaining: 1 },
	],
};

export const TOKEN = "T".repeat(43);

export const manageView: ManageView = {
	reference: "CR-000005",
	status: "pending_review",
	product: {
		id: 3,
		name_ar: "استشارة تحديد المستوى",
		name_en: "Placement consultation",
		delivery_mode: "video_call",
		duration_minutes: 30,
		reschedulable: true,
	},
	teacher: { user_id: 8, full_name: "Ustadh Bilal" },
	timezone: "Asia/Riyadh",
	academy_timezone: "UTC",
	starts_at: "2026-10-12T16:00:00+00:00",
	ends_at: "2026-10-12T16:30:00+00:00",
	proposed_starts_at: null,
	meeting_url: "",
	hold_until: "2026-10-11T12:30:00+00:00",
	payment: {
		paid: false,
		method: "",
		amount_minor: 1500,
		fee_minor: 0,
		currency: "USD",
		paid_on: null,
	},
	last_day: null,
	providers: ["stripe"],
	actions: { pay: true, reschedule: false, review: false },
	review: null,
};

export const familyRequest: FamilyRequest = {
	...manageView,
	id: 5,
	student: { id: 21, full_name: "Yusuf Omar" },
};

export const officeReview: OfficeReview = {
	id: 9,
	request: {
		id: 5,
		reference: "CR-000005",
		product: { id: 3, name_ar: "استشارة تحديد المستوى", name_en: "Placement consultation" },
	},
	name: "Sara",
	rating: 4,
	comment: "Clear",
	status: "pending",
	reason: "",
	created_at: "2026-10-13T10:00:00+00:00",
	decided_at: null,
	decided_by: null,
};
```

- [ ] **Step 6: Strings (en and ar, key-equal)**

Merge these keys into the two locale files with this one-off script (run from the meta worktree; it deep-merges, refuses to overwrite an existing key, and writes tab-indented JSON that biome then formats):

```bash
python3 - <<'EOF'
import json, pathlib

ADD = {
    "en": {
        "nav": {"family": "My consultations"},
        "book": {
            "title": "Book a consultation",
            "notFound": "This consultation cannot be booked.",
            "closed": "Booking consultations is not open.",
            "none": "No consultation can be booked right now.",
            "pick": "Choose a consultation",
            "minutes": "{{n}} min",
            "fee": "A payment fee may be added at checkout.",
            "signedIn": "Have an account? Book from your account.",
            "teacher": "Choose a teacher",
            "time": "Choose a time",
            "noSlots": "No free times in these days.",
            "slotsError": "The times could not be loaded.",
            "earlier": "Earlier",
            "later": "Later",
            "academyTime": "Academy time: {{time}}",
            "details": "Your details",
            "accountHint": "Leave a field blank to use your account's details.",
            "child": "For",
            "self": "Myself",
            "name": "Name",
            "email": "Email",
            "whatsapp": "WhatsApp",
            "timezone": "Your timezone",
            "notes": "Notes (optional)",
            "pay": "Pay",
            "payWith": "Pay with {{provider}}",
            "noProviders": "Online payment is not available right now.",
            "keepLink": "Keep this link to manage your booking:",
            "notStarted": "Your booking is saved, but the payment did not start. Open your booking to pay.",
            "open": "Open your booking",
        },
        "manage": {
            "title": "Your consultation",
            "notFound": "This booking link is not valid.",
            "status": "Status",
            "teacher": "Teacher",
            "time": "Time",
            "noTime": "Answered by email",
            "payment": "Payment",
            "paid": "Paid {{amount}}",
            "unpaid": "Not paid yet",
            "holdUntil": "Your time is held until {{time}}.",
            "payTitle": "Pay for your booking",
            "pay": "Pay with {{provider}}",
            "join": "Join the consultation",
            "proposed": "You asked to move it to {{time}}.",
            "reschedule": "Ask to move it",
            "note": "Note (optional)",
            "send": "Send",
            "review": "Rate this consultation",
            "rating": "Rating",
            "stars": "{{n}} of 5",
            "comment": "Comment (optional)",
            "sendReview": "Send review",
            "reviewSent": "Thank you. Your review waits for the academy's approval.",
            "reviewStatus": {
                "approved": "Your review is published.",
                "rejected": "Your review was not published.",
            },
        },
        "family": {
            "title": "My consultations",
            "subtitle": "Book a consultation and follow your bookings.",
            "book": "Book a consultation",
            "empty": "No consultations yet.",
            "for": "For {{name}}",
        },
        "reviews": {
            "empty": "No reviews.",
            "status": "Review status",
            "approve": "Approve",
            "reject": "Reject",
            "reason": "Reason (optional)",
            "rating": "{{n}} / 5",
            "statuses": {"pending": "Pending", "approved": "Approved", "rejected": "Rejected"},
            "done": "Saved.",
        },
        "requests": {
            "tabs": {"reviews": "Reviews"},
            "filters": {"selfBooked": "Booked"},
            "selfBooked": "Online",
            "officeBooked": "By the office",
            "fee": "+ {{fee}} fee",
            "proposed": "Proposed: {{time}}",
        },
        "return": {
            "open": "Open your booking",
            "mine": "Open my consultations",
            "emailed": "Booked a consultation? Open it from the link we email you once it is paid.",
        },
        "errors": {
            "too_many_pending": "Too many bookings are waiting for payment. Pay one, or wait 30 minutes.",
            "slot_taken": "Someone else took this time. Book another one.",
            "not_payable": "This booking cannot be paid now.",
            "not_bookable": "This consultation takes no new bookings.",
            "too_late": "It is too late to move this consultation.",
            "not_completed": "Rate a consultation once it is complete.",
            "already_reviewed": "You have rated this consultation already.",
            "request_changed": "This booking changed. Try again.",
        },
    },
    "ar": {
        "nav": {"family": "استشاراتي"},
        "book": {
            "title": "احجز استشارة",
            "notFound": "لا يمكن حجز هذه الاستشارة.",
            "closed": "حجز الاستشارات غير متاح.",
            "none": "لا توجد استشارة متاحة للحجز الآن.",
            "pick": "اختر استشارة",
            "minutes": "{{n}} دقيقة",
            "fee": "قد تُضاف رسوم دفع عند الدفع.",
            "signedIn": "لديك حساب؟ احجز من حسابك.",
            "teacher": "اختر معلمًا",
            "time": "اختر موعدًا",
            "noSlots": "لا توجد مواعيد متاحة في هذه الأيام.",
            "slotsError": "تعذّر تحميل المواعيد.",
            "earlier": "أبكر",
            "later": "لاحقًا",
            "academyTime": "بتوقيت الأكاديمية: {{time}}",
            "details": "بياناتك",
            "accountHint": "اترك الحقل فارغًا لاستخدام بيانات حسابك.",
            "child": "لـ",
            "self": "لي",
            "name": "الاسم",
            "email": "البريد الإلكتروني",
            "whatsapp": "واتساب",
            "timezone": "منطقتك الزمنية",
            "notes": "ملاحظات (اختياري)",
            "pay": "الدفع",
            "payWith": "ادفع عبر {{provider}}",
            "noProviders": "الدفع الإلكتروني غير متاح الآن.",
            "keepLink": "احتفظ بهذا الرابط لإدارة حجزك:",
            "notStarted": "حُفظ حجزك لكن الدفع لم يبدأ. افتح حجزك للدفع.",
            "open": "افتح حجزك",
        },
        "manage": {
            "title": "استشارتك",
            "notFound": "رابط الحجز هذا غير صالح.",
            "status": "الحالة",
            "teacher": "المعلم",
            "time": "الموعد",
            "noTime": "الإجابة بالبريد الإلكتروني",
            "payment": "الدفع",
            "paid": "مدفوع {{amount}}",
            "unpaid": "لم يُدفع بعد",
            "holdUntil": "موعدك محجوز حتى {{time}}.",
            "payTitle": "ادفع ثمن حجزك",
            "pay": "ادفع عبر {{provider}}",
            "join": "انضم إلى الاستشارة",
            "proposed": "طلبت نقلها إلى {{time}}.",
            "reschedule": "اطلب تغيير الموعد",
            "note": "ملاحظة (اختياري)",
            "send": "إرسال",
            "review": "قيّم هذه الاستشارة",
            "rating": "التقييم",
            "stars": "{{n}} من 5",
            "comment": "تعليق (اختياري)",
            "sendReview": "أرسل التقييم",
            "reviewSent": "شكرًا لك. تقييمك بانتظار موافقة الأكاديمية.",
            "reviewStatus": {
                "approved": "نُشر تقييمك.",
                "rejected": "لم يُنشر تقييمك.",
            },
        },
        "family": {
            "title": "استشاراتي",
            "subtitle": "احجز استشارة وتابع حجوزاتك.",
            "book": "احجز استشارة",
            "empty": "لا توجد استشارات بعد.",
            "for": "لـ {{name}}",
        },
        "reviews": {
            "empty": "لا توجد تقييمات.",
            "status": "حالة التقييم",
            "approve": "اعتماد",
            "reject": "رفض",
            "reason": "السبب (اختياري)",
            "rating": "{{n}} / 5",
            "statuses": {"pending": "بانتظار المراجعة", "approved": "معتمد", "rejected": "مرفوض"},
            "done": "تم الحفظ.",
        },
        "requests": {
            "tabs": {"reviews": "التقييمات"},
            "filters": {"selfBooked": "الحجز"},
            "selfBooked": "إلكتروني",
            "officeBooked": "عبر الإدارة",
            "fee": "+ رسوم {{fee}}",
            "proposed": "الموعد المقترح: {{time}}",
        },
        "return": {
            "open": "افتح حجزك",
            "mine": "افتح استشاراتي",
            "emailed": "حجزت استشارة؟ افتحها من الرابط الذي نرسله إلى بريدك بعد الدفع.",
        },
        "errors": {
            "too_many_pending": "حجوزات كثيرة بانتظار الدفع. ادفع أحدها أو انتظر 30 دقيقة.",
            "slot_taken": "حجز شخص آخر هذا الموعد. احجز موعدًا آخر.",
            "not_payable": "لا يمكن دفع هذا الحجز الآن.",
            "not_bookable": "هذه الاستشارة لا تقبل حجوزات جديدة.",
            "too_late": "فات وقت تغيير موعد هذه الاستشارة.",
            "not_completed": "قيّم الاستشارة بعد اكتمالها.",
            "already_reviewed": "قيّمت هذه الاستشارة من قبل.",
            "request_changed": "تغيّر هذا الحجز. حاول مرة أخرى.",
        },
    },
}


def merge(into, extra):
    for key, value in extra.items():
        if isinstance(value, dict):
            merge(into.setdefault(key, {}), value)
        else:
            assert key not in into, key
            into[key] = value


for lang, extra in ADD.items():
    path = pathlib.Path(f"dashboard/src/locales/{lang}/consultations.json")
    data = json.loads(path.read_text())
    merge(data, extra)
    path.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")
EOF
F pnpm biome check --write src/locales/en/consultations.json src/locales/ar/consultations.json
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `F pnpm vitest run src/features/consultations src/locales`
Expected: PASS (`locales.test.ts` confirms en and ar are key-equal; B7c's consultations tests still pass with the new `request` fields).

Run: `F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git -C dashboard add src/features/consultations/schemas.ts src/features/consultations/api.ts \
  src/features/consultations/bookingApi.ts src/features/consultations/bookingApi.test.ts \
  src/features/consultations/bookingQueries.ts src/features/consultations/manageLink.ts \
  src/features/consultations/manageLink.test.ts src/features/consultations/fixtures.ts \
  src/features/consultations/index.ts src/locales/en/consultations.json src/locales/ar/consultations.json
git -C dashboard commit -m "feat(consultations): booking data layer, manage-link helpers and strings (B7d)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: The manage page, "My consultations" and the nav item (K-9…K-13)

**Files:**
- Create: `dashboard/src/features/consultations/BookingSlots.tsx`, `ManagePage.tsx`, `ManagePage.test.tsx`, `FamilyConsultations.tsx`, `FamilyConsultations.test.tsx`; `dashboard/src/routes/consult.manage.$token.tsx`, `dashboard/src/routes/consult.test.ts`, `dashboard/src/routes/_authed/learning.consultations.index.tsx`, `dashboard/src/routes/_authed/learning.consultations.$requestId.tsx`
- Modify: `dashboard/src/features/consultations/index.ts`; `dashboard/src/routeTree.gen.ts` (generated); **claims**: `dashboard/src/features/shell/nav.ts`, `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/permissions.test.ts`

**Interfaces:**
- Consumes: Task 14's hooks, `Booker`, `manageView`, `familyRequest`, `bookingSlots`, `TOKEN`, `rememberManage`, `useNoReferrer`; B7c's `TONE` (exported from `RequestsAdmin.tsx`), `consultationsErrorText`; `@/lib/zoned-time` (`dayIn`, `wallTime`, `otherZoneTime`, `todayIn`, `addDays`); `go` from `@/features/gateways/redirect`; `PROVIDER_NAMES`.
- Produces:
  - `BookingSlots({productId, teacherId, zone, value, onChange, lastDay?})`: slot radios named by their time on `zone`'s clock (e.g. "19:00"), with "Academy time: 16:00" when the academy's clock reads differently; pages a week at a time;
  - `ManagePage({booker})`, `FamilyConsultations()`, `productName(p, language)`;
  - public route `/consult/manage/$token`; app routes `/_authed/learning/consultations/` and `/_authed/learning/consultations/$requestId` (feature `consultations`); nav item `/learning/consultations`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/consultations/ManagePage.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { go } from "@/features/gateways/redirect";
import { renderWithRouter } from "@/test/render";
import { bookingApi } from "./bookingApi";
import { bookingSlots, manageView, TOKEN } from "./fixtures";
import { ManagePage } from "./ManagePage";
import { manageTokenFor } from "./manageLink";
import type { ManageView } from "./schemas";

vi.mock("./bookingApi", () => ({
	bookingApi: {
		manage: vi.fn(),
		pay: vi.fn(),
		reschedule: vi.fn(),
		review: vi.fn(),
		slots: vi.fn(),
	},
}));
vi.mock("@/features/gateways/redirect", () => ({ go: vi.fn() }));

const visitor = { kind: "public", token: TOKEN } as const;
const confirmed: ManageView = {
	...manageView,
	status: "confirmed",
	hold_until: null,
	meeting_url: "https://meet.test/bilal",
	payment: { ...manageView.payment, paid: true, method: "stripe", paid_on: "2026-10-11" },
	last_day: "2026-10-25",
	providers: [],
	actions: { pay: false, reschedule: true, review: false },
};

describe("ManagePage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		sessionStorage.clear();
		vi.mocked(bookingApi.manage).mockResolvedValue(manageView);
		vi.mocked(bookingApi.slots).mockResolvedValue(bookingSlots);
	});

	it("shows the booking on the booker's clock, with no link before confirmation", async () => {
		renderWithRouter(<ManagePage booker={visitor} />);
		expect(
			await screen.findByRole("heading", { name: "Placement consultation" }),
		).toBeInTheDocument();
		expect(screen.getByText("Under review")).toBeInTheDocument();
		expect(screen.getByText(/Oct 12, 2026, 19:00/)).toBeInTheDocument();
		expect(screen.getByText("Academy time: 16:00")).toBeInTheDocument();
		expect(screen.getByText("Not paid yet")).toBeInTheDocument();
		expect(screen.queryByRole("link", { name: "Join the consultation" })).toBeNull();
	});

	it("sends no referrer", async () => {
		renderWithRouter(<ManagePage booker={visitor} />);
		await screen.findByRole("heading", { name: "Placement consultation" });
		expect(
			document.head.querySelector('meta[name="referrer"]')?.getAttribute("content"),
		).toBe("no-referrer");
	});

	it("pays again and remembers the link for the return page", async () => {
		vi.mocked(bookingApi.pay).mockResolvedValue({
			id: "c-9",
			redirect_url: "https://pay.test/c-9",
			amount_minor: 1500,
			fee_minor: 0,
			currency: "USD",
		});
		const user = userEvent.setup();
		renderWithRouter(<ManagePage booker={visitor} />);
		await user.click(await screen.findByRole("button", { name: "Pay with Stripe" }));
		await waitFor(() => expect(go).toHaveBeenCalledWith("https://pay.test/c-9"));
		expect(bookingApi.pay).toHaveBeenCalledWith(visitor, "stripe");
		expect(manageTokenFor("c-9")).toBe(TOKEN);
	});

	it("shows the meeting link once confirmed, without a referrer", async () => {
		vi.mocked(bookingApi.manage).mockResolvedValue(confirmed);
		renderWithRouter(<ManagePage booker={visitor} />);
		const join = await screen.findByRole("link", { name: "Join the consultation" });
		expect(join).toHaveAttribute("href", "https://meet.test/bilal");
		expect(join).toHaveAttribute("rel", "noreferrer noopener");
	});

	it("asks to move to an offered time", async () => {
		vi.mocked(bookingApi.manage).mockResolvedValue(confirmed);
		vi.mocked(bookingApi.reschedule).mockResolvedValue({
			...confirmed,
			status: "reschedule_requested",
			proposed_starts_at: "2026-10-12T16:30:00+00:00",
		});
		const user = userEvent.setup();
		renderWithRouter(<ManagePage booker={visitor} />);
		await user.click(await screen.findByRole("radio", { name: "19:30" }));
		await user.type(screen.getByLabelText("Note (optional)"), "Later please");
		await user.click(screen.getByRole("button", { name: "Send" }));
		await waitFor(() =>
			expect(bookingApi.reschedule).toHaveBeenCalledWith(visitor, {
				starts_at: "2026-10-12T16:30:00+00:00",
				note: "Later please",
			}),
		);
	});

	it("rates a completed consultation once", async () => {
		const done: ManageView = {
			...confirmed,
			status: "completed",
			actions: { pay: false, reschedule: false, review: true },
		};
		vi.mocked(bookingApi.manage)
			.mockResolvedValueOnce(done)
			.mockResolvedValue({
				...done,
				actions: { ...done.actions, review: false },
				review: { rating: 5, comment: "Great", status: "pending" },
			});
		vi.mocked(bookingApi.review).mockResolvedValue(done);
		const user = userEvent.setup();
		renderWithRouter(<ManagePage booker={{ kind: "my", id: 5 }} />);
		await user.click(await screen.findByRole("radio", { name: "5 of 5" }));
		await user.type(screen.getByLabelText("Comment (optional)"), "Great");
		await user.click(screen.getByRole("button", { name: "Send review" }));
		expect(
			await screen.findByText("Thank you. Your review waits for the academy's approval."),
		).toBeInTheDocument();
		expect(bookingApi.review).toHaveBeenCalledWith(
			{ kind: "my", id: 5 },
			{ rating: 5, comment: "Great" },
		);
		expect(screen.queryByRole("button", { name: "Send review" })).toBeNull();
	});

	it("says when the link is not valid", async () => {
		vi.mocked(bookingApi.manage).mockRejectedValue(
			new AxiosError("Not found", "404", undefined, undefined, {
				status: 404,
				data: { detail: "Not found." },
			} as never),
		);
		renderWithRouter(<ManagePage booker={visitor} />);
		expect(await screen.findByText("This booking link is not valid.")).toBeInTheDocument();
	});
});
```

`dashboard/src/features/consultations/FamilyConsultations.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { bookingApi } from "./bookingApi";
import { FamilyConsultations } from "./FamilyConsultations";
import { familyRequest } from "./fixtures";

vi.mock("./bookingApi", () => ({ bookingApi: { mine: vi.fn() } }));

const PATHS = ["/learning/consultations/$requestId", "/learning/consultations/book"];

describe("FamilyConsultations", () => {
	beforeEach(() => vi.clearAllMocks());

	it("lists the family's consultations, each opening its page", async () => {
		vi.mocked(bookingApi.mine).mockResolvedValue([familyRequest]);
		renderWithRouter(<FamilyConsultations />, { extraPaths: PATHS });
		const link = await screen.findByRole("link", { name: /Placement consultation/ });
		expect(link).toHaveAttribute("href", expect.stringContaining("/learning/consultations/5"));
		expect(within(link).getByText("Under review")).toBeInTheDocument();
		expect(within(link).getByText(/For Yusuf Omar/)).toBeInTheDocument();
	});

	it("says when there are none", async () => {
		vi.mocked(bookingApi.mine).mockResolvedValue([]);
		renderWithRouter(<FamilyConsultations />, { extraPaths: PATHS });
		expect(await screen.findByText("No consultations yet.")).toBeInTheDocument();
	});
});
```

`dashboard/src/routes/consult.test.ts`:

```ts
import { QueryClient } from "@tanstack/react-query";
import { type AnyRoute, createRouter } from "@tanstack/react-router";
import { describe, expect, it } from "vitest";
import { routeTree } from "@/routeTree.gen";

const router = createRouter({
	routeTree,
	context: { queryClient: new QueryClient() },
});
const byId: Record<string, AnyRoute> = Object.fromEntries(
	(Object.values(router.routesById) as AnyRoute[]).map((r) => [r.id, r]),
);

/** B7d K-9, K-14: a visitor has no account, so the booking pages hang off
 * the root, never `_authed` (whose `beforeLoad` would send them to login). */
describe("public consultation routes", () => {
	it.each(["/consult/manage/$token"])("%s is outside the app shell", (id) => {
		expect(byId[id]).toBeDefined();
		expect(byId[id].parentRoute?.id).toBe("__root__");
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `F pnpm vitest run src/features/consultations/ManagePage.test.tsx src/features/consultations/FamilyConsultations.test.tsx src/routes/consult.test.ts`
Expected: FAIL with `Failed to resolve import "./ManagePage"`.

- [ ] **Step 3: The slot list**

`dashboard/src/features/consultations/BookingSlots.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { addDays, dayIn, otherZoneTime, todayIn, wallTime } from "@/lib/zoned-time";
import { Button, Spinner } from "@/ui";
import { useBookingSlots } from "./bookingQueries";
import type { Slot } from "./schemas";

const DAYS = 7;

/** K-2: one teacher's free slots, a week at a time, on the booker's clock
 * (`zone`), with the academy's as a second line ("system timezone",
 * CONS-002). `lastDay` stops paging (a reschedule's validity). */
export function BookingSlots({
	productId,
	teacherId,
	zone,
	value,
	onChange,
	lastDay,
}: {
	productId: number;
	teacherId: number;
	zone: string;
	value: string;
	onChange: (startsAt: string) => void;
	lastDay?: string | null;
}) {
	const { t, i18n } = useTranslation();
	const [from, setFrom] = useState<string>();
	const slots = useBookingSlots(productId, { teacher: teacherId, from });
	const academy = slots.data?.academy_timezone ?? zone;
	const today = todayIn(academy);
	const first = from ?? today;
	const last = lastDay ?? slots.data?.last_day;
	const byDay = new Map<string, Slot[]>();
	for (const slot of slots.data?.slots ?? []) {
		const day = dayIn(new Date(slot.starts_at), zone, i18n.language);
		byDay.set(day, [...(byDay.get(day) ?? []), slot]);
	}
	const earlier = addDays(first, -DAYS);
	return (
		<fieldset className="flex flex-col gap-2">
			<legend className="font-medium">{t("consultations.book.time")}</legend>
			{slots.isPending && slots.fetchStatus !== "idle" ? <Spinner /> : null}
			{slots.isError ? (
				<p className="text-sm text-destructive">{t("consultations.book.slotsError")}</p>
			) : null}
			{slots.data && byDay.size === 0 ? (
				<p className="text-sm text-muted-foreground">{t("consultations.book.noSlots")}</p>
			) : null}
			{[...byDay.entries()].map(([day, items]) => (
				<fieldset key={day} className="flex flex-col gap-1">
					<legend className="text-sm text-muted-foreground">{day}</legend>
					<div className="flex flex-wrap gap-2">
						{items.map((slot) => {
							const at = new Date(slot.starts_at);
							const time = wallTime(at, zone, i18n.language);
							const theirs = otherZoneTime(at, academy, zone, i18n.language);
							return (
								<label
									key={slot.starts_at}
									className="cursor-pointer rounded-md border border-border px-3 py-1 text-sm has-[:checked]:border-primary has-[:checked]:bg-primary has-[:checked]:text-primary-foreground has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring"
								>
									<input
										type="radio"
										name="booking-slot"
										className="sr-only"
										aria-label={time}
										checked={value === slot.starts_at}
										onChange={() => onChange(slot.starts_at)}
									/>
									<span>{time}</span>
									{theirs ? (
										<span className="block text-xs">
											{t("consultations.book.academyTime", { time: theirs })}
										</span>
									) : null}
								</label>
							);
						})}
					</div>
				</fieldset>
			))}
			<div className="flex gap-2">
				<Button
					type="button"
					size="sm"
					variant="outline"
					disabled={first <= today}
					onClick={() => setFrom(earlier < today ? today : earlier)}
				>
					{t("consultations.book.earlier")}
				</Button>
				<Button
					type="button"
					size="sm"
					variant="outline"
					disabled={!!last && addDays(first, DAYS) > last}
					onClick={() => setFrom(addDays(first, DAYS))}
				>
					{t("consultations.book.later")}
				</Button>
			</div>
		</fieldset>
	);
}
```

- [ ] **Step 4: The manage page and the family list**

`dashboard/src/features/consultations/ManagePage.tsx`:

```tsx
import { isAxiosError } from "axios";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { go } from "@/features/gateways/redirect";
import { PROVIDER_NAMES, type Provider } from "@/features/gateways/schemas";
import { formatMoney } from "@/lib/money";
import { dayIn, otherZoneTime, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Field,
	FormError,
	Spinner,
	StatusChip,
	Textarea,
} from "@/ui";
import { BookingSlots } from "./BookingSlots";
import {
	useAskReschedule,
	useManage,
	usePayBooking,
	useReviewBooking,
} from "./bookingQueries";
import { consultationsErrorText } from "./errors";
import { rememberManage, useNoReferrer } from "./manageLink";
import { TONE } from "./RequestsAdmin";
import type { Booker } from "./schemas";

export function productName(p: { name_ar: string; name_en: string }, language: string) {
	return language === "ar" ? p.name_ar || p.name_en : p.name_en || p.name_ar;
}

/** K-10, K-13: a booking's own page, by its link's token (a visitor) or by
 * id (a family). The payload has no contact details. The page sends no
 * referrer, so the token cannot leak (K-9). No booker cancellation. */
export function ManagePage({ booker }: { booker: Booker }) {
	const { t, i18n } = useTranslation();
	const lang = i18n.language;
	useNoReferrer();
	const view = useManage(booker);
	const pay = usePayBooking(booker);
	const ask = useAskReschedule(booker);
	const rate = useReviewBooking(booker);
	const [moving, setMoving] = useState("");
	const [note, setNote] = useState("");
	const [rating, setRating] = useState(0);
	const [comment, setComment] = useState("");
	if (view.isPending) return <Spinner />;
	if (view.isError)
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{isAxiosError(view.error) && view.error.response?.status === 404
						? t("consultations.manage.notFound")
						: consultationsErrorText(view.error, t)}
				</AlertDescription>
			</Alert>
		);
	const v = view.data;
	const failure = pay.error ?? ask.error ?? rate.error;
	const when = (iso: string) => {
		const at = new Date(iso);
		return `${dayIn(at, v.timezone, lang)}, ${wallTime(at, v.timezone, lang)}`;
	};
	const academyLine = v.starts_at
		? otherZoneTime(new Date(v.starts_at), v.academy_timezone, v.timezone, lang)
		: null;

	async function payWith(provider: Provider) {
		const started = await pay.mutateAsync(provider);
		if (booker.kind === "public")
			rememberManage(started.id, `/consult/manage/${booker.token}`);
		go(started.redirect_url);
	}

	return (
		<div className="flex flex-col gap-4">
			<header className="flex flex-col gap-1">
				<h1 className="text-xl font-semibold">{productName(v.product, lang)}</h1>
				<p className="text-sm text-muted-foreground">{v.reference}</p>
			</header>
			<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
				<dt>{t("consultations.manage.status")}</dt>
				<dd>
					<StatusChip tone={TONE[v.status]}>
						{t(`consultations.statuses.${v.status}`)}
					</StatusChip>
				</dd>
				<dt>{t("consultations.manage.teacher")}</dt>
				<dd>{v.teacher.full_name}</dd>
				<dt>{t("consultations.manage.time")}</dt>
				<dd>
					{v.starts_at ? when(v.starts_at) : t("consultations.manage.noTime")}
					{academyLine ? (
						<span className="block text-xs text-muted-foreground">
							{t("consultations.book.academyTime", { time: academyLine })}
						</span>
					) : null}
				</dd>
				<dt>{t("consultations.manage.payment")}</dt>
				<dd>
					{v.payment.paid
						? t("consultations.manage.paid", {
								amount: formatMoney(
									v.payment.amount_minor + v.payment.fee_minor,
									v.payment.currency,
									lang,
								),
							})
						: t("consultations.manage.unpaid")}
				</dd>
			</dl>
			{v.proposed_starts_at ? (
				<p className="text-sm">
					{t("consultations.manage.proposed", { time: when(v.proposed_starts_at) })}
				</p>
			) : null}
			{v.meeting_url ? (
				<Button asChild className="self-start">
					<a href={v.meeting_url} target="_blank" rel="noreferrer noopener">
						{t("consultations.manage.join")}
					</a>
				</Button>
			) : null}
			{failure ? <FormError>{consultationsErrorText(failure, t)}</FormError> : null}
			{v.actions.pay ? (
				<section
					aria-label={t("consultations.manage.payTitle")}
					className="flex flex-col gap-2"
				>
					{v.hold_until ? (
						<p className="text-sm text-muted-foreground">
							{t("consultations.manage.holdUntil", { time: when(v.hold_until) })}
						</p>
					) : null}
					<div className="flex flex-wrap gap-2">
						{v.providers.map((provider) => (
							<Button
								key={provider}
								disabled={pay.isPending}
								onClick={() => void payWith(provider).catch(() => undefined)}
							>
								{t("consultations.manage.pay", {
									provider: PROVIDER_NAMES[provider],
								})}
							</Button>
						))}
					</div>
				</section>
			) : null}
			{v.actions.reschedule ? (
				<section
					aria-label={t("consultations.manage.reschedule")}
					className="flex flex-col gap-3"
				>
					<h2 className="font-medium">{t("consultations.manage.reschedule")}</h2>
					<BookingSlots
						productId={v.product.id}
						teacherId={v.teacher.user_id}
						zone={v.timezone}
						value={moving}
						onChange={setMoving}
						lastDay={v.last_day}
					/>
					<Field id="move-note" label={t("consultations.manage.note")}>
						<Textarea value={note} onChange={(e) => setNote(e.target.value)} />
					</Field>
					<Button
						className="self-start"
						disabled={!moving || ask.isPending}
						onClick={() => ask.mutate({ starts_at: moving, note })}
					>
						{t("consultations.manage.send")}
					</Button>
				</section>
			) : null}
			{v.actions.review ? (
				<section
					aria-label={t("consultations.manage.review")}
					className="flex flex-col gap-3"
				>
					<fieldset className="flex gap-2">
						<legend className="font-medium">{t("consultations.manage.rating")}</legend>
						{[1, 2, 3, 4, 5].map((n) => (
							<label key={n} className="cursor-pointer text-lg">
								<input
									type="radio"
									name="review-rating"
									className="sr-only"
									aria-label={t("consultations.manage.stars", { n })}
									checked={rating === n}
									onChange={() => setRating(n)}
								/>
								<span aria-hidden>{n <= rating ? "★" : "☆"}</span>
							</label>
						))}
					</fieldset>
					<Field id="review-comment" label={t("consultations.manage.comment")}>
						<Textarea
							maxLength={1000}
							value={comment}
							onChange={(e) => setComment(e.target.value)}
						/>
					</Field>
					<Button
						className="self-start"
						disabled={rating === 0 || rate.isPending}
						onClick={() => rate.mutate({ rating, comment })}
					>
						{t("consultations.manage.sendReview")}
					</Button>
				</section>
			) : null}
			{v.review ? (
				<p className="text-sm">
					{v.review.status === "pending"
						? t("consultations.manage.reviewSent")
						: t(`consultations.manage.reviewStatus.${v.review.status}`)}
				</p>
			) : null}
		</div>
	);
}
```

`dashboard/src/features/consultations/FamilyConsultations.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { MessagesSquare } from "lucide-react";
import { useTranslation } from "react-i18next";
import { dayIn, wallTime } from "@/lib/zoned-time";
import { Card, CardContent, EmptyState, FormError, Spinner, StatusChip } from "@/ui";
import { useMyConsultations } from "./bookingQueries";
import { consultationsErrorText } from "./errors";
import { productName } from "./ManagePage";
import { TONE } from "./RequestsAdmin";

/** K-13: a student's consultations, and a parent's children's and their own. */
export function FamilyConsultations() {
	const { t, i18n } = useTranslation();
	const list = useMyConsultations();
	if (list.isPending) return <Spinner />;
	if (list.isError) return <FormError>{consultationsErrorText(list.error, t)}</FormError>;
	if (list.data.length === 0)
		return (
			<Card>
				<CardContent>
					<EmptyState icon={MessagesSquare} title={t("consultations.family.empty")} />
				</CardContent>
			</Card>
		);
	return (
		<ul className="flex flex-col gap-2">
			{list.data.map((r) => {
				const at = r.starts_at ? new Date(r.starts_at) : null;
				const when = at
					? `${dayIn(at, r.timezone, i18n.language)}, ${wallTime(at, r.timezone, i18n.language)}`
					: t("consultations.manage.noTime");
				return (
					<li key={r.id}>
						<Link
							to="/learning/consultations/$requestId"
							params={{ requestId: String(r.id) }}
							className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border p-3"
						>
							<span className="flex flex-col">
								<span className="font-medium">{productName(r.product, i18n.language)}</span>
								<span className="text-sm text-muted-foreground">
									{when}
									{r.student
										? ` · ${t("consultations.family.for", { name: r.student.full_name })}`
										: ""}
								</span>
							</span>
							<StatusChip tone={TONE[r.status]}>
								{t(`consultations.statuses.${r.status}`)}
							</StatusChip>
						</Link>
					</li>
				);
			})}
		</ul>
	);
}
```

In `index.ts`, add `export { BookingSlots } from "./BookingSlots";`, `export { FamilyConsultations } from "./FamilyConsultations";`, `export { ManagePage, productName } from "./ManagePage";`.

- [ ] **Step 5: The routes**

`dashboard/src/routes/consult.manage.$token.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ManagePage } from "@/features/consultations";
import { PublicFrame } from "@/features/gateways";

// Plan 60 (B7d K-9, K-10): a booking's own page, by its unguessable token;
// no sign-in. A malformed or unknown token is the server's 404.
export const Route = createFileRoute("/consult/manage/$token")({
	component: function ConsultManageRoute() {
		const { t } = useTranslation();
		const { token } = Route.useParams();
		usePageTitle(t("consultations.manage.title"));
		return (
			<PublicFrame>
				<ManagePage booker={{ kind: "public", token }} />
			</PublicFrame>
		);
	},
});
```

`dashboard/src/routes/_authed/learning.consultations.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { FamilyConsultations } from "@/features/consultations";
import { PageHeader } from "@/ui";

// Plan 60 (B7d K-13): a family's consultations.
export const Route = createFileRoute("/_authed/learning/consultations/")({
	staticData: { feature: "consultations" },
	component: function FamilyConsultationsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("consultations.family.title"));
		return (
			<>
				<PageHeader
					title={t("consultations.family.title")}
					description={t("consultations.family.subtitle")}
				/>
				<FamilyConsultations />
			</>
		);
	},
});
```

`dashboard/src/routes/_authed/learning.consultations.$requestId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { ManagePage } from "@/features/consultations";

// Plan 60 (B7d K-13): the manage page's signed-in twin, by ownership.
export const Route = createFileRoute("/_authed/learning/consultations/$requestId")({
	staticData: { feature: "consultations" },
	component: function FamilyConsultationRoute() {
		const { t } = useTranslation();
		const { requestId } = Route.useParams();
		usePageTitle(t("consultations.manage.title"));
		return <ManagePage booker={{ kind: "my", id: Number(requestId) }} />;
	},
});
```

Regenerate the route tree: `F pnpm build` (B7b PF20: there is no tsr CLI).

- [ ] **Step 6: The nav item and its tables (claims, one commit)**

```bash
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/shell/nav.ts --reason "B7d K-13: /learning/consultations nav item"
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/shell/nav.test.ts --reason "B7d K-13: the nav item in the nav tables"
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/routes/permissions.test.ts --reason "B7d: FEATURE_SCREENS for the family consultation pages"
```

In `nav.ts`, under `── phase B7 ──`, after B7c's `/teaching/consultations` item:

```ts
	// B7d: a family's consultations (and booking one).
	{
		to: "/learning/consultations",
		labelKey: "consultations.nav.family",
		icon: MessagesSquare,
		group: "learning",
		requiresRole: ["student", "parent"],
		feature: "consultations",
	},
```

In `nav.test.ts`:
- in the list of every nav path, after `"/teaching/consultations",` add `"/learning/consultations", // B7d`;
- in the path → feature map, after `"/teaching/consultations": "consultations",` add `"/learning/consultations": "consultations", // B7d`;
- in the student/parent visible list, after `"/learning/recorded/store", // B7b` add `"/learning/consultations", // B7d`;
- run the file; if a length assertion on the `learning` group fails, raise that count by one and add `+ B7d consultations` to its comment.

In `routes/permissions.test.ts` `FEATURE_SCREENS`, after the B7b lines:

```ts
	// B7d
	"/_authed/learning/consultations/": "consultations",
	"/_authed/learning/consultations/$requestId": "consultations",
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `F pnpm vitest run src/features/consultations src/features/shell src/routes`
Expected: PASS.

Run: `F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 8: Commit (then release the three claims)**

```bash
git -C dashboard add src/features/consultations/BookingSlots.tsx src/features/consultations/ManagePage.tsx \
  src/features/consultations/ManagePage.test.tsx src/features/consultations/FamilyConsultations.tsx \
  src/features/consultations/FamilyConsultations.test.tsx src/features/consultations/index.ts \
  'src/routes/consult.manage.$token.tsx' src/routes/consult.test.ts \
  src/routes/_authed/learning.consultations.index.tsx 'src/routes/_authed/learning.consultations.$requestId.tsx' \
  src/routeTree.gen.ts src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts
git -C dashboard commit -m "feat(consultations): manage page, My consultations and its nav item (B7d K-9…K-13)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/shell/nav.ts
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/shell/nav.test.ts
python3 scripts/orchestration/ledger.py release B7 dashboard/src/routes/permissions.test.ts
```

---

### Task 16: The booking wizard, public and signed in (K-2, K-3, K-13, K-14)

**Files:**
- Create: `dashboard/src/features/consultations/BookingWizard.tsx`, `BookingWizard.test.tsx`, `BookPicker.tsx`; `dashboard/src/routes/consult.$productId.tsx`, `dashboard/src/routes/_authed/learning.consultations.book.tsx`
- Modify: `dashboard/src/features/consultations/FamilyConsultations.tsx` (+ test: the "Book" link), `index.ts`, `dashboard/src/routes/consult.test.ts`; `dashboard/src/routeTree.gen.ts` (generated); **claim**: `dashboard/src/routes/permissions.test.ts`

**Interfaces:**
- Consumes: Task 14 (`usePublicProduct`, `useBook`, `useBookableProducts`, `rememberManage`, `tokenOf`, `publicDetail`, `bookingSlots`, `TOKEN`); Task 15 (`BookingSlots`, `productName`, routes `/consult/manage/$token`, `/learning/consultations/$requestId`); `useMe` (`me.role`, `me.children`); `go`; `Money`.
- Produces: `BookingWizard({productId, signedIn?})`, `BookPicker()`, `browserZone()`; public route `/consult/$productId`; app route `/_authed/learning/consultations/book?product=<id>`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/consultations/BookingWizard.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { go } from "@/features/gateways/redirect";
import { identityApi } from "@/features/identity/api";
import { renderWithRouter } from "@/test/render";
import { bookingApi } from "./bookingApi";
import { BookingWizard } from "./BookingWizard";
import { BookPicker } from "./BookPicker";
import { bookingSlots, publicDetail, publicProduct, TOKEN } from "./fixtures";
import type { BookAnswer } from "./schemas";

vi.mock("./bookingApi", () => ({
	bookingApi: { product: vi.fn(), products: vi.fn(), slots: vi.fn(), book: vi.fn() },
}));
vi.mock("@/features/gateways/redirect", () => ({ go: vi.fn() }));
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

const PATHS = [
	"/learning/consultations/book",
	"/learning/consultations/$requestId",
	"/consult/manage/$token",
];
const MANAGE_URL = `http://demo.etqan.localhost/app/consult/manage/${TOKEN}`;
const answer: BookAnswer = {
	request: { id: 5, manage_url: MANAGE_URL },
	checkout: {
		id: "c-1",
		redirect_url: "https://pay.test/c-1",
		amount_minor: 1500,
		fee_minor: 75,
		currency: "USD",
	},
};

async function choose(user: ReturnType<typeof userEvent.setup>) {
	await user.selectOptions(await screen.findByLabelText("Your timezone"), "Asia/Riyadh");
	await user.click(screen.getByRole("radio", { name: "Ustadh Bilal" }));
	await user.click(await screen.findByRole("radio", { name: "19:00" }));
}

async function details(user: ReturnType<typeof userEvent.setup>) {
	await user.type(screen.getByLabelText("Name"), "Sara");
	await user.type(screen.getByLabelText("Email"), "sara@x.test");
	await user.type(screen.getByLabelText("WhatsApp"), "+201000000009");
}

describe("BookingWizard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		sessionStorage.clear();
		vi.mocked(bookingApi.product).mockResolvedValue(publicDetail);
		vi.mocked(bookingApi.slots).mockResolvedValue(bookingSlots);
		vi.mocked(bookingApi.book).mockResolvedValue(answer);
	});

	it("books a visitor: teacher, time, details, provider, then the total and the link", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BookingWizard productId={3} />, { extraPaths: PATHS });
		expect(
			await screen.findByRole("heading", { name: "Placement consultation" }),
		).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Pay with Stripe" })).toBeDisabled();
		await choose(user);
		expect(screen.getAllByText("Academy time: 16:00").length).toBeGreaterThan(0);
		await details(user);
		await user.click(screen.getByRole("button", { name: "Pay with Stripe" }));
		expect(bookingApi.book).toHaveBeenCalledWith(
			{
				product: 3,
				teacher: 8,
				starts_at: "2026-10-12T16:00:00+00:00",
				name: "Sara",
				email: "sara@x.test",
				whatsapp: "+201000000009",
				notes: "",
				timezone: "Asia/Riyadh",
				provider: "stripe",
				language: "en",
			},
			false,
		);
		const sheet = await screen.findByRole("region", { name: "Pay online" });
		expect(within(sheet).getByText(/16\.50/)).toBeInTheDocument();
		expect(within(sheet).getByRole("link", { name: MANAGE_URL })).toBeInTheDocument();
		expect(sessionStorage.getItem("consult:c-1")).toBe(MANAGE_URL);
		await user.click(within(sheet).getByRole("button", { name: "Continue to Stripe" }));
		expect(go).toHaveBeenCalledWith("https://pay.test/c-1");
	});

	it("skips the time for an email consultation", async () => {
		vi.mocked(bookingApi.product).mockResolvedValue({
			...publicDetail,
			delivery_mode: "email",
		});
		const user = userEvent.setup();
		renderWithRouter(<BookingWizard productId={3} />, { extraPaths: PATHS });
		await user.click(await screen.findByRole("radio", { name: "Ustadh Bilal" }));
		expect(screen.queryByText("Choose a time")).toBeNull();
		await details(user);
		await user.click(screen.getByRole("button", { name: "Pay with PayPal" }));
		await waitFor(() =>
			expect(vi.mocked(bookingApi.book).mock.calls[0][0]).toMatchObject({
				starts_at: null,
				provider: "paypal",
			}),
		);
	});

	it("keeps the booking when the payment does not start", async () => {
		vi.mocked(bookingApi.book).mockResolvedValue({ ...answer, checkout: null });
		const user = userEvent.setup();
		renderWithRouter(<BookingWizard productId={3} />, { extraPaths: PATHS });
		await choose(user);
		await details(user);
		await user.click(screen.getByRole("button", { name: "Pay with Stripe" }));
		expect(
			await screen.findByText(/the payment did not start/),
		).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Open your booking" })).toHaveAttribute(
			"href",
			expect.stringContaining(`/consult/manage/${TOKEN}`),
		);
	});

	it("lets a signed-in parent book for a child", async () => {
		vi.mocked(identityApi.me).mockResolvedValue({
			id: 31,
			email: "omar@x.test",
			full_name: "Omar",
			role: "parent",
			profiles: [],
			children: [{ id: 21, full_name: "Yusuf Omar" }],
		} as never);
		const user = userEvent.setup();
		renderWithRouter(<BookingWizard productId={3} signedIn />, { extraPaths: PATHS });
		await choose(user);
		await user.selectOptions(await screen.findByLabelText("For"), "21");
		await user.click(screen.getByRole("button", { name: "Pay with Stripe" }));
		await waitFor(() =>
			expect(bookingApi.book).toHaveBeenCalledWith(
				expect.objectContaining({ student: 21, name: "" }),
				true,
			),
		);
		const sheet = await screen.findByRole("region", { name: "Pay online" });
		expect(within(sheet).queryByText("Keep this link to manage your booking:")).toBeNull();
	});

	it("shows the server's field errors", async () => {
		vi.mocked(bookingApi.book).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { email: ["Enter a valid email."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<BookingWizard productId={3} />, { extraPaths: PATHS });
		await choose(user);
		await details(user);
		await user.click(screen.getByRole("button", { name: "Pay with Stripe" }));
		expect(await screen.findByText("Enter a valid email.")).toBeInTheDocument();
	});

	it("says when the consultation cannot be booked", async () => {
		vi.mocked(bookingApi.product).mockRejectedValue(
			new AxiosError("Not found", "404", undefined, undefined, {
				status: 404,
				data: { detail: "Not found." },
			} as never),
		);
		renderWithRouter(<BookingWizard productId={3} />, { extraPaths: PATHS });
		expect(
			await screen.findByText("This consultation cannot be booked."),
		).toBeInTheDocument();
	});
});

describe("BookPicker", () => {
	it("lists the bookable consultations", async () => {
		vi.mocked(bookingApi.products).mockResolvedValue([publicProduct]);
		renderWithRouter(<BookPicker />, { extraPaths: PATHS });
		const link = await screen.findByRole("link", { name: /Placement consultation/ });
		expect(link).toHaveAttribute("href", expect.stringContaining("product=3"));
	});
});
```

Add to `FamilyConsultations.test.tsx`, inside the `describe`:

```tsx
	it("offers to book a consultation", async () => {
		vi.mocked(bookingApi.mine).mockResolvedValue([]);
		renderWithRouter(<FamilyConsultations />, { extraPaths: PATHS });
		expect(
			await screen.findByRole("link", { name: "Book a consultation" }),
		).toHaveAttribute("href", expect.stringContaining("/learning/consultations/book"));
	});
```

In `routes/consult.test.ts`, change the `it.each` list to `["/consult/$productId", "/consult/manage/$token"]`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `F pnpm vitest run src/features/consultations/BookingWizard.test.tsx src/features/consultations/FamilyConsultations.test.tsx src/routes/consult.test.ts`
Expected: FAIL with `Failed to resolve import "./BookingWizard"`.

- [ ] **Step 3: Implement the wizard and the picker**

`dashboard/src/features/consultations/BookingWizard.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { go } from "@/features/gateways/redirect";
import { PROVIDER_NAMES, type Provider } from "@/features/gateways/schemas";
import { useMe } from "@/features/identity/queries";
import { formatMoney } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	Field,
	FormError,
	Input,
	Select,
	Spinner,
	Textarea,
} from "@/ui";
import { BookingSlots } from "./BookingSlots";
import { useBook, usePublicProduct } from "./bookingQueries";
import { formErrors } from "./errors";
import { productName } from "./ManagePage";
import { rememberManage, tokenOf } from "./manageLink";
import type { BookAnswer, BookBody, PublicProductDetail } from "./schemas";

const INPUTS = ["name", "email", "whatsapp", "timezone", "notes"] as const;

export function browserZone(): string {
	try {
		return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
	} catch {
		return "UTC";
	}
}

function zones(current: string): string[] {
	const all =
		typeof Intl.supportedValuesOf === "function"
			? Intl.supportedValuesOf("timeZone")
			: [];
	return all.includes(current) ? all : [current, ...all];
}

/** K-14, K-13: teacher, then time (not for email), then details, then a
 * provider. A visitor needs no account (posts to public/book); a signed-in
 * family posts to my/book and a parent may name a child. */
export function BookingWizard({
	productId,
	signedIn = false,
}: {
	productId: number;
	signedIn?: boolean;
}) {
	const { t, i18n } = useTranslation();
	const product = usePublicProduct(productId);
	const me = useMe({ enabled: signedIn });
	const book = useBook(signedIn);
	const [teacher, setTeacher] = useState<number>();
	const [startsAt, setStartsAt] = useState("");
	const [form, setForm] = useState({ name: "", email: "", whatsapp: "", notes: "" });
	const [zone, setZone] = useState(browserZone);
	const [child, setChild] = useState<number>();
	const [done, setDone] = useState<{ answer: BookAnswer; provider: Provider } | null>(
		null,
	);
	if (product.isPending) return <Spinner />;
	if (product.isError)
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("consultations.book.notFound")}</AlertDescription>
			</Alert>
		);
	const p = product.data;
	if (done)
		return (
			<Booked product={p} answer={done.answer} provider={done.provider} signedIn={signedIn} />
		);
	const slotted = p.delivery_mode !== "email";
	const children = signedIn && me.data?.role === "parent" ? (me.data.children ?? []) : [];
	const errors = book.error ? formErrors(book.error, t, INPUTS) : null;
	const filled =
		signedIn ||
		(form.name.trim() !== "" && form.email.trim() !== "" && form.whatsapp.trim() !== "");
	const ready = teacher !== undefined && (!slotted || startsAt !== "") && filled;
	const set =
		(key: keyof typeof form) => (e: { target: { value: string } }) =>
			setForm((f) => ({ ...f, [key]: e.target.value }));

	async function pay(provider: Provider) {
		const body: BookBody = {
			product: p.id,
			teacher: teacher as number,
			starts_at: slotted ? startsAt : null,
			...form,
			timezone: zone,
			provider,
			language: i18n.language === "ar" ? "ar" : "en",
			...(child !== undefined ? { student: child } : {}),
		};
		const answer = await book.mutateAsync(body);
		if (answer.checkout && !signedIn)
			rememberManage(answer.checkout.id, answer.request.manage_url);
		setDone({ answer, provider });
	}

	return (
		<div className="flex flex-col gap-6">
			<header className="flex flex-col gap-1">
				<h1 className="text-xl font-semibold">{productName(p, i18n.language)}</h1>
				<p className="text-sm text-muted-foreground">
					{t("consultations.book.minutes", { n: p.duration_minutes })} ·{" "}
					{formatMoney(p.price_minor, p.currency, i18n.language)}
				</p>
				{p.fee_enabled ? (
					<p className="text-xs text-muted-foreground">{t("consultations.book.fee")}</p>
				) : null}
				{signedIn ? null : (
					<Link
						to="/learning/consultations/book"
						search={{ product: p.id }}
						className="text-sm underline"
					>
						{t("consultations.book.signedIn")}
					</Link>
				)}
			</header>
			<fieldset className="flex flex-col gap-2">
				<legend className="font-medium">{t("consultations.book.teacher")}</legend>
				{p.teachers.map((tc) => (
					<label
						key={tc.user_id}
						className="flex cursor-pointer items-start gap-3 rounded-md border border-border p-3 has-[:checked]:border-primary"
					>
						<input
							type="radio"
							name="booking-teacher"
							aria-label={tc.full_name}
							checked={teacher === tc.user_id}
							onChange={() => {
								setTeacher(tc.user_id);
								setStartsAt("");
							}}
						/>
						<span
							aria-hidden
							className="flex size-8 items-center justify-center rounded-full bg-secondary font-medium"
						>
							{tc.initial}
						</span>
						<span className="flex flex-col">
							<span className="font-medium">{tc.full_name}</span>
							{tc.bio ? (
								<span className="whitespace-pre-line text-sm text-muted-foreground">
									{tc.bio}
								</span>
							) : null}
						</span>
					</label>
				))}
			</fieldset>
			{slotted && teacher !== undefined ? (
				<BookingSlots
					productId={p.id}
					teacherId={teacher}
					zone={zone}
					value={startsAt}
					onChange={setStartsAt}
				/>
			) : null}
			<fieldset className="flex flex-col gap-3">
				<legend className="font-medium">{t("consultations.book.details")}</legend>
				{signedIn ? (
					<p className="text-sm text-muted-foreground">
						{t("consultations.book.accountHint")}
					</p>
				) : null}
				{children.length > 0 ? (
					<Field id="book-child" label={t("consultations.book.child")}>
						<Select
							value={child ?? ""}
							onChange={(e) =>
								setChild(e.target.value ? Number(e.target.value) : undefined)
							}
						>
							<option value="">{t("consultations.book.self")}</option>
							{children.map((c) => (
								<option key={c.id} value={c.id}>
									{c.full_name}
								</option>
							))}
						</Select>
					</Field>
				) : null}
				<Field
					id="book-name"
					label={t("consultations.book.name")}
					required={!signedIn}
					error={errors?.fields.name}
				>
					<Input value={form.name} onChange={set("name")} autoComplete="name" />
				</Field>
				<Field
					id="book-email"
					label={t("consultations.book.email")}
					required={!signedIn}
					error={errors?.fields.email}
				>
					<Input type="email" value={form.email} onChange={set("email")} autoComplete="email" />
				</Field>
				<Field
					id="book-whatsapp"
					label={t("consultations.book.whatsapp")}
					required={!signedIn}
					error={errors?.fields.whatsapp}
				>
					<Input type="tel" value={form.whatsapp} onChange={set("whatsapp")} autoComplete="tel" />
				</Field>
				<Field
					id="book-timezone"
					label={t("consultations.book.timezone")}
					error={errors?.fields.timezone}
				>
					<Select value={zone} onChange={(e) => setZone(e.target.value)}>
						{zones(zone).map((z) => (
							<option key={z} value={z}>
								{z}
							</option>
						))}
					</Select>
				</Field>
				<Field id="book-notes" label={t("consultations.book.notes")} error={errors?.fields.notes}>
					<Textarea value={form.notes} onChange={set("notes")} maxLength={2000} />
				</Field>
			</fieldset>
			{errors?.form ? <FormError>{errors.form}</FormError> : null}
			<fieldset className="flex flex-col gap-2">
				<legend className="font-medium">{t("consultations.book.pay")}</legend>
				{p.providers.length === 0 ? (
					<Alert>
						<AlertDescription>{t("consultations.book.noProviders")}</AlertDescription>
					</Alert>
				) : (
					<div className="flex flex-wrap gap-2">
						{p.providers.map((provider) => (
							<Button
								key={provider}
								disabled={!ready || book.isPending}
								onClick={() => void pay(provider).catch(() => undefined)}
							>
								{t("consultations.book.payWith", { provider: PROVIDER_NAMES[provider] })}
							</Button>
						))}
					</div>
				)}
			</fieldset>
		</div>
	);
}

/** K-3, K-9: the server's amounts before the redirect, and (for a visitor)
 * the manage link at once; a payment that did not start links to the
 * booking, whose page offers Pay while the hold lasts. */
function Booked({
	product,
	answer,
	provider,
	signedIn,
}: {
	product: PublicProductDetail;
	answer: BookAnswer;
	provider: Provider;
	signedIn: boolean;
}) {
	const { t, i18n } = useTranslation();
	const token = tokenOf(answer.request.manage_url);
	const open = signedIn ? (
		<Link
			to="/learning/consultations/$requestId"
			params={{ requestId: String(answer.request.id) }}
			className="underline"
		>
			{t("consultations.book.open")}
		</Link>
	) : token ? (
		<Link to="/consult/manage/$token" params={{ token }} className="underline">
			{t("consultations.book.open")}
		</Link>
	) : null;
	const c = answer.checkout;
	if (!c)
		return (
			<Alert variant="destructive">
				<AlertDescription className="flex flex-col gap-2">
					<span>{t("consultations.book.notStarted")}</span>
					{open}
				</AlertDescription>
			</Alert>
		);
	return (
		<Card>
			<CardContent className="pt-6">
				<section aria-label={t("gateways.pay.title")} className="flex flex-col gap-4">
					<h2 className="font-medium">{t("gateways.pay.title")}</h2>
					<dl className="grid grid-cols-2 gap-2 text-sm">
						<dt>{productName(product, i18n.language)}</dt>
						<dd>
							<Money minor={c.amount_minor} currency={c.currency} />
						</dd>
						<dt>{t("gateways.pay.fee")}</dt>
						<dd>
							<Money minor={c.fee_minor} currency={c.currency} />
						</dd>
						<dt className="font-medium">{t("gateways.pay.total")}</dt>
						<dd className="font-medium">
							<Money minor={c.amount_minor + c.fee_minor} currency={c.currency} />
						</dd>
					</dl>
					{signedIn ? null : (
						<div className="flex flex-col gap-1 text-sm">
							<p>{t("consultations.book.keepLink")}</p>
							<a
								href={answer.request.manage_url}
								rel="noreferrer noopener"
								className="break-all underline"
							>
								{answer.request.manage_url}
							</a>
						</div>
					)}
					<Button className="self-start" onClick={() => go(c.redirect_url)}>
						{t("gateways.pay.continue", { provider: PROVIDER_NAMES[provider] })}
					</Button>
				</section>
			</CardContent>
		</Card>
	);
}
```

`dashboard/src/features/consultations/BookPicker.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { MessagesSquare } from "lucide-react";
import { useTranslation } from "react-i18next";
import { formatMoney } from "@/lib/money";
import { Alert, AlertDescription, EmptyState, Spinner } from "@/ui";
import { useBookableProducts } from "./bookingQueries";
import { productName } from "./ManagePage";

/** K-13: a family first picks the consultation to book. */
export function BookPicker() {
	const { t, i18n } = useTranslation();
	const products = useBookableProducts();
	if (products.isPending) return <Spinner />;
	if (products.isError)
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("consultations.book.closed")}</AlertDescription>
			</Alert>
		);
	if (products.data.length === 0)
		return <EmptyState icon={MessagesSquare} title={t("consultations.book.none")} />;
	return (
		<section aria-label={t("consultations.book.pick")}>
			<ul className="grid gap-3 sm:grid-cols-2">
				{products.data.map((p) => (
					<li key={p.id}>
						<Link
							to="/learning/consultations/book"
							search={{ product: p.id }}
							className="flex flex-col gap-1 rounded-md border border-border p-4"
						>
							<span className="font-medium">{productName(p, i18n.language)}</span>
							<span className="text-sm text-muted-foreground">
								{t("consultations.book.minutes", { n: p.duration_minutes })} ·{" "}
								{formatMoney(p.price_minor, p.currency, i18n.language)}
							</span>
						</Link>
					</li>
				))}
			</ul>
		</section>
	);
}
```

`FamilyConsultations.tsx` becomes (the "Book" link above the list and above the empty state):

```tsx
import { Link } from "@tanstack/react-router";
import { MessagesSquare } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { dayIn, wallTime } from "@/lib/zoned-time";
import {
	buttonVariants,
	Card,
	CardContent,
	EmptyState,
	FormError,
	Spinner,
	StatusChip,
} from "@/ui";
import { useMyConsultations } from "./bookingQueries";
import { consultationsErrorText } from "./errors";
import { productName } from "./ManagePage";
import { TONE } from "./RequestsAdmin";
import type { FamilyRequest } from "./schemas";

/** K-13: a student's consultations, and a parent's children's and their
 * own, with "Book a consultation" (my/book). */
export function FamilyConsultations() {
	const { t } = useTranslation();
	const list = useMyConsultations();
	let body: ReactNode;
	if (list.isPending) body = <Spinner />;
	else if (list.isError)
		body = <FormError>{consultationsErrorText(list.error, t)}</FormError>;
	else if (list.data.length === 0)
		body = (
			<Card>
				<CardContent>
					<EmptyState icon={MessagesSquare} title={t("consultations.family.empty")} />
				</CardContent>
			</Card>
		);
	else
		body = (
			<ul className="flex flex-col gap-2">
				{list.data.map((r) => (
					<FamilyRow key={r.id} row={r} />
				))}
			</ul>
		);
	return (
		<div className="flex flex-col gap-4">
			<Link
				to="/learning/consultations/book"
				search={{}}
				className={`${buttonVariants()} self-start`}
			>
				{t("consultations.family.book")}
			</Link>
			{body}
		</div>
	);
}

function FamilyRow({ row }: { row: FamilyRequest }) {
	const { t, i18n } = useTranslation();
	const at = row.starts_at ? new Date(row.starts_at) : null;
	const when = at
		? `${dayIn(at, row.timezone, i18n.language)}, ${wallTime(at, row.timezone, i18n.language)}`
		: t("consultations.manage.noTime");
	return (
		<li>
			<Link
				to="/learning/consultations/$requestId"
				params={{ requestId: String(row.id) }}
				className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border p-3"
			>
				<span className="flex flex-col">
					<span className="font-medium">{productName(row.product, i18n.language)}</span>
					<span className="text-sm text-muted-foreground">
						{when}
						{row.student
							? ` · ${t("consultations.family.for", { name: row.student.full_name })}`
							: ""}
					</span>
				</span>
				<StatusChip tone={TONE[row.status]}>
					{t(`consultations.statuses.${row.status}`)}
				</StatusChip>
			</Link>
		</li>
	);
}
```


In `index.ts`, add `export { BookingWizard, browserZone } from "./BookingWizard";` and `export { BookPicker } from "./BookPicker";`.

- [ ] **Step 4: The routes**

`dashboard/src/routes/consult.$productId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { BookingWizard } from "@/features/consultations";
import { PublicFrame } from "@/features/gateways";

// Plan 60 (B7d K-14): the public booking wizard; no sign-in. The server
// answers 404 while booking is off, which the wizard shows as "cannot be
// booked".
export const Route = createFileRoute("/consult/$productId")({
	component: function ConsultBookRoute() {
		const { t } = useTranslation();
		const { productId } = Route.useParams();
		usePageTitle(t("consultations.book.title"));
		const id = Number(productId);
		return (
			<PublicFrame>
				<BookingWizard productId={Number.isInteger(id) && id > 0 ? id : 0} />
			</PublicFrame>
		);
	},
});
```

`dashboard/src/routes/_authed/learning.consultations.book.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { BookingWizard, BookPicker } from "@/features/consultations";
import { PageHeader } from "@/ui";

// Plan 60 (B7d K-13): a family books from its account (my/book).
export const Route = createFileRoute("/_authed/learning/consultations/book")({
	staticData: { feature: "consultations" },
	validateSearch: (search: Record<string, unknown>): { product?: number } => {
		const id = Number(search.product);
		return Number.isInteger(id) && id > 0 ? { product: id } : {};
	},
	component: function BookConsultationRoute() {
		const { t } = useTranslation();
		const { product } = Route.useSearch();
		usePageTitle(t("consultations.book.title"));
		return (
			<>
				<PageHeader title={t("consultations.book.title")} />
				{product === undefined ? (
					<BookPicker />
				) : (
					<BookingWizard productId={product} signedIn />
				)}
			</>
		);
	},
});
```

Regenerate the route tree: `F pnpm build`.

- [ ] **Step 5: The feature screen (claim `dashboard/src/routes/permissions.test.ts`)**

```bash
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/routes/permissions.test.ts --reason "B7d: FEATURE_SCREENS for the family booking page"
```

Under `// B7d` in `FEATURE_SCREENS`, add `"/_authed/learning/consultations/book": "consultations",`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `F pnpm vitest run src/features/consultations src/routes`
Expected: PASS.

Run: `F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 7: Commit (then release the claim)**

```bash
git -C dashboard add src/features/consultations/BookingWizard.tsx src/features/consultations/BookingWizard.test.tsx \
  src/features/consultations/BookPicker.tsx src/features/consultations/FamilyConsultations.tsx \
  src/features/consultations/FamilyConsultations.test.tsx src/features/consultations/index.ts \
  'src/routes/consult.$productId.tsx' src/routes/_authed/learning.consultations.book.tsx \
  src/routes/consult.test.ts src/routeTree.gen.ts src/routes/permissions.test.ts
git -C dashboard commit -m "feat(consultations): booking wizard for visitors and families (B7d K-2, K-3, K-13, K-14)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 dashboard/src/routes/permissions.test.ts
```

---

### Task 17: The office sees online bookings and moderates reviews (K-11, K-12, K-16)

**Files:**
- Modify: `dashboard/src/features/consultations/RequestsAdmin.tsx` (+ test), `RequestsTabs.tsx` (+ test), `index.ts`; `dashboard/src/routes/_authed/scheduling.consultations.tsx`
- Create: `dashboard/src/features/consultations/ReviewsAdmin.tsx`, `ReviewsAdmin.test.tsx`

**Interfaces:**
- Consumes: Task 14's `useOfficeReviews`, `useDecideReview`, `officeReview`, `REVIEW_STATUSES`; Task 15's `productName`; B7c's `RequestsAdmin`, `RequestsTabs`, `formatStart`, `TONE`.
- Produces: the request list's "Booked" filter (`self_booked`), an "Online" chip, the fee beside the amount ("$15.00 + $0.75 fee · Stripe"), the proposed time ("Proposed: …"); `ReviewsAdmin()`; `RequestsTabs({view: "list" | "calendar" | "reviews"})`; `/scheduling/consultations?view=reviews` (needs `consultation_review.view_any`).

- [ ] **Step 1: Write the failing tests**

Add inside `describe("RequestsAdmin", …)` in `RequestsAdmin.test.tsx`:

```tsx
	it("shows online bookings with their fee, gateway and proposed time, and filters them", async () => {
		vi.mocked(consultationsApi.requests).mockResolvedValue(
			page([
				{
					...request,
					self_booked: true,
					status: "reschedule_requested",
					proposed_starts_at: "2026-10-12T17:00:00+00:00",
					payment: {
						...(request.payment as NonNullable<typeof request.payment>),
						paid_method: "stripe",
						amount_minor: 1500,
						fee_minor: 75,
						currency: "USD",
						paid_on: "2026-10-11",
					},
				},
			]),
		);
		const user = userEvent.setup();
		show("consultation_request.view_any");
		const row = (await screen.findByText("CR-000005")).closest("tr") as HTMLElement;
		expect(within(row).getByText("Online")).toBeInTheDocument();
		expect(within(row).getByText(/\$15\.00 \+ \$0\.75 fee · Stripe/)).toBeInTheDocument();
		expect(within(row).getByText(/Proposed: Oct 12, 2026, 17:00/)).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Booked"), "true");
		await waitFor(() =>
			expect(consultationsApi.requests).toHaveBeenLastCalledWith(
				expect.objectContaining({ self_booked: true }),
			),
		);
	});
```

Add to `RequestsTabs.test.tsx`:

```tsx
	it("shows the reviews tab with the review code", async () => {
		show("consultation_review.view_any");
		expect(await screen.findByText("Reviews")).toBeInTheDocument();
		expect(screen.queryByText("Calendar")).toBeNull();
	});
```

`dashboard/src/features/consultations/ReviewsAdmin.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { bookingApi } from "./bookingApi";
import { officeReview } from "./fixtures";
import { ReviewsAdmin } from "./ReviewsAdmin";

vi.mock("./bookingApi", () => ({ bookingApi: { reviews: vi.fn(), decide: vi.fn() } }));

const page = (rows = [officeReview]) => ({
	count: rows.length,
	next: null,
	previous: null,
	results: rows,
});

function show(...codes: string[]) {
	return renderWithRouter(
		<CanProvider me={staffMe(...codes)}>
			<ReviewsAdmin />
		</CanProvider>,
	);
}

describe("ReviewsAdmin", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(bookingApi.reviews).mockResolvedValue(page());
		vi.mocked(bookingApi.decide).mockResolvedValue({ ...officeReview, status: "approved" });
	});

	it("lists pending reviews and approves one with a reason", async () => {
		const user = userEvent.setup();
		show("consultation_review.view_any", "consultation_review.update");
		expect(await screen.findByText("Clear")).toBeInTheDocument();
		expect(screen.getByText(/Sara · 4 \/ 5/)).toBeInTheDocument();
		expect(bookingApi.reviews).toHaveBeenCalledWith({ status: "pending", page: 1 });
		await user.type(screen.getByLabelText("Reason (optional)"), "Fine");
		await user.click(screen.getByRole("button", { name: "Approve" }));
		await waitFor(() =>
			expect(bookingApi.decide).toHaveBeenCalledWith(9, {
				status: "approved",
				reason: "Fine",
			}),
		);
	});

	it("filters by status and hides the actions without the update code", async () => {
		const user = userEvent.setup();
		show("consultation_review.view_any");
		await screen.findByText("Clear");
		expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
		await user.selectOptions(screen.getByLabelText("Review status"), "rejected");
		await waitFor(() =>
			expect(bookingApi.reviews).toHaveBeenLastCalledWith({ status: "rejected", page: 1 }),
		);
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `F pnpm vitest run src/features/consultations/RequestsAdmin.test.tsx src/features/consultations/RequestsTabs.test.tsx src/features/consultations/ReviewsAdmin.test.tsx`
Expected: FAIL (`Unable to find … "Online"`, no "Reviews" tab, `Failed to resolve import "./ReviewsAdmin"`).

- [ ] **Step 3: The request list**

In `RequestsAdmin.tsx`:
- import `type RequestPayment` from `./schemas`;
- in `filters`, add `self_booked: f.self_booked ? f.self_booked === "true" : undefined,`;
- after the `paid_method` filter `select(...)`, add:

```tsx
				{select("self_booked", t("consultations.requests.filters.selfBooked"), [
					["true", t("consultations.requests.selfBooked")],
					["false", t("consultations.requests.officeBooked")],
				])}
```

- inside the component, before `return`, add:

```tsx
	// K-16: the amount, its fee (online sales) and how it was paid.
	const paidText = (pay: RequestPayment) => {
		const money = formatMoney(pay.amount_minor, pay.currency, i18n.language);
		const fee =
			pay.fee_minor > 0
				? ` ${t("consultations.requests.fee", {
						fee: formatMoney(pay.fee_minor, pay.currency, i18n.language),
					})}`
				: "";
		const how = pay.billing_method
			? t(`consultations.billingMethods.${pay.billing_method}`)
			: t(`consultations.paid.${pay.paid_method}`);
		return `${money}${fee} · ${how}`;
	};
```

- in the payment cell, replace the first branch of `pay?.paid_method ? … : t("consultations.paid.unpaid")` (the template literal) with `paidText(pay)`;
- in the status cell, after the status `StatusChip`, add:

```tsx
											{row.self_booked ? (
												<StatusChip tone="neutral">
													{t("consultations.requests.selfBooked")}
												</StatusChip>
											) : null}
											{row.proposed_starts_at ? (
												<span className="block text-xs text-muted-foreground">
													{t("consultations.requests.proposed", {
														time:
															formatStart(
																{
																	starts_at: row.proposed_starts_at,
																	timezone: row.timezone,
																},
																zone,
																i18n.language,
															)?.academy ?? "",
													})}
												</span>
											) : null}
```

- [ ] **Step 4: Tabs, the reviews page and the route**

`RequestsTabs.tsx` becomes:

```tsx
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";

export type RequestsView = "list" | "calendar" | "reviews";

/** List / calendar (consultation_schedule.view_any) / reviews
 * (consultation_review.view_any, B7d); no tabs when only the list shows. */
export function RequestsTabs({ view }: { view: RequestsView }) {
	const { t } = useTranslation();
	const can = useCan();
	const views: RequestsView[] = ["list"];
	if (can("consultation_schedule.view_any")) views.push("calendar");
	if (can("consultation_review.view_any")) views.push("reviews");
	if (views.length === 1) return null;
	return (
		<nav
			aria-label={t("consultations.requests.title")}
			className="flex gap-1 border-b border-border"
		>
			{views.map((v) => (
				<Link
					key={v}
					to="/scheduling/consultations"
					search={{ view: v }}
					aria-current={view === v ? "page" : undefined}
					className={
						view === v
							? "border-b-2 border-primary px-3 py-2 font-medium"
							: "px-3 py-2 text-muted-foreground"
					}
				>
					{t(`consultations.requests.tabs.${v}`)}
				</Link>
			))}
		</nav>
	);
}
```

`dashboard/src/features/consultations/ReviewsAdmin.tsx`:

```tsx
import { ChevronLeft, ChevronRight, Star } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan } from "@/features/identity/permissions";
import {
	Button,
	Card,
	CardContent,
	EmptyState,
	Field,
	FormError,
	Input,
	Select,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { useDecideReview, useOfficeReviews } from "./bookingQueries";
import { consultationsErrorText } from "./errors";
import { productName } from "./ManagePage";
import { REVIEW_STATUSES, type ReviewStatus } from "./schemas";

const TONES: Record<ReviewStatus, "neutral" | "live" | "warning"> = {
	pending: "neutral",
	approved: "live",
	rejected: "warning",
};

/** K-12, K-16: the office approves or rejects the bookers' ratings
 * (consultation_review.update); only approved ones go public. */
export function ReviewsAdmin() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [status, setStatus] = useState("pending");
	const [page, setPage] = useState(1);
	const [reasons, setReasons] = useState<Record<number, string>>({});
	const list = useOfficeReviews({ status: status || undefined, page });
	const decide = useDecideReview();
	const canDecide = can("consultation_review.update");

	function run(id: number, verdict: "approved" | "rejected") {
		decide
			.mutateAsync({ id, status: verdict, reason: reasons[id] ?? "" })
			.then(() =>
				toast({ description: t("consultations.reviews.done"), variant: "success" }),
			)
			.catch((error) =>
				toast({ description: consultationsErrorText(error, t), variant: "destructive" }),
			);
	}

	return (
		<div className="flex flex-col gap-4">
			<Select
				aria-label={t("consultations.reviews.status")}
				className="w-auto self-start"
				value={status}
				onChange={(e) => {
					setPage(1);
					setStatus(e.target.value);
				}}
			>
				<option value="">{t("consultations.any")}</option>
				{REVIEW_STATUSES.map((s) => (
					<option key={s} value={s}>
						{t(`consultations.reviews.statuses.${s}`)}
					</option>
				))}
			</Select>
			{list.isPending ? (
				<Spinner />
			) : list.isError ? (
				<FormError>{consultationsErrorText(list.error, t)}</FormError>
			) : list.data.results.length === 0 ? (
				<EmptyState icon={Star} title={t("consultations.reviews.empty")} />
			) : (
				<ul className="flex flex-col gap-3">
					{list.data.results.map((r) => (
						<li key={r.id}>
							<Card>
								<CardContent className="flex flex-col gap-2 pt-6">
									<div className="flex flex-wrap items-center justify-between gap-2">
										<span className="font-medium">
											{productName(r.request.product, i18n.language)} · {r.request.reference}
										</span>
										<StatusChip tone={TONES[r.status]}>
											{t(`consultations.reviews.statuses.${r.status}`)}
										</StatusChip>
									</div>
									<p className="text-sm">
										{r.name} · {t("consultations.reviews.rating", { n: r.rating })}
									</p>
									{r.comment ? (
										<p className="whitespace-pre-line text-sm">{r.comment}</p>
									) : null}
									{r.reason ? (
										<p className="text-sm text-muted-foreground">{r.reason}</p>
									) : null}
									{canDecide ? (
										<div className="flex flex-wrap items-end gap-2">
											<Field id={`reason-${r.id}`} label={t("consultations.reviews.reason")}>
												<Input
													maxLength={500}
													value={reasons[r.id] ?? ""}
													onChange={(e) =>
														setReasons((old) => ({ ...old, [r.id]: e.target.value }))
													}
												/>
											</Field>
											<Button size="sm" disabled={decide.isPending} onClick={() => run(r.id, "approved")}>
												{t("consultations.reviews.approve")}
											</Button>
											<Button
												size="sm"
												variant="outline"
												disabled={decide.isPending}
												onClick={() => run(r.id, "rejected")}
											>
												{t("consultations.reviews.reject")}
											</Button>
										</div>
									) : null}
								</CardContent>
							</Card>
						</li>
					))}
				</ul>
			)}
			{list.data && (list.data.next || list.data.previous) ? (
				<div className="flex justify-end gap-2">
					<Button
						variant="outline"
						size="sm"
						disabled={!list.data.previous}
						aria-label={t("common.pager.previous")}
						onClick={() => setPage((p) => p - 1)}
					>
						<ChevronLeft aria-hidden className="size-4 rtl:rotate-180" />
					</Button>
					<Button
						variant="outline"
						size="sm"
						disabled={!list.data.next}
						aria-label={t("common.pager.next")}
						onClick={() => setPage((p) => p + 1)}
					>
						<ChevronRight aria-hidden className="size-4 rtl:rotate-180" />
					</Button>
				</div>
			) : null}
		</div>
	);
}
```

In `index.ts`, add `export { ReviewsAdmin } from "./ReviewsAdmin";` and change the tabs export to `export { RequestsTabs, type RequestsView } from "./RequestsTabs";`.

In `routes/_authed/scheduling.consultations.tsx`:
- import `ReviewsAdmin` and `type RequestsView` from `@/features/consultations`;
- `validateSearch` becomes:

```tsx
	validateSearch: (search: Record<string, unknown>): { view?: RequestsView } =>
		search.view === "list" || search.view === "calendar" || search.view === "reviews"
			? { view: search.view }
			: {},
```

- after `const calendar = …`, add `const reviews = view === "reviews" && can("consultation_review.view_any");` and render `{calendar ? <ScheduleWeek /> : reviews ? <ReviewsAdmin /> : <RequestsAdmin />}`.

Regenerate the route tree: `F pnpm build`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `F pnpm vitest run src/features/consultations src/routes`
Expected: PASS.

Run: `F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/consultations/RequestsAdmin.tsx src/features/consultations/RequestsAdmin.test.tsx \
  src/features/consultations/RequestsTabs.tsx src/features/consultations/RequestsTabs.test.tsx \
  src/features/consultations/ReviewsAdmin.tsx src/features/consultations/ReviewsAdmin.test.tsx \
  src/features/consultations/index.ts src/routes/_authed/scheduling.consultations.tsx src/routeTree.gen.ts
git -C dashboard commit -m "feat(consultations): office sees online bookings and moderates reviews (B7d K-12, K-16)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 18: The return page's consultation branch and the attention codes (K-6, K-15; claims)

**Files (all claimed, two commits):**
- Commit A: `dashboard/src/features/gateways/schemas.ts`, `dashboard/src/locales/en/gateways.json`, `dashboard/src/locales/ar/gateways.json`
- Commit B: `dashboard/src/features/gateways/ReturnPage.tsx`, `dashboard/src/features/gateways/ReturnPage.test.tsx`

**Interfaces:**
- Consumes: Task 6's attention reasons; Task 14's `consultations.return.*` strings and the `consult:<checkout id>` key; Task 15's routes `/consult/manage/$token`, `/learning/consultations`.
- Produces: `ATTENTION_CODES` gains `request_paid`, `request_cancelled`, `slot_taken`, `not_bookable`; the return page links a consultation to its manage page (remembered link) or to My consultations (`purpose === "consultation"`), and otherwise, on an anonymous completed read, says to use the emailed link. The `useMe` line is unchanged (D30).

- [ ] **Step 1: Commit A — the attention codes (claims)**

```bash
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/gateways/schemas.ts --reason "B7d K-6: consultation attention codes"
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/locales/en/gateways.json --reason "B7d K-6: consultation attention strings"
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/locales/ar/gateways.json --reason "B7d K-6: consultation attention strings"
```

In `ATTENTION_CODES`, after B7b's `"purchase_paid",`:

```ts
	// B7d K-6: a consultation sale that could not be applied.
	"request_paid",
	"request_cancelled",
	"slot_taken",
	"not_bookable",
```

In `locales/en/gateways.json` `attention`, after `purchase_paid`:

```json
		"request_paid": "This consultation booking was already paid by another checkout; refund one.",
		"request_cancelled": "The consultation booking was cancelled when the money arrived; refund it or book it again by hand.",
		"slot_taken": "Someone else took the booked time after its hold ran out; refund it or move the booking by hand.",
		"not_bookable": "The consultation took no new bookings when the money arrived; refund it or record the booking by hand."
```

In `locales/ar/gateways.json` `attention`, after `purchase_paid`:

```json
		"request_paid": "دُفع حجز الاستشارة هذا بالفعل عبر دفعة أخرى؛ استرد إحداهما.",
		"request_cancelled": "كان حجز الاستشارة ملغيًا عند وصول المبلغ؛ استرده أو أعد الحجز يدويًا.",
		"slot_taken": "حجز شخص آخر الموعد بعد انتهاء مهلة الحجز؛ استرد المبلغ أو انقل الحجز يدويًا.",
		"not_bookable": "لم تعد الاستشارة تقبل حجوزات عند وصول المبلغ؛ استرده أو سجّل الحجز يدويًا."
```

(Add the comma after the `purchase_paid` line in both files.)

Run: `F pnpm vitest run src/features/gateways src/locales`
Expected: PASS (the gateways schema test keeps every code translated; en and ar key-equal).

```bash
git -C dashboard add src/features/gateways/schemas.ts src/locales/en/gateways.json src/locales/ar/gateways.json
git -C dashboard commit -m "feat(gateways): consultation attention codes (B7d K-6)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/gateways/schemas.ts
python3 scripts/orchestration/ledger.py release B7 dashboard/src/locales/en/gateways.json
python3 scripts/orchestration/ledger.py release B7 dashboard/src/locales/ar/gateways.json
```

- [ ] **Step 2: Commit B — claim the return page and write the failing tests**

```bash
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/gateways/ReturnPage.tsx --reason "B7d K-15: consultation branch (D53)"
python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/gateways/ReturnPage.test.tsx --reason "B7d K-15: consultation branch tests"
```

Add to `ReturnPage.test.tsx` (the import goes with the others at the top: `import { rememberManage } from "@/features/consultations/manageLink";`):

```tsx
describe("ReturnPage, consultations (B7d K-15)", () => {
	const TOKEN = "T".repeat(43);
	const CONSULT = ["/consult/manage/$token", "/learning/consultations"];
	const anonymous = (status: string) => {
		const { purpose: _purpose, reference_id: _reference, ...rest } = body(status);
		return rest;
	};

	beforeEach(() => {
		vi.clearAllMocks();
		sessionStorage.clear();
	});

	it("links a visitor's booking to its manage page, remembered by this tab", async () => {
		rememberManage(ID, `http://demo.etqan.localhost/app/consult/manage/${TOKEN}`);
		vi.mocked(gatewaysApi.checkout).mockResolvedValue(anonymous("completed") as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: CONSULT });
		expect(
			await screen.findByRole("link", { name: "Open your booking" }),
		).toHaveAttribute("href", expect.stringContaining(`/consult/manage/${TOKEN}`));
		expect(screen.queryByText(/link we email you/)).toBeNull();
		expect(identityApi.me).not.toHaveBeenCalled();
	});

	it("sends a family's own booking to My consultations", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue({
			...body("completed"),
			purpose: "consultation",
			reference_id: 5,
		} as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: CONSULT });
		expect(
			await screen.findByRole("link", { name: "Open my consultations" }),
		).toHaveAttribute("href", expect.stringContaining("/learning/consultations"));
		expect(identityApi.me).not.toHaveBeenCalled();
	});

	it("tells an anonymous payer with no remembered link to use the emailed one", async () => {
		vi.mocked(gatewaysApi.checkout).mockResolvedValue(anonymous("completed") as never);
		renderWithRouter(<ReturnPage checkoutId={ID} />, { extraPaths: CONSULT });
		expect(
			await screen.findByText(
				"Booked a consultation? Open it from the link we email you once it is paid.",
			),
		).toBeInTheDocument();
		expect(screen.queryByRole("link")).toBeNull();
		expect(identityApi.me).not.toHaveBeenCalled();
	});
});
```

Run: `F pnpm vitest run src/features/gateways/ReturnPage.test.tsx`
Expected: the three new tests FAIL; every existing test (invoice, wallet top-up, recorded course, PayPal capture/cancel) PASSES.

- [ ] **Step 3: Implement the branch, keeping every existing branch**

In `ReturnPage.tsx`, add above `ReturnPage` (next to `RecordedLink`):

```tsx
/** B7d K-15: the booking wizard leaves this tab a consultation's manage link
 * under `consult:<checkout id>` (consultations' manageLink.ts); an anonymous
 * read of a public checkout has no purpose to branch on. */
function consultToken(checkoutId: string | undefined): string | null {
	if (!checkoutId) return null;
	try {
		const url = sessionStorage.getItem(`consult:${checkoutId}`);
		return url
			? (/\/consult\/manage\/([A-Za-z0-9_-]{43})$/.exec(url)?.[1] ?? null)
			: null;
	} catch {
		return null;
	}
}

/** B7d K-15: a consultation booking opens its manage page (a visitor) or My
 * consultations (a family's own checkout); no `me` call (D30). */
function ConsultationLink({ token }: { token: string | null }) {
	const { t } = useTranslation();
	return (
		<Button asChild variant="outline" size="sm">
			{token ? (
				<Link to="/consult/manage/$token" params={{ token }}>
					{t("consultations.return.open")}
				</Link>
			) : (
				<Link to="/learning/consultations">{t("consultations.return.mine")}</Link>
			)}
		</Button>
	);
}
```

Inside `ReturnPage`, after the line `const status = …;`:

```tsx
	const token = consultToken(checkoutId);
	const consultation = token !== null || data.purpose === "consultation";
```

Put the new branch at the **head** of the existing `link` chain and keep the rest exactly as it is (B7b PF7):

```tsx
	const link = (label: string) =>
		consultation ? (
			<ConsultationLink token={token} />
		) : data.purpose === "recorded_course" ? (
```

(the `recorded_course`, `invoice` and `topUp` branches follow unchanged). Leave the `useMe({ enabled: purpose === "invoice" || purpose === "wallet_topup" })` line unchanged. In the card, after the final `{status === "completed" || status === "pending" ? link(…) : null}`, add:

```tsx
				{status === "completed" && data.purpose === undefined && token === null ? (
					<p className="text-sm text-muted-foreground">
						{t("consultations.return.emailed")}
					</p>
				) : null}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `F pnpm vitest run src/features/gateways`
Expected: PASS (all old and new tests).

Run: `F pnpm tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit B (then release both claims)**

```bash
git -C dashboard add src/features/gateways/ReturnPage.tsx src/features/gateways/ReturnPage.test.tsx
git -C dashboard commit -m "feat(gateways): return page links consultation bookings back (B7d K-15, D53)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/gateways/ReturnPage.tsx
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/gateways/ReturnPage.test.tsx
```

---

### Task 19: Marketing fetchers for the public catalogue (K-14)

**Files:**
- Create: `marketing/src/lib/consultations.ts`
- Test: `marketing/test/consultations.test.ts` (new; Tasks 20 and 21 add to it)

**Interfaces:**
- Consumes: `fetchSiteJson`, `Fetched`, `normalizeHost`, `isValidHost`, `validStars` (`src/lib/site.ts`); `getJson` (`src/lib/http.ts`); the payloads of Task 10.
- Produces: types `PublicConsultation`, `ConsultationDetail`, `ConsultTeacher`, `ConsultReview`, `ConsultMode`; `CONSULT_ID_RE`; `isConsultation`, `isConsultationDetail`; `getConsultations(host) -> Promise<Fetched<PublicConsultation[]>>`; `getConsultation(host, id: string) -> Promise<Fetched<ConsultationDetail>>`; `hasConsultations(host) -> Promise<boolean>` (cached per host for 60 s, never throws); `clearConsultationsCache()`; `pickText(ar, en, lang)`; `ratingText(average, count, lang)`.

- [ ] **Step 1: Write the failing tests**

`marketing/test/consultations.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import * as consult from "../src/lib/consultations";
import * as http from "../src/lib/http";

const product = (
	patch: Partial<consult.ConsultationDetail> = {},
): consult.ConsultationDetail => ({
	id: 3,
	name_ar: "استشارة تحديد المستوى",
	name_en: "Placement consultation",
	description_ar: "",
	description_en: "Thirty minutes <b>with</b> a teacher.",
	price_minor: 1500,
	currency: "USD",
	fee_enabled: false,
	duration_minutes: 30,
	validity_days: 14,
	participants: 1,
	delivery_mode: "video_call",
	featured: true,
	reschedulable: true,
	cover_url: "/media/c.png",
	rating_average: 4.5,
	rating_count: 2,
	teachers: [{ user_id: 8, full_name: "Ustadh Bilal", initial: "U", bio: "Ijazah." }],
	reviews: [
		{ rating: 5, comment: "Clear", created_at: "2026-10-01T10:00:00+00:00", by: "visitor" },
	],
	providers: ["stripe"],
	...patch,
});

afterEach(() => {
	vi.restoreAllMocks();
	consult.clearConsultationsCache();
});

describe("consultation fetchers", () => {
	it("reads the list and a detail by id, refusing bad ids", async () => {
		const spy = vi
			.spyOn(http, "getJson")
			.mockResolvedValue({ status: 200, body: [product()] });
		expect((await consult.getConsultations("Demo.Example")).kind).toBe("ok");
		expect(spy).toHaveBeenCalledWith(
			"/api/v1/consultations/public/products/",
			"demo.example",
		);
		spy.mockResolvedValue({ status: 200, body: product() });
		expect((await consult.getConsultation("demo.example", "3")).kind).toBe("ok");
		expect(spy).toHaveBeenLastCalledWith(
			"/api/v1/consultations/public/products/3/",
			"demo.example",
		);
		for (const bad of ["0", "03", "x", "../3", "12345678901"])
			expect((await consult.getConsultation("demo.example", bad)).kind).toBe(
				"notfound",
			);
	});

	it("rejects a malformed body as unavailable", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({
			status: 200,
			body: [{ id: 1 }],
		});
		expect((await consult.getConsultations("demo.example")).kind).toBe("unavailable");
	});

	it("validates every field it renders", () => {
		expect(consult.isConsultationDetail(product())).toBe(true);
		for (const patch of [
			{ delivery_mode: "phone" },
			{ currency: "usd" },
			{ rating_average: "4.5" },
			{ reviews: [{ rating: 6, comment: "", created_at: "", by: "visitor" }] },
			{ reviews: [{ rating: 5, comment: "", created_at: "", by: "Omar" }] },
			{ teachers: [{ user_id: 8, full_name: "B" }] },
		])
			expect(consult.isConsultationDetail({ ...product(), ...patch })).toBe(false);
	});

	it("caches the header flag per host and never throws", async () => {
		const spy = vi
			.spyOn(http, "getJson")
			.mockResolvedValue({ status: 200, body: [product()] });
		expect(await consult.hasConsultations("demo.example")).toBe(true);
		expect(await consult.hasConsultations("demo.example")).toBe(true);
		expect(spy).toHaveBeenCalledTimes(1);
		consult.clearConsultationsCache();
		spy.mockResolvedValue({ status: 200, body: [] });
		expect(await consult.hasConsultations("demo.example")).toBe(false);
		consult.clearConsultationsCache();
		spy.mockRejectedValue(new Error("down"));
		expect(await consult.hasConsultations("demo.example")).toBe(false);
		expect(await consult.hasConsultations(undefined)).toBe(false);
	});

	it("picks the page's language and formats the rating", () => {
		expect(consult.pickText("عربي", "English", "ar")).toBe("عربي");
		expect(consult.pickText("", "English", "ar")).toBe("English");
		expect(consult.pickText("عربي", "", "en")).toBe("عربي");
		expect(consult.ratingText(4.5, 2, "en")).toBe("★ 4.5 (2)");
		expect(consult.ratingText(null, 0, "en")).toBe("");
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `M pnpm vitest run test/consultations.test.ts`
Expected: FAIL with `Failed to load url ../src/lib/consultations`.

- [ ] **Step 3: Implement**

`marketing/src/lib/consultations.ts`:

```ts
import { getJson } from "./http";
import type { Lang } from "./i18n";
import {
	type Fetched,
	fetchSiteJson,
	isValidHost,
	normalizeHost,
	validStars,
} from "./site";

// B7d K-14: the public consultation catalogue, read as B7b's courses are:
// the list and the detail uncached; the header's "has consultations" flag
// cached per host and never throwing. Every field the pages render is
// checked here (D2: text is rendered escaped).

export type ConsultMode = "video_call" | "live_chat" | "email";

export type PublicConsultation = {
	id: number;
	name_ar: string;
	name_en: string;
	description_ar: string;
	description_en: string;
	price_minor: number;
	currency: string;
	fee_enabled: boolean;
	duration_minutes: number;
	validity_days: number;
	participants: number;
	delivery_mode: ConsultMode;
	featured: boolean;
	reschedulable: boolean;
	cover_url: string;
	rating_average: number | null;
	rating_count: number;
};

export type ConsultTeacher = {
	user_id: number;
	full_name: string;
	initial: string;
	bio: string;
};

export type ConsultReview = {
	rating: number;
	comment: string;
	created_at: string;
	by: "student" | "visitor";
};

export type ConsultationDetail = PublicConsultation & {
	teachers: ConsultTeacher[];
	reviews: ConsultReview[];
	providers: string[];
};

export const CONSULT_ID_RE = /^[1-9][0-9]{0,9}$/;
const MODES = new Set(["video_call", "live_chat", "email"]);
const isObj = (v: unknown): v is Record<string, unknown> =>
	typeof v === "object" && v !== null && !Array.isArray(v);
const isNum = (v: unknown) => typeof v === "number" && Number.isFinite(v);
const isStr = (v: unknown) => typeof v === "string";
const isBool = (v: unknown) => typeof v === "boolean";

export const isConsultation = (v: unknown): v is PublicConsultation =>
	isObj(v) &&
	Number.isInteger(v.id) &&
	(v.id as number) > 0 &&
	isStr(v.name_ar) &&
	isStr(v.name_en) &&
	isStr(v.description_ar) &&
	isStr(v.description_en) &&
	isNum(v.price_minor) &&
	typeof v.currency === "string" &&
	/^[A-Z]{3}$/.test(v.currency) &&
	isBool(v.fee_enabled) &&
	isNum(v.duration_minutes) &&
	typeof v.delivery_mode === "string" &&
	MODES.has(v.delivery_mode) &&
	isBool(v.featured) &&
	isStr(v.cover_url) &&
	(v.rating_average === null || isNum(v.rating_average)) &&
	isNum(v.rating_count);

const isTeacher = (v: unknown): v is ConsultTeacher =>
	isObj(v) &&
	Number.isInteger(v.user_id) &&
	isStr(v.full_name) &&
	isStr(v.initial) &&
	isStr(v.bio);

const isReview = (v: unknown): v is ConsultReview =>
	isObj(v) &&
	validStars(v.rating) &&
	isStr(v.comment) &&
	isStr(v.created_at) &&
	(v.by === "student" || v.by === "visitor");

export const isConsultationDetail = (v: unknown): v is ConsultationDetail =>
	isConsultation(v) &&
	isObj(v) &&
	Array.isArray(v.teachers) &&
	v.teachers.every(isTeacher) &&
	Array.isArray(v.reviews) &&
	v.reviews.every(isReview);

const isList = (v: unknown): v is PublicConsultation[] =>
	Array.isArray(v) && v.every(isConsultation);

const LIST = "/api/v1/consultations/public/products/";

export function getConsultations(
	host: string,
): Promise<Fetched<PublicConsultation[]>> {
	return fetchSiteJson(host, LIST, isList);
}

export function getConsultation(
	host: string,
	id: string,
): Promise<Fetched<ConsultationDetail>> {
	if (!CONSULT_ID_RE.test(id)) return Promise.resolve({ kind: "notfound" });
	return fetchSiteJson(host, `${LIST}${id}/`, isConsultationDetail);
}

const TTL = 60_000;
const MAX = 1000;
const flags = new Map<string, { expires: number; value: boolean }>();

export function clearConsultationsCache(): void {
	flags.clear();
}

/** Whether the header shows "Consultations": a non-empty bookable list. */
export async function hasConsultations(
	rawHost: string | undefined,
): Promise<boolean> {
	if (!rawHost) return false;
	const host = normalizeHost(rawHost);
	if (!isValidHost(host)) return false;
	const hit = flags.get(host);
	if (hit && hit.expires > Date.now()) return hit.value;
	let value = false;
	try {
		const { status, body } = await getJson(LIST, host);
		value = status === 200 && isList(body) && body.length > 0;
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

/** The page language's text, falling back to the other one. */
export const pickText = (ar: string, en: string, lang: Lang): string =>
	lang === "ar" ? ar || en : en || ar;

/** "★ 4.5 (2)", or "" with no approved reviews (K-12). */
export function ratingText(
	average: number | null,
	count: number,
	lang: Lang,
): string {
	if (average === null || count === 0) return "";
	const value = new Intl.NumberFormat(lang, {
		minimumFractionDigits: 1,
		maximumFractionDigits: 1,
	}).format(average);
	return `★ ${value} (${count})`;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `M pnpm vitest run test/consultations.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C marketing add src/lib/consultations.ts test/consultations.test.ts
git -C marketing commit -m "feat(consultations): public catalogue fetchers and header flag (B7d K-14)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 20: Marketing strings, header link and sitemap (K-14; claims)

**Files (claims, one commit):** `marketing/src/lib/i18n.ts`, `marketing/src/components/Header.astro`, `marketing/src/pages/sitemap.xml.ts`, and any existing `marketing/test/*.test.ts` this commit's new fetch breaks
- Test: `marketing/test/consultations.test.ts`

**Interfaces:**
- Consumes: Task 19's `getConsultations`, `hasConsultations`.
- Produces: `ui(lang)` keys `consultations`, `bookConsultation`, `consultTeachers`, `consultReviews`, `noReviews`, `reviewerStudent`, `reviewerVisitor`, `consultFee`, `consultMinutes`, `modeVideoCall`, `modeLiveChat`, `modeEmail`; `minutesText(lang, n)`, `consultModeText(lang, mode)`; the header's `/{lang}/consultations` link; sitemap entries `/consultations` and `/consultations/{id}`.

- [ ] **Step 1: Claim the files**

```bash
python3 scripts/orchestration/ledger.py claim B7 marketing/src/lib/i18n.ts --reason "B7d K-14: consultation strings"
python3 scripts/orchestration/ledger.py claim B7 marketing/src/components/Header.astro --reason "B7d K-14: Consultations header link"
python3 scripts/orchestration/ledger.py claim B7 marketing/src/pages/sitemap.xml.ts --reason "B7d K-14: consultation URLs in the sitemap"
```

- [ ] **Step 2: Write the failing tests**

Add to `marketing/test/consultations.test.ts` (imports at the top: `import { experimental_AstroContainer as AstroContainer } from "astro/container";`, `import Header from "../src/components/Header.astro";`, `import { consultModeText, minutesText } from "../src/lib/i18n";`, `import { GET as sitemap } from "../src/pages/sitemap.xml";`, `import { demoSite } from "./fixtures";`):

```ts
const locals = {
	host: "demo.etqan.localhost",
	siteResult: { kind: "ok" as const, site: demoSite },
};
const onlyConsultations = (body: unknown) => async (path: string) =>
	path.startsWith("/api/v1/consultations/")
		? { status: 200, body }
		: { status: 404, body: null };

describe("consultation strings, header and sitemap", () => {
	it("words lengths and modes in both languages", () => {
		expect(minutesText("en", 30)).toBe("30 minutes");
		expect(minutesText("ar", 30)).toBe("30 دقيقة");
		expect(consultModeText("en", "video_call")).toBe("Video call");
		expect(consultModeText("ar", "email")).toBe("بالبريد الإلكتروني");
	});

	it("shows the Consultations link only when one can be booked", async () => {
		const spy = vi
			.spyOn(http, "getJson")
			.mockImplementation(onlyConsultations([product()]));
		const c = await AstroContainer.create();
		const render = () =>
			c.renderToString(Header, {
				props: { site: demoSite, lang: "en", path: "/" },
				locals,
			});
		expect(await render()).toContain('href="/en/consultations"');
		consult.clearConsultationsCache();
		spy.mockImplementation(onlyConsultations([]));
		expect(await render()).not.toContain("/en/consultations");
	});

	it("lists the consultations in the sitemap when there are some", async () => {
		vi.spyOn(http, "getJson").mockImplementation(onlyConsultations([product()]));
		const xml = await (await sitemap({ locals } as never)).text();
		expect(xml).toContain("/en/consultations/3</loc>");
		expect(xml).toContain("/ar/consultations</loc>");
	});

	it("leaves them out when booking is off or the backend is down", async () => {
		const spy = vi
			.spyOn(http, "getJson")
			.mockResolvedValue({ status: 404, body: null });
		let res = await sitemap({ locals } as never);
		expect(res.status).toBe(200);
		expect(await res.text()).not.toContain("/consultations");
		spy.mockRejectedValue(new Error("down"));
		res = await sitemap({ locals } as never);
		expect(res.status).toBe(200);
		expect(await res.text()).not.toContain("/consultations");
	});
});
```

Run: `M pnpm vitest run test/consultations.test.ts`
Expected: the new tests FAIL (`minutesText` is not exported; no header link; no sitemap entry).

- [ ] **Step 3: Strings**

In `marketing/src/lib/i18n.ts`, add to `STRINGS.ar` after B7b's `signInToBuy`:

```ts
		consultations: "الاستشارات",
		bookConsultation: "احجز استشارة",
		consultTeachers: "المعلمون",
		consultReviews: "التقييمات",
		noReviews: "لا توجد تقييمات بعد.",
		reviewerStudent: "طالب",
		reviewerVisitor: "زائر",
		consultFee: "قد تُضاف رسوم دفع عند الدفع.",
		consultMinutes: "{n} دقيقة",
		modeVideoCall: "مكالمة فيديو",
		modeLiveChat: "محادثة مباشرة",
		modeEmail: "بالبريد الإلكتروني",
```

and to `STRINGS.en` after `signInToBuy`:

```ts
		consultations: "Consultations",
		bookConsultation: "Book a consultation",
		consultTeachers: "Teachers",
		consultReviews: "Reviews",
		noReviews: "No reviews yet.",
		reviewerStudent: "Student",
		reviewerVisitor: "Visitor",
		consultFee: "A payment fee may be added at checkout.",
		consultMinutes: "{n} minutes",
		modeVideoCall: "Video call",
		modeLiveChat: "Live chat",
		modeEmail: "By email",
```

At the end of the module:

```ts
// B7d K-14: a consultation's length and how it is held.
export function minutesText(lang: Lang, n: number): string {
	return STRINGS[lang].consultMinutes.replace("{n}", String(n));
}

const MODE_KEYS = {
	video_call: "modeVideoCall",
	live_chat: "modeLiveChat",
	email: "modeEmail",
} as const;

export function consultModeText(
	lang: Lang,
	mode: keyof typeof MODE_KEYS,
): string {
	return STRINGS[lang][MODE_KEYS[mode]];
}
```

- [ ] **Step 4: The header link and the sitemap**

In `Header.astro`, add `import { hasConsultations } from "../lib/consultations";` with the imports, `const showConsultations = await hasConsultations(Astro.locals?.host);` after B7b's `showRecorded` line, and after B7b's recorded-courses link:

```astro
			{showConsultations && <a href={`/${lang}/consultations`}>{t.consultations}</a>}
```

In `sitemap.xml.ts`, add `import { getConsultations } from "../lib/consultations";` and, after B7b's `coursePaths` block:

```ts
	// B7d K-14: bookable consultations, as B7b's courses: any result other
	// than ok (booking off, backend trouble) leaves them out; never a 503.
	const consultations = await getConsultations(locals.host);
	const consultationPaths: { path: string }[] =
		consultations.kind === "ok" && consultations.data.length > 0
			? [
					{ path: "/consultations" },
					...consultations.data.map((c) => ({ path: `/consultations/${c.id}` })),
				]
			: [];
```

and add `...consultationPaths,` after `...coursePaths,` in `paths`.

- [ ] **Step 5: Run the whole marketing suite**

Run: `M pnpm vitest run`
Expected: PASS. The header's new call has the same guard as B7b's `hasRecordedCourses` (`Astro.locals?.host`, never throws), so the B8 tests B7b adjusted stay green. If any other existing test fails because it asserts that `getJson` was never called, or mocks every path with a body the sitemap now reads, scope that assertion to its own path (`expect(spy).not.toHaveBeenCalledWith(expect.stringContaining("<its path>"), expect.anything())`) or mock `/api/v1/consultations/` to a 404, as B7b PF25 did, **after** claiming that test file (`ledger.py claim B7 marketing/test/<file> --reason "B7d: header/sitemap fetch"`); include it in this commit and release it after.

Run: `M pnpm astro check`
Expected: PASS.

- [ ] **Step 6: Commit (then release every claim)**

```bash
git -C marketing add src/lib/i18n.ts src/components/Header.astro src/pages/sitemap.xml.ts test/consultations.test.ts
git -C marketing commit -m "feat(consultations): header link, sitemap and strings (B7d K-14)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 marketing/src/lib/i18n.ts
python3 scripts/orchestration/ledger.py release B7 marketing/src/components/Header.astro
python3 scripts/orchestration/ledger.py release B7 marketing/src/pages/sitemap.xml.ts
```

(Add any B8 test file adjusted in Step 5 to the `git add` and release its claim too.)

---

### Task 21: The public consultation pages (K-12, K-14)

**Files:**
- Create: `marketing/src/pages/[lang]/consultations/index.astro`, `marketing/src/pages/[lang]/consultations/[id].astro`
- Test: `marketing/test/consultations.test.ts`

**Interfaces:**
- Consumes: Tasks 19 and 20 (`getConsultations`, `getConsultation`, `pickText`, `ratingText`, `minutesText`, `consultModeText`, `ui(lang)` keys); B7b's `priceText`, `safeMedia` (`src/lib/recorded.ts`).
- Produces: `/{lang}/consultations` (featured first, as the API orders them; 404 when empty or off) and `/{lang}/consultations/{id}` (description, teachers, approved reviews by "Student"/"Visitor", Book → `/app/consult/{id}`).

- [ ] **Step 1: Write the failing tests**

Add to `marketing/test/consultations.test.ts` (imports at the top: `import Detail from "../src/pages/[lang]/consultations/[id].astro";` and `import Index from "../src/pages/[lang]/consultations/index.astro";`):

```ts
describe("consultation pages", () => {
	const render = async (page: never, params: Record<string, string>, path: string) =>
		(await AstroContainer.create()).renderToResponse(page, {
			params,
			locals,
			request: new Request(`https://demo.example${path}`),
		});
	const detail = (patch: Partial<consult.ConsultationDetail> = {}) => {
		vi.spyOn(http, "getJson").mockImplementation(onlyConsultations(product(patch)));
		return render(Detail as never, { lang: "en", id: "3" }, "/en/consultations/3");
	};

	it("lists consultations with their price, length, mode and rating, text escaped", async () => {
		vi.spyOn(http, "getJson").mockImplementation(
			onlyConsultations([product(), product({ id: 4, name_en: "Written", delivery_mode: "email", rating_average: null, rating_count: 0 })]),
		);
		const html = await (
			await render(Index as never, { lang: "en" }, "/en/consultations")
		).text();
		expect(html).toContain('href="/en/consultations/3"');
		expect(html).toContain("Thirty minutes &lt;b&gt;with&lt;/b&gt; a teacher.");
		expect(html).toContain("30 minutes · Video call · ★ 4.5 (2)");
		expect(html).toContain("By email");
		expect(html).toContain("$15.00");
	});

	it("is a 404 when nothing can be booked, and unavailable on backend trouble", async () => {
		const spy = vi.spyOn(http, "getJson").mockImplementation(onlyConsultations([]));
		expect(
			(await render(Index as never, { lang: "en" }, "/en/consultations")).status,
		).toBe(404);
		spy.mockResolvedValue({ status: 500, body: null });
		const res = await render(Index as never, { lang: "en" }, "/en/consultations");
		expect(await res.text()).toContain("temporarily unavailable");
	});

	it("shows a detail with teachers, anonymous reviews and the booking link", async () => {
		const html = await (await detail()).text();
		expect(html).toContain('href="/app/consult/3"');
		expect(html).toContain("Book a consultation");
		expect(html).toContain("Ustadh Bilal");
		expect(html).toContain("Ijazah.");
		expect(html).toContain("Clear");
		expect(html).toContain("Visitor");
		expect(html).toMatch(/src="https?:\/\/demo\.example\/media\/c\.png"/);
	});

	it("says when there are no reviews and notes the fee", async () => {
		const html = await (
			await detail({ reviews: [], rating_average: null, rating_count: 0, fee_enabled: true })
		).text();
		expect(html).toContain("No reviews yet.");
		expect(html).toContain("A payment fee may be added at checkout.");
	});

	it("is a 404 for an unknown or malformed id and drops an unsafe cover", async () => {
		vi.spyOn(http, "getJson").mockResolvedValue({ status: 404, body: null });
		expect(
			(await render(Detail as never, { lang: "en", id: "99" }, "/en/consultations/99"))
				.status,
		).toBe(404);
		expect(
			(await render(Detail as never, { lang: "en", id: "x" }, "/en/consultations/x"))
				.status,
		).toBe(404);
		vi.restoreAllMocks();
		const html = await (await detail({ cover_url: "javascript:alert(1)" })).text();
		expect(html).not.toContain("javascript:");
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `M pnpm vitest run test/consultations.test.ts`
Expected: FAIL with `Failed to load url ../src/pages/[lang]/consultations/index.astro`.

- [ ] **Step 3: The pages**

`marketing/src/pages/[lang]/consultations/index.astro`:

```astro
---
import Footer from "../../../components/Footer.astro";
import Header from "../../../components/Header.astro";
import PageNotFound from "../../../components/PageNotFound.astro";
import StatusPage from "../../../components/StatusPage.astro";
import Layout from "../../../layouts/Layout.astro";
import { getConsultations, pickText, ratingText } from "../../../lib/consultations";
import {
	consultModeText,
	isLang,
	minutesText,
	pick,
	preferredLang,
	ui,
} from "../../../lib/i18n";
import { priceText, safeMedia } from "../../../lib/recorded";

// B7d K-14: bookable consultations, featured first (the API's order). A 404
// (booking off, or nothing bookable) renders the academy 404, as B7b's
// course pages do.
const result = Astro.locals.siteResult;
const lang = Astro.params.lang;
const site = result.kind === "ok" ? result.site : null;
const fetched =
	site && isLang(lang) ? await getConsultations(Astro.locals.host) : null;
const list =
	fetched?.kind === "ok" && fetched.data.length > 0 ? fetched.data : null;
const path = "/consultations";
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
	<Layout site={site} lang={lang} title={ui(lang).consultations} description={pick(site.branding.name, lang)} path={path}>
		<Header site={site} lang={lang} path={path} />
		<main class="mx-auto max-w-5xl p-6">
			<h1 class="text-2xl font-semibold">{ui(lang).consultations}</h1>
			<div class="mt-6 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
				{list.map((c) => (
					<article class="flex flex-col gap-2 rounded-lg border border-border p-4">
						<a href={`/${lang}/consultations/${c.id}`} class="flex flex-col gap-2 font-medium">
							{safeMedia(site, c.cover_url) && (
								<img src={safeMedia(site, c.cover_url)} alt="" class="aspect-video w-full rounded object-cover" loading="lazy" />
							)}
							<span>{pickText(c.name_ar, c.name_en, lang)}</span>
						</a>
						<p class="whitespace-pre-line text-sm">{pickText(c.description_ar, c.description_en, lang)}</p>
						<p class="text-sm text-muted-foreground">
							{[minutesText(lang, c.duration_minutes), consultModeText(lang, c.delivery_mode), ratingText(c.rating_average, c.rating_count, lang)].filter(Boolean).join(" · ")}
						</p>
						<p class="font-medium">{priceText(c.price_minor, c.currency, lang)}</p>
					</article>
				))}
			</div>
		</main>
		<Footer site={site} lang={lang} />
	</Layout>
)}
```

`marketing/src/pages/[lang]/consultations/[id].astro`:

```astro
---
import Footer from "../../../components/Footer.astro";
import Header from "../../../components/Header.astro";
import PageNotFound from "../../../components/PageNotFound.astro";
import StatusPage from "../../../components/StatusPage.astro";
import Layout from "../../../layouts/Layout.astro";
import { getConsultation, pickText, ratingText } from "../../../lib/consultations";
import { consultModeText, isLang, minutesText, preferredLang, ui } from "../../../lib/i18n";
import { priceText, safeMedia } from "../../../lib/recorded";

// B7d K-12, K-14: one bookable consultation: description, teachers (no
// private details reach this payload) and approved reviews, attributed only
// as "Student" or "Visitor". "Book" opens the dashboard's public wizard.
const result = Astro.locals.siteResult;
const lang = Astro.params.lang;
const id = Astro.params.id ?? "";
const site = result.kind === "ok" ? result.site : null;
const fetched =
	site && isLang(lang) ? await getConsultation(Astro.locals.host, id) : null;
const c = fetched?.kind === "ok" ? fetched.data : null;
const path = `/consultations/${id}`;
const cover = site && c ? safeMedia(site, c.cover_url) : "";
const rating = c ? ratingText(c.rating_average, c.rating_count, isLang(lang) ? lang : "en") : "";
---
{!site ? (
	<StatusPage kind={result.kind === "ok" ? "notfound" : result.kind} />
) : !isLang(lang) ? (
	<PageNotFound site={site} lang={preferredLang(Astro.request.headers.get("accept-language"))} path="/" />
) : fetched?.kind === "unavailable" ? (
	<StatusPage kind="unavailable" />
) : !c ? (
	<PageNotFound site={site} lang={lang} path="/consultations" />
) : (
	<Layout site={site} lang={lang} title={pickText(c.name_ar, c.name_en, lang)} description={pickText(c.description_ar, c.description_en, lang).slice(0, 160)} path={path}>
		<Header site={site} lang={lang} path={path} />
		<main class="mx-auto grid max-w-5xl gap-6 p-6 lg:grid-cols-3">
			<section class="flex flex-col gap-4 lg:col-span-2">
				<h1 class="text-2xl font-semibold">{pickText(c.name_ar, c.name_en, lang)}</h1>
				{cover && <img src={cover} alt="" class="aspect-video w-full rounded object-cover" />}
				<p class="whitespace-pre-line">{pickText(c.description_ar, c.description_en, lang)}</p>
				<h2 class="font-medium">{ui(lang).consultTeachers}</h2>
				<ul class="flex flex-col gap-3">
					{c.teachers.map((tc) => (
						<li class="flex gap-3">
							<span aria-hidden="true" class="flex size-8 items-center justify-center rounded-full bg-secondary font-medium">{tc.initial}</span>
							<span class="flex flex-col">
								<span class="font-medium">{tc.full_name}</span>
								{tc.bio && <span class="whitespace-pre-line text-sm text-muted-foreground">{tc.bio}</span>}
							</span>
						</li>
					))}
				</ul>
				<h2 class="font-medium">{ui(lang).consultReviews}</h2>
				{c.reviews.length === 0 ? (
					<p class="text-sm text-muted-foreground">{ui(lang).noReviews}</p>
				) : (
					<ul class="flex flex-col gap-3">
						{c.reviews.map((r) => (
							<li class="flex flex-col gap-1 rounded border border-border p-3">
								<span aria-label={`${r.rating}/5`}>{"★".repeat(r.rating)}{"☆".repeat(5 - r.rating)}</span>
								{r.comment && <p class="whitespace-pre-line text-sm">{r.comment}</p>}
								<span class="text-xs text-muted-foreground">{r.by === "student" ? ui(lang).reviewerStudent : ui(lang).reviewerVisitor}</span>
							</li>
						))}
					</ul>
				)}
			</section>
			<aside class="flex flex-col gap-3 rounded-lg border border-border p-4">
				<p class="text-lg font-medium">{priceText(c.price_minor, c.currency, lang)}</p>
				<p class="text-sm">{minutesText(lang, c.duration_minutes)} · {consultModeText(lang, c.delivery_mode)}</p>
				{rating && <p class="text-sm">{rating}</p>}
				<a href={`/app/consult/${c.id}`} class="rounded-md bg-primary px-3 py-2 text-center text-primary-foreground">
					{ui(lang).bookConsultation}
				</a>
				{c.fee_enabled && <p class="text-xs text-muted-foreground">{ui(lang).consultFee}</p>}
			</aside>
		</main>
		<Footer site={site} lang={lang} />
	</Layout>
)}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `M pnpm vitest run` and `M pnpm astro check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C marketing add 'src/pages/[lang]/consultations/index.astro' 'src/pages/[lang]/consultations/[id].astro' test/consultations.test.ts
git -C marketing commit -m "feat(consultations): public consultation list and detail pages (B7d K-12, K-14)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 22: e2e — a visitor books, pays, is confirmed, completes and reviews

**Files:**
- Modify: `dashboard/e2e/b7-helpers.ts` (B7-owned: `patchAsAdmin`)
- Create: `dashboard/e2e/b7-consultation-booking.spec.ts`

**Interfaces:**
- Consumes: `visit` (`e2e/b7-helpers.ts`), `DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD`, `expectLoggedIn`, `postAsAdmin` (`e2e/fixtures.ts`), `manage` (`e2e/manage.ts`); the demo seed (B7c: "Placement consultation", Bilal opted in; B2e: Bilal's windows Monday–Thursday 16:00–21:00); the wizard, manage page and return page strings above.
- Produces: `patchAsAdmin(page, path, data)`.

- [ ] **Step 1: The PATCH helper**

Add to `dashboard/e2e/b7-helpers.ts` (`type Page` and `DEMO_URL` are already imported there):

```ts
/** A PATCH to the API as the signed-in admin, CSRF as postAsAdmin sends it. */
export async function patchAsAdmin(page: Page, path: string, data: object) {
	const csrf =
		(await page.context().cookies()).find((c) => c.name === "csrftoken")?.value ?? "";
	return page.request.patch(`${DEMO_URL}/api/v1/${path}`, {
		headers: { "X-CSRFToken": csrf, Referer: `${DEMO_URL}/app/` },
		data,
	});
}
```

- [ ] **Step 2: The spec**

`dashboard/e2e/b7-consultation-booking.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { patchAsAdmin, visit } from "./b7-helpers";
import { DEMO_ADMIN, DEMO_URL, DEV_PASSWORD, expectLoggedIn, postAsAdmin } from "./fixtures";
import { manage } from "./manage";

// Plan 60 (B7d): a visitor books the demo consultation's first free slot,
// pays through the simulator and lands on the manage page; the office
// confirms (the link shows), the consultation takes place and completes, and
// the visitor's review, once approved, shows on the public page. Stamped
// names, so a second run works too.

// The marketing site's header flag is cached for 60 s.
const POLL = { timeout: 90_000, intervals: [2_000, 5_000] };

test("a visitor books and pays a consultation, and the approved review goes public", async ({
	page,
	browser,
}) => {
	test.setTimeout(300_000);
	manage(
		"set_features",
		"demo",
		"--on",
		"consultations",
		"teacher_availability",
		"invoices",
		"online_payments",
	);
	const stamp = Date.now();
	const email = `b7d-${stamp}@demo.test`;
	const comment = `Very helpful ${stamp}`;

	await visit(page, `${DEMO_URL}/app/login`, page.getByRole("textbox", { name: /email/i }));
	await page.getByRole("textbox", { name: /email/i }).fill(DEMO_ADMIN);
	await page.getByRole("textbox", { name: /password/i }).fill(DEV_PASSWORD);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, /demo academy admin/i);
	const products = (await (
		await page.request.get(`${DEMO_URL}/api/v1/consultations/products/`)
	).json()) as { id: number; name_en: string }[];
	const placement = products.find((p) => p.name_en === "Placement consultation");
	expect(placement, "seeded Placement consultation").toBeTruthy();
	const productId = (placement as { id: number }).id;

	// A visitor books the first free slot and pays through the simulator.
	const visitor = await browser.newContext();
	const guest = await visitor.newPage();
	await guest.addInitScript(() => localStorage.setItem("etqan-locale", "en"));
	await visit(
		guest,
		`${DEMO_URL}/app/consult/${productId}`,
		guest.getByRole("heading", { name: "Placement consultation" }),
	);
	await guest.getByRole("radio", { name: /Bilal/ }).check();
	// Slot and star radios are visually hidden inside their labels: click the label.
	await guest.locator('label:has(input[name="booking-slot"])').first().click();
	await guest.getByLabel("Name").fill(`B7d Visitor ${stamp}`);
	await guest.getByLabel("Email").fill(email);
	await guest.getByLabel("WhatsApp").fill("+201000000777");
	await guest.getByRole("button", { name: "Pay with Stripe" }).click();
	const sheet = guest.getByRole("region", { name: "Pay online" });
	await expect(sheet.getByText(/15\.00/).first()).toBeVisible();
	await sheet.getByRole("button", { name: "Continue to Stripe" }).click();
	await expect(guest).toHaveURL(/\/app\/pay\/simulate\//);
	await guest.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(guest).toHaveURL(/\/app\/pay\/return\?checkout=/);
	await expect(guest.getByText("Paid — thank you.")).toBeVisible();
	await guest.getByRole("link", { name: "Open your booking" }).click();
	await expect(guest).toHaveURL(/\/app\/consult\/manage\/[A-Za-z0-9_-]{43}$/);
	await expect(guest.getByText("Under review")).toBeVisible();
	const manageUrl = guest.url();

	// The office finds it among the online bookings, gives it a link and confirms it.
	const listed = await page.request.get(
		`${DEMO_URL}/api/v1/consultations/requests/?self_booked=true&page_size=100`,
	);
	const rows = (await listed.json()).results as { id: number; email: string }[];
	const row = rows.find((r) => r.email === email);
	expect(row, "the visitor's booking in the office list").toBeTruthy();
	const id = (row as { id: number }).id;
	const office = async (action: string, data: object) => {
		const resp = await postAsAdmin(page, `consultations/requests/${id}/${action}/`, data);
		expect(resp.status(), await resp.text()).toBe(200);
	};
	await office("delivery", { meeting_url: "https://meet.example.test/b7d" });
	await office("confirm", {});
	await guest.goto(manageUrl);
	await expect(guest.getByRole("link", { name: "Join the consultation" })).toHaveAttribute(
		"href",
		"https://meet.example.test/b7d",
	);

	// It took place: the office moves it to yesterday, records it and completes it.
	await office("reschedule", { starts_at: new Date(Date.now() - 86_400_000).toISOString() });
	await office("delivery", {
		student_attendance: "present",
		teacher_attendance: "present",
		session_status: "completed",
	});
	await office("complete", {});

	// The visitor rates it; the office approves; the public page shows it.
	await guest.goto(manageUrl);
	await guest.locator('label:has(input[name="review-rating"])').nth(4).click();
	await guest.getByLabel("Comment (optional)").fill(comment);
	await guest.getByRole("button", { name: "Send review" }).click();
	await expect(
		guest.getByText("Thank you. Your review waits for the academy's approval."),
	).toBeVisible();
	const pending = await page.request.get(
		`${DEMO_URL}/api/v1/consultations/reviews/?status=pending&page_size=100`,
	);
	const review = ((await pending.json()).results as { id: number; comment: string }[]).find(
		(r) => r.comment === comment,
	);
	expect(review, "the visitor's review").toBeTruthy();
	const decided = await patchAsAdmin(
		page,
		`consultations/reviews/${(review as { id: number }).id}/`,
		{ status: "approved" },
	);
	expect(decided.status(), await decided.text()).toBe(200);
	await expect
		.poll(
			async () => (await guest.request.get(`${DEMO_URL}/en/consultations/${productId}`)).text(),
			POLL,
		)
		.toContain(comment);
	await visitor.close();
});
```

- [ ] **Step 3: Run it against a fresh stack**

Run (meta worktree; rebuild images first if dependencies changed): `just seed` then `just e2e e2e/b7-consultation-booking.spec.ts`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git -C dashboard add e2e/b7-helpers.ts e2e/b7-consultation-booking.spec.ts
git -C dashboard commit -m "test(e2e): a visitor books, pays and reviews a consultation (B7d)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 23: Gates, final review and queue

These run only once the phase holds a slot and B7c (and B7b) are merged. No step was run when this plan was written.

- [ ] **Step 1:** `just test` (backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70; marketing tests) and `just lint` (ruff, biome, `lint-imports`, gitleaks, `astro check`). Both must pass.
- [ ] **Step 2:** `just seed`, then `just e2e`: the whole suite, because `b3-online-payments`, `b3-paypal`, `b7-recorded-store` and the new spec share the simulator and the demo teacher's time. It must pass on a fresh stack.
- [ ] **Step 3:** Dispatch a fresh whole-slice reviewer against the spec (K-1…K-16, §3–§6), the phase decisions (B7-3, B7-4, B7-10, B7-17) and this plan's Review Focus and "Decisions this plan takes". Fix every critical or important finding. Log minor ones in `../_ledger/orchestration/phases/B7.md`.
- [ ] **Step 4:** In the meta worktree, commit the submodule pointers on `feat/b7d-consultation-booking` with `git add backend dashboard marketing`, never `-a`. Then run `python3 scripts/orchestration/ledger.py queue B7d` and follow the merge-queue steps:
  - rebase every touched repo onto its trunk;
  - regenerate `routeTree.gen.ts` (`F pnpm build`);
  - regenerate `0002_booking.py` if B7c's migrations moved (another B7 slice landing a consultations migration first);
  - rerun the gates;
  - push, open the four PRs (meta with `--repo Etqan-agency/etqan_tutor`), and record them with `python3 scripts/orchestration/ledger.py slice B7d --prs "<urls>"`.

---

## Self-review (done while writing)

- **Spec coverage.** K-1 → Tasks 3, 10, 12; K-2 → 1, 3, 10, 15; K-3 → 4, 11, 16; K-4 → 7, 11, 12; K-5 → 5; K-6 → 6, 18; K-7 → 1, 2, 8; K-8 → 4, 10, 11; K-9 → 4, 6, 9, 14, 15; K-10 → 7, 9, 11, 15; K-11 → 9, 11, 15, 17; K-12 → 1, 9, 10, 13, 17, 21; K-13 → 4, 9, 12, 15, 16; K-14 → 10, 16, 19–21; K-15 → 14, 18; K-16 → 2, 12, 13, 17. §3 → Task 1; §4 → Tasks 10–13 (and D53's contract in Task 5); §5 → each task's tests and Task 22; §6 non-goals: no booker cancellation, no notices beyond K-9, no Zoom, no wallet or hand payment in the wizard.
- **Names used across tasks** (checked): `book_one`, `book_body`, `MANAGE_KEYS`, `SUNDAY_NOON`, `frozen`, `online`; `room_left`, `live_q`, `hold_expired`, `lock_booker`; `bookable_product`, `offered_teachers`, `booking_slots`, `last_bookable_day`; `prepare`/`complete`/`slot_gone`/`not_payable`/`slot_taken`; `require_provider`, `providers_for_product`, `providers_for_request`, `rehold`, `start_payment`; `by_token`, `family_requests`, `family_request`, `actions`, `review_of`, `last_day`, `ask_reschedule`, `leave_review`; `review_summary`, `ratings_by_product`, `decide_review`; dashboard `Booker`, `bookingApi`, `useManage`, `usePayBooking`, `useAskReschedule`, `useReviewBooking`, `BookingSlots`, `ManagePage`, `productName`, `BookingWizard`, `BookPicker`, `FamilyConsultations`, `ReviewsAdmin`, `rememberManage`, `manageTokenFor`, `tokenOf`, `useNoReferrer`; marketing `getConsultations`, `getConsultation`, `hasConsultations`, `pickText`, `ratingText`, `minutesText`, `consultModeText`.
