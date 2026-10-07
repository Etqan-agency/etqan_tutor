# Phase B7 — Add-on sales — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); the review's findings were applied on 2026-10-08. Written in spec-only mode (ledger D45).
**Phase:** B7 of `2026-09-24-parity-roadmap-design.md` §2: recorded courses (playlists, videos, enrolment, watch
tracking, comments, reviews) and consultations (products, slot booking, payments, rescheduling, profit
margins) (RC-001…005, CONS-001…004, FLOW-009, BR-26…28, EXP-002 consultation exports). Depends on B3
(gateways). B3's phase spec is recorded. B3b, B3c and B3g are merged. Only B7g needs unmerged slices (§3).
**Works under:** `2026-10-02-parallel-orchestration-design.md` (ledger, slices, merge queue, ownership).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (cited `P1 §x` / IDs) and
`docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (cited `TH §x`). R7 is dropped (ledger D1). Anything the
audits do not show is marked `[assumed]`. The audits show only the admin screens for RC and CONS. The
student panel is unobserved (TH §4 U2), so every student-facing behaviour here is `[assumed]`.

This document holds two specs. §1–§4 are the phase spec: how B7 splits into slices and the decisions every
slice shares. §5–§12 are the first slice's spec, **B7a — recorded courses: catalogue, enrolment and
watching**. Each later slice gets its own spec file, designed against this one.

## 1. Goal

Let an academy sell two things besides tutoring subscriptions:

- **Recorded courses.** Ordered video playlists that a student buys once (or gets free, or is enrolled in
  by the office), watches at their own pace, and comments on and reviews.
- **Paid consultations.** One-off timed sessions with a responsible teacher. A person books a free slot of
  that teacher and pays online or by hand. The office confirms the booking, records attendance, and may
  reschedule it. The office exports what each teacher earned and what the academy kept.

Every feature is a per-academy switch, off by default (PO-5), so each slice merges on its own.

## 2. Phase decisions

| # | Decision | Source |
|---|---|---|
| B7-1 | **Two new tenant apps**, both owned by B7 and added to `TENANT_APPS` under the `── phase B7 ──` marker: **`etqan.recorded`** (recorded courses) and **`etqan.consultations`**. They point at other apps' models only through string foreign keys (`identity.StudentProfile` / `TeacherProfile`, `billing.Payment`). They read other apps only through those apps' `services`, which an import-linter contract per app enforces (§4). B7 changes no model in another app; it sends requests instead (§4). The app is named `recorded`, not `courses` or `videos`. This avoids confusion with `catalogue.Course` and with B8's site `Video` and its access resource `video`. | orchestration §4.3 (new areas in new apps); B6-1 precedent |
| B7-2 | **Switches.** The registry's `_later` lines `recorded_courses` and `consultations` are flipped in place to built, `default=False`. No new switch is added: TutorHamster gates each whole vertical with one flag (P1 §16 "flags": `نظام الكورسات المسجله` covers playlists, videos, RC subscriptions, comments and reviews; `نظام الاستشارات` covers consultations and the teacher opt-in). Turning a switch off hides everything under it and keeps every record (FT-4). Paying online also needs `online_payments` (B3b). CSV exports also need `export` (Plan 13). | PO-5; P1 §16; spec 2026-09-30 FT-2/FT-4 |
| B7-3 | **Online money goes only through `gateways.services`**, under purposes B7 registers in each app's `AppConfig.ready()`: `recorded_course` (B7b, signed-in buyers only, `public=False`) and `consultation` (B7d, `public=True`, so a visitor with no account can book from the public site). **A checkout's `reference_id` is always a B7-owned pending row**, never a product id. The B7b row is `recorded.Purchase(playlist, student, amount_minor, currency, created_by, status)`. The B7d row is the consultation booking itself. Each row holds the price snapshot and who the sale is for, because `CompletedCheckout` carries neither a user nor params. **`prepare`** reads only that row. It refuses with 404 while the switch is off, or when the caller may not pay for the row: for a purchase, the caller must be the student or a parent of the student (`identity.services.is_parent_of`); for a booking, the caller must present the booking's manage token, which gateways' public routes build from the URL, or `RECHECK`, as payment links do (D28). It refuses with 409 when the sale can no longer apply (already enrolled, booking cancelled, slot gone). It never reads request data. The checkout's `description` holds no personal data. **The fee:** `recorded_course` returns `add_fee=True, use_switch=True` (the academy's fee switch decides, as for invoices). `consultation` returns `add_fee=product.fee_enabled, use_switch=False`, so CONS-001's "5 % fee" toggle decides, at the academy's `fee_basis_points` rather than a fixed 5 % (D28, BR-26). A sale whose net price is 0 never starts a checkout: it takes the free path. | ledger D4, D13, D17, D28, D30; P1 BR-26 |
| B7-4 | **A sale is revenue, recorded with the B7 row in one step.** Each B7 `complete` runs one `transaction.atomic()` block. In it, it re-reads and locks its own row and records the money as a billing standalone payment record through the existing `billing.services.record_link_payment(...)`: student profile pk when there is one, else the buyer's name (stripped, truncated to 120, never empty), email (validated) and phone (truncated to 30); `amount_minor` and `fee_minor` from the `CompletedCheckout`; method = provider; transaction number; `notes` naming the sale, truncated to 500 (for example "Recorded course: <title>"). It then applies the sale: it enrols the student, or confirms the payment on the booking, and stores the payment id. The B7 row stores the amount without the fee; revenue is amount + fee (D16). **When the sale can no longer apply** (already enrolled, booking cancelled, product off), B7 records nothing and returns `Applied(ok=False, reason=…)`. The checkout then shows "needs attention" in gateways, and the office settles it by hand, as with a closed payment link (B3g). A `transaction_number` refusal or an `IntegrityError` on `billing_payment_transaction_unique` returns `Applied(ok=False, reason="already_recorded")`. Any other billing refusal returns `Applied(ok=False)` and is logged by field only. Revenue, the payments list and the receipts therefore include B7 sales with no change to billing (D5, D16). **Money received by hand** (CONS-002's Manual, Zelle, InstaPay, Telda, PayMob; B7a's manual enrolment) is recorded in billing in the same request. The B7 form takes a billing manual method (`billing.services.MANUAL_PAYMENT_METHODS`; Telda and PayMob are `other` with the name in the reference), a paid-on date and a reference. B7 calls `billing.services.create_record(customer_type="student", …, by=user)` and stores the payment id, so a hand sale cannot be left out of revenue. Recording a hand sale therefore also needs `payment.create`. A refund is marked on the billing payment (B3-10). It does not by itself revoke an enrolment or cancel a booking; the office does that. | ledger D5, D16, D36; P1 BR-47; B3-10; `billing/services/link_purpose.py` (same refusal mapping) · [assumed] link to billing |
| B7-5 | **Prices** are integer minor units plus a currency per product. The currency defaults to the academy's `default_currency`. TutorHamster prices consultations "in USD" only; we let each product choose its currency. Country prices (B3d) do not apply to B7 products. | CLAUDE.md money rule; P1 CONS-001 · [assumed] currency per product |
| B7-6 | **Who does what.** The office manages everything. A **student** sees, buys, watches and reviews only their own. A **parent** sees their children's enrolments and bookings, and buys or books for a child; they do not watch or comment for the child. A **teacher** sees and records attendance only on consultations assigned to them, and nothing in recorded courses. A **visitor** may browse published products and book a consultation (B7d). Anyone else gets 404 on a record, as Plan 5 scoping does. | P1 §5.4, CONS-002 (teacher on the request); TH §4 U2 · [assumed] student/parent/teacher rights |
| B7-7 | **No uploaded HTML runs on the academy origin** (D2). Descriptions, terms and comments are plain text, rendered with line breaks. Link videos embed only YouTube and Vimeo, from IDs parsed and validated on the server, through a fixed iframe template. Any other URL opens in a new tab and is never embedded. | ledger D2 |
| B7-8 | **Files.** Thumbnails, covers and the intro video are public marketing media on the default storage: images through `etqan.platform.uploads.check_upload` (re-encoded), intro video MP4 ≤ 100 MB (BR-39). Lesson video files are **private** (`STORAGES["private"]`). An authenticated endpoint that applies B7-6 serves them. With a dedicated private S3 bucket (`PRIVATE_STORAGE_SHARED_WITH_PUBLIC` false) it answers a 302 to a signed URL valid for 10 minutes, so S3 handles range requests and seeking. Otherwise it streams the file itself and honours a single `Range: bytes=a-b` header (206), so seeking works. That covers local storage, and the fallback where private files sit under an unlisted prefix of the public-read bucket: there a URL must never be handed out, because the object key is the only protection. | ledger D12; P1 BR-39; spec platform-extras A-10; `config/settings/production.py` (W901 fallback) · [assumed] signed-URL serving |
| B7-9 | **B7 sends no notifications of its own.** Booking, payment and reminder notices are B5's (D39). B5 builds them as finders over the read services each B7 slice exports. The one exception is the booking's own manage link, sent to a visitor who has no account (B7d). That is a transactional email sent with `identity.services.send_notice`, like B9c's registration emails. | ledger D39; spec 2026-10-03-b9c |
| B7-10 | **Consultations are not scheduling sessions.** They live in `etqan.consultations` with their own time, link, statuses and attendance (CONS-002). **Slots** are computed for one product and one teacher. A slot is a start inside one of the teacher's B2e availability windows (`scheduling.services.windows_of`, academy time), stepped by the product's duration, with the whole duration inside the window. It is at least 12 hours ahead and no later than the product's validity window (B7d). It is removed when it overlaps the teacher's non-cancelled scheduling sessions (read through `scheduling.services.sessions_queryset`) or the teacher's live consultations of other products. **Self-booking (B7d) needs `teacher_availability` on.** A teacher with no windows offers no self-bookable slots, since `windows_of` is empty and `is_available` is `None`. The office (B7c) may pick any datetime and sees overlaps as warnings, never blocks, as B2e E-11 does. Scheduling's own conflict warnings do not see consultations. | P1 CONS-002 (own session status and attendance), BR-28; spec 2026-10-03-b2e E-9…E-11 · [assumed] separate model, lead time, step |
| B7-15 | **Participants and delivery mode** (CONS-001). `participants` is the capacity of one slot: up to N live bookings may share the same product, teacher and start. A slot is offered while it has room. Delivery mode `video_call` gets a meeting link (prefilled from the teacher's `default_meeting_url`, editable by the office and the teacher). `live_chat` gets a slot and an optional link. `email` has no slot and no link: the booking is answered by the teacher by email, and is confirmed and then completed with no attendance. | P1 CONS-001, CONS-002 · [assumed] meanings |
| B7-16 | **CONS-003.** The audit shows only the permission groups `consultation::review` and `consultation::schedule`; their UI is unknown. We read `review` as the booker's 1–5 star rating and comment on a completed consultation (B7d), moderated by the office, and `schedule` as the office's calendar of booked consultations (B7c). Both are access resources, `consultation_review` and `consultation_schedule`. | P1 CONS-003 · [assumed] |
| B7-17 | **Anonymous booking safeguards (B7d).** Visitors start through B7d's own anonymous endpoints, which create the booking and start its checkout. The generic `checkouts/start/` route is for signed-in users only. B7d's spec checks whether `start_checkout` accepts an anonymous caller for a public purpose (the payment-link start does), and files an additive request to B3 if it does not. A pending booking holds its slot for 30 minutes on its own expiry, independent of the checkout's reuse window. After that the slot is free again, and a late payment for it becomes "needs attention" under B7-4. The start is throttled per IP. One email or IP may hold at most 3 pending bookings. | ledger D17, D28; `gateways/services/checkouts.py` REUSE_FOR · [assumed] limits |
| B7-11 | **Teacher earnings from consultations are not payroll.** Each consultation product has a teacher share in integer basis points (0–10 000). Per completed consultation, the teacher's share is `amount_minor` (without the fee) × share / 10 000, rounded half up to a whole minor unit. The academy's margin is the amount less that share. Totals are summed per currency, never across currencies. The profit-margin report (B7f) shows, per teacher and currency, completed consultations, the amount received, the teacher's share and the academy's margin. Paying the teacher stays a manual office act. B4 may later read `consultations.services.teacher_earnings(...)` to add those earnings to payslips; that is B4's decision. | P1 CONS-002 ("export teacher profit margins"), FLOW-009 · [assumed] share model |
| B7-12 | **Codes and certificates come from their owners.** An activation code for a recorded course (RC-003 "payment method: activation code") is a new voucher kind owned by B3 (D44): B7 asks B3 for it. A recorded-course certificate (playlist "accredited certificate", RC-003 "certificate obtained") is a learning certificate owned by B6 (D33): B7 asks B6 for an additive change. Both are B7g, written once B3f and B6d are merged. | ledger D33, D44 |
| B7-13 | Dashboard code lives in `src/features/recorded/` and `src/features/consultations/`. Office pages: `/catalogue/recorded…` and `/catalogue/consultations…`. Student and parent pages go under `/learning/…`, teacher pages under `/teaching/…`. Strings go in new area files `recorded.json` and `consultations.json` (en and ar, D11/D22). The public storefront pages are marketing pages (B7b, B7d) that read new anonymous `site`-style endpoints of the B7 apps. | B6-11 precedent; nav.ts `NavGroup`; ledger D11, D22 |
| B7-14 | New columns go only on B7's own new tables. No B7 migration touches an existing table. | orchestration §8.2; B6-10 precedent |

## 3. Slices

Each slice is its own spec → plan → build → queue cycle.

| Slice | Topic | Contents | Audit IDs | Switches | Requires | Size |
|---|---|---|---|---|---|---|
| **B7a** | recorded courses: catalogue, enrolment, watching | `etqan.recorded`. Office: playlists (RC-001 fields), videos (link / file / live; order; draft / published / hidden; downloadable), enrolments recorded by hand (RC-003: student, amount, method, transaction number, notes, watched videos). Student: "My recorded courses" with a player, marking a video watched, and progress. Parent: read-only view of a child's courses and progress. | RC-001, RC-002, RC-003 (manual), BR-39 | `recorded_courses` (flipped) | — | M–L |
| **B7b** | selling recorded courses | Storefront for students and parents in the dashboard: published, not app-only playlists, with price, discount, intro video and terms. Free enrolment. Buying online through purpose `recorded_course` (Stripe or PayPal); the sale is recorded in billing (B7-4). The return page's branch for the purpose. An anonymous listing endpoint and a marketing "Recorded courses" page with a detail page that links to sign-in or registration to buy. | RC-001 (price, discount, app-only), RC-003 (online methods) | `recorded_courses` (+ `online_payments` to pay online) | — (B3b/B3c/B3g merged) | M |
| **B7c** | consultations: office | `etqan.consultations`. Products (CONS-001: cover, name, description, price, duration, validity days, participants, delivery mode, status, enabled, featured, reschedulable, fee toggle, responsible teachers, teacher share). The teacher opt-in "offers consultations" (CONS-004) as a B7-owned row per teacher with a card on the teacher page. Requests created by the office (CONS-002): person, product, teacher, free-slot picker, link, statuses (§8.4 machine), both attendances, rescheduling, manual payment details. Teacher view: "My consultations" with the link and attendance marking. The office's calendar of booked consultations (`consultation_schedule`, B7-16). Hand payments recorded in billing (B7-4). | CONS-001, CONS-002, CONS-003 (schedule), CONS-004, BR-27, BR-28, P1 §8.4 | `consultations` (flipped) | — (B2e merged) | L |
| **B7d** | consultations: booking and paying online | Booking by a signed-in student or parent, and by a visitor from a public marketing page (name, email, WhatsApp, their timezone). Pick a teacher, then a free slot. Pay through purpose `consultation`. A slot is held while the checkout is pending. Booking validity (BR-26: the slot must fall within N days of payment). The manage page (by unguessable token, emailed to visitors, B7-9). Reschedule request when the product allows it (BR-27). Consultation reviews (CONS-003, B7-16) after completion. The anonymous safeguards of B7-17. | CONS-002, CONS-003 (review), FLOW-009, BR-26, BR-27 | `consultations` + `teacher_availability` for self-booking (+ `online_payments` to pay online) | — | L |
| **B7e** | recorded courses: comments and reviews | Comments on a video by enrolled students, with office replies and hide or delete (RC-004). One review per enrolment, 1–5 stars and text, shown on the storefront with the average once the office approves it (RC-005). | RC-004, RC-005 | `recorded_courses` | — | S–M |
| **B7f** | consultation reports | The consultation requests report CSV and the teacher profit-margin report: screen and CSV, per teacher and currency, for a date range, with the same filters as the list (CONS-002 header actions, EXP-002). `consultations.services.teacher_earnings(...)` for B4. | CONS-002 (exports), EXP-002 | `consultations` + `export` (CSV) | — | S |
| **B7g** | recorded-course certificates and activation codes | Certificate on completion (all published videos watched) for playlists with "accredited certificate". The enrolment's "certificate obtained" flag. Activation codes that enrol a student in a playlist (RC-003 method "activation code"), redeemed by the student. Requests to B6 (an additive certificate change) and to B3 (a new voucher kind), written when this slice's spec is written. | RC-001 (certificate), RC-003 (activation code, certificate obtained) | `recorded_courses` (+ `certificates`, `system_codes`) | B6d, B3f | M |

The build order is B7a, B7b, B7c, B7d, B7e, B7f, B7g. Recorded courses come first because their evidence
is the most complete (RC-001/002/003 are CONFIRMED field lists). B7g comes last because it waits on two
other phases.

Not taken by any B7 slice, with the reason:

- **AI content generation** for a playlist's content (RC-001 "content (AI)") belongs to B10. B7a stores the
  content as plain text.
- **Gateways other than Stripe and PayPal** (Zelle, InstaPay, Telda, PayMob in CONS-002's gateway list) are
  never called online. They are hand-recorded payment methods (B7-4). B3d's local methods cover how a
  family is told to pay that way.
- **Live-stream hosting.** A "live stream" video is a link to an external live page (YouTube Live, Zoom).
  Etqan hosts no streams (roadmap §3, "built-in video: out").
- **Apps.** The playlist's "show in app only" flag is stored and keeps the playlist off the web storefront
  (B7b). The apps themselves are B11.
- **Wallet payment for B7 products.** Not observed (BILL-007 names only invoices). Left out `[assumed]`.

## 4. Shared lists, ownership and requests

- B7 adds lines only under its `── phase B7 ──` markers. That covers `TENANT_APPS` (both apps),
  `config/api_router.py` (`recorded/` in B7a, `consultations/` in B7c), the feature registry (it flips its
  two `_later` lines in place), the access `RESOURCES`, `seed_academy` (`seed_b7(subdomain)` from
  `etqan/tenants/seeds/b7.py`), `pyproject.toml` (the platform contract's forbidden list, plus one contract
  per app) and the dashboard's `NAV_ITEMS`. The `FeatureCode` union in
  `dashboard/src/features/identity/schemas.ts` gains the two codes.
- **Contracts** follow the gateways pattern (`pyproject.toml`, "gateways reaches other apps only through
  services"). The `etqan.recorded` contract forbids whole apps: `etqan.identity`, `etqan.academy`,
  `etqan.billing`, `etqan.gateways`, `etqan.catalogue`, `etqan.scheduling`, `etqan.tenants`, `etqan.site`,
  `etqan.notifications`, `etqan.access`, `etqan.payroll`, `etqan.finance`, `etqan.learning`,
  `etqan.consultations`. It then whitelists `etqan.recorded.** -> etqan.<app>.services` for identity,
  academy, billing and gateways, plus learning and vouchers in B7g. The `etqan.consultations` contract is
  the same with scheduling's services allowed and recorded forbidden. Both contracts have
  `allow_indirect_imports = true` and `ignore_imports` entries for their tests' fixtures, as B6's contract
  does.
- **"gateways imports no business app"** lists its apps explicitly. The slice that registers a B7 purpose
  (B7b, B7d) adds its app to that list in one commit, under a ledger `claim` on `pyproject.toml`'s
  gateways contract, then releases it.
- **Shared dashboard files outside B7's folders.** The gateways return page
  (`features/gateways/ReturnPage.tsx`) gets one "back to" branch per B7 purpose (B7b, B7d), next to the
  merged `invoice` branch. It is a one-commit change under a ledger `claim` on the file, released after the
  commit, because B3 is still active.
  The teacher page gets one line rendering `<ConsultantCard teacherId />`, exported from
  `@/features/consultations` (B7c). That card hides itself while `consultations` is off.
- New e2e specs are `e2e/b7-*.spec.ts`.
- **Requests (filed when the slice's spec is written):** R-B7g-1 to B6, an additive certificate for a
  playlist. R-B7g-2 to B3, a voucher kind that enrols a student in a playlist. None is needed before B7g.
- **For B5 (D39):** B7c and B7d each export windowed read services (shaped like D29's
  `homework_events(*, since, until)`) for booking, confirmation, reschedule and reminder notices. Each
  slice's spec names its own.

---

# Slice B7a — Recorded courses: catalogue, enrolment and watching

## 5. B7a decisions

| # | Decision | Source |
|---|---|---|
| A-1 | **Playlist** fields (RC-001). Thumbnail (required; JPEG, PNG or WEBP ≤ 2 MB, shown at 400×225 and stored as uploaded after the re-encode). Intro video (optional, MP4 ≤ 100 MB). Title (required, ≤ 160). Slug (required, unique, `[a-z0-9-]`, ≤ 80). Description (required, plain text ≤ 2000). Code (required, unique, ≤ 40, upper-cased). Content language (required: `ar`, `en`, `ur`, `tr`, `fr`, `es`). Price (`price_minor` ≥ 0; 0 means free). Discount (`discount_minor`, 0 ≤ discount ≤ price). Currency (defaults to the academy currency, B7-5). Content (plain text ≤ 20 000). Terms and conditions (required, plain text ≤ 10 000). Published flag. Certificate flag (stored now, used in B7g). App-only flag (stored now, used in B7b). | P1 RC-001; TH §2 RC-001 (tabs basic, course details, content, terms, publishing) · [assumed] limits, discount as an amount |
| A-2 | **Total hours and lesson count are computed** from the playlist's published videos: their count and the sum of their durations. TutorHamster has the office type both numbers. We compute them because every video has a required duration, so typed numbers could only drift from the truth. | P1 RC-001, RC-002 (duration required) · [assumed] deviation |
| A-3 | The playlist's **title, description, content and terms are single-language**, written in its content language, as TutorHamster has them (one title, one content language). Labels around them follow the reader's UI language. | P1 RC-001 · [assumed] |
| A-4 | **Video** fields (RC-002). Playlist (fixed once set). Thumbnail (optional, as A-1; the playlist's thumbnail shows when it is missing). Code (required, unique within the playlist). Title (required, ≤ 160). Slug (required, unique within the playlist). Type: `link`, `file` or `live`. URL (required for `link` and `live`, https only). File (required for `file`, private MP4 ≤ `RECORDED_VIDEO_MAX_MB`, a setting with default 100, the same limit as BR-39's intro video). Uploads pass through a gunicorn sync worker (3 workers, 30 s timeout, `backend/Dockerfile`), so long lessons are expected to be link videos (unlisted YouTube or Vimeo). Raising the cap is an infrastructure change and is not part of B7. Duration (required, 1 second to 24 hours, entered and shown as HH:MM:SS). Position. Description (plain text ≤ 2000). Status: `draft`, `published` or `hidden`. Downloadable flag (`file` only). | P1 RC-002, §8.5 (draft → published \| hidden) · [assumed] size cap, https only, optional thumbnail |
| A-5 | **Link and live URLs.** On save the server classifies the URL as YouTube (`youtube.com/watch?v=`, `youtu.be/`, `/embed/`, `/live/`: an 11-character id), Vimeo (numeric id), or external. It stores `embed_provider` and `embed_id`. The player embeds only YouTube and Vimeo (B7-7). An external URL is shown as an "Open video" button. | ledger D2 · [assumed] |
| A-6 | **Status.** Only `published` videos are visible to students and count towards lesson count, hours and progress. `draft` means not ready yet. `hidden` means withdrawn. A student's watch records of a hidden video are kept and come back if the video is published again. | P1 §8.5 · [assumed] meaning of hidden |
| A-7 | **Order.** Videos have a dense 0-based `position` within the playlist. The office moves a video up or down (`playlist_video.reorder`). A new video goes last. | P1 RC-002 ("order\*") · [assumed] dense positions as B6a levels |
| A-8 | **Enrolment** (TutorHamster's "RC subscription", RC-003). Fields: playlist, student, amount paid (`amount_minor` ≥ 0) and currency (the playlist's at the time), method (`manual`, `free`, `stripe`, `paypal` or `code`), transaction number (≤ 120, may be blank for `manual` or `free`), billing payment id (null for office-recorded enrolments, B7-4), certificate-obtained flag (B7g), notes (≤ 2000), status `active` or `revoked`, who enrolled the student and when, who revoked and when. At most one **active** enrolment per student and playlist (409 `recorded.already_enrolled`). Access does not expire. | P1 RC-003 (playlist, student, amount, method, transaction number, certificate obtained, watched videos, notes) · [assumed] status and revoke, no expiry, manual and free methods |
| A-9 | **The office enrols by hand.** Method is `manual` or `free` (`stripe`, `paypal` and `code` are set only by B7b and B7g, through `enrol_from_sale`, an internal service no API route reaches). `free` forces the amount to 0 and creates no billing record. A `manual` amount must be > 0. In the same transaction it creates a billing standalone record (B7-4) with: `billing_method` (one of `MANUAL_PAYMENT_METHODS`, required), `paid_on` (default today), `reference` (optional), the transaction number and the student. The enrolment stores that payment's id. A manual enrolment therefore also needs `payment.create`: without it the route answers 403 `recorded.payment_code_required`. An enrolment may be in a draft playlist (the office prepares a course ahead of time); the student sees it only once the playlist is published. | B7-4 · [assumed] |
| A-10 | **Revoke, don't delete.** The office revokes an enrolment (it keeps the row and its watch history), and may later restore it unless another active enrolment for the same student and playlist exists (409). An enrolment can be deleted only if it is `manual` or `free` and has no watch records (409 `recorded.enrolment_in_use`). | [assumed] keep history, as B6a C-2 |
| A-11 | **Watched videos** (RC-003 "watched videos"). One row per enrolment and video, with when it was watched. The student marks a video watched or unwatched. The player also marks it on its own when a `file` video plays to its end. Embedded and external videos are marked by the student. The office can edit the watched set from the enrolment page (the RC-003 multi-select). Progress is the number of watched **published** videos over the number of published videos. | P1 RC-003 · [assumed] how a video becomes watched |
| A-12 | **Deleting.** A playlist with any enrolment cannot be deleted (409 `recorded.playlist_in_use`); unpublish it instead. A video with any watch record cannot be deleted (409 `recorded.video_in_use`); hide it instead. Deleting a video or playlist deletes its files after commit. | [assumed]; B6a C-2 precedent |
| A-13 | **Who sees a playlist.** The office sees all of them. A student sees a playlist they hold an active enrolment in, once it is published, with its published videos. A parent sees the same for each child, read-only. Lesson files and marking a video watched answer **403** to a parent; this differs from the 404 that anyone else gets, because the parent may see the record. The storefront (browsing unenrolled playlists) is B7b. | B7-6 · [assumed] |
| A-14 | **Lesson files** are streamed or redirected (B7-8) only to the office and to the enrolled student, while the enrolment is active, the playlist is published and the video is published. A request for a file that is not downloadable is served with `Content-Disposition: inline`. Only a downloadable file gets the "Download" action, which uses `?download=1` and `attachment`. Students can still save an inline stream; the downloadable flag controls the offer, not access. | P1 RC-002 ("downloadable") · [assumed] |
| A-15 | **Access resources** (new, under the B7 marker). `in_use` lists exactly the codes §9 declares. `playlist` ("Recorded courses" / "الدورات المسجلة"): `view`, `view_any`, `create`, `update`, `delete`. `playlist_video` ("Recorded course videos" / "فيديوهات الدورات المسجلة"): `view_any`, `create`, `update`, `delete`, `reorder`. `rc_enrolment` ("Recorded course enrolments" / "اشتراكات الدورات المسجلة"): `view`, `view_any`, `create`, `update`, `delete`. Admins always pass. Staff need the codes. Students and parents pass by role and A-13 scoping, never by codes. | `etqan/access/registry.py`; P1 permission keys `play::lists`, `playlist::videos`, `rc::subscriptions` |
| A-16 | `recorded_courses` is flipped to built, `default=False`, in place. The check comes after the role check (`[…, FeatureOn]`): a caller who passes the role check gets 404 while it is off, and a caller who fails it gets 403 either way. The demo academy's seed turns it on (`seed_dev.FEATURES`) and seeds two playlists (one free, one paid) with link videos and a demo student's enrolment. | B7-2; spec 2026-09-30 FT-4, §7 |

## 6. B7a screens (dashboard)

| Who | Where | What |
|---|---|---|
| Office | **Catalogue → Recorded courses** `/catalogue/recorded` (nav, group `catalogue`, `playlist.view_any`, `recorded_courses`) | List: thumbnail, title, code, language, price (with discount struck through), lessons, hours, published, enrolments count. Filters: published, language, has discount, search (title or code). Add, edit and delete. |
| Office | **Recorded course** `/catalogue/recorded/$playlistId` | Tabs, following RC-001's five tabs folded into three: **Details** (the form in sections basic, course details, content, terms, publishing; save), **Videos** (ordered table: thumbnail, title, type, duration, status, downloadable; move up and down; add and edit in a dialog with a type-dependent URL or file field; delete; filters status and downloadable), **Enrolments** (student, method, amount, enrolled on, progress n / total, status; filters method and status; add enrolment dialog with student picker, method `manual`/`free`, amount, and for `manual` the billing method, paid-on date, reference and transaction number, plus notes; a hint says a manual enrolment is also recorded as a payment; open an enrolment). |
| Office | **Enrolment** dialog | Fields as A-8, and the watched-videos multi-select (searchable, published and hidden videos). Revoke or restore. Delete when allowed (A-10). |
| Student | **Learning → My recorded courses** `/learning/recorded` (role student, `recorded_courses`) | Cards: thumbnail, title, progress bar n / total. |
| Student | **Course player** `/learning/recorded/$playlistId` | Sidebar of published videos in order, each with a watched tick and its duration. The main pane shows the selected video: an embedded YouTube or Vimeo iframe, a native `<video>` for `file` (marked watched on `ended`), or an "Open video" button for an external link or live stream. Below it: title, description, a "Mark as watched" toggle, and "Download" when allowed. The terms and the course content are in a collapsible panel. RTL-safe, phone width. |
| Parent | `/learning/recorded` and `/learning/recorded/$playlistId` (role parent) | The same pages with a child picker, read-only: no player, the video list shows watched ticks only. |

## 7. B7a data

```text
etqan.recorded.Playlist
  thumbnail        ImageField  (default storage, upload_to=recorded.files.thumb_path)
  intro_video      FileField   blank  (default storage, upload_to=recorded.files.intro_path)
  title            CharField(160)
  slug             SlugField(80) unique
  description      TextField(max 2000)
  code             CharField(40) unique
  content_language CharField(2) choices ar | en | ur | tr | fr | es
  price_minor      BigIntegerField  >= 0  (default 0)
  discount_minor   BigIntegerField  >= 0  (default 0)   CHECK discount_minor <= price_minor
  currency         CharField(3)  [A-Z]{3}
  content          TextField(blank, max 20000)
  terms            TextField(max 10000)
  is_published     BooleanField(default False)
  certificate      BooleanField(default False)
  app_only         BooleanField(default False)
  created_at, updated_at
  ordering (-created_at, id)

