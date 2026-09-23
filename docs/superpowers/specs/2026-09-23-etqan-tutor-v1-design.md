# etqan_tutor v1 — Design

**Date:** 2026-09-23
**Owner:** Etqan Agency (`Etqan-agency` GitHub org)
**Status:** Approved. Amended by `2026-09-23-academy-sites-design.md` (public academy sites, branding, custom domains).
**Inputs:** `PHASE_1_SYSTEM_AUDIT.md` (TutorHamster audit), `PHASE_2_SYSTEM_DESIGN.md` (full-parity design), the `kaleem-lms/Kaleem` codebase

---

## 1. What we are building

A **multi-tenant SaaS for online tutoring academies**. Etqan Agency runs one platform; each academy gets an isolated workspace on its own subdomain. Inside an academy, **admins do the operational work** (enrol students, create subscriptions, set weekly timetables), **teachers** deliver sessions over an external meeting link and record attendance and reports, and **students/parents** mostly view.

It is deliberately **simple and CRUD-shaped**. Phase 2 describes full parity with a 54-module commercial product; etqan_tutor v1 takes only the operational spine from it:

> package → subscription → weekly slots → generated sessions → attendance → student invoices and teacher payslips

### 1.1 Decisions made during brainstorming

| # | Decision | Choice |
|---|---|---|
| D1 | Audience | Multi-tenant SaaS; many academies on one platform |
| D2 | Operating model inside an academy | Admin-run; teachers mark attendance; students/parents view |
| D3 | v1 scope beyond the core | Student billing (manual payments), teacher payroll, session reports, notifications |
| D4 | Academy onboarding & SaaS billing | Etqan staff create tenants by hand; plan/payment recorded manually; no public signup, no Stripe |
| D5 | Lesson delivery | External meeting link (Zoom / Google Meet / any URL); no built-in video |
| D6 | Codebase approach | **Full fork of Kaleem, keep the React dashboard as the UI**, strip what doesn't fit, add tenancy |
| D7 | Tenancy mechanism | Schema-per-tenant (`django-tenants`, PostgreSQL), subdomain routing |
| D8 | Subscription shape | One course + one teacher per subscription; no group sessions in v1 |
| D9 | Notification channels | In-app + email in v1; WhatsApp designed-for but deferred |

### 1.2 Non-goals for v1

Public academy signup; SaaS plan billing via a gateway; online student payments (Stripe/PayPal); built-in video; group sessions; family accounts; levels/curriculum progress; homework; certificates; wallets; trial-session pipeline (a trial is just a one-off session); recorded courses; consultations; page builder (academy sites are a fixed template + rich-text pages — see the academy-sites spec); chat; AI features; fine-grained permission editor; feature-flag system; WhatsApp/SMS delivery; mobile app; data migration from any existing system.

---

## 2. Repositories

| Repo | Action | Notes |
|---|---|---|
| `Etqan-agency/etqan_tutor` | Fork of `kaleem-lms/Kaleem` (meta repo) | `.gitmodules` repointed to Etqan forks; `marketing` submodule removed |
| `Etqan-agency/etqan_tutor_backend` | Fork of `kaleem-lms/backend` | Django + DRF modular monolith |
| `Etqan-agency/etqan_tutor_dashboard` | Fork of `kaleem-lms/dashboard` | React + TanStack; the only end-user UI |
| `Etqan-agency/etqan_tutor_infra` | Fork of `kaleem-lms/infra` | Docker, nginx, monitoring; coturn removed |
| `Etqan-agency/etqan_tutor_tokens` | Fork of `kaleem-lms/tokens` | Design tokens, kept as-is then rebranded |
| `kaleem-lms/marketing` | **Not forked** | Revisit when public signup is in scope |

`PHASE_1_SYSTEM_AUDIT.md`, `PHASE_2_SYSTEM_DESIGN.md` and this spec move into the meta repo's `docs/`.

### 2.1 Kept from Kaleem

* **Backend:** `identity` base (custom `User`, Student/Teacher/Parent profiles, auth flows, password reset), `platform` (DRF conventions, error envelope, pagination, throttling, logging, middleware), settings layout, Celery + beat wiring, test setup.
* **Dashboard:** app shell, routing, auth screens, UI primitives, i18n (ar/en) and RTL handling, API client.
* **Infra:** Docker Compose, nginx, monitoring, deploy scripts.
* **Tokens:** as-is.

### 2.2 Removed from Kaleem

