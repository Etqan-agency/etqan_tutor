---
name: kaleem-product-spec
phase: 0
modules: [identity, billing, scheduling, assessment, content, messaging, notifications, analytics]
status: approved
created: 2026-06-08
closed: null
---

## Goal

kaleem is an LMS for teaching non-Arabic speakers Islamic sciences (Quran, Tafsir, Arabic language).
Parents or adult students subscribe monthly to get a fixed number of 1-on-1 sessions with a vetted
teacher. The platform auto-matches students to teachers, handles scheduling, hosts video sessions
(LiveKit), and collects post-session reports, homework notes, and ratings from both sides.

This document is the single source of truth for product decisions. Every module spec links back here.
It does not contain data models or API shapes — those live in each module's spec.

---

## Actors

### Parent
- Pays the subscription on behalf of one or more children.
- Allocates sessions from the family pool to each child.
- Can fully manage any child's account (set preferences, view reports, cancel sessions, rate teachers).
- Child retains their own access; parent access is additive, not exclusive.

### Student — Adult
- Self-managed. No parent linked.
- Subscribes directly on an Individual plan.
- Does everything independently.

### Student — Child
- Has a parent linked to their account.
- Can do everything an adult student can.
- Parent can also do everything on their behalf.
- No age threshold — the parent/child relationship is set during registration, not derived from age.

### Teacher
- Applies to join. Not self-serve.
- Once approved, enters the teacher pool and becomes eligible for matching.
- Delivers sessions, writes reports, assigns homework, rates students.
- Paid monthly by kaleem based on sessions delivered.

### Admin
- Manages the platform: approves teachers, handles the waitlist, processes teacher changes,
  configures plans, monitors metrics, generates teacher payroll.

---

## Subscription & Billing

### Plans
- **Individual** — one student, **4 sessions per month**, price configurable by admin.
- **Family** — one parent, unlimited children, **4 sessions per child per month** in a shared pool,
  parent allocates sessions across children.
- Price is set by kaleem via admin config, not by teachers. Not hardcoded — stored in DB.
- Billing is monthly, auto-renewing.

### Session allocation (Family plan)
- Parent decides how many sessions each child gets from the family pool.
- e.g. Family plan = 8 sessions/month. Parent gives child A 4, child B 4.
- Allocation can be adjusted each billing cycle.

### Unused sessions
- Unused sessions **expire at the end of the billing cycle**. No rollover.

### Teacher pay
- kaleem pays teachers monthly.
- Pay is calculated as: sessions delivered × rate per session.
- Admin generates the payroll summary at end of month.
- kaleem sets teacher rates (same fixed rate as the platform price, or a separate internal rate TBD per billing spec).

---

## User Flows

### Flow 1 — Adult Student Onboarding
1. Register with email + password.
2. Choose Individual plan, enter payment details.
3. Set matching preferences: weekly time slots available + preferred teacher gender.
4. System runs matching engine (see Flow 6).
5. Student notified when matched with a teacher.
6. First recurring session slot created.

### Flow 2 — Parent + Child Onboarding
1. Parent registers with email + password.
2. Choose Family plan, enter payment details.
3. Add one or more children (name, basic details).
4. Allocate sessions from the pool to each child.
5. For each child: set matching preferences (time slots + teacher gender).
6. System runs matching engine per child.
7. Parent notified when each child is matched.
8. Recurring session slots created per child.

### Flow 3 — Teacher Application
1. Prospective teacher visits the application page.
2. Fills in the application form:
   - CV (file upload)
   - Teaching certificate (file upload)
   - Short introduction video (file upload)
   - Weekly availability schedule (time slots per day)
   - Additional fields as configured by admin (flexible schema)
3. Submits application → status: pending.
4. Admin reviews inside the platform.
5. Admin approves → teacher notified, account activated, enters matching pool.
6. Admin rejects → teacher notified with optional reason.

### Flow 4 — Session Lifecycle
1. Recurring session slot exists (teacher + student, fixed weekly time, 60 min).
2. System sends reminder to both parties: **24h before** and **1h before** session.
3. At session time: both join the LiveKit video room (link in dashboard + notification).
4. Session happens (60 min, 1-on-1).
5. Session ends → post-session window opens for both parties.
6. **Teacher** submits:
   - Session report: what was covered this session.
   - Next session plan: what will be covered next.
   - Homework note: task for the student.
   - Rating for the student.
7. **Student / Parent** submits:
   - Rating for the teacher.
8. Session marked complete. Report and homework visible to student and parent.

### Flow 5 — Cancellation & No-show

**Student cancels with ≥24h notice:**
- Session is rescheduled to a mutually available slot.
- Session is NOT consumed from the monthly pool.

