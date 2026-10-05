# Slice B3h — Exchange rates and the converted estimate — Design

**Date:** 2026-10-05
**Status:** Draft for the B3 orchestrator's review (orchestration spec PO-3). It was split from B3d by B3d's
spec review and is built before B3d (phase B3-1, reordered 2026-10-05); it requires no B3d work.
**Phase:** B3 (`2026-10-03-b3-money-depth-design.md`), slice B3h. **Requires:** no other phase's slice and
no B3d work (it is built before B3d).
**Builds on:**
- B3a (`2026-10-03-b3a-expenses-donations-design.md`): `finance.services.summary`, net profit and the home's
  `FinanceSummaryCard`;
- B3g: revenue counts every completed payment, grouped by `Payment.currency` (ledger D16);
- `etqan.platform.currency` (`minor_digits`); `academy.AcademySettings.default_currency`;
- Plan 13 feature switches; Plan 12a roles.

**Evidence:**
- P1 INT-013 (Exchange Rate API: CONFIRMED as configuration, INFERRED as usage);
- P1 §1.3 "Currencies" (multi-currency everywhere; automatic conversion INFERRED);
- audit INT (an exchange-rate API key in the settings);
- P1 BR-47 and BR-48 (revenue; net profit = revenue − expenses);
- phase B3-4 and §5 (estimates only; no automatic fetching).

## 1. Goal

The admin enters how much one unit of each currency the academy deals in is worth in the academy's own
currency. The home's net-profit card then adds a single converted figure for the month, labelled as an
estimate, under the per-currency lines, which stay the truth.

## 2. Decisions

