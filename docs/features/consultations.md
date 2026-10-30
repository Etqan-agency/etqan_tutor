---
title: "Consultations"
---

An academy sells one-off paid consultations: a video call, a live chat or an email answer with one of its teachers.
The office defines consultation products, chooses which teachers offer them, records requests (by phone, say) and
moves them through review, confirmation, rescheduling and completion. It records manual payments and moderates
reviews. A teacher sees their own requests and records how a session went. Visitors, students and parents can book and
pay online themselves. A booking holds its slot for 30 minutes while unpaid. A margins report shows what each teacher
earned. Everything sits behind the per-academy feature `consultations`, which is off by default.

## Concepts

| Model (`etqan.consultations.models`) | What it is |
|---|---|
| `Product` | A consultation type. It has bilingual name and description, `price_minor` > 0 with `currency`, `duration_minutes` (15–240), `validity_days` (1–365), `participants` (1–50, the seats per slot) and `delivery_mode` (`video_call`, `live_chat`, `email`). Flags: `status` (available/archived), `enabled`, `featured`, `reschedulable`, `fee_enabled` (the gateway fee is added). `teacher_share_bp` is in basis points. M2M `teachers`. `bookable` = available and enabled. |
| `Consultant` | One row per teacher: the "offers consultations" switch (`offers`). Only opted-in teachers can be added to a product or booked. |
| `Request` | One consultation. It holds the person (`name`, `email`, `whatsapp`, `timezone`, optional `student`), `teacher`, `starts_at`/`ends_at` (both null for email), `meeting_url`, `status`, `session_status`, student and teacher attendance, payment fields (`paid_method` manual/stripe/paypal, `billing_method`, FK `billing.Payment`, `amount_minor`, `fee_minor`, `currency`, `paid_on`), and `teacher_share_bp` (snapshot at completion). Self-booking adds `self_booked`, `manage_token`, `hold_until`, `proposed_starts_at`, `cancel_reason` (`unpaid`/`office`), `booked_ip_hash`, `language` and a price snapshot (`price_minor`, `price_currency`, `price_fee_enabled`). Reference is `CR-000123`. `paid` = `paid_method` is set. |
| `Review` | One per request (one-to-one). `rating` is 1–5, with an optional comment. Pending until the office approves or rejects it. |

Request statuses: `pending_review` → `confirmed` → `completed`, with `reschedule_requested` (and back to `confirmed`)
and `cancelled`. Completed and cancelled requests are closed.

## How it works

**Products and teachers.** `services/products.py`: `create_product`, `update_product` and `delete_product`. A product
with any request is archived, never deleted (409 `consultations.product_in_use`). `services/consultants.py:set_consultant`
flips the teacher opt-in.

**Slots.** `services/slots.py:free_slots` builds candidate starts from the teacher's weekly availability windows
(`scheduling.services.windows_of`, academy wall clock, pure math in `slot_math.py`). It removes overlaps with the
teacher's scheduled sessions and live requests. A start is free while fewer than `participants` live requests share it
for the same product. Email products have no slots, and with `teacher_availability` off there are none.
`room_left` / `check_capacity` give the one hard refusal (409 `consultations.slot_full`). `warnings_for` returns
non-blocking warnings for a start the office types in: conflicts, outside availability, outside validity.

**Office requests.** `services/requests.py:create_request` fills contact details from the student when given. A
`video_call` defaults its link to the teacher's `default_meeting_url` (https only). `update_request` edits a request.
`delete_request` works only on unpaid `pending_review` requests. Moves are in `services/transitions.py`: `confirm`
(needs a time unless email), `cancel`, `request_reschedule` (only if `reschedulable`), `reschedule` (the office can
always move a confirmed start; it resets attendance), `decline_reschedule`, `record_delivery` (link; attendance and
session status only once confirmed and started), and `complete` (needs a recorded session unless email; it snapshots
`teacher_share_bp`). Any change to a start takes a per-teacher advisory lock (`common.lock_teacher`) before the row
lock.

**Manual payment.** `services/payments.py:record_payment` writes `billing.services.create_record` and marks the request
`paid_method="manual"` in the same transaction. The view also needs `payment.create` (or admin) and refuses
impersonation.

**Self-booking (B7d).** It is open only when `consultations` and `online_payments` are both on
(`services/booking.py:booking_open`). A slot product also needs `teacher_availability` (`self_bookable`).
1. `booking.py:booking_slots` returns slots from today, at least 12 hours ahead, up to the earlier of
   `validity_days` and 31 days.