**Student no-shows (no notice or <24h notice):**
- Session is marked consumed. No refund, no reschedule.
- Teacher is still counted as having delivered the session (paid for it).

**Teacher no-show:**
- Student reports the no-show through the platform.
- Admin is notified.
- Outcome (admin decides): reschedule the session OR add +1 session to the student's next billing cycle.
- Teacher is NOT paid for that session.

### Flow 6 — Matching Engine
1. Triggered when a student completes onboarding preferences.
2. Inputs: student's available time slots + preferred teacher gender.
3. System finds teachers in the pool who:
   - Have a matching available time slot.
   - Match the gender preference.
4. **Match found:** assign teacher + student to a recurring weekly slot. Notify both.
5. **No match found:** add student to waitlist. Alert admin with student details and preferences.
6. Admin can manually intervene (adjust preferences, assign manually, or waitlist student until a teacher joins).

Future matching inputs (not in v1): student level, subject preference, teacher rating.

### Flow 7 — Teacher Change
1. Student or parent contacts support (outside the platform in v1, or via a support form).
2. Admin reviews the request.
3. Admin reassigns the student to a new teacher (manual matching).
4. New recurring session slot created. Old slot removed.
5. Both old teacher and new teacher notified.

### Flow 8 — Admin — Teacher Payroll
1. At end of each month, admin opens the payroll view.
2. System shows: each teacher → sessions delivered this month → amount owed.
3. Admin marks payroll as processed.
4. Teachers can view their own earnings summary.

---

## Business Rules

| # | Rule |
|---|---|
| BR-01 | Sessions are 60 minutes, 1-on-1. |
| BR-02 | Unused sessions expire at month end. No rollover. |
| BR-03 | Student cancellation with ≥24h notice → reschedule, session not consumed. |
| BR-04 | Student no-show or <24h cancellation → session consumed, gone. |
| BR-05 | Teacher no-show → admin notified → reschedule or +1 next month. Teacher not paid. |
| BR-06 | A parent can fully manage any child's account. Child retains their own access. |
| BR-07 | Teacher rates are fixed by kaleem. Teachers do not set their own price. |
| BR-08 | Teacher change requires contacting support. Student cannot self-reassign. |
| BR-09 | Unmatched students go on a waitlist. Admin is alerted. |
| BR-10 | Session reminders sent 24h before and 1h before. |
| BR-11 | Family plan sessions are allocated by parent across children. |
| BR-12 | Teacher application fields are admin-configurable. |
| BR-13 | Teacher is not paid for sessions where they were a no-show. |
| BR-14 | Video sessions use LiveKit (self-hosted). Zoom is not used. |

---

## Module Build Order

```
Phase A → identity      Users, profiles (Student, Teacher, Parent), auth (allauth)
Phase B → billing       Plans, subscriptions, session pool, Stripe, teacher payroll
Phase C → scheduling    Matching engine, recurring slots, waitlist, cancellation rules
Phase D → assessment    Session reports, homework notes, bidirectional ratings
Phase E → content       LiveKit video rooms, session join flow
Phase F → notifications Reminders (24h + 1h), match notifications, no-show alerts
Phase G → admin         Teacher applications, payroll view, waitlist management, plan config
```

Dependencies:
- Phase B requires Phase A (need users to have subscriptions)
- Phase C requires Phase A + B (need users and session pools)
- Phase D requires Phase C (need sessions to have reports)
- Phase E requires Phase C (need session slots to create video rooms)
- Phase F requires Phase C (need sessions to send reminders)
- Phase G requires all of the above

---

## Out of Scope (v1)

- Group sessions (class with multiple students)
- Student level / progress tracking (planned for a later phase)
- Student leaderboard and gamification (planned)
- Subject selection (all subjects bundled in v1)
- In-platform support chat (v1 uses external support channel)
- Teacher self-service onboarding (admin-reviewed only)
- Mobile apps (web-first)
- Multiple languages in UI (Arabic UI in a later phase)

---

## Open Questions

| # | Question | Owner | Status |
|---|---|---|---|
| OQ-01 | Exact session counts and prices per plan (Individual and Family) | Business | **Resolved**: Individual = 4/month. Family = 4 per child/month. Price stored in DB, admin-configurable. |
| OQ-02 | Teacher pay rate per session (internal rate vs plan price) | Business | Open |
| OQ-03 | LiveKit: self-host on existing VPS or dedicated server? | Tech | Open |
| OQ-04 | Session recording: store or discard? | Business/Legal | Open |
| OQ-05 | What additional fields does the teacher application form need? | Business | Open |
| OQ-06 | Stripe or alternative payment processor? | Business | **Resolved**: Stripe as primary. Payment layer must be abstracted behind a provider interface to support local payment methods later. |
| OQ-07 | What does "family plan" cost relative to individual × N? | Business | Open |
