# Plan 6 — Billing (Invoices & Manual Payments) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins bill families and record what they pay. A subscription is invoiced automatically when it is created or renewed, and admins can also issue invoices by hand. Payments are recorded against an invoice and its status follows from them. The admin home shows this month's revenue per currency and the overdue invoices. Parents and students see their own invoices and print an academy-branded invoice or receipt.

**Architecture:** A new tenant app, `etqan.billing` (P6-1), owns `Invoice`, `Payment` and a one-row `InvoiceCounter` per academy. Its services are split by job:
- `services/rules.py`: the one status function, the one overdue rule, the invoice read with `paid_minor`/`is_overdue` in SQL, the list filters and the invoice-row lock.
- `services/numbering.py`: invoice numbers.
- `services/payers.py`: the one payer rule.
- `services/invoices.py` and `services/payments.py`: the writes.
- `services/subscriptions.py`: automatic invoices, the delete guard and payment status.
- `services/summary.py`: the one revenue query.

Billing reads subscriptions only through `etqan.scheduling.services.lock_subscription`. Scheduling's services never import billing. Scheduling's API views call billing after scheduling, in the same transaction, and pass billing's invoice check into `delete_subscription` as a hook. The dashboard adds:
- a `features/billing` module;
- an admin Billing group (Invoices list, New invoice, Invoice page);
- Invoices under My learning for parents and students;
- a Money card on the admin home;
- a payment column and an Invoices panel on subscriptions;
- a print page on a pathless `_print` layout without the app shell.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, `Intl` for money and dates; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-25-billing-design.md` (Phase B0 milestone 6 of `2026-09-24-parity-roadmap-design.md`). It builds on:
- Plan 4, `2026-09-24-subscriptions-scheduling-design.md` (subscriptions, renew, delete, lock order), and Plan 5, `2026-09-25-sessions-attendance-design.md`, both as amended;
- Plan 3, `2026-09-24-people-catalogue-design.md` (roles, guardianship, `scope_for`, CSV);
- the academy-sites spec, `2026-09-23-academy-sites-design.md` (site branding: logo and names).

Where this plan fills a gap in the spec, the Decisions below say so.

**Verified:** the code in Tasks 1–14 was applied in order to copies of `backend@b336ae0` and `dashboard@8f7797f` (the current `main` of each). After every task, its format, lint, import-contract, type, test and coverage commands passed:
- backend: 896 → 975 tests, coverage 97.7%;
- dashboard: 498 → 543 tests, lines 93.8%, branches 85.7%, functions 79.8%.

The Task 15 suite then passed through Caddy, run the way the CI `e2e` job runs it: Django (`config.settings.local`, file email backend) and the Vite preview on a freshly migrated and seeded database, plus the marketing server on `:4321`, so every spec ran. That was 15 of 15, `academy-sites.spec.ts` included. Migrations are generated in Task 1 with `makemigrations`, so only their timestamps will differ.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`).
- The branch `feat/billing` already exists in the meta repo, `backend/` and `dashboard/`, so do not create it. Check with `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and Task 9.
- Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Backend commands**
- Run from `backend/` with the virtualenv `backend/.venv`. Export this environment once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
- Tests: `.venv/bin/pytest …`. Add `--create-db` once after Task 1, which adds migrations.
- Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`
- Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
- Watch `PLR0913`: keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`, as Plans 4–5 do.

**Dashboard commands**
- Run from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- New route files are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`.
- Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere in `src/`, `e2e/` or `scripts/`, comments included. Use semantic tokens only; the `@media print` CSS uses `var(--color-*)` too.
- `tsc` has `noUnusedLocals`/`noUnusedParameters`.

**Coverage and dev data**
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`.
- Academies: `demo` (`admin@demo.test`, timezone UTC) and `other` (`admin@other.test`).

**Tenancy and module boundaries**
- `etqan.billing` goes in `TENANT_APPS`. Migrate with `migrate_schemas`. No background job and no user-facing URL is added.
- Business logic lives in `etqan/billing/services/`. Views parse, call one service, re-read and arrange a payload. Payloads call services and never restate a rule.
- Billing reaches identity, academy and scheduling only through their `services`. Scheduling's services, models, rules, scopes, dates and tasks never import billing; only `etqan.scheduling.api` may. Other apps import only `etqan.billing.services`. `lint-imports` enforces all of this (Task 1).
- The admin-only flag is keyword-only with no default: `invoice_row(invoice, *, is_admin)`, `payment_row(payment, *, is_admin)`, and Plan 4's `subscription_row(…, *, is_admin)`.

**API and data rules**
- All routes are under `/api/v1/billing/`.
- Money is integer minor units plus an ISO 4217 currency. A payment's currency is its invoice's, and totals are never summed across currencies (P6-6).
- `issued_on`, `due_on` and `paid_on` are academy-calendar dates (`AcademySettings.timezone`). `voided_at` is UTC.
- Spec values, verbatim:
  - invoice status `unpaid · partial · paid · void`;
  - payment methods `cash · bank_transfer · instapay · vodafone_cash · western_union · zelle · venmo · cashapp · other`;
  - `auto_invoice_on_subscription` default `true`;
  - `invoice_due_days` 0–90, default 7;
  - number format `INV-000123`;
  - the description is "{course name} — {package name}".
- Errors:
  - rule refusals are `409 {"detail", "code"}` with `billing.has_payments`, `billing.invoice_void` or `billing.subscription_invoiced`;
  - field problems are `400 {"<field>": [...]}`, with overpaying a 400 on `amount_minor`;
  - out-of-scope objects are `404`;
  - a role that may not use a route gets `403`.
- Access (spec §4.6):
  - admins everything;
  - a parent reads the invoices they pay or whose student is their child;
  - a student reads their own, as the student or the payer;
  - a teacher gets nothing;
  - create, edit, void, payments, summary, payers and CSV are admin-only;
  - `billing.scopes.scope_for(user, queryset, *, via="")` is the one scoping function.
- Every write answers with a fresh read of what it changed. Views define only the methods the spec lists, so there is no PUT.
- Lists `select_related` what a row shows. The invoice list and the subscription list (with payment status) have query-count tests.

**Dashboard strings and helpers**
- Every dashboard string is in `src/locales/en/common.json` and `src/locales/ar/common.json`, with no English literal in components.
- zod messages are i18n keys rendered through `useFieldError`. 409 codes render as `errors.<code>` through `applyServerErrors`/`errorText`.
- Required fields render `*` inside the `<label>`, so tests query `getByLabelText(/^Amount/)`. Where one accessible name is a substring of another (the `Paid` tab inside `Unpaid` and `Partly paid`), match exactly.
- Screens work RTL and at phone width.
- Reuse the shared helpers: `Pager`, `clean`/`csvUrl`/`Paginated`, `applyServerErrors`/`errorText`, `useFieldError`, `formatMoney`/`toMinor`/`toMajor`, `formatDay`/`todayIn`/`addDays`, `Fact`, `Confirm`. No copies inside a feature.
- Detail pages handle a non-numeric id, a 404 and a load error with translated messages.

**Tests**
- Each assertion fails without the code under test.
- Duplicate matches are scoped (`within(row)`, `within(dialog)`).
- Cross-academy tests hold data in BOTH academies, with the other academy's pk forced above this one's (`until_pk_exceeds`). They assert the explicit 404 and that this academy's own data is still there.
- Timezone tests put the academy in a zone whose date differs from UTC's at the pinned instant, and from the student's.
- Lock-shape tests assert `FOR UPDATE` on the exact table (and the exact clause where it matters), never a bare substring.

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — Numbering.**
  - **The table:** `billing.InvoiceCounter(last_number)` holds one row, pk 1, in each academy's schema, so "per academy" comes from django-tenants.
  - **Taking a number:** `numbering.next_number()` runs `InvoiceCounter.objects.select_for_update().get_or_create(pk=1)`, adds one and saves, inside the caller's transaction. A concurrent invoice waits on that row, so no two invoices share a number. A rolled-back invoice hands its number back, so committed numbers have no gaps.
  - **The first number in an academy:** both racers miss the row. The second `INSERT` waits on the primary key, fails and re-reads the row under the lock, which is `get_or_create`'s own `IntegrityError` path.
  - **Format:** `INV-{:06d}`, which grows past six digits on its own.
  - **Where it is taken:** `invoices.issue` validates every field first and takes the number last, so a refused invoice takes none and the counter row is held briefly.
  - **Backstop:** `Invoice.number` is unique.
- **D2 — Where the subscription-delete invoice check lives.** It is a required keyword-only hook: `delete_subscription(subscription, *, before_delete: Callable[[int], None])`.
  - **How it runs:** scheduling calls it with the id right after it locks the subscription row, before its own checks and the session lock.
  - **Who passes what:** the API view passes `billing_services.refuse_if_invoiced`, and tests pass a no-op.
  - **Why not the view:** a check made there, before the lock, could miss a manual invoice written in between.
  - **Why required:** a caller cannot forget to decide.
  - **The other half:** an invoice that names a subscription takes the same row lock through `scheduling_services.lock_subscription(pk)`, so a delete and an invoice for one subscription never interleave.
  - **What stays:** a void invoice does not block deletion, and it keeps the deleted subscription's id (spec §4.3).
- **D3 — The payer rule.**
  - **The ordered list:** the new `identity_services.guardians_by_link(student_user_id)` lists the student's guardians by `Guardianship.created_at, id`. It is not `guardians_of`, which sorts by name.
  - **The choices:** `billing.services.payer_choices(student_user_id)` is those guardians followed by the student.
  - **The rule:** the default payer is its first entry; a payer is valid exactly when listed there, checked by `resolve_payer`, which gives a 400 on `payer` otherwise.
  - **The dashboard:** the form gets the same list from a new admin route, `GET /api/v1/billing/payers/?student=<user id>` → `{default, choices: [{id, full_name, relation}]}`. The spec's form needs it and its route table lacks it.
- **D4 — Payload shapes.**
  - **Invoice row:** `id, number, status, is_overdue, student {id, full_name}, payer {id, full_name}, subscription_id, description, amount_minor, paid_minor, balance_minor, currency, issued_on, due_on, voided_at, created_at`, plus admin-only `notes` and `created_by {id, full_name} | null`.
  - **Invoice detail:** the row plus `payments`.
  - **Payment row:** `id, invoice_id, amount_minor, method, paid_on, reference, created_at`, plus admin-only `notes` and `recorded_by`.
  - **What each write returns:** creating an invoice answers `201` with the detail; PATCH and void answer `200` with it; recording a payment answers `201` with the invoice's detail, so the new status arrives with it; deleting a payment answers `204`.
  - **Summary:** `{revenue_this_month: [{currency, amount_minor}], overdue: [{currency, count, balance_minor}]}`, each list in currency order.
  - **Subscriptions:** admins' rows and details gain `payment_status` (`none · unpaid · partial · paid`) and `payment_overdue`.
  - **Not shown:** `voided_by` is stored, not shown.
- **D5 — The description's language.**
  - **Automatic invoices:** `AcademySettings.default_language` at the moment of issue, "{course} — {package}" from the subscription's course and package names in that language. The text is stored and never re-translated.
  - **The manual form:** choosing a subscription pre-fills the description in the admin's reading language, and the admin may edit it.
- **D6 — Payment status in lists.** `payment_statuses(subscription_ids)` is one grouped query over the non-void invoices of those ids, counting `invoices`, `paid`, `paid_into` (partial or paid) and `overdue` per subscription.
  - **The mapping:** none → `none`; all paid → `paid`; any paid into → `partial`; else `unpaid`; `overdue` when any is.
  - **Why counting statuses is enough:** the stored status always follows the payments (one status function, run in the transaction that changes them).
  - **Who pays for it:** the subscription payloads call it once per page, for admins only.
- **D7 — Time: overdue and the revenue month.**
  - **The clock:** billing reads `etqan.billing.clock.now()` and `today()`, the academy's calendar date from `AcademySettings.timezone`. Tests pin it together with scheduling's clock.
  - **Overdue:** `rules.overdue(today)` is the one `Q` (status unpaid or partial, `due_on < today`). It is used by the list's `is_overdue` annotation, the `overdue` filter, the summary and payment status.
  - **The month:** "this month" is `[first day of today's month, first day of the next)` on that calendar. `paid_on` is a date, so no instant is converted.
  - **The one revenue query:** `summary.revenue_this_month()` sums per currency.
- **D8 — Lock order.** Plans 4 and 5 lock a subscription before its sessions, and Plan 6 keeps that order.
  - **Writing an invoice:** it locks the subscription it names (if any), then the counter row, then inserts. Renew locks the old subscription and creates the new one first.
  - **Invoice writes:** pay, delete a payment, void and edit lock only that invoice's row (`SELECT … FOR UPDATE`) and decide on the fresh row.
  - **Deleting a subscription:** it locks the subscription, runs the invoice check (a plain `EXISTS`, no lock), then locks its sessions in id order.
  - **Why this cannot deadlock:** no path locks an invoice and then a subscription, and none holds the counter while waiting for a subscription.
- **D9 — Fresh sums after the lock.** The invoice row is locked in its own statement, and the payments are summed in the next one (`rules.paid_of`).
  - **Why:** under READ COMMITTED each statement takes a new snapshot, so a payment committed while this request waited for the lock is counted.
  - **The trap avoided:** a sum inside the locking `SELECT` would read the snapshot from before the wait and could let two admins overpay together.
- **D10 — The print page.**
  - **The route:** the pathless layout `src/routes/_print.tsx` (`requireAuth`, renders `<Outlet />` only, no `AppShell`) holds `src/routes/_print/invoices.$invoiceId.print.tsx`, so the page lives at `/app/invoices/<id>/print`.
  - **Who may open it:** anyone signed in. The server already scopes `billing/invoices/<id>/`, so a teacher or a stranger sees "Couldn't load" or "couldn't be found".
  - **What it shows:** the academy's name and logo from `site/branding/` (`useBrandName`, `useBranding`), the title "Receipt" once paid and "Invoice" otherwise, the number, the status, the payer, the student, the dates, the description, the payments and the balance due.
  - **Direction:** `dir={i18n.dir()}`.
  - **Styles:** `@media print` in `index.css` sets A4, uses tokens only, and drops the sheet's frame. `print:hidden` hides the Print button.
  - **Palette:** paper is white, so while it is open the page removes the `dark` class from `<html>` and restores it on leaving. The stored theme is untouched.
- **D11 — Navigation and pages.**
  - **Admins:** a new `billing` nav group after Scheduling with Invoices (`/billing/invoices`, `?status=overdue` opens that tab), New invoice (`/billing/invoices/new`) and the invoice page (`/billing/invoices/$invoiceId`), under `requireAdmin`.
  - **Students and parents:** the `learning` group gains Invoices (`/learning/invoices`, `/learning/invoices/$invoiceId`), which are read-only with Print.
  - **The admin home:** it gains a Money card with revenue per currency, the overdue count and balance, and a link to the overdue tab.
  - **Subscriptions:** the list gains a Payment column. The detail gains an Invoices panel that the route passes in as a render prop, so the scheduling feature never imports billing. The panel is a list, not a table, so Plan 4's e2e `getByRole("table")` on that page stays unique.
- **D12 — CSV columns.**
  - **Invoices:** Number, Student, Payer, Description, Amount (minor units), Paid (minor units), Balance (minor units), Currency, Issued on, Due on, Status, Overdue (yes/no).
  - **Subscriptions:** the CSV gains a last column, Payment status.
- **D13 — Permissions.** `READERS = IsAdmin | (ReadOnly & (IsParent | IsStudent))` guards the invoice list, the invoice detail and its payments list; every other billing route is `IsAdmin`.
  - **Teachers:** they get `403` everywhere (spec: "none").
  - **What a parent keeps:** a parent who pays an invoice keeps seeing it even after being unlinked from the child, because "invoices they pay" (spec §4.6).
- **D14 — Edit and void refusals.**
  - **409 `billing.invoice_void`:** voiding twice, paying a void invoice, and editing any field of a void invoice.
  - **409 `billing.has_payments`:** changing the amount once paid into, and voiding with payments.
  - **400 on `amount_minor`:** paying more than the balance, which includes any payment on a paid invoice.
  - **Not restricted:** `paid_on` (a backdated or future-dated transfer is the admin's call).
- **D15 — Seeds.** The seeds create subscriptions through the service, which never invoices (only the API does, P6-1). So `seed_billing()` backfills with `invoice_subscription(pk, by=None, issued_on=sub.starts_on)`.
  - **What each seeded subscription gets:** the demo academy's four become paid in full, partly paid (a third), unpaid and overdue (the one that started 17 days ago), and void. The other academy's one stays unpaid.
  - **Idempotent and quiet:** it runs only when the academy has no invoice, prints `skip:` for an item a rule refuses and carries on, and sends nothing.
- **D16 — Shared UI.** `Fact` (a labelled value in a `<dl>`) and `Confirm` (a destructive action behind an alert dialog) move from scheduling's private copies into `src/components/`, and scheduling uses them. `addDays(day, n)` joins `@/lib/zoned-time`.

## Review Focus

- **Money status drifting from the payments.** Adding, deleting and voiding in any order must leave `status`, `paid_minor` and `balance_minor` consistent. A voided invoice must refuse payments even when the caller holds a stale copy. Tests:
  - Task 3: `test_status_follows_every_payment_added_and_deleted`, `test_void_needs_no_payments_and_is_final`, `test_a_stale_copy_never_pays_a_voided_invoice`, `test_editing_keeps_the_amount_once_paid_into`;
  - Task 11: `InvoicePage` "offers nothing to change on a void invoice".
- **Two admins at once: numbers and overpayment.** Concurrent invoices must never share a number. Two payments racing on one invoice must never together pass the amount, so each write locks the invoice row and sums after the lock. Tests:
  - Task 2: `test_numbering_locks_the_academys_counter_row`;
  - Task 3: `test_every_write_locks_the_invoice_row_first`, `test_overpaying_is_refused_on_the_amount`;
  - Task 4: `test_an_invoice_locks_its_subscription_before_the_counter`.
- **An automatic invoice failing half-way.** If billing fails after scheduling created or renewed a subscription, nothing of either may remain. An invoiced subscription must not be deleted from under its invoice. Tests:
  - Task 7: `test_a_billing_failure_rolls_the_new_subscription_back`, `test_a_billing_failure_rolls_the_renewal_back`, `test_an_invoiced_subscription_is_deleted_only_after_voiding`;
  - Task 4: `test_the_invoice_check_runs_between_the_subscription_and_session_locks`.
- **A parent reading another family's invoices.** Parents and students must see exactly their family's invoices and payments (and print them), never another family's or another academy's, and never staff notes. Tests:
  - Task 6: `test_parents_and_students_read_their_family_only`, `test_every_role_on_every_route`, `test_another_academy_never_leaks`;
  - Task 10: `the print route` "prints a parent's invoice without the app shell".
- **Revenue across currencies and month boundaries.** "This month" must be the academy's month, even when UTC is still in the previous one. Each currency must stay apart, and overdue balances must count partial payments. Tests:
  - Task 5: `test_revenue_is_this_academy_month_per_currency`, `test_overdue_counts_and_balances_per_currency`;
  - Task 13: `BillingSummaryCard` "shows each currency's revenue apart…".

---

## File Structure

```
backend/
  config/settings/base.py            TENANT_APPS += etqan.billing
  config/api_router.py               billing/ → etqan.billing.api.urls
  pyproject.toml                     import-linter contracts for billing
  etqan/academy/                     auto_invoice_on_subscription, invoice_due_days (+ migration 0005, API, tests)
  etqan/identity/services.py         guardians_by_link (+ test)
  etqan/billing/                     NEW app
    apps.py models.py                InvoiceCounter, Invoice, Payment (+ migrations/0001_initial.py)
    clock.py                         now(), today() on the academy's calendar
    scopes.py                        scope_for(user, queryset, *, via="")
    services/__init__.py             the public API
    services/rules.py                status_for, overdue, paid_of, lock, check/save, refuse_if_void,
                                     refuse_if_paid_into, invoices_queryset, filter_invoices, has_invoices
    services/numbering.py            next_number
    services/payers.py               student_of, payer_choices, resolve_payer
    services/invoices.py             issue, create_invoice, update_invoice, void_invoice
    services/payments.py             add_payment, delete_payment
    services/subscriptions.py        invoice_subscription, refuse_if_invoiced, PaymentStatus, payment_statuses
    services/summary.py              revenue_this_month, overdue_by_currency, summary
    api/serializers.py payloads.py views.py urls.py
    tests/conftest.py                Clock (both clocks), world, subscribe, admin, make_parent
    tests/test_models.py test_rules.py test_invoices.py test_subscriptions.py test_summary.py
    tests/test_api.py test_subscription_api.py
  etqan/scheduling/
    services/subscriptions.py        lock_subscription; delete_subscription(…, *, before_delete)
    api/views.py                     create/renew invoice in one transaction; delete passes the guard; CSV column
    api/payloads.py                  subscription_row(sub, values, payment, *, is_admin): payment_status/overdue
    tests/test_actions.py            call sites pass before_delete; hook and lock tests
    tests/test_api_subscriptions.py  renewal is invoiced: void before delete
  etqan/tenants/management/commands/seed_dev.py   INVOICES, seed_billing (+ tests/test_seed_dev.py)
dashboard/
  src/components/Fact.tsx Confirm.tsx               shared (scheduling's copies removed)
  src/lib/zoned-time.ts                             addDays
  src/features/academy/                             the invoice switch and due days
  src/features/billing/
    schemas api queries bits index                  types, calls, hooks, InvoiceStatusChip, Money
    InvoicePrint                                    print page
    InvoicePage EditInvoiceDialog PaymentDialog     invoice page (admin and family)
    InvoicesList InvoiceForm                        admin list and new invoice
    FamilyInvoices BillingSummaryCard               family list, admin home card
    SubscriptionInvoices                            subscription page panel
  src/features/scheduling/                          PaymentStatusChip, payment fields, useSubscriptions(…, {enabled}),
                                                    SubscriptionsList column, SubscriptionDetail `invoices` slot
  src/features/shell/nav.ts                         billing group, learning Invoices
  src/routes/_print.tsx, _print/invoices.$invoiceId.print.tsx
  src/routes/_authed/billing{,.index,.invoices.index,.invoices.new,.invoices.$invoiceId}.tsx,
                     learning.invoices.{index,$invoiceId}.tsx, index.tsx (Money card),
                     scheduling.subscriptions.$subscriptionId.tsx (Invoices panel)
  src/test/billing-fixtures.ts, scheduling-fixtures.ts
  src/locales/{en,ar}/common.json
  e2e/billing.spec.ts, fixtures.ts (acceptInvite, INVITE shared), sessions.spec.ts, people-catalogue.spec.ts
meta: STATE.md, submodule pointers
```

---


### Task 1: Data: the billing app, its models, the academy's invoice settings and the import contracts

**Files:**
- Create (generated): `backend/etqan/academy/migrations/0005_billing_settings.py`, `backend/etqan/billing/migrations/__init__.py`, `backend/etqan/billing/migrations/0001_initial.py`
- Create: `backend/etqan/billing/__init__.py`, `backend/etqan/billing/api/__init__.py`, `backend/etqan/billing/apps.py`, `backend/etqan/billing/models.py`
- Modify: `backend/config/settings/base.py`, `backend/etqan/academy/api/serializers.py`, `backend/etqan/academy/models.py`, `backend/etqan/academy/services.py`, `backend/pyproject.toml`
- Test: `backend/etqan/academy/tests/test_api.py`, `backend/etqan/academy/tests/test_services.py`, `backend/etqan/billing/tests/__init__.py` (new), `backend/etqan/billing/tests/test_models.py` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: tenant app `etqan.billing` (label `billing`) in `TENANT_APPS`, with models:
  - `InvoiceCounter(last_number)`;
  - `Invoice(number unique, payer → User PROTECT, student → identity.StudentProfile PROTECT, subscription_id: BigInteger null, description, amount_minor > 0, currency, issued_on, due_on ≥ issued_on, status: Invoice.Status unpaid/partial/paid/void, notes, created_by/voided_by → User SET_NULL, voided_at, created_at, updated_at)`, ordered `-id`;
  - `Payment(invoice → Invoice PROTECT related_name="payments", amount_minor > 0, method: Payment.Method, paid_on, reference ≤ 120, notes, recorded_by → User SET_NULL, created_at)`, ordered `paid_on, id`.
- Produces: `AcademySettings.auto_invoice_on_subscription` (default `True`) and `.invoice_due_days` (0–90, default 7); `academy_services.update_settings(..., auto_invoice_on_subscription: bool | None = None, invoice_due_days: int | None = None)` (400 on `invoice_due_days` outside 0–90); `GET/PATCH /api/v1/academy/settings/` carries both.
- Produces: import-linter contracts:
  - scheduling's core never imports billing;
  - billing reaches other apps only through their services;
  - other apps (scheduling included) reach billing only through `etqan.billing.services`;
  - platform and academy import no billing.

- [ ] **Step 1: Write the failing tests**

Append to the end of `backend/etqan/academy/tests/test_api.py`:

```python
def test_admin_sets_the_billing_settings(api_for):
    admin = api_for("admin")
    body = admin.get(URL).json()
    assert (body["auto_invoice_on_subscription"], body["invoice_due_days"]) == (
        True,
        7,
    )
    resp = admin.patch(
        URL,
        {"auto_invoice_on_subscription": False, "invoice_due_days": 30},
        format="json",
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert (body["auto_invoice_on_subscription"], body["invoice_due_days"]) == (
        False,
        30,
    )
    assert admin.get(URL).json()["invoice_due_days"] == 30


@pytest.mark.parametrize("value", [-1, 91, "soon"])
def test_due_days_are_0_to_90(api_for, value):
    resp = api_for("admin").patch(URL, {"invoice_due_days": value}, format="json")
    assert resp.status_code == 400
    assert "invoice_due_days" in resp.json()
```

Append to the end of `backend/etqan/academy/tests/test_services.py`:

```python
def test_billing_settings_default_update_and_bounds():
    s = services.get_settings()
    assert (s.auto_invoice_on_subscription, s.invoice_due_days) == (True, 7)
    s = services.update_settings(auto_invoice_on_subscription=False, invoice_due_days=0)
    s.refresh_from_db()
    assert (s.auto_invoice_on_subscription, s.invoice_due_days) == (False, 0)
    s = services.update_settings(invoice_due_days=90)
    s.refresh_from_db()
    # Leaving the switch out leaves it alone.
    assert (s.auto_invoice_on_subscription, s.invoice_due_days) == (False, 90)
    for value in (-1, 91):
        with pytest.raises(ValidationError) as exc:
            services.update_settings(invoice_due_days=value)
        assert exc.value.field == "invoice_due_days"
```

Create `backend/etqan/billing/tests/__init__.py`:

```python

```

Create `backend/etqan/billing/tests/test_models.py`:

```python
from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.identity import services as identity_services


@pytest.fixture
def student():
    return identity_services.create_person("student", full_name="Yusuf")


def invoice(student, **overrides):
    fields = {
        "number": "INV-000001",
        "payer": student,
        "student": student.student_profile,
        "description": "Tajweed — Monthly",
        "amount_minor": 150000,
        "currency": "EGP",
        "issued_on": date(2026, 6, 1),
        "due_on": date(2026, 6, 8),
        **overrides,
    }
    return Invoice.objects.create(**fields)


@pytest.mark.parametrize(
    "overrides",
    [
        {"amount_minor": 0},
        {"amount_minor": -5},
        {"due_on": date(2026, 5, 31)},
    ],
)
def test_the_database_refuses_a_bad_invoice(student, overrides):
    with pytest.raises(IntegrityError), transaction.atomic():
        invoice(student, **overrides)


def test_invoice_numbers_are_unique(student):
    invoice(student)
    with pytest.raises(IntegrityError), transaction.atomic():
        invoice(student)


def test_the_database_refuses_a_payment_of_nothing(student):
    inv = invoice(student)
    with pytest.raises(IntegrityError), transaction.atomic():
        Payment.objects.create(
            invoice=inv, amount_minor=0, method="cash", paid_on=date(2026, 6, 2)
        )
    assert str(inv) == "Invoice<INV-000001, unpaid>"
```

- [ ] **Step 2: Run them to verify they fail**

Every backend command runs from `backend/` with the environment from Global Constraints exported once per shell.

Run (from `backend/`): `.venv/bin/pytest -q etqan/academy`
Expected: FAIL — `update_settings() got an unexpected keyword argument 'auto_invoice_on_subscription'`, and the settings API has no `auto_invoice_on_subscription` (`KeyError`).

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing`
Expected: FAIL — collection stops at `ModuleNotFoundError: No module named 'etqan.billing.models'`.

- [ ] **Step 3: Implement**

In `backend/config/settings/base.py`, replace:

```python
    "etqan.academy",
    "etqan.catalogue",
    "etqan.scheduling",
]
INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
TENANT_MODEL = "tenants.Academy"
```

with:

```python
    "etqan.academy",
    "etqan.catalogue",
    "etqan.scheduling",
    "etqan.billing",
]
INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
TENANT_MODEL = "tenants.Academy"
```

In `backend/etqan/academy/api/serializers.py`, replace:

```python
    )
    absent_consumes_session = serializers.BooleanField(required=False)
    excused_consumes_session = serializers.BooleanField(required=False)
    updated_at = serializers.DateTimeField(read_only=True)
```

with:

```python
    )
    absent_consumes_session = serializers.BooleanField(required=False)
    excused_consumes_session = serializers.BooleanField(required=False)
    auto_invoice_on_subscription = serializers.BooleanField(required=False)
    invoice_due_days = serializers.IntegerField(
        min_value=0, max_value=90, required=False
    )
    updated_at = serializers.DateTimeField(read_only=True)
```

In `backend/etqan/academy/models.py`, replace:

```python
    # uses up one of the package's sessions. Read live by the one counting rule.
    absent_consumes_session = models.BooleanField(default=True)
    excused_consumes_session = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

```

with:

```python
    # uses up one of the package's sessions. Read live by the one counting rule.
    absent_consumes_session = models.BooleanField(default=True)
    excused_consumes_session = models.BooleanField(default=False)
    # Plan 6 (spec §3.1): an invoice for every new or renewed subscription, due
    # this many days after it is issued.
    auto_invoice_on_subscription = models.BooleanField(default=True)
    invoice_due_days = models.PositiveSmallIntegerField(
        default=7, validators=[MinValueValidator(0), MaxValueValidator(90)]
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

```

In `backend/etqan/academy/services.py`, replace:

```python

HORIZON_DAYS = (1, 60)
GRACE_DAYS = (0, 60)


def _days(value: int, bounds: tuple[int, int], field: str) -> int:
```

with:

```python

HORIZON_DAYS = (1, 60)
GRACE_DAYS = (0, 60)
DUE_DAYS = (0, 90)


def _days(value: int, bounds: tuple[int, int], field: str) -> int:
```

In `backend/etqan/academy/services.py`, replace:

```python
    renewal_grace_days: int | None = None,
    absent_consumes_session: bool | None = None,
    excused_consumes_session: bool | None = None,
) -> AcademySettings:
    settings_row = get_settings()
    if timezone is not None:
```

with:

```python
    renewal_grace_days: int | None = None,
    absent_consumes_session: bool | None = None,
    excused_consumes_session: bool | None = None,
    auto_invoice_on_subscription: bool | None = None,
    invoice_due_days: int | None = None,
) -> AcademySettings:
    settings_row = get_settings()
    if timezone is not None:
```

In `backend/etqan/academy/services.py`, replace:

```python
        settings_row.absent_consumes_session = absent_consumes_session
    if excused_consumes_session is not None:
        settings_row.excused_consumes_session = excused_consumes_session
    settings_row.save()
    return settings_row
```

with:

```python
        settings_row.absent_consumes_session = absent_consumes_session
    if excused_consumes_session is not None:
        settings_row.excused_consumes_session = excused_consumes_session
    if auto_invoice_on_subscription is not None:
        settings_row.auto_invoice_on_subscription = auto_invoice_on_subscription
    if invoice_due_days is not None:
        settings_row.invoice_due_days = _days(
            invoice_due_days, DUE_DAYS, "invoice_due_days"
        )
    settings_row.save()
    return settings_row
```

Create `backend/etqan/billing/__init__.py`:

```python

```

Create `backend/etqan/billing/api/__init__.py`:

```python

```

Create `backend/etqan/billing/apps.py`:

```python
from django.apps import AppConfig


class BillingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.billing"
    label = "billing"
```

Create `backend/etqan/billing/models.py`:

```python
"""Invoices, the payments recorded against them, and invoice numbering (P6-1).

Other apps' models are referenced by string: billing never imports them. A
subscription is a plain id, validated through scheduling's services. Business
rules live in `etqan.billing.services`.
"""

from django.conf import settings
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import F
from django.db.models import Q

CURRENCY = RegexValidator(r"^[A-Z]{3}$")


class InvoiceCounter(models.Model):
    """The last invoice number handed out. One row (pk 1) in each academy's
    schema, locked while a number is taken (plan D1)."""

    last_number = models.PositiveIntegerField(default=0)

    def __str__(self):
        return f"InvoiceCounter<{self.last_number}>"


class Invoice(models.Model):
    class Status(models.TextChoices):
        UNPAID = "unpaid", "Unpaid"
        PARTIAL = "partial", "Partly paid"
        PAID = "paid", "Paid"
        VOID = "void", "Void"

    number = models.CharField(max_length=20, unique=True)
    # PROTECT: people are deactivated, never deleted.
    payer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    # A plain id, not a foreign key (P6-1): billing never imports scheduling's
    # models, and scheduling refuses to delete a subscription with a non-void
    # invoice (spec §4.3).
    subscription_id = models.BigIntegerField(null=True, blank=True, db_index=True)
    description = models.TextField()
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    currency = models.CharField(max_length=3, validators=[CURRENCY])
    issued_on = models.DateField()  # the academy's calendar
    due_on = models.DateField()  # the academy's calendar
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.UNPAID
    )
    notes = models.TextField(blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    voided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    voided_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0), name="billing_invoice_amount_positive"
            ),
            models.CheckConstraint(
                condition=Q(due_on__gte=F("issued_on")),
                name="billing_invoice_due_after_issue",
            ),
        ]
        indexes = [models.Index(fields=["status", "due_on"])]

    def __str__(self):
        return f"Invoice<{self.number}, {self.status}>"


class Payment(models.Model):
    class Method(models.TextChoices):
        # TutorHamster's manual options (P6-3).
        CASH = "cash", "Cash"
        BANK_TRANSFER = "bank_transfer", "Bank transfer"
        INSTAPAY = "instapay", "InstaPay"
        VODAFONE_CASH = "vodafone_cash", "Vodafone Cash"
        WESTERN_UNION = "western_union", "Western Union"
        ZELLE = "zelle", "Zelle"
        VENMO = "venmo", "Venmo"
        CASHAPP = "cashapp", "Cash App"
        OTHER = "other", "Other"

    invoice = models.ForeignKey(
        Invoice, on_delete=models.PROTECT, related_name="payments"
    )
    amount_minor = models.BigIntegerField(validators=[MinValueValidator(1)])
    method = models.CharField(max_length=16, choices=Method.choices)
    paid_on = models.DateField()
    reference = models.CharField(max_length=120, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["paid_on", "id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(amount_minor__gt=0), name="billing_payment_amount_positive"
            )
        ]
        indexes = [models.Index(fields=["paid_on"])]

    def __str__(self):
        return f"Payment<{self.invoice_id}, {self.amount_minor}>"
```

In `backend/pyproject.toml`, replace:

```toml
name = "platform imports no business modules"
type = "forbidden"
source_modules = ["etqan.platform"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling"]

[[tool.importlinter.contracts]]
name = "identity does not import tenants"
```

with:

```toml
name = "platform imports no business modules"
type = "forbidden"
source_modules = ["etqan.platform"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing"]

[[tool.importlinter.contracts]]
name = "identity does not import tenants"
```

In `backend/pyproject.toml`, replace:

```toml
name = "academy imports no other business module"
type = "forbidden"
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling"]

[[tool.importlinter.contracts]]
name = "catalogue reaches identity only through its services"
```

with:

```toml
name = "academy imports no other business module"
type = "forbidden"
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling", "etqan.billing"]

[[tool.importlinter.contracts]]
name = "catalogue reaches identity only through its services"
```

In `backend/pyproject.toml`, replace:

```toml
# scheduling.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "other apps reach scheduling only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
    "etqan.scheduling.scopes", "etqan.scheduling.tasks",
]
allow_indirect_imports = true
```

with:

```toml
# scheduling.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "scheduling's core never imports billing"
type = "forbidden"
# P6-1: only scheduling's API views call billing (after scheduling, in the
# same request transaction); the services, models and rules never do, not
# even indirectly.
source_modules = [
    "etqan.scheduling.services", "etqan.scheduling.models", "etqan.scheduling.scopes",
    "etqan.scheduling.dates", "etqan.scheduling.tasks",
]
forbidden_modules = ["etqan.billing"]

[[tool.importlinter.contracts]]
name = "other apps reach scheduling only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.billing"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
    "etqan.scheduling.scopes", "etqan.scheduling.tasks",
]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "billing reaches other apps only through their services"
type = "forbidden"
source_modules = ["etqan.billing"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue",
    "etqan.academy.models", "etqan.academy.api",
    "etqan.tenants", "etqan.site",
]
# billing.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "other apps reach billing only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling"]
forbidden_modules = ["etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock"]
allow_indirect_imports = true
```

- [ ] **Step 4: Generate the migrations**

Run (from `backend/`): `.venv/bin/python manage.py makemigrations academy --name billing_settings --settings=config.settings.test`
Expected: `etqan/academy/migrations/0005_billing_settings.py` adding `auto_invoice_on_subscription` and `invoice_due_days`.

Run (from `backend/`): `.venv/bin/python manage.py makemigrations billing --settings=config.settings.test`
Expected: `etqan/billing/migrations/0001_initial.py` with `+ Create model InvoiceCounter`, `+ Create model Invoice`, `+ Create model Payment`, the `status, due_on` and `paid_on` indexes and the three check constraints.

Then create the empty `backend/etqan/billing/migrations/__init__.py` if `makemigrations` did not (it does when the folder is new).

- [ ] **Step 5: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q --create-db etqan/academy etqan/billing`
Expected: PASS. `--create-db` because of the new migrations.

- [ ] **Step 6: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 7: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(billing): billing app, invoice settings and import contracts

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rules: the one status function, overdue, numbering and the payer rule

**Files:**
- Create: `backend/etqan/billing/clock.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/numbering.py`, `backend/etqan/billing/services/payers.py`, `backend/etqan/billing/services/rules.py`
- Modify: `backend/etqan/identity/services.py`
- Test: `backend/etqan/billing/tests/conftest.py` (new), `backend/etqan/billing/tests/test_rules.py` (new), `backend/etqan/identity/tests/test_people_services.py`

