# Slice B7d — Consultations: booking and paying online — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (PO-3); findings applied 2026-10-08. Spec-only mode (ledger D45).
**Phase:** B7, slice d (`2026-10-08-b7-add-on-sales-design.md` §3).
**Requires:** B7c (same phase). From other phases: merged work only. That covers B3b/B3c/B3g
(`gateways.services.start_checkout(..., user=None, params=...)` for public purposes, as
`start_link_checkout` uses it), `billing.services.record_link_payment`, B2e availability, and B9c's
`identity.services.send_notice`.
**Evidence:** P1 FLOW-009, CONS-002 (person fields, student timezone, payment ID / amount / gateway),
CONS-003, §8.4, BR-26, BR-27, BR-28. The booker's own screens are unobserved (TH §4 U2): `[assumed]`.

## 1. Goal

A visitor on the public site, or a signed-in student or parent, picks a consultation product, picks a
teacher and then one of that teacher's free slots, gives their contact details, and pays with Stripe or
PayPal. The request then waits for the office to confirm it (FLOW-009: "under review → confirmed"). The
booker follows it on a manage page, which a visitor reaches through an emailed link. There the booker can
ask to reschedule when the product allows it, and rate the consultation once it is complete.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| K-1 | **Self-booking needs** `consultations`, `online_payments`, and, for products with a slot (not `email`), `teacher_availability` (B7-10). When `consultations` or `online_payments` is off, the booking routes answer 404 and the public pages hide "Book". While only `teacher_availability` is off, slot products are hidden from booking, and `email` products stay listed and bookable. There is no unpaid self-booking: TutorHamster's flow pays before review (FLOW-009). | P1 FLOW-009; B7-10 · [assumed] |
| K-2 | **Teachers offered** are the product's responsible teachers who are opted in (B7c C-3) and active. They are read with `identity.services.active_teachers(user_ids)` (not `teacher_profiles_for`, which validates and returns raw rows). The payload is whitelisted to `user_id`, `full_name`, an initial and `bio`. It never carries payout details, date of birth or meeting URL. **Slots** are B7c's `free_slots`, with B7-10's lead time of 12 hours. They run up to the earlier of 31 days and `validity_days` from today in academy time, because payment happens now (BR-26). A slot with room left is offered. Times are shown in the booker's timezone, with the academy time as a secondary line ("system timezone", CONS-002). | P1 BR-26, BR-28, CONS-002 · [assumed] 31-day horizon |
| K-3 | **Booking** creates a B7c `Request` with: status `pending_review`; person fields (name, email and WhatsApp are required; a signed-in student's are prefilled; a parent books for a child, `student` = the child); `timezone` (from the browser, validated); `notes`; `self_booked=true`; `hold_until = now + 30 min` (B7-17); `manage_token` (`secrets.token_urlsafe(32)`, 43 characters, unique); `booked_ip_hash` (HMAC-SHA256 under `SECRET_KEY` of DRF's `get_ident`, which honours `NUM_PROXIES=1`); and the **price snapshot** `price_minor`, `price_currency` and `price_fee_enabled`, copied from the product (B7-3). It takes, in this order, an advisory lock on the booker (`consultations.booker.<schema>.<ip hash>`) and then B7c's teacher advisory lock. It refuses a full slot with 409 `consultations.slot_full`, and refuses K-8's caps with 409 `consultations.too_many_pending`. Then, outside the transaction, it starts the checkout (K-4). The answer is `{request: {id, manage_url}, checkout: {id, redirect_url, amount_minor, fee_minor, currency}}`. If the provider start fails, the request stays and the manage page offers "Pay" again while the hold lasts. | B7-17; P1 CONS-002 · [assumed] |
| K-4 | **Checkout start.** Every booking checkout starts with `gateways.services.start_checkout("consultation", request.pk, provider, user=<user>, params={"token": request.manage_token})`. `user` is always None on the anonymous routes, `public/book` and `public/manage/*`, which have `authentication_classes = []` as `PublicLinkView` has (ruling M2). `user` is the signed-in user on `my/book` and `my/<id>/pay`. The token is read from the row by the server, never from the request body (D28). Retries from the manage page pass the URL's token, as `PublicLinkCheckoutView` does. | ledger D17, D28; `gateways/services/links.py` start_link_checkout |
| K-5 | **`prepare(reference_id, user, params)`** (purpose `consultation`, `public=True`) checks in order. (1) The switches of K-1 are off: 404. (2) The request is missing, or `params` is neither `{"token": <its manage_token>}` nor gateways' `RECHECK`: 404. (3) The request is already paid, not `pending_review`, or not self-booked: 409 `consultations.not_payable`. (4) Its hold has expired and its slot has no room left without it: 409 `consultations.slot_taken`. (5) The product is no longer bookable: 409 `consultations.not_bookable`. `prepare` is read-only, because gateways' `still_payable` calls it. Otherwise it returns `Prepared(amount_minor=request.price_minor, currency=request.price_currency, description=f"Consultation CR-{pk:06}", add_fee=request.price_fee_enabled, use_switch=False)`, the snapshot rather than the live product, (BR-26, B7-3). No personal data is in the description. | B7-3; ledger D28; P1 BR-26 |
| K-6 | **`complete(done)`** follows B7-4. Lock order: gateways' `finish` already holds the checkout row. B7 then takes the teacher advisory lock (the request's teacher read unlocked first), then the request row. After locking, it re-reads the teacher; if the office has reassigned it, it releases nothing and retries once with the new teacher's lock. If the request is missing, the result is `reference_missing`. If it is already paid, the result is `request_paid` and nothing is recorded: a second payment is attention for a refund. If it is cancelled, the result is `request_cancelled`. If the checkout's currency differs from `price_currency`, the result is `currency_mismatch`. If the hold has expired and the slot is now full without this request, the result is `slot_taken`. Otherwise, inside an inner `atomic()` wrapped whole in `try`, it records `record_link_payment(student_id=<profile pk> or None, customer_name=name[:120], customer_email=email, customer_phone=whatsapp[:30], amount_minor, fee_minor, currency, method=provider, transaction_number, notes=f"Consultation CR-{pk:06}")`. It then sets `paid_method=provider`, the payment id, the amount, the fee, the currency, the transaction number, `paid_on` (the academy's today) and `hold_until=null`. Refusals map as B7-4 says. **The manage-link email** (K-9) is sent here, with `transaction.on_commit`, only once the payment is recorded. The request stays `pending_review` for the office to confirm (FLOW-009). The four new attention codes (`request_paid`, `request_cancelled`, `slot_taken`, `not_bookable`) go into `ATTENTION_CODES` and `locales/{en,ar}/gateways.json` in one commit under a claim, as in B7b S-11. | B7-4; P1 FLOW-009 |
| K-7 | **Unpaid holds.** A self-booked request is **live unpaid** while `paid_method == ""` and `hold_until > now`. Once the hold has expired and it is still unpaid, it no longer counts as live (B7c C-5). A periodic task, `consultations.tasks.cancel_unpaid` (every 15 minutes), runs through `platform.tenancy.for_each_academy`. Its `CELERY_BEAT_SCHEDULE` entry goes in under a one-commit claim. For each candidate it locks the row with `select_for_update`, never taking the advisory lock after it, and re-checks: unpaid, hold expired, no pending checkout (`gateways.services.checkouts_queryset().filter(purpose="consultation", reference_id=pk, status="pending")`), and no checkout created in the last 2 minutes (gateways' `STARTING_FOR`). Only then does it set `cancelled`, `cancelled_at` and `cancel_reason="unpaid"`. A Stripe checkout left pending is expired only by gateways' daily job, so such requests may stay uncancelled for up to about two days. That is harmless, since they are not live. A payment that still arrives after the cancel becomes `request_cancelled` attention, which we accept. The office list hides cancelled-unpaid requests unless the "unpaid" filter is set. | CLAUDE.md (jobs loop academies) · [assumed] |
| K-8 | **Limits** (B7-17). The booking route has the `ScopedRateThrottle` scope `consultation_book` (`10/hour` per IP; one line in `DEFAULT_THROTTLE_RATES` under a claim). At most 3 live unpaid self-booked requests per email, and 3 per `booked_ip_hash`, are allowed (409 `consultations.too_many_pending`). Both counts are taken under the booker lock of K-3. The three new scopes (`consultation_book` 10/hour, `consultation_manage` 60/minute, `consultation_public` 60/minute per IP) go into `DEFAULT_THROTTLE_RATES` in one commit under a ledger claim. | B7-17 |
| K-9 | **The manage link** is `app_url(f"/consult/manage/{token}")`. A visitor sees it at once on the wizard's last step, and it is kept in `sessionStorage` (K-15). It is emailed **only after payment**, from `complete` on commit (K-6), with `identity.services.send_notice(email, subject, body, language=<page language>)`. The email is a fixed bilingual template naming the product, the time in their timezone, and the link. It carries **no booker-supplied text** (no name, no notes), so the route cannot relay arbitrary branded mail, and an unpaid booking sends nothing (B7-9). A signed-in booker is not emailed: their pages list the request. **The token** must match `^[A-Za-z0-9_-]{43}$` in full before any query, and is compared with `hmac.compare_digest`, as `link_by_token` does. It never expires. Knowing it allows only what the manage page offers. The manage page sets `<meta name="referrer" content="no-referrer">`, and its meeting link has `rel="noreferrer noopener"`, so the token never leaks through a referrer. | B7-9 · [assumed] |
| K-10 | **The manage page** (`GET consultations/public/manage/<token>/`, anonymous, throttle `consultation_manage` 60/minute) shows: product, teacher name, status, start in the booker's timezone, the meeting link once `confirmed` (`video_call`, `live_chat`), payment state, and the actions that apply. It **never returns the booker's email or WhatsApp**, because the token never expires and can be forwarded. The actions are: **Pay**, while unpaid and not cancelled. If the hold has expired, the pay view first takes the booker and teacher locks and re-holds the slot for 30 minutes when it has room (409 `consultations.slot_taken` otherwise). It then starts the checkout (K-4) with the URL's token. **Ask to reschedule** (K-11); **Review** (K-12). No booker cancellation: TutorHamster shows none, so refunds stay with the office. | P1 §8.4 · [assumed] |
| K-11 | **Reschedule request** (BR-27). Allowed while `confirmed`, if the product is reschedulable, and at least 12 hours before the start. The booker picks a new slot from K-2's list, which must fall within `paid_on + validity_days`, and may add a note. The request moves to `reschedule_requested` and stores `proposed_starts_at`. The proposed slot is **not** held. The office then reschedules it, to that slot or another, or declines (B7c C-6). | P1 BR-27, §8.4 · [assumed] proposal and 12 h |
| K-12 | **Reviews** (CONS-003, B7-16). Once `completed`, the booker gives one review per request: rating 1–5 and a comment of up to 1 000 characters of plain text. It starts `pending`, and the office approves or rejects it (`consultation_review.update`), the same rule as B7e's course reviews. The public product payload (`public/products/<id>/`) embeds the approved reviews' average (as B7e E-5) and count, and the 5 latest comments, attributed only as "Visitor" or "Student" with no name. | P1 CONS-003 · [assumed] |
| K-13 | **Signed-in pages.** `Learning → Consultations` `/learning/consultations` lists the requests of the student, and for a parent, of their children plus those they created. A request opens the manage view through the authenticated twin of the routes (`my/<id>/…`), scoped by ownership rather than token. "Book a consultation" opens `/learning/consultations/book`, which posts to `my/book` (session, CSRF, `NotImpersonating`) with an optional `student`: a child's user id, checked with `is_parent_of`. | B7-6 · [assumed] |
| K-14 | **Public pages.** On the marketing site, `/{lang}/consultations` lists bookable products, featured first, with price, duration, delivery mode and rating. `/{lang}/consultations/{id}` adds the description and teachers. "Book" links to the dashboard's public route `/app/consult/$productId`, the booking wizard (teacher → slot → details → provider → pay), which needs no sign-in; a signed-in user there is offered the signed-in wizard (K-13). Products are addressed by id; they have no slug. The public product endpoints are `GET consultations/public/products/` and `…/<id>/`. They are anonymous, use throttle `consultation_public`, and answer 404 while K-1's switches are off. Header link, caching and claims follow B7b S-10. | B7-13; B7b S-10 precedent |
| K-15 | **Return page.** For an anonymous reader, gateways' public read is `payloads.checkout_status(full=False)`, which carries neither the purpose nor the token. So the wizard stores `sessionStorage["consult:<checkout id>"] = <manage URL>` before redirecting, and the return page's consultation branch keys on that entry. A signed-in creator (the `my/` flow) gets the full payload and branches on `purpose === "consultation"`, linking to `/learning/consultations`. With neither, the page says "Use the link we emailed you after payment". The page makes no `me` call for this branch (D30). This is a one-commit claim on `ReturnPage.tsx`, as in B7b S-8. | ledger D30 · [assumed] |
| K-16 | **Access.** New resource `consultation_review` ("Consultation reviews" / "تقييمات الاستشارات"): `view_any`, `update`. The office request list gains the filter "self-booked" and shows the payment, its fee and its gateway. All booking, pay, reschedule and review routes have `NotImpersonating` (D19); the anonymous routes have no session to check. | ledger D19; P1 consultation::review |

## 3. Data (B7d's migration on `etqan.consultations`)

```text
Request  (+)
  self_booked        BooleanField(default False)
  manage_token       CharField(64) unique null   (set for self-booked requests)
  hold_until         DateTimeField null
  proposed_starts_at DateTimeField null
  cancel_reason      CharField(10) blank  ("" | unpaid | office)
  booked_ip_hash     CharField(64) blank
  price_minor        BigIntegerField null;  price_currency CharField(3) blank;  price_fee_enabled BooleanField null
                     (price snapshot at self-booking, B7-3)

Review
  request    OneToOne Request  CASCADE  related_name="review"
  rating     PositiveSmallIntegerField 1..5
  comment    TextField(blank, max 1000)
  status     CharField(8) pending | approved | rejected (default pending)
  reason     TextField(blank, max 500)
  created_at; decided_by FK AUTH_USER null SET_NULL; decided_at null
```

## 4. API (`/api/v1/consultations/`)

| Route | Methods | Who |
|---|---|---|
| `public/products/`, `public/products/<id>/` | GET | anyone (K-14); the detail embeds K-12's approved reviews |
| `public/products/<id>/teachers/` | GET | anyone (K-2) |
| `public/products/<id>/slots/?teacher=&from=&days=` | GET | anyone (K-2) |
| `public/book/` | POST | anyone; throttle `consultation_book` (K-3). Body `{product, teacher, starts_at?, name, email, whatsapp, timezone, notes, provider}` |
| `public/manage/<token>/` | GET | token holder (K-10) |
| `public/manage/<token>/pay/` | POST | token holder; `{provider}` (K-4) |
| `public/manage/<token>/reschedule/` | POST | token holder (K-11) |
| `public/manage/<token>/review/` | POST | token holder (K-12) |
| `my/`, `my/<id>/`, `my/<id>/{pay,reschedule,review}/`, `my/book/` | GET/POST | student, parent (K-13); `NotImpersonating` on writes; `my/book` body adds `student?` |
| `reviews/`, `reviews/<id>/` | GET, PATCH | `consultation_review.view_any` / `.update` |

The views that start checkouts declare `atomic_request = False`. Anonymous views have `authentication_classes = []`. This slice also adds `etqan.consultations` to the "gateways imports no business app" import contract under a one-commit claim (D53).

## 5. Tests

- **Booking.** Field validation. The per-IP and per-email caps. No email sent before payment, and the email's
  body carrying no booker text. Token regex rejection before any query. The price snapshot used after
  a product price change. The slot rules of K-2 (lead time, horizon, validity, room). The hold
  counted as live and then expiring. The email cap. The throttle. Parent for child. The signed-in
  prefill. Email-mode booking without a start.
- **Purpose.** Each of `prepare`'s refusals, in order, and its token and `RECHECK` paths. A body token is
  never used. `complete`: happy path (billing record for a student and for an unregistered person, fee,
  notes, paid fields, hold cleared), plus `request_paid`, `request_cancelled`, `slot_taken`,
  `currency_mismatch`, `reference_missing`, a transaction clash, and the IntegrityError race. A late
  payment with room left is accepted. Lock order under concurrency (two payments for the last place). End
  to end through the simulator with Stripe and PayPal: revenue includes amount + fee. A PayPal capture
  re-check refuses after the slot is taken.
- **Task.** `cancel_unpaid` across two academies, skipping a request with a pending checkout.
- **Manage.** Token scoping (another token gives 404), each action's preconditions, the link shown only
  when confirmed, reschedule within validity and 12 h, one review only and only after completion, and
  public reviews carrying the first name only.
- **Access.** Switches off give 404. Impersonation refused. The `consultation_review` matrix.
- **Dashboard.** The wizard steps and timezone display (MSW), the manage page actions, the
  `/learning/consultations` list, the ReturnPage branch with and without the `sessionStorage` entry, and
  the office reviews tab.
- **Marketing.** The product list and detail render. The header link is hidden when off.
- **e2e** (`e2e/b7-consultation-booking.spec.ts`): a visitor books the demo product's first slot, pays
  through the simulator, and lands on the manage page. The office confirms; the manage page shows the
  link. The office completes; the visitor leaves a review, which shows on the public page.

## 6. Non-goals

- Booker cancellation and automatic refunds (B3-10).
- Notices other than the K-9 manage-link email: B5 builds confirmation, reminder and reschedule notices
  on B7c's `consultation_events` / `consultations_starting`, extended by B7d's `self_booked`.
- Automatic Zoom meetings (D42).
- Payment by wallet or by hand from the booking wizard.
