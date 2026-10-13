# Plan 61: B7f Consultation Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B7c, B7d

**Goal:** The office exports the consultation request list as CSV. It also sees and exports what each teacher earned from paid, completed consultations and what the academy kept, per teacher and currency, over a date range.

**Architecture:** One new service module, `etqan/consultations/services/earnings.py`, holds the F-2 earnings rules, the F-3 grouping and estimate, and `teacher_earnings` for B4. It reads billing payment statuses through `billing.services.payments_queryset()` and converts through `finance.services.convert_estimate`. The B7c request list view gains `CSVExportMixin` (office-only CSV). A new view `reports/margins/` answers JSON and two CSVs, guarded by the new verb `consultation_request.export_margins`. The dashboard's `/scheduling/consultations` gains an Export button and a **Profit margins** tab.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest + RTL; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7f-consultation-reports-design.md` (F-1…F-5, §3, §4) is binding. Phase rules: `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md` B7-11, §3 row B7f. Code this plan builds on: B7c (plan 50, merged: `backend/etqan/consultations/`, `dashboard/src/features/consultations/`) and B7d (plan 60, `docs/superpowers/plans/2026-10-09-plan-60-consultation-booking.md` on branch `feat/b7b-recorded-store`, which must merge **before** this plan starts).

**Written in spec-only mode.** No command below has been run.

## Global Constraints

- **B7d first.** Before Task 1, check that B7d is on trunk: `grep -n "self_booked" backend/etqan/consultations/models.py dashboard/src/features/consultations/schemas.ts` must print lines in both files. If it prints nothing, stop: this plan cannot start.
- **Branches.** `backend/` and `dashboard/` are on `feat/b7f-consultation-reports`. Bring each up to trunk with B7d: `git -C backend fetch origin && git -C backend rebase origin/main`, and the same for `dashboard`. The meta repo stays on `feat/b7f-consultation-reports`. Never run any `git submodule` command. Never use `git commit -a`: stage explicit paths.
- **Commands.** Backend tests run only through `just test-backend` (the whole suite, with coverage). Never call `manage.py` or `pytest` directly. The final gate is `just test`, `just lint` and `just e2e e2e/b7-consultations-office.spec.ts`. Prefixes, after `set -a; . ./.env.stream; set +a` in the meta worktree:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>`. It is used here **only** for `ruff format` / `ruff check`, never for tests.
  - `F <cmd>` = the same with the `dashboard` service (vitest, tsc, biome).
- **Lint on every commit.** Backend: `B ruff format <files> && B ruff check <files>`. Dashboard: `F pnpm biome check --write <files>`. Imports go only at the top of a module.
- **Boundaries.** Business logic goes in `etqan/consultations/services/`. `etqan.consultations` reaches `billing` and `finance` only through their `services` (lint-imports). Billing's `Payment.Status.COMPLETED` is read as the string `"completed"`, because consultations may not import `billing.models` (B7c precedent: `"cancelled"` for scheduling).
- **Money.** Integer minor units plus a 3-letter currency. Never summed across currencies (B3-4). The teacher's share is `round_half_up(amount_minor × teacher_share_bp / 10 000)` per request, in integers only. `amount_minor` excludes the fee (B3-8, D16). CSV money columns are minor units, labelled "(minor units)" (billing CSV precedent).
- **Dates.** `from`/`to` are academy dates, both ends included, compared against `completed_at` converted to the academy zone (`common.academy_zone()`). Stored instants are UTC.
- **Shared lists.** Additions go only under `── phase B7 ──` markers, or in the B7 blocks of `access/tests/test_routes.py` (`# Phase B7, slice B7c` precedent; this plan adds `# Phase B7, slice B7f`). `VERB_LABELS` in `access/registry.py` sits outside the markers. It goes in under a one-commit ledger claim (Task 3). Every other file outside B7's own folders is also changed under a claim, one commit per claim (B7d precedent):

  ```bash
  python3 scripts/orchestration/ledger.py claim B7 <path> --reason "<why>"
  # … edit, run the named tests, commit …
  python3 scripts/orchestration/ledger.py release B7 <path>
  ```

  | Path | What changes | Task |
  |---|---|---|
  | `backend/pyproject.toml` | the consultations contract's `etqan.finance.services` whitelist (B7 block) | 2 |
  | `backend/etqan/access/registry.py` | `EXPORT_MARGINS`, `VERB_LABELS` (outside markers); `consultation_request` verbs (B7 marker) | 3 |
  | `backend/etqan/access/tests/test_registry.py` | the verb assertions that name `supervise` as the only extra verb | 3 |
  | `backend/etqan/access/tests/test_routes.py` | `ROUTES`, `NEEDS_ALL_CODES`, `FEATURES` lines for `reports/margins/` | 4 |

- **Strings.** New strings go in `dashboard/src/locales/{en,ar}/consultations.json`, en and ar only, with equal keys (`src/locales/locales.test.ts`). No plural keys.
- **Coverage.** Backend ≥ 80 %. Dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- **No migration.** B7f adds no model field (F-2 reads B7c's columns and B7d's `self_booked`).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## B7d dependencies (narrowed)