**Interfaces:**
- Consumes: Task 1's models.
- Produces (re-exported from `etqan.billing.services`):
  - `status_for(amount_minor: int, paid_minor: int) -> str`, the one status function (spec §4.1);
  - `overdue(today: date, *, via: str = "") -> Q`, the one overdue rule (D7);
  - `invoices_queryset() -> QuerySet[Invoice]`, with `payer`, `student__user`, `created_by` joined and `paid_minor` and `is_overdue` annotated in SQL;
  - `next_number() -> str` (D1; call inside a transaction);
  - `payer_choices(student_user_id: int) -> list[User]` (guardians by link, then the student);
  - `resolve_payer(student_user_id: int, payer_id: int | None) -> User` (default when None; `ValidationError(field="payer")` otherwise).
- Produces: `etqan.billing.clock.now() -> datetime` and `today() -> date` (the academy's calendar); `rules.paid_of(invoice) -> int`; constants `rules.UNPAID/PARTIAL/PAID/VOID/OPEN`.
- Produces: `identity_services.guardians_by_link(student_user_id: int) -> list[User]`.
- Produces (tests): `etqan.billing.tests.conftest` with `Clock` (pins scheduling's and billing's clocks to Monday 1 June 2026 08:00 UTC), fixtures `clock`, `world`, `subscribe`, `admin`, and `make_parent(name, *children) -> User`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/conftest.py`:

```python
"""Billing fixtures. Both clocks are pinned: scheduling's (sessions) and
billing's (invoice dates), to Monday 1 June 2026, 08:00 UTC."""

import pytest

from etqan.billing import clock as billing_clock
from etqan.identity import services as identity_services
from etqan.scheduling.tests.conftest import Clock as SchedulingClock
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for


class Clock(SchedulingClock):
    def set(self, when) -> None:
        super().set(when)
        self._monkeypatch.setattr(billing_clock, "now", lambda: when)


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


@pytest.fixture
def world(clock):
    """Scheduling's world: student Yusuf (Asia/Riyadh), teacher Bilal, course
    Tajweed and the Monthly package at 150000 EGP."""
    return build_world()


@pytest.fixture
def subscribe(world):
    return lambda **overrides: subscription_for(world, **overrides)


@pytest.fixture
def admin():
    return make_admin()


def make_parent(name, *children):
    parent = identity_services.create_person("parent", full_name=name)
    for child in children:
        identity_services.link_guardian(parent, child)
    return parent
```

Create `backend/etqan/billing/tests/test_rules.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.billing import services
from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.billing.tests.conftest import make_parent
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_student


@pytest.mark.parametrize(
    ("amount", "paid", "status"),
    [
        (1000, 0, "unpaid"),
        (1000, 1, "partial"),
        (1000, 999, "partial"),
        (1000, 1000, "paid"),
    ],
)
def test_the_one_status_function(amount, paid, status):
    assert services.status_for(amount, paid) == status


def test_numbers_are_handed_out_in_sequence():
    numbers = [services.next_number() for _ in range(3)]
    assert numbers == ["INV-000001", "INV-000002", "INV-000003"]


def test_numbering_locks_the_academys_counter_row():
    with CaptureQueriesContext(connection) as ctx:
        services.next_number()
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    # One lock, on the counter table: a concurrent invoice waits for it.
    assert [sql.split(" FROM ")[1].split()[0] for sql in locks] == [
        '"billing_invoicecounter"'
    ]


def raw_invoice(student, **overrides) -> Invoice:
    """An invoice written straight to the table, for the read rules."""
    fields = {
        "number": services.next_number(),
        "payer": student,
        "student": student.student_profile,
        "description": "Tajweed — Monthly",
        "amount_minor": 1000,
        "currency": "EGP",
        "issued_on": date(2026, 6, 1),
        "due_on": date(2026, 6, 8),
        **overrides,
    }
    return Invoice.objects.create(**fields)


def test_paid_is_summed_without_multiplying_rows(clock):
    student = make_student()
    invoice = raw_invoice(student, status="partial")
    for amount in (300, 200):
        Payment.objects.create(
            invoice=invoice,
            amount_minor=amount,
            method="cash",
            paid_on=date(2026, 6, 2),
        )
    raw_invoice(student)
    rows = list(services.invoices_queryset().order_by("id"))
    assert [(row.pk, row.paid_minor) for row in rows] == [
        (invoice.pk, 500),
        (rows[1].pk, 0),
    ]


def test_overdue_is_the_academys_today(clock):
    # 16:00 UTC on 8 June is already 9 June in Tokyo (and still 8 June in
    # the student's Riyadh and in UTC): due on the 8th is overdue there.
    academy_services.update_settings(timezone="Asia/Tokyo")
    clock.set(datetime(2026, 6, 8, 16, 0, tzinfo=UTC))
    student = make_student(timezone="Asia/Riyadh")
    due = {
        status: raw_invoice(student, status=status)
        for status in ("unpaid", "partial", "paid", "void")
    }
    later = raw_invoice(student, due_on=date(2026, 6, 9))
    overdue = {row.pk: row.is_overdue for row in services.invoices_queryset()}
    assert overdue == {
        due["unpaid"].pk: True,
        due["partial"].pk: True,
        due["paid"].pk: False,
        due["void"].pk: False,
        later.pk: False,
    }
    academy_services.update_settings(timezone="UTC")
    assert not any(row.is_overdue for row in services.invoices_queryset())


def test_the_payer_defaults_to_the_earliest_guardian(clock):
    student = make_student()
    assert [p.pk for p in services.payer_choices(student.pk)] == [student.pk]
    assert services.resolve_payer(student.pk, None) == student
    zainab = make_parent("Zainab", student)
    adam = make_parent("Adam", student)
    assert [p.pk for p in services.payer_choices(student.pk)] == [
        zainab.pk,
        adam.pk,
        student.pk,
    ]
    assert services.resolve_payer(student.pk, None) == zainab
    assert services.resolve_payer(student.pk, adam.pk) == adam
    assert services.resolve_payer(student.pk, student.pk) == student


def test_a_payer_outside_the_family_is_refused(clock):
    student = make_student()
    stranger = make_parent("Stranger", make_student("Other child"))
    teacher = identity_services.create_person(
        "teacher", full_name="Bilal", profile={"gender": "male"}
    )
    for payer in (stranger, teacher):
        with pytest.raises(ValidationError) as exc:
            services.resolve_payer(student.pk, payer.pk)
        assert exc.value.field == "payer"
```

In `backend/etqan/identity/tests/test_people_services.py`, replace:

```python
        with pytest.raises(ValidationError):
            services.link_guardian(kid, kid)


class TestLookups:
    def test_get_person_is_role_scoped(self):
```

with:

```python
        with pytest.raises(ValidationError):
            services.link_guardian(kid, kid)

    def test_guardians_by_link_puts_the_earliest_link_first(self):
        kid = student()
        zainab = services.create_person("parent", full_name="Zainab", profile={})
        adam = services.create_person("parent", full_name="Adam", profile={})
        services.link_guardian(zainab, kid)
        services.link_guardian(adam, kid)
        # By name Adam comes first; by link Zainab does.
        assert services.guardians_of(kid) == [adam, zainab]
        assert services.guardians_by_link(kid.pk) == [zainab, adam]
        assert services.guardians_by_link(adam.pk) == []


class TestLookups:
    def test_get_person_is_role_scoped(self):
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing etqan/identity/tests/test_people_services.py -k "billing or guardians"`
Expected: FAIL — the billing conftest cannot load (`ImportError: cannot import name 'clock' from 'etqan.billing'`), and `AttributeError: module 'etqan.identity.services' has no attribute 'guardians_by_link'`.

- [ ] **Step 3: Implement**

Create `backend/etqan/billing/clock.py`:

```python
"""The only clock billing reads, so tests pin it by monkeypatching `now`."""

from datetime import date
from datetime import datetime
from zoneinfo import ZoneInfo

from django.utils import timezone

from etqan.academy import services as academy_services


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()


def today() -> date:
    """Today on the academy's calendar (`AcademySettings.timezone`): invoices
    are issued, due and overdue by it, and revenue months follow it."""
    return now().astimezone(ZoneInfo(academy_services.get_settings().timezone)).date()
```

Create `backend/etqan/billing/services/__init__.py`:

```python
"""Public API of the billing module. Other apps import only this package."""

from etqan.billing.services.numbering import next_number
from etqan.billing.services.payers import payer_choices
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for

__all__ = [
    "invoices_queryset",
    "next_number",
    "overdue",
    "payer_choices",
    "resolve_payer",
    "status_for",
]
```

Create `backend/etqan/billing/services/numbering.py`:

```python
"""Invoice numbers (spec §3.2, plan D1)."""

from etqan.billing.models import InvoiceCounter

NUMBER_FORMAT = "INV-{:06d}"


def next_number() -> str:
    """The academy's next invoice number, `INV-000123`.

    The one counter row is taken `FOR UPDATE`, so a second invoice created at
    the same moment waits here until the first one's transaction ends: no two
    invoices share a number and, because the counter moves in the same
    transaction as the invoice, a rolled-back invoice gives its number back.
    Call it inside a transaction. The first call in an academy creates the row
    (`get_or_create` re-reads it under the lock if another request created it
    first)."""
    counter, _ = InvoiceCounter.objects.select_for_update().get_or_create(pk=1)
    counter.last_number += 1
    counter.save(update_fields=["last_number"])
    return NUMBER_FORMAT.format(counter.last_number)
```

Create `backend/etqan/billing/services/payers.py`:

```python
"""Who pays an invoice (P6-4)."""

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError


def payer_choices(student_user_id: int) -> list:
    """The people who may pay a student's invoices, the default first: their
    guardians, the earliest-linked first, then the student. The one payer
    rule: the default payer is ``payer_choices(...)[0]`` and a payer is valid
    exactly when listed here."""
    return [
        *identity_services.guardians_by_link(student_user_id),
        identity_services.get_user(student_user_id),
    ]


def resolve_payer(student_user_id: int, payer_id: int | None):
    """``payer_id``'s user when it is one of `payer_choices`, the default
    when it is None; otherwise a 400 on ``payer``."""
    choices = payer_choices(student_user_id)
    if payer_id is None:
        return choices[0]
    for person in choices:
        if person.pk == payer_id:
            return person
    raise ValidationError(
        "Choose the student or one of their guardians.", field="payer"
    )
```

Create `backend/etqan/billing/services/rules.py`:

```python
"""The rules every invoice follows (spec §4.1). One implementation each."""

from datetime import date

from django.db.models import BigIntegerField
from django.db.models import BooleanField
from django.db.models import ExpressionWrapper
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Subquery
from django.db.models import Sum
from django.db.models import Value
from django.db.models.functions import Coalesce

from etqan.billing import clock
from etqan.billing.models import Invoice
from etqan.billing.models import Payment

UNPAID = Invoice.Status.UNPAID
PARTIAL = Invoice.Status.PARTIAL
PAID = Invoice.Status.PAID
VOID = Invoice.Status.VOID
OPEN = (UNPAID, PARTIAL)


def status_for(amount_minor: int, paid_minor: int) -> str:
    """The one status function (spec §4.1, §9): nothing paid is `unpaid`,
    part of the amount `partial`, all of it `paid`. `void` is only ever set by
    voiding, which requires no payments."""
    if paid_minor <= 0:
        return UNPAID
    if paid_minor < amount_minor:
        return PARTIAL
    return PAID


def overdue(today: date, *, via: str = "") -> Q:
    """Spec §4.1: unpaid or partly paid and due before the academy's today.
    Derived, never stored; ``via`` reaches the invoice through a relation."""
    prefix = f"{via}__" if via else ""
    return Q(**{f"{prefix}status__in": OPEN, f"{prefix}due_on__lt": today})


def paid_of(invoice: Invoice) -> int:
    """The sum of ``invoice``'s payments, read in its own statement: after the
    invoice row is locked, this sees every payment committed before the lock
    was granted (plan D9)."""
    total = Payment.objects.filter(invoice=invoice).aggregate(t=Sum("amount_minor"))
    return total["t"] or 0


def _paid_subquery():
    """The same sum as `paid_of`, as a correlated subquery for lists: no join,
    so a row never multiplies by its payments."""
    paid = (
        Payment.objects.filter(invoice=OuterRef("pk"))
        .order_by()
        .values("invoice")
        .annotate(total=Sum("amount_minor"))
        .values("total")
    )
    return Coalesce(Subquery(paid, output_field=BigIntegerField()), Value(0))


def invoices_queryset() -> QuerySet[Invoice]:
    """Invoices with everything a row shows, in one query: the payer, student
    and creator joined, ``paid_minor`` summed in SQL and ``is_overdue`` from
    `overdue` on the academy's today."""
    return Invoice.objects.select_related(
        "payer", "student__user", "created_by"
    ).annotate(
        paid_minor=_paid_subquery(),
        is_overdue=ExpressionWrapper(
            overdue(clock.today()), output_field=BooleanField()
        ),
    )
```

In `backend/etqan/identity/services.py`, replace:

```python
    )


def children_of(parent: User) -> list[User]:
    return list(
        User.objects.filter(
```

with:

```python
    )


def guardians_by_link(student_user_id: int) -> list[User]:
    """The student's guardians, the earliest-linked first (billing's default
    payer, Plan 6 P6-4). ``guardians_of`` sorts by name for people screens."""
    links = (
        Guardianship.objects.filter(student__user_id=student_user_id)
        .select_related("parent__user")
        .order_by("created_at", "id")
    )
    return [link.parent.user for link in links]


def children_of(parent: User) -> list[User]:
    return list(
        User.objects.filter(
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing etqan/identity`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(billing): status, overdue and payer rules and invoice numbering

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Invoices and payments: issue, edit, void, pay and delete, each under the invoice-row lock

**Files:**
- Create: `backend/etqan/billing/services/invoices.py`, `backend/etqan/billing/services/payments.py`
- Modify: `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/rules.py`
- Test: `backend/etqan/billing/tests/test_invoices.py` (new)

**Interfaces:**
- Consumes: Task 2's rules, numbering and payer rule.
- Produces (re-exported from `etqan.billing.services`):
  - `create_invoice(*, student_id, amount_minor, due_on, description, by, payer_id=None, currency=None, notes="") -> Invoice`: issued today, with the default payer (P6-4) and the academy's currency by default; a 400 on `student`, `payer`, `due_on`, `amount_minor`, `description` or `currency`;
  - `update_invoice(invoice, *, description=None, due_on=None, notes=None, amount_minor=None) -> Invoice` (D14);
  - `void_invoice(invoice, *, by) -> Invoice` (D14);
  - `add_payment(invoice, *, amount_minor, method, paid_on, by, reference="", notes="") -> Payment` (a 400 on `amount_minor` over the balance, 409 `billing.invoice_void`);
  - `delete_payment(payment) -> None` (`NotFoundError` if already gone).
- Produces: `invoices.issue(*, student, payer, amount_minor, currency, issued_on, due_on, description, by, subscription_id=None, notes="") -> Invoice` (checks every field, then numbers); `rules.lock(invoice) -> Invoice`; `rules.check(obj, *, exclude=())`; `rules.save(obj, update_fields=None)`; `rules.refuse_if_void(invoice)`; `rules.refuse_if_paid_into(invoice)`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_invoices.py`:

```python
from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.billing import services
from etqan.billing.models import Invoice
from etqan.billing.tests.conftest import make_parent
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

JUNE_1, JUNE_8 = date(2026, 6, 1), date(2026, 6, 8)


def invoice_for(world, admin, **overrides) -> Invoice:
    fields = {
        "student_id": world.student.id,
        "amount_minor": 1000,
        "due_on": JUNE_8,
        "description": "Tajweed — June",
        "by": admin,
        **overrides,
    }
    return services.create_invoice(**fields)


def pay(invoice, admin, amount, **overrides):
    fields = {"method": "cash", "paid_on": JUNE_1, "by": admin, **overrides}
    return services.add_payment(invoice, amount_minor=amount, **fields)


def code(exc) -> str:
    return exc.value.code


def status(invoice) -> str:
    return Invoice.objects.get(pk=invoice.pk).status


def test_an_invoice_is_numbered_issued_today_and_billed_to_the_first_guardian(
    world, admin
):
    academy_services.update_settings(default_currency="SAR")
    father = make_parent("Omar", world.student)
    make_parent("Huda", world.student)
    invoice = invoice_for(world, admin, notes="Sibling rate")
    assert (invoice.number, invoice.status, invoice.issued_on) == (
        "INV-000001",
        "unpaid",
        JUNE_1,
    )
    assert (invoice.payer, invoice.student.user, invoice.currency) == (
        father,
        world.student,
        "SAR",
    )
    assert (invoice.created_by, invoice.notes) == (admin, "Sibling rate")
    assert invoice_for(world, admin, currency="egp").number == "INV-000002"


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"due_on": date(2026, 5, 31)}, "due_on"),
        ({"amount_minor": 0}, "amount_minor"),
        ({"description": ""}, "description"),
        ({"currency": "pounds"}, "currency"),
    ],
)
def test_bad_invoices_are_field_errors_and_take_no_number(
    world, admin, overrides, field
):
    with pytest.raises(ValidationError) as exc:
        invoice_for(world, admin, **overrides)
    assert exc.value.field == field
    assert invoice_for(world, admin).number == "INV-000001"


def test_only_a_student_is_billed(world, admin):
    with pytest.raises(ValidationError) as exc:
        invoice_for(world, admin, student_id=world.teacher.id)
    assert exc.value.field == "student"


def test_status_follows_every_payment_added_and_deleted(world, admin):
    invoice = invoice_for(world, admin)
    first = pay(invoice, admin, 400)
    assert status(invoice) == "partial"
    second = pay(invoice, admin, 600, method="instapay", reference="IP-77")
    assert status(invoice) == "paid"
    services.delete_payment(second)
    assert status(invoice) == "partial"
    services.delete_payment(first)
    assert status(invoice) == "unpaid"
    services.void_invoice(invoice, by=admin)
    assert status(invoice) == "void"


def test_overpaying_is_refused_on_the_amount(world, admin):
    invoice = invoice_for(world, admin)
    pay(invoice, admin, 700)
    with pytest.raises(ValidationError) as exc:
        pay(invoice, admin, 301)
    assert exc.value.field == "amount_minor"
    pay(invoice, admin, 300)
    with pytest.raises(ValidationError) as exc:
        pay(invoice, admin, 1)
    assert exc.value.field == "amount_minor"
    assert status(invoice) == "paid"


@pytest.mark.parametrize(
    ("overrides", "field"),
    [({"amount_minor": 0}, "amount_minor"), ({"method": "cheque"}, "method")],
)
def test_bad_payments_are_field_errors(world, admin, overrides, field):
    invoice = invoice_for(world, admin)
    amount = overrides.pop("amount_minor", 100)
    with pytest.raises(ValidationError) as exc:
        pay(invoice, admin, amount, **overrides)
    assert exc.value.field == field
    assert status(invoice) == "unpaid"


def test_a_payment_deleted_twice_is_not_found(world, admin):
    invoice = invoice_for(world, admin)
    payment = pay(invoice, admin, 100)
    services.delete_payment(payment)
    with pytest.raises(NotFoundError):
        services.delete_payment(payment)
    assert status(invoice) == "unpaid"


def test_void_needs_no_payments_and_is_final(world, admin):
    invoice = invoice_for(world, admin)
    payment = pay(invoice, admin, 100)
    with pytest.raises(ConflictError) as exc:
        services.void_invoice(invoice, by=admin)
    assert code(exc) == "billing.has_payments"
    services.delete_payment(payment)
    voided = services.void_invoice(invoice, by=admin)
    assert (voided.status, voided.voided_by) == ("void", admin)
    assert voided.voided_at is not None
    for action in (
        lambda: services.void_invoice(invoice, by=admin),
        lambda: pay(invoice, admin, 100),
        lambda: services.update_invoice(invoice, notes="again"),
    ):
        with pytest.raises(ConflictError) as exc:
            action()
        assert code(exc) == "billing.invoice_void"
    assert status(invoice) == "void"


def test_editing_keeps_the_amount_once_paid_into(world, admin):
    invoice = invoice_for(world, admin)
    edited = services.update_invoice(
        invoice,
        description="Tajweed — June, 8 sessions",
        due_on=date(2026, 6, 15),
        notes="Agreed by phone",
        amount_minor=1200,
    )
    assert (edited.description, edited.due_on, edited.notes, edited.amount_minor) == (
        "Tajweed — June, 8 sessions",
        date(2026, 6, 15),
        "Agreed by phone",
        1200,
    )
    pay(invoice, admin, 200)
    with pytest.raises(ConflictError) as exc:
        services.update_invoice(invoice, amount_minor=900)
    assert code(exc) == "billing.has_payments"
    # The same amount is no change; the other fields still edit.
    services.update_invoice(invoice, amount_minor=1200, notes="Paid 200")
    with pytest.raises(ValidationError) as exc:
        services.update_invoice(invoice, due_on=date(2026, 5, 31))
    assert exc.value.field == "due_on"
    fresh = Invoice.objects.get(pk=invoice.pk)
    assert (fresh.amount_minor, fresh.notes, fresh.status) == (
        1200,
        "Paid 200",
        "partial",
    )


def test_a_stale_copy_never_pays_a_voided_invoice(world, admin):
    invoice = invoice_for(world, admin)
    stale = Invoice.objects.get(pk=invoice.pk)
    services.void_invoice(invoice, by=admin)
    assert stale.status == "unpaid"
    with pytest.raises(ConflictError) as exc:
        pay(stale, admin, 100)
    assert code(exc) == "billing.invoice_void"


def _statements(action):
    with CaptureQueriesContext(connection) as ctx:
        action()
    return [q["sql"] for q in ctx.captured_queries]


def _table(sql: str) -> str:
    return sql.split(" FROM ")[1].split(maxsplit=1)[0]


@pytest.mark.parametrize("write", ["pay", "delete", "void", "edit"])
def test_every_write_locks_the_invoice_row_first(world, admin, write):
    invoice = invoice_for(world, admin)
    payment = pay(invoice, admin, 100)
    actions = {
        "pay": lambda: pay(invoice, admin, 100),
        "delete": lambda: services.delete_payment(payment),
        "void": lambda: services.void_invoice(invoice_for(world, admin), by=admin),
        "edit": lambda: services.update_invoice(invoice, notes="x"),
    }
    sql = _statements(actions[write])
    locks = [s for s in sql if "FOR UPDATE" in s]
    if write == "void":
        # A new invoice takes the counter first, then voiding locks it.
        locks = locks[1:]
    assert _table(locks[0]) == '"billing_invoice"'
    assert locks[0].rstrip().endswith("FOR UPDATE")
    if write in ("pay", "delete"):
        # The balance is summed in a statement after the lock is granted,
        # so it counts a payment committed while this one waited (D9).
        lock_at = sql.index(locks[0])
        sums = [i for i, s in enumerate(sql) if 'SUM("billing_payment"' in s]
        assert sums
        assert all(i > lock_at for i in sums)
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing/tests/test_invoices.py`
Expected: FAIL — `AttributeError: module 'etqan.billing.services' has no attribute 'create_invoice'`.

- [ ] **Step 3: Implement**

In `backend/etqan/billing/services/__init__.py`, replace:

```python
"""Public API of the billing module. Other apps import only this package."""

from etqan.billing.services.numbering import next_number
from etqan.billing.services.payers import payer_choices
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for

__all__ = [
    "invoices_queryset",
    "next_number",
    "overdue",
    "payer_choices",
    "resolve_payer",
    "status_for",
]
```

with:

```python
"""Public API of the billing module. Other apps import only this package."""

from etqan.billing.services.invoices import create_invoice
from etqan.billing.services.invoices import update_invoice
from etqan.billing.services.invoices import void_invoice
from etqan.billing.services.numbering import next_number
from etqan.billing.services.payers import payer_choices
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.payments import add_payment
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for

__all__ = [
    "add_payment",
    "create_invoice",
    "delete_payment",
    "invoices_queryset",
    "next_number",
    "overdue",
    "payer_choices",
    "resolve_payer",
    "status_for",
    "update_invoice",
    "void_invoice",
]
```

Create `backend/etqan/billing/services/invoices.py`:

```python
"""Issuing, editing and voiding invoices (spec §4.2, §5)."""

from datetime import date

from django.db import transaction

from etqan.academy import services as academy_services
from etqan.billing import clock
from etqan.billing.models import Invoice
from etqan.billing.services import numbering
from etqan.billing.services import payers
from etqan.billing.services import rules
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency


def _student(student_id: int):
    profile = identity_services.get_student_profile(student_id)
    if profile is None or profile.user.role != "student":
        raise ValidationError("Choose a student.", field="student")
    return profile


def _check_due(issued_on: date, due_on: date) -> None:
    if due_on < issued_on:
        raise ValidationError("Make it due on or after the issue date.", field="due_on")


def issue(  # noqa: PLR0913 -- keyword-only; one invoice's columns
    *,
    student,
    payer,
    amount_minor: int,
    currency: str,
    issued_on: date,
    due_on: date,
    description: str,
    by,
    subscription_id: int | None = None,
    notes: str = "",
) -> Invoice:
    """Write one invoice. Checked first, numbered last: a refused invoice
    takes no number, and the counter row is held as briefly as possible."""
    _check_due(issued_on, due_on)
    invoice = Invoice(
        payer=payer,
        student=student,
        subscription_id=subscription_id,
        description=description,
        amount_minor=amount_minor,
        currency=clean_currency(currency, field="currency"),
        issued_on=issued_on,
        due_on=due_on,
        notes=notes,
        created_by=by,
    )
    rules.check(invoice, exclude=["number"])
    invoice.number = numbering.next_number()
    invoice.save()
    return invoice


@transaction.atomic
def create_invoice(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    *,
    student_id: int,
    amount_minor: int,
    due_on: date,
    description: str,
    by,
    payer_id: int | None = None,
    currency: str | None = None,
    notes: str = "",
) -> Invoice:
    """An admin's invoice, issued today (academy calendar). The payer
    defaults to the student's first guardian (P6-4); the currency to the
    academy's."""
    student = _student(student_id)
    return issue(
        student=student,
        payer=payers.resolve_payer(student.user_id, payer_id),
        amount_minor=amount_minor,
        currency=currency or academy_services.get_settings().default_currency,
        issued_on=clock.today(),
        due_on=due_on,
        description=description,
        notes=notes,
        by=by,
    )


@transaction.atomic
def update_invoice(
    invoice: Invoice,
    *,
    description: str | None = None,
    due_on: date | None = None,
    notes: str | None = None,
    amount_minor: int | None = None,
) -> Invoice:
    """Spec §4.2: nothing changes on a void invoice; the amount only while
    nothing is paid. Only the edited columns are written back."""
    locked = rules.lock(invoice)
    rules.refuse_if_void(locked)
    changed = []
    if description is not None:
        locked.description = description
        changed.append("description")
    if notes is not None:
        locked.notes = notes
        changed.append("notes")
    if due_on is not None:
        _check_due(locked.issued_on, due_on)
        locked.due_on = due_on
        changed.append("due_on")
    if amount_minor is not None and amount_minor != locked.amount_minor:
        rules.refuse_if_paid_into(locked)
        locked.amount_minor = amount_minor
        changed.append("amount_minor")
    rules.save(locked, update_fields=[*changed, "updated_at"])
    return locked


@transaction.atomic
def void_invoice(invoice: Invoice, *, by) -> Invoice:
    """Spec §4.2: only without payments, and for good."""
    locked = rules.lock(invoice)
    rules.refuse_if_void(locked)
    rules.refuse_if_paid_into(locked)
    locked.status = Invoice.Status.VOID
    locked.voided_by = by
    locked.voided_at = clock.now()
    locked.save(update_fields=["status", "voided_by", "voided_at", "updated_at"])
    return locked
```

Create `backend/etqan/billing/services/payments.py`:

```python
"""Recording and deleting payments; the status follows (spec §4.1)."""

from datetime import date

from django.db import transaction

from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.billing.services import rules
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError


def _recalculate(invoice: Invoice) -> None:
    """Set the locked ``invoice``'s status from its payments, with the one
    status function, in the transaction that changed them."""
    invoice.status = rules.status_for(invoice.amount_minor, rules.paid_of(invoice))
    invoice.save(update_fields=["status", "updated_at"])


@transaction.atomic
def add_payment(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    invoice: Invoice,
    *,
    amount_minor: int,
    method: str,
    paid_on: date,
    by,
    reference: str = "",
    notes: str = "",
) -> Payment:
    """A payment in the invoice's currency (P6-6). More than the balance is a
    400 on ``amount_minor``; a void invoice takes none (409)."""
    locked = rules.lock(invoice)
    rules.refuse_if_void(locked)
    balance = locked.amount_minor - rules.paid_of(locked)
    if amount_minor > balance:
        raise ValidationError("That is more than the balance.", field="amount_minor")
    payment = Payment(
        invoice=locked,
        amount_minor=amount_minor,
        method=method,
        paid_on=paid_on,
        reference=reference,
        notes=notes,
        recorded_by=by,
    )
    rules.save(payment)
    _recalculate(locked)
    return payment


@transaction.atomic
def delete_payment(payment: Payment) -> None:
    """For mistakes (spec §4.2). The invoice is locked first, as when paying."""
    locked = rules.lock(payment.invoice)
    deleted, _ = Payment.objects.filter(pk=payment.pk).delete()
    if not deleted:
        raise NotFoundError("Payment", payment.pk)
    _recalculate(locked)
```

In `backend/etqan/billing/services/rules.py`, replace:

```python

from datetime import date

from django.db.models import BigIntegerField
from django.db.models import BooleanField
from django.db.models import ExpressionWrapper
```

with:

```python

from datetime import date

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import BigIntegerField
from django.db.models import BooleanField
from django.db.models import ExpressionWrapper
```

In `backend/etqan/billing/services/rules.py`, replace:

```python
from etqan.billing import clock
from etqan.billing.models import Invoice
from etqan.billing.models import Payment

UNPAID = Invoice.Status.UNPAID
PARTIAL = Invoice.Status.PARTIAL
```

with:

```python
from etqan.billing import clock
from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.platform.exceptions import ConflictError
from etqan.platform.validators import from_django

UNPAID = Invoice.Status.UNPAID
PARTIAL = Invoice.Status.PARTIAL
```

In `backend/etqan/billing/services/rules.py`, replace:

```python
    return PAID


def overdue(today: date, *, via: str = "") -> Q:
    """Spec §4.1: unpaid or partly paid and due before the academy's today.
    Derived, never stored; ``via`` reaches the invoice through a relation."""
```

with:

```python
    return PAID


def check(obj, *, exclude=()) -> None:
    """Field checks with readable messages (a bad method, a zero amount, a
    blank description), as 400s on their fields."""
    try:
        obj.full_clean(exclude=list(exclude), validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None


def save(obj, update_fields=None) -> None:
    check(obj)
    obj.save(update_fields=update_fields)


def lock(invoice: Invoice) -> Invoice:
    """``invoice``'s row, `SELECT … FOR UPDATE`, read fresh. Every write to
    an invoice or its payments takes this lock first and decides on the
    fresh row, so two admins at once can never pay past the amount or pay a
    voided invoice (plan D9)."""
    return Invoice.objects.select_for_update().get(pk=invoice.pk)


def refuse_if_void(invoice: Invoice) -> None:
    if invoice.status == VOID:
        raise ConflictError("This invoice is void.", code="billing.invoice_void")


def refuse_if_paid_into(invoice: Invoice) -> None:
    if Payment.objects.filter(invoice=invoice).exists():
        raise ConflictError("This invoice has payments.", code="billing.has_payments")


def overdue(today: date, *, via: str = "") -> Q:
    """Spec §4.1: unpaid or partly paid and due before the academy's today.
    Derived, never stored; ``via`` reaches the invoice through a relation."""
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(billing): issue, edit and void invoices; record and delete payments

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Subscriptions and billing: the row lock, the delete hook, automatic invoices and payment status

**Files:**
- Create: `backend/etqan/billing/services/subscriptions.py`
- Modify: `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/invoices.py`, `backend/etqan/scheduling/api/views.py`, `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/services/subscriptions.py`
- Test: `backend/etqan/billing/tests/test_subscriptions.py` (new), `backend/etqan/scheduling/tests/test_actions.py`, `backend/etqan/tenants/tests/test_seed_dev.py`

**Interfaces:**
- Consumes: Task 3's `invoices.issue`, `create_invoice`, `void_invoice`, `add_payment`.
- Produces (scheduling, re-exported from `etqan.scheduling.services`):
  - `lock_subscription(pk: int) -> Subscription | None`: `FOR UPDATE OF "scheduling_subscription"`, with `student__user`, `course` and `package`;
  - `delete_subscription(subscription, *, before_delete: Callable[[int], None]) -> None`: the hook is required and runs with the id right after the subscription lock (D2). Every existing caller now passes one.
- Produces (re-exported from `etqan.billing.services`):
  - `invoice_subscription(subscription_id: int, *, by, issued_on: date | None = None) -> Invoice | None` (spec §4.3, D5);
  - `refuse_if_invoiced(subscription_id: int) -> None` (409 `billing.subscription_invoiced`);
  - `PaymentStatus(status: str, overdue: bool)`;
  - `payment_statuses(subscription_ids) -> dict[int, PaymentStatus]` (D6);
  - `create_invoice(..., subscription_id: int | None = None, ...)`: the student's subscription, locked, whose currency becomes the default; a 400 on `subscription` otherwise.
- Produces: the subscription `DELETE` view passes `billing_services.refuse_if_invoiced`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_subscriptions.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.billing import services
from etqan.billing.models import Invoice
from etqan.billing.tests.conftest import make_parent
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import two_slots


def test_a_subscription_is_invoiced_at_its_price_in_the_academys_language(
    subscribe, world, admin
):
    academy_services.update_settings(invoice_due_days=10)
    mother = make_parent("Maryam", world.student)
    sub = subscribe(price_minor=120000)
    invoice = services.invoice_subscription(sub.pk, by=admin)
    assert (invoice.amount_minor, invoice.currency, invoice.subscription_id) == (
        120000,
        "EGP",
        sub.pk,
    )
    assert (invoice.student.user, invoice.payer, invoice.created_by) == (
        world.student,
        mother,
        admin,
    )
    assert (invoice.issued_on, invoice.due_on) == (date(2026, 6, 1), date(2026, 6, 11))
    # The academy's default language is Arabic until it is changed.
    assert invoice.description == "تجويد — شهري"
    academy_services.update_settings(default_language="en")
    again = services.invoice_subscription(sub.pk, by=admin)
    assert again.description == "Tajweed — Monthly"
    assert (invoice.number, again.number) == ("INV-000001", "INV-000002")


def test_no_invoice_with_the_switch_off_or_a_zero_price(subscribe, admin):
    free = subscribe(price_minor=0)
    assert services.invoice_subscription(free.pk, by=admin) is None
    academy_services.update_settings(auto_invoice_on_subscription=False)
    paid = subscribe()
    assert services.invoice_subscription(paid.pk, by=admin) is None
    assert not Invoice.objects.exists()


def test_the_seeds_can_backdate_an_invoice(subscribe, admin):
    sub = subscribe()
    invoice = services.invoice_subscription(
        sub.pk, by=None, issued_on=date(2026, 5, 20)
    )
    assert (invoice.issued_on, invoice.due_on, invoice.created_by) == (
        date(2026, 5, 20),
        date(2026, 5, 27),
        None,
    )


def test_a_manual_invoice_takes_the_students_subscription_and_its_currency(
    subscribe, world, admin
):
    academy_services.update_settings(default_currency="USD")
    sub = subscribe()
    invoice = services.create_invoice(
        student_id=world.student.id,
        subscription_id=sub.pk,
        amount_minor=5000,
        due_on=date(2026, 6, 8),
        description="Extra session",
        by=admin,
    )
    assert (invoice.subscription_id, invoice.currency) == (sub.pk, "EGP")
    other = subscribe(student_id=make_student("Aisha").id)
    for subscription_id in (other.pk, other.pk + 1000):
        with pytest.raises(ValidationError) as exc:
            services.create_invoice(
                student_id=world.student.id,
                subscription_id=subscription_id,
                amount_minor=5000,
                due_on=date(2026, 6, 8),
                description="Extra session",
                by=admin,
            )
        assert exc.value.field == "subscription"


def _locks(sql):
    return [s.split(" FROM ")[1].split()[0] for s in sql if "FOR UPDATE" in s]


def test_an_invoice_locks_its_subscription_before_the_counter(subscribe, world, admin):
    sub = subscribe()
    with CaptureQueriesContext(connection) as ctx:
        services.create_invoice(
            student_id=world.student.id,
            subscription_id=sub.pk,
            amount_minor=5000,
            due_on=date(2026, 6, 8),
            description="Extra session",
            by=admin,
        )
    sql = [q["sql"] for q in ctx.captured_queries]
    assert _locks(sql) == ['"scheduling_subscription"', '"billing_invoicecounter"']


def test_a_subscription_with_a_live_invoice_is_not_deleted(subscribe, admin):
    sub = subscribe(slots=two_slots())
    invoice = services.invoice_subscription(sub.pk, by=admin)
    with pytest.raises(ConflictError) as exc:
        scheduling_services.delete_subscription(
            sub, before_delete=services.refuse_if_invoiced
        )
    assert exc.value.code == "billing.subscription_invoiced"
    assert scheduling_services.sessions_of(sub).count() == 5
    services.void_invoice(invoice, by=admin)
    scheduling_services.delete_subscription(
        sub, before_delete=services.refuse_if_invoiced
    )
    assert not scheduling_services.subscriptions_queryset().filter(pk=sub.pk).exists()
    # The void invoice stays, pointing at the id it was for (spec §4.3).
    assert Invoice.objects.get(pk=invoice.pk).subscription_id == sub.pk


def test_the_invoice_check_runs_between_the_subscription_and_session_locks(
    subscribe,
):
    sub = subscribe(slots=two_slots())
    with CaptureQueriesContext(connection) as ctx:
        scheduling_services.delete_subscription(
            sub, before_delete=services.refuse_if_invoiced
        )
    sql = [q["sql"] for q in ctx.captured_queries]
    order = [
        "check" if '"billing_invoice"' in s else _locks([s])[0]
        for s in sql
        if "FOR UPDATE" in s or '"billing_invoice"' in s
    ]
    assert order == ['"scheduling_subscription"', "check", '"scheduling_session"']


def test_payment_status_follows_the_non_void_invoices(subscribe, world, admin, clock):
    def status_of(sub):
        found = services.payment_statuses([sub.pk])[sub.pk]
        return (found.status, found.overdue)

    sub = subscribe()
    assert status_of(sub) == ("none", False)
    first = services.invoice_subscription(sub.pk, by=admin)
    assert status_of(sub) == ("unpaid", False)
    second = services.invoice_subscription(sub.pk, by=admin)
    services.add_payment(
        first, amount_minor=150000, method="cash", paid_on=date(2026, 6, 1), by=admin
    )
    # One paid, one untouched: some payment, not everything paid.
    assert status_of(sub) == ("partial", False)
    services.void_invoice(second, by=admin)
    assert status_of(sub) == ("paid", False)
    third = services.invoice_subscription(sub.pk, by=admin)
    assert status_of(sub) == ("partial", False)
    # Due 8 June; on the 9th it is overdue.
    clock.set(datetime(2026, 6, 9, 8, tzinfo=UTC))
    assert status_of(sub) == ("partial", True)
    services.add_payment(
        third, amount_minor=150000, method="cash", paid_on=date(2026, 6, 9), by=admin
    )
    assert status_of(sub) == ("paid", False)


def test_payment_status_costs_the_same_queries_for_one_or_five(subscribe, admin):
    subs = [subscribe(student_id=make_student(f"S{n}").id) for n in range(5)]
    for sub in subs[:3]:
        services.invoice_subscription(sub.pk, by=admin)

    def queries(ids):
        with CaptureQueriesContext(connection) as ctx:
            found = services.payment_statuses(ids)
        return len(ctx.captured_queries), found

    one, _ = queries([subs[0].pk])
    five, found = queries([s.pk for s in subs])
    assert one == five
    assert [found[s.pk].status for s in subs] == [
        "unpaid",
        "unpaid",
        "unpaid",
        "none",
        "none",
    ]
    assert services.payment_statuses([]) == {}
```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
    Session.objects.filter(pk=session.pk).update(student_attendance="present")


def code(exc_info):
    return exc_info.value.code

```

with:

```python
    Session.objects.filter(pk=session.pk).update(student_attendance="present")


def allow(_subscription_id: int) -> None:
    """A `before_delete` that refuses nothing: these tests are about sessions
    (billing's invoice check is tested in `etqan.billing`)."""


def code(exc_info):
    return exc_info.value.code

```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
    sub = subscribe(slots=two_slots())
    mark(on(sub, JUNE[1]))
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(sub)
    assert code(exc) == "scheduling.has_marked_sessions"
    Session.objects.filter(subscription=sub).update(student_attendance="not_set")
    services.delete_subscription(sub)
    assert not Subscription.objects.filter(pk=sub.pk).exists()
    assert not Session.objects.exists()


def test_delete_refuses_a_session_marked_after_a_stale_load(subscribe):
    # Behaviour documentation, not a lock proof: a same-process test can't
    # tell "re-reads fresh" from "holds a row lock" without a second
```

with:

```python
    sub = subscribe(slots=two_slots())
    mark(on(sub, JUNE[1]))
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(sub, before_delete=allow)
    assert code(exc) == "scheduling.has_marked_sessions"
    Session.objects.filter(subscription=sub).update(student_attendance="not_set")
    services.delete_subscription(sub, before_delete=allow)
    assert not Subscription.objects.filter(pk=sub.pk).exists()
    assert not Session.objects.exists()


def test_delete_asks_before_delete_and_stops_when_it_refuses(subscribe):
    sub = subscribe(slots=two_slots())
    seen = []

    def refuse(subscription_id):
        seen.append(subscription_id)
        raise ConflictError("Not today.", code="test.refused")

    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(sub, before_delete=refuse)
    assert code(exc) == "test.refused"
    assert seen == [sub.pk]
    assert Subscription.objects.filter(pk=sub.pk).exists()
    assert sessions(sub).count() == 5


def test_lock_subscription_locks_only_the_subscription_row(subscribe):
    sub = subscribe(slots=two_slots())
    with CaptureQueriesContext(connection) as ctx:
        locked = services.lock_subscription(sub.pk)
    assert (locked.pk, locked.course.name_en, locked.student.user.full_name) == (
        sub.pk,
        "Tajweed",
        "Yusuf",
    )
    (sql,) = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert sql.rstrip().endswith('FOR UPDATE OF "scheduling_subscription"')
    assert services.lock_subscription(sub.pk + 1000) is None


def test_delete_refuses_a_session_marked_after_a_stale_load(subscribe):
    # Behaviour documentation, not a lock proof: a same-process test can't
    # tell "re-reads fresh" from "holds a row lock" without a second
```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
    stale = Subscription.objects.get(pk=sub.pk)
    mark(on(sub, JUNE[1]))
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(stale)
    assert code(exc) == "scheduling.has_marked_sessions"
    assert Subscription.objects.filter(pk=sub.pk).exists()
    assert sessions(sub).count() == 5
```

with:

```python
    stale = Subscription.objects.get(pk=sub.pk)
    mark(on(sub, JUNE[1]))
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(stale, before_delete=allow)
    assert code(exc) == "scheduling.has_marked_sessions"
    assert Subscription.objects.filter(pk=sub.pk).exists()
    assert sessions(sub).count() == 5
```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
def test_delete_subscription_locks_the_subscription_then_its_sessions(subscribe):
    sub = subscribe(slots=two_slots())
    with CaptureQueriesContext(connection) as ctx:
        services.delete_subscription(sub)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert [sql.split(" FROM ")[1].split()[0] for sql in locks] == [
        '"scheduling_subscription"',
```

with:

```python
def test_delete_subscription_locks_the_subscription_then_its_sessions(subscribe):
    sub = subscribe(slots=two_slots())
    with CaptureQueriesContext(connection) as ctx:
        services.delete_subscription(sub, before_delete=allow)
    locks = [q["sql"] for q in ctx.captured_queries if "FOR UPDATE" in q["sql"]]
    assert [sql.split(" FROM ")[1].split()[0] for sql in locks] == [
        '"scheduling_subscription"',
```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))
    Session.objects.filter(pk=on(sub, JUNE[1]).pk).update(**acted)
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(sub)
    assert code(exc) == "scheduling.has_marked_sessions"
    assert sessions(sub).count() == 5

```

with:

```python
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))
    Session.objects.filter(pk=on(sub, JUNE[1]).pk).update(**acted)
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(sub, before_delete=allow)
    assert code(exc) == "scheduling.has_marked_sessions"
    assert sessions(sub).count() == 5

