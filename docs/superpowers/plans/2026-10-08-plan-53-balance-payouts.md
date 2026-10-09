# Plan 53 — Teacher balance, withdrawals, acknowledgement, salary expenses (slice B4c) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B4a (Plan 46), B3a (merged).
B4c is built on top of B4a's code. This plan treats what Plan 46 produces as existing:
- the conftest helpers `rules_on`, `student_rate` and `june_group`;
- `PaySettings` and `effective_settings`;
- the `payroll_settings` access resource;
- the payroll strings area;
- migration `0002_pay_rules`;
- the payslip CSV's `count_*` columns.

Nothing from B4b is needed.

**Slice:** B4c · **Spec:** `docs/superpowers/specs/2026-10-08-b4c-balance-payouts-design.md` · **Phase spec:** `docs/superpowers/specs/2026-10-08-b4-payroll-depth-design.md` (§3 row B4c, B4-1…B4-10)

**Goal:** Three switches, each off by default.
- `teacher_balance`: the office can pay an issued payslip into the teacher's balance. The teacher (or the office for them) asks to withdraw from it, and the office approves, pays, rejects or cancels the request.
- `payslip_acknowledgement`: the teacher confirms receipt of a paid payslip.
- `salary_expenses`: a payslip posts a `salaries` expense when it becomes paid, even while finance's `expenses` switch is off.

**Architecture:**
- **Data** (spec §3).
  - `Payslip` gains `paid_to_balance` and `acknowledged_at`.
  - Two new models: `WithdrawalRequest`, and `BalanceLock(teacher, currency)`, the payroll-owned lock row.
  - One migration, `payroll/0003_balance_payouts`, or `0004_balance_payouts` if B4b has merged first (see Global Constraints). It only adds tables and columns.
- **Balance.** `services/balances.py` derives the balance in **one SELECT**:
  - credits are the paid-to-balance payslips, grouped by currency;
  - withdrawn and reserved are correlated `Sum` subqueries.

  `balances_of(teacher_user_id)` is the only read other apps use.
- **Withdrawals.** `services/withdrawals.py` holds create, approve, reject, pay and cancel. Each write first takes `BalanceLock` (`get_or_create`, then `SELECT … FOR UPDATE`), and only then the request row.
- **Paying.** `services/payslips.py` gets one `_pay` that both `mark_paid` and `pay_to_balance` use. Inside the same transaction, it calls `services/salary_expenses.post_salary`, which calls `finance.services.post_expense`.
- **Acknowledgement.** `services/payslips.acknowledge`.
- **API** (`/api/v1/payroll/`).
  - New routes: `payslips/<id>/pay-to-balance/`, `payslips/<id>/acknowledge/` (SELF_SERVICE), `balances/`, `withdrawals/` and `withdrawals/<id>/` with `approve/`, `reject/`, `pay/` and `cancel/`.
  - Every write refuses a quick-login session (`NotImpersonating`).
  - Payslip rows gain two fields, which the CSV also gains as its last two columns.
- **Dashboard.**
  - On the office payslip page: "Pay to balance" beside "Mark paid", a "Paid to balance" chip, and the receipt date.
  - The office withdrawals page, which shows a teacher's balances once one is picked.
  - The teacher's "My balance" page, and "Confirm receipt" on their paid payslips.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-08-b4c-balance-payouts-design.md`. It builds on:
- Plan 7 (`2026-09-26-payroll-design.md`; code in `backend/etqan/payroll/`);
- Plan 46 (B4a);
- B3a (`finance.services.post_expense`, the `salaries` expense type);
- B9b (`NotImpersonating`, quick login).

It also applies these ledger decisions:
- **D5:** money stays per currency.
- **D11** and **D22:** a language other than ar or en falls back to English.
- **D19:** money-moving actions refuse an impersonated session.
- **D25:** `ValidationError(code=…)`.

## Plan rulings (where this plan fills a gap in the spec)

| # | Ruling |
|---|---|
| R1 | **Instants come from payroll's clock.** `WithdrawalRequest.created_at` has `default=timezone.now`, but `create_withdrawal` passes `created_at=clock.now()`. `decided_at` and `acknowledged_at` also come from `clock.now()`. The `paid_on`-after-creation rule (C-4) and the tests then share one clock. (`auto_now_add` would stamp the real time, which tests cannot pin.) |
| R2 | **`balances_of` groups the credits by currency** and reads the requests through correlated subqueries, all in one SELECT. Every currency with a request also has a credit: a request is only created in a currency `balances_of` lists, and a paid payslip never changes. So grouping the credits lists every currency with "any credit or request" (C-2). |
| R3 | **Payout details come from the `select_related` teacher row.** `withdrawals_queryset()` joins `teacher__user`, and `payout_method` and `payout_details` are columns of that `TeacherProfile` row. A page of rows therefore costs **zero** extra queries, tighter than C-7's "one query per page through `teacher_profiles_by_id`". This is a field path on payroll's own foreign key (B4-1). |
| R4 | **`withdrawals/` (GET and POST) composes `ReadOnly \| NotImpersonating`.** A quick-login session can still read the list, but a POST refuses it. Office-only writes, cancel, pay-to-balance and acknowledge list `NotImpersonating` directly, after `FeatureOn`. |
| R5 | **Acknowledge's permissions are `[IsTeacher, FeatureOn, NotImpersonating]`.** Admins, staff, students and parents get 403. A teacher gets 404 while the switch is off, and 404 for a payslip that is not theirs (`scope_for`). Spec §4 states the same refusals. |
| R6 | **`TITLE_MAX = 200` is repeated in payroll**, because payroll may not import `finance.models`. A test posts a 201-character title through `finance.services.post_expense` and expects a 400 on `title`, which pins the two values together. |
| R7 | **`_pay` is the only code that makes a payslip `paid`.** It posts the salary expense after saving the payslip, inside `mark_paid`'s or `pay_to_balance`'s `@transaction.atomic`. The lock order is the payslip row, then (inside finance's savepoint) the expense row. A test captures the SQL to check it. |
| R8 | **The dashboard string for `payroll.not_allowed_in_status` becomes neutral:** "That isn't possible in the current status." Withdrawals reuse the code (C-4), and no trunk test asserts the old wording ("…the payslip's current status"). |
| R9 | **The `teacher_withdrawal` resource is added in Task 7, with its routes.** `test_routes` requires `registry.IN_USE` to equal the codes the routes declare. |
| R10 | **A withdrawal form checks the available balance on submit** (`withdrawalProblem`), not in the zod schema. The office picks the teacher first, and only then do that teacher's balances load. The schema stays static and only checks that the fields are filled in. |
| R11 | **`cancel_withdrawal(…, as_office: bool)`.** The view passes `is_office(request.user)`. A teacher's cancel of another teacher's request is a 404 in the service as well as in the view's scope. |
| R12 | **The office balance read is `balances_for_teacher(user_id)`.** It answers 404 when the user is not a teacher. The view stays thin, and a teacher's own read calls `balances_of(request.user.pk)`. |
| R13 | **"Confirm receipt" appears in two places:** on each paid row of My payslips, and on the teacher's payslip page. Both use the one `ConfirmReceipt` component. |
| R14 | **The new CSV columns** are `("paid_to_balance", "Paid to balance")` and `("acknowledged_at", "Receipt confirmed at")`. They come after every column B4a and B4b add. |
| R15 | **The E2E creates its teacher through the office form**, because the invite email is what lets the teacher sign in (`acceptInvite`, as in `payroll.spec.ts`). Everything else goes through `postAsAdmin`, whose bodies are copied from the trunk serializers: `AdjustmentCreateInput`, `MonthInput`. Last month is computed in UTC, the demo academy's clock (as in Plan 46's E2E). |

## Global Constraints

**Repos and branches**
- The meta worktree is `/home/abdulkhalek/Projects/etqan_tutor-wt/b4`, written `$W` below.
- The branch is `feat/b4c-balance-payouts`.
  - Meta is cut from `origin/master`; `backend/` and `dashboard/` are cut from `origin/main`.
  - B4a must be merged first. If it isn't, stop and tell the conductor.
  - `marketing/` is untouched.
- Commit in the submodule that owns each file (`git -C $W/backend …`, `git -C $W/dashboard …`).
- Never run `git submodule update`, or any other `git submodule` subcommand that writes.
- Commit messages are Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Never edit `STATE.md`, CI workflows, Caddyfiles or meta's submodule pointers.
- Shared lists get lines only under `── phase B4 ──` markers, **after** the lines B4a (and B4b, if merged) put there. This plan's markers are in:
  - `etqan/platform/features.py`;
  - `etqan/access/registry.py`;
  - `dashboard/src/features/shell/nav.ts`.

  B4c adds no seed (spec §6), so `seed_dev.py` is untouched.

**Commands.** The stream stack must be up (`just dev-backend`) and `$W/.env.stream` must exist. The conductor creates it when it gives B4 a slot.
- Load the stream's environment first: `cd $W; set -a; . ./.env.stream; set +a`.
- Run docker compose directly. Below, `…` stands for `docker compose -f docker-compose.local.yml`.
- **Backend tests:** `… exec -T django pytest -q <paths>`. Add `--create-db` once after the migration.
- **Backend format:** `… exec -T django ruff check --fix .`, then `… exec -T django ruff format .`.
- **Backend verify:** `ruff check .`, `ruff format --check .`, `lint-imports`, `pytest -q --cov=etqan`, each through `… exec -T django`.
- **Migration:** `… exec -T django python manage.py makemigrations payroll --name balance_payouts`.
  - First run `ls $W/backend/etqan/payroll/migrations/`.
  - If the payroll leaf is `0002_pay_rules` (B4b not merged), this makes `0003_balance_payouts`.
  - If the leaf is B4b's `0003_…`, it makes `0004_balance_payouts`.
  - Use the generated name in every `git add` below.
- **Dashboard tests:** `… exec -T dashboard pnpm exec vitest run <paths>`.
- **Dashboard verify:** `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm test:coverage`, each through `… exec -T dashboard`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
- **New route files:** regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build`. It is generated: never edit it by hand.
- **Seeding:** `just _stack-manage migrate_schemas`, then `just _stack-manage seed_dev`.
- **E2E:** only through `just e2e …`.
- **Slice gates:** `just test`, `just lint`, `just e2e`.
- Never run `manage.py`, `migrate` or pytest any other way.

**Code style**
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10) and `E501` (88).
- Imports are one per line (`from x import a`, then `from x import b`), as every trunk file has them.
- A boolean keyword argument is keyword-only.
- Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §4)`.
- Payroll code and tests never import another app's `models`.
  - Use `identity_services`, `catalogue_services`, `scheduling_services` and `finance_services` (`etqan.finance.services`).
  - Field paths on returned querysets are allowed (B4-1).
  - Payroll's tests never import `finance.models` either: the import contract covers `etqan.payroll.tests`.
- `pnpm lint` allows semantic colour tokens only, never a literal colour, and that includes tests.

**TDD and reports**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helpers:
  - root fixtures: `staff_for(*codes)`, `api_for("admin")`, `set_features(**switches)`, `tenants`;
  - payroll's conftest: `clock`, `world`, `admin`, `june_sessions`, `mark`, `set_rate`, `adjust`, `JUNE`, plus B4a's `rules_on`, `student_rate` and `june_group`;
  - scheduling's conftest: `make_teacher`, `make_student`, `make_admin`, `until_pk_exceeds`.
- New shared payroll test helpers go once in `etqan/payroll/tests/conftest.py`:
  - Task 2: `JULY_FIRST`, `balance_on`, `credit` and `withdrawal`;
  - Task 4: `salary_on` and `issued_slip`;
  - Task 6: `quick_login` and `office_impersonated`.
- Every list or read that renders rows carries a query-count test that counts SELECTs only. It must give the same count for 1 row and for 3 rows.
- `etqan/platform/tests/test_features.py` `BUILT` lists every built switch **in registry order**. `teacher_balance`, `payslip_acknowledgement` and `salary_expenses` are new lines under `# ── phase B4 ──`, after B4a's (and B4b's) lines.
- `etqan/access/tests/test_routes.py`:
  - every new route joins `ROUTES`, and every gated route joins `FEATURES`, under a `# Slice B4c.` comment;
  - `FEATURE_WORDS` gains `"/pay-to-balance/"`, `"/payroll/balances/"` and `"/withdrawals/"`, all mapped to `"teacher_balance"`;
  - `SELF_SERVICE` gains `etqan.payroll.api.views.AcknowledgeView`.
- `dashboard/src/routes/permissions.test.ts`:
  - `FEATURE_SCREENS` gains `"/_authed/payroll/withdrawals": "teacher_balance"` and `"/_authed/teaching/balance": "teacher_balance"`;
  - `FEATURE_WORDS` gains `payroll\/withdrawals|teaching\/balance|`.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- The seeded dev password is `e2e-EtqanTest-2026`. The demo admin is `admin@demo.test`.

## Review Focus

1. **Two concurrent requests that together exceed the available balance.** Both take `BalanceLock(teacher, currency)` before reading `balances_of`, so the second sees the first and is refused with 409. Pinned by Task 3's lock-shape test and the insufficient-balance test.
2. **Paying moves money exactly once.**
   - A failing `post_expense` rolls the payment back.
   - A net of 0 posts nothing.
   - A second post updates the one expense instead of adding another.
   - The expense posts with `expenses` off.

   Pinned in Task 4.
3. **The balance read is one statement and per currency.** Reserved requests lower only `available`. Pinned in Task 2, including the query count.
4. **Quick login cannot move money.** Every B4c write answers 403 `identity.impersonating`, and reads stay open. Pinned in Tasks 6 and 7.
5. **A teacher's reach.**
   - A teacher sees only their own requests, balance and payslips.
   - They cancel only while a request is under review.
   - Only they acknowledge their own paid payslip.

   Pinned in Tasks 3, 5, 6 and 7.

---

### Task 1: The switches, the models and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py`. Under `# ── phase B4 ──`, after B4a's lines, add three `Feature` lines.
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`).
- Modify: `backend/etqan/payroll/models.py`.
- Create: `backend/etqan/payroll/migrations/0003_balance_payouts.py` (generated; `0004_…` if B4b merged).
- Test: `backend/etqan/payroll/tests/test_models.py` (append).

**Interfaces:**
- Produces:
  - `Payslip.paid_to_balance` (bool, default false) and `Payslip.acknowledged_at` (datetime, null);
  - `WithdrawalRequest(teacher, amount_minor, currency, status, notes, office_notes, requested_by, decided_by, paid_by, decided_at, paid_on, created_at, updated_at)`, with `WithdrawalRequest.Status.UNDER_REVIEW / APPROVED / PAID / REJECTED / CANCELLED`;
  - `BalanceLock(teacher, currency)`;
  - the switch codes `teacher_balance`, `payslip_acknowledgement` and `salary_expenses`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/payroll/tests/test_models.py`. Merge the imports into the file's import block, one per line, without repeating those B4a already added (`IntegrityError`, `features`).

```python
from etqan.payroll.models import BalanceLock
from etqan.payroll.models import Payslip
from etqan.payroll.models import WithdrawalRequest


def test_a_payslip_is_not_paid_to_balance_or_acknowledged_by_default():
    assert Payslip._meta.get_field("paid_to_balance").default is False  # noqa: SLF001
    assert Payslip._meta.get_field("acknowledged_at").null  # noqa: SLF001


def test_a_withdrawal_request_starts_under_review(world):
    row = WithdrawalRequest.objects.create(
        teacher=world.teacher.teacher_profile, amount_minor=100, currency="USD"
    )
    assert row.status == WithdrawalRequest.Status.UNDER_REVIEW
    assert (row.notes, row.office_notes, row.decided_at, row.paid_on) == (
        "",
        "",
        None,
        None,
    )


@pytest.mark.parametrize("amount", [0, -1])
def test_a_withdrawal_amount_must_be_positive(world, amount):
    with pytest.raises(IntegrityError):
        WithdrawalRequest.objects.create(
            teacher=world.teacher.teacher_profile, amount_minor=amount, currency="USD"
        )


def test_one_balance_lock_per_teacher_and_currency(world):
    teacher = world.teacher.teacher_profile
    BalanceLock.objects.create(teacher=teacher, currency="USD")
    BalanceLock.objects.create(teacher=teacher, currency="EGP")
    with pytest.raises(IntegrityError):
        BalanceLock.objects.create(teacher=teacher, currency="USD")


def test_the_b4c_switches_are_built_off_and_need_nothing():
    for code in ("teacher_balance", "payslip_acknowledgement", "salary_expenses"):
        feature = features.get(code)
        assert (feature.built, feature.default, feature.requires) == (True, False, ())
```

In `etqan/platform/tests/test_features.py` `BUILT`, under `# ── phase B4 ──`, add these lines after the last B4 line (B4a's `"bulk_teacher_rates": False`, or B4b's last line if B4b merged):

```python
    "teacher_balance": False,
    "payslip_acknowledgement": False,
    "salary_expenses": False,
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_models.py etqan/platform/tests/test_features.py`
Expected: FAIL. The first is an ImportError (`BalanceLock`), and the `BUILT` comparison fails too.

- [ ] **Step 3: The switches**

In `features.py`, under `# ── phase B4 ──`, after the last B4 line:

```python
    # Slice B4c (C-1, C-2): pay a payslip into the teacher's balance, and
    # withdrawal requests against it.
    Feature("teacher_balance", "Teacher balance", "رصيد المعلم", "money", built=True),
    # Slice B4c (C-8): the teacher confirms receipt of a paid payslip.
    Feature(
        "payslip_acknowledgement",
        "Payslip receipt confirmation",
        "تأكيد استلام الراتب",
        "money",
        built=True,
    ),
    # Slice B4c (C-9): a paid payslip posts a salary expense. It requires
    # nothing, so it posts while `expenses` is off too (B3a A-8).
    Feature(
        "salary_expenses",
        "Salary expenses",
        "مصروفات الرواتب",
        "money",
        built=True,
        requires=(),
    ),
```

- [ ] **Step 4: The models**

In `payroll/models.py`, add `from django.utils import timezone` to the imports. In `Payslip`, after `notes`:

```python
    # Slice B4c C-1: paid into the teacher's balance rather than directly.
    paid_to_balance = models.BooleanField(default=False)
    # Slice B4c C-8: when the teacher confirmed receipt (UTC); set once.
    acknowledged_at = models.DateTimeField(null=True, blank=True)
```

After `PayslipLine`, add:

```python
class WithdrawalRequest(models.Model):
    """Slice B4c C-3: a teacher's request to withdraw from their balance, in
    one of its currencies. The office approves, pays, rejects or cancels it;
    the teacher may cancel it while it is under review (C-4)."""

    class Status(models.TextChoices):
        UNDER_REVIEW = "under_review", "Under review"
        APPROVED = "approved", "Approved"
        PAID = "paid", "Paid"
        REJECTED = "rejected", "Rejected"
        CANCELLED = "cancelled", "Cancelled"

    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.UNDER_REVIEW
    )
    notes = models.TextField(blank=True, default="")  # the requester's
    # The office's; a rejection's reason, which the teacher reads (C-7).
    office_notes = models.TextField(blank=True, default="")
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    paid_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    paid_on = models.DateField(null=True, blank=True)  # the academy's calendar
    # Plan R1: the service stamps payroll's clock; the default is for rows
    # written directly.
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0),
                name="payroll_withdrawal_amount_positive",
            )
        ]
        indexes = [
            models.Index(fields=["teacher", "status"]),
            models.Index(fields=["status", "created_at"]),
        ]

    def __str__(self):
        return f"WithdrawalRequest<{self.amount_minor} {self.currency}, {self.status}>"


class BalanceLock(models.Model):
    """Slice B4c C-5: the row every withdrawal write locks first (`SELECT …
    FOR UPDATE`), one per teacher and currency, created on first use.
    Nothing in identity is locked."""

    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    currency = models.CharField(max_length=3, validators=[CURRENCY])

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["teacher", "currency"], name="payroll_one_balance_lock"
            )
        ]

    def __str__(self):
        return f"BalanceLock<{self.teacher_id}, {self.currency}>"
```

- [ ] **Step 5: The migration**

Run `ls $W/backend/etqan/payroll/migrations/`, then `… exec -T django python manage.py makemigrations payroll --name balance_payouts`. Open the generated file. It must hold exactly:
- two `AddField` operations on `payslip`;
- two `CreateModel` operations;
- the constraint and index operations.

