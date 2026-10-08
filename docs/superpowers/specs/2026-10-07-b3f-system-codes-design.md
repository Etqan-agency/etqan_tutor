# Slice B3f — System codes — Design

**Date:** 2026-10-07
**Status:** Draft for the B3 orchestrator's review (orchestration spec PO-3), revised after an independent
spec review (`.superpowers/sdd/b3f-spec-review.md`). Its 1 critical, 5 important and 17 minor findings are
folded in under the orchestrator's rulings.
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3f, the last B3 slice. B3d and B3e merge first
(phase B3-1).

**Requires:** no change in another phase. The phase row says B3f needs "B2's subscription model (codes create
or renew subscriptions): recorded when B3f's spec is written". This spec records it as **no request to B2**. Every
scheduling service B3f calls already exists and is public (§7):
- `create_subscription`;
- `renew_subscription`, with R2's `currency=` (ledger D23);
- `subscriptions_queryset`;
- `lock_subscription`;
- `today`.

B3e's request R3 is done, so B3e keeps its Part B, and B3f inherits nothing from B3e.

**Builds on:**
- Plan 4 catalogue and scheduling: the package snapshot (P4-5), `sessions_total`, and the renewal price
  (P4-10);
- Plan 6 billing: invoices, the one balance rule, the invoice lock, and `invoice_subscription` (P6-1);
- B3d: `package_price`, ledger D23 and D35;
- B3e: the payment-row flags, `invoice_for`, and the billing guards (ledger D36, D38);
- B3g: the payment records list and CSV export (ledger D16);
- B2d: the archive rule (`refuse_if_archived`, ledger D14);
- Plan 11 guardians; Plan 12a roles; Plan 13 feature switches; B9b impersonation (ledger D19); B8c's per-IP
  throttle pattern.

