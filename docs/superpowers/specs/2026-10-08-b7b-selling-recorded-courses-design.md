# Slice B7b — Selling recorded courses — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (PO-3); findings applied 2026-10-08. Spec-only mode (ledger D45).
**Phase:** B7, slice b (`2026-10-08-b7-add-on-sales-design.md` §3). Builds on B7a (same file, §5–§12).
**Requires:** B7a (same phase). From other phases it needs only merged work: B3b, B3c and B3g
(`etqan.gateways`, `billing.services.record_link_payment`).
**Evidence:** P1 RC-001 (price, discount, app-only), RC-003 (payment method PayPal / Stripe, transaction
number, amount paid). How a student buys is unobserved (TH §4 U2), so the buying flow is `[assumed]`.

## 1. Goal

A signed-in student, or a parent for a child, browses the academy's published recorded courses, and
either enrols for free or pays online with Stripe or PayPal. Once the provider confirms the payment, they
are enrolled. Visitors see the same catalogue on the public site, and are sent to sign in or register to
buy. Every sale is revenue (B7-4).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| S-1 | **The storefront lists playlists that are published and not app-only** (B7a A-1 `app_only`). The net price is `price_minor − discount_minor`; the list shows the price struck through when there is a discount. A playlist the viewing student (or the parent's chosen child) already holds an active enrolment in shows "Open course" instead of buying. | P1 RC-001 (price, discount, "show in app only") · [assumed] |
| S-2 | **The detail page** shows the thumbnail, the intro video (native `<video>` from public storage), title, language, description, content, lessons and hours, the price, and the **outline**: the titles and durations of the published videos, without their files or links. The terms and conditions are shown, and buying or enrolling needs the "I accept the terms" box ticked. The API rejects the request without it: 400 `accept_terms`. | P1 RC-001 (terms and conditions required) · [assumed] outline, acceptance |
| S-3 | **Free enrolment.** When the net price is 0, "Enrol for free" calls `enrol_from_sale(method="free", amount_minor=0, …)`. No checkout and no billing record are created. It needs only `recorded_courses`, not `online_payments`. | B7-3 ("net 0 takes the free path"); B7a A-8 |
| S-4 | **A purchase row** (B7-3) is the checkout's `reference_id`: `recorded.Purchase(playlist, student, amount_minor, currency, status pending / paid / cancelled, created_by, created_at, paid_at, enrolment)`. "Buy" with a provider first finds the pair's pending purchase. If its amount and currency still equal the playlist's current net price, it is reused. Otherwise it is cancelled and a new one made. Then `gateways.services.start_checkout("recorded_course", purchase.pk, provider, user=request.user)` is called outside any transaction (as `StartCheckoutView` does). The answer is `{id, redirect_url, amount_minor, fee_minor, currency}`, which the dashboard handles like `PayOnline` (a fee sheet, then the redirect). `gatewaysApi.start`'s body type is `purpose: "invoice"` only, so B7b has its own buy hook against its own route. The `buy/` view declares `atomic_request = False`, as `StartCheckoutView` does, so the provider is never called inside a transaction. | B7-3; `gateways/services/checkouts.py` start_checkout; `features/gateways/PayOnline.tsx`; `gateways/api/views.py` StartCheckoutView |
| S-5 | **`prepare(reference_id, user, params)`** runs these checks in order. (1) The `recorded_courses` switch is off: 404. (2) The purchase is missing or not pending: 404. (3) `user` is None (gateways' re-check never passes one without a creator, so this only fails closed), or `user` is neither the purchase's student nor a parent of that student (`identity.services.is_parent_of`, user ids): 404. (4) The playlist is no longer published or is app-only: 409 `recorded.not_for_sale`. (5) The student already holds an active enrolment: 409 `recorded.already_enrolled`. (6) The purchase's amount or currency differs from the current net price: 409 `recorded.price_changed`; the dashboard then simply buys again. Otherwise it returns `Prepared(amount_minor, currency, description=f"Recorded course {playlist.code}", add_fee=True, use_switch=True)`. Under `RECHECK` (gateways' capture-time re-check, which passes the checkout's creator) the same checks run. | B7-3; ledger D28 |
| S-6 | **`complete(done)`** runs B7-4. Lock order is the same as `start_purchase` and `enrol_from_sale`: the playlist row first, then the purchase. It reads the purchase's playlist id unlocked, locks that playlist, then locks the purchase and re-checks that it still belongs to that playlist. If the purchase is missing, the result is `reference_missing`. If it is already paid by another checkout, the result is `purchase_paid` and nothing is recorded: a second payment was really taken and the office refunds it. If it is cancelled but nothing blocks the sale, the money is still taken: the family paid for this price, and a later re-buy only cancels the row. If the currency differs from the checkout's, the result is `currency_mismatch`. If the student is already enrolled, the result is `already_enrolled`, with nothing recorded: the office settles it from the checkout's "needs attention". Otherwise, inside an inner `transaction.atomic()` wrapped as a whole in `try`, it records the billing payment with `record_link_payment(student_id=<profile pk>, customer_name="", customer_email=(student user's email or ""), customer_phone="", amount_minor=done.amount_minor, fee_minor=done.fee_minor, currency=done.currency, method=done.provider, transaction_number=done.transaction_number, notes="Recorded course: <title>"[:500])`. It enrols with `enrol_from_sale(method=done.provider, amount_minor=done.amount_minor, currency, transaction_number, payment_id)`, and marks the purchase paid with its enrolment. A `ConflictError` `recorded.already_enrolled` from `enrol_from_sale` (an office or free enrolment won the race) rolls the inner block back, billing row included, and maps to `already_enrolled`. A `transaction_number` refusal or the `billing_payment_transaction_unique` `IntegrityError` maps to `already_recorded`. Any other refusal maps as B7-4 says. Whether the playlist is still published is **not** re-checked at completion: money already paid for an unpublished course still enrols, and the student sees the course again once it is republished. | B7-4; `billing/services/link_purpose.py` (mapping precedent) · [assumed] cancelled purchase still taken |
| S-7 | **Who may buy:** a student for themselves, or a parent for a child (`student_id` in the body, checked with `is_parent_of`). Staff and admins enrol from the office (B7a), never through the store: 403. All buy routes carry `NotImpersonating` (D19). | B7-6; ledger D19 |
| S-8 | **The return page** (`features/gateways/ReturnPage.tsx`, public, D17/D30) gets one branch, as `invoice` has. A completed `recorded_course` checkout links to "My recorded courses" (`/learning/recorded`). A pending, failed or cancelled one links to the store list (`/learning/recorded/store`): the checkout's `reference_id` is the purchase, not the playlist. Both links are the same for students and parents, so this branch makes no `me` call. This is a one-commit change under a ledger `claim` on the file (phase spec §4). | ledger D17, D30; phase §4 |
| S-9 | **The public catalogue.** These routes are anonymous and throttled per IP by a new `ScopedRateThrottle` scope `recorded_public` (`60/minute`). It is one line in `DEFAULT_THROTTLE_RATES` (`config/settings/base.py`), added under a one-commit ledger claim, as the `payment_link` scope was: `GET /api/v1/recorded/public/playlists/` and `GET /api/v1/recorded/public/playlists/<slug>/` return S-1's playlists (with their `id`, so the site can link into the dashboard; not paginated, newest first, at most 100) with S-2's fields, the public thumbnail and intro URLs, and the outline. While `recorded_courses` is off they answer 404. They carry no student data. | ledger D2 (no raw HTML: plain-text fields) · [assumed] |
| S-10 | **The marketing pages** `/{lang}/recorded-courses` and `/{lang}/recorded-courses/{slug}` (Astro, ar/en, the layout and cache of the B8 video pages) render the public catalogue. "Buy" or "Enrol" links to `/app/learning/recorded/store/<id>`; the dashboard's auth guard sends a visitor to sign in or register first. The header shows a "Recorded courses" link when the list endpoint answers non-empty. That fetch is cached with the site payload (`resolveSite`'s cache). A 404 or an empty list hides the link and makes the page a 404. `etqan.site` cannot import `etqan.recorded`, so it gets no flag. The B8-built files this touches (`components/Header.astro`, `lib/site.ts`, the i18n strings, `pages/sitemap.xml.ts`) change in one commit under a ledger claim. **After sign-in the visitor lands on the dashboard home**, not on the course: `requireAuth` keeps no return path. We accept that, and the marketing button's hint says "Sign in, then open Recorded courses". A validated `?next=` on login and register would be a request to the identity owner and is not part of B7. | B7-13; `marketing/src/pages/[lang]/videos` precedent; `features/identity/require-auth.ts` · [assumed] |
| S-11 | **Needs-attention codes.** The gateways checkouts list shows `description` and translates `gateways.attention.<code>` from `ATTENTION_CODES` (`features/gateways/schemas.ts`). B7b adds `already_enrolled` ("The student was already enrolled; refund or keep as credit by hand") and `purchase_paid` ("This course purchase was already paid by another checkout; refund one") to `ATTENTION_CODES` and to `locales/{en,ar}/gateways.json`, in one commit under a ledger claim. `already_recorded`, `currency_mismatch` and `reference_missing` exist already. | `features/gateways/CheckoutsList.tsx`, `schemas.ts` · [assumed] wording |
| S-12 | **Office view.** The enrolments tab (B7a §6) shows the method and the transaction number for online enrolments, and links to the billing payment (`/billing/payments/<id>` when the viewer holds `payment.view`). Online enrolments cannot be deleted (B7a A-10), only revoked. | B7a A-10 |

## 3. Data

```text
etqan.recorded.Purchase
  playlist     FK Playlist  PROTECT  related_name="purchases"
  student      FK identity.StudentProfile  PROTECT  related_name="+"
  amount_minor BigIntegerField  > 0
  currency     CharField(3)
  status       CharField(9) choices pending | paid | cancelled  (default pending)
  enrolment    FK Enrolment  null  SET_NULL  related_name="+"
  created_by   FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at   DateTimeField(auto_now_add)
  paid_at      DateTimeField  null
  accepted_terms_at DateTimeField   (when the buyer ticked the terms, S-2)
  indexes (playlist, student, status)