| Id | Decision | Source |
|---|---|---|
| H-1 | **Rates live in `etqan.finance`**, the app that owns net profit. There is one current rate per currency, entered by hand: "1 unit of `currency` = `rate` units of the base". <br>• The base is the academy's `default_currency`, stamped on the row as `base_currency`. <br>• There is no history, and no API fetching. | phase B3-2, §5; P1 INT-013; [assumed] |
| H-2 | **A rate is a decimal, not money:** `Decimal(20, 10)`. <br>• Input is a JSON string only (a JSON number is a 400 on `rate`); surrounding spaces are stripped, then it must match `^\d{1,10}(\.\d{1,10})?$` and be greater than 0. <br>• The bounds (at most 10 integer digits and 10 decimals) cover rates of VND-to-KWD scale (about 0.00003) and the reverse (tens of thousands). <br>• Output is a fixed-point string: `format(d.normalize(), 'f')`, so trailing fractional zeros and a trailing "." are stripped and there is never an exponent (`10` stays `10`, not `1E+1`; `0.0000000001` stays as is; `4.1200000000` is `4.12`). <br>• The base currency takes no row, since its rate is 1. | CLAUDE.md (money is minor units; a rate is not money); [assumed]; [review] |
| H-3 | **Stale rates.** A row whose `base_currency` is no longer the academy currency is shown `stale` and is never used. <br>• Its `stale_reason` is `base_changed`, and editing it re-stamps the base and makes it current. Switching the academy currency back makes a `base_changed` row current again without any edit (its stamped base matches again); the `old` badge (H-4) flags its age. <br>• A row whose own `currency` has become the academy currency has `stale_reason` `own_currency`. `own_currency` wins over `base_changed` when both hold (the row's currency equals the academy currency while its stamped base differs). A PATCH on it is a 400 on `currency` ("Delete this rate"), checked before any write, so the `currency <> base_currency` constraint is never hit and there is no 500. Only DELETE remains. <br>• `convert_estimate` ignores such a row: the academy currency converts at 1. | [assumed]; [review] |
| H-4 | **Old rates.** <br>• A rate updated more than 30 days ago is marked `old` in the list. It is still used. <br>• The estimate reports `as_of`, the oldest `updated_at` among the rates it used. <br>• The home shows "rates as of <date>". | review (D-16 age); [assumed] (30 days) |
| H-5 | **Conversion is exact, then rounded once.** <br>• It runs inside `decimal.localcontext()` with `prec=60` and the `Inexact` trap set on multiply and add, so a silent context rounding is an error, never a wrong figure. <br>• The result is `sum(amount_minor × rate / 10^minor_digits(currency)) × 10^minor_digits(base)`, in exact `Decimal`. <br>• It is quantized once to an integer (the base's minor units) with `ROUND_HALF_UP`, which rounds a negative half away from zero (−0.5 becomes −1); that is intended. <br>• There is no per-line rounding. | review (D-16 rounding); [assumed]; [review] |
| H-6 | **No partial estimate.** When any currency has no usable rate (none, or stale), the amount is `null` and the codes are listed in `missing`. A partial sum is never shown. <br>• Lines with `amount_minor == 0` are skipped: they need no rate, are not listed in `missing` and do not count for `as_of`. | phase B3-4; [assumed] |
| H-7 | **Rates are the academy's own snapshot.** The month's figures are converted at the current rates, not at rates of their dates. The card says so with "at your current rates". | phase B3-4; [assumed] |
| H-8 | **The helper is `finance.services.convert_estimate(lines) -> Estimate(currency, amount_minor \| None, missing, as_of)`**, where `lines` is `[{currency, amount_minor}]`. It is public so that later phases (B4 salaries, reports) convert only through it, with H-5 to H-7's rules and labelled as an estimate. B3h uses it only for net profit. <br>• While `exchange_rates` is off it returns `None`, so a caller cannot skip the gate; the summary and every later caller get the switch for free. | phase B3-4; [assumed] |
| H-9 | **The feature `exchange_rates`** is new under the B3 marker, `default=False`. It has `requires=()`: the rates page is useful on its own. The summary rule is unchanged: the estimate is `null` unless `exchange_rates` is on and net profit is not null (net profit is null while B3a's `expenses` and `invoices` are not both on, spec b3a A-7), so nothing shows until they are. | phase B3-3; spec b3a A-7; [review] |
| H-10 | **Access:** a new resource `exchange_rate` (`view_any`, `create`, `update`, `delete`). The estimate rides on `finance/summary/` with B3a's `widget.revenue_stats`. Nothing moves money, so no route adds `NotImpersonating`. <br>• Default grants: admins get all four codes; staff get them by grant; teachers, parents and students get none. | spec roles-permissions; spec b3a A-9; ledger D19; [review] |
| H-11 | Only en and ar strings. | ledger D11, D22 |

## 3. Data (`etqan.finance`)

**`ExchangeRate`** has these fields:
- `currency`: 3 letters, unique;
- `base_currency`: 3 letters;
- `rate`: `Decimal(20, 10)`;
- `updated_by`: → user, `SET_NULL`;
- `updated_at`.

Its checks are `rate > 0` and `currency <> base_currency`. It is ordered by currency. The migration only
creates the table.

## 4. Behaviour

- **`GET finance/exchange-rates/`** (`exchange_rate.view_any`, `exchange_rates`) answers
  `{base_currency, rates: [{id, currency, base_currency, rate, stale, stale_reason, old, updated_by, updated_at}]}`.
  `stale_reason` is `null`, `base_changed` or `own_currency` (H-3). `rate` is the H-2 output string.
- **`POST`** (`exchange_rate.create`) takes `{currency, rate}`:
  - the currency is cleaned (`clean_currency`);
  - it must differ from the academy currency and must not already have a row (400 on `currency`); an existing stale `base_changed` row counts as a row: the 400 says "already has a row, edit it";
  - a concurrent POST that loses the unique race (`IntegrityError`) is caught and answered as the same 400 on `currency`;
  - a rate that does not match H-2 (including a JSON number), or is 0, is a 400 on `rate`;
  - `base_currency` and `updated_by` are stamped.
- **`PATCH finance/exchange-rates/<id>/`** (`exchange_rate.update`) takes `{rate}` and re-stamps
  `base_currency` and `updated_by`. A PATCH while the row's currency has become the academy currency is a
  400 on `currency` ("Delete this rate"), checked before any write (H-3); the row can only be deleted.
- **`DELETE`** (`exchange_rate.delete`) removes the row.
- **`convert_estimate(lines)`** follows H-5 to H-8:
  - it returns `None` while `exchange_rates` is off (H-8);
  - the base's own line counts at rate 1;
  - lines with `amount_minor == 0` are skipped (H-6);
  - an empty `lines` (or only zero lines) gives `amount_minor = 0` with no `as_of`.
- **`finance/summary/`** gains `net_profit_estimate`:
  - while `exchange_rates` is on and `net_profit_this_month` is not null, it is
    `{currency, amount_minor, missing, as_of}`, computed over `net_profit_this_month`;
  - otherwise it is `null`;
  - the other keys are unchanged.

## 5. API summary (`/api/v1/`)

| Route | Methods | Feature | Codes |
|---|---|---|---|
| `finance/exchange-rates/` | GET, POST | `exchange_rates` | `exchange_rate.view_any`, `exchange_rate.create` |
| `finance/exchange-rates/<id>/` | PATCH, DELETE | `exchange_rates` | `exchange_rate.update`, `exchange_rate.delete` |

**Payload change:** `finance/summary/` gains `net_profit_estimate`.

## 6. Dashboard

- **Billing → Exchange rates** (`_authed/billing.exchange-rates.tsx`, `exchange_rate.view_any`,
  `exchange_rates`):
  - the base currency;
  - the rates as "1 SAR = 4.12 EGP", with `stale` and `old` badges and the last update;
  - add, edit and delete;
  - rates typed and shown as decimal strings, never parsed into floats for display.
- **Home** (`FinanceSummaryCard`): under the per-currency net profit, only when `net_profit_estimate` is not null and net profit has at least one line in a non-base currency (an all-base month shows no estimate line), one of three lines:
  - "≈ {amount} {currency}, estimated at your current rates (as of {date})", with `as_of` shown as a date in the academy's timezone;
  - the same line without "(as of …)" when `as_of` is null (nothing needed a rate);
  - "Add rates for {codes} to see an estimate" when `missing` is not empty. The "Add rates" part is a link to the rates page only for holders of `exchange_rate.create`, and plain text for everyone else.
- **Wiring:**
  - keys in `locales/{en,ar}/finance.json`;
  - `FeatureCode` gains `exchange_rates`;
  - `FEATURE_SCREENS` and `FEATURE_WORDS` rows;
  - a nav item under the B3 marker;
  - `/billing/exchange-rates` (`exchange_rate.view_any`, `exchange_rates`) is appended to `BILLING_PAGES` in `dashboard/src/features/finance/landing.ts` after `/billing/checkouts` (`/billing` redirects to the first visible entry; it is not a list);
  - semantic tokens, RTL and phone width.

## 7. Dependencies and environment

- **No new package, setting or environment variable.**
- **Wiring under the B3 markers:**
  - `exchange_rates` in `platform/features.py`, with `requires`;
  - `exchange_rate` in `access/registry.py`;
  - `finance` reads the academy currency through `academy.services.get_settings()`.
- **Decision to record** (`decide`, affecting B4, B7 and B11): H-8, together with H-5 and H-6.

## 8. Seeds

The seeds go in `etqan/tenants/seeds/finance.py` (the B3a module), in a new function `seed_rates(subdomain)`
called under the B3 marker, using finance services only. The step runs only when the table is empty. `seed_dev.FEATURES` already enables every BUILT feature, so the seed needs no switch. It
writes sample rates for SAR and USD against the academy currency, from a fixed table keyed on that currency:
- **EGP base:** SAR 13.0 and USD 48.5;
- **USD base:** SAR 0.2667;
- **any other base:** no rates.

## 9. Testing

- **Backend:**
  - **Validation:** the academy's own currency, a duplicate, a duplicate against a stale `base_changed` row ("edit it"), a concurrent-POST `IntegrityError` giving 400 on `currency`, zero, a JSON number, surrounding spaces stripped, 11 integer digits or 11 decimals rejected, and PATCH after the academy currency changed.
  - **Rate output:** `10` stays `10`, `0.0000000001` stays as is, `4.1200000000` is `4.12` (no exponent, no trailing zeros or ".").
  - **Stale and old:** a row becomes stale when the academy currency changes and current again after a
    PATCH, or without any edit when the academy currency is switched back; `own_currency` wins over
    `base_changed`; a rate older than 30 days is marked `old`.
  - **Own currency (H-3):** the academy currency changes from USD to EGP while an EGP row exists. GET marks
    the row `stale` with `own_currency`; PATCH is a 400 on `currency` with no IntegrityError and the row
    unchanged; `convert_estimate` converts EGP at 1 and ignores the row; DELETE works.
  - **Feature:** the switch (`requires=()`, default off).
  - **`convert_estimate`:**
    - 0-, 2- and 3-digit currencies;
    - a negative line and a negative half;
    - one rounding of a sum that per-line rounding would change;
    - a 20-digit-rate × 12-digit-amount line (exact, no `Inexact` trap raised) and a negative half rounding away from zero;
    - missing and stale rates give `null` with `missing`;
    - a zero-amount line in a currency with no rate: skipped, not in `missing`, not in `as_of`;
    - `None` while `exchange_rates` is off;
    - empty lines;
    - `as_of`.
  - **The summary:** `null` with the feature off, or with net profit `null`; present with `exchange_rates` on alone plus whatever makes net profit non-null.
  - **Matrix and isolation:** the role × route rows and cross-academy isolation.
- **Dashboard:** the rates page and dialog, the badges, the estimate line in its three states, hidden for an all-base month, the "Add rates" link only with `exchange_rate.create`, the as-of date in the academy timezone, the `/billing` landing entry, and both languages.
- **E2E** (`dashboard/e2e/b3-exchange-rates.spec.ts`):
  1. Turn on only what `seed_dev.FEATURES` leaves off for demo (it already enables every BUILT feature).
  2. The admin records a GBP expense (no seeded rate), so the home lists GBP as missing.
  3. The admin adds a GBP rate, and the home shows the estimate with its date.

## 10. Out of scope

- Fetching rates from an API (INT-013's key), dated or historical rates (phase §5).
- Converting any figure other than net profit; later phases use H-8.
- Choosing a display currency other than the academy currency.
