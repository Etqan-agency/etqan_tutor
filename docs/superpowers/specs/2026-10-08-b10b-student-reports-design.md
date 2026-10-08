# Slice B10b — Monthly student reports — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied
2026-10-08.
**Phase spec:** `2026-10-08-b10-ai-design.md` (decisions AI-1…AI-11; B10a's drafts A-1…A-16).
**Requires:** B10a (the draft machinery); B6c (`learning.services.reviews_of`, ledger D32); B6d
(`learning.services.certificates_of`, ledger D33). `progress_of` (D26) and `homework_of` (D29) are merged.
**Evidence:** P1 EXP-001 (`/admin/student-reports`), P1 data model `StudentReport`; TH V28, U13.

## 1. Goal

The office writes a monthly report per student, as TutorHamster's "Monthly student reports" screen does:
choose a student, see their subscriptions and the month's sessions, press **Generate report** to get a draft
written from those facts, edit it, save. The list shows student, report and generation date.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| R-1 | **`StudentReport`** (in `etqan.ai`): `student` (string FK `identity.StudentProfile`, PROTECT), `month` (date, the 1st), `body` (plain text, 1–10 000 chars), `generated_at` (when an AI draft was last inserted; null for a hand-written report), `created_by`, `updated_by`, `created_at`, `updated_at`. **One report per student and month** (unique; 409 `ai.report_exists` with the existing id). | P1 EXP-001 (columns student, report, generation date), P1 data model StudentReport · [assumed] the month field and uniqueness: a "monthly" report |
| R-2 | **The month** is a calendar month in the academy's timezone, as `progress_of` (D26). The form defaults to the previous month; a future month is 400 `month`. | ledger D26 · [assumed] default |
| R-3 | **Who**: office only — admins, and staff holding the new resource `student_report` ("Monthly student reports" / "التقارير الشهرية": `view_any`, `create`, `update`, `delete`). Teachers, students and parents have no access (403). Reports are not shown to students or parents and are not sent (phase §3). | P1 EXP-001 (reached from the office Students screen) · [assumed] office-only |
| R-4 | **Switch `ai_reports`** gates the screen, the API and the facts (404 `FEATURE_OFF` when off, after the code check). Generating additionally needs a resolved AI account (409 `ai.not_set_up`); writing a report by hand needs none. `ai_assistant` is not required: TutorHamster 18.5 has a separate "AI reports" flag, though P1 INT-010 listed the reports under the AI-assistant flag. | AI-4; TH SYS-002 (37 flags) and TH §1 finding 1; P1 INT-010 |
| R-5 | **Facts of a month** (`ai.services.month_facts(student_user_id, month) -> MonthFacts`), read only through other apps' services, archived rows included (D14): **subscriptions** from `scheduling.services.subscriptions_queryset()` for the student whose `starts_on` ≤ the month's last day and `term_ends_on` ≥ its first day, any status (course, teacher's name — shown on screen, never prompted (R-8) — package name, current status, `sessions_total`); **sessions** from `sessions_queryset()` filtered by `filter_sessions(student=, from_date=, to_date=, archived="include")` with `occurs_on` in the month, trial-kind sessions left out: counts by status (scheduled, completed, cancelled, at_disposal), by student attendance (present, absent, excused, not set), attended minutes (`minutes` of sessions with the student present), per course; **session reports** only while `session_reports` is on, read through the same queryset with `select_related("report")` (no scheduling model import — the B6d precedent): average behaviour and participation (1–5) and up to 10 most recent non-empty notes (≤ 500 chars each); **learning**, each only while its switch is on: `progress_of` (`levels`), `homework_of` (`homework`), `reviews_of` (`session_reviews`), `certificates_of` (`certificates`). A fixed number of queries. | P1 EXP-001 ("subscription details and session details auto-populate"); ledger D14, D26, D29, D32, D33 · [assumed] which facts |
| R-6 | **The facts panel** shows R-5 (teacher names included, for the office) in the form as soon as a student and month are chosen ("Please choose a student first" before that, as P1). | P1 EXP-001 |
| R-7 | **Generate report** is a B10a draft task `student_report.body` (A-10): inputs `student` (the student's user id, as every students API and `filter_sessions` use), `month`, `current` (the body so far, ≤ 10 000), plus every task's `instructions` (≤ 500); `Task.validate` refuses an unknown student or a future month (400) before anything is queued, and `Task.build` computes the facts in the worker — the client never supplies them. Permission: role admin/staff with `student_report.create` or `student_report.update`; switch `ai_reports` only. Output plain text, `max_chars` 10 000, `max_tokens` 7 000 (A-10's rule), effort `medium`, appendable, in the language chosen in the dialog (AI-11). Shares B10a's throttle. | AI-6, AI-7; A-10, A-12 |
| R-8 | **What the prompt carries** (AI-8): the student's **first name** (the first word of `User.full_name`; the first two when the first is `عبد` or `Abd`/`Abdul`, so "عبد الله" stays whole; "the student" when the name is empty), the academy's name, the month, and R-5's facts with course, package and level names, topic names, homework titles and statuses, review counts and average rating, certificate kinds. Left out: teacher names, review comments, any contact or money field. Session report notes are sent as written (free text, AI-8). | AI-8 · [assumed] |
| R-9 | **Inserting a draft** fills the body; saving sends `generated: true`, which sets `generated_at` to now. `generated: false` or absent leaves `generated_at` as it is; a hand edit afterwards keeps it. `generated_at` therefore means "saved from an AI draft, as the user's form reported", not a server-side proof. | P1 EXP-001 "generation date" · [assumed] |
| R-10 | **Save options** as P1: Save, Save & add another (keeps the month, clears the student), Cancel. | P1 EXP-001 |
| R-11 | **Print / copy**: the report page has Copy and Print (browser print of a plain layout with academy name, student, month, body). No PDF and no sending. | [assumed] |
| R-12 | **Seeds**: none (phase A-16): demo gets `ai_reports` on with `seed_dev`'s built switches; no report is seeded. | PO-5; phase A-16 |

## 3. Screens

| Who | Where | What |
|---|---|---|
| Office | **People → Monthly reports** `/people/student-reports` (nav item, group `people`, `student_report.view_any`, `ai_reports`) | List: student · month · first line of the report · generated at · updated; filters: student, month; add; open; delete (`student_report.delete`, confirm). |
| Office | Add / edit page `/people/student-reports/new`, `/$reportId` | Student picker (fixed on edit) and month; the facts panel (R-6); body textarea with **Generate report** (B10a's `AiDraftButton` with task `student_report.body`, shown with `student_report.create`/`update`); Save / Save & add another / Cancel; Copy / Print on a saved report. |
| Office | Students list header | A "Monthly reports" link to the list (as P1 "التقارير الشهرية"), shown with `student_report.view_any` and `ai_reports`. |

## 4. API

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/ai/student-reports/` | paginated; `?student=<user id>&month=YYYY-MM` (the row stores the profile FK; the API speaks user ids); `student_report.view_any` |
| POST | `/api/v1/ai/student-reports/` | `{student (user id), month: "YYYY-MM", body, generated}`; `student_report.create`; 409 `ai.report_exists` |
| GET/PATCH/DELETE | `/api/v1/ai/student-reports/<id>/` | `view_any` / `update` (body, generated) / `delete` |
| GET | `/api/v1/ai/student-reports/facts/?student=<user id>&month=YYYY-MM` | R-5 as JSON; any of `student_report.create`/`update`/`view_any` |

Drafts go through `POST /api/v1/ai/drafts/` with `task: "student_report.body"` (B10a).

## 5. Data

```text
ai.StudentReport
  id           bigint pk
  student      FK identity.StudentProfile (PROTECT)
  month        date (day 1)               unique (student, month)
  body         text
  generated_at datetime null
  created_by   FK user (SET_NULL, null)
  updated_by   FK user (SET_NULL, null)
  created_at, updated_at
```

## 6. Tests

- Facts: each count and average from fixtures; archived sessions counted; trial sessions left out; the
  subscription overlap rule at both month edges; the month boundary in a non-UTC academy timezone; the
  session-report block and each learning block present only with its switch on; a fixed query count.
- Reports: unique per month (409), future month 400, access (403 for teachers/students/parents and for staff
  without codes; 404 switch off), `generated` sets `generated_at`, hand edit keeps it, PROTECT on student.
- Draft task: permission and switch, facts computed server-side (a client-sent facts key is refused 400 `inputs`, as any unknown input key), the prompt holds
  only R-8's data (no email/phone/teacher name/review comment; first-name rule incl. "عبد الله"), fake mode completes.
- Dashboard: list filters, facts panel states, generate → insert → save, save & add another, copy/print.
- e2e `e2e/b10-student-reports.spec.ts`: admin connects a fake AI key, turns `ai_reports` on, opens Monthly
  reports, picks the demo student and last month, sees the facts, generates, saves, sees it in the list.

## 7. Risks

1. **Student data leaving the academy** — R-8 keeps it to the minimum; the dialog's note (AI-8) says it is sent.
2. **Facts that differ from the dashboard's numbers** — the facts read the same services the scheduling and
   learning screens use, with the same archived-row rule (D14).
3. **B6c/B6d not merged when B10b builds** — `ready B10b` blocks until they are; nothing in B10b is built
   against unmerged code.