etqan.recorded.PlaylistVideo
  playlist         FK Playlist  CASCADE  related_name="videos"
  thumbnail        ImageField  blank
  code             CharField(40)
  title            CharField(160)
  slug             SlugField(80)
  kind             CharField(4) choices link | file | live
  url              URLField(500) blank
  embed_provider   CharField(7) blank choices "" | youtube | vimeo
  embed_id         CharField(20) blank
  file             FileField  blank  (storage=recorded.files.private_storage, upload_to=recorded.files.video_path)
  duration_seconds PositiveIntegerField  1..86400
  position         PositiveSmallIntegerField
  description      TextField(blank, max 2000)
  status           CharField(9) choices draft | published | hidden  (default draft)
  downloadable     BooleanField(default False)
  created_at, updated_at
  UNIQUE (playlist, code); UNIQUE (playlist, slug)
  CHECK (kind = file AND file <> '' AND url = '') OR (kind IN (link, live) AND url <> '' AND file = '')
  CHECK downloadable implies kind = file
  ordering (position, id)

etqan.recorded.Enrolment
  playlist         FK Playlist  PROTECT  related_name="enrolments"
  student          FK identity.StudentProfile  PROTECT  related_name="+"
  amount_minor     BigIntegerField  >= 0
  currency         CharField(3)
  method           CharField(7) choices manual | free | stripe | paypal | code
  transaction_number CharField(120) blank
  payment          FK billing.Payment  null  SET_NULL  related_name="+"
  certificate_obtained BooleanField(default False)
  notes            TextField(blank, max 2000)
  status           CharField(7) choices active | revoked  (default active)
  enrolled_by      FK AUTH_USER  null  SET_NULL  related_name="+"
  enrolled_at      DateTimeField(default now)
  revoked_by       FK AUTH_USER  null  SET_NULL  related_name="+"
  revoked_at       DateTimeField  null
  UNIQUE (playlist, student) WHERE status = active
  CHECK method <> free OR amount_minor = 0
  indexes (student, status)