```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
    sub = subscribe(slots=two_slots())
    services.add_pause(sub, from_date=JUNE[20], to_date=JUNE[22])
    clock.set(datetime(2026, 6, 4, 9, tzinfo=UTC))  # 1 and 3 June are past
    services.delete_subscription(sub)
    assert not Subscription.objects.filter(pk=sub.pk).exists()
    assert not Session.objects.exists()
    assert not ScheduleSlot.objects.exists()
```

with:

```python
    sub = subscribe(slots=two_slots())
    services.add_pause(sub, from_date=JUNE[20], to_date=JUNE[22])
    clock.set(datetime(2026, 6, 4, 9, tzinfo=UTC))  # 1 and 3 June are past
    services.delete_subscription(sub, before_delete=allow)
    assert not Subscription.objects.filter(pk=sub.pk).exists()
    assert not Session.objects.exists()
    assert not ScheduleSlot.objects.exists()
```

In `backend/etqan/scheduling/tests/test_actions.py`, replace:

```python
    old = subscribe(slots=two_slots())
    renewal = subscribe(starts_on=date(2026, 7, 1), renewed_from=old)
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(old)
    assert code(exc) == "scheduling.already_renewed"
    services.cancel_subscription(renewal)
    services.delete_subscription(old)
    assert not Subscription.objects.filter(pk=old.pk).exists()
    renewal.refresh_from_db()
    assert renewal.renewed_from is None
```

with:

```python
    old = subscribe(slots=two_slots())
    renewal = subscribe(starts_on=date(2026, 7, 1), renewed_from=old)
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(old, before_delete=allow)
    assert code(exc) == "scheduling.already_renewed"
    services.cancel_subscription(renewal)
    services.delete_subscription(old, before_delete=allow)
    assert not Subscription.objects.filter(pk=old.pk).exists()
    renewal.refresh_from_db()
    assert renewal.renewed_from is None
```

In `backend/etqan/tenants/tests/test_seed_dev.py`, replace:

```python
        User.objects.filter(full_name="Ustadha Maryam").update(is_active=False)
        # Force seed_subscriptions to run again (it is otherwise idempotent).
        for sub in scheduling.subscriptions_queryset():
            scheduling.delete_subscription(sub)

    call_command("seed_dev")  # must not raise

```

with:

```python
        User.objects.filter(full_name="Ustadha Maryam").update(is_active=False)
        # Force seed_subscriptions to run again (it is otherwise idempotent).
        for sub in scheduling.subscriptions_queryset():
            scheduling.delete_subscription(sub, before_delete=lambda _pk: None)

    call_command("seed_dev")  # must not raise

```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing/tests/test_subscriptions.py etqan/scheduling/tests/test_actions.py`
Expected: FAIL — `AttributeError: module 'etqan.billing.services' has no attribute 'invoice_subscription'` (and `refuse_if_invoiced`, `payment_statuses`; `lock_subscription` on scheduling's services), `TypeError: create_invoice() got an unexpected keyword argument 'subscription_id'`, and `TypeError: delete_subscription() got an unexpected keyword argument 'before_delete'` in every delete test.

- [ ] **Step 3: Implement**

In `backend/etqan/billing/services/__init__.py`, replace:

```python
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for

