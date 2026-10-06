# Slice B3e — Student wallet — Design

**Date:** 2026-10-06
**Status:** Draft for the B3 orchestrator's review (orchestration spec PO-3), revised after an independent
spec review (`.superpowers/sdd/b3e-spec-review.md`). Its 1 critical, 9 important and 16 minor findings are
folded in under the orchestrator's rulings.
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3e. B3h and B3d merge first (phase B3-1).

**Requires:** no other phase for Part A. Part B (compensation for a session) is built only if request R3 to
B2 (§7) has landed. If R3 slips, Part B moves to B3f, and B3e merges with no B2 change.

**Builds on:**
- Plan 6 billing: invoices, payments, the one balance rule and the invoice lock;
- B3b / B3c gateways: `register_purpose`, `start_checkout`, `Prepared`, `RECHECK`, `fee_for` /
  `providers_for` and the return page (ledger D13, D17, D28, D30);
- B3g: standalone payment records with a currency, revenue and the payment-row flags (ledger D16);
- B2a / B2d: `is_compensable`, `Session.compensated`, `sessions_queryset`, and the archive rule (ledger D8, D14);
- Plan 11 guardians; Plan 12a roles; Plan 13 feature switches; B9b impersonation (ledger D19);
- ledger D36 (revenue for the wallet) and D37 (`balances_of`), recorded by the conductor on 2026-10-06 from this spec's draft.

**Evidence:**
- audit BILL-007 ("the student's balance field, gated by the balances flag") and PEOPLE-001, under
  "Balances & points": the balance is "used to pay invoices and subscriptions; students can be compensated
  for sessions as balance";
- P1 BILL-007 and P1 BR-22, both CONFIRMED;
- P1 SYS-002: the flag `نظام الارصده` ("add balance to the student's account");
- audit U2 / U7: the student panel has the wallet, and "wallet debits" are a money-correctness item;
- P2 §7 `Wallet` / `WalletEntry` (kinds `topup · spend · refund · compensation · adjust`) and P2 rule P2
  ("balances are projections over ledgers; a correction is itself an entry");
- phase B3-3 (`balances` is off by default and requires nothing; the online top-up shows only while
  `online_payments` is on) and B3-11 (a ledger of entries, summed per currency).

## 1. Goal

Each student holds money with the academy, one balance per currency.
- **The office** credits it with a cash top-up or an adjustment, and by moving a payment off an invoice
  into the balance. Part B adds compensation for a session the student did not get.
- **A family** tops it up online.
- **Either** spends it on the student's invoices.

Every movement is an append-only entry. A balance is never negative, and revenue counts each received
amount once.

The slice has two parts:
- **Part A:** the wallet, top-ups, adjustments, paying invoices, moving payments, reversing top-ups, and the
  pages.
- **Part B:** compensation for a session. It is the last task, and it is built only on R3 (§7).

## 2. Decisions