2. `booking.py:book` takes the booker lock (HMAC of the IP), then the teacher lock. It caps live unpaid holds at 3
   per email and 3 per IP (409 `consultations.too_many_pending`) and re-checks that the start is still offered. It
   creates a `pending_review` request with `self_booked=True`, `hold_until = now + 30 min`, a random `manage_token`
   and a price snapshot.
3. The view then calls `paying.py:start_payment`. That re-holds the slot if the hold expired (`rehold`) and calls
   `gateways.services.start_checkout("consultation", pk, provider, params={"token": manage_token})`. If the checkout
   fails to start, the booking stays and the manage page offers Pay.
4. The gateways purpose `services/purpose.py` (registered `public=True`). `prepare` checks the token and the switches,
   that the request is unpaid and under review, and that the slot is not gone. `complete` records
   `billing.services.record_link_payment` and the request's paid fields in one block. For a visitor (no `created_by`),
   it emails the manage link on commit (`notices.py:send_manage_link`, through `identity.services.send_notice`). The
   request stays `pending_review` for the office to confirm.
5. `services/unpaid.py:cancel_unpaid` cancels expired unpaid holds (`cancel_reason="unpaid"`), skipping any with an open
   checkout.

**Manage page.** `services/manage.py`. A visitor uses the token (`by_token`, compared in constant time); a family uses
ownership (`family_requests`: a student's own; a parent's children's plus those the parent made; unpaid auto-cancels
hidden). `actions` offers pay, reschedule (`ask_reschedule`: confirmed, reschedulable, ≥12 h ahead, to an offered
slot; the office then decides) and review (`leave_review`, once completed). Bookers cannot cancel.

**Reviews.** `services/reviews.py:decide_review` approves or rejects. `ratings_by_product` / `review_summary` feed the
public product payload (approved average, count, latest comments attributed only as student or visitor).

**Margins report (B7f).** `services/earnings.py:earning_lines` takes completed requests with `completed_at` in the range
(academy days) whose billing payment is still `completed`; the others are counted as excluded. Share =
round-half-up(`amount_minor × teacher_share_bp / 10000`), and margin = amount − share. `margins_report` groups rows by
teacher and currency (never summed across currencies), with an optional academy-currency estimate when
`exchange_rates` is on. `teacher_earnings` is exported for payroll (B4). The default range is the current academy
month.

## API

All paths are under `/api/v1/consultations/`. Office routes are `HasCode`; every route needs `consultations` on.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `public/products/`, `public/products/<id>/` | anyone (throttle `consultation_public`); 404 unless booking is open | Bookable products; the detail has teachers and reviews |
| GET | `public/products/<id>/teachers/` | anyone | Offered teachers |
| GET | `public/products/<id>/slots/?teacher=&from=&days=` | anyone | Free starts |
| POST | `public/book/` | anyone (throttle `consultation_book` 10/h) | Book and start checkout; returns `manage_url` and `checkout` |
| GET | `public/manage/<token>/` | token holder (throttle `consultation_manage`) | Booking state and actions (no email/WhatsApp) |
| POST | `public/manage/<token>/pay/`, `…/reschedule/`, `…/review/` | token holder | Pay / ask to move / review |
| GET | `my/`, `my/<id>/` | student, parent | Family's consultations |
| POST | `my/book/`, `my/<id>/pay/` | student, parent; not impersonating | Signed-in booking / pay (need `online_payments`) |
| POST | `my/<id>/reschedule/`, `my/<id>/review/` | student, parent; not impersonating | Ask to move / review |
| GET/POST | `products/` | `consultation.view_any` (or request create/update) / `consultation.create` | Products |
| GET/PATCH/DELETE | `products/<id>/` | `consultation.view_any/update/delete` | One product (multipart cover) |
| GET | `products/<id>/slots/` | `consultation_request.create` or `.update` | Office slot picker |
| GET | `consultants/` | product readers | Opted-in teachers |
| GET/PUT | `consultants/<user_id>/` | `consultation.view_any` / `consultation.update` | Teacher opt-in |
| GET/POST | `requests/` | `consultation_request.view_any` (teacher: own, read-only) / `.create` | List with filters; `?format=csv` office-only (needs `export`) |
| GET/PATCH/DELETE | `requests/<id>/` | `consultation_request.view/update/delete` (teacher: own GET) | One request |
| POST | `requests/<id>/confirm/`, `cancel/`, `request-reschedule/`, `reschedule/`, `decline-reschedule/` | `consultation_request.update` | Status moves |
| POST | `requests/<id>/delivery/`, `complete/` | `consultation_request.update`, or the request's teacher | Link, attendance, session status; complete |
| POST | `requests/<id>/payment/` | `consultation_request.update` + `payment.create`; not impersonating | Record a manual payment |
| GET | `schedule/?week=&teacher=&product=` | `consultation_schedule.view_any` | Week agenda |
| GET | `reports/margins/?from=&to=&detail=1` | `consultation_request.export_margins` + `.view_any` | Margins (JSON or CSV) |
| GET | `reviews/` | `consultation_review.view_any` | Reviews by status |
| GET/PATCH | `reviews/<id>/` | `consultation_review.view_any/update` | Approve / reject |