etqan.recorded.WatchedVideo
  enrolment        FK Enrolment  CASCADE  related_name="watched"
  video            FK PlaylistVideo  PROTECT  related_name="watches"
  watched_at       DateTimeField(default now)
  UNIQUE (enrolment, video)
```

`Enrolment.payment` is a string foreign key to `billing.Payment`. B7a sets it for manual enrolments (A-9)
and B7b for online sales. The `billing` app is never imported for models (B7-1). Upload paths and the
storage are module-level callables in `etqan/recorded/files.py`, each with `__module__` set, as in
`learning/files.py`, so that migrations can serialize them.

## 8. B7a services (`etqan.recorded.services`)

### 8.1 Playlists and videos
- `create_playlist(data, *, by)`, `update_playlist(playlist, changes)`, `delete_playlist(playlist)`. These
  validate A-1 and refuse a delete per A-12. Files go through `check_upload` (images) and the MP4
  signature check (videos).
- `playlists_queryset()` annotates `lessons` (published count), `seconds` (sum of published durations) and
  `enrolments` (active count). `filter_playlists(qs, params)` applies the §6 filters.
- `create_video(playlist, data)`, `update_video(video, changes)`, `delete_video(video)`,
  `move_video(video, direction)`. Under a lock on the playlist row, a move swaps positions and a delete
  closes the gap. `parse_video_url(url) -> (provider, id)` implements A-5.

### 8.2 Enrolments and watching
- **Ids:** services take user ids for people (`student_user_id`) and resolve the profile with
  `identity.services.get_student_profile`. A missing student or a non-student user gives 400 `student`.
  Billing receives the profile pk (`student_id`).
- `enrol_by_office(*, playlist, student_user_id, method, amount_minor, billing_method="", paid_on=None,
  reference="", transaction_number="", notes="", by) -> Enrolment` takes only `manual` or `free` (A-9) and
  creates the billing record for `manual`. `enrol_from_sale(*, playlist, student_user_id, method,
  amount_minor, currency, transaction_number, payment_id, by=None) -> Enrolment` is for B7b and B7g only:
  it is not exported to the API layer and is not called by any view. Both lock the playlist row and
  re-check the partial unique constraint (409 `recorded.already_enrolled`).
- `revoke(enrolment, *, by)`, `restore(enrolment, *, by)`, `delete_enrolment(enrolment)`,
  `update_enrolment(enrolment, changes)` (notes, transaction number, watched set).
- `set_watched(enrolment, video, watched: bool)`. The video must be published and in the enrolment's
  playlist (else 404), and the enrolment active (409 `recorded.enrolment_revoked`). It is idempotent.
- `progress(enrolment) -> Progress(watched, total)`, and `enrolments_of(student_user_id)` for the
  student's list.
- Read services for later slices: `enrolment_for(student_user_id, playlist_id) -> Enrolment | None` (B7b,
  B7g) and `is_complete(enrolment) -> bool` (B7g).

### 8.3 Scoping
- `can_watch(user, video) -> bool` implements A-14. `visible_playlists(user)` implements A-13 (for a
  parent, across `identity.services.children_of`).

## 9. B7a API (`/api/v1/recorded/`)

| Route | Methods | Who | Notes |
|---|---|---|---|
| `playlists/` | GET, POST | office `playlist.view_any` / `.create` | Multipart on POST. Filters per §6. |
| `playlists/<id>/` | GET, PATCH, DELETE | office `playlist.view` / `.update` / `.delete` | |
| `playlists/<id>/videos/` | GET, POST | office `playlist_video.view_any` / `.create` | Ordered. |
| `videos/<id>/` | PATCH, DELETE | office `playlist_video.update` / `.delete` | |
| `videos/<id>/move/` | POST | office `playlist_video.reorder` | `{direction: "up"\|"down"}` |
| `videos/<id>/file/` | GET | office `playlist_video.view_any`, or the enrolled student (A-14) | 302 to a signed URL or a stream (B7-8). `?download=1` only when downloadable. |
| `playlists/<id>/enrolments/` | GET, POST | office `rc_enrolment.view_any` / `.create` | POST: `{student_id (user id), method, amount_minor, billing_method, paid_on, reference, transaction_number, notes}`; `manual` also needs `payment.create` (A-9) |
| `enrolments/<id>/` | GET, PATCH, DELETE | office `rc_enrolment.view` / `.update` / `.delete` | PATCH takes `watched_video_ids` (the set) |
| `enrolments/<id>/revoke/`, `…/restore/` | POST | office `rc_enrolment.update` | |
| `my/` | GET | student, or parent with `?student=<user id>` of a child | The visible enrolments with progress. |
| `my/<playlist id>/` | GET | same | The playlist, its published videos with `watched` and the embed data, and the progress. |
| `my/videos/<id>/watched/` | PUT, DELETE | student (own active enrolment) | Parents get 403. |

Every route has `FeatureOn` with `feature = "recorded_courses"`. Errors use `etqan.platform.exceptions`
with the codes named in §5. Throttling: `my/videos/<id>/watched/` uses the existing user rate.

## 10. B7a seeds

`etqan/tenants/seeds/b7.py` `seed_b7(subdomain)` is called from `seed_academy` under the B7 marker, and is
idempotent by playlist code. It creates two published playlists: `QURAN-INTRO` (free, three YouTube link
videos) and `TAJWEED-1` (price 2 000 USD minor, discount 500, four link videos and one live link). It
enrols the demo student in both through `enrol_by_office`: `QURAN-INTRO` as `free`, and `TAJWEED-1` as
`manual` with 1 500 USD minor and billing method `cash`, by the demo admin, which creates its billing
record. One video is marked watched. No seeded video files.

## 11. B7a tests

- **Models and services:** A-1 limits and uniqueness; discount ≤ price; computed lessons and hours
  (published only); A-5 URL parsing for each YouTube form, Vimeo and external URLs, and refusal of http
  and javascript URLs; the type and file checks; positions on create, move and delete (dense) under
  concurrency; enrol uniqueness under concurrency (409); free amount 0; office methods only; revoke,
  restore and delete rules; watched idempotency, a hidden video's record kept and counted again once
  republished; progress.
- **API and access:** the code matrix per A-15 (the `in_use` equality test); a student seeing only their
  own published enrolled playlists; a parent seeing a child's but getting 403 on writes and on files;
  404 for anything else; `FeatureOn` 404 when off; the file route's inline and attachment behaviour, its
  302 only with a dedicated private bucket (a fake storage and the settings flag), its 206 for a
  `Range` request when streaming, and its refusal for draft or hidden videos,
  revoked enrolments and unpublished playlists.
- **Contracts:** `lint-imports` with the new `etqan.recorded` contract.
- **Dashboard (Vitest + RTL + MSW):** the list and filters, the playlist tabs, the video dialog's
  type-dependent fields and HH:MM:SS input, the enrolment dialog and watched multi-select, the student
  player choosing iframe, video or button by type, mark-as-watched (optimistic, rolled back on error), the
  parent's read-only view, and the hidden nav and route while off. ar/en key equality.
- **e2e** (`e2e/b7-recorded.spec.ts`): the office creates a playlist and a link video, publishes them and
  enrols the demo student. The student opens it, marks the video watched and sees progress 1 / 1.

## 12. B7a non-goals

- Selling, the storefront and the marketing page are B7b. Comments and reviews are B7e. Certificates and
  activation codes are B7g.
- Transcoding, HLS, DRM or watermarking. Files play as uploaded MP4.
- Watch-time analytics beyond the watched flag.
- A teacher role in recorded courses.