**Evidence:**
- **audit SUB-005** (`/admin/system-codes`):
  - columns: code type · code · expiry · created;
  - filters: code type, status, discount type, used;
  - form: code type\* (activation / renewal / discount), package\*, course\*, session count ("from the package
    details"), created date, validity (days)\*, status (not used yet / used / expired);
  - "The discount-type filter exists but the create form showed no discount-type or discount-value field. How
    discount codes are valued is UNKNOWN."
- **P1 SUB-005** (CONFIRMED): the same form, code example `SYS-Y5OED`. P1 §8.5: "لم يستخدم بعد → مستخدم | منتهي
  الصلاحية" (unused → used | expired).
- **P1 §16.2:** creating a subscription "consumes a SystemCode when the activation-code route is used".
- **audit SUB-001 #6 / P1 SUB-006:** "activation code" is one of the subscription's payment methods.
- **audit SYS-003 / P1 SYS-003:** "كود التفعيل (activation code)" is a payment-gateway switch.
- **P2 §6.5 `RedemptionCode`:** `code UQ`, `kind`, `package_id`, `course_id`, `session_count`, `valid_days`,
  `expires_at`, `status`, `redeemed_by_account_id`, `redeemed_at`.
- **Phase B3-3:** `system_codes` is off by default and has no TutorHamster flag.

## 1. Goal

An academy sells or gives out **system codes**, and a family redeems one instead of paying:
- **an activation code** starts a new subscription to a course and package;
- **a renewal code** renews one of the student's subscriptions;
- **a discount code** takes a percentage or a fixed amount off an invoice.

**The office:**
- generates codes in batches;
- lists them, exports them to CSV, and voids unused ones;
- redeems a code for a family;
- removes a discount applied by mistake.

**A family** (the student, or a parent of the student) redeems a code:
- on its own "Redeem a code" page, for activation and renewal;
- on an invoice, for a discount.

Each code is redeemed at most once. Billing shows what a code paid as a payment with the method "System code".
That payment is never revenue, so no amount is counted twice.

## 2. Decisions

| Id | Decision | Source |
|---|---|---|
| F-1 | **A new app, `etqan.vouchers`**, in `TENANT_APPS` under the B3 marker, with its own import contracts (§7). It holds `VoucherBatch` and `Voucher`. It reaches identity, academy, catalogue, scheduling, billing and platform only through their `services` (platform's `features`). **No app imports it, except the tenants seeds, through its services** (§8). The name avoids a clash with permission codes. | phase B3-2; CLAUDE.md; `backend/pyproject.toml:357-400` (the wallet's contracts as the pattern); review M9 |
| F-2 | **Three kinds, as observed: `activation`, `renewal` and `discount`.** Codes are generated in a **batch** that holds the shared terms (kind, course, package, teacher, validity, discount). Each code holds only its own state. The audit form makes one code at a time, but the phase row asks for codes "generated in bulk". | audit SUB-005; phase §3 B3f row; [assumed] (batch holds the terms) |
| F-3 | **What each batch names:** <br>• **activation:** a course, a package and a **teacher**, all required. `create_subscription` needs an active teacher (`scheduling/services/subscriptions.py:68-78, 196-199`), and a family cannot choose one. The audit form shows no teacher, so the teacher is the one addition. <br>• **renewal:** a course and a package, both required. The renewal keeps the old subscription's teacher. <br>• **discount:** a course and a package are optional. When a package is set, the invoice must belong to a subscription of that package, and the same holds for a course. An empty package and course mean "any invoice". <br>Because the columns are `PROTECT` foreign keys (F-25), whether a discount is scoped is fixed at generation and can never widen later. <br>The session count is not stored: it is shown from `catalogue.services.sessions_total(package)` ("from the package details"). | audit SUB-005 (package\*, course\*, session count from the package); `catalogue/services.py:41`; [assumed] (teacher on activation). **Deliberate deviation** for discounts: both audits mark package\* and course\* required for every kind (audit SUB-005; `PHASE_1_SYSTEM_AUDIT.md:395`). A discount form with no value field was never fully observed, and a whole-academy discount is the common case (review M5). |
| F-4 | **How a discount is valued** (unobserved, audit SUB-005): <br>• `discount_kind` is `percent` or `fixed`, matching the observed "discount type" filter; <br>• `percent`: a whole number from 1 to 100, taken off the invoice's `amount_minor` and rounded half up. It is at least 1 minor unit and is capped at the invoice's balance; <br>• `fixed`: `discount_value` from 1 to 100,000,000 minor units plus a `currency`. It applies only to an invoice in that currency (409 `vouchers.wrong_currency`) and is capped at the balance. <br>A cap is never an error: the code pays what is still owed. Each invoice takes at most one discount code (409 `vouchers.invoice_discounted`). | audit SUB-005 ("discount type" filter); phase B3-4 (no conversion); [assumed] (values, rounding, cap, one per invoice) |
| F-5 | **A code pays with a billing `Payment` of a new method, `code`** ("System code" / "كود النظام"): <br>• It is always on an invoice, with `fee_minor = 0`; a DB check enforces both. <br>• Its `reference` is the code's display form, `paid_on` is the academy's today, and `recorded_by` is the person who redeemed it. <br>• **Activation and renewal:** the new subscription gets an invoice for its own price (package price via D23, or P4-10 for a renewal). A `code` payment pays it in full. <br>• **Discount:** a `code` payment for the discount's amount pays part or all of an existing invoice. <br>This is TutorHamster's "activation code" payment method. A discount is recorded as a payment rather than an edit to the invoice amount, so the invoice keeps its price and the reduction stays visible and audited. | audit SUB-001 #6 (payment method "activation code"); P1 §16.2; spec Plan 6 P6-1 (subscriptions are paid through invoices); billing `models.py:104-121, 214-230` (the wallet's check as pattern); [assumed] (discount as a payment) |
| F-6 | **The subscription's invoice is issued even when the academy's "invoice on subscription" setting is off.** The code's payment needs an invoice to show the subscription as paid. <br>• A new billing service, `settle_with_code`, issues the invoice as `invoice_subscription` does, but without reading that setting. <br>• While `invoices` is off, no invoice and no payment is written. The code row is then the only record, and the subscription is created anyway. <br>• A price of 0 also writes nothing. <br>**Turning `invoices` on later does not back-fill.** The subscription then shows payment status "none". The office finds such subscriptions by their code in System codes, whose row links `subscription_id`. A later manual invoice for that subscription is the office's own decision. | billing `services/subscriptions.py:31-64`; Plan 13 §5.3; [assumed]; review M7 |
| F-7 | **Revenue: a `code` payment is never revenue.** This refines D36 the way the wallet did: <br>• `revenue_between` excludes method `code` as it excludes `wallet`; <br>• the money for a code is revenue only if the academy **sold** it. The office records that sale as an ordinary payment record (B3g), standalone, in any manual method, on the day it is paid; <br>• a code given away free is never revenue; <br>• redeeming a sold code counts nothing a second time. <br>So revenue counts what was received, once, when it was received (BR-47). The redemption is a settlement in kind, like a wallet spend. B3f tracks no sale price on a batch (§10). <br>**A compensation** (B3e Part B) on a code-paid subscription is the office's choice, as for any subscription, and is never revenue (D36). | ledger D5, D16, D36; P1 BR-47; billing `services/summary.py:22-44`; `wallet/services/compensation.py:39-43`; [assumed] (sale recorded as a payment record); review M10 |
| F-8 | **Billing guards for code payments** (B3 owns billing; this extends D38): <br>• **Refund and delete.** `refund_payment` and `delete_payment` refuse a `code` payment on the fresh, locked row (409 `billing.code_payment`). The guard they call is renamed `refuse_reserved_money` and gains the `code` refusal; its wallet codes are unchanged. **`refuse_wallet_money` stays exported as an alias**, so B3e's imports and tests are untouched. <br>• **Move to the balance.** `credit_payment` refuses only `code`, by an explicit check on the fresh locked row (`fresh.method == CODE` → 409 `billing.code_payment`) placed before its `completed` check. It does **not** call `refuse_reserved_money`: that guard's wallet refusals would break B3e E-12's undo of a spend (`wallet/services/ledger.py:209-232`). <br>• **Manual entry.** `add_payment` and `create_record` refuse method `code` (400 `method`). `NOT_MANUAL` gains `code`, so `create_record` and the serializers already refuse it (`records.py:24, 82-84`; `api/serializers.py:48, 73`), and `MANUAL_PAYMENT_METHODS` and finance's pinned copy are unchanged. <br>• **Payment-row flags.** `deletable`, `refundable` and a new `movable` are false for `code`. `movable` = `completed`, on an invoice, and the method is not `code`. B3e's `MoveToWallet` reads `movable` instead of `status`. <br>• **Only `etqan.vouchers`** records a code payment (`settle_with_code`, `record_code_payment`) or removes one (`delete_code_payment`, discounts only, F-9). <br>While a code payment stands, the invoice cannot be voided or have its amount edited (`refuse_if_paid_into`), and its subscription cannot be deleted (`refuse_if_invoiced`). | ledger D38; billing `services/payments.py:15-27, 86-104, 144-163, 277-310`, `api/payloads.py:67-96`, `services/rules.py:85-87`, `services/subscriptions.py:67-77`, `services/__init__.py:42, 114`; `wallet/tests/test_spending.py:196`; review I1, M12 |
| F-9 | **What can be undone:** <br>• **Activation and renewal redemptions are final.** A used code stays used. If the office made a mistake, it cancels the subscription in scheduling as usual, and the invoice and the code payment stay as a record. An undo would need to remove a payment, an invoice and possibly a renewal across three apps. <br>• **A discount can be removed by the office** (`voucher.update` and `payment.update`, `NotImpersonating`). `vouchers.services.remove_discount(voucher_id, *, reason, by)` runs in one transaction. It locks the voucher, which must be a `used` discount (409 `vouchers.not_discount` for activation and renewal, `vouchers.not_used` otherwise). It calls the new, vouchers-only `billing.delete_code_payment(payment_id)`, which locks the invoice, then the payment, refuses anything but a `code` payment, deletes it and recalculates the invoice. The voucher then becomes `void`, with the reason, never `unused`, so a removed code is never spent again. <br>After a removal the invoice can be voided or edited again. This keeps a discount applied to the wrong invoice from freezing that invoice for good. | P1 §8.5 (used is final); CLAUDE.md (CRUD-first); [assumed]; review I4; orchestrator ruling I4 |
| F-10 | **Status:** the code row stores `unused`, `used` or `void`. **`expired` is derived:** a code is expired when it is `unused` and its `expires_on` is before the academy's today. <br>• "Today" is `scheduling.services.today()`, passed into the query as a value, never `CURRENT_DATE`. <br>• No job flips statuses, so there is no per-academy loop. <br>• The status filter and the CSV use the derived value. <br>`void` is an office action TutorHamster does not show. It lets a lost or leaked code be withdrawn without deleting its record, and it records a reason (up to 200 characters, optional when voiding an unused code). | audit SUB-005 (unused / used / expired); P1 §8.5; CLAUDE.md (jobs loop academies, so avoid a job); `scheduling/services/rules.py:90`; [assumed] (void; derived expiry); review M3 |
| F-11 | **Validity is exactly `valid_days` days, inclusive** (1–3650). `expires_on` = the academy's today when the batch is generated + `valid_days` − 1. A code can be redeemed through `expires_on` on the academy's calendar, so 1 day means today only. Validity limits when the code can be redeemed. It never shortens the subscription, whose term comes from the package. | audit SUB-005 ("validity (days)\*", column "expiry"); P2 `valid_days`, `expires_at`; [assumed] (inclusive; academy calendar); review M3 |
| F-12 | **Code format and entropy:** <br>• 10 characters from Crockford's base-32 alphabet (`0-9 A-Z` without `I L O U`), drawn with `secrets.choice`: 50 bits per code. <br>• Shown as `SYS-XXXXX-XXXXX`, following TutorHamster's `SYS-` prefix. Stored as the 10 bare characters, unique. <br>• **Input is normalized:** spaces and dashes are dropped, the text is upper-cased, and a leading `SYS` is removed when 13 characters remain. <br>• `generate` draws, drops any code already present (one `IN` query) and redraws. A unique violation on `bulk_create` (a concurrent batch drew the same code, about 1e-11) retries the whole draw once inside a savepoint. <br>Codes are stored in plain text, because the office must list, export and print them at any time. They are tenant-scoped, and only `voucher.view_any` lists them. | P1 SUB-005 (`SYS-Y5OED`); [assumed] (length, alphabet, normalization); orchestrator ruling I5; review M14 |
| F-13 | **Guessing protection:** <br>• The family routes (`check/`, `redeem/`) need a signed-in student or parent. <br>• **Two throttles.** A per-user `voucher_redeem` at 20/hour (`ScopedRateThrottle`). A per-IP `voucher_redeem_ip` at 60/hour: a `SimpleRateThrottle` keyed by schema and `get_ident`, as `InquiryIPThrottle` is (`site/throttling.py:21-26`). <br>• An unknown code and a void code give the same answer (400 `vouchers.invalid` on `code`). A used or expired code answers 409 `vouchers.used` / `vouchers.expired`, so a real family knows why. <br>**The guessing math, honestly:** <br>• The space is 32¹⁰ ≈ 1.1 × 10¹⁵. With 10,000 live unused codes in one academy, one guess succeeds with probability ≈ 9 × 10⁻¹². <br>• Self-registration lets an attacker open many accounts (`registration/services.py:337-392`), so the per-IP limit is the real bound: 60/hour is about 5.3 × 10⁵ guesses per IP per year. <br>• That gives about 5 × 10⁻⁶ per IP-year, about 0.5 % a year for an attacker with 1,000 addresses, and about 37 % a year for one with 100,000. <br>• A large botnet running for a year could therefore find one code. The prize is one subscription or one discount. Codes expire, and the office voids leaked ones. That is an accepted risk for a CRUD-first product. <br>Office routes need `voucher.update` and are not throttled. | settings `base.py:399-409`; B3e §5 (throttled family money route); B8c C-10 (per-IP throttle); [assumed] (rates); review I5 |
| F-14 | **Exactly once.** Every redemption is one `@transaction.atomic` call that: <br>1. reads the code with `select_for_update()`, by its normalized text (family and office text routes) or its id (office id route); <br>2. checks status and expiry on that locked row; <br>3. does its work; <br>4. sets `used` with the redemption fields. <br>A second redeemer of the same code waits on the row lock and then gets 409 `vouchers.used`. <br>**Two discount codes on one invoice:** after `billing.record_code_payment` returns, this transaction holds the invoice lock. `redeem` then checks under it for another `used` discount voucher on the invoice (409 `vouchers.invoice_discounted`). The error rolls back the payment through the request transaction (`ATOMIC_REQUESTS`, `set_rollback`). <br>**DB checks:** `used` ⇔ `redeemed_at` set; `used` ⇒ `student` set; `void` ⇔ `voided_at` set. <br>**Unique:** `code`; `payment_id` where it is not null; `invoice_id` where `kind = 'discount'` and `status = 'used'`. The last one is only a final guard: the locked check above answers first, and the constraint is never relied on for the 409. | B3e E-6 pattern; billing `services/payments.py:107-111`; `config/settings/base.py:31`; [assumed]; review M2, M17 |
| F-15 | **Lock order:** `Voucher → Subscription → Session → InvoiceCounter → Invoice → Payment`. <br>• **Activation:** the voucher. Then `create_subscription`, whose `generate_horizon` locks the new subscription and its sessions (`generation.py:93-102`). Then `settle_with_code` locks the subscription again (`lock_subscription`), takes a number, and locks the new invoice. <br>• **Renewal:** the voucher. Then `renew_subscription` locks the old subscription, then the old subscription's sessions (`delete_untouched`, `_postponed_unmarked`) before the new subscription exists. The rest follows as for activation. <br>• **Discount, and removing a discount:** the voucher, then the invoice, then the payment, through billing. <br>Nothing locks a `Voucher` after any of those rows, and nothing outside vouchers locks one. The tail follows scheduling's (`Subscription → Session`) and billing's (`Subscription → Counter → Invoice → Payment`, plan D8) orders, so it stays acyclic with B3e's chains (`Checkout → TopUp → Wallet → Invoice → Payment`; `Subscription → Session → Wallet`). | B3e E-6; billing `services/invoices.py:29-38`, `services/subscriptions.py:52`; scheduling `services/generation.py:93-102`, `services/rules.py:114-130`, `services/subscriptions.py:258-268, 428-444, 627`; review M1 |
| F-16 | **Who redeems for a family:** the student, or a parent of the student (`identity.services.is_parent_of`), the same rule as B3e E-17. A payer who is neither (a paying sibling) cannot. A student with no parent acts alone. <br>• **Discount:** the invoice must be readable through `billing.services.invoice_for(user, id)`, and its student must be the user or one of their children. <br>• **Activation:** the redeemer names one student in scope. <br>• **Renewal:** the subscription must belong to a student in scope. <br>Anything out of scope is a 404. | B3e E-17; `identity/services.py:261`; billing `services/online.py:34-43` |
| F-17 | **Activation redemption:** <br>• It calls `create_subscription(student_id, course_id, teacher_id, package_id, starts_on=today, slots=())`, then `billing.settle_with_code`. Price and currency resolve per D23. <br>• The subscription starts on the academy's today, with no weekly slots: the office adds the lesson times, and the family page says so. <br>• A student may already have a subscription to the course; that is allowed. <br>• A course, package or teacher that is no longer active (scheduling's 400 on `course`, `package` or `teacher`) becomes 409 `vouchers.unavailable` ("This code can't be used right now. Contact the academy."), and the code stays `unused`. A student who is not active stays a 400 on `student`, because the family chose that student. | P1 §16.2; scheduling `services/subscriptions.py:47-78, 179-236`; ledger D23; [assumed] (start today, no slots) |
| F-18 | **Renewal redemption:** <br>• The subscription must be the student's, and its course must be the batch's course (409 `vouchers.wrong_course`). <br>• It calls `renew_subscription(old, package_id=batch.package_id, by=user)`, with no price or currency. The price is the **old subscription's** `price_minor` when the currency is the same (P4-10), otherwise the resolved package price (D23), so D35 does not apply. Then it calls `settle_with_code`. The check step shows that price. <br>• As in F-17, scheduling's 400 on `course`, `package`, `teacher` **or `student`** becomes 409 `vouchers.unavailable`, and the code stays `unused`. The `student` case is included because the family chose the subscription, not the student. <br>• Scheduling's 409s with a `scheduling.*` code pass through: `scheduling.archived`, a wrong status, `scheduling.already_renewed`. <br>• The renewal's start date is scheduling's default (`renewal_starts_on`). | audit SUB-002; scheduling `services/subscriptions.py:61-65, 608-706`; ledger D23, D35; review I2; orchestrator ruling I2 |
| F-19 | **Discount redemption:** <br>• It reads the invoice through `invoice_for` (F-16). A void invoice is 409 `billing.invoice_void`; nothing due is 409 `billing.nothing_due`. <br>• It checks the batch's scope against the invoice's subscription, read through `scheduling.services.subscriptions_queryset()`. A package mismatch, or a scoped code on an invoice with no subscription, is 409 `vouchers.wrong_package`. A course mismatch is 409 `vouchers.wrong_course`. A scoped package that is now inactive still matches existing invoices of it. <br>• It computes the amount (F-4) from `amount_minor` and calls `billing.record_code_payment(invoice, amount_minor=…, up_to_balance=True)`, which caps at the balance under the invoice lock. It then runs F-14's check for another discount. <br>• A discount applied while a family's online checkout is open can make that checkout's later payment exceed the balance. It then goes to B3b's "needs attention", exactly as a manual payment recorded meanwhile would. | billing `services/online.py:34-43`, `services/rules.py:90-95`; phase B3-7 / ledger D13 (needs attention); [assumed]; review M17 |
| F-20 | **The office:** <br>• **Generate:** a batch of 1–500 codes with a note of up to 200 characters (`voucher.create`). <br>• **List and filter:** by kind, derived status, discount kind, batch, and a code search; `?code=` is an exact match on the normalized code (`voucher.view_any`). <br>• **Export** the filtered list to CSV (`voucher.view_any`). <br>• **Void** one unused code, expired ones included, with an optional reason (`voucher.update`). A used or void code is 409 `vouchers.not_unused`. Codes are voided one at a time: the filtered list makes that quick for 500 codes. <br>• **Redeem or apply for a family**, by id from the list or **by code text** (exact normalized match). This needs `voucher.update` plus what the same manual action needs: `subscription.create` for activation, `subscription.update` for renewal, `payment.create` and `invoice.view` for a discount. <br>• **Remove a discount** (F-9; `voucher.update` + `payment.update`). | audit SUB-005 (list, filters); phase row ("generated in bulk"); scheduling `api/views.py:168, 256`; billing `api/views.py:186, 280`; [assumed] (limits, void, export); review I3, M13; orchestrator rulings I3, I4 |
| F-21 | **Access:** a new resource `voucher` ("System codes" / "أكواد النظام"), with verbs in use `view_any`, `create` and `update`. <br>• Admins hold every code. Teachers hold none. The Supervisor preset gains nothing. <br>• Families act by role, scoped by F-16. <br>• Every route that redeems or removes, office and family, adds `NotImpersonating`, because a redemption pays like money. | spec roles-permissions; `access/registry.py:122-159`; ledger D19 |
| F-22 | **Feature `system_codes`** ("System codes" / "أكواد النظام", group `money`), built, `default=False`, `requires=()`. <br>• It covers TutorHamster's "activation code" gateway switch as well. <br>• Discount routes and the invoice action also need `invoices` (404 otherwise). <br>• While `system_codes` is off, every vouchers route is a 404. Codes stay as they are, and redeem normally once the feature is back on. Code payments already recorded stay, and billing's guards (F-8) still hold. | phase B3-3; audit SYS-003; `platform/features.py:259-281` |
| F-23 | **Notices.** Nothing is sent on generating or redeeming a code. B5's "new invoice" notice reads `billing.services.invoices_issued` (`notifications/finders.py:151`). That finder is billing's, so B3f changes it to **skip an invoice that is `paid` and has a `code` payment**. Without this, every activation and renewal would announce an invoice that is already paid, even in academies whose auto-invoice setting is off. B5's finder code is unchanged. A discounted invoice that is still open is announced as before. | ledger D39 (pull-based notices); billing `services/notices.py:16-24`; review M8 |
| F-24 | Strings in en and ar only. | ledger D11, D22 |
| F-25 | **The batch's `course`, `package` and `teacher` are `PROTECT` foreign keys.** A deleted target can never turn a scoped discount into a universal one. Catalogue deletes are refused while any batch references the row, and the existing delete paths answer that as a 409, never a 500: <br>• **courses and packages:** `delete_course` and `delete_package` go through catalogue's `_delete`, which already maps `ProtectedError` to 409 `catalogue.in_use` (`catalogue/services.py:100-108, 125-126, 200-201`). B3f widens its message from "has subscriptions" to "is used by subscriptions or system codes", and keeps the code. The dashboard already shows `catalogue.in_use`. <br>• **teachers:** identity has no delete path for a teacher, who is deactivated, never deleted (`identity/services.py:977-999`). So `PROTECT` cannot be reached from the API, and a deactivated teacher makes an activation code `unavailable` (F-17). <br>An inactive (not deleted) target behaves as in F-17 to F-19. | orchestrator ruling C1; review C1 |

