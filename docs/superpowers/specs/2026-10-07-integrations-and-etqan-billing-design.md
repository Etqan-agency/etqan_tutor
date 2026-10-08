# Integrations & Etqan billing — Design

**Date:** 2026-10-07
**Status:** Approved in brainstorming (sections 1–4), pending written-spec review.
**Origin:** B5's WhatsApp provider question (escalation E3) widened by the owner into how every outside
service is owned and paid for across academies (tenants).
**Builds on:** the tenancy rules (CLAUDE.md), Plan 13's feature switches (`etqan.platform.features`), B3b's
online payments (`etqan.gateways`, `GatewayAccount`, `etqan.platform.secrets`), the notification channels
(Plan 8, B5), the parallel-phase ledger (decisions D40, D41).

## 1. Goal

Every outside service an academy needs — WhatsApp, email, online payments, video meetings, AI — works on
day one through an **Etqan default account**, and an academy may switch any service to **its own account**.
Use of Etqan's defaults is **metered** and **invoiced to the academy monthly**; academies pay manually and
Etqan marks invoices paid.

## 2. Decisions

| # | Decision |
|---|---|
| IN-1 | **Hybrid ownership (owner).** Per service: Etqan default, overridable by the academy's own account. |
| IN-2 | **Scope (owner):** WhatsApp, email, online payments, video meetings (Zoom), AI. SMS is out. |
| IN-3 | **WhatsApp default = one shared Etqan number (owner)** on the official WhatsApp Cloud API (D40). Not Meta Tech Provider (a later option). |
| IN-4 | **Payments default = Stripe Connect (owner):** Etqan is the Stripe platform; each academy onboards an Express account; families pay into the academy's own Stripe balance; Etqan takes a per-academy platform fee via `application_fee`. B3's own-keys model stays as the academy's own account. |
| IN-5 | **Metered usage, invoiced monthly (owner)**, only for use on Etqan defaults; use on an academy's own accounts is never charged. |
| IN-6 | **Manual payment of Etqan invoices (owner):** bank transfer or any method Etqan accepts; Etqan marks paid. No card-on-file. |
| IN-7 | **One shared layer (approach A).** `etqan.integrations` resolves the account for every service; `etqan.etqan_billing` meters and invoices. Services never store keys of their own. |
| IN-8 | Out of scope: two-way chat on the shared WhatsApp number, automatic charging, tax/VAT on Etqan invoices, SMS, Meta Tech Provider onboarding. |

## 3. Accounts and resolution — `etqan.integrations`

### 3.1 Models
- **`PlatformAccount`** (SHARED_APPS, public schema): one row per `service` ∈ {`whatsapp`, `email`,
  `payments`, `video`, `ai`}; `enabled`, `config` (non-secret JSON: phone number id, from address, model, …),
  `secret_enc` (Fernet via `etqan.platform.secrets`), `last_test_at`, `last_test_ok`, `last_test_error`.
  Edited only by Etqan staff in the platform admin.