It must hold no `RunPython` and no `AlterField` on existing columns. If it shows anything else, the models differ from Step 4: fix the models, never the migration.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q --create-db etqan/payroll etqan/platform/tests/test_features.py`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/payroll/models.py etqan/payroll/migrations/0003_balance_payouts.py etqan/payroll/tests/test_models.py
git -C $W/backend commit -m "feat(payroll): B4c switches, withdrawal requests, balance locks, payslip flags

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

(Use `0004_balance_payouts.py` if that is the generated name.)

---

### Task 2: The derived balance in one SELECT

**Files:**
- Create: `backend/etqan/payroll/services/balances.py`
- Modify: `backend/etqan/payroll/services/__init__.py` (exports)
- Modify: `backend/etqan/payroll/tests/conftest.py` (`JULY_FIRST`, `balance_on`, `credit`, `withdrawal`)
- Test: `backend/etqan/payroll/tests/test_balances.py` (new)

**Interfaces:**
- Consumes: the Task 1 models.
- Produces:
  - `Balance(currency, balance_minor, available_minor)`, a frozen dataclass;
  - `balances_of(teacher_user_id) -> list[Balance]`;
  - `balances_for_teacher(teacher_user_id) -> list[Balance]` (404 for a user who is not a teacher);
  - in conftest: `JULY_FIRST`, the `balance_on` fixture, `credit(teacher, net, *, currency, month, to_balance)` and `withdrawal(teacher, amount, *, currency, status)`.

- [ ] **Step 1: Write the conftest helpers and the failing tests**

Append to `etqan/payroll/tests/conftest.py`, and merge its imports: `import itertools`, `from datetime import UTC`, `from datetime import datetime`, `from etqan.payroll.models import Payslip` and `from etqan.payroll.models import WithdrawalRequest`.

```python
# ── Slice B4c ────────────────────────────────────────────────────────────────

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
_NUMBERS = itertools.count(900001)


@pytest.fixture
def balance_on(set_features):
    """Slice B4c: the teacher balance and withdrawals switched on."""
    set_features(teacher_balance=True)


def credit(teacher, net, *, currency="USD", month=6, to_balance=True):
    """A paid 2026 payslip of ``teacher`` (a User) for ``month``, written
    directly, paid to their balance unless ``to_balance`` is false. One per
    month: a payslip is unique per teacher and month."""
    return Payslip.objects.create(
        number=f"PAY-{next(_NUMBERS)}",
        teacher=teacher.teacher_profile,
        year=2026,
        month=month,
        status=Payslip.Status.PAID,
        currency=currency,
        gross_minor=net,
        net_minor=net,
        paid_on=date(2026, month, 28),
        paid_to_balance=to_balance,
    )


def withdrawal(teacher, amount, *, currency="USD", status="under_review"):
    """A withdrawal request of ``teacher`` (a User) in ``status``, written
    directly and dated 1 July 2026, 09:00 UTC."""
    return WithdrawalRequest.objects.create(
        teacher=teacher.teacher_profile,
        amount_minor=amount,
        currency=currency,
        status=status,
        requested_by=teacher,
        created_at=JULY_FIRST,
    )
```

`backend/etqan/payroll/tests/test_balances.py`:

```python
"""Slice B4c C-2: the derived balance, per currency, in one SELECT."""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.payroll import services
from etqan.payroll.services import Balance
from etqan.payroll.tests.conftest import credit
from etqan.payroll.tests.conftest import withdrawal
from etqan.platform.exceptions import NotFoundError
from etqan.scheduling.tests.conftest import make_teacher


def test_credits_are_the_paid_to_balance_payslips(world):
    credit(world.teacher, 5000)
    credit(world.teacher, 3000, month=5)
    credit(world.teacher, 9999, month=4, to_balance=False)  # paid directly
    assert services.balances_of(world.teacher.id) == [Balance("USD", 8000, 8000)]


def test_reserved_requests_lower_only_the_available(world):
    credit(world.teacher, 5000)
    withdrawal(world.teacher, 700)
    withdrawal(world.teacher, 300, status="approved")
    withdrawal(world.teacher, 400, status="rejected")
    withdrawal(world.teacher, 200, status="cancelled")
    assert services.balances_of(world.teacher.id) == [Balance("USD", 5000, 4000)]


def test_paid_withdrawals_lower_the_balance(world):
    credit(world.teacher, 5000)
    withdrawal(world.teacher, 1000, status="paid")
    withdrawal(world.teacher, 500)
    assert services.balances_of(world.teacher.id) == [Balance("USD", 4000, 3500)]


def test_each_currency_stands_alone_ordered_by_code(world):
    credit(world.teacher, 5000)
    credit(world.teacher, 2000, currency="EGP", month=5)
    withdrawal(world.teacher, 1000, status="paid")
    withdrawal(world.teacher, 500, currency="EGP")
    assert services.balances_of(world.teacher.id) == [
        Balance("EGP", 2000, 1500),
        Balance("USD", 4000, 4000),
    ]


def test_another_teachers_rows_never_count(world):
    maryam = make_teacher("Maryam")
    credit(maryam, 7000)
    withdrawal(maryam, 100)
    credit(world.teacher, 5000)
    assert services.balances_of(world.teacher.id) == [Balance("USD", 5000, 5000)]


def test_a_user_with_no_teacher_profile_has_none(world):
    assert services.balances_of(world.student.id) == []
    assert services.balances_of(999999) == []


def test_the_balance_is_read_in_one_select(world):
    credit(world.teacher, 5000)
    credit(world.teacher, 2000, currency="EGP", month=5)
    withdrawal(world.teacher, 1000, status="paid")
    withdrawal(world.teacher, 500, status="approved")
    with CaptureQueriesContext(connection) as ctx:
        balances = services.balances_of(world.teacher.id)
    assert len(balances) == 2
    assert len(ctx.captured_queries) == 1
    assert ctx.captured_queries[0]["sql"].lstrip().upper().startswith("SELECT")


def test_the_office_read_refuses_a_user_who_is_not_a_teacher(world):
    credit(world.teacher, 5000)
    assert services.balances_for_teacher(world.teacher.id) == [
        Balance("USD", 5000, 5000)
    ]
    for user_id in (world.student.id, 999999):
        with pytest.raises(NotFoundError):
            services.balances_for_teacher(user_id)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_balances.py`
Expected: FAIL with `ImportError: cannot import name 'Balance'`.

- [ ] **Step 3: Implement `services/balances.py`**

```python
"""Slice B4c C-2: a teacher's balance, derived, with no ledger table, so
nothing can drift. Credits are the net of their paid-to-balance payslips;
withdrawn is their paid requests; reserved is their requests under review or
approved."""

from dataclasses import dataclass

from django.db.models import BigIntegerField
from django.db.models import OuterRef
from django.db.models import Subquery
from django.db.models import Sum
from django.db.models import Value
from django.db.models.functions import Coalesce

from etqan.identity import services as identity_services
from etqan.payroll.models import Payslip
from etqan.payroll.models import WithdrawalRequest
from etqan.platform.exceptions import NotFoundError

WITHDRAWN = (WithdrawalRequest.Status.PAID,)
RESERVING = (WithdrawalRequest.Status.UNDER_REVIEW, WithdrawalRequest.Status.APPROVED)


@dataclass(frozen=True)
class Balance:
    currency: str
    balance_minor: int
    available_minor: int


def _requested(teacher_user_id: int, statuses) -> Coalesce:
    """The teacher's requests in ``statuses``, summed in the outer row's
    currency: a correlated subquery, so the read stays one statement."""
    rows = (
        WithdrawalRequest.objects.filter(
            teacher__user_id=teacher_user_id,
            currency=OuterRef("currency"),
            status__in=statuses,
        )
        .order_by()
        .values("currency")
        .annotate(total=Sum("amount_minor"))
        .values("total")
    )
    return Coalesce(
        Subquery(rows, output_field=BigIntegerField()),
        Value(0),
        output_field=BigIntegerField(),
    )


def balances_of(teacher_user_id: int) -> list[Balance]:
    """C-2, per currency, ordered by code: ``balance = credits − withdrawn``
    and ``available = balance − reserved``, in ONE SELECT. The credits are
    grouped by currency, and the requests are correlated subqueries. Plan R2:
    every currency with a request has a credit, so the groups list every
    currency. A user with no teacher profile has none. The only read other
    apps use (affects B11)."""
    rows = (
        Payslip.objects.filter(
            teacher__user_id=teacher_user_id,
            status=Payslip.Status.PAID,
            paid_to_balance=True,
        )
        .order_by()
        .values("currency")
        .annotate(
            credits=Sum("net_minor"),
            withdrawn=_requested(teacher_user_id, WITHDRAWN),
            reserved=_requested(teacher_user_id, RESERVING),
        )
        .order_by("currency")
    )
    balances = []
    for row in rows:
        balance = row["credits"] - row["withdrawn"]
        balances.append(Balance(row["currency"], balance, balance - row["reserved"]))
    return balances


def balances_for_teacher(teacher_user_id: int) -> list[Balance]:
    """The office's read (spec §4, plan R12): 404 for a user who is not a
    teacher."""
    profile = identity_services.get_teacher_profile(teacher_user_id)
    if profile is None or profile.user.role != "teacher":
        raise NotFoundError("Teacher", teacher_user_id)
    return balances_of(teacher_user_id)
```

In `services/__init__.py`, import `Balance`, `balances_for_teacher` and `balances_of` from `etqan.payroll.services.balances`, one per line, and add the three names to `__all__` in sorted order.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_balances.py`
Expected: PASS. If the query-count test shows 2 queries, the subquery was evaluated on its own: `Subquery` must wrap the queryset, never a `list`.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/balances.py etqan/payroll/services/__init__.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_balances.py
git -C $W/backend commit -m "feat(payroll): derived teacher balance per currency in one select (B4c C-2)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Withdrawal requests — create, the transitions and the locks

**Files:**
- Create: `backend/etqan/payroll/services/withdrawals.py`
- Modify: `backend/etqan/payroll/clock.py` (`day_of`)
- Modify: `backend/etqan/payroll/services/__init__.py` (exports)
- Test: `backend/etqan/payroll/tests/test_withdrawals.py` (new)

**Interfaces:**
- Consumes: `balances_of` (Task 2), `rules.teacher_of`, `rules.save` (trunk).
- Produces:
  - `create_withdrawal(*, teacher_id, amount_minor, currency, by, notes="")`;
  - `approve_withdrawal(withdrawal, *, by)`;
  - `reject_withdrawal(withdrawal, *, by, office_notes)`;
  - `pay_withdrawal(withdrawal, *, by, paid_on)`;
  - `cancel_withdrawal(withdrawal, *, by, as_office)`;
  - `withdrawals_queryset()` and `filter_withdrawals(rows, *, status, currency, teacher)`;
  - `hold_balance(teacher_id, currency)`;
  - `clock.day_of(instant) -> date`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_withdrawals.py`:

```python
"""Slice B4c C-3 to C-6: withdrawal requests, every transition and refusal,
and the lock order (BalanceLock, then the request row)."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.payroll import services
from etqan.payroll.services import Balance
from etqan.payroll.tests.conftest import JULY_FIRST
from etqan.payroll.tests.conftest import credit
from etqan.payroll.tests.conftest import withdrawal
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_teacher


@pytest.fixture
def funded(world, clock):
    """Bilal with 5000 USD in his balance, on 1 July 2026."""
    clock.set(JULY_FIRST)
    credit(world.teacher, 5000)
    return world.teacher


def create(teacher, amount, *, by=None, currency="USD"):
    return services.create_withdrawal(
        teacher_id=teacher.id,
        amount_minor=amount,
        currency=currency,
        by=by or teacher,
    )


ACTIONS = {
    "approve": lambda w, admin: services.approve_withdrawal(w, by=admin),
    "reject": lambda w, admin: services.reject_withdrawal(
        w, by=admin, office_notes="No"
    ),
    "pay": lambda w, admin: services.pay_withdrawal(
        w, by=admin, paid_on=date(2026, 7, 1)
    ),
    "cancel": lambda w, admin: services.cancel_withdrawal(w, by=admin, as_office=True),
}
ALLOWED = {
    "under_review": {"approve", "reject", "cancel"},
    "approved": {"pay", "reject", "cancel"},
    "paid": set(),
    "rejected": set(),
    "cancelled": set(),
}
REFUSED = [(s, a) for s in ALLOWED for a in ACTIONS if a not in ALLOWED[s]]


def test_a_request_starts_under_review_and_reserves(funded):
    made = services.create_withdrawal(
        teacher_id=funded.id,
        amount_minor=2000,
        currency=" usd ",
        by=funded,
        notes="Rent",
    )
    assert (made.status, made.currency, made.notes) == ("under_review", "USD", "Rent")
    assert (made.requested_by, made.created_at) == (funded, JULY_FIRST)
    assert services.balances_of(funded.id) == [Balance("USD", 5000, 3000)]


def test_more_than_available_is_refused(funded):
    create(funded, 4000)
    with pytest.raises(ConflictError) as refused:
        create(funded, 1001)
    assert refused.value.code == "payroll.insufficient_balance"
    assert create(funded, 1000).amount_minor == 1000  # exactly what is left


def test_a_currency_outside_the_balances_is_a_400(funded):
    with pytest.raises(ValidationError) as bad:
        create(funded, 100, currency="EGP")
    assert bad.value.field == "currency"


def test_an_inactive_teacher_cannot_ask_but_the_office_can_for_them(funded, admin):
    funded.is_active = False
    funded.save(update_fields=["is_active"])
    with pytest.raises(ValidationError) as own:
        create(funded, 100)
    assert own.value.field == "teacher"
    assert create(funded, 100, by=admin).status == "under_review"


def test_the_office_approves_then_pays(funded, admin):
    made = create(funded, 2000)
    approved = services.approve_withdrawal(made, by=admin)
    assert (approved.status, approved.decided_by, approved.decided_at) == (
        "approved",
        admin,
        JULY_FIRST,
    )
    assert services.balances_of(funded.id) == [Balance("USD", 5000, 3000)]
    paid = services.pay_withdrawal(made, by=admin, paid_on=date(2026, 7, 1))
    assert (paid.status, paid.paid_by, paid.paid_on) == (
        "paid",
        admin,
        date(2026, 7, 1),
    )
    assert services.balances_of(funded.id) == [Balance("USD", 3000, 3000)]


@pytest.mark.parametrize("start", ["under_review", "approved"])
def test_a_rejection_needs_a_reason_and_frees_the_amount(funded, admin, start):
    made = withdrawal(funded, 1000, status=start)
    with pytest.raises(ValidationError) as bare:
        services.reject_withdrawal(made, by=admin, office_notes="  ")
    assert bare.value.field == "office_notes"
    done = services.reject_withdrawal(made, by=admin, office_notes=" Wrong IBAN ")
    assert (done.status, done.office_notes, done.decided_by) == (
        "rejected",
        "Wrong IBAN",
        admin,
    )
    assert services.balances_of(funded.id) == [Balance("USD", 5000, 5000)]


@pytest.mark.parametrize(
    ("start", "as_office"),
    [("under_review", False), ("under_review", True), ("approved", True)],
)
def test_who_may_cancel_and_when(funded, admin, start, as_office):
    made = withdrawal(funded, 1000, status=start)
    by = admin if as_office else funded
    done = services.cancel_withdrawal(made, by=by, as_office=as_office)
    assert (done.status, done.decided_by) == ("cancelled", by)


def test_a_teacher_cannot_cancel_an_approved_request(funded):
    made = withdrawal(funded, 1000, status="approved")
    with pytest.raises(ConflictError) as refused:
        services.cancel_withdrawal(made, by=funded, as_office=False)
    assert refused.value.code == "payroll.not_allowed_in_status"


def test_a_teacher_cannot_cancel_another_teachers_request(funded):
    made = withdrawal(funded, 1000)
    with pytest.raises(NotFoundError):
        services.cancel_withdrawal(made, by=make_teacher("Maryam"), as_office=False)


@pytest.mark.parametrize(("start", "action"), REFUSED)
def test_every_other_move_is_a_409(funded, admin, start, action):
    made = withdrawal(funded, 1000, status=start)
    with pytest.raises(ConflictError) as refused:
        ACTIONS[action](made, admin)
    assert refused.value.code == "payroll.not_allowed_in_status"
    made.refresh_from_db()
    assert made.status == start


@pytest.mark.parametrize("day", [date(2026, 6, 30), date(2026, 7, 2)])
def test_paid_on_is_between_the_request_day_and_today(funded, admin, day):
    made = withdrawal(funded, 1000, status="approved")  # made on 1 July
    with pytest.raises(ValidationError) as bad:
        services.pay_withdrawal(made, by=admin, paid_on=day)
    assert bad.value.field == "paid_on"


# ── Lock shape (C-5) ─────────────────────────────────────────────────────────


def _for_update(captured) -> list[str]:
    return [q["sql"] for q in captured if "FOR UPDATE" in q["sql"]]


def _table(sql: str) -> str:
    for table in ("payroll_balancelock", "payroll_withdrawalrequest", "payroll_payslip"):
        if f'FROM "{table}"' in sql:
            return table
    return sql


def test_create_locks_the_balance_before_writing_the_request(funded):
    with CaptureQueriesContext(connection) as ctx:
        create(funded, 100)
    sqls = [q["sql"] for q in ctx.captured_queries]
    lock = next(
        i for i, sql in enumerate(sqls)
        if 'FROM "payroll_balancelock"' in sql and "FOR UPDATE" in sql
    )
    insert = next(
        i for i, sql in enumerate(sqls)
        if sql.startswith('INSERT INTO "payroll_withdrawalrequest"')
    )
    assert lock < insert
    assert [_table(sql) for sql in _for_update(ctx.captured_queries)] == [
        "payroll_balancelock"
    ]


@pytest.mark.parametrize(
    ("action", "start"),
    [("approve", "under_review"), ("pay", "approved"), ("cancel", "approved")],
)
def test_decisions_lock_the_balance_then_the_request(funded, admin, action, start):
    made = withdrawal(funded, 1000, status=start)
    with CaptureQueriesContext(connection) as ctx:
        ACTIONS[action](made, admin)
    assert [_table(sql) for sql in _for_update(ctx.captured_queries)] == [
        "payroll_balancelock",
        "payroll_withdrawalrequest",
    ]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_withdrawals.py`
Expected: FAIL with `AttributeError: module 'etqan.payroll.services' has no attribute 'create_withdrawal'`.

- [ ] **Step 3: Add `clock.day_of`**

In `payroll/clock.py`:

```python
def day_of(instant: datetime) -> date:
    """``instant``'s day on the academy's calendar."""
    return instant.astimezone(
        ZoneInfo(academy_services.get_settings().timezone)
    ).date()


def today() -> date:
    """Today on the academy's calendar (`AcademySettings.timezone`): a month
    is over, and a payslip is paid, by it."""
    return day_of(now())
```

- [ ] **Step 4: Implement `services/withdrawals.py`**

```python
"""Teacher withdrawal requests against the balance (slice B4c C-3 to C-6).

