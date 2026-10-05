# Slice B3d — Country prices and local payment methods — Design

**Date:** 2026-10-05
**Status:** Draft for the B3 orchestrator's review (orchestration spec PO-3), revised after an independent
spec review (2 critical, 7 important, 13 minor findings folded in). The review moved exchange rates and the
converted net-profit estimate to the new slice B3h (`2026-10-05-b3h-exchange-rates-design.md`, built right
after this one).
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3d. **Requires:** B2's subscription-creation
hook (phase §3, §4). This spec designs that hook as one additive change to `scheduling`. The change is
requested from B2 in the ledger and written out in full in §7. B3c and B3g merge first (phase B3-1).
**Builds on:**
- Plan 4 catalogue and scheduling: the package snapshot (P4-5) and the renewal price (P4-10);
- Plan 6 billing: the invoice page, `invoices_queryset` and `pay_options`;
- B3b / B3c gateways: the payment settings page;
- B9a uploads (ledger D12);
- Plan 13 feature switches; Plan 12a roles.

**Evidence:**
- audit CATALOG-003 and §1.3 #13: per-country prices are a repeater of country · price · currency (seen:
  Egypt → EGP, Saudi Arabia → SAR);
- audit BILL-002: per-country methods, each country with an enable toggle and a repeater of name · logo ·
  rich-text instructions;
- audit SYS-003: the "local payment" switch;
- P1 CATALOG-003, BILL-002 and INT-003 (manual methods: bank transfer, Zelle, InstaPay, Telda, PayMob);
- P1 BR-35 (package prices overridden per country), BR-36 (methods offered per country, a whole country can
  be switched off) and BR-39 (method logos 200×200);
- P1 SYS-002: the TutorHamster flag "نظام الاسعار المخصص حسب الدولة" (per-country pricing).

## 1. Goal

An academy that sells in several countries sets the price and currency a student of each country pays for
each package, and a new subscription for that student takes it. For each country the academy also lists
the local ways to pay (bank transfer, InstaPay, …), each with a logo and instructions. A family sees them on
its unpaid invoice.

## 2. Decisions