| What B7f reads | From B7d | Where |
|---|---|---|
| `Request.self_booked` (the "self-booked" CSV column) | plan 60 Task 1 | Task 5 only |
| `FLAGS` and `filter_requests(self_booked=)` in the list view (the CSV follows the list's filters) | plan 60 Task 2 | Task 5 only |
| `filter_requests` hiding `cancel_reason="unpaid"` rows by default | plan 60 Task 2 | Task 5 (inherited, no code) |
| Online payments: `paid_method` `stripe`/`paypal`, `fee_minor > 0`, `billing_method` blank, `payment` set by `record_link_payment` (status `completed`) | plan 60 Task 6 | Task 1 reads only `payment_id`, `amount_minor`, `fee_minor`, `currency`, so it works for both paths with no B7d-specific code |
| `RequestFilters.self_booked?: boolean` | plan 60 Task 14 | Task 6 (`csv.ts` turns booleans into text) |
| `RequestsTabs` with `type RequestsView = "list" \| "calendar" \| "reviews"`, the route's `reviews` branch | plan 60 Task 16 | Task 8 |

## Decisions this plan takes where the spec is silent

Each is `[assumed]`; the tests pin it.

1. **The requests CSV's product column** is the product's English name (`name_en`), as `safe_cell` renders a product dict elsewhere. Times are written `YYYY-MM-DD HH:MM`. "Created at" is in academy time.
2. **Unpaid rows in the requests CSV** show amount `0`, fee `0` and blank currency, transaction and paid-on cells (the stored values).
3. **The verb label** is lowercase, `("export_margins", "export profit margins", "تصدير هوامش الربح")`, to match `VERBS` and `SUPERVISE`.
4. **Margins also need `view_any`** (F-5 "Both reports need `consultation_request.view_any`"). The route declares `consultation_request.export_margins`. The view also checks `view_any` itself and answers 403 naming it (the B7c `payment.create` precedent). `test_routes.NEEDS_ALL_CODES` records the pair.
5. **Default range.** Each missing end defaults on its own: `from` to the first day of the current academy month, `to` to its last day. `to` before `from` is 400 `to`.
6. **A null share snapshot** (impossible after B7c's `complete`) counts as 0 bp.
7. **The JSON report** has no per-request lines. Those are only in `?detail=1` CSV. The summary CSV has no total rows.
8. **The dashboard estimate line** shows only when the estimate exists *and* some total is in another currency than the estimate's (the `FinanceSummaryCard` precedent: an all-base report needs no conversion).
9. **CSV column order and labels** are this plan's (EXP-002 columns are UNKNOWN).
10. **Row order.** Margin rows are sorted by teacher name (case-folded), then teacher id, then currency. Totals are sorted by currency. Detail lines are sorted by `completed_at`, then id.

## Review Focus

1. **A payment refunded, credited to a wallet or deleted after completion.** Expected: the request leaves the earnings and the "Left out" count goes up. A credited payment is excluded too (D36). Pinned in Task 1 `test_unpaid_refunded_credited_and_deleted_payments_are_left_out_and_counted`.
2. **A consultation completed near midnight in a non-UTC academy.** Expected: it falls on its academy date, and both ends of the range are included. Pinned in Task 1 `test_completed_in_range_both_ends_in_academy_dates` and Task 2 `test_report_range_defaults_to_the_academy_month`.
3. **Mixed currencies with one exchange rate missing.** Expected: there is one row and one total per currency and no estimate at all, never a partial one. Pinned in Task 2 `test_rows_per_teacher_and_currency_and_totals_per_currency` and `test_no_estimate_when_a_rate_is_missing`.
4. **Who can pull money out through a CSV.** Expected: a teacher gets 403 for `requests/?format=csv` but can still read the list. A clerk with only `view_any` gets 403 on margins. With `export` off, `?format=csv` is 404 on both routes. Pinned in Task 5 `test_a_teacher_reads_the_list_but_gets_403_for_the_csv`, Task 4 `test_margins_need_export_margins_and_view_any`, and `test_csv_is_404_while_export_is_off` in both Task 4 (margins) and Task 5 (requests).
5. **A person's name or a transaction number starting with `=`, `+` or `@`.** Expected: every cell is defused with a leading `'` in both CSVs and in the margins detail CSV. A phone number like `+201000000001` stays as it is. Pinned in Task 5 `test_formula_cells_are_defused` and Task 4 `test_the_detail_csv_has_its_own_columns`.

---

## File Structure

```text
backend/etqan/consultations/
  services/earnings.py        NEW  F-2 lines, F-3 grouping/totals/estimate, F-4 teacher_earnings, report_range
  services/__init__.py        re-exports (sorted __all__)
  api/report_payloads.py      NEW  JSON + CSV rows for the margins report and the requests CSV
  api/report_views.py         NEW  MarginsView (JSON, CSV, ?detail=1)
  api/request_views.py        RequestListView + CSVExportMixin, office-only CSV, _list_filters
  api/urls.py                 + reports/margins/
  tests/conftest.py           + two fixture, done() helper
  tests/test_earnings.py      NEW
  tests/test_margins.py       NEW
  tests/test_api_margins.py   NEW
  tests/test_api_requests_csv.py NEW
Claimed: backend/pyproject.toml, backend/etqan/access/registry.py,
  backend/etqan/access/tests/test_registry.py, backend/etqan/access/tests/test_routes.py

dashboard/src/features/consultations/
  schemas.ts                  + MarginFilters, MarginRow, MarginTotal, MarginEstimate, MarginsAnswer
  api.ts                      + margins()
  csv.ts / csv.test.ts        NEW  requestsCsvUrl, marginsCsvUrl (not in api.ts: tests mock ./api whole)
  queries.ts                  + useMargins
  fixtures.ts                 + marginsReport
  RequestsAdmin.tsx (+test)   + ExportButton
  MarginsReport.tsx (+test)   NEW  the Profit margins tab
  RequestsTabs.tsx (+test)    + "margins"
  index.ts                    + MarginsReport
dashboard/src/routes/_authed/scheduling.consultations.tsx   view=margins
dashboard/src/locales/{en,ar}/consultations.json            requests.tabs.margins, margins.*
dashboard/e2e/b7-consultations-office.spec.ts               share on the product; margins step
```

---

### Task 1: Earnings lines and `teacher_earnings` (F-2, F-4)

**Files:**
- Create: `backend/etqan/consultations/services/earnings.py`
- Modify: `backend/etqan/consultations/services/__init__.py`, `backend/etqan/consultations/tests/conftest.py`
- Test: `backend/etqan/consultations/tests/test_earnings.py` (new)

**Interfaces:**
- Consumes: B7c `Request` (`status`, `completed_at`, `teacher_share_bp`, `amount_minor`, `fee_minor`, `currency`, `payment_id`, `paid_method`, `billing_method`, `reference`), `common.academy_zone()`, `billing.services.payments_queryset()`.
- Produces (all re-exported from `etqan.consultations.services`):
  - `EarningLine(request_id, reference, completed_on: date, product_id, product_name_ar, product_name_en, teacher_user_id, teacher_name, name, currency, amount_minor, fee_minor, share_bp, share_minor, margin_minor, paid_method, billing_method)` (frozen dataclass)
  - `Earnings(lines: list[EarningLine], excluded: int)`
  - `MarginRow(teacher_user_id, teacher_name, currency, count, amount_minor, fee_minor, share_minor, margin_minor)`
  - `TeacherEarning(teacher_user_id, currency, count, amount_minor, share_minor, margin_minor)`
  - `earning_lines(*, since: date, until: date, teacher_user_id: int | None = None, product_id: int | None = None) -> Earnings`
  - `group_by_teacher(lines: list[EarningLine]) -> list[MarginRow]`
  - `teacher_earnings(*, since: date, until: date, teacher_user_id: int | None = None) -> list[TeacherEarning]`
  - module-level `round_half_up(numerator: int, denominator: int) -> int` (not re-exported)
  - test helpers in `tests/conftest.py`: fixture `two`, function `done(b, *, amount=1500, fee=0, share_bp=5000, at=MID, currency="USD", teacher=None, paid=True) -> Request`, constants `OCT_1`, `OCT_31`, `MID`.

- [ ] **Step 1: Add the test helpers to `tests/conftest.py`**

Add the imports at the top of `backend/etqan/consultations/tests/conftest.py` (keep the existing ones). Add `from datetime import date` next to the other `datetime` imports, and `from etqan.consultations.models import Request` next to the `Product` import:

```python
from datetime import date

from etqan.consultations.models import Request
```

Append at the end of the module:

```python
# Slice B7f: completed, paid requests for the earnings reports.
OCT_1, OCT_31 = date(2026, 10, 1), date(2026, 10, 31)
MID = datetime(2026, 10, 15, 12, 0, tzinfo=UTC)


@pytest.fixture
def two(booking):
    """Maryam opted in and on the product beside Bilal."""
    consult_services.set_consultant(booking.teacher2.pk, offers=True, by=booking.admin)
    consult_services.update_product(
        booking.product,
        teacher_user_ids=[booking.teacher.pk, booking.teacher2.pk],
    )
    return booking


def done(  # noqa: PLR0913 -- keyword-only test helper
    b,
    *,
    amount=1500,
    fee=0,
    share_bp=5000,
    at=MID,
    currency="USD",
    teacher=None,
    paid=True,
):
    """A completed request, paid by hand in billing unless `paid=False`. The
    share snapshot, fee and currency are set as `complete` and B7d's online
    payment would set them."""
    extra = {"teacher_user_id": teacher.pk} if teacher else {}
    row = new_request(b, starts_at=None, **extra)
    if paid:
        row = consult_services.record_payment(
            row, billing_method="cash", by=b.admin, amount_minor=amount
        )
    Request.objects.filter(pk=row.pk).update(
        status="completed",
        completed_at=at,
        teacher_share_bp=share_bp,
        fee_minor=fee if paid else 0,
        currency=currency if paid else "",
    )
    return Request.objects.get(pk=row.pk)
```

- [ ] **Step 2: Write the failing tests**

`backend/etqan/consultations/tests/test_earnings.py`:

```python
"""Slice B7f F-2, F-4 (phase B7-11): the earnings rules."""

from datetime import UTC
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.billing import services as billing_services
from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.services import common
from etqan.consultations.services.earnings import round_half_up
from etqan.consultations.tests.conftest import OCT_1
from etqan.consultations.tests.conftest import OCT_31
from etqan.consultations.tests.conftest import done
from etqan.consultations.tests.conftest import new_request

pytestmark = pytest.mark.django_db


def lines(**kwargs):
    return services.earning_lines(since=OCT_1, until=OCT_31, **kwargs)


def ids(earnings):
    return [line.request_id for line in earnings.lines]


def test_round_half_up():
    assert [round_half_up(n, 2) for n in (1, 2, 3, 5)] == [1, 1, 2, 3]


def test_completed_in_range_both_ends_in_academy_dates(booking, monkeypatch):
    done(booking, at=datetime(2026, 9, 30, 20, 59, tzinfo=UTC))  # 23:59, 30 Sep
    first = done(booking, at=datetime(2026, 9, 30, 21, 0, tzinfo=UTC))  # 00:00, 1 Oct
    last = done(booking, at=datetime(2026, 10, 31, 20, 59, tzinfo=UTC))  # 23:59, 31 Oct
    done(booking, at=datetime(2026, 10, 31, 21, 0, tzinfo=UTC))  # 00:00, 1 Nov
    monkeypatch.setattr(common, "academy_zone", lambda: "Asia/Riyadh")
    got = lines()
    assert ids(got) == [first.pk, last.pk]
    assert got.excluded == 0  # out of range is not "left out"
    assert [line.completed_on for line in got.lines] == [OCT_1, OCT_31]


def test_only_completed_requests_count(booking):
    kept = done(booking)
    confirmed = new_request(booking, starts_at=None)
    services.record_payment(confirmed, billing_method="cash", by=booking.admin)
    Request.objects.filter(pk=confirmed.pk).update(status="confirmed")
    got = lines()
    assert (ids(got), got.excluded) == ([kept.pk], 0)


def test_unpaid_refunded_credited_and_deleted_payments_are_left_out_and_counted(
    booking,
):
    kept = done(booking)
    done(booking, paid=False)
    refunded, credited, deleted = done(booking), done(booking), done(booking)
    payments = billing_services.payments_queryset()
    payments.filter(pk=refunded.payment_id).update(status="refunded")
    payments.filter(pk=credited.payment_id).update(status="credited")
    payments.filter(pk=deleted.payment_id).delete()
    got = lines()
    assert ids(got) == [kept.pk]
    assert got.excluded == 4


def test_the_fee_is_left_out_of_the_split_and_shown(booking):
    row = done(booking, amount=1500, fee=75, share_bp=5000)
    [line] = lines().lines
    assert (
        line.amount_minor,
        line.fee_minor,
        line.share_minor,
        line.margin_minor,
    ) == (1500, 75, 750, 750)
    assert (line.reference, line.currency, line.share_bp) == (
        row.reference,
        "USD",
        5000,
    )
    assert (line.teacher_user_id, line.teacher_name, line.name) == (
        booking.teacher.pk,
        "Bilal",
        "Yusuf Omar",
    )
    assert (line.paid_method, line.billing_method) == ("manual", "cash")


@pytest.mark.parametrize(
    ("amount", "share_bp", "share"),
    [(1001, 5000, 501), (3, 5000, 2), (1003, 3333, 334), (999, 0, 0), (999, 10000, 999)],
)
def test_the_share_rounds_half_up(booking, amount, share_bp, share):
    done(booking, amount=amount, share_bp=share_bp)
    [line] = lines().lines
    assert (line.share_minor, line.margin_minor) == (share, amount - share)


def test_the_snapshot_holds_after_the_product_share_changes(booking):
    done(booking, amount=1000, share_bp=4000)
    services.update_product(booking.product, teacher_share_bp=1000)
    [line] = lines().lines
    assert (line.share_bp, line.share_minor) == (4000, 400)


def test_the_product_filter(booking):
    kept = done(booking)
    assert ids(lines(product_id=booking.product.pk)) == [kept.pk]
    assert lines(product_id=booking.product.pk + 999) == services.Earnings([], 0)


def test_teacher_earnings_per_teacher_and_currency(two):
    done(two, amount=1500)
    done(two, amount=500, share_bp=2000)
    done(two, amount=10000, currency="EGP")
    done(two, amount=2000, teacher=two.teacher2)
    assert services.teacher_earnings(since=OCT_1, until=OCT_31) == [
        services.TeacherEarning(two.teacher.pk, "EGP", 1, 10000, 5000, 5000),
        services.TeacherEarning(two.teacher.pk, "USD", 2, 2000, 850, 1150),
        services.TeacherEarning(two.teacher2.pk, "USD", 1, 2000, 1000, 1000),
    ]


def test_teacher_filter_and_a_fixed_number_of_queries(two):
    done(two, teacher=two.teacher2)

    def cost(**kwargs):
        with CaptureQueriesContext(connection) as ctx:
            got = services.teacher_earnings(since=OCT_1, until=OCT_31, **kwargs)
        return got, len(ctx.captured_queries)

    one, few = cost()
    for _ in range(3):
        done(two)
    more, many = cost()
    assert (len(one), len(more)) == (1, 2)
    assert few == many
    only, _ = cost(teacher_user_id=two.teacher2.pk)
    assert [e.teacher_user_id for e in only] == [two.teacher2.pk]
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `just test-backend`
Expected: FAIL in `etqan/consultations/tests/test_earnings.py` with `ModuleNotFoundError: No module named 'etqan.consultations.services.earnings'`.

- [ ] **Step 4: Write `services/earnings.py`**

`backend/etqan/consultations/services/earnings.py`:

```python
"""Slice B7f F-2, F-3, F-4 (phase B7-11): what each teacher earned from
consultations and what the academy kept. Integer minor units, per currency,
never summed across currencies (B3-4). Paying the teacher stays manual."""

from dataclasses import dataclass
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from etqan.billing import services as billing_services
from etqan.consultations.models import Request
from etqan.consultations.services import common

# billing's Payment.Status.COMPLETED. A string: consultations may not import
# billing's models. A later wallet "credited" (D36) or "refunded" is excluded.
PAYMENT_COMPLETED = "completed"
BP = 10_000


def round_half_up(numerator: int, denominator: int) -> int:
    """``numerator / denominator`` rounded half up, in integers only. For
    ``numerator >= 0`` and ``denominator > 0``."""
    return (2 * numerator + denominator) // (2 * denominator)


@dataclass(frozen=True)
class EarningLine:
    request_id: int
    reference: str
    completed_on: date
    product_id: int
    product_name_ar: str
    product_name_en: str
    teacher_user_id: int
    teacher_name: str
    name: str
    currency: str
    amount_minor: int
    fee_minor: int
    share_bp: int
    share_minor: int
    margin_minor: int
    paid_method: str
    billing_method: str


@dataclass(frozen=True)
class Earnings:
    lines: list[EarningLine]
    excluded: int


@dataclass(frozen=True)
class MarginRow:
    teacher_user_id: int
    teacher_name: str
    currency: str
    count: int
    amount_minor: int
    fee_minor: int
    share_minor: int
    margin_minor: int


@dataclass(frozen=True)
class TeacherEarning:
    """F-4: what B4 may read (ledger D52)."""

    teacher_user_id: int
    currency: str
    count: int
    amount_minor: int
    share_minor: int
    margin_minor: int


def _window(since: date, until: date) -> tuple[ZoneInfo, datetime, datetime]:
    """Academy days [since, until], both included, as aware instants."""
    zone = ZoneInfo(common.academy_zone())
    first = datetime.combine(since, time.min, tzinfo=zone)
    after = datetime.combine(until + timedelta(days=1), time.min, tzinfo=zone)
    return zone, first, after


def _line(row: Request, zone: ZoneInfo) -> EarningLine:
    share_bp = row.teacher_share_bp or 0  # always set by complete (C-8)
    share = round_half_up(row.amount_minor * share_bp, BP)
    return EarningLine(
        request_id=row.pk,
        reference=row.reference,
        completed_on=row.completed_at.astimezone(zone).date(),
        product_id=row.product_id,
        product_name_ar=row.product.name_ar,
        product_name_en=row.product.name_en,
        teacher_user_id=row.teacher.user_id,
        teacher_name=row.teacher.user.full_name,
        name=row.name,
        currency=row.currency,
        amount_minor=row.amount_minor,
        fee_minor=row.fee_minor,
        share_bp=share_bp,
        share_minor=share,
        margin_minor=row.amount_minor - share,
        paid_method=row.paid_method,
        billing_method=row.billing_method,
    )


def earning_lines(
    *,
    since: date,
    until: date,
    teacher_user_id: int | None = None,
    product_id: int | None = None,
) -> Earnings:
    """F-2: completed requests with completed_at in [since, until] (academy
    dates) whose billing payment is still `completed`. The others in range
    are counted as excluded. Two queries at most: the requests, then their
    payments' statuses in one read."""
    zone, first, after = _window(since, until)
    rows = (
        Request.objects.select_related("product", "teacher__user")
        .filter(
            status=Request.Status.COMPLETED,
            completed_at__gte=first,
            completed_at__lt=after,
        )
        .order_by("completed_at", "pk")
    )
    if teacher_user_id:
        rows = rows.filter(teacher__user_id=teacher_user_id)
    if product_id:
        rows = rows.filter(product_id=product_id)
    rows = list(rows)
    payment_ids = [row.payment_id for row in rows if row.payment_id]
    statuses = {}
    if payment_ids:
        statuses = {
            p["id"]: p["status"]
            for p in billing_services.payments_queryset()
            .filter(id__in=payment_ids)
            .values("id", "status")
        }
    kept = [
        _line(row, zone)
        for row in rows
        if statuses.get(row.payment_id) == PAYMENT_COMPLETED
    ]
    return Earnings(kept, len(rows) - len(kept))


def group_by_teacher(lines: list[EarningLine]) -> list[MarginRow]:
    """F-3: one row per teacher and currency. The margin is the sum of the
    per-request margins, so rounding happens once per request."""
    sums: dict[tuple[int, str], list[int]] = {}
    names: dict[int, str] = {}
    for line in lines:
        names[line.teacher_user_id] = line.teacher_name
        total = sums.setdefault((line.teacher_user_id, line.currency), [0] * 5)
        total[0] += 1
        total[1] += line.amount_minor
        total[2] += line.fee_minor
        total[3] += line.share_minor
        total[4] += line.margin_minor
    rows = [
        MarginRow(teacher, names[teacher], currency, *values)
        for (teacher, currency), values in sums.items()
    ]
    return sorted(
        rows, key=lambda r: (r.teacher_name.casefold(), r.teacher_user_id, r.currency)
    )


def teacher_earnings(
    *, since: date, until: date, teacher_user_id: int | None = None
) -> list[TeacherEarning]:
    """F-4 (B7-11, D52): F-3's rows for B4, in a fixed number of queries."""
    lines = earning_lines(since=since, until=until, teacher_user_id=teacher_user_id)
    return [
        TeacherEarning(
            r.teacher_user_id,
            r.currency,
            r.count,
            r.amount_minor,
            r.share_minor,
            r.margin_minor,
        )
        for r in group_by_teacher(lines.lines)
    ]
```

In `backend/etqan/consultations/services/__init__.py`, add the imports, keeping the import block sorted:

```python
from etqan.consultations.services.earnings import EarningLine
from etqan.consultations.services.earnings import Earnings
from etqan.consultations.services.earnings import MarginRow
from etqan.consultations.services.earnings import TeacherEarning
from etqan.consultations.services.earnings import earning_lines
from etqan.consultations.services.earnings import group_by_teacher
from etqan.consultations.services.earnings import teacher_earnings
```

Then add `"EarningLine"`, `"Earnings"`, `"MarginRow"`, `"TeacherEarning"`, `"earning_lines"`, `"group_by_teacher"` and `"teacher_earnings"` to `__all__`, keeping it sorted (ruff's RUF022 order: classes in the upper-case block, functions in the lower-case block).

- [ ] **Step 5: Run the tests to see them pass**

Run: `B ruff format etqan/consultations && B ruff check etqan/consultations`, then `just test-backend`.
Expected: `etqan/consultations/tests/test_earnings.py` all PASS; nothing else red.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/consultations/services/earnings.py etqan/consultations/services/__init__.py \
  etqan/consultations/tests/conftest.py etqan/consultations/tests/test_earnings.py
git -C backend commit -m "feat(consultations): earnings lines and teacher_earnings (B7f F-2, F-4)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The margins report service: totals, estimate, date range (F-3)

**Files:**
- Modify: `backend/etqan/consultations/services/earnings.py`, `backend/etqan/consultations/services/__init__.py`
- Modify (claim): `backend/pyproject.toml`
- Test: `backend/etqan/consultations/tests/test_margins.py` (new)

**Interfaces:**
- Consumes: Task 1's `earning_lines`, `group_by_teacher`, `MarginRow`, `EarningLine`; `finance.services.convert_estimate(lines) -> Estimate | None` (`Estimate.currency`, `.amount_minor | None`, `.as_of`); `common.now()`, `common.academy_zone()`.
- Produces (re-exported from `etqan.consultations.services`):
  - `CurrencyTotal(currency, count, amount_minor, fee_minor, share_minor, margin_minor)`
  - `MarginEstimate(currency, amount_minor, fee_minor, share_minor, margin_minor, as_of: datetime | None)`
  - `MarginReport(since: date, until: date, rows: list[MarginRow], totals: list[CurrencyTotal], excluded: int, lines: list[EarningLine], estimate: MarginEstimate | None)`
  - `report_range(since: date | None, until: date | None) -> tuple[date, date]` (raises `ValidationError(field="to")`)
  - `margins_report(*, since: date | None = None, until: date | None = None, teacher_user_id: int | None = None, product_id: int | None = None) -> MarginReport`

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_margins.py`:

```python
"""Slice B7f F-3: the profit-margin report: per teacher and currency, never
summed across currencies, with an optional all-or-nothing estimate."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.consultations import services
from etqan.consultations.services import common
from etqan.consultations.tests.conftest import OCT_1
from etqan.consultations.tests.conftest import OCT_31
from etqan.consultations.tests.conftest import done
from etqan.finance import services as finance_services
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


def report(**kwargs):
    return services.margins_report(since=OCT_1, until=OCT_31, **kwargs)


def test_rows_per_teacher_and_currency_and_totals_per_currency(two):
    done(two, amount=1500, fee=75)
    done(two, amount=10000, currency="EGP")
    done(two, amount=2000, teacher=two.teacher2)
    done(two, paid=False)
    got = report()
    assert [
        (r.teacher_name, r.currency, r.count, r.amount_minor, r.fee_minor)
        + (r.share_minor, r.margin_minor)
        for r in got.rows
    ] == [
        ("Bilal", "EGP", 1, 10000, 0, 5000, 5000),
        ("Bilal", "USD", 1, 1500, 75, 750, 750),
        ("Maryam", "USD", 1, 2000, 0, 1000, 1000),
    ]
    assert got.totals == [
        services.CurrencyTotal("EGP", 1, 10000, 0, 5000, 5000),
        services.CurrencyTotal("USD", 2, 3500, 75, 1750, 1750),
    ]
    assert (got.excluded, len(got.lines), got.since, got.until) == (
        1,
        3,
        OCT_1,
        OCT_31,
    )


def test_the_teacher_and_product_filters(two):
    done(two)
    done(two, teacher=two.teacher2)
    assert [r.teacher_user_id for r in report(teacher_user_id=two.teacher2.pk).rows] == [
        two.teacher2.pk
    ]
    assert report(product_id=two.product.pk + 999).rows == []


def test_no_estimate_while_exchange_rates_is_off(two, set_features):
    set_features(exchange_rates=False)
    done(two)
    assert report().estimate is None


def test_the_estimate_converts_each_total_column(two, set_features):
    set_features(exchange_rates=True)
    academy_services.update_settings(default_currency="EGP")
    rate = finance_services.create_rate(currency="USD", rate="48.5", by=None)
    done(two, amount=1500, fee=75)  # USD
    done(two, amount=10000, currency="EGP")
    assert report().estimate == services.MarginEstimate(
        currency="EGP",
        amount_minor=10000 + 72750,
        fee_minor=3638,  # 75 x 48.5 = 3637.5, half up
        share_minor=5000 + 36375,
        margin_minor=5000 + 36375,
        as_of=rate.updated_at,
    )


def test_no_estimate_when_a_rate_is_missing(two, set_features):
    set_features(exchange_rates=True)
    academy_services.update_settings(default_currency="EGP")
    done(two)  # USD, with no USD rate
    assert report().estimate is None


def test_report_range_defaults_to_the_academy_month(monkeypatch):
    # 22:00 UTC on 31 Oct is 01:00 on 1 Nov in Riyadh.
    monkeypatch.setattr(common, "now", lambda: datetime(2026, 10, 31, 22, tzinfo=UTC))
    monkeypatch.setattr(common, "academy_zone", lambda: "Asia/Riyadh")
    assert services.report_range(None, None) == (date(2026, 11, 1), date(2026, 11, 30))
    assert services.report_range(date(2026, 11, 5), None) == (
        date(2026, 11, 5),
        date(2026, 11, 30),
    )
    monkeypatch.setattr(common, "now", lambda: datetime(2026, 2, 10, tzinfo=UTC))
    assert services.report_range(None, None) == (date(2026, 2, 1), date(2026, 2, 28))


def test_to_before_from_is_refused():
    with pytest.raises(ValidationError) as e:
        services.report_range(date(2026, 11, 5), date(2026, 11, 4))
    assert e.value.field == "to"


def test_margins_report_uses_the_default_range(two, monkeypatch):
    monkeypatch.setattr(common, "now", lambda: datetime(2026, 10, 20, tzinfo=UTC))
    done(two)
    got = services.margins_report()
    assert (got.since, got.until, len(got.rows)) == (OCT_1, OCT_31, 1)
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `just test-backend`
Expected: FAIL in `test_margins.py` with `AttributeError: module 'etqan.consultations.services' has no attribute 'margins_report'`.

- [ ] **Step 3: Allow `finance.services` in the consultations contract (claim)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/pyproject.toml --reason "B7f: consultations may import finance.services (convert_estimate)"
```

In `backend/pyproject.toml`, in the contract `"consultations reach other apps only through their services"` (in the `── phase B7 ──` block), add one line to `ignore_imports`, after the `scheduling.services` line:

```toml
    "etqan.consultations.** -> etqan.finance.services",
```

- [ ] **Step 4: Write the report service**

Append to `backend/etqan/consultations/services/earnings.py`. The imports go at the top of the module, merged with the existing ones:

```python
from etqan.finance import services as finance_services
from etqan.platform.exceptions import ValidationError

MONEY_FIELDS = ("amount_minor", "fee_minor", "share_minor", "margin_minor")


@dataclass(frozen=True)
class CurrencyTotal:
    currency: str
    count: int
    amount_minor: int
    fee_minor: int
    share_minor: int
    margin_minor: int


@dataclass(frozen=True)
class MarginEstimate:
    """F-3: every total column in the academy currency at current rates."""

    currency: str
    amount_minor: int
    fee_minor: int
    share_minor: int
    margin_minor: int
    as_of: datetime | None


@dataclass(frozen=True)
class MarginReport:
    since: date
    until: date
    rows: list[MarginRow]
    totals: list[CurrencyTotal]
    excluded: int
    lines: list[EarningLine]
    estimate: MarginEstimate | None


def _month_end(day: date) -> date:
    following = (day.replace(day=28) + timedelta(days=4)).replace(day=1)
    return following - timedelta(days=1)


def report_range(since: date | None, until: date | None) -> tuple[date, date]:
    """F-3: each missing end defaults to the current academy month's
    [assumed]; `to` before `from` is refused."""
    today = common.now().astimezone(ZoneInfo(common.academy_zone())).date()
    since = since or today.replace(day=1)
    until = until or _month_end(today)
    if until < since:
        raise ValidationError("Choose an end date on or after the start.", field="to")
    return since, until


def currency_totals(rows: list[MarginRow]) -> list[CurrencyTotal]:
    sums: dict[str, list[int]] = {}
    for row in rows:
        total = sums.setdefault(row.currency, [0] * 5)
        total[0] += row.count
        total[1] += row.amount_minor
        total[2] += row.fee_minor
        total[3] += row.share_minor
        total[4] += row.margin_minor
    return [CurrencyTotal(code, *values) for code, values in sorted(sums.items())]


def _estimate(totals: list[CurrencyTotal]) -> MarginEstimate | None:
    """One convert_estimate call per total column (D24, D31). All four or
    nothing: off (`exchange_rates`) or any missing rate gives None."""
    found = {}
    for field in MONEY_FIELDS:
        estimate = finance_services.convert_estimate(
            [{"currency": t.currency, "amount_minor": getattr(t, field)} for t in totals]
        )
        if estimate is None or estimate.amount_minor is None:
            return None
        found[field] = estimate
    stamps = [e.as_of for e in found.values() if e.as_of is not None]
    return MarginEstimate(
        currency=found["amount_minor"].currency,
        **{field: found[field].amount_minor for field in MONEY_FIELDS},
        as_of=min(stamps, default=None),
    )


def margins_report(
    *,
    since: date | None = None,
    until: date | None = None,
    teacher_user_id: int | None = None,
    product_id: int | None = None,
) -> MarginReport:
    """F-3: F-2's lines grouped by teacher and currency, the per-currency
    subtotals, the excluded count and the optional estimate."""
    since, until = report_range(since, until)
    earnings = earning_lines(
        since=since,
        until=until,
        teacher_user_id=teacher_user_id,
        product_id=product_id,
    )
    rows = group_by_teacher(earnings.lines)
    totals = currency_totals(rows)
    return MarginReport(
        since=since,
        until=until,
        rows=rows,
        totals=totals,
        excluded=earnings.excluded,
        lines=earnings.lines,
        estimate=_estimate(totals),
    )
```

In `services/__init__.py`, re-export `CurrencyTotal`, `MarginEstimate`, `MarginReport`, `margins_report` and `report_range` (imports and `__all__` both sorted).

- [ ] **Step 5: Run the tests and the boundaries**

Run: `B ruff format etqan/consultations && B ruff check etqan/consultations`, then `just check-boundaries` and `just test-backend`.
Expected: lint-imports clean (the consultations contract is KEPT); `test_margins.py` and `test_earnings.py` PASS.

- [ ] **Step 6: Commit, then release the claim**

```bash
git -C backend add pyproject.toml etqan/consultations/services/earnings.py \
  etqan/consultations/services/__init__.py etqan/consultations/tests/test_margins.py
git -C backend commit -m "feat(consultations): profit-margin report service (B7f F-3)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/pyproject.toml
```

---

### Task 3: The `export_margins` verb (F-5), under a one-commit claim

**Files:**
- Modify (claim): `backend/etqan/access/registry.py`, `backend/etqan/access/tests/test_registry.py`

**Interfaces:**
- Produces: `registry.EXPORT_MARGINS = ("export_margins", "export profit margins", "تصدير هوامش الربح")`; `VERB_LABELS["export_margins"]`; the `consultation_request` resource with `verbs=(*ALL_VERBS, "export_margins")`. `in_use` is **not** changed here: Task 4 adds `export_margins` to it with the route that declares it, so `test_every_code_in_the_table_is_in_the_registry_and_in_use` stays green at every commit.

- [ ] **Step 1: Claim the two shared paths**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/registry.py --reason "B7f F-5: EXPORT_MARGINS in VERB_LABELS (outside the phase markers)"
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/tests/test_registry.py --reason "B7f F-5: verb assertions"
```

- [ ] **Step 2: Write the failing tests**

In `backend/etqan/access/tests/test_registry.py`:

In `test_resources_carry_the_12_verbs_and_the_role_resource_6`, replace

```python
    assert by_code["session"].verbs == (*registry.ALL_VERBS, "supervise")
    for code, resource in by_code.items():
        if code not in ("role", "session"):
            assert resource.verbs == registry.ALL_VERBS, code
```

with

```python
    assert by_code["session"].verbs == (*registry.ALL_VERBS, "supervise")
    # Slice B7f F-5: the profit-margin report's own verb.
    assert by_code["consultation_request"].verbs == (
        *registry.ALL_VERBS,
        "export_margins",
    )
    for code, resource in by_code.items():
        if code not in ("role", "session", "consultation_request"):
            assert resource.verbs == registry.ALL_VERBS, code
```

In `test_the_payload_lists_verbs_resources_pages_and_widgets`, replace `assert body["verbs"][-1]["code"] == "supervise"` with:

```python
    assert [v["code"] for v in body["verbs"][-2:]] == ["supervise", "export_margins"]
```

Append:

```python
def test_export_margins_has_its_labels():
    """Slice B7f F-5: a clerk may list requests without the money split."""
    assert registry.VERB_LABELS["export_margins"] == (
        "export profit margins",
        "تصدير هوامش الربح",
    )
    assert "consultation_request.export_margins" in registry.CODES
```

- [ ] **Step 3: Run to see them fail**

Run: `just test-backend`
Expected: FAIL in `access/tests/test_registry.py` with `KeyError: 'export_margins'` and the verbs assertion.

- [ ] **Step 4: Add the verb**

In `backend/etqan/access/registry.py`, after `SUPERVISE = (...)`:

```python
# Slice B7f F-5: the consultation profit-margin report (CONS-002).
EXPORT_MARGINS = ("export_margins", "export profit margins", "تصدير هوامش الربح")
```

Change the `VERB_LABELS` line to:

```python
VERB_LABELS = {
    code: (en, ar) for code, en, ar in (*VERBS, SUPERVISE, EXPORT_MARGINS)
}
```

Under `# ── phase B7 ──`, the `consultation_request` resource becomes:

```python
    Resource(
        "consultation_request",
        "Consultation requests",
        "طلبات الاستشارات",
        ("view", "view_any", "create", "update", "delete"),
        verbs=(*ALL_VERBS, EXPORT_MARGINS[0]),
    ),
```

- [ ] **Step 5: Run the tests**

Run: `B ruff format etqan/access && B ruff check etqan/access`, then `just test-backend`.
Expected: `test_registry.py` PASS; `test_routes.py` still PASS (`in_use` unchanged).

- [ ] **Step 6: Commit (one commit), then release both claims**

```bash
git -C backend add etqan/access/registry.py etqan/access/tests/test_registry.py
git -C backend commit -m "feat(access): consultation_request.export_margins verb (B7f F-5)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/registry.py
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/tests/test_registry.py
```

---

### Task 4: `reports/margins/`: JSON, summary CSV and detail CSV (F-3, F-5, §3)

**Files:**
- Create: `backend/etqan/consultations/api/report_payloads.py`, `backend/etqan/consultations/api/report_views.py`
- Modify: `backend/etqan/consultations/api/urls.py`, `backend/etqan/access/registry.py` (B7 marker: `in_use`)
- Modify (claim): `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/consultations/tests/test_api_margins.py` (new)

**Interfaces:**
- Consumes: Task 2's `services.margins_report(...) -> MarginReport`; `etqan.platform.csv.CSVExportMixin`; `HasCode`, `FeatureOn`, `role_of`, `codes_of`; `as_int`.
- Produces:
  - `GET /api/v1/consultations/reports/margins/?from=&to=&teacher=&product=[&format=csv][&detail=1]`. The JSON is `{"from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "rows": [{"teacher": {"id", "full_name"}, "currency", "count", "amount_minor", "fee_minor", "share_minor", "margin_minor"}], "totals": [{"currency", "count", "amount_minor", "fee_minor", "share_minor", "margin_minor"}], "excluded": int, "estimate": null | {"currency", "amount_minor", "fee_minor", "share_minor", "margin_minor", "as_of": iso | null}}`.
  - `report_payloads.margins_data(report) -> dict`, `report_payloads.margin_csv_rows(report) -> list[dict]`, `report_payloads.margin_detail_rows(report) -> list[dict]`, `SUMMARY_COLUMNS`, `DETAIL_COLUMNS`.

- [ ] **Step 1: Write the failing API tests**

`backend/etqan/consultations/tests/test_api_margins.py`:

```python
"""Slice B7f F-3, F-5, §3: the profit-margin report over HTTP."""

import csv
import io

import pytest

from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import done

pytestmark = pytest.mark.django_db
M = "/api/v1/consultations/reports/margins/"
RANGE = {"from": "2026-10-01", "to": "2026-10-31"}
BOTH = ("consultation_request.view_any", "consultation_request.export_margins")


def table(resp):
    return list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))


@pytest.fixture
def admin(two, api_for):
    return api_for("admin")


def test_the_report_as_json(admin, two):
    done(two, amount=1500, fee=75)
    done(two, paid=False)
    resp = admin.get(M, RANGE)
    assert resp.status_code == 200, resp.content
    body = resp.json()
    money = {
        "currency": "USD",
        "count": 1,
        "amount_minor": 1500,
        "fee_minor": 75,
        "share_minor": 750,
        "margin_minor": 750,
    }
    assert (body["from"], body["to"]) == ("2026-10-01", "2026-10-31")
    assert body["rows"] == [
        {"teacher": {"id": two.teacher.pk, "full_name": "Bilal"}, **money}
    ]
    assert body["totals"] == [money]
    assert (body["excluded"], body["estimate"]) == (1, None)


def test_filters_and_bad_dates(admin, two):
    done(two)
    assert admin.get(M, {**RANGE, "teacher": two.teacher2.pk}).json()["rows"] == []
    assert admin.get(M, {**RANGE, "product": two.product.pk}).json()["totals"]
    resp = admin.get(M, {"from": "soon"})
    assert (resp.status_code, list(resp.json())) == (400, ["from"])
    resp = admin.get(M, {"from": "2026-10-05", "to": "2026-10-04"})
    assert (resp.status_code, list(resp.json())) == (400, ["to"])


def test_the_summary_csv(admin, two):
    done(two, amount=1500, fee=75)
    resp = admin.get(M, {**RANGE, "format": "csv"})
    assert resp.status_code == 200
    assert resp["Content-Disposition"] == 'attachment; filename="consultation-margins.csv"'
    assert table(resp) == [
        [
            "Teacher",
            "Currency",
            "Completed",
            "Amount (minor units)",
            "Fee (minor units)",
            "Teacher share (minor units)",
            "Margin before fees (minor units)",
        ],
        ["Bilal", "USD", "1", "1500", "75", "750", "750"],
    ]


def test_the_detail_csv_has_its_own_columns(admin, two):
    row = done(two, amount=1500, fee=75)
    Request.objects.filter(pk=row.pk).update(name="=HYPERLINK(1)")
    resp = admin.get(M, {**RANGE, "format": "csv", "detail": "1"})
    assert (
        resp["Content-Disposition"]
        == 'attachment; filename="consultation-margins-detail.csv"'
    )
    header, line = table(resp)
    assert header == [
        "Reference",
        "Completed on",
        "Product",
        "Teacher",
        "Person",
        "Currency",
        "Amount (minor units)",
        "Fee (minor units)",
        "Teacher share (basis points)",
        "Teacher share (minor units)",
        "Margin before fees (minor units)",
        "Paid method",
        "Billing method",
    ]
    assert line == [
        row.reference,
        "2026-10-15",
        "Placement",
        "Bilal",
        "'=HYPERLINK(1)",
        "USD",
        "1500",
        "75",
        "5000",
        "750",
        "750",
        "manual",
        "cash",
    ]


def test_csv_is_404_while_export_is_off(admin, two, set_features):
    set_features(export=False)
    assert admin.get(M, {"format": "csv"}).status_code == 404
    assert admin.get(M).status_code == 200  # the screen still works
    # The requests list's own 404 is pinned in Task 5's test file.


def test_margins_need_export_margins_and_view_any(two, staff_for):
    assert staff_for("consultation_request.view_any").get(M).status_code == 403
    only = staff_for("consultation_request.export_margins").get(M)
    assert only.status_code == 403
    assert "consultation_request.view_any" in str(only.json())
    assert staff_for(*BOTH).get(M).status_code == 200


def test_teachers_students_and_parents_get_403(two, api_for):
    for role in ("teacher", "student", "parent"):
        assert api_for(role).get(M).status_code == 403, role


def test_the_switch_off_gives_404(admin, set_features):
    set_features(consultations=False)
    assert admin.get(M).status_code == 404
```

- [ ] **Step 2: Run to see them fail**

Run: `just test-backend`
Expected: FAIL in `test_api_margins.py`, all with 404 (no route).

- [ ] **Step 3: Write the payloads**

`backend/etqan/consultations/api/report_payloads.py`:

```python
"""Slice B7f: the report answers and CSV rows. Every CSV cell goes through
etqan.platform.csv.safe_cell in the renderer."""

from dataclasses import asdict

SUMMARY_COLUMNS = (
    ("teacher", "Teacher"),
    ("currency", "Currency"),
    ("count", "Completed"),
    ("amount_minor", "Amount (minor units)"),
    ("fee_minor", "Fee (minor units)"),
    ("share_minor", "Teacher share (minor units)"),
    ("margin_minor", "Margin before fees (minor units)"),
)
DETAIL_COLUMNS = (
    ("reference", "Reference"),
    ("completed_on", "Completed on"),
    ("product", "Product"),
    ("teacher", "Teacher"),
    ("name", "Person"),
    ("currency", "Currency"),
    ("amount_minor", "Amount (minor units)"),
    ("fee_minor", "Fee (minor units)"),
    ("share_bp", "Teacher share (basis points)"),
    ("share_minor", "Teacher share (minor units)"),
    ("margin_minor", "Margin before fees (minor units)"),
    ("paid_method", "Paid method"),
    ("billing_method", "Billing method"),
)
MONEY = ("count", "amount_minor", "fee_minor", "share_minor", "margin_minor")


def _money(row) -> dict:
    return {key: getattr(row, key) for key in MONEY}


def margins_data(report) -> dict:
    """F-3's screen: rows, per-currency totals, excluded, estimate."""
    estimate = None
    if report.estimate is not None:
        estimate = asdict(report.estimate)
        as_of = report.estimate.as_of
        estimate["as_of"] = as_of.isoformat() if as_of else None
    return {
        "from": report.since.isoformat(),
        "to": report.until.isoformat(),
        "rows": [
            {
                "teacher": {"id": r.teacher_user_id, "full_name": r.teacher_name},
                "currency": r.currency,
                **_money(r),
            }
            for r in report.rows
        ],
        "totals": [{"currency": t.currency, **_money(t)} for t in report.totals],
        "excluded": report.excluded,
        "estimate": estimate,
    }


def margin_csv_rows(report) -> list[dict]:
    """One row per teacher and currency; no totals ([assumed])."""
    return [
        {"teacher": r.teacher_name, "currency": r.currency, **_money(r)}
        for r in report.rows
    ]


def margin_detail_rows(report) -> list[dict]:
    """`?detail=1`: one row per request ([assumed] product in English)."""
    return [
        {
            "reference": line.reference,
            "completed_on": line.completed_on.isoformat(),
            "product": line.product_name_en,
            "teacher": line.teacher_name,
            "name": line.name,
            "currency": line.currency,
            "amount_minor": line.amount_minor,
            "fee_minor": line.fee_minor,
            "share_bp": line.share_bp,
            "share_minor": line.share_minor,
            "margin_minor": line.margin_minor,
            "paid_method": line.paid_method,
            "billing_method": line.billing_method,
        }
        for line in report.lines
    ]
```

- [ ] **Step 4: Write the view and the route**

`backend/etqan/consultations/api/report_views.py`:

```python
"""Slice B7f F-3, F-5: the teacher profit-margin report and its CSVs."""

from datetime import date

from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.consultations import services
from etqan.consultations.api import report_payloads as payloads
from etqan.platform.csv import CSVExportMixin
from etqan.platform.exceptions import ForbiddenError
from etqan.platform.exceptions import ValidationError
from etqan.platform.params import as_int
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import role_of

VIEW_ANY = "consultation_request.view_any"


def _date(value, field) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise ValidationError("Use a date like 2026-10-12.", field=field) from None


class MarginsView(CSVExportMixin, APIView):
    """F-3. The route declares export_margins; F-5 says both reports need
    view_any too, which the view checks itself ([assumed], as B7c's
    payment.create)."""

    feature = "consultations"
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "consultation_request.export_margins"}

    def _detail(self) -> bool:
        return self.request.query_params.get("detail") == "1"

    @property
    def csv_columns(self):
        return payloads.DETAIL_COLUMNS if self._detail() else payloads.SUMMARY_COLUMNS

    @property
    def csv_filename(self):
        return (
            "consultation-margins-detail" if self._detail() else "consultation-margins"
        )

    def get(self, request):
        if role_of(request.user) != "admin" and VIEW_ANY not in codes_of(request.user):
            raise ForbiddenError(
                f"The margins report also needs the {VIEW_ANY} permission.",
                field="consultation_request",
            )
        p = request.query_params
        report = services.margins_report(
            since=_date(p.get("from"), "from"),
            until=_date(p.get("to"), "to"),
            teacher_user_id=as_int(p.get("teacher", "")),
            product_id=as_int(p.get("product", "")),
        )
        if self.wants_csv():
            rows = (
                payloads.margin_detail_rows(report)
                if self._detail()
                else payloads.margin_csv_rows(report)
            )
            return self.csv_response(rows)
        return Response(payloads.margins_data(report))
```

In `backend/etqan/consultations/api/urls.py`, add the import `from etqan.consultations.api import report_views` (sorted with the others) and append to `urlpatterns`:

```python
    path("reports/margins/", report_views.MarginsView.as_view()),
```

In `backend/etqan/access/registry.py` (inside `── phase B7 ──`, no claim needed: inside the marker), the `consultation_request` resource's `in_use` becomes:

```python
        ("view", "view_any", "create", "update", "delete", EXPORT_MARGINS[0]),
```

- [ ] **Step 5: Add the route to the access tables (claim)**

```bash
python3 scripts/orchestration/ledger.py claim B7 backend/etqan/access/tests/test_routes.py --reason "B7f: reports/margins/ in ROUTES, NEEDS_ALL_CODES, FEATURES"
```

In `backend/etqan/access/tests/test_routes.py`:

- In `ROUTES`, after the B7c line `("GET", "/api/v1/consultations/schedule/", "consultation_schedule.view_any"),`:

```python
    # Phase B7, slice B7f
    (
        "GET",
        "/api/v1/consultations/reports/margins/",
        "consultation_request.export_margins",
    ),
```

- In `NEEDS_ALL_CODES`, add:

```python
    # Slice B7f F-5: the margins report also needs the list's view_any.
    ("GET", "/api/v1/consultations/reports/margins/"): (
        "consultation_request.export_margins",
        "consultation_request.view_any",
    ),
```

- In `FEATURES`, in the `# Phase B7, slice B7c` `"consultations"` tuple, after `("GET", "/api/v1/consultations/schedule/"),`, add:

```python
            ("GET", "/api/v1/consultations/reports/margins/"),  # B7f
```

- [ ] **Step 6: Run the tests**

Run: `B ruff format etqan/consultations etqan/access && B ruff check etqan/consultations etqan/access`, then `just test-backend`.
Expected: `test_api_margins.py` all PASS. Every `access/tests/test_routes.py` test PASSES, including `test_every_code_in_the_table_is_in_the_registry_and_in_use` and `test_staff_pass_with_the_code_and_get_403_without_it[GET-/api/v1/consultations/reports/margins/-…]`.

- [ ] **Step 7: Commit, then release the claim**

```bash
git -C backend add etqan/consultations/api/report_payloads.py etqan/consultations/api/report_views.py \
  etqan/consultations/api/urls.py etqan/consultations/tests/test_api_margins.py \
  etqan/access/registry.py etqan/access/tests/test_routes.py
git -C backend commit -m "feat(consultations): profit-margin report route and CSVs (B7f F-3, F-5)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 backend/etqan/access/tests/test_routes.py
```

---

### Task 5: The requests CSV, office only (F-1)

**B7d dependency:** the `self_booked` column reads B7d's `Request.self_booked`. `_list_filters` carries B7d's `self_booked=FLAGS.get(...)` and inherits its default hiding of `cancel_reason="unpaid"` rows. Nothing else in this task needs B7d.

**Files:**
- Modify: `backend/etqan/consultations/api/request_views.py`, `backend/etqan/consultations/api/report_payloads.py`
- Test: `backend/etqan/consultations/tests/test_api_requests_csv.py` (new)

**Interfaces:**
- Consumes: B7c `RequestListView`, `services.filter_requests`, `_scoped`, `_is_teacher`, `_day`, `_zone`; B7d `FLAGS`; `CSVExportMixin`, `HasCode`.
- Produces: `GET /api/v1/consultations/requests/?format=csv&<list filters>` (`consultation-requests.csv`); `report_payloads.REQUEST_COLUMNS`; `report_payloads.request_csv_row(row, zone) -> dict`; `request_views._list_filters(request) -> dict`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/consultations/tests/test_api_requests_csv.py`:

```python
"""Slice B7f F-1: the consultation requests CSV, office only."""

import csv
import io

import pytest
from rest_framework.test import APIClient

from etqan.consultations import services
from etqan.consultations.models import Request
from etqan.consultations.tests.conftest import MONDAY_4PM
from etqan.consultations.tests.conftest import new_request

pytestmark = pytest.mark.django_db
R = "/api/v1/consultations/requests/"
HEADER = [
    "Reference",
    "Created at (academy time)",
    "Product",
    "Teacher",
    "Person",
    "Email",
    "WhatsApp",
    "Timezone",
    "Start (academy time)",
    "Start (person's time)",
    "Delivery",
    "Request status",
    "Session status",
    "Student attendance",
    "Teacher attendance",
    "Paid method",
    "Billing method",
    "Amount (minor units)",
    "Fee (minor units)",
    "Currency",
    "Transaction number",
    "Paid on",
    "Self-booked",
]


def table(resp):
    return list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))


