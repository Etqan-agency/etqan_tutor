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
| B3-1 | B3 is built as five slices, in the order of §3. Expenses come first because B4 (payroll depth) needs them; gateways second because B7 (add-on sales) needs them. | roadmap §2 (B4 needs "B3 expenses", B7 needs "B3 gateways"); orchestration spec §6.3 |
| B3-2 | New apps, each in `TENANT_APPS` under the B3 marker with its own import contract: `etqan.finance` (expenses, donations, net profit), `etqan.gateways` (online providers, checkouts, payment links, webhooks), `etqan.wallet` (student balances), `etqan.vouchers` (TutorHamster's "system codes"; named so it is not confused with permission codes). `etqan.billing` keeps invoices and payments and gains the new payment methods; `etqan.catalogue` gains the country prices. | orchestration spec §4.3 ("new business areas go in new apps") |
| B3-3 | **Every B3 feature is off by default.** TutorHamster's own flags become built in place, written with an explicit `default=False` (`_built(...)` defaults to on): `donations`, `balances`, `country_pricing`, `payment_links`, `payment_receipts`. Features TutorHamster has without a flag go under the B3 marker, also `default=False`: `expenses`, `online_payments`, `system_codes`, `exchange_rates`. Prerequisites: `payment_links` requires `online_payments`. `balances` requires nothing; its online top-up appears only while `online_payments` is on too. The seeded demo academy turns on every built feature (`seed_dev.FEATURES`, Plan 13 §7). | orchestration spec PO-5; audit §2.10 / P1 SYS-002 (flag list); spec feature-toggles §3.3, §7 |
| B3-4 | **Money stays integer minor units plus an ISO 4217 currency, and is never summed across currencies.** Exchange rates (B3c) only ever produce figures labelled as converted estimates, next to the per-currency truth. | spec 2026-09-25-billing P6-6; CLAUDE.md |
| B3-5 | **Revenue** is what TutorHamster calls it: money received from completed payment records (BR-47). Donations are recorded and reported separately and are not revenue. **Net profit** = revenue − expenses, per currency, per academy month (BR-48). Today every billing payment is a received payment; once B3b gives payments a status, revenue counts `completed` ones only. | P1 BR-47, BR-48; audit §3 #9 |
| B3-6 | **Gateways use each academy's own merchant account**, entered by the academy admin (TutorHamster: settings → payment gateways). Secrets are encrypted at rest with Fernet (`cryptography`) under a key from the environment variable `ETQAN_SECRETS_KEY`. In development and tests a missing key is derived from `SECRET_KEY`; in production a missing key makes saving or using gateway secrets fail closed. The secrets are never returned by the API. B3b asks the conductor to add the variable to `infra/` and CI. Development and CI use test keys only; live keys are an owner escalation (§8.1) and never part of a slice. | audit SYS-003; P1 INT-001/002; orchestration spec §3.1, §6.3 ("gateways with test keys only"); [assumed] (mechanism) |
| B3-7 | **One gateway interface, two providers.** `etqan.gateways` exposes `start_checkout(purpose, …)` and calls back the purpose's owner (billing, finance, wallet, and later B7) through a registered handler when a payment completes. A webhook is the only thing that marks a checkout paid; the browser's return page only shows status. | P1 §9 (webhook secret implies a receiving route); [assumed] (handler registry) |
| B3-8 | **The service fee**: an academy setting (on/off and a percentage, default 5 %) is the default for online invoice payments, and each payment link carries its own "add the service fee" toggle, defaulting to the setting. The fee is added on top of the amount, and is recorded on the checkout and on the resulting payment. It is a business rule, so a setting, not a feature switch. | P1 BR-25, BILL-003 ("always enabled"), BILL-004 (per-link toggle), SYS-003 ("required fees"); spec feature-toggles FT-5 |
| B3-9 | **Webhooks are reached through Caddy at `/api/v1/gateways/webhooks/<provider>/`**, one route per provider, on each academy's own host. They are unauthenticated and CSRF-exempt, accepted only with a valid provider signature, and keep accepting events while `online_payments` is off, so a payment started before the switch went off is still recorded. | CLAUDE.md (all API routes under `/api/v1/`, every academy host routes `/api/*` to Django); spec feature-toggles FT-4; [assumed] |
| B3-10 | Refunds are recorded, not executed: an admin marks a payment or donation refunded; no gateway refund API is called. | billing spec §10 (refunds are B3); audit §1.3 #6 (payment status "refunded"); [assumed] (no refund API) |
| B3-11 | The student wallet is a ledger of entries (credit / debit, reason, source), never a stored balance edited by hand; the balance is their sum per currency. | P1 BILL-007, BR-22; [assumed] (ledger form) |

## 3. Slices

| Slice | Contents | Audit IDs | Requires (other phases) | Feature switches |
|---|---|---|---|---|
| **B3a — Expenses, donations, net profit** | `etqan.finance`: expenses (title, type, amount, currency, date, notes), the posting service other apps call (B4 posts paid payslips, PAY-013), donation records (manual), the admin home's expenses, net-profit and donations cards | BILL-005, BILL-006, DASH-003, PAY-013 (service only) | — | `expenses`, `donations` |
| **B3b — Online payments** | `etqan.gateways`: academy gateway settings (Stripe, PayPal; encrypted secrets; test mode), checkouts, webhooks, the service fee; families pay an invoice online; payment links for registered and unregistered students; payments gain a status; standalone payment records (a payment with no invoice, for an unregistered payer, as TutorHamster's customer type allows) and the payment records list (`payment_receipts` gates that list); refunds marked; online donations through a donation-purpose link | BILL-001, BILL-003 (fee), BILL-004, SYS-003 (PayPal, Stripe, required fees), INT-001/002 | — | `online_payments`, `payment_links`, `payment_receipts` |
| **B3c — Countries and currencies** | Per-country package prices (catalogue) used when a subscription is created for a student of that country; per-country manual ("local") payment methods with logo and instructions shown on the family's invoice page; exchange rates entered by the admin and the converted net-profit estimate | CATALOG-003, BILL-002, SYS-003 (local payment), INT-013 | B2's subscription-creation slice (a price-and-currency hook in scheduling): requested and recorded when B3c's spec is written | `country_pricing`, `exchange_rates` |
| **B3d — Student wallet** | `etqan.wallet`: credits (manual, online top-up, compensation for a session, refund), paying an invoice from the wallet, the balance on the student page and the family's pages | BILL-007, BR-22 | — (online top-up uses B3b) | `balances` |
| **B3e — System codes** | `etqan.vouchers`: activation, renewal and discount codes with validity, generated in bulk, redeemed by a family, status unused / used / expired; "activation code" as a way to pay. How a discount code is valued is not observed (audit SUB-005): B3e's spec decides it as `[assumed]`. | SUB-005, SYS-003 (activation code) | B2's subscription model (codes create or renew subscriptions): recorded when B3e's spec is written | `system_codes` |

Each slice is one plan. A slice's spec may move a minor item to a later B3 slice; it never drops one.

## 4. Interfaces other phases rely on (shared decisions in the ledger)

- **B4 (payroll depth):** `finance.services.post_expense(source, source_id, …)` and
  `finance.services.withdraw_expense(source, source_id)` (B3a §4.3). Posting is idempotent per
  `(source, source_id)`.
- **B7 (add-on sales):** `gateways.services.start_checkout(purpose, …)` with a per-purpose completion handler
  (B3-7). B7 registers its own purposes (recorded course, consultation). B3b's spec fixes the signature.
- **B2 (scheduling depth):** B3c and B3e need an additive hook in subscription creation (a price and currency
  given by the caller). Requested from B2 when those specs are written (orchestration spec §6.2.1).

## 5. Non-goals for the whole phase

- Live gateway keys, real money, and any production configuration (owner, orchestration spec §8.1).
- Executing refunds through a gateway API (B3-10).
- Automatic exchange-rate fetching from an external API (needs an account; escalation §8.1). Rates are
  entered by hand in B3c.
- Accounting beyond TutorHamster's: no ledgers, tax, VAT, or reports other than the monthly cards and lists.
- SaaS billing of academies by Etqan (roadmap §3).
