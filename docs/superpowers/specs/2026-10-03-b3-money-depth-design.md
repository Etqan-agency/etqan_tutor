# Phase B3 — Money depth — Phase design

**Date:** 2026-10-03
**Status:** Approved by the B3 orchestrator on 2026-10-03, after an independent spec review whose findings
are folded in (orchestration spec PO-3).
**Phase:** B3 of the parity roadmap (`2026-09-24-parity-roadmap-design.md`): per-country package pricing;
discount / activation / renewal codes; per-country manual payment methods; student wallet; donations;
expenses and net profit; service fee; exchange rates; Stripe / PayPal gateways, payment links and webhooks
(CATALOG-003; SUB-005; BILL-002…007; SYS-003).
**Depends on:** B0 billing (Plan 6, merged) and B1 payer (Plan 11 families, merged). No B2–B11 slice for the
phase as a whole; two slices name B2 hooks (§3).
**Ownership (ledger):** `billing`, and the pricing fields of `catalogue`. New areas go in new apps.

This document splits B3 into slices and fixes the decisions every slice shares. Each slice then has its own
spec (`2026-10-03-b3a-…`, …) with the full detail.

## 1. Goal

Give an academy every money tool TutorHamster has: what it spends and what it is given (expenses,
donations, net profit), how families pay online (Stripe, PayPal, payment links, a service fee), what each
country pays and how (country prices, local payment methods, exchange rates), money held for a student
(wallet), and codes that activate, renew or discount a subscription. Every piece ships switched off.

## 2. Phase decisions

Sources: `audit` = `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`, `P1` = `docs/PHASE_1_SYSTEM_AUDIT.md`,
`spec <file>` = an earlier spec, `[assumed]` = not observable in either audit (orchestration spec PO-2).

