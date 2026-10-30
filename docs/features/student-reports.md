---
title: "Monthly student reports"
---

A monthly student report is the office's written report on one student for one calendar month. The
report is plain text. Someone can write it by hand, or start it from an AI draft built from that month's
facts: subscriptions, sessions, session reports, level progress, homework, reviews and certificates. The
office then prints it or copies it to share with the family. Only the office has access: admins, and
staff holding `student_report.*` codes. Teachers, students and parents get 403. Reports are never shown
to families in the app and are never sent. The code lives in `etqan.ai` (not `etqan.learning`) because
it grew out of the AI phase. It reads learning data only through learning's services.

## Concepts

| Model | Key fields | Notes |
|---|---|---|
| `ai.StudentReport` | `student` (`identity.StudentProfile`, PROTECT), `month` (date, DB check: the 1st), `body` (1–10 000 chars), `generated_at`, `created_by`, `updated_by`, timestamps | Unique per (student, month) (`ai_student_report_one_per_month`). Indexed on `month`. |

- The **month** is a calendar month in the academy's timezone. A month after the academy's current one is
  refused (400 `month`).
- `generated_at` means "last saved from an AI draft, as the form reported it". It is not a server-side
  proof.
- The API addresses students by **user id**. The row stores the profile FK.

## How it works

**Report CRUD** (`etqan/ai/reports/crud.py`, re-exported from `etqan/ai/services.py`):
- `parse_month("YYYY-MM")` and `check_month` validate the month.
- `create_report`:
  - It checks that the student and month are valid and cleans the body.
  - If a report already exists for that student and month, it raises `ReportExistsError`. The view turns
    this into 409 `ai.report_exists` with the existing `id`.
  - A concurrent insert that hits the unique constraint is reported the same way.
- `update_report` changes only the body. `generated=true` stamps `generated_at` with the current time;
  otherwise the stamp stays as it is.
- `reports_queryset(student=, month=)` orders by newest month first, then by student name.

**Facts** (`etqan/ai/reports/facts.py:month_facts(student_user_id, month)`): a fixed number of queries,
read only through other apps' services. Archived rows are included and trial sessions are left out.

| Fact | Source | Present only when |
|---|---|---|
| Subscriptions overlapping the month (course, teacher name, package, status, sessions total) | `scheduling.services.subscriptions_queryset` / `filter_subscriptions` | always |
| Session counts by status and by attendance, attended minutes, per course | `scheduling.services.sessions_queryset` / `filter_sessions` | always |
| Session-report averages (behaviour, participation) and up to 10 recent notes (≤ 500 chars each) | the same sessions query with `select_related("report")` | `session_reports` on |
| Level progress | `learning.services.progress_of` | `levels` on |
| Homework | `learning.services.homework_of` | `homework` on |
| Reviews | `learning.services.reviews_of` | `session_reviews` on |
| Certificates | `learning.services.certificates_of` | `certificates` on |

A fact whose switch is off comes back as `None`, and the panel hides it.

**AI draft**: "Generate report" runs the AI draft task `student_report.body` (`etqan/ai/registry.py`).
- Its inputs are `student`, `month` and `current` (the body so far), plus `instructions`.
- `check_report_inputs` validates the inputs before anything is queued.
- `build_report_prompt` (`etqan/ai/reports/prompt.py`) computes the facts **in the worker**. The client
  never sends them.
- What the prompt carries:
  - The student's first name. When the first word is عبد / Abd / Abdul, the first two words are kept.
  - The academy name, the month, and the names and numbers from the facts.
  - Session-report notes as written, with `<` and `>` swapped for angle quotes.
- What the prompt leaves out: teacher names, review comments, decision reasons, contacts and money.
- The draft machinery (queueing, throttles, the AI account, 409 `ai.not_set_up`) is described in
  [AI assistant](ai.md).

## API

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/ai/student-reports/?student=&month=YYYY-MM` | `student_report.view_any` | Paginated list. A malformed `month` filter is ignored. |
| POST | `/api/v1/ai/student-reports/` | `student_report.create` | `{student, month, body, generated}`; 409 `ai.report_exists` |
| GET | `/api/v1/ai/student-reports/<id>/` | `student_report.view_any` | One report |
| PATCH | `/api/v1/ai/student-reports/<id>/` | `student_report.update` | `{body?, generated?}` |
| DELETE | `/api/v1/ai/student-reports/<id>/` | `student_report.delete` | Delete |
| GET | `/api/v1/ai/student-reports/facts/?student=&month=` | any of `student_report.create` / `.update` / `.view_any` | The facts panel |
| POST | `/api/v1/ai/drafts/` with `task: "student_report.body"` | `student_report.create` or `.update` | Start an AI draft (see [AI assistant](ai.md)) |

All report routes are `[HasCode, FeatureOn]` with the `ai_reports` switch.

## Dashboard

Feature folder: `dashboard/src/features/studentReports/`.

| Route file | Component |
|---|---|
| `routes/_authed/people.student-reports.index.tsx` | `ReportsList` (filters by student and month; delete) |
| `routes/_authed/people.student-reports.new.tsx` | `ReportForm`: student and month (defaults to the previous month), `FactsPanel`, body with `AiDraftButton`, Save / Save & add another |
| `routes/_authed/people.student-reports.$reportId.tsx` | `ReportForm` in edit mode, `ReportActions` (Copy, Print) |
| `routes/_print/student-reports.$reportId.print.tsx` | `ReportPrint` |
| `routes/_authed/people.students.index.tsx` | `StudentReportsLink` in the students list header |

The nav item "Monthly reports" is in the People group. It is shown with `student_report.view_any` and
`ai_reports`.

## Background jobs

None of its own. A draft runs on the AI drafts worker (see [AI assistant](ai.md)).

## Configuration

- Switch `ai_reports` (built, off by default). It does not require `ai_assistant`.
- Generating a draft needs an AI account resolved through `integrations.services.resolve`. Writing a
  report by hand needs none.
- Access resource `student_report` (`view_any`, `create`, `update`, `delete`), under the B10 marker.
- There are no seeds.

## Code map

- `backend/etqan/ai/models.py`: `StudentReport`.
- `backend/etqan/ai/reports/crud.py`, `facts.py`, `prompt.py`.
- `backend/etqan/ai/api/report_views.py`, `report_payloads.py`, `urls.py`.
- `backend/etqan/ai/registry.py`: the `student_report.body` task.
- `backend/etqan/learning/services/progress.py:progress_of`, `hooks.py:homework_of`,
  `reviews.py:reviews_of`, `certificates.py:certificates_of`.
- `dashboard/src/features/studentReports/`.

## Design history

- [B10b spec: monthly student reports](../superpowers/specs/2026-10-08-b10b-student-reports-design.md),
  decisions R-1…R-12.
- [B10 phase spec](../superpowers/specs/2026-10-08-b10-ai-design.md): the AI decisions AI-1…AI-11.
- [Plan 48](../superpowers/plans/2026-10-08-plan-48-student-reports.md).
- The learning hooks it reads were fixed in earlier specs: B6-9 / D26 (`progress_of`), H-12 / D29
  (`homework_of`), R-5 / D32 (`reviews_of`) and T-11 / D33 (`certificates_of`).