## 3. Data

### 3.1 `etqan.vouchers`

**`VoucherBatch`:**
- `kind`: `activation | renewal | discount`;
- `course` → `catalogue.Course`, nullable, `PROTECT`;
- `package` → `catalogue.Package`, nullable, `PROTECT`;
- `teacher` → `identity.TeacherProfile`, nullable, `PROTECT` (F-25);
- `valid_days`: 1–3650; `expires_on` (date, academy calendar, F-11);
- `discount_kind`: `"" | percent | fixed`;
- `discount_value`: an integer (a percent, or minor units), default 0;
- `currency`: `""` or `^[A-Z]{3}$`;
- `quantity`: 1–500;
- `note`: up to 200 characters;
- `created_by` → user, `SET_NULL`;
- `created_at` (UTC).

**Checks:**
- `discount_kind` is set if and only if `kind = 'discount'`;
- `percent` needs a value of 1–100 and no currency;
- `fixed` needs a value of 1–100,000,000 and a currency;
- the other kinds have value 0 and no currency;
- `activation` needs a course, a package and a teacher; `renewal` needs a course and a package and no
  teacher; `discount` has no teacher. With `PROTECT`, these hold for the row's whole life.

The service also checks that the targets are active, and that the teacher is active and, when
`catalogue.services.teacher_user_ids_for_course(course)` is non-empty, in it. This mirrors scheduling's
`_teacher` (`subscriptions.py:68-78`), which accepts any active teacher for a course that lists none.