__all__ = [
    "add_payment",
    "create_invoice",
    "delete_payment",
    "invoices_queryset",
    "next_number",
    "overdue",
    "payer_choices",
    "resolve_payer",
    "status_for",
    "update_invoice",
```

with:

```python
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for
from etqan.billing.services.subscriptions import PaymentStatus
from etqan.billing.services.subscriptions import invoice_subscription
from etqan.billing.services.subscriptions import payment_statuses
from etqan.billing.services.subscriptions import refuse_if_invoiced

__all__ = [
    "PaymentStatus",
    "add_payment",
    "create_invoice",
    "delete_payment",
    "invoice_subscription",
    "invoices_queryset",
    "next_number",
    "overdue",
    "payer_choices",
    "payment_statuses",
    "refuse_if_invoiced",
    "resolve_payer",
    "status_for",
    "update_invoice",
```

In `backend/etqan/billing/services/invoices.py`, replace:

```python
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency


def _student(student_id: int):
```

with:

```python
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.scheduling import services as scheduling_services


def _student(student_id: int):
```

In `backend/etqan/billing/services/invoices.py`, replace:

```python
    return profile


def _check_due(issued_on: date, due_on: date) -> None:
    if due_on < issued_on:
        raise ValidationError("Make it due on or after the issue date.", field="due_on")
```

with:

```python
    return profile


def _subscription_of(student, subscription_id: int):
    """The student's subscription with this id, its row locked until the
    invoice is written (subscription before invoice, plan D8); a 400 on
    ``subscription`` otherwise."""
    subscription = scheduling_services.lock_subscription(subscription_id)
    if subscription is None or subscription.student_id != student.pk:
        raise ValidationError(
            "Choose one of this student's subscriptions.", field="subscription"
        )
    return subscription


def _check_due(issued_on: date, due_on: date) -> None:
    if due_on < issued_on:
        raise ValidationError("Make it due on or after the issue date.", field="due_on")
```

In `backend/etqan/billing/services/invoices.py`, replace:

```python
    description: str,
    by,
    payer_id: int | None = None,
    currency: str | None = None,
    notes: str = "",
) -> Invoice:
    """An admin's invoice, issued today (academy calendar). The payer
    defaults to the student's first guardian (P6-4); the currency to the
    academy's."""
    student = _student(student_id)
    return issue(
        student=student,
        payer=payers.resolve_payer(student.user_id, payer_id),
        amount_minor=amount_minor,
        currency=currency or academy_services.get_settings().default_currency,
        issued_on=clock.today(),
        due_on=due_on,
        description=description,
```

with:

```python
    description: str,
    by,
    payer_id: int | None = None,
    subscription_id: int | None = None,
    currency: str | None = None,
    notes: str = "",
) -> Invoice:
    """An admin's invoice, issued today (academy calendar). The payer
    defaults to the student's first guardian (P6-4). A subscription must be
    the student's, and is locked until the invoice is written (plan D8); the
    currency defaults to the subscription's, else the academy's."""
    student = _student(student_id)
    default_currency = academy_services.get_settings().default_currency
    if subscription_id is not None:
        subscription = _subscription_of(student, subscription_id)
        default_currency = subscription.currency
    return issue(
        student=student,
        payer=payers.resolve_payer(student.user_id, payer_id),
        subscription_id=subscription_id,
        amount_minor=amount_minor,
        currency=currency or default_currency,
        issued_on=clock.today(),
        due_on=due_on,
        description=description,
```

Create `backend/etqan/billing/services/subscriptions.py`:

```python
"""Invoices for subscriptions (spec §4.3, §4.4). Subscriptions are read only
through `etqan.scheduling.services` (P6-1)."""

from dataclasses import dataclass
from datetime import date
from datetime import timedelta

from django.db import transaction
from django.db.models import Count
from django.db.models import Q

from etqan.academy import services as academy_services
from etqan.billing import clock
from etqan.billing.models import Invoice
from etqan.billing.services import invoices
from etqan.billing.services import payers
from etqan.billing.services import rules
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services as scheduling_services


def describe(subscription, language: str) -> str:
    """ "{course} — {package}" in ``language`` (spec §4.3)."""
    suffix = "ar" if language == "ar" else "en"
    course = getattr(subscription.course, f"name_{suffix}")
    package = getattr(subscription.package, f"name_{suffix}")
    return f"{course} — {package}"


@transaction.atomic
def invoice_subscription(
    subscription_id: int, *, by, issued_on: date | None = None
) -> Invoice | None:
    """Spec §4.3: the invoice for a new or renewed subscription, when the
    academy's switch is on and the price is not 0. Its amount and currency
    are the subscription's, its payer the default (P6-4), its description in
    the academy's default language (plan D5). Issued today unless the seeds
    backfill an older one. Runs in the caller's transaction: a failure here
    rolls the subscription back too."""
    settings_row = academy_services.get_settings()
    if not settings_row.auto_invoice_on_subscription:
        return None
    subscription = scheduling_services.lock_subscription(subscription_id)
    if subscription is None or subscription.price_minor == 0:
        return None
    issued_on = issued_on or clock.today()
    return invoices.issue(
        student=subscription.student,
        payer=payers.resolve_payer(subscription.student.user_id, None),
        subscription_id=subscription.pk,
        amount_minor=subscription.price_minor,
        currency=subscription.currency,
        issued_on=issued_on,
        due_on=issued_on + timedelta(days=settings_row.invoice_due_days),
        description=describe(subscription, settings_row.default_language),
        by=by,
    )


def refuse_if_invoiced(subscription_id: int) -> None:
    """Spec §4.3: a subscription with a non-void invoice is not deleted. Passed
    to `delete_subscription` as ``before_delete`` (plan D2)."""
    invoiced = Invoice.objects.filter(subscription_id=subscription_id).exclude(
        status=rules.VOID
    )
    if invoiced.exists():
        raise ConflictError(
            "This subscription has invoices. Void them first.",
            code="billing.subscription_invoiced",
        )


@dataclass(frozen=True)
class PaymentStatus:
    status: str  # none · unpaid · partial · paid
    overdue: bool


NO_INVOICE = PaymentStatus("none", overdue=False)


def payment_statuses(subscription_ids) -> dict[int, PaymentStatus]:
    """Spec §4.4 for every id passed, from its non-void invoices, in one query
    however many ids (plan D6). An invoice's stored status already follows its
    payments, so counting statuses is enough: all paid is `paid`, any paid
    into is `partial`, else `unpaid`; `overdue` when any invoice is."""
    ids = list(subscription_ids)
    if not ids:
        return {}
    rows = (
        Invoice.objects.filter(subscription_id__in=ids)
        .exclude(status=rules.VOID)
        .order_by()
        .values("subscription_id")
        .annotate(
            invoices=Count("pk"),
            paid=Count("pk", filter=Q(status=rules.PAID)),
            paid_into=Count("pk", filter=Q(status__in=(rules.PARTIAL, rules.PAID))),
            overdue=Count("pk", filter=rules.overdue(clock.today())),
        )
    )
    found = {row["subscription_id"]: row for row in rows}
    return {pk: _payment_status(found.get(pk)) for pk in ids}


def _payment_status(row) -> PaymentStatus:
    if row is None:
        return NO_INVOICE
    if row["paid"] == row["invoices"]:
        status = "paid"
    elif row["paid_into"]:
        status = "partial"
    else:
        status = "unpaid"
    return PaymentStatus(status, overdue=row["overdue"] > 0)
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import ReadOnly
```

with:

```python
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.billing import services as billing_services
from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import ReadOnly
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
        return detail(sub.pk, request)

    def delete(self, request, pk):
        services.delete_subscription(subscription_or_404(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


```

with:

```python
        return detail(sub.pk, request)

    def delete(self, request, pk):
        # Plan 6 D2: refused while a non-void invoice points at it (409
        # `billing.subscription_invoiced`), checked under the row lock.
        services.delete_subscription(
            subscription_or_404(request, pk),
            before_delete=billing_services.refuse_if_invoiced,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
from etqan.scheduling.services.subscriptions import delete_slot
from etqan.scheduling.services.subscriptions import delete_subscription
from etqan.scheduling.services.subscriptions import end_pause
from etqan.scheduling.services.subscriptions import renew_subscription
from etqan.scheduling.services.subscriptions import update_slot
from etqan.scheduling.services.subscriptions import update_subscription
```

with:

```python
from etqan.scheduling.services.subscriptions import delete_slot
from etqan.scheduling.services.subscriptions import delete_subscription
from etqan.scheduling.services.subscriptions import end_pause
from etqan.scheduling.services.subscriptions import lock_subscription
from etqan.scheduling.services.subscriptions import renew_subscription
from etqan.scheduling.services.subscriptions import update_slot
from etqan.scheduling.services.subscriptions import update_subscription
```

In `backend/etqan/scheduling/services/__init__.py`, replace:

```python
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
    "mark_attendance",
    "missing_reports",
    "pause_state",
```

with:

```python
    "has_marked_sessions",
    "has_started",
    "has_subscriptions",
    "lock_subscription",
    "mark_attendance",
    "missing_reports",
    "pause_state",
```

In `backend/etqan/scheduling/services/subscriptions.py`, replace:

```python
"""Subscriptions and everything an admin does to them (spec §4.2)."""

from collections.abc import Iterable
from datetime import date
from datetime import time
```

with:

```python
"""Subscriptions and everything an admin does to them (spec §4.2)."""

from collections.abc import Callable
from collections.abc import Iterable
from datetime import date
from datetime import time
```

In `backend/etqan/scheduling/services/subscriptions.py`, replace:

```python


@transaction.atomic
def delete_subscription(subscription: Subscription) -> None:
    """For undoing mistakes: only while none of its sessions is completed,
    marked or cancelled. Then every session goes, past ones too.

    Locked and re-read, as cancel and update are: the subscription row is
    locked first and then its sessions (select_for_update, id order — Plan
    4's lock order, never the reverse), so a mark or cancel racing with this
    delete is never lost to a check taken before the lock."""
    locked = Subscription.objects.select_for_update().get(pk=subscription.pk)
    if rules.live_renewal(locked) is not None:
        # Its renewed_from would become null and its carry-over would change.
        raise ConflictError(
```

with:

```python


@transaction.atomic
def delete_subscription(
    subscription: Subscription, *, before_delete: Callable[[int], None]
) -> None:
    """For undoing mistakes: only while none of its sessions is completed,
    marked or cancelled. Then every session goes, past ones too.

    Locked and re-read, as cancel and update are: the subscription row is
    locked first and then its sessions (select_for_update, id order — Plan
    4's lock order, never the reverse), so a mark or cancel racing with this
    delete is never lost to a check taken before the lock.

    ``before_delete`` is called with the id while the subscription row is
    locked and before anything is checked or deleted; it raises to refuse.
    The API passes billing's invoice check (Plan 6 D2), so scheduling never
    imports billing, and a caller cannot forget to decide."""
    locked = Subscription.objects.select_for_update().get(pk=subscription.pk)
    before_delete(locked.pk)
    if rules.live_renewal(locked) is not None:
        # Its renewed_from would become null and its carry-over would change.
        raise ConflictError(
```

In `backend/etqan/scheduling/services/subscriptions.py`, replace:

```python
    locked.delete()


# ── Pauses ───────────────────────────────────────────────────────────────────


```

with:

```python
    locked.delete()


def lock_subscription(pk: int) -> Subscription | None:
    """The subscription with this id, its row taken `FOR UPDATE`, with its
    student, course and package; None when this academy has none.

    Billing validates an invoice's subscription through this and keeps the
    lock while it writes the invoice, so an invoice and a delete of the same
    subscription never interleave: whichever locks the row second sees the
    other's result (Plan 6 D2). Only the subscription's row is locked."""
    return (
        Subscription.objects.select_for_update(of=("self",))
        .select_related("student__user", "course", "package")
        .filter(pk=pk)
        .first()
    )


# ── Pauses ───────────────────────────────────────────────────────────────────


```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing etqan/scheduling etqan/tenants/tests/test_seed_dev.py`
Expected: PASS, Plan 4's delete lock-shape test included (the hook takes no lock).

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(billing): invoice subscriptions and refuse deleting an invoiced one

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Revenue, overdue and the invoice list's filters

**Files:**
- Create: `backend/etqan/billing/services/summary.py`
- Modify: `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/rules.py`
- Test: `backend/etqan/billing/tests/test_summary.py` (new)

**Interfaces:**
- Consumes: Task 2's `invoices_queryset`, `overdue`; Task 3's writes.
- Produces (re-exported): `summary() -> {"revenue_this_month": [{currency, amount_minor}], "overdue": [{currency, count, balance_minor}]}` (D7); `filter_invoices(invoices, *, status="", student=None, payer=None, subscription=None, issued_from=None, issued_to=None, q="") -> QuerySet` (newest first; `status="overdue"` reads `is_overdue`); `FILTER_STATUSES` (the four statuses plus `overdue`).
- Produces: `summary.month_of(day) -> (first, first_of_next)`, `summary.revenue_this_month()` (the one revenue query), `summary.overdue_by_currency()`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_summary.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

from etqan.academy import services as academy_services
from etqan.billing import services
from etqan.billing.tests.conftest import make_parent
from etqan.scheduling.tests.conftest import make_student


def invoice(student, admin, amount, currency="EGP", **overrides):
    fields = {
        "student_id": student.id,
        "amount_minor": amount,
        "currency": currency,
        "due_on": date(2026, 7, 31),
        "description": "Lessons",
        "by": admin,
        **overrides,
    }
    return services.create_invoice(**fields)


def pay(inv, admin, amount, paid_on):
    services.add_payment(
        inv, amount_minor=amount, method="cash", paid_on=paid_on, by=admin
    )


def test_revenue_is_this_academy_month_per_currency(world, admin, clock):
    # 20:00 UTC on 30 June is already 1 July in Tokyo: July is this month.
    clock.set(datetime(2026, 6, 30, 20, tzinfo=UTC))
    academy_services.update_settings(timezone="Asia/Tokyo")
    egp = invoice(world.student, admin, 10000)
    usd = invoice(world.student, admin, 5000, currency="USD")
    pay(egp, admin, 1000, date(2026, 6, 30))
    pay(egp, admin, 2000, date(2026, 7, 1))
    pay(egp, admin, 3000, date(2026, 7, 31))
    pay(egp, admin, 4000, date(2026, 8, 1))
    pay(usd, admin, 700, date(2026, 7, 2))
    assert services.summary()["revenue_this_month"] == [
        {"currency": "EGP", "amount_minor": 5000},
        {"currency": "USD", "amount_minor": 700},
    ]
    # In UTC it is still 30 June: only June's payment counts.
    academy_services.update_settings(timezone="UTC")
    assert services.summary()["revenue_this_month"] == [
        {"currency": "EGP", "amount_minor": 1000}
    ]


def test_overdue_counts_and_balances_per_currency(world, admin, clock):
    due = {"due_on": date(2026, 6, 5)}
    partial = invoice(world.student, admin, 10000, **due)
    pay(partial, admin, 2500, date(2026, 6, 2))
    invoice(world.student, admin, 4000, **due)
    invoice(world.student, admin, 900, currency="USD", **due)
    paid = invoice(world.student, admin, 300, **due)
    pay(paid, admin, 300, date(2026, 6, 2))
    services.void_invoice(invoice(world.student, admin, 800, **due), by=admin)
    invoice(world.student, admin, 600, due_on=date(2026, 6, 6))
    clock.set(datetime(2026, 6, 6, 9, tzinfo=UTC))
    assert services.summary()["overdue"] == [
        {"currency": "EGP", "count": 2, "balance_minor": 11500},
        {"currency": "USD", "count": 1, "balance_minor": 900},
    ]


def test_the_list_filters(world, admin, clock, subscribe):
    aisha = make_student("Aisha")
    father = make_parent("Omar", aisha)
    sub = subscribe()
    first = invoice(world.student, admin, 1000, subscription_id=sub.pk)
    clock.set(datetime(2026, 6, 3, 8, tzinfo=UTC))
    second = invoice(aisha, admin, 2000, due_on=date(2026, 6, 4))
    pay(second, admin, 500, date(2026, 6, 3))
    third = invoice(aisha, admin, 3000, payer_id=aisha.id)
    services.void_invoice(third, by=admin)
    clock.set(datetime(2026, 6, 5, 8, tzinfo=UTC))

    def ids(**query):
        rows = services.filter_invoices(services.invoices_queryset(), **query)
        return [row.pk for row in rows]

    assert ids() == [third.pk, second.pk, first.pk]
    assert ids(status="unpaid") == [first.pk]
    assert ids(status="partial") == [second.pk]
    assert ids(status="void") == [third.pk]
    assert ids(status="overdue") == [second.pk]
    assert ids(student=aisha.id) == [third.pk, second.pk]
    assert ids(payer=father.id) == [second.pk]
    assert ids(subscription=sub.pk) == [first.pk]
    assert ids(issued_from=date(2026, 6, 2)) == [third.pk, second.pk]
    assert ids(issued_to=date(2026, 6, 2)) == [first.pk]
    assert ids(q="000002") == [second.pk]
    assert ids(q="aish") == [third.pk, second.pk]
    assert ids(q="omar") == [second.pk]
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing/tests/test_summary.py`
Expected: FAIL — `AttributeError: module 'etqan.billing.services' has no attribute 'summary'` (and `filter_invoices`).

- [ ] **Step 3: Implement**

In `backend/etqan/billing/services/__init__.py`, replace:

```python
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.payments import add_payment
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for
```

with:

```python
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.payments import add_payment
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import FILTER_STATUSES
from etqan.billing.services.rules import filter_invoices
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
from etqan.billing.services.subscriptions import invoice_subscription
from etqan.billing.services.subscriptions import payment_statuses
from etqan.billing.services.subscriptions import refuse_if_invoiced

__all__ = [
    "PaymentStatus",
    "add_payment",
    "create_invoice",
    "delete_payment",
    "invoice_subscription",
    "invoices_queryset",
    "next_number",
```

with:

```python
from etqan.billing.services.subscriptions import invoice_subscription
from etqan.billing.services.subscriptions import payment_statuses
from etqan.billing.services.subscriptions import refuse_if_invoiced
from etqan.billing.services.summary import summary

__all__ = [
    "FILTER_STATUSES",
    "PaymentStatus",
    "add_payment",
    "create_invoice",
    "delete_payment",
    "filter_invoices",
    "invoice_subscription",
    "invoices_queryset",
    "next_number",
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
    "refuse_if_invoiced",
    "resolve_payer",
    "status_for",
    "update_invoice",
    "void_invoice",
]
```

with:

```python
    "refuse_if_invoiced",
    "resolve_payer",
    "status_for",
    "summary",
    "update_invoice",
    "void_invoice",
]
```

In `backend/etqan/billing/services/rules.py`, replace:

```python
    return Coalesce(Subquery(paid, output_field=BigIntegerField()), Value(0))


def invoices_queryset() -> QuerySet[Invoice]:
    """Invoices with everything a row shows, in one query: the payer, student
    and creator joined, ``paid_minor`` summed in SQL and ``is_overdue`` from
```

with:

```python
    return Coalesce(Subquery(paid, output_field=BigIntegerField()), Value(0))


FILTER_STATUSES = (*Invoice.Status.values, "overdue")


def filter_invoices(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §5)
    invoices: QuerySet[Invoice],
    *,
    status: str = "",
    student: int | None = None,
    payer: int | None = None,
    subscription: int | None = None,
    issued_from: date | None = None,
    issued_to: date | None = None,
    q: str = "",
) -> QuerySet[Invoice]:
    """The invoice list's filters (spec §5), newest first. ``invoices`` comes
    from `invoices_queryset` (``status="overdue"`` reads its ``is_overdue``);
    people are User ids, dates the academy's calendar."""
    if status == "overdue":
        invoices = invoices.filter(is_overdue=True)
    elif status:
        invoices = invoices.filter(status=status)
    exact = {
        "student__user_id": student,
        "payer_id": payer,
        "subscription_id": subscription,
        "issued_on__gte": issued_from,
        "issued_on__lte": issued_to,
    }
    invoices = invoices.filter(
        **{key: value for key, value in exact.items() if value is not None}
    )
    if q := q.strip():
        invoices = invoices.filter(
            Q(number__icontains=q)
            | Q(student__user__full_name__icontains=q)
            | Q(payer__full_name__icontains=q)
        )
    return invoices.order_by("-id")


def invoices_queryset() -> QuerySet[Invoice]:
    """Invoices with everything a row shows, in one query: the payer, student
    and creator joined, ``paid_minor`` summed in SQL and ``is_overdue`` from
```

Create `backend/etqan/billing/services/summary.py`:

```python
"""The admin home's money figures (spec §4.5). Never summed across
currencies (P6-6)."""

from datetime import date
from datetime import timedelta

from django.db.models import Count
from django.db.models import F
from django.db.models import Sum

from etqan.billing import clock
from etqan.billing.models import Payment
from etqan.billing.services import rules


def month_of(day: date) -> tuple[date, date]:
    """The first day of ``day``'s month and the first day of the next."""
    first = day.replace(day=1)
    return first, (first + timedelta(days=32)).replace(day=1)


def revenue_this_month() -> list[dict]:
    """The one revenue query: payments whose `paid_on` falls in the academy's
    current calendar month (its timezone decides the month near midnight),
    summed per currency, in currency order."""
    first, following = month_of(clock.today())
    rows = (
        Payment.objects.filter(paid_on__gte=first, paid_on__lt=following)
        .values(currency=F("invoice__currency"))
        .annotate(amount_minor=Sum("amount_minor"))
        .order_by("currency")
    )
    return [
        {"currency": row["currency"], "amount_minor": row["amount_minor"]}
        for row in rows
    ]


def overdue_by_currency() -> list[dict]:
    """How many invoices are overdue and their balance, per currency."""
    rows = (
        rules.invoices_queryset()
        .filter(is_overdue=True)
        .values("currency")
        .annotate(
            count=Count("pk"),
            balance_minor=Sum(F("amount_minor") - F("paid_minor")),
        )
        .order_by("currency")
    )
    return [
        {
            "currency": row["currency"],
            "count": row["count"],
            "balance_minor": row["balance_minor"],
        }
        for row in rows
    ]


def summary() -> dict:
    return {
        "revenue_this_month": revenue_this_month(),
        "overdue": overdue_by_currency(),
    }
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(billing): revenue and overdue summary and the invoice list filters

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: API: invoices, payments, summary and payers

**Files:**
- Create: `backend/etqan/billing/api/payloads.py`, `backend/etqan/billing/api/serializers.py`, `backend/etqan/billing/api/urls.py`, `backend/etqan/billing/api/views.py`, `backend/etqan/billing/scopes.py`
- Modify: `backend/config/api_router.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/invoices.py`, `backend/etqan/billing/services/payers.py`
- Test: `backend/etqan/billing/tests/test_api.py` (new)

**Interfaces:**
- Consumes: Tasks 2–5's services.
- Produces: `etqan.billing.scopes.scope_for(user, queryset, *, via="")` (D13) and `services.student_of(student_id) -> StudentProfile` (a 400 on `student`), which `create_invoice` now uses.
- Produces: `payloads.invoice_row(invoice, *, is_admin)`, `payment_row(payment, *, is_admin)`, `invoice_detail(invoice, *, is_admin)` and `payers_payload(student_user_id, people)` (D4).
- Routes (`/api/v1/billing/`, D4, D12, D13):
  - `invoices/` GET (filters, pagination, admin-only `?format=csv`) and POST;
  - `invoices/<id>/` GET and PATCH;
  - `invoices/<id>/void/` POST;
  - `invoices/<id>/payments/` GET and POST;
  - `payments/<id>/` DELETE;
  - `summary/` GET;
  - `payers/?student=` GET.
- Produces: `views.PAYMENTS` (the payments prefetch), `views.detail(pk, request, *, code)` and `views.invoice_or_404(request, pk)`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_api.py`:

```python
import csv
import io
from datetime import date

import pytest
from django.contrib.auth.models import AnonymousUser
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.billing import services
from etqan.billing.models import Invoice
from etqan.billing.models import Payment
from etqan.billing.scopes import scope_for
from etqan.billing.tests.conftest import make_parent
from etqan.identity import services as identity_services
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import until_pk_exceeds

URL = "/api/v1/billing/invoices/"


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def body(student, /, **overrides):
    return {
        "student": student.id,
        "amount_minor": 150000,
        "due_on": "2026-06-08",
        "description": "Tajweed — June",
        **overrides,
    }


def create(client, student, **overrides):
    resp = client.post(URL, body(student, **overrides), format="json")
    assert resp.status_code == 201, resp.json()
    return resp.json()


def test_admin_issues_pays_and_reads_an_invoice(api_for, world):
    father = make_parent("Omar", world.student)
    admin = api_for("admin")
    data = create(admin, world.student, currency="EGP", notes="Sibling rate")
    assert {
        key: data[key]
        for key in (
            "number",
            "status",
            "is_overdue",
            "amount_minor",
            "paid_minor",
            "balance_minor",
            "currency",
            "issued_on",
            "due_on",
            "notes",
            "subscription_id",
            "payments",
        )
    } == {
        "number": "INV-000001",
        "status": "unpaid",
        "is_overdue": False,
        "amount_minor": 150000,
        "paid_minor": 0,
        "balance_minor": 150000,
        "currency": "EGP",
        "issued_on": "2026-06-01",
        "due_on": "2026-06-08",
        "notes": "Sibling rate",
        "subscription_id": None,
        "payments": [],
    }
    assert data["student"] == {"id": world.student.id, "full_name": "Yusuf"}
    assert data["payer"] == {"id": father.id, "full_name": "Omar"}
    assert data["created_by"]["id"] == admin.user.id
    paid = admin.post(
        f"{URL}{data['id']}/payments/",
        {
            "amount_minor": 50000,
            "method": "instapay",
            "paid_on": "2026-06-02",
            "reference": "IP-9",
            "notes": "First half",
        },
        format="json",
    )
    after = paid.json()
    assert paid.status_code == 201, after
    assert (after["status"], after["paid_minor"], after["balance_minor"]) == (
        "partial",
        50000,
        100000,
    )
    (payment,) = after["payments"]
    assert (payment["method"], payment["reference"], payment["notes"]) == (
        "instapay",
        "IP-9",
        "First half",
    )
    assert payment["recorded_by"]["id"] == admin.user.id
    listed = admin.get(f"{URL}{data['id']}/payments/").json()
    assert [p["id"] for p in listed] == [payment["id"]]
    edited = admin.patch(
        f"{URL}{data['id']}/", {"due_on": "2026-06-15", "notes": ""}, format="json"
    )
    assert (edited.json()["due_on"], edited.json()["notes"]) == ("2026-06-15", "")
    assert admin.put(f"{URL}{data['id']}/", {}, format="json").status_code == 405
    gone = admin.delete(f"/api/v1/billing/payments/{payment['id']}/")
    assert gone.status_code == 204
    voided = admin.post(f"{URL}{data['id']}/void/")
    assert voided.json()["status"] == "void"
    assert voided.json()["voided_at"] is not None


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"amount_minor": 0}, "amount_minor"),
        ({"due_on": "2026-05-31"}, "due_on"),
        ({"due_on": "soon"}, "due_on"),
        ({"description": ""}, "description"),
        ({"student": 999999}, "student"),
    ],
)
def test_bad_invoice_bodies_are_field_errors(api_for, world, overrides, field):
    resp = api_for("admin").post(URL, body(world.student, **overrides), format="json")
    assert resp.status_code == 400
    assert field in resp.json()


def test_the_payer_and_subscription_must_be_the_students(api_for, world, subscribe):
    admin = api_for("admin")
    aisha = make_student("Aisha")
    stranger = make_parent("Stranger", aisha)
    theirs = subscribe(student_id=aisha.id)
    resp = admin.post(URL, body(world.student, payer=stranger.id), format="json")
    assert resp.status_code == 400
    assert "payer" in resp.json()
    resp = admin.post(URL, body(world.student, subscription=theirs.pk), format="json")
    assert resp.status_code == 400
    assert "subscription" in resp.json()


def test_payments_refuse_overpaying_and_bad_methods(api_for, world):
    admin = api_for("admin")
    invoice = create(admin, world.student, amount_minor=1000)
    url = f"{URL}{invoice['id']}/payments/"
    pay = {"amount_minor": 1001, "method": "cash", "paid_on": "2026-06-01"}
    resp = admin.post(url, pay, format="json")
    assert resp.status_code == 400
    assert "amount_minor" in resp.json()
    resp = admin.post(url, {**pay, "amount_minor": 10, "method": "cheque"})
    assert resp.status_code == 400
    assert "method" in resp.json()
    assert admin.get(f"{URL}{invoice['id']}/").json()["status"] == "unpaid"


def test_rule_refusals_are_409_with_a_code(api_for, world):
    admin = api_for("admin")
    invoice = create(admin, world.student, amount_minor=1000)
    url = f"{URL}{invoice['id']}/"
    admin.post(
        f"{url}payments/",
        {"amount_minor": 10, "method": "cash", "paid_on": "2026-06-01"},
        format="json",
    )
    for resp, code in (
        (admin.post(f"{url}void/"), "billing.has_payments"),
        (admin.patch(url, {"amount_minor": 5}, format="json"), "billing.has_payments"),
    ):
        assert resp.status_code == 409
        assert resp.json() == {"detail": resp.json()["detail"], "code": code}
    other = create(admin, world.student)
    admin.post(f"{URL}{other['id']}/void/")
    for resp in (
        admin.post(f"{URL}{other['id']}/void/"),
        admin.patch(f"{URL}{other['id']}/", {"notes": "x"}, format="json"),
        admin.post(
            f"{URL}{other['id']}/payments/",
            {"amount_minor": 10, "method": "cash", "paid_on": "2026-06-01"},
            format="json",
        ),
    ):
        assert resp.status_code == 409
        assert resp.json()["code"] == "billing.invoice_void"


def test_the_list_filters_and_refuses_bad_filters(api_for, world):
    admin = api_for("admin")
    aisha = make_student("Aisha")
    mine = create(admin, world.student)
    theirs = create(admin, aisha, amount_minor=500)
    admin.post(
        f"{URL}{theirs['id']}/payments/",
        {"amount_minor": 100, "method": "cash", "paid_on": "2026-06-01"},
        format="json",
    )

    def ids(query):
        resp = admin.get(f"{URL}{query}")
        assert resp.status_code == 200, resp.json()
        return [row["id"] for row in resp.json()["results"]]

    assert ids("") == [theirs["id"], mine["id"]]
    assert ids("?status=partial") == [theirs["id"]]
    assert ids(f"?student={world.student.id}") == [mine["id"]]
    assert ids("?q=aish&issued_from=2026-06-01&issued_to=2026-06-01") == [theirs["id"]]
    for query, field in (
        ("?status=late", "status"),
        ("?student=abc", "student"),
        ("?issued_from=June", "issued_from"),
    ):
        resp = admin.get(f"{URL}{query}")
        assert resp.status_code == 400
        assert field in resp.json()


def test_csv_has_the_filtered_rows(api_for, world):
    admin = api_for("admin")
    create(admin, world.student, currency="EGP")
    create(admin, make_student("Aisha"), amount_minor=500)
    resp = admin.get(f"{URL}?student={world.student.id}&format=csv")
    assert resp.status_code == 200
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0] == [
        "Number",
        "Student",
        "Payer",
        "Description",
        "Amount (minor units)",
        "Paid (minor units)",
        "Balance (minor units)",
        "Currency",
        "Issued on",
        "Due on",
        "Status",
        "Overdue",
    ]
    assert rows[1:] == [
        [
            "INV-000001",
            "Yusuf",
            "Yusuf",
            "Tajweed — June",
            "150000",
            "0",
            "150000",
            "EGP",
            "2026-06-01",
            "2026-06-08",
            "unpaid",
            "no",
        ]
    ]


def test_the_list_costs_the_same_queries_for_two_or_six_rows(api_for, world):
    admin = api_for("admin")

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            assert admin.get(URL).status_code == 200
        return len(ctx.captured_queries)

    for n in range(2):
        student = make_student(f"S{n}")
        make_parent(f"P{n}", student)
        create(admin, student)
    two = queries()
    for n in range(2, 6):
        create(admin, make_student(f"S{n}"))
    assert queries() == two


def test_summary_and_payers(api_for, world):
    admin = api_for("admin")
    father = make_parent("Omar", world.student)
    invoice = create(admin, world.student, amount_minor=1000, currency="EGP")
    admin.post(
        f"{URL}{invoice['id']}/payments/",
        {"amount_minor": 400, "method": "cash", "paid_on": "2026-06-01"},
        format="json",
    )
    assert admin.get("/api/v1/billing/summary/").json() == {
        "revenue_this_month": [{"currency": "EGP", "amount_minor": 400}],
        "overdue": [],
    }
    resp = admin.get(f"/api/v1/billing/payers/?student={world.student.id}")
    assert resp.json() == {
        "default": father.id,
        "choices": [
            {"id": father.id, "full_name": "Omar", "relation": "guardian"},
            {"id": world.student.id, "full_name": "Yusuf", "relation": "student"},
        ],
    }
    for query in ("", f"?student={world.teacher.id}"):
        resp = admin.get(f"/api/v1/billing/payers/{query}")
        assert resp.status_code == 400
        assert "student" in resp.json()


@pytest.fixture
def families(api_for, world):
    """Yusuf's invoice paid by his father Omar, one Yusuf pays himself, and
    Aisha's invoice paid by her mother Huda."""
    admin = api_for("admin")
    omar = make_parent("Omar", world.student)
    aisha = make_student("Aisha")
    huda = make_parent("Huda", aisha)
    by_father = create(admin, world.student, notes="Staff only")
    by_himself = create(admin, world.student, payer=world.student.id)
    hers = create(admin, aisha)
    for invoice in (by_father, hers):
        admin.post(
            f"{URL}{invoice['id']}/payments/",
            {
                "amount_minor": 10,
                "method": "cash",
                "paid_on": "2026-06-01",
                "notes": "x",
            },
            format="json",
        )
    return {
        "admin": admin,
        "omar": omar,
        "huda": huda,
        "yusuf": world.student,
        "teacher": world.teacher,
        "invoices": (by_father["id"], by_himself["id"], hers["id"]),
    }


def test_parents_and_students_read_their_family_only(families):
    by_father, by_himself, hers = families["invoices"]
    cases = [
        (families["omar"], {by_father, by_himself}),
        (families["yusuf"], {by_father, by_himself}),
        (families["huda"], {hers}),
    ]
    for user, visible in cases:
        client = as_user(user)
        rows = client.get(URL).json()["results"]
        assert {row["id"] for row in rows} == visible, user.full_name
        for row in rows:
            assert "notes" not in row
            assert "created_by" not in row
        for pk in (by_father, by_himself, hers):
            expected = 200 if pk in visible else 404
            assert client.get(f"{URL}{pk}/").status_code == expected
            assert client.get(f"{URL}{pk}/payments/").status_code == expected
        detail = client.get(f"{URL}{min(visible)}/").json()
        for payment in detail["payments"]:
            assert "notes" not in payment
            assert "recorded_by" not in payment
    # A parent who pays for a child they are no longer linked to still
    # sees what they pay.
    identity_services.unlink_guardian(families["omar"], families["yusuf"])
    rows = as_user(families["omar"]).get(URL).json()["results"]
    assert [row["id"] for row in rows] == [by_father]


def test_every_role_on_every_route(families, api_for):
    pk = families["invoices"][0]
    payment = Payment.objects.filter(invoice_id=pk).first().pk
    writes = [
        ("post", URL, body(families["yusuf"])),
        ("patch", f"{URL}{pk}/", {"notes": "x"}),
        ("post", f"{URL}{pk}/void/", {}),
        (
            "post",
            f"{URL}{pk}/payments/",
            {"amount_minor": 1, "method": "cash", "paid_on": "2026-06-01"},
        ),
        ("delete", f"/api/v1/billing/payments/{payment}/", None),
        ("get", "/api/v1/billing/summary/", None),
        ("get", f"/api/v1/billing/payers/?student={families['yusuf'].id}", None),
        ("get", f"{URL}?format=csv", None),
    ]
    reads = [URL, f"{URL}{pk}/", f"{URL}{pk}/payments/"]
    clients = {
        "teacher": as_user(families["teacher"]),
        "parent": as_user(families["omar"]),
        "student": as_user(families["yusuf"]),
        "anonymous": APIClient(),
    }
    for role, client in clients.items():
        for path in reads:
            expected = 200 if role in ("parent", "student") else 403
            assert client.get(path).status_code == expected, (role, path)
        for method, path, data in writes:
            resp = getattr(client, method)(path, data, format="json")
            assert resp.status_code == 403, (role, method, path)
            assert "csv" not in resp.headers.get("Content-Type", "")
    admin = families["admin"]
    # The invoice Yusuf pays himself has no payments to refuse a void.
    unpaid = f"{URL}{families['invoices'][1]}/void/"
    for method, path, data in writes:
        target = unpaid if path.endswith("/void/") else path
        resp = getattr(admin, method)(target, data, format="json")
        assert resp.status_code in (200, 201, 204), (method, target, resp.content)


def test_another_academy_never_leaks(api_for, world, tenants):
    admin = api_for("admin")
    mine = create(admin, world.student)
    invoice_ceiling = Invoice.objects.aggregate(m=Max("pk"))["m"]
    payment_ceiling = Payment.objects.aggregate(m=Max("pk"))["m"] or 0
    with tenant_context(tenants.other):
        other = build_world()
        identity_services.update_person(
            other.student, fields={"full_name": "Layla Other"}
        )

        def their_invoice():
            return services.create_invoice(
                student_id=other.student.id,
                amount_minor=777,
                due_on=date(2026, 6, 8),
                description="Theirs",
                by=None,
            )

        theirs = until_pk_exceeds(Invoice, invoice_ceiling, their_invoice)
        their_payment = until_pk_exceeds(
            Payment,
            payment_ceiling,
            lambda: services.add_payment(
                theirs,
                amount_minor=77,
                method="cash",
                paid_on=date(2026, 6, 1),
                by=None,
            ),
        )
    assert theirs.pk > invoice_ceiling
    listing = admin.get(URL)
    assert [row["id"] for row in listing.json()["results"]] == [mine["id"]]
    csv_body = admin.get(f"{URL}?format=csv").content
    assert b"Layla Other" not in csv_body
    assert b"Yusuf" in csv_body
    for path in (
        f"{URL}{theirs.pk}/",
        f"{URL}{theirs.pk}/payments/",
    ):
        resp = admin.get(path)
        assert resp.status_code == 404, path
        assert b"Layla Other" not in resp.content
    assert admin.post(f"{URL}{theirs.pk}/void/").status_code == 404
    resp = admin.delete(f"/api/v1/billing/payments/{their_payment.pk}/")
    assert resp.status_code == 404
    assert admin.get("/api/v1/billing/summary/").json()["revenue_this_month"] == []
    with tenant_context(tenants.other):
        theirs.refresh_from_db()
        assert (theirs.status, Payment.objects.filter(invoice=theirs).count()) == (
            "partial",
            1,
        )


def test_scope_leaves_a_teacher_and_a_visitor_nothing(families):
    # The routes refuse them first (403); the scope agrees on its own.
    invoices = Invoice.objects.all()
    assert invoices.count() == 3
    assert not scope_for(families["teacher"], invoices).exists()
    assert not scope_for(AnonymousUser(), invoices).exists()
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing/tests/test_api.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'etqan.billing.scopes'`, and every route answers 404.

- [ ] **Step 3: Implement**

In `backend/config/api_router.py`, replace:

```python
    path("people/", include("etqan.identity.api.people_urls")),
    # subscriptions/, pauses/, slots/, schedule/ (spec §5).
    path("", include("etqan.scheduling.api.urls")),
    # OpenAPI schema (drf-spectacular) + Swagger UI / ReDoc browsers.
    path("schema/", SpectacularAPIView.as_view(), name="schema"),
    path(
```

with:

```python
    path("people/", include("etqan.identity.api.people_urls")),
    # subscriptions/, pauses/, slots/, schedule/ (spec §5).
    path("", include("etqan.scheduling.api.urls")),
    # invoices/, payments/, summary/, payers/ (Plan 6 spec §5).
    path("billing/", include("etqan.billing.api.urls")),
    # OpenAPI schema (drf-spectacular) + Swagger UI / ReDoc browsers.
    path("schema/", SpectacularAPIView.as_view(), name="schema"),
    path(
```

Create `backend/etqan/billing/api/payloads.py`:

```python
"""JSON shapes for billing (plan D4). `notes`, `created_by` and a payment's
`notes` and `recorded_by` are for admins only (spec §4.6); the flag is
keyword-only with no default, so a caller cannot forget it."""

STAFF_ONLY_INVOICE_FIELDS = ("notes", "created_by")
STAFF_ONLY_PAYMENT_FIELDS = ("notes", "recorded_by")


def _person(user) -> dict | None:
    if user is None:
        return None
    return {"id": user.pk, "full_name": user.full_name}


def invoice_row(invoice, *, is_admin: bool) -> dict:
    """Read ``invoice`` from `services.invoices_queryset()`: it carries
    ``paid_minor`` and ``is_overdue``."""
    row = {
        "id": invoice.pk,
        "number": invoice.number,
        "status": invoice.status,
        "is_overdue": invoice.is_overdue,
        "student": _person(invoice.student.user),
        "payer": _person(invoice.payer),
        "subscription_id": invoice.subscription_id,
        "description": invoice.description,
        "amount_minor": invoice.amount_minor,
        "paid_minor": invoice.paid_minor,
        "balance_minor": invoice.amount_minor - invoice.paid_minor,
        "currency": invoice.currency,
        "issued_on": invoice.issued_on,
        "due_on": invoice.due_on,
        "voided_at": invoice.voided_at,
        "created_at": invoice.created_at,
        "notes": invoice.notes,
        "created_by": _person(invoice.created_by),
    }
    if not is_admin:
        for field in STAFF_ONLY_INVOICE_FIELDS:
            row.pop(field)
    return row


def payment_row(payment, *, is_admin: bool) -> dict:
    row = {
        "id": payment.pk,
        "invoice_id": payment.invoice_id,
        "amount_minor": payment.amount_minor,
        "method": payment.method,
        "paid_on": payment.paid_on,
        "reference": payment.reference,
        "created_at": payment.created_at,
        "notes": payment.notes,
        "recorded_by": _person(payment.recorded_by),
    }
    if not is_admin:
        for field in STAFF_ONLY_PAYMENT_FIELDS:
            row.pop(field)
    return row


def invoice_detail(invoice, *, is_admin: bool) -> dict:
    """The row plus its payments (prefetched with ``recorded_by``)."""
    return {
        **invoice_row(invoice, is_admin=is_admin),
        "payments": [
            payment_row(payment, is_admin=is_admin)
            for payment in invoice.payments.all()
        ],
    }


def payers_payload(student_user_id: int, people) -> dict:
    """The payer choices for one student, the default first (P6-4)."""
    return {
        "default": people[0].pk,
        "choices": [
            {
                **_person(person),
                "relation": "student" if person.pk == student_user_id else "guardian",
            }
            for person in people
        ],
    }
```

Create `backend/etqan/billing/api/serializers.py`:

```python
"""Request bodies and list queries (spec §5). Responses are built in
`payloads`."""

from rest_framework import serializers

from etqan.billing import services
from etqan.billing.models import Payment


def _id(**kwargs):
    return serializers.IntegerField(min_value=1, **kwargs)


class InvoiceQueryInput(serializers.Serializer):
    # A bad value is a 400 on its field, never silently "everything".
    status = serializers.ChoiceField(choices=services.FILTER_STATUSES, required=False)
    student = _id(required=False)
    payer = _id(required=False)
    subscription = _id(required=False)
    issued_from = serializers.DateField(required=False)
    issued_to = serializers.DateField(required=False)
    q = serializers.CharField(required=False, allow_blank=True)


class InvoiceCreateInput(serializers.Serializer):
    student = _id()
    payer = _id(required=False)
    subscription = _id(required=False)
    amount_minor = serializers.IntegerField(min_value=1)
    currency = serializers.CharField(max_length=3, required=False)
    due_on = serializers.DateField()
    description = serializers.CharField()
    notes = serializers.CharField(required=False, allow_blank=True)


class InvoiceUpdateInput(serializers.Serializer):
    description = serializers.CharField(required=False)
    due_on = serializers.DateField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True)
    amount_minor = serializers.IntegerField(min_value=1, required=False)


class PaymentInput(serializers.Serializer):
    amount_minor = serializers.IntegerField(min_value=1)
    method = serializers.ChoiceField(choices=Payment.Method.choices)
    paid_on = serializers.DateField()
    reference = serializers.CharField(max_length=120, required=False, allow_blank=True)
    notes = serializers.CharField(required=False, allow_blank=True)


class PayersQueryInput(serializers.Serializer):
    student = _id()
```

Create `backend/etqan/billing/api/urls.py`:

```python
from django.urls import path

from etqan.billing.api import views

app_name = "billing"
urlpatterns = [
    path("invoices/", views.InvoiceListView.as_view(), name="invoices"),
    path("invoices/<int:pk>/", views.InvoiceDetailView.as_view(), name="invoice"),
    path("invoices/<int:pk>/void/", views.VoidView.as_view(), name="void"),
    path(
        "invoices/<int:pk>/payments/",
        views.PaymentListView.as_view(),
        name="payments",
    ),
    path("payments/<int:pk>/", views.PaymentDetailView.as_view(), name="payment"),
    path("summary/", views.SummaryView.as_view(), name="summary"),
    path("payers/", views.PayersView.as_view(), name="payers"),
]
```

Create `backend/etqan/billing/api/views.py`:

```python
"""Billing endpoints (spec §5). Thin: parse, call one service, re-read and
arrange a payload."""

from django.db.models import Prefetch
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.billing import services
from etqan.billing.api import payloads
from etqan.billing.api.serializers import InvoiceCreateInput
from etqan.billing.api.serializers import InvoiceQueryInput
from etqan.billing.api.serializers import InvoiceUpdateInput
from etqan.billing.api.serializers import PayersQueryInput
from etqan.billing.api.serializers import PaymentInput
from etqan.billing.models import Payment
from etqan.billing.scopes import scope_for
from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import role_of

# Spec §4.6: admins do everything; parents and students read what
# `scope_for` leaves them; teachers get nothing (403).
READERS = IsAdmin | (ReadOnly & (IsParent | IsStudent))
CSV_COLUMNS = (
    ("number", "Number"),
    ("student", "Student"),
    ("payer", "Payer"),
    ("description", "Description"),
    ("amount_minor", "Amount (minor units)"),
    ("paid_minor", "Paid (minor units)"),
    ("balance_minor", "Balance (minor units)"),
    ("currency", "Currency"),
    ("issued_on", "Issued on"),
    ("due_on", "Due on"),
    ("status", "Status"),
    ("is_overdue", "Overdue"),
)
# Body keys (spec §5) → service keyword arguments.
ID_FIELDS = {
    "student": "student_id",
    "payer": "payer_id",
    "subscription": "subscription_id",
}
PAYMENTS = Prefetch("payments", Payment.objects.select_related("recorded_by"))


def _ids(data: dict) -> dict:
    return {ID_FIELDS.get(key, key): value for key, value in data.items()}


def _is_admin(request) -> bool:
    return role_of(request.user) == "admin"


def invoice_or_404(request, pk):
    invoices = scope_for(request.user, services.invoices_queryset())
    return get_object_or_404(invoices.prefetch_related(PAYMENTS), pk=pk)


def detail(pk, request, *, code=status.HTTP_200_OK) -> Response:
    """A fresh read of what a write changed."""
    invoice = services.invoices_queryset().prefetch_related(PAYMENTS).get(pk=pk)
    payload = payloads.invoice_detail(invoice, is_admin=_is_admin(request))
    return Response(payload, status=code)


class InvoiceListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [READERS]
    csv_filename = "invoices"
    csv_columns = CSV_COLUMNS

    def get(self, request):
        query = InvoiceQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        invoices = services.filter_invoices(
            scope_for(request.user, services.invoices_queryset()),
            **query.validated_data,
        )
        if self.wants_csv():
            # Raised, not returned: CSVExportMixin answers the error as JSON.
            if not _is_admin(request):
                raise PermissionDenied("CSV export is for admins only.")
            return self.csv_response(
                [payloads.invoice_row(i, is_admin=True) for i in invoices]
            )
        page = self.paginate_queryset(invoices)
        is_admin = _is_admin(request)
        return self.get_paginated_response(
            [payloads.invoice_row(i, is_admin=is_admin) for i in page]
        )

    def post(self, request):
        body = InvoiceCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        invoice = services.create_invoice(**_ids(body.validated_data), by=request.user)
        return detail(invoice.pk, request, code=status.HTTP_201_CREATED)


class InvoiceDetailView(APIView):
    permission_classes = [READERS]

    def get(self, request, pk):
        invoice = invoice_or_404(request, pk)
        return Response(payloads.invoice_detail(invoice, is_admin=_is_admin(request)))

    def patch(self, request, pk):
        invoice = invoice_or_404(request, pk)
        body = InvoiceUpdateInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_invoice(invoice, **body.validated_data)
        return detail(pk, request)


class VoidView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        services.void_invoice(invoice_or_404(request, pk), by=request.user)
        return detail(pk, request)


class PaymentListView(APIView):
    permission_classes = [READERS]

    def get(self, request, pk):
        invoice = invoice_or_404(request, pk)
        is_admin = _is_admin(request)
        return Response(
            [payloads.payment_row(p, is_admin=is_admin) for p in invoice.payments.all()]
        )

    def post(self, request, pk):
        invoice = invoice_or_404(request, pk)
        body = PaymentInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.add_payment(invoice, **body.validated_data, by=request.user)
        return detail(pk, request, code=status.HTTP_201_CREATED)


class PaymentDetailView(APIView):
    permission_classes = [IsAdmin]

    def delete(self, request, pk):
        payment = get_object_or_404(Payment.objects.select_related("invoice"), pk=pk)
        services.delete_payment(payment)
        return Response(status=status.HTTP_204_NO_CONTENT)


class SummaryView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(services.summary())


class PayersView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        query = PayersQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        student = services.student_of(query.validated_data["student"])
        people = services.payer_choices(student.user_id)
        return Response(payloads.payers_payload(student.user_id, people))
```

Create `backend/etqan/billing/scopes.py`:

```python
"""Who sees which invoices and payments (spec §4.6). Out of scope → 404."""

from django.db.models import Q

from etqan.identity import services as identity_services
from etqan.platform.permissions import role_of


def scope_for(user, queryset, *, via: str = ""):
    """Filter an Invoice queryset (``via=""``), or one that reaches an invoice
    through ``via`` (``"invoice"`` for payments). A parent reads the invoices
    they pay and those of their children; a student reads their own, as the
    student or the payer; a teacher reads none."""
    role = role_of(user)
    prefix = f"{via}__" if via else ""
    if role == "admin":
        return queryset
    if role == "student":
        return queryset.filter(
            Q(**{f"{prefix}student__user": user}) | Q(**{f"{prefix}payer": user})
        )
    if role == "parent":
        children = identity_services.get_children(user.pk)
        return queryset.filter(
            Q(**{f"{prefix}payer": user}) | Q(**{f"{prefix}student__in": children})
        )
    return queryset.none()
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
from etqan.billing.services.numbering import next_number
from etqan.billing.services.payers import payer_choices
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.payments import add_payment
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import FILTER_STATUSES
```

with:

```python
from etqan.billing.services.numbering import next_number
from etqan.billing.services.payers import payer_choices
from etqan.billing.services.payers import resolve_payer
from etqan.billing.services.payers import student_of
from etqan.billing.services.payments import add_payment
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import FILTER_STATUSES
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
    "refuse_if_invoiced",
    "resolve_payer",
    "status_for",
    "summary",
    "update_invoice",
    "void_invoice",
```

with:

```python
    "refuse_if_invoiced",
    "resolve_payer",
    "status_for",
    "student_of",
    "summary",
    "update_invoice",
    "void_invoice",
```

In `backend/etqan/billing/services/invoices.py`, replace:

```python
from etqan.billing.services import numbering
from etqan.billing.services import payers
from etqan.billing.services import rules
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.scheduling import services as scheduling_services


def _student(student_id: int):
    profile = identity_services.get_student_profile(student_id)
    if profile is None or profile.user.role != "student":
        raise ValidationError("Choose a student.", field="student")
    return profile


def _subscription_of(student, subscription_id: int):
    """The student's subscription with this id, its row locked until the
    invoice is written (subscription before invoice, plan D8); a 400 on
```

with:

```python
from etqan.billing.services import numbering
from etqan.billing.services import payers
from etqan.billing.services import rules
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.scheduling import services as scheduling_services


def _subscription_of(student, subscription_id: int):
    """The student's subscription with this id, its row locked until the
    invoice is written (subscription before invoice, plan D8); a 400 on
```

In `backend/etqan/billing/services/invoices.py`, replace:

```python
    defaults to the student's first guardian (P6-4). A subscription must be
    the student's, and is locked until the invoice is written (plan D8); the
    currency defaults to the subscription's, else the academy's."""
    student = _student(student_id)
    default_currency = academy_services.get_settings().default_currency
    if subscription_id is not None:
        subscription = _subscription_of(student, subscription_id)
```

with:

```python
    defaults to the student's first guardian (P6-4). A subscription must be
    the student's, and is locked until the invoice is written (plan D8); the
    currency defaults to the subscription's, else the academy's."""
    student = payers.student_of(student_id)
    default_currency = academy_services.get_settings().default_currency
    if subscription_id is not None:
        subscription = _subscription_of(student, subscription_id)
```

In `backend/etqan/billing/services/payers.py`, replace:

```python
from etqan.platform.exceptions import ValidationError


def payer_choices(student_user_id: int) -> list:
    """The people who may pay a student's invoices, the default first: their
    guardians, the earliest-linked first, then the student. The one payer
```

with:

```python
from etqan.platform.exceptions import ValidationError


def student_of(student_id: int):
    """The student profile of this User id; a 400 on ``student`` otherwise."""
    profile = identity_services.get_student_profile(student_id)
    if profile is None or profile.user.role != "student":
        raise ValidationError("Choose a student.", field="student")
    return profile


def payer_choices(student_user_id: int) -> list:
    """The people who may pay a student's invoices, the default first: their
    guardians, the earliest-linked first, then the student. The one payer
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(billing): invoice, payment, summary and payer API

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Scheduling API: invoice on create and renew, and payment status for admins

**Files:**
- Modify: `backend/etqan/scheduling/api/payloads.py`, `backend/etqan/scheduling/api/views.py`
- Test: `backend/etqan/billing/tests/test_subscription_api.py` (new), `backend/etqan/scheduling/tests/test_api_subscriptions.py`

**Interfaces:**
- Consumes: Task 4's `invoice_subscription`, `payment_statuses`, `PaymentStatus`.
- Produces: `POST /api/v1/subscriptions/` and `POST /api/v1/subscriptions/<id>/renew/` call `billing_services.invoice_subscription(new.pk, by=request.user)` right after scheduling, inside `transaction.atomic()` (P6-1). A billing error rolls back the subscription, its sessions and a renewal's changes to the old term.
- Produces: `payloads.subscription_row(sub, values, payment: PaymentStatus | None, *, is_admin)`; admin rows and details carry `payment_status` and `payment_overdue`; the CSV gains `Payment status`.
- Changes an existing test: `test_renew_cancel_and_delete` now voids the renewal's invoice before deleting it.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_subscription_api.py`:

```python
"""P6-1 through HTTP: scheduling's create and renew views invoice in the same
transaction, delete is refused while invoiced, and admins see each
subscription's payment status."""

from datetime import UTC
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from etqan.academy import services as academy_services
from etqan.billing import services
from etqan.billing.models import Invoice
from etqan.billing.tests.conftest import make_parent
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import make_student

URL = "/api/v1/subscriptions/"
SLOTS = [{"weekdays": [0, 2], "start_time": "18:00"}]


def body(world, student=None, **overrides):
    return {
        "student": (student or world.student).id,
        "course": world.course.id,
        "teacher": world.teacher.id,
        "package": world.package.id,
        "starts_on": "2026-06-01",
        "slots": SLOTS,
        **overrides,
    }


def subscribe(client, world, student=None, **overrides):
    resp = client.post(URL, body(world, student, **overrides), format="json")
    assert resp.status_code == 201, resp.json()
    return resp.json()


def invoices_of(subscription_id):
    return list(Invoice.objects.filter(subscription_id=subscription_id))


def test_creating_and_renewing_invoice_each_term(api_for, world):
    admin = api_for("admin")
    father = make_parent("Omar", world.student)
    sub = subscribe(admin, world, price_minor=120000)
    (first,) = invoices_of(sub["id"])
    assert (first.amount_minor, first.currency, first.payer, first.created_by) == (
        120000,
        "EGP",
        father,
        admin.user,
    )
    renewal = admin.post(f"{URL}{sub['id']}/renew/", {}, format="json").json()
    (second,) = invoices_of(renewal["id"])
    assert (second.number, second.amount_minor) == ("INV-000002", 120000)
    assert len(invoices_of(sub["id"])) == 1


def test_nothing_is_invoiced_when_switched_off_or_free(api_for, world):
    admin = api_for("admin")
    free = subscribe(admin, world, price_minor=0)
    paid = subscribe(admin, world, make_student("Aisha"))
    academy_services.update_settings(auto_invoice_on_subscription=False)
    unbilled = subscribe(admin, world, make_student("Zaid"))
    assert invoices_of(free["id"]) == invoices_of(unbilled["id"]) == []
    # The same request with the switch on is invoiced.
    assert len(invoices_of(paid["id"])) == 1


@pytest.fixture
def break_billing(monkeypatch):
    """Call it to make every automatic invoice fail from then on. The views
    look `invoice_subscription` up on the services module at call time."""

    def fail(subscription_id, *, by):
        raise ConflictError("Billing is down.", code="billing.test_failure")

    return lambda: monkeypatch.setattr(services, "invoice_subscription", fail)


def test_a_billing_failure_rolls_the_new_subscription_back(
    api_for, world, break_billing
):
    break_billing()
    resp = api_for("admin").post(URL, body(world), format="json")
    assert resp.status_code == 409
    assert resp.json()["code"] == "billing.test_failure"
    assert not scheduling_services.subscriptions_queryset().exists()
    assert not scheduling_services.sessions_queryset().exists()
    assert not Invoice.objects.exists()


def test_a_billing_failure_rolls_the_renewal_back(api_for, world, break_billing):
    admin = api_for("admin")
    sub = subscribe(admin, world)
    sessions_before = scheduling_services.sessions_queryset().count()
    break_billing()
    resp = admin.post(f"{URL}{sub['id']}/renew/", {}, format="json")
    assert resp.status_code == 409
    assert [s.pk for s in scheduling_services.subscriptions_queryset()] == [sub["id"]]
    assert scheduling_services.sessions_queryset().count() == sessions_before
    assert admin.get(f"{URL}{sub['id']}/").json()["renewal"] is None


def test_an_invoiced_subscription_is_deleted_only_after_voiding(api_for, world):
    admin = api_for("admin")
    sub = subscribe(admin, world)
    resp = admin.delete(f"{URL}{sub['id']}/")
    assert resp.status_code == 409
    assert resp.json()["code"] == "billing.subscription_invoiced"
    assert admin.get(f"{URL}{sub['id']}/").status_code == 200
    (invoice,) = invoices_of(sub["id"])
    services.void_invoice(invoice, by=admin.user)
    assert admin.delete(f"{URL}{sub['id']}/").status_code == 204


def test_admins_see_payment_status_and_nobody_else_does(api_for, world, clock):
    admin = api_for("admin")
    father = make_parent("Omar", world.student)
    sub = subscribe(admin, world)
    unbilled = subscribe(admin, world, make_student("Aisha"), price_minor=0)

    def statuses():
        rows = admin.get(URL).json()["results"]
        return {r["id"]: (r["payment_status"], r["payment_overdue"]) for r in rows}

    assert statuses() == {sub["id"]: ("unpaid", False), unbilled["id"]: ("none", False)}
    (invoice,) = invoices_of(sub["id"])
    services.add_payment(
        invoice,
        amount_minor=1000,
        method="cash",
        paid_on=invoice.issued_on,
        by=admin.user,
    )
    clock.set(datetime(2026, 6, 9, 8, tzinfo=UTC))
    assert statuses()[sub["id"]] == ("partial", True)
    detail = admin.get(f"{URL}{sub['id']}/").json()
    assert (detail["payment_status"], detail["payment_overdue"]) == ("partial", True)
    rows = admin.get(f"{URL}?format=csv").content.decode("utf-8-sig").splitlines()
    assert rows[0].endswith(",Payment status")
    parent = APIClient()
    parent.force_login(father)
    for payload in (
        parent.get(URL).json()["results"][0],
        parent.get(f"{URL}{sub['id']}/").json(),
    ):
        assert "payment_status" not in payload
        assert "payment_overdue" not in payload


def test_the_subscription_list_costs_the_same_queries_with_invoices(api_for, world):
    admin = api_for("admin")

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            rows = admin.get(URL).json()["results"]
        return len(ctx.captured_queries), rows

    for n in range(2):
        subscribe(admin, world, make_student(f"S{n}"))
    two, _ = queries()
    for n in range(2, 6):
        subscribe(admin, world, make_student(f"S{n}"))
    six, rows = queries()
    assert six == two
    assert {row["payment_status"] for row in rows} == {"unpaid"}
```

In `backend/etqan/scheduling/tests/test_api_subscriptions.py`, replace:

```python
    assert again.json()["code"] == "scheduling.already_renewed"
    cancelled = admin.post(f"{URL}{renewal['id']}/cancel/")
    assert cancelled.json()["status"] == "cancelled"
    assert admin.delete(f"{URL}{renewal['id']}/").status_code == 204
    assert admin.get(f"{URL}{renewal['id']}/").status_code == 404

```

with:

```python
    assert again.json()["code"] == "scheduling.already_renewed"
    cancelled = admin.post(f"{URL}{renewal['id']}/cancel/")
    assert cancelled.json()["status"] == "cancelled"
    # Plan 6: the renewal was invoiced, so it is deleted only once its
    # invoice is void.
    refused = admin.delete(f"{URL}{renewal['id']}/")
    assert refused.status_code == 409
    assert refused.json()["code"] == "billing.subscription_invoiced"
    invoices = admin.get(f"/api/v1/billing/invoices/?subscription={renewal['id']}")
    (invoice,) = invoices.json()["results"]
    admin.post(f"/api/v1/billing/invoices/{invoice['id']}/void/")
    assert admin.delete(f"{URL}{renewal['id']}/").status_code == 204
    assert admin.get(f"{URL}{renewal['id']}/").status_code == 404

```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing/tests/test_subscription_api.py`
Expected: FAIL — `ValueError: not enough values to unpack (expected 1, got 0)` (no invoice), `KeyError: 'payment_status'`, and the failure tests get `201` instead of `409`.

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
never sees staff notes or money — `notes`, `price_minor` and `currency` are
left out of the list and detail payloads, following Plan 3's precedent of
hiding staff notes from non-admins (see `etqan.identity.api.payloads`).
"""

from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling import services
```

with:

```python
never sees staff notes or money — `notes`, `price_minor` and `currency` are
left out of the list and detail payloads, following Plan 3's precedent of
hiding staff notes from non-admins (see `etqan.identity.api.payloads`).
Plan 6 adds `payment_status` and `payment_overdue`, for admins only, from
billing's services (the API layer may call billing; the services may not).
"""

from etqan.billing import services as billing_services
from etqan.platform.permissions import role_of
from etqan.scheduling import dates
from etqan.scheduling import services
```

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
    return value.strftime("%H:%M")


def subscription_row(sub, values: services.Derived, *, is_admin: bool) -> dict:
    row = {
        "id": sub.pk,
        "status": sub.status,
```

with:

```python
    return value.strftime("%H:%M")


def subscription_row(
    sub,
    values: services.Derived,
    payment: billing_services.PaymentStatus | None,
    *,
    is_admin: bool,
) -> dict:
    """``payment`` is billing's status for ``sub`` (admins) or None."""
    row = {
        "id": sub.pk,
        "status": sub.status,
```

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
        "renewed_from": sub.renewed_from_id,
        "renewal": getattr(sub, "renewal_id", None),
    }
    if not is_admin:
        for field in STAFF_ONLY_ROW_FIELDS:
            row.pop(field, None)
    return row


def subscription_rows(subs, *, is_admin: bool) -> list[dict]:
    subs = list(subs)
    values = services.derive(subs)
    return [subscription_row(sub, values[sub.pk], is_admin=is_admin) for sub in subs]


def slot_row(slot) -> dict:
```

with:

```python
        "renewed_from": sub.renewed_from_id,
        "renewal": getattr(sub, "renewal_id", None),
    }
    if is_admin and payment is not None:
        row["payment_status"] = payment.status
        row["payment_overdue"] = payment.overdue
    if not is_admin:
        for field in STAFF_ONLY_ROW_FIELDS:
            row.pop(field, None)
    return row


def _payments(subs, *, is_admin: bool) -> dict:
    """Billing's payment status per subscription, in one query; admins only."""
    if not is_admin:
        return {}
    return billing_services.payment_statuses([sub.pk for sub in subs])


def subscription_rows(subs, *, is_admin: bool) -> list[dict]:
    subs = list(subs)
    values = services.derive(subs)
    payments = _payments(subs, is_admin=is_admin)
    return [
        subscription_row(sub, values[sub.pk], payments.get(sub.pk), is_admin=is_admin)
        for sub in subs
    ]


def slot_row(slot) -> dict:
```

In `backend/etqan/scheduling/api/payloads.py`, replace:

```python
def subscription_detail(sub, *, is_admin: bool) -> dict:
    values = services.derived(sub)
    today = services.today()
    detail = {
        **subscription_row(sub, values, is_admin=is_admin),
        "duration_value": sub.duration_value,
        "duration_unit": sub.duration_unit,
        "session_minutes": sub.session_minutes,
```

with:

```python
def subscription_detail(sub, *, is_admin: bool) -> dict:
    values = services.derived(sub)
    today = services.today()
    payment = _payments([sub], is_admin=is_admin).get(sub.pk)
    detail = {
        **subscription_row(sub, values, payment, is_admin=is_admin),
        "duration_value": sub.duration_value,
        "duration_unit": sub.duration_unit,
        "session_minutes": sub.session_minutes,
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
"""Scheduling endpoints (spec §5). Thin: parse, call a service, arrange a payload."""

from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics
```

with:

```python
"""Scheduling endpoints (spec §5). Thin: parse, call a service, arrange a payload."""

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
    ("sessions_remaining", "Remaining"),
    ("price_minor", "Price (minor units)"),
    ("currency", "Currency"),
)
# Body keys (spec §5) → service keyword arguments.
ID_FIELDS = {
```

with:

```python
    ("sessions_remaining", "Remaining"),
    ("price_minor", "Price (minor units)"),
    ("currency", "Currency"),
    ("payment_status", "Payment status"),
)
# Body keys (spec §5) → service keyword arguments.
ID_FIELDS = {
```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
        body = SubscriptionCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = _ids(body.validated_data)
        sub = services.create_subscription(**data)
        return detail(sub.pk, request, code=status.HTTP_201_CREATED)


```

with:

```python
        body = SubscriptionCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = _ids(body.validated_data)
        # P6-1: billing after scheduling, in one transaction: if the invoice
        # fails, the subscription and its sessions are rolled back too.
        with transaction.atomic():
            sub = services.create_subscription(**data)
            billing_services.invoice_subscription(sub.pk, by=request.user)
        return detail(sub.pk, request, code=status.HTTP_201_CREATED)


```

In `backend/etqan/scheduling/api/views.py`, replace:

```python
        sub = subscription_or_404(request, pk)
        body = RenewInput(data=request.data)
        body.is_valid(raise_exception=True)
        new = services.renew_subscription(sub, **_ids(body.validated_data))
        return detail(new.pk, request, code=status.HTTP_201_CREATED)


```

with:

```python
        sub = subscription_or_404(request, pk)
        body = RenewInput(data=request.data)
        body.is_valid(raise_exception=True)
        # P6-1, as on create: the renewal and its invoice commit together.
        with transaction.atomic():
            new = services.renew_subscription(sub, **_ids(body.validated_data))
            billing_services.invoice_subscription(new.pk, by=request.user)
        return detail(new.pk, request, code=status.HTTP_201_CREATED)


```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/billing etqan/scheduling`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): invoice new and renewed subscriptions and show payment status

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dev seeds: a paid, a part-paid, an overdue and a void invoice

**Files:**
- Modify: `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/services/rules.py`, `backend/etqan/tenants/management/commands/seed_dev.py`
- Test: `backend/etqan/tenants/tests/test_seed_dev.py`

**Interfaces:**
- Consumes: Task 4's `invoice_subscription(…, issued_on=)`; Task 3's `add_payment`, `void_invoice`.
- Produces: `billing_services.has_invoices() -> bool`; `seed_dev.INVOICES` and `seed_dev.seed_billing(outcomes)` (D15), run after `seed_attendance()` for each academy.

- [ ] **Step 1: Write the failing tests**

Append to the end of `backend/etqan/tenants/tests/test_seed_dev.py`:

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_invoices_the_seeded_subscriptions_once():
    from etqan.billing import services as billing  # noqa: PLC0415

    def state():
        invoices = list(billing.invoices_queryset().order_by("pk"))
        return [
            (i.status, i.is_overdue, i.payer.full_name, i.paid_minor) for i in invoices
        ], billing.summary()

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first[0] == [
            ("paid", False, "Omar Hassan", 150000),
            ("partial", False, "Omar Hassan", 50000),
            ("unpaid", True, "Huda Ali", 0),
            ("void", False, "Omar Hassan", 0),
        ]
        assert first[1]["revenue_this_month"] == [
            {"currency": "EGP", "amount_minor": 200000}
        ]
        assert first[1]["overdue"] == [
            {"currency": "EGP", "count": 1, "balance_minor": 90000}
        ]
    with tenant_context(other):
        assert [row[:2] for row in state()[0]] == [("unpaid", False)]
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_billing_skips_what_a_rule_refuses_and_carries_on(capsys, monkeypatch):
    from etqan.billing import services as billing  # noqa: PLC0415
    from etqan.platform.exceptions import ConflictError  # noqa: PLC0415

    def refuse(invoice, *, by):
        raise ConflictError("Not now.", code="billing.test_refusal")

    monkeypatch.setattr(billing, "void_invoice", refuse)
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(Academy.objects.get(subdomain="demo")):
        statuses = [i.status for i in billing.invoices_queryset().order_by("pk")]
    assert statuses == ["paid", "partial", "unpaid", "unpaid"]
    assert capsys.readouterr().out.count("invoice — Not now.") == 1
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py -k "invoices or billing"`
Expected: FAIL — the seeded academies have no invoices (`assert [] == [('paid', False, 'Omar Hassan', 150000), …]` and `assert [] == ['paid', 'partial', 'unpaid', 'unpaid']`).

- [ ] **Step 3: Implement**

In `backend/etqan/billing/services/__init__.py`, replace:

```python
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import FILTER_STATUSES
from etqan.billing.services.rules import filter_invoices
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for
```

with:

```python
from etqan.billing.services.payments import delete_payment
from etqan.billing.services.rules import FILTER_STATUSES
from etqan.billing.services.rules import filter_invoices
from etqan.billing.services.rules import has_invoices
from etqan.billing.services.rules import invoices_queryset
from etqan.billing.services.rules import overdue
from etqan.billing.services.rules import status_for
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
    "create_invoice",
    "delete_payment",
    "filter_invoices",
    "invoice_subscription",
    "invoices_queryset",
    "next_number",
```

with:

```python
    "create_invoice",
    "delete_payment",
    "filter_invoices",
    "has_invoices",
    "invoice_subscription",
    "invoices_queryset",
    "next_number",
```

In `backend/etqan/billing/services/rules.py`, replace:

```python
    return invoices.order_by("-id")


def invoices_queryset() -> QuerySet[Invoice]:
    """Invoices with everything a row shows, in one query: the payer, student
    and creator joined, ``paid_minor`` summed in SQL and ``is_overdue`` from
```

with:

```python
    return invoices.order_by("-id")


def has_invoices() -> bool:
    return Invoice.objects.exists()


def invoices_queryset() -> QuerySet[Invoice]:
    """Invoices with everything a row shows, in one query: the payer, student
    and creator joined, ``paid_minor`` summed in SQL and ``is_overdue`` from
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
```

with:

```python
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.billing import services as billing_services
from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
            print(f"skip: session {session.pk} report — {exc}")  # noqa: T201


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."

```

with:

```python
            print(f"skip: session {session.pk} report — {exc}")  # noqa: T201


# Plan 6 (spec §7): what becomes of each seeded subscription's invoice, in
# the order the subscriptions were seeded. The third demo subscription
# started 17 days ago, so its unpaid invoice is overdue.
INVOICES = {
    "demo": ("paid", "partial", "overdue", "void"),
    "other": ("unpaid",),
}


def seed_billing(outcomes: tuple[str, ...]) -> None:
    """Idempotent: an academy that already has an invoice is left alone.

    The seeds create subscriptions through the service, which never invoices
    (only the API does, P6-1), so each one is invoiced here as of its start
    date, as the automatic invoice would have been, then paid, part paid or
    voided. Nothing is sent. An item a rule refuses is skipped."""
    if billing_services.has_invoices():
        return
    today = scheduling_services.today()
    subscriptions = scheduling_services.subscriptions_queryset().order_by("pk")
    for sub, outcome in zip(subscriptions, outcomes, strict=False):
        try:
            invoice = billing_services.invoice_subscription(
                sub.pk, by=None, issued_on=sub.starts_on
            )
            if invoice is None:
                continue
            if outcome in ("paid", "partial"):
                share = 1 if outcome == "paid" else 3
                billing_services.add_payment(
                    invoice,
                    amount_minor=invoice.amount_minor // share,
                    method="cash" if outcome == "paid" else "instapay",
                    paid_on=today,
                    by=None,
                )
            elif outcome == "void":
                billing_services.void_invoice(invoice, by=None)
        except (ValidationError, ConflictError, NotFoundError) as exc:
            print(f"skip: subscription {sub.pk} invoice — {exc}")  # noqa: T201


class Command(BaseCommand):
    help = "Create the public tenant and two dev academies with known admin logins."

```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
                seed_people(PEOPLE[subdomain])
                seed_subscriptions(SUBSCRIPTIONS[subdomain])
                seed_attendance()
```

with:

```python
                seed_people(PEOPLE[subdomain])
                seed_subscriptions(SUBSCRIPTIONS[subdomain])
                seed_attendance()
                seed_billing(INVOICES[subdomain])
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(seed): demo invoices, paid, part paid, overdue and void

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard groundwork: billing data layer, invoice settings, payment status, shared Fact and Confirm

**Files:**
- Create: `dashboard/src/components/Confirm.tsx`, `dashboard/src/components/Fact.tsx`, `dashboard/src/features/billing/api.ts`, `dashboard/src/features/billing/bits.tsx`, `dashboard/src/features/billing/index.ts`, `dashboard/src/features/billing/queries.ts`, `dashboard/src/features/billing/schemas.ts`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/features/academy/AcademySettingsForm.tsx`, `dashboard/src/features/academy/api.ts`, `dashboard/src/features/scheduling/SessionPage.tsx`, `dashboard/src/features/scheduling/SubscriptionActions.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, `dashboard/src/features/scheduling/bits.tsx`, `dashboard/src/features/scheduling/index.ts`, `dashboard/src/features/scheduling/queries.ts`, `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/lib/zoned-time.ts`
- Test: `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, `dashboard/src/features/billing/api.test.ts` (new), `dashboard/src/features/scheduling/SubscriptionActions.test.tsx`, `dashboard/src/lib/zoned-time.test.ts`, `dashboard/src/test/billing-fixtures.ts` (new), `dashboard/src/features/catalogue/PackageForm.test.tsx`, `dashboard/src/features/people/AdminsList.test.tsx`, `dashboard/src/features/people/ParentForm.test.tsx`, `dashboard/src/features/people/StudentForm.test.tsx`, `dashboard/src/features/people/TeacherForm.test.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, `dashboard/src/features/scheduling/SubscriptionForm.test.tsx`, `dashboard/src/features/scheduling/TodayBoard.test.tsx`, `dashboard/src/test/scheduling-fixtures.ts`

**Interfaces:**
- Consumes: Tasks 1, 6 and 7's API.
- Produces (`@/features/billing`):
  - types `Invoice`, `InvoiceDetail`, `Payment`, `BillingSummary`, `Payers`, `Person`, `InvoiceBody`, `InvoicePatch`, `PaymentBody`, `InvoiceStatus`, `PaymentMethod`;
  - constants `INVOICE_STATUSES`, `PAYMENT_METHODS`;
  - zod `amount`, `invoiceFormSchema`/`InvoiceFormValues`, `editInvoiceSchema(issuedOn)`/`EditInvoiceValues`, `paymentFormSchema(balanceMinor, toMinor)`/`PaymentFormValues`;
  - `billingApi.list/get/create/update({id,…})/void/addPayment({id,…})/deletePayment/summary/payers`, `invoicesCsvUrl(params)`;
  - hooks `billingKey`, `useInvoices(params)`, `useInvoice(id | undefined)`, `useBillingSummary()`, `usePayers(student | undefined)`, `useBillingMutation(write)` (refreshes billing and scheduling);
  - `InvoiceStatusChip({invoice})`, `Money({minor, currency})`.
- Produces (`@/features/scheduling`): `Subscription.payment_status?`, `payment_overdue?`, `PAYMENT_STATUSES`, `PaymentStatus`; `PaymentStatusChip({status, overdue})` and `useLocalName` exported; `useSubscriptions(params, { enabled })`.
- Produces: `@/components/Fact`, `@/components/Confirm` (D16); `@/lib/zoned-time` `addDays(day, n)`; `AcademySettings.auto_invoice_on_subscription`/`invoice_due_days` and their form fields.
- Produces (tests): `@/test/billing-fixtures` `invoiceRow`, `paymentRow`, `invoiceDetail`, `familyInvoice` (no staff fields), `billingSummary`.

- [ ] **Step 1: Update the settings objects in existing tests**

Add the two settings to every existing test's academy-settings object (each file has exactly one `excused_consumes_session: false,` line; `AcademySettingsForm.test.tsx` gets its own block below):

```bash
cd dashboard
sed -i 's/^\(\s*\)excused_consumes_session: false,$/&\n\1auto_invoice_on_subscription: true,\n\1invoice_due_days: 7,/' \
  src/features/catalogue/PackageForm.test.tsx \
  src/features/people/AdminsList.test.tsx \
  src/features/people/ParentForm.test.tsx \
  src/features/people/StudentForm.test.tsx \
  src/features/people/TeacherForm.test.tsx \
  src/features/scheduling/SubscriptionDetail.test.tsx \
  src/features/scheduling/SubscriptionForm.test.tsx \
  src/features/scheduling/TodayBoard.test.tsx \
  src/test/scheduling-fixtures.ts
cd ..
```

- [ ] **Step 2: Write the failing tests**

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
const SWITCHES = {
	absent_consumes_session: true,
	excused_consumes_session: false,
};

describe("AcademySettingsForm", () => {
```

with:

```tsx
const SWITCHES = {
	absent_consumes_session: true,
	excused_consumes_session: false,
	auto_invoice_on_subscription: true,
	invoice_due_days: 7,
};

describe("AcademySettingsForm", () => {
```

In `dashboard/src/features/academy/AcademySettingsForm.test.tsx`, replace:

```tsx
			).toBe(true),
		);
	});
});
```

with:

```tsx
			).toBe(true),
		);
	});

	it("saves the invoice switch and due days and checks their range", async () => {
		vi.mocked(academyApi.update).mockImplementation(async (body) => ({
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...SWITCHES,
			...body,
		}));
		const user = userEvent.setup();
		renderForm();
		const auto = await screen.findByRole("checkbox", {
			name: "Invoice every new or renewed subscription",
		});
		const due = screen.getByLabelText("Invoices are due after (days)");
		expect(auto).toBeChecked();
		expect(due).toHaveValue(7);
		await user.clear(due);
		await user.type(due, "91");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("Choose 0 to 90 days.")).toBeInTheDocument();
		expect(academyApi.update).not.toHaveBeenCalled();
		await user.clear(due);
		await user.type(due, "0");
		await user.click(auto);
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(academyApi.update).toHaveBeenCalledWith(
				expect.objectContaining({
					auto_invoice_on_subscription: false,
					invoice_due_days: 0,
				}),
			),
		);
	});
});
```

Create `dashboard/src/features/billing/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { billingApi, invoicesCsvUrl } from "./api";

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

describe("billingApi", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads invoices, the summary and payers from the spec §5 routes", async () => {
		await billingApi.list({ status: "overdue", q: "", page: 2 });
		expect(api.get).toHaveBeenCalledWith("billing/invoices/", {
			params: { status: "overdue", page: "2" },
		});
		await billingApi.get(51);
		expect(api.get).toHaveBeenLastCalledWith("billing/invoices/51/");
		await billingApi.summary();
		expect(api.get).toHaveBeenLastCalledWith("billing/summary/");
		await billingApi.payers(11);
		expect(api.get).toHaveBeenLastCalledWith("billing/payers/", {
			params: { student: 11 },
		});
	});

	it("writes invoices and payments", async () => {
		const body = {
			student: 11,
			amount_minor: 1000,
			due_on: "2026-06-08",
			description: "June",
		};
		await billingApi.create(body);
		expect(api.post).toHaveBeenLastCalledWith("billing/invoices/", body);
		await billingApi.update({ id: 51, notes: "x" });
		expect(api.patch).toHaveBeenLastCalledWith("billing/invoices/51/", {
			notes: "x",
		});
		await billingApi.void(51);
		expect(api.post).toHaveBeenLastCalledWith("billing/invoices/51/void/");
		await billingApi.addPayment({
			id: 51,
			amount_minor: 500,
			method: "cash",
			paid_on: "2026-06-02",
		});
		expect(api.post).toHaveBeenLastCalledWith("billing/invoices/51/payments/", {
			amount_minor: 500,
			method: "cash",
			paid_on: "2026-06-02",
		});
		await billingApi.deletePayment(61);
		expect(api.delete).toHaveBeenLastCalledWith("billing/payments/61/");
	});

	it("builds the CSV link with the list's filters", () => {
		const url = invoicesCsvUrl({ status: "paid", page: 3, student: 11 });
		expect(url).toBe(
			"/api/v1/billing/invoices/?status=paid&student=11&format=csv",
		);
	});
});
```

In `dashboard/src/features/scheduling/SubscriptionActions.test.tsx`, replace:

```tsx
		);
	});

	it("edits teacher, start, price and notes, sending only the changed fields", async () => {
		vi.mocked(schedulingApi.update).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
```

with:

```tsx
		);
	});

	it("says to void the invoices before deleting an invoiced subscription", async () => {
		vi.mocked(schedulingApi.remove).mockRejectedValueOnce(
			conflict("billing.subscription_invoiced"),
		);
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionActions sub={subscriptionDetail()} />);
		await user.click(await screen.findByRole("button", { name: "Delete" }));
		const confirm = await screen.findByRole("alertdialog");
		await user.click(
			within(confirm).getByRole("button", { name: "Delete subscription" }),
		);
		expect(
			await screen.findByText(
				"This subscription has invoices. Void them before deleting it.",
				{ exact: true },
			),
		).toBeInTheDocument();
	});

	it("edits teacher, start, price and notes, sending only the changed fields", async () => {
		vi.mocked(schedulingApi.update).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
```

In `dashboard/src/lib/zoned-time.test.ts`, replace:

```ts
import { describe, expect, it } from "vitest";
import {
	dayIn,
	formatDay,
	otherZoneTime,
```

with:

```ts
import { describe, expect, it } from "vitest";
import {
	addDays,
	dayIn,
	formatDay,
	otherZoneTime,
```

In `dashboard/src/lib/zoned-time.test.ts`, replace:

```ts
	});
});

describe("weekdayName", () => {
	it("numbers the week from Monday", () => {
		expect(weekdayName(0, "en")).toBe("Mon");
```

with:

```ts
	});
});

describe("addDays", () => {
	it("counts calendar days across months, years and leap days", () => {
		expect(addDays("2026-06-01", 7)).toBe("2026-06-08");
		expect(addDays("2026-06-28", 7)).toBe("2026-07-05");
		expect(addDays("2026-12-30", 3)).toBe("2027-01-02");
		expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
		expect(addDays("2026-03-28", 2)).toBe("2026-03-30");
		expect(addDays("2026-06-01", 0)).toBe("2026-06-01");
	});
});

describe("weekdayName", () => {
	it("numbers the week from Monday", () => {
		expect(weekdayName(0, "en")).toBe("Mon");
```

Create `dashboard/src/test/billing-fixtures.ts`:

```ts
import type {
	BillingSummary,
	Invoice,
	InvoiceDetail,
	Payment,
} from "@/features/billing/schemas";

/** API-shaped billing rows for feature tests (an admin's view). */
export function invoiceRow(overrides: Partial<Invoice> = {}): Invoice {
	return {
		id: 51,
		number: "INV-000051",
		status: "partial",
		is_overdue: false,
		student: { id: 11, full_name: "Yusuf" },
		payer: { id: 31, full_name: "Omar" },
		subscription_id: 7,
		description: "Tajweed — Monthly",
		amount_minor: 150000,
		paid_minor: 50000,
		balance_minor: 100000,
		currency: "EGP",
		issued_on: "2026-06-01",
		due_on: "2026-06-08",
		voided_at: null,
		created_at: "2026-06-01T08:00:00Z",
		notes: "Sibling rate",
		created_by: { id: 1, full_name: "Amina" },
		...overrides,
	};
}

export function paymentRow(overrides: Partial<Payment> = {}): Payment {
	return {
		id: 61,
		invoice_id: 51,
		amount_minor: 50000,
		method: "instapay",
		paid_on: "2026-06-02",
		reference: "IP-9",
		created_at: "2026-06-02T09:00:00Z",
		notes: "First half",
		recorded_by: { id: 1, full_name: "Amina" },
		...overrides,
	};
}

export function invoiceDetail(
	overrides: Partial<InvoiceDetail> = {},
): InvoiceDetail {
	return { ...invoiceRow(), payments: [paymentRow()], ...overrides };
}

/** What a parent or student receives: no staff fields. */
export function familyInvoice(
	overrides: Partial<InvoiceDetail> = {},
): InvoiceDetail {
	const { notes: _notes, created_by: _by, ...row } = invoiceRow();
	const { notes: _n, recorded_by: _r, ...payment } = paymentRow();
	return { ...row, payments: [payment], ...overrides };
}

export function billingSummary(
	overrides: Partial<BillingSummary> = {},
): BillingSummary {
	return {
		revenue_this_month: [
			{ currency: "EGP", amount_minor: 200000 },
			{ currency: "USD", amount_minor: 4000 },
		],
		overdue: [{ currency: "EGP", count: 2, balance_minor: 90000 }],
		...overrides,
	};
}
```

- [ ] **Step 3: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing src/features/academy src/lib/zoned-time.test.ts src/features/scheduling/SubscriptionActions.test.tsx`
Expected: FAIL — `Failed to resolve import "./api"` in `billing/api.test.ts`, `addDays is not a function`, `Unable to find role="checkbox" and name "Invoice every new or renewed subscription"`, and the subscription-delete refusal shows the generic message.

- [ ] **Step 4: Implement**

Create `dashboard/src/components/Confirm.tsx`:

```tsx
import { useTranslation } from "react-i18next";
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
} from "@/ui";

/** A destructive action behind a confirmation: the trigger reads `action`,
 * the dialog asks `title` / `body` and confirms with `title`. */
export function Confirm({
	action,
	title,
	body,
	onConfirm,
}: {
	action: string;
	title: string;
	body: string;
	onConfirm: () => void;
}) {
	const { t } = useTranslation();
	return (
		<AlertDialog>
			<AlertDialogTrigger asChild>
				<Button size="sm" variant="destructive">
					{action}
				</Button>
			</AlertDialogTrigger>
			<AlertDialogContent>
				<AlertDialogTitle>{title}</AlertDialogTitle>
				<AlertDialogDescription>{body}</AlertDialogDescription>
				<AlertDialogFooter>
					<AlertDialogCancel asChild>
						<Button type="button" variant="outline">
							{t("people.cancel")}
						</Button>
					</AlertDialogCancel>
					<AlertDialogAction asChild>
						<Button type="button" variant="destructive" onClick={onConfirm}>
							{title}
						</Button>
					</AlertDialogAction>
				</AlertDialogFooter>
			</AlertDialogContent>
		</AlertDialog>
	);
}
```

Create `dashboard/src/components/Fact.tsx`:

```tsx
import type { ReactNode } from "react";

/** One labelled value in a `<dl>` of details (a subscription's summary, a
 * session's or an invoice's facts). */
export function Fact({
	label,
	children,
}: {
	label: string;
	children: ReactNode;
}) {
	return (
		<div className="flex flex-col gap-0.5">
			<dt className="text-xs text-muted-foreground">{label}</dt>
			<dd className="font-medium">{children}</dd>
		</div>
	);
}
```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
	renewal_grace_days: days(0, 60, "academySettings.errors.graceRange"),
	absent_consumes_session: z.boolean(),
	excused_consumes_session: z.boolean(),
});
type Values = z.infer<typeof schema>;

```

with:

```tsx
	renewal_grace_days: days(0, 60, "academySettings.errors.graceRange"),
	absent_consumes_session: z.boolean(),
	excused_consumes_session: z.boolean(),
	auto_invoice_on_subscription: z.boolean(),
	invoice_due_days: days(0, 90, "academySettings.errors.dueDaysRange"),
});
type Values = z.infer<typeof schema>;

```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
					renewal_grace_days: data.renewal_grace_days,
					absent_consumes_session: data.absent_consumes_session,
					excused_consumes_session: data.excused_consumes_session,
				}
			: undefined,
	});