@pytest.fixture
def admin(booking, api_for):
    return api_for("admin")


def test_columns_and_a_paid_row(admin, booking):
    row = new_request(booking)  # Yusuf, Africa/Cairo, Mon 12 Oct 16:00 UTC
    row = services.record_payment(
        row, billing_method="cash", by=booking.admin, transaction_number="T-9"
    )
    Request.objects.filter(pk=row.pk).update(self_booked=True)  # B7d's column
    resp = admin.get(R, {"format": "csv"})
    assert resp.status_code == 200
    assert resp["Content-Disposition"] == 'attachment; filename="consultation-requests.csv"'
    header, line = table(resp)
    assert header == HEADER
    got = dict(zip(header, line, strict=True))
    assert got["Reference"] == row.reference
    assert (got["Product"], got["Teacher"], got["Person"]) == (
        "Placement",
        "Bilal",
        "Yusuf Omar",
    )
    assert (got["Email"], got["WhatsApp"], got["Timezone"]) == (
        "yusuf@x.test",
        "+201000000001",  # an integer-looking phone is left alone
        "Africa/Cairo",
    )
    # The academy zone is UTC in tests; Cairo is UTC+3 on 12 Oct 2026.
    assert (got["Start (academy time)"], got["Start (person's time)"]) == (
        "2026-10-12 16:00",
        "2026-10-12 19:00",
    )
    assert (got["Delivery"], got["Request status"], got["Session status"]) == (
        "video_call",
        "pending_review",
        "scheduled",
    )
    assert (got["Student attendance"], got["Teacher attendance"]) == (
        "not_set",
        "not_set",
    )
    assert (got["Paid method"], got["Billing method"]) == ("manual", "cash")
    assert (got["Amount (minor units)"], got["Fee (minor units)"]) == ("1500", "0")
    assert (got["Currency"], got["Transaction number"]) == ("USD", "T-9")
    assert got["Paid on"] == row.paid_on.isoformat()
    assert got["Self-booked"] == "yes"


