---
title: "AI"
---

The office (admins, and staff who hold the right codes) can ask Claude to draft text for a form field. The
fields are: article summary, body, SEO title, SEO description and keywords; article category description;
course description; contract details; and the monthly student report body. A draft is only a suggestion. The
user reads it, then inserts it into the form or discards it, and only the form's normal save stores anything.
B10b adds monthly student reports, which the office writes and prints, optionally starting from an AI draft.
There is no chat assistant and no data-analysis agent. The AI account comes from the integrations resolver
(see [integrations.md](integrations.md)), and use of Etqan's key is metered by token (see
[etqan-billing.md](etqan-billing.md)).

## Concepts

Both models are in the **academy schema** (TENANT_APPS `etqan.ai`).

| Model | Purpose |
|---|---|
| `AiDraft` | One draft job. It has these fields: UUID `id`, `user` (the requester), `task`, `language` (`ar`/`en`), `inputs` (blanked when the draft finishes), `status` (`pending`/`done`/`failed`), `text`, `truncated`, `error_code`, `source` (`academy`/`etqan`), `model`, `input_tokens`, `output_tokens`, `started_at`, `finished_at`. |
| `StudentReport` | The office's report on one student for one month. One per `(student, month)`; `month` is the 1st of the month. It holds `body` and `generated_at`, which is stamped when a form saves it from an AI draft. |

**Task registry** (`registry.py:TASKS`). Each `Task` defines:

- `codes`: the user needs any one of them;
- `switches`: all of them must be on;
- the input keys and their character limits;
- `max_chars`, `effort`, `output` (`text` or `html`), `form`, and `appendable`;
- the optional hooks `validate` and `build`.

`max_tokens` is `max_chars // 2 + 2000`.

| Task | Codes | Switches |
|---|---|---|
| `article.summary`, `article.body`, `article.seo_title`, `article.seo_description`, `article.keywords` | `article.create` / `article.update` | `ai_assistant`, `articles` |
| `article_category.description` | `article_category.create` / `.update` | `ai_assistant`, `articles` |
| `course.description` | `course.create` / `.update` | `ai_assistant` |
| `contract.details` | `contract.create` / `.update` | `ai_assistant`, `contracts` |
| `student_report.body` | `student_report.create` / `.update` | `ai_reports` |

The dashboard keeps a copy of each task's switches in `dashboard/src/features/ai/tasks.ts`.
`manage.py ai_tasks` prints the server's copy as JSON, and the e2e suite compares the two.

## How it works

Draft flow, in `etqan/ai/services.py`:

1. `start_draft(user=, task=, language=, inputs=)` runs these checks in order:
   1. `check()` verifies the task exists.
   2. The user must be admin or staff and hold one of the task's codes, else 403. Teachers, students and
      parents always get 403.
   3. Every switch the task needs must be on, else `SwitchedOffError`, which the view turns into 404
      `FEATURE_OFF`.

   It then cleans the inputs with `text.clean_inputs`, which cuts them to their limits and reduces HTML inputs
   to text. It runs the task's `validate` hook if there is one; B10b uses it to check for a real student and a
   month not in the future. If `integrations.resolve("ai")` returns `None`, it answers 409 `ai.not_set_up`.
   Before creating the draft it calls `prune()`, which deletes drafts older than 30 days. It creates the draft
   as `pending`, and on commit it queues `ai.run_draft(schema, id)` with `expires=60`. Only the schema and the
   draft id reach the broker.
2. The worker, `run_draft`, works in these steps:
   1. `_claim` locks the row. It does nothing unless the draft is pending, unclaimed and less than 60 s old.
      Otherwise it sets `started_at`.
   2. It resolves the account again.
   3. It builds the prompt, with `prompts.build` or the task's own `build` hook.
   4. It calls `client.complete`: one streamed Claude call with the resolved key and model, `effort`, a 240 s
      timeout and no retries.
   5. `_finish` stores the result, but only while the row is still `pending`.
3. Output and error handling:
   - A refusal ends as `failed` with `ai.refused`.
   - A response that stopped at `max_tokens`, or that was cut to `max_chars`, is stored with `truncated`.
   - HTML tasks, such as `article.body`, get model text converted by `render.to_html`, which builds only
     `h2`, `p`, `ul` and `li`.
   - Provider errors map to `ai.provider_rejected`, `ai.billing`, `ai.model_unavailable`, `ai.busy`,
     `ai.timeout` and `ai.provider_error`.
4. Stale rule, applied by `draft_for` when a draft is read:
   - pending and never started after 90 s → `ai.busy`;
   - pending after 6 minutes → `ai.timeout`.
5. Metering: `meter(resolved, draft)` runs once per draft that got a response, including a refusal or a
   failure after the response arrived. It records only when `resolved.source == "etqan"`. It writes one
   `record_usage` per non-zero unit (`input_token` and `output_token`), keyed `ai-draft-<uuid>:<unit>`. A
   metering failure is logged and never raised.

Model choice:

- An academy's own account picks one of `claude-sonnet-5`, `claude-sonnet-5-5`, `claude-opus-5-5` or
  `claude-haiku-5-5`.
- When the model is missing or not on that list, `claude-sonnet-5` is used.
- The list is kept in both `etqan/ai/client.py` and `etqan/integrations/providers/ai.py`, and a test pins the
  two copies equal.