Locks (C-5): every write first takes the payroll-owned
``BalanceLock(teacher, currency)`` row, then the request's row. It decides on
fresh rows and never locks a payslip."""

from datetime import date

from django.db import transaction
from django.db.models import QuerySet

from etqan.payroll import clock
from etqan.payroll.models import BalanceLock
from etqan.payroll.models import WithdrawalRequest
from etqan.payroll.services import rules
from etqan.payroll.services.balances import balances_of
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency

UNDER_REVIEW = WithdrawalRequest.Status.UNDER_REVIEW
APPROVED = WithdrawalRequest.Status.APPROVED
PAID = WithdrawalRequest.Status.PAID
REJECTED = WithdrawalRequest.Status.REJECTED
CANCELLED = WithdrawalRequest.Status.CANCELLED


def hold_balance(teacher_id: int, currency: str) -> None:
    """C-5: lock ``(teacher, currency)``'s row, creating it on first use
    (`get_or_create` survives a concurrent create)."""
    row, _ = BalanceLock.objects.get_or_create(teacher_id=teacher_id, currency=currency)
    BalanceLock.objects.select_for_update().get(pk=row.pk)


def _locked(withdrawal: WithdrawalRequest) -> WithdrawalRequest:
    """The BalanceLock first, then the request's own row, read fresh. Its
    teacher and currency never change, so the unlocked read is safe."""
    hold_balance(withdrawal.teacher_id, withdrawal.currency)
    try:
        return (
            WithdrawalRequest.objects.select_for_update(of=("self",))
            .select_related("teacher")
            .get(pk=withdrawal.pk)
        )
    except WithdrawalRequest.DoesNotExist:
        raise NotFoundError("Withdrawal request", withdrawal.pk) from None


def _refuse_unless(withdrawal: WithdrawalRequest, *statuses: str) -> None:
    if withdrawal.status not in statuses:
        raise ConflictError(
            f"Not allowed while the request is {withdrawal.status}.",
            code="payroll.not_allowed_in_status",
        )


def _decide(
    locked: WithdrawalRequest, status: str, *, by, office_notes: str | None = None
) -> WithdrawalRequest:
    locked.status = status
    locked.decided_by = by
    locked.decided_at = clock.now()
    fields = ["status", "decided_by", "decided_at", "updated_at"]
    if office_notes is not None:
        locked.office_notes = office_notes
        fields.append("office_notes")
    locked.save(update_fields=fields)
    return locked


@transaction.atomic
def create_withdrawal(
    *, teacher_id: int, amount_minor: int, currency: str, by, notes: str = ""
) -> WithdrawalRequest:
    """C-3, C-5, C-6. ``teacher_id`` is a User id.
    - A teacher asking for themselves must be active (400 on ``teacher``).
      The office may ask for anyone, active or not.
    - The currency must be one of the teacher's balances (400 on
      ``currency``).
    - The amount may be no more than that balance's available amount (409
      `payroll.insufficient_balance`). This is decided under the
      BalanceLock, so two concurrent requests cannot both pass."""
    teacher = rules.teacher_of(teacher_id)
    if by is not None and by.pk == teacher.user_id and not teacher.user.is_active:
        raise ValidationError("This teacher is no longer active.", field="teacher")
    code = clean_currency(currency, field="currency")
    hold_balance(teacher.pk, code)
    balance = next(
        (b for b in balances_of(teacher.user_id) if b.currency == code), None
    )
    if balance is None:
        raise ValidationError(
            "This teacher has no balance in that currency.", field="currency"
        )
    if amount_minor > balance.available_minor:
        raise ConflictError(
            "That is more than the available balance.",
            code="payroll.insufficient_balance",
        )
    withdrawal = WithdrawalRequest(
        teacher=teacher,
        amount_minor=amount_minor,
        currency=code,
        notes=notes,
        requested_by=by,
        created_at=clock.now(),
    )
    rules.save(withdrawal)
    return withdrawal


@transaction.atomic
def approve_withdrawal(withdrawal: WithdrawalRequest, *, by) -> WithdrawalRequest:
    """C-4: under review → approved (office). The amount stays reserved."""
    locked = _locked(withdrawal)
    _refuse_unless(locked, UNDER_REVIEW)
    return _decide(locked, APPROVED, by=by)


@transaction.atomic
def reject_withdrawal(
    withdrawal: WithdrawalRequest, *, by, office_notes: str
) -> WithdrawalRequest:
    """C-4: under review or approved → rejected (office). The reason is
    required (400 on ``office_notes``), and the teacher reads it."""
    reason = office_notes.strip()
    if not reason:
        raise ValidationError("Say why the request is rejected.", field="office_notes")
    locked = _locked(withdrawal)
    _refuse_unless(locked, UNDER_REVIEW, APPROVED)
    return _decide(locked, REJECTED, by=by, office_notes=reason)


@transaction.atomic
def pay_withdrawal(
    withdrawal: WithdrawalRequest, *, by, paid_on: date
) -> WithdrawalRequest:
    """C-4: approved → paid (office). ``paid_on`` may not be after the
    academy's today, nor before the day the request was made (400 on
    ``paid_on``). It never posts an expense (C-9)."""
    locked = _locked(withdrawal)
    _refuse_unless(locked, APPROVED)
    if paid_on > clock.today():
        raise ValidationError("A request can't be paid in the future.", field="paid_on")
    if paid_on < clock.day_of(locked.created_at):
        raise ValidationError(
            "A request can't be paid before it was made.", field="paid_on"
        )
    locked.status = PAID
    locked.paid_on = paid_on
    locked.paid_by = by
    locked.save(update_fields=["status", "paid_on", "paid_by", "updated_at"])
    return locked


@transaction.atomic
def cancel_withdrawal(
    withdrawal: WithdrawalRequest, *, by, as_office: bool
) -> WithdrawalRequest:
    """C-4: the request's teacher cancels it while it is under review, and
    the office also once it is approved. Plan R11: a teacher cancelling
    another teacher's request is not found."""
    locked = _locked(withdrawal)
    if as_office:
        _refuse_unless(locked, UNDER_REVIEW, APPROVED)
    else:
        if locked.teacher.user_id != by.pk:
            raise NotFoundError("Withdrawal request", withdrawal.pk)
        _refuse_unless(locked, UNDER_REVIEW)
    return _decide(locked, CANCELLED, by=by)


def withdrawals_queryset() -> QuerySet[WithdrawalRequest]:
    """Requests with everything a row shows, in one query: the teacher with
    their payout details (C-7, plan R3), and the people who asked, decided
    and paid."""
    return WithdrawalRequest.objects.select_related(
        "teacher__user", "requested_by", "decided_by", "paid_by"
    )


def filter_withdrawals(
    rows: QuerySet[WithdrawalRequest],
    *,
    status: str = "",
    currency: str = "",
    teacher: int | None = None,
) -> QuerySet[WithdrawalRequest]:
    """The list's filters (spec §4); a teacher is a User id. Newest first."""
    if status:
        rows = rows.filter(status=status)
    if currency:
        rows = rows.filter(currency=currency.strip().upper())
    if teacher is not None:
        rows = rows.filter(teacher__user_id=teacher)
    return rows.order_by("-created_at", "-id")
```

In `services/__init__.py`, import and export `approve_withdrawal`, `cancel_withdrawal`, `create_withdrawal`, `filter_withdrawals`, `pay_withdrawal`, `reject_withdrawal` and `withdrawals_queryset`, one import per line, with `__all__` kept sorted.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/clock.py etqan/payroll/services/withdrawals.py etqan/payroll/services/__init__.py etqan/payroll/tests/test_withdrawals.py
git -C $W/backend commit -m "feat(payroll): withdrawal requests with balance locks and transitions (B4c C-3..C-6)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Pay to balance and the salary expense

**Files:**
- Create: `backend/etqan/payroll/services/salary_expenses.py`
- Modify: `backend/etqan/payroll/services/payslips.py` (`_pay`, `mark_paid`, `pay_to_balance`)
- Modify: `backend/etqan/payroll/services/__init__.py` (export `pay_to_balance`)
- Modify: `backend/etqan/payroll/tests/conftest.py` (`salary_on`, `issued_slip`)
- Test: `backend/etqan/payroll/tests/test_pay_to_balance.py` (new)

**Interfaces:**
- Consumes: `finance.services.post_expense` (B3a), `academy_services.get_settings`, `features.enabled`.
- Produces:
  - `pay_to_balance(payslip, *, paid_on, by, notes=None) -> Payslip`;
  - `salary_expenses.SOURCE`, `TITLE_MAX`, `salary_title(name, number, language)` and `post_salary(payslip)`;
  - in conftest: the `salary_on` and `issued_slip` fixtures.

- [ ] **Step 1: Write the conftest fixtures and the failing tests**

Append to `etqan/payroll/tests/conftest.py`:

```python
@pytest.fixture
def salary_on(set_features):
    """Slice B4c: paid payslips post salary expenses."""
    set_features(salary_expenses=True)


@pytest.fixture
def issued_slip(world, clock, admin):
    """Bilal's June payslip, issued: a 5000 bonus and nothing else (the
    simplest activity), with both clocks moved to 1 July 2026, 09:00 UTC."""
    adjust(world.teacher, "bonus", 5000, on=date(2026, 6, 15))
    clock.set(JULY_FIRST)
    services.generate(2026, 6)
    payslip = Payslip.objects.get(teacher=world.teacher.teacher_profile)
    return services.issue(payslip, by=admin)
```

`backend/etqan/payroll/tests/test_pay_to_balance.py`:

```python
"""Slice B4c C-1 (pay to balance) and C-9 (salary expenses)."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.finance import services as finance_services
from etqan.payroll import services
from etqan.payroll.services import Balance
from etqan.payroll.services.salary_expenses import TITLE_MAX
from etqan.payroll.services.salary_expenses import post_salary
from etqan.payroll.services.salary_expenses import salary_title
from etqan.payroll.tests.conftest import JULY_FIRST
from etqan.payroll.tests.conftest import adjust
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

PAID_ON = date(2026, 6, 30)
PAYS = [services.mark_paid, services.pay_to_balance]


def posted():
    return list(finance_services.expenses_queryset().filter(source="payroll.payslip"))


# ── Pay to balance (C-1) ─────────────────────────────────────────────────────


def test_pay_to_balance_pays_and_flags(issued_slip, admin):
    services.pay_to_balance(issued_slip, paid_on=PAID_ON, by=admin, notes="Balance")
    issued_slip.refresh_from_db()
    assert (
        issued_slip.status,
        issued_slip.paid_on,
        issued_slip.paid_by,
        issued_slip.paid_to_balance,
        issued_slip.notes,
    ) == ("paid", PAID_ON, admin, True, "Balance")


def test_the_balance_rises_by_the_net_and_mark_paid_never_feeds_it(
    world, issued_slip, admin
):
    services.pay_to_balance(issued_slip, paid_on=PAID_ON, by=admin)
    assert services.balances_of(world.teacher.id) == [Balance("USD", 5000, 5000)]


def test_mark_paid_does_not_pay_to_balance(world, issued_slip, admin):
    services.mark_paid(issued_slip, paid_on=PAID_ON, by=admin)
    issued_slip.refresh_from_db()
    assert issued_slip.paid_to_balance is False
    assert services.balances_of(world.teacher.id) == []


def test_pay_to_balance_refuses_as_mark_paid_does(issued_slip, admin):
    with pytest.raises(ValidationError) as future:
        services.pay_to_balance(issued_slip, paid_on=date(2026, 7, 2), by=admin)
    assert future.value.field == "paid_on"
    services.pay_to_balance(issued_slip, paid_on=PAID_ON, by=admin)
    with pytest.raises(ConflictError) as again:
        services.pay_to_balance(issued_slip, paid_on=PAID_ON, by=admin)
    assert again.value.code == "payroll.not_allowed_in_status"


# ── Salary expenses (C-9) ────────────────────────────────────────────────────


@pytest.mark.parametrize("pay", PAYS)
def test_paying_posts_a_salary_expense_with_expenses_off(
    issued_slip, admin, set_features, salary_on, pay
):
    set_features(expenses=False)
    pay(issued_slip, paid_on=PAID_ON, by=admin)
    (expense,) = posted()
    assert (
        expense.source_id,
        expense.type,
        expense.amount_minor,
        expense.currency,
        expense.spent_on,
    ) == (issued_slip.pk, "salaries", 5000, "USD", PAID_ON)
    # The academy's default language is Arabic unless set otherwise.
    assert expense.title == f"راتب المعلم – Bilal – إيصال {issued_slip.number}"


def test_the_title_follows_the_academys_language(issued_slip, admin, salary_on):
    academy_services.update_settings(default_language="en")
    services.mark_paid(issued_slip, paid_on=PAID_ON, by=admin)
    assert posted()[0].title == f"Teacher salary – Bilal – receipt {issued_slip.number}"


def test_titles_fall_back_to_english_and_fit():
    number = "PAY-000001"
    assert salary_title("Bilal", number, "ar") == f"راتب المعلم – Bilal – إيصال {number}"
    assert salary_title("Bilal", number, "es") == (
        f"Teacher salary – Bilal – receipt {number}"
    )
    long = salary_title("N" * 300, number, "en")
    assert len(long) == TITLE_MAX
    assert long.endswith(f" – receipt {number}")


def test_a_long_name_is_cut_to_fit_finance(world, issued_slip, admin, salary_on):
    world.teacher.full_name = "N" * 255
    world.teacher.save(update_fields=["full_name"])
    services.mark_paid(issued_slip, paid_on=PAID_ON, by=admin)
    assert len(posted()[0].title) == TITLE_MAX


def test_title_max_is_finances_title_length(world):
    """Plan R6: one character more is refused by finance's own check."""
    with pytest.raises(ValidationError) as too_long:
        finance_services.post_expense(
            source="payroll.payslip",
            source_id=999999,
            title="x" * (TITLE_MAX + 1),
            type="salaries",
            amount_minor=1,
            currency="USD",
            spent_on=PAID_ON,
        )
    assert too_long.value.field == "title"


def test_a_failing_post_rolls_the_payment_back(
    issued_slip, admin, salary_on, monkeypatch
):
    def refuse(**fields):
        raise ValidationError("No.", field="title")

    monkeypatch.setattr(finance_services, "post_expense", refuse)
    with pytest.raises(ValidationError):
        services.pay_to_balance(issued_slip, paid_on=PAID_ON, by=admin)
    issued_slip.refresh_from_db()
    assert (issued_slip.status, issued_slip.paid_on, issued_slip.paid_to_balance) == (
        "issued",
        None,
        False,
    )


def test_nothing_posts_while_the_switch_is_off(issued_slip, admin):
    services.mark_paid(issued_slip, paid_on=PAID_ON, by=admin)
    assert posted() == []


def test_a_net_of_zero_posts_nothing(world, clock, admin, salary_on):
    adjust(world.teacher, "bonus", 500, on=date(2026, 6, 15))
    adjust(world.teacher, "deduction", 500, on=date(2026, 6, 16))
    clock.set(JULY_FIRST)
    services.generate(2026, 6)
    payslip = services.issue(
        services.payslips_queryset().get(teacher__user=world.teacher), by=admin
    )
    assert payslip.net_minor == 0
    services.mark_paid(payslip, paid_on=PAID_ON, by=admin)
    assert posted() == []


def test_posting_twice_keeps_one_expense(issued_slip, admin, salary_on):
    paid = services.mark_paid(issued_slip, paid_on=PAID_ON, by=admin)
    post_salary(paid)
    assert len(posted()) == 1


def test_the_payslip_row_is_locked_before_the_expense_row(
    issued_slip, admin, salary_on
):
    with CaptureQueriesContext(connection) as ctx:
        services.mark_paid(issued_slip, paid_on=PAID_ON, by=admin)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    payslip = next(i for i, sql in enumerate(locks) if 'FROM "payroll_payslip"' in sql)
    expense = next(i for i, sql in enumerate(locks) if 'FROM "finance_expense"' in sql)
    assert payslip < expense
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_pay_to_balance.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'etqan.payroll.services.salary_expenses'`.

- [ ] **Step 3: Implement `services/salary_expenses.py`**

```python
"""Slice B4c C-9: a payslip posts itself to the academy's expenses when it
becomes paid, while `salary_expenses` is on. This happens whether or not
finance's own `expenses` switch is on (B3a A-8). Withdrawals never post, and
payslips paid while the switch was off are not back-posted."""

from etqan.academy import services as academy_services
from etqan.finance import services as finance_services
from etqan.platform import features

SOURCE = "payroll.payslip"
# Finance's `Expense.title` length. Payroll may not import finance's models;
# a test posts one character more through finance and is refused (plan R6).
TITLE_MAX = 200
TITLES = {
    "en": "Teacher salary – {name} – receipt {number}",
    "ar": "راتب المعلم – {name} – إيصال {number}",
}


def salary_title(name: str, number: str, language: str) -> str:
    """The expense's title in ``language``. Any language but Arabic and
    English falls back to English (D11/D22). The name is cut so the title
    fits finance's column."""
    template = TITLES.get(language, TITLES["en"])
    room = TITLE_MAX - len(template.format(name="", number=number))
    return template.format(name=name[:room], number=number)


def post_salary(payslip) -> None:
    """Post ``payslip``, just made paid inside the caller's transaction, as a
    `salaries` expense dated its ``paid_on``. Does nothing while the switch
    is off or for a net of 0. Idempotent by the payslip's id. An error
    propagates and rolls the payment back."""
    if not features.enabled("salary_expenses") or payslip.net_minor == 0:
        return
    language = academy_services.get_settings().default_language
    title = salary_title(payslip.teacher.user.full_name, payslip.number, language)
    finance_services.post_expense(
        source=SOURCE,
        source_id=payslip.pk,
        title=title,
        type="salaries",
        amount_minor=payslip.net_minor,
        currency=payslip.currency,
        spent_on=payslip.paid_on,
    )
```

- [ ] **Step 4: One `_pay` in `payslips.py`**

Add `from etqan.payroll.services import salary_expenses`, then replace `mark_paid` with:

```python
def _pay(
    payslip: Payslip, *, paid_on: date, by, notes: str | None, to_balance: bool
) -> Payslip:
    """Spec §4.4 and slice B4c C-1, C-9. Payment is from issued only (409
    `payroll.not_allowed_in_status`). ``paid_on`` may not be after the
    academy's today (400 on ``paid_on``). Plan R7: this is the only code that
    makes a payslip paid. The caller's transaction also posts the salary
    expense, so a failing post rolls the payment back. Locks: the payslip's
    row, then (in finance's savepoint) the expense's row."""
    locked = lock(payslip)
    _refuse_unless(locked, ISSUED)
    if paid_on > clock.today():
        raise ValidationError("A payslip can't be paid in the future.", field="paid_on")
    locked.status = PAID
    locked.paid_on = paid_on
    locked.paid_by = by
    locked.paid_to_balance = to_balance
    fields = ["status", "paid_on", "paid_by", "paid_to_balance", "updated_at"]
    if notes is not None:
        locked.notes = notes
        fields.append("notes")
    locked.save(update_fields=fields)
    salary_expenses.post_salary(locked)
    return locked


@transaction.atomic
def mark_paid(
    payslip: Payslip, *, paid_on: date, by, notes: str | None = None
) -> Payslip:
    """Spec §4.4: ``notes`` (admin-only) may say how it was paid (plan D10)."""
    return _pay(payslip, paid_on=paid_on, by=by, notes=notes, to_balance=False)


@transaction.atomic
def pay_to_balance(
    payslip: Payslip, *, paid_on: date, by, notes: str | None = None
) -> Payslip:
    """Slice B4c C-1: everything `mark_paid` does, with the net paid into the
    teacher's balance. The route checks `teacher_balance`."""
    return _pay(payslip, paid_on=paid_on, by=by, notes=notes, to_balance=True)
```

Export `pay_to_balance` from `services/__init__.py`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`, then `… exec -T django lint-imports`
Expected: PASS. Trunk's `mark_paid` tests pass unchanged. The import contracts hold: payroll reaches finance only through `etqan.finance.services`.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/payroll/services/salary_expenses.py etqan/payroll/services/payslips.py etqan/payroll/services/__init__.py etqan/payroll/tests/conftest.py etqan/payroll/tests/test_pay_to_balance.py
git -C $W/backend commit -m "feat(payroll): pay to balance and salary expenses on payment (B4c C-1, C-9)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Receipt acknowledgement

**Files:**
- Modify: `backend/etqan/payroll/services/payslips.py` (`acknowledge`)
- Modify: `backend/etqan/payroll/services/__init__.py`
- Test: `backend/etqan/payroll/tests/test_acknowledge.py` (new)

**Interfaces:**
- Consumes: `lock`, `_refuse_unless` and `issued_slip` (Task 4).
- Produces: `acknowledge(payslip, *, by) -> Payslip`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_acknowledge.py`:

```python
"""Slice B4c C-8: the payslip's teacher confirms receipt of a paid payslip,
once."""

from datetime import date

import pytest

from etqan.payroll import services
from etqan.payroll.tests.conftest import JULY_FIRST
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.scheduling.tests.conftest import make_teacher


@pytest.fixture
def paid_slip(issued_slip, admin):
    return services.mark_paid(issued_slip, paid_on=date(2026, 7, 1), by=admin)


def test_the_teacher_confirms_receipt_once(world, paid_slip):
    done = services.acknowledge(paid_slip, by=world.teacher)
    assert done.acknowledged_at == JULY_FIRST
    with pytest.raises(ConflictError) as again:
        services.acknowledge(paid_slip, by=world.teacher)
    assert again.value.code == "payroll.already_acknowledged"
    paid_slip.refresh_from_db()
    assert (paid_slip.status, paid_slip.net_minor, paid_slip.acknowledged_at) == (
        "paid",
        5000,
        JULY_FIRST,
    )


def test_a_payslip_paid_to_the_balance_is_acknowledged_too(world, issued_slip, admin):
    services.pay_to_balance(issued_slip, paid_on=date(2026, 7, 1), by=admin)
    assert services.acknowledge(issued_slip, by=world.teacher).acknowledged_at


def test_only_a_paid_payslip(world, issued_slip):
    with pytest.raises(ConflictError) as refused:
        services.acknowledge(issued_slip, by=world.teacher)
    assert refused.value.code == "payroll.not_allowed_in_status"


def test_nobody_else_acknowledges(paid_slip, admin):
    for someone in (admin, make_teacher("Maryam")):
        with pytest.raises(NotFoundError):
            services.acknowledge(paid_slip, by=someone)
    paid_slip.refresh_from_db()
    assert paid_slip.acknowledged_at is None
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_acknowledge.py`
Expected: FAIL with `AttributeError: … has no attribute 'acknowledge'`.

- [ ] **Step 3: Implement**

In `payslips.py`:

```python
@transaction.atomic
def acknowledge(payslip: Payslip, *, by) -> Payslip:
    """Slice B4c C-8: the payslip's teacher confirms receipt of a paid
    payslip.
    - A payslip that is not paid is a 409 `payroll.not_allowed_in_status`.
    - A second confirmation is a 409 `payroll.already_acknowledged`.
    - For anyone else the payslip is not found (the route also scopes a
      teacher to their own).
    It changes no amount."""
    locked = lock(payslip)
    if locked.teacher.user_id != by.pk:
        raise NotFoundError("Payslip", payslip.pk)
    _refuse_unless(locked, PAID)
    if locked.acknowledged_at is not None:
        raise ConflictError(
            "Receipt of this payslip is already confirmed.",
            code="payroll.already_acknowledged",
        )
    locked.acknowledged_at = clock.now()
    locked.save(update_fields=["acknowledged_at", "updated_at"])
    return locked
```

Export `acknowledge` from `services/__init__.py`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/services/payslips.py etqan/payroll/services/__init__.py etqan/payroll/tests/test_acknowledge.py
git -C $W/backend commit -m "feat(payroll): teacher confirms receipt of a paid payslip (B4c C-8)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Payslip routes — pay to balance, acknowledge, the row fields and the CSV

**Files:**
- Modify: `backend/etqan/payroll/api/payloads.py` (`payslip_row`)
- Modify: `backend/etqan/payroll/api/views.py` (`PayToBalanceView`, `AcknowledgeView`, `CSV_COLUMNS`)
- Modify: `backend/etqan/payroll/api/urls.py`
- Modify: `backend/etqan/payroll/tests/conftest.py` (`quick_login`, `office_impersonated`)
- Modify: `backend/etqan/payroll/tests/test_api.py` (the CSV test's header and row)
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/payroll/tests/test_api_payslip_balance.py` (new)