def test_an_unpaid_row_without_a_start(admin, booking):
    new_request(booking, starts_at=None)
    got = dict(zip(*table(admin.get(R, {"format": "csv"})), strict=True))
    assert (got["Start (academy time)"], got["Start (person's time)"]) == ("", "")
    assert (got["Paid method"], got["Amount (minor units)"], got["Paid on"]) == (
        "",
        "0",
        "",
    )
    assert got["Self-booked"] == "no"


def test_formula_cells_are_defused(admin, booking):
    row = new_request(booking, name="=HYPERLINK(1)")
    Request.objects.filter(pk=row.pk).update(transaction_number="@SUM(1)")
    got = dict(zip(*table(admin.get(R, {"format": "csv"})), strict=True))
    assert (got["Person"], got["Transaction number"]) == ("'=HYPERLINK(1)", "'@SUM(1)")


def test_the_csv_follows_the_list_filters_and_is_not_paged(admin, booking):
    kept = new_request(booking, starts_at=None)
    services.confirm(new_request(booking, starts_at=MONDAY_4PM), by=booking.admin)
    for _ in range(30):
        new_request(booking, starts_at=None)
    rows = table(admin.get(R, {"format": "csv", "status": "pending_review"}))[1:]
    assert len(rows) == 31
    assert kept.reference in {r[0] for r in rows}
    assert table(admin.get(R, {"format": "csv", "status": "confirmed"}))[1][11] == (
        "confirmed"
    )