**`Voucher`:**
- `batch` → VoucherBatch, `PROTECT`, related name `codes`;
- `kind`: copied from the batch, for the partial unique constraint;
- `code`: 10 characters, unique;
- `status`: `unused | used | void`, indexed;
- `redeemed_at`, `redeemed_by` → user (`SET_NULL`);
- `student` → `identity.StudentProfile`, nullable, `PROTECT`;
- plain ids, nullable: `subscription_id`, `invoice_id`, `payment_id`;
- `voided_at`, `voided_by` → user (`SET_NULL`), `void_reason` (up to 200 characters);
- `created_at`.

**Checks:**
- `used` ⇔ `redeemed_at` is not null;
- `used` ⇒ `student` is not null;
- `void` ⇔ `voided_at` is not null.

**Unique:**
- `code`;
- `payment_id` where it is not null;
- `invoice_id` where `kind = 'discount'` and `status = 'used'`.

It is indexed on `(batch, id)`. A removed discount keeps its `invoice_id` and `payment_id` as history (the
payment row is gone, F-9).

### 3.2 `etqan.billing`

- `Payment.Method` gains `CODE = "code"` ("System code");
- a check, `billing_payment_code_on_invoice`: method `code` implies an invoice and `fee_minor = 0`.

Existing rows satisfy the check.