**Interfaces:**
- Consumes: `pay_to_balance` (Task 4) and `acknowledge` (Task 5).
- Produces:
  - `POST /api/v1/payroll/payslips/<id>/pay-to-balance/` with body `{paid_on, notes?}`;
  - `POST /api/v1/payroll/payslips/<id>/acknowledge/`;
  - payslip rows with `paid_to_balance` and `acknowledged_at`;
  - CSV columns "Paid to balance" and "Receipt confirmed at", last (R14).

- [ ] **Step 1: Write the conftest helpers and the failing tests**

Append to `etqan/payroll/tests/conftest.py`, and merge its imports: `import time`, `from rest_framework.test import APIClient` and `from etqan.platform.permissions import IMPERSONATOR_KEY`.

```python
def quick_login(admin, user):
    """An APIClient of ``admin`` signed in as ``user`` (a teacher) through
    quick login (B9b). Needs `quick_login` on. Every B4c write refuses it
    (C-10)."""
    if not user.email:  # quick login needs an account that can sign in
        user.email = f"user{user.pk}@teachers.test"
        user.save(update_fields=["email"])
    client = APIClient()
    client.force_login(admin)
    resp = client.post(f"/api/v1/people/teachers/{user.pk}/quick-login/")
    assert resp.status_code == 200, resp.content
    return client


@pytest.fixture
def office_impersonated(set_features, admin, api_for):
    """An admin's client in a session marked as opened by ``admin``. Quick
    login cannot target the office, so the mark is written directly:
    NotImpersonating reads only it (as in gateways' tests)."""
    set_features(quick_login=True)
    client = api_for("admin")
    session = client.session
    session[IMPERSONATOR_KEY] = {
        "id": admin.pk,
        "hash": admin.get_session_auth_hash(),
        "since": time.time(),
    }
    session.save()
    return client
```

`backend/etqan/payroll/tests/test_api_payslip_balance.py`:

```python
"""Slice B4c §4: pay to balance and acknowledge on payslips, the row fields,
the CSV columns, and quick-login refusals (C-10)."""

import csv
import io
from datetime import date

import pytest
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.tests.conftest import quick_login
from etqan.platform.permissions import IMPERSONATING
from etqan.scheduling.tests.conftest import make_teacher

P = "/api/v1/payroll/payslips/"
BODY = {"paid_on": "2026-07-01", "notes": "Into the balance"}


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def refused(resp):
    assert (resp.status_code, resp.json()) == (403, IMPERSONATING), resp.content


@pytest.fixture
def paid_slip(issued_slip, admin):
    return services.mark_paid(issued_slip, paid_on=date(2026, 7, 1), by=admin)


@pytest.fixture
def acknowledgement_on(set_features):
    set_features(payslip_acknowledgement=True)


# ── Pay to balance ───────────────────────────────────────────────────────────


def test_pay_to_balance_is_404_while_off(issued_slip, admin):
    resp = as_user(admin).post(f"{P}{issued_slip.pk}/pay-to-balance/", BODY, format="json")
    assert resp.status_code == 404


def test_pay_to_balance_answers_the_fresh_payslip(issued_slip, admin, balance_on):
    resp = as_user(admin).post(f"{P}{issued_slip.pk}/pay-to-balance/", BODY, format="json")
    assert resp.status_code == 200, resp.json()
    body = resp.json()
    assert (body["status"], body["paid_on"], body["notes"]) == (
        "paid",
        "2026-07-01",
        "Into the balance",
    )
    assert (body["paid_to_balance"], body["acknowledged_at"]) == (True, None)
    again = as_user(admin).post(f"{P}{issued_slip.pk}/pay-to-balance/", BODY, format="json")
    assert (again.status_code, again.json()["code"]) == (
        409,
        "payroll.not_allowed_in_status",
    )


def test_a_future_date_is_a_field_error(issued_slip, admin, balance_on):
    resp = as_user(admin).post(
        f"{P}{issued_slip.pk}/pay-to-balance/", {"paid_on": "2026-07-02"}, format="json"
    )
    assert resp.status_code == 400
    assert "paid_on" in resp.json()


def test_only_the_office_pays_to_balance(world, issued_slip, balance_on, staff_for):
    parent = identity_services.create_person("parent", full_name="Omar")
    for client in (as_user(world.teacher), as_user(world.student), as_user(parent)):
        resp = client.post(f"{P}{issued_slip.pk}/pay-to-balance/", BODY, format="json")
        assert resp.status_code == 403
    staff = staff_for("payslip.update")
    resp = staff.post(f"{P}{issued_slip.pk}/pay-to-balance/", BODY, format="json")
    assert resp.status_code == 200


def test_a_teacher_reads_the_new_fields_on_their_own_payslip(
    world, issued_slip, admin
):
    services.pay_to_balance(issued_slip, paid_on=date(2026, 7, 1), by=admin)
    body = as_user(world.teacher).get(f"{P}{issued_slip.pk}/").json()
    assert (body["paid_to_balance"], body["acknowledged_at"]) == (True, None)
    (row,) = as_user(world.teacher).get(P).json()["results"]
    assert row["paid_to_balance"] is True


def test_the_csv_ends_with_the_balance_columns(issued_slip, admin):
    services.pay_to_balance(issued_slip, paid_on=date(2026, 7, 1), by=admin)
    resp = as_user(admin).get(f"{P}?format=csv")
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0][-2:] == ["Paid to balance", "Receipt confirmed at"]
    assert rows[1][-2:] == ["yes", ""]


# ── Acknowledge ──────────────────────────────────────────────────────────────


def test_acknowledge_is_404_while_off(world, paid_slip):
    assert as_user(world.teacher).post(f"{P}{paid_slip.pk}/acknowledge/").status_code == 404


def test_the_teacher_acknowledges_once(world, paid_slip, acknowledgement_on):
    client = as_user(world.teacher)
    first = client.post(f"{P}{paid_slip.pk}/acknowledge/")
    assert first.status_code == 200, first.json()
    assert first.json()["acknowledged_at"] == "2026-07-01T09:00:00Z"
    second = client.post(f"{P}{paid_slip.pk}/acknowledge/")
    assert (second.status_code, second.json()["code"]) == (
        409,
        "payroll.already_acknowledged",
    )
    # The office sees the date.
    admin_view = as_user(paid_slip.paid_by).get(f"{P}{paid_slip.pk}/").json()
    assert admin_view["acknowledged_at"] == "2026-07-01T09:00:00Z"


def test_only_a_paid_payslip_is_acknowledged(world, issued_slip, acknowledgement_on):
    resp = as_user(world.teacher).post(f"{P}{issued_slip.pk}/acknowledge/")
    assert (resp.status_code, resp.json()["code"]) == (
        409,
        "payroll.not_allowed_in_status",
    )


def test_nobody_else_acknowledges(
    world, paid_slip, admin, acknowledgement_on, staff_for
):
    parent = identity_services.create_person("parent", full_name="Omar")
    everything = staff_for("payslip.view", "payslip.view_any", "payslip.update")
    for client in (
        as_user(admin),
        everything,
        as_user(world.student),
        as_user(parent),
    ):
        assert client.post(f"{P}{paid_slip.pk}/acknowledge/").status_code == 403
    other = as_user(make_teacher("Maryam"))
    assert other.post(f"{P}{paid_slip.pk}/acknowledge/").status_code == 404


# ── Quick login (C-10) ───────────────────────────────────────────────────────


def test_pay_to_balance_refuses_an_impersonated_session(
    issued_slip, balance_on, office_impersonated
):
    refused(
        office_impersonated.post(
            f"{P}{issued_slip.pk}/pay-to-balance/", BODY, format="json"
        )
    )


def test_acknowledge_refuses_quick_login(
    world, paid_slip, admin, set_features, acknowledgement_on
):
    set_features(quick_login=True)
    client = quick_login(admin, world.teacher)
    refused(client.post(f"{P}{paid_slip.pk}/acknowledge/"))
    assert client.get(f"{P}{paid_slip.pk}/").status_code == 200  # reads stay open
```

In `test_api.py`, `test_the_csv_is_for_admins` asserts the whole header and the whole first row. Append to the expected header, after B4a's counter labels, `"Paid to balance"` and `"Receipt confirmed at"`. Append to the expected row `"no"` and `""`.

In `test_routes.py`:
- `ROUTES`, under a `# Slice B4c.` comment: `("POST", f"/api/v1/payroll/payslips/{N}/pay-to-balance/", "payslip.update"),`
- `FEATURES`: `("POST", f"/api/v1/payroll/payslips/{N}/pay-to-balance/"): "teacher_balance",`
- `FEATURE_WORDS`: `"/pay-to-balance/": "teacher_balance",  # B4c`
- `SELF_SERVICE`:

```python
    # Phase B4, slice B4c (C-8): IsTeacher, scoped to their own payslips.
    "etqan.payroll.api.views.AcknowledgeView": (
        "the payslip's teacher states receipt (payslip_acknowledgement)"
    ),
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_api_payslip_balance.py etqan/payroll/tests/test_api.py etqan/access/tests/test_routes.py`
Expected: FAIL with 404 on both new routes and `KeyError: 'paid_to_balance'`. The route-table coverage test names the missing view.

- [ ] **Step 3: Payloads and views**

In `payloads.py` `payslip_row`, after `"updated_at"`:

```python
        # Slice B4c (C-1, C-8): visible to the teacher on their own payslips.
        "paid_to_balance": payslip.paid_to_balance,
        "acknowledged_at": payslip.acknowledged_at,
```

In `views.py`:
- import `FeatureOn` and `NotImpersonating` from `etqan.platform.permissions`;
- append to `CSV_COLUMNS`, last (after B4a's `count_*`, and anything B4b added):

```python
    # Slice B4c (plan R14). B4d appends after these.
    ("paid_to_balance", "Paid to balance"),
    ("acknowledged_at", "Receipt confirmed at"),
```

- after `MarkPaidView`, add:

```python
class PayToBalanceView(APIView):
    """Slice B4c C-1: mark paid into the teacher's balance. C-10: never in a
    quick-login session."""

    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    permission_codes = {"POST": "payslip.update"}
    feature = "teacher_balance"

    def post(self, request, pk):
        payslip = payslip_or_404(request, pk)
        body = MarkPaidInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.pay_to_balance(payslip, **body.validated_data, by=request.user)
        return detail(pk, request)


class AcknowledgeView(APIView):
    """Slice B4c C-8 (SELF_SERVICE, plan R5): only a teacher, and only for
    their own payslip (`scope_for`; others 404). Admins and staff get 403.
    C-10: never in a quick-login session."""

    permission_classes = [IsTeacher, FeatureOn, NotImpersonating]
    feature = "payslip_acknowledgement"

    def post(self, request, pk):
        services.acknowledge(payslip_or_404(request, pk), by=request.user)
        return detail(pk, request)
```

In `urls.py`, after `mark-paid`:

```python
    path(
        "payslips/<int:pk>/pay-to-balance/",
        views.PayToBalanceView.as_view(),
        name="pay-to-balance",
    ),
    path(
        "payslips/<int:pk>/acknowledge/",
        views.AcknowledgeView.as_view(),
        name="acknowledge",
    ),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/access`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/payroll/api etqan/payroll/tests/conftest.py etqan/payroll/tests/test_api.py etqan/payroll/tests/test_api_payslip_balance.py etqan/access/tests/test_routes.py
git -C $W/backend commit -m "feat(payroll): pay-to-balance and acknowledge routes, payslip fields and CSV (B4c §4)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Balance and withdrawal routes, the access resource and the route table

**Files:**
- Modify: `backend/etqan/access/registry.py`. Under `# ── phase B4 ──`, after B4a's `payroll_settings`, add `teacher_withdrawal`.
- Modify: `backend/etqan/access/tests/test_registry.py`
- Modify: `backend/etqan/payroll/scopes.py` (`withdrawals_for`)
- Modify: `backend/etqan/payroll/api/serializers.py`, `payloads.py`, `views.py`, `urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/payroll/tests/test_api_withdrawals.py` (new)

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces:
  - `GET balances/`;
  - `GET/POST withdrawals/` and `GET withdrawals/<id>/`;
  - `POST withdrawals/<id>/approve/`, `reject/`, `pay/` and `cancel/`;
  - the resource `teacher_withdrawal` (`view_any`, `create`, `update`).

  The withdrawal row is `{id, teacher, amount_minor, currency, status, notes, office_notes, requested_by, decided_by, decided_at, paid_on, paid_by, created_at, payout?: {method, details}}`. A balance row is `{currency, balance_minor, available_minor}`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/payroll/tests/test_api_withdrawals.py`:

```python
"""Slice B4c §4: the balance and withdrawal routes, the role matrix, the
teacher's own scope, quick-login refusals, query counts and cross-academy
isolation."""

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.payroll.models import WithdrawalRequest
from etqan.payroll.tests.conftest import JULY_FIRST
from etqan.payroll.tests.conftest import credit
from etqan.payroll.tests.conftest import quick_login
from etqan.payroll.tests.conftest import withdrawal
from etqan.platform.permissions import IMPERSONATING
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import until_pk_exceeds

W = "/api/v1/payroll/withdrawals/"
B = "/api/v1/payroll/balances/"


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def refused(resp):
    assert (resp.status_code, resp.json()) == (403, IMPERSONATING), resp.content


def selects(captured):
    return [q for q in captured if q["sql"].lstrip().upper().startswith("SELECT")]


@pytest.fixture
def funded(world, clock, balance_on):
    """Bilal with 5000 USD in his balance and payout details, on 1 July."""
    clock.set(JULY_FIRST)
    credit(world.teacher, 5000)
    profile = world.teacher.teacher_profile
    profile.payout_method = "wise"
    profile.payout_details = "IBAN GB00 0000"
    profile.save(update_fields=["payout_method", "payout_details"])
    return world.teacher


def test_every_route_is_404_while_off(world, admin):
    client = as_user(admin)
    assert client.get(B, {"teacher": world.teacher.id}).status_code == 404
    assert client.get(W).status_code == 404
    body = {"teacher": world.teacher.id, "amount_minor": 1, "currency": "USD"}
    assert client.post(W, body, format="json").status_code == 404


def test_a_teacher_requests_reads_and_cancels_their_own(funded):
    client = as_user(funded)
    created = client.post(
        W,
        {"teacher": 999999, "amount_minor": 2000, "currency": "usd", "notes": "Rent"},
        format="json",
    )
    assert created.status_code == 201, created.json()
    row = created.json()
    assert row["teacher"] == {"id": funded.id, "full_name": "Bilal"}
    assert (row["amount_minor"], row["currency"], row["status"], row["notes"]) == (
        2000,
        "USD",
        "under_review",
        "Rent",
    )
    assert row["requested_by"] == {"id": funded.id, "full_name": "Bilal"}
    assert row["created_at"] == "2026-07-01T09:00:00Z"
    assert "payout" not in row
    assert client.get(B, {"teacher": 999999}).json() == [
        {"currency": "USD", "balance_minor": 5000, "available_minor": 3000}
    ]
    assert [r["id"] for r in client.get(W).json()["results"]] == [row["id"]]
    cancelled = client.post(f"{W}{row['id']}/cancel/")
    assert cancelled.status_code == 200, cancelled.json()
    assert cancelled.json()["status"] == "cancelled"


def test_the_office_acts_for_any_teacher(funded, admin):
    client = as_user(admin)
    created = client.post(
        W, {"teacher": funded.id, "amount_minor": 1000, "currency": "USD"}, format="json"
    ).json()
    assert created["payout"] == {"method": "wise", "details": "IBAN GB00 0000"}
    approved = client.post(f"{W}{created['id']}/approve/").json()
    assert (approved["status"], approved["decided_by"]["id"]) == ("approved", admin.id)
    assert approved["decided_at"] == "2026-07-01T09:00:00Z"
    paid = client.post(
        f"{W}{created['id']}/pay/", {"paid_on": "2026-07-01"}, format="json"
    ).json()
    assert (paid["status"], paid["paid_on"], paid["paid_by"]["id"]) == (
        "paid",
        "2026-07-01",
        admin.id,
    )
    assert client.get(B, {"teacher": funded.id}).json() == [
        {"currency": "USD", "balance_minor": 4000, "available_minor": 4000}
    ]
    assert client.get(f"{W}{created['id']}/").json()["status"] == "paid"


def test_the_office_creates_for_an_inactive_teacher(funded, admin):
    funded.is_active = False
    funded.save(update_fields=["is_active"])
    resp = as_user(admin).post(
        W, {"teacher": funded.id, "amount_minor": 100, "currency": "USD"}, format="json"
    )
    assert resp.status_code == 201, resp.json()


def test_reject_needs_a_reason_and_the_teacher_reads_it(funded, admin):
    made = withdrawal(funded, 1000)
    client = as_user(admin)
    bare = client.post(f"{W}{made.pk}/reject/", {"office_notes": " "}, format="json")
    assert bare.status_code == 400
    assert "office_notes" in bare.json()
    done = client.post(
        f"{W}{made.pk}/reject/", {"office_notes": "Wrong IBAN"}, format="json"
    )
    assert done.json()["status"] == "rejected"
    mine = as_user(funded).get(f"{W}{made.pk}/").json()
    assert mine["office_notes"] == "Wrong IBAN"


def test_the_refusals_are_coded(funded, admin):
    client = as_user(admin)
    no_teacher = client.post(W, {"amount_minor": 1, "currency": "USD"}, format="json")
    assert no_teacher.status_code == 400
    assert "teacher" in no_teacher.json()
    other_currency = client.post(
        W, {"teacher": funded.id, "amount_minor": 1, "currency": "EGP"}, format="json"
    )
    assert other_currency.status_code == 400
    assert "currency" in other_currency.json()
    too_much = client.post(
        W, {"teacher": funded.id, "amount_minor": 5001, "currency": "USD"}, format="json"
    )
    assert (too_much.status_code, too_much.json()["code"]) == (
        409,
        "payroll.insufficient_balance",
    )
    approved = withdrawal(funded, 100, status="approved")
    early = client.post(f"{W}{approved.pk}/pay/", {"paid_on": "2026-06-30"}, format="json")
    assert early.status_code == 400
    assert "paid_on" in early.json()
    teacher_cancel = as_user(funded).post(f"{W}{approved.pk}/cancel/")
    assert (teacher_cancel.status_code, teacher_cancel.json()["code"]) == (
        409,
        "payroll.not_allowed_in_status",
    )


def test_the_office_balance_read(world, funded, admin):
    client = as_user(admin)
    missing = client.get(B)
    assert missing.status_code == 400
    assert "teacher" in missing.json()
    assert client.get(B, {"teacher": world.student.id}).status_code == 404


def test_a_teacher_reaches_only_their_own(funded, admin):
    theirs = withdrawal(funded, 100)
    maryam = make_teacher("Maryam")
    other = as_user(maryam)
    assert other.get(W).json()["results"] == []
    assert other.get(f"{W}{theirs.pk}/").status_code == 404
    assert other.post(f"{W}{theirs.pk}/cancel/").status_code == 404
    assert other.get(B).json() == []
    for action in ("approve", "reject", "pay"):
        resp = as_user(funded).post(f"{W}{theirs.pk}/{action}/", {}, format="json")
        assert resp.status_code == 403, action


def test_students_and_parents_get_403(world, funded):
    parent = identity_services.create_person("parent", full_name="Omar")
    for user in (world.student, parent):
        client = as_user(user)
        assert client.get(W).status_code == 403
        assert client.get(B).status_code == 403
        body = {"amount_minor": 1, "currency": "USD"}
        assert client.post(W, body, format="json").status_code == 403


def test_the_list_filters(funded, admin):
    first = withdrawal(funded, 100)
    second = withdrawal(funded, 200, status="paid")
    maryam = make_teacher("Maryam")
    credit(maryam, 900, currency="EGP")
    third = withdrawal(maryam, 300, currency="EGP")
    client = as_user(admin)

    def ids(**query):
        return [row["id"] for row in client.get(W, query).json()["results"]]

    assert ids(status="paid") == [second.pk]
    assert ids(currency="egp") == [third.pk]
    assert sorted(ids(teacher=funded.id)) == sorted([first.pk, second.pk])
    assert client.get(W, {"status": "void"}).status_code == 400


def test_the_list_costs_the_same_queries_for_more_rows(funded, admin):
    withdrawal(funded, 100)
    client = as_user(admin)

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            assert client.get(W).status_code == 200
        return len(selects(ctx.captured_queries))

    one = queries()
    for n in range(2):
        other = make_teacher(f"T{n}")
        credit(other, 500)
        withdrawal(other, 100)
    assert WithdrawalRequest.objects.count() == 3
    assert queries() == one


def test_another_academy_never_leaks(funded, admin, tenants):
    mine = withdrawal(funded, 100)
    ceiling = WithdrawalRequest.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        kareem = make_teacher("Kareem")
        theirs = until_pk_exceeds(
            WithdrawalRequest, ceiling, lambda: withdrawal(kareem, 100)
        )
    client = as_user(admin)
    assert [r["id"] for r in client.get(W).json()["results"]] == [mine.pk]
    assert client.get(f"{W}{theirs.pk}/").status_code == 404
    for action in ("approve", "cancel"):
        assert client.post(f"{W}{theirs.pk}/{action}/").status_code == 404
    with tenant_context(tenants.other):
        theirs.refresh_from_db()
        assert theirs.status == "under_review"


# ── Quick login (C-10) ───────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("path", "body"),
    [
        ("", {"amount_minor": 1, "currency": "USD"}),
        ("{pk}/approve/", {}),
        ("{pk}/reject/", {"office_notes": "No"}),
        ("{pk}/pay/", {"paid_on": "2026-07-01"}),
        ("{pk}/cancel/", {}),
    ],
)
def test_office_writes_refuse_an_impersonated_session(
    funded, office_impersonated, path, body
):
    made = withdrawal(funded, 100)
    data = {**body, "teacher": funded.id} if not path else body
    refused(office_impersonated.post(f"{W}{path.format(pk=made.pk)}", data, format="json"))
    assert office_impersonated.get(W).status_code == 200  # reads stay open