| Id | Decision | Source |
|---|---|---|
| D-1 | **Country prices live in `etqan.catalogue`**, which B3 owns for pricing. Each `PackageCountryPrice` row holds a package, a country, a price and any ISO currency, unique per package and country. The package's own price stays the default for every other country. | phase B3-2; audit CATALOG-003; ledger ownership |
| D-2 | **The student's country is `identity.StudentProfile.country`**, which already exists (ISO 3166-1 alpha-2, may be blank). No new field. A blank country always gets the package's price. | identity model (`country`, `COUNTRY_CODE`); audit PEOPLE-001 |
| D-3 | **One resolver:** `catalogue.services.package_price(package, *, country) -> Price(price_minor, currency, country, source)`. <br>• While `country_pricing` is on and a row exists for the country, it answers that row with `source="country"`. <br>• Otherwise it answers the package's price with `source="package"`. <br>• `Price.country` is always the country asked for, blank when none, whichever source answered. <br>With the switch off, every result is today's. | phase B3-4; [assumed] (resolver form) |
| D-4 | **The B2 hook is a call plus one optional field.** <br>• `create_subscription` and `renew_subscription` take their default price **and currency** from `package_price(package, country=student.country)`. <br>• Both gain an optional `currency`, and so do the subscription create and renew bodies. <br>• An explicit `price_minor` is read in the resolved currency. A given `currency` that differs from the resolved one is a 400 on `price_minor` with code `catalogue.price_currency_changed`. <br>• P4-10 ("keep the amount paid unless the currency changed") compares with the resolved currency. <br>• Every create path goes through these two functions: the API, renewals, B2e's trial conversion and B2f's bundle rows. Every change is additive. | phase §4; orchestration spec §6.2.5; scheduling code; review C1 |
| D-5 | **Group bundles (B2f) and mixed currencies.** <br>• A group row with an explicit `price_minor` is refused (400 on `rows[0].price_minor`) unless every member resolves to the same currency. Without a price, each member takes its own resolved default. <br>• Adding a student to a group copies the template's price only when the two currencies match (P4-10); otherwise the student takes the resolved default. <br>• The group form shows no price prefill while the members' currencies differ. | spec b2f §4.2–4.3; review C2 |
| D-6 | **B2 makes the hook.** <br>• It is a ledger `request` (§7). B3d makes it itself under a `claim` only if B2 explicitly delegates it. <br>• The backend and dashboard halves land in the same merge pair. <br>• The hook needs B3d's resolver and `usePackagePrice`, so its commits are added to B3d's branches. <br>• B3d's hook-dependent work (the E2E) is blocked until those commits are in, and B3d is not queued before then. | orchestration spec §6.2.1; review I1 |
| D-7 | **The snapshot stays** (P4-5). A later change to the student's country, to a country row or to the switch never reaches an existing subscription or its invoices. | spec Plan 4 P4-5 |
| D-8 | **The office form shows the resolved price.** `GET catalogue/packages/<id>/price/?student=<user id>` answers `{price_minor, currency, source}`. The subscription form and the renew dialog prefill the price and label the currency from it, and always send the currency they converted with. | review C1, I3; [assumed] |
| D-9 | **Country prices are edited as one list** per package, like TutorHamster's repeater: `PUT` replaces the whole list. <br>• Duplicating a package copies the rows in the same transaction; deleting a package deletes them. <br>• The routes are office-only views (`HasCode`). Teachers can read packages but never these routes. | audit CATALOG-003; catalogue code (teacher read scope, `duplicate_package`); review I3 |
| D-10 | **Local payment methods live in `etqan.billing`**, which B3 owns: `LocalPaymentMethod` and `LocalPaymentCountry` (the per-country enabled toggle). A country that has methods but no country row is enabled. | phase B3-2; audit BILL-002; P1 BR-36 |
| D-11 | **SYS-003's "local payment" switch** is a billing setting, `local_payment_enabled` (default false), shown on the payment settings page and on the methods page. <br>• While it is off, no invoice shows methods and the nav item is hidden. The admin page stays reachable from the `/billing` index and from the settings card. <br>• It is a setting, not a feature switch: phase §3 gives B3d only `country_pricing`. | audit SYS-003; phase B3-8 (a switch inside payment settings is a setting); review I2 |
| D-12 | **A method may name a currency.** <br>• Blank (the default): it shows for an invoice in any currency. <br>• Set: it shows only for invoices in that currency. | review I7; [assumed] |
| D-13 | **Instructions are plain text**, not TutorHamster's rich text. <br>• On save they are trimmed, `\r\n` is normalised to `\n`, and the result is 1–4000 characters. <br>• They are rendered escaped, with line breaks kept, and links are not made clickable. HTML an academy writes never renders on the academy origin. | ledger D2; P1 BILL-002; [assumed] |
| D-14 | **The logo is optional.** <br>• It is checked by `platform.uploads.check_upload`: extensions `.png`, `.jpg`, `.jpeg` and `.webp` only, not `uploads.IMAGE`, so GIF is refused; at most 1 MB. <br>• It is stored in public media through a module-level `LOGO_PATH = tenant_upload_path("payment-methods")`. <br>• It is shown at 200×200, which is not enforced. <br>• A replaced, cleared or deleted logo file is removed in `transaction.on_commit`. | ledger D12, D2; P1 BR-39; [assumed] (size cap) |
| D-15 | **What the family sees.** The methods of the invoice student's country appear on the invoice page while the invoice has a balance and is not void, and only while all of these hold: <br>• `local_payment_enabled` is on; <br>• the country is enabled; <br>• the method is active and its currency is blank or equal to the invoice's. <br>They are ordered by `position`. Office viewers see the same block. Paying stays out of band: the office records the payment as a manual method, as today. | P1 INT-003 ("instructions rendered to the payer"); billing code (`_nothing_due`) |
| D-16 | **Country codes are only format-checked** (`^[A-Z]{2}$` via `clean_country`); there is no ISO list on the server. "Unknown" means malformed. A method needs a non-blank country. | identity `clean_country`; review I5 |
| D-17 | **Online payment follows the invoice currency unchanged.** A country price in a currency that no enabled provider takes leaves `can_pay_online` empty for that invoice; its local methods are the way to pay. Nothing warns when the price is entered (PayPal takes one currency, B3c C-6). | spec b3c C-6; billing `pay_options` |
| D-18 | **Feature:** `country_pricing` becomes built in place, `default=False` (TutorHamster's flag). Local methods sit under `invoices` plus D-11's setting. | phase B3-3; audit SYS-002 |
| D-19 | **Access:** <br>• a new resource `payment_method` (`view_any`, `create`, `update`, `delete`); <br>• country prices use `package.view_any` / `package.update`; <br>• the price route with `?student` also needs `student.view_any`. <br>No B3d route moves money, so none adds `NotImpersonating` (ledger D19). | spec roles-permissions; ledger D19; review I3 |
| D-20 | **Error code:** `etqan.platform.exceptions.ValidationError` gains an optional `code` (default `validation_error`), an additive change of the kind B2f made with `member_id` (ledger D15), so D-4's 400 carries `catalogue.price_currency_changed`. | ledger D15; [assumed] |
| D-21 | Only en and ar strings. | ledger D11, D22 |

## 3. Data

### 3.1 `etqan.catalogue` (pricing, B3)

**`PackageCountryPrice`:**
- `package` → Package, `CASCADE`, related name `country_prices`;
- `country`: 2 letters (`COUNTRY_CODE`);
- `price_minor` ≥ 0;
- `currency`: `^[A-Z]{3}$`;
- `updated_at`.

Rows are unique on `(package, country)` and ordered by country.

### 3.2 `etqan.billing`

- **`BillingSettings`** (pk 1): `local_payment_enabled`, default false.
- **`LocalPaymentCountry`:** `country` (2 letters, unique), `enabled` (default true), `updated_at`.
- **`LocalPaymentMethod`:**
  - `country`: 2 letters, indexed;
  - `name`: 1–120 characters;
  - `currency`: blank, or `^[A-Z]{3}$`;
  - `is_active`: default true;
  - `logo`: ImageField, nullable, public storage, `LOGO_PATH`;
  - `instructions`: 1–4000 characters;
  - `position`: small integer, default 0;
  - `created_at`, `updated_at`.

  Ordering is `(country, position, id)`.

The migrations only create tables and run in each academy's schema through `migrate_schemas`.

## 4. Behaviour

### 4.1 Country prices and the resolver

Each route below is its own `APIView` with `permission_classes=[HasCode]`, never `IsTeacher & ReadOnly`.

- **`GET catalogue/packages/<id>/country-prices/`** (`package.view_any`, `country_pricing`) answers
  `[{country, price_minor, currency}]`, ordered by country.
- **`PUT`** on the same route (`package.update`) takes the whole list `[{country, price_minor, currency}]`,
  at most 250 rows, and replaces it in one transaction. Each row is checked:
  - the country is non-blank and passes `clean_country`;
  - `price_minor` ≥ 0;
  - the currency passes `clean_currency`;
  - a repeated country is a 400 on that row.

  Errors are keyed `rows[i].<field>`. The route answers the new list.
- **`catalogue.services`** gains:
  - `country_prices(package)`;
  - `set_country_prices(package, rows)`;
  - `package_price(package, *, country)` (D-3);
  - `copy_country_prices(source, copy)`. `duplicate_package` becomes `@transaction.atomic` and calls it.
- **`GET catalogue/packages/<id>/price/`** (`package.view_any`, no feature gate) answers
  `{price_minor, currency, source}`:
  - without `student`, the package's own price;
  - with `?student=<user id>`, it also needs `student.view_any`, and resolves for that student's country;
  - a student that `identity.services.get_student_profile` does not find is a 400 on `student`.

### 4.2 The subscription hook (D-4, D-5; made per §7)

In `scheduling/services/subscriptions.py`:
1. **`create_subscription(…, currency=None)`:**
   - after `_copy_package`, it resolves `price = catalogue_services.package_price(package, country=student.country)`;
   - a given `currency` other than `price.currency` raises `ValidationError(field="price_minor", code="catalogue.price_currency_changed")`;
   - it sets `subscription.currency = price.currency`;
   - it sets `subscription.price_minor = price.price_minor if price_minor is None else price_minor`.
2. **`renew_subscription(…, currency=None)`:**
   - it resolves the price for the old subscription's student and the new package;
   - it checks `currency` as in step 1;
   - P4-10 becomes `old.price_minor if price.currency == old.currency else price.price_minor`.
3. **Group bundles** follow D-5.

The invoice follows without change: `billing.invoice_subscription` copies the subscription's price and
currency, and `pay_options` already filters providers by currency.

### 4.3 Local payment methods

- **`GET billing/settings/`** (`payment_method.view_any`, `invoices`) answers `{local_payment_enabled}`.
  **`PATCH`** (`payment_method.update`) changes it.
- **`GET billing/local-methods/`** (`payment_method.view_any`, `invoices`) answers
  `{countries: [{country, enabled}], methods: [row]}`, with the filters `country` and `is_active`. A row is
  `{id, country, name, currency, is_active, logo_url, instructions, position, updated_at}`.
- **`POST billing/local-methods/`** (`payment_method.create`, multipart) takes `country` (required,
  non-blank), `name`, `instructions`, `currency?`, `is_active?`, `position?` and `logo?`. It answers 201 with
  the row.
- **`PATCH billing/local-methods/<id>/`** (`payment_method.update`, multipart) takes any subset of those
  fields; `logo=""` clears the logo. **`DELETE`** (`payment_method.delete`) removes the row. Both handle the
  old file as D-14 says.
- **`PUT billing/local-countries/<CC>/`** (`payment_method.update`) takes `{enabled}` and creates or updates
  the country row. A malformed code is a 404.
- **`billing.services.local_methods_for(invoice) -> list`** returns D-15's methods. It answers `[]` when:
  - the setting is off;
  - the invoice is void or has nothing due;
  - the student has no country;
  - the country is disabled;
  - no method matches.

  The student is already joined by `invoices_queryset` (`select_related("student__user")`).
- **The invoice payload:** `payloads.invoice_detail` gains a `local_methods` argument, as it has
  `can_pay_online`, and outputs `local_methods: [{id, name, logo_url, instructions}]` for every viewer who
  may read the invoice. Both callers pass it: `detail()`, which answers every write route, and
  `InvoiceDetailView.get`. The list and print payloads are unchanged.

## 5. API summary (`/api/v1/`)

| Route | Methods | Feature | Codes |
|---|---|---|---|
| `catalogue/packages/<id>/country-prices/` | GET, PUT | `country_pricing` | `package.view_any`, `package.update` |
| `catalogue/packages/<id>/price/` | GET | — | `package.view_any` (+ `student.view_any` with `?student`) |
| `billing/settings/` | GET, PATCH | `invoices` | `payment_method.view_any`, `payment_method.update` |
| `billing/local-methods/` | GET, POST | `invoices` | `payment_method.view_any`, `payment_method.create` |
| `billing/local-methods/<id>/` | PATCH, DELETE | `invoices` | `payment_method.update`, `payment_method.delete` |
| `billing/local-countries/<CC>/` | PUT | `invoices` | `payment_method.update` |

**Payload changes:** the invoice detail gains `local_methods`.

**Changed on purpose (through §7):**
- the subscription create and renew bodies gain an optional `currency`;
- a new subscription's default price and currency follow D-4, unchanged while `country_pricing` is off;
- the route table, the registry and the feature counts.

## 6. Dashboard

- **Package page** (`_authed/catalogue.packages.$packageId.tsx`): a "Prices by country" card
  (`CountryPricesCard` in `features/catalogue`), shown while `country_pricing` is on and only once the
  package exists.
  - Each row has a country (from `lib/countries.ts`), a currency and a price.
  - Each row converts with `toMinor` / `toMajor` in its own currency.
  - Rows can be added and removed, and one Save sends the PUT.
- **`usePackagePrice(packageId, studentId)`** is exported from `features/catalogue` for §7. It reports
  `isPending` until the price has resolved.
- **Billing → Local payment methods** (`_authed/billing.local-methods.tsx`, `payment_method.view_any`,
  `invoices`):
  - the `local_payment_enabled` switch at the top;
  - methods grouped by country, each group with its enabled toggle;
  - per method: the logo, name, currency (or "any"), active toggle and position;
  - an add / edit dialog with a logo picker (PNG, JPEG or WEBP) and a plain-text instructions box;
  - delete.

  The nav item shows only while the setting is on. The `/billing` index always lists the page, in the order
  invoices, payments, links, expenses, donations, local methods.
- **Settings → Payment gateways:** a "Local payment" card with the same switch and a link to the methods
  page.
- **Invoice page** (`InvoicePage`, office and family): a "Pay locally" section (`LocalPaymentMethods`) next
  to "Pay online", shown when `local_methods` is not empty. Each method shows its logo, name and
  instructions, escaped and with `whitespace-pre-line`.
- **Wiring:**
  - keys in `locales/{en,ar}/catalogue.json` and `billing.json`;
  - `country_pricing` becomes a built feature;
  - `FEATURE_SCREENS` and `FEATURE_WORDS` rows;
  - nav under the B3 marker;
  - semantic tokens, RTL and phone width.

## 7. Dependencies and environment

- **No new package, setting or environment variable.**
- **Wiring under the B3 markers:**
  - `country_pricing` is flipped in place in `platform/features.py`;
  - `payment_method` is added to `access/registry.py`;
  - the import contracts are unchanged: catalogue already imports `identity.services`, and scheduling
    already imports `catalogue.services`.
- **Platform:** D-20's optional `code` on `ValidationError`.
- **Request to B2** (`ledger.py request B3 scheduling B2 "<text>"`). The text, in full:

  > B3d country-pricing hook (spec 2026-10-05-b3d §4.2, §7, D-4..D-6). Additive only, no model or migration.
  > BACKEND etqan/scheduling/services/subscriptions.py: (1) create_subscription gains currency: str | None = None;
  > after _copy_package it resolves price = catalogue_services.package_price(package, country=student.country),
  > raises ValidationError(field="price_minor", code="catalogue.price_currency_changed") when currency is given
  > and differs from price.currency, sets subscription.currency = price.currency and subscription.price_minor =
  > price.price_minor if price_minor is None else price_minor. (2) renew_subscription gains currency=None, resolves
  > the price for the old subscription's student and the new package, applies the same check, and P4-10 becomes
  > price_minor = old.price_minor if price.currency == old.currency else price.price_minor. (3) scheduling API:
  > SubscriptionCreateInput and RenewInput gain optional currency (3 letters, upper-cased); bundle rows inherit it.
  > (4) B2f group bundles: a group row with explicit price_minor is refused 400 on rows[0].price_minor unless every
  > active member resolves to the same currency (then (1)'s check applies); without price_minor each member takes
  > its own resolved default; add_to_group_bundle copies the template's price_minor only when the new student's
  > resolved currency equals the template's currency, otherwise the resolved default. If B2f is not merged when
  > this lands, (4) becomes part of B2f's own build.
  > DASHBOARD: features/scheduling/TermFields.tsx gains optional studentId; with studentId and a package, the
  > price prefill and currency label come from usePackagePrice(packageId, studentId) (@/features/catalogue);
  > when the resolved currency changes the price field resets to the resolved price; submit is disabled while
  > usePackagePrice is pending. SubscriptionForm.tsx passes watch("student"), converts with the resolved currency
  > and sends currency. RenewDialog.tsx passes the subscription's student, prefills by P4-10 against the resolved
  > currency (the current price if the currency is unchanged, else the resolved price) and sends currency. The
  > B2e conversion form and B2f's family/individual bundle forms pass studentId the same way; the group form shows
  > no price prefill and sends no price while the members' resolved currencies differ.
  > TESTS: a priced-country student gets the country price and currency; an explicit price in the resolved
  > currency is accepted; a different currency is 400 catalogue.price_currency_changed; a price without currency
  > takes the resolved currency; renewal P4-10 with the same and a changed resolved currency; group explicit price
  > with mixed currencies 400 and without price per-member defaults; group add with a currency mismatch takes the
  > resolved default; every existing scheduling test passes unchanged with country_pricing off; dashboard prefill,
  > reset on currency change, submit disabled while pending, RenewDialog prefill.
  > EXECUTION: B2 makes it; B3d does it under a claim only if B2 explicitly delegates. It needs B3d's
  > package_price and usePackagePrice, so its commits go on B3d's branches and backend + dashboard land in
  > B3d's merge pair; rebase on whichever of B2e/B2f merges first. B3d is not queued until it is in.

- **Blocked tasks:** B3d's plan builds everything else first. The E2E (§9) and B3d's queueing wait for the
  hook commits.

## 8. Seeds

The seeds go in a new module, `etqan/tenants/seeds/countries.py` (`seed_countries(subdomain)`), called under
the B3 marker of `seed_dev`. They use catalogue, identity and billing services only. Each step runs only when
its table is empty, or for the student, when the student is absent.
- **A new demo student**, "Karim Saleh" (`karim@demo.test`), active, with country `SA`. No existing journey
  uses this student.
- **A country price** on the package "Monthly, 2 a week" (EGP 1500.00): `SA` → 450.00 SAR.
- **Local methods for `SA`:**
  - "Bank transfer", with no currency;
  - "STC Pay", in SAR.

  Both have plain-text instructions and no logo.
- **The country and the setting:** the `SA` country row is enabled, and `local_payment_enabled` is set to
  true.

## 9. Testing

- **Backend:**
  - **Country prices:**
    - PUT validation: blank or malformed country, a repeated country, the currency, a negative price;
    - replace semantics;
    - duplicating copies the rows in one transaction; deleting cascades;
    - feature off is 404;
    - a teacher is refused on GET and PUT.
  - **Resolver and price route:**
    - switch off and on; row present and absent; blank country;
    - the source;
    - `?student` without `student.view_any` is 403; an unknown student is 400;
    - a teacher is refused.
  - **Hook:** the request's tests (§7). The `ValidationError` code reaches the error body.
  - **Local methods:**
    - CRUD and multipart;
    - logo checks (GIF, SVG, over 1 MB, bad content) and file removal on commit;
    - instructions trimmed and normalised;
    - the country toggle, and a malformed country being 404;
    - a method with a blank country is 400.
  - **`local_methods_for`:** each empty case (setting off, void, paid, no country, disabled, inactive,
    currency mismatch) and the blank-currency match.
  - **The invoice payload:** for a family and for the office, and from `detail()` after a payment.
  - **Matrix and isolation:**
    - a family is refused on the admin routes;
    - the role × route rows;
    - cross-academy isolation of every new table.
- **Dashboard:**
  - the country-prices card (per-row currency conversion);
  - the local-methods page, dialog and switch;
  - the settings card;
  - the invoice block (escaped text, absent when empty);
  - the nav item hidden while the setting is off;
  - both languages.
- **E2E** (`dashboard/e2e/b3-countries.spec.ts`), once the hook is in:
  1. Switch on `invoices` and `country_pricing` for demo.
  2. The admin creates a subscription for Karim Saleh on "Monthly, 2 a week". The form shows 450.00 SAR, and
     the invoice is in SAR.
  3. The admin adds a SAR-only method for `SA`. Karim's invoice page lists it, with "Bank transfer".
  4. With `local_payment_enabled` switched off, the invoice page shows no "Pay locally" section.

## 10. Out of scope

- **Moved to B3h:** exchange rates and the converted net-profit estimate (`exchange_rates`, INT-013).
- **Per-visitor prices:** on the public site, or chosen by IP country (that needs the IP API, an
  integration key).
- **Not observed in the audits, so not built and given no target slice:**
  - a fallback method list for "all other countries";
  - payment proof uploaded by the family;
  - local methods on the printed invoice.
- **Rich-text instructions:** D-13.