### 3.3 `etqan.catalogue`

No model change. One message in `_delete` (F-25).

## 4. Behaviour

### 4.1 Billing services (new, public; `etqan.vouchers` only, like D38's wallet services)

- **`settle_with_code(subscription_id, *, reference, by) -> Invoice | None`:**
  - it returns None while `invoices` is off;
  - it locks the subscription with `lock_subscription`, and returns None for a price of 0;
  - otherwise it issues the subscription's invoice as `invoice_subscription` does (active student, the
    default payer, the description in the academy's language, due after `invoice_due_days`), without reading
    `auto_invoice_on_subscription`;
  - it records a `code` payment for the full amount and recalculates, so the invoice is `paid`.

  The shared body of `invoice_subscription` moves into a private `_issue_for(subscription, *, by, issued_on)`,
  and the setting check stays in `invoice_subscription` alone.
- **`record_code_payment(invoice, *, amount_minor, reference, by, up_to_balance=False) -> Payment`:**
  - it locks the invoice and refuses a void one;
  - it reads the balance on the locked row. With `up_to_balance`, the amount becomes `min(amount, balance)`,
    and a balance of 0 is 409 `billing.nothing_due`. Without it, billing's one balance rule applies;
  - it writes the payment, dated today with no fee, and recalculates.
- **`delete_code_payment(payment_id) -> Invoice`:** locks the invoice, then re-reads the payment with
  `select_for_update`.
  - A missing payment is 404.
  - A payment that is not method `code` is 409 `billing.not_code_payment`.
  - Otherwise it deletes the payment, recalculates the invoice and returns it.
- **Guards** (F-8):
  - `refuse_reserved_money(fresh)` adds `code` → 409 `billing.code_payment`, and `refuse_wallet_money` stays
    as an alias;
  - `refund_payment` and `delete_payment` call it, as today;
  - `credit_payment` checks `fresh.method == CODE` itself;
  - `add_payment` and `create_record` refuse `code`;
  - `NOT_MANUAL = ONLINE_METHODS | {WALLET, CODE}`.
- **`revenue_between`** also excludes `code` (F-7).
- **`invoices_issued`** skips paid invoices with a `code` payment (F-23).
- **Payment rows** gain `movable`. `deletable` and `refundable` are false for `code`.

### 4.2 Vouchers services (`etqan/vouchers/services/`)

**Writes.** Every write is `@transaction.atomic`.

- **`generate(*, kind, quantity, valid_days, course_id=None, package_id=None, teacher_user_id=None, discount_kind="", discount_value=0, currency="", note="", by) -> VoucherBatch`:**
  - it validates against F-3, F-4 and §3.1;
  - `expires_on` follows F-11;
  - it draws the codes and `bulk_create`s them (F-12).
- **`void(voucher_id, *, by, reason="")`:** locks the code, which must be `unused` (expired included;
  otherwise 409 `vouchers.not_unused`), and sets `void`.
- **`redeem(*, code=None, voucher_id=None, user, student_user_id=None, subscription_id=None, invoice_id=None, office=False) -> Redemption`:**
  - it locks the voucher by its normalized code or its id (F-14), and refuses `invalid`, `used` and `expired`;
  - by kind:
    - **activation** needs `student_user_id` (F-16, F-17);
    - **renewal** needs `subscription_id` and derives the student from it (F-18);
    - **discount** needs `invoice_id` and derives the student from the invoice (F-19);
  - a missing target is a 400 on that field; a target given for another kind is ignored;
  - it calls scheduling and billing, then sets `used`, `redeemed_at`, `redeemed_by`, `student`,
    `subscription_id`, `invoice_id` and `payment_id`;
  - it returns `Redemption(kind, subscription_id, invoice_id, amount_minor, currency)`.

  Family scope (F-16) applies when `office` is False. Office callers are checked for their codes in the
  view (F-20).
- **`remove_discount(voucher_id, *, reason, by) -> Voucher`:** F-9. `reason` is 1–200 characters.

**Reads:**
- `normalize(text) -> str` (F-12);
- `display(code) -> str`;
- `vouchers_queryset(today)`, annotated with the derived `state` (F-10), joined to the batch, course,
  package, teacher and student, in a fixed number of queries;
- `filter_vouchers(qs, *, kind, state, discount_kind, batch, q, code)`;
- `batches_queryset()`, for the batch filter;
- **`preview(code, *, user) -> Preview`**, the family's check step. It refuses as `redeem` does, without
  locking. It answers:
  - the kind, the course and package names, the session count, the teacher's name (activation), the discount
    (kind, value, currency), and `expires_on`;
  - **activation:** the active students in scope;
  - **renewal:** each student's eligible subscriptions, with the price the renewal will take (F-18). A
    subscription is eligible when it is in scope, in the batch's course, has status
    `active | paused | expired`, and has no live renewal (`renewal_id` is null), read through
    `subscriptions_queryset()`. It applies **the same archive rule as scheduling's `refuse_if_archived`**
    (`rules.py:177-182`): an archived subscription is excluded only while `subscription_archive` is on;
  - **discount:** no targets; the page points to the invoices (§6).
- `has_batches()` for the seeds.

## 5. API summary (`/api/v1/vouchers/`)

Office payloads show codes as `SYS-XXXXX-XXXXX`. A family never lists codes.