def test_a_teacher_quick_login_cannot_request_or_cancel(
    funded, admin, set_features
):
    set_features(quick_login=True)
    made = withdrawal(funded, 100)
    client = quick_login(admin, funded)
    refused(client.post(W, {"amount_minor": 1, "currency": "USD"}, format="json"))
    refused(client.post(f"{W}{made.pk}/cancel/"))
    assert client.get(W).status_code == 200
    assert client.get(B).status_code == 200
```

In `test_routes.py`, under `# Slice B4c.` in `ROUTES`:

```python
    ("GET", "/api/v1/payroll/balances/", "teacher_withdrawal.view_any"),
    ("GET", "/api/v1/payroll/withdrawals/", "teacher_withdrawal.view_any"),
    ("POST", "/api/v1/payroll/withdrawals/", "teacher_withdrawal.create"),
    ("GET", f"/api/v1/payroll/withdrawals/{N}/", "teacher_withdrawal.view_any"),
    ("POST", f"/api/v1/payroll/withdrawals/{N}/approve/", "teacher_withdrawal.update"),
    ("POST", f"/api/v1/payroll/withdrawals/{N}/reject/", "teacher_withdrawal.update"),
    ("POST", f"/api/v1/payroll/withdrawals/{N}/pay/", "teacher_withdrawal.update"),
    ("POST", f"/api/v1/payroll/withdrawals/{N}/cancel/", "teacher_withdrawal.update"),
```

`FEATURES`, under `# Slice B4c.`:

```python
    **dict.fromkeys(
        (
            ("GET", "/api/v1/payroll/balances/"),
            ("GET", "/api/v1/payroll/withdrawals/"),
            ("POST", "/api/v1/payroll/withdrawals/"),
            ("GET", f"/api/v1/payroll/withdrawals/{N}/"),
            ("POST", f"/api/v1/payroll/withdrawals/{N}/approve/"),
            ("POST", f"/api/v1/payroll/withdrawals/{N}/reject/"),
            ("POST", f"/api/v1/payroll/withdrawals/{N}/pay/"),
            ("POST", f"/api/v1/payroll/withdrawals/{N}/cancel/"),
        ),
        "teacher_balance",
    ),
```

`FEATURE_WORDS`: `"/payroll/balances/": "teacher_balance",  # B4c` and `"/withdrawals/": "teacher_balance",  # B4c`.

In `test_registry.py` `test_resources_carry_the_12_verbs_and_the_role_resource_6`, after the B3e lines:

```python
    # Phase B4 (slice B4c, C-6).
    assert by_code["teacher_withdrawal"].in_use == ("view_any", "create", "update")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T django pytest -q etqan/payroll/tests/test_api_withdrawals.py etqan/access`
Expected: FAIL with 404 on every route, and `KeyError: 'teacher_withdrawal'` in the registry test.

- [ ] **Step 3: The resource and the scope**

In `access/registry.py`, under `# ── phase B4 ──`, after B4a's `payroll_settings`:

```python
    # Slice B4c (C-6): TutorHamster's withdrawal requests (PAY-007).
    Resource(
        "teacher_withdrawal",
        "Teacher withdrawals",
        "طلبات سحب المعلمين",
        ("view_any", "create", "update"),
    ),
```

In `payroll/scopes.py`:

```python
def withdrawals_for(user, queryset):
    """Slice B4c C-6: the office reads every request; a teacher their own;
    everyone else none."""
    if is_office(user):
        return queryset
    if role_of(user) == "teacher":
        return queryset.filter(teacher__user=user)
    return queryset.none()
```

- [ ] **Step 4: Serializers and payloads**

In `serializers.py`, add `from etqan.payroll.models import WithdrawalRequest` and:

```python
class BalanceQueryInput(serializers.Serializer):
    # The office names the teacher (a User id); a teacher's own read ignores it.
    teacher = _id()


class WithdrawalQueryInput(serializers.Serializer):
    status = serializers.ChoiceField(
        choices=WithdrawalRequest.Status.choices, required=False
    )
    currency = serializers.CharField(required=False, max_length=3)
    teacher = _id(required=False)


class WithdrawalCreateInput(serializers.Serializer):
    # Office only: a teacher's own request is always for themselves.
    teacher = _id(required=False)
    amount_minor = serializers.IntegerField(min_value=1)
    currency = serializers.CharField(max_length=3)
    notes = serializers.CharField(required=False, allow_blank=True, default="")


class RejectInput(serializers.Serializer):
    # Blank passes here; the service refuses it on this field (C-4).
    office_notes = serializers.CharField(allow_blank=True)


class PayWithdrawalInput(serializers.Serializer):
    paid_on = serializers.DateField()
```

In `payloads.py`:

```python
def balance_row(balance) -> dict:
    return {
        "currency": balance.currency,
        "balance_minor": balance.balance_minor,
        "available_minor": balance.available_minor,
    }


def withdrawal_row(withdrawal, *, is_office: bool) -> dict:
    """Slice B4c §4. Read from `services.withdrawals_queryset()`. ``payout``
    (C-7) is the office's only, from the joined teacher row (plan R3). A
    teacher reads ``office_notes``, which is how they read a rejection's
    reason."""
    row = {
        "id": withdrawal.pk,
        "teacher": person(withdrawal.teacher.user),
        "amount_minor": withdrawal.amount_minor,
        "currency": withdrawal.currency,
        "status": withdrawal.status,
        "notes": withdrawal.notes,
        "office_notes": withdrawal.office_notes,
        "requested_by": person(withdrawal.requested_by),
        "decided_by": person(withdrawal.decided_by),
        "decided_at": withdrawal.decided_at,
        "paid_on": withdrawal.paid_on,
        "paid_by": person(withdrawal.paid_by),
        "created_at": withdrawal.created_at,
    }
    if is_office:
        row["payout"] = {
            "method": withdrawal.teacher.payout_method,
            "details": withdrawal.teacher.payout_details,
        }
    return row
```

- [ ] **Step 5: Views and urls**

In `views.py`, import:
- the serializers `BalanceQueryInput`, `PayWithdrawalInput`, `RejectInput`, `WithdrawalCreateInput` and `WithdrawalQueryInput`;
- `withdrawals_for` from `etqan.payroll.scopes`;
- `ValidationError` from `etqan.platform.exceptions`.

Then add:

```python
# ── Teacher balance and withdrawals (slice B4c) ──────────────────────────────

# C-6: the office by code; a teacher for themselves (scoped below).
OFFICE_OR_TEACHER = HasCode | IsTeacher
# C-10 (plan R4): a read stays open in a quick-login session; a write refuses.
WRITES_REFUSE_IMPERSONATION = ReadOnly | NotImpersonating


def withdrawal_or_404(request, pk):
    rows = withdrawals_for(request.user, services.withdrawals_queryset())
    return get_object_or_404(rows, pk=pk)


def withdrawal_response(pk, request, status_code=status.HTTP_200_OK) -> Response:
    """A fresh read of what a write changed."""
    row = services.withdrawals_queryset().get(pk=pk)
    return Response(
        payloads.withdrawal_row(row, is_office=_is_office(request)),
        status=status_code,
    )


class BalancesView(APIView):
    """C-2, C-11: the office reads a named teacher's balances (plan R12);
    a teacher reads their own, whatever ``?teacher=`` says."""

    permission_classes = [OFFICE_OR_TEACHER, FeatureOn]
    permission_codes = {"GET": "teacher_withdrawal.view_any"}
    feature = "teacher_balance"

    def get(self, request):
        if _is_office(request):
            query = BalanceQueryInput(data=request.query_params)
            query.is_valid(raise_exception=True)
            balances = services.balances_for_teacher(query.validated_data["teacher"])
        else:
            balances = services.balances_of(request.user.pk)
        return Response([payloads.balance_row(balance) for balance in balances])


class WithdrawalListView(generics.GenericAPIView):
    permission_classes = [OFFICE_OR_TEACHER, FeatureOn, WRITES_REFUSE_IMPERSONATION]
    permission_codes = {
        "GET": "teacher_withdrawal.view_any",
        "POST": "teacher_withdrawal.create",
    }
    feature = "teacher_balance"

    def get(self, request):
        query = WithdrawalQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        filters = dict(query.validated_data)
        is_office = _is_office(request)
        if not is_office:
            filters.pop("teacher", None)
        rows = services.filter_withdrawals(
            withdrawals_for(request.user, services.withdrawals_queryset()), **filters
        )
        page = self.paginate_queryset(rows)
        return self.get_paginated_response(
            [payloads.withdrawal_row(row, is_office=is_office) for row in page]
        )

    def post(self, request):
        body = WithdrawalCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        if not _is_office(request):
            teacher_id = request.user.pk
        elif "teacher" in data:
            teacher_id = data["teacher"]
        else:
            raise ValidationError("Choose a teacher.", field="teacher")
        made = services.create_withdrawal(
            teacher_id=teacher_id,
            amount_minor=data["amount_minor"],
            currency=data["currency"],
            notes=data["notes"],
            by=request.user,
        )
        return withdrawal_response(made.pk, request, status.HTTP_201_CREATED)


class WithdrawalDetailView(APIView):
    permission_classes = [OFFICE_OR_TEACHER, FeatureOn]
    permission_codes = {"GET": "teacher_withdrawal.view_any"}
    feature = "teacher_balance"

    def get(self, request, pk):
        return withdrawal_response(withdrawal_or_404(request, pk).pk, request)


class _OfficeDecision(APIView):
    """C-4: the office's moves; C-10: never in a quick-login session."""

    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    permission_codes = {"POST": "teacher_withdrawal.update"}
    feature = "teacher_balance"


class ApproveWithdrawalView(_OfficeDecision):
    def post(self, request, pk):
        services.approve_withdrawal(withdrawal_or_404(request, pk), by=request.user)
        return withdrawal_response(pk, request)


class RejectWithdrawalView(_OfficeDecision):
    def post(self, request, pk):
        made = withdrawal_or_404(request, pk)
        body = RejectInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.reject_withdrawal(made, by=request.user, **body.validated_data)
        return withdrawal_response(pk, request)


class PayWithdrawalView(_OfficeDecision):
    def post(self, request, pk):
        made = withdrawal_or_404(request, pk)
        body = PayWithdrawalInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.pay_withdrawal(made, by=request.user, **body.validated_data)
        return withdrawal_response(pk, request)


class CancelWithdrawalView(APIView):
    """C-4: the request's teacher while it is under review; the office also
    once it is approved."""

    permission_classes = [OFFICE_OR_TEACHER, FeatureOn, NotImpersonating]
    permission_codes = {"POST": "teacher_withdrawal.update"}
    feature = "teacher_balance"

    def post(self, request, pk):
        services.cancel_withdrawal(
            withdrawal_or_404(request, pk),
            by=request.user,
            as_office=_is_office(request),
        )
        return withdrawal_response(pk, request)
```

`urls.py` gains:

```python
    path("balances/", views.BalancesView.as_view(), name="balances"),
    path("withdrawals/", views.WithdrawalListView.as_view(), name="withdrawals"),
    path(
        "withdrawals/<int:pk>/",
        views.WithdrawalDetailView.as_view(),
        name="withdrawal",
    ),
    path(
        "withdrawals/<int:pk>/approve/",
        views.ApproveWithdrawalView.as_view(),
        name="withdrawal-approve",
    ),
    path(
        "withdrawals/<int:pk>/reject/",
        views.RejectWithdrawalView.as_view(),
        name="withdrawal-reject",
    ),
    path(
        "withdrawals/<int:pk>/pay/",
        views.PayWithdrawalView.as_view(),
        name="withdrawal-pay",
    ),
    path(
        "withdrawals/<int:pk>/cancel/",
        views.CancelWithdrawalView.as_view(),
        name="withdrawal-cancel",
    ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `… exec -T django pytest -q etqan/payroll etqan/access`, then `… exec -T django lint-imports`
Expected: PASS.
- The registry's in-use set now includes `teacher_withdrawal.*`.
- A staff account with all codes but `teacher_withdrawal.update` gets 403 on cancel: `HasCode` fails and so does `IsTeacher`.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/access/registry.py etqan/access/tests/test_registry.py etqan/access/tests/test_routes.py etqan/payroll/scopes.py etqan/payroll/api etqan/payroll/tests/test_api_withdrawals.py
git -C $W/backend commit -m "feat(payroll): balance and withdrawal routes, teacher_withdrawal resource (B4c §4)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dashboard foundations — types, API, hooks, fixtures, strings, switches

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`)
- Modify: `dashboard/src/features/payroll/schemas.ts`, `schemas.test.ts`
- Modify: `dashboard/src/features/payroll/api.ts`, `api.test.ts`
- Modify: `dashboard/src/features/payroll/queries.ts`
- Modify: `dashboard/src/test/payroll-fixtures.ts`
- Modify: `dashboard/src/locales/{en,ar}/payroll.json`, `errors.json` (the `payroll` section), `nav.json`

**Interfaces:**
- Produces:
  - the TS types `Balance`, `Withdrawal`, `WithdrawalStatus`, `WithdrawalBody` and `WithdrawalFormValues`, and the constant `WITHDRAWAL_STATUSES`;
  - `Payslip.paid_to_balance` and `Payslip.acknowledged_at`;
  - `withdrawalFormSchema`, `withdrawalProblem(balances, currency, amount)`, `rejectSchema` and `payWithdrawalSchema`;
  - `payrollApi.payToBalance`, `acknowledge`, `balances`, `withdrawals`, `createWithdrawal`, `approveWithdrawal`, `rejectWithdrawal`, `payWithdrawal` and `cancelWithdrawal`;
  - the hooks `useBalances(teacher?, {enabled})` and `useWithdrawals(params, {enabled})`;
  - the fixtures `withdrawalRow(o)` and `balanceRow(o)`.

- [ ] **Step 1: Write the failing tests**

Append to `api.test.ts`, inside `describe("payrollApi")`:

```ts
	it("calls the B4c routes", async () => {
		await payrollApi.payToBalance({ id: 71, paid_on: "2026-07-01" });
		expect(api.post).toHaveBeenLastCalledWith(
			"payroll/payslips/71/pay-to-balance/",
			{ paid_on: "2026-07-01" },
		);
		await payrollApi.acknowledge(71);
		expect(api.post).toHaveBeenLastCalledWith("payroll/payslips/71/acknowledge/");
		await payrollApi.balances({ teacher: 21 });
		expect(api.get).toHaveBeenLastCalledWith("payroll/balances/", {
			params: { teacher: "21" },
		});
		await payrollApi.withdrawals({ status: "", page: 1 });
		expect(api.get).toHaveBeenLastCalledWith("payroll/withdrawals/", {
			params: { page: "1" },
		});
		await payrollApi.createWithdrawal({
			amount_minor: 2000,
			currency: "USD",
			notes: "",
		});
		expect(api.post).toHaveBeenLastCalledWith("payroll/withdrawals/", {
			amount_minor: 2000,
			currency: "USD",
			notes: "",
		});
		await payrollApi.approveWithdrawal(101);
		expect(api.post).toHaveBeenLastCalledWith("payroll/withdrawals/101/approve/");
		await payrollApi.rejectWithdrawal({ id: 101, office_notes: "Wrong IBAN" });
		expect(api.post).toHaveBeenLastCalledWith("payroll/withdrawals/101/reject/", {
			office_notes: "Wrong IBAN",
		});
		await payrollApi.payWithdrawal({ id: 101, paid_on: "2026-07-01" });
		expect(api.post).toHaveBeenLastCalledWith("payroll/withdrawals/101/pay/", {
			paid_on: "2026-07-01",
		});
		await payrollApi.cancelWithdrawal(101);
		expect(api.post).toHaveBeenLastCalledWith("payroll/withdrawals/101/cancel/");
	});
```

Append to `schemas.test.ts`:

```ts
import { withdrawalProblem } from "./schemas";

describe("withdrawalProblem", () => {
	const balances = [
		{ currency: "USD", balance_minor: 5000, available_minor: 3000 },
		{ currency: "JPY", balance_minor: 900, available_minor: 900 },
	];

	it("takes an amount up to the available balance", () => {
		expect(withdrawalProblem(balances, "USD", "30")).toBeNull();
		expect(withdrawalProblem(balances, "JPY", "900")).toBeNull();
	});

	it("refuses more than available, a bad amount and an unknown currency", () => {
		expect(withdrawalProblem(balances, "USD", "30.01")).toEqual({
			field: "amount",
			message: "payroll.withdrawals.overAvailable",
		});
		expect(withdrawalProblem(balances, "JPY", "1.5")).toEqual({
			field: "amount",
			message: "billing.errors.amountInvalid",
		});
		expect(withdrawalProblem(balances, "EGP", "1")).toEqual({
			field: "currency",
			message: "payroll.errors.required",
		});
	});
});
```

Merge the `withdrawalProblem` import into the file's existing `./schemas` import.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/api.test.ts src/features/payroll/schemas.test.ts`
Expected: FAIL with `payrollApi.payToBalance is not a function` and `withdrawalProblem is not a function`.

- [ ] **Step 3: Implement**

`identity/schemas.ts` `FeatureCode`, after B4a's lines:

```ts
	// Phase B4, slice B4c.
	| "teacher_balance"
	| "payslip_acknowledgement"
	| "salary_expenses"
```

In `payroll/schemas.ts`, add `import { toMinor } from "@/lib/money";`. `Payslip` gains:

```ts
	// Slice B4c: paid into the teacher's balance (C-1); when the teacher
	// confirmed receipt (C-8). Both visible to the teacher.
	paid_to_balance: boolean;
	acknowledged_at: string | null;
```

Add:

```ts
export const WITHDRAWAL_STATUSES = [
	"under_review",
	"approved",
	"paid",
	"rejected",
	"cancelled",
] as const;
export type WithdrawalStatus = (typeof WITHDRAWAL_STATUSES)[number];

/** Slice B4c C-2: one currency of a teacher's balance. */
export interface Balance {
	currency: string;
	balance_minor: number;
	available_minor: number;
}

/** Slice B4c C-3. `payout` (C-7) is sent to the office only. */
export interface Withdrawal {
	id: number;
	teacher: Person;
	amount_minor: number;
	currency: string;
	status: WithdrawalStatus;
	notes: string;
	office_notes: string;
	requested_by: Person | null;
	decided_by: Person | null;
	decided_at: string | null;
	paid_on: string | null;
	paid_by: Person | null;
	created_at: string;
	payout?: { method: string; details: string };
}

// A teacher's own request never names the teacher (the server forces it).
export interface WithdrawalBody {
	teacher?: number;
	amount_minor: number;
	currency: string;
	notes?: string;
}

/** Plan R10: only "filled in" here; the amount is checked against the
 * chosen balance on submit (`withdrawalProblem`). */
export const withdrawalFormSchema = z.object({
	teacher: z.string(),
	currency: z.string().min(1, "payroll.errors.required"),
	amount: z.string().min(1, "billing.errors.required"),
	notes: z.string(),
});
export type WithdrawalFormValues = z.infer<typeof withdrawalFormSchema>;

/** Why `value` can't be requested in `currency` from `balances`, as a field
 * and an i18n key, or null: an unknown currency, an amount the currency
 * can't hold, or more than its available amount. */
export function withdrawalProblem(
	balances: Balance[],
	currency: string,
	value: string,
): { field: "currency" | "amount"; message: string } | null {
	const balance = balances.find((b) => b.currency === currency);
	if (!balance) return { field: "currency", message: "payroll.errors.required" };
	const checked = amount(balance.currency).safeParse(value);
	if (!checked.success) {
		return {
			field: "amount",
			message: checked.error.issues[0]?.message ?? "billing.errors.amountInvalid",
		};
	}
	if (toMinor(value, balance.currency) > balance.available_minor) {
		return { field: "amount", message: "payroll.withdrawals.overAvailable" };
	}
	return null;
}

export const rejectSchema = z.object({
	office_notes: z.string().trim().min(1, "payroll.withdrawals.reasonRequired"),
});
export type RejectValues = z.infer<typeof rejectSchema>;

export const payWithdrawalSchema = z.object({ paid_on: day });
export type PayWithdrawalValues = z.infer<typeof payWithdrawalSchema>;
```

