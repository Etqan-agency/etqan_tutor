# Phase B2 — Scheduling Depth — Phase Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3).
**Phase:** B2 of the parity roadmap (`2026-09-24-parity-roadmap-design.md` §2): multi-course / multi-teacher
subscriptions; group and family subscriptions with rosters; a weekly-schedule entity with bulk change, move
and restore; compensation (make-up) sessions; a postponement window; extra sessions; the trial-session
pipeline; teacher availability; session statuses with in/out times; an activity log with revert; archives;
a simplified view; student-timezone display.
**Works under:** `2026-10-02-parallel-orchestration-design.md` (ledger, slices, merge queue, ownership).
**Builds on:** Plan 4 (`2026-09-24-subscriptions-scheduling-design.md`), Plan 5
(`2026-09-25-sessions-attendance-design.md`), Plan 11 (families), Plan 12a/b (roles, supervision), Plan 13
(feature switches).
**Evidence:** `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (cited `TH §x`) and `docs/PHASE_1_SYSTEM_AUDIT.md`
(cited `P1 §x`). R7 is dropped (ledger D1): what the audits do not show is marked `[assumed]`.

## 1. Goal

Deepen `etqan.scheduling` from "one student, one course, one teacher, generated weekly sessions" to
TutorHamster's operating model: several kinds of session, sessions that move, a log of every change, records
that can be archived and restored, trials that turn into subscriptions, teacher availability, subscriptions that
bundle several courses or several students, and weekly schedules managed as their own objects. Every new
feature is a per-academy switch, off by default (PO-5), so each slice merges safely on its own.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| B2-1 | All of B2 lives in `etqan.scheduling`, which B2 owns. Subscriptions, sessions, trials, availability, study groups and weekly schedules share one rule set (Plan 4 P4-1). No new app. | spec Plan 4 P4-1; orchestration §4.3 |
| B2-2 | **A session stays one row per student.** A group class is one session row per roster student at the same time, linked by the group; each keeps its own attendance and consumption. How a teacher is paid for a group class is B4's. | TH §2.4 SCHED-003 (session type normal / group; per-student attendance); P1 SCHED-004 (`student`, `group` on one session) · [assumed] row-per-student |
| B2-3 | **A `Subscription` keeps its meaning:** one student, one course, one teacher, one package, its own term, pauses, slots and derived numbers. TutorHamster's multi-course, family and group subscriptions become a **bundle** that groups several of them and is created, renewed, paused and cancelled as one. Billing, payroll and notifications keep reading single subscriptions unchanged. | TH §2.3 SUB-001 (details repeater: student → courses → course/teacher/package rows) · [assumed] bundle over rewrite, to keep B3/B4/B5 stable |
| B2-4 | **Session kinds:** `regular` (from a slot or added by hand to a subscription), `compensation` (a make-up for one session that did not use up the package), `extra` (outside the package; never consumes), `trial` (from a trial request, no subscription; never consumes). The one consumption rule (Plan 5 §4.2) counts only `regular` and `compensation`. | TH §2.4 SCHED-003 tabs (core / compensation), SCHED-007, SCHED-008; TH §1.3 #18 |
| B2-5 | **`pays_teacher`** on every session, default true (TutorHamster's "paid to teacher?" on extra and trial sessions). `payroll_sessions` leaves out sessions with it off; every other pay rule stays B4's. | P1 SCHED-007/008 · [assumed] the flag lives on the session |
| B2-6 | **Session status `at_disposal`** ("at the administration's disposal") is added. It never consumes and today's payroll rule does not pay it; B4 decides its pay. TutorHamster's status "absent without excuse" is already our `completed` + student attendance `absent`, so no status is added for it. | TH §1.3 #4; TH §4 U9 (semantics unknown) · [assumed] meaning |
| B2-7 | In/out times are recorded by people (the teacher's "I'm in / I'm out", or the office), not stamped by a video room: rooms stay external links. | v1 D5; TH SCHED-003 · [assumed] |
| B2-8 | **Postponement moves the session** to a new time; the row is detached from its slot and remembers the slot and slot date it came from, so generation never recreates it (B2b B-4). Students, parents (for a child) and teachers may postpone until `postpone_limit_minutes` before the start; the office may reschedule any time. | TH §2.4 SCHED-015; TH §1.3 #11 · [assumed] who and how |
| B2-9 | **The activity log** records the changes services make to sessions (actor, action, field-level before/after; B2c lists what is and isn't logged). A subscription log is not taken [assumed low value; P1 SYS-008 confirms the log for sessions only, other entities UNKNOWN]. Reverting one entry restores its fields only when none has changed since; otherwise 409. | P1 SCHED-004; TH SCHED-004 · [assumed] revert conflict rule |
| B2-10 | **Archive = "delete keeping records".** An archived subscription and its sessions leave the default lists but keep counting everywhere (consumption, invoices, payroll, dashboard totals "table + archive"). Restore brings them back. Permanent delete keeps Plan 4's rules. | TH SUB-003/004, SCHED-005; P1 BR-45, BR-46 |
| B2-11 | **Trials** are requests with TutorHamster's fields; scheduling one creates a `trial` session (no subscription) so attendance, reports and lists work unchanged. A completed trial can be converted into a subscription pre-filled from it. Site inquiries of kind `trial` can be turned into trial requests from the dashboard, which then marks the inquiry handled through the site's admin API; the trial keeps the inquiry's id (no scheduling → site import; B2e E-8). | TH SCHED-007; P1 FLOW-002 ("conversion INFERRED") |
| B2-12 | **Teacher availability** is weekly windows per teacher. It powers "suggest a teacher" (course, gender, availability, no clash) and warns on scheduling outside it; it never blocks, like double-bookings (P4-9). | P1 SCHED-012 (fields unknown) · [assumed] |
| B2-13 | **Study groups** live in scheduling: name, students (each in at most one group), notes, active. The registry's `study_groups` line is flipped to built. | TH PEOPLE-003; P1 BR-17 |
| B2-14 | **The weekly schedule** is a subscription's (or bundle's) slot set shown and managed on its own screen, with status active / stopped / deleted, restore, bulk teacher change, substitute teachers (a record generation reads), CSV download and an expanded calendar. Bulk change of times and "delete and move sessions" are not built (BR-44's target is UNKNOWN; B2g G-1, G-7, G-8). | TH SCHED-001; P1 BR-44, §19 · [assumed] |
| B2-15 | Student-timezone display (SCHED-017) is already built (P4-6, P5-8). Every new B2 screen follows the same rule: academy time, plus the student's when it differs. | spec Plan 4 P4-6 |
| B2-16 | New columns on existing tables are nullable or carry a database default (blue/green, Plan 10 M4). No B2 migration rewrites or drops existing data. | spec Plan 13 §4; orchestration §8.2 |
| B2-17 | `AcademySettings` (`etqan.academy`, unowned) gains fields only under a one-commit `claim`. | orchestration §6.2.1 |

## 3. Slices

Each slice is its own spec → plan → build → queue cycle. None requires another phase's slice: B2 depends only
on B1, which is merged.

| Slice | Contents | Audit IDs | Switches (off by default) | Unblocks |
|---|---|---|---|---|
| **B2a** session classes | Session kinds; adding a session by hand to a subscription; extra sessions; compensation sessions; `pays_teacher`; `at_disposal`; who created a session | SCHED-003, SCHED-008; TH §1.3 #4, #18 | `manual_sessions`, `extra_sessions`, `compensation_sessions`, `disposal_status` | B4 (session classes) |
| **B2b** times & postponement | Teacher / student in / out times and actual minutes; postponement window and rescheduling | SCHED-003, SCHED-015 | `session_times`, `postponement` | B5 (postponement notices) |
| **B2c** activity log | The session activity log with revert | SCHED-004, SYS-008 (sessions) | `activity_log` | — |
| **B2d** archives & simplified view | Subscription archive (delete keeping records, restore, archive screen), session archive, the simplified sessions view | SUB-003, SUB-004, SCHED-005, SCHED-006 | `subscription_archive`, `session_archive` (registry lines flipped), `simplified_sessions` | — |
| **B2e** trials & availability | Trial requests, scheduling, outcome, conversion, inquiry intake; teacher availability windows and "suggest a teacher" | SCHED-007, SCHED-012, FLOW-002 | `trial_sessions`, `teacher_availability` | B4 (trial pay) |
| **B2f** bundles & groups | Study groups; subscription bundles (multi-course, family, group) with rosters; the individual-subscription type normal / group; bundle renew / pause / cancel | SUB-001, SUB-006 (individual type), SUB-008, PEOPLE-003 | `study_groups` (flipped), `multi_course_subscriptions`, `family_subscriptions` (requires `families`), `group_subscriptions` (requires `study_groups`) | B6 (student levels on subscriptions) |
| **B2g** weekly schedules | The weekly-schedule object, its tabs, stop / restore, bulk teacher change, substitute teachers, CSV download, expanded calendar | SCHED-001, BR-44 | `weekly_schedules` | B5 (per-course WhatsApp group routing) |

Not taken by any B2 slice, with the reason:

- **SUB-006** payment type (prepaid / postpaid) and subscription system (normal / monthly): payment metadata, handed
  to B3 by a ledger decision. SUB-006's individual type normal / group is B2e's.
- **SUB-007** "Calculate and update subscription details": not applicable, our totals are derived (TH §5.4).
- TutorHamster session fields teacher approval (BR-05, set automatically), student excuse, actual session timestamp
  and "creation date used for salaries" (BR-06): not built [assumed low value]; payroll keeps `occurs_on` (TH §5.5).
- The registry's `free_sessions` ("free sessions for subscribers") is not B2's: an extra session with
  `pays_teacher` off already covers a free lesson; the switch stays unbuilt for B3 to decide.

Each slice spec details its own data, rules, API, screens, seeds and tests; this table is the contract between
them. A slice may move an item to a later slice only by amending this table.

## 4. Shared lists and ownership

- B2 adds lines only under its `── phase B2 ──` markers: feature registry, access `RESOURCES`, `config/api_router.py`
  (scheduling's routes already live in `etqan/scheduling/api/urls.py`, which B2 owns), `seed_academy` /
  `etqan/tenants/seeds/`, `pyproject.toml`, the dashboard's `NAV_ITEMS`. It flips its own registry lines
  (`study_groups`, `subscription_archive`, `session_archive`) in place.
- Widening the `in_use` verbs of scheduling's existing resource lines (`subscription`, `session`) is a B2 edit to
  B2-owned resources.
- New translation areas are new files `dashboard/src/locales/{en,ar}/<area>.json`.
- New e2e specs are `e2e/b2-*.spec.ts`.

## 5. Decisions recorded in the ledger

B2-2 (group sessions are rows per student), B2-3 (bundles over subscriptions), B2-4 (session kinds and the
consumption rule), B2-5 (`pays_teacher` filters `payroll_sessions`) and B2-6 (`at_disposal`) are recorded with
`decide`, affecting B3, B4, B5, B6 and B11 as each applies.

## 6. Out of scope (other phases)

- Pay for each session class, report deductions, per-student rates: B4.
- Notices for postponements, trials and compensation; WhatsApp routing; the nine reminder timestamps: B5.
- Levels, homework, session reviews, certificates: B6.
- Payment fields on the subscription, auto-renew, activation / renewal / discount codes, bulk renewal: B3.
- A built-in classroom (Jitsi, Zoom API): out (v1 D5).