| Route | Methods | Feature | Permission |
|---|---|---|---|
| `batches/` | GET, POST | `system_codes` | GET `voucher.view_any` (paginated: kind, terms, note, `expires_on`, `quantity`, `created_by`); POST `voucher.create`: `{kind, quantity, valid_days, course?, package?, teacher?, discount_kind?, discount_value?, currency?, note?}` → 201 batch |
| `codes/` | GET | `system_codes` | `voucher.view_any`. Filters `?kind=&state=&discount_kind=&batch=&q=&code=`, paginated. With `?format=csv` it returns the CSV (code, kind, course, package, teacher, discount, `expires_on`, state, `redeemed_at`, student, batch note, void reason) through `CSVExportMixin`. Row: `{id, code, kind, state, batch: {id, note}, course, package, teacher, sessions_total, discount, expires_on, redeemed_at, redeemed_by, student, subscription_id, invoice_id, void_reason, created_at}` |
| `codes/<id>/void/` | POST | `system_codes` | `voucher.update`: `{reason?}` |
| `codes/<id>/redeem/` | POST | `system_codes` (+`invoices` for a discount) | `voucher.update` plus the kind's own code (F-20), checked in the view; `NotImpersonating`: `{student?, subscription?, invoice?}` → 201 `Redemption` |
| `codes/redeem/` | POST | `system_codes` (+`invoices` for a discount) | The same as above, by code text (exact normalized match): `{code, student?, subscription?, invoice?}` → 201 `Redemption`. Not throttled. An unknown or void code is 400 `vouchers.invalid`. |
| `codes/<id>/remove-discount/` | POST | `system_codes` + `invoices` | `voucher.update` and `payment.update`, `NotImpersonating`: `{reason}` → the voucher row |
| `check/` | POST | `system_codes` | Student or parent; throttles `voucher_redeem` and `voucher_redeem_ip`: `{code}` → `Preview` |
| `redeem/` | POST | `system_codes` (+`invoices` for a discount) | Student or parent; `NotImpersonating`; throttles `voucher_redeem` and `voucher_redeem_ip`: `{code, student?, subscription?, invoice?}` → 201 `Redemption` |

**Payload changes in billing:**
- the `method` enum gains `code`;
- payment rows gain `movable`.

**Error codes:**
- `vouchers.invalid` (400, `code`);
- `vouchers.used`, `vouchers.expired`, `vouchers.not_unused`, `vouchers.not_used`, `vouchers.not_discount`,
  `vouchers.unavailable`, `vouchers.wrong_course`, `vouchers.wrong_package`, `vouchers.wrong_currency`,
  `vouchers.invoice_discounted` (409);
- `billing.code_payment`, `billing.not_code_payment`, `billing.nothing_due` (409).

## 6. Dashboard

The new feature folder is `src/features/vouchers/`. Billing, wallet and scheduling never import it: routes pass
`ApplyCode` and `RemoveDiscount` into billing's `InvoicePage` through `actions` and `paymentActions` (B3e's
pattern). Every redemption or removal invalidates the vouchers, invoice, billing records and subscriptions
queries.

- **Office → System codes** (`_authed/billing.codes.tsx`, `voucher.view_any`, `system_codes`):
  - **The table:** code (with copy), kind, course · package, teacher, discount, expiry, a state chip, and
    "redeemed by {student} on {date}" with links to the subscription or invoice.
  - **Filters:** kind, state, discount kind, batch; a search box.
  - **Export CSV** follows the filters.
  - **Generate codes** (`voucher.create`), as a dialog:
    - kind; course and package (required except for a discount); teacher (activation only). The teacher list
      shows the course's teachers, or every active teacher when the course lists none (F-3);
    - quantity, validity in days, and for a discount the type (percent / fixed), the value and the currency;
    - it shows the package's session count;
    - on success, it filters the table to the new batch.
  - **Row actions** (`voucher.update`):
    - **Void**, with a confirm dialog and an optional reason;
    - **Redeem for a student**, for activation and renewal: find a student, and for renewal one of their
      eligible subscriptions. The dialog hides without the kind's extra code (F-20);
    - **Remove discount**, on a used discount (`voucher.update` + `payment.update`), with a required reason.
- **Family → Redeem a code** (`_authed/learning.codes.tsx`, students and parents, `system_codes`):
  1. Enter the code. **Check** calls `check/` and shows what it is.
  2. For **activation**, choose the student (a lone student is preselected). Confirm. The page then says "Your
     subscription has started. The academy will set your lesson times." and links to My subscriptions.
  3. For **renewal**, choose the subscription. Each one shows the price its renewal takes. With none eligible,
     the page explains why.
  4. For a **discount**, the page says "Open the invoice you want to reduce and apply the code there", with a
     link to the invoices.
  5. Server errors, the 429 included, show by code.

  Its nav item sits under the B3 marker, group `learning`, `requiresRole: ["student", "parent"]`, feature
  `system_codes`.
- **Invoice page, office and family** (`billing.invoices.$invoiceId.tsx`, `learning.invoices.$invoiceId.tsx`):
  - **`ApplyCode`** in `actions`. It shows while the invoice is not void and has a balance, `system_codes` and
    `invoices` are on, and the viewer is either:
    - **in the family:** the invoice's student, or a parent of that student (the dashboard knows the
      children). A paying sibling does not see it;
    - **office staff** with `voucher.update`, `payment.create` and `invoice.view`.

    Its dialog takes a code. The family posts it to `redeem/`, the office to `codes/redeem/`, each with the
    invoice. It shows the amount taken off ("Discount of {amount} applied").
  - **`RemoveDiscount`** in `paymentActions`, office only, on a `code` payment whose voucher is a discount. It
    finds the voucher with `codes/?code=` from the payment's reference.
- **Billing changes:**
  - the method label "System code";
  - `InvoicePrint` and `PaymentRecordsPage` show it;
  - B3e's `MoveToWallet` reads `movable` (F-8);
  - the records page's method filter gains it;
  - the `catalogue.in_use` text follows the new message (F-25).
- **Wiring:**
  - `locales/{en,ar}/vouchers.json`, plus the new keys in `billing.json`;
  - the `vouchers.*` and new `billing.*` error codes in the server-error text;
  - `FeatureCode` gains `system_codes` under the B3 comment;
  - `FEATURE_SCREENS` and `FEATURE_WORDS` gain rows;
  - office nav `/billing/codes` (`voucher.view_any`, `system_codes`) and family nav `/learning/codes`, both
    under the B3 marker;
  - semantic tokens, RTL, phone width; codes in a monospace, left-to-right span inside RTL text.

## 7. Dependencies, wiring and cross-phase hooks

- **No new package or environment variable.** Two settings lines in `config/settings/base.py`, next to B3g's:
  - `DEFAULT_THROTTLE_RATES["voucher_redeem"] = "20/hour"`;
  - `DEFAULT_THROTTLE_RATES["voucher_redeem_ip"] = "60/hour"`.

  The IP throttle class lives in `etqan/vouchers/throttling.py`.
- **Wiring under the B3 markers:**
  - `etqan.vouchers` in `TENANT_APPS` and `config/api_router.py` (`vouchers/`);
  - `system_codes` in `platform/features.py`;
  - the `voucher` resource in `access/registry.py`;
  - the route matrix rows and `FEATURE_WORDS["/vouchers/"] = "system_codes"`;
  - the two family routes named as role-exempt in `test_routes.py`, as B3e's are (`:929-933`);
  - `seed_vouchers` in `seed_dev` (§8).