```

with:

```tsx
					renewal_grace_days: data.renewal_grace_days,
					absent_consumes_session: data.absent_consumes_session,
					excused_consumes_session: data.excused_consumes_session,
					auto_invoice_on_subscription: data.auto_invoice_on_subscription,
					invoice_due_days: data.invoice_due_days,
				}
			: undefined,
	});
```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
		name: "excused_consumes_session",
		defaultValue: false,
	});

	async function onSubmit(values: Values) {
		try {
```

with:

```tsx
		name: "excused_consumes_session",
		defaultValue: false,
	});
	const autoInvoice = useController({
		control,
		name: "auto_invoice_on_subscription",
		defaultValue: true,
	});

	async function onSubmit(values: Values) {
		try {
```

In `dashboard/src/features/academy/AcademySettingsForm.tsx`, replace:

```tsx
					{t("academySettings.countsHint")}
				</p>
			</fieldset>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
```

with:

```tsx
					{t("academySettings.countsHint")}
				</p>
			</fieldset>
			<fieldset className="flex flex-col gap-3">
				<legend className="mb-2 text-sm font-medium">
					{t("academySettings.invoices")}
				</legend>
				<label
					htmlFor="auto_invoice_on_subscription"
					className="flex items-center gap-2 text-sm"
				>
					<Checkbox
						id="auto_invoice_on_subscription"
						checked={autoInvoice.field.value}
						onCheckedChange={autoInvoice.field.onChange}
					/>
					{t("academySettings.autoInvoice")}
				</label>
				<Field
					id="invoice_due_days"
					label={t("academySettings.dueDays")}
					error={fieldError(errors.invoice_due_days?.message)}
				>
					<Input
						type="number"
						min={0}
						max={90}
						{...register("invoice_due_days", { valueAsNumber: true })}
					/>
				</Field>
				<p className="text-sm text-muted-foreground">
					{t("academySettings.invoicesHint")}
				</p>
			</fieldset>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
```

In `dashboard/src/features/academy/api.ts`, replace:

```ts
	// Plan 5 spec §4.2: whether a missed session counts as used.
	absent_consumes_session: boolean;
	excused_consumes_session: boolean;
	updated_at?: string;
}

```

with:

```ts
	// Plan 5 spec §4.2: whether a missed session counts as used.
	absent_consumes_session: boolean;
	excused_consumes_session: boolean;
	// Plan 6 spec §3.1: invoice each new or renewed subscription, due after.
	auto_invoice_on_subscription: boolean;
	invoice_due_days: number;
	updated_at?: string;
}

```

Create `dashboard/src/features/billing/api.ts`:

```ts
import {
	api,
	clean,
	csvUrl,
	type Paginated,
	type QueryParams,
} from "@/lib/api";
import type {
	BillingSummary,
	Invoice,
	InvoiceBody,
	InvoiceDetail,
	InvoicePatch,
	Payers,
	PaymentBody,
} from "./schemas";

const I = "billing/invoices/";

export const billingApi = {
	list: async (params: QueryParams) =>
		(await api.get<Paginated<Invoice>>(I, { params: clean(params) })).data,
	get: async (id: number) => (await api.get<InvoiceDetail>(`${I}${id}/`)).data,
	create: async (body: InvoiceBody) =>
		(await api.post<InvoiceDetail>(I, body)).data,
	update: async ({ id, ...body }: InvoicePatch & { id: number }) =>
		(await api.patch<InvoiceDetail>(`${I}${id}/`, body)).data,
	void: async (id: number) =>
		(await api.post<InvoiceDetail>(`${I}${id}/void/`)).data,
	addPayment: async ({ id, ...body }: PaymentBody & { id: number }) =>
		(await api.post<InvoiceDetail>(`${I}${id}/payments/`, body)).data,
	deletePayment: async (paymentId: number) => {
		await api.delete(`billing/payments/${paymentId}/`);
	},
	summary: async () => (await api.get<BillingSummary>("billing/summary/")).data,
	payers: async (student: number) =>
		(await api.get<Payers>("billing/payers/", { params: { student } })).data,
};

/** The invoice list's CSV export, with the list's filters (admins only). */
export function invoicesCsvUrl(params: QueryParams): string {
	return csvUrl(I, params);
}
```

Create `dashboard/src/features/billing/bits.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { formatMoney } from "@/lib/money";
import { StatusChip } from "@/ui";
import type { Invoice, InvoiceStatus } from "./schemas";

const TONE: Record<InvoiceStatus, "live" | "neutral" | "warning"> = {
	unpaid: "neutral",
	partial: "neutral",
	paid: "live",
	void: "neutral",
};

/** The invoice's status, and "Overdue" beside it when it is (spec §6). */
export function InvoiceStatusChip({
	invoice,
}: {
	invoice: Pick<Invoice, "status" | "is_overdue">;
}) {
	const { t } = useTranslation();
	return (
		<span className="inline-flex flex-wrap items-center gap-1">
			<StatusChip tone={TONE[invoice.status]}>
				{t(`billing.status.${invoice.status}`)}
			</StatusChip>
			{invoice.is_overdue ? (
				<StatusChip tone="warning">{t("billing.overdue")}</StatusChip>
			) : null}
		</span>
	);
}

/** Minor units in the reader's language, kept left-to-right in RTL text. */
export function Money({
	minor,
	currency,
}: {
	minor: number;
	currency: string;
}) {
	const { i18n } = useTranslation();
	return <span dir="ltr">{formatMoney(minor, currency, i18n.language)}</span>;
}
```

Create `dashboard/src/features/billing/index.ts`:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export * from "./queries";
export * from "./schemas";
```

Create `dashboard/src/features/billing/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { schedulingKey } from "@/features/scheduling/queries";
import type { QueryParams } from "@/lib/api";
import { billingApi } from "./api";

/** Every billing query lives under this key. */
export const billingKey = ["billing"] as const;

export function useInvoices(params: QueryParams) {
	return useQuery({
		queryKey: [...billingKey, "invoices", params],
		queryFn: () => billingApi.list(params),
		placeholderData: keepPreviousData,
	});
}

export function useInvoice(id: number | undefined) {
	return useQuery({
		queryKey: [...billingKey, "invoice", id],
		queryFn: () => billingApi.get(id as number),
		enabled: id !== undefined,
	});
}

export function useBillingSummary() {
	return useQuery({
		queryKey: [...billingKey, "summary"],
		queryFn: billingApi.summary,
	});
}

/** The student's possible payers, the default first; nothing until a
 * student is chosen. */
export function usePayers(student: number | undefined) {
	return useQuery({
		queryKey: [...billingKey, "payers", student],
		queryFn: () => billingApi.payers(student as number),
		enabled: student !== undefined,
	});
}

/** A billing write. On success it refreshes billing and scheduling: a
 * payment or a void moves a subscription's payment status (spec §4.4). */
export function useBillingMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () =>
			Promise.all([
				qc.invalidateQueries({ queryKey: billingKey }),
				qc.invalidateQueries({ queryKey: schedulingKey }),
			]),
	});
}
```

Create `dashboard/src/features/billing/schemas.ts`:

```ts
import { z } from "zod";

export const INVOICE_STATUSES = ["unpaid", "partial", "paid", "void"] as const;
export type InvoiceStatus = (typeof INVOICE_STATUSES)[number];

/** Plan 6 P6-3: TutorHamster's manual payment options. */
export const PAYMENT_METHODS = [
	"cash",
	"bank_transfer",
	"instapay",
	"vodafone_cash",
	"western_union",
	"zelle",
	"venmo",
	"cashapp",
	"other",
] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

export interface Person {
	id: number;
	full_name: string;
}

export interface Invoice {
	id: number;
	number: string;
	status: InvoiceStatus;
	// Derived on the server from the academy's today (spec §4.1).
	is_overdue: boolean;
	student: Person;
	payer: Person;
	subscription_id: number | null;
	description: string;
	amount_minor: number;
	paid_minor: number;
	balance_minor: number;
	currency: string;
	issued_on: string;
	due_on: string;
	voided_at: string | null;
	created_at: string;
	// Admins only (spec §4.6).
	notes?: string;
	created_by?: Person | null;
}

export interface Payment {
	id: number;
	invoice_id: number;
	amount_minor: number;
	method: PaymentMethod;
	paid_on: string;
	reference: string;
	created_at: string;
	// Admins only (spec §4.6).
	notes?: string;
	recorded_by?: Person | null;
}

export interface InvoiceDetail extends Invoice {
	payments: Payment[];
}

export interface BillingSummary {
	revenue_this_month: { currency: string; amount_minor: number }[];
	overdue: { currency: string; count: number; balance_minor: number }[];
}

export interface Payers {
	default: number;
	choices: (Person & { relation: "guardian" | "student" })[];
}

// Request bodies (spec §5). People are User ids.
export interface InvoiceBody {
	student: number;
	payer?: number;
	subscription?: number;
	amount_minor: number;
	currency?: string;
	due_on: string;
	description: string;
	notes?: string;
}
export interface InvoicePatch {
	description?: string;
	due_on?: string;
	notes?: string;
	amount_minor?: number;
}
export interface PaymentBody {
	amount_minor: number;
	method: PaymentMethod;
	paid_on: string;
	reference?: string;
	notes?: string;
}

// Form schemas. Messages are i18n keys, translated by `useFieldError`.
const pick = z.string().min(1, "billing.errors.required");
const day = z
	.string()
	.regex(/^\d{4}-\d{2}-\d{2}$/, "billing.errors.dateRequired");
export const amount = z
	.string()
	.regex(/^\d+(\.\d{1,3})?$/, "billing.errors.amountInvalid")
	.refine((value) => Number(value) > 0, "billing.errors.amountInvalid");

export const invoiceFormSchema = z.object({
	student: pick,
	payer: pick,
	subscription: z.string(),
	amount,
	currency: z.string().regex(/^[A-Z]{3}$/, "billing.errors.required"),
	due_on: day,
	description: z.string().trim().min(1, "billing.errors.required"),
	notes: z.string(),
});
export type InvoiceFormValues = z.infer<typeof invoiceFormSchema>;

/** The edit dialog: due on or after the invoice's own issue date. */
export const editInvoiceSchema = (issuedOn: string) =>
	z.object({
		description: z.string().trim().min(1, "billing.errors.required"),
		due_on: day.refine(
			(value) => value >= issuedOn,
			"billing.errors.dueBeforeIssue",
		),
		amount,
		notes: z.string(),
	});
export type EditInvoiceValues = z.infer<ReturnType<typeof editInvoiceSchema>>;

/** Recording a payment: no more than the balance, in the invoice's
 * currency (`toMinor` turns the typed amount into minor units). */
export const paymentFormSchema = (
	balanceMinor: number,
	toMinor: (major: string) => number,
) =>
	z.object({
		amount: amount.refine(
			(value) => toMinor(value) <= balanceMinor,
			"billing.errors.overBalance",
		),
		method: z.enum(PAYMENT_METHODS),
		paid_on: day,
		reference: z.string().max(120, "billing.errors.tooLong"),
		notes: z.string(),
	});
export type PaymentFormValues = z.infer<ReturnType<typeof paymentFormSchema>>;
```

In `dashboard/src/features/scheduling/SessionPage.tsx`, replace:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { errorText } from "@/lib/form-errors";
import { formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
```

with:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { useAcademySettings } from "@/features/academy/queries";
import { errorText } from "@/lib/form-errors";
import { formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
```

In `dashboard/src/features/scheduling/SessionPage.tsx`, replace:

```tsx
import { ReportForm } from "./ReportForm";
import type { Session } from "./schemas";

function Fact({ label, children }: { label: string; children: ReactNode }) {
	return (
		<div className="flex flex-col gap-0.5">
			<dt className="text-xs text-muted-foreground">{label}</dt>
			<dd className="font-medium">{children}</dd>
		</div>
	);
}

function ReportCard({ session }: { session: Session }) {
	const { t } = useTranslation();
	const { data: report, isError } = useReport(
```

with:

```tsx
import { ReportForm } from "./ReportForm";
import type { Session } from "./schemas";

function ReportCard({ session }: { session: Session }) {
	const { t } = useTranslation();
	const { data: report, isError } = useReport(
```

In `dashboard/src/features/scheduling/SubscriptionActions.tsx`, replace:

```tsx
import { Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { errorText } from "@/lib/form-errors";
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
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { EditDialog } from "./EditDialog";
import { useSchedulingMutation } from "./queries";
import { RenewDialog } from "./RenewDialog";
import { isLive, type SubscriptionDetail } from "./schemas";

function Confirm({
	action,
	title,
	body,
	onConfirm,
}: {
	action: string;
	title: string;
	body: string;
	onConfirm: () => void;
}) {
	const { t } = useTranslation();
	return (
		<AlertDialog>
			<AlertDialogTrigger asChild>
				<Button size="sm" variant="destructive">
					{action}
				</Button>
			</AlertDialogTrigger>
			<AlertDialogContent>
				<AlertDialogTitle>{title}</AlertDialogTitle>
				<AlertDialogDescription>{body}</AlertDialogDescription>
				<AlertDialogFooter>
					<AlertDialogCancel asChild>
						<Button type="button" variant="outline">
							{t("people.cancel")}
						</Button>
					</AlertDialogCancel>
					<AlertDialogAction asChild>
						<Button type="button" variant="destructive" onClick={onConfirm}>
							{title}
						</Button>
					</AlertDialogAction>
				</AlertDialogFooter>
			</AlertDialogContent>
		</AlertDialog>
	);
}

/** Renew, edit, cancel and delete (spec §6), each shown only when allowed. */
export function SubscriptionActions({ sub }: { sub: SubscriptionDetail }) {
	const { t } = useTranslation();
```

with:

```tsx
import { Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { errorText } from "@/lib/form-errors";
import { Button, toast } from "@/ui";
import { schedulingApi } from "./api";
import { EditDialog } from "./EditDialog";
import { useSchedulingMutation } from "./queries";
import { RenewDialog } from "./RenewDialog";
import { isLive, type SubscriptionDetail } from "./schemas";

/** Renew, edit, cancel and delete (spec §6), each shown only when allowed. */
export function SubscriptionActions({ sub }: { sub: SubscriptionDetail }) {
	const { t } = useTranslation();
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { formatMoney } from "@/lib/money";
import { formatDay, studentTime, todayIn } from "@/lib/zoned-time";
```

with:

```tsx
import { isAxiosError } from "axios";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { useAcademySettings } from "@/features/academy/queries";
import { formatMoney } from "@/lib/money";
import { formatDay, studentTime, todayIn } from "@/lib/zoned-time";
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
import { SubscriptionActions } from "./SubscriptionActions";
import type { SubscriptionDetail as Detail } from "./schemas";

function Fact({ label, children }: { label: string; children: ReactNode }) {
	return (
		<div className="flex flex-col gap-0.5">
			<dt className="text-xs text-muted-foreground">{label}</dt>
			<dd className="font-medium">{children}</dd>
		</div>
	);
}

function Summary({ sub }: { sub: Detail }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
```

with:

```tsx
import { SubscriptionActions } from "./SubscriptionActions";
import type { SubscriptionDetail as Detail } from "./schemas";

function Summary({ sub }: { sub: Detail }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
```

In `dashboard/src/features/scheduling/bits.tsx`, replace:

```tsx
import { Meter, StatusChip } from "@/ui";
import type {
	NamedRef,
	Session,
	SessionStatus,
	SubscriptionStatus,
```

with:

```tsx
import { Meter, StatusChip } from "@/ui";
import type {
	NamedRef,
	PaymentStatus,
	Session,
	SessionStatus,
	SubscriptionStatus,
```

In `dashboard/src/features/scheduling/bits.tsx`, replace:

```tsx
	);
}

/** A course or package name in the reader's language. */
export function useLocalName() {
	const { i18n } = useTranslation();
```

with:

```tsx
	);
}

const PAYMENT_TONE: Record<PaymentStatus, "live" | "neutral"> = {
	none: "neutral",
	unpaid: "neutral",
	partial: "neutral",
	paid: "live",
};

/** A subscription's payment status from its invoices (Plan 6 spec §4.4),
 * with "Overdue" beside it when one of them is. */
export function PaymentStatusChip({
	status,
	overdue,
}: {
	status: PaymentStatus;
	overdue: boolean;
}) {
	const { t } = useTranslation();
	return (
		<span className="inline-flex flex-wrap items-center gap-1">
			<StatusChip tone={PAYMENT_TONE[status]}>
				{t(`billing.paymentStatus.${status}`)}
			</StatusChip>
			{overdue ? (
				<StatusChip tone="warning">{t("billing.overdue")}</StatusChip>
			) : null}
		</span>
	);
}

/** A course or package name in the reader's language. */
export function useLocalName() {
	const { i18n } = useTranslation();
```

In `dashboard/src/features/scheduling/index.ts`, replace:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export { FamilyHome } from "./FamilyHome";
export { FamilySessions } from "./FamilySessions";
export { FamilySubscriptions } from "./FamilySubscriptions";
```

with:

```ts
export { schedulingApi, sessionsCsvUrl, subscriptionsCsvUrl } from "./api";
export { PaymentStatusChip, useLocalName } from "./bits";
export { FamilyHome } from "./FamilyHome";
export { FamilySessions } from "./FamilySessions";
export { FamilySubscriptions } from "./FamilySubscriptions";
```

In `dashboard/src/features/scheduling/queries.ts`, replace:

```ts
 * mutation refreshes them all. */
export const schedulingKey = ["scheduling"] as const;

export function useSubscriptions(params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "subscriptions", params],
		queryFn: () => schedulingApi.list(params),
		placeholderData: keepPreviousData,
	});
}

```

with:

```ts
 * mutation refreshes them all. */
export const schedulingKey = ["scheduling"] as const;

export function useSubscriptions(
	params: QueryParams,
	{ enabled = true }: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...schedulingKey, "subscriptions", params],
		queryFn: () => schedulingApi.list(params),
		placeholderData: keepPreviousData,
		enabled,
	});
}

```

In `dashboard/src/features/scheduling/schemas.ts`, replace:

```ts
	currency?: string;
	renewed_from: number | null;
	renewal: number | null;
}

export interface Slot {
	id: number;
	weekday: number;
```

with:

```ts
	currency?: string;
	renewed_from: number | null;
	renewal: number | null;
	// Admins only (Plan 6 spec §4.4), from the subscription's invoices.
	payment_status?: PaymentStatus;
	payment_overdue?: boolean;
}

export const PAYMENT_STATUSES = ["none", "unpaid", "partial", "paid"] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export interface Slot {
	id: number;
	weekday: number;
```

In `dashboard/src/lib/zoned-time.ts`, replace:

```ts
	}).format(now);
}

/** A weekday's name, 0 = Monday … 6 = Sunday (the API's numbering). */
export function weekdayName(
	weekday: number,
```

with:

```ts
	}).format(now);
}

/** The calendar date `days` after `day` (both "YYYY-MM-DD"); no clock or
 * zone is involved, so a daylight-saving change never shifts it. */
export function addDays(day: string, days: number): string {
	const [year, month, date] = day.split("-").map(Number);
	return new Date(Date.UTC(year, month - 1, date + days))
		.toISOString()
		.slice(0, 10);
}

/** A weekday's name, 0 = Monday … 6 = Sunday (the API's numbering). */
export function weekdayName(
	weekday: number,
```


Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "errors": {
    "billing": {
      "has_payments": "This invoice has payments, so it can't be changed that way.",
      "invoice_void": "This invoice is void.",
      "subscription_invoiced": "This subscription has invoices. Void them before deleting it."
    }
  },
  "academySettings": {
    "invoices": "Invoices",
    "autoInvoice": "Invoice every new or renewed subscription",
    "dueDays": "Invoices are due after (days)",
    "invoicesHint": "The invoice is for the subscription's price and is billed to the student's first guardian. A free subscription gets no invoice.",
    "errors": {
      "dueDaysRange": "Choose 0 to 90 days."
    }
  },
  "billing": {
    "status": {
      "unpaid": "Unpaid",
      "partial": "Partly paid",
      "paid": "Paid",
      "void": "Void"
    },
    "overdue": "Overdue",
    "paymentStatus": {
      "none": "No invoice",
      "unpaid": "Unpaid",
      "partial": "Partly paid",
      "paid": "Paid"
    },
    "methods": {
      "cash": "Cash",
      "bank_transfer": "Bank transfer",
      "instapay": "InstaPay",
      "vodafone_cash": "Vodafone Cash",
      "western_union": "Western Union",
      "zelle": "Zelle",
      "venmo": "Venmo",
      "cashapp": "Cash App",
      "other": "Other"
    },
    "errors": {
      "required": "Fill this in.",
      "dateRequired": "Choose a date.",
      "amountInvalid": "Enter an amount above zero, like 150 or 150.50.",
      "dueBeforeIssue": "Make it due on or after the issue date.",
      "overBalance": "That is more than the balance.",
      "tooLong": "Keep it under 120 characters."
    }
  }
}
```

Arabic:

```json
{
  "errors": {
    "billing": {
      "has_payments": "على هذه الفاتورة دفعات، فلا يمكن تغييرها بهذه الطريقة.",
      "invoice_void": "هذه الفاتورة ملغاة.",
      "subscription_invoiced": "لهذا الاشتراك فواتير. ألغِها قبل حذفه."
    }
  },
  "academySettings": {
    "invoices": "الفواتير",
    "autoInvoice": "أصدر فاتورة لكل اشتراك جديد أو مجدَّد",
    "dueDays": "تستحق الفواتير بعد (أيام)",
    "invoicesHint": "تكون الفاتورة بسعر الاشتراك وتُصدر باسم أول وليّ أمر للطالب. الاشتراك المجاني لا فاتورة له.",
    "errors": {
      "dueDaysRange": "اختر من 0 إلى 90 يومًا."
    }
  },
  "billing": {
    "status": {
      "unpaid": "غير مدفوعة",
      "partial": "مدفوعة جزئيًا",
      "paid": "مدفوعة",
      "void": "ملغاة"
    },
    "overdue": "متأخرة",
    "paymentStatus": {
      "none": "بلا فاتورة",
      "unpaid": "غير مدفوع",
      "partial": "مدفوع جزئيًا",
      "paid": "مدفوع"
    },
    "methods": {
      "cash": "نقدًا",
      "bank_transfer": "تحويل بنكي",
      "instapay": "إنستاباي",
      "vodafone_cash": "فودافون كاش",
      "western_union": "ويسترن يونيون",
      "zelle": "Zelle",
      "venmo": "Venmo",
      "cashapp": "Cash App",
      "other": "أخرى"
    },
    "errors": {
      "required": "املأ هذا الحقل.",
      "dateRequired": "اختر تاريخًا.",
      "amountInvalid": "أدخل مبلغًا أكبر من صفر، مثل 150 أو 150.50.",
      "dueBeforeIssue": "اجعل الاستحقاق في تاريخ الإصدار أو بعده.",
      "overBalance": "هذا أكثر من الرصيد المتبقي.",
      "tooLong": "اجعله أقل من 120 حرفًا."
    }
  }
}
```

- [ ] **Step 5: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features src/lib`
Expected: PASS.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): billing data layer, invoice settings and shared Fact and Confirm

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard: the print page, on its own layout

**Files:**
- Create: `dashboard/src/features/billing/InvoicePrint.tsx`, `dashboard/src/routes/_print.tsx`, `dashboard/src/routes/_print/invoices.$invoiceId.print.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated), `dashboard/src/features/billing/index.ts`, `dashboard/src/index.css`
- Test: `dashboard/src/features/billing/InvoicePrint.test.tsx` (new), `dashboard/src/routes/_print.test.tsx` (new), `dashboard/src/test/billing-fixtures.ts`

**Interfaces:**
- Consumes: Task 9's `useInvoice`, `Money`, `Fact`; `@/features/branding` `useBranding`, `useBrandName`; `requireAuth`.
- Produces: route `/_print` (pathless; signed in; no app shell) and `/_print/invoices/$invoiceId/print` → `/app/invoices/<id>/print` (D10); `InvoicePrint({invoiceId: string})` exported from `@/features/billing`.
- Produces: the `@media print` block in `src/index.css`.
- Produces (tests): `academyBranding(overrides)` in `@/test/billing-fixtures`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/billing/InvoicePrint.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { brandingApi } from "@/features/branding/api";
import i18n from "@/lib/i18n";
import {
	academyBranding,
	familyInvoice,
	invoiceDetail,
	paymentRow,
} from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { billingApi } from "./api";
import { InvoicePrint } from "./InvoicePrint";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, billingApi: { ...actual.billingApi, get: vi.fn() } };
});
vi.mock("@/features/branding/api", () => ({ brandingApi: { get: vi.fn() } }));

function notFound() {
	return new AxiosError("Not Found", "404", undefined, undefined, {
		status: 404,
	} as never);
}

describe("InvoicePrint", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(brandingApi.get).mockResolvedValue(
			academyBranding({ logo_url: "/media/logo.png" }),
		);
		vi.mocked(billingApi.get).mockResolvedValue(invoiceDetail());
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
		document.documentElement.classList.remove("dark");
	});

	it("prints the academy's invoice with its payments and balance", async () => {
		const print = vi.spyOn(window, "print").mockImplementation(() => {});
		const user = userEvent.setup();
		renderWithRouter(<InvoicePrint invoiceId="51" />);
		const sheet = await screen.findByRole("article", { name: "Invoice" });
		expect(billingApi.get).toHaveBeenCalledWith(51);
		expect(within(sheet).getByText("INV-000051")).toBeInTheDocument();
		expect(within(sheet).getByText("Partly paid")).toBeInTheDocument();
		expect(
			await within(sheet).findByRole("img", { name: "Demo Academy" }),
		).toHaveAttribute("src", "/media/logo.png");
		expect(within(sheet).getByText("Omar")).toBeInTheDocument();
		expect(within(sheet).getByText("Yusuf")).toBeInTheDocument();
		expect(within(sheet).getByText("Jun 8, 2026")).toBeInTheDocument();
		expect(within(sheet).getByText("Tajweed — Monthly")).toBeInTheDocument();
		expect(
			within(sheet).getByText("Jun 2, 2026 · InstaPay · IP-9"),
		).toBeInTheDocument();
		const balance = within(sheet).getByText("Balance due").nextElementSibling;
		expect(balance?.textContent).toMatch(/1,000\.00/);
		await user.click(screen.getByRole("button", { name: "Print" }));
		expect(print).toHaveBeenCalledOnce();
	});

	it("is a receipt once paid, for a parent too, with no staff fields", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			familyInvoice({
				status: "paid",
				paid_minor: 150000,
				balance_minor: 0,
				payments: [paymentRow({ amount_minor: 150000, method: "cash" })],
			}),
		);
		renderWithRouter(<InvoicePrint invoiceId="51" />);
		const sheet = await screen.findByRole("article", { name: "Receipt" });
		// The status under the number; "Paid" is also a label in the totals.
		expect(
			within(sheet).getByText("Paid", { selector: "header p" }),
		).toBeInTheDocument();
		expect(within(sheet).queryByText("Sibling rate")).toBeNull();
		expect(within(sheet).queryByText("First half")).toBeNull();
	});

	it("reads right to left in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<InvoicePrint invoiceId="51" />);
		const sheet = await screen.findByRole("article", { name: "فاتورة" });
		expect(screen.getByRole("main")).toHaveAttribute("dir", "rtl");
		expect(within(sheet).getByText("مدفوعة جزئيًا")).toBeInTheDocument();
		expect(await within(sheet).findByText("أكاديمية ديمو")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "طباعة" })).toBeInTheDocument();
	});

	it("prints on the light palette and gives the dark one back", async () => {
		document.documentElement.classList.add("dark");
		const { unmount } = renderWithRouter(<InvoicePrint invoiceId="51" />);
		await screen.findByRole("article", { name: "Invoice" });
		expect(document.documentElement).not.toHaveClass("dark");
		unmount();
		expect(document.documentElement).toHaveClass("dark");
	});

	it("says so for a missing invoice, a bad id or a failed load", async () => {
		vi.mocked(billingApi.get).mockRejectedValueOnce(notFound());
		const { unmount } = renderWithRouter(<InvoicePrint invoiceId="99" />);
		expect(
			await screen.findByText("This invoice couldn't be found."),
		).toBeInTheDocument();
		unmount();
		const second = renderWithRouter(<InvoicePrint invoiceId="abc" />);
		expect(
			await screen.findByText("This invoice couldn't be found."),
		).toBeInTheDocument();
		expect(billingApi.get).toHaveBeenCalledTimes(1);
		second.unmount();
		vi.mocked(billingApi.get).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<InvoicePrint invoiceId="51" />);
		expect(
			await screen.findByText("Couldn't load this invoice."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/routes/_print.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { billingApi } from "@/features/billing/api";
import { brandingApi } from "@/features/branding/api";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { academyBranding, familyInvoice } from "@/test/billing-fixtures";
import { page } from "@/test/scheduling-fixtures";
import { routeTree } from "../routeTree.gen";

vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});
vi.mock("@/features/billing/api", async (orig) => {
	const actual = await orig<typeof import("@/features/billing/api")>();
	return { ...actual, billingApi: { ...actual.billingApi, get: vi.fn() } };
});
vi.mock("@/features/branding/api", () => ({ brandingApi: { get: vi.fn() } }));
vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			list: vi.fn(),
			sessionList: vi.fn(),
		},
	};
});

const parent: Me = {
	id: 31,
	email: "omar@b.com",
	full_name: "Omar",
	role: "parent",
	profiles: ["parent"],
	children: [{ id: 11, full_name: "Yusuf", student_profile_id: 5 }],
};

function renderAt(path: string) {
	const queryClient = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	const router = createRouter({
		routeTree,
		context: { queryClient },
		history: createMemoryHistory({ initialEntries: [path] }),
	});
	render(
		<ThemeProvider>
			<QueryClientProvider client={queryClient}>
				<RouterProvider router={router} />
			</QueryClientProvider>
		</ThemeProvider>,
	);
	return router;
}

describe("the print route", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(identityApi.me).mockResolvedValue(parent);
		vi.mocked(billingApi.get).mockResolvedValue(familyInvoice());
		vi.mocked(brandingApi.get).mockResolvedValue(academyBranding());
		vi.mocked(schedulingApi.list).mockResolvedValue(page([]));
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(page([]));
	});

	it("prints a parent's invoice without the app shell", async () => {
		renderAt("/invoices/51/print");
		expect(
			await screen.findByRole("article", { name: "Invoice" }),
		).toBeInTheDocument();
		expect(billingApi.get).toHaveBeenCalledWith(51);
		expect(
			screen.queryByRole("navigation", { name: "Main navigation" }),
		).toBeNull();
	});

	it("keeps the app shell on the app's own pages", async () => {
		renderAt("/");
		expect(
			await screen.findByRole("navigation", { name: "Main navigation" }),
		).toBeInTheDocument();
	});

	it("sends a signed-out visitor to sign in", async () => {
		vi.mocked(identityApi.me).mockRejectedValue(new Error("401"));
		const router = renderAt("/invoices/51/print");
		await vi.waitFor(() =>
			expect(router.state.location.pathname).toBe("/login"),
		);
		expect(billingApi.get).not.toHaveBeenCalled();
	});
});
```

In `dashboard/src/test/billing-fixtures.ts`, replace:

```ts
	BillingSummary,
	Invoice,
	InvoiceDetail,
	Payment,
} from "@/features/billing/schemas";

/** API-shaped billing rows for feature tests (an admin's view). */
export function invoiceRow(overrides: Partial<Invoice> = {}): Invoice {
	return {
		id: 51,
```

with:

```ts
	BillingSummary,
	Invoice,
	InvoiceDetail,
	Payment,
} from "@/features/billing/schemas";
import type { Branding } from "@/features/branding";
import {
	NOOR_ACCENT,
	NOOR_PRIMARY,
	NOOR_PRIMARY_TEXT,
} from "@/test/branding-fixtures";

/** API-shaped billing rows for feature tests (an admin's view). */
export function invoiceRow(overrides: Partial<Invoice> = {}): Invoice {
	return {
		id: 51,
```

Append to the end of `dashboard/src/test/billing-fixtures.ts`:

```ts
/** The academy's site branding (`site/branding/`), for the print page. */
export function academyBranding(overrides: Partial<Branding> = {}): Branding {
	return {
		name: { ar: "أكاديمية ديمو", en: "Demo Academy" },
		tagline: { ar: "", en: "" },
		logo_url: "",
		favicon_url: "",
		share_image_url: "",
		primary_color: NOOR_PRIMARY,
		primary_text: NOOR_PRIMARY_TEXT,
		accent_color: NOOR_ACCENT,
		contact: {
			email: "",
			phone: "",
			whatsapp: "",
			address: { ar: "", en: "" },
		},
		social: {},
		show_powered_by: true,
		...overrides,
	};
}
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing/InvoicePrint.test.tsx src/routes/_print.test.tsx`
Expected: FAIL — `Failed to resolve import "./InvoicePrint"`; the route test finds no print page (`Unable to find role="article" and name "Invoice"`) and a signed-out visitor is not sent to `/login` (there is no such route yet).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/billing/InvoicePrint.tsx`:

```tsx
import { isAxiosError } from "axios";
import { type ReactNode, useEffect } from "react";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { useBranding, useBrandName } from "@/features/branding";
import { formatDay } from "@/lib/zoned-time";
import { Alert, AlertDescription, Button, Spinner } from "@/ui";
import { Money } from "./bits";
import { useInvoice } from "./queries";

/** Paper is white: while the print page is open it renders on the light
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

/** Spec §6 print page (P6-5): the academy's logo and name, the invoice or
 * receipt, its payments and the balance due, in the reader's language and
 * direction, for A4. Whoever may read the invoice may print it: the server
 * already scopes `billing/invoices/<id>/`. */
export function InvoicePrint({ invoiceId }: { invoiceId: string }) {
	const { t, i18n } = useTranslation();
	useLightPaper();
	const parsed = Number(invoiceId);
	// `/invoices/abc/print` is never an invoice: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: invoice,
		isError,
		error,
	} = useInvoice(invalidId ? undefined : parsed);
	const { data: brand } = useBranding();
	const academy = useBrandName();
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
		const receipt = invoice.status === "paid";
		body = (
			<>
				<div className="flex justify-end print:hidden">
					<Button onClick={() => window.print()}>
						{t("billing.print.print")}
					</Button>
				</div>
				<article
					aria-labelledby="invoice-title"
					className="invoice-sheet flex flex-col gap-6 rounded-lg border border-border bg-card p-6 text-card-foreground sm:p-8"
				>
					<header className="flex flex-wrap items-start justify-between gap-4 border-b border-border pb-4">
						<div className="flex items-center gap-3">
							{brand?.logo_url ? (
								<img
									src={brand.logo_url}
									alt={academy}
									className="h-12 w-auto"
								/>
							) : null}
							<p className="text-lg font-semibold">{academy}</p>
						</div>
						<div className="flex flex-col gap-1 text-end">
							<h1 id="invoice-title" className="text-2xl font-semibold">
								{receipt
									? t("billing.print.receipt")
									: t("billing.print.invoice")}
							</h1>
							<p dir="ltr" className="font-medium">
								{invoice.number}
							</p>
							<p className="text-sm">{t(`billing.status.${invoice.status}`)}</p>
						</div>
					</header>
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
						<dt className="font-semibold">{t("billing.print.balanceDue")}</dt>
						<dd className="text-end font-semibold">
							<Money
								minor={invoice.balance_minor}
								currency={invoice.currency}
							/>
						</dd>
					</dl>
				</article>
			</>
		);
	}
	return (
		<main
			dir={i18n.dir()}
			className="mx-auto flex max-w-3xl flex-col gap-4 p-4 sm:p-6 print:max-w-none print:p-0"
		>
			{body}
		</main>
	);
}
```

In `dashboard/src/features/billing/index.ts`, replace:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export * from "./queries";
export * from "./schemas";
```

with:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export { InvoicePrint } from "./InvoicePrint";
export * from "./queries";
export * from "./schemas";
```

Append to the end of `dashboard/src/index.css`:

```css
/* The printed invoice (Plan 6, spec §6): A4 paper, and the sheet drops its
   on-screen frame. Controls marked `print:hidden` stay on the screen. The
   print page switches to the light palette while it is open, so the tokens
   below are the light ones. */
@media print {
	@page {
		size: A4;
		margin: 16mm;
	}
	body {
		background-color: var(--color-card);
	}
	.invoice-sheet {
		border-color: transparent;
		padding: 0;
	}
}
```

Create `dashboard/src/routes/_print.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireAuth } from "@/features/identity/require-auth";

/** Pages printed on paper (Plan 6 P6-5): signed in, but without the app
 * shell — no sidebar, top bar or menus. The page itself decides who may see
 * what; the server scopes the data. */
export const Route = createFileRoute("/_print")({
	beforeLoad: ({ context }) => requireAuth(context),
	component: () => <Outlet />,
});
```

Create `dashboard/src/routes/_print/invoices.$invoiceId.print.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoicePrint } from "@/features/billing";
import { usePageTitle } from "@/features/branding";

export const Route = createFileRoute("/_print/invoices/$invoiceId/print")({
	component: function InvoicePrintRoute() {
		const { t } = useTranslation();
		const { invoiceId } = Route.useParams();
		usePageTitle(t("billing.print.invoice"));
		return <InvoicePrint invoiceId={invoiceId} />;
	},
});
```


Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "billing": {
    "columns": {
      "number": "Number",
      "student": "Student",
      "payer": "Billed to",
      "amount": "Amount",
      "paid": "Paid",
      "balance": "Balance",
      "issued": "Issued",
      "due": "Due",
      "status": "Status",
      "description": "Description"
    },
    "invoice": {
      "notFound": "This invoice couldn't be found.",
      "loadError": "Couldn't load this invoice."
    },
    "payments": {
      "title": "Payments",
      "none": "No payments yet."
    },
    "print": {
      "invoice": "Invoice",
      "receipt": "Receipt",
      "print": "Print",
      "balanceDue": "Balance due"
    }
  }
}
```

Arabic:

```json
{
  "billing": {
    "columns": {
      "number": "الرقم",
      "student": "الطالب",
      "payer": "باسم",
      "amount": "المبلغ",
      "paid": "المدفوع",
      "balance": "المتبقي",
      "issued": "تاريخ الإصدار",
      "due": "تاريخ الاستحقاق",
      "status": "الحالة",
      "description": "الوصف"
    },
    "invoice": {
      "notFound": "لم نعثر على هذه الفاتورة.",
      "loadError": "تعذّر تحميل هذه الفاتورة."
    },
    "payments": {
      "title": "الدفعات",
      "none": "لا دفعات بعد."
    },
    "print": {
      "invoice": "فاتورة",
      "receipt": "إيصال",
      "print": "طباعة",
      "balanceDue": "المبلغ المستحق"
    }
  }
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing src/routes`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): printable invoice and receipt

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Dashboard: the invoice page, with edit and payment dialogs

**Files:**
- Create: `dashboard/src/features/billing/EditInvoiceDialog.tsx`, `dashboard/src/features/billing/InvoicePage.tsx`, `dashboard/src/features/billing/PaymentDialog.tsx`, `dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`, `dashboard/src/routes/_authed/billing.tsx`, `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated), `dashboard/src/features/billing/index.ts`
- Test: `dashboard/src/features/billing/InvoicePage.test.tsx` (new)

**Interfaces:**
- Consumes: Task 9's hooks, schemas and `Confirm`/`Fact`; Task 10's print route (`/invoices/$invoiceId/print`).
- Produces: `InvoicePage({invoiceId: string, admin: boolean})` (spec §6; D14) with `EditInvoiceDialog({invoice})` and `PaymentDialog({invoice})`.
- Routes: `/_authed/billing` (`requireAdmin`, `PageContainer`); `/_authed/billing/invoices/$invoiceId` (admin); `/_authed/learning/invoices/$invoiceId` (read-only).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/billing/InvoicePage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import i18n from "@/lib/i18n";
import {
	familyInvoice,
	invoiceDetail,
	paymentRow,
} from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings } from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { InvoicePage } from "./InvoicePage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		billingApi: {
			...actual.billingApi,
			get: vi.fn(),
			update: vi.fn(),
			void: vi.fn(),
			addPayment: vi.fn(),
			deletePayment: vi.fn(),
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

const PRINT = "/invoices/$invoiceId/print";
const SUBSCRIPTION = "/scheduling/subscriptions/$subscriptionId";

function renderPage(admin = true, invoiceId = "51") {
	return renderWithRouter(<InvoicePage invoiceId={invoiceId} admin={admin} />, {
		extraPaths: [PRINT, SUBSCRIPTION],
	});
}

describe("InvoicePage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Tokyo" }),
		);
		vi.mocked(billingApi.get).mockResolvedValue(invoiceDetail());
	});
	afterEach(() => vi.useRealTimers());

	it("shows an admin the invoice, its payments and every action", async () => {
		renderPage();
		expect(await screen.findByText("INV-000051")).toBeInTheDocument();
		expect(billingApi.get).toHaveBeenCalledWith(51);
		expect(screen.getByText("Partly paid")).toBeInTheDocument();
		expect(screen.getByText("Omar")).toBeInTheDocument();
		expect(screen.getByText("Sibling rate")).toBeInTheDocument();
		expect(screen.getByText("First half")).toBeInTheDocument();
		expect(screen.getByText("Jun 2, 2026 · IP-9")).toBeInTheDocument();
		expect(
			screen.getByRole("link", { name: "Open the subscription" }),
		).toHaveAttribute("href", "/scheduling/subscriptions/7");
		expect(screen.getByRole("link", { name: "Print" })).toHaveAttribute(
			"href",
			"/invoices/51/print",
		);
		expect(screen.getByRole("button", { name: "Edit" })).toBeInTheDocument();
		expect(
			screen.getByRole("button", { name: "Record payment" }),
		).toBeInTheDocument();
		// Paid into: no voiding until the payment is deleted.
		expect(screen.queryByRole("button", { name: "Void invoice" })).toBeNull();
		expect(
			screen.getByRole("button", { name: /^Delete payment of .*500\.00$/ }),
		).toBeInTheDocument();
	});

	it("is read-only for a parent or student, who can still print", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(familyInvoice());
		renderPage(false);
		expect(await screen.findByText("INV-000051")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Print" })).toBeInTheDocument();
		for (const name of ["Edit", "Record payment", "Void invoice"]) {
			expect(screen.queryByRole("button", { name })).toBeNull();
		}
		expect(
			screen.queryByRole("button", { name: /^Delete payment/ }),
		).toBeNull();
		expect(
			screen.queryByRole("link", { name: "Open the subscription" }),
		).toBeNull();
		expect(screen.queryByText("Sibling rate")).toBeNull();
	});

	it("records a payment of at most the balance, dated the academy's today", async () => {
		// 20:00 UTC on 1 June is already 2 June in the academy's Tokyo, and
		// still 1 June for a reader in UTC.
		vi.useFakeTimers({
			now: new Date("2026-06-01T20:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(billingApi.addPayment).mockResolvedValue(invoiceDetail());
		const user = userEvent.setup();
		renderPage();
		await user.click(
			await screen.findByRole("button", { name: "Record payment" }),
		);
		const dialog = await screen.findByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Amount/);
		expect(amount).toHaveValue("1000.00");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Paid on/)).toHaveValue(
				"2026-06-02",
			),
		);
		await user.clear(amount);
		await user.type(amount, "1000.01");
		await user.click(
			within(dialog).getByRole("button", { name: "Record payment" }),
		);
		expect(
			await within(dialog).findByText("That is more than the balance."),
		).toBeInTheDocument();
		expect(billingApi.addPayment).not.toHaveBeenCalled();
		await user.clear(amount);
		await user.type(amount, "250");
		await user.selectOptions(
			within(dialog).getByLabelText(/^Method/),
			"bank_transfer",
		);
		await user.clear(within(dialog).getByLabelText(/^Paid on/));
		await user.type(within(dialog).getByLabelText(/^Paid on/), "2026-06-03");
		await user.type(within(dialog).getByLabelText("Reference"), "TR-1");
		await user.click(
			within(dialog).getByRole("button", { name: "Record payment" }),
		);
		await waitFor(() =>
			expect(billingApi.addPayment).toHaveBeenCalledWith({
				id: 51,
				amount_minor: 25000,
				method: "bank_transfer",
				paid_on: "2026-06-03",
				reference: "TR-1",
				notes: "",
			}),
		);
		expect(await screen.findByText("Payment recorded.")).toBeInTheDocument();
	});

	it("shows the server's refusal of a payment on the amount", async () => {
		vi.mocked(billingApi.addPayment).mockRejectedValue(
			error(400, { amount_minor: ["That is more than the balance."] }),
		);
		const user = userEvent.setup();
		renderPage();
		await user.click(
			await screen.findByRole("button", { name: "Record payment" }),
		);
		const dialog = await screen.findByRole("dialog");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Paid on/)).not.toHaveValue(""),
		);
		await user.click(
			within(dialog).getByRole("button", { name: "Record payment" }),
		);
		const amount = within(dialog).getByLabelText(/^Amount/);
		await waitFor(() => expect(amount).toHaveAttribute("aria-invalid", "true"));
		expect(
			within(dialog).getByText("That is more than the balance."),
		).toBeInTheDocument();
	});

	it("edits only what changed and keeps the amount once paid into", async () => {
		vi.mocked(billingApi.update).mockResolvedValue(invoiceDetail());
		const user = userEvent.setup();
		renderPage();
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		const dialog = await screen.findByRole("dialog");
		expect(within(dialog).getByLabelText(/^Amount/)).toBeDisabled();
		const due = within(dialog).getByLabelText(/^Due/);
		await user.clear(due);
		await user.type(due, "2026-05-31");
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		expect(
			await within(dialog).findByText(
				"Make it due on or after the issue date.",
			),
		).toBeInTheDocument();
		await user.clear(due);
		await user.type(due, "2026-06-15");
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(billingApi.update).toHaveBeenCalledWith({
				id: 51,
				due_on: "2026-06-15",
			}),
		);
	});

	it("edits the amount of an invoice nobody has paid into", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				status: "unpaid",
				paid_minor: 0,
				balance_minor: 150000,
				payments: [],
			}),
		);
		vi.mocked(billingApi.update).mockResolvedValue(invoiceDetail());
		const user = userEvent.setup();
		renderPage();
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		const dialog = await screen.findByRole("dialog");
		const amount = within(dialog).getByLabelText(/^Amount/);
		await user.clear(amount);
		await user.type(amount, "1200");
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(billingApi.update).toHaveBeenCalledWith({
				id: 51,
				amount_minor: 120000,
			}),
		);
	});

	it("voids an unpaid invoice, or says why it can't", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				status: "unpaid",
				paid_minor: 0,
				balance_minor: 150000,
				payments: [],
			}),
		);
		vi.mocked(billingApi.void)
			.mockRejectedValueOnce(
				error(409, { detail: "x", code: "billing.has_payments" }),
			)
			.mockResolvedValueOnce(invoiceDetail({ status: "void" }));
		const user = userEvent.setup();
		renderPage();
		const voidOnce = async () => {
			await user.click(
				await screen.findByRole("button", { name: "Void invoice" }),
			);
			const confirm = await screen.findByRole("alertdialog");
			await user.click(
				within(confirm).getByRole("button", { name: "Void this invoice" }),
			);
		};
		await voidOnce();
		expect(
			await screen.findByText(
				"This invoice has payments, so it can't be changed that way.",
			),
		).toBeInTheDocument();
		await voidOnce();
		await waitFor(() => expect(billingApi.void).toHaveBeenCalledTimes(2));
		expect(billingApi.void).toHaveBeenLastCalledWith(51);
		expect(await screen.findByText("Invoice voided.")).toBeInTheDocument();
	});

	it("deletes a payment after confirmation", async () => {
		vi.mocked(billingApi.deletePayment).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderPage();
		await user.click(
			await screen.findByRole("button", { name: /^Delete payment of/ }),
		);
		const confirm = await screen.findByRole("alertdialog");
		await user.click(
			within(confirm).getByRole("button", { name: "Delete payment" }),
		);
		await waitFor(() =>
			expect(billingApi.deletePayment).toHaveBeenCalledWith(61),
		);
	});

	it("offers nothing to change on a void invoice", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				status: "void",
				payments: [],
				paid_minor: 0,
				balance_minor: 150000,
			}),
		);
		renderPage();
		expect(await screen.findByText("Void")).toBeInTheDocument();
		for (const name of ["Edit", "Record payment", "Void invoice"]) {
			expect(screen.queryByRole("button", { name })).toBeNull();
		}
		expect(screen.getByRole("link", { name: "Print" })).toBeInTheDocument();
	});

	it("says so for a missing invoice, a bad id or a failed load", async () => {
		vi.mocked(billingApi.get).mockRejectedValueOnce(error(404, {}));
		const { unmount } = renderPage(true, "99");
		expect(
			await screen.findByText("This invoice couldn't be found."),
		).toBeInTheDocument();
		unmount();
		const second = renderPage(true, "abc");
		expect(
			await screen.findByText("This invoice couldn't be found."),
		).toBeInTheDocument();
		expect(billingApi.get).toHaveBeenCalledTimes(1);
		second.unmount();
		vi.mocked(billingApi.get).mockRejectedValueOnce(new Error("offline"));
		renderPage();
		expect(
			await screen.findByText("Couldn't load this invoice."),
		).toBeInTheDocument();
	});

	it("lists payments in the reader's language", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [paymentRow({ method: "vodafone_cash", reference: "" })],
			}),
		);
		renderPage();
		expect(await screen.findByText(/Vodafone Cash/)).toBeInTheDocument();
		expect(screen.getByText("Jun 2, 2026")).toBeInTheDocument();
	});

	it("reads in Arabic, the payment dialog too", async () => {
		await i18n.changeLanguage("ar");
		try {
			const user = userEvent.setup();
			renderPage();
			expect(await screen.findByText("مدفوعة جزئيًا")).toBeInTheDocument();
			expect(screen.getByText("باسم")).toBeInTheDocument();
			expect(screen.getByRole("link", { name: "طباعة" })).toBeInTheDocument();
			await user.click(screen.getByRole("button", { name: "تسجيل دفعة" }));
			const dialog = await screen.findByRole("dialog");
			expect(within(dialog).getByLabelText(/^طريقة الدفع/)).toHaveValue("cash");
			expect(
				within(dialog).getByRole("option", { name: "إنستاباي" }),
			).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing/InvoicePage.test.tsx`
Expected: FAIL — `Failed to resolve import "./InvoicePage"`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/billing/EditInvoiceDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
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
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { billingApi } from "./api";
import { useBillingMutation } from "./queries";
import {
	type EditInvoiceValues,
	editInvoiceSchema,
	type InvoiceDetail,
	type InvoicePatch,
} from "./schemas";

/** Spec §4.2 Edit: description, due date and notes; the amount only while
 * nothing is paid. Sends only the fields that changed. */
export function EditInvoiceDialog({ invoice }: { invoice: InvoiceDetail }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const save = useBillingMutation(billingApi.update);
	const paidInto = invoice.payments.length > 0;
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting, dirtyFields },
	} = useForm<EditInvoiceValues>({
		resolver: zodResolver(editInvoiceSchema(invoice.issued_on)),
		values: {
			description: invoice.description,
			due_on: invoice.due_on,
			amount: toMajor(invoice.amount_minor, invoice.currency),
			notes: invoice.notes ?? "",
		},
	});

	async function onSubmit(values: EditInvoiceValues) {
		const patch: InvoicePatch = {};
		if (dirtyFields.description) patch.description = values.description;
		if (dirtyFields.due_on) patch.due_on = values.due_on;
		if (dirtyFields.notes) patch.notes = values.notes;
		if (dirtyFields.amount) {
			patch.amount_minor = toMinor(values.amount, invoice.currency);
		}
		try {
			await save.mutateAsync({ id: invoice.id, ...patch });
			setOpen(false);
			toast({ description: t("people.saved"), variant: "success" });
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
				<Button size="sm" variant="outline">
					{t("billing.edit.action")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("billing.edit.title")}</DialogTitle>
				<DialogDescription>
					{paidInto ? t("billing.edit.amountLocked") : t("billing.edit.body")}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="edit-description"
						label={t("billing.columns.description")}
						error={fieldError(errors.description?.message)}
						required
					>
						<Input {...register("description")} />
					</Field>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="edit-due_on"
							label={t("billing.columns.due")}
							error={fieldError(errors.due_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("due_on")} />
						</Field>
						<Field
							id="edit-amount"
							label={t("billing.form.amount", { currency: invoice.currency })}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input
								inputMode="decimal"
								dir="ltr"
								disabled={paidInto}
								{...register("amount")}
							/>
						</Field>
					</div>
					<Field
						id="edit-notes"
						label={t("people.field.notes")}
						error={fieldError(errors.notes?.message)}
					>
						<Textarea rows={3} {...register("notes")} />
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
							{t("people.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/billing/InvoicePage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Fact } from "@/components/Fact";
import { errorText } from "@/lib/form-errors";
import { formatMoney } from "@/lib/money";
import { formatDay } from "@/lib/zoned-time";
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
import { billingApi } from "./api";
import { InvoiceStatusChip, Money } from "./bits";
import { EditInvoiceDialog } from "./EditInvoiceDialog";
import { PaymentDialog } from "./PaymentDialog";
import { useBillingMutation, useInvoice } from "./queries";
import type { InvoiceDetail } from "./schemas";

function Actions({
	invoice,
	admin,
}: {
	invoice: InvoiceDetail;
	admin: boolean;
}) {
	const { t } = useTranslation();
	const voidInvoice = useBillingMutation(billingApi.void);
	const open = admin && invoice.status !== "void";
	return (
		<section
			aria-label={t("billing.invoice.actions")}
			className="flex flex-wrap items-center gap-2"
		>
			{open ? <EditInvoiceDialog invoice={invoice} /> : null}
			{open && invoice.balance_minor > 0 ? (
				<PaymentDialog invoice={invoice} />
			) : null}
			{open && invoice.payments.length === 0 ? (
				<Confirm
					action={t("billing.void.action")}
					title={t("billing.void.title")}
					body={t("billing.void.body")}
					onConfirm={() =>
						voidInvoice.mutate(invoice.id, {
							onSuccess: () =>
								toast({
									description: t("billing.void.done"),
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
			<Button asChild size="sm" variant="outline">
				<Link
					to="/invoices/$invoiceId/print"
					params={{ invoiceId: String(invoice.id) }}
				>
					{t("billing.print.print")}
				</Link>
			</Button>
		</section>
	);
}

function Payments({
	invoice,
	admin,
}: {
	invoice: InvoiceDetail;
	admin: boolean;
}) {
	const { t, i18n } = useTranslation();
	const remove = useBillingMutation(billingApi.deletePayment);
	const canDelete = admin && invoice.status !== "void";
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("billing.payments.title")}</CardTitle>
			</CardHeader>
			<CardContent>
				{invoice.payments.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("billing.payments.none")}
					</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{invoice.payments.map((payment) => {
							const amount = formatMoney(
								payment.amount_minor,
								invoice.currency,
								i18n.language,
							);
							return (
								<li
									key={payment.id}
									className="flex flex-wrap items-center justify-between gap-2 py-3"
								>
									<div className="flex flex-col gap-0.5 text-sm">
										<span className="font-medium">
											<span dir="ltr">{amount}</span> ·{" "}
											{t(`billing.methods.${payment.method}`)}
										</span>
										<span className="text-muted-foreground">
											{formatDay(payment.paid_on, i18n.language)}
											{payment.reference ? ` · ${payment.reference}` : ""}
										</span>
										{payment.notes ? (
											<span className="text-muted-foreground">
												{payment.notes}
											</span>
										) : null}
									</div>
									{canDelete ? (
										<Confirm
											action={t("billing.payments.delete", { amount })}
											title={t("billing.payments.deleteTitle")}
											body={t("billing.payments.deleteBody")}
											onConfirm={() =>
												remove.mutate(payment.id, {
													onError: (error) =>
														toast({
															description: errorText(error, t),
															variant: "destructive",
														}),
												})
											}
										/>
									) : null}
								</li>
							);
						})}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}

/** Spec §6 invoice page. Admins edit, record and delete payments, void and
 * print; a parent or student reads it and prints (``admin`` false). */
export function InvoicePage({
	invoiceId,
	admin,
}: {
	invoiceId: string;
	admin: boolean;
}) {
	const { t, i18n } = useTranslation();
	const parsed = Number(invoiceId);
	// `/billing/invoices/abc` is never an invoice: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: invoice,
		isError,
		error,
	} = useInvoice(invalidId ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	if (invalidId || status === 404 || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("billing.invoice.notFound")
						: t("billing.invoice.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!invoice) return <Spinner />;
	const day = (value: string) => formatDay(value, i18n.language);
	const money = (minor: number) => (
		<Money minor={minor} currency={invoice.currency} />
	);
	return (
		<div className="flex flex-col gap-6">
			<Actions invoice={invoice} admin={admin} />
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle dir="ltr">{invoice.number}</CardTitle>
					<InvoiceStatusChip invoice={invoice} />
				</CardHeader>
				<CardContent className="flex flex-col gap-4">
					<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
						<Fact label={t("billing.columns.student")}>
							{invoice.student.full_name}
						</Fact>
						<Fact label={t("billing.columns.payer")}>
							{invoice.payer.full_name}
						</Fact>
						<Fact label={t("billing.columns.issued")}>
							{day(invoice.issued_on)}
						</Fact>
						<Fact label={t("billing.columns.due")}>{day(invoice.due_on)}</Fact>
						<Fact label={t("billing.columns.amount")}>
							{money(invoice.amount_minor)}
						</Fact>
						<Fact label={t("billing.columns.paid")}>
							{money(invoice.paid_minor)}
						</Fact>
						<Fact label={t("billing.columns.balance")}>
							{money(invoice.balance_minor)}
						</Fact>
						{admin && invoice.subscription_id !== null ? (
							<Fact label={t("billing.invoice.subscription")}>
								<Link
									to="/scheduling/subscriptions/$subscriptionId"
									params={{ subscriptionId: String(invoice.subscription_id) }}
									className="text-primary-text underline-offset-4 hover:underline"
								>
									{t("billing.invoice.openSubscription")}
								</Link>
							</Fact>
						) : null}
					</dl>
					<p>{invoice.description}</p>
					{invoice.notes ? (
						<p className="text-sm text-muted-foreground">{invoice.notes}</p>
					) : null}
				</CardContent>
			</Card>
			<Payments invoice={invoice} admin={admin} />
		</div>
	);
}
```

Create `dashboard/src/features/billing/PaymentDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
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
import { billingApi } from "./api";
import { Money } from "./bits";
import { useBillingMutation } from "./queries";
import {
	type InvoiceDetail,
	PAYMENT_METHODS,
	type PaymentFormValues,
	paymentFormSchema,
} from "./schemas";

/** Spec §6 "Record payment": the amount defaults to the balance and the date
 * to the academy's today; more than the balance is refused here and by the
 * server (spec §4.1). */
export function PaymentDialog({ invoice }: { invoice: InvoiceDetail }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const { data: academy } = useAcademySettings();
	const pay = useBillingMutation(billingApi.addPayment);
	const minor = (major: string) => toMinor(major, invoice.currency);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<PaymentFormValues>({
		resolver: zodResolver(paymentFormSchema(invoice.balance_minor, minor)),
		values: {
			amount: toMajor(invoice.balance_minor, invoice.currency),
			method: "cash",
			paid_on: academy ? todayIn(academy.timezone) : "",
			reference: "",
			notes: "",
		},
	});

	async function onSubmit(values: PaymentFormValues) {
		try {
			await pay.mutateAsync({
				id: invoice.id,
				amount_minor: minor(values.amount),
				method: values.method,
				paid_on: values.paid_on,
				reference: values.reference,
				notes: values.notes,
			});
			reset();
			setOpen(false);
			toast({ description: t("billing.pay.done"), variant: "success" });
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
				<Button size="sm">{t("billing.pay.action")}</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("billing.pay.action")}</DialogTitle>
				<DialogDescription>
					{t("billing.pay.balance")}{" "}
					<Money minor={invoice.balance_minor} currency={invoice.currency} />
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="pay-amount"
							label={t("billing.form.amount", { currency: invoice.currency })}
							error={fieldError(errors.amount?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("amount")} />
						</Field>
						<Field
							id="pay-method"
							label={t("billing.pay.method")}
							error={fieldError(errors.method?.message)}
							required
						>
							<Select {...register("method")}>
								{PAYMENT_METHODS.map((method) => (
									<option key={method} value={method}>
										{t(`billing.methods.${method}`)}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="pay-paid_on"
							label={t("billing.pay.paidOn")}
							error={fieldError(errors.paid_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("paid_on")} />
						</Field>
						<Field
							id="pay-reference"
							label={t("billing.pay.reference")}
							error={fieldError(errors.reference?.message)}
						>
							<Input dir="ltr" {...register("reference")} />
						</Field>
					</div>
					<Field
						id="pay-notes"
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
							{t("billing.pay.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

In `dashboard/src/features/billing/index.ts`, replace:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export { InvoicePrint } from "./InvoicePrint";
export * from "./queries";
export * from "./schemas";
```

with:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export { InvoicePage } from "./InvoicePage";
export { InvoicePrint } from "./InvoicePrint";
export * from "./queries";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoicePage } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/invoices/$invoiceId")({
	component: function InvoiceRoute() {
		const { t } = useTranslation();
		const { invoiceId } = Route.useParams();
		usePageTitle(t("billing.invoice.title"));
		return (
			<>
				<PageHeader title={t("billing.invoice.title")} />
				<InvoicePage invoiceId={invoiceId} admin />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/billing.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireAdmin } from "@/features/identity/require-admin";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/billing")({
	beforeLoad: ({ context }) => requireAdmin(context),
	component: () => (
		<PageContainer>
			<Outlet />
		</PageContainer>
	),
});
```

Create `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoicePage } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/invoices/$invoiceId")({
	component: function FamilyInvoiceRoute() {
		const { t } = useTranslation();
		const { invoiceId } = Route.useParams();
		usePageTitle(t("billing.invoice.title"));
		return (
			<>
				<PageHeader title={t("billing.invoice.title")} />
				<InvoicePage invoiceId={invoiceId} admin={false} />
			</>
		);
	},
});
```


Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "billing": {
    "invoice": {
      "title": "Invoice",
      "actions": "Invoice actions",
      "subscription": "Subscription",
      "openSubscription": "Open the subscription"
    },
    "form": {
      "amount": "Amount ({{currency}})"
    },
    "edit": {
      "action": "Edit",
      "title": "Edit invoice",
      "body": "Change the description, due date, amount or notes.",
      "amountLocked": "Payments are recorded, so the amount stays as it is. Delete them to change it."
    },
    "pay": {
      "action": "Record payment",
      "balance": "Balance:",
      "method": "Method",
      "paidOn": "Paid on",
      "reference": "Reference",
      "save": "Record payment",
      "done": "Payment recorded."
    },
    "void": {
      "action": "Void invoice",
      "title": "Void this invoice",
      "body": "A void invoice takes no payments and can't be brought back. It stays in the list for the record.",
      "done": "Invoice voided."
    },
    "payments": {
      "delete": "Delete payment of {{amount}}",
      "deleteTitle": "Delete payment",
      "deleteBody": "Only for a payment recorded by mistake. The invoice's balance and status follow."
    }
  }
}
```

Arabic:

```json
{
  "billing": {
    "invoice": {
      "title": "فاتورة",
      "actions": "إجراءات الفاتورة",
      "subscription": "الاشتراك",
      "openSubscription": "افتح الاشتراك"
    },
    "form": {
      "amount": "المبلغ ({{currency}})"
    },
    "edit": {
      "action": "تعديل",
      "title": "تعديل الفاتورة",
      "body": "غيّر الوصف أو تاريخ الاستحقاق أو المبلغ أو الملاحظات.",
      "amountLocked": "سُجّلت دفعات، فيبقى المبلغ كما هو. احذفها لتغييره."
    },
    "pay": {
      "action": "تسجيل دفعة",
      "balance": "المتبقي:",
      "method": "طريقة الدفع",
      "paidOn": "تاريخ الدفع",
      "reference": "المرجع",
      "save": "تسجيل الدفعة",
      "done": "سُجّلت الدفعة."
    },
    "void": {
      "action": "إلغاء الفاتورة",
      "title": "إلغاء هذه الفاتورة",
      "body": "الفاتورة الملغاة لا تقبل دفعات ولا يمكن استعادتها. تبقى في القائمة للسجل.",
      "done": "أُلغيت الفاتورة."
    },
    "payments": {
      "delete": "حذف دفعة بقيمة {{amount}}",
      "deleteTitle": "حذف الدفعة",
      "deleteBody": "فقط لدفعة سُجّلت خطأً. يتبعها رصيد الفاتورة وحالتها."
    }
  }
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): invoice page with edit, payments and void

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Dashboard: the admin Invoices list, New invoice and the Billing nav group

**Files:**
- Create: `dashboard/src/features/billing/InvoiceForm.tsx`, `dashboard/src/features/billing/InvoicesList.tsx`, `dashboard/src/routes/_authed/billing.index.tsx`, `dashboard/src/routes/_authed/billing.invoices.index.tsx`, `dashboard/src/routes/_authed/billing.invoices.new.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated), `dashboard/src/features/billing/index.ts`, `dashboard/src/features/shell/nav.ts`
- Test: `dashboard/src/features/billing/InvoiceForm.test.tsx` (new), `dashboard/src/features/billing/InvoicesList.test.tsx` (new), `dashboard/src/features/shell/nav.test.ts`

**Interfaces:**
- Consumes: Task 9's hooks, `usePayers`, `useSubscriptions(…, {enabled})`, `useLocalName`, `addDays`; Task 11's `/billing/invoices/$invoiceId`.
- Produces: `InvoicesList({initialStatus?: string})` and `INVOICE_TABS`; `InvoiceForm()` (D3, D5).
- Routes: `/_authed/billing/` (redirects to `/billing/invoices`); `/_authed/billing/invoices/` (`validateSearch` → `{status?: string}`); `/_authed/billing/invoices/new`.
- Produces: `NavGroup` gains `"billing"`; `NAV_ITEMS` gains `admin("/billing/invoices", "nav.invoices", Receipt, "billing")` after the Scheduling group (D11).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/billing/InvoiceForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import { schedulingApi } from "@/features/scheduling/api";
import i18n from "@/lib/i18n";
import { invoiceDetail } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import {
	academySettings,
	page,
	subscriptionRow,
} from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { InvoiceForm } from "./InvoiceForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		billingApi: { ...actual.billingApi, create: vi.fn(), payers: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, list: vi.fn() },
	};
});

const DETAIL = "/billing/invoices/$invoiceId";

describe("InvoiceForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		// 22:00 UTC on 1 June is 2 June in the academy's Riyadh.
		vi.useFakeTimers({
			now: new Date("2026-06-01T22:00:00Z"),
			toFake: ["Date"],
		});
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({
				timezone: "Asia/Riyadh",
				default_currency: "SAR",
				invoice_due_days: 10,
			}),
		);
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				{ id: 11, user: { full_name: "Yusuf" } },
				{ id: 12, user: { full_name: "Aisha" } },
			]) as never,
		);
		vi.mocked(billingApi.payers).mockImplementation(async (student) => ({
			default: student === 11 ? 31 : 12,
			choices:
				student === 11
					? [
							{ id: 31, full_name: "Omar", relation: "guardian" as const },
							{ id: 32, full_name: "Huda", relation: "guardian" as const },
							{ id: 11, full_name: "Yusuf", relation: "student" as const },
						]
					: [{ id: 12, full_name: "Aisha", relation: "student" as const }],
		}));
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([subscriptionRow({ price_minor: 150000, currency: "EGP" })]),
		);
		vi.mocked(billingApi.create).mockResolvedValue(invoiceDetail({ id: 70 }));
	});
	afterEach(() => vi.useRealTimers());

	it("bills the first guardian from a subscription's price, due after the academy's days", async () => {
		const user = userEvent.setup();
		const { router } = renderWithRouter(<InvoiceForm />, {
			extraPaths: [DETAIL],
		});
		const due = await screen.findByLabelText(/^Due/);
		expect(due).toHaveValue("2026-06-12");
		expect(screen.getByLabelText(/^Currency/)).toHaveValue("SAR");
		expect(screen.getByLabelText(/^Billed to/)).toBeDisabled();
		expect(schedulingApi.list).not.toHaveBeenCalled();
		await user.selectOptions(screen.getByLabelText(/^Student/), "11");
		await waitFor(() =>
			expect(screen.getByLabelText(/^Billed to/)).toHaveValue("31"),
		);
		expect(billingApi.payers).toHaveBeenCalledWith(11);
		expect(
			screen.getByRole("option", { name: "Yusuf (the student)" }),
		).toBeInTheDocument();
		await waitFor(() =>
			expect(schedulingApi.list).toHaveBeenCalledWith({
				student: "11",
				page_size: 100,
			}),
		);
		await user.selectOptions(
			screen.getByLabelText("Subscription"),
			await screen.findByRole("option", { name: "Tajweed, from Jun 1, 2026" }),
		);
		expect(screen.getByLabelText(/^Amount/)).toHaveValue("1500.00");
		expect(screen.getByLabelText(/^Currency/)).toHaveValue("EGP");
		expect(screen.getByLabelText(/^Description/)).toHaveValue(
			"Tajweed — Monthly",
		);
		await user.selectOptions(screen.getByLabelText(/^Billed to/), "32");
		await user.type(screen.getByLabelText("Notes"), "Sibling rate");
		await user.click(screen.getByRole("button", { name: "Create invoice" }));
		await waitFor(() =>
			expect(billingApi.create).toHaveBeenCalledWith({
				student: 11,
				payer: 32,
				subscription: 7,
				amount_minor: 150000,
				currency: "EGP",
				due_on: "2026-06-12",
				description: "Tajweed — Monthly",
				notes: "Sibling rate",
			}),
		);
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/billing/invoices/70"),
		);
	});

	it("resets the payer to the new student's default", async () => {
		const user = userEvent.setup();
		renderWithRouter(<InvoiceForm />);
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await waitFor(() =>
			expect(screen.getByLabelText(/^Billed to/)).toHaveValue("31"),
		);
		await user.selectOptions(screen.getByLabelText(/^Student/), "12");
		await waitFor(() =>
			expect(screen.getByLabelText(/^Billed to/)).toHaveValue("12"),
		);
	});

	it("checks the fields and shows the server's field errors", async () => {
		vi.mocked(billingApi.create).mockRejectedValue(
			new AxiosError("Bad Request", "400", undefined, undefined, {
				status: 400,
				data: { amount_minor: ["Too much."], payer: ["Choose again."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<InvoiceForm />);
		await user.click(
			await screen.findByRole("button", { name: "Create invoice" }),
		);
		expect(await screen.findAllByText("Fill this in.")).toHaveLength(3);
		expect(
			screen.getByText("Enter an amount above zero, like 150 or 150.50."),
		).toBeInTheDocument();
		expect(billingApi.create).not.toHaveBeenCalled();
		await user.selectOptions(screen.getByLabelText(/^Student/), "12");
		await waitFor(() =>
			expect(screen.getByLabelText(/^Billed to/)).toHaveValue("12"),
		);
		await user.type(screen.getByLabelText(/^Amount/), "10");
		await user.type(screen.getByLabelText(/^Description/), "Books");
		await user.click(screen.getByRole("button", { name: "Create invoice" }));
		expect(await screen.findByText("Too much.")).toBeInTheDocument();
		expect(screen.getByText("Choose again.")).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		try {
			const user = userEvent.setup();
			renderWithRouter(<InvoiceForm />);
			await user.selectOptions(await screen.findByLabelText(/^الطالب/), "11");
			expect(
				await screen.findByRole("option", { name: "Omar (وليّ أمر)" }),
			).toBeInTheDocument();
			expect(screen.getByLabelText("الاشتراك")).toBeInTheDocument();
			expect(
				screen.getByRole("button", { name: "إنشاء الفاتورة" }),
			).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

Create `dashboard/src/features/billing/InvoicesList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { peopleApi } from "@/features/people/api";
import i18n from "@/lib/i18n";
import { invoiceRow } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { InvoicesList } from "./InvoicesList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, billingApi: { ...actual.billingApi, list: vi.fn() } };
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

function lastParams() {
	return vi.mocked(billingApi.list).mock.calls.at(-1)?.[0];
}

describe("InvoicesList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 11, user: { full_name: "Yusuf" } }]) as never,
		);
		vi.mocked(billingApi.list).mockResolvedValue(
			page([
				invoiceRow(),
				invoiceRow({
					id: 52,
					number: "INV-000052",
					student: { id: 12, full_name: "Aisha" },
					status: "unpaid",
					is_overdue: true,
					paid_minor: 0,
					balance_minor: 90000,
					amount_minor: 90000,
					due_on: "2026-05-20",
				}),
			]),
		);
	});

	it("shows each invoice's money, due date and status", async () => {
		renderWithRouter(<InvoicesList />, {
			extraPaths: ["/billing/invoices/$invoiceId", "/billing/invoices/new"],
		});
		const table = await screen.findByRole("table");
		const yusuf = within(table).getByRole("row", { name: /Yusuf/ });
		expect(within(yusuf).getByText("Partly paid")).toBeInTheDocument();
		// Amount, paid and balance, each in the invoice's currency.
		const cells = within(yusuf)
			.getAllByRole("cell")
			.map((cell) => cell.textContent);
		expect(cells.slice(3, 6)).toEqual([
			expect.stringMatching(/1,500\.00/),
			expect.stringMatching(/^\D*500\.00$/),
			expect.stringMatching(/1,000\.00/),
		]);
		expect(within(yusuf).getByText("Jun 8, 2026")).toBeInTheDocument();
		expect(within(yusuf).queryByText("Overdue")).toBeNull();
		const aisha = within(table).getByRole("row", { name: /Aisha/ });
		expect(within(aisha).getByText("Unpaid")).toBeInTheDocument();
		expect(within(aisha).getByText("Overdue")).toBeInTheDocument();
		expect(
			within(yusuf).getByRole("link", { name: "INV-000051" }),
		).toHaveAttribute("href", "/billing/invoices/51");
		expect(screen.getByRole("link", { name: "New invoice" })).toHaveAttribute(
			"href",
			"/billing/invoices/new",
		);
	});

	it("filters by tab, student, dates and search, and exports them", async () => {
		const user = userEvent.setup();
		renderWithRouter(<InvoicesList />);
		await screen.findByRole("table");
		expect(lastParams()).toEqual({ page: 1, status: undefined });
		await user.click(screen.getByRole("tab", { name: "Overdue" }));
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ status: "overdue", page: 1 }),
		);
		await user.selectOptions(screen.getByLabelText("Student"), "11");
		await user.type(screen.getByLabelText("Issued from"), "2026-06-01");
		await user.type(screen.getByLabelText("Issued to"), "2026-06-30");
		await user.type(screen.getByRole("searchbox"), "INV-0000");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				status: "overdue",
				student: "11",
				issued_from: "2026-06-01",
				issued_to: "2026-06-30",
				q: "INV-0000",
			}),
		);
		const csv = screen.getByRole("link", { name: "Export CSV" });
		expect(csv.getAttribute("href")).toContain("status=overdue");
		expect(csv.getAttribute("href")).toContain("student=11");
		expect(csv.getAttribute("href")).toContain("format=csv");
		await user.click(screen.getByRole("tab", { name: "All" }));
		await waitFor(() => expect(lastParams()?.status).toBeUndefined());
	});

	it("opens on the tab it is given, and ignores one it doesn't know", async () => {
		const { unmount } = renderWithRouter(
			<InvoicesList initialStatus="overdue" />,
		);
		expect(
			await screen.findByRole("tab", { name: "Overdue", selected: true }),
		).toBeInTheDocument();
		expect(lastParams()).toMatchObject({ status: "overdue" });
		unmount();
		renderWithRouter(<InvoicesList initialStatus="late" />);
		expect(
			await screen.findByRole("tab", { name: "All", selected: true }),
		).toBeInTheDocument();
		expect(lastParams()?.status).toBeUndefined();
	});

	it("shows an empty state and a load error", async () => {
		vi.mocked(billingApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<InvoicesList />);
		expect(await screen.findByText("No invoices here.")).toBeInTheDocument();
		unmount();
		vi.mocked(billingApi.list).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<InvoicesList />);
		expect(
			await screen.findByText("Couldn't load invoices."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		try {
			renderWithRouter(<InvoicesList />);
			const table = await screen.findByRole("table");
			expect(
				within(table).getByRole("columnheader", { name: "باسم" }),
			).toBeInTheDocument();
			expect(screen.getByRole("tab", { name: "متأخرة" })).toBeInTheDocument();
			expect(within(table).getByText("غير مدفوعة")).toBeInTheDocument();
			expect(
				screen.getByRole("link", { name: "فاتورة جديدة" }),
			).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/scheduling/sessions",
			"/scheduling/reports",
			"/scheduling/subscriptions",
			"/teaching/sessions",
			"/teaching/reports",
			"/learning/sessions",
```

with:

```ts
			"/scheduling/sessions",
			"/scheduling/reports",
			"/scheduling/subscriptions",
			"/billing/invoices",
			"/teaching/sessions",
			"/teaching/reports",
			"/learning/sessions",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		expect(groups.map((g) => g.group)).toEqual([
			undefined,
			"scheduling",
			"people",
			"catalogue",
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(4);
		expect(groups[2]?.items).toHaveLength(4);
	});
});
```

with:

```ts
		expect(groups.map((g) => g.group)).toEqual([
			undefined,
			"scheduling",
			"billing",
			"people",
			"catalogue",
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(4);
		expect(groups[2]?.items.map((i) => i.labelKey)).toEqual(["nav.invoices"]);
		expect(groups[3]?.items).toHaveLength(4);
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing src/features/shell/nav.test.ts`
Expected: FAIL — `Failed to resolve import "./InvoicesList"` and `"./InvoiceForm"`, and the nav order lacks `/billing/invoices`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/billing/InvoiceForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { usePeople } from "@/features/people";
import { useLocalName, useSubscriptions } from "@/features/scheduling";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
import { addDays, formatDay, todayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	Textarea,
} from "@/ui";
import { billingApi } from "./api";
import { useBillingMutation, usePayers } from "./queries";
import { type InvoiceFormValues, invoiceFormSchema } from "./schemas";

/** Spec §6 New invoice: the student, then the payer (their first guardian
 * by default, P6-4), optionally one of the student's subscriptions (which
 * fills the amount, currency and description), the due date (today plus the
 * academy's due days) and notes. */
export function InvoiceForm() {
	const { t, i18n } = useTranslation();
	const navigate = useNavigate();
	const fieldError = useFieldError();
	const localName = useLocalName();
	const [query, setQuery] = useState("");
	const { data: academy } = useAcademySettings();
	const { data: students } = usePeople("students", {
		page_size: 100,
		q: query.trim(),
	});
	const create = useBillingMutation(billingApi.create);
	const {
		register,
		handleSubmit,
		setError,
		setValue,
		getValues,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<InvoiceFormValues>({
		resolver: zodResolver(invoiceFormSchema),
		values: academy
			? {
					student: "",
					payer: "",
					subscription: "",
					amount: "",
					currency: academy.default_currency,
					due_on: addDays(todayIn(academy.timezone), academy.invoice_due_days),
					description: "",
					notes: "",
				}
			: undefined,
	});
	const chosen = watch("student");
	const studentId = chosen ? Number(chosen) : undefined;
	const { data: payers } = usePayers(studentId);
	const { data: subscriptions } = useSubscriptions(
		{ student: chosen, page_size: 100 },
		{ enabled: studentId !== undefined },
	);
	const subs = studentId === undefined ? [] : (subscriptions?.results ?? []);

	// P6-4: the default payer, once the student's choices arrive.
	useEffect(() => {
		if (!payers) return;
		const current = getValues("payer");
		if (!payers.choices.some((p) => String(p.id) === current)) {
			setValue("payer", String(payers.default));
		}
	}, [payers, getValues, setValue]);

	function pickSubscription(id: string) {
		const sub = subs.find((s) => String(s.id) === id);
		if (!sub || sub.price_minor === undefined || !sub.currency) return;
		setValue("amount", toMajor(sub.price_minor, sub.currency));
		setValue("currency", sub.currency);
		setValue(
			"description",
			`${localName(sub.course)} — ${localName(sub.package)}`,
		);
	}

	async function onSubmit(values: InvoiceFormValues) {
		try {
			const invoice = await create.mutateAsync({
				student: Number(values.student),
				payer: Number(values.payer),
				subscription: values.subscription
					? Number(values.subscription)
					: undefined,
				amount_minor: toMinor(values.amount, values.currency),
				currency: values.currency,
				due_on: values.due_on,
				description: values.description,
				notes: values.notes,
			});
			navigate({
				to: "/billing/invoices/$invoiceId",
				params: { invoiceId: String(invoice.id) },
			});
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.amount_minor) {
				setError("amount", { message: parsed.fieldErrors.amount_minor });
			}
		}
	}

	if (!academy) return <Spinner />;
	const currency = watch("currency");
	const currencies = CURRENCIES.includes(
		currency as (typeof CURRENCIES)[number],
	)
		? [...CURRENCIES]
		: [currency, ...CURRENCIES];

	return (
		<form
			onSubmit={handleSubmit(onSubmit)}
			className="flex max-w-2xl flex-col gap-4"
			noValidate
		>
			<div className="grid gap-4 sm:grid-cols-2">
				<Field
					id="invoice-student-search"
					label={t("billing.form.findStudent")}
				>
					<Input
						type="search"
						value={query}
						onChange={(e) => setQuery(e.target.value)}
					/>
				</Field>
				<Field
					id="invoice-student"
					label={t("billing.columns.student")}
					error={fieldError(errors.student?.message)}
					required
				>
					<Select
						{...register("student", {
							onChange: () => {
								setValue("payer", "");
								setValue("subscription", "");
							},
						})}
					>
						<option value="">—</option>
						{students?.results.map((p) => (
							<option key={p.id} value={p.id}>
								{p.user.full_name}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id="invoice-payer"
					label={t("billing.columns.payer")}
					error={fieldError(errors.payer?.message)}
					required
				>
					<Select disabled={!payers} {...register("payer")}>
						<option value="">—</option>
						{payers?.choices.map((person) => (
							<option key={person.id} value={person.id}>
								{t(`billing.form.payerOption.${person.relation}`, {
									name: person.full_name,
								})}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id="invoice-subscription"
					label={t("billing.invoice.subscription")}
					error={fieldError(errors.subscription?.message)}
				>
					<Select
						disabled={studentId === undefined}
						{...register("subscription", {
							onChange: (e) => pickSubscription(e.target.value),
						})}
					>
						<option value="">{t("billing.form.noSubscription")}</option>
						{subs.map((sub) => (
							<option key={sub.id} value={sub.id}>
								{t("billing.form.subscriptionOption", {
									course: localName(sub.course),
									date: formatDay(sub.starts_on, i18n.language),
								})}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id="invoice-amount"
					label={t("billing.form.amount", { currency })}
					error={fieldError(errors.amount?.message)}
					required
				>
					<Input inputMode="decimal" dir="ltr" {...register("amount")} />
				</Field>
				<Field
					id="invoice-currency"
					label={t("billing.form.currency")}
					error={fieldError(errors.currency?.message)}
					required
				>
					<Select dir="ltr" {...register("currency")}>
						{currencies.map((code) => (
							<option key={code} value={code}>
								{code}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id="invoice-due_on"
					label={t("billing.columns.due")}
					error={fieldError(errors.due_on?.message)}
					required
				>
					<Input type="date" dir="ltr" {...register("due_on")} />
				</Field>
			</div>
			<Field
				id="invoice-description"
				label={t("billing.columns.description")}
				error={fieldError(errors.description?.message)}
				required
			>
				<Input {...register("description")} />
			</Field>
			<Field
				id="invoice-notes"
				label={t("people.field.notes")}
				error={fieldError(errors.notes?.message)}
			>
				<Textarea rows={3} {...register("notes")} />
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>
						{fieldError(errors.root.server.message)}
					</AlertDescription>
				</Alert>
			) : null}
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("billing.form.create")}
			</SubmitButton>
		</form>
	);
}
```

Create `dashboard/src/features/billing/InvoicesList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Plus, Receipt } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Input,
	Select,
	Spinner,
} from "@/ui";
import { invoicesCsvUrl } from "./api";
import { InvoiceStatusChip, Money } from "./bits";
import { useInvoices } from "./queries";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
export const INVOICE_TABS = [
	"all",
	"unpaid",
	"partial",
	"paid",
	"overdue",
	"void",
] as const;
const COLUMNS = [
	"number",
	"student",
	"payer",
	"amount",
	"paid",
	"balance",
	"due",
	"status",
] as const;

/** Spec §6 Invoices (admin): status tabs, student and issue-date filters,
 * search, paging and CSV. ``initialStatus`` opens a tab (the home page's
 * overdue link). */
export function InvoicesList({ initialStatus }: { initialStatus?: string }) {
	const { t, i18n } = useTranslation();
	const opening = INVOICE_TABS.find(
		(tab) => tab === initialStatus && tab !== "all",
	);
	const [params, setParams] = useState<QueryParams>({
		page: 1,
		status: opening,
	});
	const { data, isPending, isError } = useInvoices(params);
	const { data: students } = usePeople("students", { page_size: 100 });
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const current = String(params.status ?? "all");
	const update = (patch: QueryParams) =>
		setParams({ ...params, page: 1, ...patch });

	const date = (key: "issued_from" | "issued_to", label: string) => (
		<div className="flex flex-col gap-1">
			<label htmlFor={`invoices-${key}`} className="text-xs">
				{label}
			</label>
			<Input
				id={`invoices-${key}`}
				type="date"
				dir="ltr"
				className="w-auto"
				value={String(params[key] ?? "")}
				onChange={(e) => update({ [key]: e.target.value })}
			/>
		</div>
	);

	return (
		<div className="flex flex-col gap-4">
			<div
				role="tablist"
				aria-label={t("billing.columns.status")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{INVOICE_TABS.map((tab) => (
					<button
						key={tab}
						type="button"
						role="tab"
						aria-selected={current === tab}
						onClick={() => update({ status: tab === "all" ? undefined : tab })}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{t(`billing.tabs.${tab}`)}
					</button>
				))}
			</div>
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="invoices-search" className="sr-only">
						{t("billing.list.search")}
					</label>
					<Input
						id="invoices-search"
						type="search"
						placeholder={t("billing.list.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				<Select
					aria-label={t("billing.columns.student")}
					className="w-auto"
					value={String(params.student ?? "")}
					onChange={(e) => update({ student: e.target.value })}
				>
					<option value="">{t("billing.list.anyStudent")}</option>
					{students?.results.map((p) => (
						<option key={p.id} value={p.id}>
							{p.user.full_name}
						</option>
					))}
				</Select>
				{date("issued_from", t("billing.list.issuedFrom"))}
				{date("issued_to", t("billing.list.issuedTo"))}
				<Button asChild variant="outline" size="sm">
					<a href={invoicesCsvUrl(params)} download>
						{t("people.exportCsv")}
					</a>
				</Button>
				<Button asChild size="sm">
					<Link to="/billing/invoices/new">
						<Plus className="size-4" />
						{t("billing.new")}
					</Link>
				</Button>
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("billing.list.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={Receipt} title={t("billing.list.empty")} />
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
										{t(`billing.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((invoice) => (
								<tr key={invoice.id} className="border-t border-border">
									<td className="p-3">
										<Link
											to="/billing/invoices/$invoiceId"
											params={{ invoiceId: String(invoice.id) }}
											dir="ltr"
											className="font-medium text-primary-text underline-offset-4 hover:underline"
										>
											{invoice.number}
										</Link>
									</td>
									<td className="p-3">{invoice.student.full_name}</td>
									<td className="p-3">{invoice.payer.full_name}</td>
									<td className="p-3">
										<Money
											minor={invoice.amount_minor}
											currency={invoice.currency}
										/>
									</td>
									<td className="p-3">
										<Money
											minor={invoice.paid_minor}
											currency={invoice.currency}
										/>
									</td>
									<td className="p-3">
										<Money
											minor={invoice.balance_minor}
											currency={invoice.currency}
										/>
									</td>
									<td className="p-3">
										{formatDay(invoice.due_on, i18n.language)}
									</td>
									<td className="p-3">
										<InvoiceStatusChip invoice={invoice} />
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

In `dashboard/src/features/billing/index.ts`, replace:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export { InvoicePage } from "./InvoicePage";
export { InvoicePrint } from "./InvoicePrint";
export * from "./queries";
export * from "./schemas";
```

with:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export { InvoiceForm } from "./InvoiceForm";
export { InvoicePage } from "./InvoicePage";
export { InvoicePrint } from "./InvoicePrint";
export { InvoicesList } from "./InvoicesList";
export * from "./queries";
export * from "./schemas";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	NotebookPen,
	Package,
	Presentation,
	Repeat,
	Settings,
	ShieldCheck,
```

with:

```ts
	NotebookPen,
	Package,
	Presentation,
	Receipt,
	Repeat,
	Settings,
	ShieldCheck,
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts

export type NavGroup =
	| "scheduling"
	| "teaching"
	| "learning"
	| "people"
```

with:

```ts

export type NavGroup =
	| "scheduling"
	| "billing"
	| "teaching"
	| "learning"
	| "people"
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	admin("/scheduling/sessions", "nav.sessions", ListChecks, "scheduling"),
	admin("/scheduling/reports", "nav.missingReports", FileClock, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
	// Plan 5: a teacher's own sessions and the reports they still owe.
	{
		to: "/teaching/sessions",
```

with:

```ts
	admin("/scheduling/sessions", "nav.sessions", ListChecks, "scheduling"),
	admin("/scheduling/reports", "nav.missingReports", FileClock, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
	// Plan 6: invoices and payments.
	admin("/billing/invoices", "nav.invoices", Receipt, "billing"),
	// Plan 5: a teacher's own sessions and the reports they still owe.
	{
		to: "/teaching/sessions",
```

Create `dashboard/src/routes/_authed/billing.index.tsx`:

```tsx
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/_authed/billing/")({
	beforeLoad: () => {
		throw redirect({ to: "/billing/invoices" });
	},
});
```

Create `dashboard/src/routes/_authed/billing.invoices.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoicesList } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/invoices/")({
	// `?status=overdue` opens that tab (the home page links to it).
	validateSearch: (search: Record<string, unknown>): { status?: string } => ({
		status: typeof search.status === "string" ? search.status : undefined,
	}),
	component: function InvoicesRoute() {
		const { t } = useTranslation();
		const { status } = Route.useSearch();
		usePageTitle(t("nav.invoices"));
		return (
			<>
				<PageHeader title={t("nav.invoices")} />
				<InvoicesList initialStatus={status} />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/billing.invoices.new.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { InvoiceForm } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/billing/invoices/new")({
	component: function NewInvoiceRoute() {
		const { t } = useTranslation();
		usePageTitle(t("billing.new"));
		return (
			<>
				<PageHeader title={t("billing.new")} />
				<InvoiceForm />
			</>
		);
	},
});
```


Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "nav": {
    "invoices": "Invoices",
    "group": {
      "billing": "Billing"
    }
  },
  "billing": {
    "new": "New invoice",
    "tabs": {
      "all": "All",
      "unpaid": "Unpaid",
      "partial": "Partly paid",
      "paid": "Paid",
      "overdue": "Overdue",
      "void": "Void"
    },
    "list": {
      "search": "Search by number or name",
      "anyStudent": "Any student",
      "issuedFrom": "Issued from",
      "issuedTo": "Issued to",
      "loadError": "Couldn't load invoices.",
      "empty": "No invoices here."
    },
    "form": {
      "findStudent": "Find a student",
      "payerOption": {
        "guardian": "{{name}} (guardian)",
        "student": "{{name}} (the student)"
      },
      "noSubscription": "No subscription",
      "subscriptionOption": "{{course}}, from {{date}}",
      "currency": "Currency",
      "create": "Create invoice"
    }
  }
}
```

Arabic:

```json
{
  "nav": {
    "invoices": "الفواتير",
    "group": {
      "billing": "الفوترة"
    }
  },
  "billing": {
    "new": "فاتورة جديدة",
    "tabs": {
      "all": "الكل",
      "unpaid": "غير مدفوعة",
      "partial": "مدفوعة جزئيًا",
      "paid": "مدفوعة",
      "overdue": "متأخرة",
      "void": "ملغاة"
    },
    "list": {
      "search": "ابحث بالرقم أو الاسم",
      "anyStudent": "أي طالب",
      "issuedFrom": "صادرة من",
      "issuedTo": "صادرة حتى",
      "loadError": "تعذّر تحميل الفواتير.",
      "empty": "لا فواتير هنا."
    },
    "form": {
      "findStudent": "ابحث عن طالب",
      "payerOption": {
        "guardian": "{{name}} (وليّ أمر)",
        "student": "{{name}} (الطالب نفسه)"
      },
      "noSubscription": "بلا اشتراك",
      "subscriptionOption": "{{course}}، من {{date}}",
      "currency": "العملة",
      "create": "إنشاء الفاتورة"
    }
  }
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): invoices list and new invoice form

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Dashboard: family Invoices and the admin home's Money card

**Files:**
- Create: `dashboard/src/features/billing/BillingSummaryCard.tsx`, `dashboard/src/features/billing/FamilyInvoices.tsx`, `dashboard/src/routes/_authed/learning.invoices.index.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (generated), `dashboard/src/features/billing/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/routes/_authed/index.tsx`
- Test: `dashboard/src/features/billing/BillingSummaryCard.test.tsx` (new), `dashboard/src/features/billing/FamilyInvoices.test.tsx` (new), `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/_authed/index.test.tsx`

**Interfaces:**
- Consumes: Task 9's hooks; Task 11's `/learning/invoices/$invoiceId`; Task 12's `/billing/invoices?status=`.
- Produces: `FamilyInvoices()` and `BillingSummaryCard()` from `@/features/billing`; route `/_authed/learning/invoices/`; the `learning` nav group gains Invoices for students and parents; `Home` renders `BillingSummaryCard` for admins only (D11).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/billing/BillingSummaryCard.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { billingSummary } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { billingApi } from "./api";
import { BillingSummaryCard } from "./BillingSummaryCard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, billingApi: { ...actual.billingApi, summary: vi.fn() } };
});

describe("BillingSummaryCard", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows each currency's revenue apart and links to the overdue invoices", async () => {
		vi.mocked(billingApi.summary).mockResolvedValue(billingSummary());
		renderWithRouter(<BillingSummaryCard />, {
			extraPaths: ["/billing/invoices"],
		});
		expect(await screen.findByText(/2,000\.00/)).toBeInTheDocument();
		expect(screen.getByText(/\$40\.00/)).toBeInTheDocument();
		expect(screen.getByText("Overdue invoices: 2")).toBeInTheDocument();
		expect(screen.getByText(/900\.00/)).toBeInTheDocument();
		expect(
			screen.getByRole("link", { name: "See overdue invoices" }),
		).toHaveAttribute("href", "/billing/invoices?status=overdue");
	});

	it("says when nothing is paid or overdue yet, and when it can't load", async () => {
		vi.mocked(billingApi.summary).mockResolvedValueOnce(
			billingSummary({ revenue_this_month: [], overdue: [] }),
		);
		const { unmount } = renderWithRouter(<BillingSummaryCard />);
		expect(
			await screen.findByText("No payments yet this month."),
		).toBeInTheDocument();
		expect(screen.getByText("Overdue invoices: 0")).toBeInTheDocument();
		expect(
			screen.queryByRole("link", { name: "See overdue invoices" }),
		).toBeNull();
		unmount();
		vi.mocked(billingApi.summary).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<BillingSummaryCard />);
		expect(
			await screen.findByText("Couldn't load this month's figures."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		vi.mocked(billingApi.summary).mockResolvedValue(billingSummary());
		await i18n.changeLanguage("ar");
		try {
			renderWithRouter(<BillingSummaryCard />);
			expect(
				await screen.findByRole("heading", { name: "إيرادات هذا الشهر" }),
			).toBeInTheDocument();
			expect(screen.getByText("الفواتير المتأخرة: 2")).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

Create `dashboard/src/features/billing/FamilyInvoices.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import i18n from "@/lib/i18n";
import { familyInvoice } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { FamilyInvoices } from "./FamilyInvoices";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, billingApi: { ...actual.billingApi, list: vi.fn() } };
});

describe("FamilyInvoices", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(billingApi.list).mockResolvedValue(
			page([
				familyInvoice(),
				familyInvoice({
					id: 52,
					number: "INV-000052",
					student: { id: 12, full_name: "Aisha" },
					status: "unpaid",
					is_overdue: true,
				}),
			]),
		);
	});

	it("lists each child's invoices with the balance and status", async () => {
		renderWithRouter(<FamilyInvoices />, {
			extraPaths: ["/learning/invoices/$invoiceId"],
		});
		const link = await screen.findByRole("link", { name: "INV-000051" });
		expect(link).toHaveAttribute("href", "/learning/invoices/51");
		expect(billingApi.list).toHaveBeenCalledWith({ page: 1 });
		const aisha = screen
			.getByRole("link", { name: "INV-000052" })
			.closest("li");
		expect(aisha).not.toBeNull();
		const card = within(aisha as HTMLElement);
		expect(card.getByText("For Aisha, due Jun 8, 2026")).toBeInTheDocument();
		expect(card.getByText("Overdue")).toBeInTheDocument();
		expect(card.getByText(/1,000\.00/)).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		try {
			renderWithRouter(<FamilyInvoices />);
			expect(await screen.findAllByText("مدفوعة جزئيًا")).toHaveLength(1);
			expect(screen.getByText("متأخرة")).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});

	it("shows an empty state and a load error", async () => {
		vi.mocked(billingApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<FamilyInvoices />);
		expect(await screen.findByText("No invoices here.")).toBeInTheDocument();
		unmount();
		vi.mocked(billingApi.list).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<FamilyInvoices />);
		expect(
			await screen.findByText("Couldn't load invoices."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/teaching/reports",
			"/learning/sessions",
			"/learning/subscriptions",
			"/people/students",
			"/people/parents",
			"/people/teachers",
```

with:

```ts
			"/teaching/reports",
			"/learning/sessions",
			"/learning/subscriptions",
			"/learning/invoices",
			"/people/students",
			"/people/parents",
			"/people/teachers",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		]);
	});

	it("shows students and parents their sessions and subscriptions", () => {
		for (const role of ["student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/learning/sessions",
				"/learning/subscriptions",
				"/account",
			]);
		}
```

with:

```ts
		]);
	});

	it("shows students and parents their sessions, subscriptions and invoices", () => {
		for (const role of ["student", "parent"] as const) {
			expect(visibleNavItems(NAV_ITEMS, [], role).map((i) => i.to)).toEqual([
				"/",
				"/learning/sessions",
				"/learning/subscriptions",
				"/learning/invoices",
				"/account",
			]);
		}
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { page, sessionRow, subscriptionRow } from "@/test/scheduling-fixtures";
import { Home } from "./index";

```

with:

```tsx
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { billingApi } from "@/features/billing/api";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { schedulingApi } from "@/features/scheduling/api";
import { ThemeProvider } from "@/lib/theme";
import { billingSummary } from "@/test/billing-fixtures";
import { page, sessionRow, subscriptionRow } from "@/test/scheduling-fixtures";
import { Home } from "./index";

```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
		},
	};
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
```

with:

```tsx
		},
	};
});
vi.mock("@/features/billing/api", async (orig) => {
	const actual = await orig<typeof import("@/features/billing/api")>();
	return { ...actual, billingApi: { ...actual.billingApi, summary: vi.fn() } };
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([subscriptionRow(), subscriptionRow({ id: 9, status: "expired" })]),
		);
	});

	it("shows a teacher today's sessions and their menu", async () => {
```

with:

```tsx
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([subscriptionRow(), subscriptionRow({ id: 9, status: "expired" })]),
		);
		vi.mocked(billingApi.summary).mockResolvedValue(billingSummary());
	});

	it("shows a teacher today's sessions and their menu", async () => {
```

In `dashboard/src/routes/_authed/index.test.tsx`, replace:

```tsx
		expect(screen.getByText("Reports to write")).toBeInTheDocument();
	});

	it("shows an admin no session panel", async () => {
		renderHome({ ...student, role: "admin", profiles: [] });
		expect(await screen.findByText("Students")).toBeInTheDocument();
		expect(schedulingApi.sessionList).not.toHaveBeenCalled();
	});

	it("greets the user", async () => {
```

with:

```tsx
		expect(screen.getByText("Reports to write")).toBeInTheDocument();
	});

	it("shows an admin this month's money and no session panel", async () => {
		renderHome({ ...student, role: "admin", profiles: [] });
		expect(await screen.findByText("Students")).toBeInTheDocument();
		expect(schedulingApi.sessionList).not.toHaveBeenCalled();
		expect(
			await screen.findByRole("heading", { name: "Revenue this month" }),
		).toBeInTheDocument();
		expect(screen.getByText("Invoices")).toBeInTheDocument();
	});

	it("shows no money to anyone but an admin", async () => {
		renderHome(student);
		expect(await screen.findByText("Next session")).toBeInTheDocument();
		expect(screen.queryByText("Revenue this month")).toBeNull();
		expect(billingApi.summary).not.toHaveBeenCalled();
		// Their own invoices are a tile under My learning.
		expect(screen.getByText("Invoices")).toBeInTheDocument();
	});

	it("greets the user", async () => {
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing src/features/shell/nav.test.ts src/routes/_authed/index.test.tsx`
Expected: FAIL — `Failed to resolve import "./FamilyInvoices"` and `"./BillingSummaryCard"`, the nav lacks `/learning/invoices`, and Home shows neither "Revenue this month" nor an Invoices tile.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/billing/BillingSummaryCard.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { Money } from "./bits";
import { useBillingSummary } from "./queries";

/** Spec §6 admin home: this month's revenue per currency (the academy's
 * month) and the overdue invoices. Never summed across currencies (P6-6). */
export function BillingSummaryCard() {
	const { t } = useTranslation();
	const { data, isError } = useBillingSummary();
	let body: ReactNode;
	if (isError) {
		body = (
			<Alert variant="destructive">
				<AlertDescription>{t("billing.home.loadError")}</AlertDescription>
			</Alert>
		);
	} else if (!data) {
		body = <Spinner />;
	} else {
		const overdue = data.overdue.reduce((sum, row) => sum + row.count, 0);
		body = (
			<div className="grid gap-6 sm:grid-cols-2">
				<section className="flex flex-col gap-2">
					<h3 className="text-sm text-muted-foreground">
						{t("billing.home.revenue")}
					</h3>
					{data.revenue_this_month.length === 0 ? (
						<p className="text-sm">{t("billing.home.noRevenue")}</p>
					) : (
						<ul className="flex flex-col gap-1 text-lg font-semibold">
							{data.revenue_this_month.map((row) => (
								<li key={row.currency}>
									<Money minor={row.amount_minor} currency={row.currency} />
								</li>
							))}
						</ul>
					)}
				</section>
				<section className="flex flex-col gap-2">
					<h3 className="text-sm text-muted-foreground">
						{t("billing.home.overdue", { count: overdue })}
					</h3>
					<ul className="flex flex-col gap-1 text-sm">
						{data.overdue.map((row) => (
							<li key={row.currency}>
								{t("billing.home.overdueLine", { count: row.count })}{" "}
								<Money minor={row.balance_minor} currency={row.currency} />
							</li>
						))}
					</ul>
					{overdue > 0 ? (
						<Link
							to="/billing/invoices"
							search={{ status: "overdue" }}
							className="text-sm font-medium text-primary-text underline-offset-4 hover:underline"
						>
							{t("billing.home.seeOverdue")}
						</Link>
					) : null}
				</section>
			</div>
		);
	}
	return (
		<Card className="mb-6">
			<CardHeader className="border-b border-border">
				<CardTitle>{t("billing.home.title")}</CardTitle>
			</CardHeader>
			<CardContent>{body}</CardContent>
		</Card>
	);
}
```

Create `dashboard/src/features/billing/FamilyInvoices.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Receipt } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Spinner,
} from "@/ui";
import { InvoiceStatusChip, Money } from "./bits";
import { useInvoices } from "./queries";

const PAGE_SIZE = 25;

/** Spec §6 Invoices (parent, student): the invoices they pay or that are
 * for them or their children, as the server scopes `billing/invoices/`;
 * each opens read-only with Print. */
export function FamilyInvoices() {
	const { t, i18n } = useTranslation();
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useInvoices({ page });
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	return (
		<div className="flex flex-col gap-4">
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("billing.list.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={Receipt} title={t("billing.list.empty")} />
					</CardContent>
				</Card>
			) : (
				<ul className="flex flex-col gap-3">
					{rows.map((invoice) => (
						<li key={invoice.id}>
							<Card>
								<CardContent className="flex flex-wrap items-center justify-between gap-3">
									<div className="flex flex-col gap-1">
										<Link
											to="/learning/invoices/$invoiceId"
											params={{ invoiceId: String(invoice.id) }}
											dir="ltr"
											className="font-medium text-primary-text underline-offset-4 hover:underline"
										>
											{invoice.number}
										</Link>
										<span className="text-sm text-muted-foreground">
											{t("billing.family.line", {
												student: invoice.student.full_name,
												date: formatDay(invoice.due_on, i18n.language),
											})}
										</span>
									</div>
									<div className="flex flex-col items-end gap-1">
										<span className="text-sm">
											{t("billing.columns.balance")}:{" "}
											<Money
												minor={invoice.balance_minor}
												currency={invoice.currency}
											/>
										</span>
										<InvoiceStatusChip invoice={invoice} />
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

In `dashboard/src/features/billing/index.ts`, replace:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { InvoiceStatusChip, Money } from "./bits";
export { InvoiceForm } from "./InvoiceForm";
export { InvoicePage } from "./InvoicePage";
export { InvoicePrint } from "./InvoicePrint";
```

with:

```ts
export { billingApi, invoicesCsvUrl } from "./api";
export { BillingSummaryCard } from "./BillingSummaryCard";
export { InvoiceStatusChip, Money } from "./bits";
export { FamilyInvoices } from "./FamilyInvoices";
export { InvoiceForm } from "./InvoiceForm";
export { InvoicePage } from "./InvoicePage";
export { InvoicePrint } from "./InvoicePrint";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
		group: "learning",
		requiresRole: ["student", "parent"],
	},
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
```

with:

```ts
		group: "learning",
		requiresRole: ["student", "parent"],
	},
	// Plan 6: the family's invoices.
	{
		to: "/learning/invoices",
		labelKey: "nav.invoices",
		icon: Receipt,
		group: "learning",
		requiresRole: ["student", "parent"],
	},
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
```

In `dashboard/src/routes/_authed/index.tsx`, replace:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
```

with:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { BillingSummaryCard } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
```

In `dashboard/src/routes/_authed/index.tsx`, replace:

```tsx
	return (
		<PageContainer>
			<PageHeader title={t("auth.greeting", { name: me.full_name })} />
			{me.role === "teacher" ? <TeacherHome /> : null}
			{me.role === "student" || me.role === "parent" ? <FamilyHome /> : null}
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
```

with:

```tsx
	return (
		<PageContainer>
			<PageHeader title={t("auth.greeting", { name: me.full_name })} />
			{me.role === "admin" ? <BillingSummaryCard /> : null}
			{me.role === "teacher" ? <TeacherHome /> : null}
			{me.role === "student" || me.role === "parent" ? <FamilyHome /> : null}
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
```

Create `dashboard/src/routes/_authed/learning.invoices.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { FamilyInvoices } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/learning/invoices/")({
	component: function LearningInvoicesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.invoices"));
		return (
			<>
				<PageHeader title={t("nav.invoices")} />
				<FamilyInvoices />
			</>
		);
	},
});
```


Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "billing": {
    "family": {
      "line": "For {{student}}, due {{date}}"
    },
    "home": {
      "title": "Money",
      "revenue": "Revenue this month",
      "noRevenue": "No payments yet this month.",
      "overdue": "Overdue invoices: {{count}}",
      "overdueLine": "Owed ({{count}}):",
      "seeOverdue": "See overdue invoices",
      "loadError": "Couldn't load this month's figures."
    }
  }
}
```

Arabic:

```json
{
  "billing": {
    "family": {
      "line": "لـ{{student}}، تستحق في {{date}}"
    },
    "home": {
      "title": "المال",
      "revenue": "إيرادات هذا الشهر",
      "noRevenue": "لا دفعات بعد هذا الشهر.",
      "overdue": "الفواتير المتأخرة: {{count}}",
      "overdueLine": "المستحق ({{count}}):",
      "seeOverdue": "اعرض الفواتير المتأخرة",
      "loadError": "تعذّر تحميل أرقام هذا الشهر."
    }
  }
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features src/routes`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): family invoices and the admin money card

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Dashboard: payment status and the Invoices panel on subscriptions

**Files:**
- Create: `dashboard/src/features/billing/SubscriptionInvoices.tsx`
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/features/billing/index.ts`, `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, `dashboard/src/features/scheduling/SubscriptionsList.tsx`, `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx`
- Test: `dashboard/src/features/billing/SubscriptionInvoices.test.tsx` (new), `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, `dashboard/src/features/scheduling/SubscriptionsList.test.tsx`, `dashboard/src/test/scheduling-fixtures.ts`

**Interfaces:**
- Consumes: Task 9's `PaymentStatusChip`, `useInvoices`; Task 7's `payment_status`/`payment_overdue`.
- Produces: `SubscriptionInvoices({subscriptionId: number})` from `@/features/billing` (a list, D11); `SubscriptionDetail({subscriptionId, invoices?: (subscriptionId: number) => ReactNode})`; the subscription route passes `(id) => <SubscriptionInvoices subscriptionId={id} />`; `SubscriptionsList` gains the Payment column.
- Produces (tests): `subscriptionRow()` carries `payment_status: "unpaid", payment_overdue: false`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/billing/SubscriptionInvoices.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { invoiceRow } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { billingApi } from "./api";
import { SubscriptionInvoices } from "./SubscriptionInvoices";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, billingApi: { ...actual.billingApi, list: vi.fn() } };
});

describe("SubscriptionInvoices", () => {
	beforeEach(() => vi.clearAllMocks());

	it("lists the subscription's invoices without a second table", async () => {
		vi.mocked(billingApi.list).mockResolvedValue(
			page([
				invoiceRow({ id: 53, number: "INV-000053", status: "void" }),
				invoiceRow(),
			]),
		);
		renderWithRouter(<SubscriptionInvoices subscriptionId={7} />, {
			extraPaths: ["/billing/invoices/$invoiceId"],
		});
		const link = await screen.findByRole("link", { name: "INV-000051" });
		expect(link).toHaveAttribute("href", "/billing/invoices/51");
		expect(billingApi.list).toHaveBeenCalledWith({
			subscription: 7,
			page_size: 100,
		});
		const voided = screen
			.getByRole("link", { name: "INV-000053" })
			.closest("li");
		expect(within(voided as HTMLElement).getByText("Void")).toBeInTheDocument();
		expect(screen.getAllByText(/due Jun 8, 2026/)).toHaveLength(2);
		expect(screen.queryByRole("table")).toBeNull();
	});

	it("says when there are none, and when they can't load", async () => {
		vi.mocked(billingApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(
			<SubscriptionInvoices subscriptionId={7} />,
		);
		expect(
			await screen.findByText("No invoices for this subscription."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(billingApi.list).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<SubscriptionInvoices subscriptionId={7} />);
		expect(
			await screen.findByText("Couldn't load invoices."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		vi.mocked(billingApi.list).mockResolvedValue(page([]));
		await i18n.changeLanguage("ar");
		try {
			renderWithRouter(<SubscriptionInvoices subscriptionId={7} />);
			expect(
				await screen.findByText("لا فواتير لهذا الاشتراك."),
			).toBeInTheDocument();
			expect(screen.getByText("الفواتير")).toBeInTheDocument();
		} finally {
			await i18n.changeLanguage("en");
		}
	});
});
```

In `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, replace:

```tsx
				in_grace: true,
			}),
		);
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(await screen.findByText("Monthly")).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledWith(7);
		expect(screen.getByText("Jul 3, 2026")).toBeInTheDocument();
		expect(screen.getByText("Includes 3 paused days")).toBeInTheDocument();
```

with:

```tsx
				in_grace: true,
			}),
		);
		const invoices = vi.fn((id: number) => <p>{`invoices of ${id}`}</p>);
		renderWithRouter(
			<SubscriptionDetail subscriptionId="7" invoices={invoices} />,
		);
		expect(await screen.findByText("Monthly")).toBeInTheDocument();
		// Billing's panel, handed in by the route (Plan 6).
		expect(screen.getByText("invoices of 7")).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledWith(7);
		expect(screen.getByText("Jul 3, 2026")).toBeInTheDocument();
		expect(screen.getByText("Includes 3 paused days")).toBeInTheDocument();
```

In `dashboard/src/features/scheduling/SubscriptionsList.test.tsx`, replace:

```tsx
					sessions_remaining: -2,
					extra_sessions: 2,
					in_grace: true,
				}),
			]),
		);
```

with:

```tsx
					sessions_remaining: -2,
					extra_sessions: 2,
					in_grace: true,
					payment_status: "partial",
					payment_overdue: true,
				}),
			]),
		);