Prompts carry only:

- the task's declared inputs;
- the user's instructions (at most 500 characters);
- the academy's name;
- for reports, the student's first name and the month's facts.

`reports/facts.py:month_facts` reads those facts only through other apps' services (scheduling, learning).
`reports/prompt.py` builds the report prompt inside the worker.

Student reports (`reports/crud.py`, re-exported from `services.py`):

- `create_report` answers 409 with the existing report's id when the `(student, month)` report already exists.
- `update_report` changes only `body`. When `generated=true` it stamps `generated_at`.
- A month after the academy's current month is refused.

## API

The **office** is admins plus staff who hold the listed code. Report endpoints also need the `ai_reports` switch
(404 if it is off, checked after the code).

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/api/v1/ai/drafts/` | office with any task's code; throttled at 30/hour per user | `{task, language, inputs}` → 202 `{id, status}` |
| GET | `/api/v1/ai/drafts/<uuid>/` | the requester only (others get 404) | `{id, task, language, status, text, truncated, error_code}` |
| GET | `/api/v1/ai/student-reports/` | `student_report.view_any` | Paginated list, filtered by `?student=` and `?month=YYYY-MM` |
| POST | `/api/v1/ai/student-reports/` | `student_report.create` | Create `{student, month, body, generated}` |
| GET | `/api/v1/ai/student-reports/<id>/` | `student_report.view_any` | One report |
| PATCH | `/api/v1/ai/student-reports/<id>/` | `student_report.update` | Edit body, optionally stamping it as generated |
| DELETE | `/api/v1/ai/student-reports/<id>/` | `student_report.delete` | Delete |
| GET | `/api/v1/ai/student-reports/facts/?student=&month=` | any report code | The facts panel for that student and month |

## Dashboard

- `dashboard/src/features/ai/`:
  - `AiDraftButton` is the "Write with AI" dialog. It starts a draft and polls it until it leaves `pending`.
  - `tasks.ts` holds the task list and its switches. `errors.ts` maps error codes to messages.
  - The button is used in `website/ArticleEditor.tsx`, `website/ArticleCategoriesManager.tsx`,
    `catalogue/CourseForm.tsx`, `employment/ContractDialog.tsx` and `studentReports/ReportForm.tsx`.
- `dashboard/src/features/studentReports/` holds the list, form, facts panel, actions and print view.
- Routes:
  - `routes/_authed/people.student-reports.index.tsx`
  - `routes/_authed/people.student-reports.new.tsx`
  - `routes/_authed/people.student-reports.$reportId.tsx`
  - `routes/_print/student-reports.$reportId.print.tsx`

  There is also a link from `people.students.index.tsx`.
- The academy's own Claude key is entered in Settings → Integrations (`features/integrations/AiAccountForm.tsx`).

## Background jobs

- `ai.run_draft` (`tasks.py`) runs one draft in `academy_context(schema)`. Settings: `ignore_result`,
  `soft_time_limit=270`, `time_limit=300`. It runs on Celery's default queue.
- There is no beat job. Old drafts are pruned whenever a new draft starts.

## Configuration

- Switches: `ai_assistant` (form drafts) and `ai_reports` (reports). Either one also enables Etqan's AI default
  in the resolver.
- Account:
  - The academy's own account (`AcademyAccount(ai)`) holds `config.model` and the secret `api_key`.
  - Etqan's default `PlatformAccount(ai)` is set in the platform admin, with config `{"model": …}` and secret
    `{"api_key": "sk-ant-…"}`.
- `ETQAN_AI_FAKE`:
  - With it on, a deterministic fake model answers with 0 tokens, and the probe passes for any key.
  - It is on in `local.py` and `test.py`, and pinned off in production.
  - System check `ai.E001` refuses it without `DEBUG`.

## Code map

- `backend/etqan/ai/models.py`, `services.py`, `registry.py`, `client.py`, `prompts.py`, `render.py`, `text.py`,
  `tasks.py`, `checks.py`
- `backend/etqan/ai/reports/`: `crud.py`, `facts.py`, `prompt.py`
- `backend/etqan/ai/api/`: `views.py`, `report_views.py`, `serializers.py`, `report_payloads.py`, `throttles.py`
- `backend/etqan/ai/management/commands/ai_tasks.py`
- `backend/etqan/integrations/providers/ai.py` (the Claude provider and probe)
- `dashboard/src/features/ai/`, `dashboard/src/features/studentReports/`

## Design history

- [B10 AI design](../superpowers/specs/2026-10-08-b10-ai-design.md): the phase decisions AI-1 to AI-11 and the
  B10a drafts A-1 to A-16. AI-9's note that `record_usage` is idempotent without the unit is out of date (the
  unit is now in the key). The A-1 probe (`models.retrieve`) is a recorded deviation from the integrations
  spec's "one-token call".
- [B10b student reports design](../superpowers/specs/2026-10-08-b10b-student-reports-design.md): reports, facts
  and the `student_report.body` task.
- [Plan 47: AI drafts](../superpowers/plans/2026-10-08-plan-47-ai-drafts.md).
- [Plan 48: student reports](../superpowers/plans/2026-10-08-plan-48-student-reports.md).