- **Import contracts** (`pyproject.toml`, under the B3 marker):
  - "vouchers reaches other apps only through their services": identity, academy, catalogue, scheduling and
    billing `services`, and `platform`;
  - "other apps reach vouchers only through its services". Its source list includes `etqan.tenants`, whose
    seeds call `vouchers.services`;
  - "billing never imports vouchers";
  - "scheduling never imports vouchers";
  - "catalogue never imports vouchers";
  - `etqan.vouchers` is added to "gateways imports no business app"'s forbidden list.
- **Catalogue.** The one changed message in `_delete` (F-25) is outside B3's pricing fields of catalogue.
  Like B3e's student-page card, B3f makes it and notes it in the ledger. The code `catalogue.in_use` is
  unchanged.
- **B2 (scheduling): no request.** This is the phase row's "recorded when B3f's spec is written". B3f uses only
  public, exported services (`scheduling/services/__init__.py:83-101`):
  - `create_subscription`, with D23's resolution already inside;
  - `renew_subscription`, P4-10 plus D23;
  - `subscriptions_queryset`;
  - `lock_subscription`, through billing;
  - `today`.

  It adds no field, signature or line to scheduling's code or routes. The family's new subscription appears on
  B2's existing "My subscriptions" page unchanged. If B2 later changes these signatures, ledger D23 and D35
  already name B3f as affected.