```

In `dashboard/src/features/scheduling/SubscriptionsList.test.tsx`, replace:

```tsx
		expect(
			within(aisha).getByText("In grace until Jul 7, 2026"),
		).toBeInTheDocument();
		expect(within(yusuf).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/7",
```

with:

```tsx
		expect(
			within(aisha).getByText("In grace until Jul 7, 2026"),
		).toBeInTheDocument();
		// Plan 6: each subscription's payment status, from its invoices.
		expect(within(yusuf).getByText("Unpaid")).toBeInTheDocument();
		expect(within(yusuf).queryByText("Overdue")).toBeNull();
		expect(within(aisha).getByText("Partly paid")).toBeInTheDocument();
		expect(within(aisha).getByText("Overdue")).toBeInTheDocument();
		expect(within(yusuf).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/7",
```

In `dashboard/src/test/scheduling-fixtures.ts`, replace:

```ts
		currency: "EGP",
		renewed_from: null,
		renewal: null,
		...overrides,
	};
}
```

with:

```ts
		currency: "EGP",
		renewed_from: null,
		renewal: null,
		payment_status: "unpaid",
		payment_overdue: false,
		...overrides,
	};
}
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/billing/SubscriptionInvoices.test.tsx src/features/scheduling/SubscriptionsList.test.tsx src/features/scheduling/SubscriptionDetail.test.tsx`
Expected: FAIL — `Failed to resolve import "./SubscriptionInvoices"`, `Unable to find an element with the text: Unpaid`, and `Unable to find an element with the text: invoices of 7`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/billing/SubscriptionInvoices.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { InvoiceStatusChip, Money } from "./bits";
import { useInvoices } from "./queries";

/** Spec §6: the subscription page's Invoices panel (admin), newest first. A
 * list, not a table: the page's sessions table stays the only one. */
export function SubscriptionInvoices({
	subscriptionId,
}: {
	subscriptionId: number;
}) {
	const { t, i18n } = useTranslation();
	const { data, isPending, isError } = useInvoices({
		subscription: subscriptionId,
		page_size: 100,
	});
	const rows = data?.results ?? [];
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("nav.invoices")}</CardTitle>
			</CardHeader>
			<CardContent>
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>{t("billing.list.loadError")}</AlertDescription>
					</Alert>
				) : isPending ? (
					<Spinner />
				) : rows.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("billing.subscription.none")}
					</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{rows.map((invoice) => (
							<li
								key={invoice.id}
								className="flex flex-wrap items-center justify-between gap-2 py-3"
							>
								<div className="flex flex-col gap-0.5">
									<Link
										to="/billing/invoices/$invoiceId"
										params={{ invoiceId: String(invoice.id) }}
										dir="ltr"
										className="font-medium text-primary-text underline-offset-4 hover:underline"
									>
										{invoice.number}
									</Link>
									<span className="text-sm text-muted-foreground">
										<Money
											minor={invoice.amount_minor}
											currency={invoice.currency}
										/>{" "}
										·{" "}
										{t("billing.subscription.due", {
											date: formatDay(invoice.due_on, i18n.language),
										})}
									</span>
								</div>
								<InvoiceStatusChip invoice={invoice} />
							</li>
						))}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}
```