| Id | Decision | Source |
|---|---|---|
| E-1 | **A new app, `etqan.wallet`**, in `TENANT_APPS` under the B3 marker, with its own import contracts (§7). It holds `Wallet`, `WalletEntry` and `TopUp`. It reaches billing, gateways, identity, scheduling and academy only through their `services`, and never imports another app's `api`. No app imports wallet. | phase B3-2; orchestration spec §4.3; CLAUDE.md; `backend/pyproject.toml:297-304` |
| E-2 | **One wallet per (student, currency).** It is created on its first entry. Money never moves between currencies: an invoice is paid only from the wallet in its own currency, with no conversion. | phase B3-4; CLAUDE.md; ledger D24 |
| E-3 | **Append-only ledger.** <br>• Every change is a `WalletEntry` with a signed `amount_minor` (credit > 0, debit < 0) and the running `balance_after_minor`. <br>• `Wallet.balance_minor` is a cache, written only by the service in the entry's transaction. <br>• Both carry `CHECK >= 0`. A test keeps the cache equal to the sum of the entries and to the last `balance_after_minor`. <br>• There is no route to update or delete an entry. | phase B3-11; P2 rule P2; [assumed] (cache plus running balance, for O(1) reads) |
| E-4 | **Entry kinds:** <br>• credits: `topup` (money received), `refund` (a payment moved off an invoice into the wallet), `adjustment` (positive), and in Part B `compensation`; <br>• debits: `spend` (an invoice paid from the wallet), `reversal` (a top-up given back), `adjustment` (negative). <br>An `adjustment` needs a reason of 1–500 characters. | P2 §7; phase §3 B3e row; [assumed] (`reversal`) |
| E-5 | **An adjustment is a correction, never money in or out.** It never represents cash leaving the academy, so it never touches revenue. The debit dialog says "Correction only: not a cash refund". <br>If a family wants cash back for a payment, the office refunds it in billing *before* moving it to the wallet. Once moved (`credited`), a payment cannot be given back in B3e (§10). | review I3, option (a); ledger D36 |
| E-6 | **Concurrency.** <br>• Every write locks its `Wallet` row with `select_for_update`. The row is created first through `get_or_create`, and the unique constraint settles a race. <br>• The write then reads the fresh balance. A debit beyond it is 409 `wallet.insufficient_balance`; the DB check is the last guard. <br>• **There are two disjoint lock chains:** <br>  – money: `Checkout → TopUp → Wallet → Invoice → Payment`; <br>  – compensation (Part B): `Subscription → Session → Wallet`. <br>• No path holds an `Invoice` or `Payment` lock and then takes a `Wallet`, `Subscription` or `Session` lock, and no money path locks scheduling rows. A new path that would do either must be reviewed against both chains. | CLAUDE.md task rule; billing `services/rules.py:61-66`, `services/payments.py:174-211`; scheduling `services/manual.py:195-232`; review I9 |
| E-7 | **Revenue follows ledger D36**, which refines D16: <br>• revenue = `amount_minor + fee_minor` of billing payments whose status is `completed` or `credited` and whose method is not `wallet`, per currency; <br>• a **top-up** is a billing `Payment` (standalone, the student as customer, `wallet_topup=true`), counted when received; <br>• a **wallet spend** is a `Payment` with method `wallet`: it pays the invoice but is never revenue; <br>• a payment **moved to the wallet** (`credited`) stays revenue; <br>• **adjustment** and **compensation** credits create no payment, so they are never revenue; <br>• a **reversed top-up** is `refunded` and leaves revenue together with its fee, as any B3b refund does. <br>The one query stays `billing.services.revenue_between`, so finance's net profit and B3h's estimate follow. It keeps counting top-ups while `balances` is off. | ledger D5, D16, D36; P1 BR-47; billing `services/summary.py:22-39` |
| E-8 | **Billing's payment changes** (B3 owns billing): <br>• `Payment.Method.WALLET = "wallet"`, not a manual method. `MANUAL_PAYMENT_METHODS` (and finance's pinned copy) leave it out. <br>• `Payment.Status.CREDITED = "credited"` ("Moved to balance"). <br>• a new field `Payment.wallet_topup` (bool, default false). <br>• Two checks: method `wallet` implies an invoice and `fee_minor = 0`; `wallet_topup` implies no invoice, customer type `student` and a method other than `wallet`. <br>• `refunded_at` / `refunded_by` also stamp a move. The UI labels the date by status ("Moved on" for `credited`). The records CSV keeps its single `refunded_at` column, which is accepted. | billing `models.py:104-215`, `services/payments.py:15-23`; finance `models.py:88-90`; review M13 |
| E-9 | **Billing guards, decided on the fresh locked row.** Every guard reads the payment row under its lock, never the caller's copy: <br>• `delete_payment` locks the invoice (when it has one), then re-reads the payment with `select_for_update()` (404 if gone). It then refuses `wallet` (409 `billing.wallet_payment`), `wallet_topup` (409 `billing.wallet_topup`) and `credited` (409 `billing.payment_credited`), before its existing online check. <br>• `refund_payment` applies the same three guards to `fresh`. <br>• `update_record` (already on `fresh`) refuses `wallet_topup` and `credited` with 409 `billing.payment_not_editable`. <br>• `add_payment` and `create_record` refuse method `wallet` (400 `method`). <br>Only `etqan.wallet` undoes wallet money. The messages ("move it back to the balance", "reverse it from the balance") show even while `balances` is off; turning `balances` off freezes those payments until it is back on. | review C1, M11; billing `services/payments.py:174-211`, `services/records.py:204-241`, `api/views.py:267-269` |
| E-10 | **Payment-row flags** are computed on the server, and every page reads them; none re-derives them from `method`: <br>• `editable`: as today, and not `wallet_topup`, not `credited`; <br>• `deletable`: not online, and not `wallet`, `wallet_topup` or `credited`; <br>• `refundable` (new): `status == completed`, method ≠ `wallet` and not `wallet_topup`. <br>In the dashboard, `completedPayments` keeps `status === "completed"` only, and the status type gains `credited`. `InvoicePage`, `PaymentRecordsPage` and `InvoicePrint` read the flags, and `InvoicePrint` labels `credited` "Moved to balance". | review I2; billing `api/payloads.py:86-91`; dashboard `features/billing/schemas.ts:73, 252-255`, `InvoicePrint.tsx:112-115`, `PaymentRecordsPage.tsx:55` |
| E-11 | **Paying an invoice from the wallet.** <br>• The amount defaults to `min(wallet balance, invoice balance)`. <br>• An amount over the wallet balance is 409 `wallet.insufficient_balance`. An amount over the invoice balance is billing's one rule, 400 `amount_minor`. <br>• A void invoice is 409 `billing.invoice_void`; nothing due is 409 `wallet.nothing_due`. <br>• It records a `wallet` payment dated the academy's today and a linked `spend` entry, in one transaction. Partial payments are allowed. <br>• Subscriptions are paid through their invoices (P6-1), which covers BR-22's "invoices and subscriptions". | P1 BR-22; billing `services/rules.py:79-83`; spec Plan 6 P6-1; review M3 |
| E-12 | **Moving a payment to the wallet** (the `refund` credit). <br>• It applies to a `completed` payment on an invoice, in any method; for method `wallet` it undoes a spend. <br>• Billing sets it `credited` and recalculates the invoice. The wallet of (the invoice's student, the payment's currency) gets `amount_minor`; the fee stays revenue and is not credited. <br>• A standalone record cannot be moved: 409 `wallet.not_invoice_payment`. | phase §3 B3e row ("refund"); phase B3-10; billing `services/payments.py:174-194` |
| E-13 | **Reversing a top-up** gives the family's money back. <br>• It needs the balance, otherwise 409 `wallet.insufficient_balance`. <br>• It writes a `reversal` entry, and billing marks the top-up payment `refunded`. Its revenue and fee leave together (E-7). <br>• It is reached from the `topup` entry on the student card's statement, so it works with `payment_receipts` off. | review I6, M14; phase B3-10 |
| E-14 | **Office top-ups** are manual money received. <br>• The body has a manual method, `paid_on` (not in the future) and an optional reference. <br>• They create the `wallet_topup` payment (`recorded_by` = the office user) and the `topup` entry in one transaction. <br>• They do not use B3g's `active_student`: a deactivated student keeps, receives and spends a wallet. | audit PEOPLE-001; billing `services/records.py:82-100`; review M4; identity `services.py:977` (deactivate, never delete) |
| E-15 | **The online top-up is a new private gateways purpose, `wallet_topup`**, registered in `WalletConfig.ready()`. <br>• Because `still_payable` re-runs `prepare` with `RECHECK` and no request data (D28), the amount comes from a `TopUp` row created first; the checkout's `reference_id` is its id. <br>• `prepare` answers `Prepared(amount, currency, "Wallet top-up · <student>", add_fee=True)`, with `use_switch` left True: the academy's fee switch decides, as for invoices. <br>• `prepare` is a 404 unless the caller created the row and still may use the wallet (E-17), and `balances` and `online_payments` are on. A row already `paid` is 409 `wallet.topup_paid`: no new checkout starts for it. | ledger D13, D17, D28; gateways `services/purposes.py:16-24, 57-62, 75-80`, `services/captures.py:32-56`; billing `services/online.py:45-56` |
| E-16 | **Completing an online top-up credits every paid checkout.** <br>• `complete` locks the `TopUp`, checks `done.currency` and `done.amount_minor` against the row (`currency_mismatch` / `amount_mismatch` attention otherwise), then locks the wallet. <br>• It records a `wallet_topup` payment (with the fee) and a `topup` entry, and marks the row `paid` the first time. <br>• A second paid checkout for the same row (Stripe, then PayPal) is still the family's money, so it is credited too. The only duplicate guard is the unique transaction number per method (`already_recorded`), so `TopUp` keeps no `payment_id`. <br>• It applies even while `balances` is off: money received is never dropped (phase B3-9). | review M7; gateways `services/completion.py:35-99`; billing `services/link_purpose.py:321-360` |
| E-17 | **Who sees and spends a wallet:** <br>• the student (their own); <br>• a parent of the student (`identity.services.is_parent_of`); <br>• the office, by codes (E-20). <br>A student with no parent acts alone. A payer who is neither (a paying sibling) reads the invoices it pays, but not the sibling's wallet. Out of scope is a 404. | audit PEOPLE-001; billing `scopes.py:10-29`; identity `services.py:255-266`; [assumed] (payer-only excluded) |
| E-18 | **Top-up currencies:** <br>• the academy's `default_currency`; <br>• the currencies of the student's wallets; <br>• the currencies of the student's non-void invoices (`billing.services.invoices_queryset`). B3d prices invoices in the country currency (D23). <br>A currency no enabled provider takes for that amount gives no providers, and the dialog says so. | review I5; ledger D23; gateways `services/fees.py:154-167` |
| E-19 | **Top-up amount bounds:** 1 to 100,000,000 minor units per top-up, online or manual (400 `amount_minor`). An invoice payment is already bounded by its invoice. | review M8; [assumed] (cap) |
| E-20 | **Access:** a new resource `wallet` ("Student balances" / "أرصدة الطلاب"), with verbs in use `view_any`, `create` and `update`. <br>• `view_any`: any student's balances and statement. <br>• `create`: manual top-up, positive adjustment, and in Part B compensation. <br>• `update`: negative adjustment, reversing a top-up, paying an invoice for the family, moving a payment. <br>Two routes touch billing rows, so staff also need billing's own codes: <br>• paying needs `invoice.view` (through `billing.services.invoice_for`, as `online._readable` does); <br>• moving needs `payment.update` (as billing's refund does), checked in the view. <br>Admins hold every code. Teachers hold none. The Supervisor preset gains nothing. Parents and students act by role, scoped by E-17. Every money route adds `NotImpersonating` (D19). | spec roles-permissions; ledger D19; review M10; billing `services/online.py:34-42`; access `presets.py` |
| E-21 | **Feature `balances`** becomes built in place, `default=False`, `requires=()`. <br>• Online top-ups also need `online_payments`; paying an invoice and moving a payment also need `invoices` (404 otherwise; the buttons hide). <br>• While `balances` is off, every wallet route is a 404, but a started top-up still completes (E-16). <br>• Compensation (Part B) needs only `balances`, not B2a's `compensation_sessions`: TutorHamster's hint ties it to balances. | phase B3-3; P1 SYS-002; platform `features.py:123`; review M6 |
| E-22 | **What a family sees.** <br>• It sees the statement's dates, kinds, amounts and balances. <br>• It never sees `created_by`. <br>• An adjustment shows as "Adjustment" without the office's reason. <br>• The other entries' notes (invoice number, provider, session date) are shown. | billing `api/payloads.py:7-8` (staff-only fields); review M9 |
| E-23 | **Compensation for a session** (Part B, only on R3). <br>• The office credits a session that scheduling's `is_compensable` accepts and that is not of kind `compensation` (R3 refuses it, since the lesson is owed through the original). The subscription must not be archived, matching B2d D-7 for make-ups. <br>• The amount is prefilled with `price_minor // sessions_total` (0 when the total is 0) in the subscription's currency, read through `sessions_queryset`. It is editable, minimum 1. <br>• `claim_session_for_balance` marks the session `compensated` under scheduling's locks, so a balance and a make-up exclude each other and the session freezes. <br>• One compensation per session (a partial unique constraint). It cannot be undone; the money is corrected by an adjustment. | P1 BR-22; scheduling `services/rules.py:139-155`, `services/manual.py:226-271`; review I4, I7, M5; [assumed] (prefill; no undo) |
| E-24 | **Nothing is sent** on a balance change. Later phases read balances only through `wallet.services.balances_of` (ledger D37). | ledger D37; [assumed] |
| E-25 | Only en and ar strings. | ledger D11, D22 |

## 3. Data

### 3.1 `etqan.wallet`

**`Wallet`:**
- `student` → `identity.StudentProfile`, `PROTECT` (students are deactivated, never deleted);
- `currency`: `^[A-Z]{3}$`;
- `balance_minor`: default 0, `CHECK >= 0`;
- `created_at`, `updated_at`.

It is unique on `(student, currency)`.

**`WalletEntry`:**
- `wallet` → Wallet, `PROTECT`, related name `entries`;
- `kind`: `topup | refund | adjustment | spend | reversal | compensation`;
- `amount_minor`: signed, non-zero;
- `balance_after_minor`: `CHECK >= 0`;
- plain ids, nullable: `payment_id` (indexed), `invoice_id`, `session_id`;
- `top_up` → TopUp, nullable, `PROTECT`;
- `note`: up to 500 characters, filled by the service;
- `created_by` → user, `SET_NULL`;
- `created_at` (UTC).

**Checks:**
- the sign follows the kind;
- `compensation` needs `session_id`;
- `topup`, `refund`, `spend` and `reversal` need `payment_id`.

**Unique:**
- `(kind, payment_id)` where `payment_id` is not null;
- `session_id` where the kind is `compensation`.

It is indexed on `(wallet, -id)`. The `compensation` choice and its constraint are in the first migration, so Part B adds no migration.

**`TopUp`:**
- `student` → StudentProfile, `PROTECT`;
- `currency`;
- `amount_minor`: 1–100,000,000;
- `status`: `pending | paid`;
- `created_by` → user, `SET_NULL` (`prepare` fails closed without one);
- `created_at`, `paid_at`.

### 3.2 `etqan.billing`

- `Payment.Method` gains `WALLET`;
- `Payment.Status` gains `CREDITED`;
- a new field `wallet_topup` (`db_default=False`);
- the checks `billing_payment_wallet_on_invoice` and `billing_payment_topup_standalone` (E-8).

Existing rows satisfy both checks.

## 4. Behaviour

### 4.1 Billing services (new, public; billing's lock order: invoice, then payment)

- **`record_wallet_payment(invoice, *, amount_minor, by) -> Payment`:** locks the invoice, refuses a void
  invoice and an amount over the balance, and records a `wallet` payment dated today with `fee_minor=0`.
  It then recalculates the invoice.
- **`credit_payment(payment, *, by) -> Payment`:** locks the invoice, then re-reads the payment with
  `select_for_update`. A payment that is not `completed` is 409 `billing.payment_not_completed`. It sets
  `credited` and the stamps, and recalculates.
- **`record_topup_payment(*, student_profile_id, amount_minor, currency, method, by, fee_minor=0, paid_on=None, transaction_number="", reference="", notes="") -> Payment`:**
  - manual methods need `by` and take `paid_on` (not in the future);
  - online methods take the fee, are dated today and have nobody as recorder;
  - the transaction number is unique per method, and the `IntegrityError` is mapped as in `records._save`;
  - it does not call `active_student` (E-14).
- **`refund_topup_payment(payment, *, by) -> Payment`:** re-reads the payment with `select_for_update`,
  needs a `completed` `wallet_topup` payment, and sets `refunded`.
- **`invoice_for(user, invoice_id) -> Invoice`:** `online._readable` made public: office scope, staff needing
  `invoice.view`, family scope through `scope_for` (404 otherwise).
- **Guards** (E-9) and the **payment-row flags** (E-10). `MANUAL_PAYMENT_METHODS` is derived from
  `NOT_MANUAL = ONLINE_METHODS | {WALLET}`.
- **`revenue_between`** follows E-7.

### 4.2 Wallet services (`etqan/wallet/services/`)

Every write is `@transaction.atomic`, locks per E-6, and returns the new entry.

**Part A writes:**
- **`top_up(student_user_id, *, amount_minor, currency, method, paid_on, by, reference="")`:** the
  office's manual top-up (E-14, E-19).
- **`adjust(student_user_id, *, amount_minor, currency, reason, by)`:** a signed amount (≠ 0) and a reason.
  A negative amount must be covered by the balance.
- **`pay_invoice(invoice_id, *, by, amount_minor=None)`:**
  - it reads the invoice through `invoice_for(by, …)` and, for a family caller, also checks E-17 for the
    invoice's student;
  - it locks the wallet, computes the amount on fresh values (E-11), and calls `record_wallet_payment`,
    which re-checks under the invoice lock;
  - it writes `spend`.
- **`move_to_wallet(payment_id, *, by)`:** reads the payment unlocked to learn its invoice's student and
  its currency. It refuses a standalone payment, locks that wallet, calls `credit_payment`, and writes
  `refund` for `amount_minor`.
- **`reverse_topup(payment_id, *, by)`:** reads the payment unlocked and needs `wallet_topup`
  (409 `wallet.not_topup`). It locks the wallet, checks the balance, writes `reversal`, and calls
  `refund_topup_payment`, which re-checks the status on the locked row.
- **`start_top_up(student_user_id, *, amount_minor, currency, provider, user) -> StartedCheckout`:**
  - it validates against E-17 to E-19;
  - it reuses the newest `pending` `TopUp` of the same student, currency, amount and creator younger than
    23 hours (gateways' `REUSE_FOR`, `services/checkouts.py:39`), or creates one in its own committed
    block;
  - it calls `gateways.services.start_checkout("wallet_topup", topup.id, provider, user=user)`.

  The reuse lookup is unlocked: two simultaneous clicks may create two rows. That is harmless, because each
  row is paid only through its own checkout.

**Reads:**
- `balances_of(student_user_id)` (D37);
- `entries_of(student_user_id, currency=None)`;
- `family_wallets(user)`;
- `may_use(user, student_user_id)` (E-17);
- `topup_currencies(student_user_id)` (E-18).

**Part B:**
- **`compensation_for(session_id)`:** reads the session through `scheduling.services.sessions_queryset()`
  (with its subscription) and `is_compensable`. It answers `{session_id, compensable, currency,
  default_amount_minor, entry | None}`. `compensable` is false for a `compensation`-kind session or an
  archived subscription.
- **`compensate(session_id, *, amount_minor, by, reason="")`:** calls
  `scheduling.services.claim_session_for_balance(session_id)`, which locks subscription then session and
  marks it. It then locks the wallet in the subscription's currency and writes `compensation`, with the
  note "<date> · <course>".

### 4.3 The `wallet_topup` purpose (`etqan/wallet/services/topup_purpose.py`)

- **`prepare`** follows E-15. It reads the row only and never uses `params`, so `RECHECK` prices it the same
  as the start.
- **`complete`** follows E-16. It maps billing's `transaction_number` `ValidationError` and the
  `billing_payment_transaction_unique` `IntegrityError` to `already_recorded`, as
  `billing/services/link_purpose.py` does. Any other refusal is `Applied(ok=False, reason="")`, logged by
  field only.

## 5. API summary (`/api/v1/`)

User ids identify students. Every write answers 201 with the new entry; the payment and the invoice are
refetched by the dashboard. No wallet route answers a billing payload, because `etqan.billing.api` is
forbidden to other apps.

| Route | Methods | Feature | Permission |
|---|---|---|---|
| `wallet/mine/` | GET | `balances` | Student or parent: `[{student: {id, name}, balances: [{currency, balance_minor}], topup_currencies}]` |
| `wallet/students/<id>/` | GET | `balances` | `wallet.view_any`, or the family by E-17: `{student, balances}` |
| `wallet/students/<id>/entries/` | GET | `balances` | The same; `?currency=`, paginated. Each entry: `{id, kind, currency, amount_minor, balance_after_minor, note, invoice_id, payment_id, session_id, created_at}`, plus `created_by` for the office only. A family sees no adjustment reason (E-22). |
| `wallet/students/<id>/top-ups/` | POST | `balances` | `wallet.create`, `NotImpersonating`: `{amount_minor, currency, method, paid_on?, reference?}` |
| `wallet/students/<id>/adjustments/` | POST | `balances` | `wallet.create` for a positive amount, `wallet.update` for a negative one (checked in the view), `NotImpersonating`: `{amount_minor, currency, reason}` |
| `wallet/invoices/<id>/pay/` | POST | `balances` (+`invoices`) | `wallet.update` (staff also `invoice.view`), or the family by E-17; `NotImpersonating`: `{amount_minor?}` |
| `wallet/payments/<id>/move/` | POST | `balances` (+`invoices`) | `wallet.update` and `payment.update`, `NotImpersonating` |
| `wallet/payments/<id>/reverse/` | POST | `balances` | `wallet.update`, `NotImpersonating` |
| `wallet/top-ups/options/` | GET | `balances` (+`online_payments`) | The family by E-17: `?student=&currency=&amount_minor=` gives `{currencies, providers}` |
| `wallet/top-ups/` | POST, non-atomic | `balances` (+`online_payments`) | Student or parent by E-17, `NotImpersonating`, throttle `gateway_start`: `{student, amount_minor, currency, provider}` gives a `StartedCheckout` |
| `wallet/compensations/` (Part B) | GET `?session=`, POST | `balances` | `wallet.create` (POST adds `NotImpersonating`): `{session, amount_minor, reason?}` |

**Payload changes in billing:**
- payment rows gain `wallet_topup` and `refundable`;
- `editable` and `deletable` follow E-10;
- the `status` enum gains `credited`;
- the `method` enum gains `wallet`.

## 6. Dashboard

The new feature folder is `src/features/wallet/`. Billing and gateways never import it: routes pass wallet
components into billing's pages through `actions` and a new `paymentActions` prop on `InvoicePage`. Every
wallet mutation invalidates the wallet, invoice and billing records queries (`useBillingMutation`'s
pattern).

- **Student page** (`people.students.$personId.tsx`, edit mode only): `StudentWalletCard`, shown with
  `wallet.view_any` and `balances`.
  - One tab per currency, with its balance and the statement (date in the academy's timezone, kind, note,
    ± amount, balance after, by).
  - **Top up** (`wallet.create`): manual method, date, reference, amount and currency.
  - **Adjust** (`wallet.create` / `wallet.update`): a signed amount, the balance shown, a reason, and the
    note "Correction only: not a cash refund".
  - **Reverse** on each `topup` entry (`wallet.update`), with a confirm dialog.
  - Links to the payment's invoice for `spend` and `refund` entries.
- **Invoice page, office and family** (`billing.invoices.$invoiceId.tsx`, `learning.invoices.$invoiceId.tsx`):
  - `PayFromWallet` in the route's `actions`. It shows while the invoice has a balance, is not void, the
    student's wallet in its currency is above 0, and the viewer may spend.
  - The confirm dialog says "Pay {min} from the balance ({balance} available)". The office may lower the
    amount.
  - `paymentActions` carries `MoveToWallet` (`wallet.update`, `payment.update`, `balances`) on each
    `completed` payment.
- **Billing fixes (E-10):**
  - `completedPayments` filters `status === "completed"`, and `Payment.status` gains `credited`;
  - `InvoicePage` and `PaymentRecordsPage` read `editable`, `deletable` and `refundable` instead of
    `method` or status;
  - `PaymentRecordsPage` shows a "Balance top-up" chip, and its status filter gains "Moved to balance";
  - `InvoicePrint` labels `credited` "Moved to balance";
  - the refunded date reads "Moved on" for `credited`.
- **Family → Balance** (`_authed/learning.wallet.tsx`, students and parents, `balances`):
  - one section per student (a student without a parent sees only their own);
  - per currency: the balance and the statement (E-22), and **Top up** while `online_payments` is on;
  - the Top up dialog takes the amount and a currency from `topup_currencies`, then the providers from
    `top-ups/options`. Starting shows the server's fee and total in a sheet like `PayOnline`'s, then
    redirects (`go`).

  Its nav item sits under the B3 marker, group `learning`, `requiresRole: ["student", "parent"]`, feature
  `balances`.
- **Return page** (`features/gateways/ReturnPage.tsx`): a `wallet_topup` checkout also asks `me` (a private
  purpose, D30). Its back and retry links go to `/learning/wallet`.
- **Session page** (Part B, R3's line): `SessionWalletCard` (`wallet.create`, `balances`; regardless of
  `compensation_sessions`):
  - "Compensate as balance" with the prefilled amount, when `compensable`;
  - "Compensated with {amount} on {date}" when an entry exists;
  - nothing otherwise.
- **Wiring:**
  - `locales/{en,ar}/wallet.json`, plus the new keys in `billing.json`;
  - the `wallet.*` and new `billing.*` error codes in the server-error text;
  - `FeatureCode` gains `balances` under the B3 comment;
  - `FEATURE_SCREENS` and `FEATURE_WORDS` gain rows;
  - semantic tokens, RTL, phone width, and money in each row's own currency.

## 7. Dependencies, wiring and cross-phase hooks

- **No new package, setting or environment variable.**
- **Wiring under the B3 markers:**
  - `etqan.wallet` in `TENANT_APPS` and `config/api_router.py` (`wallet/`);
  - `balances` flipped in `platform/features.py` to `_built(..., default=False)`;
  - the `wallet` resource in `access/registry.py`;
  - the route matrix rows and `FEATURE_WORDS["/wallet/"] = "balances"`;
  - `seed_wallet` in `seed_dev` (§8).
- **Import contracts** (`pyproject.toml`, under the B3 marker):
  - "wallet reaches other apps only through their services", which forbids every other app's `models`,
    `api`, `scopes` and `clock`;
  - "other apps reach wallet only through its services";
  - "billing never imports wallet";
  - "scheduling never imports wallet";
  - `etqan.wallet` is added to "gateways imports no business app"'s forbidden list and to "other apps reach
    gateways only through its services"'s source list.
- **The student page line** in `people.students.$personId.tsx` is an additive card on a trunk page that no
  phase owns (B9 owns identity authentication, orchestration spec §4.3). B3e makes it and notes it in the
  ledger.
- **Ledger:** D36 and D37 are already recorded. The only refinement to record is E-9: "billing refuses to
  refund, delete or edit wallet, top-up and credited payments, deciding on the locked row; only
  etqan.wallet undoes them."
- **Part B and R3.** Part B (the compensation services, the `wallet/compensations/` route,
  `SessionWalletCard`, and e2e step 7) is the slice's last task.
  - It is built only if R3 has landed when the Part A tasks have passed review.
  - Otherwise Part B moves to B3f. The phase rule allows "a slice's spec may move a minor item to a later
    B3 slice". B3e then merges with no B2 change, and its migration already holds the `compensation` kind.
  - Compensation is never built without R3. An unmarked credit would let a make-up and a credit both pay
    for one session.
- **Request R3 to B2 (scheduling)**, filed as `ledger.py request B3 scheduling B2 "<text>"`. The text, exactly:

  > B3e wallet compensation hook (spec docs/superpowers/specs/2026-10-06-b3e-student-wallet-design.md E-23, §4.2, §7). Additive only: no model, no migration, no change to any existing signature. BACKEND etqan/scheduling/services (exported from the package): claim_session_for_balance(session_id: int) -> Session, @transaction.atomic, locking as create_compensation does (read the session's subscription_id unlocked, select_for_update the subscription, then select_for_update the session, re-checking the subscription id). Refusals: a missing session or one without a subscription -> ValidationError(field="session"); an archived subscription -> the existing refuse_if_archived (as B2d D-7 does for make-ups); session.compensated -> ConflictError(code="scheduling.already_compensated"); session.kind == "compensation" -> ConflictError(code="scheduling.not_compensable") (the lesson is owed through the original); not is_compensable(session) -> ConflictError(code="scheduling.not_compensable"). Otherwise set compensated=True (update_fields compensated, updated_at) and return the session. The wallet reads values through the existing sessions_queryset and is_compensable; nothing else is added. DASHBOARD: routes/_authed/scheduling.sessions.$sessionId.tsx renders <SessionWalletCard sessionId={sessionId} /> from @/features/wallet under SessionPage (one import, one line; the card hides itself without wallet.create or balances). STRINGS: "made up or compensated" replaces "has a make-up session" in en and ar for sessionClasses.frozen and errors.scheduling.has_compensation / already_compensated, and in the backend messages of refuse_if_compensated (services/attendance.py:66-68) and create_compensation's already-compensated refusal (services/manual.py:240-244); codes unchanged. TESTS: a claim marks compensated; a second claim is 409 already_compensated; a scheduled, an extra and a compensation-kind session are 409 not_compensable; an archived subscription is refused; after a claim create_compensation is 409 already_compensated and attendance/restore are refused; the claim's FOR UPDATE order is subscription then session (captured SQL); every existing scheduling test passes unchanged. EXECUTION: B2 makes it or delegates to B3 under a claim (as R2); commits go on B3e's branches and land in B3e's merge pair. If it is not in when B3e's Part A has passed review, B3e merges without it and wallet compensation moves to B3f. NOTE (not part of this request): a cancelled make-up releases its original and is itself compensable, so an original and its make-up can both be made up today; B2 may want to look at that.

## 8. Seeds

The seeds go in a new module, `etqan/tenants/seeds/wallet.py` (`seed_wallet(subdomain)`).
- It is called under the B3 marker **after** `gateways_seeds.seed_links`. That step skips itself once any
  standalone record exists (`tenants/seeds/gateways.py:110`), and a top-up is one.
- It uses wallet services only, and runs only when the academy has no wallet entry.
- `seed_dev.FEATURES` enables every built feature, so `balances` is on for demo.

For **demo**, on "Aisha Omar" (no e2e journey reads her):
- a cash top-up of EGP 300.00, dated today;
- an adjustment of +EGP 50.00 with the reason "Welcome credit".

The **other** academy gets nothing.

## 9. Testing

### Backend

**Ledger invariants:**
- after every write, the cache equals Σ entries and the last `balance_after_minor`;
- a raw update of `balance_minor` or `balance_after_minor` to −1 raises `IntegrityError`, and so does a
  wrong sign for a kind;
- no route edits or deletes an entry.

**Locking.** No threads. Lock order is proven from captured SQL: the `FOR UPDATE` statements in order, as
billing's `test_invoices.py:313-334` and `test_subscriptions.py:99,147` do.
- `pay_invoice` and `move_to_wallet` lock wallet, then invoice, then payment.
- Top-up `complete` locks checkout, then top-up, then wallet.
- `compensate` (Part B) locks subscription, then session, then wallet.
- A debit computed from a stale in-memory balance is still refused: the service reads after the lock. The
  test lowers the balance between load and call.

**C1 race:**
- a payment is loaded `completed`;
- it is moved to the wallet before `delete_payment(payment)` runs;
- the delete is 409 `billing.payment_credited`, and the wallet and entry are unchanged.

The same check runs for `refund_payment` on a moved payment and on a `wallet` payment.

**Top-ups and adjustments:**
- a manual top-up creates its `wallet_topup` payment, method and date, also for a deactivated student;
- a future date, 0, more than 100,000,000 and a bad currency are 400s;
- an adjustment needs a reason;
- a negative adjustment beyond the balance is 409;
- staff without `wallet.update` cannot debit.

**Paying an invoice:**
- the default amount, a partial payment;
- over the wallet balance is 409 `wallet.insufficient_balance`; over the invoice balance is 400
  `amount_minor`;
- a void invoice, nothing due, an empty wallet, and a wallet in another currency;
- the invoice status follows, and the `spend` entry is linked;
- a family member in scope, a sibling payer (404), a student without a parent;
- staff without `invoice.view` are refused;
- impersonation is 403; `invoices` off is 404.

**Moving to the wallet:**
- a cash payment and a wallet payment become `credited`, the invoice reopens, and the wallet gets
  `amount_minor` without the fee;
- a standalone record, a refunded payment and a credited one are refused;
- staff without `payment.update` are refused.

**Reversing a top-up:** the balance must cover it; the payment becomes `refunded`; a non-top-up is refused.

**Billing (E-9, E-10):**
- every guard's code;
- `add_payment` and `create_record` refuse `wallet`;
- the pinned `MANUAL_PAYMENT_METHODS` test still passes;
- the flags for each kind of payment;
- the status filter accepts `credited`.

**Revenue (E-7):**
- a top-up counts with its fee;
- a spend does not count;
- a credited payment still counts;
- a reversed top-up leaves together with its fee;
- adjustments and compensation never count;
- top-ups count with `balances` off;
- end to end: top up 100 and spend 100, and revenue is 100.

**Online top-up:**
- start creates or reuses the row;
- `prepare` refuses another user, a paid row, a lost guardian link, and either feature off;
- `RECHECK` prices the same as the start;
- a Stripe webhook and a PayPal capture both apply, with the fee;
- a second paid checkout for the same row credits again;
- a duplicate transaction is `already_recorded`;
- a currency or amount mismatch needs attention;
- completion applies with `balances` off;
- the currencies include an open invoice's currency (E-18), and the options list follows the providers.

**Family view:** a family's statement has no `created_by` and no adjustment reason.

**Part B (with R3):**
- the prefill;
- the claim and the credit;
- a second claim, a claim after a make-up, and a make-up after a claim are refused;
- a `compensation`-kind session and an archived subscription are refused;
- the unique constraint holds.

**Feature, matrix and isolation:**
- `balances` is built, off by default and `requires=()`;
- every route is 404 while it is off;
- the role × route rows;
- `NotImpersonating`;
- cross-academy isolation of the three tables;
- `lint-imports`.

**Seeds:** idempotent; Aisha's balance is EGP 350.00; `seed_links` still writes its records.

### Dashboard

- `StudentWalletCard`: tabs, the statement, Top up, Adjust (signed, its note, the cap), Reverse on
  `topup` entries, and hidden without codes or the feature;
- `PayFromWallet`: the hidden cases, the default amount, the office lowering it, and the two over-balance
  errors;
- `MoveToWallet`;
- refetching after each mutation;
- billing: `completedPayments` excludes `credited` (Void and the invoice amount edit follow); `InvoicePage`
  and `PaymentRecordsPage` read `editable`, `deletable` and `refundable`; `InvoicePrint` labels
  `credited`; the records chip and filter;
- the family Balance page for a student and for a parent with two children, without staff names or
  adjustment reasons;
- the top-up dialog (currencies, providers, the fee sheet, the redirect);
- `ReturnPage` for `wallet_topup`;
- `SessionWalletCard` in its three states (Part B);
- the nav item, `FeatureCode`, and both languages with RTL.

### E2E

The file is `dashboard/e2e/b3-wallet.spec.ts`.
- It uses **USD**, so it never touches `b3-finance.spec.ts`'s exact EGP net-profit deltas, even when local
  runs are `fullyParallel`. CI is serial (`playwright.config.ts:26`).
- It creates a **fresh parent and student per run**, "E2E Wallet Payer/Child {stamp}", as
  `b3-online-payments.spec.ts:20-45` does. No seeded person drifts.

Steps:
1. `manage("set_features", "demo", "--on", "invoices", "online_payments", "balances")`.
2. The admin creates the parent and the child, then a 200.00 USD invoice for the child with the invoice
   form.
3. On the child's page, the admin adds a cash top-up of 300.00 USD. The card shows 300.00.
4. The parent signs in. Balance shows 300.00 USD. On the invoice they pay from the balance. The invoice is
   paid, and the balance is 100.00.
5. The admin moves that payment to the balance. The invoice is unpaid, and the balance is 300.00.
6. The parent tops up 50.00 USD with the Stripe simulator. The return page says paid, and Balance shows
   350.00.
7. Part B only: the admin creates a subscription for the child, cancels one of its scheduled sessions,
   compensates it as balance from the session page, and the statement lists it.

## 10. Out of scope

- **Giving cash back for a moved payment** (or any non-top-up credit). A moved payment is `credited`: it
  stays revenue, and billing refuses to refund it. Giving it back would need a general "reverse a credit
  backed by a payment" path that also takes revenue out. TutorHamster shows no cash-out of a student
  balance (audit BILL-007: the balance pays and compensates), so the CRUD-first rule keeps that path out.
  The office refunds in billing before moving (E-5). An adjustment debit is never a cash refund.
- **An office page listing every student's balance**, a balances card on the office family page, and the
  students list's optional "balance" column (audit PEOPLE-001). They are not in the phase row, which asks
  for "the balance on the student page and the family's pages". They are left to a later slice that adds
  balance reporting.
- **Transfers** between students, siblings or currencies, and family-level wallets (E-2, E-17).
- **Automatic payment** of new invoices from the balance. It is not observed; paying is explicit.
- **Undoing a compensation** (E-23).
- **Notifications** on balance changes (E-24).
- **XP points**, which sit beside the balance in the same audit tab: not money.
- **Gateway refund APIs** (phase B3-10).

## 11. Open questions

None. Every decision above is sourced or marked `[assumed]`.