- **B5: no request.** The "new invoice" skip (F-23) is in billing's finder, which B5 already calls.
- **Ledger, to record from this spec** (as D36 to D38 were from B3e's):
  - **revenue and guards:** "Refines D36 and D38: billing payments with method `code` (B3f system codes) are
    never revenue; a code is revenue only when the academy records its sale as a payment record. Billing
    refuses to refund or delete (`refuse_reserved_money`, alias `refuse_wallet_money`) or move to the balance
    (`credit_payment`'s own check) a `code` payment (409 `billing.code_payment`). Only `etqan.vouchers`
    records one (`settle_with_code`, `record_code_payment`) or removes one (`delete_code_payment`, discounts
    only, by the office with `voucher.update` + `payment.update`). Activation and renewal redemptions are
    final."
  - **reads for later phases:** "Later phases (B7 recorded courses, P1 RC-003 'activation code') reach codes only
    through `vouchers.services`; B7 asks B3 for a new kind rather than reading voucher models."
  - **catalogue:** "Catalogue's `_delete` message reads 'is used by subscriptions or system codes' (B3f F-25);
    the code `catalogue.in_use` is unchanged."

## 8. Seeds

The seeds go in a new module, `etqan/tenants/seeds/vouchers.py` (`seed_vouchers(subdomain)`).
- It is called under the B3 marker after `wallet_seeds.seed_wallet`.
- It runs only for **demo** and only when the academy has no batch (`has_batches()`).
- It uses vouchers services only.
- `seed_dev.FEATURES` enables every built feature, so `system_codes` is on for demo.

For **demo:**
- an **activation** batch of 5 codes: Quran Memorisation, "Monthly, 2 a week", Ustadha Maryam (who teaches the
  course, `seed_dev.py:87-126`), valid for 90 days, note "Demo activation codes";
- a **discount** batch of 3 codes: 10 %, no package, valid for 90 days, note "Demo discount codes".

Nothing is redeemed, so no subscription, invoice or revenue changes. The codes are random on each fresh seed,
and no e2e journey reads them. The **other** academy gets nothing.

## 9. Testing

### Backend

Throttle counters live in the process-wide locmem cache. The vouchers tests clear it in an autouse fixture, as
`gateways/tests/conftest.py:145-149` does, so one test's calls never 429 the next.

**Generation:**
- the requirements per kind (F-3, §3.1):
  - an activation without a teacher, or with a teacher outside a course that lists teachers;
  - an activation whose course lists no teachers accepts any active teacher;
  - a renewal without a package;
- the discount checks (F-4): a percent of 0 or 101, a fixed amount without a currency, a currency on a
  percent;
- the limits for quantity (0, 501) and `valid_days` (0, 3651);
- codes are 10 characters from the alphabet and distinct;
- `expires_on` = today + `valid_days` − 1 (F-11);
- a forced collision (a patched `secrets.choice`) is redrawn;
- a forced `bulk_create` unique violation retries once;
- the DB checks reject a bad `used`/`void` pairing, `used` without a student, and bad batch discount
  fields.

**Normalization:** `sys-abcde-fghjk`, spaces, and the bare 10 characters find the same code.

**State and expiry:**
- with `valid_days = 1`, the code redeems today and reads `expired` tomorrow (a frozen academy date);
- with `valid_days = 30`, it redeems on day 30 and is expired on day 31;
- the derived state appears in the filter and the CSV;
- void works on unused and expired codes and stores the reason; on a used code it is 409
  `vouchers.not_unused`;
- a code generated, then switched off with the feature (404), then switched back on still redeems.

**Catalogue (F-25):**
- deleting a package, or a course, that a batch references is 409 `catalogue.in_use` with the new message,
  never a 500;
- a discount batch scoped to a package keeps that scope: an unrelated invoice is 409 `vouchers.wrong_package`.

**Activation:**
- it creates a subscription for the batch's course, package and teacher, starting today, with no slots;
- its price and currency follow D23 (country pricing on, with a row);
- one invoice, `paid` by one `code` payment with the code as reference;
- with `auto_invoice_on_subscription` off, the invoice is still issued;
- with `invoices` off, there is no invoice and the code is still `used`;
- a price of 0 writes no invoice;
- an inactive package, course or teacher is 409 `vouchers.unavailable`, and the code stays `unused`;
- a student outside the family is 404.

**Renewal:**
- it renews the chosen subscription with the batch's package at P4-10;
- its invoice is paid by code;
- another course is 409 `vouchers.wrong_course`;
- the batch's package deactivated, the old teacher deactivated, and the student deactivated are each 409
  `vouchers.unavailable`, and the code stays `unused`;
- archived (with `subscription_archive` on), already renewed, and cancelled pass scheduling's 409s through,
  and the code stays `unused`;
- with `subscription_archive` off, an archived subscription is listed by `preview` and renews (one rule).

**Discount:**
- percent with rounding half up, and the 1-unit minimum;
- fixed;
- the cap at the balance on a partly paid invoice, and 100 % paying the invoice in full;
- each refusal: the wrong currency, the wrong package, the wrong course, a scoped code on an invoice without a
  subscription, a void invoice, nothing due;
- a second discount code on the same invoice is 409 `vouchers.invoice_discounted`, checked under the invoice
  lock, with the second payment rolled back;
- a sibling payer gets 404;
- an office discount by code text through `codes/redeem/`.

**Removing a discount (F-9):**
- the payment is deleted, the invoice recalculated, and the voucher is `void` with the reason;
- the invoice can then be voided;
- it is refused for an activation or renewal code (`vouchers.not_discount`) and an unused code
  (`vouchers.not_used`);
- staff without `payment.update` are refused;
- `delete_code_payment` refuses a cash payment (`billing.not_code_payment`).

**Exactly once and locking, without threads:**
- a code loaded `unused` is redeemed, and redeeming it again from the stale copy is 409 `vouchers.used`;
- **the lock order from captured SQL.** The tests assert the relative order of the first `FOR UPDATE` on each
  table, not an exact list (scheduling locks some rows twice):
  - activation: voucher < subscription < invoice;
  - renewal: voucher < subscription < session < invoice;
  - discount and removal: voucher < invoice < payment;
- a failure after the voucher lock (for example `already_renewed`) rolls everything back.

**Billing (F-5 to F-8, F-23):**
- `refund_payment` and `delete_payment` refuse `code` with `billing.code_payment`, decided on the fresh row
  (the C1 pattern);
- `credit_payment` refuses `code`;
- `credit_payment` still moves a `wallet` payment, so B3e's `test_moving_a_wallet_payment_undoes_the_spend`
  passes unchanged, and a `credited` payment still answers `billing.payment_not_completed`;
- `refuse_wallet_money` is still importable;
- `add_payment` and `create_record` refuse `code`;
- the pinned `MANUAL_PAYMENT_METHODS` test still passes;
- the flags `deletable`, `refundable` and `movable` for each kind of payment;
- voiding an invoice paid by code is 409 `billing.has_payments`;
- deleting the subscription is refused (`billing.subscription_invoiced`);
- `invoices_issued` skips a code-paid activation invoice and keeps a discounted open one.

**Revenue (F-7):**
- a code payment never counts;
- a payment record for a code sale counts once;
- end to end: record a 1,500.00 sale and redeem an activation for 1,500.00, and revenue is 1,500.00;
- net profit follows `revenue_between`.

**Family routes:**
- a student and a parent redeem;
- staff and teachers get 403;
- impersonation is 403;
- the 21st call in an hour from one user is 429;
- the 61st call in an hour from one IP, across several users, is 429;
- an unknown code and a void code give the identical 400 body;
- `check` returns the renewal targets with their prices, and the activation students.

**Office routes:**
- each code (`view_any`, `create`, `update`);
- office redemption by id and by text needs the kind's extra code (F-20);
- `?code=` is an exact match;
- the CSV's columns and filters;
- fixed query counts for the list.

**Feature, matrix and isolation:**
- `system_codes` is built, off by default and `requires=()`;
- every route is 404 while it is off;
- discount routes are 404 with `invoices` off;
- the role × route rows;
- cross-academy isolation of both tables: a code from one academy is `vouchers.invalid` in another;
- `lint-imports`.

**Seeds:** idempotent; two batches, eight unused codes; no invoice or payment is written.

### Dashboard

- `CodesPage`: the table, the state chips, the filters, the CSV link, hidden without codes or the feature;
- `GenerateCodesDialog`:
  - the fields per kind (teacher only for activation, the discount fields only for a discount);
  - the teacher list limited to the course, or all teachers when the course lists none;
  - the session count;
  - the server errors mapped onto the fields;
- void with its reason; `RemoveDiscount` with its required reason;
- `OfficeRedeemDialog` for activation and renewal, hidden without the extra code;
- `RedeemCodePage`: check, then activation with one and with two students, renewal with eligible and with no
  subscriptions (and the shown price), the discount pointer, each error code's text, and the 429;
- `ApplyCode`:
  - shown for the student and a parent, hidden for a sibling payer and in the other hidden cases;
  - the office posts to `codes/redeem/`;
  - the applied amount, and a second code refused;
- billing: the "System code" label in `InvoicePage`, `InvoicePrint` and `PaymentRecordsPage`, and
  `MoveToWallet` hidden when `movable` is false;
- the nav items, `FeatureCode`, and both languages with RTL (the code kept LTR).

### E2E

The file is `dashboard/e2e/b3-codes.spec.ts`. It is safe to rerun:
- a **fresh parent and child per run** ("E2E Codes Payer/Child {stamp}"), as `b3-wallet.spec.ts` does;
- batches noted "E2E {stamp}", and the table filtered to that batch;
- the discount invoice in **USD**, closed at the end;
- code payments are never revenue, and USD revenue is not asserted by `b3-finance.spec.ts`. So
  `b3-finance.spec.ts`'s exact EGP net-profit deltas are untouched even when local runs are `fullyParallel`.

Steps:
1. `manage("set_features", "demo", "--on", "invoices", "system_codes")`.
2. The admin creates the parent and the child, and links them.
3. On System codes, the admin generates an **activation** batch of 2 (Quran Memorisation, "Monthly, 2 a week",
   Ustadha Maryam, 30 days, note "E2E {stamp} activation"), filters to it, and reads both codes.
4. The parent signs in. On Redeem a code they enter the first code, typed in lower case with spaces. They see
   the course and package, choose the child, and redeem. My subscriptions lists the new subscription. Its
   invoice reads Paid, with a "System code" payment.
5. The parent enters the same code again and sees "already used".
6. The admin voids the second code, and its chip reads Void. The parent entering it sees "not valid".
7. The admin creates a 200.00 USD invoice for the child and generates a **discount** batch of 1 (10 %, note
   "E2E {stamp} discount"). The parent opens the invoice, applies the code, and sees "Discount of 20.00
   applied". The invoice reads Partly paid with a balance of 180.00.
8. The admin records the 180.00 balance in cash on that invoice. It reads Paid, so no open invoice is left
   behind.

## 10. Out of scope

- **Undoing an activation or renewal redemption** (F-9).
- **A sale price on a batch, or selling codes online.** The sale is recorded as a payment record (F-7). Online
  code sales, and codes for recorded courses (P1 RC-003), are B7's.
- **Editing a batch's terms** after generation. The office voids its codes and generates a new batch.
- **Voiding a whole batch at once**, and per-state counts on the batch list. Codes are voided one at a time
  (review M13).
- **Mapping look-alike characters** (`O`→`0`, `I`/`L`→`1`) on input. The alphabet has no `I L O U`, so such
  input is simply invalid. This is cheap to add later (review M13).
- **Codes limited to one student or family**, multi-use codes, and per-code usage limits: not observed.
- **A discount on a subscription's price before invoicing.** Subscriptions are paid through their invoices
  (P6-1), so the discount applies to the invoice.
- **Choosing a start date or lesson times on redemption.** The office schedules (F-17).
- **Back-filling invoices** for subscriptions activated while `invoices` was off (F-6).
- **Sending notices** about codes (F-23).
- **A background expiry job** (F-10).

## 11. Open questions

None. Every decision above is sourced or marked `[assumed]`.