In `dashboard/src/features/billing/index.ts`, replace:

```ts
export { InvoicePrint } from "./InvoicePrint";
export { InvoicesList } from "./InvoicesList";
export * from "./queries";
export * from "./schemas";
```

with:

```ts
export { InvoicePrint } from "./InvoicePrint";
export { InvoicesList } from "./InvoicesList";
export * from "./queries";
export { SubscriptionInvoices } from "./SubscriptionInvoices";
export * from "./schemas";
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
import { isAxiosError } from "axios";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { useAcademySettings } from "@/features/academy/queries";
```

with:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { useAcademySettings } from "@/features/academy/queries";
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
	);
}

export function SubscriptionDetail({
	subscriptionId,
}: {
	subscriptionId: string;
}) {
	const { t, i18n } = useTranslation();
	const { data: academy } = useAcademySettings();
```

with:

```tsx
	);
}

/** ``invoices`` renders billing's Invoices panel for the loaded
 * subscription: the route passes it in, so scheduling never imports billing
 * (Plan 6 P6-1). */
export function SubscriptionDetail({
	subscriptionId,
	invoices,
}: {
	subscriptionId: string;
	invoices?: (subscriptionId: number) => ReactNode;
}) {
	const { t, i18n } = useTranslation();
	const { data: academy } = useAcademySettings();
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
			<Summary sub={sub} />
			<SlotsPanel sub={sub} studentTime={timeForStudent} />
			<PausesPanel sub={sub} />
			<SessionsPanel subscriptionId={sub.id} academyZone={academy.timezone} />
		</div>
	);
```

with:

```tsx
			<Summary sub={sub} />
			<SlotsPanel sub={sub} studentTime={timeForStudent} />
			<PausesPanel sub={sub} />
			{invoices?.(sub.id)}
			<SessionsPanel subscriptionId={sub.id} academyZone={academy.timezone} />
		</div>
	);
```

In `dashboard/src/features/scheduling/SubscriptionsList.tsx`, replace:

```tsx
} from "@/ui";
import { subscriptionsCsvUrl } from "./api";
import {
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
```

with:

```tsx
} from "@/ui";
import { subscriptionsCsvUrl } from "./api";
import {
	PaymentStatusChip,
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
```

In `dashboard/src/features/scheduling/SubscriptionsList.tsx`, replace:

```tsx
										"teacher",
										"progress",
										"status",
										"ends",
									] as const
								).map((key) => (
```

with:

```tsx
										"teacher",
										"progress",
										"status",
										"payment",
										"ends",
									] as const
								).map((key) => (
```

In `dashboard/src/features/scheduling/SubscriptionsList.tsx`, replace:

```tsx
									<td className="p-3">
										<SubscriptionStatusChip status={sub.status} />
									</td>
									<td className="p-3">{ends(sub)}</td>
								</tr>
							))}
```

with:

```tsx
									<td className="p-3">
										<SubscriptionStatusChip status={sub.status} />
									</td>
									<td className="p-3">
										{sub.payment_status ? (
											<PaymentStatusChip
												status={sub.payment_status}
												overdue={Boolean(sub.payment_overdue)}
											/>
										) : null}
									</td>
									<td className="p-3">{ends(sub)}</td>
								</tr>
							))}
```

In `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx`, replace:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubscriptionDetail } from "@/features/scheduling";
import { PageHeader } from "@/ui";
```

with:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { SubscriptionInvoices } from "@/features/billing";
import { usePageTitle } from "@/features/branding";
import { SubscriptionDetail } from "@/features/scheduling";
import { PageHeader } from "@/ui";
```

In `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx`, replace:

```tsx
		return (
			<>
				<PageHeader title={t("scheduling.detailTitle")} />
				<SubscriptionDetail subscriptionId={subscriptionId} />
			</>
		);
	},
```

with:

```tsx
		return (
			<>
				<PageHeader title={t("scheduling.detailTitle")} />
				<SubscriptionDetail
					subscriptionId={subscriptionId}
					invoices={(id) => <SubscriptionInvoices subscriptionId={id} />}
				/>
			</>
		);
	},
```


Merge these keys into `dashboard/src/locales/en/common.json` and `dashboard/src/locales/ar/common.json` (a nested object merges into the existing one of the same name; a key that already exists takes the new value). Keep the files' tab indentation.

English:

```json
{
  "scheduling": {
    "columns": {
      "payment": "Payment"
    }
  },
  "billing": {
    "subscription": {
      "none": "No invoices for this subscription.",
      "due": "due {{date}}"
    }
  }
}
```

Arabic:

```json
{
  "scheduling": {
    "columns": {
      "payment": "الدفع"
    }
  },
  "billing": {
    "subscription": {
      "none": "لا فواتير لهذا الاشتراك.",
      "due": "تستحق {{date}}"
    }
  }
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 exec vite build`
(the build regenerates `src/routeTree.gen.ts`).

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features src/routes`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; coverage lines/statements ≥ 80, branches/functions ≥ 70; `check-colors` prints no findings.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): payment status and invoices on subscriptions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: End-to-end through Caddy, STATE.md

**Files:**
- Modify: `STATE.md` (meta), submodule pointers (meta, after merge)
- Test: `dashboard/e2e/billing.spec.ts` (new), `dashboard/e2e/fixtures.ts`, `dashboard/e2e/people-catalogue.spec.ts`, `dashboard/e2e/sessions.spec.ts`
- CI: no change. The `e2e` job already migrates a fresh database, runs `seed_dev`, sends email inline into files that `e2e/mail.ts` reads (`E2E_MAIL_DIR`), starts the marketing server and runs every spec in `e2e/`.

**Interfaces:**
- Consumes: `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN` from `e2e/fixtures.ts`; `latestLink` from `e2e/mail.ts`; the labels and texts of Tasks 9–14.
- Produces: `acceptInvite(browser, email, password, name) -> Page` and `INVITE` in `e2e/fixtures.ts` (moved from `sessions.spec.ts`; `people-catalogue.spec.ts` imports `INVITE` too, so no spec keeps a copy); the spec §8 billing journey in `e2e/billing.spec.ts`. It creates its own parent (invited by email), child and package, and uses the seeded Tajweed course and Ustadh Bilal.

- [ ] **Step 1: Write the e2e spec and share the invite helper**

The slot sits at noon on the academy's clock, away from midnight; the invoice needs no session to have started. The parent sets a password through the emailed invite. Names that are substrings of others use `exact: true` (`Paid` is inside `Unpaid` and `Partly paid`).

Create `dashboard/e2e/billing.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
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

// Spec §8: the admin creates a subscription and its invoice appears; the
// admin records part of the payment, then the rest, and the status goes
// partly paid, then paid; the parent (invited, sets a password) sees the
// paid invoice and opens its print page. Required labels end in `*`, hence
// the regex queries. The slot sits at noon, away from midnight.
test("a subscription is invoiced and paid, and the parent prints the receipt", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const parent = `E2E Guardian ${stamp}`;
	const parentEmail = `e2e-guardian-${stamp}@e2e.test`;
	const student = `E2E Child ${stamp}`;
	const pkg = `E2E Billing ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A parent (invited by email), their child and a package at 600
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/^full name/i).fill(parent);
	await page.getByLabel(/^email/i).fill(parentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	await page.getByLabel("Find a parent").fill(parent);
	await page
		.getByRole("button", { name: `Link ${parent}`, exact: true })
		.click();
	await expect(
		page.getByRole("button", { name: `Unlink ${parent}`, exact: true }),
	).toBeVisible();

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`فوترة ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("1");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Price").fill("600");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	// 1. A subscription, and its invoice appears on it
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	const startsOn = page.getByLabel(/^Starts/);
	await expect(startsOn).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
	const today = await startsOn.inputValue();
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: "Tajweed" });
	await page.getByLabel(/^Teacher/).selectOption({ label: "Ustadh Bilal" });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await expect(page.getByLabel(/^Price/)).toHaveValue(/^600/);
	await page.getByLabel(weekday(today), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("12:00");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);
	const invoiceLink = page.getByRole("link", { name: /^INV-\d{6}$/ });
	await expect(invoiceLink).toHaveCount(1);
	const number = (await invoiceLink.textContent()) ?? "";
	await invoiceLink.click();
	await expect(page).toHaveURL(/\/app\/billing\/invoices\/\d+$/);
	await expect(page.getByText(parent, { exact: true })).toBeVisible();
	await expect(page.getByText("Unpaid", { exact: true })).toBeVisible();

	// 2. Part of it, then the rest (the amount defaults to the balance)
	await page.getByRole("button", { name: "Record payment" }).click();
	const first = page.getByRole("dialog");
	await expect(first.getByLabel(/^Amount/)).toHaveValue("600.00");
	await first.getByLabel(/^Amount/).fill("200");
	await first.getByLabel(/^Method/).selectOption("instapay");
	await first.getByRole("button", { name: "Record payment" }).click();
	await expect(page.getByRole("dialog")).toHaveCount(0);
	await expect(page.getByText("Partly paid", { exact: true })).toBeVisible();

	await page.getByRole("button", { name: "Record payment" }).click();
	const rest = page.getByRole("dialog");
	await expect(rest.getByLabel(/^Amount/)).toHaveValue("400.00");
	await rest.getByRole("button", { name: "Record payment" }).click();
	await expect(page.getByRole("dialog")).toHaveCount(0);
	// Nothing left to pay: no more payments, and the list says paid.
	await expect(page.getByRole("button", { name: "Record payment" })).toHaveCount(
		0,
	);
	await page.goto(`${DEMO_URL}/app/billing/invoices`);
	await page.getByRole("tab", { name: "Paid", exact: true }).click();
	await page.getByRole("searchbox").fill(number);
	const row = page.getByRole("row", { name: new RegExp(number) });
	await expect(row.getByText("Paid", { exact: true })).toBeVisible();

	// 3. The parent accepts the invite, finds the paid invoice and prints it
	const guardian = await acceptInvite(
		browser,
		parentEmail,
		"e2e-Guardian-2026",
		parent,
	);
	await guardian.getByRole("link", { name: "Invoices" }).first().click();
	await expect(guardian).toHaveURL(/\/app\/learning\/invoices$/);
	await guardian.getByRole("link", { name: number, exact: true }).click();
	await expect(guardian).toHaveURL(/\/app\/learning\/invoices\/\d+$/);
	await expect(guardian.getByText("Paid", { exact: true }).first()).toBeVisible();
	await guardian.getByRole("link", { name: "Print" }).click();
	await expect(guardian).toHaveURL(/\/app\/invoices\/\d+\/print$/);
	const receipt = guardian.getByRole("article", { name: "Receipt" });
	await expect(receipt.getByText(number, { exact: true })).toBeVisible();
	await expect(
		receipt.locator("header").getByText("Paid", { exact: true }),
	).toBeVisible();
	await expect(receipt.getByText(student, { exact: true })).toBeVisible();
	// Printed without the app's navigation.
	await expect(
		guardian.getByRole("navigation", { name: "Main navigation" }),
	).toHaveCount(0);
	await guardian.context().close();
});
```

In `dashboard/e2e/fixtures.ts`, replace:

```ts
import { expect, type Page } from "@playwright/test";

// Must match backend/etqan/tenants/management/commands/seed_dev.py
export const DEV_PASSWORD = "e2e-EtqanTest-2026";
```

with:

```ts
import { type Browser, expect, type Page } from "@playwright/test";
import { latestLink } from "./mail";

// Must match backend/etqan/tenants/management/commands/seed_dev.py
export const DEV_PASSWORD = "e2e-EtqanTest-2026";
```

Append to the end of `dashboard/e2e/fixtures.ts`:

```ts
export const INVITE =
	/http:\/\/[^\s"<]+\/app\/reset-password\?uid=[^\s"<&]+&token=[^\s"<]+/;

/** Follow the emailed invite, set a password and sign in, in a new context. */
export async function acceptInvite(
	browser: Browser,
	email: string,
	password: string,
	name: string,
): Promise<Page> {
	const link = await latestLink(email, INVITE);
	const context = await browser.newContext();
	const page = await context.newPage();
	await page.goto(link);
	await page.getByLabel(/^new password/i).fill(password);
	await page.getByRole("button", { name: "Reset password" }).click();
	await expect(page.getByText(/you can now sign in/i)).toBeVisible();
	await page.goto(`${DEMO_URL}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(password);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, new RegExp(name));
	return page;
}
```

In `dashboard/e2e/people-catalogue.spec.ts`, replace:

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { latestLink } from "./mail";

const INVITE =
	/http:\/\/[^\s"<]+\/app\/reset-password\?uid=[^\s"<&]+&token=[^\s"<]+/;

// Spec §8: the admin sets up a teacher linked to a course, a package, a parent and
// a student; the student's invite sets a password and they see only their profile.
// Required fields render a trailing `*` in their label, hence the regex queries.
```

with:

```ts
import { expect, test } from "@playwright/test";
import {
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	INVITE,
	login,
} from "./fixtures";
import { latestLink } from "./mail";

// Spec §8: the admin sets up a teacher linked to a course, a package, a parent and
// a student; the student's invite sets a password and they see only their profile.
// Required fields render a trailing `*` in their label, hence the regex queries.
```

In `dashboard/e2e/sessions.spec.ts`, replace:

```ts
import { type Browser, expect, type Page, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { latestLink } from "./mail";

const INVITE =
	/http:\/\/[^\s"<]+\/app\/reset-password\?uid=[^\s"<&]+&token=[^\s"<]+/;
const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
```

with:

```ts
import { expect, test } from "@playwright/test";
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
```

In `dashboard/e2e/sessions.spec.ts`, replace:

```ts
	return earlier.toISOString().slice(11, 16);
}

/** Follow the emailed invite, set a password and sign in, in a new context. */
async function acceptInvite(
	browser: Browser,
	email: string,
	password: string,
	name: string,
): Promise<Page> {
	const link = await latestLink(email, INVITE);
	const context = await browser.newContext();
	const page = await context.newPage();
	await page.goto(link);
	await page.getByLabel(/^new password/i).fill(password);
	await page.getByRole("button", { name: "Reset password" }).click();
	await expect(page.getByText(/you can now sign in/i)).toBeVisible();
	await page.goto(`${DEMO_URL}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(password);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expectLoggedIn(page, new RegExp(name));
	return page;
}

// Spec §8: the admin sees today's session; the invited teacher marks the
// student present and writes the report; the admin sees the report; the
// student sees one session used. Required labels end in `*`, hence regexes.
```

with:

```ts
	return earlier.toISOString().slice(11, 16);
}

// Spec §8: the admin sees today's session; the invited teacher marks the
// student present and writes the report; the admin sees the report; the
// student sees one session used. Required labels end in `*`, hence regexes.
```

- [ ] **Step 2: Run it against the stack, as the CI `e2e` job does**

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
E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost E2E_MAIL_DIR=/tmp/etqan-mail \
  npx pnpm@10 exec playwright test --workers=1
```

(`etqan_e2e` must be an empty database: `createdb -h localhost -p 55432 -U etqan etqan_e2e`. The marketing server needs a built `marketing/dist`: `pnpm install && pnpm build` in `marketing/` once.) Expected: all 15 specs pass, `billing.spec.ts` and the moved-helper `sessions.spec.ts` and `people-catalogue.spec.ts` included. Afterwards stop the four servers (`docker rm -f edge`, and the Django, preview and marketing processes) and drop `etqan_e2e`.

- [ ] **Step 3: Update `STATE.md`**

Replace the "Where we are", "Next" and "Follow-ups" sections with:

```markdown
## Where we are

Plan 6 (billing: invoices and manual payments, B0 milestone 6) built and in review: branch
`feat/billing` in backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-25-billing-design.md`,
plan `docs/superpowers/plans/2026-09-25-plan-6-billing.md`). New tenant app `etqan.billing`: creating
or renewing a subscription through the API invoices it in the same transaction (switch and due days in
academy settings); admins issue, edit and void invoices, record and delete payments (status follows,
overpaying refused), see revenue this month per currency and overdue invoices, and export CSV;
parents and students see their invoices and print a branded invoice or receipt at `/app/invoices/<id>/print`.
The e2e suite covers the journey through the Caddy edge.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 7 of the roadmap. Invoice status goes through `billing.services` (`status_for`, `add_payment`,
`delete_payment`, `void_invoice`), numbers through `next_number`, the payer through `payer_choices`;
never restate any of them. Scheduling's services never import billing.

## Follow-ups (from Plans 4–6)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher, course and student pickers in list filters and forms cap at 100.
- Restore is allowed on any cancelled session, even inside a pause or on an ended subscription.
- A teacher's attendance controls open within a minute of the start (the list re-reads each minute), not at the exact second.
- `seed_dev` marks and reports past sessions in every academy, not only the demo one.
- A teacher or family in a far timezone sees "Today" and "This week" roll over at the academy's midnight, not their own (PM6).
- A subscription edited after its invoice keeps the invoice's amount; the admin edits or voids it by hand (spec §9).
- Subscriptions created by the seeds or by services (not the API) are not invoiced automatically.
- No payroll locks yet (Plan 7): nothing freezes a marked session.
- No session or unpaid-invoice reminders yet (Plan 8, B5). No gateways, refunds or family accounts (B1, B3).
```

- [ ] **Step 4: Commit (dashboard, then meta) and open PRs**

```bash
git -C dashboard add e2e
git -C dashboard commit -m "test(e2e): a subscription is invoiced and paid; the parent prints the receipt

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C backend push -u origin feat/billing
git -C dashboard push -u origin feat/billing
git add STATE.md
git commit -m "chore: state for Plan 6 — billing

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/billing
```

Open one PR per repo: backend → `main`, dashboard → `main`, meta → `master`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Nothing merges without the user's approval. After the submodule PRs merge, bump the meta pointers (`git add backend dashboard`) to the merge commits, commit `chore: bump backend and dashboard for Plan 6 — billing` with the trailer above, and push.

---