etqan.recorded.Enrolment   (B7b's migration adds)
  accepted_terms_at DateTimeField null   (set by the free path and by a sale from its purchase)
```

At most one pending purchase per pair is kept by the reuse rule (S-4) under a lock on the playlist row. It
is not a database constraint: a cancelled or paid purchase may sit next to a new pending one.

## 4. Services and API

`recorded.services`:
- `storefront(user, student_user_id=None)` lists S-1's playlists with an `enrolled` flag for that student.
- `store_detail(playlist_id, user, student_user_id=None)` returns S-2's data.
- `enrol_free(playlist, *, student_user_id, by)` implements S-3.
- `start_purchase(playlist, *, student_user_id, provider, by) -> StartedCheckout` implements S-4. It
  creates or reuses the purchase, then calls `gateways.services.start_checkout` and returns its result.
  Gateways' refusals pass through.
- `purpose.register()` is called from `RecordedConfig.ready()` and registers `recorded_course` with
  S-5's `prepare` and S-6's `complete`.
- `public_playlists()` and `public_playlist(slug)` back S-9.

| Route | Methods | Who | Notes |
|---|---|---|---|
| `store/` | GET | student; parent with `?student=` | `recorded_courses` |
| `store/<id>/` | GET | same | |
| `store/<id>/enrol/` | POST | same; `NotImpersonating` | `{student_id?, accept_terms}`. 201 enrolment, or 409 when not free (`recorded.not_free`), already enrolled, or not for sale |
| `store/<id>/buy/` | POST | same; `NotImpersonating`; throttle `gateway_start` | `{student_id?, provider, accept_terms}`. `recorded_courses` and `online_payments` (404 when either is off). 201 started checkout |
| `store/<id>/providers/` | GET | same | The providers that can take the net price: `gateways.services.providers_for(currency, amount_minor, add_fee=True)`; 404 while `online_payments` is off |
| `public/playlists/`, `public/playlists/<slug>/` | GET | anyone | S-9 |

## 5. Screens

| Who | Where | What |
|---|---|---|
| Student / parent | **Learning → Recorded courses store** `/learning/recorded/store` (nav item next to "My recorded courses") | Cards with thumbnail, title, language, lessons, hours, price, and an "Enrolled" badge. A parent picks a child first. |
| Student / parent | `/learning/recorded/store/$playlistId` | S-2's detail. Below it: "Enrol for free", or a provider choice (from `providers/`) and "Buy", gated on the terms box, then the fee sheet and the redirect. "Open course" when already enrolled. |
| Anyone | marketing `/{lang}/recorded-courses[/{slug}]` | S-10. |
| Office | enrolments tab (B7a) | S-12. |

## 6. Tests

- **Backend.** S-1's filtering. The net price. The outline carrying no URLs or file names. Terms
  acceptance. The free path, with no billing record. Purchase reuse and replacement on a price change,
  under concurrency. `prepare`'s six refusals in order, its happy path and its `RECHECK` path. `complete`:
  happy path (billing record with fee and notes, enrolment, purchase paid), idempotent second delivery,
  `already_enrolled` with nothing recorded, `currency_mismatch`, `reference_missing`, a cancelled
  purchase still taken, a transaction-number clash giving `already_recorded`, and an `IntegrityError` race
  on `billing_payment_transaction_unique`. End-to-end through the gateways simulator: a Stripe and a
  PayPal checkout complete into an enrolment, and revenue for the month includes amount + fee. Access:
  student and parent, the other family's child (404), staff (403), impersonation (403), both switches
  off (404). Public routes: anonymous, 404 when off, no student data.
- **Contracts.** `etqan.recorded` imports only `gateways.services` and `billing.services`. The gateways
  contract lists `etqan.recorded` (phase spec §4).
- **Dashboard.** The store list and the child picker. The detail and its terms gate. The free enrol. The
  buy flow with the fee sheet (MSW). The ReturnPage branch.
- **Marketing.** The pages render from fixtures; the nav link is hidden on 404 or an empty list.
- **e2e** (`e2e/b7-recorded-store.spec.ts`): the demo student buys `TAJWEED-1` through the simulator
  (PayPal or Stripe test mode, as the existing B3 e2e does), lands on the return page, opens "My recorded
  courses" and sees the course. First the student is un-enrolled from it, by revoking the seeded enrolment
  in the test's own setup through the office API.

**A replaced purchase's Stripe session stays payable.** `start_checkout` expires only pending checkouts
with the same reference, so a purchase cancelled by a price change leaves its Stripe Checkout Session
open. If the family pays it, S-6 takes the money at the old price and enrols, since the row is cancelled
but nothing blocks the sale. PayPal's capture re-check refuses it instead (409 `recorded.price_changed`).
We accept this, and it is tested for both providers.

## 7. Non-goals

- Coupons and discount codes on courses (B3f codes are subscription codes; recorded-course codes are
  B7g's activation codes).
- Wallet payment (phase §3).
- Gifting a course to someone who is not one's child.
- Selling on the apps (B11).