`day` is declared further down the file. Move `withdrawalFormSchema`, `withdrawalProblem`, `rejectSchema` and `payWithdrawalSchema` below `const day`, next to `markPaidSchema`.

`api.ts` imports `Balance`, `Withdrawal` and `WithdrawalBody`, and adds to `payrollApi`:

```ts
	payToBalance: async ({ id, ...body }: MarkPaidBody & { id: number }) =>
		(await api.post<PayslipDetail>(`${PAYSLIPS}${id}/pay-to-balance/`, body))
			.data,
	acknowledge: async (id: number) =>
		(await api.post<PayslipDetail>(`${PAYSLIPS}${id}/acknowledge/`)).data,
	balances: async (params: QueryParams = {}) =>
		(await api.get<Balance[]>(`${P}balances/`, { params: clean(params) })).data,
	withdrawals: async (params: QueryParams) =>
		(
			await api.get<Paginated<Withdrawal>>(`${P}withdrawals/`, {
				params: clean(params),
			})
		).data,
	createWithdrawal: async (body: WithdrawalBody) =>
		(await api.post<Withdrawal>(`${P}withdrawals/`, body)).data,
	approveWithdrawal: async (id: number) =>
		(await api.post<Withdrawal>(`${P}withdrawals/${id}/approve/`)).data,
	rejectWithdrawal: async ({
		id,
		office_notes,
	}: {
		id: number;
		office_notes: string;
	}) =>
		(
			await api.post<Withdrawal>(`${P}withdrawals/${id}/reject/`, {
				office_notes,
			})
		).data,
	payWithdrawal: async ({ id, paid_on }: { id: number; paid_on: string }) =>
		(await api.post<Withdrawal>(`${P}withdrawals/${id}/pay/`, { paid_on }))
			.data,
	cancelWithdrawal: async (id: number) =>
		(await api.post<Withdrawal>(`${P}withdrawals/${id}/cancel/`)).data,
```

`queries.ts`:

```ts
/** Slice B4c: a teacher's balances. The office names the teacher (a User
 * id); a teacher's own read passes none. */
export function useBalances(
	teacher?: number,
	{ enabled = true }: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...payrollKey, "balances", teacher ?? "mine"],
		queryFn: () =>
			payrollApi.balances(teacher === undefined ? {} : { teacher }),
		enabled,
	});
}

export function useWithdrawals(
	params: QueryParams,
	{ enabled = true }: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...payrollKey, "withdrawals", params],
		queryFn: () => payrollApi.withdrawals(params),
		placeholderData: keepPreviousData,
		enabled,
	});
}
```

`payroll-fixtures.ts`:
- `payslipRow` gains `paid_to_balance: false` and `acknowledged_at: null`.
- Import `Balance` and `Withdrawal`.
- Add:

```ts
export function withdrawalRow(overrides: Partial<Withdrawal> = {}): Withdrawal {
	return {
		id: 101,
		teacher: { id: 21, full_name: "Bilal" },
		amount_minor: 2000,
		currency: "USD",
		status: "under_review",
		notes: "Rent",
		office_notes: "",
		requested_by: { id: 21, full_name: "Bilal" },
		decided_by: null,
		decided_at: null,
		paid_on: null,
		paid_by: null,
		created_at: "2026-07-01T09:00:00Z",
		payout: { method: "wise", details: "IBAN GB00 0000" },
		...overrides,
	};
}

export function balanceRow(overrides: Partial<Balance> = {}): Balance {
	return {
		currency: "USD",
		balance_minor: 5000,
		available_minor: 3000,
		...overrides,
	};
}
```

**Strings.** Every key below goes into `en/payroll.json` and `ar/payroll.json` with equal keys. `es` falls back to English per key (D22), so no `es` file changes. Add to `payroll.json`:

```json
"balance": {
	"title": "Balance",
	"ofTeacher": "The teacher's balance",
	"balance": "Balance",
	"available": "Available",
	"none": "No balance yet.",
	"loadError": "Couldn't load the balance.",
	"paidTo": "Paid to balance",
	"payAction": "Pay to balance",
	"payBody": "Add this payslip's net pay to the teacher's balance, dated the day it was paid. The teacher can then ask to withdraw it.",
	"payDone": "Payslip paid to the teacher's balance."
},
"withdrawals": {
	"status": {
		"under_review": "Under review",
		"approved": "Approved",
		"paid": "Paid",
		"rejected": "Rejected",
		"cancelled": "Cancelled"
	},
	"anyStatus": "Any status",
	"new": "New request",
	"request": "Request a withdrawal",
	"body": "Withdraw from the teacher's balance, in one of its currencies. The amount can't be more than what is available.",
	"amount": "Amount ({{currency}})",
	"send": "Send request",
	"created": "Withdrawal request sent.",
	"overAvailable": "That is more than the available balance.",
	"columns": {
		"teacher": "Teacher",
		"amount": "Amount",
		"status": "Status",
		"requested": "Requested",
		"payout": "Payout method",
		"actions": "Actions"
	},
	"noPayout": "Not set",
	"empty": "No withdrawal requests.",
	"loadError": "Couldn't load the withdrawal requests.",
	"approve": "Approve",
	"approveTitle": "Approve this request",
	"approveBody": "The amount stays reserved until the request is paid, rejected or cancelled.",
	"approved": "Request approved.",
	"reject": "Reject",
	"rejectTitle": "Reject this request",
	"rejectBody": "The teacher will see your reason.",
	"rejectSubmit": "Reject request",
	"reason": "Reason",
	"reasonRequired": "Give a reason.",
	"rejected": "Request rejected.",
	"pay": "Pay",
	"payTitle": "Pay this request",
	"payBody": "Record the date the teacher was paid. The amount leaves the balance.",
	"paySubmit": "Record payment",
	"paid": "Request paid.",
	"cancel": "Cancel request",
	"cancelTitle": "Cancel this request",
	"cancelBody": "The amount goes back to the available balance.",
	"cancelled": "Request cancelled.",
	"rejectedBecause": "Reason: {{reason}}",
	"mine": "My requests"
},
"receipt": {
	"action": "Confirm receipt",
	"title": "Confirm you received this pay",
	"body": "This tells the academy you received this payslip's pay. It can't be undone.",
	"done": "Receipt confirmed.",
	"confirmed": "Receipt confirmed"
}
```

Arabic values, in the same keys and order:
- `balance`:
  - "الرصيد"
  - "رصيد المعلم"
  - "الرصيد"
  - "المتاح"
  - "لا يوجد رصيد بعد."
  - "تعذر تحميل الرصيد."
  - "مدفوع إلى الرصيد"
  - "الدفع إلى الرصيد"
  - "أضف صافي هذا الراتب إلى رصيد المعلم بتاريخ الدفع، ويمكن للمعلم بعدها طلب سحبه."
  - "تم دفع الراتب إلى رصيد المعلم."
- `withdrawals.status`: "قيد المراجعة", "تمت الموافقة", "مدفوع", "مرفوض", "ملغى".
- `withdrawals` (the rest, in order):
  - "أي حالة"
  - "طلب جديد"
  - "طلب سحب"
  - "اسحب من رصيد المعلم بإحدى عملاته. لا يمكن أن يزيد المبلغ على المتاح."
  - "المبلغ ({{currency}})"
  - "إرسال الطلب"
  - "تم إرسال طلب السحب."
  - "المبلغ أكبر من الرصيد المتاح."
- `withdrawals.columns`: "المعلم", "المبلغ", "الحالة", "تاريخ الطلب", "طريقة الاستلام", "الإجراءات".
- `withdrawals` (continued, in order):
  - "غير محددة"
  - "لا توجد طلبات سحب."
  - "تعذر تحميل طلبات السحب."
  - "موافقة"
  - "الموافقة على هذا الطلب"
  - "يبقى المبلغ محجوزًا حتى يُدفع الطلب أو يُرفض أو يُلغى."
  - "تمت الموافقة على الطلب."
  - "رفض"
  - "رفض هذا الطلب"
  - "سيرى المعلم سبب الرفض."
  - "رفض الطلب"
  - "السبب"
  - "اكتب السبب."
  - "تم رفض الطلب."
  - "دفع"
  - "دفع هذا الطلب"
  - "سجّل تاريخ الدفع للمعلم. يُخصم المبلغ من الرصيد."
  - "تسجيل الدفع"
  - "تم دفع الطلب."
  - "إلغاء الطلب"
  - "إلغاء هذا الطلب"
  - "يعود المبلغ إلى الرصيد المتاح."
  - "تم إلغاء الطلب."
  - "السبب: {{reason}}"
  - "طلباتي"
- `receipt`:
  - "تأكيد الاستلام"
  - "أكّد أنك استلمت هذا الراتب"
  - "يُعلم هذا الأكاديمية بأنك استلمت راتب هذا الكشف. لا يمكن التراجع عنه."
  - "تم تأكيد الاستلام."
  - "تم تأكيد الاستلام"

The `errors.json` `payroll` section changes:
- en:
  - `"not_allowed_in_status": "That isn't possible in the current status."` (reworded, plan R8)
  - `"insufficient_balance": "That is more than the available balance."`
  - `"already_acknowledged": "Receipt of this payslip is already confirmed."`
- ar:
  - `"not_allowed_in_status": "هذا غير ممكن في الحالة الحالية."`
  - `"insufficient_balance": "المبلغ أكبر من الرصيد المتاح."`
  - `"already_acknowledged": "تم تأكيد استلام هذا الراتب من قبل."`

`identity.impersonating` already exists.

`nav.json` gains:
- en: `"withdrawals": "Withdrawals"` and `"myBalance": "My balance"`;
- ar: `"withdrawals": "طلبات السحب"` and `"myBalance": "رصيدي"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll src/locales`, then `… exec -T dashboard pnpm exec tsc --noEmit`
Expected: PASS. The ar/en key-equality test passes. Wherever `tsc` flags a `Payslip` literal missing the two fields, add them there.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/payroll src/test/payroll-fixtures.ts src/locales
git -C $W/dashboard commit -m "feat(payroll): B4c types, API, hooks, fixtures and strings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Office payslip actions — Pay to balance, the chip and the receipt date

**Files:**
- Modify: `dashboard/src/features/payroll/MarkPaidDialog.tsx` (`toBalance`)
- Modify: `dashboard/src/features/payroll/bits.tsx` (`PayslipStatusChip`)
- Modify: `dashboard/src/features/payroll/PayslipPage.tsx`
- Modify: `dashboard/src/features/payroll/PayslipPage.test.tsx`

**Interfaces:**
- Consumes: `payrollApi.payToBalance` and the `Payslip` fields (Task 8).
- Produces:
  - `MarkPaidDialog({payslip, toBalance?})`;
  - the "Paid to balance" chip in `PayslipStatusChip`, which shows on the page and the board;
  - the "Receipt confirmed" fact.

- [ ] **Step 1: Write the failing tests**

In `PayslipPage.test.tsx`:
- add `payToBalance: vi.fn()` and `acknowledge: vi.fn()` to the mocked `payrollApi`;
- import `adminWith` from `@/test/access-fixtures`.

Then add:

```tsx
	it("pays an issued payslip to the balance with the same date dialog", async () => {
		vi.useFakeTimers({
			now: new Date("2026-07-01T20:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		vi.mocked(payrollApi.payToBalance).mockResolvedValue(
			payslipDetail({ status: "paid", paid_to_balance: true }),
		);
		const user = userEvent.setup();
		renderPage();
		await user.click(
			await screen.findByRole("button", { name: "Pay to balance" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText(/^Paid on/)).toHaveValue("2026-07-02");
		await user.click(
			within(dialog).getByRole("button", { name: "Pay to balance" }),
		);
		await waitFor(() =>
			expect(payrollApi.payToBalance).toHaveBeenCalledWith({
				id: 71,
				paid_on: "2026-07-02",
				notes: "Bank transfer",
			}),
		);
		expect(payrollApi.markPaid).not.toHaveBeenCalled();
		expect(
			await screen.findByText("Payslip paid to the teacher's balance."),
		).toBeInTheDocument();
	});

	it("offers no Pay to balance while teacher_balance is off", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<PayslipPage payslipId="71" admin />
			</CanProvider>,
			{ extraPaths: ["/payslips/$payslipId/print"] },
		);
		expect(
			await screen.findByRole("button", { name: "Mark paid" }),
		).toBeVisible();
		expect(screen.queryByRole("button", { name: "Pay to balance" })).toBeNull();
	});

	it("shows Paid to balance and when the teacher confirmed receipt", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({
				status: "paid",
				paid_on: "2026-07-02",
				paid_to_balance: true,
				// 01:00 UTC on 3 July is 10:00 in the academy's Tokyo.
				acknowledged_at: "2026-07-03T01:00:00Z",
			}),
		);
		renderPage();
		expect(await screen.findByText("Paid to balance")).toBeInTheDocument();
		expect(screen.getByText("Receipt confirmed")).toBeInTheDocument();
		expect(screen.getByText("Jul 3, 2026")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Pay to balance" })).toBeNull();
	});

	it("reads Pay to balance in Arabic", async () => {
		await i18n.changeLanguage("ar");
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		renderPage();
		expect(
			await screen.findByRole("button", { name: "الدفع إلى الرصيد" }),
		).toBeVisible();
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/PayslipPage.test.tsx`
Expected: FAIL. There is no "Pay to balance" button yet.

- [ ] **Step 3: Implement**

`MarkPaidDialog.tsx`: the signature becomes `MarkPaidDialog({ payslip, toBalance = false }: { payslip: Payslip; toBalance?: boolean })`. Make these changes:

```tsx
	const pay = usePayrollMutation(
		toBalance ? payrollApi.payToBalance : payrollApi.markPaid,
	);
	const action = t(toBalance ? "payroll.balance.payAction" : "payroll.paid.action");
	const prefix = toBalance ? "balance" : "paid";
```

- Replace `markPaid.mutateAsync` with `pay.mutateAsync`.
- The trigger, the title and the submit button read `{action}`.
- The description is `t(toBalance ? "payroll.balance.payBody" : "payroll.paid.body")`.
- The toast is `t(toBalance ? "payroll.balance.payDone" : "payroll.paid.done")`.
- The field ids become `${prefix}-paid_on` and `${prefix}-notes`.
- Update the docstring to name slice B4c C-1.

`bits.tsx` `PayslipStatusChip`: the prop type becomes `Pick<Payslip, "status" | "missing_rate"> & Partial<Pick<Payslip, "paid_to_balance">>`. After the status chip:

```tsx
			{payslip.status === "paid" && payslip.paid_to_balance ? (
				<StatusChip tone="neutral">{t("payroll.balance.paidTo")}</StatusChip>
			) : null}
```

`PayslipPage.tsx`:
- import `useHasFeature` from `@/features/identity/permissions`.
- In `Actions`, add `const hasFeature = useHasFeature();`, and after the `MarkPaidDialog` line:

```tsx
			{writes && payslip.status === "issued" && hasFeature("teacher_balance") ? (
				<MarkPaidDialog payslip={payslip} toBalance />
			) : null}
```

- Add a fact component and render `<ReceiptFact payslip={payslip} />` after the "Paid on" fact, for admins and teachers alike:

```tsx
/** Slice B4c C-8: when the teacher confirmed receipt, on the academy's
 * calendar. */
function ReceiptFact({ payslip }: { payslip: PayslipDetail }) {
	const { t, i18n } = useTranslation();
	const { data: academy } = useAcademySettings();
	if (!payslip.acknowledged_at || !academy) return null;
	return (
		<Fact label={t("payroll.receipt.confirmed")}>
			{dayIn(new Date(payslip.acknowledged_at), academy.timezone, i18n.language)}
		</Fact>
	);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`, then `tsc --noEmit`
Expected: PASS. The trunk "Mark paid" tests pass unchanged: their `exact` names never match "Pay to balance".

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll
git -C $W/dashboard commit -m "feat(payroll): pay to balance on the payslip page, paid-to-balance chip, receipt date (B4c §5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The office withdrawals page