- **`AcademyAccount`** (TENANT_APPS, each academy's schema): one row per `service`; `enabled`, `config`,
  `secret_enc`, the same test fields, `updated_by`, `updated_at`. For `payments` the row stores only the
  Stripe Connect `acct_…` id and onboarding status; the academy's own Stripe/PayPal keys stay in B3's
  `GatewayAccount`.
- Secrets are never returned by any API: screens show "connected · ••••last4 · tested OK on <date>".

### 3.2 The resolver
`integrations.services.resolve(service) -> Resolved | None`, inside the current academy:
1. the academy's own account if connected and enabled → `Resolved(source="academy", account=…)`;
2. else Etqan's default if Etqan's `PlatformAccount` is enabled **and** the academy's feature switch for the
   service is on (Plan 13: `whatsapp`, `video`, `ai_assistant`/`ai_reports`; email and payments follow
   their existing switches) → `Resolved(source="etqan", account=…)`;
3. else `None` — the feature shows "not set up".
Callers meter only when `source == "etqan"`. The resolver adds no query beyond reading two small rows,
cached per request.

### 3.3 Testing a connection
`integrations.services.test(service, scope)` runs a provider-specific probe (WhatsApp: send a template to
the tester's number; email: send to the tester; payments: retrieve the Connect account; video: request a
Zoom token; AI: a one-token Claude call) and records the result on the row.

## 4. The services

| Service | Etqan default | Academy's own | Metered unit |
|---|---|---|---|
| WhatsApp (B5c) | One shared Etqan number; approved templates carry the academy's name; replies get an auto-reply pointing to the academy's contact | Its own Phone number id, access token, WABA id and own templates mapped by name | conversation (Meta's billing unit), on the delivery webhook |
| Email | Today's sending; from `noreply@…` with the academy as display name, reply-to the academy's email | SMTP (host, port, user, password) or provider API key (Postmark/SES/SendGrid) and its own from-address | email accepted by the provider |
| Payments | Stripe Connect Express via hosted onboarding; Etqan fee (percent + fixed, per academy) through `application_fee` | B3 as built (own Stripe/PayPal keys); no Etqan fee | none on the usage invoice; collected fees shown as a read-only line |
| Video | Etqan's Zoom Server-to-Server app creates a meeting per session (Etqan hosts); Jitsi link stays the free fallback when nothing resolves | Its own Zoom S2S credentials; its own Zoom users host | meeting minutes, on Zoom's meeting-ended event |
| AI (B10) | Etqan's Claude API key, default model `claude-sonnet-5` | Its own Claude API key | input and output tokens |

WhatsApp messages go only to families whose profile has a WhatsApp number and who have not opted out.

## 5. Metering and invoices — `etqan.etqan_billing` (SHARED_APPS)

- **`UsageEvent`**: academy, service, unit, quantity, `occurred_at` (UTC), `source_ref` (unique per
  academy+service — a repeated webhook never double-counts). Recorded only on provider confirmation and
  only for `source == "etqan"`.
- **`Price`**: service, unit, `amount` (integer minor units), `currency` (one Etqan currency), `effective_from`.
  **`AcademyPricing`**: per-academy override amount and/or monthly free allowance per service+unit; the
  Stripe Connect platform fee (percent, fixed) per academy.
- **`EtqanInvoice`** + **`EtqanInvoiceLine`**: number `ETQ-YYYY-MM-NNNN`; one per academy per calendar month
  (UTC) with usage; lines = quantity × price − allowance per service+unit, a read-only "Stripe Connect platform
  fees collected" line, manual lines added by Etqan; statuses `draft → issued → paid | void`.
- **Monthly job** (1st, 03:00 UTC, loops academies): builds drafts for the previous month; drafts are
  editable for 24 h, then issued automatically (or earlier by Etqan); issuing emails the academy's admins
  with the PDF.
- **Overdue**: 15 days after issue → banner on the academy's dashboard; from 30 days Etqan may switch
  "suspend Etqan defaults" for that academy (manual, never automatic) — the resolver then skips step 2;
  the academy's own accounts keep working.
- Issued invoices never change; corrections are credit lines on the next invoice.

## 6. Screens

- **Academy → Settings → Integrations** (admins; staff need new codes `integration.view`, `integration.update`):
  one card per service — "Using Etqan's default" / "Using your own account", Connect / Edit / Test /
  Disconnect, last test, and the default's price; payments shows "Connect with Stripe" beside B3's own keys.
- **Academy → Settings → Etqan billing** (admins): usage this month per service (daily), past invoices
  (PDF, status, due date); the overdue banner on every page.
- **Platform admin** (bare base domain, Etqan staff): Etqan default accounts (keys, Test, enabled); prices,
  per-academy overrides, allowances and Connect fee; invoices (review drafts, add manual line, issue, mark paid
  with date/method/reference, void); usage per academy; the per-academy suspend switch.

## 7. Delivery and effect on the parallel phases

- Built as its own plan in two slices, outside the phase streams: **(1) integrations core** — models, resolver,
  test, Settings → Integrations, email moved onto the resolver; **(2) metering and Etqan invoices** — usage,
  prices, the monthly job, billing screens, platform admin.
- Ledger shared decision: every phase uses `integrations.resolve(service)` and stores no keys of its own;
  usage on Etqan defaults is recorded through `etqan_billing.record_usage(...)`.
- **B5c** (WhatsApp) waits for slice 1 (D41), then builds the Cloud API provider on the resolver.
- **B3** gets a follow-up slice: Stripe Connect as the payments default.
- **Video** (Zoom) is built with the session-meeting work (B2) and **AI** with B10, both on the resolver.

## 8. Testing
- Resolver: own vs default vs none, feature switch off, suspended academy, per-request caching.
- Secrets never serialised; Test probes with faked providers; webhook-driven metering idempotent on
  `source_ref`; no usage recorded for `source == "academy"`.
- Invoices: allowance and override arithmetic in minor units, price `effective_from`, zero-usage month makes
  no invoice, issued invoices immutable, credit line on correction, monthly job loops every academy.
- Dashboard/platform screens: role gates, never showing a secret, overdue banner.
