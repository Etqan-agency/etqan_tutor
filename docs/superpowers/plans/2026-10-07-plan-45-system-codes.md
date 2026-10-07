# Plan 45 — Slice B3f: System codes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B3f (the last B3 slice; B3d and B3e merge first, phase B3-1)
**Requires:** nothing from another phase. The spec records "B2's subscription model" as **no request to B2**: every scheduling service B3f calls is already public (spec §7). No B2-owned file is edited; no hook is needed (checked against the real code, see the self-review).

**Goal:** An academy generates **system codes** in batches; a family (the student, or a parent) redeems one instead of paying: an **activation** code starts a subscription, a **renewal** code renews one, a **discount** code takes a percentage or a fixed amount off an invoice. Each code is redeemed at most once; billing shows what a code paid as a payment with the method "System code", which is never revenue (ledger D43).

**Architecture:**
- **Backend, new app `etqan.vouchers` (TENANT_APPS, B3 marker):** `VoucherBatch` (the shared terms: kind, course, package, teacher, validity, discount) and `Voucher` (one code's own state). Services in `etqan/vouchers/services/` generate batches, void codes, redeem (one `@transaction.atomic` call that locks the code row first, F-14/F-15), remove a discount and preview a code for a family. Vouchers reaches identity, catalogue, scheduling and billing only through their `services` (F-1).
- **Backend, billing (B3 owns it):** `Payment.Method.CODE` and the check `billing_payment_code_on_invoice` (migration `billing.0010`); vouchers-only services `settle_with_code`, `record_code_payment`, `delete_code_payment`; the guard `refuse_reserved_money` (alias `refuse_wallet_money`) and `credit_payment`'s own `code` check; the row flag `movable`; `revenue_between` excludes `code`; `invoices_issued` skips a paid invoice a code paid (F-5..F-8, F-23).
- **Backend, catalogue:** one message in `_delete` (F-25).
- **API:** `/api/v1/vouchers/…` (spec §5): the office's batches, codes, CSV, void, redeem by id or text and remove-discount behind the new resource `voucher` and the feature `system_codes` (built, off by default); the family's `check/` and `redeem/`, throttled per user and per IP.
- **Dashboard:** a new `src/features/vouchers/` (Billing → System codes with Generate, Void, Redeem for a student and Remove discount; Family → Redeem a code; `ApplyCode` and `RemoveDiscount` passed into billing's `InvoicePage` by the routes), billing's "System code" label and `movable`, and the new catalogue `in_use` text.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query, react-hook-form + zod 4, i18next, `Intl`; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-07-b3f-system-codes-design.md` (decisions F-1..F-25, review-revised). Ledger: D16 and D36 (revenue), D19 (`NotImpersonating` on money routes), D23 and D35 (subscription price resolution), D25 (`ValidationError.code`), D34 (dot-form row keys; no row lists here), D37 (`balances_of`; untouched), D38 (billing guards on the locked row), D43 and D44 (recorded from this spec). Format and conventions follow Plan 40 (`2026-10-06-plan-40-student-wallet.md`).

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), and the meta worktree `/home/abdulkhalek/Projects/etqan_tutor-wt/b3` (trunk `master`). `marketing/` is not touched.
- **The orchestrator, not the implementer, creates the branches.** `backend/`, `dashboard/` and meta are on `feat/b3f-system-codes`, which equals the B3e tips (trunk + B2e + B3d + B3e). Before Task 1, check `git -C backend branch --show-current` and `git -C dashboard branch --show-current` both print `feat/b3f-system-codes`; stop and report if not.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`), never the submodule pointers in meta, and never `git commit -a` in meta.
- Commits use Conventional Commits and end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Ownership.** B3 owns `etqan.billing`, `etqan.gateways`, `etqan.wallet`, the new `etqan.vouchers`, `features/billing`, `features/wallet` and the new `features/vouchers`. Catalogue's `_delete` message (F-25) and `features/catalogue/CourseForm.test.tsx`'s copy of it are outside B3's pricing fields: B3f changes them and the ledger notes it (Task 16). Scheduling files are B2's: B3f only **imports** `etqan.scheduling.services` (backend) and `@/features/scheduling` (`useChoices`, `useSubscriptions`; dashboard) and edits none of them.

**Shared lists:** add lines only under the `── phase B3 ──` markers: `TENANT_APPS` (`config/settings/base.py`), `config/api_router.py`, the access `RESOURCES` (`etqan/access/registry.py`), `etqan/platform/features.py`, `pyproject.toml`'s import contracts (and the platform contract's forbidden list), `seed_academy` (`seed_dev.py`), the dashboard `NAV_ITEMS` and `FeatureCode`'s B3 comments. The throttle rates go next to B3g's `payment_link` line (spec §7). Test tables without markers take additive edits only (`access/tests/test_routes.py`, `access/tests/test_registry.py`, `platform/tests/test_features.py`, `features/shell/nav.test.ts`, `routes/permissions.test.ts`, `locales/*/errors.json`); keep both sides on a rebase conflict. Translations: a new area file `locales/{en,ar}/vouchers.json`, plus keys in the existing `billing.json` and `errors.json`.

**Features:** `system_codes` is new, built, `default=False`, `requires=()` (F-22), under the B3 marker. While it is off every vouchers route is a 404 (`FeatureOn`, after the code check) and codes stay as they are. Discount routes, the invoice's Apply code and Remove discount also need `invoices` (404 otherwise; the buttons hide).

**Money:** integer minor units plus an ISO currency, converted in the dashboard only with `toMinor` / `toMajor` / `formatMoney` in the row's own currency. A fixed discount applies only to an invoice in its currency (F-4). Stored instants are UTC; a code's expiry is a date on the academy's calendar (F-11).

**Bad input is a 400, never a 500:** every body field goes through a serializer or a service check (`ValidationError(field=…)`); a JSON string, bool or float where an integer belongs is a 400 on that field; any code text that is not a live code is the one 400 `vouchers.invalid` (plan V5).

**Locks:** `Voucher → Subscription → Session → InvoiceCounter → Invoice → Payment` (F-15). Lock order is proven from the captured `FOR UPDATE` statements (`CaptureQueriesContext`) by the **relative order of each table's first lock**, never an exact list (scheduling locks some rows twice), and never with threads.

**Language:** only en and ar strings (F-24, D11), real Arabic: `locales.test.ts` fails when keys differ.

**Dashboard forms:** dialogs use `defaultValues` + `useFillOnOpen` (from `@/features/finance/shared`), never `values:`; saves go through `saveOrShowErrors`. A currency select always includes its current value (`currencyChoices` from `@/features/finance/ExpenseDialog`). Every vouchers write refreshes on error as well as success (`onSettled`). Billing, wallet and scheduling never import `@/features/vouchers`: the routes pass `ApplyCode` and `RemoveDiscount` into billing's `InvoicePage` (`actions`, `paymentActions`).

**Tests:** every test fails without the code it covers; no vacuous asserts; a test that asserts something is absent first waits for the data that would show it (`await screen.findBy…` of a sibling, or the request's mock having resolved). An academy-isolation test hits real routes. E2E toasts are matched with `{ exact: true }`; an amount or balance check targets the specific new row or fact, never a substring an earlier row also contains.

**Backend commands.** Run from the meta worktree, inside this stream's stack (`just dev-backend`). Load the ports first:
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b3
set -a && . ./.env.stream && set +a
export HOST_UID=$(id -u) HOST_GID=$(id -g)
DJ="docker compose -f docker-compose.local.yml run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan -e DJANGO_EMAIL_SUBJECT_PREFIX= django"
```
- Targeted tests: `$DJ pytest etqan/vouchers -q` (add `--create-db` once after a task adds a migration).
- Migrations: `$DJ python manage.py makemigrations vouchers` / `… billing --name payment_code`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- Whole suite: `just test-backend`. Watch `PLR0913` (keyword-only signatures that mirror an API body carry `# noqa: PLR0913 -- <reason>`).

**Dashboard commands.** From the meta worktree (`.env.stream` and `HOST_UID`/`HOST_GID` loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
```
- One test file: `$DASH pnpm vitest run src/features/vouchers/<file>`.
- Full dashboard tests with coverage: `$DASH pnpm test:coverage`.
- Types: `just test-frontend` (`tsc --noEmit` only). Lint: `just lint-frontend` (`biome ci . && node scripts/check-colors.mjs`): semantic tokens only, no hex, no Tailwind palette utilities.
- A new route file regenerates `src/routeTree.gen.ts` with `$DASH pnpm exec vite build` before `tsc`; it is generated, never hand-edited.
- Format: `$DASH pnpm exec biome check --write src e2e`.

**Gates before queuing:** `just test`, `just lint` (on the trunk's justfile it ends with `secrets`, the gitleaks scan; plan V31), `just e2e e2e/b3-codes.spec.ts` (twice: it must pass on a rerun) plus the full `just e2e`, backend coverage ≥ 80 %, dashboard lines and statements ≥ 80, branches and functions ≥ 70.

## Decisions (gaps the spec left, filled here)

| # | Decision |
|---|---|
| V1 | **Branches:** the orchestrator has already put backend, dashboard and meta on `feat/b3f-system-codes` (the B3e tips); the implementer only checks it (Global Constraints). |
| V2 | **Migrations:** `vouchers.0001_initial` (Task 1) and `billing.0010_payment_code` (Task 2, after B3e's `0009_payment_wallet`; generated with `--name payment_code`). |
| V3 | **The state checks** (refines F-14's "used ⇔ redeemed_at" so F-9's removed discount keeps its history): `used` ⇒ `redeemed_at` set, `student` set, `voided_at` null; `unused` ⇒ `redeemed_at` and `voided_at` null; `void` ⇒ `voided_at` set. A `void` row may keep `redeemed_at`, `student`, `invoice_id` and `payment_id`: that is a removed discount. |
| V4 | **`settle_with_code` returns the `Payment | None`** (spec §4.1 says `Invoice | None`): vouchers stores `payment_id` and reads the invoice through `payment.invoice_id`, so one return carries both. None while `invoices` is off or for a price of 0. |
| V5 | **`vouchers.invalid` body.** The platform handler writes the error code under the key `code`, which is also the field's name, so a 400 on field `code` with code `vouchers.invalid` answers `{"code": "vouchers.invalid"}`; the dashboard's `parseApiError` reads a top-level `code` as the rule code and shows `errors.vouchers.invalid`. The request's `code` is `CharField(required=False, allow_blank=True, default="")` with no `max_length`, so a missing, blank, short, long or unknown text is that same 400 from the service (never a DRF field list under `code`). A void code by id is `vouchers.invalid` too (one rule). |
| V6 | **The per-user throttle is schema-keyed** (`VoucherUserThrottle`, a `SimpleRateThrottle` with scope `voucher_redeem`, keyed `"<schema>:<user pk>"`) instead of `ScopedRateThrottle`, whose key is the user pk alone and would share counters between academies whose user ids collide. `VoucherIPThrottle` (scope `voucher_redeem_ip`) is keyed `"<schema>:<ip>"` like `InquiryIPThrottle`. `check/` and `redeem/` share both counters. |
| V7 | **What another kind would name is left out at generation:** a teacher on a renewal or discount batch, and discount fields on an activation or renewal batch, are dropped (null / `""` / 0), not refused. A note and a void reason are trimmed, up to 200 characters. |
| V8 | **Generation's order of checks:** kind → quantity (1–500) → valid_days (1–3650) → note → course → package → the kind's requirements → teacher → discount. Each is a 400 on its own field. Ids are whole numbers ≥ 1; an unknown or inactive course, package or teacher is a 400 on that field. |
| V9 | **The office's kind check:** the office routes look the code up first without a lock (`kind_of`: 404 for an unknown id, 400 `vouchers.invalid` for bad text), then check the kind's extra codes (F-20, 403 `Redeeming this code also needs …`) and, for a discount, `invoices` (404); `redeem` then re-reads the row under its lock. The family's `redeem/` uses `kind_of` the same way to 404 a discount while `invoices` is off. |
| V10 | **Dashboard visibility beyond F-20** (the server checks only F-20's codes): the office's Redeem for a student also needs `student.view_any` (to find the student) and, for renewal, `subscription.view_any` (to list their subscriptions); `RemoveDiscount` on the invoice page also needs `voucher.view_any` (it finds the voucher with `codes/?code=`). |
| V11 | **Lock order as asserted:** activation `vouchers_voucher < scheduling_subscription < billing_invoice`; renewal `vouchers_voucher < scheduling_subscription < scheduling_session < billing_invoice`; discount `vouchers_voucher < billing_invoice` (the payment is inserted, so no payment row is locked: spec §9's "< payment" holds only for removal); removal `vouchers_voucher < billing_invoice < billing_payment`; `settle_with_code` `scheduling_subscription < billing_invoicecounter < billing_invoice`; `delete_code_payment` `billing_invoice < billing_payment`. |
| V12 | **Error messages:** `vouchers.invalid` "This code isn't valid."; `vouchers.used` "This code has already been used."; `vouchers.expired` "This code has expired."; `vouchers.unavailable` "This code can't be used right now. Contact the academy."; `vouchers.wrong_course` "This code is for another course."; `vouchers.wrong_package` "This code is for another package."; `vouchers.wrong_currency` "This code is in another currency."; `vouchers.invoice_discounted` "This invoice already has a discount code."; `vouchers.not_unused` "Only an unused code can be voided."; `vouchers.not_used` "This code hasn't been used."; `vouchers.not_discount` "Only a discount code can be removed."; `billing.code_payment` "A system code's payment can't be refunded, deleted or moved."; `billing.not_code_payment` "This is not a system code's payment."; `billing.nothing_due` "Nothing is due on this invoice." |
| V13 | **Clocks:** `redeemed_at` and `voided_at` are `django.utils.timezone.now()` (vouchers may not import scheduling's `dates` or billing's `clock`); expiry and "today" are `scheduling.services.today()`, passed into the list query as a value (F-10). `vouchers.services.today` re-exports it for the views. |
| V14 | **Preview shape** (`check/`): `{code, kind, course, package, sessions_total, teacher, discount, expires_on, students, subscriptions}`; `course`/`package` are `{id, name_en, name_ar}` or null, `teacher` `{id, full_name}` (user id) or null, `discount` `{kind, value, currency}` or null, `students` `[{id, name}]` (activation only), `subscriptions` `[{subscription_id, student: {id, name}, course, package, term_ends_on, price_minor, currency}]` (renewal only). Both lists hold only **active** students in scope (F-16). |
| V15 | **A renewal choice's price** is `renewal_price(sub, package)`: the subscription's own `price_minor` when the package's resolved currency for the student equals the subscription's (P4-10), else the resolved package price (D23), exactly what `renew_subscription` will take with no price given. |
| V16 | **Seeds read their targets through catalogue's and identity's services** (`find_course`, `find_package`, `people_queryset`) and write only through `vouchers.services.generate` (spec §8's "vouchers services only" is about writes). |
| V17 | **Payloads:** a batch row `{id, kind, course, package, teacher, sessions_total, discount, valid_days, expires_on, quantity, note, created_by, created_at}`; a code row as spec §5 (codes shown as `SYS-XXXXX-XXXXX`; `teacher.id` is the user id; `student` and `redeemed_by` are `{id, full_name}` with user ids); a redemption `{kind, subscription_id, invoice_id, amount_minor, currency}`. Remove-discount and void answer the code row. |
| V18 | **CSV:** filename `system-codes`; columns Code, Type, Course, Package, Teacher, Discount type, Discount value, Discount currency, Expires on, Status, Redeemed at, Student, Batch note, Void reason (spec §5's list, discount split in three). Office only, like every list CSV; needs `export`. |
| V19 | **Route matrix:** the seven office routes are tabled with `voucher.*` codes and `FEATURES[...] = "system_codes"`, `FEATURE_WORDS["/vouchers/"] = "system_codes"`. The kind's extra codes and remove-discount's `payment.update` are checked in the view **after** the lookup (as B3e's move, plan W14), so the matrix's "with the code: not 403" holds. `check/` and `redeem/` are `SELF_SERVICE` (families only, F-16 in the service), like B3e's family routes. |
| V20 | **A code's family scope at redemption:** the redeemer is the student, or a parent of the student (`identity.services.is_parent_of`); everything else, a paying sibling included, is a 404 on the target (F-16). The office (`office=True`) is not scoped; its codes are the view's. |
| V21 | **Activation's subscription** is created with `starts_on=today`, `slots=()` and no price or currency (D23 resolves both). A renewal passes only `package_id=batch.package_id` and `by=user`. Scheduling's 400 on `course`, `package` or `teacher` (activation) or also `student` (renewal) becomes 409 `vouchers.unavailable`; every other scheduling error passes through unchanged. |
| V22 | **The discount amount** is `max(1, (amount_minor * percent + 50) // 100)` (half up, at least 1 minor unit) or the fixed value, then capped at the locked balance by `record_code_payment(..., up_to_balance=True)`. |
| V23 | **The voucher's display reference** on the payment is `SYS-XXXXX-XXXXX` (15 characters, inside `Payment.reference`'s 120). `RemoveDiscount` finds the voucher by `codes/?code=<reference>`. |
| V24 | **Nav:** office `/billing/codes` ("System codes", icon `Ticket`, `voucher.view_any`, `system_codes`) right after `/billing/local-methods`; family `/learning/codes` ("Redeem a code", icon `TicketCheck`, `requiresRole: ["student", "parent"]`, `system_codes`) right after `/learning/wallet`. Both under the B3 marker. |
| V25 | **`catalogue.in_use`** reads "This {noun} is used by subscriptions or system codes. Deactivate it instead." (server) and "This is used by subscriptions or system codes, so it can't be deleted. Deactivate it instead." (dashboard), Arabic "هذا العنصر مستخدم في اشتراكات أو أكواد نظام، فلا يمكن حذفه. عطّله بدلًا من ذلك.". |
| V26 | **After Generate,** the table's filters reset and the batch filter is set to the new batch, so exactly its codes show (spec §6). |
| V27 | **The toast after applying a discount** is "Discount of {amount} applied." with `formatMoney` in the invoice's currency (`$20.00` in the e2e). |
| V28 | **`state` ordering in the dashboard:** chips `unused` → "Not used yet" (tone `live`), `used` → "Used" (`neutral`), `expired` → "Expired" (`warning`), `void` → "Void" (`neutral`). |
| V29 | **The family page's lone choice:** a single active student (activation) or a single eligible subscription (renewal) is preselected. |
| V30 | **E2E throttle budget:** each run of `b3-codes.spec.ts` makes six `check/`/`redeem/` calls from one IP, well under 60 an hour for the gates' three runs (two of the file, one full suite). |
| V31 | **`just secrets`:** the trunk's `justfile` runs `secrets` (gitleaks `dir` over tracked files) as the last step of `just lint`. If this worktree's meta branch predates it (`just --list` shows no `secrets`), run the trunk's recipe instead: `just --justfile /home/abdulkhalek/Projects/etqan_tutor/justfile --working-directory . secrets`. |

## Review Focus

1. **Two people redeeming one code at once** (a parent's tab and the student's, or two office tabs): the second waits on the row lock and gets 409 `vouchers.used`; no second subscription, invoice or payment. Tests in Task 5 (`test_a_stale_copy_never_redeems_twice`, the lock-order tests) and Task 6 (`test_two_discount_codes_on_one_invoice…`).
2. **Odd code text and bodies:** lower case, spaces, dashes, a `SYS` prefix, 9 or 11 characters, look-alike `O`/`I`, a JSON number or list, an empty body, a 5,000-character string: normalized, or the one 400 `{"code": "vouchers.invalid"}`, never a 500. Tests in Task 4 (`normalize`) and Task 7 (`test_odd_bodies_and_huge_ids_are_never_500s`).
3. **A discount meeting an invoice that changed since the page loaded:** partly paid meanwhile (capped at the balance), paid in full (409 `billing.nothing_due`), voided (409 `billing.invoice_void`), or another code applied first (409 `vouchers.invoice_discounted`, the second payment rolled back). Tests in Task 6.
4. **Catalogue rows a batch names changing:** deactivated (409 `vouchers.unavailable`, the code stays unused), deleted (409 `catalogue.in_use`, never a 500, the scope never widens), the teacher deactivated. Tests in Tasks 4 and 5.
5. **What a family must not do:** redeem for a student outside the family or as a paying sibling (404), list or export codes (403), redeem while impersonated (403), guess at scale (429 per user at 21, per IP at 61). Tests in Tasks 5–7.

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/vouchers/__init__.py`, `apps.py` | the app |
| `etqan/vouchers/models.py`, `migrations/0001_initial.py` (generated) | `VoucherBatch`, `Voucher`, the limits |
| `etqan/vouchers/services/__init__.py` | the public API |
| `etqan/vouchers/services/errors.py` | one constructor per refusal (V12) |
| `etqan/vouchers/services/codes.py` | `normalize`, `display`, `draw`, `fresh_codes`, `create_codes` |
| `etqan/vouchers/services/batches.py` | `generate`, `void`, `clean_text` |
| `etqan/vouchers/services/reads.py` | `today`, `STATES`, `vouchers_queryset`, `filter_vouchers`, `batches_queryset`, `has_batches`, `Preview`, `Renewable`, `preview`, `renewal_price` |
| `etqan/vouchers/services/redeem.py` | `Redemption`, `in_family`, `find`, `kind_of`, `redeem`, `remove_discount`, `discount_amount` |
| `etqan/vouchers/throttling.py` | `VoucherUserThrottle`, `VoucherIPThrottle` |
| `etqan/vouchers/api/{urls,views,serializers,payloads}.py` | the routes of spec §5 |
| `etqan/vouchers/tests/` | `conftest.py`, `test_models.py`, `test_generation.py`, `test_redeem.py`, `test_discount.py`, `test_preview.py`, `test_api.py` |
| `etqan/billing/models.py`, `migrations/0010_payment_code.py` (generated) | `CODE`, the check |
| `etqan/billing/services/payments.py`, `subscriptions.py`, `notices.py`, `summary.py`, `__init__.py` | guards, vouchers-only services, the notice skip, revenue |
| `etqan/billing/api/payloads.py` | `movable`, the flags for `code` |
| `etqan/billing/tests/test_code_payments.py` | billing's side of B3f |
| `etqan/catalogue/services.py` | the `_delete` message (F-25) |
| `etqan/platform/features.py`, `platform/tests/test_features.py` | `system_codes` |
| `etqan/access/registry.py`, `access/tests/test_registry.py`, `access/tests/test_routes.py` | the `voucher` resource, the route matrix |
| `config/settings/base.py`, `config/api_router.py`, `pyproject.toml` | the app, its throttle rates, its routes, its import contracts |
| `etqan/tenants/seeds/vouchers.py`, `management/commands/seed_dev.py`, `tests/test_seed_vouchers.py` | `seed_vouchers` |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/billing/schemas.ts`, `PaymentRecordsPage.tsx` (+ tests: `InvoicePage.test.tsx`, `InvoicePrint.test.tsx`, `PaymentRecordsPage.test.tsx`) | `code`, `movable`, the label and the filter |
| `src/features/wallet/MoveToWallet.tsx` (+ test) | reads `movable` |
| `src/features/vouchers/schemas.ts`, `api.ts`, `queries.ts`, `index.ts` (+ `schemas.test.ts`, `api.test.ts`) | types, form schemas, `vouchersApi`, `useVoucherMutation` |
| `src/features/vouchers/CodesPage.tsx`, `VoidCodeDialog.tsx` (+ tests) | Billing → System codes |
| `src/features/vouchers/GenerateCodesDialog.tsx` (+ test) | Generate codes |
| `src/features/vouchers/OfficeRedeemDialog.tsx`, `RemoveDiscount.tsx` (+ tests) | the office's redemption and removal |
| `src/features/vouchers/RedeemCodePage.tsx` (+ test) | Family → Redeem a code |
| `src/features/vouchers/ApplyCode.tsx` (+ test) | the invoice page's Apply a code |
| `src/routes/_authed/billing.codes.tsx`, `learning.codes.tsx` (new), `billing.invoices.$invoiceId.tsx`, `learning.invoices.$invoiceId.tsx` | wiring |
| `src/features/shell/nav.ts`, `nav.test.ts`, `src/routes/permissions.test.ts`, `src/features/identity/schemas.ts` | nav items, `FEATURE_SCREENS` / `FEATURE_WORDS`, `FeatureCode` |
| `src/features/catalogue/CourseForm.test.tsx` | the new `in_use` text |
| `src/locales/{en,ar}/vouchers.json` (new), `billing.json`, `errors.json` | strings |
| `src/test/billing-fixtures.ts`, `src/test/voucher-fixtures.ts` (new) | fixtures |
| `e2e/b3-codes.spec.ts` | the journey through Caddy |

---

### Task 1: The vouchers app, its tables and the `system_codes` feature

**Files:**
- Create: `backend/etqan/vouchers/__init__.py`, `backend/etqan/vouchers/apps.py`, `backend/etqan/vouchers/models.py`, `backend/etqan/vouchers/migrations/__init__.py`, `backend/etqan/vouchers/migrations/0001_initial.py` (generated), `backend/etqan/vouchers/services/__init__.py`, `backend/etqan/vouchers/tests/__init__.py`, `backend/etqan/vouchers/tests/conftest.py`, `backend/etqan/vouchers/tests/test_models.py`
- Modify: `backend/config/settings/base.py` (B3 marker), `backend/etqan/platform/features.py` (B3 marker), `backend/etqan/platform/tests/test_features.py`, `backend/pyproject.toml` (B3 marker)

**Interfaces:**
- Produces:
  - `etqan.vouchers.models`: `MAX_QUANTITY = 500`, `MAX_VALID_DAYS = 3650`, `MAX_FIXED_MINOR = 100_000_000`, `NOTE_LENGTH = 200`;
  - `VoucherBatch(kind, course → catalogue.Course PROTECT null, package → catalogue.Package PROTECT null, teacher → identity.TeacherProfile PROTECT null, valid_days, expires_on, discount_kind, discount_value, currency, quantity, note, created_by, created_at)` with `VoucherBatch.Kind` (`ACTIVATION`, `RENEWAL`, `DISCOUNT`) and `VoucherBatch.DiscountKind` (`NONE = ""`, `PERCENT`, `FIXED`);
  - `Voucher(batch → VoucherBatch PROTECT related_name="codes", kind, code (10, unique), status, redeemed_at, redeemed_by, student → identity.StudentProfile PROTECT null, subscription_id, invoice_id, payment_id, voided_at, voided_by, void_reason, created_at)` with `Voucher.Status` (`UNUSED`, `USED`, `VOID`);
  - feature `system_codes` built, `default=False`, `requires=()`, group `money`;
  - test fixtures in `etqan/vouchers/tests/conftest.py`: `_clear_cache` (autouse), `clock`, `world`, `admin`, `codes_on`, `parent`, `invoice`; function `as_user(user)`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/platform/tests/test_features.py`, in `BUILT`, under `# ── phase B3 ──`, after `"exchange_rates": False,`:

```python
    "system_codes": False,
```

Create `backend/etqan/vouchers/__init__.py`:

```python
"""System codes (phase B3, slice B3f)."""
```

Create `backend/etqan/vouchers/tests/__init__.py` (empty) and `backend/etqan/vouchers/tests/conftest.py`:

```python
"""Vouchers fixtures. Scheduling's and billing's clocks are pinned to Monday
1 June 2026, 08:00 UTC (billing's `Clock` sets both). The test academy's
timezone is UTC and its default currency USD."""

from datetime import date

import pytest
from django.core.cache import cache
from rest_framework.test import APIClient

from etqan.billing import services as billing_services
from etqan.billing.tests.conftest import Clock
from etqan.billing.tests.conftest import make_parent
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin


@pytest.fixture(autouse=True)
def _clear_cache():
    """Throttle counters live in the process-wide cache (spec §9): no test
    may see another's."""
    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


@pytest.fixture
def world(clock):
    """Scheduling's world: student Yusuf, teacher Bilal (listed on the
    course), course Tajweed and the Monthly package (2 a week, 8 sessions)
    at 150000 EGP."""
    return build_world()


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def codes_on(set_features):
    """B3f ships `system_codes` off (F-22); discounts also need invoices."""
    return set_features(invoices=True, system_codes=True)


@pytest.fixture
def parent(world):
    return make_parent("Zainab", world.student)


@pytest.fixture
def invoice(world, admin):
    """`invoice(amount_minor=20000)`: an unpaid EGP invoice for Yusuf, due
    8 June, with no subscription."""

    def make(**overrides):
        fields = {
            "student_id": world.student.id,
            "amount_minor": 20000,
            "currency": "EGP",
            "due_on": date(2026, 6, 8),
            "description": "Tajweed — June",
            "by": admin,
            **overrides,
        }
        return billing_services.create_invoice(**fields)

    return make


def as_user(user) -> APIClient:
    client = APIClient()
    client.force_login(user)
    return client
```

Create `backend/etqan/vouchers/tests/test_models.py`:

```python
"""B3f §3.1, F-14, F-22, plan V3: the codes' tables refuse what the services
never write; `system_codes` is built, off by default and needs nothing."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.identity import services as identity_services
from etqan.platform import features
from etqan.vouchers.models import Voucher
from etqan.vouchers.models import VoucherBatch

pytestmark = pytest.mark.django_db
EXPIRES = date(2026, 6, 30)


def refused(make):
    with pytest.raises(IntegrityError), transaction.atomic():
        make()


def batch(**fields):
    """A whole-academy 10 % discount batch unless ``fields`` say otherwise."""
    values = {
        "kind": "discount",
        "valid_days": 30,
        "expires_on": EXPIRES,
        "discount_kind": "percent",
        "discount_value": 10,
        "quantity": 1,
        **fields,
    }
    return VoucherBatch.objects.create(**values)


def code(parent, **fields):
    values = {"batch": parent, "kind": parent.kind, "code": "0123456789", **fields}
    return Voucher.objects.create(**values)


def test_system_codes_is_built_off_by_default_and_needs_nothing():
    feature = features.get("system_codes")
    assert (feature.built, feature.default, feature.requires, feature.group) == (
        True,
        False,
        (),
        "money",
    )
    assert (feature.label_en, feature.label_ar) == ("System codes", "أكواد النظام")


@pytest.mark.parametrize(
    "fields",
    [
        {"discount_kind": ""},
        {"discount_value": 0},
        {"discount_value": 101},
        {"currency": "EGP"},
        {"discount_kind": "fixed", "discount_value": 500, "currency": ""},
        {"discount_kind": "fixed", "discount_value": 100_000_001, "currency": "EGP"},
        {"valid_days": 0},
        {"valid_days": 3651},
        {"quantity": 0},
        {"quantity": 501},
    ],
)
def test_a_discount_batch_refuses_bad_terms(fields):
    refused(lambda: batch(**fields))


def test_each_kind_names_what_it_needs(world):
    teacher = identity_services.get_teacher_profile(world.teacher.pk)
    terms = {
        "course": world.course,
        "package": world.package,
        "discount_kind": "",
        "discount_value": 0,
    }
    refused(lambda: batch(kind="activation", **terms))  # no teacher
    batch(kind="activation", teacher=teacher, **terms)
    refused(lambda: batch(kind="renewal", teacher=teacher, **terms))
    refused(
        lambda: batch(
            kind="renewal", course=world.course, discount_kind="", discount_value=0
        )
    )
    refused(lambda: batch(kind="renewal", **{**terms, "discount_kind": "percent"}))
    batch(kind="renewal", **terms)
    refused(lambda: batch(teacher=teacher))  # a discount names no teacher
    batch()  # a whole-academy discount
    batch(
        discount_kind="fixed", discount_value=500, currency="EGP", package=world.package
    )


def test_a_codes_state_matches_its_stamps(world):
    student = identity_services.get_student_profile(world.student.pk)
    parent, now = batch(), timezone.now()
    refused(lambda: code(parent, status="used", student=student))
    refused(lambda: code(parent, status="used", redeemed_at=now))
    refused(lambda: code(parent, redeemed_at=now))
    refused(lambda: code(parent, status="void"))
    refused(lambda: code(parent, voided_at=now))
    refused(
        lambda: code(
            parent, status="used", redeemed_at=now, student=student, voided_at=now
        )
    )
    code(parent, code="AAAAAAAAAA", status="used", redeemed_at=now, student=student)
    code(parent, code="BBBBBBBBBB", status="void", voided_at=now)
    # V3: a removed discount keeps when, by whom and for whom it was used.
    code(
        parent,
        code="CCCCCCCCCC",
        status="void",
        voided_at=now,
        redeemed_at=now,
        student=student,
    )


def test_a_code_its_payment_and_an_invoices_discount_are_each_unique(world):
    student = identity_services.get_student_profile(world.student.pk)
    parent, now = batch(), timezone.now()
    code(parent)
    refused(lambda: code(parent))
    used = {"status": "used", "redeemed_at": now, "student": student, "invoice_id": 7}
    code(parent, code="AAAAAAAAAA", payment_id=5, **used)
    refused(lambda: code(parent, code="BBBBBBBBBB", payment_id=5))
    refused(lambda: code(parent, code="CCCCCCCCCC", payment_id=6, **used))
    # A removed discount (void) may share the invoice with a later one.
    code(
        parent,
        code="DDDDDDDDDD",
        payment_id=6,
        invoice_id=7,
        status="void",
        voided_at=now,
    )
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/vouchers etqan/platform/tests/test_features.py -q`
Expected: FAIL (`ModuleNotFoundError: etqan.vouchers.models`; `system_codes` not in the registry).

- [ ] **Step 3: Implement the app and the models**

Create `backend/etqan/vouchers/apps.py`:

```python
from django.apps import AppConfig


class VouchersConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.vouchers"
    label = "vouchers"
```

Create `backend/etqan/vouchers/migrations/__init__.py` (empty) and `backend/etqan/vouchers/services/__init__.py`:

```python
"""Public API of the vouchers module (B3f). Other apps import only this
package; later phases reach system codes only through it (ledger D44)."""

__all__: list[str] = []
```

Create `backend/etqan/vouchers/models.py`:

```python
"""System codes (phase B3, slice B3f): batches of codes a family redeems
instead of paying (F-2). Other apps' rows are referenced by string or by
plain id: vouchers imports no other app's models (F-1)."""

from django.conf import settings
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q

CURRENCY = RegexValidator(r"^[A-Z]{3}$")
MAX_QUANTITY = 500  # F-20
MAX_VALID_DAYS = 3650  # F-11
MAX_FIXED_MINOR = 100_000_000  # F-4
NOTE_LENGTH = 200  # F-10, F-20


class VoucherBatch(models.Model):
    """The terms its codes share (F-2, F-3). PROTECT (F-25): a deleted
    course, package or teacher can never widen a scoped discount."""

    class Kind(models.TextChoices):
        ACTIVATION = "activation", "Activation"
        RENEWAL = "renewal", "Renewal"
        DISCOUNT = "discount", "Discount"

    class DiscountKind(models.TextChoices):
        NONE = "", "None"
        PERCENT = "percent", "Percentage"
        FIXED = "fixed", "Fixed amount"

    kind = models.CharField(max_length=10, choices=Kind.choices)
    course = models.ForeignKey(
        "catalogue.Course",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    package = models.ForeignKey(
        "catalogue.Package",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    teacher = models.ForeignKey(
        "identity.TeacherProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    valid_days = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(MAX_VALID_DAYS)]
    )
    expires_on = models.DateField()  # the academy's calendar (F-11)
    discount_kind = models.CharField(
        max_length=7, choices=DiscountKind.choices, blank=True, default=""
    )
    # A percent (1–100) or minor units (1–MAX_FIXED_MINOR); 0 off discounts.
    discount_value = models.BigIntegerField(default=0)
    currency = models.CharField(
        max_length=3, blank=True, default="", validators=[CURRENCY]
    )
    quantity = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(MAX_QUANTITY)]
    )
    note = models.CharField(max_length=NOTE_LENGTH, blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(valid_days__gte=1, valid_days__lte=MAX_VALID_DAYS),
                name="vouchers_batch_valid_days_range",
            ),
            models.CheckConstraint(
                condition=Q(quantity__gte=1, quantity__lte=MAX_QUANTITY),
                name="vouchers_batch_quantity_range",
            ),
            # §3.1: a discount kind on discounts only; the others carry none.
            models.CheckConstraint(
                condition=Q(kind="discount", discount_kind__in=["percent", "fixed"])
                | (
                    ~Q(kind="discount")
                    & Q(discount_kind="", discount_value=0, currency="")
                ),
                name="vouchers_batch_discount_follows_kind",
            ),
            models.CheckConstraint(
                condition=~Q(discount_kind="percent")
                | Q(discount_value__gte=1, discount_value__lte=100, currency=""),
                name="vouchers_batch_percent_range",
            ),
            models.CheckConstraint(
                condition=~Q(discount_kind="fixed")
                | (
                    Q(discount_value__gte=1, discount_value__lte=MAX_FIXED_MINOR)
                    & ~Q(currency="")
                ),
                name="vouchers_batch_fixed_range",
            ),
            # F-3: what each kind names, for the row's whole life (PROTECT).
            models.CheckConstraint(
                condition=Q(
                    kind="activation",
                    course__isnull=False,
                    package__isnull=False,
                    teacher__isnull=False,
                )
                | Q(
                    kind="renewal",
                    course__isnull=False,
                    package__isnull=False,
                    teacher__isnull=True,
                )
                | Q(kind="discount", teacher__isnull=True),
                name="vouchers_batch_targets_follow_kind",
            ),
        ]

    def __str__(self):
        return f"VoucherBatch<{self.pk}, {self.kind}, {self.quantity}>"


class Voucher(models.Model):
    """One code: only its own state (F-2). `expired` is derived (F-10)."""

    class Status(models.TextChoices):
        UNUSED = "unused", "Not used yet"
        USED = "used", "Used"
        VOID = "void", "Void"

    batch = models.ForeignKey(
        VoucherBatch, on_delete=models.PROTECT, related_name="codes"
    )
    # Copied from the batch for the partial unique constraint (§3.1).
    kind = models.CharField(max_length=10, choices=VoucherBatch.Kind.choices)
    code = models.CharField(max_length=10, unique=True)  # bare (F-12)
    status = models.CharField(
        max_length=6, choices=Status.choices, default=Status.UNUSED, db_index=True
    )
    redeemed_at = models.DateTimeField(null=True, blank=True)
    redeemed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    student = models.ForeignKey(
        "identity.StudentProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    # Plain ids (F-1): scheduling's subscription, billing's invoice and payment.
    subscription_id = models.BigIntegerField(null=True, blank=True)
    invoice_id = models.BigIntegerField(null=True, blank=True)
    payment_id = models.BigIntegerField(null=True, blank=True)
    voided_at = models.DateTimeField(null=True, blank=True)
    voided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    void_reason = models.CharField(max_length=NOTE_LENGTH, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]
        indexes = [models.Index(fields=["batch", "id"], name="vouchers_code_by_batch")]
        constraints = [
            # Plan V3 (F-14, F-9): a removed discount (void) keeps its history.
            models.CheckConstraint(
                condition=Q(
                    status="used",
                    redeemed_at__isnull=False,
                    student__isnull=False,
                    voided_at__isnull=True,
                )
                | Q(status="unused", redeemed_at__isnull=True, voided_at__isnull=True)
                | Q(status="void", voided_at__isnull=False),
                name="vouchers_code_state_matches_stamps",
            ),
            models.UniqueConstraint(
                fields=["payment_id"],
                condition=Q(payment_id__isnull=False),
                name="vouchers_code_one_per_payment",
            ),
            # F-14: a final guard only; the locked check answers first.
            models.UniqueConstraint(
                fields=["invoice_id"],
                condition=Q(kind="discount", status="used"),
                name="vouchers_code_one_discount_per_invoice",
            ),
        ]

    def __str__(self):
        return f"Voucher<{self.code}, {self.status}>"
```

`backend/config/settings/base.py`, `TENANT_APPS`, under `# ── phase B3 ──`, after `"etqan.wallet",`:

```python
    "etqan.vouchers",
```

`backend/etqan/platform/features.py`, under `# ── phase B3 ──`, after the `exchange_rates` `Feature(...)`:

```python
    # B3f (F-22): system codes, also TutorHamster's "activation code" gateway
    # switch. Discounts check `invoices` themselves, so it requires nothing.
    _built("system_codes", "System codes", "أكواد النظام", "money", default=False),
```

`backend/pyproject.toml`:
- In "platform imports no business modules", under `# ── phase B3 ──`, after `"etqan.wallet",`: `"etqan.vouchers",`.
- In "gateways imports no business app", append `"etqan.vouchers"` to `forbidden_modules` (after `"etqan.wallet"`).
- Under `# ── phase B3 ──`, after the last B3 contract ("scheduling never imports wallet"), add:

```toml
[[tool.importlinter.contracts]]
name = "vouchers reaches other apps only through their services"
type = "forbidden"
# B3f F-1, spec 7: identity, academy, catalogue, scheduling and billing through
# their services only (platform is open). The packages are forbidden whole and
# only the services imports are let through, so a later module stays forbidden.
source_modules = ["etqan.vouchers"]
forbidden_modules = [
    "etqan.identity", "etqan.academy", "etqan.catalogue", "etqan.scheduling",
    "etqan.billing", "etqan.gateways", "etqan.wallet", "etqan.finance",
    "etqan.payroll", "etqan.notifications", "etqan.access", "etqan.tenants",
    "etqan.site",
]
allow_indirect_imports = true
ignore_imports = [
    "etqan.vouchers.** -> etqan.identity.services",
    "etqan.vouchers.** -> etqan.academy.services",
    "etqan.vouchers.** -> etqan.catalogue.services",
    "etqan.vouchers.** -> etqan.scheduling.services",
    "etqan.vouchers.** -> etqan.billing.services",
    "etqan.vouchers.tests.** -> etqan.**",
]

[[tool.importlinter.contracts]]
name = "other apps reach vouchers only through its services"
type = "forbidden"
# F-1: no app imports vouchers but the tenants seeds, through its services.
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access", "etqan.finance", "etqan.gateways", "etqan.wallet", "etqan.learning", "etqan.employment", "etqan.library", "etqan.registration"]
forbidden_modules = ["etqan.vouchers.models", "etqan.vouchers.api", "etqan.vouchers.throttling"]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "billing never imports vouchers"
type = "forbidden"
# F-1: vouchers calls billing; billing never reads a code.
source_modules = ["etqan.billing"]
forbidden_modules = ["etqan.vouchers"]

[[tool.importlinter.contracts]]
name = "scheduling never imports vouchers"
type = "forbidden"
source_modules = ["etqan.scheduling"]
forbidden_modules = ["etqan.vouchers"]

[[tool.importlinter.contracts]]
name = "catalogue never imports vouchers"
type = "forbidden"
source_modules = ["etqan.catalogue"]
forbidden_modules = ["etqan.vouchers"]
```

Generate the migration: `$DJ python manage.py makemigrations vouchers` (it writes `vouchers/migrations/0001_initial.py` depending on catalogue's, identity's and the user model's latest migrations; commit it as generated).

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/vouchers etqan/platform -q --create-db`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`
Expected: clean (the five new contracts kept).

```bash
git -C backend add etqan/vouchers config/settings/base.py etqan/platform/features.py etqan/platform/tests/test_features.py pyproject.toml
git -C backend commit -m "feat(vouchers): the vouchers app, its batch and code tables and the system_codes feature (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 2: Billing: the `code` method, its check, revenue, the guards and the row flags

**Files:**
- Modify: `backend/etqan/billing/models.py`, `backend/etqan/billing/services/payments.py`, `backend/etqan/billing/services/summary.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/api/payloads.py`
- Create: `backend/etqan/billing/migrations/0010_payment_code.py` (generated), `backend/etqan/billing/tests/test_code_payments.py`

**Interfaces:**
- Produces:
  - `Payment.Method.CODE = "code"` (label "System code"); the check `billing_payment_code_on_invoice`;
  - `billing.services.payments.CODE`, `NOT_MANUAL = ONLINE_METHODS | {WALLET, CODE}` (so `MANUAL_PAYMENT_METHODS` is unchanged);
  - `billing.services.refuse_reserved_money(payment)` (409 `billing.code_payment` for `code`, then B3e's wallet refusals) and `refuse_wallet_money` as an alias of it;
  - `credit_payment` refuses `code` on the fresh locked row (409 `billing.code_payment`), before its `completed` check;
  - `add_payment` and `create_record` refuse method `code` (400 `method`);
  - payment rows gain `movable`; `deletable` and `refundable` are false for `code`;
  - `revenue_between` excludes `code`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_code_payments.py`:

```python
"""B3f F-5, F-7, F-8 (ledger D43): billing's `code` method, its check,
revenue, the guards decided on the locked row and the payment-row flags.
Task 3 adds the vouchers-only services."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.billing import services
from etqan.billing.api import payloads
from etqan.billing.models import Payment
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError

JUNE = (date(2026, 6, 1), date(2026, 7, 1))
JUNE_1 = date(2026, 6, 1)


def code_payment(invoice, amount=500, **fields):
    """A raw `code` row: the check, not a service, is under test."""
    values = {
        "invoice": invoice,
        "currency": invoice.currency,
        "amount_minor": amount,
        "method": "code",
        "paid_on": JUNE_1,
        "reference": "SYS-ABCDE-FGHJK",
        **fields,
    }
    return Payment.objects.create(**values)


def refused(make):
    with pytest.raises(IntegrityError), transaction.atomic():
        make()


def flags(payment) -> tuple:
    row = payloads.payment_row(
        services.payments_queryset().get(pk=payment.pk), is_admin=True
    )
    return (row["deletable"], row["refundable"], row["movable"])


def test_a_code_is_a_method_but_never_a_manual_one():
    assert Payment.Method.CODE == "code"
    assert services.METHOD_LABELS["code"] == "System code"
    assert "code" not in [value for value, _ in services.MANUAL_PAYMENT_METHODS]


def test_a_code_payment_is_on_an_invoice_with_no_fee(world, admin):
    bill = invoice_for(world, admin, currency="EGP")
    student = identity_services.get_student_profile(world.student.pk)
    refused(
        lambda: Payment.objects.create(
            currency="EGP",
            amount_minor=100,
            method="code",
            paid_on=JUNE_1,
            customer_type="student",
            student=student,
        )
    )
    refused(lambda: code_payment(bill, fee_minor=10))
    assert code_payment(bill).fee_minor == 0


def test_a_code_payment_is_never_revenue(world, admin):
    """F-7: a code is revenue only when its sale is recorded as a payment."""
    bill = invoice_for(world, admin, currency="EGP", amount_minor=5000)
    code_payment(bill, amount=3000)
    pay(bill, admin, 1000)
    assert services.revenue_between(*JUNE) == [{"currency": "EGP", "amount_minor": 1000}]


def test_refund_and_delete_refuse_a_code_payment_on_the_locked_row(world, admin):
    """F-8 (review C1): decided on the row re-read under its lock."""
    bill = invoice_for(world, admin, currency="EGP", amount_minor=5000)
    cash = pay(bill, admin, 1000)
    stale = Payment.objects.select_related("invoice").get(pk=cash.pk)
    Payment.objects.filter(pk=cash.pk).update(method="code")  # after `stale`
    for action in (
        lambda: services.delete_payment(stale),
        lambda: services.refund_payment(stale, by=admin),
    ):
        with pytest.raises(ConflictError) as caught:
            action()
        assert caught.value.code == "billing.code_payment"
    assert Payment.objects.get(pk=cash.pk).status == "completed"


def test_moving_to_the_balance_refuses_only_a_code_payment(world, admin):
    bill = invoice_for(world, admin, currency="EGP", amount_minor=5000)
    coded = code_payment(bill)
    with pytest.raises(ConflictError) as caught:
        services.credit_payment(coded, by=admin)
    assert caught.value.code == "billing.code_payment"
    assert Payment.objects.get(pk=coded.pk).status == "completed"
    # B3e E-12 still holds: a wallet payment moves back, once.
    spent = services.record_wallet_payment(bill, amount_minor=500, by=admin)
    assert services.credit_payment(spent, by=admin).status == "credited"
    with pytest.raises(ConflictError) as again:
        services.credit_payment(spent, by=admin)
    assert again.value.code == "billing.payment_not_completed"


def test_the_wallet_guard_keeps_its_name():
    """F-8: B3e's imports and tests are untouched by the rename."""
    assert services.refuse_wallet_money is services.refuse_reserved_money


def test_no_one_records_a_code_payment_by_hand(world, admin):
    bill = invoice_for(world, admin, amount_minor=1000)
    with pytest.raises(ValidationError) as on_invoice:
        pay(bill, admin, 100, method="code")
    assert on_invoice.value.field == "method"
    with pytest.raises(ValidationError) as standalone:
        services.create_record(
            customer_type="unregistered",
            customer_name="Abu Khalid",
            amount_minor=100,
            method="code",
            by=admin,
        )
    assert standalone.value.field == "method"
    assert not Payment.objects.filter(method="code").exists()


def test_the_row_flags_hold_a_code_payment(world, admin):
    """F-8: `movable` is completed, on an invoice and not `code`."""
    bill = invoice_for(world, admin, currency="EGP", amount_minor=5000)
    assert flags(code_payment(bill)) == (False, False, False)
    cash = pay(bill, admin, 1000)
    assert flags(cash) == (True, True, True)
    spent = services.record_wallet_payment(bill, amount_minor=500, by=admin)
    assert flags(spent) == (False, False, True)
    services.credit_payment(cash, by=admin)
    assert flags(cash) == (False, False, False)
    record = services.create_record(
        customer_type="unregistered",
        customer_name="Abu Khalid",
        amount_minor=100,
        method="cash",
        by=admin,
    )
    assert flags(record) == (True, True, False)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_code_payments.py -q`
Expected: FAIL (`AttributeError: CODE`; no `refuse_reserved_money`; no `movable`).

- [ ] **Step 3: Implement**

`backend/etqan/billing/models.py`, in `Payment.Method`, after `WALLET = "wallet", "Balance"`:

```python
        # B3f F-5: what a system code paid; never by hand, never revenue.
        CODE = "code", "System code"
```

and in `Payment.Meta.constraints`, after `billing_payment_topup_standalone`:

```python
            # B3f F-5: a code pays an invoice, with no fee.
            models.CheckConstraint(
                condition=~Q(method="code")
                | (Q(invoice__isnull=False) & Q(fee_minor=0)),
                name="billing_payment_code_on_invoice",
            ),
```

Generate: `$DJ python manage.py makemigrations billing --name payment_code` (it writes `billing/migrations/0010_payment_code.py`: the method choices and the check; commit it as generated).

`backend/etqan/billing/services/payments.py`: replace

```python
CREDITED = Payment.Status.CREDITED
NOT_MANUAL = ONLINE_METHODS | {WALLET}
```

with

```python
CREDITED = Payment.Status.CREDITED
# B3f F-5: what a system code paid, recorded only by etqan.vouchers.
CODE = Payment.Method.CODE
NOT_MANUAL = ONLINE_METHODS | {WALLET, CODE}
```

In `add_payment`, after the `WALLET` refusal:

```python
    if method == CODE:
        raise ValidationError(
            "A system code's payment is made by redeeming the code.", field="method"
        )
```

Replace `refuse_wallet_money` (the whole function) with:

```python
def refuse_reserved_money(payment: Payment) -> None:
    """B3e E-9, B3f F-8 (ledger D43): only etqan.wallet undoes wallet money
    and nothing undoes a code's but etqan.vouchers. ``payment`` is the fresh
    row read under its lock, never the caller's copy (review C1). The
    refusals stand while `balances` or `system_codes` is off."""
    if payment.method == CODE:
        raise ConflictError(
            "A system code's payment can't be refunded, deleted or moved.",
            code="billing.code_payment",
        )
    if payment.method == WALLET:
        raise ConflictError(
            "A payment from the balance is moved back to the balance, "
            "not refunded or deleted.",
            code="billing.wallet_payment",
        )
    if payment.wallet_topup:
        raise ConflictError(
            "A balance top-up is reversed from the balance, not refunded or deleted.",
            code="billing.wallet_topup",
        )
    if payment.status == CREDITED:
        raise ConflictError(
            "This payment was moved to the balance.", code="billing.payment_credited"
        )


# B3f F-8: B3e's name, kept so its imports and tests are untouched.
refuse_wallet_money = refuse_reserved_money
```

In `credit_payment`, between `fresh = _locked_payment(payment)` and the `completed` check:

```python
    # B3f F-8: its own check, not `refuse_reserved_money`, whose wallet
    # refusals would stop B3e E-12's undo of a spend.
    if fresh.method == CODE:
        raise ConflictError(
            "A system code's payment can't be refunded, deleted or moved.",
            code="billing.code_payment",
        )
```

In `refund_payment` and `delete_payment`, replace `refuse_wallet_money(fresh)` with `refuse_reserved_money(fresh)`.

`backend/etqan/billing/services/summary.py`, in `revenue_between`: replace `.exclude(method=Payment.Method.WALLET)` with

```python
        # B3e E-7 and B3f F-7: neither a wallet spend nor a code is money
        # received now.
        .exclude(method__in=(Payment.Method.WALLET, Payment.Method.CODE))
```

and add to its docstring, after "…since its money counted when it was topped up.": " B3f F-7 (ledger D43): nor does a `code` payment; a code is revenue only when its sale is recorded as a payment record."

`backend/etqan/billing/services/__init__.py`: add `from etqan.billing.services.payments import refuse_reserved_money` (after `refund_topup_payment`) and `"refuse_reserved_money",` to `__all__` (after `"refuse_if_invoiced",`, keeping `"refuse_wallet_money"`).

`backend/etqan/billing/api/payloads.py`: import `CODE` beside `CREDITED` (`from etqan.billing.services.payments import CODE`), and in `payment_row`:

```python
    from_code = payment.method == CODE
```

after `credited = …`; replace the `deletable` and `refundable` entries with

```python
        "deletable": not (online or from_wallet or top_up or credited or from_code),
        "refundable": payment.status == "completed"
        and not from_wallet
        and not top_up
        and not from_code,
        # B3f F-8: B3e's MoveToWallet reads it instead of the status.
        "movable": payment.status == "completed"
        and payment.invoice_id is not None
        and not from_code,
```

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/billing etqan/wallet etqan/finance -q --create-db`
Expected: PASS (B3e's `test_moving_a_wallet_payment_undoes_the_spend`, `test_the_row_flags_follow_e10` and `test_the_manual_payment_methods_are_the_payment_choices` unchanged).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing
git -C backend commit -m "feat(billing): the system code method, never revenue, refused by every manual path (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Billing: the vouchers-only services and the new-invoice notice skip

**Files:**
- Modify: `backend/etqan/billing/services/payments.py`, `backend/etqan/billing/services/subscriptions.py`, `backend/etqan/billing/services/notices.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/tests/test_code_payments.py`

**Interfaces:**
- Consumes: Task 2's `CODE`.
- Produces (all `etqan.vouchers`-only, ledger D43):
  - `billing.services.record_code_payment(invoice, *, amount_minor: int, reference: str, by, up_to_balance: bool = False) -> Payment`: locks the invoice, refuses a void one (409 `billing.invoice_void`); with `up_to_balance` the amount becomes `min(amount, balance)` and a balance of 0 is 409 `billing.nothing_due`, without it billing's one balance rule applies (400 `amount_minor`); dated the academy's today, no fee;
  - `billing.services.delete_code_payment(payment_id: int) -> Invoice`: locks the invoice, then the payment re-read; 404 when missing, 409 `billing.not_code_payment` for any other method;
  - `billing.services.settle_with_code(subscription_id: int, *, reference: str, by) -> Payment | None` (plan V4): None while `invoices` is off or for a price of 0; else the subscription's invoice, issued whatever `auto_invoice_on_subscription` says, paid in full by one `code` payment;
  - `invoices_issued` leaves out an invoice that is `paid` and has a `code` payment (F-23).

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/billing/tests/test_code_payments.py` (add the imports to the file's import block):

```python
import re
from datetime import timedelta

from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from etqan.academy import services as academy_services
from etqan.platform.exceptions import NotFoundError


def first_locks(action) -> list[str]:
    """Each table's first `FOR UPDATE`, in order (plan V11)."""
    with CaptureQueriesContext(connection) as ctx:
        action()
    order: list[str] = []
    for query in ctx.captured_queries:
        if "FOR UPDATE" in query["sql"]:
            table = re.search(r'FROM "(\w+)"', query["sql"]).group(1)
            if table not in order:
                order.append(table)
    return order


def in_order(order: list[str], *tables: str) -> None:
    positions = [order.index(table) for table in tables]
    assert positions == sorted(positions), order


def status(invoice) -> str:
    return services.invoices_queryset().get(pk=invoice.pk).status


def test_a_code_payment_is_dated_today_and_capped_when_asked(world, admin):
    bill = invoice_for(world, admin, currency="EGP", amount_minor=1000)
    payment = services.record_code_payment(
        bill, amount_minor=400, reference="SYS-ABCDE-FGHJK", by=admin
    )
    assert (
        payment.method,
        payment.fee_minor,
        payment.paid_on,
        payment.recorded_by,
        payment.reference,
        payment.currency,
    ) == ("code", 0, JUNE_1, admin, "SYS-ABCDE-FGHJK", "EGP")
    assert status(bill) == "partial"
    with pytest.raises(ValidationError) as over:
        services.record_code_payment(bill, amount_minor=601, reference="R", by=admin)
    assert over.value.field == "amount_minor"
    capped = services.record_code_payment(
        bill, amount_minor=5000, reference="R", by=admin, up_to_balance=True
    )
    assert (capped.amount_minor, status(bill)) == (600, "paid")
    with pytest.raises(ConflictError) as nothing:
        services.record_code_payment(
            bill, amount_minor=1, reference="R", by=admin, up_to_balance=True
        )
    assert nothing.value.code == "billing.nothing_due"
    void = invoice_for(world, admin)
    services.void_invoice(void, by=admin)
    with pytest.raises(ConflictError) as voided:
        services.record_code_payment(
            void, amount_minor=1, reference="R", by=admin, up_to_balance=True
        )
    assert voided.value.code == "billing.invoice_void"
    assert Payment.objects.filter(method="code").count() == 2


@pytest.mark.parametrize("amount", [None, True, 1.5, "5", 0])
def test_a_code_payment_takes_whole_minor_units(world, admin, amount):
    bill = invoice_for(world, admin, amount_minor=1000)
    with pytest.raises(ValidationError) as caught:
        services.record_code_payment(bill, amount_minor=amount, reference="R", by=admin)
    assert caught.value.field == "amount_minor"


def test_only_a_code_payment_is_deleted_by_the_vouchers_service(world, admin):
    bill = invoice_for(world, admin, currency="EGP", amount_minor=1000)
    coded = services.record_code_payment(
        bill, amount_minor=1000, reference="R", by=admin
    )
    cash = pay(invoice_for(world, admin, currency="EGP", amount_minor=1000), admin, 500)
    with pytest.raises(ConflictError) as caught:
        services.delete_code_payment(cash.pk)
    assert caught.value.code == "billing.not_code_payment"
    order = first_locks(lambda: services.delete_code_payment(coded.pk))
    in_order(order, "billing_invoice", "billing_payment")
    assert status(bill) == "unpaid"
    assert not Payment.objects.filter(pk=coded.pk).exists()
    with pytest.raises(NotFoundError):
        services.delete_code_payment(coded.pk)
    # F-9: with the code's payment gone the invoice can be voided again.
    assert services.void_invoice(bill, by=admin).status == "void"


def test_settling_with_a_code_issues_a_paid_invoice_whatever_the_setting(
    world, admin, subscribe
):
    academy_services.update_settings(auto_invoice_on_subscription=False)
    sub = subscribe()
    assert services.invoice_subscription(sub.pk, by=admin) is None  # F-6
    payment = services.settle_with_code(
        sub.pk, reference="SYS-ABCDE-FGHJK", by=admin
    )
    invoice = services.invoices_queryset().get(pk=payment.invoice_id)
    assert (
        invoice.status,
        invoice.amount_minor,
        invoice.currency,
        invoice.subscription_id,
        invoice.issued_on,
        invoice.due_on,
        invoice.description,
    ) == ("paid", 150000, "EGP", sub.pk, JUNE_1, date(2026, 6, 8), "تجويد — شهري")
    assert (
        payment.method,
        payment.amount_minor,
        payment.recorded_by,
        payment.reference,
    ) == ("code", 150000, admin, "SYS-ABCDE-FGHJK")


def test_settling_locks_the_subscription_then_the_counter_then_the_invoice(
    world, admin, subscribe
):
    sub = subscribe()
    order = first_locks(
        lambda: services.settle_with_code(sub.pk, reference="R", by=admin)
    )
    in_order(
        order, "scheduling_subscription", "billing_invoicecounter", "billing_invoice"
    )


def test_settling_writes_nothing_with_invoices_off_or_a_price_of_0(
    world, admin, subscribe, set_features
):
    free = subscribe(price_minor=0)
    assert services.settle_with_code(free.pk, reference="R", by=admin) is None
    set_features(invoices=False)
    assert services.settle_with_code(subscribe().pk, reference="R", by=admin) is None
    assert not services.has_invoices()


def test_a_code_payment_freezes_its_invoice_and_its_subscription(
    world, admin, subscribe
):
    sub = subscribe()
    payment = services.settle_with_code(sub.pk, reference="R", by=admin)
    with pytest.raises(ConflictError) as void:
        services.void_invoice(payment.invoice, by=admin)
    assert void.value.code == "billing.has_payments"
    with pytest.raises(ConflictError) as edit:
        services.update_invoice(payment.invoice, amount_minor=1)
    assert edit.value.code == "billing.has_payments"
    with pytest.raises(ConflictError) as delete:
        services.refuse_if_invoiced(sub.pk)
    assert delete.value.code == "billing.subscription_invoiced"


def test_new_invoice_notices_skip_an_invoice_a_code_paid(world, admin, subscribe):
    """F-23: a discounted invoice still open is announced; a code-paid one is
    not; a paid one without a code is, as before."""
    since = timezone.now() - timedelta(hours=1)
    coded = services.settle_with_code(subscribe().pk, reference="R", by=admin)
    discounted = invoice_for(world, admin, currency="EGP", amount_minor=1000)
    services.record_code_payment(discounted, amount_minor=100, reference="R", by=admin)
    cash = invoice_for(world, admin, currency="EGP", amount_minor=1000)
    pay(cash, admin, 1000)
    rows = [row.pk for row in services.invoices_issued(since=since)]
    assert rows == [discounted.pk, cash.pk]
    assert coded.invoice_id not in rows
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/billing/tests/test_code_payments.py -q`
Expected: FAIL (`AttributeError: record_code_payment`, `settle_with_code`, `delete_code_payment`; the notice test lists the code-paid invoice).

- [ ] **Step 3: Implement**

`backend/etqan/billing/services/payments.py`, after `refund_topup_payment`:

```python
@transaction.atomic
def record_code_payment(
    invoice: Invoice,
    *,
    amount_minor: int,
    reference: str,
    by,
    up_to_balance: bool = False,
) -> Payment:
    """etqan.vouchers only (B3f F-8, ledger D43). What a system code paid:
    dated the academy's today, no fee, the code's display form as its
    reference. The void and balance rules run here, under the invoice lock;
    ``up_to_balance`` caps the amount at what is still owed (a discount,
    F-4) and refuses an invoice that owes nothing."""
    rules.check_whole_amount(amount_minor)
    locked = rules.lock(invoice)
    rules.refuse_if_void(locked)
    if up_to_balance:
        balance = locked.amount_minor - rules.paid_of(locked)
        if balance <= 0:
            raise ConflictError(
                "Nothing is due on this invoice.", code="billing.nothing_due"
            )
        amount_minor = min(amount_minor, balance)
    else:
        rules.refuse_if_over_balance(locked, amount_minor)
    payment = Payment(
        invoice=locked,
        currency=locked.currency,
        amount_minor=amount_minor,
        method=CODE,
        paid_on=clock.today(),
        reference=reference,
        recorded_by=by,
    )
    rules.save(payment)
    _recalculate(locked)
    return payment


@transaction.atomic
def delete_code_payment(payment_id: int) -> Invoice:
    """etqan.vouchers only (B3f F-9): a removed discount's payment. Billing's
    lock order: the invoice, then the payment re-read; anything but a `code`
    payment is refused on that fresh row."""
    payment = Payment.objects.select_related("invoice").filter(pk=payment_id).first()
    if payment is None:
        raise NotFoundError("Payment", payment_id)
    locked = rules.lock(payment.invoice) if payment.invoice_id else None
    fresh = _locked_payment(payment)
    if fresh.method != CODE or locked is None:
        raise ConflictError(
            "This is not a system code's payment.", code="billing.not_code_payment"
        )
    fresh.delete()
    _recalculate(locked)
    return locked
```

`backend/etqan/billing/services/subscriptions.py`: add `from etqan.billing.models import Payment` (after the `Invoice` import) and `from etqan.billing.services import payments` (after `payers`), then replace `invoice_subscription` with:

```python
def _issue_for(subscription, *, by, issued_on: date) -> Invoice:
    """Spec §4.3's invoice for a locked ``subscription``: its amount and
    currency, the default payer (P6-4), the academy's language (plan D5),
    due after `invoice_due_days`. The student must be active."""
    settings_row = academy_services.get_settings()
    student = invoices.active_student(subscription.student.user_id)
    return invoices.issue(
        student=student,
        payer=payers.resolve_payer(student.user_id, None),
        subscription_id=subscription.pk,
        amount_minor=subscription.price_minor,
        currency=subscription.currency,
        issued_on=issued_on,
        due_on=issued_on + timedelta(days=settings_row.invoice_due_days),
        description=describe(subscription, settings_row.default_language),
        by=by,
    )


@transaction.atomic
def invoice_subscription(
    subscription_id: int, *, by, issued_on: date | None = None
) -> Invoice | None:
    """Spec §4.3: the invoice for a new or renewed subscription, when the
    academy has invoices (Plan 13 §5.3), its switch is on and the price is
    not 0. Issued today unless the seeds backfill an older one. Runs in the
    caller's transaction: a failure here rolls the subscription back too."""
    if not features.enabled("invoices"):
        return None
    if not academy_services.get_settings().auto_invoice_on_subscription:
        return None
    subscription = scheduling_services.lock_subscription(subscription_id)
    if subscription is None or subscription.price_minor == 0:
        return None
    return _issue_for(subscription, by=by, issued_on=issued_on or clock.today())


@transaction.atomic
def settle_with_code(subscription_id: int, *, reference: str, by) -> Payment | None:
    """etqan.vouchers only (B3f F-5, F-6, plan V4). The subscription's
    invoice, issued whatever `auto_invoice_on_subscription` says, paid in
    full by one `code` payment. None while `invoices` is off or for a price
    of 0: the code row is then the only record (no back-fill later). Lock
    order: the subscription, the counter, then the invoice (F-15)."""
    if not features.enabled("invoices"):
        return None
    subscription = scheduling_services.lock_subscription(subscription_id)
    if subscription is None or subscription.price_minor == 0:
        return None
    invoice = _issue_for(subscription, by=by, issued_on=clock.today())
    return payments.record_code_payment(
        invoice, amount_minor=invoice.amount_minor, reference=reference, by=by
    )
```

`backend/etqan/billing/services/notices.py`: add `from django.db.models import Exists` and `from django.db.models import OuterRef`, `from etqan.billing.models import Payment`, and replace `invoices_issued` with:

```python
def invoices_issued(*, since: datetime) -> QuerySet[Invoice]:
    """Invoices created at ``since`` or later that are not void, oldest
    first. B3f F-23: an invoice that is paid and has a `code` payment is left
    out: an activation or renewal would otherwise announce an invoice that
    was paid as it was issued. A discounted invoice still open stays."""
    code_paid = Payment.objects.filter(
        invoice=OuterRef("pk"), method=Payment.Method.CODE
    )
    return (
        Invoice.objects.filter(created_at__gte=since)
        .exclude(status=rules.VOID)
        .annotate(code_paid=Exists(code_paid))
        .exclude(status=rules.PAID, code_paid=True)
        .select_related(*NOTICE_RELATED)
        .order_by("created_at", "id")
    )
```

`backend/etqan/billing/services/__init__.py`: add the imports `from etqan.billing.services.payments import delete_code_payment`, `from etqan.billing.services.payments import record_code_payment` and `from etqan.billing.services.subscriptions import settle_with_code` (alphabetical within their groups), and `"delete_code_payment"`, `"record_code_payment"`, `"settle_with_code"` to `__all__` (alphabetical).

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/billing etqan/notifications -q`
Expected: PASS (`invoice_subscription`'s own tests and the notifications finders unchanged).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/billing
git -C backend commit -m "feat(billing): settle, record and delete a system code's payment; skip code-paid invoices in notices (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: Vouchers services: code text, generating, voiding, the list; catalogue's refusal

**Files:**
- Create: `backend/etqan/vouchers/services/errors.py`, `backend/etqan/vouchers/services/codes.py`, `backend/etqan/vouchers/services/batches.py`, `backend/etqan/vouchers/services/reads.py`, `backend/etqan/vouchers/tests/test_generation.py`
- Modify: `backend/etqan/vouchers/services/__init__.py`, `backend/etqan/vouchers/tests/conftest.py`, `backend/etqan/catalogue/services.py`

**Interfaces:**
- Consumes: Task 1's models.
- Produces (`etqan.vouchers.services`):
  - `normalize(text) -> str` (F-12: drops spaces and dashes, upper-cases, takes a leading `SYS` off when 13 characters remain; a non-string is `""`), `display(code: str) -> str` (`SYS-XXXXX-XXXXX`), `LENGTH = 10`;
  - `generate(*, kind, quantity, valid_days, by, course_id=None, package_id=None, teacher_user_id=None, discount_kind="", discount_value=0, currency="", note="") -> VoucherBatch` (plan V7, V8);
  - `void(voucher_id: int, *, by, reason: str = "") -> Voucher` (409 `vouchers.not_unused`, 404 unknown);
  - `today() -> date`, `STATES = ("unused", "used", "void", "expired")`, `vouchers_queryset(today) -> QuerySet[Voucher]` annotated with `state`, `filter_vouchers(qs, *, kind="", state="", discount_kind="", batch=None, q="", code="")`, `batches_queryset()`, `has_batches() -> bool`;
  - `etqan.vouchers.services.errors`: `invalid()`, `used()`, `expired()`, `unavailable()`, `wrong_course()`, `wrong_package()`, `wrong_currency()`, `invoice_discounted()`, `not_unused()`, `not_used()`, `not_discount()` (V12);
  - test helpers in `conftest.py`: `activation(world, admin, **overrides)`, `renewal(world, admin, **overrides)`, `discount(world, admin, **overrides)`, `codes_of(batch) -> list[str]` (display forms in id order), `row_of(code) -> Voucher`, `state_of(code) -> str`.
  - catalogue's `catalogue.in_use` message: "This {noun} is used by subscriptions or system codes. Deactivate it instead." (code unchanged).

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/vouchers/tests/conftest.py` (add `from etqan.scheduling import services as scheduling_services` and `from etqan.vouchers import services` to its imports):

```python
def activation(world, admin, **overrides):
    """One activation code for Tajweed, Monthly, Bilal, valid 30 days."""
    fields = {
        "kind": "activation",
        "quantity": 1,
        "valid_days": 30,
        "course_id": world.course.pk,
        "package_id": world.package.pk,
        "teacher_user_id": world.teacher.pk,
        "by": admin,
        **overrides,
    }
    return services.generate(**fields)


def renewal(world, admin, **overrides):
    """One renewal code for Tajweed with the Monthly package."""
    fields = {
        "kind": "renewal",
        "quantity": 1,
        "valid_days": 30,
        "course_id": world.course.pk,
        "package_id": world.package.pk,
        "by": admin,
        **overrides,
    }
    return services.generate(**fields)


def discount(world, admin, **overrides):
    """One whole-academy 10 % discount code."""
    fields = {
        "kind": "discount",
        "quantity": 1,
        "valid_days": 30,
        "discount_kind": "percent",
        "discount_value": 10,
        "by": admin,
        **overrides,
    }
    return services.generate(**fields)


def codes_of(batch) -> list[str]:
    """The batch's codes as the office shows them, in id order."""
    return [services.display(c) for c in batch.codes.order_by("id").values_list("code", flat=True)]


def row_of(code: str):
    from etqan.vouchers.models import Voucher  # noqa: PLC0415

    return Voucher.objects.get(code=services.normalize(code))


def state_of(code: str) -> str:
    """F-10's derived state on the academy's today."""
    return (
        services.vouchers_queryset(scheduling_services.today())
        .get(code=services.normalize(code))
        .state
    )
```

Create `backend/etqan/vouchers/tests/test_generation.py`:

```python
"""B3f F-2..F-4, F-10..F-12, F-20, F-25: generating batches, the codes'
format and how typed text finds them, the derived state, voiding, the list's
filters, and the catalogue's refusal to delete what a batch names."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import IntegrityError
from django.utils import timezone

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import make_teacher
from etqan.vouchers import services
from etqan.vouchers.models import Voucher
from etqan.vouchers.models import VoucherBatch
from etqan.vouchers.services import codes as code_module
from etqan.vouchers.tests.conftest import activation
from etqan.vouchers.tests.conftest import codes_of
from etqan.vouchers.tests.conftest import discount
from etqan.vouchers.tests.conftest import renewal
from etqan.vouchers.tests.conftest import row_of
from etqan.vouchers.tests.conftest import state_of

pytestmark = pytest.mark.django_db
ALPHABET = set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
TOMORROW = datetime(2026, 6, 2, 8, 0, tzinfo=UTC)


def test_a_batch_holds_its_terms_and_draws_distinct_codes(world, admin):
    batch = activation(world, admin, quantity=25, note="  June flyers ")
    assert (
        batch.kind,
        batch.course_id,
        batch.package_id,
        batch.teacher.user_id,
        batch.quantity,
        batch.note,
        batch.created_by,
    ) == ("activation", world.course.pk, world.package.pk, world.teacher.pk, 25, "June flyers", admin)
    assert batch.expires_on == date(2026, 6, 30)  # F-11: 1 June + 30 − 1
    rows = list(batch.codes.all())
    assert len({row.code for row in rows}) == 25
    for row in rows:
        assert len(row.code) == 10
        assert set(row.code) <= ALPHABET
        assert (row.kind, row.status) == ("activation", "unused")


def test_codes_show_as_sys_and_reasonable_typing_finds_them():
    assert services.display("ABCDE12345") == "SYS-ABCDE-12345"
    for typed in (
        "sys-abcde-12345",
        " SYS ABCDE 12345 ",
        "abcde12345",
        "ABCDE-12345",
        "sysabcde12345",
        "SYS-ABCDE-12345",
    ):
        assert services.normalize(typed) == "ABCDE12345", typed
    assert services.normalize("SYSAB12345") == "SYSAB12345"  # a code may start SYS
    assert services.normalize("SYSABCDE1234") == "SYSABCDE1234"  # 9 left: kept
    for junk in (None, 12345, ["ABCDE12345"], {"code": 1}):
        assert services.normalize(junk) == ""


def test_a_drawn_code_already_held_is_drawn_again(world, admin, monkeypatch):
    taken = discount(world, admin).codes.get().code
    letters = iter(taken + "1111111111")
    monkeypatch.setattr(code_module.secrets, "choice", lambda alphabet: next(letters))
    assert discount(world, admin).codes.get().code == "1111111111"


def test_a_code_a_concurrent_batch_took_retries_the_draw_once(
    world, admin, monkeypatch
):
    taken = discount(world, admin).codes.get().code
    draws = iter([[taken], ["2222222222"]])
    monkeypatch.setattr(code_module, "fresh_codes", lambda count: next(draws))
    assert discount(world, admin).codes.get().code == "2222222222"
    assert Voucher.objects.filter(code=taken).count() == 1


def test_a_second_clash_is_not_swallowed(world, admin, monkeypatch):
    taken = discount(world, admin).codes.get().code
    monkeypatch.setattr(code_module, "fresh_codes", lambda count: [taken])
    with pytest.raises(IntegrityError):
        discount(world, admin)
    assert VoucherBatch.objects.count() == 1


@pytest.mark.parametrize(
    ("make", "overrides", "field"),
    [
        (discount, {"kind": "gift"}, "kind"),
        (discount, {"quantity": 0}, "quantity"),
        (discount, {"quantity": 501}, "quantity"),
        (discount, {"quantity": "5"}, "quantity"),
        (discount, {"quantity": True}, "quantity"),
        (discount, {"valid_days": 0}, "valid_days"),
        (discount, {"valid_days": 3651}, "valid_days"),
        (discount, {"note": "x" * 201}, "note"),
        (discount, {"note": 7}, "note"),
        (discount, {"course_id": 999999}, "course"),
        (discount, {"package_id": 999999}, "package"),
        (discount, {"course_id": "1"}, "course"),
        (activation, {"course_id": None}, "course"),
        (activation, {"package_id": None}, "package"),
        (activation, {"teacher_user_id": None}, "teacher"),
        (activation, {"teacher_user_id": 999999}, "teacher"),
        (renewal, {"course_id": None}, "course"),
        (renewal, {"package_id": None}, "package"),
        (discount, {"discount_kind": ""}, "discount_kind"),
        (discount, {"discount_kind": "half"}, "discount_kind"),
        (discount, {"discount_value": 0}, "discount_value"),
        (discount, {"discount_value": 101}, "discount_value"),
        (discount, {"discount_value": True}, "discount_value"),
        (discount, {"currency": "EGP"}, "currency"),
        (discount, {"discount_kind": "fixed", "discount_value": 500}, "currency"),
        (
            discount,
            {"discount_kind": "fixed", "discount_value": 500, "currency": "EG"},
            "currency",
        ),
        (
            discount,
            {"discount_kind": "fixed", "discount_value": 500, "currency": 840},
            "currency",
        ),
        (
            discount,
            {"discount_kind": "fixed", "discount_value": 100_000_001, "currency": "EGP"},
            "discount_value",
        ),
    ],
)
def test_bad_terms_are_a_400_on_their_field_and_write_nothing(
    world, admin, make, overrides, field
):
    with pytest.raises(ValidationError) as caught:
        make(world, admin, **overrides)
    assert caught.value.field == field
    assert not VoucherBatch.objects.exists()
    assert not Voucher.objects.exists()


def test_a_fixed_discount_keeps_its_currency_upper_cased(world, admin):
    batch = discount(
        world, admin, discount_kind="fixed", discount_value=5000, currency="egp"
    )
    assert (batch.discount_kind, batch.discount_value, batch.currency) == (
        "fixed",
        5000,
        "EGP",
    )


def test_an_activation_teacher_teaches_the_course_or_any_when_it_lists_none(
    world, admin
):
    stranger = make_teacher("Hamza")
    with pytest.raises(ValidationError) as outside:
        activation(world, admin, teacher_user_id=stranger.pk)
    assert outside.value.field == "teacher"
    catalogue_services.update_course(world.course, teacher_ids=[])
    assert activation(world, admin, teacher_user_id=stranger.pk).teacher.user_id == (
        stranger.pk
    )
    identity_services.deactivate(stranger, by=admin)
    with pytest.raises(ValidationError) as inactive:
        activation(world, admin, teacher_user_id=stranger.pk)
    assert inactive.value.field == "teacher"


@pytest.mark.parametrize("retire", ["course", "package"])
def test_an_inactive_course_or_package_is_refused(world, admin, retire):
    if retire == "course":
        catalogue_services.update_course(world.course, is_active=False)
    else:
        catalogue_services.update_package(world.package, is_active=False)
    with pytest.raises(ValidationError) as caught:
        renewal(world, admin)
    assert caught.value.field == retire


def test_what_another_kind_would_name_is_left_out(world, admin):
    """Plan V7."""
    batch = renewal(
        world,
        admin,
        teacher_user_id=world.teacher.pk,
        discount_kind="percent",
        discount_value=10,
        currency="EGP",
    )
    assert (batch.teacher_id, batch.discount_kind, batch.discount_value, batch.currency) == (
        None,
        "",
        0,
        "",
    )
    whole = discount(world, admin, teacher_user_id=world.teacher.pk)
    assert (whole.teacher_id, whole.course_id, whole.package_id) == (None, None, None)


def test_a_one_day_code_is_expired_tomorrow(world, admin, clock):
    code = codes_of(discount(world, admin, valid_days=1))[0]
    assert row_of(code).batch.expires_on == date(2026, 6, 1)
    assert state_of(code) == "unused"
    clock.set(TOMORROW)
    assert state_of(code) == "expired"
    assert row_of(code).status == "unused"  # derived, never stored (F-10)


def test_the_list_filters_by_derived_state_kind_discount_batch_and_code(
    world, admin, clock
):
    flyers = activation(world, admin, quantity=2, note="Flyers")
    fixed = discount(
        world,
        admin,
        valid_days=1,
        discount_kind="fixed",
        discount_value=500,
        currency="EGP",
    )
    first, second = codes_of(flyers)
    (gift,) = codes_of(fixed)
    services.void(row_of(first).pk, by=admin, reason="Leaked")
    clock.set(TOMORROW)
    rows = services.vouchers_queryset(scheduling_services.today())

    def found(**filters) -> list[str]:
        return [services.display(v.code) for v in services.filter_vouchers(rows, **filters)]

    assert found(state="void") == [first]
    assert found(state="expired") == [gift]
    assert found(state="unused") == [second]
    assert found(kind="discount") == [gift]
    assert found(discount_kind="fixed") == [gift]
    assert found(batch=flyers.pk) == [second, first]  # newest first
    assert found(code=first.lower()) == [first]
    assert found(code=first[:9]) == []  # `code` is an exact match
    assert found(q="flyers") == [second, first]
    assert found(q=gift[4:9].lower()) == [gift]


def test_void_takes_an_unused_or_expired_code_once_with_its_reason(
    world, admin, clock
):
    one, two, three = codes_of(discount(world, admin, quantity=3, valid_days=1))
    voided = services.void(row_of(one).pk, by=admin, reason="  Posted online ")
    assert (voided.status, voided.void_reason, voided.voided_by) == (
        "void",
        "Posted online",
        admin,
    )
    assert voided.voided_at is not None
    clock.set(TOMORROW)
    assert services.void(row_of(two).pk, by=admin).status == "void"  # expired too
    with pytest.raises(ConflictError) as again:
        services.void(row_of(one).pk, by=admin)
    assert again.value.code == "vouchers.not_unused"
    student = identity_services.get_student_profile(world.student.pk)
    Voucher.objects.filter(pk=row_of(three).pk).update(
        status="used", redeemed_at=timezone.now(), student=student
    )
    with pytest.raises(ConflictError) as used:
        services.void(row_of(three).pk, by=admin)
    assert used.value.code == "vouchers.not_unused"
    with pytest.raises(ValidationError) as long_reason:
        services.void(row_of(three).pk, by=admin, reason="x" * 201)
    assert long_reason.value.field == "reason"
    with pytest.raises(NotFoundError):
        services.void(999999, by=admin)


def test_has_batches_and_the_batch_list(world, admin):
    assert services.has_batches() is False
    older, newer = discount(world, admin), renewal(world, admin)
    assert services.has_batches() is True
    assert list(services.batches_queryset()) == [newer, older]


def test_the_catalogue_refuses_to_delete_what_a_batch_names(api_for, world, admin):
    """F-25: a 409, never a 500; the scope can never widen."""
    renewal(world, admin)
    office = api_for("admin")
    for noun, url in (
        ("package", f"/api/v1/catalogue/packages/{world.package.pk}/"),
        ("course", f"/api/v1/catalogue/courses/{world.course.pk}/"),
    ):
        resp = office.delete(url)
        assert (resp.status_code, resp.json()) == (
            409,
            {
                "detail": f"This {noun} is used by subscriptions or system codes. "
                "Deactivate it instead.",
                "code": "catalogue.in_use",
            },
        ), url
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/vouchers/tests/test_generation.py -q`
Expected: FAIL (`ImportError: cannot import name 'codes' from etqan.vouchers.services`; `AttributeError: generate`).

- [ ] **Step 3: Implement**

Create `backend/etqan/vouchers/services/errors.py`:

```python
"""The vouchers' refusals (B3f §5, plan V12), one constructor each, so every
caller answers with the same code and words."""

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError


def invalid() -> ValidationError:
    """F-13: an unknown code and a void one answer alike (plan V5)."""
    return ValidationError(
        "This code isn't valid.", field="code", code="vouchers.invalid"
    )


def used() -> ConflictError:
    return ConflictError("This code has already been used.", code="vouchers.used")


def expired() -> ConflictError:
    return ConflictError("This code has expired.", code="vouchers.expired")


def unavailable() -> ConflictError:
    return ConflictError(
        "This code can't be used right now. Contact the academy.",
        code="vouchers.unavailable",
    )


def wrong_course() -> ConflictError:
    return ConflictError(
        "This code is for another course.", code="vouchers.wrong_course"
    )


def wrong_package() -> ConflictError:
    return ConflictError(
        "This code is for another package.", code="vouchers.wrong_package"
    )


def wrong_currency() -> ConflictError:
    return ConflictError(
        "This code is in another currency.", code="vouchers.wrong_currency"
    )


def invoice_discounted() -> ConflictError:
    return ConflictError(
        "This invoice already has a discount code.",
        code="vouchers.invoice_discounted",
    )


def not_unused() -> ConflictError:
    return ConflictError(
        "Only an unused code can be voided.", code="vouchers.not_unused"
    )


def not_used() -> ConflictError:
    return ConflictError("This code hasn't been used.", code="vouchers.not_used")


def not_discount() -> ConflictError:
    return ConflictError(
        "Only a discount code can be removed.", code="vouchers.not_discount"
    )
```

Create `backend/etqan/vouchers/services/codes.py`:

```python
"""Code text (B3f F-12): drawing codes, showing them and reading typed text
back. 10 characters of Crockford's base 32 (no I, L, O or U): 50 bits."""

import re
import secrets

from django.db import IntegrityError
from django.db import transaction

from etqan.vouchers.models import Voucher

ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
LENGTH = 10
PREFIX = "SYS"
_SEPARATORS = re.compile(r"[\s-]+")


def normalize(text) -> str:
    """Spaces and dashes dropped, upper-cased, and a leading `SYS` taken off
    when 13 characters remain. Anything but a string reads as no code."""
    if not isinstance(text, str):
        return ""
    bare = _SEPARATORS.sub("", text).upper()
    if len(bare) == len(PREFIX) + LENGTH and bare.startswith(PREFIX):
        return bare[len(PREFIX) :]
    return bare


def display(code: str) -> str:
    """`SYS-XXXXX-XXXXX`, as the office lists, exports and prints it."""
    return f"{PREFIX}-{code[:5]}-{code[5:]}"


def draw() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(LENGTH))


def fresh_codes(count: int) -> list[str]:
    """``count`` distinct codes no row holds yet: each round drops the drawn
    codes already present in one `IN` query and draws again."""
    codes: set[str] = set()
    while len(codes) < count:
        drawn = {draw() for _ in range(count - len(codes))} - codes
        held = set(
            Voucher.objects.filter(code__in=drawn).values_list("code", flat=True)
        )
        codes |= drawn - held
    return sorted(codes)


def create_codes(batch) -> None:
    """The batch's codes. A concurrent batch that drew one of them between
    the check and the insert (about 1e-11) makes the unique constraint fail
    inside a savepoint: the whole draw is retried once."""
    for attempt in range(2):
        rows = [
            Voucher(batch=batch, kind=batch.kind, code=code)
            for code in fresh_codes(batch.quantity)
        ]
        try:
            with transaction.atomic():
                Voucher.objects.bulk_create(rows)
        except IntegrityError:
            if attempt:
                raise
        else:
            return
```

Create `backend/etqan/vouchers/services/batches.py`:

```python
"""Generating batches and voiding codes (B3f F-2..F-4, F-10, F-11, F-20).
Every write is one transaction."""

from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import clean_currency
from etqan.scheduling import services as scheduling_services
from etqan.vouchers.models import MAX_FIXED_MINOR
from etqan.vouchers.models import MAX_QUANTITY
from etqan.vouchers.models import MAX_VALID_DAYS
from etqan.vouchers.models import NOTE_LENGTH
from etqan.vouchers.models import Voucher
from etqan.vouchers.models import VoucherBatch
from etqan.vouchers.services import errors
from etqan.vouchers.services.codes import create_codes

Kind = VoucherBatch.Kind
DiscountKind = VoucherBatch.DiscountKind
MAX_ID = 2**63 - 1


def _whole(value, low: int, high: int, field: str, message: str) -> int:
    """A whole number in ``low..high``; a bool, a string or a float is a 400."""
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValidationError(message, field=field)
    return value


def clean_text(value, field: str, *, required: bool = False) -> str:
    """A batch note or a reason (plan V7): trimmed, up to 200 characters."""
    if value is None:
        value = ""
    if not isinstance(value, str):
        raise ValidationError("Enter text.", field=field)
    text = value.strip()
    if len(text) > NOTE_LENGTH:
        raise ValidationError(f"Use at most {NOTE_LENGTH} characters.", field=field)
    if required and not text:
        raise ValidationError("Say why.", field=field)
    return text


def _course(course_id):
    _whole(course_id, 1, MAX_ID, "course", "Choose an active course.")
    course = catalogue_services.get_course(course_id)
    if course is None or not course.is_active:
        raise ValidationError("Choose an active course.", field="course")
    return course


def _package(package_id):
    _whole(package_id, 1, MAX_ID, "package", "Choose an active package.")
    package = catalogue_services.get_package(package_id)
    if package is None or not package.is_active:
        raise ValidationError("Choose an active package.", field="package")
    return package


def _teacher(user_id, course):
    """§3.1: an active teacher, one of the course's when it lists any (as
    scheduling's own check, `subscriptions.py:68-78`)."""
    _whole(user_id, 1, MAX_ID, "teacher", "Choose an active teacher.")
    profile = identity_services.get_teacher_profile(user_id)
    if profile is None or profile.user.role != "teacher" or not profile.user.is_active:
        raise ValidationError("Choose an active teacher.", field="teacher")
    allowed = catalogue_services.teacher_user_ids_for_course(course.pk)
    if allowed and user_id not in allowed:
        raise ValidationError(
            "This teacher does not teach the course.", field="teacher"
        )
    return profile


def _discount(kind: str, discount_kind, value, currency) -> tuple[str, int, str]:
    """F-4: a percent of 1–100 with no currency, or 1–MAX_FIXED_MINOR minor
    units in a currency. Other kinds carry none (plan V7)."""
    if kind != Kind.DISCOUNT:
        return "", 0, ""
    if discount_kind == DiscountKind.PERCENT:
        _whole(value, 1, 100, "discount_value", "Enter a percentage from 1 to 100.")
        if currency:
            raise ValidationError("A percentage takes no currency.", field="currency")
        return discount_kind, value, ""
    if discount_kind == DiscountKind.FIXED:
        _whole(
            value,
            1,
            MAX_FIXED_MINOR,
            "discount_value",
            f"Enter an amount from 1 to {MAX_FIXED_MINOR} minor units.",
        )
        if not isinstance(currency, str):
            raise ValidationError(
                "Use a three-letter currency code, like EGP.", field="currency"
            )
        return discount_kind, value, clean_currency(currency, field="currency")
    raise ValidationError(
        "Choose a percentage or a fixed amount.", field="discount_kind"
    )


@transaction.atomic
def generate(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    *,
    kind: str,
    quantity: int,
    valid_days: int,
    by,
    course_id: int | None = None,
    package_id: int | None = None,
    teacher_user_id: int | None = None,
    discount_kind: str = "",
    discount_value: int = 0,
    currency: str = "",
    note: str = "",
) -> VoucherBatch:
    """F-2, F-3: a batch and its codes, checked in plan V8's order.
    ``expires_on`` is the academy's today + ``valid_days`` − 1 (F-11)."""
    if kind not in Kind.values:
        raise ValidationError("Choose activation, renewal or discount.", field="kind")
    _whole(quantity, 1, MAX_QUANTITY, "quantity", f"Make 1 to {MAX_QUANTITY} codes at a time.")
    _whole(
        valid_days,
        1,
        MAX_VALID_DAYS,
        "valid_days",
        f"Make the codes valid for 1 to {MAX_VALID_DAYS} days.",
    )
    note = clean_text(note, "note")
    course = _course(course_id) if course_id is not None else None
    package = _package(package_id) if package_id is not None else None
    if kind in (Kind.ACTIVATION, Kind.RENEWAL):
        if course is None:
            raise ValidationError("Choose a course.", field="course")
        if package is None:
            raise ValidationError("Choose a package.", field="package")
    teacher = None
    if kind == Kind.ACTIVATION:
        if teacher_user_id is None:
            raise ValidationError("Choose a teacher.", field="teacher")
        teacher = _teacher(teacher_user_id, course)
    terms = _discount(kind, discount_kind, discount_value, currency)
    batch = VoucherBatch.objects.create(
        kind=kind,
        course=course,
        package=package,
        teacher=teacher,
        valid_days=valid_days,
        expires_on=scheduling_services.today() + timedelta(days=valid_days - 1),
        discount_kind=terms[0],
        discount_value=terms[1],
        currency=terms[2],
        quantity=quantity,
        note=note,
        created_by=by,
    )
    create_codes(batch)
    return batch


@transaction.atomic
def void(voucher_id: int, *, by, reason: str = "") -> Voucher:
    """F-10, F-20: one unused code (expired ones too) withdrawn for good,
    with an optional reason; a used or void code is 409."""
    reason = clean_text(reason, "reason")
    voucher = Voucher.objects.select_for_update().filter(pk=voucher_id).first()
    if voucher is None:
        raise NotFoundError("Code", voucher_id)
    if voucher.status != Voucher.Status.UNUSED:
        raise errors.not_unused()
    voucher.status = Voucher.Status.VOID
    voucher.voided_at = timezone.now()
    voucher.voided_by = by
    voucher.void_reason = reason
    voucher.save(update_fields=["status", "voided_at", "voided_by", "void_reason"])
    return voucher
```

Create `backend/etqan/vouchers/services/reads.py`:

```python
"""What the vouchers read (B3f §4.2). `expired` is derived from the
academy's today, passed in as a value, never `CURRENT_DATE` (F-10)."""

from datetime import date

from django.db.models import Case
from django.db.models import CharField
from django.db.models import F
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Value
from django.db.models import When

from etqan.scheduling import services as scheduling_services
from etqan.vouchers.models import Voucher
from etqan.vouchers.models import VoucherBatch
from etqan.vouchers.services.codes import normalize

STATES = ("unused", "used", "void", "expired")


def today() -> date:
    """The academy's today (plan V13)."""
    return scheduling_services.today()


def vouchers_queryset(on: date) -> QuerySet[Voucher]:
    """Codes with their batch, course, package, teacher, student and
    redeemer joined in one query, and ``state``: `expired` for an unused
    code whose expiry is before ``on``, else the stored status."""
    return Voucher.objects.select_related(
        "batch__course",
        "batch__package",
        "batch__teacher__user",
        "student__user",
        "redeemed_by",
    ).annotate(
        state=Case(
            When(
                status=Voucher.Status.UNUSED,
                batch__expires_on__lt=on,
                then=Value("expired"),
            ),
            default=F("status"),
            output_field=CharField(),
        )
    )


def filter_vouchers(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §5)
    codes: QuerySet[Voucher],
    *,
    kind: str = "",
    state: str = "",
    discount_kind: str = "",
    batch: int | None = None,
    q: str = "",
    code: str = "",
) -> QuerySet[Voucher]:
    """F-20's filters, newest first. ``code`` is an exact match on the
    normalized code; ``q`` searches the code, the student and the note."""
    if kind:
        codes = codes.filter(kind=kind)
    if state:
        codes = codes.filter(state=state)
    if discount_kind:
        codes = codes.filter(batch__discount_kind=discount_kind)
    if batch is not None:
        codes = codes.filter(batch_id=batch)
    if code:
        codes = codes.filter(code=normalize(code))
    if text := q.strip():
        codes = codes.filter(
            Q(code__icontains=normalize(text))
            | Q(student__user__full_name__icontains=text)
            | Q(batch__note__icontains=text)
        )
    return codes.order_by("-id")


def batches_queryset() -> QuerySet[VoucherBatch]:
    """Every batch, newest first, with what a batch row names."""
    return VoucherBatch.objects.select_related(
        "course", "package", "teacher__user", "created_by"
    ).order_by("-id")


def has_batches() -> bool:
    """Whether this academy has any batch (the seeds' guard, §8)."""
    return VoucherBatch.objects.exists()
```

Replace `backend/etqan/vouchers/services/__init__.py` with:

```python
"""Public API of the vouchers module (B3f). Other apps import only this
package; later phases reach system codes only through it (ledger D44)."""

from etqan.vouchers.services.batches import generate
from etqan.vouchers.services.batches import void
from etqan.vouchers.services.codes import LENGTH
from etqan.vouchers.services.codes import display
from etqan.vouchers.services.codes import normalize
from etqan.vouchers.services.reads import STATES
from etqan.vouchers.services.reads import batches_queryset
from etqan.vouchers.services.reads import filter_vouchers
from etqan.vouchers.services.reads import has_batches
from etqan.vouchers.services.reads import today
from etqan.vouchers.services.reads import vouchers_queryset

__all__ = [
    "LENGTH",
    "STATES",
    "batches_queryset",
    "display",
    "filter_vouchers",
    "generate",
    "has_batches",
    "normalize",
    "today",
    "void",
    "vouchers_queryset",
]
```

`backend/etqan/catalogue/services.py`, in `_delete`, replace the message line with:

```python
            f"This {noun} is used by subscriptions or system codes. "
            "Deactivate it instead.",
```

and its docstring with `"""Subscriptions, sessions and system-code batches (B3f F-25) PROTECT what they name: deactivate instead."""`.

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/vouchers etqan/catalogue -q`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/vouchers etqan/catalogue/services.py
git -C backend commit -m "feat(vouchers): generate batches of codes, void one, list them by derived state (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: Vouchers services: redeeming activation and renewal codes, exactly once

**Files:**
- Create: `backend/etqan/vouchers/services/redeem.py`, `backend/etqan/vouchers/tests/test_redeem.py`
- Modify: `backend/etqan/vouchers/services/__init__.py`, `backend/etqan/vouchers/tests/conftest.py`

**Interfaces:**
- Consumes: Task 3's `billing.services.settle_with_code`; Task 4's `normalize`, `display`, `errors`; scheduling's public `create_subscription`, `renew_subscription`, `subscriptions_queryset`, `today`.
- Produces (`etqan.vouchers.services`):
  - `Redemption(kind: str, subscription_id: int | None, invoice_id: int | None, amount_minor: int, currency: str)` (frozen dataclass);
  - `in_family(user, student_user_id: int) -> bool` (F-16, plan V20);
  - `find(*, code=None, voucher_id=None, lock=False) -> Voucher` (404 unknown id; 400 `vouchers.invalid` for bad text or a void code);
  - `kind_of(*, code=None, voucher_id=None) -> str` (plan V9);
  - `refuse_spent(voucher, on: date)` (409 `vouchers.used` / `vouchers.expired`);
  - `redeem(*, user, code=None, voucher_id=None, student_user_id=None, subscription_id=None, invoice_id=None, office=False) -> Redemption` (activation and renewal here; Task 6 adds discount);
  - test helpers in `conftest.py`: `first_locks(action) -> list[str]`, `in_order(order, *tables)`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/vouchers/tests/conftest.py` (add `import re`, `from django.db import connection` and `from django.test.utils import CaptureQueriesContext` to its imports):

```python
def first_locks(action) -> list[str]:
    """Each table's first `FOR UPDATE`, in order: scheduling locks some rows
    twice, so tests assert relative order, never an exact list (plan V11)."""
    with CaptureQueriesContext(connection) as ctx:
        action()
    order: list[str] = []
    for query in ctx.captured_queries:
        if "FOR UPDATE" in query["sql"]:
            table = re.search(r'FROM "(\w+)"', query["sql"]).group(1)
            if table not in order:
                order.append(table)
    return order


def in_order(order: list[str], *tables: str) -> None:
    positions = [order.index(table) for table in tables]
    assert positions == sorted(positions), order
```

Create `backend/etqan/vouchers/tests/test_redeem.py`:

```python
"""B3f F-14..F-18, F-7: activation and renewal redemptions, exactly once and
in the lock order, scheduling's refusals mapped, the family's scope, and
revenue counted once."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.academy import services as academy_services
from etqan.billing import services as billing_services
from etqan.billing.tests.conftest import make_parent
from etqan.catalogue import services as catalogue_services
from etqan.finance import clock as finance_clock
from etqan.finance import services as finance_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import START
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import stamp_archived
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots
from etqan.vouchers import services
from etqan.vouchers.tests.conftest import activation
from etqan.vouchers.tests.conftest import codes_of
from etqan.vouchers.tests.conftest import first_locks
from etqan.vouchers.tests.conftest import in_order
from etqan.vouchers.tests.conftest import renewal
from etqan.vouchers.tests.conftest import row_of
from etqan.vouchers.tests.conftest import state_of

pytestmark = pytest.mark.django_db
JUNE = (date(2026, 6, 1), date(2026, 7, 1))


def office_redeem(world, admin, code, **targets):
    targets.setdefault("student_user_id", world.student.pk)
    return services.redeem(code=code, user=admin, office=True, **targets)


def subscriptions() -> int:
    return scheduling_services.subscriptions_queryset().count()


# ── Activation ───────────────────────────────────────────────────────────────


def test_an_activation_starts_a_paid_subscription_today_with_no_slots(
    codes_on, world, admin, parent
):
    (code,) = codes_of(activation(world, admin))
    redeemed = services.redeem(
        code=code.lower().replace("-", " "),
        user=parent,
        student_user_id=world.student.pk,
    )
    sub = scheduling_services.subscriptions_queryset().get(pk=redeemed.subscription_id)
    assert (
        sub.student.user_id,
        sub.course_id,
        sub.package_id,
        sub.teacher.user_id,
        sub.starts_on,
        sub.price_minor,
        sub.currency,
    ) == (world.student.pk, world.course.pk, world.package.pk, world.teacher.pk, date(2026, 6, 1), 150000, "EGP")
    assert not sub.slots.exists()
    invoice = billing_services.invoices_queryset().get(pk=redeemed.invoice_id)
    payments = list(invoice.payments.all())
    assert (invoice.status, invoice.subscription_id) == ("paid", sub.pk)
    assert [(p.method, p.amount_minor, p.reference, p.recorded_by) for p in payments] == [
        ("code", 150000, code, parent)
    ]
    assert redeemed == services.Redemption("activation", sub.pk, invoice.pk, 150000, "EGP")
    row = row_of(code)
    assert (
        row.status,
        row.redeemed_by,
        row.student.user_id,
        row.subscription_id,
        row.invoice_id,
        row.payment_id,
    ) == ("used", parent, world.student.pk, sub.pk, invoice.pk, payments[0].pk)
    assert row.redeemed_at is not None


def test_an_activation_takes_the_students_country_price(set_features, world, admin):
    """F-17, ledger D23."""
    set_features(country_pricing=True)
    identity_services.update_person(world.student, profile={"country": "SA"})
    catalogue_services.set_country_prices(
        world.package, [{"country": "SA", "price_minor": 50000, "currency": "SAR"}]
    )
    redeemed = office_redeem(world, admin, codes_of(activation(world, admin))[0])
    assert (redeemed.amount_minor, redeemed.currency) == (50000, "SAR")
    invoice = billing_services.invoices_queryset().get(pk=redeemed.invoice_id)
    assert (invoice.amount_minor, invoice.currency, invoice.status) == (50000, "SAR", "paid")


def test_the_invoice_is_issued_with_the_auto_invoice_setting_off(world, admin):
    """F-6."""
    academy_services.update_settings(auto_invoice_on_subscription=False)
    redeemed = office_redeem(world, admin, codes_of(activation(world, admin))[0])
    assert billing_services.invoices_queryset().get(pk=redeemed.invoice_id).status == "paid"


def test_with_invoices_off_the_code_row_is_the_only_record(set_features, world, admin):
    set_features(invoices=False)
    (code,) = codes_of(activation(world, admin))
    redeemed = office_redeem(world, admin, code)
    assert (redeemed.invoice_id, redeemed.amount_minor, redeemed.currency) == (None, 150000, "EGP")
    assert not billing_services.has_invoices()
    assert state_of(code) == "used"
    assert row_of(code).subscription_id == redeemed.subscription_id


def test_a_free_package_writes_no_invoice(world, admin):
    free = catalogue_services.create_package(
        name_ar="مجاني",
        name_en="Free",
        sessions_per_week=1,
        session_minutes=30,
        duration_value=1,
        duration_unit="month",
        price_minor=0,
        currency="EGP",
    )
    redeemed = office_redeem(world, admin, codes_of(activation(world, admin, package_id=free.pk))[0])
    assert (redeemed.invoice_id, redeemed.amount_minor) == (None, 0)
    assert not billing_services.has_invoices()


@pytest.mark.parametrize("retire", ["package", "course", "teacher"])
def test_an_activation_whose_terms_retired_is_unavailable_and_stays_unused(
    world, admin, retire
):
    (code,) = codes_of(activation(world, admin))
    if retire == "package":
        catalogue_services.update_package(world.package, is_active=False)
    elif retire == "course":
        catalogue_services.update_course(world.course, is_active=False)
    else:
        identity_services.deactivate(world.teacher, by=admin)
    with pytest.raises(ConflictError) as caught:
        office_redeem(world, admin, code)
    assert caught.value.code == "vouchers.unavailable"
    assert state_of(code) == "unused"
    assert not scheduling_services.has_subscriptions()


def test_an_inactive_student_the_family_chose_stays_a_400(world, admin):
    (code,) = codes_of(activation(world, admin))
    identity_services.deactivate(world.student, by=admin)
    with pytest.raises(ValidationError) as caught:
        office_redeem(world, admin, code)
    assert caught.value.field == "student"
    assert state_of(code) == "unused"


def test_only_the_student_or_a_parent_redeems_an_activation(world, admin, parent):
    """F-16: anyone else is a 404 on the student; the student acts alone."""
    first, second, third = codes_of(activation(world, admin, quantity=3))
    for stranger in (make_parent("Huda"), make_student("Layla")):
        with pytest.raises(NotFoundError):
            services.redeem(code=first, user=stranger, student_user_id=world.student.pk)
    assert state_of(first) == "unused"
    for target in (None, "11", True):
        with pytest.raises(ValidationError) as missing:
            services.redeem(code=first, user=parent, student_user_id=target)
        assert missing.value.field == "student"
    assert services.redeem(code=second, user=parent, student_user_id=world.student.pk).kind == "activation"
    assert services.redeem(code=third, user=world.student, student_user_id=world.student.pk).kind == "activation"


def test_a_code_redeems_through_its_last_day_and_not_after(world, admin, clock):
    """F-11: inclusive on the academy's calendar."""
    today_only = codes_of(activation(world, admin, valid_days=1))[0]
    first, second = codes_of(activation(world, admin, quantity=2, valid_days=30))
    assert office_redeem(world, admin, today_only).kind == "activation"
    clock.set(datetime(2026, 6, 30, 8, 0, tzinfo=UTC))
    assert office_redeem(world, admin, first).kind == "activation"
    clock.set(datetime(2026, 7, 1, 8, 0, tzinfo=UTC))
    with pytest.raises(ConflictError) as caught:
        office_redeem(world, admin, second)
    assert caught.value.code == "vouchers.expired"
    assert state_of(second) == "expired"


def test_unknown_and_void_codes_are_invalid_and_a_used_one_says_so(world, admin):
    first, second = codes_of(activation(world, admin, quantity=2))
    services.void(row_of(second).pk, by=admin)
    for text in ("SYS-00000-00000", second, "", "SYS-ABC", None, 42):
        with pytest.raises(ValidationError) as caught:
            office_redeem(world, admin, text)
        assert (caught.value.field, caught.value.code) == ("code", "vouchers.invalid")
    with pytest.raises(ValidationError) as by_id:
        services.redeem(voucher_id=row_of(second).pk, user=admin, office=True, student_user_id=world.student.pk)
    assert by_id.value.code == "vouchers.invalid"
    with pytest.raises(NotFoundError):
        services.redeem(voucher_id=999999, user=admin, office=True, student_user_id=world.student.pk)
    office_redeem(world, admin, first)
    with pytest.raises(ConflictError) as again:
        office_redeem(world, admin, first)
    assert again.value.code == "vouchers.used"
    assert subscriptions() == 1


def test_a_stale_copy_never_redeems_twice(world, admin):
    """F-14: the second redeemer decides on the locked row."""
    (code,) = codes_of(activation(world, admin))
    stale = row_of(code)
    office_redeem(world, admin, code)
    with pytest.raises(ConflictError) as again:
        services.redeem(voucher_id=stale.pk, user=admin, office=True, student_user_id=world.student.pk)
    assert again.value.code == "vouchers.used"
    assert billing_services.invoices_queryset().count() == 1


def test_a_failure_after_the_lock_rolls_everything_back(world, admin, monkeypatch):
    (code,) = codes_of(activation(world, admin))

    def refuse(*args, **kwargs):
        raise ConflictError("Billing said no.", code="billing.test_refusal")

    monkeypatch.setattr(billing_services, "settle_with_code", refuse)
    with pytest.raises(ConflictError) as caught:
        office_redeem(world, admin, code)
    assert caught.value.code == "billing.test_refusal"
    assert state_of(code) == "unused"
    assert not scheduling_services.has_subscriptions()  # created, then rolled back


def test_an_activation_locks_the_code_then_the_subscription_then_the_invoice(
    world, admin
):
    (code,) = codes_of(activation(world, admin))
    order = first_locks(lambda: office_redeem(world, admin, code))
    assert order[0] == "vouchers_voucher"
    in_order(order, "vouchers_voucher", "scheduling_subscription", "billing_invoice")


# ── Renewal ──────────────────────────────────────────────────────────────────


def test_a_renewal_renews_at_the_amount_paid_and_the_code_pays_it(world, admin, parent):
    """F-18: P4-10, the old subscription's price in the same currency."""
    old = subscription_for(world, slots=two_slots(), price_minor=120000)
    starts_on = scheduling_services.renewal_starts_on(old)
    (code,) = codes_of(renewal(world, admin))
    redeemed = services.redeem(code=code, user=parent, subscription_id=old.pk)
    new = scheduling_services.subscriptions_queryset().get(pk=redeemed.subscription_id)
    assert (
        new.renewed_from_id,
        new.package_id,
        new.teacher.user_id,
        new.price_minor,
        new.currency,
        new.starts_on,
    ) == (old.pk, world.package.pk, world.teacher.pk, 120000, "EGP", starts_on)
    invoice = billing_services.invoices_queryset().get(pk=redeemed.invoice_id)
    assert (invoice.status, invoice.amount_minor, invoice.subscription_id) == ("paid", 120000, new.pk)
    assert [p.method for p in invoice.payments.all()] == ["code"]
    assert (redeemed.kind, redeemed.amount_minor) == ("renewal", 120000)
    assert row_of(code).student.user_id == world.student.pk


def test_a_renewal_needs_a_subscription_of_its_course_in_the_family(
    world, admin, parent
):
    other = catalogue_services.create_course(
        name_ar="عربي", name_en="Arabic", teacher_ids=[world.teacher.pk]
    )
    elsewhere = subscription_for(world, course_id=other.pk)
    mine = subscription_for(world)
    (code,) = codes_of(renewal(world, admin))
    with pytest.raises(ConflictError) as course:
        services.redeem(code=code, user=parent, subscription_id=elsewhere.pk)
    assert course.value.code == "vouchers.wrong_course"
    for stranger in (make_parent("Huda"), make_student("Layla")):
        with pytest.raises(NotFoundError):
            services.redeem(code=code, user=stranger, subscription_id=mine.pk)
    with pytest.raises(NotFoundError):
        services.redeem(code=code, user=parent, subscription_id=999999)
    with pytest.raises(ValidationError) as missing:
        services.redeem(code=code, user=parent)
    assert missing.value.field == "subscription"
    assert state_of(code) == "unused"


@pytest.mark.parametrize("retire", ["package", "teacher", "student"])
def test_a_renewal_whose_terms_retired_is_unavailable_and_rolls_back(
    world, admin, retire
):
    old = subscription_for(world, slots=two_slots())
    (code,) = codes_of(renewal(world, admin))
    before = subscriptions()
    if retire == "package":
        catalogue_services.update_package(world.package, is_active=False)
    elif retire == "teacher":
        identity_services.deactivate(world.teacher, by=admin)
    else:
        identity_services.deactivate(world.student, by=admin)
    with pytest.raises(ConflictError) as caught:
        services.redeem(code=code, user=admin, office=True, subscription_id=old.pk)
    assert caught.value.code == "vouchers.unavailable"
    assert state_of(code) == "unused"
    assert subscriptions() == before
    assert not billing_services.has_invoices()


@pytest.mark.parametrize(
    ("setup", "expected"),
    [
        ("archived", "scheduling.archived"),
        ("renewed", "scheduling.already_renewed"),
        ("cancelled", "scheduling.not_allowed_in_status"),
    ],
)
def test_schedulings_refusals_pass_through_and_the_code_stays_unused(
    set_features, world, admin, setup, expected
):
    old = subscription_for(world)
    if setup == "archived":
        set_features(subscription_archive=True)
        stamp_archived(old)
    elif setup == "renewed":
        scheduling_services.renew_subscription(old)
    else:
        scheduling_services.cancel_subscription(old)
    (code,) = codes_of(renewal(world, admin))
    before = subscriptions()
    with pytest.raises(ConflictError) as caught:
        services.redeem(code=code, user=admin, office=True, subscription_id=old.pk)
    assert caught.value.code == expected
    assert state_of(code) == "unused"
    assert subscriptions() == before
    assert not billing_services.has_invoices()


def test_an_archived_subscription_renews_while_the_archive_is_off(world, admin):
    """B2d D-13: the one archive rule (refuse only while the switch is on)."""
    old = stamp_archived(subscription_for(world))
    (code,) = codes_of(renewal(world, admin))
    redeemed = services.redeem(code=code, user=admin, office=True, subscription_id=old.pk)
    assert redeemed.kind == "renewal"


def test_a_renewal_locks_the_code_then_subscriptions_sessions_and_the_invoice(
    world, admin
):
    old = subscription_for(world, slots=two_slots())
    (code,) = codes_of(renewal(world, admin))
    order = first_locks(
        lambda: services.redeem(code=code, user=admin, office=True, subscription_id=old.pk)
    )
    assert order[0] == "vouchers_voucher"
    in_order(
        order,
        "vouchers_voucher",
        "scheduling_subscription",
        "scheduling_session",
        "billing_invoice",
    )


# ── Revenue (F-7) ────────────────────────────────────────────────────────────


def test_a_sold_code_counts_once_as_revenue(world, admin, monkeypatch):
    """Record a 1,500.00 sale and redeem a 1,500.00 activation: 1,500.00."""
    billing_services.create_record(
        customer_type="student",
        student_id=world.student.pk,
        amount_minor=150000,
        currency="EGP",
        method="cash",
        notes="Sold a system code",
        by=admin,
    )
    office_redeem(world, admin, codes_of(activation(world, admin))[0])
    assert billing_services.revenue_between(*JUNE) == [{"currency": "EGP", "amount_minor": 150000}]
    monkeypatch.setattr(finance_clock, "now", lambda: START)
    assert finance_services.summary()["net_profit_this_month"] == [
        {"currency": "EGP", "amount_minor": 150000}
    ]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/vouchers/tests/test_redeem.py -q`
Expected: FAIL (`AttributeError: module 'etqan.vouchers.services' has no attribute 'redeem'`).

- [ ] **Step 3: Implement**

Create `backend/etqan/vouchers/services/redeem.py`:

```python
"""Redeeming a code (B3f F-14, F-16..F-18; Task 6 adds the discount, F-19,
and removing one, F-9). One transaction locks the code row first, checks it
on that row, does the kind's work and marks it used. Nothing locks a code
after a subscription, session, invoice or payment (F-15)."""

from dataclasses import dataclass

from django.db import transaction
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import role_of
from etqan.scheduling import services as scheduling_services
from etqan.vouchers.models import Voucher
from etqan.vouchers.models import VoucherBatch
from etqan.vouchers.services import errors
from etqan.vouchers.services.codes import LENGTH
from etqan.vouchers.services.codes import display
from etqan.vouchers.services.codes import normalize

Kind = VoucherBatch.Kind
# F-17, F-18 (plan V21): scheduling's 400s that mean the code's own terms
# retired; a renewal's student too, as the family chose the subscription.
RETIRED = {
    Kind.ACTIVATION: ("course", "package", "teacher"),
    Kind.RENEWAL: ("course", "package", "teacher", "student"),
}


@dataclass(frozen=True)
class Redemption:
    kind: str
    subscription_id: int | None
    invoice_id: int | None
    amount_minor: int
    currency: str


@dataclass(frozen=True)
class _Outcome:
    redemption: Redemption
    student_profile_id: int
    payment_id: int | None


def in_family(user, student_user_id: int) -> bool:
    """F-16: the student, or a parent of the student. A paying sibling, the
    office and teachers are not (the office is decided by its codes)."""
    role = role_of(user)
    if role == "student":
        return user.pk == student_user_id
    if role == "parent":
        return identity_services.is_parent_of(user.pk, student_user_id)
    return False


def find(*, code=None, voucher_id=None, lock: bool = False) -> Voucher:
    """By id (404 when unknown) or by typed text (exact normalized match).
    Unknown text and a void code answer alike (F-13, plan V5)."""
    rows = Voucher.objects.select_related("batch")
    if lock:
        rows = rows.select_for_update(of=("self",))
    if voucher_id is not None:
        voucher = rows.filter(pk=voucher_id).first()
        if voucher is None:
            raise NotFoundError("Code", voucher_id)
    else:
        bare = normalize(code)
        voucher = rows.filter(code=bare).first() if len(bare) == LENGTH else None
        if voucher is None:
            raise errors.invalid()
    if voucher.status == Voucher.Status.VOID:
        raise errors.invalid()
    return voucher


def kind_of(*, code=None, voucher_id=None) -> str:
    """Plan V9: what a code is, read without a lock, so a view can check the
    kind's own codes and features before redeeming."""
    return find(code=code, voucher_id=voucher_id).kind


def refuse_spent(voucher: Voucher, on) -> None:
    """F-14: used or expired on the academy's ``on`` (F-11, inclusive)."""
    if voucher.status == Voucher.Status.USED:
        raise errors.used()
    if voucher.batch.expires_on < on:
        raise errors.expired()


def _target(value, field: str, message: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError(message, field=field)
    return value


def _settled(voucher: Voucher, subscription, user) -> _Outcome:
    """F-5, F-6: billing issues and pays the subscription's invoice; with
    `invoices` off or a price of 0 the code row is the only record."""
    payment = billing_services.settle_with_code(
        subscription.pk, reference=display(voucher.code), by=user
    )
    redemption = Redemption(
        kind=voucher.kind,
        subscription_id=subscription.pk,
        invoice_id=payment.invoice_id if payment else None,
        amount_minor=payment.amount_minor if payment else subscription.price_minor,
        currency=payment.currency if payment else subscription.currency,
    )
    return _Outcome(redemption, subscription.student_id, payment.pk if payment else None)


def _activate(voucher: Voucher, user, student_user_id, *, office: bool) -> _Outcome:
    """F-17: a subscription to the batch's course, package and teacher from
    the academy's today with no slots (the office adds lesson times)."""
    student_user_id = _target(student_user_id, "student", "Choose a student.")
    if not office and not in_family(user, student_user_id):
        raise NotFoundError("Student", student_user_id)
    batch = voucher.batch
    try:
        subscription = scheduling_services.create_subscription(
            student_id=student_user_id,
            course_id=batch.course_id,
            teacher_id=batch.teacher.user_id,
            package_id=batch.package_id,
            starts_on=scheduling_services.today(),
        )
    except ValidationError as exc:
        if exc.field in RETIRED[Kind.ACTIVATION]:
            raise errors.unavailable() from None
        raise
    return _settled(voucher, subscription, user)


def _renew(voucher: Voucher, user, subscription_id, *, office: bool) -> _Outcome:
    """F-18: the student's subscription of the batch's course, renewed with
    the batch's package at scheduling's price (P4-10, D23)."""
    subscription_id = _target(subscription_id, "subscription", "Choose a subscription.")
    old = scheduling_services.subscriptions_queryset().filter(pk=subscription_id).first()
    if old is None or (not office and not in_family(user, old.student.user_id)):
        raise NotFoundError("Subscription", subscription_id)
    if old.course_id != voucher.batch.course_id:
        raise errors.wrong_course()
    try:
        renewed = scheduling_services.renew_subscription(
            old, package_id=voucher.batch.package_id, by=user
        )
    except ValidationError as exc:
        if exc.field in RETIRED[Kind.RENEWAL]:
            raise errors.unavailable() from None
        raise
    return _settled(voucher, renewed, user)


def _mark_used(voucher: Voucher, user, outcome: _Outcome) -> None:
    voucher.status = Voucher.Status.USED
    voucher.redeemed_at = timezone.now()
    voucher.redeemed_by = user
    voucher.student_id = outcome.student_profile_id
    voucher.subscription_id = outcome.redemption.subscription_id
    voucher.invoice_id = outcome.redemption.invoice_id
    voucher.payment_id = outcome.payment_id
    voucher.save(
        update_fields=[
            "status",
            "redeemed_at",
            "redeemed_by",
            "student",
            "subscription_id",
            "invoice_id",
            "payment_id",
        ]
    )


@transaction.atomic
def redeem(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    *,
    user,
    code=None,
    voucher_id=None,
    student_user_id=None,
    subscription_id=None,
    invoice_id=None,
    office: bool = False,
) -> Redemption:
    """F-14: exactly once. A target given for another kind is ignored; the
    family's scope applies unless ``office`` (its codes are the view's)."""
    voucher = find(code=code, voucher_id=voucher_id, lock=True)
    refuse_spent(voucher, scheduling_services.today())
    if voucher.kind == Kind.ACTIVATION:
        outcome = _activate(voucher, user, student_user_id, office=office)
    else:
        outcome = _renew(voucher, user, subscription_id, office=office)
    _mark_used(voucher, user, outcome)
    return outcome.redemption
```

In `backend/etqan/vouchers/services/__init__.py` add (sorted into the imports and `__all__`):

```python
from etqan.vouchers.services.redeem import Redemption
from etqan.vouchers.services.redeem import find
from etqan.vouchers.services.redeem import in_family
from etqan.vouchers.services.redeem import kind_of
from etqan.vouchers.services.redeem import redeem
from etqan.vouchers.services.redeem import refuse_spent
```

with `"Redemption"`, `"find"`, `"in_family"`, `"kind_of"`, `"redeem"`, `"refuse_spent"` in `__all__`.

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/vouchers -q`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/vouchers
git -C backend commit -m "feat(vouchers): redeem activation and renewal codes once, under the code's lock (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: Vouchers services: discounts, removing one, and the family's preview

**Files:**
- Create: `backend/etqan/vouchers/tests/test_discount.py`, `backend/etqan/vouchers/tests/test_preview.py`
- Modify: `backend/etqan/vouchers/services/redeem.py`, `backend/etqan/vouchers/services/reads.py`, `backend/etqan/vouchers/services/__init__.py`

**Interfaces:**
- Consumes: Task 3's `record_code_payment`, `delete_code_payment`; billing's `invoice_for`; Task 4's `clean_text`; Task 5's `find`, `refuse_spent`, `in_family`, `_Outcome`, `_target`.
- Produces (`etqan.vouchers.services`):
  - `redeem(...)` also redeems a discount (F-19): `invoice_id` required (400 `invoice`), read through `invoice_for` (404), the family's scope (404), void 409 `billing.invoice_void`, nothing due 409 `billing.nothing_due`, scope 409 `vouchers.wrong_package` / `vouchers.wrong_course`, currency 409 `vouchers.wrong_currency`, then `record_code_payment(..., up_to_balance=True)` and the locked one-per-invoice check (409 `vouchers.invoice_discounted`);
  - `discount_amount(batch, amount_minor: int) -> int` (plan V22);
  - `remove_discount(voucher_id: int, *, reason: str, by) -> Voucher` (F-9);
  - `Renewable(subscription_id, student, course, package, term_ends_on, price_minor, currency)`, `Preview(code, kind, course, package, sessions_total, teacher, discount, expires_on, students, subscriptions)` (frozen dataclasses, plan V14), `preview(code, *, user) -> Preview`, `renewal_price(subscription, package) -> tuple[int, str]` (plan V15).

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/vouchers/tests/test_discount.py`:

```python
"""B3f F-4, F-9, F-14, F-16, F-19, F-25: discount codes on invoices, their
scope and cap, one per invoice, the family, removing one, the lock order."""

from datetime import date

import pytest

from etqan.billing import services as billing_services
from etqan.billing.models import Invoice
from etqan.billing.tests.conftest import make_parent
from etqan.catalogue import services as catalogue_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import subscription_for
from etqan.vouchers import services
from etqan.vouchers.tests.conftest import activation
from etqan.vouchers.tests.conftest import codes_of
from etqan.vouchers.tests.conftest import discount
from etqan.vouchers.tests.conftest import first_locks
from etqan.vouchers.tests.conftest import in_order
from etqan.vouchers.tests.conftest import row_of
from etqan.vouchers.tests.conftest import state_of

pytestmark = pytest.mark.django_db
JUNE_1 = date(2026, 6, 1)


def apply(code, bill, user, **kwargs):
    return services.redeem(code=code, user=user, invoice_id=bill.pk, **kwargs)


def figures(bill) -> tuple:
    row = billing_services.invoices_queryset().get(pk=bill.pk)
    return (row.status, row.paid_minor, row.balance_minor)


def code_payments(bill) -> list[tuple]:
    rows = billing_services.payments_queryset().filter(invoice_id=bill.pk, method="code")
    return [(p.amount_minor, p.reference) for p in rows.order_by("id")]


@pytest.mark.parametrize(
    ("amount", "percent", "taken"),
    [(1995, 10, 200), (1994, 10, 199), (4, 10, 1), (20000, 10, 2000), (20000, 100, 20000)],
)
def test_a_percentage_rounds_half_up_with_a_1_unit_minimum(
    world, admin, invoice, parent, amount, percent, taken
):
    bill = invoice(amount_minor=amount)
    (code,) = codes_of(discount(world, admin, discount_value=percent))
    redeemed = apply(code, bill, parent)
    assert redeemed == services.Redemption("discount", None, bill.pk, taken, "EGP")
    assert code_payments(bill) == [(taken, code)]
    assert figures(bill)[1] == taken
    row = row_of(code)
    assert (row.status, row.invoice_id, row.student.user_id, row.subscription_id) == (
        "used",
        bill.pk,
        world.student.pk,
        None,
    )


def test_a_full_discount_pays_the_invoice(world, admin, invoice, parent):
    bill = invoice(amount_minor=20000)
    (code,) = codes_of(discount(world, admin, discount_value=100))
    apply(code, bill, parent)
    assert figures(bill) == ("paid", 20000, 0)


def test_a_fixed_amount_applies_in_its_currency_only(world, admin, invoice, parent):
    (egp,) = codes_of(
        discount(world, admin, discount_kind="fixed", discount_value=5000, currency="EGP")
    )
    (usd,) = codes_of(
        discount(world, admin, discount_kind="fixed", discount_value=5000, currency="USD")
    )
    assert apply(egp, invoice(amount_minor=20000), parent).amount_minor == 5000
    with pytest.raises(ConflictError) as other:
        apply(usd, invoice(amount_minor=20000), parent)
    assert other.value.code == "vouchers.wrong_currency"
    assert state_of(usd) == "unused"


def test_a_discount_never_takes_more_than_is_owed(world, admin, invoice, parent):
    """F-4: capped at the balance read under the invoice lock."""
    bill = invoice(amount_minor=20000)
    billing_services.add_payment(
        bill, amount_minor=15000, method="cash", paid_on=JUNE_1, by=admin
    )
    (code,) = codes_of(discount(world, admin, discount_value=50))
    assert apply(code, bill, parent).amount_minor == 5000
    assert figures(bill) == ("paid", 20000, 0)


def test_a_scoped_code_applies_only_to_its_package_and_course(
    world, admin, invoice, parent
):
    weekly_package = catalogue_services.create_package(
        name_ar="أسبوعي",
        name_en="Weekly",
        sessions_per_week=1,
        session_minutes=30,
        duration_value=7,
        duration_unit="day",
        price_minor=40000,
        currency="EGP",
    )
    arabic_course = catalogue_services.create_course(
        name_ar="عربي", name_en="Arabic", teacher_ids=[world.teacher.pk]
    )
    monthly = subscription_for(world)
    weekly = subscription_for(world, package_id=weekly_package.pk)
    arabic = subscription_for(world, course_id=arabic_course.pk)

    def bill_for(sub):
        return invoice(amount_minor=10000, subscription_id=sub.pk)

    (by_package,) = codes_of(discount(world, admin, package_id=world.package.pk))
    (by_course,) = codes_of(discount(world, admin, course_id=world.course.pk))
    for code, target, expected in (
        (by_package, bill_for(weekly), "vouchers.wrong_package"),
        (by_package, invoice(amount_minor=10000), "vouchers.wrong_package"),
        (by_course, bill_for(arabic), "vouchers.wrong_course"),
        (by_course, invoice(amount_minor=10000), "vouchers.wrong_package"),
    ):
        with pytest.raises(ConflictError) as caught:
            apply(code, target, parent)
        assert caught.value.code == expected
    assert apply(by_package, bill_for(monthly), parent).amount_minor == 1000
    assert apply(by_course, bill_for(monthly), parent).amount_minor == 1000


def test_a_scoped_package_keeps_its_scope_whatever_happens_to_it(
    world, admin, invoice, parent
):
    """F-19, F-25: deactivated later it still matches its invoices; it can't
    be deleted, so the code never becomes a whole-academy one."""
    monthly = subscription_for(world)
    first, second = codes_of(discount(world, admin, quantity=2, package_id=world.package.pk))
    catalogue_services.update_package(world.package, is_active=False)
    with pytest.raises(ConflictError) as delete:
        catalogue_services.delete_package(world.package)
    assert delete.value.code == "catalogue.in_use"
    bill = invoice(amount_minor=10000, subscription_id=monthly.pk)
    assert apply(first, bill, parent).amount_minor == 1000
    with pytest.raises(ConflictError) as unrelated:
        apply(second, invoice(amount_minor=10000), parent)
    assert unrelated.value.code == "vouchers.wrong_package"


def test_a_void_or_settled_invoice_takes_no_discount(world, admin, invoice, parent):
    void = invoice()
    billing_services.void_invoice(void, by=admin)
    settled = invoice(amount_minor=1000)
    billing_services.add_payment(
        settled, amount_minor=1000, method="cash", paid_on=JUNE_1, by=admin
    )
    (code,) = codes_of(discount(world, admin))
    for target, expected in ((void, "billing.invoice_void"), (settled, "billing.nothing_due")):
        with pytest.raises(ConflictError) as caught:
            apply(code, target, parent)
        assert caught.value.code == expected
    assert state_of(code) == "unused"


def test_two_discount_codes_on_one_invoice_keep_the_first_and_roll_back_the_second(
    world, admin, invoice, parent
):
    """F-14: checked under the invoice lock, after the second payment was
    written; the error rolls that payment back."""
    bill = invoice(amount_minor=20000)
    first, second = codes_of(discount(world, admin, quantity=2))
    apply(first, bill, parent)
    with pytest.raises(ConflictError) as caught:
        apply(second, bill, parent)
    assert caught.value.code == "vouchers.invoice_discounted"
    assert code_payments(bill) == [(2000, first)]
    assert figures(bill) == ("partial", 2000, 18000)
    assert state_of(second) == "unused"


def test_the_student_or_a_parent_applies_a_discount_and_a_paying_sibling_cannot(
    world, admin, invoice, parent
):
    first, second, third = codes_of(discount(world, admin, quantity=3))
    payer_only = make_parent("Huda")
    billed = invoice(amount_minor=1000)
    Invoice.objects.filter(pk=billed.pk).update(payer=payer_only)
    assert billing_services.invoice_for(payer_only, billed.pk).pk == billed.pk
    for outsider in (payer_only, make_parent("Nobody")):
        with pytest.raises(NotFoundError):
            apply(first, billed, outsider)
    assert state_of(first) == "unused"
    assert apply(first, billed, parent).amount_minor == 100
    assert apply(second, invoice(amount_minor=1000), world.student).amount_minor == 100
    with pytest.raises(ValidationError) as missing:
        services.redeem(code=third, user=parent)
    assert missing.value.field == "invoice"


def test_the_office_reads_the_invoice_as_billing_scopes_it(
    world, admin, invoice, staff_for
):
    bill = invoice(amount_minor=1000)
    (code,) = codes_of(discount(world, admin))
    with pytest.raises(NotFoundError):
        services.redeem(
            code=code, user=staff_for("voucher.update").user, invoice_id=bill.pk, office=True
        )
    clerk = staff_for("voucher.update", "payment.create", "invoice.view").user
    redeemed = services.redeem(code=code, user=clerk, invoice_id=bill.pk, office=True)
    assert redeemed.amount_minor == 100


def test_a_discount_locks_the_code_then_the_invoice(world, admin, invoice, parent):
    bill = invoice()
    (code,) = codes_of(discount(world, admin))
    order = first_locks(lambda: apply(code, bill, parent))
    assert order[0] == "vouchers_voucher"
    in_order(order, "vouchers_voucher", "billing_invoice")


def test_removing_a_discount_deletes_its_payment_and_voids_the_code(
    world, admin, invoice, parent
):
    bill = invoice(amount_minor=20000)
    (code,) = codes_of(discount(world, admin))
    apply(code, bill, parent)
    used = row_of(code)
    removed = services.remove_discount(used.pk, reason=" Wrong invoice ", by=admin)
    assert (
        removed.status,
        removed.void_reason,
        removed.voided_by,
        removed.invoice_id,
        removed.payment_id,
    ) == ("void", "Wrong invoice", admin, bill.pk, used.payment_id)
    assert removed.redeemed_at is not None  # plan V3: history kept
    assert figures(bill) == ("unpaid", 0, 20000)
    assert code_payments(bill) == []
    with pytest.raises(ValidationError) as again:
        apply(code, bill, parent)
    assert again.value.code == "vouchers.invalid"  # never spent again
    assert billing_services.void_invoice(bill, by=admin).status == "void"  # F-9


def test_only_a_used_discount_is_removed_and_only_with_a_reason(world, admin):
    (act,) = codes_of(activation(world, admin))
    services.redeem(code=act, user=admin, office=True, student_user_id=world.student.pk)
    (unused,) = codes_of(discount(world, admin))
    for code, expected in ((act, "vouchers.not_discount"), (unused, "vouchers.not_used")):
        with pytest.raises(ConflictError) as caught:
            services.remove_discount(row_of(code).pk, reason="Mistake", by=admin)
        assert caught.value.code == expected
    for reason in ("", "   ", "x" * 201, None, 5):
        with pytest.raises(ValidationError) as bad:
            services.remove_discount(row_of(unused).pk, reason=reason, by=admin)
        assert bad.value.field == "reason"
    with pytest.raises(NotFoundError):
        services.remove_discount(999999, reason="Mistake", by=admin)


def test_removing_locks_the_code_then_the_invoice_then_the_payment(
    world, admin, invoice, parent
):
    bill = invoice()
    (code,) = codes_of(discount(world, admin))
    apply(code, bill, parent)
    row = row_of(code)
    order = first_locks(lambda: services.remove_discount(row.pk, reason="Mistake", by=admin))
    assert order[0] == "vouchers_voucher"
    in_order(order, "vouchers_voucher", "billing_invoice", "billing_payment")
```

Create `backend/etqan/vouchers/tests/test_preview.py`:

```python
"""B3f §4.2 `preview`, F-16, F-18 (plans V14, V15): what a family's check
shows, refused as `redeem` refuses, without a lock."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import stamp_archived
from etqan.scheduling.tests.conftest import subscription_for
from etqan.vouchers import services
from etqan.vouchers.tests.conftest import activation
from etqan.vouchers.tests.conftest import codes_of
from etqan.vouchers.tests.conftest import discount
from etqan.vouchers.tests.conftest import first_locks
from etqan.vouchers.tests.conftest import renewal
from etqan.vouchers.tests.conftest import row_of

pytestmark = pytest.mark.django_db
TOMORROW = datetime(2026, 6, 2, 8, 0, tzinfo=UTC)


def test_an_activation_preview_names_its_terms_and_the_active_students(
    world, admin, parent
):
    sister = make_student("Maryam")
    identity_services.link_guardian(parent, sister)
    gone = make_student("Hamid")
    identity_services.link_guardian(parent, gone)
    identity_services.deactivate(gone, by=admin)
    (code,) = codes_of(activation(world, admin))
    assert services.preview(code.lower(), user=parent) == services.Preview(
        code=code,
        kind="activation",
        course={"id": world.course.pk, "name_en": "Tajweed", "name_ar": "تجويد"},
        package={"id": world.package.pk, "name_en": "Monthly", "name_ar": "شهري"},
        sessions_total=8,
        teacher={"id": world.teacher.pk, "full_name": "Bilal"},
        discount=None,
        expires_on=date(2026, 6, 30),
        students=[
            {"id": world.student.pk, "name": "Yusuf"},
            {"id": sister.pk, "name": "Maryam"},
        ],
        subscriptions=[],
    )
    assert services.preview(code, user=world.student).students == [
        {"id": world.student.pk, "name": "Yusuf"}
    ]


def test_a_renewal_preview_lists_each_eligible_subscription_with_its_price(
    set_features, world, admin, parent
):
    arabic = catalogue_services.create_course(
        name_ar="عربي", name_en="Arabic", teacher_ids=[world.teacher.pk]
    )
    kept = subscription_for(world, price_minor=120000)
    subscription_for(world, course_id=arabic.pk)  # another course
    cancelled = subscription_for(world)
    scheduling_services.cancel_subscription(cancelled)
    renewed = subscription_for(world)
    follow = scheduling_services.renew_subscription(renewed)  # renewed: out
    archived = stamp_archived(subscription_for(world))
    (code,) = codes_of(renewal(world, admin))
    shown = services.preview(code, user=parent)
    assert [(r.subscription_id, r.price_minor, r.currency) for r in shown.subscriptions] == [
        (kept.pk, 120000, "EGP"),
        (follow.pk, 150000, "EGP"),
        (archived.pk, 150000, "EGP"),  # listed while the archive is off
    ]
    first = shown.subscriptions[0]
    assert (first.student, first.course, first.package, first.term_ends_on) == (
        {"id": world.student.pk, "name": "Yusuf"},
        {"id": world.course.pk, "name_en": "Tajweed", "name_ar": "تجويد"},
        {"id": world.package.pk, "name_en": "Monthly", "name_ar": "شهري"},
        kept.term_ends_on,
    )
    assert shown.students == []
    set_features(subscription_archive=True)
    assert [r.subscription_id for r in services.preview(code, user=parent).subscriptions] == [
        kept.pk,
        follow.pk,
    ]


def test_a_renewal_choice_shows_the_price_the_renewal_will_take(
    set_features, world, admin, parent
):
    """Plan V15, ledger D23: the currency changed, so the resolved price."""
    old = subscription_for(world, price_minor=120000)
    set_features(country_pricing=True)
    identity_services.update_person(world.student, profile={"country": "SA"})
    catalogue_services.set_country_prices(
        world.package, [{"country": "SA", "price_minor": 50000, "currency": "SAR"}]
    )
    (code,) = codes_of(renewal(world, admin))
    (choice,) = services.preview(code, user=parent).subscriptions
    assert (choice.price_minor, choice.currency) == (50000, "SAR")
    redeemed = services.redeem(code=code, user=parent, subscription_id=old.pk)
    assert (redeemed.amount_minor, redeemed.currency) == (50000, "SAR")


def test_a_discount_preview_shows_the_discount_and_no_targets(world, admin, parent):
    (code,) = codes_of(
        discount(world, admin, discount_kind="fixed", discount_value=5000, currency="EGP")
    )
    shown = services.preview(code, user=parent)
    assert (
        shown.kind,
        shown.discount,
        shown.course,
        shown.package,
        shown.sessions_total,
        shown.teacher,
        shown.students,
        shown.subscriptions,
    ) == ("discount", {"kind": "fixed", "value": 5000, "currency": "EGP"}, None, None, None, None, [], [])


def test_a_preview_refuses_as_redeem_does_and_locks_nothing(
    world, admin, parent, clock
):
    (used,) = codes_of(activation(world, admin))
    services.redeem(code=used, user=parent, student_user_id=world.student.pk)
    (void,) = codes_of(discount(world, admin))
    services.void(row_of(void).pk, by=admin)
    (late,) = codes_of(discount(world, admin, valid_days=1))
    (live,) = codes_of(discount(world, admin))
    with pytest.raises(ConflictError) as spent:
        services.preview(used, user=parent)
    assert spent.value.code == "vouchers.used"
    for text in (void, "SYS-00000-00000", ""):
        with pytest.raises(ValidationError) as caught:
            services.preview(text, user=parent)
        assert caught.value.code == "vouchers.invalid"
    assert first_locks(lambda: services.preview(live, user=parent)) == []
    clock.set(TOMORROW)
    with pytest.raises(ConflictError) as gone:
        services.preview(late, user=parent)
    assert gone.value.code == "vouchers.expired"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/vouchers/tests/test_discount.py etqan/vouchers/tests/test_preview.py -q`
Expected: FAIL (a discount reaches `_renew` and answers 400 `subscription`; no `remove_discount`, `preview`, `Preview`).

- [ ] **Step 3: Implement**

`backend/etqan/vouchers/services/redeem.py`: add `from etqan.platform.exceptions import ConflictError` and `from etqan.vouchers.services.batches import clean_text` to the imports; after `RETIRED` add:

```python
DiscountKind = VoucherBatch.DiscountKind
```

and after `_renew` add:

```python
def discount_amount(batch: VoucherBatch, amount_minor: int) -> int:
    """F-4 (plan V22): a percent of the invoice's amount, half up and at
    least 1 minor unit, or the fixed value; the balance caps it later."""
    if batch.discount_kind == DiscountKind.PERCENT:
        return max(1, (amount_minor * batch.discount_value + 50) // 100)
    return batch.discount_value


def _in_scope(batch: VoucherBatch, invoice) -> None:
    """F-19: a scoped code needs the invoice's subscription to be of its
    package and course; no subscription is a package mismatch."""
    if batch.course_id is None and batch.package_id is None:
        return
    subscription = (
        scheduling_services.subscriptions_queryset()
        .filter(pk=invoice.subscription_id)
        .first()
        if invoice.subscription_id is not None
        else None
    )
    if subscription is None:
        raise errors.wrong_package()
    if batch.package_id is not None and subscription.package_id != batch.package_id:
        raise errors.wrong_package()
    if batch.course_id is not None and subscription.course_id != batch.course_id:
        raise errors.wrong_course()


def _apply(voucher: Voucher, user, invoice_id, *, office: bool) -> _Outcome:
    """F-19: part or all of an invoice, paid by one `code` payment."""
    invoice_id = _target(invoice_id, "invoice", "Choose an invoice.")
    invoice = billing_services.invoice_for(user, invoice_id)
    if not office and not in_family(user, invoice.student.user_id):
        raise NotFoundError("Invoice", invoice_id)
    if invoice.status == "void":
        raise ConflictError("This invoice is void.", code="billing.invoice_void")
    if invoice.balance_minor <= 0:
        raise ConflictError(
            "Nothing is due on this invoice.", code="billing.nothing_due"
        )
    batch = voucher.batch
    _in_scope(batch, invoice)
    if batch.discount_kind == DiscountKind.FIXED and batch.currency != invoice.currency:
        raise errors.wrong_currency()
    payment = billing_services.record_code_payment(
        invoice,
        amount_minor=discount_amount(batch, invoice.amount_minor),
        reference=display(voucher.code),
        by=user,
        up_to_balance=True,
    )
    # F-14: under the invoice lock `record_code_payment` took; the error
    # rolls the payment back with the request (ATOMIC_REQUESTS).
    taken = Voucher.objects.filter(
        kind=Kind.DISCOUNT, status=Voucher.Status.USED, invoice_id=invoice.pk
    )
    if taken.exists():
        raise errors.invoice_discounted()
    redemption = Redemption(
        kind=voucher.kind,
        subscription_id=invoice.subscription_id,
        invoice_id=invoice.pk,
        amount_minor=payment.amount_minor,
        currency=payment.currency,
    )
    return _Outcome(redemption, invoice.student_id, payment.pk)
```

In `redeem`, replace

```python
    if voucher.kind == Kind.ACTIVATION:
        outcome = _activate(voucher, user, student_user_id, office=office)
    else:
        outcome = _renew(voucher, user, subscription_id, office=office)
```

with

```python
    if voucher.kind == Kind.ACTIVATION:
        outcome = _activate(voucher, user, student_user_id, office=office)
    elif voucher.kind == Kind.RENEWAL:
        outcome = _renew(voucher, user, subscription_id, office=office)
    else:
        outcome = _apply(voucher, user, invoice_id, office=office)
```

and at the end of the file add:

```python
@transaction.atomic
def remove_discount(voucher_id: int, *, reason: str, by) -> Voucher:
    """F-9 (ledger D43): the office removes a discount applied by mistake.
    The code is locked first, then billing locks the invoice and the payment
    (F-15). The code becomes `void`, never `unused`, and keeps its history."""
    reason = clean_text(reason, "reason", required=True)
    voucher = Voucher.objects.select_for_update().filter(pk=voucher_id).first()
    if voucher is None:
        raise NotFoundError("Code", voucher_id)
    if voucher.kind != Kind.DISCOUNT:
        raise errors.not_discount()
    if voucher.status != Voucher.Status.USED:
        raise errors.not_used()
    billing_services.delete_code_payment(voucher.payment_id)
    voucher.status = Voucher.Status.VOID
    voucher.voided_at = timezone.now()
    voucher.voided_by = by
    voucher.void_reason = reason
    voucher.save(update_fields=["status", "voided_at", "voided_by", "void_reason"])
    return voucher
```

`backend/etqan/vouchers/services/reads.py`: add to the imports

```python
from dataclasses import dataclass

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform import features
from etqan.platform.permissions import role_of
from etqan.vouchers.services.codes import display
from etqan.vouchers.services.redeem import find
from etqan.vouchers.services.redeem import refuse_spent
```

and append:

```python
# §4.2: a subscription a renewal code may renew; the archive rule is
# scheduling's `refuse_if_archived` (rules.py:177-182), mirrored here.
RENEWABLE = ("active", "paused", "expired")
ARCHIVE = "subscription_archive"


@dataclass(frozen=True)
class Renewable:
    subscription_id: int
    student: dict
    course: dict
    package: dict
    term_ends_on: date
    price_minor: int
    currency: str


@dataclass(frozen=True)
class Preview:
    code: str
    kind: str
    course: dict | None
    package: dict | None
    sessions_total: int | None
    teacher: dict | None
    discount: dict | None
    expires_on: date
    students: list[dict]
    subscriptions: list[Renewable]


def named(row) -> dict | None:
    if row is None:
        return None
    return {"id": row.pk, "name_en": row.name_en, "name_ar": row.name_ar}


def teacher_of(batch) -> dict | None:
    if batch.teacher_id is None:
        return None
    return {"id": batch.teacher.user_id, "full_name": batch.teacher.user.full_name}


def discount_of(batch) -> dict | None:
    if batch.kind != VoucherBatch.Kind.DISCOUNT:
        return None
    return {
        "kind": batch.discount_kind,
        "value": batch.discount_value,
        "currency": batch.currency,
    }


def renewal_price(subscription, package) -> tuple[int, str]:
    """Plan V15: what `renew_subscription` takes with no price given: the
    amount paid in the same currency (P4-10), else the resolved price."""
    price = catalogue_services.package_price(
        package, country=subscription.student.country
    )
    if price.currency == subscription.currency:
        return subscription.price_minor, subscription.currency
    return price.price_minor, price.currency


def _family(user) -> list:
    """F-16: the student, or a parent's children; active ones only (V14)."""
    role = role_of(user)
    if role == "student":
        profile = identity_services.get_student_profile(user.pk)
        profiles = [] if profile is None else [profile]
    elif role == "parent":
        profiles = list(identity_services.get_children(user.pk).select_related("user"))
    else:
        profiles = []
    return [profile for profile in profiles if profile.user.is_active]


def _renewables(batch, family) -> list[Renewable]:
    rows = scheduling_services.subscriptions_queryset().filter(
        student_id__in=[profile.pk for profile in family],
        course_id=batch.course_id,
        status__in=RENEWABLE,
        renewal_id__isnull=True,
    )
    if features.enabled(ARCHIVE):
        rows = rows.filter(archived_at__isnull=True)
    choices = []
    for sub in rows.order_by("student__user__full_name", "id"):
        price_minor, currency = renewal_price(sub, batch.package)
        choices.append(
            Renewable(
                subscription_id=sub.pk,
                student={"id": sub.student.user_id, "name": sub.student.user.full_name},
                course=named(sub.course),
                package=named(batch.package),
                term_ends_on=sub.term_ends_on,
                price_minor=price_minor,
                currency=currency,
            )
        )
    return choices


def preview(code, *, user) -> Preview:
    """The family's check step (§4.2): refused as `redeem` refuses, without
    a lock; activation lists the students, renewal the subscriptions."""
    voucher = find(code=code)
    refuse_spent(voucher, today())
    batch = voucher.batch
    family = _family(user)
    kind = voucher.kind
    return Preview(
        code=display(voucher.code),
        kind=kind,
        course=named(batch.course),
        package=named(batch.package),
        sessions_total=(
            catalogue_services.sessions_total(batch.package) if batch.package else None
        ),
        teacher=teacher_of(batch),
        discount=discount_of(batch),
        expires_on=batch.expires_on,
        students=(
            [{"id": p.user_id, "name": p.user.full_name} for p in family]
            if kind == VoucherBatch.Kind.ACTIVATION
            else []
        ),
        subscriptions=(
            _renewables(batch, family) if kind == VoucherBatch.Kind.RENEWAL else []
        ),
    )
```

In `backend/etqan/vouchers/services/__init__.py` add (sorted into the imports and `__all__`):

```python
from etqan.vouchers.services.reads import Preview
from etqan.vouchers.services.reads import Renewable
from etqan.vouchers.services.reads import discount_of
from etqan.vouchers.services.reads import named
from etqan.vouchers.services.reads import preview
from etqan.vouchers.services.reads import renewal_price
from etqan.vouchers.services.reads import teacher_of
from etqan.vouchers.services.redeem import discount_amount
from etqan.vouchers.services.redeem import remove_discount
```

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/vouchers -q`
Expected: PASS.
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/vouchers
git -C backend commit -m "feat(vouchers): discount codes on invoices, removing one, and the family's preview (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: The vouchers API, its throttles, the `voucher` resource and the route matrix

**Files:**
- Create: `backend/etqan/vouchers/throttling.py`, `backend/etqan/vouchers/api/__init__.py`, `backend/etqan/vouchers/api/urls.py`, `backend/etqan/vouchers/api/serializers.py`, `backend/etqan/vouchers/api/payloads.py`, `backend/etqan/vouchers/api/views.py`, `backend/etqan/vouchers/tests/test_api.py`
- Modify: `backend/config/settings/base.py` (next to B3g's rate), `backend/config/api_router.py` (B3 marker), `backend/etqan/access/registry.py` (B3 marker), `backend/etqan/access/tests/test_registry.py`, `backend/etqan/access/tests/test_routes.py`

**Interfaces:**
- Consumes: Tasks 4–6's services.
- Produces: `/api/v1/vouchers/` routes (spec §5, plans V5, V9, V17–V19):

| Route | Methods | View | Code |
|---|---|---|---|
| `batches/` | GET, POST | `BatchListView` | `voucher.view_any` / `voucher.create` |
| `codes/` | GET (`?format=csv`) | `CodeListView` | `voucher.view_any` |
| `codes/<id>/void/` | POST | `VoidView` | `voucher.update` |
| `codes/<id>/redeem/` | POST | `OfficeRedeemView` | `voucher.update` (+ the kind's, in the view) |
| `codes/redeem/` | POST | `OfficeRedeemByCodeView` | `voucher.update` (+ the kind's, in the view) |
| `codes/<id>/remove-discount/` | POST | `RemoveDiscountView` | `voucher.update` (+ `payment.update`, in the view) |
| `check/` | POST | `CheckView` | student or parent (`SELF_SERVICE`) |
| `redeem/` | POST | `RedeemView` | student or parent (`SELF_SERVICE`) |

  - the resource `voucher` ("System codes" / "أكواد النظام"), in use `view_any`, `create`, `update`;
  - `DEFAULT_THROTTLE_RATES["voucher_redeem"] = "20/hour"`, `["voucher_redeem_ip"] = "60/hour"`.

- [ ] **Step 1: Write the failing tests**

In `backend/etqan/access/tests/test_registry.py`, after the B3e `wallet` block (before `assert by_code["session"].verbs …`):

```python
    # Phase B3 (slice B3f, F-21).
    assert by_code["voucher"].in_use == ("view_any", "create", "update")
    assert (by_code["voucher"].label_en, by_code["voucher"].label_ar) == (
        "System codes",
        "أكواد النظام",
    )
```

In `backend/etqan/access/tests/test_routes.py`:
- In `ROUTES`, after the B3e Part B rows (`("POST", "/api/v1/wallet/compensations/", "wallet.create"),`):

```python
    # Phase B3, slice B3f: system codes (plan V19). The kind's own codes and
    # remove-discount's payment.update are checked in the view past the
    # lookup; check/ and redeem/ are SELF_SERVICE (families, F-16).
    ("GET", "/api/v1/vouchers/batches/", "voucher.view_any"),
    ("POST", "/api/v1/vouchers/batches/", "voucher.create"),
    ("GET", "/api/v1/vouchers/codes/", "voucher.view_any"),
    ("POST", f"/api/v1/vouchers/codes/{N}/void/", "voucher.update"),
    ("POST", f"/api/v1/vouchers/codes/{N}/redeem/", "voucher.update"),
    ("POST", "/api/v1/vouchers/codes/redeem/", "voucher.update"),
    ("POST", f"/api/v1/vouchers/codes/{N}/remove-discount/", "voucher.update"),
```

- In `FEATURES`, after the B3e `**dict.fromkeys(…, "balances")` block:

```python
    # Phase B3, slice B3f.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/vouchers/batches/"),
            ("POST", "/api/v1/vouchers/batches/"),
            ("GET", "/api/v1/vouchers/codes/"),
            ("POST", f"/api/v1/vouchers/codes/{N}/void/"),
            ("POST", f"/api/v1/vouchers/codes/{N}/redeem/"),
            ("POST", "/api/v1/vouchers/codes/redeem/"),
            ("POST", f"/api/v1/vouchers/codes/{N}/remove-discount/"),
        ),
        "system_codes",
    ),
```

- In `FEATURE_WORDS`, after `"/wallet/": "balances",  # B3e`: `"/vouchers/": "system_codes",  # B3f`.
- In `SELF_SERVICE`, after the B3e entries:

```python
    # Phase B3, slice B3f (plan V19): families only; F-16 in the service.
    "etqan.vouchers.api.views.CheckView": (
        "a student or parent checks a code; throttled per user and per IP"
    ),
    "etqan.vouchers.api.views.RedeemView": (
        "a student or parent redeems for their family (F-16); throttled"
    ),
```

Create `backend/etqan/vouchers/tests/test_api.py`:

```python
"""B3f §5, F-13, F-16, F-20..F-22, D19: the vouchers routes, who may use
them, the throttles, impersonation, the features, CSV and isolation."""

import time
from datetime import date

import pytest
from django.contrib.auth import get_user_model
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.billing import services as billing_services
from etqan.billing.tests.conftest import make_parent
from etqan.platform.permissions import FEATURE_OFF
from etqan.platform.permissions import IMPERSONATOR_KEY
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import until_pk_exceeds
from etqan.vouchers import services
from etqan.vouchers.models import Voucher
from etqan.vouchers.tests.conftest import activation
from etqan.vouchers.tests.conftest import as_user
from etqan.vouchers.tests.conftest import codes_of
from etqan.vouchers.tests.conftest import discount
from etqan.vouchers.tests.conftest import renewal
from etqan.vouchers.tests.conftest import row_of
from etqan.vouchers.tests.conftest import state_of

pytestmark = pytest.mark.django_db
V = "/api/v1/vouchers/"
UNKNOWN = "SYS-00000-00000"


def impersonated(client, admin):
    """``client``'s session marked as opened by ``admin`` (quick login)."""
    session = client.session
    session[IMPERSONATOR_KEY] = {
        "id": admin.pk,
        "hash": admin.get_session_auth_hash(),
        "since": time.time(),
    }
    session.save()
    return client


def post(client, url, body=None):
    return client.post(url, body or {}, format="json")


# ── The office ───────────────────────────────────────────────────────────────


def test_the_office_generates_and_lists_a_batch(api_for, codes_on, world):
    office = api_for("admin")
    resp = post(
        office,
        f"{V}batches/",
        {
            "kind": "activation",
            "quantity": 2,
            "valid_days": 30,
            "course": world.course.pk,
            "package": world.package.pk,
            "teacher": world.teacher.pk,
            "note": "June flyers",
        },
    )
    assert resp.status_code == 201, resp.content
    batch = resp.json()
    assert {k: batch[k] for k in ("kind", "quantity", "valid_days", "expires_on", "note", "sessions_total")} == {
        "kind": "activation",
        "quantity": 2,
        "valid_days": 30,
        "expires_on": "2026-06-30",
        "note": "June flyers",
        "sessions_total": 8,
    }
    assert batch["course"] == {"id": world.course.pk, "name_en": "Tajweed", "name_ar": "تجويد"}
    assert batch["teacher"] == {"id": world.teacher.pk, "full_name": "Bilal"}
    assert batch["discount"] is None
    assert batch["created_by"]["id"] == office.user.pk
    listed = office.get(f"{V}batches/").json()
    assert [row["id"] for row in listed["results"]] == [batch["id"]]
    codes = office.get(f"{V}codes/", {"batch": batch["id"]}).json()["results"]
    assert len(codes) == 2
    assert {row["state"] for row in codes} == {"unused"}
    for row in codes:
        assert len(row["code"]) == 15
        assert row["code"].startswith("SYS-")


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"kind": "discount", "quantity": "abc", "valid_days": 30}, "quantity"),
        ({"kind": "discount", "quantity": True, "valid_days": 30}, "quantity"),
        ({"kind": "discount", "quantity": 1.5, "valid_days": 30}, "quantity"),
        ({"kind": "discount", "quantity": 501, "valid_days": 30}, "quantity"),
        ({"kind": "gift", "quantity": 1, "valid_days": 30}, "kind"),
        ({"kind": "discount", "quantity": 1, "valid_days": 30, "discount_kind": "percent", "discount_value": 0}, "discount_value"),
        ({"kind": "discount", "quantity": 1, "valid_days": 30, "discount_kind": "fixed", "discount_value": 5, "currency": "EGPP"}, "currency"),
        ({"kind": "activation", "quantity": 1, "valid_days": 30, "course": 10**30}, "course"),
        ({"kind": "discount", "quantity": 1, "valid_days": 30, "note": "x" * 201}, "note"),
    ],
)
def test_a_bad_batch_is_a_400_on_its_field(api_for, codes_on, world, body, field):
    resp = post(api_for("admin"), f"{V}batches/", body)
    assert resp.status_code == 400, resp.content
    assert field in resp.json()
    assert not services.has_batches()


def test_the_list_filters_and_shows_a_redeemed_code(api_for, codes_on, world, admin, parent):
    first, second = codes_of(activation(world, admin, quantity=2))
    redeemed = services.redeem(code=first, user=parent, student_user_id=world.student.pk)
    office = api_for("admin")
    (row,) = office.get(f"{V}codes/", {"code": first.lower()}).json()["results"]
    assert row == {
        "id": row_of(first).pk,
        "code": first,
        "kind": "activation",
        "state": "used",
        "batch": {"id": row_of(first).batch_id, "note": ""},
        "course": {"id": world.course.pk, "name_en": "Tajweed", "name_ar": "تجويد"},
        "package": {"id": world.package.pk, "name_en": "Monthly", "name_ar": "شهري"},
        "teacher": {"id": world.teacher.pk, "full_name": "Bilal"},
        "sessions_total": 8,
        "discount": None,
        "expires_on": "2026-06-30",
        "redeemed_at": row["redeemed_at"],
        "redeemed_by": {"id": parent.pk, "full_name": "Zainab"},
        "student": {"id": world.student.pk, "full_name": "Yusuf"},
        "subscription_id": redeemed.subscription_id,
        "invoice_id": redeemed.invoice_id,
        "void_reason": "",
        "created_at": row["created_at"],
    }
    assert row["redeemed_at"] is not None
    states = office.get(f"{V}codes/", {"state": "unused"}).json()["results"]
    assert [r["code"] for r in states] == [second]
    assert office.get(f"{V}codes/", {"state": "lost"}).status_code == 400
    assert office.get(f"{V}codes/", {"batch": "x"}).status_code == 400


def test_the_csv_follows_the_filters(api_for, codes_on, world, admin):
    (code,) = codes_of(discount(world, admin, discount_kind="fixed", discount_value=5000, currency="EGP", note="Ramadan"))
    activation(world, admin)
    resp = api_for("admin").get(f"{V}codes/", {"format": "csv", "kind": "discount"})
    assert resp.status_code == 200
    lines = resp.content.decode("utf-8-sig").splitlines()
    assert lines[0] == (
        "Code,Type,Course,Package,Teacher,Discount type,Discount value,"
        "Discount currency,Expires on,Status,Redeemed at,Student,Batch note,Void reason"
    )
    assert lines[1:] == [f"{code},discount,,,,fixed,5000,EGP,2026-06-30,unused,,,Ramadan,"]


def test_the_list_reads_in_a_fixed_number_of_queries(api_for, codes_on, world, admin, parent):
    office = api_for("admin")
    activation(world, admin)
    with CaptureQueriesContext(connection) as few:
        assert office.get(f"{V}codes/").status_code == 200
    more = codes_of(activation(world, admin, quantity=4))
    discount(world, admin, quantity=3, package_id=world.package.pk, course_id=world.course.pk)
    services.redeem(code=more[0], user=parent, student_user_id=world.student.pk)
    with CaptureQueriesContext(connection) as many:
        assert office.get(f"{V}codes/").status_code == 200
    assert len(many) == len(few)


def test_the_office_voids_a_code_with_a_reason(api_for, codes_on, world, admin):
    (code,) = codes_of(discount(world, admin))
    office = api_for("admin")
    resp = post(office, f"{V}codes/{row_of(code).pk}/void/", {"reason": "Posted online"})
    assert resp.status_code == 200, resp.content
    assert (resp.json()["state"], resp.json()["void_reason"]) == ("void", "Posted online")
    again = post(office, f"{V}codes/{row_of(code).pk}/void/")
    assert (again.status_code, again.json()["code"]) == (409, "vouchers.not_unused")


def test_office_redemption_needs_the_kinds_own_codes(staff_for, codes_on, world, admin, invoice):
    """F-20: voucher.update plus what the same manual action needs."""
    sub = subscription_for(world)
    bill = invoice(amount_minor=1000)
    cases = (
        (activation, {"student": world.student.pk}, ("subscription.create",)),
        (renewal, {"subscription": sub.pk}, ("subscription.update",)),
        (discount, {"invoice": bill.pk}, ("payment.create", "invoice.view")),
    )
    for make, targets, extra in cases:
        by_id, by_text = codes_of(make(world, admin, quantity=2))
        bare = staff_for("voucher.update")
        for resp in (
            post(bare, f"{V}codes/{row_of(by_id).pk}/redeem/", targets),
            post(bare, f"{V}codes/redeem/", {"code": by_text, **targets}),
        ):
            assert resp.status_code == 403, (make.__name__, resp.content)
        clerk = staff_for("voucher.update", *extra)
        first = post(clerk, f"{V}codes/{row_of(by_id).pk}/redeem/", targets)
        assert first.status_code == 201, (make.__name__, first.content)
        assert first.json()["kind"] == make.__name__
        if make is not activation:
            continue  # one renewal per subscription, one discount per invoice
        second = post(clerk, f"{V}codes/redeem/", {"code": by_text.lower(), **targets})
        assert second.status_code == 201, (make.__name__, second.content)


def test_an_office_discount_by_code_text(api_for, codes_on, world, admin, invoice):
    bill = invoice(amount_minor=20000)
    (code,) = codes_of(discount(world, admin))
    resp = post(api_for("admin"), f"{V}codes/redeem/", {"code": code, "invoice": bill.pk})
    assert resp.status_code == 201, resp.content
    assert resp.json() == {
        "kind": "discount",
        "subscription_id": None,
        "invoice_id": bill.pk,
        "amount_minor": 2000,
        "currency": "EGP",
    }


def test_removing_a_discount_needs_payment_update_too(staff_for, codes_on, world, admin, invoice):
    bill = invoice(amount_minor=20000)
    (code,) = codes_of(discount(world, admin))
    services.redeem(code=code, user=admin, office=True, invoice_id=bill.pk)
    url = f"{V}codes/{row_of(code).pk}/remove-discount/"
    assert post(staff_for("voucher.update"), url, {"reason": "Wrong"}).status_code == 403
    assert post(staff_for("voucher.update", "payment.update"), f"{V}codes/999999/remove-discount/", {"reason": "x"}).status_code == 404
    clerk = staff_for("voucher.update", "payment.update")
    blank = post(clerk, url, {"reason": "  "})
    assert (blank.status_code, "reason" in blank.json()) == (400, True)
    resp = post(clerk, url, {"reason": "Wrong invoice"})
    assert resp.status_code == 200, resp.content
    assert (resp.json()["state"], resp.json()["void_reason"]) == ("void", "Wrong invoice")


def test_office_routes_refuse_families_and_teachers(api_for, codes_on, world, admin, parent):
    (code,) = codes_of(discount(world, admin))
    for client in (as_user(parent), as_user(world.student), as_user(world.teacher)):
        assert client.get(f"{V}codes/").status_code == 403
        assert client.get(f"{V}codes/", {"format": "csv"}).status_code == 403
        assert post(client, f"{V}codes/redeem/", {"code": code}).status_code == 403


def test_the_office_cannot_redeem_or_remove_while_impersonating(api_for, codes_on, world, admin, invoice):
    office = impersonated(api_for("admin"), make_admin("Hala"))
    (code,) = codes_of(discount(world, admin))
    bill = invoice()
    resp = post(office, f"{V}codes/redeem/", {"code": code, "invoice": bill.pk})
    assert (resp.status_code, resp.json()["code"]) == (403, "identity.impersonating")
    assert post(office, f"{V}codes/{row_of(code).pk}/remove-discount/", {"reason": "x"}).status_code == 403
    assert office.get(f"{V}codes/").status_code == 200  # reading stays open
    assert state_of(code) == "unused"


# ── The family ───────────────────────────────────────────────────────────────


def test_a_parent_checks_then_redeems_an_activation(codes_on, world, admin, parent):
    (code,) = codes_of(activation(world, admin))
    client = as_user(parent)
    shown = post(client, f"{V}check/", {"code": code.lower()})
    assert shown.status_code == 200, shown.content
    assert shown.json() == {
        "code": code,
        "kind": "activation",
        "course": {"id": world.course.pk, "name_en": "Tajweed", "name_ar": "تجويد"},
        "package": {"id": world.package.pk, "name_en": "Monthly", "name_ar": "شهري"},
        "sessions_total": 8,
        "teacher": {"id": world.teacher.pk, "full_name": "Bilal"},
        "discount": None,
        "expires_on": "2026-06-30",
        "students": [{"id": world.student.pk, "name": "Yusuf"}],
        "subscriptions": [],
    }
    resp = post(client, f"{V}redeem/", {"code": code, "student": world.student.pk})
    assert resp.status_code == 201, resp.content
    assert (resp.json()["kind"], resp.json()["amount_minor"]) == ("activation", 150000)
    again = post(client, f"{V}check/", {"code": code})
    assert (again.status_code, again.json()["code"]) == (409, "vouchers.used")


def test_a_student_checks_a_renewal_and_sees_its_price(codes_on, world, admin):
    old = subscription_for(world, price_minor=120000)
    (code,) = codes_of(renewal(world, admin))
    client = as_user(world.student)
    (choice,) = post(client, f"{V}check/", {"code": code}).json()["subscriptions"]
    assert {k: choice[k] for k in ("subscription_id", "price_minor", "currency")} == {
        "subscription_id": old.pk,
        "price_minor": 120000,
        "currency": "EGP",
    }
    assert choice["student"] == {"id": world.student.pk, "name": "Yusuf"}
    resp = post(client, f"{V}redeem/", {"code": code, "subscription": old.pk})
    assert (resp.status_code, resp.json()["amount_minor"]) == (201, 120000)


def test_unknown_and_void_codes_answer_alike(codes_on, world, admin, parent):
    """F-13, plan V5: one 400 body, whatever is wrong with the text."""
    (code,) = codes_of(discount(world, admin))
    services.void(row_of(code).pk, by=admin)
    client = as_user(parent)
    answers = [
        post(client, f"{V}check/", body)
        for body in ({"code": UNKNOWN}, {"code": code}, {"code": ""}, {}, {"code": "x" * 5000})
    ]
    for resp in answers:
        assert (resp.status_code, resp.json()) == (400, {"code": "vouchers.invalid"})


def test_family_routes_refuse_the_office_and_teachers(api_for, codes_on, world, admin, staff_for):
    (code,) = codes_of(discount(world, admin))
    for client in (api_for("admin"), staff_for("voucher.update"), as_user(world.teacher)):
        assert post(client, f"{V}check/", {"code": code}).status_code == 403
        assert post(client, f"{V}redeem/", {"code": code}).status_code == 403


def test_a_family_cannot_redeem_while_impersonated(codes_on, world, admin, parent, invoice):
    client = impersonated(as_user(parent), admin)
    (code,) = codes_of(discount(world, admin))
    assert post(client, f"{V}check/", {"code": code}).status_code == 200
    resp = post(client, f"{V}redeem/", {"code": code, "invoice": invoice().pk})
    assert (resp.status_code, resp.json()["code"]) == (403, "identity.impersonating")
    assert state_of(code) == "unused"


def test_a_family_outside_the_target_gets_404(codes_on, world, admin, invoice):
    stranger = as_user(make_parent("Huda"))
    act, disc = codes_of(activation(world, admin))[0], codes_of(discount(world, admin))[0]
    assert post(stranger, f"{V}redeem/", {"code": act, "student": world.student.pk}).status_code == 404
    assert post(stranger, f"{V}redeem/", {"code": disc, "invoice": invoice().pk}).status_code == 404
    missing = post(stranger, f"{V}redeem/", {"code": act})
    assert (missing.status_code, "student" in missing.json()) == (400, True)


def test_one_family_member_gets_20_tries_an_hour(codes_on, world, parent):
    client = as_user(parent)
    for _ in range(20):
        assert post(client, f"{V}check/", {"code": UNKNOWN}).status_code == 400
    assert post(client, f"{V}redeem/", {"code": UNKNOWN}).status_code == 429


def test_one_address_gets_60_tries_an_hour_across_accounts(codes_on, world):
    for n in range(4):
        client = as_user(make_parent(f"Guesser {n}"))
        for _ in range(15):
            assert post(client, f"{V}check/", {"code": UNKNOWN}).status_code == 400
    late = as_user(make_parent("Guesser 5"))
    assert post(late, f"{V}check/", {"code": UNKNOWN}).status_code == 429


def test_the_office_routes_are_not_throttled(api_for, codes_on, world, admin):
    office = api_for("admin")
    for _ in range(25):
        assert post(office, f"{V}codes/redeem/", {"code": UNKNOWN}).status_code == 400


# ── Features and isolation ───────────────────────────────────────────────────


def test_a_code_survives_the_feature_being_switched_off(api_for, set_features, world, admin, parent):
    set_features(invoices=True, system_codes=True)
    (code,) = codes_of(activation(world, admin))
    set_features(system_codes=False)
    client = as_user(parent)
    off = post(client, f"{V}check/", {"code": code})
    assert (off.status_code, off.json()) == (404, {"detail": FEATURE_OFF})
    assert post(client, f"{V}redeem/", {"code": code, "student": world.student.pk}).status_code == 404
    assert api_for("admin").get(f"{V}codes/").status_code == 404
    set_features(system_codes=True)
    resp = post(client, f"{V}redeem/", {"code": code, "student": world.student.pk})
    assert resp.status_code == 201, resp.content


def test_discount_routes_need_invoices(api_for, set_features, world, admin, parent, invoice):
    set_features(invoices=True, system_codes=True)
    bill = invoice()
    first, second = codes_of(discount(world, admin, quantity=2))
    services.redeem(code=first, user=admin, office=True, invoice_id=bill.pk)
    set_features(invoices=False)
    office = api_for("admin")
    for resp in (
        post(as_user(parent), f"{V}redeem/", {"code": second, "invoice": bill.pk}),
        post(office, f"{V}codes/redeem/", {"code": second, "invoice": bill.pk}),
        post(office, f"{V}codes/{row_of(second).pk}/redeem/", {"invoice": bill.pk}),
        post(office, f"{V}codes/{row_of(first).pk}/remove-discount/", {"reason": "x"}),
    ):
        assert (resp.status_code, resp.json()) == (404, {"detail": FEATURE_OFF})
    assert state_of(second) == "unused"
    assert state_of(first) == "used"


def test_another_academys_codes_never_leak(  # noqa: PLR0913 -- pytest fixtures
    api_for, codes_on, world, admin, parent, tenants, set_features
):
    discount(world, admin)
    voucher_ceiling = Voucher.objects.aggregate(m=Max("pk"))["m"]
    set_features(academy=tenants.other, invoices=True, system_codes=True)
    with tenant_context(tenants.other):
        batch = until_pk_exceeds(
            Voucher,
            voucher_ceiling,
            lambda: services.generate(
                kind="discount",
                quantity=1,
                valid_days=30,
                discount_kind="percent",
                discount_value=10,
                by=None,
            ),
        )
        theirs = batch.codes.get()
        their_code, their_pk = services.display(theirs.code), theirs.pk
    assert their_pk > voucher_ceiling
    office = api_for("admin")
    assert their_code not in [r["code"] for r in office.get(f"{V}codes/").json()["results"]]
    assert office.get(f"{V}codes/", {"code": their_code}).json()["results"] == []
    assert post(office, f"{V}codes/{their_pk}/void/").status_code == 404
    assert post(office, f"{V}codes/{their_pk}/remove-discount/", {"reason": "x"}).status_code == 404
    for resp in (
        post(office, f"{V}codes/redeem/", {"code": their_code}),
        post(as_user(parent), f"{V}check/", {"code": their_code}),
    ):
        assert (resp.status_code, resp.json()) == (400, {"code": "vouchers.invalid"})
    with tenant_context(tenants.other):
        assert services.vouchers_queryset(date(2026, 6, 1)).get(pk=their_pk).state == "unused"


def test_odd_bodies_and_huge_ids_are_never_500s(api_for, codes_on, world, admin, parent):
    (code,) = codes_of(discount(world, admin))
    office, huge = api_for("admin"), 10**30
    for url in (f"{V}codes/{huge}/void/", f"{V}codes/{huge}/redeem/", f"{V}codes/{huge}/remove-discount/"):
        assert post(office, url, {"reason": "x"}).status_code == 404, url
    for body in ({"code": code, "invoice": huge}, {"code": code, "invoice": "x"}, {"code": code, "invoice": True}):
        assert post(as_user(parent), f"{V}redeem/", body).status_code in (400, 404), body
    for body in ([1, 2], "text", {"code": ["a"]}):
        resp = office.post(f"{V}codes/redeem/", body, format="json")
        assert resp.status_code == 400, body
    assert office.get(f"{V}codes/", {"batch": huge}).status_code in (200, 400)
    assert state_of(code) == "unused"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DJ pytest etqan/vouchers/tests/test_api.py etqan/access -q`
Expected: FAIL (404 on every `/api/v1/vouchers/` route; `voucher` not in the registry; the route matrix names views that do not exist).

- [ ] **Step 3: Implement**

`backend/config/settings/base.py`, in `DEFAULT_THROTTLE_RATES`, after `"payment_link": "60/minute",`:

```python
        # B3f F-13: a family's code checks and redemptions, per user and per
        # IP (plan V6: both keyed by the academy's schema).
        "voucher_redeem": "20/hour",
        "voucher_redeem_ip": "60/hour",
```

`backend/config/api_router.py`, under `# ── phase B3 ──`, after the `wallet/` line:

```python
    # batches/, codes/, codes/<id>/void|redeem|remove-discount/, codes/redeem/,
    # check/, redeem/ (B3f spec §5).
    path("vouchers/", include("etqan.vouchers.api.urls")),
```

`backend/etqan/access/registry.py`, under `# ── phase B3 ──`, after the `wallet` resource:

```python
    # B3f (F-21): system codes; admins hold it, teachers never, the
    # Supervisor preset gains nothing.
    Resource(
        "voucher",
        "System codes",
        "أكواد النظام",
        ("view_any", "create", "update"),
    ),
```

Create `backend/etqan/vouchers/throttling.py`:

```python
"""B3f F-13 (plan V6): the family's code routes, throttled per user and per
IP. Both keys carry the academy's schema, as `site/throttling.py`'s do, so
two academies never share a counter (user ids repeat across schemas)."""

from django.db import connection
from rest_framework.throttling import SimpleRateThrottle


class VoucherUserThrottle(SimpleRateThrottle):
    scope = "voucher_redeem"

    def get_cache_key(self, request, view):
        ident = f"{connection.schema_name}:{request.user.pk}"
        return self.cache_format % {"scope": self.scope, "ident": ident}


class VoucherIPThrottle(SimpleRateThrottle):
    scope = "voucher_redeem_ip"

    def get_cache_key(self, request, view):
        ident = f"{connection.schema_name}:{self.get_ident(request)}"
        return self.cache_format % {"scope": self.scope, "ident": ident}
```

Create `backend/etqan/vouchers/api/__init__.py` (empty) and `backend/etqan/vouchers/api/urls.py`:

```python
from django.urls import path

from etqan.vouchers.api import views

app_name = "vouchers"
urlpatterns = [
    path("batches/", views.BatchListView.as_view(), name="batches"),
    path("codes/", views.CodeListView.as_view(), name="codes"),
    path("codes/redeem/", views.OfficeRedeemByCodeView.as_view(), name="redeem-by-code"),
    path("codes/<int:pk>/void/", views.VoidView.as_view(), name="void"),
    path("codes/<int:pk>/redeem/", views.OfficeRedeemView.as_view(), name="office-redeem"),
    path(
        "codes/<int:pk>/remove-discount/",
        views.RemoveDiscountView.as_view(),
        name="remove-discount",
    ),
    path("check/", views.CheckView.as_view(), name="check"),
    path("redeem/", views.RedeemView.as_view(), name="redeem"),
]
```

Create `backend/etqan/vouchers/api/serializers.py`:

```python
"""Request bodies and list queries (spec §5). Responses are built in
`payloads`. Ranges and the kind's requirements are the services' (plan V8),
so each refusal has one wording; here only shapes are checked."""

from rest_framework import serializers

from etqan.vouchers import services
from etqan.vouchers.models import NOTE_LENGTH
from etqan.vouchers.models import VoucherBatch


def _id(**kwargs):
    return serializers.IntegerField(min_value=1, **kwargs)


class BatchInput(serializers.Serializer):
    kind = serializers.ChoiceField(choices=VoucherBatch.Kind.choices)
    quantity = serializers.IntegerField()
    valid_days = serializers.IntegerField()
    course = _id(required=False, allow_null=True)
    package = _id(required=False, allow_null=True)
    teacher = _id(required=False, allow_null=True)
    discount_kind = serializers.CharField(required=False, allow_blank=True, default="")
    discount_value = serializers.IntegerField(required=False, default=0)
    currency = serializers.CharField(required=False, allow_blank=True, default="")
    note = serializers.CharField(
        max_length=NOTE_LENGTH, required=False, allow_blank=True, default=""
    )


class CodeQueryInput(serializers.Serializer):
    # A bad value is a 400 on its field, never silently "everything".
    kind = serializers.ChoiceField(choices=VoucherBatch.Kind.choices, required=False)
    state = serializers.ChoiceField(choices=services.STATES, required=False)
    discount_kind = serializers.ChoiceField(choices=("percent", "fixed"), required=False)
    batch = _id(required=False)
    q = serializers.CharField(required=False, allow_blank=True, default="")
    code = serializers.CharField(required=False, allow_blank=True, default="")


class TargetsInput(serializers.Serializer):
    """Plan V20: user ids for `student`; plain ids otherwise."""

    student = _id(required=False)
    subscription = _id(required=False)
    invoice = _id(required=False)


class CodeTextInput(TargetsInput):
    """Plan V5: no length and no `required`: the service gives every bad
    text the one 400 `vouchers.invalid`."""

    code = serializers.CharField(required=False, allow_blank=True, default="")


class VoidInput(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, default="")


class ReasonInput(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, default="")
```

Create `backend/etqan/vouchers/api/payloads.py`:

```python
"""JSON shapes for vouchers (spec §5, plan V17). Codes always show as
`SYS-XXXXX-XXXXX`; people are user ids."""

from dataclasses import asdict

from etqan.catalogue import services as catalogue_services
from etqan.vouchers import services

# Plan V18: the CSV, spec §5's columns with the discount split in three.
CSV_COLUMNS = (
    ("code", "Code"),
    ("kind", "Type"),
    ("course.name_en", "Course"),
    ("package.name_en", "Package"),
    ("teacher.full_name", "Teacher"),
    ("discount.kind", "Discount type"),
    ("discount.value", "Discount value"),
    ("discount.currency", "Discount currency"),
    ("expires_on", "Expires on"),
    ("state", "Status"),
    ("redeemed_at", "Redeemed at"),
    ("student.full_name", "Student"),
    ("batch.note", "Batch note"),
    ("void_reason", "Void reason"),
)


def _person(user) -> dict | None:
    return None if user is None else {"id": user.pk, "full_name": user.full_name}


def _terms(batch) -> dict:
    return {
        "course": services.named(batch.course),
        "package": services.named(batch.package),
        "teacher": services.teacher_of(batch),
        "sessions_total": (
            catalogue_services.sessions_total(batch.package) if batch.package else None
        ),
        "discount": services.discount_of(batch),
    }


def batch_row(batch) -> dict:
    return {
        "id": batch.pk,
        "kind": batch.kind,
        **_terms(batch),
        "valid_days": batch.valid_days,
        "expires_on": batch.expires_on,
        "quantity": batch.quantity,
        "note": batch.note,
        "created_by": _person(batch.created_by),
        "created_at": batch.created_at,
    }


def code_row(voucher) -> dict:
    """Read ``voucher`` from `services.vouchers_queryset`: it carries
    ``state`` and everything joined."""
    batch = voucher.batch
    return {
        "id": voucher.pk,
        "code": services.display(voucher.code),
        "kind": voucher.kind,
        "state": voucher.state,
        "batch": {"id": batch.pk, "note": batch.note},
        **_terms(batch),
        "expires_on": batch.expires_on,
        "redeemed_at": voucher.redeemed_at,
        "redeemed_by": _person(voucher.redeemed_by),
        "student": _person(voucher.student.user) if voucher.student_id else None,
        "subscription_id": voucher.subscription_id,
        "invoice_id": voucher.invoice_id,
        "void_reason": voucher.void_reason,
        "created_at": voucher.created_at,
    }


def redemption(result) -> dict:
    return asdict(result)


def preview(shown) -> dict:
    return asdict(shown)
```

Create `backend/etqan/vouchers/api/views.py`:

```python
"""Vouchers endpoints (B3f §5). Thin: parse, call one service, answer.
Office routes declare `voucher.*`; the kind's own codes are checked here
past the lookup (plans V9, V19). Family routes are role-gated and scoped by
F-16 in the service; they are throttled per user and per IP (F-13)."""

from rest_framework import generics
from rest_framework import status
from rest_framework.exceptions import NotFound
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform import features
from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import FEATURE_OFF
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import IsParent
from etqan.platform.permissions import IsStudent
from etqan.platform.permissions import NotImpersonating
from etqan.platform.permissions import codes_of
from etqan.platform.permissions import role_of
from etqan.vouchers import services
from etqan.vouchers.api import payloads
from etqan.vouchers.api.serializers import BatchInput
from etqan.vouchers.api.serializers import CodeQueryInput
from etqan.vouchers.api.serializers import CodeTextInput
from etqan.vouchers.api.serializers import ReasonInput
from etqan.vouchers.api.serializers import TargetsInput
from etqan.vouchers.api.serializers import VoidInput
from etqan.vouchers.throttling import VoucherIPThrottle
from etqan.vouchers.throttling import VoucherUserThrottle

FEATURE = "system_codes"
FAMILY = IsParent | IsStudent
THROTTLES = [VoucherUserThrottle, VoucherIPThrottle]
# F-20: what the same manual action needs, beside voucher.update.
KIND_CODES = {
    "activation": ("subscription.create",),
    "renewal": ("subscription.update",),
    "discount": ("payment.create", "invoice.view"),
}
BATCH_FIELDS = {"course": "course_id", "package": "package_id", "teacher": "teacher_user_id"}
TARGETS = {"student": "student_user_id", "subscription": "subscription_id", "invoice": "invoice_id"}


def _need(feature: str) -> None:
    """A second feature a route also needs (F-22): 404 as a missing route."""
    if not features.enabled(feature):
        raise NotFound(FEATURE_OFF)


def _holds(user, code: str) -> bool:
    """Admins hold every code (F-21)."""
    return role_of(user) == "admin" or code in codes_of(user)


def _targets(data: dict) -> dict:
    return {TARGETS[key]: value for key, value in data.items() if key in TARGETS}


def _office_may(request, kind: str) -> None:
    missing = [code for code in KIND_CODES[kind] if not _holds(request.user, code)]
    if missing:
        raise PermissionDenied(f"Redeeming this code also needs {', '.join(missing)}.")
    if kind == "discount":
        _need("invoices")


def _code_row(pk: int) -> dict:
    return payloads.code_row(services.vouchers_queryset(services.today()).get(pk=pk))


class BatchListView(generics.GenericAPIView):
    permission_classes = [HasCode, FeatureOn]
    feature = FEATURE
    permission_codes = {"GET": "voucher.view_any", "POST": "voucher.create"}

    def get(self, request):
        page = self.paginate_queryset(services.batches_queryset())
        return self.get_paginated_response([payloads.batch_row(b) for b in page])

    def post(self, request):
        body = BatchInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = {BATCH_FIELDS.get(k, k): v for k, v in body.validated_data.items()}
        batch = services.generate(**data, by=request.user)
        batch = services.batches_queryset().get(pk=batch.pk)
        return Response(payloads.batch_row(batch), status=status.HTTP_201_CREATED)


class CodeListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [HasCode, FeatureOn]
    feature = FEATURE
    permission_codes = {"GET": "voucher.view_any"}
    csv_columns = payloads.CSV_COLUMNS
    csv_filename = "system-codes"

    def get(self, request):
        query = CodeQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        codes = services.filter_vouchers(
            services.vouchers_queryset(services.today()), **query.validated_data
        )
        if self.wants_csv():
            return self.csv_response([payloads.code_row(c) for c in codes])
        page = self.paginate_queryset(codes)
        return self.get_paginated_response([payloads.code_row(c) for c in page])


class VoidView(APIView):
    permission_classes = [HasCode, FeatureOn]
    feature = FEATURE
    permission_codes = {"POST": "voucher.update"}

    def post(self, request, pk):
        body = VoidInput(data=request.data)
        body.is_valid(raise_exception=True)
        voucher = services.void(pk, by=request.user, **body.validated_data)
        return Response(_code_row(voucher.pk))


class OfficeRedeemView(APIView):
    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "voucher.update"}

    def post(self, request, pk):
        _office_may(request, services.kind_of(voucher_id=pk))
        body = TargetsInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = services.redeem(
            voucher_id=pk, user=request.user, office=True, **_targets(body.validated_data)
        )
        return Response(payloads.redemption(result), status=status.HTTP_201_CREATED)


class OfficeRedeemByCodeView(APIView):
    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "voucher.update"}

    def post(self, request):
        body = CodeTextInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        _office_may(request, services.kind_of(code=data["code"]))
        result = services.redeem(
            code=data["code"], user=request.user, office=True, **_targets(data)
        )
        return Response(payloads.redemption(result), status=status.HTTP_201_CREATED)


class RemoveDiscountView(APIView):
    """F-9: voucher.update and payment.update (checked past the lookup)."""

    permission_classes = [HasCode, FeatureOn, NotImpersonating]
    feature = FEATURE
    permission_codes = {"POST": "voucher.update"}

    def post(self, request, pk):
        _need("invoices")
        services.find(voucher_id=pk)
        if not _holds(request.user, "payment.update"):
            raise PermissionDenied("Removing a discount also needs payment.update.")
        body = ReasonInput(data=request.data)
        body.is_valid(raise_exception=True)
        voucher = services.remove_discount(
            pk, reason=body.validated_data["reason"], by=request.user
        )
        return Response(_code_row(voucher.pk))


class CheckView(APIView):
    """`check/`: what a code is, for a student or a parent (F-13, F-16)."""

    permission_classes = [FAMILY, FeatureOn]
    feature = FEATURE
    throttle_classes = THROTTLES

    def post(self, request):
        body = CodeTextInput(data=request.data)
        body.is_valid(raise_exception=True)
        shown = services.preview(body.validated_data["code"], user=request.user)
        return Response(payloads.preview(shown))


class RedeemView(APIView):
    """`redeem/`: never in a quick-login session (D19)."""

    permission_classes = [FAMILY, NotImpersonating, FeatureOn]
    feature = FEATURE
    throttle_classes = THROTTLES

    def post(self, request):
        body = CodeTextInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        if services.kind_of(code=data["code"]) == "discount":
            _need("invoices")
        result = services.redeem(code=data["code"], user=request.user, **_targets(data))
        return Response(payloads.redemption(result), status=status.HTTP_201_CREATED)
```

Note on `services.find` in `RemoveDiscountView`: `find` raises `vouchers.invalid` for a void code; a void (already removed) discount by id is then a 400, and `remove_discount` answers 409 `vouchers.not_used` for every other non-used row. Both are refusals with a body the dashboard maps.

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/vouchers etqan/access etqan/platform -q`
Expected: PASS (the route matrix: every vouchers route tabled or exempt, each 404 with `system_codes` off past the code check).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/vouchers etqan/access config/settings/base.py config/api_router.py
git -C backend commit -m "feat(vouchers): the system codes API, its throttles and the voucher resource (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 8: Seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/vouchers.py`, `backend/etqan/tenants/tests/test_seed_vouchers.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (an import beside `wallet_seeds`; the call under the B3 marker)

**Interfaces:**
- Consumes: `vouchers.services.generate`, `has_batches`, `batches_queryset`, `vouchers_queryset`, `today`; catalogue's `find_course`, `find_package`; identity's `people_queryset` (plan V16).
- Produces: `etqan.tenants.seeds.vouchers.seed_vouchers(subdomain: str) -> None`.

- [ ] **Step 1: Write the failing test**

Create `backend/etqan/tenants/tests/test_seed_vouchers.py`:

```python
"""B3f §8: the demo academy's two batches (5 activation codes for Quran
Memorisation, "Monthly, 2 a week", Ustadha Maryam; 3 whole-academy 10 %
discount codes), seeded once, nothing redeemed; the other academy gets
nothing."""

import pytest
from django.core.management import call_command
from django.db import connection
from django.test import override_settings
from django_tenants.utils import tenant_context

from etqan.billing import services as billing
from etqan.tenants.models import Academy
from etqan.vouchers import services as vouchers


def batches() -> list[tuple]:
    return [
        (
            b.kind,
            b.quantity,
            b.course.name_en if b.course else None,
            b.package.name_en if b.package else None,
            b.teacher.user.full_name if b.teacher else None,
            b.discount_kind,
            b.discount_value,
            b.currency,
            b.valid_days,
            b.note,
        )
        for b in vouchers.batches_queryset()
    ]


def states() -> list[str]:
    return list(
        vouchers.vouchers_queryset(vouchers.today()).values_list("state", flat=True)
    )


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_adds_the_demo_codes_once_and_redeems_nothing():
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = batches()
        assert first == [
            ("discount", 3, None, None, None, "percent", 10, "", 90, "Demo discount codes"),
            (
                "activation",
                5,
                "Quran Memorisation",
                "Monthly, 2 a week",
                "Ustadha Maryam",
                "",
                0,
                "",
                90,
                "Demo activation codes",
            ),
        ]
        assert states() == ["unused"] * 8
        assert not billing.payments_queryset().filter(method="code").exists()
    with tenant_context(other):
        assert not vouchers.has_batches()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert batches() == first
        assert len(states()) == 8
```

- [ ] **Step 2: Run it to verify it fails**

Run: `$DJ pytest etqan/tenants/tests/test_seed_vouchers.py -q`
Expected: FAIL (`assert [] == [("discount", …), …]`).

- [ ] **Step 3: Implement**

Create `backend/etqan/tenants/seeds/vouchers.py`:

```python
"""Phase B3, slice B3f (spec §8): the demo academy's system codes, two
batches valid for 90 days. Written through vouchers services only; the
course, package and teacher are found through their own services (plan
V16). Skipped once the academy has any batch. Nothing is redeemed, so no
subscription, invoice or revenue changes; no e2e journey reads the codes,
which are random on each fresh seed."""

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.vouchers import services as vouchers_services

COURSE = "Quran Memorisation"
PACKAGE = "Monthly, 2 a week"
TEACHER = "Ustadha Maryam"  # teaches the course (seed_dev PEOPLE)
VALID_DAYS = 90


def seed_vouchers(subdomain: str) -> None:
    if subdomain != "demo" or vouchers_services.has_batches():
        return
    course = catalogue_services.find_course(COURSE)
    package = catalogue_services.find_package(PACKAGE)
    teacher = (
        identity_services.people_queryset("teacher").filter(full_name=TEACHER).first()
    )
    if course is not None and package is not None and teacher is not None:
        vouchers_services.generate(
            kind="activation",
            quantity=5,
            valid_days=VALID_DAYS,
            course_id=course.pk,
            package_id=package.pk,
            teacher_user_id=teacher.pk,
            note="Demo activation codes",
            by=None,
        )
    vouchers_services.generate(
        kind="discount",
        quantity=3,
        valid_days=VALID_DAYS,
        discount_kind="percent",
        discount_value=10,
        note="Demo discount codes",
        by=None,
    )
```

`backend/etqan/tenants/management/commands/seed_dev.py`:
- after `from etqan.tenants.seeds import wallet as wallet_seeds`: `from etqan.tenants.seeds import vouchers as vouchers_seeds` (ruff's isort keeps it next to the other seeds imports);
- in `seed_academy`, under `# ── phase B3 ──`, after `wallet_seeds.seed_wallet(subdomain)`:

```python
        vouchers_seeds.seed_vouchers(subdomain)
```

- [ ] **Step 4: Run the tests, format, lint, commit**

Run: `$DJ pytest etqan/tenants -q`
Expected: PASS (`test_seed_dev`'s revenue figures unchanged: nothing is redeemed).
Run: `$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports`

```bash
git -C backend add etqan/tenants
git -C backend commit -m "feat(tenants): seed the demo academy's system codes (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: Dashboard — billing's "System code", `movable`, the new error texts and `system_codes`

**Files:**
- Modify: `dashboard/src/features/billing/schemas.ts`, `dashboard/src/features/billing/PaymentRecordsPage.tsx`, `dashboard/src/features/billing/InvoicePage.test.tsx`, `dashboard/src/features/billing/InvoicePrint.test.tsx`, `dashboard/src/features/billing/PaymentRecordsPage.test.tsx`, `dashboard/src/features/wallet/MoveToWallet.tsx`, `dashboard/src/features/wallet/MoveToWallet.test.tsx`, `dashboard/src/features/catalogue/CourseForm.test.tsx`, `dashboard/src/features/identity/schemas.ts`, `dashboard/src/test/billing-fixtures.ts`, `dashboard/src/locales/{en,ar}/billing.json`, `dashboard/src/locales/{en,ar}/errors.json`

**Interfaces:**
- Produces:
  - `CODE_METHOD = "code"` in `@/features/billing/schemas`; `Payment.method` gains it; `Payment.movable: boolean`;
  - the label `billing.methods.code` ("System code" / "كود النظام"), shown by `InvoicePage`, `InvoicePrint` and `PaymentRecordsPage` (which already read `billing.methods.<method>`), and the records page's method filter option;
  - `MoveToWallet` shows only for `payment.movable` (it keeps its own feature, code and void checks);
  - `errors.billing.code_payment`, `not_code_payment`, `nothing_due`; `errors.vouchers.*` (V12); the new `errors.catalogue.in_use` (V25);
  - `FeatureCode` gains `"system_codes"`;
  - fixtures: `paymentRow()` carries `movable: true`, `recordRow()` `movable: false`.

- [ ] **Step 1: Write the failing tests**

In `dashboard/src/test/billing-fixtures.ts`, in `paymentRow`'s object after `refundable: true,` add `movable: true,`; in `recordRow`'s overrides after `editable: true,` add `movable: false,`.

In `dashboard/src/features/billing/InvoicePage.test.tsx`, inside `describe("InvoicePage", …)`, add:

```tsx
	it("names a system code's payment and offers nothing on it", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				status: "paid",
				paid_minor: 150000,
				balance_minor: 0,
				payments: [
					paymentRow({
						id: 65,
						method: "code",
						reference: "SYS-ABCDE-FGHJK",
						amount_minor: 150000,
						deletable: false,
						refundable: false,
						movable: false,
					}),
				],
			}),
		);
		renderPage();
		const row = (await screen.findByText(/· System code/)).closest(
			"li",
		) as HTMLElement;
		expect(within(row).getByText(/SYS-ABCDE-FGHJK/)).toBeVisible();
		expect(within(row).queryByRole("button")).toBeNull();
	});
```

In `dashboard/src/features/billing/InvoicePrint.test.tsx`, inside `describe("InvoicePrint", …)`, add:

```tsx
	it("prints a system code's payment by its method's name", async () => {
		vi.mocked(billingApi.get).mockResolvedValue(
			invoiceDetail({
				payments: [paymentRow({ method: "code", reference: "SYS-ABCDE-FGHJK" })],
			}),
		);
		renderWithRouter(<InvoicePrint invoiceId="51" />);
		const sheet = await screen.findByRole("article", { name: "Invoice" });
		expect(
			within(sheet).getByText("Jun 2, 2026 · System code · SYS-ABCDE-FGHJK"),
		).toBeInTheDocument();
	});
```

In `dashboard/src/features/billing/PaymentRecordsPage.test.tsx`, inside `describe("PaymentRecordsPage", …)`, add:

```tsx
	it("lists a system code's payment and filters by that method", async () => {
		vi.mocked(billingApi.records).mockResolvedValue(
			page([
				paymentRow({
					id: 74,
					method: "code",
					transaction_number: "",
					reference: "SYS-ABCDE-FGHJK",
					deletable: false,
					refundable: false,
					movable: false,
				}),
			]),
		);
		const user = userEvent.setup();
		renderWithRouter(<PaymentRecordsPage />, { extraPaths: [DETAIL] });
		const table = await screen.findByRole("table");
		expect(within(table).getByText("System code")).toBeVisible();
		expect(within(table).queryByRole("button")).toBeNull();
		await user.selectOptions(screen.getByLabelText("Method"), "code");
		await waitFor(() => expect(lastParams()).toMatchObject({ method: "code" }));
	});
```

In `dashboard/src/features/wallet/MoveToWallet.test.tsx`, in the `it.each` table of "is not offered for %s", add a row:

```tsx
		[
			"a payment the server marks not movable",
			paymentRow({ movable: false }),
			adminWith("balances"),
		],
```

In `dashboard/src/features/catalogue/CourseForm.test.tsx`, replace the expected English text `"This has subscriptions, so it can't be deleted. Deactivate it instead."` with `"This is used by subscriptions or system codes, so it can't be deleted. Deactivate it instead."`.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/billing src/features/wallet/MoveToWallet.test.tsx src/features/catalogue/CourseForm.test.tsx`
Expected: FAIL (`billing.methods.code` shows its key; the records method filter has no `code` option; `MoveToWallet` still offered when `movable` is false; the old `in_use` text). `just test-frontend` also fails: `movable` is not in `Payment`.

- [ ] **Step 3: Implement**

`dashboard/src/features/billing/schemas.ts`: after `WALLET_METHOD`:

```ts
/** B3f F-5: what a system code paid; never by hand, never revenue. */
export const CODE_METHOD = "code" as const;
```

In `Payment`, replace the `method` line with

```ts
	method:
		| PaymentMethod
		| OnlineMethod
		| typeof WALLET_METHOD
		| typeof CODE_METHOD;
```

and after `refundable: boolean;` add

```ts
	/** B3f F-8: completed, on an invoice and not a code's: Move to balance. */
	movable: boolean;
```

`dashboard/src/features/billing/PaymentRecordsPage.tsx`: import `CODE_METHOD` beside `WALLET_METHOD` and make the method options

```tsx
					[...PAYMENT_METHODS, ...ONLINE_METHODS, WALLET_METHOD, CODE_METHOD].map(
						(m) => [m, t(`billing.methods.${m}`)] as const,
					),
```

`dashboard/src/features/wallet/MoveToWallet.tsx`: replace the guard's

```tsx
		payment.status !== "completed" ||
		payment.invoice === null ||
		payment.wallet_topup ||
```

with

```tsx
		// B3f F-8: the server's flag (completed, on an invoice, not a code's).
		!payment.movable ||
```

and update the doc comment's first line to "B3e §6, E-12, B3f F-8: "Move to balance" on a payment the server marks movable, …".

`dashboard/src/features/identity/schemas.ts`, in `FeatureCode`, after `| "balances"`:

```ts
	// Phase B3, slice B3f.
	| "system_codes"
```

`dashboard/src/locales/en/billing.json`, in `methods`, after `"wallet": "Balance"`: `"code": "System code"`. `dashboard/src/locales/ar/billing.json`, in `methods`, after `"wallet"`: `"code": "كود النظام"`.

`dashboard/src/locales/en/errors.json`:
- `catalogue.in_use`: `"This is used by subscriptions or system codes, so it can't be deleted. Deactivate it instead."`;
- in `billing`, after `"not_topup"`:

```json
		"code_payment": "A system code's payment can't be refunded, deleted or moved.",
		"not_code_payment": "This is not a system code's payment.",
		"nothing_due": "Nothing is due on this invoice."
```

- after the `wallet` object, a new object:

```json
	"vouchers": {
		"invalid": "This code isn't valid.",
		"used": "This code has already been used.",
		"expired": "This code has expired.",
		"unavailable": "This code can't be used right now. Contact the academy.",
		"wrong_course": "This code is for another course.",
		"wrong_package": "This code is for another package.",
		"wrong_currency": "This code is in another currency.",
		"invoice_discounted": "This invoice already has a discount code.",
		"not_unused": "Only an unused code can be voided.",
		"not_used": "This code hasn't been used.",
		"not_discount": "Only a discount code can be removed."
	},
```

`dashboard/src/locales/ar/errors.json`, the same keys:
- `catalogue.in_use`: `"هذا العنصر مستخدم في اشتراكات أو أكواد نظام، فلا يمكن حذفه. عطّله بدلًا من ذلك."`;
- in `billing`:

```json
		"code_payment": "لا يمكن استرداد دفعة كود النظام أو حذفها أو نقلها.",
		"not_code_payment": "هذه ليست دفعة كود نظام.",
		"nothing_due": "لا يوجد مبلغ مستحق على هذه الفاتورة."
```

- after `wallet`:

```json
	"vouchers": {
		"invalid": "هذا الكود غير صالح.",
		"used": "استُخدم هذا الكود من قبل.",
		"expired": "انتهت صلاحية هذا الكود.",
		"unavailable": "لا يمكن استخدام هذا الكود الآن. تواصل مع الأكاديمية.",
		"wrong_course": "هذا الكود لدورة أخرى.",
		"wrong_package": "هذا الكود لباقة أخرى.",
		"wrong_currency": "هذا الكود بعملة أخرى.",
		"invoice_discounted": "على هذه الفاتورة كود خصم بالفعل.",
		"not_unused": "لا يُلغى إلا كود لم يُستخدم.",
		"not_used": "لم يُستخدم هذا الكود.",
		"not_discount": "لا يُزال إلا كود خصم."
	},
```

- [ ] **Step 4: Run the tests, types, format, commit**

Run: `$DASH pnpm vitest run src/features/billing src/features/wallet src/features/catalogue src/locales`
Expected: PASS.
Run: `just test-frontend` and `$DASH pnpm exec biome check --write src e2e`
Expected: clean.

```bash
git -C dashboard add src/features/billing src/features/wallet src/features/catalogue/CourseForm.test.tsx src/features/identity/schemas.ts src/test/billing-fixtures.ts src/locales
git -C dashboard commit -m "feat(billing): the System code method, movable payments and the system codes error texts (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 10: Dashboard — the vouchers feature's base and Billing → System codes

**Files:**
- Create: `dashboard/src/features/vouchers/schemas.ts`, `dashboard/src/features/vouchers/schemas.test.ts`, `dashboard/src/features/vouchers/api.ts`, `dashboard/src/features/vouchers/api.test.ts`, `dashboard/src/features/vouchers/queries.ts`, `dashboard/src/features/vouchers/index.ts`, `dashboard/src/features/vouchers/CodesPage.tsx`, `dashboard/src/features/vouchers/CodesPage.test.tsx`, `dashboard/src/features/vouchers/CodeActions.tsx`, `dashboard/src/features/vouchers/VoidCodeDialog.tsx`, `dashboard/src/features/vouchers/VoidCodeDialog.test.tsx`, `dashboard/src/routes/_authed/billing.codes.tsx`, `dashboard/src/test/voucher-fixtures.ts`, `dashboard/src/locales/en/vouchers.json`, `dashboard/src/locales/ar/vouchers.json`
- Modify: `dashboard/src/features/shell/nav.ts` (B3 marker), `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/permissions.test.ts`; `dashboard/src/routeTree.gen.ts` (generated)

**Interfaces:**
- Consumes: Task 9's error texts and `FeatureCode`; `useListParams`, `pageCount`, `SearchBox`, `saveOrShowErrors`, `useFillOnOpen` from `@/features/finance/shared`; `csvUrl`, `clean` from `@/lib/api`; `billingKey`, `schedulingKey`.
- Produces:
  - types `VoucherKind`, `VoucherState`, `DiscountKind`, `NamedRef`, `PersonRef`, `Discount`, `VoucherRow`, `VoucherBatch`, `StudentChoice`, `RenewalChoice`, `Preview`, `Redemption`, `RedeemTargets`, `GenerateBody`; constants `VOUCHER_KINDS`, `VOUCHER_STATES`, `DISCOUNT_KINDS`; form schemas `generateFormSchema` + `toGenerateBody` (used by Task 11), `codeFormSchema`, `reasonFormSchema(required)`; `discountText(discount, language)`;
  - `vouchersApi` (`batches`, `generate`, `codes`, `void`, `redeemById`, `redeemByCode`, `removeDiscount`, `check`, `redeem`), `codesCsvUrl(params)`;
  - `vouchersKey`, `useBatches(enabled?)`, `useCodes(params)`, `useVoucherByCode(code, enabled)`, `useCheckCode()`, `useVoucherMutation(write)` (refreshes vouchers, billing and scheduling on settle);
  - `CodesPage` (with `onGenerated` wiring added by Task 11), `StateChip`, `CodeActions` (Void here; Task 12 adds Redeem for a student and Remove discount), `VoidCodeDialog`;
  - route `/_authed/billing/codes` (`voucher.view_any`, `system_codes`) and the office nav item (plan V24);
  - fixtures `voucherRow`, `discountRow`, `voucherBatch`, `codePreview`, `redemption` in `src/test/voucher-fixtures.ts`;
  - every `vouchers.*` string Tasks 10–14 use.

- [ ] **Step 1: Write the strings, fixtures and failing tests**

Create `dashboard/src/locales/en/vouchers.json`:

```json
{
	"nav": "System codes",
	"kinds": {
		"activation": "Activation",
		"renewal": "Renewal",
		"discount": "Discount"
	},
	"states": {
		"unused": "Not used yet",
		"used": "Used",
		"expired": "Expired",
		"void": "Void"
	},
	"discountKinds": {
		"percent": "Percentage",
		"fixed": "Fixed amount"
	},
	"facts": {
		"course": "Course",
		"package": "Package",
		"sessions": "Sessions",
		"teacher": "Teacher",
		"discount": "Discount",
		"expires": "Valid until"
	},
	"list": {
		"search": "Search codes",
		"kind": "Code type",
		"state": "Status",
		"discountKind": "Discount type",
		"batch": "Batch",
		"all": "All",
		"untitled": "Batch {{id}}",
		"empty": "No codes yet.",
		"loadError": "The codes could not be loaded.",
		"columns": {
			"code": "Code",
			"kind": "Type",
			"terms": "Course · package",
			"teacher": "Teacher",
			"discount": "Discount",
			"expires": "Expiry",
			"state": "Status",
			"redeemed": "Redeemed"
		},
		"redeemedBy": "{{student}} on {{date}}",
		"openSubscription": "Subscription",
		"openInvoice": "Invoice",
		"voidReason": "Reason: {{reason}}",
		"copy": "Copy {{code}}",
		"copied": "Code copied."
	},
	"generate": {
		"action": "Generate codes",
		"title": "Generate codes",
		"body": "Codes share these terms. A family redeems each code once.",
		"kind": "Code type",
		"course": "Course",
		"package": "Package",
		"teacher": "Teacher",
		"anyCourse": "Any course",
		"anyPackage": "Any package",
		"quantity": "Number of codes",
		"validDays": "Valid for (days)",
		"discountKind": "Discount type",
		"percent": "Percentage",
		"amount": "Amount",
		"currency": "Currency",
		"note": "Note",
		"sessions": "This package has {{count}} sessions.",
		"save": "Generate",
		"done": "Codes generated."
	},
	"void": {
		"action": "Void",
		"title": "Void this code",
		"body": "{{code}} can never be redeemed after this. Its row stays for the record.",
		"reason": "Reason (optional)",
		"save": "Void code",
		"done": "Code voided."
	},
	"redeem": {
		"action": "Redeem for a student",
		"title": "Redeem {{code}} for a student",
		"findStudent": "Find a student",
		"student": "Student",
		"subscription": "Subscription",
		"choice": "{{course}} — {{package}} · ends {{date}}",
		"noRenewable": "This student has no subscription this code can renew.",
		"save": "Redeem",
		"done": "Code redeemed."
	},
	"remove": {
		"action": "Remove discount",
		"title": "Remove this discount",
		"body": "The discount's payment is deleted and the invoice owes that amount again. The code becomes void and is never used again.",
		"reason": "Reason",
		"save": "Remove discount",
		"done": "Discount removed."
	},
	"apply": {
		"action": "Apply a code",
		"title": "Apply a discount code",
		"body": "The discount is taken off what is still owed on this invoice.",
		"code": "Code",
		"save": "Apply",
		"done": "Discount of {{amount}} applied."
	},
	"family": {
		"nav": "Redeem a code",
		"title": "Redeem a code",
		"intro": "Enter the code the academy gave you.",
		"code": "Code",
		"check": "Check",
		"titles": {
			"activation": "This code starts a subscription",
			"renewal": "This code renews a subscription",
			"discount": "This code is a discount on an invoice"
		},
		"student": "Student",
		"subscription": "Subscription to renew",
		"renewalChoice": "{{student}} · {{course}} — {{package}} · renews at {{price}}",
		"noStudents": "There is no active student to start this subscription for.",
		"noRenewable": "None of your subscriptions can be renewed with this code. It renews a {{course}} subscription that is active, paused or expired and not renewed yet.",
		"discountHint": "Open the invoice you want to reduce and apply the code there.",
		"myInvoices": "My invoices",
		"redeem": "Redeem",
		"started": "Your subscription has started. The academy will set your lesson times.",
		"renewed": "The subscription is renewed. The code paid its invoice.",
		"mySubscriptions": "My subscriptions",
		"another": "Enter another code"
	},
	"errors": {
		"required": "Fill this in.",
		"quantity": "Make 1 to 500 codes at a time.",
		"validDays": "Enter 1 to 3650 days.",
		"percent": "Enter a percentage from 1 to 100.",
		"amount": "Enter an amount above zero.",
		"currency": "Choose a currency.",
		"noteTooLong": "Use at most 200 characters.",
		"codeRequired": "Enter the code.",
		"reasonRequired": "Say why.",
		"reasonTooLong": "Use at most 200 characters.",
		"throttled": "Too many tries. Wait a while and try again."
	}
}
```

Create `dashboard/src/locales/ar/vouchers.json`:

```json
{
	"nav": "أكواد النظام",
	"kinds": {
		"activation": "تفعيل",
		"renewal": "تجديد",
		"discount": "خصم"
	},
	"states": {
		"unused": "لم يُستخدم بعد",
		"used": "مستخدم",
		"expired": "منتهي الصلاحية",
		"void": "ملغى"
	},
	"discountKinds": {
		"percent": "نسبة مئوية",
		"fixed": "مبلغ ثابت"
	},
	"facts": {
		"course": "الدورة",
		"package": "الباقة",
		"sessions": "الحصص",
		"teacher": "المعلم",
		"discount": "الخصم",
		"expires": "صالح حتى"
	},
	"list": {
		"search": "ابحث في الأكواد",
		"kind": "نوع الكود",
		"state": "الحالة",
		"discountKind": "نوع الخصم",
		"batch": "الدفعة",
		"all": "الكل",
		"untitled": "الدفعة {{id}}",
		"empty": "لا توجد أكواد بعد.",
		"loadError": "تعذّر تحميل الأكواد.",
		"columns": {
			"code": "الكود",
			"kind": "النوع",
			"terms": "الدورة · الباقة",
			"teacher": "المعلم",
			"discount": "الخصم",
			"expires": "تاريخ الانتهاء",
			"state": "الحالة",
			"redeemed": "الاستخدام"
		},
		"redeemedBy": "{{student}} في {{date}}",
		"openSubscription": "الاشتراك",
		"openInvoice": "الفاتورة",
		"voidReason": "السبب: {{reason}}",
		"copy": "انسخ {{code}}",
		"copied": "نُسخ الكود."
	},
	"generate": {
		"action": "إنشاء أكواد",
		"title": "إنشاء أكواد",
		"body": "تشترك الأكواد في هذه الشروط، وتستخدم العائلة كل كود مرة واحدة.",
		"kind": "نوع الكود",
		"course": "الدورة",
		"package": "الباقة",
		"teacher": "المعلم",
		"anyCourse": "أي دورة",
		"anyPackage": "أي باقة",
		"quantity": "عدد الأكواد",
		"validDays": "مدة الصلاحية (أيام)",
		"discountKind": "نوع الخصم",
		"percent": "النسبة المئوية",
		"amount": "المبلغ",
		"currency": "العملة",
		"note": "ملاحظة",
		"sessions": "في هذه الباقة {{count}} حصة.",
		"save": "إنشاء",
		"done": "أُنشئت الأكواد."
	},
	"void": {
		"action": "إلغاء",
		"title": "إلغاء هذا الكود",
		"body": "لن يمكن استخدام {{code}} بعد ذلك، ويبقى سجله للرجوع إليه.",
		"reason": "السبب (اختياري)",
		"save": "إلغاء الكود",
		"done": "أُلغي الكود."
	},
	"redeem": {
		"action": "استخدام لطالب",
		"title": "استخدام {{code}} لطالب",
		"findStudent": "ابحث عن طالب",
		"student": "الطالب",
		"subscription": "الاشتراك",
		"choice": "{{course}} — {{package}} · ينتهي {{date}}",
		"noRenewable": "ليس لهذا الطالب اشتراك يمكن تجديده بهذا الكود.",
		"save": "استخدام",
		"done": "استُخدم الكود."
	},
	"remove": {
		"action": "إزالة الخصم",
		"title": "إزالة هذا الخصم",
		"body": "تُحذف دفعة الخصم ويعود المبلغ مستحقًا على الفاتورة، ويصبح الكود ملغى فلا يُستخدم مرة أخرى.",
		"reason": "السبب",
		"save": "إزالة الخصم",
		"done": "أُزيل الخصم."
	},
	"apply": {
		"action": "استخدام كود",
		"title": "استخدام كود خصم",
		"body": "يُخصم المبلغ مما بقي مستحقًا على هذه الفاتورة.",
		"code": "الكود",
		"save": "تطبيق",
		"done": "طُبّق خصم بقيمة {{amount}}."
	},
	"family": {
		"nav": "استخدام كود",
		"title": "استخدام كود",
		"intro": "أدخل الكود الذي أعطتك إياه الأكاديمية.",
		"code": "الكود",
		"check": "تحقّق",
		"titles": {
			"activation": "هذا الكود يبدأ اشتراكًا",
			"renewal": "هذا الكود يجدّد اشتراكًا",
			"discount": "هذا الكود خصم على فاتورة"
		},
		"student": "الطالب",
		"subscription": "الاشتراك المراد تجديده",
		"renewalChoice": "{{student}} · {{course}} — {{package}} · يُجدَّد بمبلغ {{price}}",
		"noStudents": "لا يوجد طالب نشط لبدء هذا الاشتراك له.",
		"noRenewable": "لا يمكن تجديد أي من اشتراكاتك بهذا الكود. فهو يجدّد اشتراكًا في {{course}} نشطًا أو موقوفًا أو منتهيًا ولم يُجدَّد بعد.",
		"discountHint": "افتح الفاتورة التي تريد تخفيضها واستخدم الكود فيها.",
		"myInvoices": "فواتيري",
		"redeem": "استخدام",
		"started": "بدأ اشتراكك. ستحدّد الأكاديمية مواعيد حصصك.",
		"renewed": "جُدّد الاشتراك، ودفع الكود فاتورته.",
		"mySubscriptions": "اشتراكاتي",
		"another": "أدخل كودًا آخر"
	},
	"errors": {
		"required": "املأ هذا الحقل.",
		"quantity": "أنشئ من ١ إلى ٥٠٠ كود في المرة الواحدة.",
		"validDays": "أدخل من ١ إلى ٣٦٥٠ يومًا.",
		"percent": "أدخل نسبة من ١ إلى ١٠٠.",
		"amount": "أدخل مبلغًا أكبر من صفر.",
		"currency": "اختر عملة.",
		"noteTooLong": "استخدم ٢٠٠ حرف على الأكثر.",
		"codeRequired": "أدخل الكود.",
		"reasonRequired": "اذكر السبب.",
		"reasonTooLong": "استخدم ٢٠٠ حرف على الأكثر.",
		"throttled": "محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى."
	}
}
```

Create `dashboard/src/test/voucher-fixtures.ts`:

```ts
import type {
	Preview,
	Redemption,
	VoucherBatch,
	VoucherRow,
} from "@/features/vouchers/schemas";

/** API-shaped vouchers rows (spec §5). An unused activation code. */
export function voucherRow(overrides: Partial<VoucherRow> = {}): VoucherRow {
	return {
		id: 91,
		code: "SYS-ABCDE-FGHJK",
		kind: "activation",
		state: "unused",
		batch: { id: 5, note: "June flyers" },
		course: { id: 3, name_en: "Tajweed", name_ar: "تجويد" },
		package: { id: 4, name_en: "Monthly", name_ar: "شهري" },
		teacher: { id: 21, full_name: "Bilal" },
		sessions_total: 8,
		discount: null,
		expires_on: "2026-06-30",
		redeemed_at: null,
		redeemed_by: null,
		student: null,
		subscription_id: null,
		invoice_id: null,
		void_reason: "",
		created_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

/** A whole-academy 10 % discount code. */
export function discountRow(overrides: Partial<VoucherRow> = {}): VoucherRow {
	return voucherRow({
		id: 92,
		code: "SYS-DSC0N-12345",
		kind: "discount",
		batch: { id: 6, note: "Ramadan" },
		course: null,
		package: null,
		teacher: null,
		sessions_total: null,
		discount: { kind: "percent", value: 10, currency: "" },
		...overrides,
	});
}

export function voucherBatch(overrides: Partial<VoucherBatch> = {}): VoucherBatch {
	return {
		id: 5,
		kind: "activation",
		course: { id: 3, name_en: "Tajweed", name_ar: "تجويد" },
		package: { id: 4, name_en: "Monthly", name_ar: "شهري" },
		teacher: { id: 21, full_name: "Bilal" },
		sessions_total: 8,
		discount: null,
		valid_days: 30,
		expires_on: "2026-06-30",
		quantity: 2,
		note: "June flyers",
		created_by: { id: 1, full_name: "Amina" },
		created_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

/** What `check/` answers for an activation code (plan V14). */
export function codePreview(overrides: Partial<Preview> = {}): Preview {
	return {
		code: "SYS-ABCDE-FGHJK",
		kind: "activation",
		course: { id: 3, name_en: "Tajweed", name_ar: "تجويد" },
		package: { id: 4, name_en: "Monthly", name_ar: "شهري" },
		sessions_total: 8,
		teacher: { id: 21, full_name: "Bilal" },
		discount: null,
		expires_on: "2026-06-30",
		students: [{ id: 11, name: "Yusuf" }],
		subscriptions: [],
		...overrides,
	};
}

export function redemption(overrides: Partial<Redemption> = {}): Redemption {
	return {
		kind: "activation",
		subscription_id: 7,
		invoice_id: 51,
		amount_minor: 150000,
		currency: "EGP",
		...overrides,
	};
}
```

Create `dashboard/src/features/vouchers/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	codeFormSchema,
	discountText,
	type GenerateFormValues,
	generateFormSchema,
	reasonFormSchema,
	toGenerateBody,
} from "./schemas";

const base: GenerateFormValues = {
	kind: "activation",
	course: "3",
	package: "4",
	teacher: "21",
	quantity: "2",
	valid_days: "30",
	discount_kind: "percent",
	discount_value: "",
	currency: "EGP",
	note: " June flyers ",
};

const issues = (values: GenerateFormValues) => {
	const parsed = generateFormSchema.safeParse(values);
	return parsed.success
		? {}
		: Object.fromEntries(
				parsed.error.issues.map((i) => [i.path.join("."), i.message]),
			);
};

describe("generateFormSchema", () => {
	it("needs a course, a package and a teacher for an activation", () => {
		expect(issues({ ...base, course: "", package: "", teacher: "" })).toEqual({
			course: "vouchers.errors.required",
			package: "vouchers.errors.required",
			teacher: "vouchers.errors.required",
		});
		expect(issues({ ...base, kind: "renewal", teacher: "" })).toEqual({});
		expect(
			issues({ ...base, kind: "discount", course: "", package: "", teacher: "", discount_value: "10" }),
		).toEqual({});
	});

	it("checks the quantity, the validity and the discount", () => {
		expect(issues({ ...base, quantity: "0", valid_days: "3651" })).toEqual({
			quantity: "vouchers.errors.quantity",
			valid_days: "vouchers.errors.validDays",
		});
		const discount = { ...base, kind: "discount" as const };
		expect(issues({ ...discount, discount_value: "101" })).toEqual({
			discount_value: "vouchers.errors.percent",
		});
		expect(
			issues({ ...discount, discount_kind: "fixed", discount_value: "5.001", currency: "EGP" }),
		).toEqual({ discount_value: "vouchers.errors.amount" });
		expect(
			issues({ ...discount, discount_kind: "fixed", discount_value: "50", currency: "" }),
		).toEqual({ currency: "vouchers.errors.currency" });
	});
});

describe("toGenerateBody", () => {
	it("sends what the kind names, a fixed amount in minor units", () => {
		expect(toGenerateBody(base)).toEqual({
			kind: "activation",
			quantity: 2,
			valid_days: 30,
			course: 3,
			package: 4,
			teacher: 21,
			note: "June flyers",
		});
		expect(
			toGenerateBody({
				...base,
				kind: "discount",
				course: "",
				package: "4",
				teacher: "21",
				discount_kind: "fixed",
				discount_value: "50.50",
				currency: "USD",
			}),
		).toEqual({
			kind: "discount",
			quantity: 2,
			valid_days: 30,
			package: 4,
			discount_kind: "fixed",
			discount_value: 5050,
			currency: "USD",
			note: "June flyers",
		});
		expect(
			toGenerateBody({ ...base, kind: "discount", discount_value: "10" }),
		).toMatchObject({ discount_kind: "percent", discount_value: 10 });
		expect(toGenerateBody({ ...base, kind: "discount", discount_value: "10" })).not.toHaveProperty("currency");
	});
});

describe("the small forms", () => {
	it("needs a code, and a reason only where one is required", () => {
		expect(codeFormSchema.safeParse({ code: "  " }).success).toBe(false);
		expect(codeFormSchema.safeParse({ code: "sys abcde" }).success).toBe(true);
		expect(reasonFormSchema(true).safeParse({ reason: " " }).success).toBe(false);
		expect(reasonFormSchema(false).safeParse({ reason: "" }).success).toBe(true);
		expect(reasonFormSchema(false).safeParse({ reason: "x".repeat(201) }).success).toBe(false);
	});

	it("shows a discount as a percentage or money", () => {
		expect(discountText({ kind: "percent", value: 10, currency: "" }, "en")).toBe("10%");
		expect(discountText({ kind: "fixed", value: 5000, currency: "USD" }, "en")).toBe("$50.00");
	});
});
```

Create `dashboard/src/features/vouchers/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { codesCsvUrl, vouchersApi } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	return {
		...actual,
		api: { get: vi.fn(), post: vi.fn(), defaults: { baseURL: "/api/v1/" } },
	};
});

describe("vouchersApi", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(api.get).mockResolvedValue({ data: { results: [] } });
		vi.mocked(api.post).mockResolvedValue({ data: {} });
	});

	it("reads and writes spec §5's routes", async () => {
		await vouchersApi.codes({ kind: "discount", q: "" });
		expect(api.get).toHaveBeenCalledWith("vouchers/codes/", { params: { kind: "discount" } });
		await vouchersApi.batches({ page_size: 100 });
		expect(api.get).toHaveBeenCalledWith("vouchers/batches/", { params: { page_size: "100" } });
		await vouchersApi.generate({ kind: "discount", quantity: 1, valid_days: 30 });
		expect(api.post).toHaveBeenCalledWith("vouchers/batches/", { kind: "discount", quantity: 1, valid_days: 30 });
		await vouchersApi.void({ id: 9, reason: "Leaked" });
		expect(api.post).toHaveBeenCalledWith("vouchers/codes/9/void/", { reason: "Leaked" });
		await vouchersApi.redeemById({ id: 9, student: 11 });
		expect(api.post).toHaveBeenCalledWith("vouchers/codes/9/redeem/", { student: 11 });
		await vouchersApi.redeemByCode({ code: "SYS-A", invoice: 51 });
		expect(api.post).toHaveBeenCalledWith("vouchers/codes/redeem/", { code: "SYS-A", invoice: 51 });
		await vouchersApi.removeDiscount({ id: 9, reason: "Wrong" });
		expect(api.post).toHaveBeenCalledWith("vouchers/codes/9/remove-discount/", { reason: "Wrong" });
		await vouchersApi.check("sys a");
		expect(api.post).toHaveBeenCalledWith("vouchers/check/", { code: "sys a" });
		await vouchersApi.redeem({ code: "sys a", subscription: 7 });
		expect(api.post).toHaveBeenCalledWith("vouchers/redeem/", { code: "sys a", subscription: 7 });
	});

	it("exports the filtered list without paging", () => {
		expect(codesCsvUrl({ kind: "discount", page: 2 })).toMatch(
			/vouchers\/codes\/\?kind=discount&format=csv$/,
		);
	});
});
```

Create `dashboard/src/features/vouchers/CodesPage.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { academyApi } from "@/features/academy/api";
import { CanProvider } from "@/features/identity/permissions";
import i18n from "@/lib/i18n";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { discountRow, voucherBatch, voucherRow } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { CodesPage } from "./CodesPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		vouchersApi: { ...actual.vouchersApi, codes: vi.fn(), batches: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

const lastParams = () => vi.mocked(vouchersApi.codes).mock.calls.at(-1)?.[0];
const LINKS = ["/scheduling/subscriptions/$subscriptionId", "/billing/invoices/$invoiceId"];

function renderPage(me = staffMe("voucher.view_any", "voucher.update")) {
	return renderWithRouter(
		<CanProvider me={{ ...me, features: ["system_codes", "invoices", "export"] }}>
			<CodesPage />
		</CanProvider>,
		{ extraPaths: LINKS },
	);
}

describe("CodesPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings({ timezone: "Asia/Tokyo" }));
		vi.mocked(vouchersApi.batches).mockResolvedValue(page([voucherBatch()]));
		vi.mocked(vouchersApi.codes).mockResolvedValue(
			page([
				voucherRow({
					state: "used",
					redeemed_at: "2026-06-03T21:30:00Z",
					redeemed_by: { id: 30, full_name: "Zainab" },
					student: { id: 11, full_name: "Yusuf" },
					subscription_id: 7,
					invoice_id: 51,
				}),
				discountRow({ state: "expired" }),
				voucherRow({ id: 93, code: "SYS-VVVVV-00000", state: "void", void_reason: "Leaked" }),
			]),
		);
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("lists each code with its terms, state and redemption", async () => {
		renderPage();
		const table = await screen.findByRole("table");
		const used = within(table).getByText("SYS-ABCDE-FGHJK").closest("tr") as HTMLElement;
		expect(within(used).getByText("Activation")).toBeVisible();
		expect(within(used).getByText("Tajweed · Monthly")).toBeVisible();
		expect(within(used).getByText("Bilal")).toBeVisible();
		expect(within(used).getByText("Jun 30, 2026")).toBeVisible();
		expect(within(used).getByText("Used")).toBeVisible();
		// Asia/Tokyo: 21:30 UTC on 3 June is 4 June there.
		expect(await within(used).findByText("Yusuf on Jun 4, 2026")).toBeVisible();
		expect(within(used).getByRole("link", { name: "Subscription" })).toBeVisible();
		expect(within(used).getByRole("link", { name: "Invoice" })).toBeVisible();
		const gift = within(table).getByText("SYS-DSC0N-12345").closest("tr") as HTMLElement;
		expect(within(gift).getByText("10%")).toBeVisible();
		expect(within(gift).getByText("Expired")).toBeVisible();
		const voided = within(table).getByText("SYS-VVVVV-00000").closest("tr") as HTMLElement;
		expect(within(voided).getByText("Reason: Leaked")).toBeVisible();
		expect(within(table).getByText("SYS-ABCDE-FGHJK")).toHaveAttribute("dir", "ltr");
	});

	it("passes its filters to the server and resets to page 1", async () => {
		const user = userEvent.setup();
		renderPage();
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Code type"), "discount");
		await waitFor(() => expect(lastParams()).toMatchObject({ kind: "discount", page: 1 }));
		await user.selectOptions(screen.getByLabelText("Status"), "expired");
		await waitFor(() => expect(lastParams()).toMatchObject({ state: "expired" }));
		await user.selectOptions(screen.getByLabelText("Discount type"), "fixed");
		await waitFor(() => expect(lastParams()).toMatchObject({ discount_kind: "fixed" }));
		await screen.findByRole("option", { name: "June flyers · Activation" });
		await user.selectOptions(screen.getByLabelText("Batch"), "5");
		await waitFor(() => expect(lastParams()).toMatchObject({ batch: "5" }));
		await user.type(screen.getByLabelText("Search codes"), "yusuf");
		await waitFor(() => expect(lastParams()).toMatchObject({ q: "yusuf" }));
		expect(screen.getByRole("link", { name: "Export CSV" })).toHaveAttribute(
			"href",
			expect.stringMatching(/vouchers\/codes\/\?.*kind=discount.*format=csv$/),
		);
	});

	it("copies a code", async () => {
		const user = userEvent.setup();
		const writeText = vi.spyOn(navigator.clipboard, "writeText");
		renderPage();
		await user.click(await screen.findByRole("button", { name: "Copy SYS-ABCDE-FGHJK" }));
		await waitFor(() => expect(writeText).toHaveBeenCalledWith("SYS-ABCDE-FGHJK"));
		expect(await screen.findByText("Code copied.")).toBeVisible();
	});

	it("offers Void on unused and expired codes to voucher.update only", async () => {
		vi.mocked(vouchersApi.codes).mockResolvedValue(
			page([voucherRow(), discountRow({ state: "expired" }), voucherRow({ id: 94, code: "SYS-UUUUU-11111", state: "used" })]),
		);
		const { unmount } = renderPage();
		const table = await screen.findByRole("table");
		expect(within(table).getAllByRole("button", { name: "Void" })).toHaveLength(2);
		const used = within(table).getByText("SYS-UUUUU-11111").closest("tr") as HTMLElement;
		expect(within(used).queryByRole("button", { name: "Void" })).toBeNull();
		unmount();
		renderPage(staffMe("voucher.view_any"));
		await screen.findByText("SYS-UUUUU-11111");
		expect(screen.queryByRole("button", { name: "Void" })).toBeNull();
	});

	it("says when there are none or the list failed", async () => {
		vi.mocked(vouchersApi.codes).mockResolvedValue(page([]));
		const { unmount } = renderPage();
		expect(await screen.findByText("No codes yet.")).toBeVisible();
		unmount();
		vi.mocked(vouchersApi.codes).mockRejectedValue(new Error("down"));
		renderPage();
		expect(await screen.findByText("The codes could not be loaded.")).toBeVisible();
	});

	it("reads in Arabic with the code kept left to right", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		renderPage();
		const table = await screen.findByRole("table");
		expect(within(table).getByText("تجويد · شهري")).toBeVisible();
		expect(within(table).getByText("مستخدم")).toBeVisible();
		expect(within(table).getByText("SYS-ABCDE-FGHJK")).toHaveAttribute("dir", "ltr");
	});
});
```

Create `dashboard/src/features/vouchers/VoidCodeDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { voucherRow } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { VoidCodeDialog } from "./VoidCodeDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, vouchersApi: { ...actual.vouchersApi, void: vi.fn() } };
});

describe("VoidCodeDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(vouchersApi.void).mockResolvedValue(voucherRow({ state: "void" }));
	});

	it("voids a code with an optional reason", async () => {
		const user = userEvent.setup();
		renderWithRouter(<VoidCodeDialog row={voucherRow()} />);
		await user.click(screen.getByRole("button", { name: "Void" }));
		const dialog = await screen.findByRole("dialog");
		expect(dialog).toHaveTextContent("SYS-ABCDE-FGHJK can never be redeemed after this.");
		await user.type(within(dialog).getByLabelText(/^Reason/), "  Posted online ");
		await user.click(within(dialog).getByRole("button", { name: "Void code" }));
		await waitFor(() =>
			expect(vouchersApi.void).toHaveBeenCalledWith({ id: 91, reason: "Posted online" }),
		);
		expect(await screen.findByText("Code voided.")).toBeVisible();
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
	});

	it("says why the server refused and refreshes anyway", async () => {
		vi.mocked(vouchersApi.void).mockRejectedValueOnce(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "vouchers.not_unused" },
			} as never),
		);
		const user = userEvent.setup();
		const { client } = renderWithRouter(<VoidCodeDialog row={voucherRow()} />);
		const spy = vi.spyOn(client, "invalidateQueries");
		await user.click(screen.getByRole("button", { name: "Void" }));
		await user.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Void code" }));
		expect(await screen.findByText("Only an unused code can be voided.")).toBeVisible();
		await waitFor(() => {
			const keys = spy.mock.calls.map((c) => c[0]?.queryKey?.[0]);
			expect(keys).toEqual(expect.arrayContaining(["vouchers", "billing", "scheduling"]));
		});
	});
});
```

In `dashboard/src/routes/permissions.test.ts`: in `FEATURE_SCREENS`, after `"/_authed/learning/wallet": "balances", // B3e`, add `"/_authed/billing/codes": "system_codes", // B3f`; in `FEATURE_WORDS`, add `|codes` after `|wallet`.

In `dashboard/src/features/shell/nav.test.ts`:
- "ships the grouped admin areas in order": insert `"/billing/codes",` after `"/billing/local-methods",`;
- "hides the items of every feature the academy has switched off": add `"/billing/codes",` after `"/billing/local-methods",`;
- "names a feature on exactly the items that belong to one": add `"/billing/codes": "system_codes",` after `"/billing/local-methods": "invoices",`;
- "groups consecutive items": `groups[2]`'s labels gain `"vouchers.nav",` after `"billing.local.nav",`.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/vouchers src/features/shell/nav.test.ts src/routes/permissions.test.ts src/locales`
Expected: FAIL (`Cannot find module './schemas'`, `'./CodesPage'`; no `/billing/codes` nav item or route).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/vouchers/schemas.ts`:

```ts
import { z } from "zod";
import { formatMoney, minorDigits, toMinor } from "@/lib/money";

/** B3f F-2: the three kinds, as observed. */
export const VOUCHER_KINDS = ["activation", "renewal", "discount"] as const;
export type VoucherKind = (typeof VOUCHER_KINDS)[number];
/** F-10: `expired` is derived on the server. */
export const VOUCHER_STATES = ["unused", "used", "expired", "void"] as const;
export type VoucherState = (typeof VOUCHER_STATES)[number];
export const DISCOUNT_KINDS = ["percent", "fixed"] as const;
export type DiscountKind = (typeof DISCOUNT_KINDS)[number];

export interface NamedRef {
	id: number;
	name_en: string;
	name_ar: string;
}
/** A person by user id. */
export interface PersonRef {
	id: number;
	full_name: string;
}
export interface Discount {
	kind: DiscountKind;
	/** A percent, or minor units of `currency`. */
	value: number;
	currency: string;
}

interface Terms {
	course: NamedRef | null;
	package: NamedRef | null;
	teacher: PersonRef | null;
	sessions_total: number | null;
	discount: Discount | null;
}

/** Spec §5: one code as the office sees it (`SYS-XXXXX-XXXXX`). */
export interface VoucherRow extends Terms {
	id: number;
	code: string;
	kind: VoucherKind;
	state: VoucherState;
	batch: { id: number; note: string };
	expires_on: string;
	redeemed_at: string | null;
	redeemed_by: PersonRef | null;
	student: PersonRef | null;
	subscription_id: number | null;
	invoice_id: number | null;
	void_reason: string;
	created_at: string;
}

export interface VoucherBatch extends Terms {
	id: number;
	kind: VoucherKind;
	valid_days: number;
	expires_on: string;
	quantity: number;
	note: string;
	created_by: PersonRef | null;
	created_at: string;
}

export interface StudentChoice {
	id: number;
	name: string;
}
/** Plan V15: the price the renewal will take. */
export interface RenewalChoice {
	subscription_id: number;
	student: StudentChoice;
	course: NamedRef;
	package: NamedRef;
	term_ends_on: string;
	price_minor: number;
	currency: string;
}
/** `check/` (plan V14). */
export interface Preview extends Terms {
	code: string;
	kind: VoucherKind;
	expires_on: string;
	students: StudentChoice[];
	subscriptions: RenewalChoice[];
}
export interface Redemption {
	kind: VoucherKind;
	subscription_id: number | null;
	invoice_id: number | null;
	amount_minor: number;
	currency: string;
}
/** `student` is a user id. */
export interface RedeemTargets {
	student?: number;
	subscription?: number;
	invoice?: number;
}
export interface GenerateBody {
	kind: VoucherKind;
	quantity: number;
	valid_days: number;
	course?: number;
	package?: number;
	teacher?: number;
	discount_kind?: DiscountKind;
	discount_value?: number;
	currency?: string;
	note?: string;
}

/** A discount as the reader reads it: "10%" or "$50.00". */
export function discountText(discount: Discount, language: string): string {
	return discount.kind === "percent"
		? new Intl.NumberFormat(language, { style: "percent" }).format(
				discount.value / 100,
			)
		: formatMoney(discount.value, discount.currency, language);
}

// Form schemas. Messages are i18n keys, translated by `useFieldError`.
const whole = (min: number, max: number) => (value: string) =>
	/^\d+$/.test(value.trim()) && Number(value) >= min && Number(value) <= max;

export const generateFormSchema = z
	.object({
		kind: z.enum(VOUCHER_KINDS),
		course: z.string(),
		package: z.string(),
		teacher: z.string(),
		quantity: z.string().refine(whole(1, 500), "vouchers.errors.quantity"),
		valid_days: z.string().refine(whole(1, 3650), "vouchers.errors.validDays"),
		discount_kind: z.enum(DISCOUNT_KINDS),
		discount_value: z.string(),
		currency: z.string(),
		note: z.string().max(200, "vouchers.errors.noteTooLong"),
	})
	.superRefine((v, ctx) => {
		const need = (path: "course" | "package" | "teacher") => {
			if (!v[path]) {
				ctx.addIssue({ code: "custom", path: [path], message: "vouchers.errors.required" });
			}
		};
		// F-3: a discount's course and package are optional.
		if (v.kind !== "discount") {
			need("course");
			need("package");
		}
		if (v.kind === "activation") need("teacher");
		if (v.kind !== "discount") return;
		if (v.discount_kind === "percent") {
			if (!whole(1, 100)(v.discount_value)) {
				ctx.addIssue({
					code: "custom",
					path: ["discount_value"],
					message: "vouchers.errors.percent",
				});
			}
			return;
		}
		if (!/^[A-Z]{3}$/.test(v.currency)) {
			ctx.addIssue({ code: "custom", path: ["currency"], message: "vouchers.errors.currency" });
			return;
		}
		const digits = minorDigits(v.currency);
		const pattern =
			digits > 0 ? new RegExp(`^\\d+(\\.\\d{1,${digits}})?$`) : /^\d+$/;
		if (!pattern.test(v.discount_value.trim()) || Number(v.discount_value) <= 0) {
			ctx.addIssue({ code: "custom", path: ["discount_value"], message: "vouchers.errors.amount" });
		}
	});
export type GenerateFormValues = z.infer<typeof generateFormSchema>;

/** The batch body (spec §5): what the kind names; a fixed amount in minor
 * units of its currency. */
export function toGenerateBody(values: GenerateFormValues): GenerateBody {
	const body: GenerateBody = {
		kind: values.kind,
		quantity: Number(values.quantity),
		valid_days: Number(values.valid_days),
		note: values.note.trim(),
	};
	if (values.course) body.course = Number(values.course);
	if (values.package) body.package = Number(values.package);
	if (values.kind === "activation") body.teacher = Number(values.teacher);
	if (values.kind === "discount") {
		body.discount_kind = values.discount_kind;
		if (values.discount_kind === "percent") {
			body.discount_value = Number(values.discount_value);
		} else {
			body.currency = values.currency;
			body.discount_value = toMinor(values.discount_value.trim(), values.currency);
		}
	}
	return body;
}

export const codeFormSchema = z.object({
	code: z.string().trim().min(1, "vouchers.errors.codeRequired"),
});
export type CodeFormValues = z.infer<typeof codeFormSchema>;

/** F-10's optional void reason, F-9's required removal reason. */
export function reasonFormSchema(required: boolean) {
	const text = z.string().trim().max(200, "vouchers.errors.reasonTooLong");
	return z.object({
		reason: required ? text.min(1, "vouchers.errors.reasonRequired") : text,
	});
}
export type ReasonFormValues = { reason: string };
```

Create `dashboard/src/features/vouchers/api.ts`:

```ts
import { api, clean, csvUrl, type Paginated, type QueryParams } from "@/lib/api";
import type {
	GenerateBody,
	Preview,
	RedeemTargets,
	Redemption,
	VoucherBatch,
	VoucherRow,
} from "./schemas";

const V = "vouchers/";

/** B3f spec §5. */
export const vouchersApi = {
	batches: async (params: QueryParams) =>
		(await api.get<Paginated<VoucherBatch>>(`${V}batches/`, { params: clean(params) })).data,
	generate: async (body: GenerateBody) =>
		(await api.post<VoucherBatch>(`${V}batches/`, body)).data,
	codes: async (params: QueryParams) =>
		(await api.get<Paginated<VoucherRow>>(`${V}codes/`, { params: clean(params) })).data,
	void: async ({ id, reason }: { id: number; reason: string }) =>
		(await api.post<VoucherRow>(`${V}codes/${id}/void/`, { reason })).data,
	redeemById: async ({ id, ...targets }: RedeemTargets & { id: number }) =>
		(await api.post<Redemption>(`${V}codes/${id}/redeem/`, targets)).data,
	redeemByCode: async (body: RedeemTargets & { code: string }) =>
		(await api.post<Redemption>(`${V}codes/redeem/`, body)).data,
	removeDiscount: async ({ id, reason }: { id: number; reason: string }) =>
		(await api.post<VoucherRow>(`${V}codes/${id}/remove-discount/`, { reason })).data,
	check: async (code: string) =>
		(await api.post<Preview>(`${V}check/`, { code })).data,
	redeem: async (body: RedeemTargets & { code: string }) =>
		(await api.post<Redemption>(`${V}redeem/`, body)).data,
};

/** The codes list's CSV with the same filters (plan V18). */
export function codesCsvUrl(params: QueryParams): string {
	return csvUrl(`${V}codes/`, params);
}
```

Create `dashboard/src/features/vouchers/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { billingKey } from "@/features/billing/queries";
import { schedulingKey } from "@/features/scheduling/queries";
import type { QueryParams } from "@/lib/api";
import { vouchersApi } from "./api";

/** Every vouchers query lives under this key. */
export const vouchersKey = ["vouchers"] as const;

/** The batch filter's choices (the newest 100). */
export function useBatches(enabled = true) {
	return useQuery({
		queryKey: [...vouchersKey, "batches"],
		queryFn: () => vouchersApi.batches({ page_size: 100 }),
		enabled,
	});
}

export function useCodes(params: QueryParams) {
	return useQuery({
		queryKey: [...vouchersKey, "codes", params],
		queryFn: () => vouchersApi.codes(params),
		placeholderData: keepPreviousData,
	});
}

/** The voucher behind a `code` payment's reference (plan V23), or null. */
export function useVoucherByCode(code: string, enabled: boolean) {
	return useQuery({
		queryKey: [...vouchersKey, "by-code", code],
		queryFn: async () => (await vouchersApi.codes({ code })).results[0] ?? null,
		enabled,
		retry: false,
	});
}

/** The family's check step: a read that is a POST (throttled). */
export function useCheckCode() {
	return useMutation({ mutationFn: (code: string) => vouchersApi.check(code) });
}

/** A vouchers write (spec §6): refreshes the codes, billing (the invoice and
 * the payment records) and scheduling (subscriptions). On settle: a refused
 * write (a 409) can leave figures that moved elsewhere on screen. */
export function useVoucherMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSettled: () =>
			Promise.all([
				qc.invalidateQueries({ queryKey: vouchersKey }),
				qc.invalidateQueries({ queryKey: billingKey }),
				qc.invalidateQueries({ queryKey: schedulingKey }),
			]),
	});
}
```

Create `dashboard/src/features/vouchers/VoidCodeDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { useFieldError } from "@/lib/field-error";
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
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { vouchersApi } from "./api";
import { useVoucherMutation } from "./queries";
import { type ReasonFormValues, reasonFormSchema, type VoucherRow } from "./schemas";

/** F-10, F-20: withdraw one unused (or expired) code, with an optional
 * reason. */
export function VoidCodeDialog({ row }: { row: VoucherRow }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const save = useVoucherMutation(vouchersApi.void);
	const initial = useCallback((): ReasonFormValues => ({ reason: "" }), []);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<ReasonFormValues>({
		resolver: zodResolver(reasonFormSchema(false)),
		defaultValues: initial(),
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "reason" });

	async function onSubmit(values: ReasonFormValues) {
		const saved = await saveOrShowErrors(
			() => save.mutateAsync({ id: row.id, reason: values.reason.trim() }),
			setError,
		);
		if (saved) {
			setOpen(false);
			toast({ description: t("vouchers.void.done"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="destructive">
					{t("vouchers.void.action")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("vouchers.void.title")}</DialogTitle>
				<DialogDescription>{t("vouchers.void.body", { code: row.code })}</DialogDescription>
				<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
					<Field
						id={`voucher-void-reason-${row.id}`}
						label={t("vouchers.void.reason")}
						error={fieldError(errors.reason?.message)}
					>
						<Textarea rows={2} {...register("reason")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>{t("vouchers.void.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/vouchers/CodeActions.tsx`:

```tsx
import { useCan } from "@/features/identity/permissions";
import type { VoucherRow } from "./schemas";
import { VoidCodeDialog } from "./VoidCodeDialog";

/** A code row's actions (spec §6), for the office with voucher.update. */
export function CodeActions({ row }: { row: VoucherRow }) {
	const can = useCan();
	if (!can("voucher.update")) return null;
	return (
		<div className="flex flex-wrap gap-2">
			{row.state === "unused" || row.state === "expired" ? (
				<VoidCodeDialog row={row} />
			) : null}
		</div>
	);
}
```

Create `dashboard/src/features/vouchers/CodesPage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Copy, Ticket } from "lucide-react";
import { useTranslation } from "react-i18next";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { pageCount, SearchBox, useListParams } from "@/features/finance/shared";
import { dayIn, formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	EmptyState,
	Select,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { codesCsvUrl } from "./api";
import { CodeActions } from "./CodeActions";
import { useBatches, useCodes } from "./queries";
import {
	DISCOUNT_KINDS,
	discountText,
	type NamedRef,
	VOUCHER_KINDS,
	VOUCHER_STATES,
	type VoucherRow,
	type VoucherState,
} from "./schemas";

const COLUMNS = [
	"code",
	"kind",
	"terms",
	"teacher",
	"discount",
	"expires",
	"state",
	"redeemed",
] as const;
// Plan V28.
const TONE: Record<VoucherState, "live" | "neutral" | "warning"> = {
	unused: "live",
	used: "neutral",
	expired: "warning",
	void: "neutral",
};

export function StateChip({ state }: { state: VoucherState }) {
	const { t } = useTranslation();
	return <StatusChip tone={TONE[state]}>{t(`vouchers.states.${state}`)}</StatusChip>;
}

/** A code in monospace, left to right inside RTL text, with Copy. */
function CopyCode({ code }: { code: string }) {
	const { t } = useTranslation();
	return (
		<span className="inline-flex items-center gap-1">
			<span dir="ltr" className="font-mono">
				{code}
			</span>
			<Button
				type="button"
				size="sm"
				variant="ghost"
				aria-label={t("vouchers.list.copy", { code })}
				onClick={async () => {
					await navigator.clipboard.writeText(code);
					toast({ description: t("vouchers.list.copied"), variant: "success" });
				}}
			>
				<Copy className="size-4" aria-hidden />
			</Button>
		</span>
	);
}

function Redeemed({ row }: { row: VoucherRow }) {
	const { t, i18n } = useTranslation();
	const { data: academy } = useAcademySettings();
	if (!row.student || !row.redeemed_at || !academy) return null;
	const link = "text-primary-text underline-offset-4 hover:underline";
	return (
		<div className="flex flex-col gap-0.5">
			<span>
				{t("vouchers.list.redeemedBy", {
					student: row.student.full_name,
					date: dayIn(new Date(row.redeemed_at), academy.timezone, i18n.language),
				})}
			</span>
			<span className="flex flex-wrap gap-2">
				{row.subscription_id !== null ? (
					<Link
						to="/scheduling/subscriptions/$subscriptionId"
						params={{ subscriptionId: String(row.subscription_id) }}
						className={link}
					>
						{t("vouchers.list.openSubscription")}
					</Link>
				) : null}
				{row.invoice_id !== null ? (
					<Link
						to="/billing/invoices/$invoiceId"
						params={{ invoiceId: String(row.invoice_id) }}
						className={link}
					>
						{t("vouchers.list.openInvoice")}
					</Link>
				) : null}
			</span>
		</div>
	);
}

/** B3f §6, Billing → System codes: every code with its filters and CSV;
 * Generate (Task 11) and the row actions. */
export function CodesPage() {
	const { t, i18n } = useTranslation();
	const { params, page, update, goTo } = useListParams();
	const { data, isPending, isError } = useCodes(params);
	const { data: batches } = useBatches();
	const name = (ref: NamedRef | null) =>
		ref ? (i18n.language === "ar" ? ref.name_ar : ref.name_en) : "";
	const chosenBatch = String(params.batch ?? "");
	const batchOptions = (batches?.results ?? []).map(
		(b) =>
			[String(b.id), `${b.note || t("vouchers.list.untitled", { id: b.id })} · ${t(`vouchers.kinds.${b.kind}`)}`] as const,
	);
	// A select always includes its current value (a batch just generated).
	if (chosenBatch && !batchOptions.some(([id]) => id === chosenBatch)) {
		batchOptions.unshift([chosenBatch, t("vouchers.list.untitled", { id: chosenBatch })]);
	}
	const select = (
		id: string,
		label: string,
		key: string,
		options: readonly (readonly [string, string])[],
	) => (
		<div className="flex flex-col gap-1.5">
			<label htmlFor={id} className="text-sm font-medium">
				{label}
			</label>
			<Select
				id={id}
				value={String(params[key] ?? "")}
				onChange={(e) => update({ [key]: e.target.value || undefined })}
			>
				<option value="">{t("vouchers.list.all")}</option>
				{options.map(([value, text]) => (
					<option key={value} value={value}>
						{text}
					</option>
				))}
			</Select>
		</div>
	);
	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<SearchBox
					id="codes-search"
					label={t("vouchers.list.search")}
					value={String(params.q ?? "")}
					onChange={(value) => update({ q: value || undefined })}
				/>
				{select(
					"codes-kind",
					t("vouchers.list.kind"),
					"kind",
					VOUCHER_KINDS.map((k) => [k, t(`vouchers.kinds.${k}`)] as const),
				)}
				{select(
					"codes-state",
					t("vouchers.list.state"),
					"state",
					VOUCHER_STATES.map((s) => [s, t(`vouchers.states.${s}`)] as const),
				)}
				{select(
					"codes-discount",
					t("vouchers.list.discountKind"),
					"discount_kind",
					DISCOUNT_KINDS.map((d) => [d, t(`vouchers.discountKinds.${d}`)] as const),
				)}
				{select("codes-batch", t("vouchers.list.batch"), "batch", batchOptions)}
				<ExportButton href={codesCsvUrl(params)} />
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("vouchers.list.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : data.results.length === 0 ? (
				<EmptyState icon={Ticket} title={t("vouchers.list.empty")} />
			) : (
				<div className="overflow-x-auto">
					<table className="w-full text-sm">
						<thead>
							<tr className="border-b border-border">
								{COLUMNS.map((column) => (
									<th key={column} className="px-2 py-2 text-start font-medium">
										{t(`vouchers.list.columns.${column}`)}
									</th>
								))}
								<th className="px-2 py-2" />
							</tr>
						</thead>
						<tbody>
							{data.results.map((row) => (
								<tr key={row.id} className="border-b border-border align-top">
									<td className="px-2 py-2">
										<CopyCode code={row.code} />
									</td>
									<td className="px-2 py-2">{t(`vouchers.kinds.${row.kind}`)}</td>
									<td className="px-2 py-2">
										{[name(row.course), name(row.package)].filter(Boolean).join(" · ")}
									</td>
									<td className="px-2 py-2">{row.teacher?.full_name ?? ""}</td>
									<td className="px-2 py-2">
										{row.discount ? (
											<span dir="ltr">{discountText(row.discount, i18n.language)}</span>
										) : null}
									</td>
									<td className="px-2 py-2">{formatDay(row.expires_on, i18n.language)}</td>
									<td className="px-2 py-2">
										<div className="flex flex-col gap-0.5">
											<StateChip state={row.state} />
											{row.void_reason ? (
												<span className="text-muted-foreground">
													{t("vouchers.list.voidReason", { reason: row.void_reason })}
												</span>
											) : null}
										</div>
									</td>
									<td className="px-2 py-2">
										<Redeemed row={row} />
									</td>
									<td className="px-2 py-2">
										<CodeActions row={row} />
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager page={page} pages={pageCount(data?.count)} onChange={goTo} />
		</div>
	);
}
```

Create `dashboard/src/features/vouchers/index.ts`:

```ts
export { vouchersApi } from "./api";
export { CodesPage } from "./CodesPage";
export * from "./queries";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/billing.codes.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { CodesPage } from "@/features/vouchers";
import { PageHeader } from "@/ui";

/** B3f §6: Billing → System codes (`voucher.view_any`, `system_codes`). */
export const Route = createFileRoute("/_authed/billing/codes")({
	staticData: { permission: "voucher.view_any", feature: "system_codes" },
	component: function CodesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("vouchers.nav"));
		return (
			<>
				<PageHeader title={t("vouchers.nav")} />
				<CodesPage />
			</>
		);
	},
});
```

`dashboard/src/features/shell/nav.ts`: add `Ticket,` to the `lucide-react` import (between `Tags,` and `TicketCheck,`), and under `// ── phase B3 ──`, right after the `/billing/local-methods` item (before the `/settings/gateways` one):

```ts
	// B3f: the academy's system codes (plan V24).
	office(
		"/billing/codes",
		"vouchers.nav",
		Ticket,
		"billing",
		"voucher.view_any",
		"system_codes",
	),
```

Regenerate the route tree: `$DASH pnpm exec vite build`.

- [ ] **Step 4: Run the tests, types, lint, commit**

Run: `$DASH pnpm vitest run src/features/vouchers src/features/shell src/routes src/locales`
Expected: PASS.
Run: `just test-frontend`, `just lint-frontend`, `$DASH pnpm exec biome check --write src e2e`

```bash
git -C dashboard add src/features/vouchers src/routes/_authed/billing.codes.tsx src/routeTree.gen.ts src/features/shell src/routes/permissions.test.ts src/test/voucher-fixtures.ts src/locales/en/vouchers.json src/locales/ar/vouchers.json
git -C dashboard commit -m "feat(vouchers): Billing, System codes: the list, its filters, CSV and Void (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 11: Dashboard — Generate codes

**Files:**
- Create: `dashboard/src/features/vouchers/GenerateCodesDialog.tsx`, `dashboard/src/features/vouchers/GenerateCodesDialog.test.tsx`
- Modify: `dashboard/src/features/vouchers/CodesPage.tsx`, `dashboard/src/features/vouchers/CodesPage.test.tsx`

**Interfaces:**
- Consumes: Task 10's `generateFormSchema`, `toGenerateBody`, `vouchersApi.generate`, `useVoucherMutation`; `useChoices` from `@/features/scheduling/choices` (active courses, packages, teachers; `teachersFor(courseId)` lists the course's teachers or every active one when the course lists none, F-3); `currencyChoices` from `@/features/finance/ExpenseDialog`; `useAcademySettings`.
- Produces: `GenerateCodesDialog({ onGenerated: (batch: VoucherBatch) => void })`; `CodesPage` shows it for `voucher.create` and, on success, clears the other filters and filters to the new batch (plan V26).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/vouchers/GenerateCodesDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { academySettings, page } from "@/test/scheduling-fixtures";
import { voucherBatch } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { GenerateCodesDialog } from "./GenerateCodesDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, vouchersApi: { ...actual.vouchersApi, generate: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

const person = (id: number, full_name: string) => ({ id, user: { full_name } });
const monthly = {
	id: 4,
	name_ar: "شهري",
	name_en: "Monthly",
	sessions_total: 8,
	price_minor: 150000,
	currency: "EGP",
};

async function open(user: ReturnType<typeof userEvent.setup>, onGenerated = vi.fn()) {
	renderWithRouter(<GenerateCodesDialog onGenerated={onGenerated} />);
	await user.click(screen.getByRole("button", { name: "Generate codes" }));
	const dialog = await screen.findByRole("dialog");
	// Locked until the academy's settings (the default currency) arrive.
	await waitFor(() => expect(within(dialog).getByLabelText(/^Code type/)).toBeEnabled());
	return dialog;
}

describe("GenerateCodesDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings({ default_currency: "XAF" }));
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([person(21, "Bilal"), person(22, "Maryam")]) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([
							{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [21] },
							{ id: 8, name_ar: "عربي", name_en: "Arabic", teacher_ids: [] },
						])
					: page([monthly])) as never,
		);
		vi.mocked(vouchersApi.generate).mockResolvedValue(voucherBatch({ id: 12 }));
	});

	it("generates an activation batch for a course's teacher and hands it back", async () => {
		const user = userEvent.setup();
		const onGenerated = vi.fn();
		const dialog = await open(user, onGenerated);
		await user.selectOptions(await within(dialog).findByLabelText(/^Course/), "3");
		await within(dialog).findByRole("option", { name: "Bilal" });
		// The course lists only Bilal.
		expect(within(dialog).queryByRole("option", { name: "Maryam" })).toBeNull();
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await user.selectOptions(within(dialog).getByLabelText(/^Package/), "4");
		expect(within(dialog).getByText("This package has 8 sessions.")).toBeVisible();
		await user.clear(within(dialog).getByLabelText(/^Number of codes/));
		await user.type(within(dialog).getByLabelText(/^Number of codes/), "2");
		await user.type(within(dialog).getByLabelText(/^Note/), "June flyers");
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		await waitFor(() =>
			expect(vouchersApi.generate).toHaveBeenCalledWith({
				kind: "activation",
				quantity: 2,
				valid_days: 30,
				course: 3,
				package: 4,
				teacher: 21,
				note: "June flyers",
			}),
		);
		expect(await screen.findByText("Codes generated.")).toBeVisible();
		expect(onGenerated).toHaveBeenCalledWith(expect.objectContaining({ id: 12 }));
	});

	it("lists every active teacher when the course lists none", async () => {
		const user = userEvent.setup();
		const dialog = await open(user);
		await user.selectOptions(await within(dialog).findByLabelText(/^Course/), "8");
		expect(await within(dialog).findByRole("option", { name: "Maryam" })).toBeInTheDocument();
		expect(within(dialog).getByRole("option", { name: "Bilal" })).toBeInTheDocument();
	});

	it("shows the teacher for an activation only and the discount fields for a discount", async () => {
		const user = userEvent.setup();
		const dialog = await open(user);
		expect(within(dialog).getByLabelText(/^Teacher/)).toBeVisible();
		expect(within(dialog).queryByLabelText(/^Discount type/)).toBeNull();
		await user.selectOptions(within(dialog).getByLabelText(/^Code type/), "renewal");
		expect(within(dialog).queryByLabelText(/^Teacher/)).toBeNull();
		await user.selectOptions(within(dialog).getByLabelText(/^Code type/), "discount");
		expect(within(dialog).getByRole("option", { name: "Any course" })).toBeInTheDocument();
		expect(within(dialog).getByLabelText(/^Percentage/)).toBeVisible();
		await user.selectOptions(within(dialog).getByLabelText(/^Discount type/), "fixed");
		// The academy's currency is kept even though the list lacks it.
		expect(within(dialog).getByLabelText(/^Currency/)).toHaveValue("XAF");
		await user.selectOptions(within(dialog).getByLabelText(/^Currency/), "USD");
		await user.type(within(dialog).getByLabelText(/^Amount/), "50");
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		await waitFor(() =>
			expect(vouchersApi.generate).toHaveBeenCalledWith({
				kind: "discount",
				quantity: 1,
				valid_days: 30,
				discount_kind: "fixed",
				discount_value: 5000,
				currency: "USD",
				note: "",
			}),
		);
	});

	it("checks the form and puts the server's errors on their fields", async () => {
		vi.mocked(vouchersApi.generate).mockRejectedValueOnce(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { teacher: ["This teacher does not teach the course."] },
			} as never),
		);
		const user = userEvent.setup();
		const dialog = await open(user);
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		expect(await within(dialog).findAllByText("Fill this in.")).toHaveLength(3);
		expect(vouchersApi.generate).not.toHaveBeenCalled();
		await user.selectOptions(await within(dialog).findByLabelText(/^Course/), "3");
		await within(dialog).findByRole("option", { name: "Bilal" });
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await user.selectOptions(within(dialog).getByLabelText(/^Package/), "4");
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		expect(
			await within(dialog).findByText("This teacher does not teach the course."),
		).toBeVisible();
		expect(screen.getByRole("dialog")).toBeVisible();
	});
});
```

In `dashboard/src/features/vouchers/CodesPage.test.tsx`: add `generate: vi.fn()` to the mocked `vouchersApi` and mock the catalogue and people lists as in `GenerateCodesDialog.test.tsx` (`vi.mock("@/features/people/api", …)`, `vi.mock("@/features/catalogue/api", …)`, both lists resolving `page([])`), then add:

```tsx
	it("filters to a batch just generated, for voucher.create only", async () => {
		vi.mocked(vouchersApi.generate).mockResolvedValue(voucherBatch({ id: 12, kind: "discount" }));
		const user = userEvent.setup();
		const { unmount } = renderPage(staffMe("voucher.view_any", "voucher.create"));
		await screen.findByRole("table");
		await user.selectOptions(screen.getByLabelText("Status"), "used");
		await user.click(screen.getByRole("button", { name: "Generate codes" }));
		const dialog = await screen.findByRole("dialog");
		await waitFor(() => expect(within(dialog).getByLabelText(/^Code type/)).toBeEnabled());
		await user.selectOptions(within(dialog).getByLabelText(/^Code type/), "discount");
		await user.type(within(dialog).getByLabelText(/^Percentage/), "10");
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		await waitFor(() => expect(lastParams()).toEqual({ page: 1, batch: 12 }));
		expect(screen.getByLabelText("Batch")).toHaveValue("12");
		unmount();
		renderPage(staffMe("voucher.view_any"));
		await screen.findByRole("table");
		expect(screen.queryByRole("button", { name: "Generate codes" })).toBeNull();
	});
```

(`lastParams()` passes through `clean` only inside `vouchersApi.codes`, which is mocked: the hook receives `useListParams`' object, whose cleared filters are `undefined`; `toEqual` treats undefined keys as absent.)

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/vouchers/GenerateCodesDialog.test.tsx src/features/vouchers/CodesPage.test.tsx`
Expected: FAIL (`Cannot find module './GenerateCodesDialog'`; no Generate codes button).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/vouchers/GenerateCodesDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { currencyChoices } from "@/features/finance/ExpenseDialog";
import { SettingsWait, saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { useChoices } from "@/features/scheduling/choices";
import { useFieldError } from "@/lib/field-error";
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
import { vouchersApi } from "./api";
import { useVoucherMutation } from "./queries";
import {
	DISCOUNT_KINDS,
	type GenerateFormValues,
	generateFormSchema,
	type NamedRef,
	toGenerateBody,
	VOUCHER_KINDS,
	type VoucherBatch,
} from "./schemas";

/** F-2, F-3, F-4, F-20: a batch of 1–500 codes sharing their terms. The
 * course and package are required except for a discount; the teacher is an
 * activation's, from the course's teachers (or every active one when the
 * course lists none). */
export function GenerateCodesDialog({
	onGenerated,
}: {
	onGenerated: (batch: VoucherBatch) => void;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const settings = useAcademySettings();
	const academy = settings.data;
	const [open, setOpen] = useState(false);
	const save = useVoucherMutation(vouchersApi.generate);
	const { courses, packages, packageById, teachersFor } = useChoices();
	const localName = (ref: NamedRef) => (i18n.language === "ar" ? ref.name_ar : ref.name_en);
	const initial = useCallback(
		(): GenerateFormValues => ({
			kind: "activation",
			course: "",
			package: "",
			teacher: "",
			quantity: "1",
			valid_days: "30",
			discount_kind: "percent",
			discount_value: "",
			currency: academy?.default_currency ?? "",
			note: "",
		}),
		[academy],
	);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		setValue,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<GenerateFormValues>({
		resolver: zodResolver(generateFormSchema),
		defaultValues: initial(),
	});
	const filled = useFillOnOpen({
		open,
		ready: Boolean(academy),
		reset,
		setFocus,
		initial,
		first: "kind",
	});
	const kind = watch("kind");
	const discountKind = watch("discount_kind");
	const chosenCurrency = watch("currency");
	const pkg = packageById(watch("package"));
	const teachers = teachersFor(watch("course"));
	const blank = kind === "discount";

	async function onSubmit(values: GenerateFormValues) {
		let created: VoucherBatch | undefined;
		const saved = await saveOrShowErrors(async () => {
			created = await save.mutateAsync(toGenerateBody(values));
		}, setError);
		if (saved && created) {
			setOpen(false);
			toast({ description: t("vouchers.generate.done"), variant: "success" });
			onGenerated(created);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{t("vouchers.generate.action")}</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("vouchers.generate.title")}</DialogTitle>
				<DialogDescription>{t("vouchers.generate.body")}</DialogDescription>
				{!filled ? (
					<SettingsWait
						failed={settings.isError}
						retrying={settings.isFetching}
						onRetry={() => settings.refetch()}
					/>
				) : null}
				<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
					<fieldset disabled={!filled} className="flex flex-col gap-4">
						<div className="grid gap-4 sm:grid-cols-2">
							<Field id="voucher-kind" label={t("vouchers.generate.kind")} error={fieldError(errors.kind?.message)} required>
								<Select {...register("kind")}>
									{VOUCHER_KINDS.map((k) => (
										<option key={k} value={k}>
											{t(`vouchers.kinds.${k}`)}
										</option>
									))}
								</Select>
							</Field>
							<Field
								id="voucher-course"
								label={t("vouchers.generate.course")}
								error={fieldError(errors.course?.message)}
								required={!blank}
							>
								<Select {...register("course", { onChange: () => setValue("teacher", "") })}>
									<option value="">{blank ? t("vouchers.generate.anyCourse") : "—"}</option>
									{courses.map((c) => (
										<option key={c.id} value={c.id}>
											{localName(c)}
										</option>
									))}
								</Select>
							</Field>
							<Field
								id="voucher-package"
								label={t("vouchers.generate.package")}
								error={fieldError(errors.package?.message)}
								required={!blank}
							>
								<Select {...register("package")}>
									<option value="">{blank ? t("vouchers.generate.anyPackage") : "—"}</option>
									{packages.map((p) => (
										<option key={p.id} value={p.id}>
											{localName(p)}
										</option>
									))}
								</Select>
							</Field>
							{kind === "activation" ? (
								<Field id="voucher-teacher" label={t("vouchers.generate.teacher")} error={fieldError(errors.teacher?.message)} required>
									<Select {...register("teacher")}>
										<option value="">—</option>
										{teachers.map((p) => (
											<option key={p.id} value={p.id}>
												{p.user.full_name}
											</option>
										))}
									</Select>
								</Field>
							) : null}
						</div>
						{pkg ? (
							<p className="text-sm text-muted-foreground">
								{t("vouchers.generate.sessions", { count: pkg.sessions_total })}
							</p>
						) : null}
						<div className="grid gap-4 sm:grid-cols-2">
							<Field id="voucher-quantity" label={t("vouchers.generate.quantity")} error={fieldError(errors.quantity?.message)} required>
								<Input inputMode="numeric" dir="ltr" {...register("quantity")} />
							</Field>
							<Field id="voucher-valid-days" label={t("vouchers.generate.validDays")} error={fieldError(errors.valid_days?.message)} required>
								<Input inputMode="numeric" dir="ltr" {...register("valid_days")} />
							</Field>
						</div>
						{kind === "discount" ? (
							<div className="grid gap-4 sm:grid-cols-3">
								<Field id="voucher-discount-kind" label={t("vouchers.generate.discountKind")} error={fieldError(errors.discount_kind?.message)} required>
									<Select {...register("discount_kind")}>
										{DISCOUNT_KINDS.map((d) => (
											<option key={d} value={d}>
												{t(`vouchers.discountKinds.${d}`)}
											</option>
										))}
									</Select>
								</Field>
								<Field
									id="voucher-discount-value"
									label={t(discountKind === "percent" ? "vouchers.generate.percent" : "vouchers.generate.amount")}
									error={fieldError(errors.discount_value?.message)}
									required
								>
									<Input inputMode="decimal" dir="ltr" {...register("discount_value")} />
								</Field>
								{discountKind === "fixed" ? (
									<Field id="voucher-currency" label={t("vouchers.generate.currency")} error={fieldError(errors.currency?.message)} required>
										<Select dir="ltr" {...register("currency")}>
											{currencyChoices(chosenCurrency, academy?.default_currency).map((code) => (
												<option key={code} value={code}>
													{code}
												</option>
											))}
										</Select>
									</Field>
								) : null}
							</div>
						) : null}
						<Field id="voucher-note" label={t("vouchers.generate.note")} error={fieldError(errors.note?.message)}>
							<Input {...register("note")} />
						</Field>
					</fieldset>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting} disabled={!filled}>
							{t("vouchers.generate.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

(`SettingsWait({ failed, retrying, onRetry })` and `SubmitButton`'s `disabled` are used exactly as `ExpenseDialog` uses them.)

`dashboard/src/features/vouchers/CodesPage.tsx`: import `useCan` from `@/features/identity/permissions` and `GenerateCodesDialog` from `./GenerateCodesDialog`; in `CodesPage` add `const can = useCan();` and, after `<ExportButton … />`:

```tsx
				{can("voucher.create") ? (
					<GenerateCodesDialog
						onGenerated={(batch) =>
							// Plan V26: exactly the new batch's codes.
							update({
								kind: undefined,
								state: undefined,
								discount_kind: undefined,
								q: undefined,
								batch: batch.id,
							})
						}
					/>
				) : null}
```

- [ ] **Step 4: Run the tests, types, lint, commit**

Run: `$DASH pnpm vitest run src/features/vouchers`
Expected: PASS.
Run: `just test-frontend`, `just lint-frontend`, `$DASH pnpm exec biome check --write src e2e`

```bash
git -C dashboard add src/features/vouchers
git -C dashboard commit -m "feat(vouchers): generate a batch of codes from the System codes page (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 12: Dashboard — Redeem for a student and Remove discount

**Files:**
- Create: `dashboard/src/features/vouchers/OfficeRedeemDialog.tsx`, `dashboard/src/features/vouchers/OfficeRedeemDialog.test.tsx`, `dashboard/src/features/vouchers/RemoveDiscount.tsx`, `dashboard/src/features/vouchers/RemoveDiscount.test.tsx`, `dashboard/src/features/vouchers/CodeActions.test.tsx`
- Modify: `dashboard/src/features/vouchers/CodeActions.tsx`, `dashboard/src/features/vouchers/index.ts`, `dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`

**Interfaces:**
- Consumes: `vouchersApi.redeemById`, `vouchersApi.removeDiscount`, `useVoucherByCode`, `useVoucherMutation`, `reasonFormSchema(true)`; `usePeople` from `@/features/people`; `useSubscriptions` from `@/features/scheduling` (list filtered by `student` user id and `course`); billing's `Payment`, `InvoiceDetail`.
- Produces:
  - `OfficeRedeemDialog({ row })` for an unused activation or renewal code (F-20; plan V10's visibility in `CodeActions`);
  - `RemoveDiscountDialog({ voucherId })` (required reason, F-9) and `RemoveDiscount({ payment })` for billing's `paymentActions` (office only; a `code` payment whose voucher, found by `codes/?code=<reference>`, is a used discount);
  - `CodeActions` shows Void, Redeem for a student and Remove discount as the row and the codes allow;
  - the office invoice route passes `RemoveDiscount` beside B3e's `MoveToWallet`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/vouchers/OfficeRedeemDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { peopleApi } from "@/features/people/api";
import { schedulingApi } from "@/features/scheduling/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionRow } from "@/test/scheduling-fixtures";
import { redemption, voucherRow } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { OfficeRedeemDialog } from "./OfficeRedeemDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, vouchersApi: { ...actual.vouchersApi, redeemById: vi.fn() } };
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/scheduling/api", async (orig) => {
	const actual = await orig<typeof import("@/features/scheduling/api")>();
	return { ...actual, schedulingApi: { ...actual.schedulingApi, list: vi.fn() } };
});

const person = (id: number, full_name: string) => ({ id, user: { full_name } });

async function openFor(user: ReturnType<typeof userEvent.setup>, row = voucherRow()) {
	renderWithRouter(<OfficeRedeemDialog row={row} />);
	await user.click(screen.getByRole("button", { name: "Redeem for a student" }));
	return screen.findByRole("dialog");
}

describe("OfficeRedeemDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(page([person(11, "Yusuf")]) as never);
		vi.mocked(vouchersApi.redeemById).mockResolvedValue(redemption());
	});

	it("starts an activation for the student it finds", async () => {
		const user = userEvent.setup();
		const dialog = await openFor(user);
		expect(dialog).toHaveTextContent("Redeem SYS-ABCDE-FGHJK for a student");
		await user.type(within(dialog).getByLabelText(/^Find a student/), "yus");
		await waitFor(() =>
			expect(peopleApi.list).toHaveBeenLastCalledWith(
				"students",
				expect.objectContaining({ q: "yus", is_active: "true" }),
			),
		);
		await within(dialog).findByRole("option", { name: "Yusuf" });
		await user.selectOptions(within(dialog).getByLabelText(/^Student/), "11");
		await user.click(within(dialog).getByRole("button", { name: "Redeem" }));
		await waitFor(() => expect(vouchersApi.redeemById).toHaveBeenCalledWith({ id: 91, student: 11 }));
		expect(await screen.findByText("Code redeemed.")).toBeVisible();
	});

	it("renews one of the student's eligible subscriptions of the code's course", async () => {
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([
				subscriptionRow({ id: 7 }),
				subscriptionRow({ id: 8, status: "cancelled" }),
				subscriptionRow({ id: 9, renewal: 12 }),
			]),
		);
		const user = userEvent.setup();
		const dialog = await openFor(user, voucherRow({ kind: "renewal", teacher: null }));
		await within(dialog).findByRole("option", { name: "Yusuf" });
		await user.selectOptions(within(dialog).getByLabelText(/^Student/), "11");
		await waitFor(() =>
			expect(schedulingApi.list).toHaveBeenCalledWith(
				expect.objectContaining({ student: "11", course: 3 }),
			),
		);
		const choice = await within(dialog).findByLabelText(/^Subscription/);
		await within(dialog).findByRole("option", { name: "Tajweed — Monthly · ends Jun 30, 2026" });
		expect(within(choice).getAllByRole("option")).toHaveLength(2); // "—" and #7
		await user.selectOptions(choice, "7");
		await user.click(within(dialog).getByRole("button", { name: "Redeem" }));
		await waitFor(() =>
			expect(vouchersApi.redeemById).toHaveBeenCalledWith({ id: 91, subscription: 7 }),
		);
	});

	it("says when the student has nothing this code can renew", async () => {
		vi.mocked(schedulingApi.list).mockResolvedValue(page([subscriptionRow({ status: "cancelled" })]));
		const user = userEvent.setup();
		const dialog = await openFor(user, voucherRow({ kind: "renewal", teacher: null }));
		await within(dialog).findByRole("option", { name: "Yusuf" });
		await user.selectOptions(within(dialog).getByLabelText(/^Student/), "11");
		expect(
			await within(dialog).findByText("This student has no subscription this code can renew."),
		).toBeVisible();
	});

	it("says why the server refused", async () => {
		vi.mocked(vouchersApi.redeemById).mockRejectedValueOnce(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "x", code: "vouchers.unavailable" },
			} as never),
		);
		const user = userEvent.setup();
		const dialog = await openFor(user);
		await within(dialog).findByRole("option", { name: "Yusuf" });
		await user.selectOptions(within(dialog).getByLabelText(/^Student/), "11");
		await user.click(within(dialog).getByRole("button", { name: "Redeem" }));
		expect(
			await within(dialog).findByText("This code can't be used right now. Contact the academy."),
		).toBeVisible();
	});
});
```

Create `dashboard/src/features/vouchers/RemoveDiscount.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import type { Payment } from "@/features/billing/schemas";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { paymentRow } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { discountRow, voucherRow } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { RemoveDiscount } from "./RemoveDiscount";
import type { VoucherRow } from "./schemas";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		vouchersApi: { ...actual.vouchersApi, codes: vi.fn(), removeDiscount: vi.fn() },
	};
});

const coded = paymentRow({
	method: "code",
	reference: "SYS-DSC0N-12345",
	deletable: false,
	refundable: false,
	movable: false,
});
const OFFICE = adminWith("system_codes", "invoices");

function renderRemove(payment: Payment = coded, me: Me = OFFICE) {
	return renderWithRouter(
		<CanProvider me={me}>
			<p>row mounted</p>
			<RemoveDiscount payment={payment} />
		</CanProvider>,
	);
}

describe("RemoveDiscount", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(vouchersApi.codes).mockResolvedValue(page([discountRow({ state: "used" })]));
		vi.mocked(vouchersApi.removeDiscount).mockResolvedValue(discountRow({ state: "void" }));
	});

	it("removes a used discount with a reason", async () => {
		const user = userEvent.setup();
		renderRemove();
		await user.click(await screen.findByRole("button", { name: "Remove discount" }));
		expect(vouchersApi.codes).toHaveBeenCalledWith({ code: "SYS-DSC0N-12345" });
		const dialog = await screen.findByRole("dialog");
		await user.click(within(dialog).getByRole("button", { name: "Remove discount" }));
		expect(await within(dialog).findByText("Say why.")).toBeVisible();
		expect(vouchersApi.removeDiscount).not.toHaveBeenCalled();
		await user.type(within(dialog).getByLabelText(/^Reason/), "Wrong invoice");
		await user.click(within(dialog).getByRole("button", { name: "Remove discount" }));
		await waitFor(() =>
			expect(vouchersApi.removeDiscount).toHaveBeenCalledWith({ id: 92, reason: "Wrong invoice" }),
		);
		expect(await screen.findByText("Discount removed.")).toBeVisible();
	});

	it.each<[string, VoucherRow]>([
		["an activation code's payment", voucherRow({ state: "used" })],
		["a discount already removed", discountRow({ state: "void" })],
	])("is not offered for %s, once the lookup answered", async (_, found) => {
		vi.mocked(vouchersApi.codes).mockResolvedValue(page([found]));
		renderRemove();
		await waitFor(() =>
			expect(vouchersApi.codes).toHaveBeenCalledWith({ code: "SYS-DSC0N-12345" }),
		);
		await act(async () => {
			await vi.mocked(vouchersApi.codes).mock.results[0]?.value;
		});
		expect(screen.queryByRole("button", { name: "Remove discount" })).toBeNull();
	});

	it.each<[string, Payment, Me]>([
		["a cash payment", paymentRow(), OFFICE],
		[
			"no payment.update",
			coded,
			{ ...staffMe("voucher.view_any", "voucher.update"), features: ["system_codes", "invoices"] },
		],
		["system codes off", coded, adminWith("invoices")],
		["a family", coded, { ...adminWith("system_codes", "invoices"), role: "parent", is_super_admin: false }],
	])("is not offered for %s, and looks nothing up", async (_, payment, me) => {
		renderRemove(payment, me);
		expect(await screen.findByText("row mounted")).toBeVisible();
		expect(screen.queryByRole("button", { name: "Remove discount" })).toBeNull();
		expect(vouchersApi.codes).not.toHaveBeenCalled();
	});
});
```

Create `dashboard/src/features/vouchers/CodeActions.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { discountRow, voucherRow } from "@/test/voucher-fixtures";
import { CodeActions } from "./CodeActions";
import type { VoucherRow } from "./schemas";

function renderActions(row: VoucherRow, me: Me) {
	return renderWithRouter(
		<CanProvider me={me}>
			<p>row mounted</p>
			<CodeActions row={row} />
		</CanProvider>,
	);
}

const buttons = () => screen.queryAllByRole("button").map((b) => b.textContent);

describe("CodeActions", () => {
	it("offers each action where the row and the codes allow it", async () => {
		const admin = adminWith("system_codes", "invoices");
		const { unmount } = renderActions(voucherRow(), admin);
		await screen.findByText("row mounted");
		expect(buttons()).toEqual(["Void", "Redeem for a student"]);
		unmount();
		renderActions(discountRow({ state: "used" }), admin);
		await screen.findByText("row mounted");
		expect(buttons()).toEqual(["Remove discount"]);
	});

	it("hides Redeem for a student without the kind's extra codes (F-20, plan V10)", async () => {
		const clerk = { ...staffMe("voucher.update", "subscription.update", "student.view_any"), features: ["system_codes"] } as Me;
		const { unmount } = renderActions(voucherRow(), clerk);
		await screen.findByText("row mounted");
		expect(buttons()).toEqual(["Void"]);
		unmount();
		renderActions(voucherRow({ kind: "renewal" }), clerk);
		await screen.findByText("row mounted");
		expect(buttons()).toEqual(["Void"]); // renewal also needs subscription.view_any
	});

	it("hides Remove discount without payment.update or invoices", async () => {
		const { unmount } = renderActions(
			discountRow({ state: "used" }),
			{ ...staffMe("voucher.update"), features: ["system_codes", "invoices"] } as Me,
		);
		await screen.findByText("row mounted");
		expect(buttons()).toEqual([]);
		unmount();
		renderActions(discountRow({ state: "used" }), adminWith("system_codes"));
		await screen.findByText("row mounted");
		expect(buttons()).toEqual([]);
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/vouchers/OfficeRedeemDialog.test.tsx src/features/vouchers/RemoveDiscount.test.tsx src/features/vouchers/CodeActions.test.tsx`
Expected: FAIL (`Cannot find module './OfficeRedeemDialog'`, `'./RemoveDiscount'`; `CodeActions` offers only Void).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/vouchers/OfficeRedeemDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { usePeople } from "@/features/people";
import { useSubscriptions } from "@/features/scheduling";
import { useFieldError } from "@/lib/field-error";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	Select,
	SubmitButton,
	toast,
} from "@/ui";
import { vouchersApi } from "./api";
import { useVoucherMutation } from "./queries";
import type { NamedRef, VoucherRow } from "./schemas";

// §4.2: what a renewal code may renew (scheduling decides again).
const RENEWABLE = ["active", "paused", "expired"];

const schema = (renewal: boolean) =>
	z
		.object({ student: z.string(), subscription: z.string() })
		.superRefine((v, ctx) => {
			if (!v.student) {
				ctx.addIssue({ code: "custom", path: ["student"], message: "vouchers.errors.required" });
			}
			if (renewal && !v.subscription) {
				ctx.addIssue({ code: "custom", path: ["subscription"], message: "vouchers.errors.required" });
			}
		});
type Values = { student: string; subscription: string };

/** F-20: the office redeems an activation or a renewal code for a student
 * (`codes/<id>/redeem/`); a discount is applied from its invoice. */
export function OfficeRedeemDialog({ row }: { row: VoucherRow }) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const renewal = row.kind === "renewal";
	const save = useVoucherMutation(vouchersApi.redeemById);
	const initial = useCallback((): Values => ({ student: "", subscription: "" }), []);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		setValue,
		reset,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<Values>({ resolver: zodResolver(schema(renewal)), defaultValues: initial() });
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "student" });
	const { data: students } = usePeople(
		"students",
		{ is_active: "true", page_size: 100, q: query.trim() },
		{ enabled: open },
	);
	const student = watch("student");
	const subs = useSubscriptions(
		{ student, course: row.course?.id, page_size: 100 },
		{ enabled: open && renewal && Boolean(student) },
	);
	const renewable = (subs.data?.results ?? []).filter(
		(s) => RENEWABLE.includes(s.status) && s.renewal === null,
	);
	const localName = (ref: NamedRef) => (i18n.language === "ar" ? ref.name_ar : ref.name_en);

	async function onSubmit(values: Values) {
		const targets = renewal
			? { subscription: Number(values.subscription) }
			: { student: Number(values.student) };
		const saved = await saveOrShowErrors(
			() => save.mutateAsync({ id: row.id, ...targets }),
			setError,
		);
		if (saved) {
			setOpen(false);
			toast({ description: t("vouchers.redeem.done"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("vouchers.redeem.action")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("vouchers.redeem.title", { code: row.code })}</DialogTitle>
				<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
					<Field id={`voucher-redeem-search-${row.id}`} label={t("vouchers.redeem.findStudent")}>
						<Input type="search" value={query} onChange={(e) => setQuery(e.target.value)} />
					</Field>
					<Field
						id={`voucher-redeem-student-${row.id}`}
						label={t("vouchers.redeem.student")}
						error={fieldError(errors.student?.message)}
						required
					>
						<Select {...register("student", { onChange: () => setValue("subscription", "") })}>
							<option value="">—</option>
							{students?.results.map((p) => (
								<option key={p.id} value={p.id}>
									{p.user.full_name}
								</option>
							))}
						</Select>
					</Field>
					{renewal && student ? (
						subs.isSuccess && renewable.length === 0 ? (
							<p className="text-sm text-muted-foreground">{t("vouchers.redeem.noRenewable")}</p>
						) : (
							<Field
								id={`voucher-redeem-subscription-${row.id}`}
								label={t("vouchers.redeem.subscription")}
								error={fieldError(errors.subscription?.message)}
								required
							>
								<Select {...register("subscription")}>
									<option value="">—</option>
									{renewable.map((s) => (
										<option key={s.id} value={s.id}>
											{t("vouchers.redeem.choice", {
												course: localName(s.course),
												package: localName(s.package),
												date: formatDay(s.ends_on, i18n.language),
											})}
										</option>
									))}
								</Select>
							</Field>
						)
					) : null}
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>{t("vouchers.redeem.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/vouchers/RemoveDiscount.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import type { Payment } from "@/features/billing/schemas";
import { saveOrShowErrors, useFillOnOpen } from "@/features/finance/shared";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
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
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { vouchersApi } from "./api";
import { useVoucherByCode, useVoucherMutation } from "./queries";
import { type ReasonFormValues, reasonFormSchema } from "./schemas";

/** F-9: the office removes a discount applied by mistake, with a reason. */
export function RemoveDiscountDialog({ voucherId }: { voucherId: number }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const save = useVoucherMutation(vouchersApi.removeDiscount);
	const initial = useCallback((): ReasonFormValues => ({ reason: "" }), []);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<ReasonFormValues>({
		resolver: zodResolver(reasonFormSchema(true)),
		defaultValues: initial(),
	});
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "reason" });

	async function onSubmit(values: ReasonFormValues) {
		const saved = await saveOrShowErrors(
			() => save.mutateAsync({ id: voucherId, reason: values.reason.trim() }),
			setError,
		);
		if (saved) {
			setOpen(false);
			toast({ description: t("vouchers.remove.done"), variant: "success" });
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="destructive">
					{t("vouchers.remove.action")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("vouchers.remove.title")}</DialogTitle>
				<DialogDescription>{t("vouchers.remove.body")}</DialogDescription>
				<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
					<Field
						id={`voucher-remove-reason-${voucherId}`}
						label={t("vouchers.remove.reason")}
						error={fieldError(errors.reason?.message)}
						required
					>
						<Textarea rows={2} {...register("reason")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>{t("vouchers.remove.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** Spec §6, plans V10, V23: on the office invoice page (billing's
 * `paymentActions`), a `code` payment whose voucher is a used discount. */
export function RemoveDiscount({ payment }: { payment: Payment }) {
	const can = useCan();
	const hasFeature = useHasFeature();
	const allowed =
		payment.method === "code" &&
		hasFeature("system_codes") &&
		hasFeature("invoices") &&
		can("voucher.view_any") &&
		can("voucher.update") &&
		can("payment.update");
	const { data: voucher } = useVoucherByCode(payment.reference, allowed);
	if (!allowed || !voucher || voucher.kind !== "discount" || voucher.state !== "used") {
		return null;
	}
	return <RemoveDiscountDialog voucherId={voucher.id} />;
}
```

Replace `dashboard/src/features/vouchers/CodeActions.tsx` with:

```tsx
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { OfficeRedeemDialog } from "./OfficeRedeemDialog";
import { RemoveDiscountDialog } from "./RemoveDiscount";
import type { VoucherRow } from "./schemas";
import { VoidCodeDialog } from "./VoidCodeDialog";

// F-20 and plan V10: the kind's own code, and what the dialog lists.
const REDEEM_CODES = {
	activation: ["subscription.create", "student.view_any"],
	renewal: ["subscription.update", "student.view_any", "subscription.view_any"],
} as const;

/** A code row's actions (spec §6), for the office with voucher.update. */
export function CodeActions({ row }: { row: VoucherRow }) {
	const can = useCan();
	const hasFeature = useHasFeature();
	if (!can("voucher.update")) return null;
	const redeemable =
		row.state === "unused" &&
		row.kind !== "discount" &&
		REDEEM_CODES[row.kind].every((code) => can(code));
	const removable =
		row.kind === "discount" &&
		row.state === "used" &&
		can("payment.update") &&
		hasFeature("invoices");
	return (
		<div className="flex flex-wrap gap-2">
			{row.state === "unused" || row.state === "expired" ? <VoidCodeDialog row={row} /> : null}
			{redeemable ? <OfficeRedeemDialog row={row} /> : null}
			{removable ? <RemoveDiscountDialog voucherId={row.id} /> : null}
		</div>
	);
}
```

`dashboard/src/features/vouchers/index.ts`: add `export { RemoveDiscount } from "./RemoveDiscount";`.

`dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`: import `RemoveDiscount` from `@/features/vouchers`, and make `paymentActions`

```tsx
					paymentActions={(payment, invoice) => (
						<>
							<MoveToWallet payment={payment} invoice={invoice} />
							{/* B3f §6: billing never imports vouchers either. */}
							<RemoveDiscount payment={payment} />
						</>
					)}
```

- [ ] **Step 4: Run the tests, types, lint, commit**

Run: `$DASH pnpm vitest run src/features/vouchers src/features/billing`
Expected: PASS.
Run: `just test-frontend`, `just lint-frontend`, `$DASH pnpm exec biome check --write src e2e`

```bash
git -C dashboard add src/features/vouchers 'src/routes/_authed/billing.invoices.$invoiceId.tsx'
git -C dashboard commit -m "feat(vouchers): redeem a code for a student and remove a discount from the office (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 13: Dashboard — Family → Redeem a code

**Files:**
- Create: `dashboard/src/features/vouchers/RedeemCodePage.tsx`, `dashboard/src/features/vouchers/RedeemCodePage.test.tsx`, `dashboard/src/routes/_authed/learning.codes.tsx`
- Modify: `dashboard/src/features/vouchers/index.ts`, `dashboard/src/features/shell/nav.ts` (B3 marker), `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/routes/permissions.test.ts`; `dashboard/src/routeTree.gen.ts` (generated)

**Interfaces:**
- Consumes: `useCheckCode`, `useVoucherMutation`, `vouchersApi.redeem`, `codeFormSchema`, `discountText`; `parseApiError` from `@/features/identity/api`; `errorText` from `@/lib/form-errors`.
- Produces: `RedeemCodePage` (spec §6 steps 1–5, plan V29); route `/_authed/learning/codes` (`system_codes`; the `learning` layout admits students and parents only); the family nav item (plan V24).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/vouchers/RedeemCodePage.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { codePreview, redemption } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { RedeemCodePage } from "./RedeemCodePage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		vouchersApi: { ...actual.vouchersApi, check: vi.fn(), redeem: vi.fn() },
	};
});

const LINKS = ["/learning/subscriptions", "/learning/invoices"];

function refused(status: number, data: object) {
	return new AxiosError("Refused", String(status), undefined, undefined, {
		status,
		data,
	} as never);
}

async function check(user: ReturnType<typeof userEvent.setup>, text = "sys abcde fghjk") {
	renderWithRouter(<RedeemCodePage />, { extraPaths: LINKS });
	await user.type(screen.getByLabelText(/^Code/), text);
	await user.click(screen.getByRole("button", { name: "Check" }));
}

describe("RedeemCodePage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(vouchersApi.check).mockResolvedValue(codePreview());
		vi.mocked(vouchersApi.redeem).mockResolvedValue(redemption());
	});
	afterEach(async () => {
		await act(async () => {
			await i18n.changeLanguage("en");
		});
	});

	it("checks a code and starts a subscription for a lone student", async () => {
		const user = userEvent.setup();
		await check(user);
		expect(vouchersApi.check).toHaveBeenCalledWith("sys abcde fghjk");
		expect(await screen.findByRole("heading", { name: "This code starts a subscription" })).toBeVisible();
		expect(screen.getByText("Tajweed")).toBeVisible();
		expect(screen.getByText("Monthly")).toBeVisible();
		expect(screen.getByText("Bilal")).toBeVisible();
		expect(screen.getByLabelText(/^Student/)).toHaveValue("11"); // plan V29
		await user.click(screen.getByRole("button", { name: "Redeem" }));
		await waitFor(() =>
			expect(vouchersApi.redeem).toHaveBeenCalledWith({ code: "sys abcde fghjk", student: 11 }),
		);
		expect(
			await screen.findByText("Your subscription has started. The academy will set your lesson times."),
		).toBeVisible();
		expect(screen.getByRole("link", { name: "My subscriptions" })).toHaveAttribute(
			"href",
			"/learning/subscriptions",
		);
	});

	it("waits for a parent to choose one of two children", async () => {
		vi.mocked(vouchersApi.check).mockResolvedValue(
			codePreview({ students: [{ id: 11, name: "Yusuf" }, { id: 12, name: "Maryam" }] }),
		);
		const user = userEvent.setup();
		await check(user);
		const select = await screen.findByLabelText(/^Student/);
		expect(select).toHaveValue("");
		expect(screen.getByRole("button", { name: "Redeem" })).toBeDisabled();
		await user.selectOptions(select, "12");
		await user.click(screen.getByRole("button", { name: "Redeem" }));
		await waitFor(() =>
			expect(vouchersApi.redeem).toHaveBeenCalledWith({ code: "sys abcde fghjk", student: 12 }),
		);
	});

	it("renews a chosen subscription at the price it shows", async () => {
		vi.mocked(vouchersApi.check).mockResolvedValue(
			codePreview({
				kind: "renewal",
				teacher: null,
				students: [],
				subscriptions: [
					{
						subscription_id: 7,
						student: { id: 11, name: "Yusuf" },
						course: { id: 3, name_en: "Tajweed", name_ar: "تجويد" },
						package: { id: 4, name_en: "Monthly", name_ar: "شهري" },
						term_ends_on: "2026-06-30",
						price_minor: 120000,
						currency: "EGP",
					},
				],
			}),
		);
		vi.mocked(vouchersApi.redeem).mockResolvedValue(redemption({ kind: "renewal" }));
		const user = userEvent.setup();
		await check(user);
		const choice = await screen.findByLabelText(/^Subscription to renew/);
		expect(within(choice).getByRole("option", { name: "Yusuf · Tajweed — Monthly · renews at EGP 1,200.00" })).toBeInTheDocument();
		expect(choice).toHaveValue("7");
		await user.click(screen.getByRole("button", { name: "Redeem" }));
		await waitFor(() =>
			expect(vouchersApi.redeem).toHaveBeenCalledWith({ code: "sys abcde fghjk", subscription: 7 }),
		);
		expect(await screen.findByText("The subscription is renewed. The code paid its invoice.")).toBeVisible();
	});

	it("explains a renewal with nothing to renew", async () => {
		vi.mocked(vouchersApi.check).mockResolvedValue(
			codePreview({ kind: "renewal", students: [], subscriptions: [] }),
		);
		const user = userEvent.setup();
		await check(user);
		expect(
			await screen.findByText(
				"None of your subscriptions can be renewed with this code. It renews a Tajweed subscription that is active, paused or expired and not renewed yet.",
			),
		).toBeVisible();
		expect(screen.queryByRole("button", { name: "Redeem" })).toBeNull();
	});

	it("points a discount at the invoices", async () => {
		vi.mocked(vouchersApi.check).mockResolvedValue(
			codePreview({
				kind: "discount",
				course: null,
				package: null,
				teacher: null,
				sessions_total: null,
				students: [],
				discount: { kind: "percent", value: 10, currency: "" },
			}),
		);
		const user = userEvent.setup();
		await check(user);
		expect(await screen.findByText("Open the invoice you want to reduce and apply the code there.")).toBeVisible();
		expect(screen.getByText("10%")).toBeVisible();
		expect(screen.getByRole("link", { name: "My invoices" })).toHaveAttribute("href", "/learning/invoices");
		expect(screen.queryByRole("button", { name: "Redeem" })).toBeNull();
	});

	it.each([
		[400, { code: "vouchers.invalid" }, "This code isn't valid."],
		[409, { detail: "x", code: "vouchers.used" }, "This code has already been used."],
		[409, { detail: "x", code: "vouchers.expired" }, "This code has expired."],
		[409, { detail: "x", code: "vouchers.unavailable" }, "This code can't be used right now. Contact the academy."],
		[429, { detail: "Request was throttled." }, "Too many tries. Wait a while and try again."],
	])("says why a %i refused the check", async (status, data, text) => {
		vi.mocked(vouchersApi.check).mockRejectedValueOnce(refused(status, data));
		const user = userEvent.setup();
		await check(user);
		expect(await screen.findByText(text)).toBeVisible();
		expect(screen.queryByRole("button", { name: "Redeem" })).toBeNull();
	});

	it("says why the redemption was refused", async () => {
		vi.mocked(vouchersApi.redeem).mockRejectedValueOnce(
			refused(409, { detail: "x", code: "vouchers.wrong_course" }),
		);
		const user = userEvent.setup();
		await check(user);
		await user.click(await screen.findByRole("button", { name: "Redeem" }));
		expect(await screen.findByText("This code is for another course.")).toBeVisible();
	});

	it("needs a code before it checks", async () => {
		const user = userEvent.setup();
		renderWithRouter(<RedeemCodePage />, { extraPaths: LINKS });
		await user.click(screen.getByRole("button", { name: "Check" }));
		expect(await screen.findByText("Enter the code.")).toBeVisible();
		expect(vouchersApi.check).not.toHaveBeenCalled();
	});

	it("reads in Arabic and keeps the code left to right", async () => {
		await act(async () => {
			await i18n.changeLanguage("ar");
		});
		const user = userEvent.setup();
		renderWithRouter(<RedeemCodePage />, { extraPaths: LINKS });
		const input = screen.getByLabelText(/^الكود/);
		expect(input).toHaveAttribute("dir", "ltr");
		await user.type(input, "sys abcde fghjk");
		await user.click(screen.getByRole("button", { name: "تحقّق" }));
		expect(await screen.findByRole("heading", { name: "هذا الكود يبدأ اشتراكًا" })).toBeVisible();
		expect(screen.getByText("تجويد")).toBeVisible();
	});
});
```

In `dashboard/src/routes/permissions.test.ts`, in `FEATURE_SCREENS`, after the B3f billing line: `"/_authed/learning/codes": "system_codes", // B3f`.

In `dashboard/src/features/shell/nav.test.ts`:
- "ships the grouped admin areas in order": insert `"/learning/codes",` after `"/learning/wallet",`;
- "names a feature on exactly the items that belong to one": add `"/learning/codes": "system_codes",` after `"/learning/wallet": "balances",`;
- "shows students and parents their sessions, subscriptions and invoices": insert `"/learning/codes", // B3f` after `"/learning/wallet", // B3e`.

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/vouchers/RedeemCodePage.test.tsx src/features/shell/nav.test.ts src/routes/permissions.test.ts`
Expected: FAIL (`Cannot find module './RedeemCodePage'`; no `/learning/codes` item or route).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/vouchers/RedeemCodePage.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { parseApiError } from "@/features/identity/api";
import { useFieldError } from "@/lib/field-error";
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
	Field,
	Input,
	Select,
	SubmitButton,
} from "@/ui";
import { vouchersApi } from "./api";
import { useCheckCode, useVoucherMutation } from "./queries";
import {
	type CodeFormValues,
	codeFormSchema,
	discountText,
	type NamedRef,
	type Preview,
	type Redemption,
} from "./schemas";

const link = "text-primary-text underline-offset-4 hover:underline";

/** B3f §6, Family → Redeem a code: check a code, then redeem an activation
 * for a student or a renewal for a subscription; a discount is applied on
 * its invoice. Server errors, the 429 included, show by code. */
export function RedeemCodePage() {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const check = useCheckCode();
	const redeem = useVoucherMutation(vouchersApi.redeem);
	const [typed, setTyped] = useState("");
	const [preview, setPreview] = useState<Preview | null>(null);
	const [done, setDone] = useState<Redemption | null>(null);
	const [problem, setProblem] = useState("");
	const [student, setStudent] = useState("");
	const [subscription, setSubscription] = useState("");
	const {
		register,
		handleSubmit,
		reset,
		formState: { errors },
	} = useForm<CodeFormValues>({
		resolver: zodResolver(codeFormSchema),
		defaultValues: { code: "" },
	});
	const name = (ref: NamedRef | null) =>
		ref ? (i18n.language === "ar" ? ref.name_ar : ref.name_en) : "";
	const explain = (error: unknown) =>
		parseApiError(error).throttled ? t("vouchers.errors.throttled") : errorText(error, t);

	async function onCheck(values: CodeFormValues) {
		setProblem("");
		setDone(null);
		setPreview(null);
		try {
			const shown = await check.mutateAsync(values.code.trim());
			setTyped(values.code.trim());
			setPreview(shown);
			// Plan V29: a lone choice is preselected.
			setStudent(shown.students.length === 1 ? String(shown.students[0].id) : "");
			setSubscription(
				shown.subscriptions.length === 1 ? String(shown.subscriptions[0].subscription_id) : "",
			);
		} catch (error) {
			setProblem(explain(error));
		}
	}

	async function onRedeem() {
		if (!preview) return;
		setProblem("");
		const targets =
			preview.kind === "activation"
				? { student: Number(student) }
				: { subscription: Number(subscription) };
		try {
			setDone(await redeem.mutateAsync({ code: typed, ...targets }));
		} catch (error) {
			setProblem(explain(error));
		}
	}

	function startOver() {
		setPreview(null);
		setDone(null);
		setProblem("");
		reset({ code: "" });
	}

	const chosen = preview?.kind === "activation" ? student : subscription;

	return (
		<div className="flex flex-col gap-4">
			<Card>
				<CardContent className="flex flex-col gap-4 pt-6">
					<p className="text-sm text-muted-foreground">{t("vouchers.family.intro")}</p>
					<form onSubmit={handleSubmit(onCheck)} className="flex flex-wrap items-end gap-3" noValidate>
						<Field id="family-code" label={t("vouchers.family.code")} error={fieldError(errors.code?.message)} required>
							<Input dir="ltr" className="font-mono" autoComplete="off" {...register("code")} />
						</Field>
						<SubmitButton pending={check.isPending}>{t("vouchers.family.check")}</SubmitButton>
					</form>
				</CardContent>
			</Card>
			{problem ? (
				<Alert variant="destructive">
					<AlertDescription>{problem}</AlertDescription>
				</Alert>
			) : null}
			{done ? (
				<Alert>
					<AlertDescription className="flex flex-col gap-2">
						<span>
							{t(done.kind === "activation" ? "vouchers.family.started" : "vouchers.family.renewed")}
						</span>
						<span className="flex flex-wrap gap-3">
							<Link to="/learning/subscriptions" className={link}>
								{t("vouchers.family.mySubscriptions")}
							</Link>
							<Button type="button" size="sm" variant="outline" onClick={startOver}>
								{t("vouchers.family.another")}
							</Button>
						</span>
					</AlertDescription>
				</Alert>
			) : null}
			{preview && !done ? (
				<Card>
					<CardHeader className="border-b border-border">
						<CardTitle>{t(`vouchers.family.titles.${preview.kind}`)}</CardTitle>
					</CardHeader>
					<CardContent className="flex flex-col gap-4">
						<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
							{preview.course ? <Fact label={t("vouchers.facts.course")}>{name(preview.course)}</Fact> : null}
							{preview.package ? <Fact label={t("vouchers.facts.package")}>{name(preview.package)}</Fact> : null}
							{preview.sessions_total !== null ? (
								<Fact label={t("vouchers.facts.sessions")}>{preview.sessions_total}</Fact>
							) : null}
							{preview.teacher ? <Fact label={t("vouchers.facts.teacher")}>{preview.teacher.full_name}</Fact> : null}
							{preview.discount ? (
								<Fact label={t("vouchers.facts.discount")}>
									<span dir="ltr">{discountText(preview.discount, i18n.language)}</span>
								</Fact>
							) : null}
							<Fact label={t("vouchers.facts.expires")}>{formatDay(preview.expires_on, i18n.language)}</Fact>
						</dl>
						{preview.kind === "discount" ? (
							<p className="flex flex-wrap gap-2 text-sm">
								<span>{t("vouchers.family.discountHint")}</span>
								<Link to="/learning/invoices" className={link}>
									{t("vouchers.family.myInvoices")}
								</Link>
							</p>
						) : preview.kind === "activation" && preview.students.length === 0 ? (
							<p className="text-sm text-muted-foreground">{t("vouchers.family.noStudents")}</p>
						) : preview.kind === "renewal" && preview.subscriptions.length === 0 ? (
							<p className="text-sm text-muted-foreground">
								{t("vouchers.family.noRenewable", { course: name(preview.course) })}
							</p>
						) : (
							<div className="flex flex-wrap items-end gap-3">
								{preview.kind === "activation" ? (
									<Field id="family-student" label={t("vouchers.family.student")} required>
										<Select value={student} onChange={(e) => setStudent(e.target.value)}>
											<option value="">—</option>
											{preview.students.map((s) => (
												<option key={s.id} value={s.id}>
													{s.name}
												</option>
											))}
										</Select>
									</Field>
								) : (
									<Field id="family-subscription" label={t("vouchers.family.subscription")} required>
										<Select value={subscription} onChange={(e) => setSubscription(e.target.value)}>
											<option value="">—</option>
											{preview.subscriptions.map((s) => (
												<option key={s.subscription_id} value={s.subscription_id}>
													{t("vouchers.family.renewalChoice", {
														student: s.student.name,
														course: name(s.course),
														package: name(s.package),
														price: formatMoney(s.price_minor, s.currency, i18n.language),
													})}
												</option>
											))}
										</Select>
									</Field>
								)}
								<Button type="button" disabled={!chosen || redeem.isPending} onClick={onRedeem}>
									{t("vouchers.family.redeem")}
								</Button>
							</div>
						)}
					</CardContent>
				</Card>
			) : null}
		</div>
	);
}
```

`dashboard/src/features/vouchers/index.ts`: add `export { RedeemCodePage } from "./RedeemCodePage";`.

Create `dashboard/src/routes/_authed/learning.codes.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { RedeemCodePage } from "@/features/vouchers";
import { PageHeader } from "@/ui";

/** B3f §6: Family → Redeem a code (students and parents, `learning`). */
export const Route = createFileRoute("/_authed/learning/codes")({
	staticData: { feature: "system_codes" },
	component: function LearningCodesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("vouchers.family.title"));
		return (
			<>
				<PageHeader title={t("vouchers.family.title")} />
				<RedeemCodePage />
			</>
		);
	},
});
```

`dashboard/src/features/shell/nav.ts`, under `// ── phase B3 ──`, right after the B3e `/learning/wallet` item:

```ts
	// B3f: a student or parent redeems a system code (F-16, plan V24).
	{
		to: "/learning/codes",
		labelKey: "vouchers.family.nav",
		icon: TicketCheck,
		group: "learning",
		requiresRole: ["student", "parent"],
		feature: "system_codes",
	},
```

Regenerate the route tree: `$DASH pnpm exec vite build`.

- [ ] **Step 4: Run the tests, types, lint, commit**

Run: `$DASH pnpm vitest run src/features/vouchers src/features/shell src/routes`
Expected: PASS.
Run: `just test-frontend`, `just lint-frontend`, `$DASH pnpm exec biome check --write src e2e`

```bash
git -C dashboard add src/features/vouchers src/routes/_authed/learning.codes.tsx src/routeTree.gen.ts src/features/shell src/routes/permissions.test.ts
git -C dashboard commit -m "feat(vouchers): a family checks and redeems a system code (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: Dashboard — Apply a code on the invoice page

**Files:**
- Create: `dashboard/src/features/vouchers/ApplyCode.tsx`, `dashboard/src/features/vouchers/ApplyCode.test.tsx`
- Modify: `dashboard/src/features/vouchers/index.ts`, `dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`, `dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`

**Interfaces:**
- Consumes: `vouchersApi.redeem` (family) and `vouchersApi.redeemByCode` (office), `useVoucherMutation`, `codeFormSchema`; `useMe` from `@/features/identity/queries` (the family's role and children); `applyServerErrors` from `@/lib/form-errors`.
- Produces: `ApplyCode({ invoice, office })` for billing's `actions` (spec §6): shown while the invoice is not void and has a balance, `system_codes` and `invoices` are on, and the viewer is the invoice's student, a parent of that student (not a paying sibling), or office staff with `voucher.update`, `payment.create` and `invoice.view`. Its toast is "Discount of {amount} applied." (plan V27).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/vouchers/ApplyCode.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import type { InvoiceDetail } from "@/features/billing/schemas";
import { identityApi } from "@/features/identity/api";
import { CanProvider } from "@/features/identity/permissions";
import type { Me } from "@/features/identity/schemas";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { familyInvoice, invoiceDetail } from "@/test/billing-fixtures";
import { renderWithRouter } from "@/test/render";
import { redemption } from "@/test/voucher-fixtures";
import { vouchersApi } from "./api";
import { ApplyCode } from "./ApplyCode";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		vouchersApi: { ...actual.vouchersApi, redeem: vi.fn(), redeemByCode: vi.fn() },
	};
});
vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { ...actual.identityApi, me: vi.fn() } };
});

const FEATURES = ["system_codes", "invoices"] as const;
const parentOf = (...ids: number[]): Me => ({
	id: 30,
	email: "omar@demo.test",
	full_name: "Omar",
	role: "parent",
	profiles: ["parent"],
	children: ids.map((id) => ({ id, full_name: `Child ${id}`, student_profile_id: id })),
	features: [...FEATURES],
});
const discounted = redemption({ kind: "discount", subscription_id: null, amount_minor: 2000 });

function renderApply(me: Me, invoice: InvoiceDetail = familyInvoice(), office = false) {
	vi.mocked(identityApi.me).mockResolvedValue(me);
	return renderWithRouter(
		<CanProvider me={me}>
			<p>actions mounted</p>
			<ApplyCode invoice={invoice} office={office} />
		</CanProvider>,
	);
}

describe("ApplyCode", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(vouchersApi.redeem).mockResolvedValue(discounted);
		vi.mocked(vouchersApi.redeemByCode).mockResolvedValue(discounted);
	});

	it("lets a parent of the invoice's student apply a code", async () => {
		const user = userEvent.setup();
		renderApply(parentOf(11));
		await user.click(await screen.findByRole("button", { name: "Apply a code" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Code/), " sys dsc0n 12345 ");
		await user.click(within(dialog).getByRole("button", { name: "Apply" }));
		await waitFor(() =>
			expect(vouchersApi.redeem).toHaveBeenCalledWith({ code: "sys dsc0n 12345", invoice: 51 }),
		);
		expect(await screen.findByText("Discount of EGP 20.00 applied.")).toBeVisible();
		expect(vouchersApi.redeemByCode).not.toHaveBeenCalled();
	});

	it("lets the student apply a code to their own invoice", async () => {
		renderApply({ ...parentOf(), id: 11, role: "student", children: undefined, profiles: ["student"] });
		expect(await screen.findByRole("button", { name: "Apply a code" })).toBeVisible();
	});

	it("posts the office's code to codes/redeem/", async () => {
		const user = userEvent.setup();
		renderApply(adminWith(...FEATURES), invoiceDetail(), true);
		await user.click(await screen.findByRole("button", { name: "Apply a code" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Code/), "SYS-DSC0N-12345");
		await user.click(within(dialog).getByRole("button", { name: "Apply" }));
		await waitFor(() =>
			expect(vouchersApi.redeemByCode).toHaveBeenCalledWith({ code: "SYS-DSC0N-12345", invoice: 51 }),
		);
	});

	it("says why a code was refused, the 429 included", async () => {
		vi.mocked(vouchersApi.redeem)
			.mockRejectedValueOnce(
				new AxiosError("Conflict", "409", undefined, undefined, {
					status: 409,
					data: { detail: "x", code: "vouchers.invoice_discounted" },
				} as never),
			)
			.mockRejectedValueOnce(
				new AxiosError("Throttled", "429", undefined, undefined, {
					status: 429,
					data: { detail: "Request was throttled." },
				} as never),
			);
		const user = userEvent.setup();
		renderApply(parentOf(11));
		await user.click(await screen.findByRole("button", { name: "Apply a code" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Code/), "SYS-DSC0N-12345");
		await user.click(within(dialog).getByRole("button", { name: "Apply" }));
		expect(await within(dialog).findByText("This invoice already has a discount code.")).toBeVisible();
		await user.click(within(dialog).getByRole("button", { name: "Apply" }));
		expect(await within(dialog).findByText("Too many tries. Wait a while and try again.")).toBeVisible();
	});

	it.each<[string, Me, InvoiceDetail, boolean]>([
		["a paying sibling's parent", parentOf(12), familyInvoice(), false],
		["a void invoice", parentOf(11), familyInvoice({ status: "void", balance_minor: 0 }), false],
		["nothing owed", parentOf(11), familyInvoice({ status: "paid", balance_minor: 0 }), false],
		["system codes off", { ...parentOf(11), features: ["invoices"] }, familyInvoice(), false],
		["invoices off", { ...parentOf(11), features: ["system_codes"] }, familyInvoice(), false],
		["staff without payment.create", { ...staffMe("voucher.update", "invoice.view"), features: [...FEATURES] }, invoiceDetail(), true],
	])("is not offered for %s", async (_, me, invoice, office) => {
		renderApply(me, invoice, office);
		expect(await screen.findByText("actions mounted")).toBeVisible();
		if (!office) {
			// Wait for the family's `me` (role and children) before asserting absence.
			await waitFor(() => expect(identityApi.me).toHaveBeenCalled());
			await act(async () => {
				await vi.mocked(identityApi.me).mock.results[0]?.value;
			});
		}
		expect(screen.queryByRole("button", { name: "Apply a code" })).toBeNull();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `$DASH pnpm vitest run src/features/vouchers/ApplyCode.test.tsx`
Expected: FAIL (`Cannot find module './ApplyCode'`).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/vouchers/ApplyCode.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import type { InvoiceDetail } from "@/features/billing/schemas";
import { useFillOnOpen } from "@/features/finance/shared";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { useMe } from "@/features/identity/queries";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { formatMoney } from "@/lib/money";
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
	toast,
} from "@/ui";
import { vouchersApi } from "./api";
import { useVoucherMutation } from "./queries";
import { type CodeFormValues, codeFormSchema, type Redemption } from "./schemas";

function ApplyCodeDialog({ invoice, office }: { invoice: InvoiceDetail; office: boolean }) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	// The family's route is throttled (F-13); the office's is not.
	const save = useVoucherMutation(office ? vouchersApi.redeemByCode : vouchersApi.redeem);
	const initial = useCallback((): CodeFormValues => ({ code: "" }), []);
	const {
		register,
		handleSubmit,
		setError,
		setFocus,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<CodeFormValues>({ resolver: zodResolver(codeFormSchema), defaultValues: initial() });
	useFillOnOpen({ open, ready: true, reset, setFocus, initial, first: "code" });

	async function onSubmit(values: CodeFormValues) {
		let result: Redemption;
		try {
			result = await save.mutateAsync({ code: values.code.trim(), invoice: invoice.id });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.throttled) {
				setError("root.server", { message: "vouchers.errors.throttled" });
			}
			return;
		}
		setOpen(false);
		toast({
			description: t("vouchers.apply.done", {
				amount: formatMoney(result.amount_minor, result.currency, i18n.language),
			}),
			variant: "success",
		});
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("vouchers.apply.action")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("vouchers.apply.title")}</DialogTitle>
				<DialogDescription>{t("vouchers.apply.body")}</DialogDescription>
				<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
					<Field id="apply-code" label={t("vouchers.apply.code")} error={fieldError(errors.code?.message)} required>
						<Input dir="ltr" className="font-mono" autoComplete="off" {...register("code")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>{t("vouchers.apply.save")}</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** B3f §6, F-16, F-20: "Apply a code" on an invoice with a balance, for the
 * invoice's student or a parent of that student (a paying sibling never),
 * or office staff with voucher.update, payment.create and invoice.view. */
export function ApplyCode({ invoice, office }: { invoice: InvoiceDetail; office: boolean }) {
	const can = useCan();
	const hasFeature = useHasFeature();
	const { data: me } = useMe({ enabled: !office });
	const owing = invoice.status !== "void" && invoice.balance_minor > 0;
	const on = hasFeature("system_codes") && hasFeature("invoices");
	const student = invoice.student.id;
	const family =
		!office &&
		me !== undefined &&
		((me.role === "student" && me.id === student) ||
			(me.role === "parent" && (me.children ?? []).some((child) => child.id === student)));
	const staff =
		office && can("voucher.update") && can("payment.create") && can("invoice.view");
	if (!owing || !on || !(family || staff)) return null;
	return <ApplyCodeDialog invoice={invoice} office={office} />;
}
```

`dashboard/src/features/vouchers/index.ts`: add `export { ApplyCode } from "./ApplyCode";`.

`dashboard/src/routes/_authed/billing.invoices.$invoiceId.tsx`: import `ApplyCode` beside `RemoveDiscount` and make `actions`

```tsx
					actions={(invoice) => (
						<>
							<PayFromWallet invoice={invoice} office />
							<ApplyCode invoice={invoice} office />
						</>
					)}
```

`dashboard/src/routes/_authed/learning.invoices.$invoiceId.tsx`: import `ApplyCode` from `@/features/vouchers` and add `<ApplyCode invoice={invoice} office={false} />` after `<PayFromWallet invoice={invoice} office={false} />`.

- [ ] **Step 4: Run the tests, types, lint, commit**

Run: `$DASH pnpm vitest run src/features/vouchers src/features/billing`
Expected: PASS.
Run: `just test-frontend`, `just lint-frontend`, `$DASH pnpm exec biome check --write src e2e`

```bash
git -C dashboard add src/features/vouchers 'src/routes/_authed/billing.invoices.$invoiceId.tsx' 'src/routes/_authed/learning.invoices.$invoiceId.tsx'
git -C dashboard commit -m "feat(vouchers): apply a discount code on an invoice, for the family and the office (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 15: The e2e journey

**Files:**
- Create: `dashboard/e2e/b3-codes.spec.ts`

**Interfaces:**
- Consumes: the whole slice through Caddy; `manage("set_features", …)`; `login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`, `acceptInvite`, `invoiceHeader` from `e2e/fixtures.ts`. Rerun-safe (spec §9): a fresh parent and child per run, batches noted "E2E {stamp}" and the table filtered to them, the discount invoice in USD and paid at the end. Code payments are never revenue, so `b3-finance.spec.ts`'s EGP deltas are untouched even when local runs are `fullyParallel`.

- [ ] **Step 1: Write the spec**

```ts
import { expect, type Locator, type Page, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	invoiceHeader,
	login,
} from "./fixtures";
import { manage } from "./manage";

const CODE = /^SYS-[0-9A-Z]{5}-[0-9A-Z]{5}$/;

/** On System codes, generate a batch and read its codes (the table is
 * filtered to the new batch on success, plan V26). */
async function generate(
	page: Page,
	fill: (dialog: Locator) => Promise<void>,
	count: number,
): Promise<string[]> {
	await page.goto(`${DEMO_URL}/app/billing/codes`);
	await page.getByRole("button", { name: "Generate codes" }).click();
	const dialog = page.getByRole("dialog");
	await expect(dialog.getByLabel(/^Code type/)).toBeEnabled();
	await fill(dialog);
	await dialog.getByRole("button", { name: "Generate", exact: true }).click();
	await expect(page.getByText("Codes generated.", { exact: true })).toBeVisible();
	const codes = page.getByRole("table").getByText(CODE);
	await expect(codes).toHaveCount(count);
	return codes.allTextContents();
}

// B3f spec §9: the admin generates two activation codes; the parent redeems
// the first (typed in lower case with spaces) for their child; the code is
// then used, the second is voided; the parent applies a 10 % discount code
// to a 200.00 USD invoice and the admin records the 180.00 left.
test("a family redeems an activation code and a discount code; used and void codes are refused", async ({
	page,
	browser,
}) => {
	// 1. A database seeded before B3f would not have the switch on.
	manage("set_features", "demo", "--on", "invoices", "system_codes");
	const stamp = Date.now();
	const parent = `E2E Codes Payer ${stamp}`;
	const parentEmail = `e2e-codes-${stamp}@e2e.test`;
	const child = `E2E Codes Child ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// 2. The parent (invited by email) and the child, linked.
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/^full name/i).fill(parent);
	await page.getByLabel(/^email/i).fill(parentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);
	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(child);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	await page.getByLabel("Find a parent").fill(parent);
	await page.getByRole("button", { name: `Link ${parent}`, exact: true }).click();
	await expect(page.getByRole("button", { name: `Unlink ${parent}`, exact: true })).toBeVisible();

	// 3. Two activation codes for Quran Memorisation with Ustadha Maryam.
	const [first, second] = await generate(
		page,
		async (dialog) => {
			await dialog.getByLabel(/^Code type/).selectOption("activation");
			await dialog.getByLabel(/^Course/).selectOption({ label: "Quran Memorisation" });
			await dialog.getByLabel(/^Teacher/).selectOption({ label: "Ustadha Maryam" });
			await dialog.getByLabel(/^Package/).selectOption({ label: "Monthly, 2 a week" });
			await dialog.getByLabel(/^Number of codes/).fill("2");
			await dialog.getByLabel(/^Valid for/).fill("30");
			await dialog.getByLabel(/^Note/).fill(`E2E ${stamp} activation`);
		},
		2,
	);

	// 4. The parent redeems the first code, typed in lower case with spaces.
	const guardian = await acceptInvite(browser, parentEmail, "e2e-Codes-2026", parent);
	await guardian.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await guardian.goto(`${DEMO_URL}/app/learning/codes`);
	await guardian.getByLabel(/^Code/).fill(first.toLowerCase().replaceAll("-", " "));
	await guardian.getByRole("button", { name: "Check" }).click();
	await expect(guardian.getByRole("heading", { name: "This code starts a subscription" })).toBeVisible();
	await expect(guardian.getByText("Quran Memorisation", { exact: true })).toBeVisible();
	await expect(guardian.getByText("Monthly, 2 a week", { exact: true })).toBeVisible();
	await expect(guardian.getByLabel(/^Student/)).toHaveValue(/\d+/); // the lone child
	await guardian.getByRole("button", { name: "Redeem", exact: true }).click();
	await expect(
		guardian.getByText("Your subscription has started. The academy will set your lesson times.", {
			exact: true,
		}),
	).toBeVisible();
	await guardian.getByRole("link", { name: "My subscriptions" }).click();
	await expect(guardian).toHaveURL(/\/app\/learning\/subscriptions$/);
	await expect(guardian.getByRole("heading", { name: "Quran Memorisation" })).toBeVisible();
	await expect(guardian.getByText(new RegExp(child))).toBeVisible();
	// Its invoice reads Paid, with a "System code" payment (the child's only one).
	await guardian.goto(`${DEMO_URL}/app/learning/invoices`);
	const activationInvoice = guardian.getByRole("link", { name: /^INV-\d{6}$/ });
	await expect(activationInvoice).toHaveCount(1);
	const activationNumber = (await activationInvoice.textContent()) ?? "";
	await activationInvoice.click();
	await expect(invoiceHeader(guardian, activationNumber).getByText("Paid", { exact: true })).toBeVisible();
	await expect(guardian.locator("li").filter({ hasText: "· System code" })).toContainText(first);

	// 5. The same code again is already used.
	await guardian.goto(`${DEMO_URL}/app/learning/codes`);
	await guardian.getByLabel(/^Code/).fill(first);
	await guardian.getByRole("button", { name: "Check" }).click();
	await expect(guardian.getByText("This code has already been used.", { exact: true })).toBeVisible();

	// 6. The admin voids the second code; the parent is told it isn't valid.
	await page.goto(`${DEMO_URL}/app/billing/codes`);
	await page.getByLabel("Search codes").fill(second);
	const voidRow = page.getByRole("row", { name: new RegExp(second) });
	await voidRow.getByRole("button", { name: "Void" }).click();
	await page.getByRole("dialog").getByRole("button", { name: "Void code" }).click();
	await expect(page.getByText("Code voided.", { exact: true })).toBeVisible();
	await expect(voidRow.getByRole("button", { name: "Void" })).toHaveCount(0);
	await expect(voidRow.getByText("Void", { exact: true })).toBeVisible();
	await guardian.goto(`${DEMO_URL}/app/learning/codes`);
	await guardian.getByLabel(/^Code/).fill(second);
	await guardian.getByRole("button", { name: "Check" }).click();
	await expect(guardian.getByText("This code isn't valid.", { exact: true })).toBeVisible();

	// 7. A 200.00 USD invoice for the child and a 10 % discount code.
	const dueOn = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
	await page.goto(`${DEMO_URL}/app/billing/invoices/new`);
	await page.getByLabel("Find a student").fill(child);
	await page.getByLabel(/^Student/).selectOption({ label: child });
	await page.getByLabel(/^Currency/).selectOption("USD");
	await page.getByLabel(/^Amount/).fill("200.00");
	await page.getByLabel(/^Due/).fill(dueOn);
	await page.getByLabel(/^Description/).fill(`E2E codes ${stamp}`);
	await page.getByRole("button", { name: "Create invoice" }).click();
	await expect(page).toHaveURL(/\/app\/billing\/invoices\/\d+$/);
	const invoiceUrl = page.url();
	const invoiceId = invoiceUrl.match(/invoices\/(\d+)$/)?.[1] ?? "";
	const number = (await page.getByRole("heading", { name: /^INV-\d{6}$/ }).textContent()) ?? "";
	const [gift] = await generate(
		page,
		async (dialog) => {
			await dialog.getByLabel(/^Code type/).selectOption("discount");
			await dialog.getByLabel(/^Discount type/).selectOption("percent");
			await dialog.getByLabel(/^Percentage/).fill("10");
			await dialog.getByLabel(/^Valid for/).fill("30");
			await dialog.getByLabel(/^Note/).fill(`E2E ${stamp} discount`);
		},
		1,
	);
	await guardian.goto(`${DEMO_URL}/app/learning/invoices/${invoiceId}`);
	await guardian.getByRole("button", { name: "Apply a code" }).click();
	const apply = guardian.getByRole("dialog");
	await apply.getByLabel(/^Code/).fill(gift);
	await apply.getByRole("button", { name: "Apply", exact: true }).click();
	await expect(guardian.getByText("Discount of $20.00 applied.", { exact: true })).toBeVisible();
	await expect(invoiceHeader(guardian, number).getByText("Partly paid", { exact: true })).toBeVisible();
	const balance = guardian
		.locator("dl > div")
		.filter({ has: guardian.getByText("Balance", { exact: true }) })
		.getByRole("definition");
	await expect(balance).toHaveText("$180.00");
	const discountRow = guardian.locator("li").filter({ hasText: "· System code" });
	await expect(discountRow).toHaveCount(1);
	await expect(discountRow).toContainText("$20.00");
	await expect(discountRow).toContainText(gift);

	// 8. The admin records the 180.00 left in cash: nothing open stays behind.
	await page.goto(invoiceUrl);
	await page.getByRole("button", { name: "Record payment" }).click();
	const record = page.getByRole("dialog");
	await expect(record.getByLabel(/^Amount/)).toHaveValue("180.00");
	await record.getByLabel(/^Method/).selectOption("cash");
	await record.getByRole("button", { name: "Record payment" }).click();
	await expect(invoiceHeader(page, number).getByText("Paid", { exact: true })).toBeVisible();
	await guardian.context().close();
});
```

- [ ] **Step 2: Run it against this stream's fresh stack, twice**

Run: `just e2e e2e/b3-codes.spec.ts` (stack up via `just dev-backend`; rebuild images first if dependencies changed, and use a fresh stack before trusting the result: `vouchers.0001` and `billing.0010` must have run through `migrate_schemas`).
Expected: PASS. Run it a second time: it must pass again (a fresh parent and child, batches filtered to this run; nothing seeded is read; plan V30's throttle budget).

- [ ] **Step 3: Commit**

```bash
git -C dashboard add e2e/b3-codes.spec.ts
git -C dashboard commit -m "test(e2e): redeem activation and discount codes; used and void codes refused (B3f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: Gates

**Files:** none new; fix what the gates find in the task that owns it.

- [ ] **Step 1: Backend**

Run: `just test-backend`
Expected: PASS, total coverage ≥ 80 %. Check `etqan/vouchers/services/*.py`, `etqan/vouchers/api/views.py` and the new billing functions are fully covered (`--cov-report=term-missing`).

- [ ] **Step 2: Lint, boundaries and secrets**

Run: `just lint` (ruff, biome, the colour check, `lint-imports`, and on the trunk's justfile `secrets`: gitleaks over the tracked files of meta and its submodules). If `just --list` shows no `secrets` recipe (this meta branch predates it, plan V31), also run `just --justfile /home/abdulkhalek/Projects/etqan_tutor/justfile --working-directory . secrets`.
Expected: PASS, including the five new vouchers contracts and the extended platform and gateways lists. If a contract fails, do not weaken it: move the import behind a service. No leaks (the tests carry no secrets).

- [ ] **Step 3: Dashboard**

Run: `$DASH pnpm test:coverage`
Run: `just test-frontend`
Expected: PASS; lines and statements ≥ 80, branches and functions ≥ 70.

- [ ] **Step 4: End to end**

Run: `just e2e` (the whole suite, on a fresh stack).
Expected: PASS, including `b3-codes.spec.ts`, `b3-wallet.spec.ts` (Move to balance now reads `movable`), `b3-finance.spec.ts` (EGP deltas only; code payments are never revenue) and `billing.spec.ts`.

- [ ] **Step 5: Ledger, PRs and report**

- D43 and D44 are already recorded from the spec. The orchestrator records the catalogue note (spec §7): `python3 scripts/orchestration/ledger.py decide --source "B3f spec F-25" --affects B2 B3 "Catalogue's _delete message reads 'is used by subscriptions or system codes' (B3f F-25); the code catalogue.in_use is unchanged."`.
- In the PR descriptions note: migrations `vouchers.0001_initial` and `billing.0010_payment_code`; the feature `system_codes` (built, off by default); the resource `voucher`; the throttle rates `voucher_redeem` and `voucher_redeem_ip`; the payment method `code` and the row flag `movable` (B3e's `MoveToWallet` reads it); `refuse_reserved_money` (alias `refuse_wallet_money`); `settle_with_code` returns the payment (plan V4); `invoices_issued` skips code-paid invoices (F-23, B5's finder unchanged); the catalogue message (F-25); no B2 file changed.
- Open PRs as Plan 15 did (`gh pr create --repo Etqan-agency/etqan_tutor_backend`, `…_dashboard`, then meta with `--repo Etqan-agency/etqan_tutor`); bump submodule pointers in meta only after both merge, with explicit paths (never `git commit -a`, never `git submodule`).

---
## Self-review against the spec

- **F-1** (new app, own contracts, services only, nobody imports it but the seeds): Task 1 (`TENANT_APPS`, the five contracts, the platform and gateways lists), Tasks 4–7 (services only), Task 8 (seeds through `vouchers.services`), Task 16 (`lint-imports`). **F-2** (three kinds; batch terms, code state): Tasks 1, 4. **F-3** (what each kind names; teacher in the course or any when none; scoped discount fixed for life; session count from the package): Task 1 checks, Task 4 (`_teacher`, `test_an_activation_teacher_…`), Task 6 scope, Task 11 dialog. **F-4** (percent half up, ≥ 1, capped; fixed in its currency; one per invoice): Task 4 validation, Task 6 (`discount_amount`, cap, `wrong_currency`, `invoice_discounted`). **F-5** (`code` payment on an invoice, no fee, reference, today, redeemer): Tasks 2, 3, 5. **F-6** (invoice whatever the setting; none while `invoices` is off or price 0; no back-fill): Tasks 3, 5. **F-7** (never revenue; a sale counts once): Task 2, Task 5 end to end. **F-8** (guards on the locked row; alias; `credit_payment`'s own check; manual paths refuse; flags; only vouchers writes or removes): Tasks 2, 3, 9. **F-9** (activation and renewal final; discount removed by the office, void with reason, invoice unfrozen): Tasks 6, 7, 12. **F-10** (stored unused/used/void, expired derived from today as a value; void with reason): Tasks 1, 4. **F-11** (inclusive validity on the academy calendar): Tasks 4, 5. **F-12** (alphabet, display, normalization, redraw, retry once): Task 4. **F-13** (family routes signed in; per-user and per-IP throttles; one 400 for unknown and void): Task 7. **F-14** (lock, check, work, mark used; DB checks; uniques; second discount checked under the invoice lock and rolled back): Tasks 1, 5, 6. **F-15** (lock order): Tasks 3, 5, 6 (relative order, plan V11). **F-16** (student or parent; sibling payer 404): Tasks 5–7, 14. **F-17** (activation today, no slots, D23, unavailable mapping, student 400): Task 5. **F-18** (renewal: course check, P4-10/D23 price, mapping incl. student, scheduling 409s pass): Tasks 5, 6 (preview price). **F-19** (discount via `invoice_for`, void, nothing due, scope, cap, the locked one-per-invoice check): Task 6; a checkout still open meanwhile is B3b's existing "needs attention" path, unchanged. **F-20** (generate 1–500 and a note; list, filters, exact `?code=`; CSV; void one; office redeem by id and text with the kind's codes; remove): Tasks 4, 7, 10–12. **F-21** (resource `voucher`, admins all, teachers none, `NotImpersonating` on redeem and remove): Task 7. **F-22** (`system_codes` built, off, requires nothing; 404s; discounts also need `invoices`; codes survive the switch): Tasks 1, 7. **F-23** (`invoices_issued` skips code-paid invoices; B5's finder unchanged): Task 3. **F-24** (en and ar): every locale block, real Arabic. **F-25** (`PROTECT`, catalogue's 409 message, teachers never deleted): Tasks 1, 4, 6, 9.
- **§3 data:** Task 1 (vouchers), Task 2 (billing). **§4.1 billing services:** Tasks 2, 3. **§4.2 vouchers services:** Tasks 4–6. **§5 API:** Task 7. **§6 dashboard:** Tasks 9–14. **§7 wiring:** Tasks 1, 7, 8, 13 (no B2 or B5 request). **§8 seeds:** Task 8. **§9 tests:** each backend bullet maps to a test in Tasks 1–8, each dashboard bullet to Tasks 9–14, the e2e to Task 15. **§10 out of scope:** nothing builds undoing an activation or renewal, sale prices, online code sales, batch edits, bulk void, look-alike mapping, per-student codes, pre-invoice discounts, start dates or slots on redemption, back-filling, notices or an expiry job.
- **Placeholder scan:** every code step carries its code; no "TBD", "similar to", or "add validation". **Type consistency:** `Redemption`, `Preview`, `Renewable`, `settle_with_code -> Payment | None`, `redeem(..., office=)`, `kind_of`, `find`, `remove_discount(voucher_id, *, reason, by)`, `vouchersApi.*`, `useVoucherMutation`, `VoucherRow.state` and the fixtures are named the same in every task that uses them.
- **No B2-owned file is edited and no hook is needed** (checked in the code): `create_subscription`, `renew_subscription`, `subscriptions_queryset`, `lock_subscription`, `renewal_starts_on` and `today` are exported by `etqan/scheduling/services/__init__.py`; vouchers only imports them, and the dashboard only imports `useChoices` and `useSubscriptions`. `refuse_if_archived` is not exported, so the preview mirrors its one rule with `features.enabled("subscription_archive")` and `archived_at` (spec §4.2 asks for the same rule, not the same function).

**Spec gaps and contradictions found (spec not edited):**
1. F-14 says "`used` ⇔ `redeemed_at` set", but F-9 and §3.1 keep a removed discount's history on a `void` row: the check is `used ⇒ redeemed_at`, `unused ⇒ no redeemed_at`, and a void row may keep it (plan V3).
2. §4.1's `settle_with_code(...) -> Invoice | None` leaves vouchers no way to store `payment_id`; it returns the `Payment | None` instead (plan V4).
3. `vouchers.invalid` is "400 on `code`", but the platform handler writes the error code under the same key `code`, so the body is `{"code": "vouchers.invalid"}`, which the dashboard already reads as the rule code; the request's `code` is a lenient `CharField` so every bad text gets that one answer (plan V5).
4. §9's lock order "discount: voucher < invoice < payment": a discount inserts its payment and locks no payment row; only removal locks one (plan V11, as Plan 40's W10 found for the wallet's pay).
5. F-13's per-user `ScopedRateThrottle` keys by user pk alone, which repeats across academies; both throttles are keyed by the schema too (plan V6).
6. §8 says the seeds use "vouchers services only", but generating an activation batch needs the course, package and teacher ids; they are read through catalogue's and identity's services (plan V16).
7. §4.2's preview applies "the same archive rule as `refuse_if_archived`", which scheduling does not export; the rule is mirrored without a B2 change (above).
8. §6 shows `RemoveDiscount` on the invoice page with `voucher.update` + `payment.update`, but finding the voucher by `codes/?code=` needs `voucher.view_any`; likewise the office's Redeem for a student needs `student.view_any` (and `subscription.view_any` for renewal) to list its targets. The dashboard hides them without those codes; the server checks only F-20's (plan V10).
9. §5 does not say how the office routes learn a code's kind before checking its extra codes; they read it without a lock first (`kind_of`, plan V9).
10. The gates ask for `just secrets` through `just lint`; this worktree's meta branch predates that recipe, so Task 16 falls back to the trunk's justfile (plan V31).