**Files:**
- Create: `dashboard/src/features/payroll/Balances.tsx` (`BalanceCards`)
- Create: `dashboard/src/features/payroll/WithdrawalDialog.tsx`
- Create: `dashboard/src/features/payroll/WithdrawalActions.tsx` (`WithdrawalActions`, `RejectDialog`, `PayWithdrawalDialog`)
- Create: `dashboard/src/features/payroll/WithdrawalsPage.tsx`, `WithdrawalsPage.test.tsx`
- Modify: `dashboard/src/features/payroll/bits.tsx` (`WithdrawalStatusChip`)
- Modify: `dashboard/src/features/payroll/index.ts`
- Create: `dashboard/src/routes/_authed/payroll.withdrawals.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `nav.test.ts`
- Modify: `dashboard/src/routes/permissions.test.ts`
- Generated: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: Task 8's API and hooks; `usePeople` (people); `useCan`.
- Produces:
  - `BalanceCards({balances})`, a list labelled "Balance";
  - `WithdrawalDialog({teachers?})`: office mode when `teachers` is given, teacher mode otherwise;
  - `WithdrawalActions({withdrawal})`;
  - `WithdrawalStatusChip({status})`;
  - `WithdrawalsPage`, and the route `/payroll/withdrawals` (`staticData: { permission: "teacher_withdrawal.view_any", feature: "teacher_balance" }`).

- [ ] **Step 1: Write the failing test**

`WithdrawalsPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { balanceRow, withdrawalRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { WithdrawalsPage } from "./WithdrawalsPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			withdrawals: vi.fn(),
			balances: vi.fn(),
			createWithdrawal: vi.fn(),
			approveWithdrawal: vi.fn(),
			rejectWithdrawal: vi.fn(),
			payWithdrawal: vi.fn(),
			cancelWithdrawal: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const row = (name: string) =>
	screen.getByRole("row", { name: new RegExp(name) });

describe("WithdrawalsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				{ id: 21, user: { full_name: "Bilal" }, profile: { pay_currency: "USD" } },
			]) as never,
		);
		vi.mocked(payrollApi.withdrawals).mockResolvedValue(
			page([
				withdrawalRow(),
				withdrawalRow({
					id: 102,
					teacher: { id: 22, full_name: "Maryam" },
					status: "approved",
					payout: { method: "", details: "" },
				}),
			]),
		);
		vi.mocked(payrollApi.balances).mockResolvedValue([balanceRow()]);
		vi.mocked(payrollApi.approveWithdrawal).mockResolvedValue(
			withdrawalRow({ status: "approved" }),
		);
		vi.mocked(payrollApi.rejectWithdrawal).mockResolvedValue(
			withdrawalRow({ status: "rejected" }),
		);
		vi.mocked(payrollApi.payWithdrawal).mockResolvedValue(
			withdrawalRow({ id: 102, status: "paid" }),
		);
		vi.mocked(payrollApi.cancelWithdrawal).mockResolvedValue(
			withdrawalRow({ status: "cancelled" }),
		);
		vi.mocked(payrollApi.createWithdrawal).mockResolvedValue(withdrawalRow());
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("lists requests with amount, status, date and payout, filtered by status", async () => {
		const user = userEvent.setup();
		renderWithRouter(<WithdrawalsPage />);
		await screen.findByRole("row", { name: /Bilal/ });
		const bilal = row("Bilal");
		expect(within(bilal).getByText("$20.00")).toBeInTheDocument();
		expect(within(bilal).getByText("Under review")).toBeInTheDocument();
		expect(within(bilal).getByText("Jul 1, 2026")).toBeInTheDocument();
		expect(within(bilal).getByText("Wise")).toBeInTheDocument();
		expect(within(row("Maryam")).getByText("Not set")).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Status"), "approved");
		await waitFor(() =>
			expect(vi.mocked(payrollApi.withdrawals).mock.calls.at(-1)?.[0]).toEqual({
				page: 1,
				status: "approved",
			}),
		);
	});

	it("shows the picked teacher's balances above the list", async () => {
		const user = userEvent.setup();
		renderWithRouter(<WithdrawalsPage />);
		await screen.findByRole("row", { name: /Bilal/ });
		expect(payrollApi.balances).not.toHaveBeenCalled();
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		const balances = await screen.findByRole("list", { name: "Balance" });
		expect(within(balances).getByText("$50.00")).toBeInTheDocument();
		expect(within(balances).getByText("$30.00")).toBeInTheDocument();
		expect(payrollApi.balances).toHaveBeenCalledWith({ teacher: 21 });
	});

	it("approves, rejects with a reason, pays and cancels", async () => {
		const user = userEvent.setup();
		renderWithRouter(<WithdrawalsPage />);
		await screen.findByRole("row", { name: /Bilal/ });

		await user.click(within(row("Bilal")).getByRole("button", { name: "Approve" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Approve this request",
			}),
		);
		await waitFor(() =>
			expect(payrollApi.approveWithdrawal).toHaveBeenCalledWith(101),
		);

		await user.click(within(row("Bilal")).getByRole("button", { name: "Reject" }));
		const reject = screen.getByRole("dialog");
		await user.click(within(reject).getByRole("button", { name: "Reject request" }));
		expect(await within(reject).findByText("Give a reason.")).toBeInTheDocument();
		await user.type(within(reject).getByLabelText(/^Reason/), "Wrong IBAN");
		await user.click(within(reject).getByRole("button", { name: "Reject request" }));
		await waitFor(() =>
			expect(payrollApi.rejectWithdrawal).toHaveBeenCalledWith({
				id: 101,
				office_notes: "Wrong IBAN",
			}),
		);

		await user.click(within(row("Maryam")).getByRole("button", { name: "Pay" }));
		const pay = screen.getByRole("dialog");
		await user.click(within(pay).getByRole("button", { name: "Record payment" }));
		await waitFor(() =>
			expect(payrollApi.payWithdrawal).toHaveBeenCalledWith({
				id: 102,
				paid_on: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
			}),
		);

		await user.click(
			within(row("Bilal")).getByRole("button", { name: "Cancel request" }),
		);
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Cancel this request",
			}),
		);
		await waitFor(() =>
			expect(payrollApi.cancelWithdrawal).toHaveBeenCalledWith(101),
		);
	});

	it("translates a refusal", async () => {
		vi.mocked(payrollApi.approveWithdrawal).mockRejectedValue(
			new AxiosError("Refused", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "payroll.not_allowed_in_status" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<WithdrawalsPage />);
		await screen.findByRole("row", { name: /Bilal/ });
		await user.click(within(row("Bilal")).getByRole("button", { name: "Approve" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Approve this request",
			}),
		);
		expect(
			await screen.findByText("That isn't possible in the current status."),
		).toBeInTheDocument();
	});

	it("makes a request for a teacher, no more than available", async () => {
		const user = userEvent.setup();
		renderWithRouter(<WithdrawalsPage />);
		await screen.findByRole("row", { name: /Bilal/ });
		await user.click(screen.getByRole("button", { name: "New request" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Currency/)).toHaveValue("USD"),
		);
		await user.type(within(dialog).getByLabelText(/^Amount/), "40");
		await user.click(within(dialog).getByRole("button", { name: "Send request" }));
		expect(
			await within(dialog).findByText("That is more than the available balance."),
		).toBeInTheDocument();
		await user.clear(within(dialog).getByLabelText(/^Amount/));
		await user.type(within(dialog).getByLabelText(/^Amount/), "25.5");
		await user.click(within(dialog).getByRole("button", { name: "Send request" }));
		await waitFor(() =>
			expect(payrollApi.createWithdrawal).toHaveBeenCalledWith({
				teacher: 21,
				amount_minor: 2550,
				currency: "USD",
				notes: "",
			}),
		);
	});

	it("is read-only for a staff account that can only view", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("teacher_withdrawal.view_any")}>
				<WithdrawalsPage />
			</CanProvider>,
		);
		await screen.findByRole("row", { name: /Bilal/ });
		expect(screen.queryByRole("button", { name: "New request" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
		expect(screen.queryByLabelText("Teacher")).toBeNull();
		expect(peopleApi.list).not.toHaveBeenCalled();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<WithdrawalsPage />);
		expect(
			await screen.findByRole("columnheader", { name: "طريقة الاستلام" }),
		).toBeInTheDocument();
		expect(screen.getAllByText("قيد المراجعة").length).toBeGreaterThan(0);
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll/WithdrawalsPage.test.tsx`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement**

`bits.tsx`:

```tsx
const WITHDRAWAL_TONE: Record<WithdrawalStatus, "live" | "neutral" | "warning"> = {
	under_review: "neutral",
	approved: "neutral",
	paid: "live",
	rejected: "warning",
	cancelled: "neutral",
};

/** Slice B4c C-4: a withdrawal request's status. */
export function WithdrawalStatusChip({ status }: { status: WithdrawalStatus }) {
	const { t } = useTranslation();
	return (
		<StatusChip tone={WITHDRAWAL_TONE[status]}>
			{t(`payroll.withdrawals.status.${status}`)}
		</StatusChip>
	);
}
```

`Balances.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import { Card, CardContent } from "@/ui";
import type { Balance } from "./schemas";

/** Slice B4c C-2, C-11: a teacher's balance in each currency, read-only. */
export function BalanceCards({ balances }: { balances: Balance[] }) {
	const { t } = useTranslation();
	if (balances.length === 0) {
		return (
			<p className="text-sm text-muted-foreground">{t("payroll.balance.none")}</p>
		);
	}
	return (
		<ul
			aria-label={t("payroll.balance.title")}
			className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
		>
			{balances.map((balance) => (
				<li key={balance.currency}>
					<Card>
						<CardContent className="flex flex-col gap-1">
							<span className="text-sm text-muted-foreground" dir="ltr">
								{balance.currency}
							</span>
							<span>
								{t("payroll.balance.balance")}:{" "}
								<Money minor={balance.balance_minor} currency={balance.currency} />
							</span>
							<span className="text-sm">
								{t("payroll.balance.available")}:{" "}
								<Money
									minor={balance.available_minor}
									currency={balance.currency}
								/>
							</span>
						</CardContent>
					</Card>
				</li>
			))}
		</ul>
	);
}
```

`WithdrawalDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import type { Person as PeoplePerson, TeacherProfile } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMinor } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { useBalances, usePayrollMutation } from "./queries";
import {
	type WithdrawalFormValues,
	withdrawalFormSchema,
	withdrawalProblem,
} from "./schemas";

/** Slice B4c §5. The office's "New request" (``teachers`` given: pick the
 * teacher first, then that teacher's balances load) or a teacher's "Request
 * a withdrawal" (their own balances). The amount may be no more than the
 * chosen currency's available amount (plan R10); the server decides again
 * under its lock. */
export function WithdrawalDialog({
	teachers,
}: {
	teachers?: PeoplePerson<TeacherProfile>[];
}) {
	const office = teachers !== undefined;
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const create = usePayrollMutation(payrollApi.createWithdrawal);
	const {
		register,
		handleSubmit,
		setError,
		setValue,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<WithdrawalFormValues>({
		resolver: zodResolver(withdrawalFormSchema),
		defaultValues: { teacher: "", currency: "", amount: "", notes: "" },
	});
	const teacher = watch("teacher");
	const currency = watch("currency");
	const { data: balances = [] } = useBalances(
		office && teacher ? Number(teacher) : undefined,
		{ enabled: open && (!office || teacher !== "") },
	);
	useEffect(() => {
		if (!balances.some((b) => b.currency === currency)) {
			setValue("currency", balances[0]?.currency ?? "");
		}
	}, [balances, currency, setValue]);
	const chosen = balances.find((b) => b.currency === currency);
	const label = t(
		office ? "payroll.withdrawals.new" : "payroll.withdrawals.request",
	);

	async function onSubmit(values: WithdrawalFormValues) {
		if (office && !values.teacher) {
			setError("teacher", { message: "payroll.errors.required" });
			return;
		}
		const problem = withdrawalProblem(balances, values.currency, values.amount);
		if (problem) {
			setError(problem.field, { message: problem.message });
			return;
		}
		try {
			await create.mutateAsync({
				...(office ? { teacher: Number(values.teacher) } : {}),
				amount_minor: toMinor(values.amount, values.currency),
				currency: values.currency,
				notes: values.notes,
			});
			setOpen(false);
			reset();
			toast({
				description: t("payroll.withdrawals.created"),
				variant: "success",
			});
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{label}</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{label}</DialogTitle>
				<DialogDescription>{t("payroll.withdrawals.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					{office ? (
						<Field
							id="withdrawal-teacher"
							label={t("payroll.columns.teacher")}
							error={fieldError(errors.teacher?.message)}
							required
						>
							<Select {...register("teacher")}>
								<option value="">{t("payroll.adjustments.chooseTeacher")}</option>
								{teachers.map((person) => (
									<option key={person.id} value={person.id}>
										{person.user.full_name}
									</option>
								))}
							</Select>
						</Field>
					) : null}
					<Field
						id="withdrawal-currency"
						label={t("payroll.columns.currency")}
						error={fieldError(errors.currency?.message)}
						required
					>
						<Select dir="ltr" {...register("currency")}>
							{balances.length === 0 ? (
								<option value="">{t("payroll.balance.none")}</option>
							) : null}
							{balances.map((balance) => (
								<option key={balance.currency} value={balance.currency}>
									{balance.currency}
								</option>
							))}
						</Select>
					</Field>
					<Field
						id="withdrawal-amount"
						label={t("payroll.withdrawals.amount", {
							currency: chosen?.currency ?? "",
						})}
						error={fieldError(errors.amount?.message)}
						required
					>
						<Input inputMode="decimal" dir="ltr" {...register("amount")} />
					</Field>
					{chosen ? (
						<p className="text-sm text-muted-foreground">
							{t("payroll.balance.available")}:{" "}
							<Money minor={chosen.available_minor} currency={chosen.currency} />
						</p>
					) : null}
					<Field
						id="withdrawal-notes"
						label={t("people.field.notes")}
						error={fieldError(errors.notes?.message)}
					>
						<Textarea rows={2} {...register("notes")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("payroll.withdrawals.send")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`applyServerErrors` maps a 409 `payroll.insufficient_balance` to `errors.root.server` with its code, and `fieldError` translates it. Read `src/lib/form-errors.ts` once to confirm that a coded 409 lands on `root.server`. If it lands elsewhere, show `errorText(error, t)` in a toast instead.

`WithdrawalActions.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { useAcademySettings } from "@/features/academy/queries";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors, errorText } from "@/lib/form-errors";
import { todayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { usePayrollMutation } from "./queries";
import {
	type PayWithdrawalValues,
	payWithdrawalSchema,
	type RejectValues,
	rejectSchema,
	type Withdrawal,
} from "./schemas";

function useToasts() {
	const { t } = useTranslation();
	return (done: string) => ({
		onSuccess: () => toast({ description: t(done), variant: "success" }),
		onError: (error: unknown) =>
			toast({ description: errorText(error, t), variant: "destructive" }),
	});
}

/** Slice B4c C-4: reject, with the reason the teacher will read. */
export function RejectDialog({ withdrawal }: { withdrawal: Withdrawal }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const reject = usePayrollMutation(payrollApi.rejectWithdrawal);
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<RejectValues>({
		resolver: zodResolver(rejectSchema),
		defaultValues: { office_notes: "" },
	});

	async function onSubmit(values: RejectValues) {
		try {
			await reject.mutateAsync({ id: withdrawal.id, ...values });
			setOpen(false);
			toast({ description: t("payroll.withdrawals.rejected"), variant: "success" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("payroll.withdrawals.reject")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("payroll.withdrawals.rejectTitle")}</DialogTitle>
				<DialogDescription>{t("payroll.withdrawals.rejectBody")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id={`reject-${withdrawal.id}`}
						label={t("payroll.withdrawals.reason")}
						error={fieldError(errors.office_notes?.message)}
						required
					>
						<Textarea rows={3} {...register("office_notes")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("payroll.withdrawals.rejectSubmit")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** Slice B4c C-4: pay an approved request, dated between the day it was
 * made and the academy's today (the server checks both, 400 on `paid_on`). */
export function PayWithdrawalDialog({ withdrawal }: { withdrawal: Withdrawal }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const pay = usePayrollMutation(payrollApi.payWithdrawal);
	const today = academy ? todayIn(academy.timezone) : "";
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<PayWithdrawalValues>({
		resolver: zodResolver(payWithdrawalSchema),
		values: { paid_on: today },
	});

	async function onSubmit(values: PayWithdrawalValues) {
		try {
			await pay.mutateAsync({ id: withdrawal.id, ...values });
			setOpen(false);
			toast({ description: t("payroll.withdrawals.paid"), variant: "success" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{t("payroll.withdrawals.pay")}</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("payroll.withdrawals.payTitle")}</DialogTitle>
				<DialogDescription>{t("payroll.withdrawals.payBody")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id={`pay-${withdrawal.id}`}
						label={t("payroll.columns.paidOn")}
						error={fieldError(errors.paid_on?.message)}
						required
					>
						<Input
							type="date"
							dir="ltr"
							min={
								academy
									? todayIn(academy.timezone, new Date(withdrawal.created_at))
									: undefined
							}
							max={today || undefined}
							{...register("paid_on")}
						/>
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("payroll.withdrawals.paySubmit")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** Slice B4c C-4, the office's moves on an open request: approve (under
 * review), pay (approved), reject and cancel (either). */
export function WithdrawalActions({ withdrawal }: { withdrawal: Withdrawal }) {
	const { t } = useTranslation();
	const toasts = useToasts();
	const approve = usePayrollMutation(payrollApi.approveWithdrawal);
	const cancel = usePayrollMutation(payrollApi.cancelWithdrawal);
	if (withdrawal.status !== "under_review" && withdrawal.status !== "approved") {
		return null;
	}
	return (
		<div className="flex flex-wrap gap-2">
			{withdrawal.status === "under_review" ? (
				<Confirm
					action={t("payroll.withdrawals.approve")}
					title={t("payroll.withdrawals.approveTitle")}
					body={t("payroll.withdrawals.approveBody")}
					onConfirm={() =>
						approve.mutate(withdrawal.id, toasts("payroll.withdrawals.approved"))
					}
				/>
			) : (
				<PayWithdrawalDialog withdrawal={withdrawal} />
			)}
			<RejectDialog withdrawal={withdrawal} />
			<Confirm
				action={t("payroll.withdrawals.cancel")}
				title={t("payroll.withdrawals.cancelTitle")}
				body={t("payroll.withdrawals.cancelBody")}
				onConfirm={() =>
					cancel.mutate(withdrawal.id, toasts("payroll.withdrawals.cancelled"))
				}
			/>
		</div>
	);
}
```

`WithdrawalsPage.tsx`:

```tsx
import { ArrowDownToLine } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { Money } from "@/features/billing";
import { useCan } from "@/features/identity/permissions";
import { type TeacherProfile, usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { dayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Select,
	Spinner,
} from "@/ui";
import { BalanceCards } from "./Balances";
import { WithdrawalStatusChip } from "./bits";
import { useBalances, useWithdrawals } from "./queries";
import { WITHDRAWAL_STATUSES } from "./schemas";
import { WithdrawalActions } from "./WithdrawalActions";
import { WithdrawalDialog } from "./WithdrawalDialog";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const COLUMNS = [
	"teacher",
	"amount",
	"status",
	"requested",
	"payout",
	"actions",
] as const;

/** Slice B4c §5, the office's withdrawal requests. Filters by status and
 * teacher. With a teacher picked, that teacher's balances show above the
 * list (C-11). The row actions need `teacher_withdrawal.update`. "New
 * request" needs `teacher_withdrawal.create` and `teacher.view_any`, because
 * its picker lists the teachers. */
export function WithdrawalsPage() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { data: academy } = useAcademySettings();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const { data, isPending, isError } = useWithdrawals(params);
	const listTeachers = can("teacher.view_any");
	const { data: teachers } = usePeople<TeacherProfile>(
		"teachers",
		{ page_size: 100 },
		{ enabled: listTeachers },
	);
	const teacher = params.teacher ? Number(params.teacher) : undefined;
	const { data: balances } = useBalances(teacher, {
		enabled: teacher !== undefined,
	});
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) =>
		setParams({ ...params, page: 1, ...patch });
	const writes = can("teacher_withdrawal.update");

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				{listTeachers ? (
					<Select
						aria-label={t("payroll.columns.teacher")}
						className="w-auto"
						value={String(params.teacher ?? "")}
						onChange={(e) => update({ teacher: e.target.value })}
					>
						<option value="">{t("payroll.list.anyTeacher")}</option>
						{teachers?.results.map((person) => (
							<option key={person.id} value={person.id}>
								{person.user.full_name}
							</option>
						))}
					</Select>
				) : null}
				<Select
					aria-label={t("payroll.columns.status")}
					className="w-auto"
					value={String(params.status ?? "")}
					onChange={(e) => update({ status: e.target.value })}
				>
					<option value="">{t("payroll.withdrawals.anyStatus")}</option>
					{WITHDRAWAL_STATUSES.map((status) => (
						<option key={status} value={status}>
							{t(`payroll.withdrawals.status.${status}`)}
						</option>
					))}
				</Select>
				{can("teacher_withdrawal.create") && listTeachers ? (
					<WithdrawalDialog teachers={teachers?.results ?? []} />
				) : null}
			</div>
			{teacher !== undefined && balances ? (
				<section aria-label={t("payroll.balance.ofTeacher")}>
					<BalanceCards balances={balances} />
				</section>
			) : null}
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("payroll.withdrawals.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={ArrowDownToLine}
							title={t("payroll.withdrawals.empty")}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{COLUMNS.map((key) => (
									<th key={key} scope="col" className="p-3 text-start font-medium">
										{t(`payroll.withdrawals.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((row) => (
								<tr key={row.id} className="border-t border-border">
									<td className="p-3">{row.teacher.full_name}</td>
									<td className="p-3">
										<Money minor={row.amount_minor} currency={row.currency} />
									</td>
									<td className="p-3">
										<WithdrawalStatusChip status={row.status} />
									</td>
									<td className="p-3">
										{academy
											? dayIn(
													new Date(row.created_at),
													academy.timezone,
													i18n.language,
												)
											: null}
									</td>
									<td className="p-3">
										{row.payout?.method ? (
											<span className="flex flex-col">
												<span>{t(`people.payout.${row.payout.method}`)}</span>
												<span className="text-xs text-muted-foreground" dir="ltr">
													{row.payout.details}
												</span>
											</span>
										) : (
											t("payroll.withdrawals.noPayout")
										)}
									</td>
									<td className="p-3">
										{writes ? <WithdrawalActions withdrawal={row} /> : null}
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager page={page} pages={pages} onChange={(p) => setParams({ ...params, page: p })} />
		</div>
	);
}
```

`index.ts` exports `BalanceCards`, `WithdrawalDialog`, `WithdrawalsPage` and `WithdrawalStatusChip` (alongside `PayslipStatusChip` from `./bits`).

The route `payroll.withdrawals.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { WithdrawalsPage } from "@/features/payroll";
import { PageHeader } from "@/ui";

// Slice B4c §5: the office's withdrawal requests.
export const Route = createFileRoute("/_authed/payroll/withdrawals")({
	staticData: {
		permission: "teacher_withdrawal.view_any",
		feature: "teacher_balance",
	},
	component: function WithdrawalsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.withdrawals"));
		return (
			<>
				<PageHeader title={t("nav.withdrawals")} />
				<WithdrawalsPage />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B4 ──`, after B4a's item. Add `ArrowDownToLine` to the `lucide-react` import.

```ts
	// Slice B4c: the office's withdrawal requests.
	office(
		"/payroll/withdrawals",
		"nav.withdrawals",
		ArrowDownToLine,
		"payroll",
		"teacher_withdrawal.view_any",
		"teacher_balance",
	),
```

Update `nav.test.ts`:
- In `NAV_ITEMS`' order, add `"/payroll/withdrawals"` right after B4a's `"/payroll/settings"`, under a `// B4c` comment.
- In "names a feature on exactly the items…", add `"/payroll/withdrawals": "teacher_balance"`.
- In "groups consecutive items", `groups[3]` gains `"nav.withdrawals"` after B4a's `"nav.payrollSettings"`.

In `permissions.test.ts`, add `"/_authed/payroll/withdrawals": "teacher_balance"` under a `// Slice B4c` comment, and insert `payroll\/withdrawals|` into `FEATURE_WORDS`.

- [ ] **Step 4: Regenerate the route tree and run the tests**

Run: `… exec -T dashboard pnpm exec vite build`, then `… exec -T dashboard pnpm exec vitest run src/features/payroll src/features/shell src/routes`, then `tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll src/features/shell src/routes src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(payroll): office withdrawals page with teacher balances (B4c §5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: The teacher's My balance page and Confirm receipt

**Files:**
- Create: `dashboard/src/features/payroll/MyBalance.tsx`, `MyBalance.test.tsx`
- Create: `dashboard/src/features/payroll/ConfirmReceipt.tsx`
- Modify: `dashboard/src/features/payroll/PayslipPage.tsx`, `PayslipPage.test.tsx`
- Modify: `dashboard/src/features/payroll/TeacherPayslips.tsx`, `TeacherPayslips.test.tsx`
- Modify: `dashboard/src/features/payroll/index.ts`
- Create: `dashboard/src/routes/_authed/teaching.balance.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `nav.test.ts`
- Modify: `dashboard/src/routes/permissions.test.ts`
- Generated: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: `BalanceCards`, `WithdrawalDialog` and `WithdrawalStatusChip` (Task 10); `payrollApi.acknowledge` and `cancelWithdrawal` (Task 8).
- Produces:
  - `MyBalance`, and the route `/teaching/balance` (`staticData: { feature: "teacher_balance" }`);
  - `ConfirmReceipt({payslip})`.

- [ ] **Step 1: Write the failing tests**

`MyBalance.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import i18n from "@/lib/i18n";
import { balanceRow, withdrawalRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { MyBalance } from "./MyBalance";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			balances: vi.fn(),
			withdrawals: vi.fn(),
			createWithdrawal: vi.fn(),
			cancelWithdrawal: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const mine = { payout: undefined };

describe("MyBalance", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(payrollApi.balances).mockResolvedValue([balanceRow()]);
		vi.mocked(payrollApi.withdrawals).mockResolvedValue(
			page([
				withdrawalRow(mine),
				withdrawalRow({
					...mine,
					id: 103,
					status: "rejected",
					amount_minor: 1000,
					office_notes: "Wrong IBAN",
				}),
			]),
		);
		vi.mocked(payrollApi.createWithdrawal).mockResolvedValue(withdrawalRow(mine));
		vi.mocked(payrollApi.cancelWithdrawal).mockResolvedValue(
			withdrawalRow({ ...mine, status: "cancelled" }),
		);
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("shows the balance and the requests, with a rejection's reason", async () => {
		renderWithRouter(<MyBalance />);
		const balances = await screen.findByRole("list", { name: "Balance" });
		expect(within(balances).getByText("$50.00")).toBeInTheDocument();
		expect(within(balances).getByText("$30.00")).toBeInTheDocument();
		expect(payrollApi.balances).toHaveBeenCalledWith({});
		expect(await screen.findByText("Reason: Wrong IBAN")).toBeInTheDocument();
		expect(screen.getByText("Under review")).toBeInTheDocument();
	});

	it("requests a withdrawal for themselves, never naming a teacher", async () => {
		const user = userEvent.setup();
		renderWithRouter(<MyBalance />);
		await user.click(
			await screen.findByRole("button", { name: "Request a withdrawal" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).queryByLabelText(/^Teacher/)).toBeNull();
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Currency/)).toHaveValue("USD"),
		);
		await user.type(within(dialog).getByLabelText(/^Amount/), "20");
		await user.click(within(dialog).getByRole("button", { name: "Send request" }));
		await waitFor(() =>
			expect(payrollApi.createWithdrawal).toHaveBeenCalledWith({
				amount_minor: 2000,
				currency: "USD",
				notes: "",
			}),
		);
	});

	it("cancels a request under review, and only that one", async () => {
		const user = userEvent.setup();
		renderWithRouter(<MyBalance />);
		const buttons = await screen.findAllByRole("button", {
			name: "Cancel request",
		});
		expect(buttons).toHaveLength(1);
		await user.click(buttons[0] as HTMLElement);
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Cancel this request",
			}),
		);
		await waitFor(() =>
			expect(payrollApi.cancelWithdrawal).toHaveBeenCalledWith(101),
		);
	});

	it("offers no request without a balance", async () => {
		vi.mocked(payrollApi.balances).mockResolvedValue([]);
		renderWithRouter(<MyBalance />);
		expect(await screen.findByText("No balance yet.")).toBeInTheDocument();
		expect(
			screen.queryByRole("button", { name: "Request a withdrawal" }),
		).toBeNull();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<MyBalance />);
		expect(
			await screen.findByRole("button", { name: "طلب سحب" }),
		).toBeInTheDocument();
		expect(screen.getByText("السبب: Wrong IBAN")).toBeInTheDocument();
	});
});
```

In `PayslipPage.test.tsx`, add the following (the `acknowledge` mock is already there from Task 9):

```tsx
	it("lets the teacher confirm receipt of a paid payslip", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			teacherPayslip({ status: "paid", paid_on: "2026-07-02" }),
		);
		vi.mocked(payrollApi.acknowledge).mockResolvedValue(
			teacherPayslip({
				status: "paid",
				acknowledged_at: "2026-07-03T01:00:00Z",
			}),
		);
		const user = userEvent.setup();
		renderPage(false);
		await user.click(
			await screen.findByRole("button", { name: "Confirm receipt" }),
		);
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Confirm you received this pay",
			}),
		);
		await waitFor(() => expect(payrollApi.acknowledge).toHaveBeenCalledWith(71));
		expect(await screen.findByText("Receipt confirmed.")).toBeInTheDocument();
	});

	it("offers Confirm receipt only on a paid, unconfirmed payslip, and never to the office", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(teacherPayslip());
		const { unmount } = renderPage(false);
		expect(await screen.findByText("PAY-000071")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Confirm receipt" })).toBeNull();
		unmount();
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "paid", paid_on: "2026-07-02" }),
		);
		renderPage(true);
		expect(await screen.findByText("PAY-000071")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Confirm receipt" })).toBeNull();
	});
```

If `renderWithRouter` returns no `unmount`, split the second test into two tests. Read `src/test/render.tsx` first.

In `TeacherPayslips.test.tsx`:
- add `acknowledge: vi.fn()` to the mocked `payrollApi`;
- import `CanProvider` and the `Me` type;
- add:

```tsx
	it("offers Confirm receipt on a paid payslip only while the switch is on", async () => {
		renderWithRouter(<TeacherPayslips />, {
			extraPaths: ["/teaching/payslips/$payslipId"],
		});
		const june = (await screen.findByText("June 2026")).closest(
			"li",
		) as HTMLElement;
		expect(
			within(june).getByRole("button", { name: "Confirm receipt" }),
		).toBeInTheDocument();
		const may = screen.getByText("May 2026").closest("li") as HTMLElement;
		expect(within(may).queryByRole("button", { name: "Confirm receipt" })).toBeNull();
	});

	it("hides Confirm receipt while payslip_acknowledgement is off", async () => {
		const teacher: Me = {
			id: 21,
			email: "bilal@demo.test",
			full_name: "Bilal",
			role: "teacher",
			profiles: ["teacher"],
			is_super_admin: false,
			features: [],
		};
		renderWithRouter(
			<CanProvider me={teacher}>
				<TeacherPayslips />
			</CanProvider>,
			{ extraPaths: ["/teaching/payslips/$payslipId"] },
		);
		await screen.findByText("June 2026");
		expect(screen.queryByRole("button", { name: "Confirm receipt" })).toBeNull();
	});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/payroll`
Expected: FAIL. `MyBalance` is missing, and there is no "Confirm receipt" button yet.

- [ ] **Step 3: Implement**

`ConfirmReceipt.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { useHasFeature } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { toast } from "@/ui";
import { payrollApi } from "./api";
import { usePayrollMutation } from "./queries";
import type { Payslip } from "./schemas";

/** Slice B4c C-8: the teacher confirms receipt of a paid payslip, once,
 * while `payslip_acknowledgement` is on. Its refusals are translated. */
export function ConfirmReceipt({ payslip }: { payslip: Payslip }) {
	const { t } = useTranslation();
	const hasFeature = useHasFeature();
	const acknowledge = usePayrollMutation(payrollApi.acknowledge);
	if (
		!hasFeature("payslip_acknowledgement") ||
		payslip.status !== "paid" ||
		payslip.acknowledged_at
	) {
		return null;
	}
	return (
		<Confirm
			action={t("payroll.receipt.action")}
			title={t("payroll.receipt.title")}
			body={t("payroll.receipt.body")}
			onConfirm={() =>
				acknowledge.mutate(payslip.id, {
					onSuccess: () =>
						toast({ description: t("payroll.receipt.done"), variant: "success" }),
					onError: (error) =>
						toast({ description: errorText(error, t), variant: "destructive" }),
				})
			}
		/>
	);
}
```

In `PayslipPage.tsx` `Actions`, before the Print link: `{admin ? null : <ConfirmReceipt payslip={payslip} />}`.

In `TeacherPayslips.tsx`, inside each row's right column under `PayslipStatusChip`: `<ConfirmReceipt payslip={payslip} />`.

`MyBalance.tsx`:

```tsx
import { ArrowDownToLine } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { Money } from "@/features/billing";
import { errorText } from "@/lib/form-errors";
import { dayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Spinner,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { BalanceCards } from "./Balances";
import { WithdrawalStatusChip } from "./bits";
import { useBalances, usePayrollMutation, useWithdrawals } from "./queries";
import { WithdrawalDialog } from "./WithdrawalDialog";

const PAGE_SIZE = 25;

/** Slice B4c §5, the teacher's "My balance": their balance in each currency
 * and their requests. "Request a withdrawal" is offered while there is a
 * balance. A request can be cancelled while it is under review, and a
 * rejection shows its reason. */
export function MyBalance() {
	const { t, i18n } = useTranslation();
	const { data: academy } = useAcademySettings();
	const balances = useBalances();
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useWithdrawals({ page });
	const cancel = usePayrollMutation(payrollApi.cancelWithdrawal);
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));

	return (
		<div className="flex flex-col gap-6">
			<section
				aria-label={t("payroll.balance.title")}
				className="flex flex-col gap-3"
			>
				{balances.isError ? (
					<Alert variant="destructive">
						<AlertDescription>{t("payroll.balance.loadError")}</AlertDescription>
					</Alert>
				) : balances.data ? (
					<>
						<BalanceCards balances={balances.data} />
						{balances.data.length > 0 ? (
							<div>
								<WithdrawalDialog />
							</div>
						) : null}
					</>
				) : (
					<Spinner />
				)}
			</section>
			<section aria-label={t("payroll.withdrawals.mine")} className="flex flex-col gap-3">
				<h2 className="text-lg font-semibold">{t("payroll.withdrawals.mine")}</h2>
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>
							{t("payroll.withdrawals.loadError")}
						</AlertDescription>
					</Alert>
				) : isPending ? (
					<Spinner />
				) : rows.length === 0 ? (
					<Card>
						<CardContent>
							<EmptyState
								icon={ArrowDownToLine}
								title={t("payroll.withdrawals.empty")}
							/>
						</CardContent>
					</Card>
				) : (
					<ul className="flex flex-col gap-3">
						{rows.map((row) => (
							<li key={row.id}>
								<Card>
									<CardContent className="flex flex-wrap items-center justify-between gap-3">
										<div className="flex flex-col gap-1">
											<Money minor={row.amount_minor} currency={row.currency} />
											<span className="text-sm text-muted-foreground">
												{academy
													? dayIn(
															new Date(row.created_at),
															academy.timezone,
															i18n.language,
														)
													: null}
											</span>
											{row.status === "rejected" && row.office_notes ? (
												<span className="text-sm">
													{t("payroll.withdrawals.rejectedBecause", {
														reason: row.office_notes,
													})}
												</span>
											) : null}
										</div>
										<div className="flex flex-col items-end gap-2">
											<WithdrawalStatusChip status={row.status} />
											{row.status === "under_review" ? (
												<Confirm
													action={t("payroll.withdrawals.cancel")}
													title={t("payroll.withdrawals.cancelTitle")}
													body={t("payroll.withdrawals.cancelBody")}
													onConfirm={() =>
														cancel.mutate(row.id, {
															onSuccess: () =>
																toast({
																	description: t("payroll.withdrawals.cancelled"),
																	variant: "success",
																}),
															onError: (error) =>
																toast({
																	description: errorText(error, t),
																	variant: "destructive",
																}),
														})
													}
												/>
											) : null}
										</div>
									</CardContent>
								</Card>
							</li>
						))}
					</ul>
				)}
				<Pager page={page} pages={pages} onChange={setPage} />
			</section>
		</div>
	);
}
```

`index.ts` exports `ConfirmReceipt` and `MyBalance`.

The route `teaching.balance.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { MyBalance } from "@/features/payroll";
import { PageHeader } from "@/ui";

// Slice B4c §5: a teacher's own balance and withdrawal requests.
export const Route = createFileRoute("/_authed/teaching/balance")({
	staticData: { feature: "teacher_balance" },
	component: function MyBalanceRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.myBalance"));
		return (
			<>
				<PageHeader title={t("nav.myBalance")} />
				<MyBalance />
			</>
		);
	},
});
```

`nav.ts`, under `// ── phase B4 ──`, after the withdrawals item. Add `Banknote` to the `lucide-react` import.

```ts
	// Slice B4c: a teacher's own balance and withdrawal requests.
	{
		to: "/teaching/balance",
		labelKey: "nav.myBalance",
		icon: Banknote,
		group: "teaching",
		requiresRole: "teacher",
		feature: "teacher_balance",
	},
```

Update `nav.test.ts`:
- `NAV_ITEMS` order: `"/teaching/balance"` follows `"/payroll/withdrawals"`.
- The feature map gains `"/teaching/balance": "teacher_balance"`.
- "shows a teacher their sessions…": insert `"/teaching/balance"` after `"/teaching/availability"`.

In `permissions.test.ts`, add `"/_authed/teaching/balance": "teacher_balance"` and insert `teaching\/balance|` into `FEATURE_WORDS`.

- [ ] **Step 4: Regenerate the route tree and run the tests**

Run: `… exec -T dashboard pnpm exec vite build`, then `… exec -T dashboard pnpm exec vitest run src/features/payroll src/features/shell src/routes`, then `tsc --noEmit` and `pnpm lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/payroll src/features/shell src/routes src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(payroll): teacher's My balance page and Confirm receipt (B4c §5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b4-balance.spec.ts`

**Interfaces:**
- Consumes:
  - `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `postAsAdmin` and `acceptInvite` (`e2e/fixtures.ts`);
  - `manage` (`e2e/manage.ts`).

- [ ] **Step 1: Write the E2E**

The API bodies are taken from trunk serializers (plan R15):
- `AdjustmentCreateInput`: `{teacher, kind, amount_minor, effective_on, reason}`;
- `MonthInput`: `{year, month}`.

```ts
import { expect, type Page, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
	postAsAdmin,
} from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["teacher_balance", "payslip_acknowledgement"];

/** The 15th of last month (UTC, the demo academy's clock), and its year and
 * month: always over, never a month's edge. */
function lastMonthMid() {
	const now = new Date();
	const mid = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 15));
	return {
		day: mid.toISOString().slice(0, 10),
		year: mid.getUTCFullYear(),
		month: mid.getUTCMonth() + 1,
	};
}

/** The payslip page's card header: its number and the status chips. */
const payslipHeader = (page: Page, number: string) =>
	page.locator('[data-slot="card-header"]').filter({
		has: page.getByRole("heading", { name: number, exact: true }),
	});

test.afterAll(() => {
	manage("set_features", "demo", "--off", ...SWITCHES);
});

// Slice B4c spec §7: an issued payslip paid to the balance; the teacher
// requests part of it; the admin approves and pays the request; the teacher
// sees the lower balance and confirms receipt of the payslip. The test owns
// its teacher (stamped), and its only activity is a bonus last month.
// Generating last month rebuilds the seeded teachers' drafts too, but never
// an issued or paid payslip.
test("a payslip paid to the balance is withdrawn and its receipt confirmed", async ({
	page,
	browser,
}) => {
	test.setTimeout(120_000);
	const stamp = Date.now();
	const teacher = `E2E Saver ${stamp}`;
	const teacherEmail = `e2e-saver-${stamp}@e2e.test`;
	const { day, year, month } = lastMonthMid();
	manage("set_features", "demo", "--on", ...SWITCHES);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// 1. A fresh teacher, invited by email (paid in USD by default)
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/^full name/i).fill(teacher);
	await page.getByLabel(/^gender/i).selectOption("female");
	await page.getByLabel(/^email/i).fill(teacherEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);
	const teacherId = Number(/teachers\/(\d+)$/.exec(page.url())?.[1]);

	// 2. A pending bonus last month, then generate and issue their payslip
	const created = async (path: string, data: object) => {
		const response = await postAsAdmin(page, path, data);
		expect(response.ok(), `${path}: ${await response.text()}`).toBeTruthy();
		return response.json();
	};
	await created("payroll/adjustments/", {
		teacher: teacherId,
		kind: "bonus",
		amount_minor: 5000,
		effective_on: day,
		reason: `E2E balance ${stamp}`,
	});
	await created("payroll/payslips/generate/", { year, month });
	const listed = await page.request.get(`${DEMO_URL}/api/v1/payroll/payslips/`, {
		params: { teacher: teacherId, year, month },
	});
	const [payslip] = (await listed.json()).results;
	await created(`payroll/payslips/${payslip.id}/issue/`, {});

	// 3. The admin pays it to the teacher's balance
	await page.goto(`${DEMO_URL}/app/payroll/payslips/${payslip.id}`);
	await page.getByRole("button", { name: "Pay to balance" }).click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Pay to balance" })
		.click();
	await expect(page.getByRole("dialog")).toHaveCount(0);
	const header = payslipHeader(page, payslip.number);
	await expect(header.getByText("Paid", { exact: true })).toBeVisible();
	await expect(header.getByText("Paid to balance", { exact: true })).toBeVisible();

	// 4. The teacher signs in, sees $50.00 and requests $20.00 of it
	const saver = await acceptInvite(browser, teacherEmail, "e2e-Saver-2026", teacher);
	await saver.goto(`${DEMO_URL}/app/teaching/balance`);
	const balance = saver.getByRole("list", { name: "Balance" });
	await expect(balance.getByText("$50.00")).toHaveCount(2);
	await saver.getByRole("button", { name: "Request a withdrawal" }).click();
	const ask = saver.getByRole("dialog");
	await expect(ask.getByLabel(/^Currency/)).toHaveValue("USD");
	await ask.getByLabel(/^Amount/).fill("20");
	await ask.getByRole("button", { name: "Send request" }).click();
	await expect(saver.getByText("Withdrawal request sent.")).toBeVisible();
	await expect(saver.getByText("Under review", { exact: true })).toBeVisible();
	await expect(balance.getByText("$30.00")).toBeVisible(); // available

	// 5. The admin approves and pays the request
	await page.goto(`${DEMO_URL}/app/payroll/withdrawals`);
	await page.getByLabel("Teacher", { exact: true }).selectOption({ label: teacher });
	const row = page.getByRole("row", { name: new RegExp(teacher) });
	await row.getByRole("button", { name: "Approve" }).click();
	await page
		.getByRole("alertdialog")
		.getByRole("button", { name: "Approve this request" })
		.click();
	await expect(row.getByText("Approved", { exact: true })).toBeVisible();
	await row.getByRole("button", { name: "Pay", exact: true }).click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Record payment" })
		.click();
	await expect(row.getByText("Paid", { exact: true })).toBeVisible();

	// 6. The teacher sees the lower balance and confirms receipt of the payslip
	await saver.reload();
	await expect(balance.getByText("$30.00")).toHaveCount(2);
	await saver.goto(`${DEMO_URL}/app/teaching/payslips`);
	await saver.getByRole("link", { name: payslip.number, exact: true }).click();
	await expect(saver).toHaveURL(/\/app\/teaching\/payslips\/\d+$/);
	await saver.getByRole("button", { name: "Confirm receipt" }).click();
	await saver
		.getByRole("alertdialog")
		.getByRole("button", { name: "Confirm you received this pay" })
		.click();
	await expect(saver.getByText("Receipt confirmed.")).toBeVisible();
	await expect(saver.getByText("Receipt confirmed", { exact: true })).toBeVisible();
	await expect(saver.getByRole("button", { name: "Confirm receipt" })).toHaveCount(0);
	await saver.context().close();
});
```

The generate response may name seeded teachers under `missing_rate` or `unpaid_sessions`. That is expected and not asserted.

- [ ] **Step 2: Run the E2E**

Run: `just e2e e2e/b4-balance.spec.ts`
Expected: PASS. If it fails, debug with `superpowers:systematic-debugging` and never weaken an assertion.

- [ ] **Step 3: The slice gates**

Run: `just test`, `just lint`, `just e2e`
Expected: all green, with the coverage gates met. Keep the outputs for the final review.

- [ ] **Step 4: Commit**

```bash
git -C $W/dashboard add e2e/b4-balance.spec.ts
git -C $W/dashboard commit -m "test(e2e): B4c pay to balance, withdraw, confirm receipt

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| C-1 pay to balance: as mark paid plus the flag, 404 while off, "Paid to balance" on the board and page | 4, 6, 9 |
| C-2 derived balance per currency, one SELECT, `[]` for a non-teacher, `balances_of` the only read | 2 |
| C-3 `WithdrawalRequest` fields and statuses, currency of a balance (400 on `currency`) | 1, 3, 7 |
| C-4 transitions, a reason on every rejection, `paid_on` bounds, every other move 409 | 3, 7, 10, 11 |
| C-5 `BalanceLock` get_or_create + FOR UPDATE, lock order, sufficient balance enforced, no payslip lock | 3 |
| C-6 who acts: teacher own / office any (inactive too), service refuses an inactive teacher's own request, students and parents 403, User ids | 3, 7 |
| C-7 payout details on office rows (no N+1, R3), teacher reads `office_notes` | 7, 10, 11 |
| C-8 acknowledgement: teacher only, paid only, once, the office sees the date | 5, 6, 9, 11 |
| C-9 salary expense on mark paid and pay to balance, `expenses` off, one transaction, net 0, title languages and fallback, truncation, idempotent, lock order | 4 |
| C-10 `NotImpersonating` on every B4c write; `mark-paid` unchanged | 6, 7 |
| C-11 office balance view above the list | 7 (`balances/`), 10 |
| §3 data and the one migration | 1 |
| §4 routes, codes, `SELF_SERVICE`, `FEATURES`, `FEATURE_WORDS`, row and CSV fields | 6, 7 |
| §4 `teacher_withdrawal` resource | 7 |
| §5 office payslip actions | 9 |
| §5 withdrawals page, filters, balances, actions, New request gating | 10 |
| §5 My balance, Request a withdrawal, cancel, rejection reason, Confirm receipt | 11 |
| §5 refusal codes translated (`insufficient_balance`, `already_acknowledged`, status, `identity.impersonating`) | 8 (strings), 10, 11 |
| §6 no seeds | — (spec: none) |
| §7 query counts, isolation, role matrix | 2, 7 |
| §7 E2E `e2e/b4-balance.spec.ts` | 12 |
| Switches `teacher_balance`, `payslip_acknowledgement`, `salary_expenses` (requires nothing) | 1, 8 |