def test_a_teacher_reads_the_list_but_gets_403_for_the_csv(booking):
    new_request(booking)
    teacher = APIClient()
    teacher.force_login(booking.teacher)
    assert teacher.get(R).status_code == 200
    resp = teacher.get(R, {"format": "csv", "from": "not-a-date"})
    assert resp.status_code == 403  # refused before the filters are read
    assert resp["Content-Type"].startswith("application/json")


def test_staff_need_view_any_for_the_csv(booking, staff_for):
    assert staff_for("consultation_request.view").get(R, {"format": "csv"}).status_code == 403
    assert (
        staff_for("consultation_request.view_any").get(R, {"format": "csv"}).status_code
        == 200
    )


def test_csv_is_404_while_export_is_off(admin, set_features):
    set_features(export=False)
    assert admin.get(R, {"format": "csv"}).status_code == 404
    assert admin.get(R).status_code == 200
```

Note: `new_request(booking)` with the default `starts_at=MONDAY_4PM` fills one of the product's two places. `test_the_csv_follows_the_list_filters_and_is_not_paged` therefore books only one timed request and leaves the rest without a start.

- [ ] **Step 2: Run to see them fail**

Run: `just test-backend`
Expected: FAIL in `test_api_requests_csv.py`. Most fail with 404, because DRF has no `csv` renderer on this view yet.

- [ ] **Step 3: Add the CSV row**

Append to `backend/etqan/consultations/api/report_payloads.py`. Add `from zoneinfo import ZoneInfo` to the imports at the top:

```python
# F-1 ([assumed] column order and labels; EXP-002 columns are UNKNOWN).
REQUEST_COLUMNS = (
    ("reference", "Reference"),
    ("created_at", "Created at (academy time)"),
    ("product", "Product"),
    ("teacher", "Teacher"),
    ("name", "Person"),
    ("email", "Email"),
    ("whatsapp", "WhatsApp"),
    ("timezone", "Timezone"),
    ("starts_academy", "Start (academy time)"),
    ("starts_person", "Start (person's time)"),
    ("delivery_mode", "Delivery"),
    ("status", "Request status"),
    ("session_status", "Session status"),
    ("student_attendance", "Student attendance"),
    ("teacher_attendance", "Teacher attendance"),
    ("paid_method", "Paid method"),
    ("billing_method", "Billing method"),
    ("amount_minor", "Amount (minor units)"),
    ("fee_minor", "Fee (minor units)"),
    ("currency", "Currency"),
    ("transaction_number", "Transaction number"),
    ("paid_on", "Paid on"),
    ("self_booked", "Self-booked"),
)
STAMP = "%Y-%m-%d %H:%M"