| # | Decision | Source |
|---|---|---|
| B3-1 | B3 is built as eight slices (re-sliced on 2026-10-03 when B3b's spec split PayPal and payment links into B3c, again when B3c's review split payment links and records into B3g, and on 2026-10-05 when B3d's review split exchange rates into B3h), in the order of §3: B3a, B3b, B3c, B3g, B3d, B3h, B3e, B3f. Expenses come first because B4 (payroll depth) needs them; gateways second because B7 (add-on sales) needs them. | roadmap §2 (B4 needs "B3 expenses", B7 needs "B3 gateways"); orchestration spec §6.3 |
| B3-2 | New apps, each in `TENANT_APPS` under the B3 marker with its own import contract: `etqan.finance` (expenses, donations, net profit), `etqan.gateways` (online providers, checkouts, payment links, webhooks), `etqan.wallet` (student balances), `etqan.vouchers` (B3f; TutorHamster's "system codes"; named so it is not confused with permission codes). `etqan.billing` keeps invoices and payments and gains the new payment methods; `etqan.catalogue` gains the country prices. | orchestration spec §4.3 ("new business areas go in new apps") |
| B3-3 | **Every B3 feature is off by default.** TutorHamster's own flags become built in place, written with an explicit `default=False` (`_built(...)` defaults to on): `donations`, `balances`, `country_pricing`, `payment_links`, `payment_receipts`. Features TutorHamster has without a flag go under the B3 marker, also `default=False`: `expenses`, `online_payments`, `system_codes`, `exchange_rates`. Prerequisites: `payment_links` requires `online_payments`. `balances` requires nothing; its online top-up appears only while `online_payments` is on too. The seeded demo academy turns on every built feature (`seed_dev.FEATURES`, Plan 13 §7). | orchestration spec PO-5; audit §2.10 / P1 SYS-002 (flag list); spec feature-toggles §3.3, §7 |
| B3-4 | **Money stays integer minor units plus an ISO 4217 currency, and is never summed across currencies.** Exchange rates (B3h) only ever produce figures labelled as converted estimates, next to the per-currency truth. | spec 2026-09-25-billing P6-6; CLAUDE.md |
| B3-5 | **Revenue** is what TutorHamster calls it: money received from completed payment records (BR-47). Donations are recorded and reported separately and are not revenue. **Net profit** = revenue − expenses, per currency, per academy month (BR-48). Today every billing payment is a received payment; once B3b gives payments a status, revenue counts `completed` ones only. | P1 BR-47, BR-48; audit §3 #9 |
| B3-6 | **Gateways use each academy's own merchant account**, entered by the academy admin (TutorHamster: settings → payment gateways). Secrets are encrypted at rest with Fernet (`cryptography`) under a key from the environment variable `ETQAN_SECRETS_KEY`. In development and tests a missing key is derived from `SECRET_KEY`; in production a missing key makes saving or using gateway secrets fail closed. The secrets are never returned by the API. B3b asks the conductor to add the variable to `infra/` and CI. Development and CI use test keys only; live keys are an owner escalation (§8.1) and never part of a slice. | audit SYS-003; P1 INT-001/002; orchestration spec §3.1, §6.3 ("gateways with test keys only"); [assumed] (mechanism) |
| B3-7 | **One gateway interface, two providers.** `etqan.gateways` exposes `start_checkout(purpose, …)` and calls back the purpose's owner (billing, finance, wallet, and later B7) through a registered handler when a payment completes. A webhook is the only thing that marks a checkout paid; the browser's return page only shows status. *Amended by ledger D13:* for PayPal (B3c) a verified server-side capture response also completes a checkout. | P1 §9 (webhook secret implies a receiving route); [assumed] (handler registry); ledger D13 |
| B3-8 | **The service fee**: an academy setting (on/off and a percentage, default 5 %) is the default for online invoice payments, and each payment link carries its own "add the service fee" toggle, defaulting to the setting. The fee is added on top of the amount, and is recorded on the checkout and on the resulting payment. It is a business rule, so a setting, not a feature switch. | P1 BR-25, BILL-003 ("always enabled"), BILL-004 (per-link toggle), SYS-003 ("required fees"); spec feature-toggles FT-5 |
| B3-9 | **Webhooks are reached through Caddy at `/api/v1/gateways/webhooks/<provider>/`**, one route per provider, on each academy's own host. They are unauthenticated and CSRF-exempt, accepted only with a valid provider signature, and keep accepting events while `online_payments` is off, so a payment started before the switch went off is still recorded. | CLAUDE.md (all API routes under `/api/v1/`, every academy host routes `/api/*` to Django); spec feature-toggles FT-4; [assumed] |
| B3-10 | Refunds are recorded, not executed: an admin marks a payment or donation refunded; no gateway refund API is called. | billing spec §10 (refunds are B3); audit §1.3 #6 (payment status "refunded"); [assumed] (no refund API) |
| B3-11 | The student wallet is a ledger of entries (credit / debit, reason, source), never a stored balance edited by hand; the balance is their sum per currency. | P1 BILL-007, BR-22; [assumed] (ledger form) |

## 3. Slices

| Slice | Contents | Audit IDs | Requires (other phases) | Feature switches |
|---|---|---|---|---|
| **B3a — Expenses, donations, net profit** | `etqan.finance`: expenses (title, type, amount, currency, date, notes), the posting service other apps call (B4 posts paid payslips, PAY-013), donation records (manual), the admin home's expenses, net-profit and donations cards | BILL-005, BILL-006, DASH-003, PAY-013 (service only) | — | `expenses`, `donations` |
| **B3b — Online payments (core + Stripe)** | `etqan.gateways`: the provider interface, Stripe Checkout, encrypted academy keys, test mode and an offline simulator, checkouts and purposes (`start_checkout`), webhooks, the service fee; families pay an invoice online; billing's payments gain a status, fee and transaction number; refunds marked; a checkouts list with "needs attention" | BILL-003 (fee), SYS-003 (Stripe, required fees), INT-001 | — | `online_payments` |
| **B3c — PayPal** | The PayPal provider (Orders v2; mode, client id, secret, webhook id, currency, locale, notes; a notes field on the Stripe account too): token cache, orders, server-side capture, the verified webhook, simulator parity, expiry, provider refunds and reversals recorded as attention; families pay invoices with PayPal | SYS-003 (PayPal), INT-001 (notes), INT-002 | — (uses B3b) | none new (under `online_payments`) |
| **B3g — Payment links and payment records** (built right after B3c, before B3d) | Standalone payment records (no invoice, customer type, currency on every payment) with their list, CSV and revenue; payment links for registered and unregistered students, with a per-link fee toggle and a donation purpose (online donations), and the public pay page; the checkouts CSV (`payment_receipts`); SUB-006 payment metadata (payment type prepaid/postpaid, subscription system normal/monthly; ledger D10) | BILL-001, BILL-004, BILL-005 (online), SUB-006 | — (uses B3b, B3c) | `payment_links`, `payment_receipts` |
| **B3d — Country prices and local payment methods** | Per-country package prices (catalogue) used when a subscription is created for a student of that country; per-country manual ("local") payment methods with logo and instructions shown on the family's invoice page, behind the "local payment" setting | CATALOG-003, BILL-002, SYS-003 (local payment) | B2's price-and-currency hook in scheduling: an additive change requested from B2 in B3d's spec (§7 there); it lands in B3d's merge pair, and B3d is not queued before it | `country_pricing` |
| **B3h — Exchange rates and the converted estimate** (built right after B3d) | Exchange rates entered by the admin (finance) and the converted net-profit estimate on the home card, labelled as an estimate; the shared `convert_estimate` helper | INT-013 | — | `exchange_rates` |
| **B3e — Student wallet** | `etqan.wallet`: credits (manual, online top-up, compensation for a session, refund), paying an invoice from the wallet, the balance on the student page and the family's pages | BILL-007, BR-22 | — (online top-up uses B3b) | `balances` |
| **B3f — System codes** | `etqan.vouchers`: activation, renewal and discount codes with validity, generated in bulk, redeemed by a family, status unused / used / expired; "activation code" as a way to pay. How a discount code is valued is not observed (audit SUB-005): B3f's spec decides it as `[assumed]`. | SUB-005, SYS-003 (activation code) | B2's subscription model (codes create or renew subscriptions): recorded when B3f's spec is written | `system_codes` |

Each slice is one plan (eight slices: B3a–B3h). A slice's spec may move a minor item to a later B3 slice; it never drops one.

## 4. Interfaces other phases rely on (shared decisions in the ledger)

- **B4 (payroll depth):** `finance.services.post_expense(source, source_id, …)` and
  `finance.services.withdraw_expense(source, source_id)` (B3a §4.3). Posting is idempotent per
  `(source, source_id)`.
- **B7 (add-on sales):** `gateways.services.start_checkout(purpose, reference_id, provider, *, user, params=None)` and
  `register_purpose(name, *, prepare, complete)` (B3b §4.2–4.3; ledger D4 as updated). B7 registers its own
  purposes (recorded course, consultation).
- **B2 (scheduling depth):** B3d and B3f need an additive hook in subscription creation. B3d's spec (§4.2, §7)
  fixes it: `create_subscription` / `renew_subscription` resolve the default price and currency through
  `catalogue.services.package_price(package, country=student.country)` and gain an optional `currency`.
  B3f's need is recorded when its spec is written (orchestration spec §6.2.1).

## 5. Non-goals for the whole phase

- Live gateway keys, real money, and any production configuration (owner, orchestration spec §8.1).
- Executing refunds through a gateway API (B3-10).
- Automatic exchange-rate fetching from an external API (needs an account; escalation §8.1). Rates are
  entered by hand in B3h.
- Accounting beyond TutorHamster's: no ledgers, tax, VAT, or reports other than the monthly cards and lists.
- SaaS billing of academies by Etqan (roadmap §3).