* **Backend:** matching, booking, rooms/`signaling` (WebRTC), Stripe billing + test-clock harness, and any model/app tied to them. Kaleem's `scheduling`, `billing` and `curriculum` apps are replaced by the new domain apps in §4, not adapted.
* **Dashboard features:** `call`, `matching`, `booking`, `assessment`, `analytics`, `engagement`, `content`, `messaging` (and Kaleem's `billing`/`scheduling`/`curriculum` feature folders are rewritten against the new API).
* **Infra:** coturn.
* **Process:** CI reduced to lint, typecheck, tests, build, secret scan, deploy. Coverage floor starts at **80%** (not Kaleem's 97% ratchet). Kaleem's `STATE.md`, journal, `ISSUES.md` and `tasks.todo` are reset; ADRs kept as historical record under a `kaleem-archive/` folder, new ADRs only for real decisions.

---

## 3. Tenancy

* **Library:** `django-tenants` on PostgreSQL. One schema per academy.
* **`public` schema** (shared apps): `Tenant` (name, schema name, subdomain, status `active · suspended`, plan label, plan notes, created at), `Domain`, and Etqan staff accounts.
* **Tenant schemas** (tenant apps): everything in §4.
* **Routing:** `{academy}.<platform-domain>` resolves the tenant from the `Host` header. The one dashboard build is served on every subdomain and calls the API on the same host. The root domain serves only the Etqan super-admin console.
* **Accounts are per academy.** A person in two academies has two accounts. No cross-tenant identity.
* **Suspended tenant:** API returns `403 tenant.suspended`; dashboard shows a "workspace suspended, contact Etqan" page.
* **Etqan super-admin console:** Django admin on the `public` schema, Etqan staff only. Actions: create academy (name, subdomain, timezone, currency, first admin email → schema created, admin invited by email), suspend / reactivate, edit plan notes.
* **Files:** uploads (logos, avatars) stored under a per-tenant prefix in object storage.
* **Background jobs** iterate tenants explicitly (`for tenant in active tenants: with tenant_context(...)`); every task payload carries the schema name.

---

## 4. Domain model (per-tenant schema)

Money is always **integer minor units + ISO-4217 currency**. Stored instants are UTC; wall-clock times carry the academy timezone. All business entities have `created_at`, `updated_at`.

### 4.1 Academy settings

`AcademySettings` (singleton per tenant): display name, logo, primary colour, timezone (IANA), default currency, default locale (`ar · en`), `generation_horizon_days` (default 14), `absent_consumes_session` (bool, default true), `excused_consumes_session` (bool, default false), `pay_teacher_for_student_absence` (bool, default true), `reminder_minutes_before` (default 60), `low_sessions_threshold` (default 2), `auto_invoice_on_subscription` (bool, default true), notification on/off per type (§6.5).

### 4.2 People

* **`User`** — email (unique within tenant, nullable if phone given), phone (E.164), password, full name, locale, timezone (defaults to academy's), `role` ∈ `admin · teacher · student · parent`, is_active. Exactly one role per account.
* **`StudentProfile`** — user (1:1), date of birth, gender, country, status `active · paused · inactive`, notes.
* **`TeacherProfile`** — user (1:1), gender, bio, `default_meeting_url`, `pay_currency`, is_active.
* **`ParentProfile`** — user (1:1), notes.
* **`Guardianship`** — parent, student; unique pair. A parent may have many children; a student may have several guardians.

A student may exist without a login (email/phone optional) when a parent manages everything; such a student gets `is_active=False` on `User` and cannot sign in.

### 4.3 Catalogue

* **`Course`** — name (ar, en), description (ar, en), is_active.
* **`Package`** — name (ar, en), sessions_per_week, session_minutes, term_value + term_unit (`week · month`), price_minor, currency, freeze_days_allowed, is_active.
  Derived: `sessions_total = sessions_per_week × weeks(term)` (a month counts as 4 weeks).

### 4.4 Subscriptions

* **`Subscription`** — student, course, teacher, package, starts_on, `term_ends_on` (from package term), `sessions_total` (snapshot from package), `session_minutes` (snapshot), price_minor + currency (snapshot, editable at creation), status `active · paused · expired · cancelled`, notes, `renewed_from` (nullable FK to previous subscription).
  * **`ends_on` is derived:** `term_ends_on + Σ pause days`.
  * **`sessions_used` is derived:** count of this subscription's sessions that consume (see §5.2). Never stored, never typed.
  * `sessions_remaining = sessions_total − sessions_used`.
* **`SubscriptionPause`** — subscription, from_date, to_date, reason. Invariant: total pause days ≤ package's `freeze_days_allowed` snapshot (stored on the subscription at creation as `freeze_days_allowed`).

### 4.5 Scheduling

* **`ScheduleSlot`** — subscription, weekday (0=Mon…6=Sun), `start_time` (local, academy timezone), `minutes` (defaults to subscription's), `meeting_url` (nullable; falls back to teacher's default), is_active.
  Teacher and course come from the subscription.

### 4.6 Sessions

* **`Session`** — slot (nullable for one-off sessions), `occurs_on` (local date), `starts_at` (UTC), minutes, subscription (nullable only for one-off sessions without a subscription, e.g. trials), student, teacher, course, meeting_url (copied at creation), status `scheduled · completed · cancelled`, student_attendance and teacher_attendance ∈ `not_set · present · absent · excused`, cancel_reason, notes, `generated` (bool).
  * **DB constraint:** `UNIQUE(slot, occurs_on)` where slot is not null.
  * `completed` requires student_attendance ≠ `not_set`.
* **`SessionReport`** — session (1:1), behaviour_rating 1–5, participation_rating 1–5, notes, visible_to_parent (bool, default false), submitted_by, submitted_at.

### 4.7 Billing (manual payments)

* **`Invoice`** — number (auto, per-tenant sequence `INV-000123`), payer (a parent or student `User`), student, subscription (nullable), amount_minor, currency, issued_on, due_on, status `unpaid · partial · paid · void`, notes.
  `overdue` is a derived display state (`unpaid|partial` and `due_on < today`), not stored.
* **`Payment`** — invoice, amount_minor, currency (must equal invoice currency), method `cash · bank_transfer · instapay · vodafone_cash · card_manual · other`, paid_on, reference, recorded_by, notes. Invoice status recomputed from Σ payments on every payment create/delete.
  `void` allowed only when there are no payments.

### 4.8 Payroll

* **`TeacherRate`** — teacher, course (nullable = default rate), hourly_rate_minor, currency (= teacher's pay currency). Unique (teacher, course).
* **`PayAdjustment`** — teacher, kind `bonus · deduction`, amount_minor, currency, effective_on, reason (required), payslip (nullable; set when consumed).
* **`Payslip`** — teacher, period (year + month), status `draft · issued · paid`, currency, gross_minor, bonuses_minor, deductions_minor, net_minor, issued_at, paid_at, notes.
* **`PayslipLine`** — payslip, kind `session · adjustment`, session (nullable), adjustment (nullable), description, minutes, rate_minor, amount_minor. **Copied values**, not references for computation.
  * Once `issued`, a payslip and its lines are read-only. Later edits to sessions do not change it; corrections are made as `PayAdjustment`s in a later month.

### 4.9 Notifications

* **`Notification`** — recipient (User), type, channel `inapp · email`, title, body (rendered in recipient's locale), `dedupe_key` (unique), status `pending · sent · failed`, sent_at, read_at, error.

---

## 5. Core behaviour

### 5.1 Session generation

Runs (a) daily per tenant via Celery beat for `today … today + generation_horizon_days`, (b) on demand from the admin "Generate for range" action, and (c) for the next horizon immediately when a subscription is created or a slot is added.

For each active slot of each `active` subscription, for each date D in the window with `weekday(D) = slot.weekday`:

1. Skip if D < `starts_on` or D > `ends_on`.
2. Skip if D falls inside a `SubscriptionPause`.
3. Skip if a session for (slot, D) exists — enforced by the unique constraint; the insert uses `ON CONFLICT DO NOTHING` semantics (`bulk_create(ignore_conflicts=True)`).
4. Compute `starts_at` = localise(D, slot.start_time, academy timezone) → UTC. Nonexistent/ambiguous local times (DST) resolve forward.
5. Create the session (`generated=True`, status `scheduled`, attendance `not_set`, meeting_url resolved).
6. If the teacher already has an overlapping non-cancelled session, still create it and report it as a **conflict** in the run result.

Generation does **not** stop at `sessions_remaining = 0`; running out is handled by expiry (§5.3), and extra sessions show as negative remaining.

The run returns `{created, skipped_existing, skipped_paused, skipped_out_of_term, conflicts: [...]}`, shown to the admin after an on-demand run.

**Slot edits:** changing or deactivating a slot deletes that slot's sessions that are `scheduled`, `not_set` on both attendances, and `starts_at > now`, then regenerates the horizon. Past sessions are never touched.

**Today board:** lists every slot due today across active subscriptions with its state: `generated`, `missing` (no session — offer "generate"), `cancelled`, or `completed`.

### 5.2 Attendance, completion and consumption

* Teacher (own sessions) or admin sets `student_attendance` and `teacher_attendance`; setting student attendance on a `scheduled` session moves it to `completed`. Admin bulk actions: mark present, mark absent, cancel.
* A session **consumes** one session of its subscription when `status = completed` and:
  * student `present` → always;
  * student `absent` → if `absent_consumes_session`;
  * student `excused` → if `excused_consumes_session`.
* Cancelled sessions never consume. Cancelling is allowed from `scheduled` only (and from `completed` by admin, which un-consumes it). Sessions on an issued payslip cannot be cancelled or have attendance changed — `409 payroll.payslip_issued`.

### 5.3 Subscription lifecycle

| Transition | Trigger | Effect |
|---|---|---|
| create → `active` | Admin saves subscription | Snapshot package values; optional auto-invoice; generate horizon |
| `active` → `paused` | Admin adds a pause covering today | Future sessions inside the pause that are still `scheduled` are deleted; generation skips paused dates |
| `paused` → `active` | Pause end date passes (daily job) or admin ends it early | Regenerate horizon |
| `active` → `expired` | Daily job: `ends_on < today` **or** `sessions_remaining ≤ 0` | Future `scheduled` sessions deleted; notify |
| any → `cancelled` | Admin | Future `scheduled` sessions deleted |
| Renew | Admin action on any subscription | New subscription (same student/course/teacher/package unless changed), `starts_on` = day after old `ends_on` (or today if later), slots copied, `renewed_from` set; old one marked `expired` if still active |

### 5.4 Billing

* On subscription create with `auto_invoice_on_subscription`: one invoice for the subscription price, payer = the student's first guardian if any, else the student; due in 7 days.
* Admin can create standalone invoices and record payments; invoice status is recomputed from payments.
* Dashboard revenue = Σ payments `paid_on` in the current month, per currency (never summed across currencies).

### 5.5 Payroll

* Admin chooses a month → "Generate payslips" creates or **replaces** `draft` payslips for every teacher with activity (issued/paid payslips for that month are left alone).
* Session lines: the teacher's sessions with `occurs_on` in the month, `status = completed`, `teacher_attendance ∈ {present, not_set}`, and — when the student was absent — only if `pay_teacher_for_student_absence`. Rate = `TeacherRate(teacher, course)` else `TeacherRate(teacher, default)`; if neither exists the payslip is flagged `missing_rate` and cannot be issued. `amount = round_half_up(rate × minutes / 60)`.
* Adjustment lines: unconsumed `PayAdjustment`s with `effective_on` in or before the month.
* **Issue:** freezes the payslip, marks its adjustments consumed. **Mark paid:** records `paid_at`.
* Teachers see their own issued/paid payslips with every line.

### 5.6 Session reports

Teacher submits one report per completed session they taught. Admin board lists completed sessions older than 24h without a report. Parents see a report only if `visible_to_parent`.

---

## 6. Access, API and UI

### 6.1 Roles

| Capability | Admin | Teacher | Parent | Student |
|---|:--:|:--:|:--:|:--:|
| Academy settings, users, catalogue | ✓ | | | |
| Subscriptions, slots, pauses, renew | ✓ | view own | view children's | view own |
| Generate sessions, Today board | ✓ | | | |
| Sessions | all | own (taught) | children's | own |
| Attendance | ✓ | own sessions | | |
| Session reports | ✓ | write own | read if shared | |
| Invoices & payments | ✓ | | view children's | view own |
| Payroll | ✓ | view own issued | | |
| Notifications | own | own | own | own |

Enforced in one place: a DRF permission per role plus a queryset scoping function per resource (`scope_for(user, queryset)`). Out-of-scope objects return `404`.

### 6.2 API

Kaleem's existing DRF conventions are kept (error envelope, pagination, throttling). REST resources under `/api/v1/` for every entity in §4, plus actions:
`POST /subscriptions/{id}/renew`, `POST /subscriptions/{id}/pauses`, `POST /schedule/generate {from, to}`, `GET /schedule/today`, `POST /sessions/{id}/attendance`, `POST /sessions/{id}/cancel`, `POST /sessions/bulk {ids, action}`, `POST /sessions/{id}/report`, `POST /invoices/{id}/payments`, `POST /invoices/{id}/void`, `POST /payroll/generate {year, month}`, `POST /payslips/{id}/issue`, `POST /payslips/{id}/mark-paid`, `GET /me`, `GET /dashboard/summary`.

### 6.3 Dashboard screens (one React build, role-driven navigation, ar/en, RTL)

* **Admin:** Home (Today board + counts: active students, active subscriptions, sessions today, missing reports, overdue invoices, this month's revenue per currency) · Students · Parents · Teachers · Courses · Packages · Subscriptions (form includes slots and pauses) · Sessions (table with filters + week calendar) · Invoices & payments · Payroll (month view, payslips, rates, adjustments) · Settings.
* **Teacher:** Today / this week (join link, attendance, report) · Session history · My payslips.
* **Parent / Student:** Upcoming sessions with join link · Attendance history · Subscription progress (used / remaining, ends on) · Shared reports (parent) · Invoices.
* All lists: search, filters, pagination, CSV export for admin.

### 6.4 Auth

Kaleem's identity flows kept: email or phone + password, password reset by email, session/token handling as Kaleem does today. Admin can create users and send an invite (set-password link). No self-registration in v1. Admin "view as" impersonation is out of v1.

### 6.5 Notifications (v1 channels: in-app + email)

| Type | Recipients | When |
|---|---|---|
| `session.reminder` | student (if has login), guardians, teacher | `reminder_minutes_before` before `starts_at` |
| `session.student_absent` | guardians | when marked absent |
| `subscription.low` | student, guardians, admins | `sessions_remaining` reaches `low_sessions_threshold` |
| `subscription.expired` | student, guardians, admins | on expiry |
| `invoice.issued` | payer | on invoice create |
| `invoice.overdue` | payer, admins | day after `due_on`, then weekly while unpaid |
| `report.missing` | teacher | 24h after a completed session without a report |
| `account.invite` | invited user | on invite |

Each type has an on/off switch in academy settings and ar/en templates (in code for v1). A per-minute Celery task per tenant finds due items and creates `Notification`s with `dedupe_key = type:object_id:occurrence`; the unique key makes re-runs harmless. Email goes through a channel interface so WhatsApp can be added later without touching callers.

---

## 7. Testing

* **Unit:** generation (weekday mapping, DST boundaries in e.g. `Europe/London`, pauses, term bounds, idempotency on rerun, slot edits not touching past sessions); consumption rules for every attendance × setting combination; subscription expiry; invoice status from payments; payroll math (rates, per-course override, missing rate, adjustments, rounding, frozen after issue).
* **API:** for every resource, a negative test per role (teacher can't see another teacher's session, parent can't see another family's invoice, student can't write attendance).
* **Tenant isolation:** a user/token from academy A gets `404`/`403` on academy B's host and data; a background job run for A never writes into B.
* **E2E (Playwright, reusing Kaleem's setup):** Etqan creates academy → admin creates course, package, teacher, student → subscription with two slots → generate → teacher marks attendance and writes report → admin issues invoice and records payment → admin generates and issues payslip.
* CI coverage floor 80%.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Stripping Kaleem leaves dead code / hidden coupling | Removal is its own first milestone with green CI before any new domain work |
| `django-tenants` vs Kaleem's existing auth/Celery/test setup | Tenancy is the second milestone, proven by the isolation test before domain apps are built |
| DST / timezone bugs in generation | Localise per occurrence; dedicated DST tests |
| Payroll disputes | Frozen payslips with visible per-session lines |
| Scope creep back toward Phase 2 parity | §1.2 non-goals list; new features need an explicit scope change |

---

## 9. Suggested milestone order (input to the implementation plan)

1. **Fork & strip** — forks created, `.gitmodules` repointed, removed apps/features/coturn deleted, CI trimmed, rebrand to etqan_tutor, green CI.
2. **Tenancy** — `django-tenants`, `public` vs tenant apps, subdomain routing, super-admin console, isolation tests.
3. **People & catalogue** — roles, profiles, guardianship, courses, packages, academy settings; admin CRUD screens.
4. **Subscriptions & scheduling** — subscriptions, pauses, slots, generation engine, Today board, renew/expire jobs.
5. **Sessions** — attendance, cancel, bulk actions, reports; teacher and student/parent views.
6. **Billing** — invoices, payments, auto-invoice, dashboard revenue.
7. **Payroll** — rates, adjustments, payslip generation/issue/paid, teacher payslip view.
8. **Notifications** — in-app + email, all v1 types, settings switches.
9. **E2E + staging deploy.**