def _local(at, zone: ZoneInfo) -> str:
    return at.astimezone(zone).strftime(STAMP) if at else ""


def request_csv_row(row, zone: ZoneInfo) -> dict:
    """F-1: one office row. `zone` is the academy's, read once per answer."""
    return {
        "reference": row.reference,
        "created_at": _local(row.created_at, zone),
        "product": row.product.name_en,
        "teacher": row.teacher.user.full_name,
        "name": row.name,
        "email": row.email,
        "whatsapp": row.whatsapp,
        "timezone": row.timezone,
        "starts_academy": _local(row.starts_at, zone),
        "starts_person": _local(row.starts_at, ZoneInfo(row.timezone)),
        "delivery_mode": row.product.delivery_mode,
        "status": row.status,
        "session_status": row.session_status,
        "student_attendance": row.student_attendance,
        "teacher_attendance": row.teacher_attendance,
        "paid_method": row.paid_method,
        "billing_method": row.billing_method,
        "amount_minor": row.amount_minor,
        "fee_minor": row.fee_minor,
        "currency": row.currency,
        "transaction_number": row.transaction_number,
        "paid_on": row.paid_on.isoformat() if row.paid_on else "",
        "self_booked": row.self_booked,  # B7d's column
    }
```

- [ ] **Step 4: Make the list view answer CSV**

In `backend/etqan/consultations/api/request_views.py`:

- add the imports `from etqan.consultations.api import report_payloads` and `from etqan.platform.csv import CSVExportMixin` (sorted);
- add, after `_changes`, a function holding **exactly** the keyword arguments `RequestListView.get` passes to `services.filter_requests` after B7d. Keep B7d's `self_booked` line as B7d wrote it:

```python
def _list_filters(request) -> dict:
    """§4 (CONS-002) filters, shared by the page and the CSV. C-12: a
    teacher sees no payment, so cannot filter by one either."""
    p = request.query_params
    office = not _is_teacher(request.user)
    return {
        "product": as_int(p.get("product", "")),
        "teacher": as_int(p.get("teacher", "")),
        "session_status": p.get("session_status", ""),
        "student_attendance": p.get("student_attendance", ""),
        "teacher_attendance": p.get("teacher_attendance", ""),
        "paid_method": p.get("paid_method", "") if office else "",
        "billing_method": p.get("billing_method", "") if office else "",
        "status": p.get("status", ""),
        "self_booked": FLAGS.get(p.get("self_booked", "")),  # B7d
        "date_from": _day(p.get("from"), "from"),
        "date_to": _day(p.get("to"), "to"),
    }
```

- `RequestListView` becomes `class RequestListView(CSVExportMixin, APIView):` and gains:

```python
    csv_columns = report_payloads.REQUEST_COLUMNS
    csv_filename = "consultation-requests"
```

- its `get` becomes:

```python
    def get(self, request):
        # F-1: the CSV is the office's (HasCode). A teacher, who may read the
        # list, is refused before the filters are read, so the payment
        # fields and emails never leave through it. Raised, not returned:
        # CSVExportMixin answers the error as JSON.
        if self.wants_csv() and not HasCode().has_permission(request, self):
            raise ForbiddenError(
                "The CSV export is for the office only.", field="format"
            )
        qs = services.filter_requests(_scoped(request), **_list_filters(request))
        zone = _zone()
        if self.wants_csv():
            return self.csv_response(
                [report_payloads.request_csv_row(r, zone) for r in qs]
            )
        paginator = StandardPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([_data(request, r, zone) for r in page])
```

(`HasCode` and `ForbiddenError` are already imported in this module.)

- [ ] **Step 5: Run the tests**

Run: `B ruff format etqan/consultations && B ruff check etqan/consultations`, then `just test-backend`.
Expected: `test_api_requests_csv.py` PASS, and every B7c/B7d list test (`test_api_requests.py`, `test_office_self_booked.py`) still PASS.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/consultations/api/request_views.py etqan/consultations/api/report_payloads.py \
  etqan/consultations/tests/test_api_requests_csv.py
git -C backend commit -m "feat(consultations): office-only requests CSV (B7f F-1)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Dashboard data layer and the requests Export button

**B7d dependency:** `RequestFilters.self_booked?: boolean` (plan 60). `csv.ts` turns booleans into `"true"`/`"false"`.

**Files:**
- Create: `dashboard/src/features/consultations/csv.ts`, `dashboard/src/features/consultations/csv.test.ts`
- Modify: `dashboard/src/features/consultations/schemas.ts`, `api.ts`, `api.test.ts`, `queries.ts`, `fixtures.ts`, `RequestsAdmin.tsx`, `RequestsAdmin.test.tsx`

**Interfaces:**
- Consumes: `csvUrl(path, params)` from `@/lib/api`; `ExportButton` from `@/components/ExportButton`.
- Produces:
  - types `MarginFilters { from?: string; to?: string; teacher?: number; product?: number }`, `MarginMoney { currency; count; amount_minor; fee_minor; share_minor; margin_minor }`, `MarginRow extends MarginMoney { teacher: { id: number; full_name: string } }`, `MarginEstimate { currency; amount_minor; fee_minor; share_minor; margin_minor; as_of: string | null }`, `MarginsAnswer { from; to; rows: MarginRow[]; totals: MarginMoney[]; excluded: number; estimate: MarginEstimate | null }`;
  - `consultationsApi.margins(f: MarginFilters): Promise<MarginsAnswer>`;
  - `requestsCsvUrl(f: RequestFilters): string`, `marginsCsvUrl(f: MarginFilters, detail?: boolean): string` (in `csv.ts`, kept out of `api.ts` because the component tests mock `./api` whole);
  - `useMargins(f: MarginFilters)`;
  - fixture `marginsReport: MarginsAnswer`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/consultations/csv.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { marginsCsvUrl, requestsCsvUrl } from "./csv";

describe("CSV links", () => {
	it("carries the list's filters, never the page", () => {
		const url = requestsCsvUrl({
			page: 3,
			status: "completed",
			teacher: 8,
			self_booked: true,
		});
		expect(url).toMatch(/consultations\/requests\/\?/);
		expect(url).toContain("status=completed");
		expect(url).toContain("teacher=8");
		expect(url).toContain("self_booked=true");
		expect(url).toContain("format=csv");
		expect(url).not.toContain("page=");
	});

	it("asks for the detail only when told to", () => {
		const f = { from: "2026-10-01", product: 3 };
		expect(marginsCsvUrl(f)).toMatch(/consultations\/reports\/margins\/\?/);
		expect(marginsCsvUrl(f)).toContain("from=2026-10-01");
		expect(marginsCsvUrl(f)).not.toContain("detail");
		expect(marginsCsvUrl(f, true)).toContain("detail=1");
	});
});
```

Add to `dashboard/src/features/consultations/api.test.ts`, inside `describe("consultationsApi", …)`. The file already mocks `@/lib/api`, and its `beforeEach` resolves `api.get`:

```ts
	it("reads the margins report with only the set filters", async () => {
		await consultationsApi.margins({ from: "2026-10-01", teacher: undefined });
		expect(api.get).toHaveBeenCalledWith("consultations/reports/margins/", {
			params: { from: "2026-10-01" },
		});
	});
```

Add to `RequestsAdmin.test.tsx` inside `describe("RequestsAdmin", …)`:

```tsx
	it("links the CSV of the filtered list", async () => {
		const user = userEvent.setup();
		show("consultation_request.view_any");
		await screen.findByText("CR-000005");
		await user.selectOptions(screen.getByLabelText("Status"), "completed");
		const href =
			screen.getByRole("link", { name: "Export CSV" }).getAttribute("href") ??
			"";
		expect(href).toContain("consultations/requests/?");
		expect(href).toContain("status=completed");
		expect(href).toContain("format=csv");
	});
```

- [ ] **Step 2: Run to see them fail**

Run: `F pnpm vitest run src/features/consultations/csv.test.ts src/features/consultations/api.test.ts src/features/consultations/RequestsAdmin.test.tsx`
Expected: FAIL (`Failed to resolve import "./csv"`, `margins is not a function`, no "Export CSV" link).

- [ ] **Step 3: Implement**

In `schemas.ts`, append:

```ts
/** B7f F-3: the profit-margin report's filters (academy dates). */
export interface MarginFilters {
	from?: string;
	to?: string;
	teacher?: number;
	product?: number;
}

export interface MarginMoney {
	currency: string;
	count: number;
	amount_minor: number;
	fee_minor: number;
	share_minor: number;
	margin_minor: number;
}

export interface MarginRow extends MarginMoney {
	teacher: { id: number; full_name: string };
}

/** Every total column in the academy currency; null unless all four exist. */
export interface MarginEstimate {
	currency: string;
	amount_minor: number;
	fee_minor: number;
	share_minor: number;
	margin_minor: number;
	as_of: string | null;
}

export interface MarginsAnswer {
	from: string;
	to: string;
	rows: MarginRow[];
	totals: MarginMoney[];
	excluded: number;
	estimate: MarginEstimate | null;
}
```

In `api.ts`, add `MarginFilters` and `MarginsAnswer` to the type import, and add to `consultationsApi`:

```ts
	margins: async (f: MarginFilters) =>
		(
			await api.get<MarginsAnswer>(`${B}reports/margins/`, {
				params: given(f),
			})
		).data,
```

`dashboard/src/features/consultations/csv.ts`:

```ts
import { csvUrl } from "@/lib/api";
import type { MarginFilters, RequestFilters } from "./schemas";

type Params = Record<string, string | number | boolean | undefined>;

/** Booleans as "true"/"false"; csvUrl drops empty values and the page. */
function text(params: Params): Record<string, string | number | undefined> {
	return Object.fromEntries(
		Object.entries(params).map(
			([key, value]): [string, string | number | undefined] => [
				key,
				typeof value === "boolean" ? String(value) : value,
			],
		),
	);
}

/** B7f F-1: the office's requests CSV, with the list's filters. */
export const requestsCsvUrl = (f: RequestFilters): string =>
	csvUrl("consultations/requests/", text({ ...f }));

/** B7f F-3: the margins CSV, one row per teacher and currency, or one per
 * request with `detail`. */
export const marginsCsvUrl = (f: MarginFilters, detail = false): string =>
	csvUrl(
		"consultations/reports/margins/",
		text(detail ? { ...f, detail: 1 } : { ...f }),
	);
```

In `queries.ts`, add `MarginFilters` to the schema type import and:

```ts
export const useMargins = (f: MarginFilters) =>
	useQuery({
		queryKey: [...consultationsKey, "margins", f],
		queryFn: () => consultationsApi.margins(f),
		placeholderData: keepPreviousData,
	});
```

In `fixtures.ts`, add `MarginsAnswer` to the type import and append:

```ts
export const marginsReport: MarginsAnswer = {
	from: "2026-10-01",
	to: "2026-10-31",
	rows: [
		{
			teacher: { id: 8, full_name: "Ustadh Bilal" },
			currency: "EGP",
			count: 1,
			amount_minor: 50000,
			fee_minor: 0,
			share_minor: 20000,
			margin_minor: 30000,
		},
		{
			teacher: { id: 8, full_name: "Ustadh Bilal" },
			currency: "USD",
			count: 2,
			amount_minor: 3000,
			fee_minor: 75,
			share_minor: 1500,
			margin_minor: 1500,
		},
	],
	totals: [
		{
			currency: "EGP",
			count: 1,
			amount_minor: 50000,
			fee_minor: 0,
			share_minor: 20000,
			margin_minor: 30000,
		},
		{
			currency: "USD",
			count: 2,
			amount_minor: 3000,
			fee_minor: 75,
			share_minor: 1500,
			margin_minor: 1500,
		},
	],
	excluded: 2,
	estimate: null,
};
```

In `RequestsAdmin.tsx`, import `ExportButton` from `@/components/ExportButton` and `requestsCsvUrl` from `./csv`. Just before the `{can("consultation_request.create") ? (` block in the filter row, add:

```tsx
				<ExportButton href={requestsCsvUrl(filters)} />
```

(`ExportButton` renders nothing while `export` is off. The route already needs `consultation_request.view_any`, so only the office sees this page.)

- [ ] **Step 4: Run the tests**

Run: `F pnpm vitest run src/features/consultations`, then `F pnpm tsc --noEmit`, then `F pnpm biome check --write src/features/consultations`.
Expected: PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/consultations/csv.ts src/features/consultations/csv.test.ts \
  src/features/consultations/schemas.ts src/features/consultations/api.ts src/features/consultations/api.test.ts \
  src/features/consultations/queries.ts src/features/consultations/fixtures.ts \
  src/features/consultations/RequestsAdmin.tsx src/features/consultations/RequestsAdmin.test.tsx
git -C dashboard commit -m "feat(consultations): margins data layer and requests CSV link (B7f F-1)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The Profit margins table (F-3 screen)

**Files:**
- Create: `dashboard/src/features/consultations/MarginsReport.tsx`, `dashboard/src/features/consultations/MarginsReport.test.tsx`
- Modify: `dashboard/src/features/consultations/index.ts`, `dashboard/src/locales/en/consultations.json`, `dashboard/src/locales/ar/consultations.json`

**Interfaces:**
- Consumes: Task 6's `useMargins`, `marginsCsvUrl`, `MarginFilters`, `MarginsAnswer`, `marginsReport` fixture; B7c `useProducts`, `useConsultants`, `consultationsErrorText`; `formatMoney`; `ExportButton`; `useHasFeature`.
- Produces: `MarginsReport()` (exported from `@/features/consultations`); locale keys `consultations.requests.tabs.margins` and `consultations.margins.*`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/consultations/MarginsReport.test.tsx`:

```tsx
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import { adminWith } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { consultationsApi } from "./api";
import { marginsReport, product } from "./fixtures";
import { MarginsReport } from "./MarginsReport";

vi.mock("./api", () => ({
	consultationsApi: {
		margins: vi.fn(),
		products: vi.fn(),
		consultants: vi.fn(),
	},
}));

const EGP_ESTIMATE = {
	currency: "EGP",
	amount_minor: 195500,
	fee_minor: 3638,
	share_minor: 92750,
	margin_minor: 102750,
	as_of: "2026-10-01T00:00:00Z",
};

const show = (me = adminWith("consultations", "export")) =>
	renderWithRouter(
		<CanProvider me={me}>
			<MarginsReport />
		</CanProvider>,
	);

const totalRow = (currency: string) =>
	screen.getByText(`Total (${currency})`).closest("tr") as HTMLElement;