## Dashboard

| Route | Who | Component (`dashboard/src/features/consultations/`) |
|---|---|---|
| `routes/_authed/catalogue.consultations.tsx` → `/catalogue/consultations` | office (`consultation.view_any`) | `ProductsAdmin`, `ProductDialog` |
| `routes/_authed/scheduling.consultations.tsx` → `/scheduling/consultations?view=list\|calendar\|reviews\|margins` | office (`consultation_request.view_any`) | `RequestsTabs`, `RequestsAdmin` (`RequestDialog`, `PaymentDialog`, `SlotPicker`), `ScheduleWeek`, `ReviewsAdmin`, `MarginsReport` |
| `routes/_authed/teaching.consultations.tsx` | teacher | `MyConsultations` |
| `routes/_authed/learning.consultations.index.tsx`, `.book.tsx`, `.$requestId.tsx` | student, parent | `FamilyConsultations`, `BookPicker` + `BookingWizard`, `ManagePage` |
| `routes/consult.$productId.tsx` → `/app/consult/<id>` | anyone (no sign-in) | `BookingWizard` |
| `routes/consult.manage.$token.tsx` → `/app/consult/manage/<token>` | token holder | `ManagePage` |

`ConsultantCard` (the opt-in switch) sits on `routes/_authed/people.teachers.$personId.tsx`.

**Marketing site.** `marketing/src/pages/[lang]/consultations/index.astro` and `[id].astro`, fed by
`marketing/src/lib/consultations.ts`. "Book" links to `/app/consult/<id>`.

## Background jobs

- `consultations.cancel_unpaid` (`backend/etqan/consultations/tasks.py`), every 15 minutes (Celery beat in
  `config/settings/base.py`). It runs `services.cancel_unpaid` in every academy through
  `platform.tenancy.for_each_academy` (non-atomic; each row commits on its own).

## Configuration

- Features: `consultations` (off by default). Self-booking also needs `online_payments`, and slot products also need
  `teacher_availability`. CSV export needs `export`. The margins estimate uses `exchange_rates`.
- Throttles: `consultation_book` 10/h, `consultation_manage` 60/min, `consultation_public` 60/min, plus `gateway_start`
  on pay.
- Constants in `services/common.py`: `HOLD` 30 min and `LEAD` 12 h. In `booking.py`: `HORIZON_DAYS` 31 and
  `PENDING_CAP` 3.
- The manage URL is built with `platform.frontend.app_url`. Payments go through `etqan.gateways`, purpose
  `consultation`.

## Code map

- `backend/etqan/consultations/models.py` and `slot_math.py` (pure slot arithmetic).
- `backend/etqan/consultations/services/__init__.py`: the public API.
- `services/{products,consultants,requests,transitions,payments,slots}.py`: office (B7c).
- `services/{booking,paying,purpose,manage,notices,unpaid}.py`: self-booking (B7d).
- `services/reviews.py`, `services/earnings.py` (B7f), and `services/reads.py` (`week_agenda` and finder reads
  `consultation_events` / `consultations_starting`).
- `backend/etqan/consultations/api/urls.py` (mounted at `consultations/` in `backend/config/api_router.py`).
- `dashboard/src/features/consultations/`, `marketing/src/lib/consultations.ts`.

## Design history

- [B7 add-on sales](../superpowers/specs/2026-10-08-b7-add-on-sales-design.md): the phase spec and its shared rules (B7-x).
- [B7c consultations: office](../superpowers/specs/2026-10-08-b7c-consultations-office-design.md). Plan: [plan 50](../superpowers/plans/2026-10-08-plan-50-consultations-office.md).
- [B7d booking and paying online](../superpowers/specs/2026-10-08-b7d-consultation-booking-design.md). Plan: [plan 60](../superpowers/plans/2026-10-09-plan-60-consultation-booking.md).
- [B7f consultation reports](../superpowers/specs/2026-10-08-b7f-consultation-reports-design.md). Plan: [plan 61](../superpowers/plans/2026-10-09-plan-61-consultation-reports.md).
