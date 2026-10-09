# Slice B7c — Consultations: office — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (PO-3); findings applied 2026-10-08. Spec-only mode (ledger D45).
**Phase:** B7, slice c (`2026-10-08-b7-add-on-sales-design.md` §3).
**Requires:** none from other phases beyond merged work. It needs B2e (teacher availability, merged) and
B3g (`billing.services.create_record`, merged).
**Evidence:** P1 CONS-001, CONS-002, CONS-003, CONS-004; FLOW-009; §8.4; BR-26, BR-27, BR-28; TH §2
CONS-001/002 (re-crawled fields). P1 §8.4 confirms the request statuses. How a teacher works with
consultations is unobserved (TH §4 U2).

## 1. Goal

The office sets up consultation products and names the teachers who take them. It records consultation
requests: who asked, which product, which teacher and when, picking from that teacher's free slots. It
confirms, reschedules, cancels and completes them, records attendance on both sides, and records money
paid by hand. Teachers see their own consultations, set the meeting link and record attendance.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| C-1 | **Product** (CONS-001). Cover image (optional, public, re-encoded, ≤ 5 MB). Name (`name_ar`, `name_en`, required, ≤ 120). Description (`description_ar`, `description_en`, plain text ≤ 5 000, at least one required). Price (`price_minor` > 0) and currency (B7-5). Duration in minutes (15–240). Booking validity in days (1–365). Participants (1–50). Delivery mode `video_call`, `live_chat` or `email`. Status `available` or `archived`. Enabled. Featured. Reschedulable. Fee (`fee_enabled`, default false). Teacher share in basis points (0–10 000, default 0; B7-11). Responsible teachers (at least one, each opted in, C-3). TutorHamster has one name with rich text; we use the catalogue's bilingual names, and plain text per D2. | P1 CONS-001; TH CONS-001; ledger D2 · [assumed] bilingual, limits, fee default |
| C-2 | **Bookable** means `available` and `enabled`. Archived or disabled products keep their requests and take no new ones (400 `product`). A product with any request cannot be deleted (409 `consultations.product_in_use`); archive it instead. | P1 §8.5 (available \| archived) · [assumed] |
| C-3 | **Teacher opt-in** (CONS-004, "هل يقدم استشارات"). This is a B7-owned row, `Consultant(teacher one-to-one TeacherProfile, offers bool, updated_by, updated_at)`, not a field on identity's profile (B7-1). Only teachers with `offers=true` can be added to a product (400 `teachers`) or picked for a new request (400 `teacher`). Turning it off keeps the teacher on existing products and requests, but they are not offered for new ones. The teacher page shows `<ConsultantCard teacherId />` (phase §4), a toggle for the office (`consultation.update`) that renders nothing while `consultations` is off. | P1 CONS-004, PEOPLE-005 settings tab · [assumed] storage |
| C-4 | **Request** (CONS-002). Reference: shown as `CR-<pk padded to 6>`. Person: a registered student (`student`, optional) or an unregistered person. The name (≤ 120), email and WhatsApp number (≤ 30) are required in both cases; for a student they are prefilled from the profile and stay editable. Timezone: the person's IANA zone, validated with `platform.validators.clean_timezone` (default: the student's `User.timezone`, which is never empty, since identity defaults it to UTC; the academy's zone for a person without an account). Product. Teacher (one of the product's responsible teachers). Start (`starts_at`, UTC; null for `email` delivery, B7-15). End (computed from the product's duration at the time). Meeting link (https, ≤ 500). Session status `scheduled`, `completed` or `absent`. Student and teacher attendance, each `not_set`, `present` or `absent`. Request status (C-6). Payment (C-9). Notes (≤ 2 000). | P1 CONS-002; TH CONS-002 (attendance present / absent / not started) · [assumed] optional student link, timezone default |
| C-5 | **Times.** The office picks a start from the teacher's **free slots** (B7-10): `GET products/<id>/slots/?teacher=<user id>&from=<date>&days=<1..31>[&request=<id>]` returns starts in academy time with their remaining capacity (B7-15). The teacher must be one of the product's teachers and opted in (400 `teacher`). `request` excludes that request's own place when it is moved, and applies its validity (C-10). The office's list has **no** 12-hour lead time; B7-10's lead time is B7d's (self-booking). The office may instead type any datetime, including a past one (recording what happened, as B2a A-14). The answer then carries `conflicts` (overlapping scheduling sessions or consultations of the teacher), `outside_availability` and `outside_validity` (C-10) as warnings. **The one refusal is capacity:** a start whose same-product, same-teacher, same-start group already holds `participants` live requests answers 409 `consultations.slot_full`. **Live** means `pending_review`, `confirmed` or `reschedule_requested`, plus B7d's unexpired holds. **Overlap rule:** a slot is blocked by any live consultation of the teacher that overlaps it, except those with the same product and the same start, which share its capacity instead. Scheduling sessions block when they overlap and are not `cancelled` (at-disposal and archived sessions block too: the teacher's time is still taken). They are read with `scheduling.services.sessions_queryset().filter(teacher_id=…, starts_at__gte=from − 240 min, starts_at__lt=to).exclude(status="cancelled")`, a string literal because consultations cannot import scheduling's models. Each session's end is computed in Python from its `minutes`. **Wall-clock steps:** a local start that does not exist (DST spring-forward) is skipped, and an ambiguous one uses `fold=0`. **Ids:** the API takes user ids. Services convert them with `identity.services.get_teacher_profile` / `teacher_profiles_for`, and windows and the lock use TeacherProfile ids. The slot picker hint is TutorHamster's: "Select a teacher first to see available slots". | P1 CONS-002, BR-28; spec b2e E-11 · [assumed] warnings |
| C-6 | **Request status machine** (P1 §8.4): `pending_review` → `confirmed` → `completed`. `pending_review`, `confirmed` and `reschedule_requested` may each go to `cancelled`. `confirmed` may go to `reschedule_requested` (the booker's ask, recorded by the office in B7c with a note; asked by the booker in B7d). That move needs a reschedulable product (409 `consultations.not_reschedulable`, BR-27). `reschedule_requested` goes back to `confirmed` either with a new start (`reschedule`) or without one (`decline-reschedule`, with a note). Confirming needs a start (except `email`) and a teacher. `delivery` and `complete` need `confirmed`. Cancelled and completed are final (409 `consultations.request_closed`). Each move stamps `confirmed_at`, `cancelled_at`, `reschedule_requested_at`, `rescheduled_at` or `completed_at`, which B5 reads (B7-9). | P1 §8.4, BR-27 · [assumed] cancel from confirmed, stamps |
| C-7 | **Changing the start.** There is one path: `PATCH` sets `starts_at` / `teacher` while `pending_review`. `POST reschedule {starts_at, teacher?}` moves a `confirmed` or `reschedule_requested` request and leaves or makes it `confirmed`, stamping `rescheduled_at`. BR-27 gates only the booker's request to move, never the office: the office may always move a start, so a paid request never has to be cancelled and re-created. The product cannot change once the request is paid (400 `product`); before that, the office may change it. | BR-27 · [assumed] |
| C-8 | **Delivery and completion.** Once the start has passed (`email`: once confirmed), the office or the request's teacher records both attendances and the session status (`completed` or `absent`). The office then completes the request, which needs a session status other than `scheduled`. A teacher may also complete their own request [assumed]. `email` requests take no attendance: `complete` sets their session status to `completed` itself. Completing also snapshots the product's `teacher_share_bp` onto the request, so B7f's margins do not move when a product's share changes later. The meeting link is prefilled from the teacher's `default_meeting_url` for `video_call` (B7-15). | P1 CONS-002, §8.4 sub-state (scheduled → completed \| absent) · [assumed] |
| C-9 | **Payment by hand** (B7-4). The "Record payment" action takes a billing manual method (`billing.services.MANUAL_PAYMENT_METHODS`; Telda and PayMob become `other` with the name in the reference), an amount (default the product price, > 0), a paid-on date, a reference and a transaction number. It locks the request row and, in the same atomic block, calls `billing.services.create_record(customer_type="student", student_id=<the student's **user id**>, …)`, or `customer_type="unregistered"` with name, email and phone when there is no student, with `currency=product currency, by=user`. A deactivated student makes billing answer 400 `student`; the office then records it for an unregistered customer by name. The request stores `payment_id`, `paid_method="manual"`, `billing_method` (the chosen method, for CONS-002's gateway filter and B7f), the amount, the currency, the transaction number and `paid_on` (a DateField). The route declares `consultation_request.update`. The view checks `payment.create` itself and answers 403 without it (the message names the payment permission), as B7a A-9 does. It also has `NotImpersonating` (D19). A request takes at most one payment: it is paid while `paid_method` is set (409 `consultations.already_paid`). This holds even if the billing payment is later deleted (`payment` becomes null) or refunded. Billing owns that money, and the list shows the billing status when the payment still exists. Confirming does not require payment: the list shows paid or unpaid. | P1 CONS-002 (payment ID, amount paid, gateway); B7-4; ledger D19 · [assumed] |
| C-10 | **Booking validity** (BR-26): once paid, the consultation should take place on or before `paid_on + validity_days`, compared in academy dates. For the office this is a warning (`outside_validity`) on the start and in the list. Self-booking (B7d) enforces it. | P1 BR-26 · [assumed] office warning only |
| C-11 | **Calendar** (`consultation_schedule`, B7-16). A week agenda of non-cancelled requests with a start, grouped by day in academy time, filtered by teacher and product. | P1 CONS-003 · [assumed] |
| C-12 | **Who sees what.** Admins pass, and staff need the codes (C-13). A teacher sees requests where they are the teacher. They may set the meeting link, record attendance and session status, and complete (C-8); nothing else (403). The teacher routes compose `[HasCode | (ReadOnly & IsTeacher), FeatureOn]` for reads, and `[HasCode | IsTeacher, FeatureOn]` for `delivery` and `complete`, where the service scopes a teacher to their own requests (404 otherwise; `IsTeacher` is `etqan.platform.permissions`'). A teacher's payload hides the payment fields and `notes`. Students and parents get 403 from these routes, as `HasCode` answers for any non-staff role. Their pages are B7d. A teacher asking for another teacher's request gets 404. | B7-6; `platform/permissions.py` HasCode |
| C-13 | **Access resources** (under the B7 marker), with `in_use` matching the routes. `consultation` ("Consultations" / "الاستشارات"): `view_any`, `create`, `update`, `delete`. `consultation_request` ("Consultation requests" / "طلبات الاستشارات"): `view`, `view_any`, `create`, `update`, `delete`. `consultation_schedule` ("Consultation schedules" / "مواعيد الاستشارات"): `view_any`. `consultation_review` is B7d's. | P1 permission keys `consultation`, `consultation::request`, `consultation::schedule` |
| C-14 | **Deleting a request** is allowed only while `pending_review` with no payment (409 `consultations.request_in_use`); otherwise cancel it. | [assumed] |
| C-15 | **The `consultations` switch** is flipped to built, `default=False`. Every route has `FeatureOn`. The slot picker also reads availability only while `teacher_availability` is on; while it is off, `slots/` answers an empty list and says so (`availability_off: true`). | B7-2, B7-10 |
| C-16 | **Read services for B5** (D39), each a fixed number of queries: `consultation_events(*, since, until) -> list[ConsultationEvent(kind 'created'\|'confirmed'\|'reschedule_requested'\|'rescheduled'\|'cancelled'\|'completed', request_id, product_name_ar, product_name_en, teacher_user_id, student_user_id\|None, name, email, whatsapp, timezone, starts_at\|None, at)]` for stamps in `[since, until)` (aware UTC), built from the C-6 stamps, and `consultations_starting(*, since, until)` for confirmed requests starting in the window. | ledger D29, D39 shape |

## 3. Data

```text
etqan.consultations.Product
  cover          ImageField blank (default storage, upload_to=consultations.files.cover_path)
  name_ar, name_en   CharField(120)
  description_ar, description_en   TextField(blank, max 5000)  CHECK not both empty
  price_minor    BigIntegerField  > 0
  currency       CharField(3)
  duration_minutes   PositiveSmallIntegerField 15..240
  validity_days  PositiveSmallIntegerField 1..365
  participants   PositiveSmallIntegerField 1..50
  delivery_mode  CharField(10) choices video_call | live_chat | email
  status         CharField(9) choices available | archived (default available)
  enabled, featured, reschedulable, fee_enabled   BooleanField
  teacher_share_bp   PositiveSmallIntegerField 0..10000 (default 0)
  teachers       M2M identity.TeacherProfile  related_name="+"
  created_at, updated_at

etqan.consultations.Consultant
  teacher        OneToOne identity.TeacherProfile  CASCADE  related_name="+"
  offers         BooleanField(default False)
  updated_by     FK AUTH_USER null SET_NULL; updated_at

etqan.consultations.Request
  product        FK Product PROTECT related_name="requests"
  teacher        FK identity.TeacherProfile PROTECT related_name="+"
  student        FK identity.StudentProfile null PROTECT related_name="+"
  name           CharField(120); email EmailField; whatsapp CharField(30)
  timezone       CharField(64)
  starts_at, ends_at   DateTimeField null   CHECK both null or both set, ends_at > starts_at
  meeting_url    URLField(500) blank
  session_status CharField(9) scheduled | completed | absent (default scheduled)
  student_attendance, teacher_attendance   CharField(7) not_set | present | absent
  status         CharField(20) pending_review | confirmed | completed | cancelled | reschedule_requested
  notes, reschedule_note   TextField(blank, max 2000)
  paid_method    CharField(6) blank choices "" | manual | stripe | paypal
  billing_method CharField(16) blank   (billing's manual method, C-9)
  payment        FK billing.Payment null SET_NULL related_name="+"
  amount_minor, fee_minor   BigIntegerField default 0;  currency CharField(3) blank
  transaction_number CharField(120) blank;  paid_on DateField null
  teacher_share_bp PositiveSmallIntegerField null   (snapshot at completion, C-8)
  created_by     FK AUTH_USER null SET_NULL
  created_at, confirmed_at, reschedule_requested_at, rescheduled_at, cancelled_at, completed_at
  indexes (teacher, starts_at), (status), (product, teacher, starts_at)
```

`Request` also gets B7d's fields (manage token, hold) in B7d's own migration.

## 4. Services and API (`/api/v1/consultations/`)

The services are `create_product`, `update_product` and `delete_product`; `set_consultant(teacher_user_id,
offers, by)`; `free_slots(product, teacher_user_id, start_date, days)` (B7-10, B7-15);
`create_request(...)` and `update_request(...)`; and `confirm`, `cancel`, `request_reschedule`,
`reschedule`, `decline_reschedule`, `record_delivery` (attendances, session status, link), `complete` and
`record_payment` (C-9). Each of these locks the request row, `record_payment` included. Any write that
sets or changes a start first takes a transaction-scoped advisory lock
`pg_advisory_xact_lock(hashtext('consultations.teacher.<schema>.<teacher profile id>'))`, its own
namespace (scheduling's lock is private), and only then counts places, so that two bookings cannot fill
the last place of a slot at once. Scheduling session writes never take it; they only cause warnings here.
Editing a product re-checks opt-in only for newly added teachers, and the error field is `teachers`. The read services are those of C-16.

| Route | Methods | Codes |
|---|---|---|
| `products/` | GET, POST | GET: any of `consultation.view_any`, `consultation_request.create`, `consultation_request.update` (a tuple); POST: `consultation.create` (multipart) |
| `products/<id>/` | GET, PATCH, DELETE | `consultation.view_any` / `.update` / `.delete` |
| `products/<id>/slots/` | GET | `consultation_request.create` or `.update` |
| `consultants/` | GET | `?offers=true` lists opted-in teachers; codes as the `products/` GET |
| `consultants/<teacher user id>/` | GET, PUT | `consultation.view_any` / `.update` |
| `requests/` | GET, POST | `consultation_request.view_any` / `.create`; teacher: GET own |
| `requests/<id>/` | GET, PATCH, DELETE | `.view` / `.update` / `.delete`; teacher: GET own |
| `requests/<id>/{confirm,cancel,request-reschedule,reschedule,decline-reschedule,complete}/` | POST | `.update`; the teacher may also call `complete` |
| `requests/<id>/delivery/` | POST | `.update`, or the request's teacher |
| `requests/<id>/payment/` | POST | `.update` + `payment.create`, `NotImpersonating` |
| `schedule/` | GET | `consultation_schedule.view_any` (`?week=YYYY-MM-DD&teacher=&product=`) |

List filters (CONS-002): product, teacher, session status, student attendance, teacher attendance, paid
method and billing method (the "gateway" filter), request status, from/to date. Every write answer for a start carries the C-5 warnings.

## 5. Screens

| Who | Where | What |
|---|---|---|
| Office | **Catalogue → Consultations** `/catalogue/consultations` (`consultation.view_any`, `consultations`) | Filters: delivery mode, featured, status. Columns: cover, name, price, duration, mode, teachers, status, enabled. The form has CONS-001's three tabs (details; booking: duration, validity, participants, mode, reschedulable, fee; teachers: an opted-in multi-select and the share). |
| Office | **Scheduling → Consultations** `/scheduling/consultations` (`consultation_request.view_any`) | The request list with the filters above. A dialog creates or edits a request in four sections, as CONS-002 has: person; consultation (product, then teacher, then the slot picker or free datetime, with warnings shown inline); session (link, session status, attendances); payment (read-only here; "Record payment" action). Actions for each C-6 move. A **Calendar** tab (`consultation_schedule.view_any`) shows the C-11 week agenda. |
| Office | Teacher page | `ConsultantCard` (C-3). |
| Teacher | **Teaching → My consultations** `/teaching/consultations` (role teacher, `consultations`) | Upcoming and past requests: person, product, start in academy and in the person's timezone, link editor, attendance and session status, complete. |

## 6. Seeds

`seed_b7` gains (the demo academy's `seed_dev.FEATURES` already holds every built feature, so `consultations` is on there):
the demo teacher opted in; two products ("Placement consultation", video call, 30 min,
1 500 USD minor, share 5 000 bp; "Written question", email, 2 000 USD minor); and three requests, one each
of pending_review, confirmed (paid by hand, `cash`) and completed (present on both sides).

## 7. Tests

- **Products.** C-1 limits. Opted-in teachers only. Archive versus delete.
- **Slots.** Windows stepped by duration. No lead time for the office. The DST skip and `fold=0`. Validity for a paid request passed as `request=`. The request's own place excluded when it is moved. Same-product overlapping starts blocking. `slot_full` 409. Overlap with
  scheduling sessions (non-cancelled only) and with other products' consultations. Capacity sharing for
  the same product, teacher and start. Academy timezone and DST edges. An empty answer when
  `teacher_availability` is off or the teacher has no windows. The advisory lock under concurrency (two
  takers for one place).
- **Requests.** Every C-6 transition, allowed and refused, with its stamps. Reschedule gated by the
  product. Email mode without a start. The delivery rules for times and roles. Completion needing a
  session status. Deletion rules. Payment recording: a billing record with student or unregistered
  customer, one payment only, 403 without `payment.create`, impersonation refused.
- **Access.** The C-13 matrix (`in_use` equality). Teacher scoping (own only; 403 on office actions).
  404 for others. The switch off gives 404.
- **Read services.** `consultation_events` and `consultations_starting` windows, and their query counts.
- **Contracts.** `etqan.consultations` reaches scheduling, identity, academy and billing only through
  their services.
- **Dashboard.** The product form tabs, the request dialog (teacher-first slot picker, warnings, status
  actions), the calendar week navigation, the teacher page, the ConsultantCard, the hidden nav when off,
  and ar/en key equality.
- **e2e** (`e2e/b7-consultations-office.spec.ts`): the office opts the demo teacher in, creates a product,
  creates a request by picking a free slot, confirms it and records a cash payment. The teacher records
  attendance, and the office completes the request.

## 8. Non-goals

- Online booking and payment, the manage page, reschedule requests by the booker, and reviews: B7d.
- Reports and CSV exports, including profit margins: B7f.
- Video meetings created automatically (Zoom): the integrations work (D42) and B2's session-meeting
  work own that. B7c stores a link.
- Notifications (B7-9).