describe("MarginsReport", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(consultationsApi.margins).mockResolvedValue(marginsReport);
		vi.mocked(consultationsApi.products).mockResolvedValue([product]);
		vi.mocked(consultationsApi.consultants).mockResolvedValue([
			{ id: 8, full_name: "Ustadh Bilal", offers: true },
		]);
	});

	it("shows each teacher per currency and never adds currencies together", async () => {
		show();
		await screen.findByText("Total (USD)");
		const usd = screen
			.getAllByRole("row")
			.find((r) =>
				r.textContent?.startsWith("Ustadh BilalUSD"),
			) as HTMLElement;
		expect(within(usd).getByText("$30.00")).toBeInTheDocument();
		expect(within(usd).getByText("$0.75")).toBeInTheDocument();
		expect(within(usd).getAllByText("$15.00")).toHaveLength(2);
		expect(within(totalRow("USD")).getByText("$30.00")).toBeInTheDocument();
		expect(
			within(totalRow("EGP")).getByText(formatMoney(50000, "EGP", "en")),
		).toBeInTheDocument();
		expect(screen.getByText("Margin before fees")).toBeInTheDocument();
		expect(screen.getByText(/Left out: 2/)).toBeInTheDocument();
		expect(screen.queryByText(/≈/)).toBeNull();
	});

	it("shows the estimate when a total needs converting", async () => {
		vi.mocked(consultationsApi.margins).mockResolvedValue({
			...marginsReport,
			estimate: EGP_ESTIMATE,
		});
		show();
		expect(
			await screen.findByText(/≈ In EGP at your current rates/),
		).toBeInTheDocument();
	});

	it("hides the estimate when every total is already in its currency", async () => {
		vi.mocked(consultationsApi.margins).mockResolvedValue({
			...marginsReport,
			rows: [marginsReport.rows[0]],
			totals: [marginsReport.totals[0]],
			estimate: EGP_ESTIMATE,
		});
		show();
		await screen.findByText("Total (EGP)");
		expect(screen.queryByText(/≈/)).toBeNull();
	});

	it("sends the date, teacher and product filters", async () => {
		const user = userEvent.setup();
		show();
		await screen.findByText("Total (USD)");
		expect(screen.getByLabelText("From")).toHaveValue("2026-10-01");
		fireEvent.change(screen.getByLabelText("From"), {
			target: { value: "2026-09-01" },
		});
		await user.selectOptions(screen.getByLabelText("Teacher"), "8");
		await user.selectOptions(screen.getByLabelText("Consultation"), "3");
		await waitFor(() =>
			expect(consultationsApi.margins).toHaveBeenLastCalledWith({
				from: "2026-09-01",
				teacher: 8,
				product: 3,
			}),
		);
	});

	it("links the summary and detail CSVs while export is on", async () => {
		show();
		await screen.findByText("Total (USD)");
		const summary =
			screen.getByRole("link", { name: "Export CSV" }).getAttribute("href") ??
			"";
		expect(summary).toContain("consultations/reports/margins/?");
		expect(summary).toContain("format=csv");
		expect(summary).not.toContain("detail");
		expect(
			screen.getByRole("link", { name: "Export detail CSV" }),
		).toHaveAttribute("href", expect.stringContaining("detail=1"));
	});

	it("has no CSV links while export is off", async () => {
		show(adminWith("consultations"));
		await screen.findByText("Total (USD)");
		expect(screen.queryByRole("link", { name: /Export/ })).toBeNull();
	});

	it("shows an empty state, still with the left-out count", async () => {
		vi.mocked(consultationsApi.margins).mockResolvedValue({
			...marginsReport,
			rows: [],
			totals: [],
		});
		show();
		expect(
			await screen.findByText(
				"No paid consultations were completed in this period.",
			),
		).toBeInTheDocument();
		expect(screen.getByText(/Left out: 2/)).toBeInTheDocument();
	});

	it("shows a load error", async () => {
		vi.mocked(consultationsApi.margins).mockRejectedValue(new Error("boom"));
		show();
		expect(await screen.findByRole("alert")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run to see them fail**

Run: `F pnpm vitest run src/features/consultations/MarginsReport.test.tsx`
Expected: FAIL (`Failed to resolve import "./MarginsReport"`).

- [ ] **Step 3: Add the strings**

In `dashboard/src/locales/en/consultations.json`, in `requests.tabs`, add `"margins": "Profit margins"`, and add a top-level block:

```json
	"margins": {
		"from": "From",
		"to": "To",
		"teacher": "Teacher",
		"product": "Consultation",
		"exportDetail": "Export detail CSV",
		"empty": "No paid consultations were completed in this period.",
		"columns": {
			"teacher": "Teacher",
			"currency": "Currency",
			"count": "Completed",
			"amount": "Amount received",
			"fee": "Fees",
			"share": "Teacher's share",
			"margin": "Margin before fees"
		},
		"total": "Total ({{currency}})",
		"excluded": "Left out: {{count}} (unpaid, refunded, or the payment was deleted).",
		"estimate": "≈ In {{currency}} at your current rates (an estimate): received {{amount}}, fees {{fee}}, teachers' share {{share}}, margin {{margin}}."
	}
```

In `dashboard/src/locales/ar/consultations.json`, in `requests.tabs`, add `"margins": "هوامش الربح"`, and:

```json
	"margins": {
		"from": "من",
		"to": "إلى",
		"teacher": "المعلم",
		"product": "الاستشارة",
		"exportDetail": "تصدير التفاصيل CSV",
		"empty": "لا توجد استشارات مدفوعة مكتملة في هذه الفترة.",
		"columns": {
			"teacher": "المعلم",
			"currency": "العملة",
			"count": "المكتملة",
			"amount": "المبلغ المستلم",
			"fee": "الرسوم",
			"share": "حصة المعلم",
			"margin": "الهامش قبل الرسوم"
		},
		"total": "الإجمالي ({{currency}})",
		"excluded": "مستبعد: {{count}} (غير مدفوعة أو مستردة أو حُذفت دفعتها).",
		"estimate": "≈ بعملة {{currency}} وفق أسعارك الحالية (تقدير): المستلم {{amount}}، الرسوم {{fee}}، حصة المعلمين {{share}}، الهامش {{margin}}."
	}
```

- [ ] **Step 4: Write the component**

`dashboard/src/features/consultations/MarginsReport.tsx`:

```tsx
import { Percent } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ExportButton } from "@/components/ExportButton";
import { useHasFeature } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import {
	Button,
	Card,
	CardContent,
	EmptyState,
	FormError,
	Input,
	Select,
	Spinner,
} from "@/ui";
import { marginsCsvUrl } from "./csv";
import { consultationsErrorText } from "./errors";
import { useConsultants, useMargins, useProducts } from "./queries";
import type { MarginEstimate, MarginFilters, MarginMoney } from "./schemas";

const MONEY = [
	"amount_minor",
	"fee_minor",
	"share_minor",
	"margin_minor",
] as const;
const COLUMNS = [
	"teacher",
	"currency",
	"count",
	"amount",
	"fee",
	"share",
	"margin",
] as const;

/** Shown only when some total is in another currency than the estimate's:
 * an all-base report needs no conversion (FinanceSummaryCard precedent). */
function EstimateLine({
	estimate,
	totals,
}: {
	estimate: MarginEstimate | null;
	totals: MarginMoney[];
}) {
	const { t, i18n } = useTranslation();
	if (!estimate) return null;
	if (!totals.some((line) => line.currency !== estimate.currency)) return null;
	const m = (minor: number) =>
		formatMoney(minor, estimate.currency, i18n.language);
	return (
		<p className="text-sm text-muted-foreground" dir="auto">
			{t("consultations.margins.estimate", {
				currency: estimate.currency,
				amount: m(estimate.amount_minor),
				fee: m(estimate.fee_minor),
				share: m(estimate.share_minor),
				margin: m(estimate.margin_minor),
			})}
		</p>
	);
}

/** B7f F-3: per teacher and currency, what paid, completed consultations
 * brought in, the teacher's share and the academy's margin before fees.
 * Never summed across currencies. */
export function MarginsReport() {
	const { t, i18n } = useTranslation();
	const hasFeature = useHasFeature();
	const [f, setF] = useState<MarginFilters>({});
	const report = useMargins(f);
	const products = useProducts();
	const teachers = useConsultants(false);
	const money = (minor: number, currency: string) =>
		formatMoney(minor, currency, i18n.language);
	const setText = (key: "from" | "to") => (value: string) =>
		setF((old) => ({ ...old, [key]: value || undefined }));
	const setId = (key: "teacher" | "product") => (value: string) =>
		setF((old) => ({ ...old, [key]: value ? Number(value) : undefined }));
	const name = (p: { name_ar: string; name_en: string }) =>
		i18n.language === "ar" ? p.name_ar : p.name_en;
	const cells = (line: MarginMoney) =>
		MONEY.map((key) => (
			<td key={key} className="p-3 text-end tabular-nums">
				{money(line[key], line.currency)}
			</td>
		));
	const data = report.data;

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-2">
				<Input
					type="date"
					aria-label={t("consultations.margins.from")}
					className="w-auto"
					value={f.from ?? data?.from ?? ""}
					onChange={(e) => setText("from")(e.target.value)}
				/>
				<Input
					type="date"
					aria-label={t("consultations.margins.to")}
					className="w-auto"
					value={f.to ?? data?.to ?? ""}
					onChange={(e) => setText("to")(e.target.value)}
				/>
				<Select
					aria-label={t("consultations.margins.teacher")}
					className="w-auto"
					value={f.teacher ? String(f.teacher) : ""}
					onChange={(e) => setId("teacher")(e.target.value)}
				>
					<option value="">{t("consultations.any")}</option>
					{(teachers.data ?? []).map((x) => (
						<option key={x.id} value={String(x.id)}>
							{x.full_name}
						</option>
					))}
				</Select>
				<Select
					aria-label={t("consultations.margins.product")}
					className="w-auto"
					value={f.product ? String(f.product) : ""}
					onChange={(e) => setId("product")(e.target.value)}
				>
					<option value="">{t("consultations.any")}</option>
					{(products.data ?? []).map((p) => (
						<option key={p.id} value={String(p.id)}>
							{name(p)}
						</option>
					))}
				</Select>
				<div className="ms-auto flex gap-2">
					<ExportButton href={marginsCsvUrl(f)} />
					{hasFeature("export") ? (
						<Button asChild variant="outline" size="sm">
							<a href={marginsCsvUrl(f, true)} download>
								{t("consultations.margins.exportDetail")}
							</a>
						</Button>
					) : null}
				</div>
			</div>
			{report.isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : report.isError ? (
				<FormError>{consultationsErrorText(report.error, t)}</FormError>
			) : (
				<>
					{report.data.rows.length === 0 ? (
						<Card>
							<CardContent>
								<EmptyState
									icon={Percent}
									title={t("consultations.margins.empty")}
								/>
							</CardContent>
						</Card>
					) : (
						<div className="overflow-x-auto rounded-lg border border-border">
							<table className="w-full text-sm">
								<thead className="bg-secondary text-muted-foreground">
									<tr>
										{COLUMNS.map((c) => (
											<th
												key={c}
												scope="col"
												className="p-3 text-start font-medium"
											>
												{t(`consultations.margins.columns.${c}`)}
											</th>
										))}
									</tr>
								</thead>
								<tbody>
									{report.data.rows.map((row) => (
										<tr
											key={`${row.teacher.id}-${row.currency}`}
											className="border-t border-border"
										>
											<td className="p-3">{row.teacher.full_name}</td>
											<td className="p-3">{row.currency}</td>
											<td className="p-3 text-end tabular-nums">
												{row.count}
											</td>
											{cells(row)}
										</tr>
									))}
								</tbody>
								<tfoot className="font-medium">
									{report.data.totals.map((total) => (
										<tr
											key={total.currency}
											className="border-t border-border"
										>
											<td className="p-3" colSpan={2}>
												{t("consultations.margins.total", {
													currency: total.currency,
												})}
											</td>
											<td className="p-3 text-end tabular-nums">
												{total.count}
											</td>
											{cells(total)}
										</tr>
									))}
								</tfoot>
							</table>
						</div>
					)}
					<p className="text-sm text-muted-foreground">
						{t("consultations.margins.excluded", {
							count: report.data.excluded,
						})}
					</p>
					<EstimateLine
						estimate={report.data.estimate}
						totals={report.data.totals}
					/>
				</>
			)}
		</div>
	);
}
```

If `Percent` is not in the installed `lucide-react`, use `MessagesSquare`, as `RequestsAdmin` does.

In `index.ts`, add `export { MarginsReport } from "./MarginsReport";` (sorted).

- [ ] **Step 5: Run the tests**

Run: `F pnpm vitest run src/features/consultations src/locales`, then `F pnpm tsc --noEmit`, then `F pnpm biome check --write src/features/consultations src/locales/en/consultations.json src/locales/ar/consultations.json`.
Expected: PASS (the locales test keeps en and ar key-equal).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/consultations/MarginsReport.tsx src/features/consultations/MarginsReport.test.tsx \
  src/features/consultations/index.ts src/locales/en/consultations.json src/locales/ar/consultations.json
git -C dashboard commit -m "feat(consultations): profit margins table (B7f F-3)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The Profit margins tab on `/scheduling/consultations` (§3 screen)

**B7d dependency:** builds on B7d's `RequestsTabs` (`type RequestsView = "list" | "calendar" | "reviews"`, a `views` array) and on the route's `reviews` branch.

**Files:**
- Modify: `dashboard/src/features/consultations/RequestsTabs.tsx`, `RequestsTabs.test.tsx`, `dashboard/src/routes/_authed/scheduling.consultations.tsx`

**Interfaces:**
- Consumes: Task 7's `MarginsReport`; B7d's `RequestsView`, `ReviewsAdmin`.
- Produces: `RequestsView = "list" | "calendar" | "reviews" | "margins"`; `/scheduling/consultations?view=margins` (shown with `consultation_request.export_margins`).

- [ ] **Step 1: Write the failing tests**

Add to `RequestsTabs.test.tsx`:

```tsx
	it("shows the margins tab with export_margins", async () => {
		show("consultation_request.export_margins");
		expect(await screen.findByText("Profit margins")).toBeInTheDocument();
		expect(screen.queryByText("Calendar")).toBeNull();
	});
	it("has no margins tab with view_any alone", async () => {
		show("consultation_request.view_any", "consultation_schedule.view_any");
		await screen.findByText("Calendar");
		expect(screen.queryByText("Profit margins")).toBeNull();
	});
```

- [ ] **Step 2: Run to see them fail**

Run: `F pnpm vitest run src/features/consultations/RequestsTabs.test.tsx`
Expected: FAIL ("Profit margins" not found).

- [ ] **Step 3: Implement**

In `RequestsTabs.tsx`:

```tsx
export type RequestsView = "list" | "calendar" | "reviews" | "margins";
```

and after B7d's `if (can("consultation_review.view_any")) views.push("reviews");` add:

```tsx
	// B7f F-5: the money split is its own verb.
	if (can("consultation_request.export_margins")) views.push("margins");
```

Update the doc comment to name the margins tab.

In `routes/_authed/scheduling.consultations.tsx`:
- import `MarginsReport` with the others from `@/features/consultations`;
- `validateSearch` accepts `"margins"` too:

```tsx
	validateSearch: (search: Record<string, unknown>): { view?: RequestsView } =>
		search.view === "list" ||
		search.view === "calendar" ||
		search.view === "reviews" ||
		search.view === "margins"
			? { view: search.view }
			: {},
```

- after B7d's `const reviews = …`, add:

```tsx
		const margins =
			view === "margins" && can("consultation_request.export_margins");
```

- the body renders:

```tsx
				{calendar ? (
					<ScheduleWeek />
				) : reviews ? (
					<ReviewsAdmin />
				) : margins ? (
					<MarginsReport />
				) : (
					<RequestsAdmin />
				)}
```

No route file is added, so `routeTree.gen.ts` does not change.

- [ ] **Step 4: Run the tests**

Run: `F pnpm vitest run src/features/consultations src/routes`, then `F pnpm tsc --noEmit`, then `F pnpm biome check --write src/features/consultations/RequestsTabs.tsx src/features/consultations/RequestsTabs.test.tsx src/routes/_authed/scheduling.consultations.tsx`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src/features/consultations/RequestsTabs.tsx src/features/consultations/RequestsTabs.test.tsx \
  src/routes/_authed/scheduling.consultations.tsx
git -C dashboard commit -m "feat(consultations): Profit margins tab (B7f §3)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: e2e: the margins tab after completion (§4)

**Files:**
- Modify: `dashboard/e2e/b7-consultations-office.spec.ts`

**Interfaces:**
- Consumes: the B7c flow (product created, request paid in cash at $15.00, completed); Task 7/8 labels: tab "Profit margins", filter "Consultation", CSV link "Export CSV".

- [ ] **Step 1: Give the product a share**

In step 2 ("Create a product"), after `await productDialog.getByRole("tab", { name: "Teachers" }).click();`, add:

```ts
		await productDialog.getByLabel("Teacher's share (%)").fill("40");
```

- [ ] **Step 2: Add the margins step**

At the end of the test, after `await expect(done.getByText("Completed")).toBeVisible();`, add:

```ts
		// 8. B7f: the margins tab shows Bilal's 40 % of this paid, completed
		//    request ($15.00 → $6.00 share, $9.00 margin), this academy month.
		await visit(
			page,
			`${DEMO_URL}/app/scheduling/consultations?view=margins`,
			page.getByRole("link", { name: "Profit margins" }),
		);
		await page.getByLabel("Consultation", { exact: true }).selectOption({ label: productName });
		const earned = page.getByRole("row").filter({ hasText: TEACHER_NAME }).filter({ hasText: "$15.00" });
		await expect(earned).toBeVisible();
		await expect(earned.getByText("$6.00")).toBeVisible();
		await expect(earned.getByText("$9.00")).toBeVisible();
		await expect(page.getByRole("link", { name: "Export CSV" })).toHaveAttribute(
			"href",
			/consultations\/reports\/margins\/\?.*format=csv/,
		);
```

Rename the test title to `"office books a slot, confirms and takes cash; teacher records; office completes and sees the margin"`.

- [ ] **Step 3: Run it**

Run (stream stack up, `just seed` done): `just e2e e2e/b7-consultations-office.spec.ts`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git -C dashboard add e2e/b7-consultations-office.spec.ts
git -C dashboard commit -m "test(e2e): margins tab after completion (B7f)" \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Whole-slice gate

- [ ] **Step 1:** `just test` → all green. Backend coverage ≥ 80 % (`etqan/consultations/services/earnings.py`, `api/report_views.py` and `api/report_payloads.py` each fully covered by Tasks 1–5). Then `F pnpm test:coverage` → dashboard lines/statements ≥ 80, branches ≥ 70, functions ≥ 70.
- [ ] **Step 2:** `just lint` → clean, including `lint-imports` (the consultations contract with its new `finance.services` line).
- [ ] **Step 3:** `just e2e e2e/b7-consultations-office.spec.ts`, then the whole suite `just e2e` → green.
- [ ] **Step 4:** Check by hand that no claim is still held: `python3 scripts/orchestration/ledger.py show | grep -i claim` lists none for B7f's paths.
- [ ] **Step 5:** Push `feat/b7f-consultation-reports` in `backend/` and `dashboard/` and open one PR in each. After both merge, the conductor bumps the submodule pointers in the meta repo (explicit paths, `--repo Etqan-agency/etqan_tutor` for the meta PR).

## Spec coverage

| Spec item | Task |
|---|---|
| F-1 requests CSV, list filters, `safe_cell`, office only (teacher 403), export-off 404 | 5, 6 |
| F-2 completed in `[from, to]` academy dates, payment status `completed` in one query, excluded count, fee left out, half-up share from the snapshot, "margin before fees", fee column | 1, 4, 7 |
| F-3 grouping per teacher and currency, never summed, four-call estimate only when complete, default month, teacher/product filters, summary CSV and `?detail=1` CSV (`csv_columns` property) | 2, 4, 7 |
| F-4 `teacher_earnings` with fixed queries | 1 |
| F-5 `export_margins` verb, `VERB_LABELS` claim, `in_use`, view_any + export_margins | 3, 4 |
| §3 routes and the screen (Export button, Profit margins tab, subtotals, excluded, estimate, CSV buttons) | 4, 5, 6, 7, 8 |
| §4 tests, dashboard tests, e2e | 1–9 |
