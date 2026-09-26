# Plan 7 — Teacher Payroll — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins pay teachers monthly for the sessions they taught. Rates are set per teacher (a default and per course) in the teacher's own currency, and bonuses and deductions are recorded with a reason. For any month, draft payslips are generated from completed sessions and pending adjustments. Once the month has ended, a payslip is issued, which freezes it and locks its sessions, and it is then marked paid. Teachers see and print their own issued and paid payslips.

**Architecture:** A new tenant app, `etqan.payroll` (P7-1), owns `TeacherRate`, `PayAdjustment`, `Payslip`, `PayslipLine` and a one-row `PayslipCounter` per academy. Its services are split by job:
- `services/rules.py`: the one pay rule (`PAYS`), the one amount formula (`session_amount`, integer `round_half_up`), month bounds, rate choice, the pending-adjustment filter and the payslip read.
- `services/build.py`: the one build function, `build(teacher, year, month) -> Built`, used by generate and, from fresh data, by issue.
- `services/rates.py` and `services/adjustments.py`: their writes, each saved in the teacher's current `pay_currency`.
- `services/payslips.py`: generate, issue and mark paid, under the locks of D1.
- `services/numbering.py`: `PAY-000123` numbers from the locked counter row.

Payroll reads sessions only through `etqan.scheduling.services`. **Scheduling owns the lock** (P7-1): a new `Session.payroll_locked` flag, set only by scheduling's `lock_sessions(ids)`, and refused by every write path in `scheduling/services/attendance.py`. Scheduling never imports payroll. The dashboard adds:
- a `features/payroll` module;
- an admin Payroll nav group (Payslips, Rates, Adjustments, and the payslip page);
- My payslips under Teaching;
- a payslip print page on the invoices' `_print` layout, whose branded sheet moves into `features/branding` so both documents share it;
- a "Paid in payslip" note and closed controls on a locked session.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, `Intl` for money, months and lists; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-26-payroll-design.md` (Phase B0 milestone 7 of `2026-09-24-parity-roadmap-design.md`). It builds on:
- Plan 5, `2026-09-25-sessions-attendance-design.md` (attendance, cancel, restore, bulk; the payroll lock was deferred to here), and Plan 4, `2026-09-24-subscriptions-scheduling-design.md` (sessions, the lock order);
- Plan 6, `2026-09-25-billing-design.md` (the locked counter, the `_print` layout, conventions);
- Plan 3, `2026-09-24-people-catalogue-design.md` (`TeacherProfile.pay_currency`, roles, CSV).

Where this plan fills a gap in the spec, the Decisions below say so.

**Verified:** the code in Tasks 1–15 was applied, in this plan's order and exactly as written here, to fresh copies of `backend@85e8591` and `dashboard@a79b9ba` (the current `main` of each). After every task, its format, lint, import-contract, type, test and coverage commands passed:
- backend: 1001 → 1110 tests, coverage 97.7%;
- dashboard: 564 → 616 tests, lines 93.9%, branches 86.7%, functions 80.4%.

The e2e suite then passed through Caddy, run the way the CI `e2e` job runs it: Django (`config.settings.local`, file email backend) and the Vite preview on a freshly migrated and seeded database, plus the marketing server on `:4321`, so every spec ran. That was 16 of 16, `payroll.spec.ts` and `academy-sites.spec.ts` included, twice on the same database, with no retry. Migrations are generated in Task 1 with `makemigrations`, so only their timestamps will differ.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`).
- The branch `feat/payroll` already exists in the meta repo, `backend/` and `dashboard/`, so do not create it. Check with `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and Task 9.
- Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Backend commands**
- Run from `backend/` with the virtualenv `backend/.venv`. Export this environment once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
- Tests: `.venv/bin/pytest …`. Add `--create-db` once after Task 1, which adds migrations.
- Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`
- Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
- Watch `PLR0913`: keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`, as Plans 4–6 do.

**Dashboard commands**
- Run from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- New route files are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`.
- Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere in `src/`, `e2e/` or `scripts/`, comments included. Semantic tokens only.
- `tsc` has `noUnusedLocals`/`noUnusedParameters`.

**Coverage and dev data**
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`.
- Academies: `demo` (`admin@demo.test`, timezone UTC, default language Arabic) and `other` (`admin@other.test`).

**Tenancy and module boundaries**
- `etqan.payroll` goes in `TENANT_APPS`. Migrate with `migrate_schemas`. No background job and no user-facing URL is added.
- Business logic lives in `etqan/payroll/services/`. Views parse, call one service, re-read and arrange a payload. Payloads never restate a rule.
- Payroll reaches identity, catalogue, academy and scheduling only through their `services`, and never imports billing. Scheduling never imports payroll, not even from its API. Other apps import only `etqan.payroll.services`. `lint-imports` enforces all of this (Task 1).
- The admin-only flag is keyword-only with no default: `payslip_row(payslip, *, is_admin)`, `payslip_detail(payslip, *, is_admin)`; scheduling's `session_row(session, *, viewer)` keeps its own.

**API and data rules**
- All routes are under `/api/v1/payroll/`.
- Money is integer minor units plus an ISO 4217 currency. Every payslip, rate and adjustment is in the teacher's `pay_currency`, and totals are never summed across currencies (P7-3).
- `year`/`month`, `effective_on` and `paid_on` are on the academy's calendar (`AcademySettings.timezone`); `issued_at` is UTC.
- Spec values, verbatim:
  - payslip status `draft · issued · paid`; adjustment kind `bonus · deduction`; line kind `session · adjustment`;
  - number format `PAY-000123`;
  - the pay rule (P7-2): a session pays when it is `completed` and its `teacher_attendance` is `present` or `not_set`, whatever the student's attendance;
  - the amount: `round_half_up(rate × minutes / 60)` in integer minor units;
  - net = gross + bonuses − deductions.
- Errors:
  - rule refusals are `409 {"detail", "code"}` with `payroll.not_allowed_in_status`, `payroll.month_not_over`, `payroll.missing_rate`, `payroll.negative_net`, `payroll.adjustment_used`, or (from scheduling) `payroll.payslip_issued`;
  - field problems are `400 {"<field>": [...]}` (`paid_on` in the future, a duplicate rate on `course`);
  - out-of-scope objects are `404`; a role that may not use a route gets `403`.
- Access (spec §4.7): admins everything; a teacher reads their own `issued` and `paid` payslips only (list, detail, print); students, parents and anonymous callers get 403 on every payroll route; `notes`, `issued_by` and `paid_by` are admin-only. The session payload gains `payroll_locked` for admins and the session's own teacher.
- Every write answers with a fresh read of what it changed. Views define only the methods the spec lists, so there is no PUT.
- Lists `select_related` what a row shows. The payslip list and the rate list have query-count tests.

**Dashboard strings and helpers**
- Every dashboard string is in `src/locales/en/common.json` and `src/locales/ar/common.json`, with no English literal in components. Each task lists the keys it adds; merge them into the existing objects.
- zod messages are i18n keys rendered through `useFieldError`. 409 codes render as `errors.<code>` through `applyServerErrors`/`errorText`.
- Required fields render `*` inside the `<label>`, so tests query `getByLabelText(/^Amount/)`. Where one accessible name is a substring of another (`Paid` inside `Paid on`, `Issue` inside `Issue this payslip`, `Generate` inside `Generate for range`), match exactly.
- Screens work RTL and at phone width.
- Reuse the shared helpers: `Pager`, `clean`/`csvUrl`/`Paginated`, `applyServerErrors`/`errorText`, `useFieldError`, `formatMoney`/`toMinor`/`toMajor`, billing's `Money` and `amount`, `formatDay`/`todayIn`, `Fact`, `Confirm`, the `_print` layout with `PrintPage`/`PrintSheet`. No copies inside a feature.
- Detail pages handle a non-numeric id, a 404 and a load error with translated messages.

**Tests**
- Each assertion fails without the code under test.
- Duplicate matches are scoped (`within(row)`, `within(dialog)`, the card header).
- Cross-academy tests hold data in BOTH academies, with the other academy's pk forced above this one's (`until_pk_exceeds`). They assert the explicit 404 and that this academy's own data is still there.
- Timezone tests put the academy in a zone whose date differs from UTC's at the pinned instant.
- Lock-shape tests assert the exact SQL tail (`… ORDER BY 1 ASC FOR UPDATE`, `… LIMIT 21 FOR UPDATE OF "payroll_payslip"`), never a bare `FOR UPDATE` or `ORDER BY` substring: `Meta.ordering` adds an `ORDER BY` of its own.

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — Lock order.** Plans 4–6 lock a subscription before its sessions, and sessions in id order. Plan 7 keeps both and adds payslips in front:
  - **Issue:** the payslip row (`FOR UPDATE OF "payroll_payslip"`); then the teacher's pending adjustments, in id order (`FOR UPDATE OF "payroll_payadjustment"`), so an adjustment edit and an issue never interleave; then the teacher's unlocked sessions of the month, in id order, through scheduling's `hold_sessions`; only then the rebuild, so nothing it reads can change before it commits; then `lock_sessions` flags the paying ones (their rows are already held).
  - **Generate:** the counter row, then the month's payslips in id order (`… ORDER BY "payroll_payslip"."id" ASC FOR UPDATE`), so an issue in progress finishes first and its payslip is seen as issued. Sessions are only read.
  - **Mark paid, rate and adjustment edits:** their own row only.
  - **Why this cannot deadlock:** payroll never locks a subscription, and nothing locks a session and then a payslip or an adjustment. Every session locker (attendance, bulk, delete, `delete_untouched`, hold, lock) takes session rows in id order.
- **D2 — Numbering.** `payroll.PayslipCounter(last_number)`, one row, pk 1, in each academy's schema, as billing's `InvoiceCounter` (Plan 6 D1). It is payroll's own table: a shared counter would have to live in `etqan.platform`, which is a public-schema app and imports no business module.
  - `numbering.hold()` takes the row `FOR UPDATE` (`get_or_create`, whose `IntegrityError` path re-reads it when two first calls race), and `numbering.take(counter)` hands out `PAY-{:06d}`.
  - Generate holds the counter from its first statement, so two generates for one academy run one after the other and can never both create a teacher's payslip for the month. A replaced draft keeps its number; a rolled-back generate gives its numbers back. `Payslip.number` is unique as a backstop.
- **D3 — Who generate finds.** Two queries, however many teachers: the distinct `teacher_id`s of scheduling's `payroll_sessions(first, last)` filtered by `PAYS`, and the distinct `teacher_id`s of the pending adjustments (`rules.pending_adjustments(last)`). These are the very filters `build` uses, so every teacher found builds at least one line. Their profiles come in one query (`identity_services.teacher_profiles_by_id`).
- **D4 — One rule, one formula, one build.**
  - The pay rule is `rules.PAYS = Q(status="completed", teacher_attendance__in=("present", "not_set"))`. It lives in payroll (it is payroll's rule) and filters scheduling's queryset by field name; scheduling knows nothing of it.
  - `round_half_up(n, d) = (2n + d) // 2d` for `n ≥ 0`, `d > 0`: integers only, no float or `Decimal`. `session_amount(rate, minutes) = round_half_up(rate * minutes, 60)`.
  - `build(teacher, year, month) -> Built` is the only place lines and totals are made; generate writes it, issue rebuilds and writes it.
- **D5 — Payload shapes.**
  - **Payslip row:** `id, number, status, teacher {id, full_name}, year, month, currency, sessions, minutes, gross_minor, bonuses_minor, deductions_minor, net_minor, missing_rate, issued_at, paid_on, created_at, updated_at`, plus admin-only `notes, issued_by {id, full_name} | null, paid_by`. `sessions` and `minutes` are summed from the session lines in SQL (subqueries, so a row never multiplies).
  - **Payslip detail:** the row plus `lines: [{id, kind, session_id, adjustment_id, description, minutes, rate_minor, amount_minor}]`, sessions first then adjustments, as built.
  - **Rate:** `id, teacher, course {id, name_ar, name_en} | null, hourly_rate_minor, currency, counts, created_at, updated_at`. `counts` is false for a rate left in a currency the teacher is no longer paid in.
  - **Adjustment:** `id, teacher, kind, amount_minor, currency, effective_on, reason, payslip {id, number} | null, created_by, created_at`.
  - **Generate:** `{created, replaced, removed, missing_rate: [{id, full_name}], other_currency: [{id, full_name}]}` (D11).
  - **What each write returns:** POST rate and adjustment `201` with the row; PATCH `200` with the row; DELETE `204`; issue and mark paid `200` with the payslip's detail.
- **D6 — What a teacher sees.** `payroll.scopes.scope_for(user, queryset)`: admins everything; a teacher `teacher__user=user, status__in=("issued", "paid")`; everyone else none. Permissions: the payslip list and detail are `IsAdmin | (ReadOnly & IsTeacher)`; every other payroll route is `IsAdmin`; CSV is refused for a teacher with 403 inside the view, as billing does. So a teacher's own draft and another teacher's payslip are both a 404, and the print page (which reads the same detail route) says "couldn't be found".
- **D7 — CSV columns.** Number, Teacher, Year, Month, Sessions, Minutes, Gross (minor units), Bonuses (minor units), Deductions (minor units), Net (minor units), Currency, Status, Missing rate (yes/no), Paid on. The same filters as the list.
- **D8 — Navigation and pages.**
  - **Admins:** a new `payroll` nav group after Billing with Payslips (`/payroll/payslips`), Rates (`/payroll/rates`) and Adjustments (`/payroll/adjustments`), plus the payslip page `/payroll/payslips/$payslipId`, under `requireAdmin`.
  - **Teachers:** the `teaching` group gains My payslips (`/teaching/payslips`, `/teaching/payslips/$payslipId`), read-only with Print.
  - **Print:** `/app/payslips/$payslipId/print` on the pathless `_print` layout. Its academy-branded sheet (`PrintPage`, `PrintSheet`) moves from `InvoicePrint` into `features/branding`, so invoices and payslips share one frame; the `@media print` class becomes `.print-sheet`.
- **D9 — The month picker.** Month and Year selects (not `<input type="month">`, which Firefox and Safari lack). The default is the month before today on the academy's calendar: `previousMonth(todayIn(academy.timezone))` (new in `@/lib/zoned-time`, with `formatMonth`). The years offered are the academy's this year −2 to +1. Changing the month clears a shown generate result.
- **D10 — Payslip notes.** The spec lists an admin-only `notes` field but no route that writes it. `POST mark-paid` takes an optional `notes` (how it was paid, a transfer reference); nothing else writes it. No PATCH on payslips.
- **D11 — Generate's result.** The spec's `missing_rate: [teacher ids]` becomes `[{id, full_name}]` so the page can name them (spec §6). The spec's "reported as a warning" for adjustments in a currency the teacher is no longer paid in becomes `other_currency: [{id, full_name}]`, shown under the result.
- **D12 — Rates.**
  - The list is every rate at once, not paged: a page groups them by teacher (a teacher × course table stays small).
  - A second default or a second rate for a course is a 400 on `course` (the unique constraint decides, so two admins at once get a 400, not a 500).
  - Editing a rate saves it in the teacher's current currency, which is how a stale rate (spec §4.6) counts again.
  - The Rates page warns for a teacher whose default rate is missing or stale. It lists teachers from the people list at `page_size=100` (the known cap, as elsewhere).
- **D13 — Copied text.** A session line reads `"{date} — {course} — {student}"` and an adjustment line `"{Bonus|Deduction} — {reason}"`, in the academy's `default_language` when built, as billing's descriptions (Plan 6 D5). An issued payslip never re-translates.
- **D14 — Scheduling's lock services.** In a new `scheduling/services/paylock.py`, re-exported from `etqan.scheduling.services`:
  - `refuse_if_paid(session)`: 409 `payroll.payslip_issued`. `mark_attendance`, `cancel_session` and `restore_session` call it on the locked row before any other check, so a locked, completed session is refused for its lock, not its status. `bulk_sessions` reuses them, so a locked session is skipped with that code.
  - `payroll_sessions(first, last) -> QuerySet[Session]`: unlocked sessions of the dates, with `course` and `student__user`, oldest first.
  - `hold_sessions(*, teacher_id, first, last) -> list[int]`: row locks, id order, returns the ids.
  - `lock_sessions(ids) -> list[int]`: row locks in id order, then `payroll_locked=True`.
  - `delete_untouched` and `delete_subscription` need no change: a locked session is completed, which neither ever deletes. A test pins it.
  - The session payload's `payroll_locked` follows `can_read_report`'s audience (admins and the session's own teacher), as `has_report` does.
- **D15 — Seeds.** The seeded sessions all start in the last 17 days, so last month often has none. To make last month's payslips exist whatever today is, each demo teacher gets a bonus on the 15th of last month (the spec's "one bonus", doubled — Bilal's and Maryam's). Bilal gets a default rate (1000) and a Tajweed rate (1200); Maryam only a Quran Memorisation rate (900), so the Rates page shows the "No default rate" warning while every seeded session of hers still has a rate. Last month is then generated; Bilal's is issued and marked paid today, Maryam's issued. It runs only when the academy has no rate, adjustment or payslip, prints `skip:` for anything a rule refuses and carries on, and leaves the `other` academy alone.
- **D16 — Shared helpers.**
  - `amount(currency, { allowZero })` in billing's schemas gains the option, for a zero rate, with the message key `billing.errors.amountOrZero`; payroll imports `amount` and `Money` from `@/features/billing` rather than copying them.
  - `previousMonth`, `formatMonth` join `@/lib/zoned-time`; `monthName` (the picker's option text) and `hours` live in payroll's `bits.tsx`.
  - `PayslipBody` renders the lines and totals once, for the page and the print sheet.
- **D17 — Issue's edges.** A refusal rolls the whole issue back: the draft keeps its old lines until the next generate. A draft whose activity vanished since generating (every session changed) is still issued, with no lines and a net of 0; the spec gives no refusal for it and the admin can see it before issuing.

## Review Focus

- **A teacher seeing drafts or another teacher's payslips.** A teacher must see only their own issued and paid payslips, in the list, the detail and the print page, and never staff notes; a student or parent sees nothing. Tests:
  - Task 7: `test_a_teacher_reads_only_their_own_issued_and_paid`, `test_every_role_on_every_route`, `test_another_academy_never_leaks`;
  - Task 10: `the print route` "prints a teacher's own payslip, and not another teacher's".
- **The session lock on every scheduling path.** Once issued, no attendance change, cancel, restore or bulk action may alter a paid session, and no automatic deletion may remove it. Tests:
  - Task 2: `test_every_single_write_refuses_a_locked_session` (student, teacher, cancel, restore), `test_bulk_skips_a_locked_session_with_its_code`, `test_automatic_deletion_and_delete_never_reach_a_locked_session`, `test_a_session_on_an_issued_payslip_is_a_coded_conflict`;
  - Task 9: `SessionPage` "offers no cancel or restore on a session an issued payslip pays";
  - Task 15: the e2e journey's last step.
- **Regenerate never touching issued or paid payslips.** Generating again, even with new activity or none left, must leave an issued or paid payslip byte for byte, and an issue racing a generate must be seen as issued. Tests:
  - Task 5: `test_issued_and_paid_payslips_are_never_touched`, `test_generate_locks_the_counter_then_the_months_payslips`;
  - Task 6: `test_a_stale_copy_is_never_issued_twice`, `test_issue_locks_payslip_adjustments_then_sessions`.
- **Currency drift.** When a teacher's `pay_currency` changes, old rates and adjustments must stop counting (a missing rate, not a wrong amount in the wrong currency) until rates are edited, and issue must refuse rather than pay in a stale currency. Tests:
  - Task 4: `test_a_pay_currency_change_drops_old_rates_and_adjustments`;
  - Task 3: `test_editing_a_rate_moves_it_to_the_current_currency`;
  - Task 6: `test_a_pay_currency_change_before_issue_is_a_missing_rate`;
  - Task 12: `RatesPage` "lists each teacher's rates and warns about a missing default".
- **The pay rule for every attendance combination.** Every student × teacher attendance must pay exactly when the session is completed and the teacher was present or not marked, at the right rate, rounded half up in integers. Tests:
  - Task 4: `test_the_pay_rule_for_every_attendance` (12 combinations), `test_a_session_not_completed_or_cancelled_never_pays`, `test_the_one_amount_formula_rounds_half_up_in_integers`, `test_the_courses_rate_wins_over_the_default`.

---

## File Structure

```
backend/
  config/settings/base.py            TENANT_APPS += etqan.payroll
  config/api_router.py               payroll/ → etqan.payroll.api.urls
  pyproject.toml                     import-linter contracts for payroll
  etqan/identity/services.py         teacher_profiles_by_id (+ test)
  etqan/catalogue/services.py        courses_by_id (+ test)
  etqan/scheduling/
    models.py                        Session.payroll_locked (+ migration 0003_session_payroll_locked)
    services/paylock.py              NEW: refuse_if_paid, payroll_sessions, hold_sessions, lock_sessions
    services/attendance.py           refuse_if_paid on attendance, cancel and restore (bulk reuses them)
    services/__init__.py             re-exports the three payroll services
    api/payloads.py                  session_row: payroll_locked for admins and the session's teacher
    tests/test_paylock.py            NEW; test_api_sessions.py, test_api_session_writes.py
  etqan/payroll/                     NEW app
    apps.py models.py                PayslipCounter, TeacherRate, PayAdjustment, Payslip, PayslipLine
                                     (+ migrations/0001_initial.py)
    clock.py                         now(), today() on the academy's calendar
    scopes.py                        scope_for(user, queryset)
    services/__init__.py             the public API
    services/numbering.py            hold, take
    services/rules.py                PAYS, round_half_up, session_amount, month_bounds, month_over,
                                     teacher_of, check/save, current_rates, rate_for,
                                     pending_adjustments, other_currency_adjustments,
                                     TEACHER_VISIBLE, payslips_queryset, filter_payslips, has_payroll
    services/rates.py                create_rate, update_rate, delete_rate, rates_queryset
    services/adjustments.py          create/update/delete_adjustment, adjustments_queryset, filter_adjustments
    services/build.py                Line, Built, build
    services/payslips.py             GenerateResult, generate, write, lock, issue, mark_paid
    api/serializers.py payloads.py views.py urls.py
    tests/conftest.py                Clock (both clocks), world, admin, june_sessions, mark, set_rate, adjust
    tests/test_models.py test_rates_adjustments.py test_build.py test_generate.py test_issue.py test_api.py
  etqan/tenants/management/commands/seed_dev.py   PAYROLL, seed_payroll (+ tests/test_seed_dev.py)
dashboard/
  src/features/branding/PrintSheet.tsx              PrintPage, PrintSheet (moved out of InvoicePrint)
  src/features/billing/                             InvoicePrint on the shared sheet; amount(…, {allowZero})
  src/lib/zoned-time.ts                             previousMonth, formatMonth
  src/features/scheduling/                          payroll_locked: AttendanceControls closed + note,
                                                    SessionPage hides cancel and restore
  src/features/payroll/
    schemas api queries bits index                  types, calls, hooks, PayslipStatusChip, hours, monthName
    PayslipBody PayslipPrint                        lines and totals; the print page
    PayslipPage MarkPaidDialog                      the payslip page (admin and teacher)
    RatesPage RateDialog                            rates per teacher
    AdjustmentsList AdjustmentDialog                bonuses and deductions
    PayslipsList                                    the month, Generate, the list
    TeacherPayslips                                 My payslips
  src/features/shell/nav.ts                         payroll group, teaching My payslips
  src/routes/_print/payslips.$payslipId.print.tsx
  src/routes/_authed/payroll{,.index,.payslips.index,.payslips.$payslipId,.rates,.adjustments}.tsx,
                     teaching.payslips.{index,$payslipId}.tsx
  src/test/payroll-fixtures.ts, scheduling-fixtures.ts
  src/locales/{en,ar}/common.json
  e2e/payroll.spec.ts
meta: STATE.md, submodule pointers
```

---


### Task 1: Data: the payroll app, its models, the session's lock flag and the import contracts

**Files:**
- Create: `backend/etqan/payroll/__init__.py`, `backend/etqan/payroll/apps.py`, `backend/etqan/payroll/clock.py`, `backend/etqan/payroll/models.py`, `backend/etqan/payroll/migrations/__init__.py`, `backend/etqan/payroll/services/__init__.py`, `backend/etqan/payroll/services/numbering.py`, `backend/etqan/payroll/migrations/0001_initial.py` and `backend/etqan/scheduling/migrations/0003_session_payroll_locked.py` (generated in Step 4)
- Modify: `backend/config/settings/base.py`, `backend/etqan/scheduling/models.py`, `backend/pyproject.toml`
- Test: `backend/etqan/payroll/tests/__init__.py` (new), `backend/etqan/payroll/tests/conftest.py` (new), `backend/etqan/payroll/tests/test_models.py` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - models `PayslipCounter`, `TeacherRate`, `PayAdjustment` (`Kind.BONUS/DEDUCTION`), `Payslip` (`Status.DRAFT/ISSUED/PAID`), `PayslipLine` (`Kind.SESSION/ADJUSTMENT`) in `etqan.payroll.models`;
  - `Session.payroll_locked: bool` (default `False`) in `etqan.scheduling.models`;
  - `etqan.payroll.clock.now() -> datetime`, `today() -> date` (the academy's calendar);
  - `etqan.payroll.services.numbering.hold() -> PayslipCounter` (row `FOR UPDATE`) and `take(counter) -> str` (`PAY-000123`).
- Produces (tests): `etqan.payroll.tests.conftest` with `Clock` (pins scheduling's and payroll's clocks to Monday 1 June 2026 08:00 UTC), fixtures `clock`, `world`, `admin`, and helpers `june_sessions(world, **overrides) -> list[Session]` (a June subscription on Mondays and Wednesdays at 18:00 and its nine June sessions) and `mark(session, by, *, student="present", teacher="present")`.

- [ ] **Step 1: Write the failing tests**

The database refuses what the spec forbids (a negative rate, a zero adjustment, a 13th month, a second payslip for a teacher and month, a second default or course rate), and numbering holds one blocking lock on the one counter row.

Create `backend/etqan/payroll/tests/__init__.py`:

```python
"""Payroll tests."""
```

Create `backend/etqan/payroll/tests/conftest.py`:

```python
"""Payroll fixtures. Both clocks are pinned together: scheduling's (sessions
and attendance) and payroll's (the month and `paid_on`), to Monday 1 June
2026, 08:00 UTC, unless a test moves them."""

from datetime import date

import pytest

from etqan.payroll import clock as payroll_clock
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import Clock as SchedulingClock
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

JUNE = (date(2026, 6, 1), date(2026, 6, 30))


class Clock(SchedulingClock):
    def set(self, when) -> None:
        super().set(when)
        self._monkeypatch.setattr(payroll_clock, "now", lambda: when)


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


@pytest.fixture
def world(clock):
    """Scheduling's world: teacher Bilal (paid in USD, the default), student
    Yusuf, course Tajweed and the Monthly package (2 x 45 minutes a week)."""
    return build_world()


@pytest.fixture
def admin():
    return make_admin()


def june_sessions(world, **overrides) -> list:
    """A June 2026 subscription for ``world`` (Mondays and Wednesdays at
    18:00) and every one of its June sessions, oldest first: 1, 3, 8, 10, 15,
    17, 22, 24 and 29 June."""
    sub = subscription_for(world, slots=two_slots(), **overrides)
    scheduling_services.generate(*JUNE, subscription=sub)
    return list(scheduling_services.sessions_of(sub).filter(occurs_on__range=JUNE))


def mark(session, by, *, student="present", teacher="present"):
    """Mark both attendances (the session must have started)."""
    return scheduling_services.mark_attendance(
        session, by=by, student_attendance=student, teacher_attendance=teacher
    )
```

Create `backend/etqan/payroll/tests/test_models.py`:

```python
from datetime import date

import pytest
from django.db import IntegrityError
from django.db import connection
from django.db import transaction
from django.test.utils import CaptureQueriesContext

from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.models import TeacherRate
from etqan.payroll.services import numbering
from etqan.scheduling.tests.conftest import make_teacher


@pytest.fixture
def teacher():
    return make_teacher().teacher_profile


def rate(teacher, **overrides):
    fields = {
        "teacher": teacher,
        "course_id": None,
        "hourly_rate_minor": 1000,
        "currency": "USD",
        **overrides,
    }
    return TeacherRate.objects.create(**fields)


def payslip(teacher, **overrides):
    fields = {
        "number": "PAY-000001",
        "teacher": teacher,
        "year": 2026,
        "month": 6,
        "currency": "USD",
        **overrides,
    }
    return Payslip.objects.create(**fields)


def test_the_database_refuses_a_negative_rate(teacher):
    with pytest.raises(IntegrityError), transaction.atomic():
        rate(teacher, hourly_rate_minor=-1)


@pytest.mark.parametrize("course_id", [None, 7])
def test_one_rate_per_course_and_one_default(teacher, course_id):
    rate(teacher, course_id=course_id)
    with pytest.raises(IntegrityError), transaction.atomic():
        rate(teacher, course_id=course_id, hourly_rate_minor=2000)
    # A default and a course rate live side by side.
    rate(teacher, course_id=8 if course_id is None else None)
    assert TeacherRate.objects.filter(teacher=teacher).count() == 2


def test_the_database_refuses_an_adjustment_of_nothing(teacher):
    with pytest.raises(IntegrityError), transaction.atomic():
        PayAdjustment.objects.create(
            teacher=teacher,
            kind="bonus",
            amount_minor=0,
            currency="USD",
            effective_on=date(2026, 6, 15),
            reason="Extra",
        )


def test_one_payslip_per_teacher_and_month(teacher):
    payslip(teacher)
    with pytest.raises(IntegrityError), transaction.atomic():
        payslip(teacher, number="PAY-000002")
    assert str(payslip(teacher, number="PAY-000003", month=7)) == (
        "Payslip<PAY-000003, draft>"
    )


def test_the_database_refuses_a_thirteenth_month(teacher):
    with pytest.raises(IntegrityError), transaction.atomic():
        payslip(teacher, month=13)


def test_numbers_are_handed_out_in_sequence():
    with transaction.atomic():
        counter = numbering.hold()
        numbers = [numbering.take(counter) for _ in range(3)]
    assert numbers == ["PAY-000001", "PAY-000002", "PAY-000003"]


def test_holding_locks_the_academys_counter_row():
    with transaction.atomic():
        numbering.hold()  # the counter row exists from here on
    with CaptureQueriesContext(connection) as ctx, transaction.atomic():
        numbering.hold()
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    # One blocking lock (no NOWAIT, no SKIP LOCKED) on the one counter row: a
    # concurrent generate waits for it.
    assert len(locks) == 1
    assert locks[0].endswith(
        'FROM "payroll_payslipcounter" WHERE "payroll_payslipcounter"."id" = 1 '
        "LIMIT 21 FOR UPDATE"
    )
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/payroll -q`

Expected: FAIL — collection errors: `No module named 'etqan.payroll.models'` (the app does not exist yet).

- [ ] **Step 3: Implement**

Register the app and the contracts first, then the models and the numbering.

Create `backend/etqan/payroll/__init__.py`:

```python
"""Teacher payroll (Plan 7)."""
```

Create `backend/etqan/payroll/apps.py`:

```python
from django.apps import AppConfig


class PayrollConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.payroll"
    label = "payroll"
```

Create `backend/etqan/payroll/clock.py`:

```python
"""The only clock payroll reads, so tests pin it by monkeypatching `now`."""

from datetime import date
from datetime import datetime
from zoneinfo import ZoneInfo

from django.utils import timezone

from etqan.academy import services as academy_services


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()


def today() -> date:
    """Today on the academy's calendar (`AcademySettings.timezone`): a month
    is over, and a payslip is paid, by it."""
    return now().astimezone(ZoneInfo(academy_services.get_settings().timezone)).date()
```

Create `backend/etqan/payroll/models.py`:

```python
"""Teacher rates, bonuses and deductions, and monthly payslips (P7-1).

Other apps' models are referenced by string: payroll never imports them. A
course and a session are plain ids; sessions are read and locked only through
`etqan.scheduling.services`. Business rules live in `etqan.payroll.services`.
"""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q

CURRENCY = RegexValidator(r"^[A-Z]{3}$")


class PayslipCounter(models.Model):
    """The last payslip number handed out. One row (pk 1) in each academy's
    schema, locked while payslips are generated (plan D2)."""

    last_number = models.PositiveIntegerField(default=0)

    def __str__(self):
        return f"PayslipCounter<{self.last_number}>"


class TeacherRate(models.Model):
    # PROTECT: people are deactivated, never deleted.
    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    # A plain id (P7-1), validated through catalogue's services; null is the
    # teacher's default rate.
    course_id = models.BigIntegerField(null=True, blank=True)
    hourly_rate_minor = models.BigIntegerField(validators=[MinValueValidator(0)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["teacher_id", "course_id", "id"]
        constraints = [
            # One rate per course, and one default (course null) per teacher.
            models.UniqueConstraint(
                fields=["teacher", "course_id"],
                nulls_distinct=False,
                name="payroll_rate_one_per_course",
            ),
            models.CheckConstraint(
                condition=Q(hourly_rate_minor__gte=0),
                name="payroll_rate_not_negative",
            ),
        ]

    def __str__(self):
        return f"TeacherRate<{self.teacher_id}, {self.course_id}>"


class PayAdjustment(models.Model):
    class Kind(models.TextChoices):
        BONUS = "bonus", "Bonus"
        DEDUCTION = "deduction", "Deduction"

    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    kind = models.CharField(max_length=9, choices=Kind.choices)
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    effective_on = models.DateField()  # the academy's calendar
    reason = models.TextField()
    # Set when an issued payslip uses it; from then on it never changes.
    payslip = models.ForeignKey(
        "Payslip",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="adjustments",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-effective_on", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0),
                name="payroll_adjustment_amount_positive",
            )
        ]

    def __str__(self):
        return f"PayAdjustment<{self.kind}, {self.amount_minor}>"


class Payslip(models.Model):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        ISSUED = "issued", "Issued"
        PAID = "paid", "Paid"

    number = models.CharField(max_length=20, unique=True)
    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    year = models.PositiveSmallIntegerField()
    month = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(12)]
    )
    status = models.CharField(
        max_length=6, choices=Status.choices, default=Status.DRAFT
    )
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    gross_minor = models.BigIntegerField(default=0)
    bonuses_minor = models.BigIntegerField(default=0)
    deductions_minor = models.BigIntegerField(default=0)
    net_minor = models.BigIntegerField(default=0)
    missing_rate = models.BooleanField(default=False)
    issued_at = models.DateTimeField(null=True, blank=True)
    issued_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    paid_on = models.DateField(null=True, blank=True)  # the academy's calendar
    paid_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    notes = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-year", "-month", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["teacher", "year", "month"],
                name="payroll_one_payslip_per_teacher_month",
            ),
            models.CheckConstraint(
                condition=Q(month__gte=1, month__lte=12),
                name="payroll_payslip_month_1_to_12",
            ),
        ]
        indexes = [models.Index(fields=["year", "month"])]

    def __str__(self):
        return f"Payslip<{self.number}, {self.status}>"


class PayslipLine(models.Model):
    class Kind(models.TextChoices):
        SESSION = "session", "Session"
        ADJUSTMENT = "adjustment", "Adjustment"

    payslip = models.ForeignKey(Payslip, on_delete=models.CASCADE, related_name="lines")
    kind = models.CharField(max_length=10, choices=Kind.choices)
    # A plain id (P7-1): payroll never imports scheduling's models.
    session_id = models.BigIntegerField(null=True, blank=True)
    # SET_NULL: deleting an unused adjustment leaves a draft's copied line
    # until the next generate; an issued payslip's adjustments are PROTECTed
    # by `PayAdjustment.payslip` and never deleted.
    adjustment = models.ForeignKey(
        PayAdjustment,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    description = models.TextField()
    minutes = models.PositiveSmallIntegerField(null=True, blank=True)
    rate_minor = models.BigIntegerField(null=True, blank=True)
    amount_minor = models.BigIntegerField()  # signed: a deduction is negative

    class Meta:
        ordering = ["id"]

    def __str__(self):
        return f"PayslipLine<{self.kind}, {self.amount_minor}>"
```

Create `backend/etqan/payroll/migrations/__init__.py`:

```python

```

Create `backend/etqan/payroll/services/__init__.py`:

```python
"""Public API of the payroll module. Other apps import only this package."""

__all__: list[str] = []
```

Create `backend/etqan/payroll/services/numbering.py`:

```python
"""Payslip numbers (spec §3.4, plan D2)."""

from etqan.payroll.models import PayslipCounter

NUMBER_FORMAT = "PAY-{:06d}"


def hold() -> PayslipCounter:
    """The academy's one counter row, taken `FOR UPDATE` until the caller's
    transaction ends. Generate holds it from its first statement, so two
    generates for one academy run one after the other and never both create
    the same teacher's payslip; the first call in an academy creates the row
    (`get_or_create` re-reads it under the lock if another request created it
    first). Call it inside a transaction."""
    counter, _ = PayslipCounter.objects.select_for_update().get_or_create(pk=1)
    return counter


def take(counter: PayslipCounter) -> str:
    """The next number, `PAY-000123`, from a counter returned by `hold`. The
    counter moves in the caller's transaction, so a rolled-back payslip gives
    its number back."""
    counter.last_number += 1
    counter.save(update_fields=["last_number"])
    return NUMBER_FORMAT.format(counter.last_number)
```

In `backend/config/settings/base.py`, replace:

```python
    "etqan.scheduling",
    "etqan.billing",
]
INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
```

with:

```python
    "etqan.scheduling",
    "etqan.billing",
    "etqan.payroll",
]
INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
```

In `backend/etqan/scheduling/models.py`, replace:

```python
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

with:

```python
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    # Plan 7 (P7-1): set only by `services.lock_sessions`, when an issued
    # payslip pays this session. Every write path refuses it from then on.
    payroll_locked = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

In `backend/pyproject.toml` (1 of 4), replace:

```toml
type = "forbidden"
source_modules = ["etqan.platform"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing"]

[[tool.importlinter.contracts]]
```

with:

```toml
type = "forbidden"
source_modules = ["etqan.platform"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll"]

[[tool.importlinter.contracts]]
```

In `backend/pyproject.toml` (2 of 4), replace:

```toml
type = "forbidden"
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling", "etqan.billing"]

[[tool.importlinter.contracts]]
```

with:

```toml
type = "forbidden"
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll"]

[[tool.importlinter.contracts]]
```

In `backend/pyproject.toml` (3 of 4), replace:

```toml
name = "other apps reach scheduling only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.billing"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
```

with:

```toml
name = "other apps reach scheduling only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.billing", "etqan.payroll"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
```

In `backend/pyproject.toml` (4 of 4), replace:

```toml
forbidden_modules = ["etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock"]
allow_indirect_imports = true
```

with:

```toml
forbidden_modules = ["etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock"]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "payroll reaches other apps only through their services"
type = "forbidden"
source_modules = ["etqan.payroll"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue.models", "etqan.catalogue.api",
    "etqan.academy.models", "etqan.academy.api",
    "etqan.billing",
    "etqan.tenants", "etqan.site",
]
# payroll.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "scheduling never imports payroll"
type = "forbidden"
# P7-1: scheduling owns the session lock and enforces it on its own; payroll
# calls scheduling, never the reverse, not even from scheduling's API.
source_modules = ["etqan.scheduling"]
forbidden_modules = ["etqan.payroll"]

[[tool.importlinter.contracts]]
name = "other apps reach payroll only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling", "etqan.billing"]
forbidden_modules = ["etqan.payroll.models", "etqan.payroll.api", "etqan.payroll.scopes", "etqan.payroll.clock"]
allow_indirect_imports = true
```

- [ ] **Step 4: Generate the migrations**

Run (from `backend/`):

```bash
.venv/bin/python manage.py makemigrations scheduling --name session_payroll_locked --settings=config.settings.test
.venv/bin/python manage.py makemigrations payroll --settings=config.settings.test
```

Expected: `etqan/scheduling/migrations/0003_session_payroll_locked.py` (one `AddField`) and `etqan/payroll/migrations/0001_initial.py` (the five models, the index on `year, month`, the check constraints and the two unique constraints, one of them `nulls_distinct=False`).

- [ ] **Step 5: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/payroll -q --create-db
```

Expected: 8 passed.

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1009 tests, coverage 97.6% (the gate is 80%).

- [ ] **Step 7: Commit**

```bash
git -C backend add config/settings/base.py pyproject.toml etqan/payroll etqan/scheduling/models.py etqan/scheduling/migrations/0003_session_payroll_locked.py
git -C backend commit -m "feat(payroll): the payroll app, its models and the session's lock flag

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Scheduling: the payroll lock on every session write path

**Files:**
- Create: `backend/etqan/scheduling/services/paylock.py`
- Modify: `backend/etqan/scheduling/services/attendance.py`, `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/api/payloads.py`
- Test: `backend/etqan/scheduling/tests/test_paylock.py` (new), `backend/etqan/scheduling/tests/test_api_sessions.py`, `backend/etqan/scheduling/tests/test_api_session_writes.py`

**Interfaces:**
- Consumes: Task 1's `Session.payroll_locked`.
- Produces (re-exported from `etqan.scheduling.services`, D14):
  - `payroll_sessions(first: date, last: date) -> QuerySet[Session]` — unlocked sessions of those dates with `course` and `student__user`, oldest first;
  - `hold_sessions(*, teacher_id: int, first: date, last: date) -> list[int]` — row locks, id order (`teacher_id` is a TeacherProfile pk);
  - `lock_sessions(ids: Iterable[int]) -> list[int]` — row locks in id order, then `payroll_locked=True`; unknown ids ignored.
- Produces: `paylock.refuse_if_paid(session)` raising `ConflictError(code="payroll.payslip_issued")`, called by `mark_attendance`, `cancel_session` and `restore_session` right after their row lock; `bulk_sessions` skips a locked session with that code.
- Produces: `session_row(…)` gains `payroll_locked`, for admins and the session's own teacher only (`OWN_TEACHER_SESSION_FIELDS`).

- [ ] **Step 1: Write the failing tests**

Each write path is refused on a locked session with the code, and the row is unchanged. Restore is the telling case: a completed session would otherwise be refused for its status, so the test proves the lock is checked first. Bulk skips with the code; cancelling a subscription (`delete_untouched`) and deleting one never reach a locked session. The two new services lock session rows only, in id order, with exact SQL tails.

Create `backend/etqan/scheduling/tests/test_paylock.py`:

```python
"""The payroll lock, owned and enforced by scheduling (Plan 7 spec §4.5)."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

PAID = "payroll.payslip_issued"
JUNE = (date(2026, 6, 1), date(2026, 6, 30))
# Wednesday 3 June, after both of that week's sessions started.
AFTER = datetime(2026, 6, 3, 19, tzinfo=UTC)


def on(sub, day):
    return Session.objects.get(subscription=sub, occurs_on=day)


@pytest.fixture
def paid(subscribe, world, clock):
    """Monday 1 June's session, completed and locked by payroll, plus
    Wednesday 3 June's, completed and not locked."""
    sub = subscribe(slots=two_slots())
    clock.set(AFTER)
    monday, wednesday = on(sub, date(2026, 6, 1)), on(sub, date(2026, 6, 3))
    for session in (monday, wednesday):
        services.mark_attendance(
            session, by=world.teacher, student_attendance="present"
        )
    assert services.lock_sessions([monday.pk]) == [monday.pk]
    return monday, wednesday


def test_lock_sessions_sets_the_flag_on_those_ids_only(paid):
    monday, wednesday = paid
    monday.refresh_from_db()
    wednesday.refresh_from_db()
    assert (monday.payroll_locked, wednesday.payroll_locked) == (True, False)


@pytest.mark.parametrize("path", ["student", "teacher", "cancel", "restore"])
def test_every_single_write_refuses_a_locked_session(paid, path):
    monday, _ = paid
    admin = make_admin()
    writes = {
        "student": lambda: services.mark_attendance(
            monday, by=admin, student_attendance="absent"
        ),
        "teacher": lambda: services.mark_attendance(
            monday, by=admin, teacher_attendance="absent"
        ),
        "cancel": lambda: services.cancel_session(monday, by=admin, reason="Eid"),
        # A completed session would otherwise be refused for its status
        # (`scheduling.not_allowed_in_status`): the lock is checked first.
        "restore": lambda: services.restore_session(monday),
    }
    with pytest.raises(ConflictError) as exc:
        writes[path]()
    assert exc.value.code == PAID
    monday.refresh_from_db()
    assert (monday.status, monday.student_attendance) == ("completed", "present")
    assert monday.teacher_attendance == "not_set"


@pytest.mark.parametrize("action", ["absent", "cancel"])
def test_bulk_skips_a_locked_session_with_its_code(paid, action):
    monday, wednesday = paid
    result = services.bulk_sessions(
        [monday.pk, wednesday.pk], action=action, by=make_admin(), reason="Eid"
    )
    assert result.done == [wednesday.pk]
    assert result.skipped == [(monday.pk, PAID)]
    monday.refresh_from_db()
    assert monday.status == "completed"


def test_automatic_deletion_and_delete_never_reach_a_locked_session(paid, subscribe):
    monday, _ = paid
    # Cancelling the subscription deletes its untouched sessions only.
    services.cancel_subscription(monday.subscription)
    assert Session.objects.filter(pk=monday.pk, payroll_locked=True).exists()
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(
            monday.subscription, before_delete=lambda _pk: None
        )
    assert exc.value.code == "scheduling.has_marked_sessions"
    assert Session.objects.filter(pk=monday.pk).exists()


def test_payroll_reads_only_unlocked_sessions_of_the_range(paid):
    _, wednesday = paid
    sessions = list(services.payroll_sessions(date(2026, 6, 1), date(2026, 6, 8)))
    # Oldest first, Monday's locked one left out, the range's ends included.
    assert [s.occurs_on for s in sessions] == [date(2026, 6, 3), date(2026, 6, 8)]
    assert sessions[0].pk == wednesday.pk


def test_hold_locks_the_teachers_unlocked_sessions_of_the_range(paid, subscribe, world):
    _, wednesday = paid
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    theirs = subscribe(
        student_id=make_student("Aisha").id,
        teacher_id=maryam.id,
        slots=two_slots(),
    )
    teacher_id = world.teacher.teacher_profile.pk
    first_week = (date(2026, 6, 1), date(2026, 6, 7))
    with CaptureQueriesContext(connection) as ctx:
        held = services.hold_sessions(
            teacher_id=teacher_id, first=first_week[0], last=first_week[1]
        )
    # Bilal's unlocked sessions of that week only: not Monday's (locked), not
    # Maryam's, and not the next week's.
    assert held == [wednesday.pk]
    assert not Session.objects.filter(subscription=theirs, pk__in=held).exists()
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert len(locks) == 1
    assert locks[0].split(" FROM ")[1].split()[0] == '"scheduling_session"'
    # Exact, not a bare "ORDER BY": Session's own ordering is `starts_at, id`,
    # and `values_list("pk")` compiles `.order_by("pk")` to "ORDER BY 1".
    assert locks[0].rstrip().endswith("ORDER BY 1 ASC FOR UPDATE")


def test_lock_sessions_takes_session_rows_in_id_order_only(subscribe, clock):
    sub = subscribe(slots=two_slots())
    clock.set(AFTER)
    ids = [on(sub, date(2026, 6, 3)).pk, on(sub, date(2026, 6, 1)).pk]
    with CaptureQueriesContext(connection) as ctx:
        assert services.lock_sessions([*ids, 10**9]) == sorted(ids)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert len(locks) == 1
    assert locks[0].split(" FROM ")[1].split()[0] == '"scheduling_session"'
    assert locks[0].rstrip().endswith("ORDER BY 1 ASC FOR UPDATE")
    # Never a subscription: payroll locks sessions after its payslip only.
    assert not any('"scheduling_subscription"' in sql for sql in locks)
```

In `backend/etqan/scheduling/tests/test_api_sessions.py` (1 of 2), replace:

```python
        False,
    )
    assert row["student"] == {
        "id": sub.student.user_id,
```

with:

```python
        False,
    )
    assert row["payroll_locked"] is False
    assert row["student"] == {
        "id": sub.student.user_id,
```

In `backend/etqan/scheduling/tests/test_api_sessions.py` (2 of 2), replace:

```python
        assert "notes" not in row
        assert "cancel_reason" not in row
        # Only the session's own teacher (and admins) learn whether a report exists.
        assert ("has_report" in row) is (role == "teacher")


```

with:

```python
        assert "notes" not in row
        assert "cancel_reason" not in row
        # Only the session's own teacher (and admins) learn whether a report
        # exists, or whether a payslip has locked the session (Plan 7 §4.7).
        assert ("has_report" in row) is (role == "teacher")
        assert ("payroll_locked" in row) is (role == "teacher")


```

In `backend/etqan/scheduling/tests/test_api_session_writes.py`, replace:

```python
        "code": "scheduling.not_started",
    }


```

with:

```python
        "code": "scheduling.not_started",
    }


def test_a_session_on_an_issued_payslip_is_a_coded_conflict(started, world):
    services.mark_attendance(started, by=world.teacher, student_attendance="present")
    services.lock_sessions([started.pk])
    teacher = as_user(world.teacher)
    mark = teacher.post(
        f"{URL}{started.pk}/attendance/",
        {"teacher_attendance": "absent"},
        format="json",
    )
    assert mark.status_code == 409
    assert mark.json() == {
        "detail": "This session is on an issued payslip.",
        "code": "payroll.payslip_issued",
    }
    cancel = as_user(make_admin()).post(
        f"{URL}{started.pk}/cancel/", {"reason": "Eid"}, format="json"
    )
    assert (cancel.status_code, cancel.json()["code"]) == (
        409,
        "payroll.payslip_issued",
    )
    # The teacher still sees the lock on their own session; the student
    # never learns of it (Plan 7 spec §4.7).
    assert teacher.get(f"{URL}{started.pk}/").json()["payroll_locked"] is True
    detail = as_user(world.student).get(f"{URL}{started.pk}/")
    assert detail.status_code == 200
    assert "payroll_locked" not in detail.json()


```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/scheduling/tests/test_paylock.py etqan/scheduling/tests/test_api_sessions.py etqan/scheduling/tests/test_api_session_writes.py -q`

Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'lock_sessions'`, and `KeyError: 'payroll_locked'` in the payload tests.

- [ ] **Step 3: Implement**

Create `backend/etqan/scheduling/services/paylock.py`:

```python
"""The payroll lock (Plan 7 P7-1, spec §4.5). Scheduling owns it: payroll
reads sessions and locks them only through these services, and every write
path in `attendance` refuses a locked session. Scheduling never imports
payroll."""

from collections.abc import Iterable
from datetime import date

from django.db import transaction
from django.db.models import QuerySet

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import dates
from etqan.scheduling.models import Session

PAYSLIP_ISSUED = "payroll.payslip_issued"


def refuse_if_paid(session: Session) -> None:
    """Spec §4.5: a session an issued payslip pays takes no attendance
    change, cancel or restore. Call it on the locked, fresh row."""
    if session.payroll_locked:
        raise ConflictError(
            "This session is on an issued payslip.", code=PAYSLIP_ISSUED
        )


def payroll_sessions(first: date, last: date) -> QuerySet[Session]:
    """Sessions dated ``first`` to ``last`` (the academy's calendar) that no
    issued payslip has locked, with the course and student a payslip line
    names, oldest first. Payroll applies its own pay rule (P7-2) on top."""
    return (
        Session.objects.filter(occurs_on__range=(first, last), payroll_locked=False)
        .select_related("course", "student__user")
        .order_by("starts_at", "id")
    )


@transaction.atomic
def hold_sessions(*, teacher_id: int, first: date, last: date) -> list[int]:
    """Take `FOR UPDATE`, in id order, the rows of the teacher's sessions
    (``teacher_id`` is a TeacherProfile id) dated ``first`` to ``last`` that no
    payslip has locked; return their ids. Payroll's issue holds them before it
    rebuilds the payslip, so no attendance, cancel or restore changes one
    between the payslip's read and `lock_sessions` (Plan 7 D1). Only session
    rows are locked, never a subscription."""
    return list(
        Session.objects.select_for_update()
        .filter(teacher_id=teacher_id, occurs_on__range=(first, last))
        .filter(payroll_locked=False)
        .order_by("pk")
        .values_list("pk", flat=True)
    )


@transaction.atomic
def lock_sessions(ids: Iterable[int]) -> list[int]:
    """Mark these sessions paid by an issued payslip (P7-1): their rows are
    taken `FOR UPDATE` in id order — the order every session locker uses —
    and ``payroll_locked`` is set. Returns the ids locked; an id this academy
    does not have is ignored."""
    locked = list(
        Session.objects.select_for_update()
        .filter(pk__in=sorted(set(ids)))
        .order_by("pk")
        .values_list("pk", flat=True)
    )
    Session.objects.filter(pk__in=locked).update(
        payroll_locked=True, updated_at=dates.now()
    )
    return locked
```

In `backend/etqan/scheduling/services/attendance.py` (1 of 6), replace:

```python
from etqan.scheduling import dates
from etqan.scheduling.models import Session

SCHEDULED = Session.Status.SCHEDULED
```

with:

```python
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.services.paylock import refuse_if_paid

SCHEDULED = Session.Status.SCHEDULED
```

In `backend/etqan/scheduling/services/attendance.py` (2 of 6), replace:

```python
    """Spec §4.1. A student mark completes a scheduled session; clearing an
    attendance back to ``not_set`` is an undo, and only an admin undoes
    (plan D7). The teacher's attendance never changes the status."""
    if student_attendance is None and teacher_attendance is None:
        raise ValidationError(
```

with:

```python
    """Spec §4.1. A student mark completes a scheduled session; clearing an
    attendance back to ``not_set`` is an undo, and only an admin undoes
    (plan D7). The teacher's attendance never changes the status. A session
    an issued payslip pays is refused first (Plan 7 spec §4.5)."""
    if student_attendance is None and teacher_attendance is None:
        raise ValidationError(
```

In `backend/etqan/scheduling/services/attendance.py` (3 of 6), replace:

```python
        )
    locked = lock(session)
    if locked.status == CANCELLED:
        raise ConflictError(
```

with:

```python
        )
    locked = lock(session)
    refuse_if_paid(locked)
    if locked.status == CANCELLED:
        raise ConflictError(
```

In `backend/etqan/scheduling/services/attendance.py` (4 of 6), replace:

```python
def cancel_session(session: Session, *, by, reason: str) -> Session:
    """Spec §4.3: from scheduled, or from completed (it stops counting).
    Attendance and any report are kept, for the record."""
    reason = (reason or "").strip()
    if not reason:
        raise ValidationError("Give a reason.", field="reason")
    locked = lock(session)
    if locked.status not in (SCHEDULED, COMPLETED):
        raise _not_allowed(locked)
```

with:

```python
def cancel_session(session: Session, *, by, reason: str) -> Session:
    """Spec §4.3: from scheduled, or from completed (it stops counting).
    Attendance and any report are kept, for the record. Never once an issued
    payslip pays the session (Plan 7 spec §4.5)."""
    reason = (reason or "").strip()
    if not reason:
        raise ValidationError("Give a reason.", field="reason")
    locked = lock(session)
    refuse_if_paid(locked)
    if locked.status not in (SCHEDULED, COMPLETED):
        raise _not_allowed(locked)
```

In `backend/etqan/scheduling/services/attendance.py` (5 of 6), replace:

```python
    reusing `mark_attendance` or `cancel_session` on the already-locked row
    inside its own savepoint, so one session's refusal never undoes another's
    change; the refusal's own code is the skip code."""
    if action not in BULK_ACTIONS:
        raise ValidationError("Choose present, absent or cancel.", field="action")
```

with:

```python
    reusing `mark_attendance` or `cancel_session` on the already-locked row
    inside its own savepoint, so one session's refusal never undoes another's
    change; the refusal's own code is the skip code (a session on an issued
    payslip is skipped as ``payroll.payslip_issued``)."""
    if action not in BULK_ACTIONS:
        raise ValidationError("Choose present, absent or cancel.", field="action")
```

In `backend/etqan/scheduling/services/attendance.py` (6 of 6), replace:

```python
def restore_session(session: Session) -> Session:
    """Spec §4.3: back to scheduled, or to completed when the student's
    attendance is set; the cancel fields are cleared."""
    locked = lock(session)
    if locked.status != CANCELLED:
        raise _not_allowed(locked)
```

with:

```python
def restore_session(session: Session) -> Session:
    """Spec §4.3: back to scheduled, or to completed when the student's
    attendance is set; the cancel fields are cleared. A session an issued
    payslip pays is refused before its status is looked at (Plan 7 spec
    §4.5)."""
    locked = lock(session)
    refuse_if_paid(locked)
    if locked.status != CANCELLED:
        raise _not_allowed(locked)
```

In `backend/etqan/scheduling/services/__init__.py` (1 of 2), replace:

```python
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.reports import can_read_report
from etqan.scheduling.services.reports import get_report
```

with:

```python
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.paylock import hold_sessions
from etqan.scheduling.services.paylock import lock_sessions
from etqan.scheduling.services.paylock import payroll_sessions
from etqan.scheduling.services.reports import can_read_report
from etqan.scheduling.services.reports import get_report
```

In `backend/etqan/scheduling/services/__init__.py` (2 of 2), replace:

```python
    "has_started",
    "has_subscriptions",
    "lock_subscription",
    "mark_attendance",
    "missing_reports",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
```

with:

```python
    "has_started",
    "has_subscriptions",
    "hold_sessions",
    "lock_sessions",
    "lock_subscription",
    "mark_attendance",
    "missing_reports",
    "pause_state",
    "payroll_sessions",
    "renew_subscription",
    "renewal_starts_on",
```

In `backend/etqan/scheduling/api/payloads.py` (1 of 4), replace:

```python

STAFF_ONLY_SESSION_FIELDS = ("notes", "cancel_reason")


```

with:

```python

STAFF_ONLY_SESSION_FIELDS = ("notes", "cancel_reason")
# For admins and the session's own teacher only (P5-2; Plan 7 spec §4.7).
OWN_TEACHER_SESSION_FIELDS = ("has_report", "payroll_locked")


```

In `backend/etqan/scheduling/api/payloads.py` (2 of 4), replace:

```python
    """Plan 5 spec §4.6: everyone in scope sees the times, link, status and
    both attendances; ``notes`` and ``cancel_reason`` are admin-only, and
    ``has_report`` is for admins and the session's own teacher. ``viewer`` is
    the signed-in user and has no default, so a caller can't forget it. Read
    ``session`` from `services.sessions_queryset()` (it carries
    ``has_report``)."""
    row = {
        "id": session.pk,
```

with:

```python
    """Plan 5 spec §4.6: everyone in scope sees the times, link, status and
    both attendances; ``notes`` and ``cancel_reason`` are admin-only, and
    ``has_report`` and ``payroll_locked`` are for admins and the session's own
    teacher. ``viewer`` is the signed-in user and has no default, so a caller
    can't forget it. Read ``session`` from `services.sessions_queryset()` (it
    carries ``has_report``)."""
    row = {
        "id": session.pk,
```

In `backend/etqan/scheduling/api/payloads.py` (3 of 4), replace:

```python
        "cancel_reason": session.cancel_reason,
        "has_report": session.has_report,
    }
    if role_of(viewer) != "admin":
```

with:

```python
        "cancel_reason": session.cancel_reason,
        "has_report": session.has_report,
        "payroll_locked": session.payroll_locked,
    }
    if role_of(viewer) != "admin":
```

In `backend/etqan/scheduling/api/payloads.py` (4 of 4), replace:

```python
            row.pop(field)
    if not services.can_read_report(viewer, session):
        row.pop("has_report")
    return row

```

with:

```python
            row.pop(field)
    if not services.can_read_report(viewer, session):
        for field in OWN_TEACHER_SESSION_FIELDS:
            row.pop(field)
    return row

```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/scheduling -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1021 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/scheduling
git -C backend commit -m "feat(scheduling): the payroll lock on every session write path

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Rates and adjustments, in the teacher's current currency

**Files:**
- Create: `backend/etqan/payroll/services/rules.py`, `backend/etqan/payroll/services/rates.py`, `backend/etqan/payroll/services/adjustments.py`
- Modify: `backend/etqan/payroll/services/__init__.py`
- Test: `backend/etqan/payroll/tests/conftest.py`, `backend/etqan/payroll/tests/test_rates_adjustments.py` (new)

**Interfaces:**
- Consumes: Task 1's models; `identity_services.get_teacher_profile(user_id)`, `catalogue_services.get_course(course_id)`.
- Produces (re-exported from `etqan.payroll.services`):
  - `create_rate(*, teacher_id: int, hourly_rate_minor: int, course_id: int | None = None) -> TeacherRate` (400 on `teacher`, `course` or `hourly_rate_minor`; a duplicate is a 400 on `course`);
  - `update_rate(rate, *, hourly_rate_minor: int) -> TeacherRate` (row lock; re-stamps the teacher's current currency);
  - `delete_rate(rate) -> None`; `rates_queryset() -> QuerySet[TeacherRate]` (teacher name, default first);
  - `create_adjustment(*, teacher_id, kind, amount_minor, effective_on, reason, by) -> PayAdjustment`;
  - `update_adjustment(adjustment, *, kind=None, amount_minor=None, effective_on=None, reason=None) -> PayAdjustment` and `delete_adjustment(adjustment) -> None` (row lock; 409 `payroll.adjustment_used` once a payslip used it);
  - `adjustments_queryset()`, `filter_adjustments(adjustments, *, teacher: int | None = None, used: bool | None = None)`.
- Produces: `rules.teacher_of(user_id, *, field="teacher")`, `rules.check(obj, *, exclude=())`, `rules.save(obj, update_fields=None)`; `adjustments.lock(adjustment)` and `adjustments.refuse_if_used(adjustment)`.
- Produces (tests): `conftest.set_rate(teacher, hourly, *, course=None)` and `conftest.adjust(teacher, kind, amount, *, on, **fields)`, both through the services.

- [ ] **Step 1: Write the failing tests**

A rate and an adjustment take the teacher's current `pay_currency`; editing either moves it to the current one. A used adjustment never changes, even from a copy read before it was used. Edits lock only their own row (exact tails).

In `backend/etqan/payroll/tests/conftest.py` (1 of 2), replace:

```python

from etqan.payroll import clock as payroll_clock
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import Clock as SchedulingClock
```

with:

```python

from etqan.payroll import clock as payroll_clock
from etqan.payroll import services
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import Clock as SchedulingClock
```

In `backend/etqan/payroll/tests/conftest.py` (2 of 2), replace:

```python
        session, by=by, student_attendance=student, teacher_attendance=teacher
    )
```

with:

```python
        session, by=by, student_attendance=student, teacher_attendance=teacher
    )


def set_rate(teacher, hourly, *, course=None):
    """``teacher``'s (a User) default rate, or ``course``'s."""
    return services.create_rate(
        teacher_id=teacher.id,
        hourly_rate_minor=hourly,
        course_id=course.pk if course else None,
    )


def adjust(teacher, kind, amount, *, on, **fields):
    """A bonus or deduction for ``teacher`` (a User), effective ``on``."""
    return services.create_adjustment(
        teacher_id=teacher.id,
        kind=kind,
        amount_minor=amount,
        effective_on=on,
        **{"reason": "Extra", "by": None, **fields},
    )
```

Create `backend/etqan/payroll/tests/test_rates_adjustments.py`:

```python
"""Rates and adjustments (spec §4.6): the teacher's current currency, one
rate per course, and adjustments frozen once used."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.models import TeacherRate
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import set_rate
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_student

JUNE_15 = date(2026, 6, 15)


def pay_in(teacher, currency):
    identity_services.update_person(teacher, profile={"pay_currency": currency})


def lock_sql(ctx):
    return [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]


# ── Rates ────────────────────────────────────────────────────────────────────


def test_a_rate_is_in_the_teachers_current_currency(world):
    pay_in(world.teacher, "EGP")
    default = set_rate(world.teacher, 40000)
    tajweed = set_rate(world.teacher, 50000, course=world.course)
    assert (default.course_id, default.currency) == (None, "EGP")
    assert (tajweed.course_id, tajweed.currency) == (world.course.pk, "EGP")


@pytest.mark.parametrize("course", [False, True])
def test_one_default_and_one_rate_per_course(world, course):
    first = set_rate(world.teacher, 1000, course=world.course if course else None)
    with pytest.raises(ValidationError) as exc:
        set_rate(world.teacher, 2000, course=world.course if course else None)
    assert exc.value.field == "course"
    assert list(TeacherRate.objects.values_list("pk", flat=True)) == [first.pk]


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"course_id": 10**9}, "course"),
        ({"hourly_rate_minor": -1}, "hourly_rate_minor"),
        ({"teacher_id": 10**9}, "teacher"),
    ],
)
def test_a_bad_rate_is_a_field_error(world, fields, field):
    body = {
        "teacher_id": world.teacher.id,
        "hourly_rate_minor": 1000,
        **fields,
    }
    with pytest.raises(ValidationError) as exc:
        services.create_rate(**body)
    assert exc.value.field == field


def test_a_student_is_not_a_teacher(world):
    with pytest.raises(ValidationError) as exc:
        services.create_rate(teacher_id=make_student("Aisha").id, hourly_rate_minor=1)
    assert exc.value.field == "teacher"


def test_editing_a_rate_moves_it_to_the_current_currency(world):
    rate = set_rate(world.teacher, 1000)
    pay_in(world.teacher, "EGP")
    with CaptureQueriesContext(connection) as ctx:
        edited = services.update_rate(rate, hourly_rate_minor=40000)
    assert (edited.hourly_rate_minor, edited.currency) == (40000, "EGP")
    (lock,) = lock_sql(ctx)
    assert lock.endswith(
        f'WHERE "payroll_teacherrate"."id" = {rate.pk} LIMIT 21 '
        'FOR UPDATE OF "payroll_teacherrate"'
    )
    services.delete_rate(rate)
    assert not TeacherRate.objects.exists()


def test_rates_list_by_teacher_name_default_first(world):
    course_rate = set_rate(world.teacher, 2000, course=world.course)
    default = set_rate(world.teacher, 1000)
    assert list(services.rates_queryset()) == [default, course_rate]


# ── Adjustments ──────────────────────────────────────────────────────────────


def test_an_adjustment_is_in_the_teachers_current_currency(world, admin):
    pay_in(world.teacher, "EGP")
    bonus = adjust(world.teacher, "bonus", 500, on=JUNE_15, by=admin, reason=" Eid ")
    assert (bonus.currency, bonus.reason, bonus.created_by) == ("EGP", "Eid", admin)


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"amount_minor": 0}, "amount_minor"),
        ({"kind": "gift"}, "kind"),
        ({"reason": "  "}, "reason"),
    ],
)
def test_a_bad_adjustment_is_a_field_error(world, fields, field):
    body = {
        "teacher_id": world.teacher.id,
        "kind": "bonus",
        "amount_minor": 500,
        "effective_on": JUNE_15,
        "reason": "Extra",
        "by": None,
        **fields,
    }
    with pytest.raises(ValidationError) as exc:
        services.create_adjustment(**body)
    assert exc.value.field == field


def test_an_unused_adjustment_is_edited_in_the_current_currency(world):
    bonus = adjust(world.teacher, "bonus", 500, on=JUNE_15)
    pay_in(world.teacher, "EGP")
    with CaptureQueriesContext(connection) as ctx:
        edited = services.update_adjustment(bonus, kind="deduction", amount_minor=700)
    assert (edited.kind, edited.amount_minor, edited.currency) == (
        "deduction",
        700,
        "EGP",
    )
    assert (edited.reason, edited.effective_on) == ("Extra", JUNE_15)
    (lock,) = lock_sql(ctx)
    assert lock.endswith(
        f'WHERE "payroll_payadjustment"."id" = {bonus.pk} LIMIT 21 '
        'FOR UPDATE OF "payroll_payadjustment"'
    )


@pytest.mark.parametrize("write", ["edit", "delete"])
def test_a_used_adjustment_never_changes(world, write):
    bonus = adjust(world.teacher, "bonus", 500, on=JUNE_15)
    stale = PayAdjustment.objects.get(pk=bonus.pk)  # read before it was used
    PayAdjustment.objects.filter(pk=bonus.pk).update(
        payslip=Payslip.objects.create(
            number="PAY-000001",
            teacher=world.teacher.teacher_profile,
            year=2026,
            month=6,
            currency="USD",
            status="issued",
        )
    )
    writes = {
        "edit": lambda: services.update_adjustment(stale, amount_minor=1),
        "delete": lambda: services.delete_adjustment(stale),
    }
    with pytest.raises(ConflictError) as exc:
        writes[write]()
    assert exc.value.code == "payroll.adjustment_used"
    bonus.refresh_from_db()
    assert bonus.amount_minor == 500


def test_an_unused_adjustment_is_deleted(world):
    services.delete_adjustment(adjust(world.teacher, "bonus", 500, on=JUNE_15))
    assert not PayAdjustment.objects.exists()


def test_the_adjustment_filters(world):
    maryam = identity_services.create_person(
        "teacher", full_name="Maryam", profile={"gender": "female"}
    )
    mine = adjust(world.teacher, "bonus", 500, on=JUNE_15)
    theirs = adjust(maryam, "deduction", 100, on=date(2026, 6, 20))
    PayAdjustment.objects.filter(pk=theirs.pk).update(
        payslip=Payslip.objects.create(
            number="PAY-000001",
            teacher=maryam.teacher_profile,
            year=2026,
            month=6,
            currency="USD",
        )
    )

    def ids(**query):
        found = services.filter_adjustments(services.adjustments_queryset(), **query)
        return [a.pk for a in found]

    assert ids() == [theirs.pk, mine.pk]
    assert ids(teacher=world.teacher.id) == [mine.pk]
    assert ids(used=True) == [theirs.pk]
    assert ids(used=False) == [mine.pk]
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/payroll/tests/test_rates_adjustments.py -q`

Expected: FAIL — `ImportError: cannot import name 'services' from 'etqan.payroll'` or `AttributeError: … has no attribute 'create_rate'`.

- [ ] **Step 3: Implement**

Create `backend/etqan/payroll/services/rules.py`:

```python
"""The rules every payslip follows (spec §4.1). One implementation each."""

from django.core.exceptions import ValidationError as DjangoValidationError

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import from_django


def teacher_of(user_id: int, *, field: str = "teacher"):
    """A teacher's profile, active or not, by User id (people are User ids in
    the API); otherwise a 400 on ``field``."""
    profile = identity_services.get_teacher_profile(user_id)
    if profile is None or profile.user.role != "teacher":
        raise ValidationError("Choose a teacher.", field=field)
    return profile


def check(obj, *, exclude=()) -> None:
    """Field checks with readable messages, as 400s on their fields."""
    try:
        obj.full_clean(exclude=list(exclude), validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None


def save(obj, update_fields=None) -> None:
    check(obj)
    obj.save(update_fields=update_fields)
```

Create `backend/etqan/payroll/services/rates.py`:

```python
"""Teacher rates (spec §3.2, §4.6): a default and per-course hourly rates,
each saved in the teacher's current `pay_currency`."""

from django.db import IntegrityError
from django.db import transaction
from django.db.models import F
from django.db.models import QuerySet

from etqan.catalogue import services as catalogue_services
from etqan.payroll.models import TeacherRate
from etqan.payroll.services import rules
from etqan.platform.exceptions import ValidationError


def _insert(rate: TeacherRate) -> None:
    """One rate per course and one default per teacher: the database's
    unique constraint decides, so two admins adding the same rate at once
    get a 400, not a 500."""
    try:
        with transaction.atomic():
            rate.save()
    except IntegrityError:
        raise ValidationError(
            "This teacher already has this rate. Edit it instead.", field="course"
        ) from None


@transaction.atomic
def create_rate(
    *, teacher_id: int, hourly_rate_minor: int, course_id: int | None = None
) -> TeacherRate:
    """A default rate (no course) or a course's rate, for a teacher by User
    id, in their current `pay_currency`."""
    teacher = rules.teacher_of(teacher_id)
    if course_id is not None and catalogue_services.get_course(course_id) is None:
        raise ValidationError("Choose a course.", field="course")
    rate = TeacherRate(
        teacher=teacher,
        course_id=course_id,
        hourly_rate_minor=hourly_rate_minor,
        currency=teacher.pay_currency,
    )
    rules.check(rate)
    _insert(rate)
    return rate


def _lock(rate: TeacherRate) -> TeacherRate:
    """The rate's row, `FOR UPDATE` and read fresh, with its teacher."""
    return (
        TeacherRate.objects.select_for_update(of=("self",))
        .select_related("teacher")
        .get(pk=rate.pk)
    )


@transaction.atomic
def update_rate(rate: TeacherRate, *, hourly_rate_minor: int) -> TeacherRate:
    """Spec §4.6: editable at any time (issued payslips keep their copied
    rates). It is saved in the teacher's current `pay_currency`, so editing a
    rate left in an old currency makes it count again."""
    locked = _lock(rate)
    locked.hourly_rate_minor = hourly_rate_minor
    locked.currency = locked.teacher.pay_currency
    rules.save(locked, update_fields=["hourly_rate_minor", "currency", "updated_at"])
    return locked


@transaction.atomic
def delete_rate(rate: TeacherRate) -> None:
    _lock(rate).delete()


def rates_queryset() -> QuerySet[TeacherRate]:
    """Rates with their teacher, by teacher name, each teacher's default
    first."""
    return TeacherRate.objects.select_related("teacher__user").order_by(
        "teacher__user__full_name",
        "teacher_id",
        F("course_id").asc(nulls_first=True),
    )
```

Create `backend/etqan/payroll/services/adjustments.py`:

```python
"""Bonuses and deductions (spec §3.3, §4.6): editable and deletable only
while no issued payslip has used them."""

from datetime import date

from django.db import transaction
from django.db.models import QuerySet

from etqan.payroll.models import PayAdjustment
from etqan.payroll.services import rules
from etqan.platform.exceptions import ConflictError


def refuse_if_used(adjustment: PayAdjustment) -> None:
    if adjustment.payslip_id is not None:
        raise ConflictError(
            "This adjustment is on an issued payslip.", code="payroll.adjustment_used"
        )


def lock(adjustment: PayAdjustment) -> PayAdjustment:
    """The adjustment's row, `FOR UPDATE` and read fresh, with its teacher.
    Issue locks the adjustments it uses too, so an edit and an issue never
    interleave: whichever locks second sees the other's result."""
    return (
        PayAdjustment.objects.select_for_update(of=("self",))
        .select_related("teacher")
        .get(pk=adjustment.pk)
    )


@transaction.atomic
def create_adjustment(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    *,
    teacher_id: int,
    kind: str,
    amount_minor: int,
    effective_on: date,
    reason: str,
    by,
) -> PayAdjustment:
    """A bonus or a deduction for a teacher by User id, in their current
    `pay_currency`."""
    teacher = rules.teacher_of(teacher_id)
    adjustment = PayAdjustment(
        teacher=teacher,
        kind=kind,
        amount_minor=amount_minor,
        currency=teacher.pay_currency,
        effective_on=effective_on,
        reason=reason.strip(),
        created_by=by,
    )
    rules.save(adjustment)
    return adjustment


@transaction.atomic
def update_adjustment(
    adjustment: PayAdjustment,
    *,
    kind: str | None = None,
    amount_minor: int | None = None,
    effective_on: date | None = None,
    reason: str | None = None,
) -> PayAdjustment:
    """Only while unused (409 `payroll.adjustment_used`); saved in the
    teacher's current `pay_currency`. Only the edited columns are written."""
    locked = lock(adjustment)
    refuse_if_used(locked)
    edits = {
        "kind": kind,
        "amount_minor": amount_minor,
        "effective_on": effective_on,
        "reason": reason.strip() if reason is not None else None,
    }
    changed = [name for name, value in edits.items() if value is not None]
    for name in changed:
        setattr(locked, name, edits[name])
    locked.currency = locked.teacher.pay_currency
    rules.save(locked, update_fields=[*changed, "currency"])
    return locked


@transaction.atomic
def delete_adjustment(adjustment: PayAdjustment) -> None:
    """Only while unused (409 `payroll.adjustment_used`)."""
    locked = lock(adjustment)
    refuse_if_used(locked)
    locked.delete()


def adjustments_queryset() -> QuerySet[PayAdjustment]:
    """Adjustments with everything a row shows, in one query."""
    return PayAdjustment.objects.select_related(
        "teacher__user", "payslip", "created_by"
    )


def filter_adjustments(
    adjustments: QuerySet[PayAdjustment],
    *,
    teacher: int | None = None,
    used: bool | None = None,
) -> QuerySet[PayAdjustment]:
    """The list's filters (spec §5): a teacher by User id, and used or not;
    newest first."""
    if teacher is not None:
        adjustments = adjustments.filter(teacher__user_id=teacher)
    if used is not None:
        adjustments = adjustments.filter(payslip__isnull=not used)
    return adjustments.order_by("-effective_on", "-id")
```

Replace the whole of `backend/etqan/payroll/services/__init__.py` with:

```python
"""Public API of the payroll module. Other apps import only this package."""

from etqan.payroll.services.adjustments import adjustments_queryset
from etqan.payroll.services.adjustments import create_adjustment
from etqan.payroll.services.adjustments import delete_adjustment
from etqan.payroll.services.adjustments import filter_adjustments
from etqan.payroll.services.adjustments import update_adjustment
from etqan.payroll.services.rates import create_rate
from etqan.payroll.services.rates import delete_rate
from etqan.payroll.services.rates import rates_queryset
from etqan.payroll.services.rates import update_rate

__all__ = [
    "adjustments_queryset",
    "create_adjustment",
    "create_rate",
    "delete_adjustment",
    "delete_rate",
    "filter_adjustments",
    "rates_queryset",
    "update_adjustment",
    "update_rate",
]
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/payroll -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1039 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/payroll
git -C backend commit -m "feat(payroll): teacher rates and bonuses and deductions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The pay rule, the amount formula and the one build function

**Files:**
- Create: `backend/etqan/payroll/services/build.py`
- Modify: `backend/etqan/payroll/services/rules.py`
- Test: `backend/etqan/payroll/tests/test_build.py` (new)

**Interfaces:**
- Consumes: Task 2's `scheduling_services.payroll_sessions`; Task 3's `rules.teacher_of`, `check`, `save` and the conftest helpers; `academy_services.get_settings().default_language`.
- Produces in `rules`: `PAYS: Q` (P7-2), `round_half_up(numerator, denominator) -> int`, `session_amount(rate_minor, minutes) -> int`, `month_bounds(year, month) -> tuple[date, date]`, `month_over(year, month) -> bool`, `current_rates(teacher) -> dict[int | None, int]`, `rate_for(rates, course_id) -> int | None`, `pending_adjustments(last: date) -> QuerySet[PayAdjustment]`, `other_currency_adjustments(last: date) -> QuerySet[PayAdjustment]`.
- Produces in `build`: `Line(kind, description, amount_minor, session_id=None, adjustment_id=None, minutes=None, rate_minor=None)`, `Built(currency, lines, gross_minor, bonuses_minor, deductions_minor, net_minor, missing_rate)` with `.session_ids` and `.adjustment_ids`, and `build(teacher: TeacherProfile, year: int, month: int) -> Built`.

- [ ] **Step 1: Write the failing tests**

The pay rule runs through every student × teacher attendance (12 completed combinations), and a scheduled or cancelled session never pays. A course's rate beats the default, a missing rate is a line of 0 with `missing_rate`, and the formula rounds half up in integers (a 999,999,999-an-hour rate for 240 minutes included). Adjustments count up to the month's last day, once, in the current currency. Copied text is in the academy's language.

Create `backend/etqan/payroll/tests/test_build.py`:

```python
"""Building a teacher's month (spec §4.1): the pay rule, rates, rounding,
adjustments and currency."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.payroll.models import Payslip
from etqan.payroll.services import rules
from etqan.payroll.services.build import build
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)


def june(teacher):
    teacher.teacher_profile.refresh_from_db()
    return build(teacher.teacher_profile, 2026, 6)


@pytest.fixture
def sessions(world, clock):
    """Bilal's nine June sessions, all started (it is 1 July)."""
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


# ── The pay rule (P7-2) ──────────────────────────────────────────────────────


@pytest.mark.parametrize("student", ["present", "absent", "excused"])
@pytest.mark.parametrize(
    ("teacher", "pays"),
    [("present", True), ("not_set", True), ("absent", False), ("excused", False)],
)
def test_the_pay_rule_for_every_attendance(world, sessions, student, teacher, pays):
    set_rate(world.teacher, 1000)
    if teacher == "not_set":
        scheduling_services.mark_attendance(
            sessions[0], by=world.teacher, student_attendance=student
        )
    else:
        mark(sessions[0], world.teacher, student=student, teacher=teacher)
    built = june(world.teacher)
    assert built.session_ids == ([sessions[0].pk] if pays else [])
    assert built.gross_minor == (750 if pays else 0)


def test_a_session_not_completed_or_cancelled_never_pays(world, sessions):
    set_rate(world.teacher, 1000)
    admin = identity_services.create_academy_admin(
        "amina@admins.test", full_name="Amina", password="pw-12345678"
    )
    # Teacher present, student not marked: still scheduled.
    scheduling_services.mark_attendance(
        sessions[0], by=world.teacher, teacher_attendance="present"
    )
    mark(sessions[1], world.teacher)
    scheduling_services.cancel_session(sessions[1], by=admin, reason="Eid")
    assert june(world.teacher).session_ids == []


def test_only_this_teachers_sessions_of_the_month_that_no_payslip_locked(
    world, sessions
):
    set_rate(world.teacher, 1000)
    for session in sessions[:3]:
        mark(session, world.teacher)
    scheduling_services.lock_sessions([sessions[0].pk])
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    theirs = june_sessions(
        world, student_id=make_student("Aisha").id, teacher_id=maryam.id
    )
    mark(theirs[0], maryam)
    assert june(world.teacher).session_ids == [sessions[1].pk, sessions[2].pk]
    assert build(maryam.teacher_profile, 2026, 7).lines == ()


# ── Rates and rounding ───────────────────────────────────────────────────────


def test_the_courses_rate_wins_over_the_default(world, sessions):
    hifz = catalogue_services.create_course(
        name_ar="تحفيظ", name_en="Hifz", teacher_ids=[world.teacher.id]
    )
    set_rate(world.teacher, 1000)
    set_rate(world.teacher, 2000, course=world.course)
    other = june_sessions(world, course_id=hifz.pk)
    mark(sessions[0], world.teacher)
    mark(other[0], world.teacher)
    built = june(world.teacher)
    # Tajweed at its own rate; Hifz, with no rate of its own, at the default.
    assert [(line.rate_minor, line.amount_minor) for line in built.lines] == [
        (2000, 1500),
        (1000, 750),
    ]
    assert (built.gross_minor, built.missing_rate) == (2250, False)


def test_no_rate_is_a_line_of_zero_and_a_missing_rate(world, sessions):
    mark(sessions[0], world.teacher)
    built = june(world.teacher)
    (line,) = built.lines
    assert (line.rate_minor, line.amount_minor, line.minutes) == (None, 0, 45)
    assert (built.gross_minor, built.missing_rate) == (0, True)


@pytest.mark.parametrize(
    ("hourly", "minutes", "amount"),
    [
        (1000, 45, 750),  # exact
        (1001, 45, 751),  # 750.75
        (1002, 45, 752),  # 751.5: half goes up
        (1, 30, 1),  # 0.5
        (1, 15, 0),  # 0.25
        (0, 60, 0),  # a zero rate is a rate
        (999_999_999, 240, 3_999_999_996),  # no float anywhere
    ],
)
def test_the_one_amount_formula_rounds_half_up_in_integers(hourly, minutes, amount):
    assert rules.session_amount(hourly, minutes) == amount


def test_the_amount_uses_the_sessions_own_minutes(world, sessions):
    set_rate(world.teacher, 1002)
    mark(sessions[0], world.teacher)
    assert june(world.teacher).lines[0].amount_minor == 752


# ── Adjustments and totals ───────────────────────────────────────────────────


def test_pending_adjustments_up_to_the_months_last_day(world, sessions):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    may = adjust(world.teacher, "bonus", 500, on=date(2026, 5, 20))
    last = adjust(world.teacher, "deduction", 200, on=date(2026, 6, 30))
    adjust(world.teacher, "bonus", 900, on=date(2026, 7, 1))
    used = adjust(world.teacher, "bonus", 300, on=date(2026, 6, 2))
    used.payslip = Payslip.objects.create(
        number="PAY-000001",
        teacher=world.teacher.teacher_profile,
        year=2026,
        month=5,
        currency="USD",
    )
    used.save()
    built = june(world.teacher)
    assert built.adjustment_ids == [may.pk, last.pk]
    assert [line.amount_minor for line in built.lines] == [750, 500, -200]
    assert (built.gross_minor, built.bonuses_minor, built.deductions_minor) == (
        750,
        500,
        200,
    )
    assert built.net_minor == 1050


def test_a_net_can_be_negative_while_a_draft(world, sessions):
    adjust(world.teacher, "deduction", 200, on=date(2026, 6, 15))
    assert june(world.teacher).net_minor == -200


def test_copied_text_is_in_the_academys_language(world, sessions):
    academy_services.update_settings(default_language="ar")
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    adjust(world.teacher, "deduction", 200, on=date(2026, 6, 15), reason="تأخير")
    session_line, adjustment_line = june(world.teacher).lines
    assert session_line.description == "2026-06-01 — تجويد — Yusuf"
    assert adjustment_line.description == "خصم — تأخير"
    academy_services.update_settings(default_language="en")
    assert june(world.teacher).lines[0].description == "2026-06-01 — Tajweed — Yusuf"


# ── Currency (P7-3, spec §4.6) ───────────────────────────────────────────────


def test_a_pay_currency_change_drops_old_rates_and_adjustments(world, sessions):
    set_rate(world.teacher, 1000)
    adjust(world.teacher, "bonus", 500, on=date(2026, 6, 15))
    mark(sessions[0], world.teacher)
    identity_services.update_person(world.teacher, profile={"pay_currency": "EGP"})
    built = june(world.teacher)
    # The USD rate and bonus no longer count: the line is 0, a rate is missing.
    assert built.currency == "EGP"
    assert [line.amount_minor for line in built.lines] == [0]
    assert built.missing_rate is True
    assert rules.other_currency_adjustments(date(2026, 6, 30)).count() == 1
    set_rate(world.teacher, 40000, course=world.course)
    assert june(world.teacher).lines[0].amount_minor == 30000
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/payroll/tests/test_build.py -q`

Expected: FAIL — `ModuleNotFoundError: No module named 'etqan.payroll.services.build'`.

- [ ] **Step 3: Implement**

Replace the whole of `backend/etqan/payroll/services/rules.py` with:

```python
"""The rules every payslip follows (spec §4.1). One implementation each."""

import calendar
from datetime import date

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import F
from django.db.models import Q
from django.db.models import QuerySet

from etqan.identity import services as identity_services
from etqan.payroll import clock
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import TeacherRate
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import from_django

# P7-2 (owner decision): a session pays when it is completed and its teacher
# was present or not marked, whatever the student's attendance. The one pay
# rule; it filters scheduling's `payroll_sessions`.
PAYING_TEACHER_ATTENDANCE = ("present", "not_set")
PAYS = Q(status="completed", teacher_attendance__in=PAYING_TEACHER_ATTENDANCE)
MINUTES_PER_HOUR = 60


def round_half_up(numerator: int, denominator: int) -> int:
    """``numerator / denominator`` rounded half up, in integers only (no
    float, no Decimal): ``(2n + d) // 2d``. For ``numerator >= 0`` and
    ``denominator > 0``, which is all payroll ever divides."""
    return (2 * numerator + denominator) // (2 * denominator)


def session_amount(rate_minor: int, minutes: int) -> int:
    """The one amount formula (spec §4.1): an hourly rate for ``minutes``,
    ``round_half_up(rate * minutes / 60)`` in integer minor units."""
    return round_half_up(rate_minor * minutes, MINUTES_PER_HOUR)


def month_bounds(year: int, month: int) -> tuple[date, date]:
    """The first and last day of a month of the academy's calendar."""
    return date(year, month, 1), date(year, month, calendar.monthrange(year, month)[1])


def month_over(year: int, month: int) -> bool:
    """P7-5: the month has ended on the academy's calendar."""
    return clock.today() > month_bounds(year, month)[1]


def teacher_of(user_id: int, *, field: str = "teacher"):
    """A teacher's profile, active or not, by User id (people are User ids in
    the API); otherwise a 400 on ``field``."""
    profile = identity_services.get_teacher_profile(user_id)
    if profile is None or profile.user.role != "teacher":
        raise ValidationError("Choose a teacher.", field=field)
    return profile


def check(obj, *, exclude=()) -> None:
    """Field checks with readable messages, as 400s on their fields."""
    try:
        obj.full_clean(exclude=list(exclude), validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None


def save(obj, update_fields=None) -> None:
    check(obj)
    obj.save(update_fields=update_fields)


def current_rates(teacher) -> dict[int | None, int]:
    """The teacher's rates in their current ``pay_currency`` (spec §4.1,
    §4.6), course id → hourly rate, ``None`` for the default. A rate left in
    an old currency does not count."""
    return dict(
        TeacherRate.objects.filter(
            teacher=teacher, currency=teacher.pay_currency
        ).values_list("course_id", "hourly_rate_minor")
    )


def rate_for(rates: dict[int | None, int], course_id: int) -> int | None:
    """The course's rate, else the default, else None (spec §4.1)."""
    return rates.get(course_id, rates.get(None))


def pending_adjustments(last: date) -> QuerySet[PayAdjustment]:
    """Adjustments no issued payslip has used, effective on or before
    ``last``, in their teacher's current ``pay_currency`` (spec §4.1)."""
    return PayAdjustment.objects.filter(
        payslip__isnull=True,
        effective_on__lte=last,
        currency=F("teacher__pay_currency"),
    )


def other_currency_adjustments(last: date) -> QuerySet[PayAdjustment]:
    """The same pending adjustments, but in a currency their teacher is no
    longer paid in: left out of every payslip and reported (spec §4.1)."""
    return PayAdjustment.objects.filter(
        payslip__isnull=True, effective_on__lte=last
    ).exclude(currency=F("teacher__pay_currency"))
```

Create `backend/etqan/payroll/services/build.py`:

```python
"""Building a teacher's month (spec §4.1): the one build function, used by
generate and, from fresh data, by issue."""

from dataclasses import dataclass

from etqan.academy import services as academy_services
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import PayslipLine
from etqan.payroll.services import rules
from etqan.scheduling import services as scheduling_services

SESSION = PayslipLine.Kind.SESSION
ADJUSTMENT = PayslipLine.Kind.ADJUSTMENT
# An adjustment line's copied text names its kind in the academy's language.
KIND_NAMES = {
    "en": {"bonus": "Bonus", "deduction": "Deduction"},
    "ar": {"bonus": "مكافأة", "deduction": "خصم"},
}


@dataclass(frozen=True)
class Line:
    kind: str
    description: str
    amount_minor: int  # signed: a deduction is negative
    session_id: int | None = None
    adjustment_id: int | None = None
    minutes: int | None = None
    rate_minor: int | None = None


@dataclass(frozen=True)
class Built:
    currency: str
    lines: tuple[Line, ...]
    gross_minor: int
    bonuses_minor: int
    deductions_minor: int
    net_minor: int
    missing_rate: bool

    @property
    def session_ids(self) -> list[int]:
        return [line.session_id for line in self.lines if line.kind == SESSION]

    @property
    def adjustment_ids(self) -> list[int]:
        return [line.adjustment_id for line in self.lines if line.kind == ADJUSTMENT]


def _suffix(language: str) -> str:
    return "ar" if language == "ar" else "en"


def describe_session(session, language: str) -> str:
    """ "{date} — {course} — {student}", the course in ``language``."""
    course = getattr(session.course, f"name_{_suffix(language)}")
    return (
        f"{session.occurs_on.isoformat()} — {course} — {session.student.user.full_name}"
    )


def describe_adjustment(adjustment: PayAdjustment, language: str) -> str:
    """ "{Bonus|Deduction} — {reason}", the kind in ``language``."""
    return f"{KIND_NAMES[_suffix(language)][adjustment.kind]} — {adjustment.reason}"


def _session_lines(teacher, first, last, language) -> list[Line]:
    rates = rules.current_rates(teacher)
    lines = []
    paying = scheduling_services.payroll_sessions(first, last).filter(
        rules.PAYS, teacher=teacher
    )
    for session in paying:
        rate = rules.rate_for(rates, session.course_id)
        lines.append(
            Line(
                kind=SESSION,
                session_id=session.pk,
                description=describe_session(session, language),
                minutes=session.minutes,
                rate_minor=rate,
                amount_minor=0
                if rate is None
                else rules.session_amount(rate, session.minutes),
            )
        )
    return lines


def _adjustment_lines(teacher, last, language) -> list[Line]:
    pending = (
        rules.pending_adjustments(last)
        .filter(teacher=teacher)
        .order_by("effective_on", "id")
    )
    return [
        Line(
            kind=ADJUSTMENT,
            adjustment_id=adjustment.pk,
            description=describe_adjustment(adjustment, language),
            amount_minor=adjustment.amount_minor
            if adjustment.kind == PayAdjustment.Kind.BONUS
            else -adjustment.amount_minor,
        )
        for adjustment in pending
    ]


def build(teacher, year: int, month: int) -> Built:
    """Teacher ``teacher``'s (a TeacherProfile) payslip for the month, read
    fresh: the paying sessions (P7-2) no payslip has locked, oldest first,
    each at its course's rate else the default rate, in the teacher's current
    ``pay_currency``; then their pending adjustments, oldest first. A session
    without a rate is a line of 0 and sets ``missing_rate``. Totals: gross is
    the session lines, bonuses and deductions are summed apart, net = gross +
    bonuses - deductions. Copied text is in the academy's default language."""
    first, last = rules.month_bounds(year, month)
    language = academy_services.get_settings().default_language
    sessions = _session_lines(teacher, first, last, language)
    adjustments = _adjustment_lines(teacher, last, language)
    gross = sum(line.amount_minor for line in sessions)
    bonuses = sum(line.amount_minor for line in adjustments if line.amount_minor > 0)
    deductions = -sum(
        line.amount_minor for line in adjustments if line.amount_minor < 0
    )
    return Built(
        currency=teacher.pay_currency,
        lines=(*sessions, *adjustments),
        gross_minor=gross,
        bonuses_minor=bonuses,
        deductions_minor=deductions,
        net_minor=gross + bonuses - deductions,
        missing_rate=any(line.rate_minor is None for line in sessions),
    )
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/payroll -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1067 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/payroll
git -C backend commit -m "feat(payroll): the pay rule, the amount formula and the build

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Generate: drafts for a month

**Files:**
- Create: `backend/etqan/payroll/services/payslips.py`
- Modify: `backend/etqan/identity/services.py`, `backend/etqan/payroll/services/__init__.py`
- Test: `backend/etqan/identity/tests/test_people_services.py`, `backend/etqan/payroll/tests/test_generate.py` (new)

**Interfaces:**
- Consumes: Task 4's `build`, `rules.PAYS`, `rules.pending_adjustments`, `rules.other_currency_adjustments`, `rules.month_bounds`; Task 1's `numbering.hold/take`; `scheduling_services.payroll_sessions`.
- Produces: `identity_services.teacher_profiles_by_id(profile_ids) -> dict[int, TeacherProfile]` (one query, users joined).
- Produces (re-exported): `GenerateResult(created, replaced, removed, missing_rate: list[User], other_currency: list[User])` and `generate(year: int, month: int) -> GenerateResult` (D1–D3).
- Produces in `payslips`: `write(payslip, built) -> None` (copies totals, replaces lines), and the constant `DRAFT`.

- [ ] **Step 1: Write the failing tests**

Generate creates a numbered draft per teacher with activity, replaces a draft keeping its number, removes a draft with no activity left, and never touches an issued or paid payslip — not its lines, totals or `updated_at`, even when nothing is left to pay. Missing rates and other-currency adjustments are named. The lock-shape test pins the counter, then the month's payslips in id order.

In `backend/etqan/identity/tests/test_people_services.py`, replace:

```python
        assert exc.value.field == "teacher_ids"

    def test_scope_for_admins_only(self):
        student()
```

with:

```python
        assert exc.value.field == "teacher_ids"

    def test_teacher_profiles_by_id_in_one_query(self):
        t = services.create_person("teacher", full_name="T", profile={"gender": "male"})
        with CaptureQueriesContext(connection) as queries:
            found = services.teacher_profiles_by_id([t.teacher_profile.pk, 10**9])
            assert found[t.teacher_profile.pk].user.full_name == "T"
        assert list(found) == [t.teacher_profile.pk]
        assert len([q for q in queries if q["sql"].startswith("SELECT")]) == 1

    def test_scope_for_admins_only(self):
        student()
```

Create `backend/etqan/payroll/tests/test_generate.py`:

```python
"""Generate (spec §4.2): create, replace and remove drafts, leave issued and
paid payslips alone."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.models import Payslip
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)


@pytest.fixture
def sessions(world, clock):
    """Bilal's nine June sessions, all started (it is 1 July)."""
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


@pytest.fixture
def maryam(world):
    teacher = make_teacher("Maryam")
    world.course.teachers.add(teacher.teacher_profile)
    return teacher


def june_payslips():
    return list(Payslip.objects.filter(year=2026, month=6).order_by("pk"))


def test_a_draft_for_each_teacher_with_activity(world, sessions, maryam):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher, teacher="absent")
    adjust(maryam, "bonus", 500, on=date(2026, 6, 15))
    # A teacher with only unpaid sessions, and one with nothing, get none.
    idle = make_teacher("Idle")
    world.course.teachers.add(idle.teacher_profile)
    absent = june_sessions(
        world, student_id=make_student("Aisha").id, teacher_id=idle.id
    )
    mark(absent[0], idle, teacher="absent")
    result = services.generate(2026, 6)
    assert (result.created, result.replaced, result.removed) == (2, 0, 0)
    bilal, theirs = june_payslips()
    assert (bilal.teacher, bilal.status, bilal.number) == (
        world.teacher.teacher_profile,
        "draft",
        "PAY-000001",
    )
    assert (bilal.gross_minor, bilal.net_minor, bilal.currency) == (750, 750, "USD")
    assert [line.session_id for line in bilal.lines.all()] == [sessions[0].pk]
    assert (theirs.teacher, theirs.number) == (maryam.teacher_profile, "PAY-000002")
    assert (theirs.bonuses_minor, theirs.net_minor) == (500, 500)


def test_regenerating_replaces_a_draft_and_keeps_its_number(world, sessions):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    services.generate(2026, 6)
    (first,) = june_payslips()
    mark(sessions[1], world.teacher)
    result = services.generate(2026, 6)
    assert (result.created, result.replaced, result.removed) == (0, 1, 0)
    (again,) = june_payslips()
    assert (again.pk, again.number) == (first.pk, "PAY-000001")
    assert again.gross_minor == 1500
    assert [line.session_id for line in again.lines.all()] == [
        sessions[0].pk,
        sessions[1].pk,
    ]


def test_a_draft_with_no_activity_left_is_removed(world, sessions, admin):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    services.generate(2026, 6)
    scheduling_services.mark_attendance(
        sessions[0], by=admin, teacher_attendance="absent"
    )
    result = services.generate(2026, 6)
    assert (result.created, result.replaced, result.removed) == (0, 0, 1)
    assert june_payslips() == []


@pytest.mark.parametrize("status", ["issued", "paid"])
def test_issued_and_paid_payslips_are_never_touched(world, sessions, status):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    services.generate(2026, 6)
    Payslip.objects.update(status=status, notes="Frozen")
    (frozen,) = june_payslips()
    mark(sessions[1], world.teacher)
    result = services.generate(2026, 6)
    assert (result.created, result.replaced, result.removed) == (0, 0, 0)
    (after,) = june_payslips()
    assert (after.status, after.gross_minor, after.updated_at) == (
        status,
        750,
        frozen.updated_at,
    )
    assert after.lines.count() == 1
    # With no activity left (both sessions locked), it still stays.
    scheduling_services.lock_sessions([sessions[0].pk, sessions[1].pk])
    assert services.generate(2026, 6).removed == 0
    assert june_payslips() == [after]


def test_missing_rates_and_other_currency_adjustments_are_named(
    world, sessions, maryam
):
    mark(sessions[0], world.teacher)
    adjust(maryam, "bonus", 500, on=date(2026, 6, 15))
    identity_services.update_person(maryam, profile={"pay_currency": "EGP"})
    result = services.generate(2026, 6)
    assert result.missing_rate == [world.teacher]
    assert result.other_currency == [maryam]
    # Maryam's only adjustment no longer counts: she gets no payslip.
    (only,) = june_payslips()
    assert (only.teacher, only.missing_rate) == (world.teacher.teacher_profile, True)


def test_an_inactive_teacher_is_paid_too(world, sessions):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    identity_services.deactivate(world.teacher, by=None)
    assert services.generate(2026, 6).created == 1


def test_generate_locks_the_counter_then_the_months_payslips(world, sessions):
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    services.generate(2026, 6)
    with CaptureQueriesContext(connection) as ctx:
        services.generate(2026, 6)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert len(locks) == 2
    assert locks[0].endswith(
        'FROM "payroll_payslipcounter" WHERE "payroll_payslipcounter"."id" = 1 '
        "LIMIT 21 FOR UPDATE"
    )
    # Exact: Payslip's own ordering is `-year, -month, id`, so a query that
    # lost its `.order_by("pk")` would still say "ORDER BY".
    assert locks[1].endswith(
        'WHERE ("payroll_payslip"."month" = 6 AND "payroll_payslip"."year" = 2026) '
        'ORDER BY "payroll_payslip"."id" ASC FOR UPDATE'
    )
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/payroll/tests/test_generate.py etqan/identity/tests/test_people_services.py -q`

Expected: FAIL — `AttributeError: module 'etqan.payroll.services' has no attribute 'generate'` and `… 'teacher_profiles_by_id'`.

- [ ] **Step 3: Implement**

In `backend/etqan/identity/services.py`, replace:

```python


def has_people() -> bool:
    return User.objects.exclude(role=User.Role.ADMIN).exists()
```

with:

```python


def teacher_profiles_by_id(profile_ids) -> dict[int, TeacherProfile]:
    """Teacher profiles by their own ids, with their users, in one query
    (payroll's generate, Plan 7). A missing id is simply absent."""
    profiles = TeacherProfile.objects.filter(pk__in=list(profile_ids))
    return {profile.pk: profile for profile in profiles.select_related("user")}


def has_people() -> bool:
    return User.objects.exclude(role=User.Role.ADMIN).exists()
```

Create `backend/etqan/payroll/services/payslips.py`:

```python
"""Generating, issuing and paying payslips (spec §4.2-§4.4)."""

from dataclasses import dataclass
from dataclasses import field

from django.db import transaction

from etqan.identity import services as identity_services
from etqan.payroll.models import Payslip
from etqan.payroll.models import PayslipLine
from etqan.payroll.services import numbering
from etqan.payroll.services import rules
from etqan.payroll.services.build import Built
from etqan.payroll.services.build import build
from etqan.scheduling import services as scheduling_services

DRAFT = Payslip.Status.DRAFT


@dataclass
class GenerateResult:
    created: int = 0
    replaced: int = 0
    removed: int = 0
    # Teachers (Users), by name: drafts with a session and no rate, and
    # teachers with pending adjustments in a currency they are no longer paid
    # in (left out, spec §4.1).
    missing_rate: list = field(default_factory=list)
    other_currency: list = field(default_factory=list)


def _active_teacher_ids(first, last) -> set[int]:
    """TeacherProfile ids with a paying session no payslip has locked, or a
    pending adjustment, in the month: two queries however many teachers
    (plan D3). The same pay rule and adjustment filter as `build`, so every
    teacher found here builds at least one line."""
    paying = (
        scheduling_services.payroll_sessions(first, last)
        .filter(rules.PAYS)
        .order_by()
        .values_list("teacher_id", flat=True)
        .distinct()
    )
    pending = (
        rules.pending_adjustments(last)
        .order_by()
        .values_list("teacher_id", flat=True)
        .distinct()
    )
    return set(paying) | set(pending)


def write(payslip: Payslip, built: Built) -> None:
    """Copy ``built`` onto ``payslip`` and replace its lines (spec §3.5)."""
    payslip.currency = built.currency
    payslip.gross_minor = built.gross_minor
    payslip.bonuses_minor = built.bonuses_minor
    payslip.deductions_minor = built.deductions_minor
    payslip.net_minor = built.net_minor
    payslip.missing_rate = built.missing_rate
    rules.save(payslip)
    payslip.lines.all().delete()
    PayslipLine.objects.bulk_create(
        PayslipLine(
            payslip=payslip,
            kind=line.kind,
            session_id=line.session_id,
            adjustment_id=line.adjustment_id,
            description=line.description,
            minutes=line.minutes,
            rate_minor=line.rate_minor,
            amount_minor=line.amount_minor,
        )
        for line in built.lines
    )


def _other_currency_teachers(last) -> list:
    adjustments = rules.other_currency_adjustments(last).select_related("teacher__user")
    users = {a.teacher.user_id: a.teacher.user for a in adjustments}
    return sorted(users.values(), key=lambda user: (user.full_name, user.pk))


@transaction.atomic
def generate(year: int, month: int) -> GenerateResult:
    """Spec §4.2, for every active or inactive teacher with activity in the
    month: a new draft (numbered when created), or the existing draft's lines
    and totals replaced (its number kept). Issued and paid payslips are never
    touched, and drafts whose teacher has no activity left are deleted.

    Locks, in this order (plan D1): the academy's payslip counter, so two
    generates run one after the other; then the month's payslips, in id
    order, so an issue in progress finishes first and its payslip is seen as
    issued. Sessions are only read: issue rebuilds from fresh data."""
    counter = numbering.hold()
    first, last = rules.month_bounds(year, month)
    existing = {
        payslip.teacher_id: payslip
        for payslip in Payslip.objects.select_for_update()
        .filter(year=year, month=month)
        .order_by("pk")
    }
    active = _active_teacher_ids(first, last)
    teachers = identity_services.teacher_profiles_by_id(active)
    result = GenerateResult()
    missing = []
    for teacher_id in sorted(active):
        payslip = existing.get(teacher_id)
        if payslip is not None and payslip.status != DRAFT:
            continue
        teacher = teachers[teacher_id]
        built = build(teacher, year, month)
        if payslip is None:
            payslip = Payslip(
                number=numbering.take(counter), teacher=teacher, year=year, month=month
            )
            result.created += 1
        else:
            result.replaced += 1
        write(payslip, built)
        if built.missing_rate:
            missing.append(teacher.user)
    for teacher_id, payslip in existing.items():
        if teacher_id not in active and payslip.status == DRAFT:
            payslip.delete()
            result.removed += 1
    result.missing_rate = sorted(missing, key=lambda user: (user.full_name, user.pk))
    result.other_currency = _other_currency_teachers(last)
    return result
```

Replace the whole of `backend/etqan/payroll/services/__init__.py` with:

```python
"""Public API of the payroll module. Other apps import only this package."""

from etqan.payroll.services.adjustments import adjustments_queryset
from etqan.payroll.services.adjustments import create_adjustment
from etqan.payroll.services.adjustments import delete_adjustment
from etqan.payroll.services.adjustments import filter_adjustments
from etqan.payroll.services.adjustments import update_adjustment
from etqan.payroll.services.payslips import GenerateResult
from etqan.payroll.services.payslips import generate
from etqan.payroll.services.rates import create_rate
from etqan.payroll.services.rates import delete_rate
from etqan.payroll.services.rates import rates_queryset
from etqan.payroll.services.rates import update_rate

__all__ = [
    "GenerateResult",
    "adjustments_queryset",
    "create_adjustment",
    "create_rate",
    "delete_adjustment",
    "delete_rate",
    "filter_adjustments",
    "generate",
    "rates_queryset",
    "update_adjustment",
    "update_rate",
]
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/payroll etqan/identity -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1076 tests, coverage 97.8% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/payroll etqan/identity
git -C backend commit -m "feat(payroll): generate a month's draft payslips

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Issue and mark paid, locking the paid sessions

**Files:**
- Modify: `backend/etqan/payroll/services/payslips.py`, `backend/etqan/payroll/services/__init__.py`
- Test: `backend/etqan/payroll/tests/test_issue.py` (new)

**Interfaces:**
- Consumes: Task 5's `write`, `build`; Task 2's `hold_sessions` and `lock_sessions`; Task 3's `PayAdjustment`.
- Produces (re-exported): `issue(payslip, *, by) -> Payslip` (409 `payroll.not_allowed_in_status`, `payroll.month_not_over`, `payroll.missing_rate`, `payroll.negative_net`, in that order) and `mark_paid(payslip, *, paid_on: date, by, notes: str | None = None) -> Payslip` (409 unless issued; 400 on `paid_on` after the academy's today).
- Produces in `payslips`: `lock(payslip) -> Payslip` (`FOR UPDATE OF "payroll_payslip"`, teacher joined), `ISSUED`, `PAID`.

- [ ] **Step 1: Write the failing tests**

Issuing rebuilds from fresh data (a session marked, a teacher no-show and a rate change after generating all count), freezes the payslip, marks its adjustments used and locks exactly the sessions it pays. Each refusal changes nothing. "The month has ended" follows the academy's calendar (Riyadh is already in July when UTC is not). A pay-currency change before issuing is a missing rate, not a payslip in a stale currency. The lock-shape test pins the D1 order.

Create `backend/etqan/payroll/tests/test_issue.py`:

```python
"""Issue and mark paid (spec §4.3, §4.4): refusals, the fresh rebuild, the
session lock and the lock order."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services

JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)


@pytest.fixture
def sessions(world, clock):
    """Bilal's nine June sessions, all started (it is 1 July)."""
    found = june_sessions(world)
    clock.set(JULY_FIRST)
    return found


@pytest.fixture
def draft(world, sessions):
    """Bilal's June draft: two sessions at 1000 an hour and a 500 bonus."""
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher)
    adjust(world.teacher, "bonus", 500, on=date(2026, 6, 15))
    services.generate(2026, 6)
    return Payslip.objects.get(year=2026, month=6)


def locked_ids():
    return set(
        scheduling_services.sessions_queryset()
        .filter(payroll_locked=True)
        .values_list("pk", flat=True)
    )


def refused(payslip, admin) -> str:
    with pytest.raises(ConflictError) as exc:
        services.issue(payslip, by=admin)
    return exc.value.code


def test_issuing_freezes_the_payslip_and_locks_what_it_pays(
    draft, sessions, admin, world
):
    mark(sessions[2], world.teacher, teacher="absent")
    issued = services.issue(draft, by=admin)
    assert (issued.status, issued.issued_by, issued.issued_at) == (
        "issued",
        admin,
        JULY_FIRST,
    )
    assert (issued.gross_minor, issued.bonuses_minor, issued.net_minor) == (
        1500,
        500,
        2000,
    )
    # The two paying sessions are locked; the absent one is not.
    assert locked_ids() == {sessions[0].pk, sessions[1].pk}
    assert PayAdjustment.objects.get().payslip == issued


def test_issue_rebuilds_from_fresh_data(draft, sessions, admin, world):
    # After generating: one more session, one teacher no-show, a new rate.
    mark(sessions[2], world.teacher)
    scheduling_services.mark_attendance(
        sessions[0], by=admin, teacher_attendance="absent"
    )
    rate = services.rates_queryset().get()
    services.update_rate(rate, hourly_rate_minor=2000)
    issued = services.issue(draft, by=admin)
    assert [line.session_id for line in issued.lines.all() if line.session_id] == [
        sessions[1].pk,
        sessions[2].pk,
    ]
    assert issued.gross_minor == 3000
    assert issued.number == draft.number


@pytest.mark.parametrize("status", ["issued", "paid"])
def test_only_a_draft_is_issued(draft, admin, status):
    Payslip.objects.filter(pk=draft.pk).update(status=status)
    assert refused(draft, admin) == "payroll.not_allowed_in_status"


def test_a_stale_copy_is_never_issued_twice(draft, admin):
    services.issue(Payslip.objects.get(pk=draft.pk), by=admin)
    assert refused(draft, admin) == "payroll.not_allowed_in_status"


def test_the_month_must_be_over_on_the_academys_calendar(draft, admin, clock):
    # 21:30 UTC on 30 June: still June in UTC, already 1 July in Riyadh.
    clock.set(datetime(2026, 6, 30, 21, 30, tzinfo=UTC))
    assert refused(draft, admin) == "payroll.month_not_over"
    academy_services.update_settings(timezone="Asia/Riyadh")
    assert services.issue(draft, by=admin).status == "issued"


def test_a_missing_rate_is_refused_and_changes_nothing(draft, admin):
    services.delete_rate(services.rates_queryset().get())
    assert refused(draft, admin) == "payroll.missing_rate"
    draft.refresh_from_db()
    assert (draft.status, draft.missing_rate, draft.gross_minor) == (
        "draft",
        False,
        1500,
    )
    assert locked_ids() == set()
    assert PayAdjustment.objects.get().payslip is None


def test_a_negative_net_is_refused(draft, admin, world):
    adjust(world.teacher, "deduction", 5000, on=date(2026, 6, 20))
    assert refused(draft, admin) == "payroll.negative_net"


def test_a_pay_currency_change_before_issue_is_a_missing_rate(draft, admin, world):
    identity_services.update_person(world.teacher, profile={"pay_currency": "EGP"})
    assert refused(draft, admin) == "payroll.missing_rate"
    set_rate(world.teacher, 40000, course=world.course)
    issued = services.issue(draft, by=admin)
    # The USD bonus is left out; the sessions are paid in EGP.
    assert (issued.currency, issued.gross_minor, issued.bonuses_minor) == (
        "EGP",
        60000,
        0,
    )
    assert PayAdjustment.objects.get().payslip is None


def test_issue_locks_payslip_adjustments_then_sessions(draft, admin):
    with CaptureQueriesContext(connection) as ctx:
        services.issue(draft, by=admin)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert len(locks) == 4
    assert locks[0].endswith(
        f'WHERE "payroll_payslip"."id" = {draft.pk} LIMIT 21 '
        'FOR UPDATE OF "payroll_payslip"'
    )
    assert locks[1].split(" FROM ")[1].split()[0] == '"payroll_payadjustment"'
    assert locks[1].endswith('ORDER BY 1 ASC FOR UPDATE OF "payroll_payadjustment"')
    # Scheduling's hold, then its lock: session rows in id order, never a
    # subscription (Plan 4's order is subscription before session).
    for sql in locks[2:]:
        assert sql.split(" FROM ")[1].split()[0] == '"scheduling_session"'
        assert sql.rstrip().endswith("ORDER BY 1 ASC FOR UPDATE")
    assert not any('"scheduling_subscription"' in sql for sql in locks)


# ── Mark paid ────────────────────────────────────────────────────────────────


def test_marking_paid_records_the_date_and_who(draft, admin):
    services.issue(draft, by=admin)
    paid = services.mark_paid(draft, paid_on=date(2026, 7, 1), by=admin, notes="Wise")
    assert (paid.status, paid.paid_on, paid.paid_by, paid.notes) == (
        "paid",
        date(2026, 7, 1),
        admin,
        "Wise",
    )


@pytest.mark.parametrize("status", ["draft", "paid"])
def test_only_an_issued_payslip_is_marked_paid(draft, admin, status):
    Payslip.objects.filter(pk=draft.pk).update(status=status)
    with pytest.raises(ConflictError) as exc:
        services.mark_paid(draft, paid_on=date(2026, 7, 1), by=admin)
    assert exc.value.code == "payroll.not_allowed_in_status"


def test_a_payslip_is_not_paid_in_the_future(draft, admin):
    services.issue(draft, by=admin)
    with pytest.raises(ValidationError) as exc:
        services.mark_paid(draft, paid_on=date(2026, 7, 2), by=admin)
    assert exc.value.field == "paid_on"
    draft.refresh_from_db()
    assert draft.status == "issued"
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/payroll/tests/test_issue.py -q`

Expected: FAIL — `AttributeError: module 'etqan.payroll.services' has no attribute 'issue'`.

- [ ] **Step 3: Implement**

Replace the whole of `backend/etqan/payroll/services/payslips.py` with:

```python
"""Generating, issuing and paying payslips (spec §4.2-§4.4)."""

from dataclasses import dataclass
from dataclasses import field
from datetime import date

from django.db import transaction

from etqan.identity import services as identity_services
from etqan.payroll import clock
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.models import PayslipLine
from etqan.payroll.services import numbering
from etqan.payroll.services import rules
from etqan.payroll.services.build import Built
from etqan.payroll.services.build import build
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services

DRAFT = Payslip.Status.DRAFT
ISSUED = Payslip.Status.ISSUED
PAID = Payslip.Status.PAID


@dataclass
class GenerateResult:
    created: int = 0
    replaced: int = 0
    removed: int = 0
    # Teachers (Users), by name: drafts with a session and no rate, and
    # teachers with pending adjustments in a currency they are no longer paid
    # in (left out, spec §4.1).
    missing_rate: list = field(default_factory=list)
    other_currency: list = field(default_factory=list)


def _active_teacher_ids(first, last) -> set[int]:
    """TeacherProfile ids with a paying session no payslip has locked, or a
    pending adjustment, in the month: two queries however many teachers
    (plan D3). The same pay rule and adjustment filter as `build`, so every
    teacher found here builds at least one line."""
    paying = (
        scheduling_services.payroll_sessions(first, last)
        .filter(rules.PAYS)
        .order_by()
        .values_list("teacher_id", flat=True)
        .distinct()
    )
    pending = (
        rules.pending_adjustments(last)
        .order_by()
        .values_list("teacher_id", flat=True)
        .distinct()
    )
    return set(paying) | set(pending)


def write(payslip: Payslip, built: Built) -> None:
    """Copy ``built`` onto ``payslip`` and replace its lines (spec §3.5)."""
    payslip.currency = built.currency
    payslip.gross_minor = built.gross_minor
    payslip.bonuses_minor = built.bonuses_minor
    payslip.deductions_minor = built.deductions_minor
    payslip.net_minor = built.net_minor
    payslip.missing_rate = built.missing_rate
    rules.save(payslip)
    payslip.lines.all().delete()
    PayslipLine.objects.bulk_create(
        PayslipLine(
            payslip=payslip,
            kind=line.kind,
            session_id=line.session_id,
            adjustment_id=line.adjustment_id,
            description=line.description,
            minutes=line.minutes,
            rate_minor=line.rate_minor,
            amount_minor=line.amount_minor,
        )
        for line in built.lines
    )


def _other_currency_teachers(last) -> list:
    adjustments = rules.other_currency_adjustments(last).select_related("teacher__user")
    users = {a.teacher.user_id: a.teacher.user for a in adjustments}
    return sorted(users.values(), key=lambda user: (user.full_name, user.pk))


@transaction.atomic
def generate(year: int, month: int) -> GenerateResult:
    """Spec §4.2, for every active or inactive teacher with activity in the
    month: a new draft (numbered when created), or the existing draft's lines
    and totals replaced (its number kept). Issued and paid payslips are never
    touched, and drafts whose teacher has no activity left are deleted.

    Locks, in this order (plan D1): the academy's payslip counter, so two
    generates run one after the other; then the month's payslips, in id
    order, so an issue in progress finishes first and its payslip is seen as
    issued. Sessions are only read: issue rebuilds from fresh data."""
    counter = numbering.hold()
    first, last = rules.month_bounds(year, month)
    existing = {
        payslip.teacher_id: payslip
        for payslip in Payslip.objects.select_for_update()
        .filter(year=year, month=month)
        .order_by("pk")
    }
    active = _active_teacher_ids(first, last)
    teachers = identity_services.teacher_profiles_by_id(active)
    result = GenerateResult()
    missing = []
    for teacher_id in sorted(active):
        payslip = existing.get(teacher_id)
        if payslip is not None and payslip.status != DRAFT:
            continue
        teacher = teachers[teacher_id]
        built = build(teacher, year, month)
        if payslip is None:
            payslip = Payslip(
                number=numbering.take(counter), teacher=teacher, year=year, month=month
            )
            result.created += 1
        else:
            result.replaced += 1
        write(payslip, built)
        if built.missing_rate:
            missing.append(teacher.user)
    for teacher_id, payslip in existing.items():
        if teacher_id not in active and payslip.status == DRAFT:
            payslip.delete()
            result.removed += 1
    result.missing_rate = sorted(missing, key=lambda user: (user.full_name, user.pk))
    result.other_currency = _other_currency_teachers(last)
    return result


def lock(payslip: Payslip) -> Payslip:
    """``payslip``'s row, `SELECT … FOR UPDATE`, read fresh with its teacher
    (only the payslip's row is locked). Issue and mark paid take this lock
    first and decide on the fresh row."""
    return (
        Payslip.objects.select_for_update(of=("self",))
        .select_related("teacher")
        .get(pk=payslip.pk)
    )


def _refuse_unless(payslip: Payslip, status: str) -> None:
    if payslip.status != status:
        raise ConflictError(
            f"Not allowed while the payslip is {payslip.status}.",
            code="payroll.not_allowed_in_status",
        )


@transaction.atomic
def issue(payslip: Payslip, *, by) -> Payslip:
    """Spec §4.3: a draft of a month that has ended (the academy's calendar)
    is rebuilt from fresh data and frozen. Refused with 409
    `payroll.not_allowed_in_status`, `payroll.month_not_over`,
    `payroll.missing_rate` or `payroll.negative_net`, in that order; a
    refusal changes nothing.

    Locks, in this order (plan D1): the payslip's row; the teacher's pending
    adjustments, in id order; the teacher's unlocked sessions of the month,
    in id order (scheduling's `hold_sessions`). Only then is the payslip
    rebuilt, so nothing it reads can change before it commits. Its
    adjustments are then marked used and the sessions it pays are locked
    through scheduling's `lock_sessions`. Never a subscription."""
    locked = lock(payslip)
    _refuse_unless(locked, DRAFT)
    if not rules.month_over(locked.year, locked.month):
        raise ConflictError(
            "This month hasn't ended yet.", code="payroll.month_not_over"
        )
    first, last = rules.month_bounds(locked.year, locked.month)
    list(
        rules.pending_adjustments(last)
        .filter(teacher=locked.teacher)
        .select_for_update(of=("self",))
        .order_by("pk")
        .values_list("pk", flat=True)
    )
    scheduling_services.hold_sessions(
        teacher_id=locked.teacher_id, first=first, last=last
    )
    built = build(locked.teacher, locked.year, locked.month)
    if built.missing_rate:
        raise ConflictError(
            "A session has no rate. Set the teacher's rate first.",
            code="payroll.missing_rate",
        )
    if built.net_minor < 0:
        raise ConflictError(
            "The deductions are more than the pay.", code="payroll.negative_net"
        )
    locked.status = ISSUED
    locked.issued_at = clock.now()
    locked.issued_by = by
    write(locked, built)
    PayAdjustment.objects.filter(pk__in=built.adjustment_ids).update(payslip=locked)
    scheduling_services.lock_sessions(built.session_ids)
    return locked


@transaction.atomic
def mark_paid(
    payslip: Payslip, *, paid_on: date, by, notes: str | None = None
) -> Payslip:
    """Spec §4.4: from issued only (409 `payroll.not_allowed_in_status`);
    ``paid_on`` may not be after the academy's today (400 on ``paid_on``).
    ``notes`` (admin-only) may say how it was paid (plan D10)."""
    locked = lock(payslip)
    _refuse_unless(locked, ISSUED)
    if paid_on > clock.today():
        raise ValidationError("A payslip can't be paid in the future.", field="paid_on")
    locked.status = PAID
    locked.paid_on = paid_on
    locked.paid_by = by
    fields = ["status", "paid_on", "paid_by", "updated_at"]
    if notes is not None:
        locked.notes = notes
        fields.append("notes")
    locked.save(update_fields=fields)
    return locked
```

Replace the whole of `backend/etqan/payroll/services/__init__.py` with:

```python
"""Public API of the payroll module. Other apps import only this package."""

from etqan.payroll.services.adjustments import adjustments_queryset
from etqan.payroll.services.adjustments import create_adjustment
from etqan.payroll.services.adjustments import delete_adjustment
from etqan.payroll.services.adjustments import filter_adjustments
from etqan.payroll.services.adjustments import update_adjustment
from etqan.payroll.services.payslips import GenerateResult
from etqan.payroll.services.payslips import generate
from etqan.payroll.services.payslips import issue
from etqan.payroll.services.payslips import mark_paid
from etqan.payroll.services.rates import create_rate
from etqan.payroll.services.rates import delete_rate
from etqan.payroll.services.rates import rates_queryset
from etqan.payroll.services.rates import update_rate

__all__ = [
    "GenerateResult",
    "adjustments_queryset",
    "create_adjustment",
    "create_rate",
    "delete_adjustment",
    "delete_rate",
    "filter_adjustments",
    "generate",
    "issue",
    "mark_paid",
    "rates_queryset",
    "update_adjustment",
    "update_rate",
]
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/payroll -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1090 tests, coverage 97.8% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/payroll
git -C backend commit -m "feat(payroll): issue and mark paid, locking the paid sessions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: API: rates, adjustments, payslips, generate, issue, mark paid and CSV

**Files:**
- Create: `backend/etqan/payroll/scopes.py`, `backend/etqan/payroll/api/__init__.py`, `backend/etqan/payroll/api/payloads.py`, `backend/etqan/payroll/api/serializers.py`, `backend/etqan/payroll/api/views.py`, `backend/etqan/payroll/api/urls.py`
- Modify: `backend/etqan/catalogue/services.py`, `backend/etqan/payroll/services/rules.py`, `backend/etqan/payroll/services/__init__.py`, `backend/config/api_router.py`
- Test: `backend/etqan/catalogue/tests/test_services.py`, `backend/etqan/payroll/tests/test_api.py` (new)

**Interfaces:**
- Consumes: Tasks 3–6's services; `catalogue_services.courses_by_id` (new here).
- Produces: `catalogue_services.courses_by_id(course_ids) -> dict[int, Course]`.
- Produces (re-exported): `TEACHER_VISIBLE`, `payslips_queryset()` (teacher and admins joined, `sessions`/`minutes` annotated), `filter_payslips(payslips, *, year=None, month=None, teacher=None, status="")`, `has_payroll() -> bool`.
- Produces: `etqan.payroll.scopes.scope_for(user, queryset)` (D6); `api.payloads.payslip_row(payslip, *, is_admin)`, `payslip_detail(payslip, *, is_admin)`, `rate_row(rate, courses)`, `adjustment_row(adjustment)`, `generate_result(result)`; the routes of spec §5 under `/api/v1/payroll/`.

- [ ] **Step 1: Write the failing tests**

The detail shape, a teacher's own issued payslip with staff fields hidden on the list and the detail, their own draft and another teacher's as 404s, the filters and their 400s, generate's counts and names, issue and mark paid answering fresh reads, coded 409s and field 400s, the CSV for admins only, constant query counts for the payslip and rate lists, no PUT, the role × route matrix, and another academy's payslip (pk forced above ours) as a 404 on detail, issue and mark paid.

In `backend/etqan/catalogue/tests/test_services.py`, replace:

```python
    p = services.create_package(**{**PACKAGE, "name_en": "P" * 120})
    assert services.duplicate_package(p).name_en == "P" * 113 + " (copy)"
```

with:

```python
    p = services.create_package(**{**PACKAGE, "name_en": "P" * 120})
    assert services.duplicate_package(p).name_en == "P" * 113 + " (copy)"


def test_courses_by_id_skips_missing_ids():
    course = services.create_course(name_ar="تجويد", name_en="Tajweed")
    assert services.courses_by_id([course.pk, 10**9]) == {course.pk: course}
    assert services.courses_by_id([]) == {}
```

Create `backend/etqan/payroll/tests/test_api.py`:

```python
"""Payroll API (spec §5, §4.7): shapes, writes, roles, scoping, CSV,
query counts and cross-academy isolation."""

import csv
import io
from datetime import UTC
from datetime import date
from datetime import datetime
from types import SimpleNamespace

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.payroll import services
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.models import TeacherRate
from etqan.payroll.tests.conftest import adjust
from etqan.payroll.tests.conftest import june_sessions
from etqan.payroll.tests.conftest import mark
from etqan.payroll.tests.conftest import set_rate
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import until_pk_exceeds

BASE = "/api/v1/payroll/"
PAYSLIPS = f"{BASE}payslips/"
RATES = f"{BASE}rates/"
ADJUSTMENTS = f"{BASE}adjustments/"
JULY_FIRST = datetime(2026, 7, 1, 9, tzinfo=UTC)
STAFF_ONLY = {"notes", "issued_by", "paid_by"}


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


@pytest.fixture
def payroll(world, clock):
    """Bilal's June payslip issued (two sessions at 1000 an hour and a 500
    bonus) and his July one a draft (a 100 bonus); Maryam's June payslip a
    draft (a 300 bonus)."""
    sessions = june_sessions(world)
    clock.set(JULY_FIRST)
    admin = make_admin()
    maryam = make_teacher("Maryam")
    set_rate(world.teacher, 1000)
    mark(sessions[0], world.teacher)
    mark(sessions[1], world.teacher)
    adjust(world.teacher, "bonus", 500, on=date(2026, 6, 15))
    services.generate(2026, 6)
    issued = Payslip.objects.get()
    services.issue(issued, by=admin)
    Payslip.objects.filter(pk=issued.pk).update(notes="Bank transfer")
    adjust(world.teacher, "bonus", 100, on=date(2026, 7, 1))
    services.generate(2026, 7)
    adjust(maryam, "bonus", 300, on=date(2026, 6, 20))
    services.generate(2026, 6)
    return SimpleNamespace(
        admin=as_user(admin),
        admin_user=admin,
        bilal=world.teacher,
        maryam=maryam,
        sessions=sessions,
        issued=issued.pk,
        draft=Payslip.objects.get(teacher=maryam.teacher_profile).pk,
        own_draft=Payslip.objects.get(year=2026, month=7).pk,
    )


# ── Payslips ─────────────────────────────────────────────────────────────────


def test_an_admin_reads_a_payslip_with_its_lines(payroll):
    body = payroll.admin.get(f"{PAYSLIPS}{payroll.issued}/").json()
    assert (body["number"], body["status"], body["year"], body["month"]) == (
        "PAY-000001",
        "issued",
        2026,
        6,
    )
    assert body["teacher"] == {"id": payroll.bilal.id, "full_name": "Bilal"}
    assert (body["sessions"], body["minutes"], body["currency"]) == (2, 90, "USD")
    assert (body["gross_minor"], body["bonuses_minor"]) == (1500, 500)
    assert (body["deductions_minor"], body["net_minor"]) == (0, 2000)
    assert (body["notes"], body["issued_by"]["id"]) == (
        "Bank transfer",
        payroll.admin_user.id,
    )
    assert body["paid_by"] is None
    assert [line["kind"] for line in body["lines"]] == [
        "session",
        "session",
        "adjustment",
    ]
    first = body["lines"][0]
    assert (first["session_id"], first["minutes"], first["rate_minor"]) == (
        payroll.sessions[0].pk,
        45,
        1000,
    )
    assert (first["amount_minor"], first["description"]) == (
        750,
        # The academy's default language, Arabic unless set otherwise.
        "2026-06-01 — تجويد — Yusuf",
    )


def test_a_teacher_reads_only_their_own_issued_and_paid(payroll):
    teacher = as_user(payroll.bilal)
    rows = teacher.get(PAYSLIPS).json()["results"]
    assert [row["id"] for row in rows] == [payroll.issued]
    # Staff fields are hidden on the list and on the detail.
    assert not STAFF_ONLY & set(rows[0])
    detail = teacher.get(f"{PAYSLIPS}{payroll.issued}/")
    assert detail.status_code == 200
    assert not STAFF_ONLY & set(detail.json())
    # Their own draft, and another teacher's payslip, are not found.
    assert teacher.get(f"{PAYSLIPS}{payroll.own_draft}/").status_code == 404
    assert teacher.get(f"{PAYSLIPS}{payroll.draft}/").status_code == 404
    maryam = as_user(payroll.maryam)
    assert maryam.get(PAYSLIPS).json()["results"] == []
    assert maryam.get(f"{PAYSLIPS}{payroll.issued}/").status_code == 404


def test_the_payslip_filters(payroll):
    def ids(query):
        return [
            row["id"]
            for row in payroll.admin.get(f"{PAYSLIPS}?{query}").json()["results"]
        ]

    assert ids("") == [payroll.own_draft, payroll.issued, payroll.draft]
    assert ids("year=2026&month=6") == [payroll.issued, payroll.draft]
    assert ids("status=draft&month=6") == [payroll.draft]
    assert ids(f"teacher={payroll.bilal.id}") == [payroll.own_draft, payroll.issued]


@pytest.mark.parametrize(
    ("query", "field"),
    [("month=13", "month"), ("status=void", "status"), ("year=x", "year")],
)
def test_a_bad_filter_is_a_field_error(payroll, query, field):
    resp = payroll.admin.get(f"{PAYSLIPS}?{query}")
    assert resp.status_code == 400
    assert field in resp.json()


def test_generate_answers_the_counts_and_names(payroll, world):
    # Maryam's only adjustment moves to a currency she is not paid in, and a
    # new teacher, Hamza, taught a session with no rate.
    PayAdjustment.objects.filter(
        payslip__isnull=True, teacher__user=payroll.maryam
    ).update(currency="EGP")
    hamza = make_teacher("Hamza")
    world.course.teachers.add(hamza.teacher_profile)
    theirs = june_sessions(
        world, student_id=make_student("Aisha").id, teacher_id=hamza.id
    )
    mark(theirs[0], hamza)
    resp = payroll.admin.post(
        f"{PAYSLIPS}generate/", {"year": 2026, "month": 6}, format="json"
    )
    assert resp.status_code == 200, resp.json()
    assert resp.json() == {
        "created": 1,
        "replaced": 0,
        "removed": 1,
        "missing_rate": [{"id": hamza.id, "full_name": "Hamza"}],
        "other_currency": [{"id": payroll.maryam.id, "full_name": "Maryam"}],
    }
    bad = payroll.admin.post(
        f"{PAYSLIPS}generate/", {"year": 2026, "month": 0}, format="json"
    )
    assert bad.status_code == 400
    assert "month" in bad.json()


def test_issue_and_mark_paid_answer_the_fresh_payslip(payroll, world, clock):
    draft = payroll.admin.get(f"{PAYSLIPS}{payroll.draft}/").json()
    assert draft["status"] == "draft"
    issued = payroll.admin.post(f"{PAYSLIPS}{payroll.draft}/issue/")
    assert issued.status_code == 200, issued.json()
    assert (issued.json()["status"], issued.json()["net_minor"]) == ("issued", 300)
    paid = payroll.admin.post(
        f"{PAYSLIPS}{payroll.draft}/mark-paid/",
        {"paid_on": "2026-07-01", "notes": "Wise"},
        format="json",
    )
    assert paid.status_code == 200, paid.json()
    body = paid.json()
    assert (body["status"], body["paid_on"], body["notes"]) == (
        "paid",
        "2026-07-01",
        "Wise",
    )
    assert body["paid_by"]["id"] == payroll.admin_user.id


def test_refusals_are_coded_409s_and_field_400s(payroll):
    again = payroll.admin.post(f"{PAYSLIPS}{payroll.issued}/issue/")
    assert again.status_code == 409
    assert again.json() == {
        "detail": "Not allowed while the payslip is issued.",
        "code": "payroll.not_allowed_in_status",
    }
    early = payroll.admin.post(f"{PAYSLIPS}{payroll.own_draft}/issue/")
    assert (early.status_code, early.json()["code"]) == (409, "payroll.month_not_over")
    future = payroll.admin.post(
        f"{PAYSLIPS}{payroll.issued}/mark-paid/",
        {"paid_on": "2026-07-02"},
        format="json",
    )
    assert future.status_code == 400
    assert "paid_on" in future.json()


def test_the_csv_is_for_admins(payroll):
    resp = payroll.admin.get(f"{PAYSLIPS}?format=csv&month=6")
    assert resp.status_code == 200
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0] == [
        "Number",
        "Teacher",
        "Year",
        "Month",
        "Sessions",
        "Minutes",
        "Gross (minor units)",
        "Bonuses (minor units)",
        "Deductions (minor units)",
        "Net (minor units)",
        "Currency",
        "Status",
        "Missing rate",
        "Paid on",
    ]
    assert rows[1] == [
        "PAY-000001",
        "Bilal",
        "2026",
        "6",
        "2",
        "90",
        "1500",
        "500",
        "0",
        "2000",
        "USD",
        "issued",
        "no",
        "",
    ]
    teacher = as_user(payroll.bilal).get(f"{PAYSLIPS}?format=csv")
    assert teacher.status_code == 403
    assert "csv" not in teacher.headers["Content-Type"]


def test_the_payslip_list_costs_the_same_queries_for_more_rows(payroll):
    def queries():
        with CaptureQueriesContext(connection) as ctx:
            assert payroll.admin.get(PAYSLIPS).status_code == 200
        return len(ctx.captured_queries)

    three = queries()
    for n in range(3):
        adjust(make_teacher(f"T{n}"), "bonus", 100, on=date(2026, 6, 1))
    services.generate(2026, 6)
    assert Payslip.objects.count() == 6
    assert queries() == three


# ── Rates ────────────────────────────────────────────────────────────────────


def test_rates_are_created_edited_and_deleted(payroll, world):
    created = payroll.admin.post(
        RATES,
        {
            "teacher": payroll.bilal.id,
            "course": world.course.pk,
            "hourly_rate_minor": 1200,
        },
        format="json",
    )
    assert created.status_code == 201, created.json()
    body = created.json()
    assert body["course"] == {
        "id": world.course.pk,
        "name_ar": "تجويد",
        "name_en": "Tajweed",
    }
    assert (body["hourly_rate_minor"], body["currency"], body["counts"]) == (
        1200,
        "USD",
        True,
    )
    twice = payroll.admin.post(
        RATES, {"teacher": payroll.bilal.id, "hourly_rate_minor": 1}, format="json"
    )
    assert twice.status_code == 400
    assert "course" in twice.json()
    edited = payroll.admin.patch(
        f"{RATES}{body['id']}/", {"hourly_rate_minor": 1300}, format="json"
    )
    assert edited.json()["hourly_rate_minor"] == 1300
    listed = payroll.admin.get(f"{RATES}?teacher={payroll.bilal.id}").json()
    assert [(row["course"] or {}).get("id") for row in listed] == [
        None,
        world.course.pk,
    ]
    assert (
        payroll.admin.put(f"{RATES}{body['id']}/", {}, format="json").status_code == 405
    )
    assert payroll.admin.delete(f"{RATES}{body['id']}/").status_code == 204
    assert payroll.admin.get(RATES).json()[0]["course"] is None


def test_the_rate_list_costs_the_same_queries_for_more_rates(payroll, world):
    def queries():
        with CaptureQueriesContext(connection) as ctx:
            assert payroll.admin.get(RATES).status_code == 200
        return len(ctx.captured_queries)

    set_rate(payroll.bilal, 1200, course=world.course)
    two = queries()
    for n in range(3):
        teacher = make_teacher(f"R{n}")
        set_rate(teacher, 900)
        set_rate(teacher, 950, course=world.course)
    assert queries() == two


# ── Adjustments ──────────────────────────────────────────────────────────────


def test_adjustments_are_created_edited_and_deleted_while_unused(payroll):
    created = payroll.admin.post(
        ADJUSTMENTS,
        {
            "teacher": payroll.maryam.id,
            "kind": "deduction",
            "amount_minor": 200,
            "effective_on": "2026-07-03",
            "reason": "Late",
        },
        format="json",
    )
    assert created.status_code == 201, created.json()
    body = created.json()
    assert (body["kind"], body["currency"], body["payslip"]) == (
        "deduction",
        "USD",
        None,
    )
    assert body["created_by"]["id"] == payroll.admin_user.id
    edited = payroll.admin.patch(
        f"{ADJUSTMENTS}{body['id']}/", {"amount_minor": 250}, format="json"
    )
    assert edited.json()["amount_minor"] == 250
    assert payroll.admin.delete(f"{ADJUSTMENTS}{body['id']}/").status_code == 204
    used = PayAdjustment.objects.get(payslip_id=payroll.issued)
    refused = payroll.admin.patch(
        f"{ADJUSTMENTS}{used.pk}/", {"amount_minor": 1}, format="json"
    )
    assert refused.status_code == 409
    assert refused.json()["code"] == "payroll.adjustment_used"
    listed = payroll.admin.get(f"{ADJUSTMENTS}?used=true").json()["results"]
    assert [row["payslip"] for row in listed] == [
        {"id": payroll.issued, "number": "PAY-000001"}
    ]


# ── Roles and academies ──────────────────────────────────────────────────────


def test_every_role_on_every_route(payroll, world):
    rate = TeacherRate.objects.get().pk
    adjustment = PayAdjustment.objects.filter(payslip__isnull=True).first().pk
    admin_only = [
        ("get", RATES, None),
        ("post", RATES, {"teacher": payroll.maryam.id, "hourly_rate_minor": 1}),
        ("patch", f"{RATES}{rate}/", {"hourly_rate_minor": 2}),
        ("get", ADJUSTMENTS, None),
        (
            "post",
            ADJUSTMENTS,
            {
                "teacher": payroll.maryam.id,
                "kind": "bonus",
                "amount_minor": 1,
                "effective_on": "2026-07-01",
                "reason": "x",
            },
        ),
        ("patch", f"{ADJUSTMENTS}{adjustment}/", {"reason": "y"}),
        ("post", f"{PAYSLIPS}generate/", {"year": 2026, "month": 6}),
        ("post", f"{PAYSLIPS}{payroll.draft}/issue/", {}),
        ("post", f"{PAYSLIPS}{payroll.issued}/mark-paid/", {"paid_on": "2026-07-01"}),
        ("get", f"{PAYSLIPS}?format=csv", None),
        ("delete", f"{ADJUSTMENTS}{adjustment}/", None),
        ("delete", f"{RATES}{rate}/", None),
    ]
    reads = [PAYSLIPS, f"{PAYSLIPS}{payroll.issued}/"]
    parent = identity_services.create_person("parent", full_name="Omar")
    clients = {
        "teacher": as_user(payroll.bilal),
        "student": as_user(world.student),
        "parent": as_user(parent),
        "anonymous": APIClient(),
    }
    for role, client in clients.items():
        for path in reads:
            expected = 200 if role == "teacher" else 403
            assert client.get(path).status_code == expected, (role, path)
        for method, path, data in admin_only:
            resp = getattr(client, method)(path, data, format="json")
            assert resp.status_code == 403, (role, method, path)
    for method, path, data in admin_only:
        resp = getattr(payroll.admin, method)(path, data, format="json")
        assert resp.status_code in (200, 201, 204), (method, path, resp.content)


def test_another_academy_never_leaks(payroll, tenants):
    ceiling = Payslip.objects.aggregate(m=Max("pk"))["m"]
    with tenant_context(tenants.other):
        kareem = make_teacher("Kareem")

        def their_payslip():
            adjust(kareem, "bonus", 700, on=date(2026, 6, 10))
            services.generate(2026, 6)
            return Payslip.objects.get()

        theirs = until_pk_exceeds(Payslip, ceiling, their_payslip)
    assert theirs.pk > ceiling
    listing = payroll.admin.get(PAYSLIPS).json()["results"]
    assert payroll.issued in [row["id"] for row in listing]
    assert theirs.pk not in [row["id"] for row in listing]
    assert payroll.admin.get(f"{PAYSLIPS}{theirs.pk}/").status_code == 404
    assert payroll.admin.post(f"{PAYSLIPS}{theirs.pk}/issue/").status_code == 404
    resp = payroll.admin.post(
        f"{PAYSLIPS}{theirs.pk}/mark-paid/", {"paid_on": "2026-07-01"}, format="json"
    )
    assert resp.status_code == 404
    with tenant_context(tenants.other):
        theirs.refresh_from_db()
        assert theirs.status == "draft"
    assert payroll.admin.get(f"{PAYSLIPS}{payroll.issued}/").status_code == 200
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/payroll/tests/test_api.py etqan/catalogue/tests/test_services.py -q`

Expected: FAIL — 404s on `/api/v1/payroll/…` and `AttributeError: … has no attribute 'courses_by_id'`.

- [ ] **Step 3: Implement**

In `backend/etqan/catalogue/services.py`, replace:

```python


def find_course(name_en: str) -> Course | None:
    return Course.objects.filter(name_en=name_en).first()
```

with:

```python


def courses_by_id(course_ids) -> dict[int, Course]:
    """Several courses in one query, keyed by id; a missing id is absent
    (payroll's rate list, Plan 7)."""
    return {c.pk: c for c in Course.objects.filter(pk__in=list(course_ids))}


def find_course(name_en: str) -> Course | None:
    return Course.objects.filter(name_en=name_en).first()
```

In `backend/etqan/payroll/services/rules.py` (1 of 2), replace:

```python

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import F
from django.db.models import Q
from django.db.models import QuerySet

from etqan.identity import services as identity_services
from etqan.payroll import clock
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import TeacherRate
from etqan.platform.exceptions import ValidationError
```

with:

```python

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Count
from django.db.models import F
from django.db.models import IntegerField
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Subquery
from django.db.models import Sum
from django.db.models import Value
from django.db.models.functions import Coalesce

from etqan.identity import services as identity_services
from etqan.payroll import clock
from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip
from etqan.payroll.models import PayslipLine
from etqan.payroll.models import TeacherRate
from etqan.platform.exceptions import ValidationError
```

In `backend/etqan/payroll/services/rules.py` (2 of 2), replace:

```python
        payslip__isnull=True, effective_on__lte=last
    ).exclude(currency=F("teacher__pay_currency"))
```

with:

```python
        payslip__isnull=True, effective_on__lte=last
    ).exclude(currency=F("teacher__pay_currency"))


# Spec §4.7: a teacher reads their own issued and paid payslips, never a draft.
TEACHER_VISIBLE = (Payslip.Status.ISSUED, Payslip.Status.PAID)


def _session_lines(aggregate):
    lines = (
        PayslipLine.objects.filter(
            payslip=OuterRef("pk"), kind=PayslipLine.Kind.SESSION
        )
        .order_by()
        .values("payslip")
        .annotate(value=aggregate)
        .values("value")
    )
    return Coalesce(Subquery(lines, output_field=IntegerField()), Value(0))


def payslips_queryset() -> QuerySet[Payslip]:
    """Payslips with everything a row shows, in one query: the teacher and
    the admins who issued and paid joined, and ``sessions`` and ``minutes``
    counted from the session lines in SQL (subqueries, so a row never
    multiplies by its lines)."""
    return Payslip.objects.select_related(
        "teacher__user", "issued_by", "paid_by"
    ).annotate(
        sessions=_session_lines(Count("pk")),
        minutes=_session_lines(Sum("minutes")),
    )


def filter_payslips(
    payslips: QuerySet[Payslip],
    *,
    year: int | None = None,
    month: int | None = None,
    teacher: int | None = None,
    status: str = "",
) -> QuerySet[Payslip]:
    """The payslip list's filters (spec §5); a teacher is a User id. Newest
    month first, then by teacher name."""
    exact = {"year": year, "month": month, "teacher__user_id": teacher}
    payslips = payslips.filter(
        **{key: value for key, value in exact.items() if value is not None}
    )
    if status:
        payslips = payslips.filter(status=status)
    return payslips.order_by("-year", "-month", "teacher__user__full_name", "id")


def has_payroll() -> bool:
    """Whether this academy has any rate, adjustment or payslip (seeds)."""
    return (
        TeacherRate.objects.exists()
        or PayAdjustment.objects.exists()
        or Payslip.objects.exists()
    )
```

Replace the whole of `backend/etqan/payroll/services/__init__.py` with:

```python
"""Public API of the payroll module. Other apps import only this package."""

from etqan.payroll.services.adjustments import adjustments_queryset
from etqan.payroll.services.adjustments import create_adjustment
from etqan.payroll.services.adjustments import delete_adjustment
from etqan.payroll.services.adjustments import filter_adjustments
from etqan.payroll.services.adjustments import update_adjustment
from etqan.payroll.services.payslips import GenerateResult
from etqan.payroll.services.payslips import generate
from etqan.payroll.services.payslips import issue
from etqan.payroll.services.payslips import mark_paid
from etqan.payroll.services.rates import create_rate
from etqan.payroll.services.rates import delete_rate
from etqan.payroll.services.rates import rates_queryset
from etqan.payroll.services.rates import update_rate
from etqan.payroll.services.rules import TEACHER_VISIBLE
from etqan.payroll.services.rules import filter_payslips
from etqan.payroll.services.rules import has_payroll
from etqan.payroll.services.rules import payslips_queryset

__all__ = [
    "TEACHER_VISIBLE",
    "GenerateResult",
    "adjustments_queryset",
    "create_adjustment",
    "create_rate",
    "delete_adjustment",
    "delete_rate",
    "filter_adjustments",
    "filter_payslips",
    "generate",
    "has_payroll",
    "issue",
    "mark_paid",
    "payslips_queryset",
    "rates_queryset",
    "update_adjustment",
    "update_rate",
]
```

Create `backend/etqan/payroll/scopes.py`:

```python
"""Who sees which payslips (spec §4.7). Out of scope → 404."""

from etqan.payroll import services
from etqan.platform.permissions import role_of


def scope_for(user, queryset):
    """Filter a Payslip queryset: admins read every payslip; a teacher reads
    their own issued and paid ones, never a draft; everyone else none."""
    role = role_of(user)
    if role == "admin":
        return queryset
    if role == "teacher":
        return queryset.filter(teacher__user=user, status__in=services.TEACHER_VISIBLE)
    return queryset.none()
```

Create `backend/etqan/payroll/api/__init__.py`:

```python

```

Create `backend/etqan/payroll/api/payloads.py`:

```python
"""JSON shapes for payroll (plan D4). A payslip's `notes`, `issued_by` and
`paid_by` are for admins only (spec §4.7); the flag is keyword-only with no
default, so a caller cannot forget it."""

STAFF_ONLY_PAYSLIP_FIELDS = ("notes", "issued_by", "paid_by")


def person(user) -> dict | None:
    if user is None:
        return None
    return {"id": user.pk, "full_name": user.full_name}


def _named(course) -> dict:
    return {"id": course.pk, "name_ar": course.name_ar, "name_en": course.name_en}


def rate_row(rate, courses: dict) -> dict:
    """``courses`` maps course ids to courses (`courses_by_id`). ``counts``
    is false for a rate left in a currency the teacher is no longer paid in
    (spec §4.6). A course deleted since is named by its id alone."""
    course = None
    if rate.course_id is not None:
        found = courses.get(rate.course_id)
        course = (
            _named(found)
            if found
            else {"id": rate.course_id, "name_ar": "", "name_en": ""}
        )
    return {
        "id": rate.pk,
        "teacher": person(rate.teacher.user),
        "course": course,
        "hourly_rate_minor": rate.hourly_rate_minor,
        "currency": rate.currency,
        "counts": rate.currency == rate.teacher.pay_currency,
        "created_at": rate.created_at,
        "updated_at": rate.updated_at,
    }


def adjustment_row(adjustment) -> dict:
    payslip = adjustment.payslip
    return {
        "id": adjustment.pk,
        "teacher": person(adjustment.teacher.user),
        "kind": adjustment.kind,
        "amount_minor": adjustment.amount_minor,
        "currency": adjustment.currency,
        "effective_on": adjustment.effective_on,
        "reason": adjustment.reason,
        "payslip": {"id": payslip.pk, "number": payslip.number} if payslip else None,
        "created_by": person(adjustment.created_by),
        "created_at": adjustment.created_at,
    }


def payslip_row(payslip, *, is_admin: bool) -> dict:
    """Read ``payslip`` from `services.payslips_queryset()`: it carries
    ``sessions`` and ``minutes``."""
    row = {
        "id": payslip.pk,
        "number": payslip.number,
        "status": payslip.status,
        "teacher": person(payslip.teacher.user),
        "year": payslip.year,
        "month": payslip.month,
        "currency": payslip.currency,
        "sessions": payslip.sessions,
        "minutes": payslip.minutes,
        "gross_minor": payslip.gross_minor,
        "bonuses_minor": payslip.bonuses_minor,
        "deductions_minor": payslip.deductions_minor,
        "net_minor": payslip.net_minor,
        "missing_rate": payslip.missing_rate,
        "issued_at": payslip.issued_at,
        "paid_on": payslip.paid_on,
        "created_at": payslip.created_at,
        "updated_at": payslip.updated_at,
        "notes": payslip.notes,
        "issued_by": person(payslip.issued_by),
        "paid_by": person(payslip.paid_by),
    }
    if not is_admin:
        for field in STAFF_ONLY_PAYSLIP_FIELDS:
            row.pop(field)
    return row


def line_row(line) -> dict:
    return {
        "id": line.pk,
        "kind": line.kind,
        "session_id": line.session_id,
        "adjustment_id": line.adjustment_id,
        "description": line.description,
        "minutes": line.minutes,
        "rate_minor": line.rate_minor,
        "amount_minor": line.amount_minor,
    }


def payslip_detail(payslip, *, is_admin: bool) -> dict:
    """The row plus its lines (prefetched), sessions first as copied."""
    return {
        **payslip_row(payslip, is_admin=is_admin),
        "lines": [line_row(line) for line in payslip.lines.all()],
    }


def generate_result(result) -> dict:
    return {
        "created": result.created,
        "replaced": result.replaced,
        "removed": result.removed,
        "missing_rate": [person(user) for user in result.missing_rate],
        "other_currency": [person(user) for user in result.other_currency],
    }
```

Create `backend/etqan/payroll/api/serializers.py`:

```python
"""Request bodies and list queries (spec §5). Responses are built in
`payloads`."""

from rest_framework import serializers

from etqan.payroll.models import PayAdjustment
from etqan.payroll.models import Payslip

YEARS = {"min_value": 2000, "max_value": 2100}
MONTHS = {"min_value": 1, "max_value": 12}


def _id(**kwargs):
    return serializers.IntegerField(min_value=1, **kwargs)


class RateQueryInput(serializers.Serializer):
    teacher = _id(required=False)


class RateCreateInput(serializers.Serializer):
    teacher = _id()
    course = _id(required=False, allow_null=True)
    hourly_rate_minor = serializers.IntegerField(min_value=0)


class RateUpdateInput(serializers.Serializer):
    hourly_rate_minor = serializers.IntegerField(min_value=0)


class AdjustmentQueryInput(serializers.Serializer):
    teacher = _id(required=False)
    used = serializers.BooleanField(required=False, allow_null=True, default=None)


class AdjustmentCreateInput(serializers.Serializer):
    teacher = _id()
    kind = serializers.ChoiceField(choices=PayAdjustment.Kind.choices)
    amount_minor = serializers.IntegerField(min_value=1)
    effective_on = serializers.DateField()
    reason = serializers.CharField()


class AdjustmentUpdateInput(serializers.Serializer):
    kind = serializers.ChoiceField(choices=PayAdjustment.Kind.choices, required=False)
    amount_minor = serializers.IntegerField(min_value=1, required=False)
    effective_on = serializers.DateField(required=False)
    reason = serializers.CharField(required=False)


class PayslipQueryInput(serializers.Serializer):
    # A bad value is a 400 on its field, never silently "everything".
    year = serializers.IntegerField(required=False, **YEARS)
    month = serializers.IntegerField(required=False, **MONTHS)
    teacher = _id(required=False)
    status = serializers.ChoiceField(choices=Payslip.Status.choices, required=False)


class MonthInput(serializers.Serializer):
    year = serializers.IntegerField(**YEARS)
    month = serializers.IntegerField(**MONTHS)


class MarkPaidInput(serializers.Serializer):
    paid_on = serializers.DateField()
    notes = serializers.CharField(required=False, allow_blank=True)
```

Create `backend/etqan/payroll/api/views.py`:

```python
"""Payroll endpoints (spec §5). Thin: parse, call one service, re-read and
arrange a payload. Only the methods the spec lists: no PUT."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.catalogue import services as catalogue_services
from etqan.payroll import services
from etqan.payroll.api import payloads
from etqan.payroll.api.serializers import AdjustmentCreateInput
from etqan.payroll.api.serializers import AdjustmentQueryInput
from etqan.payroll.api.serializers import AdjustmentUpdateInput
from etqan.payroll.api.serializers import MarkPaidInput
from etqan.payroll.api.serializers import MonthInput
from etqan.payroll.api.serializers import PayslipQueryInput
from etqan.payroll.api.serializers import RateCreateInput
from etqan.payroll.api.serializers import RateQueryInput
from etqan.payroll.api.serializers import RateUpdateInput
from etqan.payroll.scopes import scope_for
from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import role_of

# Spec §4.7: admins do everything; a teacher reads their own issued and paid
# payslips (`scope_for`); students, parents and visitors get 403.
READERS = IsAdmin | (ReadOnly & IsTeacher)
CSV_COLUMNS = (
    ("number", "Number"),
    ("teacher", "Teacher"),
    ("year", "Year"),
    ("month", "Month"),
    ("sessions", "Sessions"),
    ("minutes", "Minutes"),
    ("gross_minor", "Gross (minor units)"),
    ("bonuses_minor", "Bonuses (minor units)"),
    ("deductions_minor", "Deductions (minor units)"),
    ("net_minor", "Net (minor units)"),
    ("currency", "Currency"),
    ("status", "Status"),
    ("missing_rate", "Missing rate"),
    ("paid_on", "Paid on"),
)


def _is_admin(request) -> bool:
    return role_of(request.user) == "admin"


# ── Rates ────────────────────────────────────────────────────────────────────


def rate_rows(rates) -> list[dict]:
    rates = list(rates)
    courses = catalogue_services.courses_by_id(
        {rate.course_id for rate in rates if rate.course_id is not None}
    )
    return [payloads.rate_row(rate, courses) for rate in rates]


def rate_or_404(pk):
    return get_object_or_404(services.rates_queryset(), pk=pk)


class RateListView(APIView):
    """Every rate at once (not paged): a page groups them by teacher."""

    permission_classes = [IsAdmin]

    def get(self, request):
        query = RateQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rates = services.rates_queryset()
        if "teacher" in query.validated_data:
            rates = rates.filter(teacher__user_id=query.validated_data["teacher"])
        return Response(rate_rows(rates))

    def post(self, request):
        body = RateCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        rate = services.create_rate(
            teacher_id=data["teacher"],
            course_id=data.get("course"),
            hourly_rate_minor=data["hourly_rate_minor"],
        )
        (row,) = rate_rows([rate_or_404(rate.pk)])
        return Response(row, status=status.HTTP_201_CREATED)


class RateDetailView(APIView):
    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        rate = rate_or_404(pk)
        body = RateUpdateInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.update_rate(rate, **body.validated_data)
        (row,) = rate_rows([rate_or_404(pk)])
        return Response(row)

    def delete(self, request, pk):
        services.delete_rate(rate_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


# ── Adjustments ──────────────────────────────────────────────────────────────


def adjustment_or_404(pk):
    return get_object_or_404(services.adjustments_queryset(), pk=pk)


class AdjustmentListView(generics.GenericAPIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        query = AdjustmentQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        adjustments = services.filter_adjustments(
            services.adjustments_queryset(), **query.validated_data
        )
        page = self.paginate_queryset(adjustments)
        return self.get_paginated_response([payloads.adjustment_row(a) for a in page])

    def post(self, request):
        body = AdjustmentCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        adjustment = services.create_adjustment(
            teacher_id=data.pop("teacher"), **data, by=request.user
        )
        return Response(
            payloads.adjustment_row(adjustment_or_404(adjustment.pk)),
            status=status.HTTP_201_CREATED,
        )


class AdjustmentDetailView(APIView):
    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        adjustment = adjustment_or_404(pk)
        body = AdjustmentUpdateInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_adjustment(adjustment, **body.validated_data)
        return Response(payloads.adjustment_row(adjustment_or_404(pk)))

    def delete(self, request, pk):
        services.delete_adjustment(adjustment_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


# ── Payslips ─────────────────────────────────────────────────────────────────


def payslip_or_404(request, pk):
    payslips = scope_for(request.user, services.payslips_queryset())
    return get_object_or_404(payslips.prefetch_related("lines"), pk=pk)


def detail(pk, request) -> Response:
    """A fresh read of what a write changed."""
    payslip = services.payslips_queryset().prefetch_related("lines").get(pk=pk)
    return Response(payloads.payslip_detail(payslip, is_admin=_is_admin(request)))


class PayslipListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [READERS]
    csv_filename = "payslips"
    csv_columns = CSV_COLUMNS

    def get(self, request):
        query = PayslipQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        payslips = services.filter_payslips(
            scope_for(request.user, services.payslips_queryset()),
            **query.validated_data,
        )
        if self.wants_csv():
            # Raised, not returned: CSVExportMixin answers the error as JSON.
            if not _is_admin(request):
                raise PermissionDenied("CSV export is for admins only.")
            return self.csv_response(
                [payloads.payslip_row(p, is_admin=True) for p in payslips]
            )
        page = self.paginate_queryset(payslips)
        is_admin = _is_admin(request)
        return self.get_paginated_response(
            [payloads.payslip_row(p, is_admin=is_admin) for p in page]
        )


class GenerateView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        body = MonthInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = services.generate(**body.validated_data)
        return Response(payloads.generate_result(result))


class PayslipDetailView(APIView):
    permission_classes = [READERS]

    def get(self, request, pk):
        payslip = payslip_or_404(request, pk)
        return Response(payloads.payslip_detail(payslip, is_admin=_is_admin(request)))


class IssueView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        services.issue(payslip_or_404(request, pk), by=request.user)
        return detail(pk, request)


class MarkPaidView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        payslip = payslip_or_404(request, pk)
        body = MarkPaidInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.mark_paid(payslip, **body.validated_data, by=request.user)
        return detail(pk, request)
```

Create `backend/etqan/payroll/api/urls.py`:

```python
from django.urls import path

from etqan.payroll.api import views

app_name = "payroll"
urlpatterns = [
    path("rates/", views.RateListView.as_view(), name="rates"),
    path("rates/<int:pk>/", views.RateDetailView.as_view(), name="rate"),
    path("adjustments/", views.AdjustmentListView.as_view(), name="adjustments"),
    path(
        "adjustments/<int:pk>/",
        views.AdjustmentDetailView.as_view(),
        name="adjustment",
    ),
    path("payslips/", views.PayslipListView.as_view(), name="payslips"),
    path("payslips/generate/", views.GenerateView.as_view(), name="payslips-generate"),
    path("payslips/<int:pk>/", views.PayslipDetailView.as_view(), name="payslip"),
    path("payslips/<int:pk>/issue/", views.IssueView.as_view(), name="issue"),
    path(
        "payslips/<int:pk>/mark-paid/", views.MarkPaidView.as_view(), name="mark-paid"
    ),
]
```

In `backend/config/api_router.py`, replace:

```python
    # invoices/, payments/, summary/, payers/ (Plan 6 spec §5).
    path("billing/", include("etqan.billing.api.urls")),
    # OpenAPI schema (drf-spectacular) + Swagger UI / ReDoc browsers.
    path("schema/", SpectacularAPIView.as_view(), name="schema"),
```

with:

```python
    # invoices/, payments/, summary/, payers/ (Plan 6 spec §5).
    path("billing/", include("etqan.billing.api.urls")),
    # rates/, adjustments/, payslips/ (Plan 7 spec §5).
    path("payroll/", include("etqan.payroll.api.urls")),
    # OpenAPI schema (drf-spectacular) + Swagger UI / ReDoc browsers.
    path("schema/", SpectacularAPIView.as_view(), name="schema"),
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/payroll etqan/catalogue -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1107 tests, coverage 97.9% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/payroll etqan/catalogue config/api_router.py
git -C backend commit -m "feat(payroll): the payroll API

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dev seeds: rates, bonuses and last month's payslips

**Files:**
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py`
- Test: `backend/etqan/tenants/tests/test_seed_dev.py`

**Interfaces:**
- Consumes: Task 3's `create_rate`, `create_adjustment`, `rates_queryset`; Task 5's `generate`; Task 6's `issue`, `mark_paid`; Task 7's `payslips_queryset`, `has_payroll`.
- Produces: `seed_dev.PAYROLL`, `seed_dev.last_month(today) -> date` (the last day of the month before) and `seed_dev.seed_payroll(spec: dict | None)`, called for each academy after `seed_billing` (D15).

- [ ] **Step 1: Write the failing tests**

The seeds are pinned twice: on today's real date (often with no seeded session last month) and on 5 June 2026 (with seeded sessions in May, which must be paid too). Running `seed_dev` twice changes nothing, the `other` academy gets nothing, and an issue a rule refuses is skipped with `skip:` while the rest carries on.

In `backend/etqan/tenants/tests/test_seed_dev.py` (1 of 2), replace:

```python
import pytest
from django.core.management import call_command
```

with:

```python
from datetime import UTC
from datetime import datetime

import pytest
from django.core.management import call_command
```

In `backend/etqan/tenants/tests/test_seed_dev.py` (2 of 2), replace:

```python
    assert statuses == ["paid", "partial", "unpaid", "unpaid"]
    assert capsys.readouterr().out.count("invoice — Not now.") == 1
```

with:

```python
    assert statuses == ["paid", "partial", "unpaid", "unpaid"]
    assert capsys.readouterr().out.count("invoice — Not now.") == 1


# The 5th of June: the seeded sessions of the last 17 days reach into May.
EARLY_IN_THE_MONTH = datetime(2026, 6, 5, 8, tzinfo=UTC)
CLOCKS = (
    "etqan.scheduling.dates.now",
    "etqan.billing.clock.now",
    "etqan.payroll.clock.now",
)


@pytest.mark.django_db
@override_settings(DEBUG=True)
@pytest.mark.parametrize("pinned", [None, EARLY_IN_THE_MONTH])
def test_seed_dev_pays_the_demo_teachers_for_last_month_once(monkeypatch, pinned):
    from etqan.payroll import services as payroll  # noqa: PLC0415
    from etqan.scheduling import services as scheduling  # noqa: PLC0415

    if pinned is not None:
        # By dotted path: tenants may import only the apps' services.
        for clock in CLOCKS:
            monkeypatch.setattr(clock, lambda: pinned)

    def state():
        rates = [
            (r.teacher.user.full_name, r.course_id is None, r.hourly_rate_minor)
            for r in payroll.rates_queryset()
        ]
        payslips = [
            (p.teacher.user.full_name, p.year, p.month, p.status, p.paid_on)
            for p in payroll.payslips_queryset().order_by("teacher__user__full_name")
        ]
        return rates, payslips

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        today = scheduling.today()
        last = seed_dev.last_month(today)
        first = state()
        # Bilal: a default and a Tajweed rate; Maryam: a course rate only.
        assert first[0] == [
            ("Ustadh Bilal", True, 1000),
            ("Ustadh Bilal", False, 1200),
            ("Ustadha Maryam", False, 900),
        ]
        assert first[1] == [
            ("Ustadh Bilal", last.year, last.month, "paid", today),
            ("Ustadha Maryam", last.year, last.month, "issued", None),
        ]
        # Each net holds at least its bonus; early in a month, last month's
        # seeded sessions are paid too.
        nets = [p.net_minor for p in payroll.payslips_queryset().order_by("pk")]
        assert nets[0] >= 2000
        assert nets[1] >= 1500
        if pinned is not None:
            assert all(p.sessions > 0 for p in payroll.payslips_queryset())
    with tenant_context(other):
        assert not payroll.has_payroll()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_payroll_skips_what_a_rule_refuses_and_carries_on(capsys, monkeypatch):
    from etqan.payroll import services as payroll  # noqa: PLC0415
    from etqan.platform.exceptions import ConflictError  # noqa: PLC0415

    def refuse(payslip, *, by):
        raise ConflictError("Not now.", code="payroll.test_refusal")

    monkeypatch.setattr(payroll, "issue", refuse)
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(Academy.objects.get(subdomain="demo")):
        statuses = [p.status for p in payroll.payslips_queryset()]
        assert payroll.rates_queryset().count() == 3
    assert statuses == ["draft", "draft"]
    assert capsys.readouterr().out.count("payslip — Not now.") == 2
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py -q`

Expected: FAIL — `AttributeError: module '…seed_dev' has no attribute 'last_month'`.

- [ ] **Step 3: Implement**

In `backend/etqan/tenants/management/commands/seed_dev.py` (1 of 4), replace:

```python
"""Known academies and accounts for local development and the e2e suite. DEBUG only."""

from datetime import time
from datetime import timedelta
```

with:

```python
"""Known academies and accounts for local development and the e2e suite. DEBUG only."""

from datetime import date
from datetime import time
from datetime import timedelta
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (2 of 4), replace:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
```

with:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.payroll import services as payroll_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (3 of 4), replace:

```python


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."
```

with:

```python


# Plan 7 (spec §7): the demo teachers' rates, as (teacher, course or None for
# the default, hourly rate in minor units of their pay currency, USD). Maryam
# has only a course rate, so the Rates page warns she has no default. Each
# gets a bonus in the middle of last month, so both of last month's payslips
# exist whatever today is (the seeded sessions all start in the last 17
# days): Bilal's is issued and marked paid, Maryam's issued.
PAYROLL = {
    "demo": {
        "rates": (
            ("Ustadh Bilal", None, 1000),
            ("Ustadh Bilal", "Tajweed", 1200),
            ("Ustadha Maryam", "Quran Memorisation", 900),
        ),
        "bonuses": (
            ("Ustadh Bilal", 2000, "Ramadan intensive"),
            ("Ustadha Maryam", 1500, "Covered a colleague's sessions"),
        ),
        "paid": ("Ustadh Bilal",),
        "issued": ("Ustadha Maryam",),
    },
}
SKIPPED = (ValidationError, ConflictError, NotFoundError)


def last_month(today: date) -> date:
    """The last day of the month before ``today``'s."""
    return today.replace(day=1) - timedelta(days=1)


def _seed_rates(rates) -> None:
    for name, course_name, hourly in rates:
        teacher = _person("teacher", name)
        course = catalogue_services.find_course(course_name) if course_name else None
        if teacher is None or (course_name and course is None):
            print(f"skip: {name} rate — seeded record not found")  # noqa: T201
            continue
        try:
            payroll_services.create_rate(
                teacher_id=teacher.id,
                course_id=course.pk if course else None,
                hourly_rate_minor=hourly,
            )
        except SKIPPED as exc:
            print(f"skip: {name} rate — {exc}")  # noqa: T201


def _seed_bonuses(bonuses, effective_on: date) -> None:
    for name, amount, reason in bonuses:
        teacher = _person("teacher", name)
        if teacher is None:
            print(f"skip: {name} bonus — seeded record not found")  # noqa: T201
            continue
        try:
            payroll_services.create_adjustment(
                teacher_id=teacher.id,
                kind="bonus",
                amount_minor=amount,
                effective_on=effective_on,
                reason=reason,
                by=None,
            )
        except SKIPPED as exc:
            print(f"skip: {name} bonus — {exc}")  # noqa: T201


def _seed_payslips(spec: dict, last: date, today: date) -> None:
    """Generate last month (always over), then issue, and pay today."""
    payroll_services.generate(last.year, last.month)
    payslips = {
        payslip.teacher.user.full_name: payslip
        for payslip in payroll_services.payslips_queryset().filter(
            year=last.year, month=last.month
        )
    }
    outcomes = [(name, True) for name in spec["paid"]]
    outcomes += [(name, False) for name in spec["issued"]]
    for name, paid in outcomes:
        payslip = payslips.get(name)
        if payslip is None:
            print(f"skip: {name} payslip — nothing to pay last month")  # noqa: T201
            continue
        try:
            payroll_services.issue(payslip, by=None)
            if paid:
                payroll_services.mark_paid(payslip, paid_on=today, by=None)
        except SKIPPED as exc:
            print(f"skip: {name} payslip — {exc}")  # noqa: T201


def seed_payroll(spec: dict | None) -> None:
    """Idempotent: an academy with any rate, adjustment or payslip is left
    alone. Only last month is issued (a past month), and only today or
    earlier is a pay date. An item a rule refuses is skipped."""
    if spec is None or payroll_services.has_payroll():
        return
    today = scheduling_services.today()
    last = last_month(today)
    _seed_rates(spec["rates"])
    _seed_bonuses(spec["bonuses"], last.replace(day=15))
    _seed_payslips(spec, last, today)


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (4 of 4), replace:

```python
                seed_attendance()
                seed_billing(INVOICES[subdomain])
```

with:

```python
                seed_attendance()
                seed_billing(INVOICES[subdomain])
                seed_payroll(PAYROLL.get(subdomain))
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1110 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/tenants
git -C backend commit -m "feat(seed): demo rates, bonuses and last month's payslips

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard groundwork: payroll data layer, month helpers and locked sessions

**Files:**
- Create: `dashboard/src/features/payroll/schemas.ts`, `dashboard/src/features/payroll/api.ts`, `dashboard/src/features/payroll/queries.ts`, `dashboard/src/features/payroll/bits.tsx`, `dashboard/src/features/payroll/index.ts`
- Modify: `dashboard/src/features/billing/schemas.ts`, `dashboard/src/lib/zoned-time.ts`, `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/features/scheduling/AttendanceControls.tsx`, `dashboard/src/features/scheduling/SessionPage.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/billing/schemas.test.ts`, `dashboard/src/lib/zoned-time.test.ts`, `dashboard/src/test/payroll-fixtures.ts` (new), `dashboard/src/features/payroll/api.test.ts` (new), `dashboard/src/features/payroll/schemas.test.ts` (new), `dashboard/src/test/scheduling-fixtures.ts`, `dashboard/src/features/scheduling/AttendanceControls.test.tsx`, `dashboard/src/features/scheduling/SessionPage.test.tsx`
- Generated: `dashboard/src/routeTree.gen.ts` (by `vite build`, when a task adds a route)

**Interfaces:**
- Consumes: billing's `amount`; `@/lib/api`'s `api`, `clean`, `csvUrl`, `Paginated`, `QueryParams`; scheduling's `schedulingKey`.
- Produces (`@/features/payroll`): types `Payslip`, `PayslipDetail`, `PayslipLine`, `Rate`, `Adjustment`, `GenerateResult`, `Person`, `CourseRef`, `PayslipStatus`, `AdjustmentKind`, bodies `RateBody`, `AdjustmentBody`, `AdjustmentPatch`, `MarkPaidBody`; constants `PAYSLIP_STATUSES`, `ADJUSTMENT_KINDS`; schemas `rateFormSchema(currency)`, `adjustmentFormSchema(currencyOf)`, `markPaidSchema`; `payrollApi.{rates, createRate, updateRate, deleteRate, adjustments, createAdjustment, updateAdjustment, deleteAdjustment, payslips, payslip, generate, issue, markPaid}`, `payslipsCsvUrl(params)`; hooks `useRates()`, `useAdjustments(params)`, `usePayslips(params, {enabled})`, `usePayslip(id)`, `usePayrollMutation(write)` (refreshes payroll and scheduling); `PayslipStatusChip({payslip})`, `hours(minutes, language)`.
- Produces: `amount(currency, { allowZero })` (billing); `previousMonth(day) -> {year, month}` and `formatMonth(year, month, language)` in `@/lib/zoned-time`; `Session.payroll_locked?: boolean`.
- Produces (tests): `src/test/payroll-fixtures.ts` with `payslipRow`, `lineRow`, `payslipDetail`, `teacherPayslip`, `rateRow`, `adjustmentRow`, `generateResult`.

- [ ] **Step 1: Write the failing tests**

A locked session keeps both attendance pickers disabled with a "Paid in payslip" note, and the session page offers neither cancel nor restore.

In `dashboard/src/features/billing/schemas.test.ts`, replace:

```ts
		expect(amount("EGP").safeParse("-5").success).toBe(false);
		expect(amount("EGP").safeParse("abc").success).toBe(false);
	});
});
```

with:

```ts
		expect(amount("EGP").safeParse("-5").success).toBe(false);
		expect(amount("EGP").safeParse("abc").success).toBe(false);
	});

	it("takes zero when asked, still checking the decimals", () => {
		const rate = amount("EGP", { allowZero: true });
		expect(rate.safeParse("0").success).toBe(true);
		expect(rate.safeParse("-5").success).toBe(false);
		expect(rate.safeParse("1.005").error?.issues[0]?.message).toBe(
			"billing.errors.amountOrZero",
		);
	});
});
```

In `dashboard/src/lib/zoned-time.test.ts` (1 of 2), replace:

```ts
	dayIn,
	formatDay,
	otherZoneTime,
	studentTime,
	todayIn,
```

with:

```ts
	dayIn,
	formatDay,
	formatMonth,
	otherZoneTime,
	previousMonth,
	studentTime,
	todayIn,
```

In `dashboard/src/lib/zoned-time.test.ts` (2 of 2), replace:

```ts
});

describe("weekdayName", () => {
	it("numbers the week from Monday", () => {
```

with:

```ts
});

describe("previousMonth and formatMonth", () => {
	it("steps back a month, across a new year", () => {
		expect(previousMonth("2026-07-01")).toEqual({ year: 2026, month: 6 });
		expect(previousMonth("2026-01-31")).toEqual({ year: 2025, month: 12 });
	});

	it("names the month in the reader's language", () => {
		expect(formatMonth(2026, 6, "en")).toBe("June 2026");
		expect(formatMonth(2026, 12, "en")).toBe("December 2026");
	});
});

describe("weekdayName", () => {
	it("numbers the week from Monday", () => {
```

Create `dashboard/src/test/payroll-fixtures.ts`:

```ts
import type {
	Adjustment,
	GenerateResult,
	Payslip,
	PayslipDetail,
	PayslipLine,
	Rate,
} from "@/features/payroll/schemas";

/** API-shaped payroll rows for feature tests (an admin's view). */
export function payslipRow(overrides: Partial<Payslip> = {}): Payslip {
	return {
		id: 71,
		number: "PAY-000071",
		status: "draft",
		teacher: { id: 21, full_name: "Bilal" },
		year: 2026,
		month: 6,
		currency: "USD",
		sessions: 2,
		minutes: 90,
		gross_minor: 1500,
		bonuses_minor: 500,
		deductions_minor: 200,
		net_minor: 1800,
		missing_rate: false,
		issued_at: null,
		paid_on: null,
		created_at: "2026-07-01T09:00:00Z",
		updated_at: "2026-07-01T09:00:00Z",
		notes: "Bank transfer",
		issued_by: null,
		paid_by: null,
		...overrides,
	};
}

export function lineRow(overrides: Partial<PayslipLine> = {}): PayslipLine {
	return {
		id: 81,
		kind: "session",
		session_id: 41,
		adjustment_id: null,
		description: "2026-06-01 — Tajweed — Yusuf",
		minutes: 45,
		rate_minor: 1000,
		amount_minor: 750,
		...overrides,
	};
}

export function payslipDetail(
	overrides: Partial<PayslipDetail> = {},
): PayslipDetail {
	return {
		...payslipRow(),
		lines: [
			lineRow(),
			lineRow({
				id: 82,
				session_id: 42,
				description: "2026-06-03 — Tajweed — Yusuf",
			}),
			lineRow({
				id: 83,
				kind: "adjustment",
				session_id: null,
				adjustment_id: 91,
				description: "Bonus — Eid",
				minutes: null,
				rate_minor: null,
				amount_minor: 500,
			}),
			lineRow({
				id: 84,
				kind: "adjustment",
				session_id: null,
				adjustment_id: 92,
				description: "Deduction — Late",
				minutes: null,
				rate_minor: null,
				amount_minor: -200,
			}),
		],
		...overrides,
	};
}

/** What a teacher receives: their own issued or paid payslip, no staff
 * fields. */
export function teacherPayslip(
	overrides: Partial<PayslipDetail> = {},
): PayslipDetail {
	const {
		notes: _notes,
		issued_by: _issuedBy,
		paid_by: _paidBy,
		...row
	} = payslipDetail({
		status: "issued",
		issued_at: "2026-07-01T10:00:00Z",
	});
	return { ...row, ...overrides };
}

export function rateRow(overrides: Partial<Rate> = {}): Rate {
	return {
		id: 61,
		teacher: { id: 21, full_name: "Bilal" },
		course: null,
		hourly_rate_minor: 1000,
		currency: "USD",
		counts: true,
		created_at: "2026-06-01T08:00:00Z",
		updated_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function adjustmentRow(overrides: Partial<Adjustment> = {}): Adjustment {
	return {
		id: 91,
		teacher: { id: 21, full_name: "Bilal" },
		kind: "bonus",
		amount_minor: 500,
		currency: "USD",
		effective_on: "2026-06-15",
		reason: "Eid",
		payslip: null,
		created_by: { id: 1, full_name: "Amina" },
		created_at: "2026-06-15T08:00:00Z",
		...overrides,
	};
}

export function generateResult(
	overrides: Partial<GenerateResult> = {},
): GenerateResult {
	return {
		created: 2,
		replaced: 1,
		removed: 0,
		missing_rate: [],
		other_currency: [],
		...overrides,
	};
}
```

Create `dashboard/src/features/payroll/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { payrollApi, payslipsCsvUrl } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: { id: 1 } });
	return {
		...actual,
		api: {
			defaults: { baseURL: "/api/v1/" },
			get: vi.fn(ok),
			post: vi.fn(ok),
			patch: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
});

describe("payrollApi", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads rates, adjustments and payslips from the spec §5 routes", async () => {
		await payrollApi.rates();
		expect(api.get).toHaveBeenLastCalledWith("payroll/rates/", { params: {} });
		await payrollApi.adjustments({ used: "false", teacher: "", page: 2 });
		expect(api.get).toHaveBeenLastCalledWith("payroll/adjustments/", {
			params: { used: "false", page: "2" },
		});
		await payrollApi.payslips({ year: 2026, month: 6, status: "" });
		expect(api.get).toHaveBeenLastCalledWith("payroll/payslips/", {
			params: { year: "2026", month: "6" },
		});
		await payrollApi.payslip(71);
		expect(api.get).toHaveBeenLastCalledWith("payroll/payslips/71/");
	});

	it("writes rates, adjustments and payslips", async () => {
		await payrollApi.createRate({ teacher: 21, hourly_rate_minor: 1000 });
		expect(api.post).toHaveBeenLastCalledWith("payroll/rates/", {
			teacher: 21,
			hourly_rate_minor: 1000,
		});
		await payrollApi.updateRate({ id: 61, hourly_rate_minor: 1200 });
		expect(api.patch).toHaveBeenLastCalledWith("payroll/rates/61/", {
			hourly_rate_minor: 1200,
		});
		await payrollApi.deleteRate(61);
		expect(api.delete).toHaveBeenLastCalledWith("payroll/rates/61/");
		const body = {
			teacher: 21,
			kind: "bonus" as const,
			amount_minor: 500,
			effective_on: "2026-06-15",
			reason: "Eid",
		};
		await payrollApi.createAdjustment(body);
		expect(api.post).toHaveBeenLastCalledWith("payroll/adjustments/", body);
		await payrollApi.updateAdjustment({ id: 91, reason: "Late" });
		expect(api.patch).toHaveBeenLastCalledWith("payroll/adjustments/91/", {
			reason: "Late",
		});
		await payrollApi.deleteAdjustment(91);
		expect(api.delete).toHaveBeenLastCalledWith("payroll/adjustments/91/");
		await payrollApi.generate({ year: 2026, month: 6 });
		expect(api.post).toHaveBeenLastCalledWith("payroll/payslips/generate/", {
			year: 2026,
			month: 6,
		});
		await payrollApi.issue(71);
		expect(api.post).toHaveBeenLastCalledWith("payroll/payslips/71/issue/");
		await payrollApi.markPaid({ id: 71, paid_on: "2026-07-01" });
		expect(api.post).toHaveBeenLastCalledWith(
			"payroll/payslips/71/mark-paid/",
			{
				paid_on: "2026-07-01",
			},
		);
	});

	it("exports the filtered list as CSV", () => {
		expect(payslipsCsvUrl({ year: 2026, month: 6, page: 3 })).toBe(
			"/api/v1/payroll/payslips/?year=2026&month=6&format=csv",
		);
	});
});
```

Create `dashboard/src/features/payroll/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { adjustmentFormSchema, rateFormSchema } from "./schemas";

describe("rateFormSchema", () => {
	it("takes a zero rate and checks the decimals of the currency", () => {
		expect(
			rateFormSchema("USD").safeParse({ course: "", amount: "0" }).success,
		).toBe(true);
		expect(
			rateFormSchema("JPY").safeParse({ course: "3", amount: "10.5" }).success,
		).toBe(false);
	});
});

describe("adjustmentFormSchema", () => {
	const currencyOf = (teacher: string) => (teacher === "22" ? "JPY" : "USD");
	const base = {
		teacher: "21",
		kind: "bonus" as const,
		amount: "10.50",
		effective_on: "2026-06-15",
		reason: "Eid",
	};

	it("checks the amount against the chosen teacher's currency", () => {
		const schema = adjustmentFormSchema(currencyOf);
		expect(schema.safeParse(base).success).toBe(true);
		const yen = schema.safeParse({ ...base, teacher: "22" });
		expect(yen.error?.issues[0]).toMatchObject({
			path: ["amount"],
			message: "billing.errors.amountInvalid",
		});
	});

	it("needs a teacher, a date and a reason", () => {
		const result = adjustmentFormSchema(currencyOf).safeParse({
			...base,
			teacher: "",
			effective_on: "",
			reason: " ",
		});
		const messages = Object.fromEntries(
			(result.error?.issues ?? []).map((i) => [i.path[0], i.message]),
		);
		expect(messages).toMatchObject({
			teacher: "payroll.errors.required",
			effective_on: "payroll.errors.dateRequired",
			reason: "payroll.errors.required",
		});
	});
});
```

In `dashboard/src/test/scheduling-fixtures.ts`, replace:

```ts
		cancel_reason: "",
		has_report: false,
		...overrides,
	};
```

with:

```ts
		cancel_reason: "",
		has_report: false,
		payroll_locked: false,
		...overrides,
	};
```

In `dashboard/src/features/scheduling/AttendanceControls.test.tsx`, replace:

```tsx
		).toBeInTheDocument();
	});
});
```

with:

```tsx
		).toBeInTheDocument();
	});

	it("stays closed on a session an issued payslip pays", async () => {
		renderWithRouter(
			<AttendanceControls
				session={sessionRow({
					status: "completed",
					student_attendance: "present",
					payroll_locked: true,
				})}
				canClear
			/>,
		);
		expect(await student()).toBeDisabled();
		expect(await teacher()).toBeDisabled();
		expect(screen.getByText("Paid in payslip")).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/scheduling/SessionPage.test.tsx`, replace:

```tsx
		).toBeInTheDocument();
	});
});
```

with:

```tsx
		).toBeInTheDocument();
	});

	it("offers no cancel or restore on a session an issued payslip pays", async () => {
		vi.mocked(schedulingApi.session).mockResolvedValue(
			sessionRow({
				status: "completed",
				student_attendance: "present",
				payroll_locked: true,
			}),
		);
		renderWithRouter(<SessionPage sessionId="41" />);
		expect(await screen.findByText("Paid in payslip")).toBeInTheDocument();
		expect(
			screen.getByRole("combobox", { name: "Student attendance for Yusuf" }),
		).toBeDisabled();
		expect(screen.queryByRole("button", { name: "Cancel session" })).toBeNull();
		expect(
			screen.queryByRole("button", { name: "Restore session" }),
		).toBeNull();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll src/lib/zoned-time.test.ts src/features/billing/schemas.test.ts src/features/scheduling/AttendanceControls.test.tsx src/features/scheduling/SessionPage.test.tsx`

Expected: FAIL — the payroll files do not exist yet (`Failed to resolve import "./api"`); `previousMonth` is not exported; the locked-session tests find enabled controls.

- [ ] **Step 3: Implement**

In `dashboard/src/features/billing/schemas.ts` (1 of 2), replace:

```ts
 * `minorDigits` decides this, not a fixed number of decimals, and a bad
 * amount is refused rather than silently truncated when it is later turned
 * into minor units).
 */
export function amount(currency: string) {
	const digits = minorDigits(currency);
	const pattern =
```

with:

```ts
 * `minorDigits` decides this, not a fixed number of decimals, and a bad
 * amount is refused rather than silently truncated when it is later turned
 * into minor units). `allowZero` also takes 0 (a teacher's rate, Plan 7).
 */
export function amount(
	currency: string,
	{ allowZero = false }: { allowZero?: boolean } = {},
) {
	const digits = minorDigits(currency);
	const pattern =
```

In `dashboard/src/features/billing/schemas.ts` (2 of 2), replace:

```ts
		.min(1, "billing.errors.required")
		.refine(
			(value) => pattern.test(value.trim()) && Number(value) > 0,
			"billing.errors.amountInvalid",
		);
}
```

with:

```ts
		.min(1, "billing.errors.required")
		.refine(
			(value) => pattern.test(value.trim()) && (allowZero || Number(value) > 0),
			allowZero
				? "billing.errors.amountOrZero"
				: "billing.errors.amountInvalid",
		);
}
```

In `dashboard/src/lib/zoned-time.ts`, replace:

```ts
}

/** A weekday's name, 0 = Monday … 6 = Sunday (the API's numbering). */
export function weekdayName(
```

with:

```ts
}

/** The month before `day`'s ("YYYY-MM-DD"), as numbers: payroll's default
 * month is last month on the academy's calendar (Plan 7 spec §6). */
export function previousMonth(day: string): { year: number; month: number } {
	const [year, month] = day.split("-").map(Number);
	return month === 1
		? { year: year - 1, month: 12 }
		: { year, month: month - 1 };
}

/** A month for people, e.g. "June 2026" in English. */
export function formatMonth(
	year: number,
	month: number,
	language: string,
): string {
	return new Intl.DateTimeFormat(language, {
		month: "long",
		year: "numeric",
		timeZone: "UTC",
	}).format(new Date(Date.UTC(year, month - 1, 1)));
}

/** A weekday's name, 0 = Monday … 6 = Sunday (the API's numbering). */
export function weekdayName(
```

Create `dashboard/src/features/payroll/schemas.ts`:

```ts
import { z } from "zod";
import { amount } from "@/features/billing";

export const PAYSLIP_STATUSES = ["draft", "issued", "paid"] as const;
export type PayslipStatus = (typeof PAYSLIP_STATUSES)[number];
export const ADJUSTMENT_KINDS = ["bonus", "deduction"] as const;
export type AdjustmentKind = (typeof ADJUSTMENT_KINDS)[number];

export interface Person {
	id: number;
	full_name: string;
}
export interface CourseRef {
	id: number;
	name_ar: string;
	name_en: string;
}

/** A default rate (`course` null) or a course's rate (plan D4). `counts`
 * is false for a rate left in a currency the teacher is no longer paid in. */
export interface Rate {
	id: number;
	teacher: Person;
	course: CourseRef | null;
	hourly_rate_minor: number;
	currency: string;
	counts: boolean;
	created_at: string;
	updated_at: string;
}

export interface Adjustment {
	id: number;
	teacher: Person;
	kind: AdjustmentKind;
	amount_minor: number;
	currency: string;
	effective_on: string;
	reason: string;
	// The issued payslip that used it; it no longer changes (spec §4.6).
	payslip: { id: number; number: string } | null;
	created_by: Person | null;
	created_at: string;
}

export interface Payslip {
	id: number;
	number: string;
	status: PayslipStatus;
	teacher: Person;
	year: number;
	month: number;
	currency: string;
	sessions: number;
	minutes: number;
	gross_minor: number;
	bonuses_minor: number;
	deductions_minor: number;
	net_minor: number;
	missing_rate: boolean;
	issued_at: string | null;
	paid_on: string | null;
	created_at: string;
	updated_at: string;
	// Admins only (spec §4.7).
	notes?: string;
	issued_by?: Person | null;
	paid_by?: Person | null;
}

export interface PayslipLine {
	id: number;
	kind: "session" | "adjustment";
	session_id: number | null;
	adjustment_id: number | null;
	description: string;
	minutes: number | null;
	rate_minor: number | null;
	// Signed: a deduction is negative.
	amount_minor: number;
}

export interface PayslipDetail extends Payslip {
	lines: PayslipLine[];
}

export interface GenerateResult {
	created: number;
	replaced: number;
	removed: number;
	missing_rate: Person[];
	other_currency: Person[];
}

// Request bodies (spec §5). People are User ids.
export interface RateBody {
	teacher: number;
	course?: number | null;
	hourly_rate_minor: number;
}
export interface AdjustmentBody {
	teacher: number;
	kind: AdjustmentKind;
	amount_minor: number;
	effective_on: string;
	reason: string;
}
export type AdjustmentPatch = Partial<Omit<AdjustmentBody, "teacher">>;
export interface MarkPaidBody {
	paid_on: string;
	notes?: string;
}

// Form schemas. Messages are i18n keys, translated by `useFieldError`.
const day = z
	.string()
	.regex(/^\d{4}-\d{2}-\d{2}$/, "payroll.errors.dateRequired");

/** A rate in the teacher's currency: zero is a rate (spec §3.2). */
export const rateFormSchema = (currency: string) =>
	z.object({
		course: z.string(),
		amount: amount(currency, { allowZero: true }),
	});
export type RateFormValues = z.infer<ReturnType<typeof rateFormSchema>>;

/** A bonus or deduction: the amount is checked against the chosen
 * teacher's currency, with billing's one money field. */
export const adjustmentFormSchema = (currencyOf: (teacher: string) => string) =>
	z
		.object({
			teacher: z.string().min(1, "payroll.errors.required"),
			kind: z.enum(ADJUSTMENT_KINDS),
			amount: z.string(),
			effective_on: day,
			reason: z.string().trim().min(1, "payroll.errors.required"),
		})
		.superRefine((data, ctx) => {
			const checked = amount(currencyOf(data.teacher)).safeParse(data.amount);
			if (!checked.success) {
				ctx.addIssue({
					code: "custom",
					path: ["amount"],
					message: checked.error.issues[0]?.message,
				});
			}
		});
export type AdjustmentFormValues = z.infer<
	ReturnType<typeof adjustmentFormSchema>
>;

export const markPaidSchema = z.object({ paid_on: day, notes: z.string() });
export type MarkPaidValues = z.infer<typeof markPaidSchema>;
```

Create `dashboard/src/features/payroll/api.ts`:

```ts
import {
	api,
	clean,
	csvUrl,
	type Paginated,
	type QueryParams,
} from "@/lib/api";
import type {
	Adjustment,
	AdjustmentBody,
	AdjustmentPatch,
	GenerateResult,
	MarkPaidBody,
	Payslip,
	PayslipDetail,
	Rate,
	RateBody,
} from "./schemas";

const P = "payroll/";
const PAYSLIPS = `${P}payslips/`;

export const payrollApi = {
	rates: async (params: QueryParams = {}) =>
		(await api.get<Rate[]>(`${P}rates/`, { params: clean(params) })).data,
	createRate: async (body: RateBody) =>
		(await api.post<Rate>(`${P}rates/`, body)).data,
	updateRate: async ({
		id,
		...body
	}: {
		id: number;
		hourly_rate_minor: number;
	}) => (await api.patch<Rate>(`${P}rates/${id}/`, body)).data,
	deleteRate: async (id: number) => {
		await api.delete(`${P}rates/${id}/`);
	},
	adjustments: async (params: QueryParams) =>
		(
			await api.get<Paginated<Adjustment>>(`${P}adjustments/`, {
				params: clean(params),
			})
		).data,
	createAdjustment: async (body: AdjustmentBody) =>
		(await api.post<Adjustment>(`${P}adjustments/`, body)).data,
	updateAdjustment: async ({ id, ...body }: AdjustmentPatch & { id: number }) =>
		(await api.patch<Adjustment>(`${P}adjustments/${id}/`, body)).data,
	deleteAdjustment: async (id: number) => {
		await api.delete(`${P}adjustments/${id}/`);
	},
	payslips: async (params: QueryParams) =>
		(await api.get<Paginated<Payslip>>(PAYSLIPS, { params: clean(params) }))
			.data,
	payslip: async (id: number) =>
		(await api.get<PayslipDetail>(`${PAYSLIPS}${id}/`)).data,
	generate: async (body: { year: number; month: number }) =>
		(await api.post<GenerateResult>(`${PAYSLIPS}generate/`, body)).data,
	issue: async (id: number) =>
		(await api.post<PayslipDetail>(`${PAYSLIPS}${id}/issue/`)).data,
	markPaid: async ({ id, ...body }: MarkPaidBody & { id: number }) =>
		(await api.post<PayslipDetail>(`${PAYSLIPS}${id}/mark-paid/`, body)).data,
};

/** The payslip list's CSV export, with the list's filters (admins only). */
export function payslipsCsvUrl(params: QueryParams): string {
	return csvUrl(PAYSLIPS, params);
}
```

Create `dashboard/src/features/payroll/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { schedulingKey } from "@/features/scheduling/queries";
import type { QueryParams } from "@/lib/api";
import { payrollApi } from "./api";

/** Every payroll query lives under this key. */
export const payrollKey = ["payroll"] as const;

export function useRates() {
	return useQuery({
		queryKey: [...payrollKey, "rates"],
		queryFn: () => payrollApi.rates(),
	});
}

export function useAdjustments(params: QueryParams) {
	return useQuery({
		queryKey: [...payrollKey, "adjustments", params],
		queryFn: () => payrollApi.adjustments(params),
		placeholderData: keepPreviousData,
	});
}

export function usePayslips(
	params: QueryParams,
	{ enabled = true }: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...payrollKey, "payslips", params],
		queryFn: () => payrollApi.payslips(params),
		placeholderData: keepPreviousData,
		enabled,
	});
}

export function usePayslip(id: number | undefined) {
	return useQuery({
		queryKey: [...payrollKey, "payslip", id],
		queryFn: () => payrollApi.payslip(id as number),
		enabled: id !== undefined,
	});
}

/** A payroll write. On success it refreshes payroll and scheduling: issuing
 * locks sessions, whose pages then show "Paid in payslip" (spec §6). */
export function usePayrollMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () =>
			Promise.all([
				qc.invalidateQueries({ queryKey: payrollKey }),
				qc.invalidateQueries({ queryKey: schedulingKey }),
			]),
	});
}
```

Create `dashboard/src/features/payroll/bits.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { StatusChip } from "@/ui";
import type { Payslip, PayslipStatus } from "./schemas";

const TONE: Record<PayslipStatus, "live" | "neutral"> = {
	draft: "neutral",
	issued: "neutral",
	paid: "live",
};

/** The payslip's status, and "Missing rate" beside a draft that has one
 * (spec §6). */
export function PayslipStatusChip({
	payslip,
}: {
	payslip: Pick<Payslip, "status" | "missing_rate">;
}) {
	const { t } = useTranslation();
	return (
		<span className="inline-flex flex-wrap items-center gap-1">
			<StatusChip tone={TONE[payslip.status]}>
				{t(`payroll.status.${payslip.status}`)}
			</StatusChip>
			{payslip.status === "draft" && payslip.missing_rate ? (
				<StatusChip tone="warning">{t("payroll.missingRate")}</StatusChip>
			) : null}
		</span>
	);
}

/** Minutes as hours in the reader's language, e.g. "1.5". */
export function hours(minutes: number, language: string): string {
	return new Intl.NumberFormat(language, { maximumFractionDigits: 2 }).format(
		minutes / 60,
	);
}
```

Create `dashboard/src/features/payroll/index.ts`:

```ts
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, PayslipStatusChip } from "./bits";
export * from "./queries";
export * from "./schemas";
```

In `dashboard/src/features/scheduling/schemas.ts`, replace:

```ts
	// Admins and the session's own teacher only.
	has_report?: boolean;
}

```

with:

```ts
	// Admins and the session's own teacher only.
	has_report?: boolean;
	// Plan 7: an issued payslip pays it, so nothing about it changes.
	payroll_locked?: boolean;
}

```

In `dashboard/src/features/scheduling/AttendanceControls.tsx` (1 of 3), replace:

```tsx

/** The student's and the teacher's attendance for one session (spec §4.1).
 * Closed until the server says the session has started, and on a cancelled
 * session. Only an admin (`canClear`) may set one back to "Not set". */
export function AttendanceControls({
	session,
```

with:

```tsx

/** The student's and the teacher's attendance for one session (spec §4.1).
 * Closed until the server says the session has started, on a cancelled
 * session, and for good once an issued payslip pays it (Plan 7 spec §6).
 * Only an admin (`canClear`) may set one back to "Not set". */
export function AttendanceControls({
	session,
```

In `dashboard/src/features/scheduling/AttendanceControls.tsx` (2 of 3), replace:

```tsx
	const { t } = useTranslation();
	const mark = useSchedulingMutation(schedulingApi.markAttendance);
	const closed =
		!session.has_started || session.status === "cancelled" || mark.isPending;
	const name = session.student.full_name;

```

with:

```tsx
	const { t } = useTranslation();
	const mark = useSchedulingMutation(schedulingApi.markAttendance);
	const paid = session.payroll_locked === true;
	const closed =
		!session.has_started ||
		session.status === "cancelled" ||
		paid ||
		mark.isPending;
	const name = session.student.full_name;

```

In `dashboard/src/features/scheduling/AttendanceControls.tsx` (3 of 3), replace:

```tsx
				)}
			</div>
			{!session.has_started && session.status !== "cancelled" ? (
				<p className="text-xs text-muted-foreground">
```

with:

```tsx
				)}
			</div>
			{paid ? (
				<p className="text-xs text-muted-foreground">
					{t("scheduling.attendance.paid")}
				</p>
			) : null}
			{!session.has_started && session.status !== "cancelled" ? (
				<p className="text-xs text-muted-foreground">
```

In `dashboard/src/features/scheduling/SessionPage.tsx`, replace:

```tsx
				<CardContent className="flex flex-col gap-4">
					<AttendanceControls session={session} canClear />
					<div className="flex flex-wrap gap-2">
						{session.status === "cancelled" ? (
							<Button
								size="sm"
```

with:

```tsx
				<CardContent className="flex flex-col gap-4">
					<AttendanceControls session={session} canClear />
					{/* A session an issued payslip pays is never cancelled or
					    restored (Plan 7 spec §4.5); the note is above. */}
					<div className="flex flex-wrap gap-2">
						{session.payroll_locked ? null : session.status === "cancelled" ? (
							<Button
								size="sm"
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"errors": {
		"payroll": {
			"not_allowed_in_status": "That isn't possible in the payslip's current status.",
			"month_not_over": "This month hasn't ended yet. Issue the payslip once it has.",
			"missing_rate": "A session has no rate. Set the teacher's rates first.",
			"negative_net": "The deductions are more than the pay.",
			"adjustment_used": "This adjustment is on an issued payslip, so it can't change.",
			"payslip_issued": "This session is on an issued payslip, so it can't change."
		}
	},
	"scheduling": { "attendance": { "paid": "Paid in payslip" } },
	"billing": {
		"errors": {
			"amountOrZero": "Enter an amount of zero or more, like 150 or 150.50."
		}
	},
	"payroll": {
		"status": { "draft": "Draft", "issued": "Issued", "paid": "Paid" },
		"missingRate": "Missing rate",
		"kinds": { "bonus": "Bonus", "deduction": "Deduction" },
		"errors": { "required": "Fill this in.", "dateRequired": "Choose a date." }
	}
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"errors": {
		"payroll": {
			"not_allowed_in_status": "هذا غير ممكن في حالة كشف الراتب الحالية.",
			"month_not_over": "لم ينتهِ هذا الشهر بعد. أصدِر كشف الراتب بعد انتهائه.",
			"missing_rate": "إحدى الحصص بلا سعر. حدّد أسعار المعلم أولًا.",
			"negative_net": "الخصومات أكبر من الأجر.",
			"adjustment_used": "هذه التسوية مدرجة في كشف راتب صادر، فلا يمكن تغييرها.",
			"payslip_issued": "هذه الحصة مدرجة في كشف راتب صادر، فلا يمكن تغييرها."
		}
	},
	"scheduling": { "attendance": { "paid": "مدفوعة في كشف راتب" } },
	"billing": {
		"errors": {
			"amountOrZero": "أدخل مبلغًا يساوي صفرًا أو أكثر، مثل 150 أو 150.50."
		}
	},
	"payroll": {
		"status": { "draft": "مسودة", "issued": "صادر", "paid": "مدفوع" },
		"missingRate": "سعر ناقص",
		"kinds": { "bonus": "مكافأة", "deduction": "خصم" },
		"errors": { "required": "املأ هذا الحقل.", "dateRequired": "اختر تاريخًا." }
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll src/lib src/features/billing src/features/scheduling
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes, and coverage clears the gates (lines and statements 80, branches and functions 70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): dashboard data layer, month helpers and locked sessions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard: the payslip print page on the shared print sheet

**Files:**
- Create: `dashboard/src/features/branding/PrintSheet.tsx`, `dashboard/src/features/payroll/PayslipBody.tsx`, `dashboard/src/features/payroll/PayslipPrint.tsx`, `dashboard/src/routes/_print/payslips.$payslipId.print.tsx`
- Modify: `dashboard/src/features/branding/index.ts`, `dashboard/src/index.css`, `dashboard/src/features/billing/InvoicePrint.tsx`, `dashboard/src/features/payroll/index.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/payroll/PayslipPrint.test.tsx` (new), `dashboard/src/routes/_print.test.tsx`
- Generated: `dashboard/src/routeTree.gen.ts` (by `vite build`, when a task adds a route)

**Interfaces:**
- Consumes: Task 9's `usePayslip`, `PayslipDetail`; billing's `Money`; branding's `useBranding`, `useBrandName`; `Fact`; `formatDay`, `formatMonth`.
- Produces (`@/features/branding`): `PrintPage({children})` (reader's direction, light palette while open) and `PrintSheet({title, number, status, children})` (Print button off the paper, the academy's logo and name, the title, number and status, then the document). `InvoicePrint` now renders through them.
- Produces (`@/features/payroll`): `PayslipBody({payslip})` (sessions table, bonuses and deductions, totals) and `PayslipPrint({payslipId})`; the route `/_print/payslips/$payslipId/print`.

- [ ] **Step 1: Write the failing tests**

The payslip prints with its lines and totals, in Arabic right to left, with not-found, bad-id and load-error states; the print route shows a teacher their own payslip without the app shell and a 404 for another's. `InvoicePrint.test.tsx` runs unchanged against the shared sheet.

Create `dashboard/src/features/payroll/PayslipPrint.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { brandingApi } from "@/features/branding/api";
import i18n from "@/lib/i18n";
import { academyBranding } from "@/test/billing-fixtures";
import { payslipDetail, teacherPayslip } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { payrollApi } from "./api";
import { PayslipPrint } from "./PayslipPrint";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, payrollApi: { ...actual.payrollApi, payslip: vi.fn() } };
});
vi.mock("@/features/branding/api", () => ({ brandingApi: { get: vi.fn() } }));

function notFound() {
	return new AxiosError("Not Found", "404", undefined, undefined, {
		status: 404,
	} as never);
}

describe("PayslipPrint", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(brandingApi.get).mockResolvedValue(
			academyBranding({ logo_url: "/media/logo.png" }),
		);
		vi.mocked(payrollApi.payslip).mockResolvedValue(teacherPayslip());
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("prints the academy's payslip with its lines and totals", async () => {
		const print = vi.spyOn(window, "print").mockImplementation(() => {});
		const user = userEvent.setup();
		renderWithRouter(<PayslipPrint payslipId="71" />);
		const sheet = await screen.findByRole("article", { name: "Payslip" });
		expect(payrollApi.payslip).toHaveBeenCalledWith(71);
		expect(within(sheet).getByText("PAY-000071")).toBeInTheDocument();
		expect(within(sheet).getByText("Issued")).toBeInTheDocument();
		expect(
			await within(sheet).findByRole("img", { name: "Demo Academy" }),
		).toHaveAttribute("src", "/media/logo.png");
		expect(within(sheet).getByText("Bilal")).toBeInTheDocument();
		expect(within(sheet).getByText("June 2026")).toBeInTheDocument();
		const rows = within(sheet).getAllByRole("row");
		// A header and the two sessions.
		expect(rows).toHaveLength(3);
		expect(rows[1]?.textContent).toMatch(
			/2026-06-01 — Tajweed — Yusuf45\$10\.00\$7\.50/,
		);
		expect(within(sheet).getByText("Deduction — Late")).toBeInTheDocument();
		const net = within(sheet).getByText("Net").nextElementSibling;
		expect(net?.textContent).toBe("$18.00");
		await user.click(screen.getByRole("button", { name: "Print" }));
		expect(print).toHaveBeenCalledOnce();
	});

	it("shows the date it was paid", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "paid", paid_on: "2026-07-02" }),
		);
		renderWithRouter(<PayslipPrint payslipId="71" />);
		const sheet = await screen.findByRole("article", { name: "Payslip" });
		expect(within(sheet).getByText("Jul 2, 2026")).toBeInTheDocument();
		expect(
			within(sheet).getByText("Paid", { selector: "header p" }),
		).toBeInTheDocument();
	});

	it("reads right to left in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<PayslipPrint payslipId="71" />);
		const sheet = await screen.findByRole("article", { name: "كشف راتب" });
		expect(screen.getByRole("main")).toHaveAttribute("dir", "rtl");
		expect(within(sheet).getByText("صادر")).toBeInTheDocument();
		expect(within(sheet).getByText("الصافي")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "طباعة" })).toBeInTheDocument();
	});

	it("says so for a missing payslip, a bad id or a failed load", async () => {
		vi.mocked(payrollApi.payslip).mockRejectedValueOnce(notFound());
		const { unmount } = renderWithRouter(<PayslipPrint payslipId="99" />);
		expect(
			await screen.findByText("This payslip couldn't be found."),
		).toBeInTheDocument();
		unmount();
		const second = renderWithRouter(<PayslipPrint payslipId="abc" />);
		expect(
			await screen.findByText("This payslip couldn't be found."),
		).toBeInTheDocument();
		expect(payrollApi.payslip).toHaveBeenCalledTimes(1);
		second.unmount();
		vi.mocked(payrollApi.payslip).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<PayslipPrint payslipId="71" />);
		expect(
			await screen.findByText("Couldn't load this payslip."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/routes/_print.test.tsx` (1 of 7), replace:

```tsx
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
```

with:

```tsx
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
```

In `dashboard/src/routes/_print.test.tsx` (2 of 7), replace:

```tsx
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { academyBranding, familyInvoice } from "@/test/billing-fixtures";
import { page } from "@/test/scheduling-fixtures";
import { routeTree } from "../routeTree.gen";
```

with:

```tsx
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { payrollApi } from "@/features/payroll/api";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { academyBranding, familyInvoice } from "@/test/billing-fixtures";
import { teacherPayslip } from "@/test/payroll-fixtures";
import { page } from "@/test/scheduling-fixtures";
import { routeTree } from "../routeTree.gen";
```

In `dashboard/src/routes/_print.test.tsx` (3 of 7), replace:

```tsx
});
vi.mock("@/features/branding/api", () => ({ brandingApi: { get: vi.fn() } }));
vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
```

with:

```tsx
});
vi.mock("@/features/branding/api", () => ({ brandingApi: { get: vi.fn() } }));
vi.mock("@/features/payroll/api", async (orig) => {
	const actual = await orig<typeof import("@/features/payroll/api")>();
	return { ...actual, payrollApi: { ...actual.payrollApi, payslip: vi.fn() } };
});
vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
```

In `dashboard/src/routes/_print.test.tsx` (4 of 7), replace:

```tsx

function renderAt(path: string) {
	const queryClient = new QueryClient({
		defaultOptions: { queries: { retry: false } },
```

with:

```tsx

function renderAt(path: string) {
	return renderAtWithUnmount(path).router;
}

function renderAtWithUnmount(path: string) {
	const queryClient = new QueryClient({
		defaultOptions: { queries: { retry: false } },
```

In `dashboard/src/routes/_print.test.tsx` (5 of 7), replace:

```tsx
		history: createMemoryHistory({ initialEntries: [path] }),
	});
	render(
		<ThemeProvider>
			<QueryClientProvider client={queryClient}>
```

with:

```tsx
		history: createMemoryHistory({ initialEntries: [path] }),
	});
	const view = render(
		<ThemeProvider>
			<QueryClientProvider client={queryClient}>
```

In `dashboard/src/routes/_print.test.tsx` (6 of 7), replace:

```tsx
		</ThemeProvider>,
	);
	return router;
}

```

with:

```tsx
		</ThemeProvider>,
	);
	return { router, unmount: view.unmount };
}

```

In `dashboard/src/routes/_print.test.tsx` (7 of 7), replace:

```tsx
	});

	it("keeps the app shell on the app's own pages", async () => {
		renderAt("/");
```

with:

```tsx
	});

	it("prints a teacher's own payslip, and not another teacher's", async () => {
		vi.mocked(identityApi.me).mockResolvedValue({
			...parent,
			role: "teacher",
			profiles: ["teacher"],
			children: [],
		});
		vi.mocked(payrollApi.payslip).mockResolvedValueOnce(teacherPayslip());
		const { unmount } = renderAtWithUnmount("/payslips/71/print");
		expect(
			await screen.findByRole("article", { name: "Payslip" }),
		).toBeInTheDocument();
		expect(payrollApi.payslip).toHaveBeenCalledWith(71);
		expect(
			screen.queryByRole("navigation", { name: "Main navigation" }),
		).toBeNull();
		unmount();
		// The server scopes the payslip: another teacher's is a 404.
		vi.mocked(payrollApi.payslip).mockRejectedValueOnce(
			new AxiosError("Not Found", "404", undefined, undefined, {
				status: 404,
			} as never),
		);
		renderAt("/payslips/72/print");
		expect(
			await screen.findByText("This payslip couldn't be found."),
		).toBeInTheDocument();
	});

	it("keeps the app shell on the app's own pages", async () => {
		renderAt("/");
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll/PayslipPrint.test.tsx src/routes/_print.test.tsx`

Expected: FAIL — `Failed to resolve import "./PayslipPrint"`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/branding/PrintSheet.tsx`:

```tsx
import { type ReactNode, useEffect, useId } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "@/ui";
import { useBranding, useBrandName } from "./queries";

/** Paper is white: while a print page is open it renders on the light
 * palette, whatever theme the reader chose, and gives it back after. The
 * stored preference is untouched. */
function useLightPaper() {
	useEffect(() => {
		const root = document.documentElement;
		const wasDark = root.classList.contains("dark");
		root.classList.remove("dark");
		return () => {
			if (wasDark) root.classList.add("dark");
		};
	}, []);
}

/** A page printed on paper (Plan 6 P6-5; Plan 7's payslips): the reader's
 * language and direction, on the light palette, for A4. */
export function PrintPage({ children }: { children: ReactNode }) {
	const { i18n } = useTranslation();
	useLightPaper();
	return (
		<main
			dir={i18n.dir()}
			className="mx-auto flex max-w-3xl flex-col gap-4 p-4 sm:p-6 print:max-w-none print:p-0"
		>
			{children}
		</main>
	);
}

/** The academy-branded sheet: a Print button (left off the paper), then the
 * academy's logo and name beside the document's title, number and status,
 * then the document itself. */
export function PrintSheet({
	title,
	number,
	status,
	children,
}: {
	title: string;
	number: string;
	status: string;
	children: ReactNode;
}) {
	const { t } = useTranslation();
	const { data: brand } = useBranding();
	const academy = useBrandName();
	const titleId = useId();
	return (
		<>
			<div className="flex justify-end print:hidden">
				<Button onClick={() => window.print()}>{t("common.print")}</Button>
			</div>
			<article
				aria-labelledby={titleId}
				className="print-sheet flex flex-col gap-6 rounded-lg border border-border bg-card p-6 text-card-foreground sm:p-8"
			>
				<header className="flex flex-wrap items-start justify-between gap-4 border-b border-border pb-4">
					<div className="flex items-center gap-3">
						{brand?.logo_url ? (
							<img src={brand.logo_url} alt={academy} className="h-12 w-auto" />
						) : null}
						<p className="text-lg font-semibold">{academy}</p>
					</div>
					<div className="flex flex-col gap-1 text-end">
						<h1 id={titleId} className="text-2xl font-semibold">
							{title}
						</h1>
						<p dir="ltr" className="font-medium">
							{number}
						</p>
						<p className="text-sm">{status}</p>
					</div>
				</header>
				{children}
			</article>
		</>
	);
}
```

In `dashboard/src/features/branding/index.ts`, replace:

```ts
export { applyBranding } from "./apply";
export { BrandProvider, BrandWordmark, usePageTitle } from "./BrandProvider";
export { brandingQueryKey, useBranding, useBrandName } from "./queries";
```

with:

```ts
export { applyBranding } from "./apply";
export { BrandProvider, BrandWordmark, usePageTitle } from "./BrandProvider";
export { PrintPage, PrintSheet } from "./PrintSheet";
export { brandingQueryKey, useBranding, useBrandName } from "./queries";
```

In `dashboard/src/index.css` (1 of 2), replace:

```css
}

/* The printed invoice (Plan 6, spec §6): A4 paper, and the sheet drops its
   on-screen frame. Controls marked `print:hidden` stay on the screen. The
   print page switches to the light palette while it is open, so the tokens
   below are the light ones. */
@media print {
	@page {
```

with:

```css
}

/* Printed invoices and payslips (Plans 6 and 7, `PrintSheet`): A4 paper,
   and the sheet drops its on-screen frame. Controls marked `print:hidden`
   stay on the screen. The print page switches to the light palette while it
   is open, so the tokens below are the light ones. */
@media print {
	@page {
```

In `dashboard/src/index.css` (2 of 2), replace:

```css
		background-color: var(--color-card);
	}
	.invoice-sheet {
		border-color: transparent;
		padding: 0;
```

with:

```css
		background-color: var(--color-card);
	}
	.print-sheet {
		border-color: transparent;
		padding: 0;
```

Replace the whole of `dashboard/src/features/billing/InvoicePrint.tsx` with:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { PrintPage, PrintSheet } from "@/features/branding";
import { formatDay } from "@/lib/zoned-time";
import { Alert, AlertDescription, Spinner } from "@/ui";
import { Money } from "./bits";
import { useInvoice } from "./queries";

/** Spec §6 print page (P6-5): the academy's logo and name, the invoice or
 * receipt, its payments and the balance due, in the reader's language and
 * direction, for A4 (`PrintPage`, `PrintSheet`). Whoever may read the
 * invoice may print it: the server already scopes `billing/invoices/<id>/`.
 *
 * A void invoice titles the sheet "Void" and drops the balance line
 * (controller ruling): a cancelled invoice owes nothing, and showing a
 * balance would suggest otherwise. A paid one titles it "Receipt". Anything
 * else is an invoice with its balance due. */
export function InvoicePrint({ invoiceId }: { invoiceId: string }) {
	const { t, i18n } = useTranslation();
	const parsed = Number(invoiceId);
	// `/invoices/abc/print` is never an invoice: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: invoice,
		isError,
		error,
	} = useInvoice(invalidId ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	const day = (value: string) => formatDay(value, i18n.language);

	let body: ReactNode;
	if (invalidId || status === 404 || isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("billing.invoice.notFound")
						: t("billing.invoice.loadError")}
				</AlertDescription>
			</Alert>
		);
	} else if (!invoice) {
		body = <Spinner />;
	} else {
		const isReceipt = invoice.status === "paid";
		const isVoid = invoice.status === "void";
		const title = isVoid
			? t("billing.print.void")
			: isReceipt
				? t("billing.print.receipt")
				: t("billing.print.invoice");
		body = (
			<PrintSheet
				title={title}
				number={invoice.number}
				status={t(`billing.status.${invoice.status}`)}
			>
				<dl className="grid gap-4 sm:grid-cols-2">
					<Fact label={t("billing.columns.payer")}>
						{invoice.payer.full_name}
					</Fact>
					<Fact label={t("billing.columns.student")}>
						{invoice.student.full_name}
					</Fact>
					<Fact label={t("billing.columns.issued")}>
						{day(invoice.issued_on)}
					</Fact>
					<Fact label={t("billing.columns.due")}>{day(invoice.due_on)}</Fact>
				</dl>
				<table className="w-full text-sm">
					<thead className="border-b border-border text-muted-foreground">
						<tr>
							<th scope="col" className="py-2 text-start font-medium">
								{t("billing.columns.description")}
							</th>
							<th scope="col" className="py-2 text-end font-medium">
								{t("billing.columns.amount")}
							</th>
						</tr>
					</thead>
					<tbody>
						<tr>
							<td className="py-2">{invoice.description}</td>
							<td className="py-2 text-end">
								<Money
									minor={invoice.amount_minor}
									currency={invoice.currency}
								/>
							</td>
						</tr>
					</tbody>
				</table>
				<section className="flex flex-col gap-2">
					<h2 className="font-semibold">{t("billing.payments.title")}</h2>
					{invoice.payments.length === 0 ? (
						<p className="text-sm text-muted-foreground">
							{t("billing.payments.none")}
						</p>
					) : (
						<ul className="flex flex-col gap-1 text-sm">
							{invoice.payments.map((payment) => (
								<li
									key={payment.id}
									className="flex flex-wrap justify-between gap-2"
								>
									<span>
										{day(payment.paid_on)} ·{" "}
										{t(`billing.methods.${payment.method}`)}
										{payment.reference ? ` · ${payment.reference}` : ""}
									</span>
									<Money
										minor={payment.amount_minor}
										currency={invoice.currency}
									/>
								</li>
							))}
						</ul>
					)}
				</section>
				<dl className="ms-auto grid w-full max-w-xs grid-cols-2 gap-2 border-t border-border pt-4 text-sm">
					<dt>{t("billing.columns.amount")}</dt>
					<dd className="text-end">
						<Money minor={invoice.amount_minor} currency={invoice.currency} />
					</dd>
					<dt>{t("billing.columns.paid")}</dt>
					<dd className="text-end">
						<Money minor={invoice.paid_minor} currency={invoice.currency} />
					</dd>
					{isVoid ? null : (
						<>
							<dt className="font-semibold">{t("billing.print.balanceDue")}</dt>
							<dd className="text-end font-semibold">
								<Money
									minor={invoice.balance_minor}
									currency={invoice.currency}
								/>
							</dd>
						</>
					)}
				</dl>
			</PrintSheet>
		);
	}
	return <PrintPage>{body}</PrintPage>;
}
```

Create `dashboard/src/features/payroll/PayslipBody.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Money } from "@/features/billing";
import type { PayslipDetail } from "./schemas";

/** A payslip's lines, sessions then bonuses and deductions, and its totals
 * (spec §6). The payslip page and the print sheet show exactly this. */
export function PayslipBody({ payslip }: { payslip: PayslipDetail }) {
	const { t } = useTranslation();
	const sessions = payslip.lines.filter((line) => line.kind === "session");
	const adjustments = payslip.lines.filter(
		(line) => line.kind === "adjustment",
	);
	const money = (minor: number) => (
		<Money minor={minor} currency={payslip.currency} />
	);
	const heading = "py-2 font-medium";
	return (
		<>
			<section className="flex flex-col gap-2">
				<h2 className="font-semibold">{t("payroll.payslip.sessions")}</h2>
				{sessions.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("payroll.payslip.noSessions")}
					</p>
				) : (
					<div className="overflow-x-auto">
						<table className="w-full text-sm">
							<thead className="border-b border-border text-muted-foreground">
								<tr>
									<th scope="col" className={`${heading} text-start`}>
										{t("payroll.columns.description")}
									</th>
									<th scope="col" className={`${heading} text-end`}>
										{t("payroll.columns.minutes")}
									</th>
									<th scope="col" className={`${heading} text-end`}>
										{t("payroll.columns.rate")}
									</th>
									<th scope="col" className={`${heading} text-end`}>
										{t("payroll.columns.amount")}
									</th>
								</tr>
							</thead>
							<tbody>
								{sessions.map((line) => (
									<tr key={line.id} className="border-b border-border">
										<td className="py-2">{line.description}</td>
										<td className="py-2 text-end">{line.minutes}</td>
										<td className="py-2 text-end">
											{line.rate_minor === null
												? t("payroll.payslip.noRate")
												: money(line.rate_minor)}
										</td>
										<td className="py-2 text-end">
											{money(line.amount_minor)}
										</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
				)}
			</section>
			<section className="flex flex-col gap-2">
				<h2 className="font-semibold">{t("payroll.payslip.adjustments")}</h2>
				{adjustments.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("payroll.payslip.noAdjustments")}
					</p>
				) : (
					<ul className="flex flex-col gap-1 text-sm">
						{adjustments.map((line) => (
							<li
								key={line.id}
								className="flex flex-wrap justify-between gap-2"
							>
								<span>{line.description}</span>
								{money(line.amount_minor)}
							</li>
						))}
					</ul>
				)}
			</section>
			<dl className="ms-auto grid w-full max-w-xs grid-cols-2 gap-2 border-t border-border pt-4 text-sm">
				<dt>{t("payroll.columns.gross")}</dt>
				<dd className="text-end">{money(payslip.gross_minor)}</dd>
				<dt>{t("payroll.columns.bonuses")}</dt>
				<dd className="text-end">{money(payslip.bonuses_minor)}</dd>
				<dt>{t("payroll.columns.deductions")}</dt>
				<dd className="text-end">{money(payslip.deductions_minor)}</dd>
				<dt className="font-semibold">{t("payroll.columns.net")}</dt>
				<dd className="text-end font-semibold">{money(payslip.net_minor)}</dd>
			</dl>
		</>
	);
}
```

Create `dashboard/src/features/payroll/PayslipPrint.tsx`:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { PrintPage, PrintSheet } from "@/features/branding";
import { formatDay, formatMonth } from "@/lib/zoned-time";
import { Alert, AlertDescription, Spinner } from "@/ui";
import { PayslipBody } from "./PayslipBody";
import { usePayslip } from "./queries";

/** Spec §6 print page: the invoices' academy-branded A4 sheet, titled
 * "Payslip", in the reader's language and direction. The server scopes
 * `payroll/payslips/<id>/`: a teacher prints their own issued and paid
 * payslips; another teacher's, or a draft, is "couldn't be found". */
export function PayslipPrint({ payslipId }: { payslipId: string }) {
	const { t, i18n } = useTranslation();
	const parsed = Number(payslipId);
	// `/payslips/abc/print` is never a payslip: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: payslip,
		isError,
		error,
	} = usePayslip(invalidId ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;

	let body: ReactNode;
	if (invalidId || status === 404 || isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("payroll.payslip.notFound")
						: t("payroll.payslip.loadError")}
				</AlertDescription>
			</Alert>
		);
	} else if (!payslip) {
		body = <Spinner />;
	} else {
		body = (
			<PrintSheet
				title={t("payroll.payslip.title")}
				number={payslip.number}
				status={t(`payroll.status.${payslip.status}`)}
			>
				<dl className="grid gap-4 sm:grid-cols-2">
					<Fact label={t("payroll.columns.teacher")}>
						{payslip.teacher.full_name}
					</Fact>
					<Fact label={t("payroll.columns.month")}>
						{formatMonth(payslip.year, payslip.month, i18n.language)}
					</Fact>
					{payslip.paid_on ? (
						<Fact label={t("payroll.columns.paidOn")}>
							{formatDay(payslip.paid_on, i18n.language)}
						</Fact>
					) : null}
				</dl>
				<PayslipBody payslip={payslip} />
			</PrintSheet>
		);
	}
	return <PrintPage>{body}</PrintPage>;
}
```

Replace the whole of `dashboard/src/features/payroll/index.ts` with:

```ts
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, PayslipStatusChip } from "./bits";
export { PayslipBody } from "./PayslipBody";
export { PayslipPrint } from "./PayslipPrint";
export * from "./queries";
export * from "./schemas";
```

Create `dashboard/src/routes/_print/payslips.$payslipId.print.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PayslipPrint } from "@/features/payroll";

export const Route = createFileRoute("/_print/payslips/$payslipId/print")({
	component: function PayslipPrintRoute() {
		const { t } = useTranslation();
		const { payslipId } = Route.useParams();
		usePageTitle(t("payroll.payslip.title"));
		return <PayslipPrint payslipId={payslipId} />;
	},
});
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"common": { "print": "Print" },
	"payroll": {
		"columns": {
			"teacher": "Teacher",
			"month": "Month",
			"paidOn": "Paid on",
			"description": "Description",
			"minutes": "Minutes",
			"rate": "Rate / hour",
			"amount": "Amount",
			"gross": "Gross",
			"bonuses": "Bonuses",
			"deductions": "Deductions",
			"net": "Net"
		},
		"payslip": {
			"title": "Payslip",
			"notFound": "This payslip couldn't be found.",
			"loadError": "Couldn't load this payslip.",
			"sessions": "Sessions",
			"adjustments": "Bonuses and deductions",
			"noSessions": "No sessions.",
			"noAdjustments": "No bonuses or deductions.",
			"noRate": "No rate"
		}
	}
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"common": { "print": "طباعة" },
	"payroll": {
		"columns": {
			"teacher": "المعلم",
			"month": "الشهر",
			"paidOn": "تاريخ الدفع",
			"description": "الوصف",
			"minutes": "الدقائق",
			"rate": "السعر / ساعة",
			"amount": "المبلغ",
			"gross": "الإجمالي",
			"bonuses": "المكافآت",
			"deductions": "الخصومات",
			"net": "الصافي"
		},
		"payslip": {
			"title": "كشف راتب",
			"notFound": "تعذّر العثور على كشف الراتب هذا.",
			"loadError": "تعذّر تحميل كشف الراتب هذا.",
			"sessions": "الحصص",
			"adjustments": "المكافآت والخصومات",
			"noSessions": "لا توجد حصص.",
			"noAdjustments": "لا توجد مكافآت أو خصومات.",
			"noRate": "بلا سعر"
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll src/features/billing src/routes
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes, and coverage clears the gates (lines and statements 80, branches and functions 70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): the payslip print page on the shared print sheet

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Dashboard: the payslip page with Issue and Mark paid

**Files:**
- Create: `dashboard/src/features/payroll/MarkPaidDialog.tsx`, `dashboard/src/features/payroll/PayslipPage.tsx`, `dashboard/src/routes/_authed/payroll.tsx`, `dashboard/src/routes/_authed/payroll.payslips.$payslipId.tsx`
- Modify: `dashboard/src/features/payroll/index.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/payroll/PayslipPage.test.tsx` (new)
- Generated: `dashboard/src/routeTree.gen.ts` (by `vite build`, when a task adds a route)

**Interfaces:**
- Consumes: Tasks 9–10; `Confirm`, `Fact`; `useAcademySettings`, `todayIn`; `applyServerErrors`, `errorText`, `useFieldError`.
- Produces: `PayslipPage({payslipId, admin})` (admin: Issue behind a confirmation, Mark paid on an issued one, Print; teacher: read-only with Print), `MarkPaidDialog({payslip})`; the admin layout route `/_authed/payroll` (`requireAdmin`) and `/_authed/payroll/payslips/$payslipId`.

- [ ] **Step 1: Write the failing tests**

Issue asks first, then toasts; a refusal shows its translated code. Mark paid defaults to the academy's today (Tokyo is a day ahead of UTC at the pinned instant), and a server 400 lands on `paid_on`. A teacher sees no buttons and no staff notes.

Create `dashboard/src/features/payroll/PayslipPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import i18n from "@/lib/i18n";
import { payslipDetail, teacherPayslip } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { PayslipPage } from "./PayslipPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			payslip: vi.fn(),
			issue: vi.fn(),
			markPaid: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

function error(status: number, data: object) {
	return new AxiosError("Refused", String(status), undefined, undefined, {
		status,
		data,
	} as never);
}

function renderPage(admin = true, payslipId = "71") {
	return renderWithRouter(<PayslipPage payslipId={payslipId} admin={admin} />, {
		extraPaths: ["/payslips/$payslipId/print"],
	});
}

const actions = () => screen.getByRole("region", { name: "Payslip actions" });

describe("PayslipPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(payrollApi.payslip).mockResolvedValue(payslipDetail());
	});
	afterEach(async () => {
		vi.useRealTimers();
		await i18n.changeLanguage("en");
	});

	it("shows an admin a draft's lines, totals and Issue", async () => {
		renderPage();
		expect(await screen.findByText("PAY-000071")).toBeInTheDocument();
		expect(payrollApi.payslip).toHaveBeenCalledWith(71);
		expect(screen.getByText("June 2026")).toBeInTheDocument();
		expect(screen.getByText("Bank transfer")).toBeInTheDocument();
		// Sessions in a table, then bonuses and deductions, then the totals.
		const table = screen.getByRole("table");
		expect(within(table).getAllByRole("row")).toHaveLength(3);
		expect(screen.getByText("Bonus — Eid")).toBeInTheDocument();
		expect(screen.getByText("Gross").nextElementSibling?.textContent).toBe(
			"$15.00",
		);
		expect(screen.getByText("Deductions").nextElementSibling?.textContent).toBe(
			"$2.00",
		);
		expect(
			within(actions()).getByRole("button", { name: "Issue" }),
		).toBeVisible();
		expect(
			within(actions()).queryByRole("button", { name: "Mark paid" }),
		).toBeNull();
		expect(
			within(actions()).getByRole("link", { name: "Print" }),
		).toHaveAttribute("href", "/payslips/71/print");
	});

	it("issues after confirming", async () => {
		vi.mocked(payrollApi.issue).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		const user = userEvent.setup();
		renderPage();
		await user.click(await screen.findByRole("button", { name: "Issue" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Issue this payslip",
			}),
		);
		await waitFor(() => expect(payrollApi.issue).toHaveBeenCalledWith(71));
		expect(await screen.findByText("Payslip issued.")).toBeInTheDocument();
	});

	it("translates an issue refusal", async () => {
		vi.mocked(payrollApi.issue).mockRejectedValue(
			error(409, {
				detail: "This month hasn't ended yet.",
				code: "payroll.month_not_over",
			}),
		);
		const user = userEvent.setup();
		renderPage();
		await user.click(await screen.findByRole("button", { name: "Issue" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Issue this payslip",
			}),
		);
		expect(
			await screen.findByText(
				"This month hasn't ended yet. Issue the payslip once it has.",
			),
		).toBeInTheDocument();
	});

	it("warns about a missing rate on a draft", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ missing_rate: true }),
		);
		renderPage();
		expect(
			await screen.findByText(/A session has no rate, so this payslip/),
		).toBeInTheDocument();
		expect(screen.getByText("Missing rate")).toBeInTheDocument();
	});

	it("marks an issued payslip paid, dated the academy's today", async () => {
		// 20:00 UTC on 1 July is already 2 July in the academy's Tokyo.
		vi.useFakeTimers({
			now: new Date("2026-07-01T20:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		vi.mocked(payrollApi.markPaid).mockResolvedValue(
			payslipDetail({ status: "paid" }),
		);
		const user = userEvent.setup();
		renderPage();
		expect(
			within(
				await screen.findByRole("region", { name: "Payslip actions" }),
			).queryByRole("button", { name: "Issue" }),
		).toBeNull();
		await user.click(screen.getByRole("button", { name: "Mark paid" }));
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText(/^Paid on/)).toHaveValue("2026-07-02");
		await user.click(within(dialog).getByRole("button", { name: "Mark paid" }));
		await waitFor(() =>
			expect(payrollApi.markPaid).toHaveBeenCalledWith({
				id: 71,
				paid_on: "2026-07-02",
				notes: "Bank transfer",
			}),
		);
		expect(await screen.findByText("Payslip marked paid.")).toBeInTheDocument();
	});

	it("shows the server's refusal of a future date on the field", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		vi.mocked(payrollApi.markPaid).mockRejectedValue(
			error(400, { paid_on: ["A payslip can't be paid in the future."] }),
		);
		const user = userEvent.setup();
		renderPage();
		await user.click(await screen.findByRole("button", { name: "Mark paid" }));
		const dialog = screen.getByRole("dialog");
		await user.click(within(dialog).getByRole("button", { name: "Mark paid" }));
		expect(
			await within(dialog).findByText("A payslip can't be paid in the future."),
		).toBeInTheDocument();
	});

	it("is read-only for the teacher, who can still print", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(teacherPayslip());
		renderPage(false);
		expect(await screen.findByText("PAY-000071")).toBeInTheDocument();
		expect(
			within(actions()).getByRole("link", { name: "Print" }),
		).toBeVisible();
		expect(within(actions()).queryAllByRole("button")).toHaveLength(0);
		expect(screen.queryByText("Bank transfer")).toBeNull();
	});

	it("shows a paid payslip's date and nothing left to do", async () => {
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "paid", paid_on: "2026-07-02" }),
		);
		renderPage();
		expect(await screen.findByText("Jul 2, 2026")).toBeInTheDocument();
		expect(within(actions()).queryAllByRole("button")).toHaveLength(0);
	});

	it("reads in Arabic, its Mark paid dialog too", async () => {
		await i18n.changeLanguage("ar");
		vi.mocked(payrollApi.payslip).mockResolvedValue(
			payslipDetail({ status: "issued" }),
		);
		const user = userEvent.setup();
		renderPage();
		expect(await screen.findByText("يونيو 2026")).toBeInTheDocument();
		expect(screen.getByText("المكافآت والخصومات")).toBeInTheDocument();
		expect(screen.getByText("الصافي")).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "تسجيل الدفع" }));
		expect(
			within(screen.getByRole("dialog")).getByLabelText(/^تاريخ الدفع/),
		).toBeInTheDocument();
	});

	it("says so for a missing payslip, a bad id or a failed load", async () => {
		vi.mocked(payrollApi.payslip).mockRejectedValueOnce(error(404, {}));
		const { unmount } = renderPage(true, "99");
		expect(
			await screen.findByText("This payslip couldn't be found."),
		).toBeInTheDocument();
		unmount();
		const second = renderPage(true, "abc");
		expect(
			await screen.findByText("This payslip couldn't be found."),
		).toBeInTheDocument();
		expect(payrollApi.payslip).toHaveBeenCalledTimes(1);
		second.unmount();
		vi.mocked(payrollApi.payslip).mockRejectedValueOnce(new Error("offline"));
		renderPage();
		expect(
			await screen.findByText("Couldn't load this payslip."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll/PayslipPage.test.tsx`

Expected: FAIL — `Failed to resolve import "./PayslipPage"`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/payroll/MarkPaidDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
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
import { type MarkPaidValues, markPaidSchema, type Payslip } from "./schemas";

/** Spec §4.4 "Mark paid": the date defaults to the academy's today; a date
 * after it is refused by the server (400 on `paid_on`). */
export function MarkPaidDialog({ payslip }: { payslip: Payslip }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const markPaid = usePayrollMutation(payrollApi.markPaid);
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<MarkPaidValues>({
		resolver: zodResolver(markPaidSchema),
		values: {
			paid_on: academy ? todayIn(academy.timezone) : "",
			notes: payslip.notes ?? "",
		},
	});

	async function onSubmit(values: MarkPaidValues) {
		try {
			await markPaid.mutateAsync({ id: payslip.id, ...values });
			setOpen(false);
			toast({ description: t("payroll.paid.done"), variant: "success" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{t("payroll.paid.action")}</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("payroll.paid.action")}</DialogTitle>
				<DialogDescription>{t("payroll.paid.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="paid-paid_on"
						label={t("payroll.columns.paidOn")}
						error={fieldError(errors.paid_on?.message)}
						required
					>
						<Input type="date" dir="ltr" {...register("paid_on")} />
					</Field>
					<Field
						id="paid-notes"
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
							{t("payroll.paid.action")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/payroll/PayslipPage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Fact } from "@/components/Fact";
import { errorText } from "@/lib/form-errors";
import { formatDay, formatMonth } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { PayslipStatusChip } from "./bits";
import { MarkPaidDialog } from "./MarkPaidDialog";
import { PayslipBody } from "./PayslipBody";
import { usePayrollMutation, usePayslip } from "./queries";
import type { PayslipDetail } from "./schemas";

function Actions({
	payslip,
	admin,
}: {
	payslip: PayslipDetail;
	admin: boolean;
}) {
	const { t } = useTranslation();
	const issue = usePayrollMutation(payrollApi.issue);
	return (
		<section
			aria-label={t("payroll.payslip.actions")}
			className="flex flex-wrap items-center gap-2"
		>
			{admin && payslip.status === "draft" ? (
				<Confirm
					action={t("payroll.issue.action")}
					title={t("payroll.issue.title")}
					body={t("payroll.issue.body")}
					onConfirm={() =>
						issue.mutate(payslip.id, {
							onSuccess: () =>
								toast({
									description: t("payroll.issue.done"),
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
			{admin && payslip.status === "issued" ? (
				<MarkPaidDialog payslip={payslip} />
			) : null}
			<Button asChild size="sm" variant="outline">
				<Link
					to="/payslips/$payslipId/print"
					params={{ payslipId: String(payslip.id) }}
				>
					{t("common.print")}
				</Link>
			</Button>
		</section>
	);
}

/** Spec §6 payslip page. Admins issue a draft (its refusals translated),
 * mark an issued one paid and print; a teacher reads their own issued or
 * paid payslip and prints it (``admin`` false). */
export function PayslipPage({
	payslipId,
	admin,
}: {
	payslipId: string;
	admin: boolean;
}) {
	const { t, i18n } = useTranslation();
	const parsed = Number(payslipId);
	// `/payroll/payslips/abc` is never a payslip: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: payslip,
		isError,
		error,
	} = usePayslip(invalidId ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	if (invalidId || status === 404 || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("payroll.payslip.notFound")
						: t("payroll.payslip.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!payslip) return <Spinner />;
	return (
		<div className="flex flex-col gap-6">
			<Actions payslip={payslip} admin={admin} />
			{admin && payslip.status === "draft" && payslip.missing_rate ? (
				<Alert variant="destructive">
					<AlertDescription>
						{t("payroll.payslip.missingRate")}
					</AlertDescription>
				</Alert>
			) : null}
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle dir="ltr">{payslip.number}</CardTitle>
					<PayslipStatusChip payslip={payslip} />
				</CardHeader>
				<CardContent className="flex flex-col gap-6">
					<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
						<Fact label={t("payroll.columns.teacher")}>
							{payslip.teacher.full_name}
						</Fact>
						<Fact label={t("payroll.columns.month")}>
							{formatMonth(payslip.year, payslip.month, i18n.language)}
						</Fact>
						<Fact label={t("payroll.columns.currency")}>
							<span dir="ltr">{payslip.currency}</span>
						</Fact>
						{payslip.paid_on ? (
							<Fact label={t("payroll.columns.paidOn")}>
								{formatDay(payslip.paid_on, i18n.language)}
							</Fact>
						) : null}
					</dl>
					{payslip.notes ? (
						<p className="text-sm text-muted-foreground">{payslip.notes}</p>
					) : null}
					<PayslipBody payslip={payslip} />
				</CardContent>
			</Card>
		</div>
	);
}
```

Replace the whole of `dashboard/src/features/payroll/index.ts` with:

```ts
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, PayslipStatusChip } from "./bits";
export { PayslipBody } from "./PayslipBody";
export { PayslipPage } from "./PayslipPage";
export { PayslipPrint } from "./PayslipPrint";
export * from "./queries";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/payroll.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireAdmin } from "@/features/identity/require-admin";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/payroll")({
	beforeLoad: ({ context }) => requireAdmin(context),
	component: () => (
		<PageContainer>
			<Outlet />
		</PageContainer>
	),
});
```

Create `dashboard/src/routes/_authed/payroll.payslips.$payslipId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PayslipPage } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/payroll/payslips/$payslipId")({
	component: function PayslipRoute() {
		const { t } = useTranslation();
		const { payslipId } = Route.useParams();
		usePageTitle(t("payroll.payslip.title"));
		return (
			<>
				<PageHeader title={t("payroll.payslip.title")} />
				<PayslipPage payslipId={payslipId} admin />
			</>
		);
	},
});
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"payroll": {
		"columns": { "currency": "Currency" },
		"payslip": {
			"actions": "Payslip actions",
			"missingRate": "A session has no rate, so this payslip can't be issued. Set the teacher's rates, then generate the month again."
		},
		"issue": {
			"action": "Issue",
			"title": "Issue this payslip",
			"body": "Issuing rebuilds the payslip from the latest attendance, freezes it and locks its sessions. It can't be undone.",
			"done": "Payslip issued."
		},
		"paid": {
			"action": "Mark paid",
			"body": "Record the date the teacher was paid.",
			"done": "Payslip marked paid."
		}
	}
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"payroll": {
		"columns": { "currency": "العملة" },
		"payslip": {
			"actions": "إجراءات كشف الراتب",
			"missingRate": "إحدى الحصص بلا سعر، فلا يمكن إصدار كشف الراتب هذا. حدّد أسعار المعلم ثم أعِد إنشاء الشهر."
		},
		"issue": {
			"action": "إصدار",
			"title": "إصدار كشف الراتب هذا",
			"body": "يُعاد بناء كشف الراتب من آخر حضور، ثم يُجمَّد وتُقفل حصصه. لا يمكن التراجع عن ذلك.",
			"done": "صدر كشف الراتب."
		},
		"paid": {
			"action": "تسجيل الدفع",
			"body": "سجّل تاريخ دفع راتب المعلم.",
			"done": "سُجّل دفع كشف الراتب."
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes, and coverage clears the gates (lines and statements 80, branches and functions 70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): the payslip page with issue and mark paid

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Dashboard: the Rates page

**Files:**
- Create: `dashboard/src/features/payroll/RateDialog.tsx`, `dashboard/src/features/payroll/RatesPage.tsx`, `dashboard/src/routes/_authed/payroll.rates.tsx`
- Modify: `dashboard/src/features/payroll/index.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/payroll/RatesPage.test.tsx` (new)
- Generated: `dashboard/src/routeTree.gen.ts` (by `vite build`, when a task adds a route)

**Interfaces:**
- Consumes: Task 9's `useRates`, `payrollApi.createRate/updateRate/deleteRate`, `rateFormSchema`; `usePeople<TeacherProfile>("teachers", {page_size: 100})`; `useCatalogue<Course>("courses", {page_size: 100})`; scheduling's `useLocalName`; billing's `Money`.
- Produces: `RatesPage()` and `RateDialog({teacher, rates, courses, rate?})`; the route `/_authed/payroll/rates`.

- [ ] **Step 1: Write the failing tests**

Each teacher's card lists the default and course rates in the rate's currency, warns when no current default exists, and marks a rate in an old currency. Add offers only the default or courses without a rate (and disappears when none is left), converts the amount in the teacher's currency (EGP here), takes zero, refuses too many decimals, and shows a duplicate refusal on the course.

Create `dashboard/src/features/payroll/RatesPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { rateRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { RatesPage } from "./RatesPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			rates: vi.fn(),
			createRate: vi.fn(),
			updateRate: vi.fn(),
			deleteRate: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

const teacher = (id: number, full_name: string, pay_currency = "USD") => ({
	id,
	user: { full_name },
	profile: { pay_currency },
});
const TAJWEED = { id: 3, name_ar: "تجويد", name_en: "Tajweed" };
const HIFZ = { id: 4, name_ar: "حفظ", name_en: "Hifz" };

function card(name: string) {
	return screen
		.getAllByRole("listitem")
		.find((item) =>
			within(item).queryByText(name, { selector: "[data-slot='card-title']" }),
		) as HTMLElement;
}

describe("RatesPage", () => {
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([teacher(21, "Bilal"), teacher(22, "Maryam", "EGP")]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([TAJWEED, HIFZ]) as never,
		);
		vi.mocked(payrollApi.rates).mockResolvedValue([
			rateRow(),
			rateRow({ id: 62, course: TAJWEED, hourly_rate_minor: 1200 }),
			rateRow({
				id: 63,
				teacher: { id: 22, full_name: "Maryam" },
				course: HIFZ,
				hourly_rate_minor: 90000,
				currency: "USD",
				counts: false,
			}),
		]);
	});

	it("lists each teacher's rates and warns about a missing default", async () => {
		renderWithRouter(<RatesPage />);
		await screen.findByText("Maryam");
		const bilal = card("Bilal");
		expect(within(bilal).getByText("Default rate")).toBeInTheDocument();
		expect(within(bilal).getByText("$12.00")).toBeInTheDocument();
		expect(within(bilal).queryByText("No default rate")).toBeNull();
		const maryam = card("Maryam");
		expect(within(maryam).getByText("EGP")).toBeInTheDocument();
		expect(within(maryam).getByText("No default rate")).toBeInTheDocument();
		// A USD rate for a teacher now paid in EGP no longer counts.
		expect(
			within(maryam).getByText("Old currency: edit it to count"),
		).toBeInTheDocument();
	});

	it("adds a default rate in the teacher's currency", async () => {
		vi.mocked(payrollApi.createRate).mockResolvedValue(rateRow({ id: 64 }));
		const user = userEvent.setup();
		renderWithRouter(<RatesPage />);
		await user.click(
			await screen.findByRole("button", { name: "Add a rate for Maryam" }),
		);
		const dialog = screen.getByRole("dialog");
		const course = within(dialog).getByLabelText("Course");
		// Hifz already has a rate; the default and Tajweed do not.
		expect(
			within(course)
				.getAllByRole("option")
				.map((o) => o.textContent),
		).toEqual(["Default rate", "Tajweed"]);
		await user.type(
			within(dialog).getByLabelText(/^Per hour \(EGP\)/),
			"400.50",
		);
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		await waitFor(() =>
			expect(payrollApi.createRate).toHaveBeenCalledWith({
				teacher: 22,
				course: null,
				hourly_rate_minor: 40050,
			}),
		);
		expect(await screen.findByText("Rate saved.")).toBeInTheDocument();
	});

	it("adds a course rate, and shows the server's refusal on the course", async () => {
		vi.mocked(payrollApi.createRate).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: {
					course: ["This teacher already has this rate. Edit it instead."],
				},
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<RatesPage />);
		await user.click(
			await screen.findByRole("button", { name: "Add a rate for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		const course = within(dialog).getByLabelText("Course");
		expect(
			within(course)
				.getAllByRole("option")
				.map((o) => o.textContent),
		).toEqual(["Hifz"]);
		await user.type(within(dialog).getByLabelText(/^Per hour \(USD\)/), "0");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		expect(payrollApi.createRate).toHaveBeenCalledWith({
			teacher: 21,
			course: 4,
			hourly_rate_minor: 0,
		});
		expect(
			await within(dialog).findByText(
				"This teacher already has this rate. Edit it instead.",
			),
		).toBeInTheDocument();
	});

	it("checks the amount before sending it", async () => {
		const user = userEvent.setup();
		renderWithRouter(<RatesPage />);
		await user.click(
			await screen.findByRole("button", { name: "Add a rate for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Per hour/), "1.005");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		expect(
			await within(dialog).findByText(
				"Enter an amount of zero or more, like 150 or 150.50.",
			),
		).toBeInTheDocument();
		expect(payrollApi.createRate).not.toHaveBeenCalled();
	});

	it("edits a rate's amount", async () => {
		vi.mocked(payrollApi.updateRate).mockResolvedValue(rateRow());
		const user = userEvent.setup();
		renderWithRouter(<RatesPage />);
		await user.click(
			await screen.findByRole("button", {
				name: "Edit Tajweed for Bilal",
			}),
		);
		const dialog = screen.getByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Per hour \(USD\)/);
		expect(amount).toHaveValue("12.00");
		expect(within(dialog).queryByLabelText("Course")).toBeNull();
		await user.clear(amount);
		await user.type(amount, "13");
		await user.click(within(dialog).getByRole("button", { name: "Save rate" }));
		await waitFor(() =>
			expect(payrollApi.updateRate).toHaveBeenCalledWith({
				id: 62,
				hourly_rate_minor: 1300,
			}),
		);
	});

	it("deletes a rate after confirming", async () => {
		vi.mocked(payrollApi.deleteRate).mockResolvedValue();
		const user = userEvent.setup();
		renderWithRouter(<RatesPage />);
		await screen.findByText("Maryam");
		await user.click(
			within(card("Bilal")).getByRole("button", { name: "Delete Tajweed" }),
		);
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Delete this rate",
			}),
		);
		await waitFor(() => expect(payrollApi.deleteRate).toHaveBeenCalledWith(62));
	});

	it("offers no Add once the default and every course have a rate", async () => {
		vi.mocked(payrollApi.rates).mockResolvedValue([
			rateRow(),
			rateRow({ id: 62, course: TAJWEED }),
			rateRow({ id: 63, course: HIFZ }),
		]);
		renderWithRouter(<RatesPage />);
		await screen.findByText("Maryam");
		expect(
			screen.queryByRole("button", { name: "Add a rate for Bilal" }),
		).toBeNull();
		expect(
			screen.getByRole("button", { name: "Add a rate for Maryam" }),
		).toBeInTheDocument();
	});

	it("reads in Arabic, its dialog too", async () => {
		await i18n.changeLanguage("ar");
		const user = userEvent.setup();
		renderWithRouter(<RatesPage />);
		expect(await screen.findByText("بلا سعر افتراضي")).toBeInTheDocument();
		expect(screen.getByText("السعر الافتراضي")).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", { name: "إضافة سعر لـ Maryam" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(
			within(dialog).getByLabelText(/^في الساعة \(EGP\)/),
		).toBeInTheDocument();
		expect(
			within(within(dialog).getByLabelText("الدورة")).getAllByRole("option")[1],
		).toHaveTextContent("تجويد");
	});

	it("shows an empty state and a load error", async () => {
		vi.mocked(peopleApi.list).mockResolvedValueOnce(page([]) as never);
		const { unmount } = renderWithRouter(<RatesPage />);
		expect(await screen.findByText("No teachers yet.")).toBeInTheDocument();
		unmount();
		vi.mocked(payrollApi.rates).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<RatesPage />);
		expect(
			await screen.findByText("Couldn't load the rates."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll/RatesPage.test.tsx`

Expected: FAIL — `Failed to resolve import "./RatesPage"`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/payroll/RateDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import type { Course } from "@/features/catalogue";
import type { Person as PeoplePerson, TeacherProfile } from "@/features/people";
import { useLocalName } from "@/features/scheduling";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
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
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { usePayrollMutation } from "./queries";
import { type Rate, type RateFormValues, rateFormSchema } from "./schemas";

/** Add a teacher's rate (the default, or a course without one yet), or edit
 * one's hourly amount. Amounts are in the teacher's pay currency (spec
 * §4.6). */
export function RateDialog({
	teacher,
	rates,
	courses,
	rate,
}: {
	teacher: PeoplePerson<TeacherProfile>;
	rates: Rate[];
	courses: Course[];
	rate?: Rate;
}) {
	const { t } = useTranslation();
	const localName = useLocalName();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const currency = teacher.profile.pay_currency;
	const name = teacher.user.full_name;
	const create = usePayrollMutation(payrollApi.createRate);
	const update = usePayrollMutation(payrollApi.updateRate);
	// What can still get a rate: the default ("") and courses without one.
	const rated = new Set(
		rates.map((r) => (r.course ? String(r.course.id) : "")),
	);
	const options = [
		...(rated.has("")
			? []
			: [{ value: "", label: t("payroll.rates.default") }]),
		...courses
			.filter((course) => !rated.has(String(course.id)))
			.map((course) => ({
				value: String(course.id),
				label: localName(course),
			})),
	];
	const label = rate
		? rate.course
			? localName(rate.course)
			: t("payroll.rates.default")
		: "";
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<RateFormValues>({
		resolver: zodResolver(rateFormSchema(currency)),
		values: {
			course: options[0]?.value ?? "",
			amount: rate ? toMajor(rate.hourly_rate_minor, currency) : "",
		},
	});

	async function onSubmit(values: RateFormValues) {
		const minor = toMinor(values.amount, currency);
		try {
			if (rate) {
				await update.mutateAsync({ id: rate.id, hourly_rate_minor: minor });
			} else {
				await create.mutateAsync({
					teacher: teacher.id,
					course: values.course ? Number(values.course) : null,
					hourly_rate_minor: minor,
				});
			}
			reset();
			setOpen(false);
			toast({ description: t("payroll.rates.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.hourly_rate_minor) {
				setError("amount", { message: parsed.fieldErrors.hourly_rate_minor });
			}
		}
	}

	// Every course and the default are rated: nothing left to add.
	if (!rate && options.length === 0) return null;
	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button
					size="sm"
					variant={rate ? "outline" : "primary"}
					aria-label={
						rate
							? t("payroll.rates.editFor", { course: label, name })
							: t("payroll.rates.addFor", { name })
					}
				>
					{rate ? t("payroll.rates.edit") : t("payroll.rates.add")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>
					{rate
						? t("payroll.rates.editTitle", { course: label, name })
						: t("payroll.rates.addFor", { name })}
				</DialogTitle>
				<DialogDescription>{t("payroll.rates.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					{rate ? null : (
						<Field
							id="rate-course"
							label={t("payroll.rates.course")}
							error={fieldError(errors.course?.message)}
						>
							<Select {...register("course")}>
								{options.map((option) => (
									<option key={option.value} value={option.value}>
										{option.label}
									</option>
								))}
							</Select>
						</Field>
					)}
					<Field
						id="rate-amount"
						label={t("payroll.rates.amount", { currency })}
						error={fieldError(errors.amount?.message)}
						required
					>
						<Input inputMode="decimal" dir="ltr" {...register("amount")} />
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
							{t("payroll.rates.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/payroll/RatesPage.tsx`:

```tsx
import { Coins } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Money } from "@/features/billing";
import { type Course, useCatalogue } from "@/features/catalogue";
import {
	type Person as PeoplePerson,
	type TeacherProfile,
	usePeople,
} from "@/features/people";
import { useLocalName } from "@/features/scheduling";
import { errorText } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	EmptyState,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { usePayrollMutation, useRates } from "./queries";
import { RateDialog } from "./RateDialog";
import type { Rate } from "./schemas";

function TeacherRates({
	teacher,
	rates,
	courses,
}: {
	teacher: PeoplePerson<TeacherProfile>;
	rates: Rate[];
	courses: Course[];
}) {
	const { t } = useTranslation();
	const localName = useLocalName();
	const remove = usePayrollMutation(payrollApi.deleteRate);
	const name = teacher.user.full_name;
	// Only a default in the teacher's current currency counts (spec §4.1).
	const hasDefault = rates.some((rate) => rate.course === null && rate.counts);
	const labelOf = (rate: Rate) =>
		rate.course
			? localName(rate.course) || `#${rate.course.id}`
			: t("payroll.rates.default");
	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<div className="flex flex-wrap items-center gap-2">
					<CardTitle>{name}</CardTitle>
					<span dir="ltr" className="text-sm text-muted-foreground">
						{teacher.profile.pay_currency}
					</span>
					{hasDefault ? null : (
						<StatusChip tone="warning">
							{t("payroll.rates.noDefault")}
						</StatusChip>
					)}
				</div>
				<RateDialog teacher={teacher} rates={rates} courses={courses} />
			</CardHeader>
			<CardContent>
				{rates.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("payroll.rates.none")}
					</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{rates.map((rate) => (
							<li
								key={rate.id}
								className="flex flex-wrap items-center justify-between gap-2 py-3"
							>
								<div className="flex flex-col gap-1 text-sm">
									<span className="font-medium">{labelOf(rate)}</span>
									<span className="flex flex-wrap items-center gap-2">
										<Money
											minor={rate.hourly_rate_minor}
											currency={rate.currency}
										/>
										{t("payroll.rates.perHour")}
										{rate.counts ? null : (
											<StatusChip tone="warning">
												{t("payroll.rates.oldCurrency")}
											</StatusChip>
										)}
									</span>
								</div>
								<div className="flex flex-wrap gap-2">
									<RateDialog
										teacher={teacher}
										rates={rates}
										courses={courses}
										rate={rate}
									/>
									<Confirm
										action={t("payroll.rates.delete", {
											course: labelOf(rate),
										})}
										title={t("payroll.rates.deleteTitle")}
										body={t("payroll.rates.deleteBody")}
										onConfirm={() =>
											remove.mutate(rate.id, {
												onError: (error) =>
													toast({
														description: errorText(error, t),
														variant: "destructive",
													}),
											})
										}
									/>
								</div>
							</li>
						))}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}

/** Spec §6 Rates (admin): per teacher, the default rate and per-course
 * rates in their pay currency, with add, edit and delete, and a warning for
 * a teacher without a default rate. A rate left in a currency the teacher is
 * no longer paid in is marked: it counts again once edited (spec §4.6). */
export function RatesPage() {
	const { t } = useTranslation();
	const teachers = usePeople<TeacherProfile>("teachers", { page_size: 100 });
	const rates = useRates();
	const { data: courses } = useCatalogue<Course>("courses", {
		page_size: 100,
	});
	if (teachers.isError || rates.isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("payroll.rates.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (!teachers.data || !rates.data) return <Spinner />;
	if (teachers.data.results.length === 0) {
		return (
			<Card>
				<CardContent>
					<EmptyState icon={Coins} title={t("payroll.rates.empty")} />
				</CardContent>
			</Card>
		);
	}
	const byTeacher = new Map<number, Rate[]>();
	for (const rate of rates.data) {
		byTeacher.set(rate.teacher.id, [
			...(byTeacher.get(rate.teacher.id) ?? []),
			rate,
		]);
	}
	return (
		<ul className="flex flex-col gap-4">
			{teachers.data.results.map((teacher) => (
				<li key={teacher.id}>
					<TeacherRates
						teacher={teacher}
						rates={byTeacher.get(teacher.id) ?? []}
						courses={courses?.results ?? []}
					/>
				</li>
			))}
		</ul>
	);
}
```

Replace the whole of `dashboard/src/features/payroll/index.ts` with:

```ts
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, PayslipStatusChip } from "./bits";
export { PayslipBody } from "./PayslipBody";
export { PayslipPage } from "./PayslipPage";
export { PayslipPrint } from "./PayslipPrint";
export * from "./queries";
export { RatesPage } from "./RatesPage";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/payroll.rates.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { RatesPage } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/payroll/rates")({
	component: function RatesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.rates"));
		return (
			<>
				<PageHeader title={t("nav.rates")} />
				<RatesPage />
			</>
		);
	},
});
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"nav": { "rates": "Rates" },
	"payroll": {
		"rates": {
			"loadError": "Couldn't load the rates.",
			"empty": "No teachers yet.",
			"none": "No rates yet.",
			"noDefault": "No default rate",
			"default": "Default rate",
			"perHour": "per hour",
			"oldCurrency": "Old currency: edit it to count",
			"add": "Add rate",
			"addFor": "Add a rate for {{name}}",
			"edit": "Edit",
			"editFor": "Edit {{course}} for {{name}}",
			"editTitle": "Edit {{course}} for {{name}}",
			"body": "Per hour, in the teacher's pay currency. Issued payslips keep the rates they were issued with.",
			"course": "Course",
			"amount": "Per hour ({{currency}})",
			"save": "Save rate",
			"saved": "Rate saved.",
			"delete": "Delete {{course}}",
			"deleteTitle": "Delete this rate",
			"deleteBody": "Issued payslips keep the rates they were issued with."
		}
	}
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"nav": { "rates": "الأسعار" },
	"payroll": {
		"rates": {
			"loadError": "تعذّر تحميل الأسعار.",
			"empty": "لا يوجد معلمون بعد.",
			"none": "لا توجد أسعار بعد.",
			"noDefault": "بلا سعر افتراضي",
			"default": "السعر الافتراضي",
			"perHour": "في الساعة",
			"oldCurrency": "عملة قديمة: عدّله ليُحتسب",
			"add": "إضافة سعر",
			"addFor": "إضافة سعر لـ {{name}}",
			"edit": "تعديل",
			"editFor": "تعديل {{course}} لـ {{name}}",
			"editTitle": "تعديل {{course}} لـ {{name}}",
			"body": "في الساعة، بعملة راتب المعلم. تحتفظ كشوف الرواتب الصادرة بالأسعار التي صدرت بها.",
			"course": "الدورة",
			"amount": "في الساعة ({{currency}})",
			"save": "حفظ السعر",
			"saved": "حُفظ السعر.",
			"delete": "حذف {{course}}",
			"deleteTitle": "حذف هذا السعر",
			"deleteBody": "تحتفظ كشوف الرواتب الصادرة بالأسعار التي صدرت بها."
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes, and coverage clears the gates (lines and statements 80, branches and functions 70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): the rates page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Dashboard: the Adjustments page

**Files:**
- Create: `dashboard/src/features/payroll/AdjustmentDialog.tsx`, `dashboard/src/features/payroll/AdjustmentsList.tsx`, `dashboard/src/routes/_authed/payroll.adjustments.tsx`
- Modify: `dashboard/src/features/payroll/index.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/payroll/AdjustmentsList.test.tsx` (new)
- Generated: `dashboard/src/routeTree.gen.ts` (by `vite build`, when a task adds a route)

**Interfaces:**
- Consumes: Task 9's `useAdjustments`, `payrollApi.createAdjustment/updateAdjustment/deleteAdjustment`, `adjustmentFormSchema`; `usePeople<TeacherProfile>("teachers", …)`; `useAcademySettings`, `todayIn`; `Pager`, `Confirm`.
- Produces: `AdjustmentsList()` and `AdjustmentDialog({teachers, adjustment?})`; the route `/_authed/payroll/adjustments`.

- [ ] **Step 1: Write the failing tests**

Only unused adjustments offer Edit and Delete; a used one links its payslip. The teacher and used filters reach the query. Adding checks the amount against the chosen teacher's currency (yen has no decimals) and dates it on the academy's today; a 409 on edit is translated.

Create `dashboard/src/features/payroll/AdjustmentsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { adjustmentRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { AdjustmentsList } from "./AdjustmentsList";
import { payrollApi } from "./api";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: {
			...actual.payrollApi,
			adjustments: vi.fn(),
			createAdjustment: vi.fn(),
			updateAdjustment: vi.fn(),
			deleteAdjustment: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const PAYSLIP = "/payroll/payslips/$payslipId";

function lastParams() {
	return vi.mocked(payrollApi.adjustments).mock.calls.at(-1)?.[0];
}

function row(text: string) {
	return screen.getByRole("row", { name: new RegExp(text) });
}

describe("AdjustmentsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				{
					id: 21,
					user: { full_name: "Bilal" },
					profile: { pay_currency: "USD" },
				},
				{
					id: 22,
					user: { full_name: "Maryam" },
					profile: { pay_currency: "JPY" },
				},
			]) as never,
		);
		vi.mocked(payrollApi.adjustments).mockResolvedValue(
			page([
				adjustmentRow(),
				adjustmentRow({
					id: 92,
					kind: "deduction",
					reason: "Late",
					amount_minor: 200,
					payslip: { id: 71, number: "PAY-000071" },
				}),
			]),
		);
	});
	afterEach(async () => {
		vi.useRealTimers();
		await i18n.changeLanguage("en");
	});

	it("lists bonuses and deductions, and changes only the unused ones", async () => {
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await screen.findByRole("table");
		const eid = row("Eid");
		expect(within(eid).getByText("Bonus")).toBeInTheDocument();
		expect(within(eid).getByText("$5.00")).toBeInTheDocument();
		expect(within(eid).getByText("Not used yet")).toBeInTheDocument();
		expect(
			within(eid).getByRole("button", { name: "Edit Eid for Bilal" }),
		).toBeInTheDocument();
		expect(
			within(eid).getByRole("button", { name: "Delete" }),
		).toBeInTheDocument();
		const late = row("Late");
		expect(within(late).getByText("Deduction")).toBeInTheDocument();
		expect(
			within(late).getByRole("link", { name: "PAY-000071" }),
		).toHaveAttribute("href", "/payroll/payslips/71");
		expect(within(late).queryAllByRole("button")).toHaveLength(0);
	});

	it("filters by teacher and by used", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Teacher"), "22");
		await waitFor(() => expect(lastParams()).toMatchObject({ teacher: "22" }));
		await user.selectOptions(screen.getByLabelText("Used or not"), "unused");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ teacher: "22", used: "false" }),
		);
		await user.selectOptions(screen.getByLabelText("Used or not"), "all");
		await waitFor(() => expect(lastParams()?.used).toBeUndefined());
	});

	it("adds one in the chosen teacher's currency, dated the academy's today", async () => {
		// 20:00 UTC on 1 July is already 2 July in the academy's Tokyo.
		vi.useFakeTimers({
			now: new Date("2026-07-01T20:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(payrollApi.createAdjustment).mockResolvedValue(adjustmentRow());
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await user.click(
			await screen.findByRole("button", { name: "Add adjustment" }),
		);
		const dialog = screen.getByRole("dialog");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		// The teacher, the amount and the reason.
		expect(await within(dialog).findAllByText("Fill this in.")).toHaveLength(3);
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "22");
		// Maryam is paid in yen, which has no decimals.
		await user.type(within(dialog).getByLabelText(/^Amount \(JPY\)/), "500.5");
		await user.selectOptions(
			within(dialog).getByLabelText(/^Kind/),
			"deduction",
		);
		await user.type(within(dialog).getByLabelText(/^Reason/), "Late");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		expect(
			await within(dialog).findByText(
				"Enter an amount above zero, like 150 or 150.50.",
			),
		).toBeInTheDocument();
		await user.clear(within(dialog).getByLabelText(/^Amount/));
		await user.type(within(dialog).getByLabelText(/^Amount/), "500");
		expect(within(dialog).getByLabelText(/^Date/)).toHaveValue("2026-07-02");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		await waitFor(() =>
			expect(payrollApi.createAdjustment).toHaveBeenCalledWith({
				teacher: 22,
				kind: "deduction",
				amount_minor: 500,
				effective_on: "2026-07-02",
				reason: "Late",
			}),
		);
	});

	it("edits an unused one and shows a refusal translated", async () => {
		vi.mocked(payrollApi.updateAdjustment).mockRejectedValue(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: {
					detail: "This adjustment is on an issued payslip.",
					code: "payroll.adjustment_used",
				},
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await user.click(
			await screen.findByRole("button", { name: "Edit Eid for Bilal" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).queryByLabelText(/^Teacher/)).toBeNull();
		const amount = within(dialog).getByLabelText(/^Amount \(USD\)/);
		expect(amount).toHaveValue("5.00");
		await user.clear(amount);
		await user.type(amount, "7");
		await user.click(
			within(dialog).getByRole("button", { name: "Save adjustment" }),
		);
		expect(payrollApi.updateAdjustment).toHaveBeenCalledWith({
			id: 91,
			kind: "bonus",
			amount_minor: 700,
			effective_on: "2026-06-15",
			reason: "Eid",
		});
		expect(
			await within(dialog).findByText(
				"This adjustment is on an issued payslip, so it can't change.",
			),
		).toBeInTheDocument();
	});

	it("deletes an unused one after confirming", async () => {
		vi.mocked(payrollApi.deleteAdjustment).mockResolvedValue();
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		await screen.findByRole("table");
		await user.click(
			within(row("Eid")).getByRole("button", { name: "Delete" }),
		);
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Delete this adjustment",
			}),
		);
		await waitFor(() =>
			expect(payrollApi.deleteAdjustment).toHaveBeenCalledWith(91),
		);
	});

	it("reads in Arabic, its dialog too", async () => {
		await i18n.changeLanguage("ar");
		const user = userEvent.setup();
		renderWithRouter(<AdjustmentsList />, { extraPaths: [PAYSLIP] });
		const eid = (await screen.findAllByRole("row"))[1] as HTMLElement;
		expect(within(eid).getByText("مكافأة")).toBeInTheDocument();
		expect(within(eid).getByText("لم تُستخدم بعد")).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "إضافة تسوية" }));
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText(/^السبب/)).toBeInTheDocument();
		expect(
			within(within(dialog).getByLabelText(/^النوع/)).getByRole("option", {
				name: "خصم",
			}),
		).toBeInTheDocument();
	});

	it("shows an empty state and a load error", async () => {
		vi.mocked(payrollApi.adjustments).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<AdjustmentsList />);
		expect(
			await screen.findByText("No bonuses or deductions here."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(payrollApi.adjustments).mockRejectedValueOnce(
			new Error("offline"),
		);
		renderWithRouter(<AdjustmentsList />);
		expect(
			await screen.findByText("Couldn't load the adjustments."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll/AdjustmentsList.test.tsx`

Expected: FAIL — `Failed to resolve import "./AdjustmentsList"`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/payroll/AdjustmentDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import type { Person as PeoplePerson, TeacherProfile } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
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
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { payrollApi } from "./api";
import { usePayrollMutation } from "./queries";
import {
	ADJUSTMENT_KINDS,
	type Adjustment,
	type AdjustmentFormValues,
	adjustmentFormSchema,
} from "./schemas";

/** Add a bonus or deduction for a teacher, or edit an unused one (spec
 * §4.6). The amount is in the teacher's pay currency; the date defaults to
 * the academy's today. */
export function AdjustmentDialog({
	teachers,
	adjustment,
}: {
	teachers: PeoplePerson<TeacherProfile>[];
	adjustment?: Adjustment;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const create = usePayrollMutation(payrollApi.createAdjustment);
	const update = usePayrollMutation(payrollApi.updateAdjustment);
	const currencyOf = (teacher: string) =>
		adjustment?.currency ??
		teachers.find((person) => String(person.id) === teacher)?.profile
			.pay_currency ??
		"USD";
	const {
		register,
		handleSubmit,
		setError,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<AdjustmentFormValues>({
		resolver: zodResolver(adjustmentFormSchema(currencyOf)),
		values: {
			teacher: adjustment ? String(adjustment.teacher.id) : "",
			kind: adjustment?.kind ?? "bonus",
			amount: adjustment
				? toMajor(adjustment.amount_minor, adjustment.currency)
				: "",
			effective_on:
				adjustment?.effective_on ?? (academy ? todayIn(academy.timezone) : ""),
			reason: adjustment?.reason ?? "",
		},
	});
	const currency = currencyOf(watch("teacher"));

	async function onSubmit(values: AdjustmentFormValues) {
		const fields = {
			kind: values.kind,
			amount_minor: toMinor(values.amount, currencyOf(values.teacher)),
			effective_on: values.effective_on,
			reason: values.reason,
		};
		try {
			if (adjustment) {
				await update.mutateAsync({ id: adjustment.id, ...fields });
			} else {
				await create.mutateAsync({
					teacher: Number(values.teacher),
					...fields,
				});
			}
			reset();
			setOpen(false);
			toast({
				description: t("payroll.adjustments.saved"),
				variant: "success",
			});
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.amount_minor) {
				setError("amount", { message: parsed.fieldErrors.amount_minor });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button
					size="sm"
					variant={adjustment ? "outline" : "primary"}
					aria-label={
						adjustment
							? t("payroll.adjustments.editFor", {
									name: adjustment.teacher.full_name,
									reason: adjustment.reason,
								})
							: undefined
					}
				>
					{adjustment
						? t("payroll.adjustments.edit")
						: t("payroll.adjustments.add")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>
					{adjustment
						? t("payroll.adjustments.editTitle")
						: t("payroll.adjustments.add")}
				</DialogTitle>
				<DialogDescription>{t("payroll.adjustments.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						{adjustment ? null : (
							<Field
								id="adjustment-teacher"
								label={t("payroll.columns.teacher")}
								error={fieldError(errors.teacher?.message)}
								required
							>
								<Select {...register("teacher")}>
									<option value="">
										{t("payroll.adjustments.chooseTeacher")}
									</option>
									{teachers.map((person) => (
										<option key={person.id} value={person.id}>
											{person.user.full_name}
										</option>
									))}
								</Select>
							</Field>
						)}
						<Field
							id="adjustment-kind"
							label={t("payroll.adjustments.kind")}
							error={fieldError(errors.kind?.message)}
							required
						>
							<Select {...register("kind")}>
								{ADJUSTMENT_KINDS.map((kind) => (
									<option key={kind} value={kind}>
										{t(`payroll.kinds.${kind}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="adjustment-amount"
							label={t("payroll.adjustments.amount", { currency })}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="adjustment-effective_on"
							label={t("payroll.adjustments.effectiveOn")}
							error={fieldError(errors.effective_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("effective_on")} />
						</Field>
					</div>
					<Field
						id="adjustment-reason"
						label={t("payroll.adjustments.reason")}
						error={fieldError(errors.reason?.message)}
						required
					>
						<Textarea rows={2} {...register("reason")} />
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
							{t("payroll.adjustments.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/payroll/AdjustmentsList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { HandCoins } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Pager } from "@/components/Pager";
import { Money } from "@/features/billing";
import { type TeacherProfile, usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { errorText } from "@/lib/form-errors";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Select,
	Spinner,
	toast,
} from "@/ui";
import { AdjustmentDialog } from "./AdjustmentDialog";
import { payrollApi } from "./api";
import { useAdjustments, usePayrollMutation } from "./queries";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const USED = { all: undefined, unused: "false", used: "true" } as const;
const COLUMNS = [
	"date",
	"teacher",
	"kind",
	"amount",
	"reason",
	"payslip",
	"actions",
] as const;

/** Spec §6 Adjustments (admin): bonuses and deductions with teacher and
 * used filters and paging; add, and edit or delete the unused ones. */
export function AdjustmentsList() {
	const { t, i18n } = useTranslation();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const { data, isPending, isError } = useAdjustments(params);
	const { data: teachers } = usePeople<TeacherProfile>("teachers", {
		page_size: 100,
	});
	const remove = usePayrollMutation(payrollApi.deleteAdjustment);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) =>
		setParams({ ...params, page: 1, ...patch });
	const used =
		(Object.keys(USED) as (keyof typeof USED)[]).find(
			(key) => USED[key] === params.used,
		) ?? "all";

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
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
				<Select
					aria-label={t("payroll.adjustments.used")}
					className="w-auto"
					value={used}
					onChange={(e) =>
						update({ used: USED[e.target.value as keyof typeof USED] })
					}
				>
					{(Object.keys(USED) as (keyof typeof USED)[]).map((key) => (
						<option key={key} value={key}>
							{t(`payroll.adjustments.filter.${key}`)}
						</option>
					))}
				</Select>
				<AdjustmentDialog teachers={teachers?.results ?? []} />
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>
						{t("payroll.adjustments.loadError")}
					</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={HandCoins}
							title={t("payroll.adjustments.empty")}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{COLUMNS.map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`payroll.adjustments.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((adjustment) => (
								<tr key={adjustment.id} className="border-t border-border">
									<td className="p-3">
										{formatDay(adjustment.effective_on, i18n.language)}
									</td>
									<td className="p-3">{adjustment.teacher.full_name}</td>
									<td className="p-3">
										{t(`payroll.kinds.${adjustment.kind}`)}
									</td>
									<td className="p-3">
										<Money
											minor={adjustment.amount_minor}
											currency={adjustment.currency}
										/>
									</td>
									<td className="p-3">{adjustment.reason}</td>
									<td className="p-3">
										{adjustment.payslip ? (
											<Link
												to="/payroll/payslips/$payslipId"
												params={{ payslipId: String(adjustment.payslip.id) }}
												dir="ltr"
												className="font-medium text-primary-text underline-offset-4 hover:underline"
											>
												{adjustment.payslip.number}
											</Link>
										) : (
											t("payroll.adjustments.unused")
										)}
									</td>
									<td className="p-3">
										{adjustment.payslip ? null : (
											<div className="flex flex-wrap gap-2">
												<AdjustmentDialog
													teachers={teachers?.results ?? []}
													adjustment={adjustment}
												/>
												<Confirm
													action={t("payroll.adjustments.delete")}
													title={t("payroll.adjustments.deleteTitle")}
													body={t("payroll.adjustments.deleteBody")}
													onConfirm={() =>
														remove.mutate(adjustment.id, {
															onError: (error) =>
																toast({
																	description: errorText(error, t),
																	variant: "destructive",
																}),
														})
													}
												/>
											</div>
										)}
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => setParams({ ...params, page: next })}
			/>
		</div>
	);
}
```

Replace the whole of `dashboard/src/features/payroll/index.ts` with:

```ts
export { AdjustmentsList } from "./AdjustmentsList";
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, PayslipStatusChip } from "./bits";
export { PayslipBody } from "./PayslipBody";
export { PayslipPage } from "./PayslipPage";
export { PayslipPrint } from "./PayslipPrint";
export * from "./queries";
export { RatesPage } from "./RatesPage";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/payroll.adjustments.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { AdjustmentsList } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/payroll/adjustments")({
	component: function AdjustmentsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.adjustments"));
		return (
			<>
				<PageHeader title={t("nav.adjustments")} />
				<AdjustmentsList />
			</>
		);
	},
});
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"nav": { "adjustments": "Adjustments" },
	"payroll": {
		"list": { "anyTeacher": "Any teacher" },
		"adjustments": {
			"used": "Used or not",
			"filter": { "all": "All", "unused": "Unused", "used": "Used" },
			"add": "Add adjustment",
			"edit": "Edit",
			"editFor": "Edit {{reason}} for {{name}}",
			"editTitle": "Edit adjustment",
			"body": "A bonus or a deduction, in the teacher's pay currency. It goes on the teacher's next payslip issued for its month or a later one.",
			"chooseTeacher": "Choose a teacher",
			"kind": "Kind",
			"amount": "Amount ({{currency}})",
			"effectiveOn": "Date",
			"reason": "Reason",
			"save": "Save adjustment",
			"saved": "Adjustment saved.",
			"delete": "Delete",
			"deleteTitle": "Delete this adjustment",
			"deleteBody": "It isn't on any issued payslip yet, so nothing else changes.",
			"loadError": "Couldn't load the adjustments.",
			"empty": "No bonuses or deductions here.",
			"unused": "Not used yet",
			"columns": {
				"date": "Date",
				"teacher": "Teacher",
				"kind": "Kind",
				"amount": "Amount",
				"reason": "Reason",
				"payslip": "Payslip",
				"actions": "Actions"
			}
		}
	}
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"nav": { "adjustments": "التسويات" },
	"payroll": {
		"list": { "anyTeacher": "أي معلم" },
		"adjustments": {
			"used": "مستخدمة أم لا",
			"filter": { "all": "الكل", "unused": "غير مستخدمة", "used": "مستخدمة" },
			"add": "إضافة تسوية",
			"edit": "تعديل",
			"editFor": "تعديل {{reason}} لـ {{name}}",
			"editTitle": "تعديل التسوية",
			"body": "مكافأة أو خصم بعملة راتب المعلم. تُدرج في كشف الراتب التالي الذي يصدر للمعلم عن شهرها أو شهر بعده.",
			"chooseTeacher": "اختر معلمًا",
			"kind": "النوع",
			"amount": "المبلغ ({{currency}})",
			"effectiveOn": "التاريخ",
			"reason": "السبب",
			"save": "حفظ التسوية",
			"saved": "حُفظت التسوية.",
			"delete": "حذف",
			"deleteTitle": "حذف هذه التسوية",
			"deleteBody": "لم تُدرج في أي كشف راتب صادر بعد، فلا يتغير شيء آخر.",
			"loadError": "تعذّر تحميل التسويات.",
			"empty": "لا توجد مكافآت أو خصومات هنا.",
			"unused": "لم تُستخدم بعد",
			"columns": {
				"date": "التاريخ",
				"teacher": "المعلم",
				"kind": "النوع",
				"amount": "المبلغ",
				"reason": "السبب",
				"payslip": "كشف الراتب",
				"actions": "الإجراءات"
			}
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes, and coverage clears the gates (lines and statements 80, branches and functions 70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): the adjustments page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Dashboard: the Payslips list, Generate and the Payroll nav group

**Files:**
- Create: `dashboard/src/features/payroll/PayslipsList.tsx`, `dashboard/src/routes/_authed/payroll.index.tsx`, `dashboard/src/routes/_authed/payroll.payslips.index.tsx`
- Modify: `dashboard/src/features/payroll/bits.tsx`, `dashboard/src/features/payroll/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/features/payroll/PayslipsList.test.tsx` (new)
- Generated: `dashboard/src/routeTree.gen.ts` (by `vite build`, when a task adds a route)

**Interfaces:**
- Consumes: Task 9's `usePayslips`, `payrollApi.generate`, `payslipsCsvUrl`, `hours`, `PayslipStatusChip`; `previousMonth`, `todayIn`; `usePeople`; `Pager`.
- Produces: `PayslipsList()` (D9), `monthName(month, language)` in payroll's bits; the routes `/_authed/payroll/` (redirects to Payslips) and `/_authed/payroll/payslips/`; the `payroll` nav group (D8).

- [ ] **Step 1: Write the failing tests**

The list opens on last month on the academy's calendar (20:00 UTC on 31 July is already 1 August in Tokyo, so last month is July there and would be June in UTC), shows each payslip's money in its own currency with the missing-rate badge, generates the chosen month and names who is missing a rate (with a link to Rates) and whose adjustments were left out, and exports CSV with the same filters.

In `dashboard/src/features/shell/nav.test.ts` (1 of 3), replace:

```ts
			"/scheduling/subscriptions",
			"/billing/invoices",
			"/teaching/sessions",
			"/teaching/reports",
```

with:

```ts
			"/scheduling/subscriptions",
			"/billing/invoices",
			"/payroll/payslips",
			"/payroll/rates",
			"/payroll/adjustments",
			"/teaching/sessions",
			"/teaching/reports",
```

In `dashboard/src/features/shell/nav.test.ts` (2 of 3), replace:

```ts
			"scheduling",
			"billing",
			"people",
			"catalogue",
```

with:

```ts
			"scheduling",
			"billing",
			"payroll",
			"people",
			"catalogue",
```

In `dashboard/src/features/shell/nav.test.ts` (3 of 3), replace:

```ts
		expect(groups[1]?.items).toHaveLength(4);
		expect(groups[2]?.items.map((i) => i.labelKey)).toEqual(["nav.invoices"]);
		expect(groups[3]?.items).toHaveLength(4);
	});
});
```

with:

```ts
		expect(groups[1]?.items).toHaveLength(4);
		expect(groups[2]?.items.map((i) => i.labelKey)).toEqual(["nav.invoices"]);
		expect(groups[3]?.items.map((i) => i.labelKey)).toEqual([
			"nav.payslips",
			"nav.rates",
			"nav.adjustments",
		]);
		expect(groups[4]?.items).toHaveLength(4);
	});
});
```

Create `dashboard/src/features/payroll/PayslipsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { generateResult, payslipRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { PayslipsList } from "./PayslipsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		payrollApi: { ...actual.payrollApi, payslips: vi.fn(), generate: vi.fn() },
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const PATHS = ["/payroll/payslips/$payslipId", "/payroll/rates"];

function lastParams() {
	return vi.mocked(payrollApi.payslips).mock.calls.at(-1)?.[0];
}

describe("PayslipsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		// 20:00 UTC on 31 July is already 1 August in the academy's Tokyo, so
		// "last month" is July there, and still June for a reader in UTC.
		vi.useFakeTimers({
			now: new Date("2026-07-31T20:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal" } }]) as never,
		);
		vi.mocked(payrollApi.payslips).mockResolvedValue(
			page([
				payslipRow({ month: 7 }),
				payslipRow({
					id: 72,
					number: "PAY-000072",
					month: 7,
					teacher: { id: 22, full_name: "Maryam" },
					currency: "EGP",
					missing_rate: true,
					sessions: 1,
					minutes: 45,
					gross_minor: 0,
					bonuses_minor: 0,
					deductions_minor: 0,
					net_minor: 0,
				}),
				payslipRow({
					id: 73,
					number: "PAY-000073",
					month: 7,
					teacher: { id: 23, full_name: "Hamza" },
					status: "paid",
				}),
			]),
		);
	});
	afterEach(async () => {
		vi.useRealTimers();
		await i18n.changeLanguage("en");
	});

	it("opens on last month in the academy's calendar", async () => {
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		await screen.findByRole("table");
		expect(lastParams()).toMatchObject({ year: 2026, month: 7 });
		expect(screen.getByLabelText("Month")).toHaveValue("7");
		expect(screen.getByLabelText("Year")).toHaveValue("2026");
	});

	it("shows each payslip's sessions, hours, money and status", async () => {
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		const table = await screen.findByRole("table");
		const bilal = within(table).getByRole("row", { name: /Bilal/ });
		const cells = within(bilal)
			.getAllByRole("cell")
			.map((c) => c.textContent);
		expect(cells.slice(1, 8)).toEqual([
			"Bilal",
			"2",
			"1.5",
			"$15.00",
			"$5.00",
			"$2.00",
			"$18.00",
		]);
		expect(within(bilal).getByText("Draft")).toBeInTheDocument();
		expect(
			within(bilal).getByRole("link", { name: "PAY-000071" }),
		).toHaveAttribute("href", "/payroll/payslips/71");
		const maryam = within(table).getByRole("row", { name: /Maryam/ });
		expect(within(maryam).getByText("Missing rate")).toBeInTheDocument();
		// Each payslip in its own currency: Maryam's net is in EGP.
		expect(within(maryam).getAllByRole("cell")[7]?.textContent).toMatch(
			/EGP\s?0\.00/,
		);
		const hamza = within(table).getByRole("row", { name: /Hamza/ });
		// "Paid" is also the start of no other status: match it exactly.
		expect(
			within(hamza).getByText("Paid", { exact: true }),
		).toBeInTheDocument();
	});

	it("generates the chosen month and names who is missing a rate", async () => {
		vi.mocked(payrollApi.generate).mockResolvedValue(
			generateResult({
				missing_rate: [
					{ id: 22, full_name: "Maryam" },
					{ id: 23, full_name: "Hamza" },
				],
				other_currency: [{ id: 21, full_name: "Bilal" }],
			}),
		);
		const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Month"), "6");
		await waitFor(() => expect(lastParams()).toMatchObject({ month: 6 }));
		await user.click(screen.getByRole("button", { name: "Generate" }));
		await waitFor(() =>
			expect(payrollApi.generate).toHaveBeenCalledWith({
				year: 2026,
				month: 6,
			}),
		);
		expect(
			await screen.findByText("New: 2. Updated: 1. Removed: 0."),
		).toBeInTheDocument();
		expect(
			screen.getByText("No rate for a session of Maryam and Hamza.", {
				exact: false,
			}),
		).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Set rates" })).toHaveAttribute(
			"href",
			"/payroll/rates",
		);
		expect(
			screen.getByText(
				"Adjustments in a currency they are no longer paid in were left out for Bilal.",
			),
		).toBeInTheDocument();
		// Another month hides the result.
		await user.selectOptions(screen.getByLabelText("Year"), "2025");
		expect(screen.queryByText("New: 2. Updated: 1. Removed: 0.")).toBeNull();
	});

	it("reads in Arabic, month names included", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		const table = await screen.findByRole("table");
		expect(
			within(table).getByRole("columnheader", { name: "الصافي" }),
		).toBeInTheDocument();
		expect(within(table).getByText("سعر ناقص")).toBeInTheDocument();
		expect(screen.getByLabelText("الشهر")).toHaveDisplayValue("يوليو");
		expect(screen.getByRole("button", { name: "إنشاء" })).toBeInTheDocument();
	});

	it("shows a failed generate", async () => {
		vi.mocked(payrollApi.generate).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { month: ["Ensure this value is less than or equal to 12."] },
			} as never),
		);
		const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		await user.click(await screen.findByRole("button", { name: "Generate" }));
		expect(
			await screen.findByText("Ensure this value is less than or equal to 12."),
		).toBeInTheDocument();
	});

	it("filters by status and teacher, and exports the same as CSV", async () => {
		const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Status"), "issued");
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				status: "issued",
				teacher: "21",
				year: 2026,
				month: 7,
			}),
		);
		expect(screen.getByRole("link", { name: "Export CSV" })).toHaveAttribute(
			"href",
			"/api/v1/payroll/payslips/?status=issued&teacher=21&year=2026&month=7&format=csv",
		);
	});

	it("shows an empty month and a load error", async () => {
		vi.mocked(payrollApi.payslips).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<PayslipsList />, {
			extraPaths: PATHS,
		});
		expect(
			await screen.findByText("No payslips for this month."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(payrollApi.payslips).mockRejectedValueOnce(new Error("offline"));
		const second = renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		expect(
			await screen.findByText("Couldn't load payslips."),
		).toBeInTheDocument();
		second.unmount();
		vi.mocked(academyApi.get).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<PayslipsList />, { extraPaths: PATHS });
		expect(
			await screen.findByText("Couldn't load payslips."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll/PayslipsList.test.tsx src/features/shell/nav.test.ts`

Expected: FAIL — `Failed to resolve import "./PayslipsList"`; the nav test lacks the payroll group.

- [ ] **Step 3: Implement**

In `dashboard/src/features/payroll/bits.tsx`, replace:

```tsx
		minutes / 60,
	);
}
```

with:

```tsx
		minutes / 60,
	);
}

/** A month's name alone, e.g. "June", for the month picker. */
export function monthName(month: number, language: string): string {
	return new Intl.DateTimeFormat(language, {
		month: "long",
		timeZone: "UTC",
	}).format(new Date(Date.UTC(2026, month - 1, 1)));
}
```

Create `dashboard/src/features/payroll/PayslipsList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Wallet } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { Money } from "@/features/billing";
import { type TeacherProfile, usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { errorText } from "@/lib/form-errors";
import { previousMonth, todayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Select,
	Spinner,
	toast,
} from "@/ui";
import { payrollApi, payslipsCsvUrl } from "./api";
import { hours, monthName, PayslipStatusChip } from "./bits";
import { usePayrollMutation, usePayslips } from "./queries";
import { type GenerateResult, PAYSLIP_STATUSES, type Person } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const MONTHS = Array.from({ length: 12 }, (_, index) => index + 1);
const COLUMNS = [
	"number",
	"teacher",
	"sessions",
	"hours",
	"gross",
	"bonuses",
	"deductions",
	"net",
	"status",
] as const;
type Month = { year: number; month: number };

function GenerateSummary({ result }: { result: GenerateResult }) {
	const { t, i18n } = useTranslation();
	const names = (people: Person[]) =>
		new Intl.ListFormat(i18n.language, { type: "conjunction" }).format(
			people.map((person) => person.full_name),
		);
	return (
		<Alert>
			<AlertDescription className="flex flex-col gap-1">
				<p>
					{t("payroll.list.result", {
						created: result.created,
						replaced: result.replaced,
						removed: result.removed,
					})}
				</p>
				{result.missing_rate.length > 0 ? (
					<p>
						{t("payroll.list.missingRate", {
							names: names(result.missing_rate),
						})}{" "}
						<Link
							to="/payroll/rates"
							className="font-medium text-primary-text underline-offset-4 hover:underline"
						>
							{t("payroll.list.setRates")}
						</Link>
					</p>
				) : null}
				{result.other_currency.length > 0 ? (
					<p>
						{t("payroll.list.otherCurrency", {
							names: names(result.other_currency),
						})}
					</p>
				) : null}
			</AlertDescription>
		</Alert>
	);
}

function MonthPayslips({
	initial,
	thisYear,
}: {
	initial: Month;
	thisYear: number;
}) {
	const { t, i18n } = useTranslation();
	const [month, setMonth] = useState<Month>(initial);
	const [filters, setFilters] = useState<QueryParams>({ page: 1 });
	const [result, setResult] = useState<GenerateResult | null>(null);
	const params = { ...filters, year: month.year, month: month.month };
	const { data, isPending, isError } = usePayslips(params);
	const { data: teachers } = usePeople<TeacherProfile>("teachers", {
		page_size: 100,
	});
	const generate = usePayrollMutation(payrollApi.generate);
	const rows = data?.results ?? [];
	const page = Number(filters.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const years = [thisYear - 2, thisYear - 1, thisYear, thisYear + 1];
	const pick = (patch: Partial<Month>) => {
		setMonth({ ...month, ...patch });
		setFilters({ ...filters, page: 1 });
		setResult(null);
	};
	const update = (patch: QueryParams) =>
		setFilters({ ...filters, page: 1, ...patch });

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<div className="flex flex-col gap-1">
					<label htmlFor="payslips-month" className="text-xs">
						{t("payroll.columns.month")}
					</label>
					<Select
						id="payslips-month"
						className="w-auto"
						value={month.month}
						onChange={(e) => pick({ month: Number(e.target.value) })}
					>
						{MONTHS.map((value) => (
							<option key={value} value={value}>
								{monthName(value, i18n.language)}
							</option>
						))}
					</Select>
				</div>
				<div className="flex flex-col gap-1">
					<label htmlFor="payslips-year" className="text-xs">
						{t("payroll.list.year")}
					</label>
					<Select
						id="payslips-year"
						className="w-auto"
						value={month.year}
						onChange={(e) => pick({ year: Number(e.target.value) })}
					>
						{years.map((year) => (
							<option key={year} value={year}>
								{year}
							</option>
						))}
					</Select>
				</div>
				<Button
					size="sm"
					disabled={generate.isPending}
					onClick={() =>
						generate.mutate(month, {
							onSuccess: setResult,
							onError: (error) =>
								toast({
									description: errorText(error, t),
									variant: "destructive",
								}),
						})
					}
				>
					{t("payroll.list.generate")}
				</Button>
			</div>
			{result ? <GenerateSummary result={result} /> : null}
			<div className="flex flex-wrap items-end gap-3">
				<Select
					aria-label={t("payroll.columns.status")}
					className="w-auto"
					value={String(filters.status ?? "")}
					onChange={(e) => update({ status: e.target.value })}
				>
					<option value="">{t("payroll.list.anyStatus")}</option>
					{PAYSLIP_STATUSES.map((status) => (
						<option key={status} value={status}>
							{t(`payroll.status.${status}`)}
						</option>
					))}
				</Select>
				<Select
					aria-label={t("payroll.columns.teacher")}
					className="w-auto"
					value={String(filters.teacher ?? "")}
					onChange={(e) => update({ teacher: e.target.value })}
				>
					<option value="">{t("payroll.list.anyTeacher")}</option>
					{teachers?.results.map((person) => (
						<option key={person.id} value={person.id}>
							{person.user.full_name}
						</option>
					))}
				</Select>
				<Button asChild variant="outline" size="sm">
					<a href={payslipsCsvUrl(params)} download>
						{t("people.exportCsv")}
					</a>
				</Button>
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("payroll.list.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={Wallet} title={t("payroll.list.empty")} />
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{COLUMNS.map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`payroll.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((payslip) => {
								const money = (minor: number) => (
									<Money minor={minor} currency={payslip.currency} />
								);
								return (
									<tr key={payslip.id} className="border-t border-border">
										<td className="p-3">
											<Link
												to="/payroll/payslips/$payslipId"
												params={{ payslipId: String(payslip.id) }}
												dir="ltr"
												className="font-medium text-primary-text underline-offset-4 hover:underline"
											>
												{payslip.number}
											</Link>
										</td>
										<td className="p-3">{payslip.teacher.full_name}</td>
										<td className="p-3">{payslip.sessions}</td>
										<td className="p-3">
											{hours(payslip.minutes, i18n.language)}
										</td>
										<td className="p-3">{money(payslip.gross_minor)}</td>
										<td className="p-3">{money(payslip.bonuses_minor)}</td>
										<td className="p-3">{money(payslip.deductions_minor)}</td>
										<td className="p-3 font-medium">
											{money(payslip.net_minor)}
										</td>
										<td className="p-3">
											<PayslipStatusChip payslip={payslip} />
										</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => setFilters({ ...filters, page: next })}
			/>
		</div>
	);
}

/** Spec §6 Payslips (admin): a month, last month on the academy's calendar
 * by default; Generate, whose result names teachers missing a rate; the
 * month's payslips with status and teacher filters, CSV and paging. */
export function PayslipsList() {
	const { t } = useTranslation();
	const { data: academy, isError } = useAcademySettings();
	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("payroll.list.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (!academy) return <Spinner />;
	const today = todayIn(academy.timezone);
	return (
		<MonthPayslips
			initial={previousMonth(today)}
			thisYear={Number(today.slice(0, 4))}
		/>
	);
}
```

Replace the whole of `dashboard/src/features/payroll/index.ts` with:

```ts
export { AdjustmentsList } from "./AdjustmentsList";
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, monthName, PayslipStatusChip } from "./bits";
export { PayslipBody } from "./PayslipBody";
export { PayslipPage } from "./PayslipPage";
export { PayslipPrint } from "./PayslipPrint";
export { PayslipsList } from "./PayslipsList";
export * from "./queries";
export { RatesPage } from "./RatesPage";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/payroll.index.tsx`:

```tsx
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/_authed/payroll/")({
	beforeLoad: () => {
		throw redirect({ to: "/payroll/payslips" });
	},
});
```

Create `dashboard/src/routes/_authed/payroll.payslips.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PayslipsList } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/payroll/payslips/")({
	component: function PayslipsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.payslips"));
		return (
			<>
				<PageHeader title={t("nav.payslips")} />
				<PayslipsList />
			</>
		);
	},
});
```

In `dashboard/src/features/shell/nav.ts` (1 of 4), replace:

```ts
	BookOpen,
	CalendarClock,
	FileClock,
	Globe,
	GraduationCap,
	Home,
	ListChecks,
```

with:

```ts
	BookOpen,
	CalendarClock,
	Coins,
	FileClock,
	Globe,
	GraduationCap,
	HandCoins,
	Home,
	ListChecks,
```

In `dashboard/src/features/shell/nav.ts` (2 of 4), replace:

```ts
	User,
	Users,
} from "lucide-react";
import type { ProfileType, Role } from "@/features/identity/schemas";
```

with:

```ts
	User,
	Users,
	Wallet,
} from "lucide-react";
import type { ProfileType, Role } from "@/features/identity/schemas";
```

In `dashboard/src/features/shell/nav.ts` (3 of 4), replace:

```ts
	| "scheduling"
	| "billing"
	| "teaching"
	| "learning"
```

with:

```ts
	| "scheduling"
	| "billing"
	| "payroll"
	| "teaching"
	| "learning"
```

In `dashboard/src/features/shell/nav.ts` (4 of 4), replace:

```ts
	// Plan 6: invoices and payments.
	admin("/billing/invoices", "nav.invoices", Receipt, "billing"),
	// Plan 5: a teacher's own sessions and the reports they still owe.
	{
```

with:

```ts
	// Plan 6: invoices and payments.
	admin("/billing/invoices", "nav.invoices", Receipt, "billing"),
	// Plan 7: teacher payroll.
	admin("/payroll/payslips", "nav.payslips", Wallet, "payroll"),
	admin("/payroll/rates", "nav.rates", Coins, "payroll"),
	admin("/payroll/adjustments", "nav.adjustments", HandCoins, "payroll"),
	// Plan 5: a teacher's own sessions and the reports they still owe.
	{
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"nav": { "payslips": "Payslips", "group": { "payroll": "Payroll" } },
	"payroll": {
		"columns": {
			"number": "Number",
			"sessions": "Sessions",
			"hours": "Hours",
			"status": "Status"
		},
		"list": {
			"year": "Year",
			"generate": "Generate",
			"anyStatus": "Any status",
			"empty": "No payslips for this month.",
			"loadError": "Couldn't load payslips.",
			"result": "New: {{created}}. Updated: {{replaced}}. Removed: {{removed}}.",
			"missingRate": "No rate for a session of {{names}}.",
			"setRates": "Set rates",
			"otherCurrency": "Adjustments in a currency they are no longer paid in were left out for {{names}}."
		}
	}
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"nav": { "payslips": "كشوف الرواتب", "group": { "payroll": "الرواتب" } },
	"payroll": {
		"columns": {
			"number": "الرقم",
			"sessions": "الحصص",
			"hours": "الساعات",
			"status": "الحالة"
		},
		"list": {
			"year": "السنة",
			"generate": "إنشاء",
			"anyStatus": "أي حالة",
			"empty": "لا توجد كشوف رواتب لهذا الشهر.",
			"loadError": "تعذّر تحميل كشوف الرواتب.",
			"result": "جديدة: {{created}}. محدّثة: {{replaced}}. محذوفة: {{removed}}.",
			"missingRate": "لا يوجد سعر لحصة من حصص {{names}}.",
			"setRates": "تحديد الأسعار",
			"otherCurrency": "استُبعدت تسويات بعملة لم يعد يُدفع بها لـ {{names}}."
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll src/features/shell
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes, and coverage clears the gates (lines and statements 80, branches and functions 70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): the payslips list, generate and the payroll nav group

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: Dashboard: My payslips for teachers, end-to-end through Caddy, STATE.md

**Files:**
- Create: `dashboard/src/features/payroll/TeacherPayslips.tsx`, `dashboard/src/routes/_authed/teaching.payslips.index.tsx`, `dashboard/src/routes/_authed/teaching.payslips.$payslipId.tsx`
- Modify: `dashboard/src/features/payroll/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/features/payroll/TeacherPayslips.test.tsx` (new), `dashboard/e2e/payroll.spec.ts` (new)
- Modify: `STATE.md` (meta), submodule pointers (meta, after merge)

**Interfaces:**
- Consumes: Task 9's `usePayslips`; Task 11's `PayslipPage`; `e2e/fixtures.ts`'s `login`, `expectLoggedIn`, `acceptInvite`, `DEMO_URL`, `DEMO_ADMIN`.
- Produces: `TeacherPayslips()`; the routes `/_authed/teaching/payslips/` and `/_authed/teaching/payslips/$payslipId`; the Teaching group's My payslips; `e2e/payroll.spec.ts` (spec §8).
- CI: no change. The `e2e` job already migrates a fresh database, runs `seed_dev`, sends email inline into files that `e2e/mail.ts` reads, starts the marketing server and runs every spec in `e2e/`.

- [ ] **Step 1: Write the failing tests**

The e2e journey creates its own teacher (invited by email), course, weekly package and student, a subscription from the 1st of last month with its slot on the 15th's weekday at noon, and generates that one day from the Today board, so it never depends on the date it runs or on seeded sessions. The month is picked explicitly in the picker. Statuses are asserted on the payslip's card header, never page-wide.

In `dashboard/src/features/shell/nav.test.ts` (1 of 2), replace:

```ts
			"/teaching/sessions",
			"/teaching/reports",
			"/learning/sessions",
			"/learning/subscriptions",
```

with:

```ts
			"/teaching/sessions",
			"/teaching/reports",
			"/teaching/payslips",
			"/learning/sessions",
			"/learning/subscriptions",
```

In `dashboard/src/features/shell/nav.test.ts` (2 of 2), replace:

```ts
	});

	it("shows a teacher their sessions and the reports they owe", () => {
		expect(visibleNavItems(NAV_ITEMS, [], "teacher").map((i) => i.to)).toEqual([
			"/",
			"/teaching/sessions",
			"/teaching/reports",
			"/account",
		]);
```

with:

```ts
	});

	it("shows a teacher their sessions, the reports they owe and their payslips", () => {
		expect(visibleNavItems(NAV_ITEMS, [], "teacher").map((i) => i.to)).toEqual([
			"/",
			"/teaching/sessions",
			"/teaching/reports",
			"/teaching/payslips",
			"/account",
		]);
```

Create `dashboard/src/features/payroll/TeacherPayslips.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { payslipRow } from "@/test/payroll-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { payrollApi } from "./api";
import { TeacherPayslips } from "./TeacherPayslips";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, payrollApi: { ...actual.payrollApi, payslips: vi.fn() } };
});

describe("TeacherPayslips", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(payrollApi.payslips).mockResolvedValue(
			page([
				payslipRow({ status: "paid", paid_on: "2026-07-02" }),
				payslipRow({
					id: 72,
					number: "PAY-000072",
					month: 5,
					status: "issued",
				}),
			]),
		);
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("lists the teacher's payslips, each opening its page", async () => {
		renderWithRouter(<TeacherPayslips />, {
			extraPaths: ["/teaching/payslips/$payslipId"],
		});
		const june = (await screen.findByText("June 2026")).closest(
			"li",
		) as HTMLElement;
		expect(
			within(june).getByRole("link", { name: "PAY-000071" }),
		).toHaveAttribute("href", "/teaching/payslips/71");
		expect(within(june).getByText("$18.00")).toBeInTheDocument();
		expect(within(june).getByText("Paid", { exact: true })).toBeInTheDocument();
		const may = screen.getByText("May 2026").closest("li") as HTMLElement;
		expect(within(may).getByText("Issued")).toBeInTheDocument();
		expect(payrollApi.payslips).toHaveBeenCalledWith({ page: 1 });
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<TeacherPayslips />, {
			extraPaths: ["/teaching/payslips/$payslipId"],
		});
		expect(await screen.findByText("مدفوع")).toBeInTheDocument();
		expect(screen.getByText("صادر")).toBeInTheDocument();
	});

	it("shows an empty list and a load error", async () => {
		vi.mocked(payrollApi.payslips).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<TeacherPayslips />);
		expect(await screen.findByText("No payslips yet.")).toBeInTheDocument();
		unmount();
		vi.mocked(payrollApi.payslips).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<TeacherPayslips />);
		expect(
			await screen.findByText("Couldn't load payslips."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/e2e/payroll.spec.ts`:

```ts
import { expect, type Page, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
} from "./fixtures";

const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

/** Last month on the academy's calendar, from its today ("YYYY-MM-DD"): its
 * first day, and its 15th, which is always over and never a month's edge. */
function lastMonth(today: string) {
	const [year, month] = today.split("-").map(Number);
	const y = month === 1 ? year - 1 : year;
	const m = month === 1 ? 12 : month - 1;
	const mm = String(m).padStart(2, "0");
	return { year: y, month: m, first: `${y}-${mm}-01`, mid: `${y}-${mm}-15` };
}

/** The payslip page's card header: the number heading and the status chip.
 * Asserting the status here, not page-wide, keeps the "Paid on" fact and the
 * totals from satisfying it. */
const payslipHeader = (page: Page, number: string) =>
	page.locator('[data-slot="card-header"]').filter({
		has: page.getByRole("heading", { name: number, exact: true }),
	});

// Spec §8: the admin sets a rate for a teacher with a completed session last
// month and generates; issues the payslip and marks it paid; the teacher
// (invited) signs in, sees the payslip and prints it; the paid session's
// attendance is locked. The session sits on the 15th of last month at noon,
// away from midnight and the month's edges, and the month is picked
// explicitly rather than read from the picker's default. Required labels end
// in `*`, hence the regex queries.
test("an admin pays a teacher for last month, and the teacher prints the payslip", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const teacher = `E2E Payee ${stamp}`;
	const teacherEmail = `e2e-payee-${stamp}@e2e.test`;
	const student = `E2E Payroll Pupil ${stamp}`;
	const course = `E2E Payroll Course ${stamp}`;
	const pkg = `E2E Payroll Pack ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A teacher (invited by email, paid in USD by default), their course, a
	// weekly package and a student
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/^full name/i).fill(teacher);
	await page.getByLabel(/^gender/i).selectOption("female");
	await page.getByLabel(/^email/i).fill(teacherEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);

	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`رواتب ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(course);
	await page.getByLabel(teacher, { exact: true }).click();
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`أسبوعي ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("1");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Price").fill("100");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	// A subscription from the 1st of last month, its slot on the 15th's weekday
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	const startsOn = page.getByLabel(/^Starts/);
	await expect(startsOn).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
	const month = lastMonth(await startsOn.inputValue());
	await startsOn.fill(month.first);
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: course });
	await page.getByLabel(/^Teacher/).selectOption({ label: teacher });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await page.getByLabel(weekday(month.mid), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("12:00");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);

	// That past day's session, generated from the Today board
	await page.goto(`${DEMO_URL}/app/scheduling/today`);
	await page.getByRole("button", { name: "Generate for range" }).click();
	const generate = page.getByRole("dialog");
	await generate.getByLabel(/^From/).fill(month.mid);
	await generate.getByLabel(/^To/).fill(month.mid);
	await generate.getByRole("button", { name: "Generate", exact: true }).click();
	await expect(generate.getByText(/^Created [1-9]/)).toBeVisible();
	await page.keyboard.press("Escape");

	// The admin marks the student present; the teacher's attendance stays
	// "Not set", which still pays (P7-2)
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByLabel("Period").selectOption("all");
	await page.getByRole("searchbox").fill(student);
	await page
		.getByRole("row", { name: new RegExp(student) })
		.getByRole("link", { name: student, exact: true })
		.click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	const sessionUrl = page.url();
	await page
		.getByLabel(`Student attendance for ${student}`, { exact: true })
		.selectOption("present");
	await expect(
		page.locator('[data-slot="card-header"]').getByText("Completed", {
			exact: true,
		}),
	).toBeVisible();

	// 1. A default rate, then generate last month
	await page.goto(`${DEMO_URL}/app/payroll/rates`);
	await page
		.getByRole("button", { name: `Add a rate for ${teacher}`, exact: true })
		.click();
	const rate = page.getByRole("dialog");
	await expect(rate.getByLabel("Course")).toHaveValue("");
	await rate.getByLabel(/^Per hour \(USD\)/).fill("20");
	await rate.getByRole("button", { name: "Save rate" }).click();
	await expect(page.getByRole("dialog")).toHaveCount(0);

	await page.goto(`${DEMO_URL}/app/payroll/payslips`);
	await page.getByLabel("Year").selectOption(String(month.year));
	await page.getByLabel("Month").selectOption(String(month.month));
	await page.getByRole("button", { name: "Generate", exact: true }).click();
	await expect(page.getByText(/^New: \d+\. Updated: \d+\. Removed: \d+\.$/)).toBeVisible();
	const row = page.getByRole("row", { name: new RegExp(teacher) });
	await expect(row.getByText("Draft", { exact: true })).toBeVisible();
	const link = row.getByRole("link", { name: /^PAY-\d{6}$/ });
	const number = (await link.textContent()) ?? "";
	await link.click();
	await expect(page).toHaveURL(/\/app\/payroll\/payslips\/\d+$/);

	// 2. Issue it, then mark it paid (dated the academy's today)
	await page.getByRole("button", { name: "Issue", exact: true }).click();
	await page
		.getByRole("alertdialog")
		.getByRole("button", { name: "Issue this payslip" })
		.click();
	await expect(
		payslipHeader(page, number).getByText("Issued", { exact: true }),
	).toBeVisible();
	await page.getByRole("button", { name: "Mark paid" }).click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Mark paid" })
		.click();
	await expect(page.getByRole("dialog")).toHaveCount(0);
	await expect(
		payslipHeader(page, number).getByText("Paid", { exact: true }),
	).toBeVisible();

	// 3. The teacher accepts the invite, finds the payslip and prints it
	const payee = await acceptInvite(
		browser,
		teacherEmail,
		"e2e-Payee-2026",
		teacher,
	);
	await payee.getByRole("link", { name: "My payslips" }).first().click();
	await expect(payee).toHaveURL(/\/app\/teaching\/payslips$/);
	await payee.getByRole("link", { name: number, exact: true }).click();
	await expect(payee).toHaveURL(/\/app\/teaching\/payslips\/\d+$/);
	await expect(
		payslipHeader(payee, number).getByText("Paid", { exact: true }),
	).toBeVisible();
	await payee.getByRole("link", { name: "Print" }).click();
	await expect(payee).toHaveURL(/\/app\/payslips\/\d+\/print$/);
	const sheet = payee.getByRole("article", { name: "Payslip" });
	await expect(sheet.getByText(number, { exact: true })).toBeVisible();
	await expect(
		sheet.locator("header").getByText("Paid", { exact: true }),
	).toBeVisible();
	// The copied line names the course in the academy's language; both hold the stamp.
	await expect(sheet.getByText(new RegExp(`${stamp} — ${student}`))).toBeVisible();
	await expect(
		payee.getByRole("navigation", { name: "Main navigation" }),
	).toHaveCount(0);
	await payee.context().close();

	// 4. The paid session's attendance is locked
	await page.goto(sessionUrl);
	await expect(page.getByText("Paid in payslip")).toBeVisible();
	await expect(
		page.getByLabel(`Student attendance for ${student}`, { exact: true }),
	).toBeDisabled();
	await expect(
		page.getByRole("button", { name: "Cancel session" }),
	).toHaveCount(0);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/payroll/TeacherPayslips.test.tsx src/features/shell/nav.test.ts`

Expected: FAIL — `Failed to resolve import "./TeacherPayslips"`; the nav test lacks My payslips.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/payroll/TeacherPayslips.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Wallet } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { Money } from "@/features/billing";
import { formatMonth } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Spinner,
} from "@/ui";
import { PayslipStatusChip } from "./bits";
import { usePayslips } from "./queries";

const PAGE_SIZE = 25;

/** Spec §6 My payslips (teacher): their issued and paid payslips, as the
 * server scopes `payroll/payslips/`; each opens read-only with Print. */
export function TeacherPayslips() {
	const { t, i18n } = useTranslation();
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = usePayslips({ page });
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	return (
		<div className="flex flex-col gap-4">
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("payroll.list.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={Wallet} title={t("payroll.mine.empty")} />
					</CardContent>
				</Card>
			) : (
				<ul className="flex flex-col gap-3">
					{rows.map((payslip) => (
						<li key={payslip.id}>
							<Card>
								<CardContent className="flex flex-wrap items-center justify-between gap-3">
									<div className="flex flex-col gap-1">
										<Link
											to="/teaching/payslips/$payslipId"
											params={{ payslipId: String(payslip.id) }}
											dir="ltr"
											className="font-medium text-primary-text underline-offset-4 hover:underline"
										>
											{payslip.number}
										</Link>
										<span className="text-sm text-muted-foreground">
											{formatMonth(payslip.year, payslip.month, i18n.language)}
										</span>
									</div>
									<div className="flex flex-col items-end gap-1">
										<span className="text-sm">
											{t("payroll.columns.net")}:{" "}
											<Money
												minor={payslip.net_minor}
												currency={payslip.currency}
											/>
										</span>
										<PayslipStatusChip payslip={payslip} />
									</div>
								</CardContent>
							</Card>
						</li>
					))}
				</ul>
			)}
			<Pager page={page} pages={pages} onChange={setPage} />
		</div>
	);
}
```

Replace the whole of `dashboard/src/features/payroll/index.ts` with:

```ts
export { AdjustmentsList } from "./AdjustmentsList";
export { payrollApi, payslipsCsvUrl } from "./api";
export { hours, monthName, PayslipStatusChip } from "./bits";
export { PayslipBody } from "./PayslipBody";
export { PayslipPage } from "./PayslipPage";
export { PayslipPrint } from "./PayslipPrint";
export { PayslipsList } from "./PayslipsList";
export * from "./queries";
export { RatesPage } from "./RatesPage";
export * from "./schemas";
export { TeacherPayslips } from "./TeacherPayslips";
```

Create `dashboard/src/routes/_authed/teaching.payslips.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { TeacherPayslips } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/teaching/payslips/")({
	component: function TeachingPayslipsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.myPayslips"));
		return (
			<>
				<PageHeader title={t("nav.myPayslips")} />
				<TeacherPayslips />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/teaching.payslips.$payslipId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PayslipPage } from "@/features/payroll";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/teaching/payslips/$payslipId")({
	component: function TeachingPayslipRoute() {
		const { t } = useTranslation();
		const { payslipId } = Route.useParams();
		usePageTitle(t("payroll.payslip.title"));
		return (
			<>
				<PageHeader title={t("payroll.payslip.title")} />
				<PayslipPage payslipId={payslipId} admin={false} />
			</>
		);
	},
});
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
		requiresRole: "teacher",
	},
	// Plan 5: a student's or parent's sessions and subscriptions.
	{
```

with:

```ts
		requiresRole: "teacher",
	},
	// Plan 7: a teacher's own issued and paid payslips.
	{
		to: "/teaching/payslips",
		labelKey: "nav.myPayslips",
		icon: Wallet,
		group: "teaching",
		requiresRole: "teacher",
	},
	// Plan 5: a student's or parent's sessions and subscriptions.
	{
```

Add to `dashboard/src/locales/en/common.json`, merging each key into the existing object of the same name (English):

```json
{
	"nav": { "myPayslips": "My payslips" },
	"payroll": { "mine": { "empty": "No payslips yet." } }
}
```

Add to `dashboard/src/locales/ar/common.json`, merging each key into the existing object of the same name (Arabic):

```json
{
	"nav": { "myPayslips": "كشوف رواتبي" },
	"payroll": { "mine": { "empty": "لا توجد كشوف رواتب بعد." } }
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/payroll src/features/shell
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 616 tests (564 before Task 9); coverage lines 93.91%, branches 86.66%, functions 80.35% (gates 80/70/70).

- [ ] **Step 6: Run the whole e2e suite through Caddy, as the CI `e2e` job does**

From the meta root, with a fresh database: migrate and seed, start Django, the dashboard preview, the marketing server and the Caddy edge, then run Playwright.

```bash
cd backend
export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan_e2e CELERY_BROKER_URL=redis://localhost:56379/0 \
  DJANGO_SETTINGS_MODULE=config.settings.local DJANGO_SECRET_KEY=ci-only DJANGO_READ_DOT_ENV_FILE=False \
  DJANGO_EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend DJANGO_EMAIL_FILE_PATH=/tmp/etqan-mail \
  CELERY_TASK_ALWAYS_EAGER=true DJANGO_TENANT_URL_TEMPLATE=http://{domain}
mkdir -p /tmp/etqan-mail
.venv/bin/python manage.py migrate_schemas --shared && .venv/bin/python manage.py seed_dev
nohup .venv/bin/python manage.py runserver 127.0.0.1:8000 > /tmp/django.log 2>&1 &
cd ../dashboard
npx pnpm@10 build
nohup npx pnpm@10 preview --port 4173 --host 127.0.0.1 > /tmp/preview.log 2>&1 &
cd ../marketing
SITE_API_ORIGIN=http://127.0.0.1:8000 SITE_SCHEME=http HOST=127.0.0.1 PORT=4321 \
  nohup node dist/server/entry.mjs > /tmp/marketing.log 2>&1 &
cd ../dashboard
docker run -d --name edge --network host -v "$PWD/../caddy/Caddyfile.e2e:/etc/caddy/Caddyfile:ro" caddy:2.11.4-alpine
CI=1 E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost E2E_MAIL_DIR=/tmp/etqan-mail \
  npx pnpm@10 exec playwright test
```

(`etqan_e2e` must be an empty database: `createdb -h localhost -p 55432 -U etqan etqan_e2e`. The marketing server needs a built `marketing/dist`: `pnpm install && pnpm build` in `marketing/` once.) Expected: all 16 specs pass on the first try (`CI=1` allows one retry; a spec that passes only on the retry is a finding), `payroll.spec.ts` and `academy-sites.spec.ts` included. Afterwards stop the four servers (`docker rm -f edge`, and the Django, preview and marketing processes) and drop `etqan_e2e`.

- [ ] **Step 7: Update `STATE.md`**

Replace the "Where we are", "Next" and "Follow-ups" sections with:

```markdown
## Where we are

Plan 7 (teacher payroll, B0 milestone 7) built and in review: branch `feat/payroll` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-26-payroll-design.md`, plan
`docs/superpowers/plans/2026-09-26-plan-7-payroll.md`). New tenant app `etqan.payroll`: admins set
teachers' rates (a default and per course, in the teacher's pay currency) and bonuses and deductions,
generate a month's draft payslips from completed sessions (teacher present or not marked), issue them
once the month has ended (which freezes them and locks their sessions in scheduling), mark them paid
and export CSV; teachers see and print their own issued and paid payslips at `/app/payslips/<id>/print`.
The e2e suite covers the journey through the Caddy edge.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 8 of the roadmap. The pay rule is `payroll.services.rules.PAYS`, the amount `session_amount`,
and payslips come only from `build`; the session lock is scheduling's (`lock_sessions`,
`refuse_if_paid`). Never restate any of them. Scheduling never imports payroll or billing.

## Follow-ups (from Plans 4–7)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher, course and student pickers in list filters, forms and the Rates page cap at 100.
- Restore is allowed on any cancelled session, even inside a pause or on an ended subscription.
- A teacher's attendance controls open within a minute of the start (the list re-reads each minute), not at the exact second.
- `seed_dev` marks and reports past sessions in every academy, not only the demo one.
- A teacher or family in a far timezone sees "Today" and "This week" roll over at the academy's midnight, not their own (PM6).
- A subscription edited after its invoice keeps the invoice's amount; subscriptions created by seeds or services are not invoiced.
- A session completed after its month's payslip was issued is never paid; the admin adds a bonus (corrections are adjustments).
- Adjustments left in a currency the teacher is no longer paid in stay pending until edited (generate names them).
- Reports stay writable on a payroll-locked session (staff notes, not pay).
- Payslip notifications are Plan 8; incentives, per-student rates, fixed salary, balances and salaries as expenses are B4.
- No session or unpaid-invoice reminders yet (Plan 8, B5). No gateways, refunds or family accounts (B1, B3).
```

- [ ] **Step 8: Commit (dashboard twice, then meta) and open PRs**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(payroll): my payslips for teachers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C dashboard add e2e
git -C dashboard commit -m "test(e2e): the admin pays a teacher and the teacher prints the payslip

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C backend push -u origin feat/payroll
git -C dashboard push -u origin feat/payroll
git add STATE.md
git commit -m "chore: state for Plan 7 — payroll

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/payroll
```

Open one PR per repo: backend → `main`, dashboard → `main`, meta → `master`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Nothing merges without the user's approval. After the submodule PRs merge, bump the meta pointers (`git add backend dashboard`) to the merge commits, commit `chore: bump backend and dashboard for Plan 7 — payroll` with the trailer above, and push.

---
